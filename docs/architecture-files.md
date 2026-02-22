# File Handle Architecture: ConnectionPool, Pooled Streams, and FileSaver

This document explains how Skyline manages mutable file handles (`.skyd` chromatogram
caches, `.blib` spectral libraries, `.idb`/`.optdb` databases) within an immutable
document model. Understanding this architecture is essential for diagnosing why files
end up locked at the end of certain tests.

**Related documents:**
- [architecture-data-model.md](architecture-data-model.md) — SrmDocument, Identity, undo/redo
- [style-guide.md](style-guide.md) §FileSaver — atomic file write patterns
- [leak-debugging-guide.md](leak-debugging-guide.md) — handle leak investigation

---

## 1. The Core Problem

`SrmDocument` is immutable — once created, it never changes. You can traverse it from
any thread without locks. But `.skyd` and `.blib` files must be held open for the
lifetime of the document that references them, because reading chromatograms or spectra
requires random-access seeks into those files.

This creates three tensions:

1. **Multiple document versions coexist.** The current document plus every entry on the
   undo stack all reference the same cached files. Only the *current* document should
   hold file handles open.

2. **File handles are mutable state.** A `FileStream` has a seek position, can be
   closed, and can be reopened. This mutability cannot live inside the immutable
   document tree itself.

3. **Atomic file replacement.** When Skyline rebuilds a `.skyd` cache, it must close
   the existing handle, rename the new file into place, and reopen — all without
   corrupting concurrent readers.

The solution is an indirection layer. As the source comment on `CreatePooledStream`
states:

> *"This extra level of indirection is required to maintain the immutable nature of
> the document tree."*
>
> — `UtilIO.cs:77-78`

Three systems cooperate to solve this:

| System | Purpose | Key file |
|--------|---------|----------|
| **ConnectionPool** | Central registry of open handles, keyed by Identity | `UtilIO.cs:192-299` |
| **FileSaver** | Atomic write-then-rename with pool integration | `UtilIO.cs:1132-1306` |
| **BackgroundLoader.CloseRemovedStreams** | Releases handles when documents change | `BackgroundLoader.cs:91-106` |

---

## 2. Identity and GlobalIndex

Every pooled connection is keyed by `Identity.GlobalIndex` — a process-wide unique
integer assigned by `Interlocked.Increment` at construction time (`Identity.cs:50`).

```
Identity (abstract base)
├── GlobalIndex: int              ← unique key into ConnectionPool
├── Copy() → new Identity         ← gets a NEW GlobalIndex
└── content-equality via Equals/GetHashCode (GlobalIndex excluded)
```

`GlobalIndex` serves as reference-equality for dictionary lookups. Two `Identity`
objects can be content-equal (`Equals` returns true) but have different `GlobalIndex`
values, meaning they map to different pool entries. This is by design: when a document
is modified, the new document gets copies of Identity objects with new GlobalIndex
values, causing the old pool entries to become orphans that `CloseRemovedStreams` can
clean up.

---

## 3. ConnectionPool: The Central Registry

`ConnectionPool` (`UtilIO.cs:192-299`) is a thread-safe dictionary mapping
`Identity.GlobalIndex` to `IDisposable` connections:

```csharp
public sealed class ConnectionPool
{
    private readonly Dictionary<int, IDisposable> _connections;
    // All public methods synchronize on lock(this)
}
```

### Key operations

| Method | Behavior |
|--------|----------|
| `GetConnection(id, connect)` | Return existing connection or call `connect()` to create one. Both lookup and creation happen inside `lock(this)` to prevent double-open. |
| `Disconnect(id)` | Remove from dictionary and `Dispose()` the connection. Also inside `lock(this)` so a new connect won't race with the old disconnect. |
| `DisconnectWhile(stream, action)` | Acquire the stream's write lock, close the stream, run `action` (typically a file rename), then release. Used by `FileSaver.Commit`. |
| `HasPooledConnections` | Returns `_connections.Count > 0`. Used in test cleanup. |
| `ReportPooledConnections()` | Returns `"{GlobalIndex}. {connection}"` for each entry. Diagnostic output when tests leave files open. |
| `DisposeAll()` | Dispose all connections and clear the dictionary. Emergency cleanup. |

