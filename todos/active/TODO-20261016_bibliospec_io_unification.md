# TODO-20261016_bibliospec_io_unification.md

## Branch Information
- **Branch**: `Skyline/work/20261016_bibliospec_io_reader` (PR A). Each later PR gets its own
  `Skyline/work/YYYYMMDD_...` branch off `master`.
- **Base**: `master`
- **Created**: 2026-10-16
- **Status**: PR A in progress (Brendan, 2026-10-16: this sprint, ahead of the Osprey-Carafe PR 4)
- **GitHub Issue**: (none)
- **Module**: `pwiz` (BiblioSpec and the shared BiblioSpec.IO; the Skyline PRs take `skyline`)
- **PR**: PR A https://github.com/ProteoWizard/pwiz/pull/4860 (open 2026-10-16; the TeamCity
  Osprey Perf/Regression on `pull/4860` is still to be triggered, with Brendan's go-ahead)

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

### 2026-10-16 (evening) - PR A coded, unit gates green
Branch `Skyline/work/20261016_bibliospec_io_reader` off master at 9c3712129e.

**BiblioSpec.IO** (`pwiz_tools/Shared/BiblioSpec/BiblioSpec.IO`):
- `BlibReader` (new): `Info` (LibInfo), `HasTable`, `CountSpectra`, the small tables whole
  (`ReadSourceFiles`, `ReadScoreTypes`, `ReadMetadata`, `ReadDecoyPairs`, `ReadProteins` as an
  `ILookup` by RefSpectra id), streaming `ReadSpectra(withPeaks, partitionCount, partitionIndex)`
  and `ReadRetentionTimes(...)` with Nick's `id % N = k` partitioning, and by id `ReadPeaks`,
  `ReadModifications`, `ReadAnnotations`. Two constructors: a path (own read-only connection) or
  a caller's `SQLiteConnection` (Skyline's pool later). Column detection through
  `PRAGMA table_info`, so a legacy library reads with the record defaults for what it lacks.
- `BlibLibraryRecords` (new): `BlibLibraryInfo`, `BlibSourceFile`, `BlibRetentionTimeRecord`,
  `BlibDecoyPair` (moved here from Osprey, `Method` added), `BlibPeaks`.
- `BlibSqlite` (new, internal): `OpenReadOnly`, `TableExists`, `ColumnNames`; BlibWriter and
  BlibMetadata use it too.
