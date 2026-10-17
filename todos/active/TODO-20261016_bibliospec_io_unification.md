# TODO-20261016_bibliospec_io_unification.md

## Branch Information
- **Branch**: not started. Each PR below gets its own `Skyline/work/YYYYMMDD_...` branch off `master`,
  the first after #4855 merges.
- **Base**: `master`
- **Created**: 2026-10-16
- **Status**: Planned (Brendan, 2026-10-16: next sprint, ahead of the Osprey-Carafe PR 4)
- **GitHub Issue**: (none)
- **Module**: `pwiz` (BiblioSpec and the shared BiblioSpec.IO; the Skyline PRs take `skyline`)
- **PR**: (pending)

## Goal

One set of code in ProteoWizard reads and writes BiblioSpec `.blib` libraries:
`pwiz_tools/Shared/BiblioSpec/BiblioSpec.IO`. The BiblioSpec C# port (Matt's), merged in 2026,
removed the language barrier between BiblioSpec and Skyline for the first time, and the
Osprey-Carafe work left `.blib` code in four places. Writing is mostly done (BlibWriter,
#4852/#4854/#4855); this sprint is the read side, then Skyline.

## Why (Brendan, 2026-10-16)

Decision 8 of `TODO-20261014_osprey_carafe_integration.md` scheduled two BLIB sprints before PR 4:
PR 3c (BlibMaker onto BlibWriter, #4855) and a review of Skyline's BLIB support. After #4855
Brendan chose to keep going on the BiblioSpec cleanup that Osprey and Carafe exposed, now that
BiblioSpec itself is C#, rather than return to PR 4. The Osprey-Carafe TODO stays active; its PR 4
and the #4848 adaptation wait behind this one.

## Inventory (2026-10-16, master at #4855's head 6f3a482650)

### Writers
- **BiblioSpec.IO `BlibWriter`**: Osprey (`OspreyBlibWriter`, `LibraryBlibWriter`), CarafeSharp
  (`BlibLibraryWriter`), and since #4855 the port's `BlibMaker` (BlibBuild, BlibFilter).
- **Skyline `BlibDb`** (NHibernate, `Model/Lib/BlibData`): library export
  (`SpectralLibraryExporter`), minimize (`RefinementSettings`), share-zip (`SrmDocumentSharing`,
  `SkylineFiles`), `CommandLine`, Koina (`KoinaLibraryBuilder`, `KoinaModel`), MIDAS
  (`MidasBlibBuilder`). Its tests compare library bytes.

### Readers (each with its own SQL)
- **Osprey** `Osprey.IO/BlibLoader` (RefSpectra, peaks, proteins; its own raw-first then
  `DeflateStream` inflate), `BlibDecoyPairs` (DecoyPairs). Uses BiblioSpec.IO only for
  `BlibMetadata.Read` (the library contract).
- **Skyline** `Model/Lib/BiblioSpecLite.cs` (`BiblioSpecLiteLibrary`, ~2,570 lines). The load path
  (`ReadFromDatabase`) is plain SQL through Dapper, not NHibernate: `RefSpectra` without blobs and
  `RetentionTimes`, each scanned in parallel partitions (`WHERE id % N = k`), then converted to
  `LibKey`s, small-molecule attributes, crosslinks. Peaks are read lazily per spectrum through a
  pooled connection (`PooledSqliteConnection`, `ConnectionPool`). Nick's #3478 (2025-06) removed
  the `.slc` cache for BLIB once this was fast enough; the `.slc` kept only the index columns.
  Nick also added logging for a `.blib` locking problem (#3624) - connection lifetime matters.
- **The port** `LibReader` (BlibSearch, BlibToMs2), and BlibFilter / BlibBuild reading input
  libraries by `ATTACH` (the SQL transfers in `BlibMaker`).
- **CarafeSharp**, lightly: `PairingManifestReconciler.ReadBlibSequences` (raw SQL on
  `RefSpectra.peptideSeq`), `CarafeStamps` (`BlibMetadata.Read`). In the chained flow its library
  load goes through Osprey's loader.

### BiblioSpec.IO today
`BlibSchema` (one definition), `BlibWriter`, `BlibSpectrumRecord`, `BlibMetadata.Read`, and the
blob codecs on `BlibWriter` (`DecodeBlob`, `DecodeMzs`, `DecodeIntensities`). No spectrum reader.

### NHibernate
Leaving it for BLIB does not remove it from Skyline: iRT (`IrtDb`), ion mobility
(`IonMobilityDb`), optimization (`OptimizationDb`), chromatogram libraries and MIDAS use it too.
Only `BlibDb` depends on the BLIB mappings (`Model/Lib/BlibData/Db*.cs`).

## Design (discussed with Brendan 2026-10-16)

- **`BlibReader` in BiblioSpec.IO**, read-only, the format counterpart of `BlibWriter`. It knows
  the file format and nothing of any tool's domain; callers convert rows to their own types
  (Skyline's `LibKey`, Osprey's `LibraryEntry`).
  - Header and schema detection: `LibInfo`, schema version, which optional tables and columns
    exist, including legacy libraries (today handled separately by Skyline and by
    `BlibMaker.UpdateTables`).
  - Small tables whole: source files, score types, proteins, `LibMetadata`, `DecoyPairs`.
  - Streaming index scans: spectra without peaks, and retention times, with Nick's partitioned
    parallel scan built in as an option.
  - Random access by id: one spectrum's peaks (the existing decoders), annotations, modifications.
- **Rows, not objects**: the reader returns the records the writer takes (`BlibSpectrumRecord`,
  `BlibModification`, `BlibPeakAnnotation`) plus small records for retention times and source
  files, so a column is added in one place for both directions.
- **The caller controls connections**: accept a connection factory (Skyline's pool and its locking
  history), and expose the index scan per partition so the caller drives the threads.
- **No Dapper or NHibernate in BiblioSpec.IO**: ordinal readers, keeping its dependencies at
  System.Data.SQLite, Ionic.Zlib and CommonUtil (Osprey and CarafeSharp run on Linux).
- **A library copier in BiblioSpec.IO**: the port's attach-and-transfer SQL (`TransferSpectra`,
  `TransferSpectrumFiles`, ...) moved out of `BlibMaker`, for BlibFilter and Skyline's minimize,
  export and share-zip.

## PR plan (each gated on its own)

- [ ] **A. Reader, Osprey and CarafeSharp onto it.** `BlibReader` in BiblioSpec.IO; Osprey's
      `BlibLoader` and `BlibDecoyPairs` and CarafeSharp's sequence query read through it. Gate:
      the Osprey regression byte-identical (it compares the written library and the search output),
      the unit gates of Osprey, CarafeSharp and the port. Then measure the `.libcache` question
      from the Osprey-Carafe TODO (what the cache buys over reading the .blib now that a blib
      carries its own pairing and metadata; the composition hash is what a blib-only read must
      still answer).
- [ ] **B. The port's `LibReader` onto it** (BlibSearch, BlibToMs2). Gate: the port's reference
      checks (`.report`, `.lms2`, `.check`).
- [ ] **C. Skyline's read path** (`BiblioSpecLiteLibrary`) onto it, Skyline keeping its domain
      conversion. Gate: Skyline's library tests, plus load time and memory against master on large
      libraries (the property Nick worked for); ask Nick which libraries he measured on.
- [ ] **D. Skyline's write path** off NHibernate: Koina and MIDAS creation onto `BlibWriter`,
      minimize / export / share-zip onto the shared copier, then `BlibDb` and the BLIB `Db*`
      mappings go. Risk: Skyline tests compare library bytes; match `BlibDb`'s output (defaults,
      NULL versus empty, the index set) or update expected files deliberately, one by one.

## Gates and their commands (from the PR 3c work)
- `pwsh -File C:/proj/ai/scripts/BiblioSpec/Build-BiblioSpec.ps1 -SourceRoot C:/proj/pwiz -RunTests`
  (145 tests with vendor support; 128 without - the Mascot cases compile out)
- `pwsh -File C:/proj/ai/scripts/Osprey/Build-Osprey.ps1 -SourceRoot C:/proj/pwiz -Configuration Debug -RunTests -RunInspection`
- `pwsh -File C:/proj/ai/scripts/CarafeSharp/Build-CarafeSharp.ps1 -SourceRoot C:/proj/pwiz -RunTests -RunInspection`
- `pwsh -File ./pwiz_tools/Osprey/regression.ps1 -Dataset Stellar` (background; 5 PASS legs)
- `pwsh -File ./pwiz_tools/CarafeSharp/regression.ps1 -Leg Chained`
- `pwsh -File C:/proj/ai/scripts/Skyline/Build-Skyline.ps1 -SourceRoot C:/proj/pwiz -VendorLicenses -RunTests -TestName LibraryBuildTest`
Run the unit gates one at a time: all build CommonUtil and BiblioSpec.IO.

## Gotchas found 2026-10-16
- **Vendor licenses**: `C:\proj\pwiz` now has the gitignored `Directory.Build.user.props` (from
  `i-agree-to-the-vendor-licenses.bat` at the repo root). Without it BlibBuild compiles the Mascot
  reader out and Skyline's LibraryBuildTest waits out a 720 s timeout on the `.dat` input.
  `Build-Skyline.ps1` looked for the props under the long-gone `pwiz-sharp\` folder until pwiz-ai
  7764607b.
- **Docker parallel runs need a Release build for LibraryBuildTest**: the Debug `MascotShim.dll`
  and `msparserD.dll` link the Visual Studio debug C runtime, which the `always_up_runner` image
  lacks (it has no C runtime at all; a Release build ships the release runtime beside the shim).
  A Debug parallel run fails LibraryBuildTest in every language with "Unable to load DLL
  'MascotShim'". Not filed; fixing it means the shim and msparser using the release runtime in
  Debug too.
- **TestConfigureToolsDlg** fails on Docker workers only: the broken-tool message reads "missing a
  file" where the test expects "has an error in one of its files". Environment difference, not
  investigated.
- **Skyline parallel-testing setup** on this machine: Docker Desktop all-users install with Windows
  containers (wiki `parallelmode` v17, `Troubleshooting_parallel_mode` v18 updated 2026-10-16).

## Progress Log

### 2026-10-16 - Planned
Created at the end of the PR 3c session from the read-side design discussion with Brendan.
Nothing coded. #4855 merged the same day as 9c3712129e (BlibMaker on BlibWriter; one schema), so
PR A can start from master.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20261016_bibliospec_io_reader.md` before starting work.