### Singleton access

Production code uses `FileStreamManager.Default` (`UtilIO.cs:574`), which owns the
singleton `ConnectionPool`:

```csharp
public class FileStreamManager : IStreamManager
{
    public static FileStreamManager Default { get; }
    private readonly ConnectionPool _connectionPool = new ConnectionPool();
    public ConnectionPool ConnectionPool => _connectionPool;
}
```

### Conceptual diagram

```
┌─────────────────────────────────────────────────────────┐
│                    ConnectionPool                        │
│  Dictionary<int, IDisposable>                           │
│                                                         │
│  GlobalIndex 42 ──► PooledFileStream (data.skyd)        │
│  GlobalIndex 87 ──► PooledSqliteConnection (lib.blib)   │
│  GlobalIndex 91 ──► PooledSqliteConnection (lib_r.blib) │
│  GlobalIndex 103 ─► PooledSessionFactory (irt.irtdb)    │
└───────────┬─────────────────────────┬───────────────────┘
            │                         │
    ┌───────▼───────┐       ┌────────▼────────┐
    │ SrmDocument   │       │ SrmDocument     │
    │ (current)     │       │ (undo stack)    │
    │ refs GI 42,87 │       │ refs GI 42,87  │
    └───────────────┘       └─────────────────┘

Only the current document's BackgroundLoaders keep connections open.
When the undo-stack document's streams are checked, CloseRemovedStreams
closes any that are no longer in the current document's stream set.
```

---

## 4. Pooled Connection Types

### Type hierarchy

```
Identity (abstract)
└── ConnectionId<TDisp> (abstract, UtilIO.cs:306-360)
    │   owns: ConnectionPool reference, QueryLock
    │   abstract Connect() → IDisposable
    │   Connection property → pool.GetConnection(this, Connect)
    │   Disconnect() → acquires write lock, calls pool.Disconnect(this)
    │
    ├── PooledFileStream : IPooledStream (UtilIO.cs:410-511)
    │       TDisp = Stream
    │       For .skyd chromatogram cache files
    │
    ├── PooledSqliteConnection : IPooledStream (PooledSqliteConnection.cs:28-100)
    │       TDisp = SQLiteConnection
    │       For .blib spectral library files
    │
    └── PooledSessionFactory : IPooledStream (UtilIO.cs:513-565)
            TDisp = ISessionFactory
            For .irtdb, .optdb, proteome NHibernate databases
```

### IPooledStream interface (`UtilIO.cs:367-405`)

All three concrete types implement `IPooledStream`, the common interface used by
`BackgroundLoader.CloseRemovedStreams`:

```csharp
public interface IPooledStream
{
    int GlobalIndex { get; }
    Stream Stream { get; }          // May trigger Connect() on access
    bool IsModified { get; }        // File changed since first opened?
    string ModifiedExplanation { get; }
    bool IsOpen { get; }            // Currently in the pool?
    void CloseStream();             // Remove from pool and dispose
    QueryLock ReaderWriterLock { get; }
}
```

### PooledFileStream — `.skyd` files

`PooledFileStream` (`UtilIO.cs:410-511`) wraps a `FileStream` opened for read-only
access (`FileMode.Open`, `FileAccess.Read`, `FileShare.Read`).

**Modification detection:** On construction, it records `File.GetLastWriteTime`. On
reconnect (after the stream was temporarily closed), it compares timestamps. If the
file was modified while closed, `Connect()` throws `FileModifiedException`. A tolerance
of 1 millisecond (10,000 ticks) handles minor timestamp drift seen on network drives
after ZIP extraction (`UtilIO.cs:452-456`).

**IsOpen:** Delegates to `ConnectionPool.IsInPool(this)` — the stream is "open" if
its GlobalIndex is currently in the pool dictionary.

### PooledSqliteConnection — `.blib` files

`PooledSqliteConnection` (`PooledSqliteConnection.cs:28-100`) wraps a
`SQLiteConnection` for BiblioSpec spectral libraries.

**Auto-recovery:** The `ExecuteWithConnection<T>` method (`line 82-99`) wraps all
database operations. If a `SQLiteException` occurs (e.g., network failure), it calls
`CloseStream()` so the next access will reopen the connection, then rethrows as
`IOException`.

