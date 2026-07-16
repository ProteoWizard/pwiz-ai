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
- [x] Step 2: `RandomAccessZipFile` + `ByteRangeStream` foundation (committed; unit-tested)
- [x] Step 3: `.blib`-VFS mechanism decided by a bake-off (loadable extension wins)
- [x] `FilePath` (Skyline/Util) - the zip-aware path type (Nick's chosen design; see below)
- [x] Step 4: `.skyd` in-place read - `PooledZipEntryStream` + the `FilePath` wiring done;
      VERIFIED reading a real 28 MB stored `.skyd` in place from a `.sky.zip`
- [x] Safety gate: `CheckDocumentExists` extracts (no prompt) when the doc is `.zip`-backed
- [x] Step 7: write side (Share stores `.blib`/`.skyd` uncompressed)
- [x] VFS extension `libraries/SQLite/slicevfs.c` committed + Jamfile `lib slicevfs` rule
      (verified working); open-in-place criterion `ContainsOnlyEntriesWithSuffixes` +
      `OpenInPlaceExtensions` (tested). NAMING: the extension knows nothing about zips - it exposes
      a byte range of any file - hence `slicevfs` (was `zipvfs_ext`/`skyzipvfs`; the bake-off
      narrative below still uses the old names).
- [x] Step 5: `.blib` in-place read - DONE + VERIFIED (read 29 RefSpectra from a real .blib stored
      inside a .sky.zip). `SqliteSliceVfs` pins+loads `slicevfs.dll` and opens the .blib at its byte
      range (`FullUri ... ?ofs=&len=&vfs=slicevfs`); `PooledSqliteConnection.Connect` routes zip
      .blib paths through it. `slicevfs.dll` is built from source by bjam (the `install-slicevfs`
      rule in the Skyline Jamfile builds the `libraries/SQLite//slicevfs` shared lib and installs
      it next to `SQLite.Interop.dll` in `ProteowizardWrapper/obj/$(PLATFORM)`); Skyline.csproj
      copies it from there as Content. No prebuilt binary is committed anymore.

- [x] SQLite interop provisioning FIXED: the native `SQLite.Interop.dll` was bundled at 1.0.109
      inside `pwiz_aux/msrc/utility/vendor_api_ABI.7z` (the SCIEX ABI vendor package), which the
      build re-extracts overwrite-all every time -> it reverted the interop to 1.0.109 and mismatched
      the committed managed 1.0.119 (EntryPointNotFound on hashed symbols). Swapped the x64/x86
      `SQLite.Interop.dll` inside the .7z to 1.0.119 (password `i-agree-to-the-vendor-licenses`;
      solid+AES archive so extract-swap-recreate, not in-place update). Managed-provider tests pass
      (TestTableExists, DocLoadLibrary, TestConnectionPoolReportAndTracking). REMAINING CHECK: verify
      SCIEX WIFF reading still works, since Clearcore2 shares this interop (needs real .wiff data).
      VERIFIED: Nick confirmed .wiff reading still works with the 1.0.119 interop (J:\skydata\pedro).
- [x] Step 6: `OpenSharedFile` in-place branch - `CanOpenInPlace` (only DocumentZipSuffixes +
      .skyd/.blib stored) -> `OpenSharedFileInPlace` reads `.sky` from the zip, `OpenFile(<zip>\doc.sky)`,
      sets `SharedZipFilePath`. Load pipeline made FilePath-aware (`CheckResults`, `ConnectLibrarySpecs`,
      `BiblioSpecLite`, `MeasuredResults.CheckFinalCache`, `ChromatogramCache`, `PooledSqliteConnection`).
      FilePath now compares paths case-sensitively (Ordinal) since zip entry names are case-sensitive.
- [x] End-to-end functional test: `OpenDocFromZipTest` (committed, passes)
- [x] Gate `SaveDocument` like `CheckDocumentExists` (prompts to extract before writing a zip-backed
      doc; `OpenDocFromZipTest` covers it)
- [x] Jamfile deployment wiring for `zipvfs_ext.dll` (built from source, installed to obj; no
      committed binary). Verified: `quickbuild ... pwiz_tools/Skyline//install-zipvfs-ext` builds the
      DLL into `ProteowizardWrapper/obj/x64`, MSBuild copies it to output, functional test passes.
- [x] Open PR: https://github.com/ProteoWizard/pwiz/pull/4426 (DRAFT; Copilot round addressed)
- [x] Session 3: `.skyl` opens in place; `CheckDocumentExists` extracts silently; `DocumentStreams`
      closes streams opened for a document that is no longer current (see Session 3 below)
- [ ] BLOCKER: `.wiff2` is broken by the Step 1 SQLite 1.0.119 upgrade (licensing gate on encrypted
      databases) - see "BLOCKER (session 3)" below. Not fixed; not caused by the zip work.
- [ ] NEXT: TeamCity green on the full suite, then `/pw-self-review 4426` (still not run)

## Session 2 additions (pushed)

- [x] Share progress says "Storing {0}" for entries stored uncompressed vs "Compressing {0}" for
      the rest (`SrmDocumentSharing_SaveProgress`, keyed off `e.CurrentEntry.CompressionMethod`).
- [x] Split `DocumentZipSuffixes` into `SequentialAccessExtensions` (`.sky`/`.sky.view`/`.skyl` -
      read sequentially, may be compressed) vs `RandomAccessExtensions` (stored). `OpenInPlaceExtensions`
      is the union; a `.zip` opens in place when every entry is in it.
- [x] Moved `FilePath` + `RandomAccessZipFile`/`ByteRangeStream` to `pwiz.Common.Database.FileSystems`,
      and `ZipVfs` -> `SqliteSliceVfs` in `pwiz.Common.Database` (next to `SqliteOperations`). Common
      needs no DotNetZip: `FilePath.OpenRead` decompresses via `System.IO.Compression`. Kept
      `ConnectionPool`/`IPooledStream`/`PooledZipEntryStream` in Skyline (bridge via `TryGetZipEntry`).
- [x] `.protdb` (background proteome) added to `RandomAccessExtensions`. `SessionFactoryFactory`
      opens a zip-backed db through a read-only `SqliteSliceVfs.GetConnectionString` (slicevfs URI),
      so NHibernate reads a `.protdb` in place; `ProteomeDb` uses `FilePath` for existence, and
      `FindBackgroundProteome` resolves the proteome to its in-zip path. Test: `OpenProteomeFromZipTest`.
- [ ] EDGE (Nick: fall back to extract): a zip-backed `.protdb` whose schema is older than current
      would hit `ProteomeDb`'s upgrade branch and attempt a write on the read-only slicevfs connection
      (fails). Rare for a freshly-shared, current proteome. True extract-fallback not yet wired.
- [ ] `.elib` (EncyclopeDIA) intentionally still extracts - it always needs a sibling `.elibc`.

## Session 3 additions (pushed: 676f788d6, 8565c05bb)

### `.skyl` in place, and the fallout (commit 676f788d6)

- [x] `.skyl` added to `SequentialAccessExtensions` (Nick's correction - there is no `.sky.log`).
      Audit log read in place (`AuditLogEntry.ReadFromFile` via `FilePath.OpenRead` +
      `XmlTextReader(stream)`; `SrmDocument.ReadAuditLog` via `FilePath.Exists`).
- [x] `.sky.view` read in place (`SkylineGraphs` layout load) - without this the audit log form did
      not restore, which is how `DirtyDocumentSharingTest` failed.
- [x] `CheckResults` no longer tries to `FileEx.SafeDelete` a `.skyd` inside the zip (guarded with
      `IsInZipFile`) - it threw `DirectoryNotFoundException` into a swallowing catch.
- [x] `CheckDocumentExists` extracts without prompting (see the reworked safety-gate section above).
- [x] `AssertEx.FileExists`/`FileNotExists` go through `FilePath`, so they find in-zip files.
- [x] `Kernel32.LoadLibrary` moved into `pwiz.Common.SystemUtil.PInvoke` - `SqliteSliceVfs` had a
      raw `[DllImport]`, which `CodeInspection` prohibits (it would have failed CI). NOTE:
      `CodeInspectionTest` declares an EXPECTED `[DllImport]` COUNT per class (`Kernel32` 8 -> 9);
      adding a P/Invoke means bumping it.

Test fallout, all from in-place becoming the common path. Only ONE was the extract prompt; the rest
were tests reaching around Skyline's file abstraction to check things on disk themselves:
- `DirtyDocumentSharingTest`, `LibraryBuildShareTest` - pass with NO test change.
- `ChangeDocumentGuidTest` - `File.Copy` on an in-zip `DocumentFilePath`; added a `FilePath`-based
  `CopyFile` helper (it builds a "frankendoc" folder, so it genuinely needs real files).
- `LegacyIgnoreSimTest` (`XmlDocument.Load`), `LegacyOptimizationStepTest` (`File.OpenRead` on the
  `.skyd`) - one-line `FilePath.OpenRead` swaps.
- `InternationalFilenamesTest` - now uses `AssertEx.FileExists` and asserts the in-zip paths.
- `JsonToolServerTest` line ~1884 asserts `DocumentFilePath.EndsWith(".sky")` to prove extraction;
  an in-zip path ALSO ends in `.sky`, so it still passes but tests nothing. NOT yet fixed.

### Stream lifetime: DocumentStreams (commit 8565c05bb)

`TestInternationalFilenames` leaked one `PooledFileStream` on the PREVIOUS document's on-disk
`.skyd`, at a different loop iteration each run (also seen as a GC-LEAK: an open stream roots the
document, which roots `SkylineWindow`). Controlled experiment: forcing `CanOpenInPlace` to return
false gave 3/3 passes; with in-place on it failed on iteration 1. PRE-EXISTING race - opening in
place is just fast enough to win it, where extracting was slow enough to lose.

Root cause: `ChromatogramCache.Load` MANUFACTURES a `PooledFileStream` while building a new
`MeasuredResults`, i.e. the stream exists before any document holds it. If the container swaps
documents before that document lands, nothing can close it - `BackgroundLoader.OnDocumentChanged`
already ran `CloseRemovedStreams`, and `CloseStream()` on a not-yet-connected stream is a no-op.

Fix = Nick's abandoned branch `Skyline/work/20260203_DocumentStreams`, revived:
- `Util/DocumentStreams.cs` - an `IDisposable` scope that closes the streams the container's current
  document does not have. `AddStream`/`AddStreams` track streams that no document holds YET, which
  is the part a document snapshot alone cannot cover (two of my attempts failed on exactly this).
- `SrmDocument.GetOpenStreams()` (libraries + `MeasuredResults`) REPLACES the per-loader
  `GetOpenStreams`/`CloseRemovedStreams`, deleted from `BackgroundLoader` + all 8 managers (6 were
  empty stubs). That split ownership WAS the bug: a `LibraryManager` load calls `ChangeSettings`,
  which reads chromatograms, so the stream is opened by one loader and owned by another and no
  single loader's `CloseRemovedStreams` could ever close it.
- Scopes: `SkylineWindow.SetDocument` (REQUIRED - it is what replaces the per-change closing; the
  `OnLoadBackground` scope only runs when a load thread starts, so an `IsLoaded` swap would close
  nothing), `BackgroundLoader.OnLoadBackground`, `LibraryManager.CallWithSettingsChangeMonitor`,
  and `ChromatogramManager` (the `AddStreams(results)` one that actually fixes the leak).
- `ConnectionPool.RecordEvent` takes an `Identity` (history keyed by `ReferenceValue<Identity>`, not
  `int`) - readable traces with real filenames.
- Two debugging switches, BOTH OFF (Nick: no noise even under Debug): private static
  `AllDocumentStreams` (null; set it to a `ConcurrentDictionary` to make `EnsureTracked` report
  streams nothing will close) and `DocumentStreams.DumpStreamsRegex` (null; set it to e.g.
  `new Regex(@"\.skyd")` to log a stream's pool events, then diff a leaking run vs a clean one).
  Unfiltered `EnsureTracked` fired 35x over 3 passing tests, mostly `PooledSqliteConnection` paths
  that have no scope yet - that noise is the to-do list if this is ever picked up again.

Result: `TestInternationalFilenames` 8/8 (was failing on iteration 1 every run).

NOT taken from the branch (orthogonal): its `BiblioSpecLite` hunk (swaps a stream-closing loop for a
scope; needs the `DocumentStreams(IEnumerable<IPooledStream>)` ctor, which I dropped) and its
`GraphSpectrum` rendering scope.

WHY the branch was abandoned (my read): the scope model needs a `DocumentStreams` at EVERY site that
manufactures a stream, and the set is open-ended - hence its `#if DEBUG` `EnsureTracked` tripwire
hunting for uncovered sites, and scopes spreading into `GraphSpectrum`/`BiblioSpecLite`/
`ChromatogramCache`/`LongWaitDlg`/`SkylineFiles`/`Skyline.cs`. This session took only the scopes
needed for the leak.

RISK: stream lifetime is now global to Skyline (`SetDocument` runs on every document change), and
local testing covered only a slice of the functional suite. TeamCity's full run is the real check.

### BLOCKER (session 3, NOT yet fixed): .wiff2 broken by the SQLite 1.0.119 upgrade

TeamCity run 21566 on `8565c05bb` had TWO failure classes. Class 1 ("Streams left open", ~27
tests) was mine and is fixed (see the MemoryDocumentContainer commit). Class 2 is this, and it is
PRE-EXISTING on this branch from the Step 1 SQLite upgrade, independent of all the zip work:

`Wiff2ResultsTest`, `TestInstrumentInfo`, `TestInstrumentSerialNumbers`, `FileTypeTest` fail with
`[WiffFile2Impl::ctor()] Could not load file or assembly 'System.Data.SQLite.SEE.License,
Version=1.0.119.0, Culture=neutral, PublicKeyToken=0a9a2a02614f8a52'`. Reproduces locally too.
`.wiff` (v1) is fine - it is not SQLite. `.wiff2` IS a SQLite database, opened WITH A PASSWORD.

ROOT CAUSE (established by decompiling, not guessed - dotPeek export at
`C:\Users\nicksh\source\System.Data.SQLite`):
- Managed `System.Data.SQLite` 1.0.119 contains a class `SQLiteExtra` - a "Harpy late-bound
  licensing SDK" gate. `InnerVerify` does
  `Assembly.Load("System.Data.SQLite.SEE.License, Version=1.0.119.0, ..., PublicKeyToken=0a9a2a02614f8a52")`
  and throws `NotSupportedException` if it cannot verify; it looks for that assembly or an
  `SDS-SEE.exml` certificate, and on failure will even `Process.Start` a purchase URL
  (`https://urn.to/r/sds_see1`) when `Environment.UserInteractive`. Its header says its use "is
  governed by a special license agreement".
- `SQLiteExtra.Verify` is called from EXACTLY three places, all password/encryption entry points:
  `SQLite3.SetPassword` (-> `sqlite3_key`), `SQLite3.ChangePassword` (-> `sqlite3_rekey`), and
  `SQLite3.DecryptLegacyDatabase`. THAT is why every other SQLite path in this branch is fine:
  `.blib`/`.protdb`/`.skyd` never set a password, so they never reach the gate. Clearcore2's wiff2
  reader sets one, so it does.
- So encrypted-db support is a PAID feature in modern System.Data.SQLite. 1.0.98 (SCIEX's copy) has
  no `SEE.License` literal at all - no gate - which is why wiff2 worked before this branch.
  1.0.118 HAS the same literals, so this is not a 1.0.119 regression; the gate predates it.
  There is no supported bypass (`Override_SEE_Certificate`/`AlwaysVerifyLicense` still require a
  valid certificate), and I did not go looking for an unsupported one.

FIX DIRECTION (Nick): let wiff2 use the OLD dll and Skyline the NEW one, side by side.
- `pwiz_tools/Skyline/app.config` has `<bindingRedirect oldVersion="0.0.0.0-1.0.119.0"
  newVersion="1.0.119.0"/>` for `System.Data.SQLite` (ADDED BY THIS BRANCH in Step 1). Both
  versions are strong-named with the SAME token (db937bc2d44ff139) and differ only by version, so
  the CLR WOULD load them side by side - the redirect is exactly what prevents it, forcing
  Clearcore2 (compiled against 1.0.98) onto the gated 1.0.119.
- `vendor_api/ABI/{x64,x86}/SQLite_v1.0.98/System.Data.SQLite.dll` is SCIEX's own 1.0.98 copy. The
  TODO previously called it "dormant ... a deletion candidate" - WRONG, it is precisely what a
  side-by-side load needs. Do not delete it. Its Jamfile refs are commented out.
- CAVEAT before touching this: the managed/native pairing rule. There is ONE `SQLite.Interop.dll`
  in the output folder (now 1.0.119). 1.0.98-managed + 1.0.119-interop is exactly the mismatch that
  crashes, so the split probably needs the vendor's interop kept private to the vendor path too,
  not just the redirect narrowed. Unverified.
- WORTH READING: https://github.com/ProteoWizard/pwiz/pull/4178 (Port ProteoWizard core to .NET 8)
  hit the same wall and solved it by loading `.wiff2` via `SCIEX.Apis.Data.v1` in a SIDE-BY-SIDE
  `AssemblyLoadContext`. ALC is .NET Core+ only so we cannot use it on 4.7.2, but the PR should
  show why isolation was needed and whether they also had to pair a private interop with it.

NOTE the TODO's earlier "VERIFIED: Nick confirmed .wiff reading still works with the 1.0.119
interop" was a real check that simply did not cover .wiff2.

FUTURE (Nick's design, not the "for now" criterion): make `OpenSharedFile` start reading the `.sky`
straight from the zip, and as soon as `DocumentReader.ReadXml` gets past the `settings_summary`
element, decide whether it can read everything it needs directly from the zip or must extract.
The "for now" path is the simpler whole-zip-inspection criterion above.

## Architecture decision (Nick): FilePath, not a resolver

Instead of a global path->zip resolver, the zip-ness lives IN THE PATH STRING: a path like
`C:\MyDocument.sky.zip\Library.blib` means entry "Library.blib" inside the zip. `FilePath` (a thin
wrapper over one string, in Skyline/Util) has zip-aware `Exists`/`OpenRead`/`GetLastWriteTime`/
`OpenPooledStream`/`TryGetZipByteRange` that transparently handle such paths (stored entries read in
place and seekable; compressed decompressed; `GetLastWriteTime` = the outermost zip's time). The
choke points just switch `File.*` -> `new FilePath(path).*`, which is a no-op for ordinary paths.
So when the document is opened in place, its `DocumentFilePath` becomes `<zip>\doc.sky` and every
derived path (`<zip>\doc.skyd`, `<zip>\lib.blib`) is a self-describing zip path. Longer term this
becomes a proper strongly-typed path type replacing raw strings. (FileEx was NOT used - it lives in
CommonUtil, which must not take a zip dependency.)

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
  unused; the Jamfile refs to it are commented out). DO NOT DELETE - this was called a deletion
  candidate, but it is SCIEX's own ungated 1.0.98 and is what .wiff2 needs to bind to. See the
  .wiff2 BLOCKER section.
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

### Safety gate (DONE, reworked in session 3): CheckDocumentExists extracts silently

`SkylineWindow.SharedZipFilePath` (in SkylineFiles.cs) holds the `.zip` path when the document was
opened in place; null otherwise. `OpenFile` clears it (any on-disk open). `CheckDocumentExists` is
called before disk-modifying operations (`SaveDocument`, Import Results, and the peptide-search
dialogs - the only six call sites). If `SharedZipFilePath != null` it now extracts WITHOUT prompting
and re-points the open document at the extracted files, so tests and users need do nothing. The two
prompt strings were deleted from `SkylineResources`.

Nick's design (session 3), and both parts matter:
- `ExtractAndOpenSharedFile` was split: `ExtractSharedFile` just extracts and returns the document
  path, and callers do the `OpenFile`. `CheckDocumentExists` does NOT re-open - it sets
  `DocumentFilePath` to the extracted path, clears `SharedZipFilePath`, calls `SetActiveFile`
  (which puts the extracted path at the top of the MRU) and removes the in-zip path from the MRU.
- Keeping the in-memory document instead of re-opening fixes TWO bugs the old prompt path had:
  (1) DATA LOSS - re-opening replaced the document, silently discarding unsaved edits (proven by
  `ChangeDocumentGuidTest`, which pastes ELVISK then saves); and (2) a DEADLOCK - `OpenFile` calls
  `ReadAuditLog(..., AskForLogEntry)`, which shows a modal `AlertDlg` from a background worker via
  `Invoke` while the UI thread sits inside the test's `RunUI`. That hung `TestChangeDocumentGuid`
  with no output at all.

### Step 5: `.blib` in-place read

- Build `zipvfs_ext.c` for x86 + x64 and ship it beside `SQLite.Interop.dll` (prebuilt-committed
  is fine, same model as the interop; or add a bjam/native build step).
- Register the VFS once at Skyline startup (pin the DLL, load the extension).
- Route `.blib`-in-zip opens through the FullUri form above. The natural seam is
  `SqliteOperations.OpenConnection` / `PooledSqliteConnection.Connect` (a variant that takes a
  zip path + offset/length). The connection/VFS must stay valid for the whole doc session
  (BiblioSpecLite keeps a persistent connection, lazy `ReadSpectrum`).

### Step 6 (DONE): OpenSharedFile open-in-place decision

- `SkylineFiles.OpenSharedFile` calls `CanOpenInPlace` (via `RandomAccessZipFile`): the `.zip` must
  contain only `DocumentZipSuffixes` entries AND have the `RandomAccessExtensions` (`.skyd`,
  `.blib`) stored uncompressed. If so `OpenSharedFileInPlace` opens `<zip>\doc.sky` through
  `FilePath` and sets `SharedZipFilePath`; otherwise `ExtractAndOpenSharedFile` (the old path).
- The whole load pipeline was made `FilePath`-aware so background loaders read `.skyd`/`.blib`
  from inside the `.zip`: `BiblioSpecLite` -> `ZipVfs.OpenConnection`, `MeasuredResults`,
  `ChromatogramCache`, `PooledSqliteConnection`, plus `CheckResults`/`ConnectLibrarySpecs` dialogs.

### Step 7 (DONE): write side

- `SrmDocumentSharing.ZipFileShare.AddFile` sets `CompressionMethod.None` for
  `RandomAccessExtensions` (`.skyd`/`.blib`, incl. redundant `.blib`); other entries stay Deflate.

### Audit log (`.skyl`) - RESOLVED in session 3

- `.skyl` is in `SequentialAccessExtensions`, so a share of an audit-logged document opens in place.
  `AuditLogList.ReadFromFile` reads the `.skyl` through `new FilePath(fileName).OpenRead()` and
  `SrmDocument.ReadAuditLog` tests existence through `FilePath`.
- NOTE the consequence: audit logging is on by default, so in-place is now the COMMON path for
  shared documents rather than a rare one. That is what turned up the fallout in session 3 below.

## Tests

- Done (unit): `TestRandomAccessZipFile`, `TestByteRangeStreamBounds`, `TestPooledZipEntryStream`,
  `TestAreEntriesStored`, `TestContainsOnlyEntriesWithSuffixes`, `TestFilePath`; SQLite-upgrade tests.
- Done (functional): `OpenDocFromZipTest` - shares `LibraryShareTest` as a stored `.sky.zip`, opens
  it in place, asserts `SharedZipFilePath`/in-zip path, and that peptide/transition counts, library
  spectrum count (`.blib`), and chromatogram point count (`.skyd`) match the same document opened
  normally. `OpenProteomeFromZipTest` - reads a `.protdb` in place through NHibernate + slicevfs.
- Done (functional, session 3): `ChangeDocumentGuidTest` now exercises the IN-PLACE path (its share
  is `.sky`/`.sky.view`/`.skyl` only) and proves the extract-on-save keeps unsaved edits.
  `TestInternationalFilenames` is the regression test for the `DocumentStreams` leak.
- Green locally (session 3): the zip suite x2 loops, `TestRetentionTimeManager`,
  `TestMinimizeWithEmptyFiles`, `TestFilesTreeForm`, `TestMinimizeIrt`, `TestSkyp`,
  `TestShareDocument`, `TestResultFileMetadataBackCompat`, `TestLibraryShare`,
  `TestBuildLibraryShare`, `CodeInspection`.
- TODO: a large-file (>4 GB, ZIP64) case for the offset math; explicit fallback-to-extract test
  when an entry is compressed; fix the now-vacuous `JsonToolServerTest` assert.

## Key references / gotchas (quick list)

- Managed+native System.Data.SQLite versions must match exactly per output folder.
- `System.IO.Compression.ZipArchive` on .NET Framework cannot write a stored (method-0) entry; use Ionic.
- 1.0.119 interop exports are hashed (`SI<hex>`); the raw sqlite3 C API (incl. `vfs_register`) is not exported.
- The extension DLL must stay loaded for the process lifetime (the registered VFS lives in it).
- `.blib` open needs URI mode to pass ofs/len; select the VFS via `VfsName` or `?vfs=`.
- `.skyd` is self-contained; `.peaks/.scans/.scores` are build-time temporaries only.
- `CodeInspection` prohibits raw `[DllImport]` (use `pwiz.Common.SystemUtil.PInvoke`) AND asserts an
  expected `[DllImport]` count per class in `CodeInspectionTest.InspectPInvokeApi`.
- A stream can be OPENED by one background loader and OWNED by another (a library load changes the
  settings, which reads chromatograms), and `ChromatogramCache.Load` creates streams before any
  document holds them. That is why stream closing has to be document-level (`DocumentStreams`).
- `Run-Tests.ps1` defaults to `-Loop` FOREVER; pass `-Loop 1`. `-Summary` HIDES console output (so
  it hides `DumpStreamsRegex`/`EnsureTracked` dumps). The per-test "N failures" column is a RUNNING
  TOTAL, not per-test - easy to misread as every later test failing.
- Spikes were developed in the session scratchpad (ephemeral). The extension source above is the
  durable copy. The earlier `ai/.tmp/zipvfs-poc` PoC was wiped when `ai/.tmp` was cleaned.
