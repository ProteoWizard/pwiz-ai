# TODO-20261016_bibliospec_io_unification.md

## Branch Information
- **Branch**: `Skyline/work/20261016_bibliospec_io_reader` (PR A). Each later PR gets its own
  `Skyline/work/YYYYMMDD_...` branch off `master`.
- **Base**: `master`
- **Created**: 2026-10-16
- **Status**: PR A merged 2026-10-18 (#4860); the `.blib`-as-cache PR
  [#4865](https://github.com/ProteoWizard/pwiz/pull/4865) merged 2026-10-18 as 1be16fdafe. PR B
  is [#4866](https://github.com/ProteoWizard/pwiz/pull/4866)
  (`Skyline/work/20261018_bibliospec_libreader`, opened 2026-10-18, all checks green). Nick's
  #4848 and #4823 are being untangled locally (the 2026-10-18 afternoon entry): schema in #4848 off
  master, calculation in #4823, both awaiting Brendan's publishing call. Then C-E, expected to
  move to the backlog
- **GitHub Issue**: (none)
- **Module**: `pwiz` (BiblioSpec and the shared BiblioSpec.IO; the Skyline PRs take `skyline`)
- **PR**: PR A [#4860](https://github.com/ProteoWizard/pwiz/pull/4860) (merged 2026-10-18 as
  5c5f3ae815); the `.blib`-as-cache PR [#4865](https://github.com/ProteoWizard/pwiz/pull/4865)
  (merged 2026-10-18 as 1be16fdafe); PR B [#4866](https://github.com/ProteoWizard/pwiz/pull/4866) (open)

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

- [x] **A. Reader, Osprey and CarafeSharp onto it** (#4860, merged 2026-10-18). `BlibReader` in BiblioSpec.IO; Osprey's
      `BlibLoader` and `BlibDecoyPairs` and CarafeSharp's sequence query read through it. Gate:
      the Osprey regression byte-identical (it compares the written library and the search output),
      the unit gates of Osprey, CarafeSharp and the port. Then measure the `.libcache` question
      from the Osprey-Carafe TODO (what the cache buys over reading the .blib now that a blib
      carries its own pairing and metadata; the composition hash is what a blib-only read must
      still answer).
- [x] **B. The port's `LibReader` onto it** (BlibSearch, BlibToMs2). Gate: the port's reference
      checks (`.report`, `.lms2`, `.check`). [#4866](https://github.com/ProteoWizard/pwiz/pull/4866)
      merged 2026-10-18 as 43c5e5eb8a; see the 2026-10-18 PR B entries.
- [ ] **C. Skyline's read path** (`BiblioSpecLiteLibrary`) onto it, Skyline keeping its domain
      conversion. Gate: Skyline's library tests, plus load time and memory against master on large
      libraries (the property Nick worked for); ask Nick which libraries he measured on.
- [ ] **D. Skyline's write path** off NHibernate: Koina and MIDAS creation onto `BlibWriter`,
      minimize / export / share-zip onto the shared copier, then `BlibDb` and the BLIB `Db*`
      mappings go. Risk: Skyline tests compare library bytes; match `BlibDb`'s output (defaults,
      NULL versus empty, the index set) or update expected files deliberately, one by one.
- [ ] **E. Skyline's other library formats derive a .blib instead of a cache of their own** (after
      D; Brendan, 2026-10-18). `NistLibraryBase` (`.msp` -> `.slc`), `SpectrastLibrary` (`.sptxt`
      -> `.splc`) and `XHunterLibrary` (`.hlf` -> `.slc`) each keep a text parser plus a private
      binary cache writer and reader (~1,300 lines in `NistLibSpec.cs` alone), while
      `BiblioSpecLiteLibrary` dropped its cache in 26.1 once Nick made the .blib load fast enough.
      Each `CreateCache` already walks the text once into spectra with peaks, modifications,
      retention time, copies and a score: feed that walk to `BlibWriter`, load the derived .blib
      through the BiblioSpecLite path, and the three cache formats and their readers go; the
      converted library is a standard file for any tool. Invalidation as Osprey's derived library
      does it (source identity plus converter version in `LibMetadata`, rebuilt on a mismatch). To
      settle first: (1) fidelity - inventory what each `CreateCache` keeps that is not a
      `RefSpectra` column (NIST TF ratio, SpectraST probability versus replicate count, X!Hunter
      expect) and map it to `ScoreTypes` or an optional column, the door #4848 opens; (2) the
      first-open cost - SQLite writes slower than a flat cache (Osprey: 41s vs 2s at 1.57M
      spectra), tens of seconds once for a NIST-sized library, to be stated in the design. Related
      Skyline findings from the 2026-10-18 review of Skyline's typing: `MassListRowReader.
      CalcTransitionExplanations` rebuilds `GetFragmentIonMasses` and `CalcPotentialLosses` per row
      (cache per consecutive precursor), and `TransitionCalc.CompareIonMatch` keeps the first
      candidate on an equal delta while scanning ordinals longest-first, so an isobaric b12^2+ beats
      b6+ when the list gives no product charge (prefer the lower charge, then the shorter ion, as
      Osprey's typing does; pin with an import test).
- [ ] **F. The port free of .blib SQL** (Brendan, 2026-10-18; next after #4848 and #4823 merge,
      ahead of the PeptidePep/Proteins.Pep follow-up). `pwiz_tools/BiblioSpec` is to interact with
      .blib files only through BiblioSpec.IO's classes; SQL stays legitimate for the input formats
      that are themselves databases (`MSFReader` for .msf/.pdResult, `OSWReader`, EncyclopeDIA
      .elib). What remains today is BlibFilter's transfer path in `BlibMaker`: `ATTACH` of the
      redundant library and about 45 `SqlStmt` calls (`INSERT INTO main.<table> ... SELECT ... FROM
      <attached>.<table>` per table, `CreateUpdatedRefSpectraView` for older schemas,
      `TableExists`/`TableColumnExists` by `sqlite_master`/`PRAGMA`, the SpectrumSourceFiles and
      ScoreTypes upkeep, the schema upgrade `ALTER TABLE`s). #4855 moved the build path's row writes
      onto `BlibWriter` but not this cross-schema transfer, and #4848 splices the optional column
      names into three of its statements (`OptionalColumnsCsv`), which go with them. Two shapes:
      (1) code motion, a `BlibTransfer` in BiblioSpec.IO owning the `ATTACH` and the transfer
      statements, taking the schema's column lists; (2) the end state, BlibFilter on `BlibReader` +
      `BlibWriter` with no `ATTACH`: read the redundant library's rows (the filtered scan and by-id
      read from #4866), pick the best spectrum per precursor, write through `AddSpectrum`,
      `AddRetentionTime`, `AddProtein`/`AddSpectrumProtein`. Prefer (2); measure its wall time on a
      large redundant library against the SQL path before committing to it. Gate: the port's
      reference checks (`.check`, `.report`, `.lms2`), `FilterTests`, and a byte comparison of a
      filtered library against master's output; `BlibMaker.SqlStmt` gone or private to schema
      creation is the finish line. A survey of which BlibBuild readers fill the global columns, and
      which formats could, is in the 2026-10-18 progress entry below.

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

**State at the PR's opening**: three commits (38b36bdcb1 reader, cc883ef8bf review fixes,
ee2775b9ba timing lines), every gate green, PR #4860 opened with the `pwiz` label. Follow-up
idea from the timings, for an Osprey PR: type spectra on the thread pool while the reader
streams them, or carry typed ions in the blib, so a blib load approaches the cache read.
Scratch to clean when done: `D:\test\osprey-runs\blibreader-ab\` (the A/B runs, spectra
caches included) and the `_bin` snapshots.

### 2026-10-16 (night) - the sweep: a .tsv library and its .blib must search identically
Brendan: "the results should be identical", and PRs are costly, so fix what the new test
uncovers on this branch. The new test is `regression.ps1 -LibraryAsBlib`: before the legs,
the built Osprey exports each dataset's staged library with `--export-library` (with the
dataset's decoy and manifest arguments, so a library-decoy library carries `DecoyPairs`) and
every leg searches the .blib, with no manifest; mode 1 then holds the .blib search against the
.tsv golden. Opt-in, refused with `-CreateGolden`, `Compare-BlibGolden -LibraryAsBlib` leaves
`SpectrumSourceFiles.idFileName` (the library's own name) out of the comparison. First run on
Stellar: FAIL, 48 issues, every score moved.

Bisected with a `.libcache` differ (`ai/.tmp/sessions/20261016-blibreader/diff_libcache.py`,
format v4, keyed on sequence + charge + modifications) on the two runs' caches. Three
differences between the loaded libraries, and what was done about each:
1. **474 fragment annotations** - all of them 237 isobaric pairs (`b4^2`/`y3^2` of `AQIHQFR` at
   225.6266, `b6^2`/`b3`, `y5^2`/`y2`): Carafe lists two peaks at one m/z with their own
   intensities, the typing hands the first its preferred ion, the library listed them the other
   way. No "Differ" cases at all (the TSV loader's own report, with `FragmentTypeCheck` now
   keeping library-choice examples too). Fixed by option 2 of the three Brendan weighed (sparse
   annotations only where they disagree; typing authoritative, "what Skyline will do anyway";
   a lossy golden of its own): `DiannTsvLoader.ApplyTyping` takes the typing's ion wherever it
   names one, keeping a stated type only where the typing cannot reproduce it (no ion in reach,
   or a loss / a ion / charge above 2). `TestStatedTypesAreComparedWithTyping` updated.
2. **Fragment order** - every entry: .tsv row order (Carafe's: intensity descending) vs the
   .blib's m/z order. Reaches the search through tie-breaks only (`SelectTopFragmentIndices`
   keeps library order on equal intensities and returns a short entry in it; `TypeFragments`
   breaks intensity ties by index), but Carafe prints four decimals, so ties are common. Fixed
   by loading .tsv fragments in m/z order (stable), as the blib stores them, before typing.
   Brendan: in principle agreed - Skyline's `MassListImporter` loads a precursor at a time and
   derives fragment matches once it has all of them, untangling interleaved light/heavy SIL
   fragments in SRM lists the same way; accumulating a precursor's rows costs no significant
   memory. The loader already accumulated per precursor; the sort sits at that point.
3. **Modification text** - `C[UniMod:4]` / name `UniMod:4` from the .tsv vs `C[+57.0215]` /
   `Carbamidomethyl` from the .blib. Inert for these libraries (one modification, nothing sorts
   across the notations; the output text is built from the masses). Left as is; a library with
   several modifications would be the place to revisit (`PerFileScoringTask` and
   `ConsensusRts` order by the text).

   Astral then showed the last asymmetry of that rule: 90 selenocysteine peptides
   (`AEENITESCQUR`), whose fragments the typing cannot name (no residue mass for U, by design
   in `PeptideFragmentMass`), kept their stated `y` labels on the .tsv route and were Unknown
   on the .blib route - 51 issues, every Astral score moved. So the TSV loader now types every
   fragment from m/z exactly as `BlibLoader` does and the columns are a report only; a peak the
   typing cannot name is Unknown on both routes. (A residue mass for U would type them on both
   routes alike - a later improvement, not an asymmetry.) Brendan: add the U mass now, so
   the tools calculating peptide and fragment masses agree; done in `PeptideFragmentMass`
   (150.953636, C3H5NOSe from the table's own atomic masses). **Follow-up (Brendan)**: Osprey
   should compute residue masses from the atomic mass table already in
   `pwiz_tools/Shared/CommonUtil/Chemistry` (`AminoAcidFormulas`, the formulas Skyline
   calculates from, which is what lets it do isotope distributions), rather than keep its own
   six-decimal table; CarafeSharp has its own `AlphabaseMasses` too, and the BiblioSpec port
   its own. Whether the four tools (Skyline, Osprey, Carafe, BiblioSpec) can share one
   sequence mass calculator is on Brendan's list; Skyline's handles every UniMod modification
   and neutral and charged losses and may be too much to extract, but agreement is the
   priority. Precedent (Brendan): Skyline was itself normalized onto the shared chemistry,
   under `BioMassCalc`, to gain Nick's isotope distribution calculator, which he first wrote
   for Topograph and which the two tools then shared - the same move Osprey would make. The
   values Skyline uses: monoisotopic masses and abundances in
   `pwiz.Common.Chemistry.IsotopeAbundances` (CommonUtil), average masses in
   `Skyline.Util.BioMassCalc`. The U entry added here (150.953636) is C3H5NOSe from the
   `IsotopeAbundances` values (150.9536356), so it agrees with Skyline at Osprey's six decimals.
   Measured difference per residue, Osprey's table vs Skyline's calculation
   (`ai/.tmp/sessions/20261016-blibreader/residue_masses.py`; note `IsotopeAbundances.Default`
   uses Skyline's traditional C/H/N/O/P/S values, NIST only for the other elements): Osprey's
   table is exactly Skyline's values rounded to six decimals, every residue within 5e-7 Da
   (largest T and C, 4.95e-7, 0.005 ppm of the residue); ten residues at the bound move a
   1000 Da peptide by 0.005 ppm.
   Then Brendan: "if Osprey is calculating from chemical formulas and atomic masses, why not
   just use the values in IsotopeAbundances" - done: `PeptideFragmentMass` now builds its
   residue masses from `AminoAcidFormulas.Default` (the 20 + U), and `NeutralLoss`'s water,
   ammonia and phosphoric acid come from `Molecule.Parse` summed over `IsotopeAbundances.Default`.
   Every fragment m/z moves by up to 5e-7 Da, so all four goldens are recaptured once more.
   `FragmentLadderTest.AssertResidueMassesAgreeWithCommonChemistry` pins the calculation to the
   values the shared tables give today (C 103.009184505, T 101.047678505, U 150.953635605,
   water 18.0105647, ammonia 17.026549105), so a change to the shared chemistry shows up as a
   deliberate change. **The proton stays 1.007276** (Brendan: maintain consistency with
   Skyline, not something to change tonight): three proton values live in the tree -
   `BioMassCalc.MassProton` 1.007276 (Skyline's peptide and fragment m/z, the BiblioSpec port,
   Osprey), `AminoAcidFormulas.ProtonMass` 1.00727649 (CommonUtil's isotope distributions; the
   commented-out line in `BioMassCalc` shows Skyline was meant to adopt it and never did),
   alphabase's 1.007276467 in CarafeSharp, with NIST's 1.007276466879 in a comment. Unifying
   them is a separate sprint.
   CarafeSharp keeps its `AlphabaseMasses` (its Carafe-parity gates compare against Carafe's
   Java output); the BiblioSpec port keeps its own; those are the remaining two of the four.
   **Where the four tools stand** (monoisotopic element masses; residues are formulas over them):
   - Skyline and now Osprey: `IsotopeAbundances.Default` - the traditional values for C, H, N,
     O, P, S (H 1.007825035, N 14.003074, O 15.99491463, S 31.9720707), NIST for the rest
     (Se 79.9165218); proton `AminoAcidFormulas.ProtonMass` 1.00727649.
   - CarafeSharp (`AlphabaseMasses`, alphabase's table = current NIST): H 1.00782503223,
     N 14.00307400443, O 15.99491461957, S 31.9720711744, Se 79.9165218; proton 1.007276467.
     Against Skyline: a few 1e-8 per residue, 4.7e-7 (0.005 ppm) through sulfur for C and M,
     proton 2.3e-8. Cannot switch without Carafe (Java) switching, or a 1e-7-level parity
     tolerance.
   - BiblioSpec port (`AminoAcidMasses`, the C++ values, kept for the reference checks):
     H 1.00782503521, N 14.0030740052, O 15.9949146221, S 31.97207069, P 30.97376151; proton
     1.007276. Against Skyline: residues within about 1e-8, proton 4.9e-7.
   Brendan, on Skyline's traditional values: disappointing that Skyline may have fallen behind
   the standard values. The hold looks deliberate (`traditional_Skyline_CHONPS`, with the
   `ParseIsotopeAbundancesFromNIST` tool beside it), and the gap is thousandths of a ppm. The
   way to unify three of the four: move Skyline's C, H, N, O, P, S to NIST (a test-expectation
   sweep); Osprey follows automatically now that it computes from the shared table, and
   CarafeSharp's alphabase table is NIST already. Only the BiblioSpec port's C++ values would
   remain.

After 1 and 2 the .blib search equals the .tsv search in every table. **The goldens move**,
and by more than the changes suggest: Stellar precursors at 1% FDR went 31,720 (old) ->
31,253 (typing only) -> 30,534 (typing + m/z order). An experiment with m/z DESCENDING order
gave 31,175, so the count swings about 2% with nothing but the order ties are broken in: a
tie-break noise band in the pipeline's identification count, not m/z order being worse.
Worth its own follow-up (order-independent tie-breaks in the top-6 selection and the typing,
or a look at why the FDR estimate is that sensitive); not this PR. Goldens recaptured with
`-CreateGolden` on the final code (shared-chemistry residue masses, proton 1.007276), each
then checked with `-LibraryAsBlib`: Stellar 31,720 -> 32,110 (PASS), StellarLibDecoy 31,392
-> 31,015 (PASS; library decoys, so the mass change touched nothing), StellarGenDecoyEntrap
31,750 -> 31,909 (PASS), Astral 117,236 -> 118,271 (check running at the time of writing).
Stellar's count over the night's loader variants: 31,720 (old), 31,253 (typing only), 30,534
(typing + m/z order), 31,175 (m/z descending), 30,840 (shared masses, proton 1.00727649),
32,110 (shared masses, proton 1.007276) - the tie-break noise band, about +/-2%.

**Second `/code-review medium`** (after the sweep, 10 findings). Fixed: both readers'
`READER_VERSION` bumped (TSV 2 -> 3, blib "2" -> "3") and the TSV `.libcache` term keyed on the
fragment tolerance like the blib's (`DiannTsvLoader.CacheTerm`), so caches typed under the old
rules or masses are re-read; a `.tsv` with no fragment type column is typed from m/z like any
other (the early return typed nothing); `ReadDecoyPairs` reads a table without `Method`;
`FragmentTypeCheck` keeps library-choice examples in their own list so `--verbose` still shows
the peaks that disagree; `BlibLoader`'s cysteine constant comes from `PeptideFragmentMass`.
Dropped: the TSV task validity key carrying no reader term (the daily version stamp already
refuses a resumed stage from another build, and a bare `tsv_reader` term in the task key is a
design question for the morning); the removed `numPeaks` inference (as before); the
`RetentionTimes` range assertion in the subset tests (an exact count would pin data noise); the
26-column reconciler scan (as before).

**Brendan on the isobaric pairs (2026-10-17, morning)**: a mass spectrometer cannot say which
of two isobaric fragments contributed how much to one peak (CPTAC's "auto-interference" with
light/heavy pairs; ion-trap vs triple-quad secondary fragmentation, PMC3227787). The true
representation is ONE peak with the summed intensity and BOTH annotations, as Skyline's spectrum
annotation and `RefSpectraPeakAnnotations` (several rows per peak index) already allow. What the
sweep did instead: kept Carafe's two peaks at one m/z and assigned them two ions consistently on
both routes. Consequences left in place: two identical XICs at one m/z (two top-6 slots, double
weight in coelution features) and a decoy with two fragments at two m/z carrying Carafe's split
intensities. **First follow-up PR, ahead of the DecoyPairs group id**: at library load on both
routes merge fragments within the typing's 1e-5 Th into one peak with summed intensity and the
set of ions in reach; `FragmentAnnotation` on a fragment becomes a small list (libcache version
bump); the decoy generator makes one decoy fragment per annotation (decide: full summed intensity
or a share); the export writes the summed peak once with its annotations in
`RefSpectraPeakAnnotations` for multi-annotated peaks only (the sparse form of option 1, now the
right use of the table). Goldens move again (237 HeLa pairs and Astral's).

**Decision (Brendan, 2026-10-17 morning, TeamCity build 4223785 green)**: #4860 stays open as
the checkpoint and takes two more changes before merge, because both move all four goldens
and a PR's golden diff is net: (1) **summed isobaric peaks with both annotations** (above);
(2) **order-independent tie-breaks** in `SelectTopFragmentIndices` and `TypeFragments` (ties on
intensity broken by m/z, not by input index), so the identification count no longer depends on
a library's row order. Then one Perf/Regression run and merge. The `DecoyPairs` group id is the
NEXT PR (the format is the plan of record on master but incomplete; the gap is tolerable while
the manifest stays on the legs). The mass sprint (Skyline to NIST, proton onto the shared
constant) is NOT this sprint: Skyline has shipped to thousands of users for 15 years and its
proton cannot change lightly, which is why it is still 1.007276 while the code carries more
precise values.

Design notes for (1): merge at library load on both routes (`DiannTsvLoader` after the m/z
sort, `BlibLoader.ToFragments`) - fragments within `FragmentTyping.TIE_TOLERANCE` (1e-5 Th)
become one fragment with the summed intensity; typing lets ONE peak claim EVERY primary ion in
reach rather than one; `FragmentAnnotation` on a `LibraryFragment` becomes a small list (or a
primary plus `Also`); libcache `VERSION` 4 -> 5 and both `READER_VERSION`s bump;
`DecoyGenerator.RecalculateFragments` emits one decoy fragment per annotation (decide the
intensity: full sum each, or divided - Brendan's physics says the measurement is one summed
peak, so a decoy that is a "measurement" of the reversed sequence would show the sum at each
ion's m/z; discuss); `BlibSpectrum`/export writes the merged peak once and
`RefSpectraPeakAnnotations` rows only for peaks with more than one ion (the sparse form);
`BlibLoader` reads those rows back when present (they are Osprey's own). Then `-CreateGolden`
on all four, `-LibraryAsBlib` on all four, gates, TeamCity.

**Completion criterion (Brendan, 2026-10-17)**: every requirement for a normal merge is met
(build 4223785 green), but the PR is NOT merged, because it moved goldens, the two changes
above move them again, and there is no paired `maccoss/osprey` change yet. #4860 completes
only together with a **paired maccoss/osprey PR that passes the cross-impl test**
(`ai/scripts/Osprey/Compare/Compare-EndToEnd-Crossimpl.ps1`, Stellar + Astral; tolerance in
`Compare/README.md`; build with `Compare/Build-OspreyRust.ps1 -Fmt -Clippy -RunTests`). Rust
side to port, in `C:\proj\osprey` (upstream conventions: LF, cargo fmt + clippy, no Skyline
commit format; Rust TODOs are `TODO-OR-*.md`): fragments in m/z order at load; typing from m/z
authoritative over the TSV's labels (FragmentType/Number/Charge a report); residue masses equal
to the C# values (Skyline's traditional C/H/N/O/S, NIST Se, U = 150.9536356050, proton 1.007276,
water 18.0105647, ammonia 17.026549105) - the Rust table is the six-decimal one, so this is a
1e-7-level change there too; then the two new rules (order-independent tie-breaks; summed
isobaric peaks with every ion in reach, one decoy fragment per annotation at the full sum).
The next session carries #4860 to that end: C# changes -> goldens -> Rust port -> cross-impl
green -> TeamCity on `pull/4860` -> both PRs merged with Brendan's approval.

**End of session (2026-10-17 ~01:30)**: five commits pushed, last 097b7b63a9; TeamCity Osprey
Perf/Regression build 4223785 queued on `pull/4860` behind four Skyline perf builds (Brendan's
go-ahead given; do not re-trigger without asking). Merge pending his review and approval.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20261016_bibliospec_io_reader_morning.md` before starting work.

**What the .blib still cannot carry**: on StellarLibDecoy the .blib search matched the golden
in every leg but mode 1b, the model diagnostics' paired entrapment FDP (0.00721 vs 0.00809).
That statistic pairs each entrapment peptide with its original target, which the FDRBench
manifest describes (`peptide_pair_index` groups target, p_target, decoy, p_decoy) and
`DecoyPairs` does not (its `PairID` joins a target with its decoy only). So the switch keeps
the manifest on the .blib legs - the loader ignores it for pairing when the library has the
table, the diagnostics still read it. For a .blib to replace a .tsv plus manifest outright,
`DecoyPairs` would need the entrapment partner too (a fourth-row group id, or a column naming
the original target): a schema and CarafeSharp writer change, for a later PR.

### 2026-10-17 (morning) - one peak per m/z, order-independent tie-breaks
Brendan on where the isobaric-pair work should stop: two peaks at one m/z are a scoring
error as much as a representation one - two XICs at one m/z scored as independent evidence
of the precursor is counting one measurement twice - but a multi-annotation representation
(`RefSpectraPeakAnnotations` rows, an annotation list on a fragment, per-annotation decoy
fragments) is a qualitative change to a table Skyline uses only for small molecules, made to
improve gendecoy, our less reliable decoy mechanism, which can do less and still match the
field. And the merge rule is EQUALITY, not a tolerance: the .tsv is a spectrometer of unknown
resolution, two rows at different m/z, however close, are what it states, and whether they
extract one XIC is the extraction's question at its own tolerance. What no instrument can
produce is two peaks at ONE m/z, and that is what is not carried forward from Carafe. Other
formats merge such a pair to one intensity and let the reader credit one source, as Skyline
picks the most likely ion for a peak.

**Data behind the decision** (`ai/.tmp/sessions/20261017-isobaric/isobaric_pairs.py`,
`exact_vs_near.py`; outputs beside them). Across the whole libraries: Stellar 2,419 groups of
rows at one m/z (2,023 b/b - `b4^2` at `b2` for a peptide whose first four residues repeat a
composition, Carafe giving the doubly charged one 0.01-0.04 - 277 b/y, 117 y/y), Astral 1,695
(975 b/y), libdecoy 2,340. Every group is an EXACT duplicate of the written m/z text; zero
groups with distinct text within 1e-5 Th, so equality and the typing's tie tolerance pick the
same rows here. Carafe's split is lopsided (high/low median 3.3-4.3, upper quartile 8-10); for
b/y pairs the y ion holds a median 0.52-0.66 of the sum and is the larger in 57-68%. Carafe's
own decoys (libdecoy, paired through the manifest, 534 pairs with both ions on the decoy at
separate m/z) keep each ion's share: decoy ion / target same ion median 0.96 (IQR 0.46-2.00),
decoy sum / target sum median 0.98. Full sum on both decoy ions would put ~17x Carafe's value
on the minor one (`AQIHQFR` b4 0.064 / y3 0.524 -> Carafe decoy 0.035 / 0.498). Under the
rule adopted, the merged peak is typed once (the preferred ion, which is the major one nearly
every time: `b2` over `b4^2`, y over b) and the decoy gets that one fragment at the sum; the
minor ion has no decoy fragment.

**Code** (uncommitted at the time of writing, Osprey Debug gate 638/638 + inspection clean):
- `FragmentPeaks.MergeEqualMz` (new, Osprey.Core): peaks in m/z order sharing one m/z become
  one peak with the summed intensity (first annotation kept), then the spectrum is scaled to
  its base peak. Called by `DiannTsvLoader` after the m/z sort and by `BlibLoader.ToFragments`
  (which now also sorts by m/z, for a .blib written in another order) - both before typing.
  Both `READER_VERSION`s bumped (TSV 3 -> 4, blib "3" -> "4"); no libcache format change.
- Order-independent tie-breaks: `TopFragmentExtractor.SelectTopFragmentIndices` breaks equal
  intensities by m/z, then ion type, ordinal, charge; `FragmentTyping.TypeFragments` by m/z
  then index. Neither depends on a library's row order any more.
- Tests: `FragmentTypingTest.TestOnePeakPerMz` (helper, .tsv route, .blib route),
  `FragmentSelectionTest` tie case; `BlibLibraryInputTest` fixture put in m/z order;
  `SubsetPipelineTest` counts distinct (peptide, charge, m/z) where it counted lines.
- Export unchanged: the merged peak is written once; `RefSpectraPeakAnnotations` untouched.

**Golden sweep** launched 08:25 (`ai/.tmp/sessions/20261017-isobaric/run-golden-sweep.ps1`,
log `golden-sweep.log`): per dataset `-CreateGolden` then `-LibraryAsBlib`, serial.

**Rust side**: no maccoss/osprey checkout exists on this machine (nothing at `C:\proj\osprey`
or elsewhere on C:/D:); the paired PR needs a clone first.

**Later the same morning (C# follow-through)**: `FragmentMath.GetTop6FragmentMzs` (the spectrum
prefilter's memoized top six) ranked by intensity with its own stable sort, so it needed the
same tie-break as the extraction; both now go through `FragmentMath.TopIndicesByIntensity`
(Osprey.Core), the one ranking every top-N selection uses. Gate green again (638/638,
inspection clean). The first golden sweep was launched before that change and could not be
stopped (the permission classifier refused the kill), so its numbers are indicative and the
definitive sweep runs after it: Stellar 32,110 -> 32,082 (-0.09%, `-LibraryAsBlib` PASS),
StellarLibDecoy 31,015 -> 31,076 (+0.2%, PASS), StellarGenDecoyEntrap 31,909 -> 32,287
(+1.2%).

**Rust port (paired maccoss/osprey PR)**, in `C:\proj\osprey` (cloned this morning at
d19be4c; rustup via winget, vcpkg at `C:\vcpkg` with openblas/openssl, per
new-machine-setup.md), branch `fix/one-peak-per-mz-typed-from-mz`:
- New `osprey-core/src/fragment_typing.rs`: residue masses as the C# computes them (exact
  round-trip doubles from `pwiz.CommonUtil`, dumped by `ai/.tmp/sessions/20261017-isobaric/
  dump-masses.ps1` -> `masses.txt`), water/ammonia/phosphoric acid, proton 1.007276;
  `calculate_fragment_mz` in the C# summation order; the ladder, `FragmentCandidates`,
  `type_fragments`, `merge_equal_mz`, `prepare_library_fragments`/`prepare_library`,
  `top_fragment_indices` (the tie-break), .NET-style NaN comparators.
- `load_library(source, cache_dir, fragment_tolerance)` prepares every entry after a fresh
  parse; the `.libcache` is VERSION 2 and records the tolerance (a cache typed within another
  tolerance is not used). `pipeline.rs` passes `config.fragment_tolerance`.
- `DecoyGenerator` lost its six-decimal table: residue masses, the fragment m/z calculation
  and the collision ladder's constants come from core. `NeutralLoss::mass` too.
- The five top-N sites in `osprey-scoring` (`has_any_top_fragment_match`,
  `has_topn_fragment_match`, `get_top_n_fragment_indices`, the top-6 mass-error count,
  `extract_fragment_xics`) call `top_fragment_indices`.
- Gate: `Build-OspreyRust.ps1 -FmtFix -Clippy -RunTests` green (two test expectations
  updated: U has a mass now, so the ladder test's unknown residue is X).
- Cross-impl (`Compare-EndToEnd-Crossimpl.ps1`) still to run: Stellar `-Files Single` first,
  then Stellar and Astral `-Files All`, after the definitive C# sweep (the script runs the C#
  Release exe from the build tree, the same one the sweep locks).

**Tighter loop (Brendan, late morning)**: a seconds-long exact check in place of the 40-minute
sweep - `SubsetPipelineTest.TestLibraryLoadsIdenticallyFromTsvAndBlib`
(`SubsetPipelineTest.LibraryRoundTrip.cs`): the subset .tsv loaded by `DiannTsvLoader`,
written by `LibraryBlibWriter`, read back by `BlibLoader`, and the two entry lists compared
field by field (id, sequence, modified sequence, charge, precursor m/z, RT, decoy flag, every
modification's position/mass/UniMod id/name, every fragment's m/z, intensity and annotation,
proteins, genes), reporting a count per field and the first forty lines. Stellar (unit 0.5) and
Astral (10 ppm) subsets. First run: 485 differences, three families, all fixed so the round
trip is exact:
- **Id**: the TSV loader numbers from 0, the blib loader used the 1-based RefSpectra id. The
  blib loader now numbers from 0 in reading order and keeps `BlibLoader.RefSpectraIds` beside
  the entries for the tables that refer to the file's id (protein mappings, `DecoyPairs`:
  `BlibDecoyPairs.ByEntry` and `LibraryLoader.CheckLibraryContract` take the list).
- **ModifiedSequence text**: `C[UniMod:4]` (TSV) vs `C[+57.0215]` (blib). Both loaders now
  rebuild the text from the modification masses with `BlibSpectrum.FormatModifiedSequence`,
  the blib writer's own text, so the precision a file printed does not matter either. The
  text reaches no compared output (the `-LibraryAsBlib` legs passed with the two texts
  differing), so the goldens do not move for it.
- **Modification.Name**: `UniMod:4` (TSV) vs `Carbamidomethyl` (blib): the TSV loader names a
  modification by its UniMod entry when the id is known.
- **Untyped peak placeholder**: the blib route's `Unknown` carried ordinal i+1 / charge 1, the
  TSV route's 0/0; both are the bare `Unknown` now (pinned in `TestOnePeakPerMz`; the subset
  libraries have no untyped peak to show it).
`PrecursorData.ModifiedSequence` (TSV loader) is gone, unused. Gate: 639/639, inspection clean.
Residual the round trip cannot close: an entry with two modifications on one residue (an
N-terminal acetyl and an oxidized first methionine) is two `Modification` records from a .tsv
and one summed record from a .blib; the text, masses and fragments agree, the record count does
not. None of the regression libraries has one.

Definitive sweep launched after the gate (log `golden-sweep-2.log`); the indicative sweep had
finished with every leg PASS on all four datasets.

**`/code-review medium` on the C# diff** (8 findings). Fixed: the task validity key carried
only the blib reader term, so a TSV work directory scored under reader 3 would be adopted by a
reader-4 search - `OspreyTask.TSV_READER_TERM` (`;tsvreader=4`) now keys TSV searches as
`BLIB_READER_TERM` keys blib ones (`TaskValidityKeyTest` updated); a mass-bracket modification
in a .tsv (`C[+57.021464]`, DIA-NN's notation) was not identified where the blib loader
identifies the same text - `DiannTsvLoader.AddModification` now matches a numeric bracket by
residue at the printed precision (`UniMod.Match`), as `BlibLoader.IdentifyModification` does;
`BlibDecoyPairs.ByEntry` and `LibraryLoader.CheckLibraryContract` refuse entry/id lists of
different lengths; the blib writer's unresolved-text guard counts modified residues rather
than modification records (two records on one residue are one bracket); `BlibLoader.ToFragments`
sorts only when a .blib is not already in m/z order; the tie-break comment points at the Rust
twin. Dropped: the type-check report's choice between two stated labels at one m/z is
row-order dependent (said in the comment; the typing is not); `PeaklessPrecursorException`
reporting the 0-based id for a blib (TSV ids were never file rows either; the message carries
the sequence).

**A real defect the round trip then exposed**, through the mass-notation case added for the
review fix: `DiannTsvLoader.StripFlankingChars` took the text between the FIRST and LAST dot
as the `K.PEPTIDE.R` flanking notation, so `_KDC[+57.021464]PWPC[+57.021464]PK_` was cut to
`021464]PWPC[+57` - one `+57` on the wrong residue, matched to Carbamidomethyl at precision 0.
Every mass-notation library with two or more modified residues on a peptide loaded wrong
(Carafe's UniMod notation has no dots, so the regression libraries never showed it). Flanks are
now one residue and a dot at each end, nothing else; pinned in the round-trip test. The Rust
loader's `strip_flanking_chars` had the identical rule and fix
(`test_strip_flanking_chars_leaves_mass_brackets_whole`). Gates: C# 639/639 + inspection
clean; Rust fmt/clippy/tests green.

Cross-impl so far: Stellar `-Files Single` and `-Files All` OVERALL PASS at 1e-9 (on the
pre-review binary); Astral refused by the stale-binary guard (source edited after the Release
build) and reruns on the final build with the final sweep.

**Committed (local, pushes after the final gates)**: pwiz 29c194f35c on
`Skyline/work/20261016_bibliospec_io_reader` (16 source files + the four goldens); maccoss/osprey
2d72cc4 on `fix/one-peak-per-mz-typed-from-mz` (8 files; PR to open with
`gh pr create --repo maccoss/osprey`, body `ai/.tmp/sessions/20261017-isobaric/pr-body-rust.md`).
Definitive sweep (`golden-sweep-2.log`): 49 legs PASS, 0 FAIL; counts Stellar 32,082,
StellarLibDecoy 31,076, StellarGenDecoyEntrap 32,287, Astral 118,314 (the indicative run's
Astral 118,456 predates the prefilter tie-break, which that dataset felt). Final gates on the
final Release build running (`run-final-gates.ps1` -> `final-gates.log`): `regression-parallel
-Dataset All`, then `Compare-EndToEnd-Crossimpl.ps1 -Dataset Astral -Files All`. The #4860
description update is built (`pr-body-new.md`, from `merge_pr_body.py`). Then: push both,
open the Rust PR, `gh pr edit 4860 --body-file`, ask Brendan for the TeamCity go-ahead.

**Pushed (2026-10-17 ~11:40)**: pwiz 29c194f35c on #4860; maccoss/osprey 2d72cc4 as
**https://github.com/maccoss/osprey/pull/73** (branch `fix/one-peak-per-mz-typed-from-mz`).
Final gates on the final Release build: `regression-parallel -Dataset All` PASSED (every mode,
all four datasets); cross-impl Stellar single and all-files and Astral all-files OVERALL PASS at
1e-9 (Rust and C# both 118,314 Astral precursors; `crossimpl-astral.log`). #4860 retitled
"pwiz: Added BlibReader to BiblioSpec.IO and made a .blib structurally equivalent to Osprey's
library cache" (Brendan's framing: everything the .libcache holds, the .blib holds or
re-derives exactly, a replacement for it if made fast enough) and the description carries the
new section. TeamCity NOT triggered: Brendan wants the `DecoyPairs` extension in this PR first
(the manifest's 4-row group in the .blib, so a .blib alone reproduces the manifest pairing and
the `-LibraryAsBlib` legs drop the manifest). **Speed is a separate PR** (Brendan): the blib is
not yet fast enough to replace the cache (3.35 s vs 0.59 s on HeLa; typing is 2.43 s of it).
Code mapping for the `DecoyPairs` design was delegated to an Explore agent at the time of
writing; the design is to be proposed before coding.

### 2026-10-17 (afternoon) - DecoyPairs as the whole pairing design
Brendan's reframing of #4860: **a .blib structurally equivalent to Osprey's .libcache**, a
replacement for it if made fast enough (speed is a separate PR: 3.35 s blib parse vs 0.59 s
cache read on HeLa). The remaining asymmetry was `DecoyPairs`, which paired a decoy with its
target but not an entrapment peptide with its original target (the manifest's 4-row group), so
a .blib still travelled with the manifest. No backward compatibility (the table was merged days
ago and no important library carries it). Schema settled with Brendan - `PairingID` (his name:
it identifies a group of four, "PairID"/"PairIndex" read as one pair), `TargetRefSpectraID` as
an indexed foreign key, `IsDecoy`/`IsEntrapment` kept (SQLite stores 0/1 in zero payload
bytes; a `Kind` column would be the same bytes), `Method` per row because Osprey's generator
mixes reverse and cycle within one library, and `entrapment_method` for LibMetadata (a
per-library fact; not yet written). Measured first: zero library peptides outside the manifest
on the libdecoy library (359,296 target-side sequences), so the Met-clip reconciliation never
fires on our data; it moved to load time unchanged.

Implemented (see handoff `ai/.tmp/handoff-20261017_bibliospec_io_reader_pairing.md` for the
file-by-file list): BiblioSpec.IO schema/record/writer/reader + tests; CarafeSharp row, planner
(the manifest index it already grouped by, the target id it already zipped), writer, tests;
Osprey `LibraryEntry.PairingId` (uint?, manifest indices start at 0), libcache v5,
`PairingIds.Assign` at load on both routes, `EntrapmentPairing.Build` from entries, the three
consumers off the manifest file, `BlibDecoyPairs.Pair` by target id, export rows for every
entry in a pairing, contract rule 6 link-based, `-LibraryAsBlib` legs manifest-free, docs
01/13/24. Gates: BiblioSpec 147, CarafeSharp 113, Osprey 639 + inspection (last log
`osprey-gate-15.log`). Not yet: the loader-level round trip on the libdecoy subset, the
Carafe-built-.blib -> Osprey test (Brendan: "a primary goal of this work is to make BLIB the
primary communication format between Carafe and Osprey"; the Carafe subset .blib is built, see
the handoff), `entrapment_method`, the libdecoy/entrapment regressions on manifest-free .blib
legs, review, PR text, TeamCity. Handed off at 10% context (measured).

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20261017_bibliospec_io_reader_pairing.md` before starting work.

### 2026-10-17 (evening) - every entry a pairing id; the .blib legs manifest-free end to end
Brendan's end-of-afternoon rule implemented: `LibraryEntry.PairingId` is a `uint` every entry
has (libcache v6), `PairingIds.Assign` is the one assigner (a .blib's DecoyPairs rows, then
the manifest, then Met-clip reconstruction, then a standalone index), and "excluded" is a
property of the group - `PairingIds.ExcludedEntrapment`: an entrapment peptide whose id no
original target shares, in a library that pairs entrapment at all (a .tsv with no manifest
pairs nothing and excludes nothing, which keeps `EntrapmentPairingTest`'s no-manifest block
as it was; the reviewer flagged that guard as a heuristic - see "Decisions for Brendan").

Three defects in the afternoon's commit, all fixed: (1) the .blib route ran `Assign` with no
manifest AFTER the table set the ids and overwrote every one with a standalone index; (2) the
generated-decoy route read neither the manifest nor the table, so an entrapment library with
generated decoys had no pairing; (3) the export wrote no DecoyPairs for a decoy-less entrapment
library (the StripDecoys dataset). Now the table is read on every .blib load that has one, the
manifest once per load (for a .tsv only; a .blib with a table logs that the manifest is not
read), `Assign` runs once after the decoys are finished, and the export writes a row per entry
of a decoy or entrapment library. One decoy-side test (`EntrapmentLibraryClassifier.IsDecoySide
(entry)`: flag or accessions) now serves `Build`, `PairingIds`, the FDRBench manifest writer
and the diagnostics - a generated decoy is flagged but carries `DECOY_`, not `decoy_`.

Tests: the library-decoy subset through `LibraryLoader.Load` (.tsv + manifest vs its .blib
alone, pairing ids and `EntrapmentPairing.Build` compared) in
`TestLibraryLoadsIdenticallyFromTsvAndBlib` - a mutation restoring defect (1) fails it with
2,142 differences; `CarafeBlibLibraryTest` with `Osprey.Test/TestData/CarafeSubset.zip` (the
CarafeSharp subset regression's .blib, 1,896 precursors with a DecoyPairs row each, plus the
manifest it was built from): the Carafe .blib loaded alone gives every entry the manifest's
pairing id, pairs every decoy, and `Build` equals the manifest. `/code-review medium`: 8
findings; fixed 2, 4, 5, 7, 8 (one manifest decision, shared decoy-side test, Met-clip
classification only from the manifest when there is one, explicit ids in the writer test);
dropped 3 (reading DecoyPairs on every .blib load is the point) and 6 (ApplyToLibrary stays
the supplied-decoy route's; doc reworded); 1 is a decision (below).

Gates: Osprey 640 + inspection clean. Regressions on the final build:
`-Dataset StellarLibDecoy -LibraryAsBlib` PASSED every leg;
`-Dataset StellarGenDecoyEntrap -LibraryAsBlib` every leg PASS except mode 1b
`pass1/pass2.experiment.pairedFdp` (3.6e-5 / 3.1e-5 off the golden); `regression-parallel`
(all four datasets, .tsv legs) 47 PASS / 2 FAIL in 29:38 wall, the two failures the same two
values of the same dataset, to the last digit on both routes (run 0.01158881178911224 vs
golden 0.011624579726732956). Logs: `ai/.tmp/sessions/20261017-pairing/`.

**Why that golden moves (root cause, measured)**: `StellarGenDecoyEntrap`'s spec in
`regression.ps1` has no `Manifest`, so its legs never pass `--decoy-pairing-manifest` and its
paired FDP has always been the degenerate no-pairing value (every peptide its own group; the
estimator keys a target by (pair index, charge), so no entrapment finds one). The old
no-manifest `Build` numbered generated-decoy SEQUENCES as peptides; this library holds 116
target/entrapment pairs that are each other's C-term-preserving reversal, so a generated decoy
could hand a base id its entrapment partner's index and make an accidental pair. The new code
has none: on the exported library, 359,296 sequences, 359,296 pairing ids, no (id, charge) key
shared by a target and an entrapment peptide.

**Decisions for Brendan**: (a) the `StellarGenDecoyEntrap` golden: recapture as is, or first add
`Manifest = 'osprey_library_db_pairing.tsv'` to its spec so the paired FDP is real there (the
better fix; mode 12's emitted manifest would then carry real pairs too); (b) the no-manifest
guard in `ExcludedEntrapment` (review finding 1): the pure group rule would exclude every
entrapment peptide of a .tsv searched with no manifest, which changes the test's no-manifest
expectations he asked to hold; (c) `entrapment_method` in LibMetadata - the method is known at
CarafeSharp's `-build_entrapment_fasta` stage only, and the manifest is the one file that
reaches the library build, so carrying it means a manifest column (all three readers find
columns by name; FDRBench never reads Carafe's manifest, Osprey rewrites its own) or a library
command flag. Not done.

**Brendan's decision on (a) and (b) (2026-10-17, evening)**: never guess entrapment pairing;
fail loudly when the user seems to be requesting entrapment without the information for it,
on every load, no flag - the Skyline principle: restrict parameters to what seems reasonable
and widen only on a user's request. Done: `LibraryLoader.Load` refuses a library with
`_p_target` accessions that brings neither a DecoyPairs table nor a manifest, with the message
naming what to supply; `PairingIds.ExcludedEntrapment` is the plain group rule (the no-manifest
guard is gone, so review finding 1 is closed); the subset round trip checks the refusal;
`EntrapmentPairingTest`'s no-manifest block now runs on the library minus its entrapment
peptides. `regression.ps1`: `StellarGenDecoyEntrap` gets `Manifest =
'osprey_library_db_pairing.tsv'` (the refusal would have demanded it) and its diagnostics
golden is recaptured: `pass1.experiment.pairedFdp` 0.011625 -> 0.010552, `pass2` 0.009155 ->
0.008286, nothing else. Decision (c), `entrapment_method`, stays open.

**Decision (c) resolved (Brendan, 2026-10-17, evening)**: `Method` is how a row's sequence was
made from the row it was made from, so entrapment targets get one too - `shuffle` or
`foreign` - beside the decoys' `reverse` / `cycle`. Only CarafeSharp's `-build_entrapment_fasta`
stage knows it, and the manifest is the hand-off to the library build, so the manifest gains an
optional sixth column `entrapment_method` (on the `p_target` rows; every reader finds columns
by name, FDRBench never reads Carafe's manifest, Osprey writes its own five-column one for it),
the reconciler keeps it, and `DecoyPairPlanner` copies it onto the entrapment-target
`DecoyPairs` rows. Direction stated with it: the .blib is the transfer format between
CarafeSharp and Osprey; Carafe internal will write .blib too; the .tsv-plus-manifest path is
the Java-Carafe-to-Rust-Osprey bridge and a removal candidate once Rust stops being the parity
oracle, with the .tsv loader kept for DIA-NN libraries.

Follow-ons, not in this PR: (1) `LibMetadata` should record the foreign source FASTA's path when
one was used (Brendan); (2) Osprey's `--export-library` writes `Method` NULL on every row - it
keeps no method on `LibraryEntry` - so a .blib exported from a Carafe .blib loses `reverse` /
`cycle` / `shuffle`; carrying it means an entry field, libcache v7, and the round-trip check.

**Night session planned (Brendan, 2026-10-17 evening)**: goal 1, the .blib replaces Osprey's
`.libcache` (stop re-typing Osprey-stamped annotations, intern parsed modifications, parallel
decode, then the derived .blib written where the cache was, `LoadCache` kept one release); goal 3,
Nick's #4848 adaptation, as fallback or extra credit; then 4 (the port's `LibReader`) and only
then PR 4. Scope: BLIB I/O outside Skyline; PRs C and D later. Local commits only overnight.
TeamCity on `pull/4860`: Osprey Perf/Regression #326 48/48 PASS; the Skyline PR build failed
once on an agent-specific leak flake (TestTicChromatogram, MacCoss Agent 1, heap delta at the
20 KB threshold; same on master #22282) and was re-run.

**Next session handoff**: read `ai/.tmp/handoff-20261018_night_blib_as_cache.md` before starting
work (it supersedes `handoff-20261017_bibliospec_io_reader_pairing.md`).

### 2026-10-18 (night session) - the .blib replaces Osprey's `.libcache`

Branch `Skyline/work/20261018_blib_as_cache` off the #4860 branch (1c49fde332), two local
commits, nothing pushed. Full detail in `ai/.tmp/handoff-20261018_blib_as_cache_morning.md`.

**Commit 59d6fbc489 - the .blib load is fast enough** (HeLa, 242,841 precursors, 16 threads):
3.38s -> 0.76-0.85s against a 0.59s `.libcache` read (the handoff's bar was 2x). Of the 2.54s
"modifications and typing" bucket, 2.42s was `FragmentTyping` and 0.03s modification parsing, so
the planned modification interning was dropped. `FragmentLadder.Build` sums each ion once per
peptide, bit-identical to `CalculateFragmentMz` (pinned by `FragmentTypingTest`); `PreferredSlot`
scans its window twice with no list; `BlibLoader` reads id-RANGE partitions on every thread
(`BlibReader` partitions were `id % N`, a full table scan per thread: 9.2s of SQLite summed over
16 threads against 0.69s on one) and merges in id order. The `RefSpectraPeakAnnotations` idea was
not taken: Skyline reads that table for peptides too (as small-molecule attributes), and 4.8M rows
cost more than the typing they replace. Per-thread typing inflates ~4x at 16 threads on this box
(i9-14900, 8 P + 16 E cores), not a lock, not GC. TSV parse fell 6.25s -> 4.53s as a side effect.

**Commit 99e5e595fb - the derived .blib** (implemented by a sub-agent from a written brief,
reviewed and gated by the session): a `.tsv` source writes `<lib>.tsv.blib` where the `.libcache`
went, keyed by LibMetadata `osprey.library_hash` (composition text + `BlibLoader.CacheTerm`); a
match loads through the existing blib branch of `LibraryLoader.Load` (the `-LibraryAsBlib` route);
a valid legacy `.libcache` is still read first for one release and never written. `OmitFragments`
reads no peak blobs; `RetainFragmentsFor` skips by final base id before the scan and releases the
rest. Derived load 0.85s on HeLa. Tests in `TestSubsetStraightThroughAndReruns` and
`TestLibraryLoadsIdenticallyFromTsvAndBlib` (`DerivedLibraryDifferences`); docs 00/01/13/14/19/20/22
and `regression.ps1` staging updated.

**Gates**: Osprey Debug 642/642 + zero inspection, BiblioSpec 147, CarafeSharp 113 (perf commit);
Stellar and StellarLibDecoy regressions PASSED on both commits, `-LibraryAsBlib` legs on the first;
`regression-parallel.ps1` (all four datasets) launched on 99e5e595fb at 00:17 - result in the
handoff.

**Open**: goal 3 (#4848) not started - Nick's branch is 103 files / 44k lines against master,
mostly Skyline UI and resx plus merges of two other branches, a daytime task. The first-run cost of
writing the derived .blib (1.57M precursors ~40s; the 6.2M entrapment library a few minutes, once
per library + configuration) against ~15s for the `.libcache` is worth a line in the PR. Astral-scale
memory profile of the derived route (`--timestamp --memstamp`, `perfviz.py`) not taken. A DIA-NN
library whose decoys are flagged only by the Decoy column gets `DECOY_`-prefixed accessions in the
derived .blib (the export always did this), so its decoys' ProteinIds differ from the parse's -
pre-existing property of the .blib route, no regression dataset has one.

**Later the same night (01:00-02:00)**: Astral scale (1.57M precursors, hram): derived load 5.13s
vs 2.37s cache read, derived write 41s vs 2s, peak +0.9 GB total during the load, floor equal; thread
scaling of the derived scan 8.5 / 5.2 / 3.8 / 2.8 / 4.4s at 1 / 2 / 4 / 8 / 16 threads (SQLite's
fetch stops scaling past a few connections). **Commit 4302722c92** caps the reader partitions at 8
(`BlibLoader.MAX_PARTITIONS`): Astral 3.47s (1.46x the cache), HeLa 1.06s (1.8x; 0.85s at 16). A
reader/typer split (8 SQLite readers feeding 16 typing threads through a bounded queue) measured
WORSE (Astral 3.86s, HeLa 0.88s) and was reverted; numbers in the handoff. Stellar regression PASSED
on 4302722c92 (`sessions/20261018-night/regression-stellar-cap8.log`); Astral `-LibraryAsBlib` on
HEAD launched 01:53. The derived .blib's `DecoyPairs.Method` is NULL (entries carry no Method; nothing
in Osprey reads it) - the open "Method through the export" follow-on covers it.

**Session close (02:59)**: `/code-review medium` on the night's diff gave nine findings; five fixed in
f1291d1924 (fallback to the .tsv when the derived read faults; decoy accessions kept as loaded in
the derived file; per-partition string interning; peptide-length check before any row work; the
"manifest is not read" line suppressed on warm derived runs), four dropped with reasons in the
handoff. efe167f695 adds the test for manifest-declared decoys without an accession prefix (374
differences without the fix). All gated (Osprey 642 + inspection; Stellar + StellarLibDecoy
regressions on f1291d1924). Five local commits, none pushed. 4h28m, context 91% -> 36%.
Handoff: `ai/.tmp/handoff-20261018_blib_as_cache_morning.md`.

### 2026-10-18 - PR A merged

PR #4860 merged as commit 5c5f3ae815 (squash, `--admin`: the only red status was the required
"Skyline code inspection", which had failed on an agent-side file-copy error, MSB3021 on
`QTFLDebugLog.dll`, before inspectcode ran; the same build's 1,819 Skyline tests passed and the step
passed on master minutes later. Brendan chose to merge rather than spend a Skyline build cycle on the
re-run, which was cancelled, and to put the TeamCity time on the night's branch instead). Shipped:
`BlibReader` and the reader-side unification, a `.tsv` and its `.blib` loading as the same object,
`DecoyPairs` as the whole pairing design, `-LibraryAsBlib` regression legs, recaptured goldens.
Deferred from A, carried by the night's branch: the `.blib` fast enough to replace the `.libcache`
(done there) and `Method` on the export (open). The TODO stays active for the night's PR and B-E.

**Session end (2026-10-18 morning)**: #4864 completed alongside (merged aef1494771); the night's five
commits rebased onto master after both merges (gate 642 + inspection each time) and opened as
PR #4865 with the TeamCity Osprey Perf/Regression on `pull/4865` (build 4224466). PR E added to the
plan. Next: #4865's checks, then Nick's #4848 adaptation, then PR B, then back to Osprey-Carafe PR 4;
the Skyline PRs C-E are expected to move to the backlog.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20261018_bibliospec_next.md` before starting work.

### 2026-10-18 - PR B: the port's LibReader onto BlibReader

**Decision (Brendan, 2026-10-18)**: Nick's #4848 adaptation waits for Nick. His branch tip is
unchanged (5c76314140, 20 commits ahead of master, 16 behind) and it contains his still-open
[#4823](https://github.com/ProteoWizard/pwiz/pull/4823) (the protein-group q-value fix: Osprey
FDR code plus the four `protein_fdr.tsv` goldens, unit builds green, nothing since his 2026-10-15
master merge), so adapting #4848 as planned would carry an algorithm change and the schema change
in one PR with the goldens moving for two reasons. Offered: merge #4823 first, adapt with #4823
inside, a schema-only branch off master, or skip. Brendan chose to skip #4848 and do PR B. A
dry-run merge of his branch onto master now conflicts in 7 source files (`BlibSchema.cs` and
`Osprey.IO/BlibWriter.cs` modify/delete against #4860's moves; `BuildParser.cs`,
`PercolatorScorer.cs`, `BlibOutputWriter.cs`, `FdrProjectionSinks.cs`, `SubsetPipelineTest.cs`);
the goldens auto-merge.

**PR B coded, gated and opened** as [#4866](https://github.com/ProteoWizard/pwiz/pull/4866)
(`Skyline/work/20261018_bibliospec_libreader` off master at aef1494771, commit 85ea3d1393 after
the review fixes below):
- `BlibReader` gains the two reads the port needed and the shared reader lacked: a filtered scan
  (`ReadSpectra(withPeaks, BlibSpectrumFilter, partitions...)`, the filter's inclusive bounds on
  precursor m/z, charge and `numPeaks` going into the SQL as bound parameters) and one row by id
  (`ReadSpectrum(refId, withPeaks)`, null when absent). Partition and filter conditions share one
  private `WhereClause`; `ReadRetentionTimes` uses it too.
- The port's `LibReader` (703 lines -> 290) keeps its `RefSpectrum` surface for BlibSearch
  (`GetSpecInMzRange`) and BlibToMs2 (`GetNextSpectrum`) plus `CountAllSpec`, `GetRefSpec`,
  `GetAllRefSpec` (the RoundTrip test), converting `BlibSpectrumRecord`s; its SQL, prepared
  statement and zlib code are gone. cpp quirks kept and documented: only spectra with a peaks row
  (cpp's inner join; the shared LEFT JOIN's null-blob rows are skipped), `"-"` flanking residues
  where cpp hard-coded them and empty where cpp read neither column, NULL retention time as 0,
  the `modPrecision` rebuild from `Modifications` (through `ReadModifications`). Members nothing
  called went: `MaxSpecId`, `GetRefSpecsInRange`, `Initialize`, the default constructor,
  `GetUncompressedPeaks`. The connection stays the port's own `SqliteRoutine.Open` (unpooled,
  extended-prefix handling) handed to `BlibReader(SQLiteConnection)`.
- Order: the shared scan appends `ORDER BY r.id`; the port's range query had none, but the blib
  has no index on `precursorMZ`, so SQLite walked `RefSpectra` in rowid order already - the
  `.check` references confirm nothing moved.
- `BlibReaderTests` covers the filter (each bound, a null bound, composed with a partition) and
  the by-id read, in the existing test method.

**Gates**: BiblioSpec 147/147 (zero warnings), Osprey Debug 642/642 + zero inspection,
CarafeSharp 113/113 + zero inspection. CarafeSharp's inspection (not Osprey's) caught two
pre-existing `<see cref="ReadSpectra"/>` references made ambiguous by the overload; qualified.
`/code-review medium` run before the PR (triage below).

**#4865 this morning**: 9 checks green, the TeamCity Perf/Regression build 4224466 (triggered
06:45) still running at 35% after 20 minutes; Skyline build and inspection pending. Nothing to fix.
`mcp__status__get_pr_checks(pr_number=4865)` again resolved the current branch instead; `gh pr
checks 4865` is the reliable form.

**`/code-review medium` triage** (7 findings, before the PR): fixed 6 - a library without
`RefSpectra` or `RefSpectraPeaks` is refused at open as cpp's prepare failure was, the
connection disposed when that check throws; the peaks-row condition is
`BlibSpectrumFilter.RequirePeaksRow` (an inner join in the SQL) instead of a client-side skip
in three places; `WhereClause` keeps (name, value) pairs and binds fresh parameters per command,
since a deferred scan may be enumerated twice; a bad peak blob is reported with the spectrum id
and the library; `LibReaderTests` writes a fixture library (compressed and raw blobs, a NULL
retention time, a precursor-only row, modifications at one position twice and past the end) and
pins the window, the charge filters, the by-id read, the enumeration's end, the `modPrecision`
rebuild (summed and clamped) and the missing-table refusal. Dropped 1: `minPeaks + 1` overflow at
`int.MaxValue` - the only caller passes 5. Gates re-run after the fixes: BiblioSpec 148/148,
Osprey 642/642 + zero inspection, CarafeSharp 113/113 + zero inspection; logs in
`ai/.tmp/sessions/20261018-865c/`.

**Osprey regression on #4866** (local, Release build of 85ea3d1393): Stellar PASSED on the
`.tsv` route and with `-LibraryAsBlib` (the leg that reads the library through the changed
partition scan; 242,841 precursors exported and searched). Logs
`ai/.tmp/sessions/20261018-865c/regression-stellar-prB.log` and
`regression-stellar-blib-prB.log`. The TeamCity Perf/Regression on `pull/4866` is not triggered:
the agent was on #4865's run and the trigger is asked for, never assumed.

### 2026-10-18 (afternoon) - untangling #4848 and #4823

**Direction (Brendan, 2026-10-18)**: while #4865 waits for its merge, separate the two PRs so
every BLIB schema change lives in #4848 targeting master, and #4823 stands alone with only the
FDR calculation changes, which are the controversial part holding the schema work up.

**The cut.** Nick's 209c65fcac mixed three things: a second-pass peptide-level competition that
changes reported peptide q-values (calculation), peptide and protein-group PEP fits that depend on
#4823's new picked-protein competition (calculation), and the two columns Osprey wrote them to
(`RefSpectra.PeptidePep`, `Proteins.Pep`). So: the schema PR defines all six optional columns
(DIA-NN, Proteome Discoverer and Skyline use them) and Osprey writes the four it has values for
today (`PrecursorQValue`, `PrecursorPep`, `PeptideQValue`, `Proteins.QValue`); the peptide
competition and both PEP fits move to #4823; Osprey writing the two PEP columns is a small
follow-up once both have merged.

**Schema branch, done locally** (local `Skyline/work/20261009_blib_protein_fdr_pep`, NOT pushed;
Nick's remote tip stays 5c76314140 until Brendan says how to publish):
1. `git revert 209c65fcac` (clean) and `git revert 1af19ebadb` (one conflict in
   `SecondPassFdrTask.cs`, the reverted `ReadFirstPassProteinScores` beside a method master added).
2. `git merge origin/master`: 18 conflicts. The 12 goldens taken from master (regenerated below);
   the port's `BlibSchema.cs` and `Osprey.IO/BlibWriter.cs` deleted (master moved both to
   BiblioSpec.IO in #4855/#4860); `BuildParser.cs`, `BlibOutputWriter.cs`, `SubsetPipelineTest.cs`
   and docs/13 taken from master and Nick's intent re-applied on the shared writer.
3. The adaptation (commit on top of the merge, 2026-10-18): `BlibOptionalColumn` and the six
   definitions in BiblioSpec.IO `BlibSchema`; `BlibSpectrumRecord` carries the four spectrum values;
   `BlibWriter.AddOptionalColumn` / `RemoveOptionalColumns` / `HasOptionalColumn` (ALTER TABLE,
   the prepared inserts rebuilt with the columns, an appended library's columns loaded at open),
   `AddProtein(accession, qValue, pep)` + `AddSpectrumProtein` (the record's accessions resolve to
   a row registered with values); `BlibReader` reads the four spectrum columns. The port's
   `BlibMaker.AddOptionalColumn` / `RemoveOptionalColumns` / `AddProtein` delegate to the writer,
   `BuildParser.EnableOptionalColumn` and `InsertSpectrum` fill the record and register valued
   proteins; Nick's BlibFilter transfer SQL (`OptionalColumnsCsv`) and `BlibBuilder.AllowsOptionalColumns`
   kept as they were. Osprey: `OspreyBlibWriter.AddSearchGlobalColumns` (four columns),
   `SearchGlobalValues` on `AddSpectrum`, `AddProteinGroup` + `AddSpectrumProtein`;
   `BlibOutputWriter` writes protein groups through `ProteinGroupRows` and leaves the library's
   own proteins off a search spectrum; `IOTest.TestSearchGlobalColumns` rewritten on the wrapper;
   `SubsetPipelineTest` asserts the four columns and the groups. Two leftovers of 209c that its
   revert could not see fixed by hand: a six-argument `FdrQValues` call Nick added later in
   `ScoringTaskShared.cs`, and a doc cref in `BlibSpectrum.cs`.
4. Gates on the result: BiblioSpec 151/151 (Nick's DIA-NN and PD references and tests included),
   Osprey Debug 643/643 + zero inspection, CarafeSharp 113/113 + zero inspection. Skyline build
   and `GlobalQValueFilterTest` and the golden regeneration (two lanes, `-CreateGolden`) in flight
   at the time of writing; see below.

**#4823 side, still to do**: on a local copy of `Skyline/work/20261011_osprey_protein_fdr`,
merge master and cherry-pick 209c65fcac minus its blib-writing hunks (`Osprey.IO/BlibWriter.cs`,
`BlibOutputWriter.cs`, `BlibComparer.cs`, `BlibGolden.ps1`, docs/13, the `SubsetPipelineTest`
column asserts), so #4823 = the protein-group competition fix + the second-pass peptide
competition + the peptide and protein-group PEPs (sidecar v4), no blib changes. Cannot start
until the golden lanes finish: they write into this checkout's tree.

**Publishing (Brendan to decide)**: push the reworked branch onto Nick's (a fast-forward, no
force-push: his commits stay, followed by two reverts, the merge and the adaptation), or open a
replacement PR from a new branch and close #4848 pointing at it. Either way #4848's description
needs the "stacked on #4823" line replaced and the Osprey column list cut to four.

**Schema branch finished** (2026-10-18, local): Skyline built and `GlobalQValueFilterTest` passed;
goldens recaptured on all four datasets (two lanes, each PASSED; `protein_fdr.tsv` unchanged in
content), committed as 5df9b1c7b1 on top of the merge a92a505085. The regenerated Stellar rows
show the dependency plainly: `PeptideQValue` equals the precursor q (the second pass copies it
until #4823's peptide competition) and every protein group's `QValue` is 0 (the defect #4823
fixes). Replacement PR description drafted in `ai/.tmp/sessions/20261018-865c/pr-body-4848.md`.

**#4823 side, done locally** (local `Skyline/work/20261011_osprey_protein_fdr`, NOT pushed):
1. `git merge origin/master`: only the four `protein_fdr.tsv` goldens conflicted (master's #4860
   recaptured them after Nick's base); kept Nick's for the merge commit 837bab4555.
2. The calculation half of 209c65fcac applied with `git apply -3` from
   `ai/.tmp/sessions/20261018-865c/4823-calc-from-209c.patch` (28 files; the blib-writing hunks
   left out). Five conflicts: master had restructured the first-pass streaming path since Nick's
   base (`ExperimentScope.Resolve` resolves each entry's experiment values once; the diagnostics
   walk hands prepared folds to the sink), so the peptide PEP became a fifth output of `Resolve`,
   a parameter of `IFdrFirstPassSink.AcceptExperimentEntry` and a value the sidecar overlay
   applies; the blib test hunk in `IOTest` dropped; docs/14 updated to sidecar v4. Commit
   8b50e62cb8. Gate: Osprey Debug 645/645 + zero inspection.
3. Stellar regression on it: every blib table PASSED (the competition changes nothing the blib
   captures on master's schema); `protein_fdr.tsv` differs from Nick's golden only by master's
   drift since his base (#4860 regrouped proteins), so the four goldens are being recaptured
   (two lanes in flight). The expected net change against master is `protein_fdr.tsv` only.

**Both branches then need Brendan's publishing call** (fast-forward pushes onto Nick's branches,
or replacement PRs) and the TeamCity Perf/Regression gate on each `pull/<N>`, asked for first.

### 2026-10-18 - PR #4865 merged

PR #4865 merged as commit 1be16fdafe (squash, `/pw-complete`; all 18 checks green, TeamCity
Perf/Regression build 4224466 SUCCESS on `pull/4865`, Copilot a quota refusal). Shipped: the
.blib as the library Osprey derives from a .tsv in place of the `.libcache` (written once as
`<lib>.tsv.blib` with the composition hash in `LibMetadata`; a valid legacy `.libcache` still
read for one release, never written), the fast .blib load (allocation-free fragment typing,
id-range partitions on several threads, capped at eight), the fallback to the .tsv when a derived
read faults, and the docs and `regression.ps1` staging. Deferred, unchanged from the night's
notes: `DecoyPairs.Method` through the export (the derived file's Method is NULL), GeneNames not
carried, no Astral-scale memory profile of the derived route. The work branch is deleted once the
golden lanes free the checkout. This TODO stays active for PR B (#4866) and the #4848/#4823
untangling.

**Session close (2026-10-18 afternoon, context 25%)**: goldens on the #4823 branch recaptured
(2bc52c9f18; `protein_fdr.tsv` its only golden difference from master). PR B: master merged
(8a2dbb2c78), the `BlibReader` conflict with #4865 resolved by giving `WhereClause.AddPartition`
the id span and the BETWEEN range; BiblioSpec 148/148; Osprey gate running at close, CarafeSharp
and the Stellar regressions, the push and the TeamCity gate still to do. Brendan's plan request
answered with the three-phase plan (complete #4866; make #4848 mergeable off master, published
by fast-forwarding Nick's branch, Perf/Regression on `pull/4848`; #4823 pushed as a draft with no
TeamCity trigger) and three decisions (A: Perf/Regression on `pull/4866` first; B: push onto
Nick's branches; C: #4866 before #4848's final master merge), unanswered at close.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20261018_blib_cleanup_next.md` before starting work.

### 2026-10-18 (evening) - PR B gated and pushed, #4823 published, #4848 under review

**Decisions (Brendan, 2026-10-18)**: all three recommendations accepted: Perf/Regression on
`pull/4866` and `pull/4848` (permission given for both), publish by fast-forward onto Nick's
branches, #4866 first.

**PR B (#4866)**: CarafeSharp 113/113 + zero inspection; Release build; `regression.ps1 -Dataset
Stellar -NoBuild` PASSED (every mode) and the same with `-LibraryAsBlib` PASSED. Pushed
(85ea3d1393 -> dd4e949f1e; GitHub now MERGEABLE). TeamCity Perf/Regression build 4224618 queued
on `pull/4866`. Then `/pw-complete 4866`.

**#4865 cleanup**: local master fast-forwarded to 1be16fdafe, local `Skyline/work/20261018_blib_as_cache`
deleted. The remote delete (`git push origin --delete Skyline/work/20261018_blib_as_cache`) was
refused by the session's permission classifier; Brendan to run it.

**#4823 published**: fast-forward push 4560f3684f -> 2bc52c9f18 onto Nick's branch, converted to
draft, description rewritten (the moved peptide competition and PEPs, "no blib changes", the
peptide q now listed among the values that change, test plan with no TeamCity run). Body kept in
`ai/.tmp/sessions/20261018-cde5/pr-body-4823.md`.

**#4848 in progress**: checkout switched to `Skyline/work/20261009_blib_protein_fdr_pep`;
`/code-review medium` running. Master is one squash (#4865) ahead of its last merge; the merge
waits for #4866 so it happens once.

**#4848 reviewed and published** (2026-10-18 evening): `/code-review medium` returned seven findings;
four fixed as 909c95fcd4 (BlibWriter.AddProtein fills a row written without values with the first
values a later call supplies, through a prepared `UPDATE ... IFNULL` once per protein;
BiblioSpecLite offers a cutoff level only where the column has a non-NULL value; LibraryGlobalScores
caches BestProteinGroup; the SecondPassFdrTask doc line the 1af19ebadb revert dropped restored;
BlibReader.ReadProteins documented as accessions-only). Dropped: DIA-NN float parsing (the parquet
report is float32 and Score shares it), the per-entry LibraryGlobalScores for a library with
protein mappings but no global columns (raised in the PR body as a review question for Brendan:
master kept one string per entry), ReadProteins not reading protein values (no caller copies a
search blib through it). Gates on the fixes: BiblioSpec 151/151, Osprey 643/643 + zero inspection,
CarafeSharp 113/113 + zero inspection, Skyline build + GlobalQValueFilterTest. Pushed onto Nick's
branch (fast-forward 5c76314140 -> 909c95fcd4); description applied from
`ai/.tmp/sessions/20261018-cde5/pr-body-4848.md`. Still draft; master merge (#4865, #4866) and
Perf/Regression on `pull/4848` follow #4866's merge.

**Memory question resolved** (2026-10-18 evening, Brendan): the per-entry `LibraryGlobalScores` is not a
regression to gate away. Master held one accession string per entry (26 + 2 x length bytes); the branch
holds a fixed `LibraryGlobalScores` + `Singleton` (about 112 bytes) and shares one `LibraryProteinGroup`
per protein. Break-even at about 43 characters, a saving for semicolon-joined group names. Brendan's
fix taken: `BiblioLiteSpectrumInfo.Protein` is now a getter on the first group's name (the entry's own
reference and name copy dropped; `LibraryGlobalScores.ForProtein` + a string overload keep BlibDb's
three name-only callers). Commit d33f22622f, Skyline build + GlobalQValueFilterTest passed, pushed onto
Nick's branch; PR body's review paragraph replaced by the arithmetic.

### 2026-10-18 - PR B (#4866) merged

PR #4866 merged as commit 43c5e5eb8a (squash, `/pw-complete`; every check green: Perf/Regression
build 330 on `pull/4866` 114 passed, Skyline PR build 1819 passed, Osprey Windows and Linux 747 each,
code inspection clean). Shipped: the port's `LibReader` (BlibSearch, BlibToMs2) on the shared
`BlibReader`, which gained the filtered scan (`BlibSpectrumFilter`) and the by-id read sharing one
WHERE builder with #4865's id-range partitions; `LibReaderTests` over a fixture library. Local master
at 43c5e5eb8a; `Skyline/work/20261018_bibliospec_libreader` deleted locally and on origin. This TODO
stays active for #4848 and #4823 (and the PeptidePep/Proteins.Pep follow-up); the #4865 remote branch
delete still needs Brendan's hand.

**#4848 after #4866**: `git merge origin/master` on `Skyline/work/20261009_blib_protein_fdr_pep` was
clean (ort auto-merged `BlibReader.cs` and `BlibReaderTests.cs`; no golden conflicts, so master's
goldens did not move in #4865/#4866 and the branch's recaptured goldens stand). Re-gate in progress.

**#4848 re-gated on master with #4866** (2026-10-18 evening): merge commit df1b4e298a. BiblioSpec
152/152, Osprey Debug 643/643 + zero inspection, CarafeSharp 113/113 + zero inspection, Skyline build +
GlobalQValueFilterTest, `regression.ps1 -Dataset Stellar -NoBuild` PASSED against the branch's goldens.
Pushed onto Nick's branch (fast-forward d33f22622f -> df1b4e298a). TeamCity Perf/Regression triggered
on `pull/4848` (Brendan's permission): the first run that compares the recaptured goldens rather than
captures them. Still draft until it passes; then mark ready for Brendan's review.

### 2026-10-18 - Survey: which BlibBuild readers fill the global q-value and PEP columns

Asked for by Brendan with item F. Refs are `pwiz_tools/BiblioSpec/src/BiblioSpec/<file>:<line>` on the
#4848 branch at df1b4e298a. Readers register in `BlibBuilder._readerFactories` (BlibBuilder.cs:834-855);
`BuildParser.InsertSpectrum` writes the four spectrum values (BuildParser.cs:1046-1049) and a protein row
with values (1083-1084). `Protein.QValue`/`Pep` are init-only (PSM.cs:34, 37): a reader sharing one
`Protein` per accession (MzIdentMLReader.cs:358-363, OSWReader.cs:177-182, TSVReader.cs:449-452) must
know the value when it creates the object.

**Fill today**: DiaNNSpecLibReader - PrecursorQValue (:327, `Global.Q.Value` :437) and Protein.QValue
(:312, `Global.PG.Q.Value` :438); MSFReader - PeptideQValue/PeptidePep (:543-544, TargetPeptideGroups
`qValue`/`PEP` or `Qvalityqvalue`/`QvalityPEP` :600-608) and Protein.QValue (:657, TargetProteins
`Expqvalue`, master proteins). Nobody sets PrecursorPep or Protein.Pep.

| Reader | Formats | Score today (type) | Precursor q/PEP in format (parsed?) | Peptide q/PEP | Protein q/PEP | Notes |
|---|---|---|---|---|---|---|
| DiaNNSpecLibReader | .speclib/.parquet + report | `Global.Q.Value` (GenericQValue) | q parsed; `PEP` column unread | `Global.Peptidoform.Q.Value` (1.9+) unread | group q parsed; `PG.PEP` unread | same row loop, :437-439 |
| MSFReader | .msf, .pdResult | PSM `PercolatorqValue`/`qValue`, or peptide-group `Qvalityqvalue`, or Confidence/Mascot expect (:782-813) | PSM q is Score on the Percolator branch (:800-806); PSM `PercolatorPEP` unread | parsed | q parsed; PEP unknown | PrecursorQValue = Score only when the PSM branch ran |
| PepXMLreader | .pep.xml (PP/iProphet, Crux/Tide+Percolator, Comet, MSFragger, Tandem, MS-GF+, Morpheus, PEAKS, PD, Spectrum Mill) | engine-dependent (:821-845) | Crux `percolator_qvalue`, MS-GF+ `qvalue`, Morpheus `psm q-value` parsed; `percolator_PEP` unread; PP probability ~ 1-PEP | MS-GF+ `PepQValue` unread | none (prot.xml not read) | PD SEQUEST: SetScoreType(PercolatorQValue) at :572 but the `q-value` capture at :830 requires SequestXCorr, so it never fires (cpp parity comment; check the C++) |
| SQTreader | .sqt | Percolator q = -(M col 6) (:330) or XCorr | q parsed when percolated | unknown | L lines are names only | PrecursorQValue = Score when percolated |
| PercolatorXmlReader | .perc.xml | psm `<q_value>` (:341) | q parsed; `<pep>` sibling unread | `<peptides>` block has q/pep; reader enters the state and consumes nothing (:279, :301) | `<proteins>` q/pep when protein inference ran; unread | most complete untapped source |
| MzIdentMLReader | .mzid(.gz) | first matching cvParam (:484-570) | MS-GF/percolator/generic q parsed; `percolator:PEP`, `MS-GF:PEP` unread (same loop :487) | `MS-GF:PepQValue`, distinct-peptide q unread | ProteinDetectionList group q unread; proteins from DBSequence only (:358-363) | |
| MzTabReader | .mzTab | one `psm_search_engine_score[n]` by priority (:111-119) | chosen q or MaxQuant:PEP parsed | PEH/PEP section unread (:230-241) | PRH/PRT unread | PrecursorQValue or PrecursorPep = Score by type (:646) |
| OSWReader | .osw | `SCORE_MS2.QVALUE` (:167), feature-level | `SCORE_MS2.PEP` unread | `SCORE_PEPTIDE` CONTEXT='global' unread | `SCORE_PROTEIN` unread | SQL joins; proteins built at :177-182 |
| TSVReader OpenSWATH | .tsv with `m_score` | `m_score` (:585) | parsed | pyprophet `m_score_peptide_global` (names unverified) | `m_score_protein_global` (unverified) | |
| TSVReader Paser | .tsv File.Name/Q.Value | `Q.Value` (:1207), run-level | unknown global columns | unknown | `Protein.Ids` only | |
| MaxQuantReader | msms.txt | `PEP` (:783) | PSM PEP parsed; no PSM q in msms.txt | peptides.txt/evidence.txt `PEP` unread | proteinGroups.txt `Q-value` unread | PrecursorPep = Score |
| TandemNativeParser | .xtan.xml | `expect` | none | none | `<protein expect>` is an e-value | nothing to add |
| MascotResultsReader (MASCOT_SUPPORT) | .dat | ions score / expect | unknown | unknown | unknown | |
| IdpXMLreader | .idpXML | `result FDR` (:506) | FDR as Score | unknown | unknown | |
| ProteinPilotReader | .group(.xml) | `confidence` | none known | unknown | ProtScore, not q | |
| PrideXmlReader | .pride.xml | first recognized cvParam | `percolator:q value` parsed when chosen | unknown | unknown | |
| ProxlXmlReader | .proxl.xml | Percolator `q-value` (:443) etc. | parsed; PSM `PEP` annotation unread | reported-peptide annotations unread | none | BuildTables hardcodes PercolatorQValue (:502) against GetScoreTypes (:182-189) |
| WatersMseReader | final_fragment.csv | `peptide.score` | none | none | `protein.falsePositiveRate` maybe | |
| SslReader | .ssl | `score` + `score-type` | only if a q type | none | none | setter table :112-132 could take new columns |
| ShimadzuMLB, Hardklor, library TSVs (OpenSWATH assay, AlphaPepDeep, Paser lib) | | none / similarity | none | none | none | |

**Cheapest wins**: MaxQuant `PrecursorPep = Pep` (:783); PercolatorXml `PrecursorQValue` from :341 plus
`<pep>` and the `<peptides>`/`<proteins>` blocks; copy-the-Score for SQT (percolated), Crux/MS-GF+/Morpheus
pep.xml, mzIdentML q types, mzTab q types, PRIDE percolator q, Proxl Percolator; mzIdentML PEP cvParams in
the loop at :487; DIA-NN `PEP`/`PG.PEP`; MSFReader PSM PEP and PrecursorQValue on the PSM branch; OSW
global peptide/protein joins. Caveat for every copy-the-Score case: a PSM q is experiment-wide only when
the tool ran across all runs; a run-level q must not be labelled global.

**#4848 TeamCity** (2026-10-18 evening): Perf/Regression build 331 on `pull/4848` (df1b4e298a) SUCCESS,
the first run comparing the recaptured goldens. Marked ready for review so the Skyline/Osprey/Core PR
builds start (a draft does not trigger them). Skyline code inspection failed with eight warnings, all in
Nick's Skyline code (seven redundant casts the .NET 10 compiler resolves without them, one unused using);
fixed as 53473678f7 and pushed. The local `Build-Skyline.ps1 -RunInspection` is not usable as a gate on
this machine: unresolved `JetBrains.Annotations` / `IdentityModel` symbols in the Shared projects swamp
it (389 "errors"), none in the touched files; TeamCity's inspection resolves them. Perf/Regression not
re-triggered for the Skyline-only fix.