**Note:** `IPooledStream.Stream` throws `InvalidOperationException` — SQLite
connections are not `Stream` objects. The interface is implemented for
`CloseRemovedStreams` compatibility via `GlobalIndex`, `IsOpen`, and `CloseStream`.

### PooledSessionFactory — `.irtdb`, `.optdb` files

`PooledSessionFactory` (`UtilIO.cs:513-565`) wraps an NHibernate `ISessionFactory`
for iRT databases, optimization databases, and proteome databases.

Like `PooledSqliteConnection`, its `IPooledStream.Stream` throws
`InvalidOperationException`. It uses `SessionFactoryFactory.CreateSessionFactory` to
connect.

---

## 5. Document Lifecycle: When Streams Open and Close

This is the most architecturally significant aspect of the pooling system.

### Ownership chains

Streams are reachable through the document tree, but *owned* by the pool:

```
SrmDocument
├── Settings.MeasuredResults
│   └── Caches[] (ChromatogramCache)
│       └── ReadStream: IPooledStream (PooledFileStream for .skyd)
│
├── Settings.PeptideSettings.Libraries.Libraries[]
│   └── (BiblioSpecLiteLibrary)
│       ├── _sqliteConnection: PooledSqliteConnection (for .blib)
│       └── _sqliteConnectionRedundant: PooledSqliteConnection (for redundant .blib)
│
├── Settings.PeptideSettings.Libraries.Libraries[]
│   └── (other library types → their own ReadStreams)
│
└── Settings.PeptideSettings.Prediction / BackgroundProteome / etc.
    └── (PooledSessionFactory instances for .irtdb, .optdb, proteome.db)
```

### BackgroundLoader.CloseRemovedStreams — the critical mechanism

When the document changes (edit, undo, redo, or SwitchDocument), each
`BackgroundLoader` subclass calls `CloseRemovedStreams` (`BackgroundLoader.cs:91-106`):

```csharp
private void CloseRemovedStreams(SrmDocument document, SrmDocument previous)
{
    // Collect GlobalIndex values from the NEW document's streams
    HashSet<int> set = new HashSet<int>();
    foreach (var id in GetOpenStreams(document))
        set.Add(id.GlobalIndex);

    // Close any stream from the OLD document that isn't in the new set
    foreach (var id in GetOpenStreams(previous))
    {
        if (!set.Contains(id.GlobalIndex))
            id.CloseStream();
    }
}
```

This is a set-difference operation: streams present in the old document but absent
from the new document get closed.

### Which BackgroundLoaders participate

Each `BackgroundLoader` subclass overrides `GetOpenStreams` to report which
`IPooledStream` objects its managed data holds:

| BackgroundLoader subclass | GetOpenStreams returns | Files managed |
|---------------------------|----------------------|---------------|
| `ChromatogramManager` | `document.Settings.MeasuredResults.ReadStreams` | `.skyd` files |
| `LibraryManager` | Each library's `ReadStreams` | `.blib`, `.sptxt`, etc. |
| `IrtDbManager` | Empty (uses PooledSessionFactory indirectly) | `.irtdb` |
| `OptimizationDbManager` | Empty | `.optdb` |
| `BackgroundProteomeManager` | Empty | proteome `.db` |
| `RetentionTimeManager` | Empty | — |
| `IonMobilityLibraryManager` | Empty | — |
| `ProteinMetadataManager` | Empty | — |
| `AutoTrainManager` | Empty | — |

**Key insight:** Only `ChromatogramManager` and `LibraryManager` actually return
non-empty stream sets. The other managers either don't hold pooled connections through
`GetOpenStreams`, or manage their connections through different lifecycles. This means
`.skyd` and `.blib` handle leaks in tests are almost always traceable to these two
managers' `CloseRemovedStreams` paths.

### Stream lifecycle timeline

