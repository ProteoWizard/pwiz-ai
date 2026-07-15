# TODO: Open documents directly from .sky.zip without extracting

- **Branch:** `Skyline/work/20260715_open_doc_from_zip`
- **Base:** `master`
- **Created:** 2026-07-15
- **Status:** Active

## Objective

Open a document directly from a `.sky.zip` when the files that need random access
(`.skyd` chromatogram cache, `.blib` spectral libraries) are stored UNCOMPRESSED,
instead of extracting everything first. `SkylineFiles.OpenSharedFile` currently always
extracts via `SrmDocumentSharing.Extract`. The `.sky` XML is read linearly, so it can be
streamed/decompressed on the fly and does not need to be stored uncompressed. Also make
File > Share store `.blib`/`.skyd` uncompressed so shared documents can be opened this way.

Requested by Nick.

## Status at a glance

- [x] Feasibility proven end to end (SQLite can read a `.blib` from a byte-range in the zip)
- [x] Step 1: System.Data.SQLite upgraded to 1.0.119 tree-wide (committed: 49fe0d25b)
- [x] Step 2: `RandomAccessZipFile` + `ByteRangeStream` foundation (uncommitted; unit-tested)
- [x] Step 3: `.blib`-VFS mechanism decided by a bake-off (loadable extension wins)
- [~] Step 4: `.skyd` in-place read - building block `PooledZipEntryStream` done + tested;
      `ChromatogramCache`/`MeasuredResults` wiring still to do
- [x] Safety gate: `CheckDocumentExists` prompts to extract when the doc is `.zip`-backed
      (state + prompt + `ExtractAndOpenSharedFile` refactor done; the in-place open in Step 6
      is what sets `SharedZipFilePath`)
- [ ] Step 5: wire `.blib` in-place read (build + ship the extension, route opens through it)
- [ ] Step 6: `OpenSharedFile` open-in-place decision + `.sky` via ZipStream (sets SharedZipFilePath)
- [ ] Step 7: write side (Share stores `.blib`/`.skyd` uncompressed)
- [ ] PR created

## How it will work (architecture)

A stored (uncompressed) zip entry is a contiguous byte range inside the `.sky.zip` on disk.
So each random-access file can be read in place at its `(offset, length)`:

- `.skyd`: hand `ChromatogramCache` a bounded, read-only, seekable stream over the zip file
  (`ByteRangeStream`). No SQLite involved.
- `.blib`: open the SQLite database through a custom read-only "offset shim" VFS that opens
  the `.zip` and adds the base offset to every read. Selected per-connection by name.
- `.sky` XML: read linearly through a decompressing zip stream (may stay Deflate-compressed).

`RandomAccessZipFile` supplies each entry's `(offset, length, isStored)` by parsing the zip
directory. `OpenSharedFile` opens in place only if every random-access entry is stored;
otherwise it falls back to the existing extract path.

## Step 1 (DONE): Upgrade System.Data.SQLite to 1.0.119 tree-wide

Prerequisite (Nick wanted newest since the version does not matter). Binary swap, not a code
port - API stable 1.0.98 -> 1.0.119, zero source changes. Committed as `49fe0d25b`.

- Skyline core: `libraries/SQLite/{x64,x86}` managed 1.0.98 (IL-mangled from 1.0.105) -> real
  1.0.119; `vendor_api/ABI/{x64,x86}/SQLite.Interop.dll` (gitignored, provided out-of-band)
  -> 1.0.119; `pwiz_tools/Skyline/app.config` DbProviderFactories 1.0.98.0 -> 1.0.119.0 plus a
  new `System.Data.SQLite` binding redirect.
- Osprey.IO + Osprey.Test: `System.Data.SQLite.Core` PackageReference 1.0.118 -> 1.0.119.
- ResourcesOrganizer devtool: committed `lib/sqlite` netstandard2.1 managed + all four native
  interops (win-x64/x86, linux-x64, osx-x64) -> 1.0.119.
- Source of 1.0.119 binaries: NuGet `Stub.System.Data.SQLite.Core.NetFramework` /
  `.NetStandard` 1.0.119 packages (in the local NuGet cache).
- Skipped (Nick): legacy Bumbershoot tools (IDPicker/ScanRanker/BumberDash) - their DLLs are
  not present in the checkout, 30+ version jump, separate products.
- Left dormant: `vendor_api/ABI/{x64,x86}/SQLite_v1.0.98/System.Data.SQLite.dll` (tracked but
  unused; the Jamfile refs to it are commented out) - a deletion candidate, not bumped.
- `libraries/SQLite/update3rdPartyDLLs.bat` (the old IL version-mangle script) is now obsolete;
  left in place (deleting it was not explicitly requested).

