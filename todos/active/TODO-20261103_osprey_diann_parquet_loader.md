# TODO-20261103_osprey_diann_parquet_loader.md

## Branch Information
- **Branch**: `Skyline/work/20261103_osprey_diann_parquet_loader`
- **Base**: `master` (3c2f42b552)
- **Created**: 2026-11-03
- **Status**: PR open, awaiting review and the TeamCity gate (parent session queues it). Decision
  for Brendan (optional): derived-cache naming for DIA-NN's fixed `report-lib.parquet` name in a
  shared `--cache-dir` (see Code review, dropped item 4).
- **GitHub Issue**: (none - backlog TODO-osprey_diann_library_interchange.md, part 1)
- **Module**: `osprey`
- **PR**: (pending)
- **Worktree**: `C:\proj\wt-progress` (agent H of the 2026-11-03 round-2 wave)

## Objective

Osprey `-l report-lib.parquet`: read DIA-NN 2.x's library `.parquet` (predicted or empirical)
directly, with no conversion script. Part 1 of
[TODO-osprey_diann_library_interchange.md](../backlog/TODO-osprey_diann_library_interchange.md);
part 2 (Osprey writes a DIA-NN TSV) and the benchmark-script simplification (plan step 5) stay in
the backlog file.

Fixtures and their measured properties: `M:\home\brendanx\data\MacCoss\Osprey\DIA-NN\README.md`
(local copy `D:\test\diann-fixtures`).

## Design decisions

- **Shared column reader: option 2** (move the column reading into the assembly both already
  share). `Osprey.IO` and `Pwiz.Tools.BiblioSpec` both reference `BiblioSpec.IO`; Osprey cannot
  reasonably reference `Pwiz.Tools.BiblioSpec` (it pulls MsData, IdentData, Analysis, the Waters
  vendor reader and the Mascot native shim build into Osprey, and its parquet reader is private
  and bound to BiblioSpec's `Entry` model). So the DIA-NN library columns (names, types, the
  row-group loop, the synchronous Parquet.Net bridge) move to `BiblioSpec.IO`
  (`DiannLibraryParquetReader`), and both `DiaNNSpecLibReader.LoadSpecLibFromParquet` and
  Osprey's `DiannParquetLoader` call it. `BiblioSpec.IO` gains `ReferenceParquetNet` (every
  consumer - Skyline, Osprey, CarafeSharp, BiblioSpec - already deploys the patched Parquet.dll).
- **Row assembly shared with the .tsv path**: `DiannTsvLoader`'s per-precursor accumulation and
  materialization (modification parsing, min-fragment rule, peak merge, typing check, interning)
  is used by both loaders, so the two formats cannot drift.
- `RT` maps to the field `NormalizedRetentionTime` fills; `Genes` to gene names (as the .tsv path
  prefers `Genes`); `Protein.Ids` to protein ids; `Decoy` (int64, 0/1) to `IsDecoy`.
- `LibraryFormat.DiannParquet` appended to the enum; derived cache `<library>.parquet.blib`;
  `.speclib` refused in `LibrarySource.FromPath` with the conversion command.

## Tasks

- [x] `DiannLibraryParquetReader` in BiblioSpec.IO
- [x] BiblioSpec `DiaNNSpecLibReader` on the shared reader; BiblioSpec tests + before/after blib check
- [x] `DiannParquetLoader` in Osprey.IO sharing the .tsv row assembly
- [x] `LibraryLoader` / `LibrarySource` / `OspreyTask` reader term dispatch; `.speclib` refusal
- [x] `-l` help text and docs (`docs/20-command-line.md`, `docs/14-intermediate-files.md`)
- [x] Tests: parquet vs converted tsv (base + varmods), empty library, `.speclib` refusal, invalid rows
- [x] Full-size load measurement (`human-fasta.library.parquet`)
- [x] Osprey pre-commit gate; Stellar regression
- [x] /code-review medium; PR

## Gate evidence (HEAD 2c4f9fb6bd)

- Osprey pre-commit (Debug, tests + inspection): 650/651, 0 inspection warnings; the one failure is
  `TestCommandLineHelpDocumentation` regenerating the help for the changed resx, which passes on
  re-run (`D:\test\agentH\osprey-precommit3.log`, `osprey-test5.log`).
- `regression.ps1 -Dataset Stellar`: PASSED, mode1 golden, 1c, 4, 6 all PASS
  (`D:\test\agentH\regress\regression-stellar.log`; the pre-review run at 9182bb4bae also passed,
  `regression-stellar-20261103_220717.log`). Golden unchanged.
- BiblioSpec: 142/142 (`D:\test\agentH\biblio-tests2.log`); BlibBuild before/after identical tables
  (`D:\test\agentH\base-emp20.blib` vs `new2-emp20.blib`).
- Not run: Skyline build (Skyline references BiblioSpec.IO, which now references Parquet.Net, which
  Skyline already references with the same patched dll) - Skyline CI covers it on the PR.

## Code review (/code-review medium, 10 findings)

Fixed (commit 2c4f9fb6bd):
1. BiblioSpec reader not disposed when `Require` threw - now inside the `using`.
2. Unconvertible column type surfaced as `InvalidDataException` in BiblioSpec - rewrapped as `BlibException`.
3. `AddFragmentRow` split proteins/genes/stripped sequence on every row - now on a precursor's first
   row only (output-neutral; the values were only used there).