```
Time ──────────────────────────────────────────────────────────►

Doc v1 created (has .skyd ref, GlobalIndex=42)
  │  PooledFileStream(42) created, added to pool
  │  Pool: {42: FileStream("data.skyd")}
  │
  ▼
Doc v2 created (edit: new GlobalIndex=42 carried over via same Identity)
  │  CloseRemovedStreams(v2, v1):
  │    v2 streams: {42}
  │    v1 streams: {42}
  │    difference: {} ← nothing to close (same Identity, same GlobalIndex)
  │  Pool: {42: FileStream("data.skyd")}
  │
  ▼
Doc v3 created (removed results: no .skyd ref)
  │  CloseRemovedStreams(v3, v2):
  │    v3 streams: {}
  │    v2 streams: {42}
  │    difference: {42} ← CLOSE this stream
  │  pool.Disconnect(42) → FileStream.Dispose()
  │  Pool: {}
  │
  ▼
Undo back to v2
  │  CloseRemovedStreams(v2, v3):
  │    v2 streams: {42}  ← Identity still exists, but pool entry was removed
  │    v3 streams: {}
  │    difference: {} ← nothing to close
  │  Next read of .skyd → pool.GetConnection(42, Connect)
  │    Connect() checks File.GetLastWriteTime → OK, reopens stream
  │  Pool: {42: FileStream("data.skyd")}  ← lazily reopened
  │
  ▼
Cache rebuild: FileSaver writes new .skyd
  │  DisconnectWhile(stream42):
  │    1. Acquire write lock on stream42.ReaderWriterLock
  │    2. stream42.CloseStream() → Disconnect(42) → dispose old FileStream
  │    3. File.Replace(temp, "data.skyd", backup)
  │    4. Release write lock
  │  Next read → GetConnection(42, Connect)
  │    Connect() sees FileTime matches (FileSaver preserved timestamp) → OK
  │  Pool: {42: FileStream("data.skyd")}  ← new file, same pool slot
```

### Undo/redo and FileModifiedException

When undoing restores a document whose `.skyd` was rebuilt, the `PooledFileStream`
for the old document version still exists (it was never collected). On the next
read, `Connect()` compares the recorded `FileTime` against the current file
timestamp. If they differ by more than 1 millisecond, it throws
`FileModifiedException`. This is a safeguard: the old document expected a file that
no longer exists in its original form.

---

## 6. FileSaver and Atomic Writes

`FileSaver` (`UtilIO.cs:1132-1306`) implements write-to-temp-then-rename. For full
usage patterns, see [style-guide.md](style-guide.md) §FileSaver.

### Pool integration via `Commit(IPooledStream)`

The critical integration point is `FileSaver.Commit(IPooledStream)` (`line 1247`):

```csharp
public bool Commit(IPooledStream streamDest)
{
    // Close the temp stream
    if (_stream != null) { _stream.Close(); _stream = null; }
    // Delegate to IStreamManager.Commit, which calls DisconnectWhile
    _streamManager.Commit(SafeName, RealName, streamDest);
    Dispose();
    return true;
}
```

Which calls `FileStreamManager.Commit` (`line 695`):

```csharp
public void Commit(string pathTemp, string pathDestination, IPooledStream streamDest)
{
    if (streamDest == null)
        Commit(pathTemp, pathDestination);          // Simple rename
    else
        _connectionPool.DisconnectWhile(streamDest,
            () => Commit(pathTemp, pathDestination)); // Close-rename-reopen
}
```

### The DisconnectWhile dance

```
Thread A (writer)                    Thread B (reader)
─────────────────                    ─────────────────
DisconnectWhile(stream, rename):
  lock(pool)                         ← blocked on pool lock
    CancelAndGetWriteLock()          ← cancels pending reads
      stream.CloseStream()           ← FileStream.Dispose()
      rename(temp → destination)     ← File.Replace or File.Move
    release write lock
  unlock pool                        → GetConnection: reopens file
                                       (new content, same path)
```

### Canonical example: ChromatogramCache.CommitCache

```csharp
// ChromatogramCache.cs:1740-1746
public void CommitCache(FileSaver fs)
{
    // Close the read stream, in case the destination is the source,
    // and overwrite is necessary.
    ReadStream.CloseStream();
    fs.Commit(ReadStream);
}
```