Validated: full solution builds; `TestTableExists` (the exact `SqliteOperations.OpenConnection`
path), `DocLoadLibrary`, `TestConnectionPoolReportAndTracking` pass with a matched 1.0.119
managed+interop pair in `bin`; Osprey and ResourcesOrganizer build clean.

The important managed/native pairing rule: the managed `System.Data.SQLite.dll` and the native
`SQLite.Interop.dll` versions MUST match exactly in every output folder, or SQLite calls crash.

## Step 2 (DONE, uncommitted): RandomAccessZipFile + ByteRangeStream

New file `pwiz_tools/Skyline/Util/RandomAccessZipFile.cs` (+ test
`pwiz_tools/Skyline/Test/RandomAccessZipFileTest.cs`, added to both `.csproj`; Test.csproj also
gets a `DotNetZip` reference for the test).

- `RandomAccessZipFile(zipPath)` parses the End-Of-Central-Directory, central directory, and
  per-entry local headers to expose each `ZipEntryInfo { FileName, CompressionMethod,
  UncompressedSize, IsStored, ... }` and, for stored entries, a `ByteRangeStream` over the data.
- ZIP64 aware - essential, because `.skyd`/`.blib` can exceed 4 GB and Share uses
  `Zip64Option.AsNecessary`. Reads 64-bit sizes/offsets from the ZIP64 extra field / ZIP64 EOCD.
