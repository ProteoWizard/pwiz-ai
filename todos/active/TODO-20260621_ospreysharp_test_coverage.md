# TODO-20260621_ospreysharp_test_coverage.md -- OspreySharp test coverage: cumulative estimate, new unit tests, and EncyclopeDIA .elib removal

> Raise and *measure* OspreySharp test coverage. Three workstreams in one session:
> **(A)** a cumulative tctest+regression coverage estimate (dev tooling, pwiz-ai);
> **(B)** new unit tests that raise the TeamCity "Osprey Windows .NET" (unit-only)
> statement coverage above its 46.8% baseline (pwiz); **(C)** removal of the
> unused EncyclopeDIA `.elib` library reader, which both deletes a 0%-covered
> class and shrinks the uncovered denominator (pwiz). Renamed/expanded from the
> original `TODO-20260610_ospreysharp_cumulative_coverage.md` to cover the whole
> session.

- **Created**: 2026-06-10 (as cumulative-coverage tooling); **expanded**: 2026-06-21
- **Status**: In Progress -- all gates green + pushed; pwiz PR not yet opened
- **Branch (pwiz)**: `Skyline/work/20260621_ospreysharp_test_coverage` (pushed)
- **pwiz-ai**: committed + pushed to master

## Deliverables (two repos, two destinations)

### 1. ProteoWizard/pwiz -- ONE PR (branch `Skyline/work/20260621_ospreysharp_test_coverage`)
Workstreams **B** + **C**:
- **New unit tests** (`pwiz_tools/OspreySharp/OspreySharp.Test/`), targeting the
  highest-value *pure* classes the unit suite missed (per the unit-only dotCover
  report):
  - `IsotopeDistributionTest.cs` -- `OspreySharp.Core.IsotopeDistribution`
    (282 stmts, was 0%): peptide composition, isotope distribution, cosine score.
  - `FragmentSelectionTest.cs` -- `FragmentMath` + `Scoring.FragmentOverlap` +
    `Scoring.TopFragmentExtractor` (~163 stmts, mostly 0%): top-N selection,
    closest-peak lookup, prefilter / overlap counting, XIC extraction.
  - `PeakDetectorTest.cs` -- `Chromatography.PeakDetector` paths not covered by
    `ChromatographyTest` (end-of-series + min-width Detect, FindBestPeak,
    Savitzky-Golay, DetectAllXicPeaks).
  - `MedianPolishMetricsTest.cs` -- `Scoring.TukeyMedianPolish` post-fit metrics
    (LibCosine, ResidualRatio, MinFragmentR2, ResidualCorrelation).
- **EncyclopeDIA `.elib` removal** (Mike-okayed; `.elib` inputs are not expected):
  - Deleted `OspreySharp.IO/ElibLoader.cs` (138 stmts, 0% unit coverage).
  - Removed `LibraryFormat.Elib`, the `.elib`->Elib case in `LibrarySource.FromPath`,
    and the `LibraryFormat.Elib` dispatch in `LibraryLoader`.
  - Updated `Program.cs` `--help` (`.tsv, .blib`) and `CoreTypesTest` (an `.elib`
    path now resolves to the default DIA-NN TSV loader, which fails loudly on
    parse -- no silently-invalid output).

### 2. ProteoWizard/pwiz-ai -- direct to master (no branch, per ai/WORKFLOW.md)
Workstream **A** (developer tooling + this TODO):
- `ai/scripts/OspreySharp/Measure-CumulativeCoverage.ps1`: added `-Files Mixed`
  (Stellar = all 3 files, Astral = single file) -- the cheap tctest+regression
  estimate that still lights up the HRAM-only code (`HramStrategy`,
  `Ms1ScoringByproduct`, `IsotopeDistribution`, `LibCosineScorer`) a single Astral
  file reaches but Stellar never does.
- This TODO file (rename + expansion).

## Results (measured 2026-06-21)

- **Unit-only (tctest) statement coverage**: 46.8% (7564/16161) baseline ->
  **50.9% (8149/16019)** after the new tests + `.elib` removal -- **+4.1 pts**
  (+585 covered statements; denominator -142 from deleting `ElibLoader`). Gains:
  Core 63.1%->79.4%, Chromatography 66.5%->77.1%, Scoring 38.3%->46.1%,
  IO 63.7%->67.1%.
- **Cumulative tctest+regression (`-Files Mixed`)**: **77.1% (12453/16161)** --
  unit + Stellar 3-file straight+resume + Astral single straight+resume,
  dotCover-merged. Progression: ~45% unit-only -> 70.8% Stellar-single -> 73.4%
  Stellar-3-file -> **77.1% +single-Astral** (the single Astral leg added ~3.7 pts
  of HRAM coverage). Per assembly: Core 90.4%, ML 90.6%, FDR 87%, Chromatography
  83.3%, Scoring 82.5%, Tasks 77.3%, IO 74.4%, exe 28.3%. (Measured against the
  pre-removal code, so `ElibLoader` still appears as 138 stmts @ 0% there.)

## Verification gates (after the goal-1 coverage run frees the exe)

