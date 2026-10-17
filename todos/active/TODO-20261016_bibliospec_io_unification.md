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