- `BlibSpectrumRecord.Id`; `BlibWriter.DecodeBlob` refuses a blob that inflates to the wrong
  length; `DecodeIntensities` accepts eight bytes per peak (float64, the Rust reader's leniency).
- Tests: `BiblioSpec.Tests/BlibReaderTests.cs` (writer round trip through every call; a
  hand-made schema-0 library with missing tables and columns and float64 intensities).

**Osprey**: `BlibLoader` reads through `BlibReader.ReadSpectra(true)` / `ReadProteins`; its own
inflate (`TryZlibDecompress`, `DecodeBlibPeaks`, `DecompressPeakBlobs`) is gone, `ToFragments`
keeps the base-peak scaling. `BlibDecoyPairs.Read` wraps `BlibReader.ReadDecoyPairs`, keyed by
`long`. `READER_VERSION` unchanged (output must be byte-identical). Two unused resources removed
(en/ja/zh-Hans + Designer).

**CarafeSharp**: `PairingManifestReconciler.ReadBlibSequences` through `ReadSpectra(false)`;
`CarafeSharp.Proteome` references BiblioSpec.IO instead of the SQLite package directly.

**Gates**: BiblioSpec 147/147 (145 + 2 new), Osprey Debug 637/637 + inspection clean,
CarafeSharp 113/113 + inspection clean, Osprey `regression.ps1 -Dataset Stellar` 5 PASS (mode 1
vs golden byte-identical, 285 s across 10 phases), CarafeSharp `regression.ps1 -Leg Chained`
PASSED (`TestResults/regression/stellar-chained-cpu-20261016-181627`, run with `-NoBuild
-OspreyExe D:/test/osprey-runs/_bin/20261016-blibreader/Osprey.exe`, a snapshot of the
regression's own Release build, so the two gates ran concurrently without colliding on the
build tree; pass that path with forward slashes from the Bash tool, which eats backslashes).
Committed as 38b36bdcb1.

**Deferred to PR C** (noted in the reader's docs): the schema 2-5 ion mobility column names in
`RetentionTimes` (`driftTimeMsec`, `ionMobilityValue`, ...) read as null; the annotation's
small-molecule text columns are not on `BlibPeakAnnotation` yet.

**Review** (`/code-review medium`, 10 findings): fixed in cc883ef8bf - the peaks join and
`ReadPeaks` on a library without `RefSpectraPeaks`, table presence cached, a bad partition
refused at the call, compressed float64 intensities, a blob neither raw nor zlib refused as
library data, CarafeSharp's missing-table IOException, a NULL `peptideModSeq` read as unmodified.
Dropped: the removed `numPeaks` inference (the format's contract, trusted by Skyline and the
port too), the 26-column reconciler scan (a one-off step), the compressed-length-equals-8n
ambiguity (no writer of ours keeps a compressed blob larger than raw).

**The blib read path was NOT covered by the Osprey regression**: every regression dataset
searches a TSV library (`carafe_spectral_library.tsv`, the HeLa filtered TSV). Covered instead
by an A/B on the HeLa TSV exported with `--export-library` as a 130 MB blib (242,841
precursors), master build vs branch build, under `D:\test\osprey-runs\blibreader-ab\`
(`_bin\20261016-master`, `_bin\20261016-blibreader`, `_bin\20261016-blibreader-timing`):
the `.libcache` of the two builds is byte-identical (104,733,099 bytes) and the search
`output.blib` identical in every table (compare_blib.py; only the work-dir path in
`LibMetadata.osprey.command` differs).

**Load timings** (Brendan's question: is the blib fast enough to drop the `.libcache`?).
Measured with `--export-library --perf-stats` and the two `[TIMING]` lines added to
`LibraryLoader` in this PR (`Library parse: ...` with the blib's split, `Library cache read: ...`),
logs under `D:\test\osprey-runs\blibreader-ab\time2\`:

| HeLa 242,841 precursors | seconds |
|---|---|
| TSV parse | 6.25 |
| blib parse, total | 3.35 (both builds, 3 s at whole-second resolution) |
| blib: file read + peak decode | 0.80 |
| blib: modification parse + peak typing | 2.43 |
| .libcache read | 0.59 |

Prosit tutorial blib (151,009 precursors, 170 MB): blib 4.30 s = read 1.52 + typing 2.70;
cache 0.65 s. So the SQLite read is already within tenths of the cache; what keeps the blib
from replacing the cache is Osprey's per-spectrum work (FragmentTyping from m/z), which is
pure and per-spectrum and could run on the thread pool while the reader streams, interning
kept in row order for identical output. An Osprey follow-up, not BiblioSpec.IO. The
`.libcache` file is not interned on disk: every entry writes its own strings; the interner
runs at read for the cache, the blib and the TSV alike.

Large local blibs Osprey refuses (peptides under 6 residues): the 557 MB Bereman redundant
library and the 128 MB HeldDIA one under `Perftests`; webinar 27's tutorial data
(`PeakBoundaryImputation-DIA.zip`, downloaded to `Downloads\Tutorials\PeakBoundaryImputation-DIA-download`)
holds only a 28 MB blib; webinar 22's local copy has mzMLs and `PRTC.sky` only.

**Final state**: three commits (38b36bdcb1 reader, cc883ef8bf review fixes, ee2775b9ba timing
lines), every gate re-run green on the final code (BiblioSpec 147, Osprey 637 + inspection,
CarafeSharp 113 + inspection, Stellar 5 PASS, chained PASSED), PR #4860 opened with the
`pwiz` label. Next: Brendan's go-ahead for the TeamCity Osprey Perf/Regression on `pull/4860`;
`/pw-respond 4860` if Copilot reviews; then PR B (the port's `LibReader`). Follow-up idea from
the timings, for an Osprey PR: type spectra on the thread pool while the reader streams them,
or carry typed ions in the blib, so a blib load approaches the cache read. Scratch to clean
when done: `D:\test\osprey-runs\blibreader-ab\` (the A/B runs, spectra caches included) and
the three `_bin` snapshots.