4. Parquet row errors headed "library lines" - own "library rows" header resource.
5. `--decoy-pairing-manifest` / `--export-library` help named only `.tsv` - now `.parquet` too.
6. `AddRow` error plumbing (duplicate clamp, dummy `ref`) - one `AddError` helper.

Dropped:
- "Decoys keep the target's Modified.Sequence and merge into it": not DIA-NN's shape - the fixture
  README measured decoy ids as different sequences (`AIIKPLEQTEC(UniMod:4)LSK2` decoy of
  `AAIKPLEQTEC(UniMod:4)LNK2`), and the key is the .tsv path's, which must stay identical.
- "Whole row group of strings materialized at once": measured instead - 23 s, peak managed 4.1 GB
  on the 1.56 M-precursor human library; acceptable, and streaming within a row group is a
  Parquet.Net-API change for a later round if a 3 M library needs it.
- "Report-parquet boxing helpers duplicated in BiblioSpec": the PSM `report.parquet` path is a
  different file and out of scope; moving it to BiblioSpec.IO is a BiblioSpec refactor.
- "Fixed name report-lib.parquet collides in a shared --cache-dir": same keying as a `.tsv`
  (file name + size + mtime); a collision mismatches the hash and rebuilds (correct, slower).
  Decision for Brendan if wanted: key the derived name by a path hash. Left as is (conservative).

## Follow-ups (not this round)

- Pair library decoys from `Source.Id` (DIA-NN empirical decoys name their target there).
  Measured why it matters: `Osprey -l empirical-20prot/report-lib.parquet --decoys-in-library
  --export-library` pairs 42 of 162 DIA-NN decoys by composition (25.9%) and refuses the library
  (needs 80%), exactly as a .tsv of the same library would; without the flag the 162 decoys are
  dropped by decoy generation and Osprey generates its own (log: `D:\test\agentH\emp-decoys\`).
- Part 2 and plan step 5 of the backlog TODO.

## Progress Log

### 2026-11-03
- Read the brief, backlog TODO and fixture README; fixtures copied to `D:\test\diann-fixtures`.
- Fixture check (pyarrow): in the 20-protein libraries the EMPTY row group is the LAST of the two
  (row groups 31,497 / 0), where the README lists it first; either way the loader iterates every
  row group and assumes nothing of any one.
- Shared reader `pwiz_tools/Shared/BiblioSpec/BiblioSpec.IO/DiannLibraryParquetReader.cs`;
  `DiaNNSpecLibReader.LoadSpecLibFromParquet` (was `...Async`) reads through it. BiblioSpec
  verification: `Build-BiblioSpec.ps1 -RunTests` 142/142 (`D:\test\agentH\biblio-tests.log`); and
  `BlibBuild report-lib.parquet` on `empirical-20prot` from a snapshot of the base build vs the
  branch: every table identical but `LibInfo`/`LibMetadata` (file name, date)
  (`D:\test\agentH\base-emp20.blib`, `new-emp20.blib`). The tree had no library-parquet test in
  BiblioSpec, so this before/after is the only check of that path.
- `Osprey.IO/DiannParquetLoader.cs`; `DiannTsvLoader` split into `AddFragmentRow` /
  `BuildEntries` (pure code motion) shared by both. `LibraryFormat.DiannParquet`,
  `.speclib` refusal, `;tsvreader=5;parquetreader=1` key term, `parquet_reader:` composition term.
- Test `SubsetPipelineTest.TestDiannParquetLibraryLoadsAsItsTsv` (fixtures in
  `Osprey.Test/TestData/DiannParquetSubset.zip`, 2.4 MB, README inside). The parquet and the
  converted .tsv load IDENTICALLY (exact, no float32 tolerance needed: pyarrow's shortest text of
  each widened float32 reads back to the same double), except gene names, which the conversion
  drops. The derived blib also drops gene names (documented: a .blib holds none, no output reads them).
- Gate: `Build-Osprey.ps1 -Configuration Debug -RunTests -RunInspection` 650/651 with 0 inspection
  warnings; the one failure was `TestCommandLineHelpDocumentation` regenerating the help pages
  for the new `-l` text, passing on re-run (`D:\test\agentH\osprey-precommit2.log`, `osprey-test3.log`).
  `TestArgumentTextComesFromArguments` caught DIA-NN's `--lib` typed into two resources; the
  command now comes from `LibrarySource.SpeclibConversionCommand`.
- Full-size measurement (Release, `--export-library`, `--timestamp --memstamp`,
  `D:\test\agentH\measure\measure.log`): `human-fasta.library.parquet` (263 MB, 18.66 M rows,
  6 row groups) -> 1,563,884 precursors. Parse 23 s (16 s reading row groups, 7 s building
  entries); peak managed heap 4.1 GB, peak total 6.3 GB (memstamp, uncollected garbage included;
  perfviz: sustained 1.5 GB managed). Derived `.parquet.blib` write 53 s; whole export 177.5 s.
  Typing check: 2,162 of 18.66 M peaks the library labels as another ion within tolerance, 504
  with no ion in tolerance (warning, as for a .tsv).