- `ByteRangeStream` is a read-only, seekable window `[offset, offset+length)` over a base stream.
- Verified against Ionic-produced zips (production's writer). Ionic uses data descriptors, so
  local-header sizes may be 0 - the parser takes sizes from the central directory and the data
  offset from the local header. Both tests pass.

GOTCHA discovered here: on .NET Framework, `System.IO.Compression.ZipArchive` ALWAYS writes
compression method 8 (Deflate), even with `CompressionLevel.NoCompression` - it cannot produce a
true STORED (method 0) entry. Use Ionic (`CompressionMethod.None`) for the write side and for any
test that needs a real stored entry. Production is fine (Share already uses Ionic).

## Step 3 (DONE): .blib VFS mechanism - the bake-off

Question: how to make System.Data.SQLite read a `.blib` from a byte-range inside the zip, given
1.0.119. Two candidates were built and run against the real 1.0.119 interop.

### 1.0.119 changed the interop's exports (why the old PoC broke)

The original feasibility PoC (on 1.0.98) P/Invoked `sqlite3_vfs_register`/`sqlite3_vfs_find` by
name to register a managed custom VFS. On 1.0.119 that fails: the interop no longer exports the
standard C API by name - exports are HASHED (`SI<16 hex>`), e.g. `sqlite3_open_interop` ->
`SI3eae3b91c35710f2`. The names are a build-time table (not a computable hash - tested
FNV-1/1a, CRC64 x4, MD5/SHA slices, xxHash64, Murmur64A: none match).

Upside: 1.0.119 added a first-class managed `SQLiteConnectionStringBuilder.VfsName`, and native
`sqlite3_open_interop` takes a `vfsName` argument, so SELECTING a registered VFS is clean. The
problem is REGISTERING our VFS.

### Candidate #1 (hashed-symbol P/Invoke): INFEASIBLE

To register a VFS you must call `sqlite3_vfs_register`. It is not among the managed provider's
imports, so its hash cannot be read from the managed assembly. The interop exports 209 hashed
symbols; 196 are the managed provider's `*_interop` wrappers and 13 are extra raw exports. A
diagnostic that probed all 13 found NONE is `vfs_find`/`vfs_register` (and several AccessViolate
when probed with a guessed signature - uncatchable corrupted-state crashes). Conclusion: the raw
`sqlite3_vfs_register` is simply not exported, so there is no P/Invoke path to register a custom
VFS. Abandoned.

### Candidate #2 (loadable extension): WORKS - this is the approach

A tiny native SQLite loadable extension registers a read-only "offset shim" VFS named
`skyzipvfs` using the `sqlite3_api_routines` table handed to its init function - so it is
independent of how the host's SQLite exports are named. The managed provider loads it with
`conn.EnableExtensions(true); conn.LoadExtension(dll, "sqlite3_zipvfs_init");`. The target `.blib`
is then opened via a URI carrying the offset/length and vfs selection.

Proven end to end: read a SQLite DB embedded at offset 1234 inside a container file; the trace
`xRead ... -> real ofst=1234` confirms the shim adds the base offset. Worked with mismatched
headers (built against sqlite 3.49.1; the interop bundles 3.46.1) because the shim only touches
the long-stable `sqlite3_vfs`/`sqlite3_io_methods` structs.

TWO CRITICAL gotchas (both cost real debugging time):

1. LIFETIME: the extension DLL must stay loaded for the whole process. The registered
   `sqlite3_vfs` struct and its functions live inside the DLL; closing the connection that
   loaded the extension unloaded the DLL, and every later open then AccessViolated on unmapped
   memory (the crash appeared BEFORE any VFS method was called - a tell-tale sign). Fix: pin the
   DLL (`LoadLibrary`) or load it once at startup and never unload it.
2. URI MODE: offset/length reach the VFS as URI parameters (`sqlite3_uri_int64(zName,"ofs",...)`),
   so the connection must open in URI mode - use `FullUri=file:///<zip>?ofs=..&len=..&vfs=skyzipvfs`
   (or `Data Source=<zip>` + `VfsName=skyzipvfs` with the URI still supplying ofs/len).

Control check: `VfsName=win32` (a built-in VFS) opened normally, confirming the managed VfsName
selection path itself is fine and the issue was purely our VFS's registration/lifetime.

### The proven extension source (to become a product file)

```c
/*
** zipvfs_ext.c - SQLite loadable extension: a read-only "offset shim" VFS "skyzipvfs" that
** opens the underlying real file through the default VFS but adds a base byte-offset to every
** read, so a db stored uncompressed at an offset inside a .sky.zip can be opened in place.
** Offset/length come from URI params: ...?ofs=NNN&len=NNN&vfs=skyzipvfs  (len 0/omitted =>
** rest of file). Build: cl /O2 /LD zipvfs_ext.c  (x86 + x64). Ship next to SQLite.Interop.dll.
*/
#include "sqlite3ext.h"
SQLITE_EXTENSION_INIT1
#include <string.h>

typedef struct ZipFile ZipFile;
struct ZipFile { sqlite3_file base; sqlite3_file *pReal; sqlite3_int64 ofs; sqlite3_int64 len; };
static sqlite3_vfs *gRoot;

static int zipClose(sqlite3_file *pF){
  ZipFile *p=(ZipFile*)pF; int rc=SQLITE_OK;
  if(p->pReal && p->pReal->pMethods) rc=p->pReal->pMethods->xClose(p->pReal);
  if(p->pReal) sqlite3_free(p->pReal); p->pReal=0; return rc;
}
static int zipRead(sqlite3_file *pF, void *z, int n, sqlite3_int64 o){
  ZipFile *p=(ZipFile*)pF; return p->pReal->pMethods->xRead(p->pReal, z, n, p->ofs+o);
}
static int zipWrite(sqlite3_file *pF, const void *z, int n, sqlite3_int64 o){ (void)pF;(void)z;(void)n;(void)o; return SQLITE_READONLY; }
static int zipTruncate(sqlite3_file *pF, sqlite3_int64 s){ (void)pF;(void)s; return SQLITE_READONLY; }
static int zipSync(sqlite3_file *pF, int f){ (void)pF;(void)f; return SQLITE_OK; }
static int zipFileSize(sqlite3_file *pF, sqlite3_int64 *pS){ *pS=((ZipFile*)pF)->len; return SQLITE_OK; }
static int zipLock(sqlite3_file *pF, int e){ (void)pF;(void)e; return SQLITE_OK; }
static int zipUnlock(sqlite3_file *pF, int e){ (void)pF;(void)e; return SQLITE_OK; }
static int zipCheckReservedLock(sqlite3_file *pF, int *pR){ (void)pF; *pR=0; return SQLITE_OK; }
static int zipFileControl(sqlite3_file *pF, int op, void *pA){ (void)pF;(void)op;(void)pA; return SQLITE_NOTFOUND; }
static int zipSectorSize(sqlite3_file *pF){ (void)pF; return 4096; }
static int zipDeviceCharacteristics(sqlite3_file *pF){ (void)pF; return SQLITE_IOCAP_IMMUTABLE; }
static const sqlite3_io_methods zipIoMethods = {
  1, zipClose, zipRead, zipWrite, zipTruncate, zipSync, zipFileSize,
  zipLock, zipUnlock, zipCheckReservedLock, zipFileControl, zipSectorSize, zipDeviceCharacteristics
};

static int zipOpen(sqlite3_vfs *pVfs, const char *zName, sqlite3_file *pFile, int flags, int *pOut){
  ZipFile *p=(ZipFile*)pFile; int rc; (void)pVfs;
  memset(p,0,sizeof(*p));
  p->ofs = sqlite3_uri_int64(zName, "ofs", 0);
  p->len = sqlite3_uri_int64(zName, "len", 0);
  p->pReal = (sqlite3_file*)sqlite3_malloc(gRoot->szOsFile);
  if(!p->pReal) return SQLITE_NOMEM;
  memset(p->pReal, 0, gRoot->szOsFile);
  rc = gRoot->xOpen(gRoot, zName, p->pReal, (flags & ~SQLITE_OPEN_READWRITE) | SQLITE_OPEN_READONLY, pOut);
  if(rc!=SQLITE_OK){ sqlite3_free(p->pReal); p->pReal=0; return rc; }
  if(p->len==0){ sqlite3_int64 sz=0; p->pReal->pMethods->xFileSize(p->pReal,&sz); p->len = sz - p->ofs; }
  p->base.pMethods = &zipIoMethods;
  return SQLITE_OK;
}
/* xFullPathname/xAccess/xDelete delegate to gRoot explicitly (proven-safe); all other VFS
** methods are inherited from the default VFS by the memcpy in init. */
static int zipFullPathname(sqlite3_vfs *v, const char *z, int n, char *o){ (void)v; return gRoot->xFullPathname(gRoot,z,n,o); }
static int zipAccess(sqlite3_vfs *v, const char *z, int f, int *r){ (void)v; return gRoot->xAccess(gRoot,z,f,r); }
static int zipDelete(sqlite3_vfs *v, const char *z, int s){ (void)v; return gRoot->xDelete(gRoot,z,s); }

#ifdef _WIN32
__declspec(dllexport)
#endif
int sqlite3_zipvfs_init(sqlite3 *db, char **pzErr, const sqlite3_api_routines *pApi){
  static sqlite3_vfs zipVfs;   /* static storage: persists for the DLL's lifetime */
  SQLITE_EXTENSION_INIT2(pApi);
  (void)db;(void)pzErr;
  gRoot = sqlite3_vfs_find(0);
  if(!gRoot) return SQLITE_ERROR;
  if(sqlite3_vfs_find("skyzipvfs")) return SQLITE_OK;   /* already registered */
  memcpy(&zipVfs, gRoot, sizeof(zipVfs));   /* correct layout by construction */
  zipVfs.szOsFile = sizeof(ZipFile);
  zipVfs.zName = "skyzipvfs";
  zipVfs.pNext = 0;
  zipVfs.xOpen = zipOpen;
  zipVfs.xFullPathname = zipFullPathname;
  zipVfs.xAccess = zipAccess;
  zipVfs.xDelete = zipDelete;
  return sqlite3_vfs_register(&zipVfs, 0);
}
```

Managed loader sketch (proven in the spike):

```csharp
NativeMethods.LoadLibrary(extDllPath);              // pin the DLL for the process lifetime
using (var boot = new SQLiteConnection("Data Source=:memory:;Version=3;")) { // keep-alive not
    boot.Open();                                    // required once the DLL is pinned, but the
    boot.EnableExtensions(true);                     // registration must happen once at startup
    boot.LoadExtension(extDllPath, "sqlite3_zipvfs_init");
}
// then, per .blib in a zip (offset/len from RandomAccessZipFile):
var cs = $"FullUri=\"file:///{zipPath.Replace('\\','/')}?ofs={ofs}&len={len}&vfs=skyzipvfs\";Version=3;Read Only=True;";
```

## Remaining work

### Step 4: `.skyd` in-place read (no SQLite; the biggest single win)

DONE (building block): `Util/PooledZipEntryStream.cs` - an `IPooledStream` whose `Stream` is a
`ByteRangeStream` over the `.sky.zip` at a stored entry's `(offset, length)`; `FilePath` reports
the logical extracted path (pool identity) while bytes come from the zip and staleness tracks the
zip's write time. Compressed entries are rejected. Unit test `TestPooledZipEntryStream` passes.
It opens a fresh `FileStream` per Connect (FileShare.Read) so concurrent readers don't collide.

DONE (Step 6 gate, tested): `RandomAccessZipFile.AreEntriesStored(params string[] extensions)` -
true iff every entry with one of the given extensions (".skyd", ".blib") is stored uncompressed,
i.e. the document can be opened in place. Unit test `TestAreEntriesStored` passes.

STILL TO DO (the wiring) - a transparent zip-aware IStreamManager will NOT work, because the
`.skyd` load path has several DIRECT filesystem accesses that bypass the StreamManager and assume
a real file. All of these must be made zip-aware (thread a zip-backed cache source through, or a
`(RandomAccessZipFile zip, ZipEntryInfo skydEntry)` context):
- `MeasuredResults.LoadFinalCache` `File.Exists(cachePath)` (~line 1315) and
  `File.OpenRead(cachePath)` + `ChromatogramCache.GetCachedFilePaths(stream)` (~line 1320).
- `MeasuredResults` calls `ChromatogramCache.Load(cachePath,...)` at ~1330, 1620, 1718, 1788, 1826.
- `ChromatogramCache.Load` (~693) `loader.StreamManager.CreatePooledStream(cachePath,false)` ->
  supply a `PooledZipEntryStream` (done - the building block) instead, via the existing
  `ChromatogramCache(..., IPooledStream readStream)` ctor / `ChangeReadStream`.
- `ChromatogramCache.ReadDataForAll` (~line 1969) opens `new FileStream(CachePath,...)` directly,
  bypassing the pool - must be redirected to the zip-backed stream too.
- The `.zip` stays on disk for the doc session (like the `.skyd`/`.blib` do today).
This is the large, careful core-results-loading refactor; it can only be exercised once Step 6
provides the zip context, so it and Step 6 should land together.

### Safety gate (DONE): CheckDocumentExists extraction prompt

`SkylineWindow.SharedZipFilePath` (in SkylineFiles.cs) holds the `.zip` path when the document was
opened in place; null otherwise. `OpenFile` clears it (any on-disk open). `CheckDocumentExists`,
called before disk-modifying operations, now: if `SharedZipFilePath != null`, shows a prompt
("This document was opened directly from '{0}'. ... extract them now?") and on OK extracts to a new
folder and reopens via `ExtractAndOpenSharedFile`, returning false so the user re-initiates the
operation on the now-on-disk document. Two new `SkylineResources` strings added. `OpenSharedFile`
was refactored to call a reusable `ExtractAndOpenSharedFile` (pure refactor, no behavior change).
Note: the state is only *set* once Step 6 (open-in-place) lands, so the gate is currently inert but
wired and building. Also consider gating `SaveDocument`/autosave the same way.

### Step 5: `.blib` in-place read

- Build `zipvfs_ext.c` for x86 + x64 and ship it beside `SQLite.Interop.dll` (prebuilt-committed
  is fine, same model as the interop; or add a bjam/native build step).
- Register the VFS once at Skyline startup (pin the DLL, load the extension).
- Route `.blib`-in-zip opens through the FullUri form above. The natural seam is
  `SqliteOperations.OpenConnection` / `PooledSqliteConnection.Connect` (a variant that takes a
  zip path + offset/length). The connection/VFS must stay valid for the whole doc session
  (BiblioSpecLite keeps a persistent connection, lazy `ReadSpectrum`).

### Step 6: OpenSharedFile open-in-place decision

- In `SkylineFiles.OpenSharedFile`, use `RandomAccessZipFile` to check whether every entry that
  needs random access (`.skyd`, `.blib`, redundant `.blib`) is stored uncompressed. If so, open in
  place; else fall back to the existing `SrmDocumentSharing.Extract` path.
- Read the `.sky` XML through a decompressing zip stream (it may remain Deflate).

### Step 7: write side

- `SrmDocumentSharing.ZipFileShare.AddFile`: set `entry.CompressionMethod = CompressionMethod.None`
  for `.blib`/`.skyd` (and redundant `.blib`) so shared documents can be opened without extraction.
  `_zip.AddFile(path, "")` returns the `ZipEntry` to set this on. Other entries stay Deflate.

## Tests

- Done: `TestRandomAccessZipFile`, `TestByteRangeStreamBounds` (pass); SQLite-upgrade tests above.
- TODO: round-trip functional test (Share with stored `.blib`/`.skyd`, then OpenSharedFile in
  place, verify chromatograms + library spectra load and match the extracted path); a large-file
  (>4 GB, ZIP64) case for the offset math; fallback-to-extract when an entry is compressed.

## Key references / gotchas (quick list)

- Managed+native System.Data.SQLite versions must match exactly per output folder.
- `System.IO.Compression.ZipArchive` on .NET Framework cannot write a stored (method-0) entry; use Ionic.
- 1.0.119 interop exports are hashed (`SI<hex>`); the raw sqlite3 C API (incl. `vfs_register`) is not exported.
- The extension DLL must stay loaded for the process lifetime (the registered VFS lives in it).
- `.blib` open needs URI mode to pass ofs/len; select the VFS via `VfsName` or `?vfs=`.
- `.skyd` is self-contained; `.peaks/.scans/.scores` are build-time temporaries only.
- Spikes were developed in the session scratchpad (ephemeral). The extension source above is the
  durable copy. The earlier `ai/.tmp/zipvfs-poc` PoC was wiped when `ai/.tmp` was cleaned.