1. `Build-OspreySharp.ps1 -Configuration Debug -RunTests -RunInspection` -- **PASS**:
   build clean, inspection 0 warnings/0 errors, tests 426 passed / 0 failed
   (3 pre-existing skips), incl. the 31 new test methods.
2. `pwiz_tools/OspreySharp/regression.ps1 -Dataset Stellar` -- **PASS**: mode1
   (vs golden), mode2 (resume), mode3 (HPC chain) all green; output unchanged.
3. `Build-OspreySharp.ps1 -Coverage` -- **DONE**: unit-only 50.9% (see Results).

## Acceptance criteria

- One pwiz PR (tests + `.elib` removal) that builds clean, passes inspection,
  raises unit-only coverage above 46.8%, and keeps the Stellar regression green.
- The `-Files Mixed` cumulative estimate runs end-to-end and reports a merged
  number above unit-only, demonstrating the pipeline + single-Astral coverage.
- pwiz-ai changes (Mixed mode + this TODO) committed to master.

## Out of scope / future

- A scheduled TeamCity cumulative-coverage config + trend.
- Per-test attribution, coverage thresholds/gates.
- Covering the remaining 0% pipeline-orchestration classes (`Tasks.*`,
  `ScoringPipeline`, `PeakDataExtractor`) -- these need integration harnesses,
  not unit tests; the regression already exercises them.
- The `Build-OspreySharp.ps1` 2025.3.0+ dotCover CLI update (separate fragility).

---

## Workstream A detail (cumulative-coverage tooling) + original progress log

The mechanics below were established while building the cumulative-coverage
orchestrator; retained for provenance.

- dotCover (console runner **2025.1.7**) accumulates across processes:
  `cover` -> per-process `.dcvr`; `merge /Output=all.dcvr /Source=a.dcvr;b.dcvr`;
  `report /Source=all.dcvr /Output=cov.json /ReportType=JSON`.
- In-repo precedent: Skyline `TestRunner.GenerateCoverageReport`
  (`pwiz_tools/Skyline/TestRunner/Program.cs:1286`) -- snapshot-per-worker, merge,
  report.
- `Measure-CumulativeCoverage.ps1` orchestrates: unit leg
  (`Build-OspreySharp.ps1 -Coverage`) + per-dataset straight + resume legs run via
  `OspreySharp.exe` directly under `dotcover cover`, then merge -> report (JSON) ->
  `Summarize-Coverage.ps1`. Runs the exe directly (not `regression.ps1`) so no pwiz
  script changes are needed for coverage.
- Serialization: sets `OSPREY_MAX_PARALLEL_FILES=1` for determinism under
  instrumentation (a 3-file Stellar parallel leg intermittently died at the blib
  write on a dotCover-specific shared-framework assembly load; serial is reliable).
  Single-file legs (incl. the Mixed-mode Astral leg) are sequential anyway.

### 2026-06-10 -- Created (ai/-only reframe); orchestrator working; first number
Confirmed cumulative coverage is ai/-side tooling. Wrote
`Measure-CumulativeCoverage.ps1` (unit + per-dataset straight+resume, merged).
**First run (unit + Stellar single straight+resume) = 70.8% cumulative**
(11465/16191) vs ~45% unit-only. Instrumentation is heavy (single-file Stellar
straight ~7.5 min under dotCover).

### 2026-06-11 -- Stellar 3-file cumulative number: 73.4%
Serialized re-run succeeded. **Cumulative = 73.4% (11878/16191)** for unit +
Stellar 3-file straight+resume. Remaining uncovered dominated by HRAM-only code
(`IsotopeDistribution`, `LibCosineScorer`, `Ms1ScoringByproduct`, `HramStrategy`),
`OspreyFileDiagnostics` (env-gated dump code), and `ElibLoader` (`.elib` input).
Staged plan: add one Astral file straight-through to light up the HRAM path.

### 2026-06-21 -- Session expansion: tests + .elib removal + Mixed mode
- Added `-Files Mixed` (Stellar all-files + Astral single-file) and launched the
  cumulative estimate (unit + Stellar 3-file + Astral single, straight+resume).
- Wrote 4 unit-test files (workstream B) targeting the top pure 0%/low classes.
- Removed EncyclopeDIA `.elib` reading (workstream C) -- one of the flagged 0%
  classes (`ElibLoader`) is now gone rather than covered.
- Branched pwiz `Skyline/work/20260621_ospreysharp_test_coverage`.

### 2026-06-21 -- Verified + committed + pushed
- Gates all green: build clean; inspection 0 warnings; 426 tests pass (incl. 31
  new); unit-only coverage **46.8% -> 50.9%**; Stellar regression PASS (mode 1/2/3,
  output unchanged); cumulative `-Files Mixed` = **77.1%**.
- pwiz branch: two commits (unit tests; `.elib` removal) pushed to origin.
- pwiz-ai: Mixed mode + this TODO committed + pushed to master.
- **Remaining**: open the pwiz PR after `/pw-self-review`, address Copilot, merge,
  then move this TODO to `completed/`.
