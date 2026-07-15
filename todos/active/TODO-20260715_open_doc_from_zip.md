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

## Feasibility (proven)

The make-or-break question was whether SQLite can read a `.blib` from a byte-range inside
the zip. PROVEN YES: a managed-registered custom read-only VFS (P/Invoke
`sqlite3_vfs_register`) whose `xRead` adds a base offset opened a DB embedded at an offset
inside a container file and queried it correctly, using the shipped provider with no native
rebuild. PoC in `ai/.tmp/zipvfs-poc/`. The `.skyd` side is a clean bounded sub-range
`IPooledStream` over the open zip (`.skyd` is self-contained; `.peaks/.scans/.scores` are
build-time temp only).

## Implementation

### Step 1 (DONE): Upgrade System.Data.SQLite to 1.0.119 tree-wide

Prerequisite (Nick wanted newest since the version does not matter). Binary swap, not a code
port - API stable 1.0.98 -> 1.0.119, zero source changes.

- Skyline core: `libraries/SQLite/{x64,x86}` managed 1.0.98 (IL-mangled) -> real 1.0.119,
  `vendor_api/ABI/{x64,x86}/SQLite.Interop.dll` (gitignored, out-of-band) -> 1.0.119,
  `app.config` DbProviderFactories 1.0.98.0 -> 1.0.119.0 plus a new System.Data.SQLite
  binding redirect.
- Osprey.IO + Osprey.Test: `System.Data.SQLite.Core` PackageReference 1.0.118 -> 1.0.119.
- ResourcesOrganizer devtool: committed lib/sqlite netstandard2.1 managed + all four native
  interops (win-x64/x86, linux-x64, osx-x64) -> 1.0.119.
- Skipped (Nick): legacy Bumbershoot tools (IDPicker/ScanRanker/BumberDash) - binaries not
  present in checkout, 30+ version jump, separate products.
- Left dormant: `vendor_api/ABI/{x64,x86}/SQLite_v1.0.98/System.Data.SQLite.dll` (tracked but
  unused; Jamfile refs commented out) - deletion candidate.
- Bonus: 1.0.119's cleaner URI/VFS handling should dissolve the 1.0.98 open_v2 routing wrinkle.

### Step 2 (TODO): Read side

- `.skyd`: substitute a bounded sub-range seekable `IPooledStream` in `ChromatogramCache.Load`;
  also redirect the direct `new FileStream(CachePath...)` in `ReadDataForAll` (~line 1969).
- `.blib`: open through the custom VFS (route System.Data.SQLite through `open_v2` with the
  vfs name; connection/VFS must stay valid for the whole doc session - persistent connection,
  lazy `ReadSpectrum`).
- Detect whether `.skyd`/`.blib` entries are stored uncompressed (parse local file headers for
  the stored byte range - DotNetZip has no public data-offset). If so, `OpenSharedFile` loads
  directly from the zip; read `.sky` XML via a ZipStream.

### Step 3 (TODO): Write side

- `SrmDocumentSharing` / `ZipFileShare.AddFile`: store `.blib` and `.skyd` with
  `CompressionMethod.None` so shared documents can be opened without extraction.

## Tests

- SQLite upgrade validated: full solution builds; `TestTableExists` (direct
  `SqliteOperations.OpenConnection` path), `DocLoadLibrary`, `TestConnectionPoolReportAndTracking`
  pass with matched 1.0.119 managed+interop in bin; Osprey and ResourcesOrganizer build clean.
- Feature tests: TBD.

## Status

- [x] Feasibility proven (SQLite-from-zip VFS PoC)
- [x] Step 1: SQLite 1.0.119 upgrade - implementation complete, builds clean, tests pass
- [ ] Step 2: read side
- [ ] Step 3: write side
- [ ] PR created