Note the explicit `CloseStream()` before `Commit` — this is belt-and-suspenders.
The `ReadStream` is passed to `Commit` so `DisconnectWhile` can coordinate the
rename, but the stream is pre-closed because the destination may be the same file
as the source.

---

## 7. IStreamManager: Production vs. Test

The `IStreamManager` interface (`UtilIO.cs:47-184`) abstracts all file system
operations, including pooled stream creation:

| Implementation | Location | Purpose |
|---------------|----------|---------|
| `FileStreamManager` | `UtilIO.cs:567-741` | Production — real disk I/O |
| `MemoryStreamManager` | `TestUtil/MemoryStreamManager.cs:29` | Tests — in-memory "file system" |

Both implementations own a `ConnectionPool` and implement `CreatePooledStream`.
Test code using `MemoryStreamManager` exercises the same pool semantics as
production, with byte arrays standing in for disk files.

Unit tests that need to verify document round-tripping without disk I/O use
`MemoryStreamManager`. Functional tests (those inheriting `TestFunctional`) use
real files via `FileStreamManager.Default`.

---

## 8. Diagnosing File Locks in Tests

### Current infrastructure

#### Test cleanup path (`TestFunctional.cs:2766-2789`)

After each functional test, cleanup proceeds:

```csharp
// 1. Switch to empty document to release all references
var docNew = new SrmDocument(SrmSettingsList.GetDefault());
RunUI(() => TryHelper.TryTwice(() => SkylineWindow.SwitchDocument(docNew, null)));

// 2. Wait up to 1 second for pool to drain
WaitForCondition(1000, () => !FileStreamManager.Default.HasPooledStreams, ...);

// 3. If streams are still open, report them (doesn't fail — just logs)
if (FileStreamManager.Default.HasPooledStreams)
{
    Console.WriteLine(TextUtil.LineSeparate("Streams left open:", "",
        FileStreamManager.Default.ReportPooledStreams()));
}

// 4. Wait for background loaders and file watchers to stop
WaitForBackgroundLoaders();
WaitForConditionUI(5000, () => SkylineWindow.IsFileSystemWatchingComplete(), ...);
```

#### TestFilesDir.CheckForFileLocks (`TestFilesDir.cs:348+`)

During directory cleanup, `CheckForFileLocks` attempts to delete the test directory.
If deletion fails because a file is locked:

1. Forces GC (`GC.Collect` / `WaitForPendingFinalizers` / `GC.Collect`)
2. Attempts `Directory.Delete(path, true)`
3. On failure, uses `FileLockingProcessFinder.GetProcessesUsingFile` to identify
   which process holds the lock
4. Reports the process name in the exception message

#### Diagnostic queries on the pool

| API | What it tells you |
|-----|-------------------|
| `FileStreamManager.Default.HasPooledStreams` | Are any connections still open? |
| `FileStreamManager.Default.ReportPooledStreams()` | Lists `"{GlobalIndex}. {connection}"` per open connection |
| `ConnectionPool.IsInPool(identity)` | Is a specific Identity's connection open? |

### What's missing — gaps for future work

The current diagnostics answer **what** is open but not **why** or **when**:

1. **No creation stack traces.** When `GetConnection` creates a new connection, it
   doesn't record `Environment.StackTrace`. You can see that GlobalIndex 42 is open,
   but not which code path opened it.

2. **No document version association.** There's no record of which `SrmDocument`
   revision caused each connection to enter the pool. When a stream is left open,
   you can't tell whether it belongs to the current document, an undo-stack entry,
   or a document that should have been garbage collected.

3. **No timestamps.** Connect and disconnect events aren't timestamped. You can't
   see whether a connection was opened 5 seconds ago or 5 minutes ago.

4. **The 1-second wait may be too short.** `WaitForCondition(1000, ...)` gives
   background loaders only 1 second to notice the document change and call
   `CloseRemovedStreams`. Complex teardown with multiple `.skyd` and `.blib` files
   may need more time.

5. **ReportPooledConnections output is minimal.** The format is
   `"{GlobalIndex}. {connection.ToString()}"`. For `PooledFileStream`, `ToString()`
   is the default `Object.ToString()` — it doesn't include the file path. For
   `PooledSqliteConnection`, same issue.

### Future improvements (design sketch)

These are ideas for making file-lock debugging more tractable:

1. **Enhanced `GetConnection` with caller info:**
   ```csharp
   public IDisposable GetConnection(Identity id, Func<IDisposable> connect,
       [CallerFilePath] string callerFile = null,
       [CallerLineNumber] int callerLine = 0)
   ```
   Or capture `Environment.StackTrace` (expensive — gate behind `#if DEBUG` or a
   test-mode flag).

2. **Connect/disconnect event log:**
   ```csharp
   #if DEBUG
   private readonly List<(int GlobalIndex, string Action, DateTime Time, string Stack)> _eventLog;
   #endif
   ```
   Conditional compilation keeps production overhead at zero.

3. **Document version tagging:** Associate each `GetConnection` call with the
   document's revision index, so `ReportPooledConnections` can show which document
   version requested each connection.

4. **Richer ToString on pooled types:** Override `ToString()` on `PooledFileStream`
   and `PooledSqliteConnection` to include the file path:
   ```csharp
   public override string ToString() => $"PooledFileStream({FilePath})";
   ```
   This alone would make `ReportPooledConnections` output actionable.

5. **Longer or adaptive wait in test cleanup:** Instead of a fixed 1-second timeout,
   wait for background loaders to complete their `CloseRemovedStreams` cycle, then
   check pool state.

---

## 9. See Also

### Cross-references
- [architecture-data-model.md](architecture-data-model.md) — SrmDocument immutability, Identity system, undo/redo
- [style-guide.md](style-guide.md) §FileSaver — atomic write patterns and usage rules
- [leak-debugging-guide.md](leak-debugging-guide.md) — handle/memory leak investigation for nightly tests

### Key source files

| File | Lines | Content |
|------|-------|---------|
| `pwiz_tools/Skyline/Util/UtilIO.cs` | 47-184 | `IStreamManager` interface |
| `pwiz_tools/Skyline/Util/UtilIO.cs` | 192-299 | `ConnectionPool` |
| `pwiz_tools/Skyline/Util/UtilIO.cs` | 306-360 | `ConnectionId<TDisp>` abstract base |
| `pwiz_tools/Skyline/Util/UtilIO.cs` | 367-405 | `IPooledStream` interface |
| `pwiz_tools/Skyline/Util/UtilIO.cs` | 410-511 | `PooledFileStream` |
| `pwiz_tools/Skyline/Util/UtilIO.cs` | 513-565 | `PooledSessionFactory` |
| `pwiz_tools/Skyline/Util/UtilIO.cs` | 567-741 | `FileStreamManager` |
| `pwiz_tools/Skyline/Util/UtilIO.cs` | 1132-1306 | `FileSaver` |
| `pwiz_tools/Skyline/Util/PooledSqliteConnection.cs` | 28-100 | `PooledSqliteConnection` |
| `pwiz_tools/Skyline/Model/BackgroundLoader.cs` | 91-106 | `CloseRemovedStreams` |
| `pwiz_tools/Skyline/Model/Results/ChromatogramCache.cs` | 1740-1746 | `CommitCache` |
| `pwiz_tools/Skyline/Model/Results/Chromatogram.cs` | 156-161 | `ChromatogramManager.GetOpenStreams` |
| `pwiz_tools/Skyline/Model/Lib/Library.cs` | 94-102 | `LibraryManager.GetOpenStreams` |
| `pwiz_tools/Skyline/Model/Lib/BiblioSpecLite.cs` | 392-404 | `EnsureConnections` |
| `pwiz_tools/Skyline/Model/Results/MeasuredResults.cs` | 174-177 | `MeasuredResults.ReadStreams` |
| `pwiz_tools/Skyline/Model/Identity.cs` | 44-81 | `Identity`, `GlobalIndex` |
| `pwiz_tools/Skyline/TestUtil/TestFunctional.cs` | 2766-2789 | Test cleanup stream detection |
| `pwiz_tools/Skyline/TestUtil/TestFilesDir.cs` | 348-400 | `CheckForFileLocks` |
| `pwiz_tools/Skyline/TestUtil/MemoryStreamManager.cs` | 29 | `MemoryStreamManager` |
