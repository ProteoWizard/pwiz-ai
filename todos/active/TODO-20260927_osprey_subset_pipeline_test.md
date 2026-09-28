# Osprey: fast committed subset-data pipeline test for per-commit coverage

## Branch Information
- **Branch**: `Skyline/work/20260927_osprey_subset_pipeline_test`
- **Base**: `Skyline/work/20260612_net8_port` (PR goes `--base` the port branch; update via `git merge origin/Skyline/work/20260612_net8_port`)
- **Checkout**: `C:\proj\pwiz-work1` (all Build-*/Run-* calls need `-SourceRoot C:/proj/pwiz-work1`)
- **Created**: 2026-09-27
- **Status**: In Progress
- **GitHub Issue**: [#4360](https://github.com/ProteoWizard/pwiz/issues/4360)
- **Module**: `osprey`
- **PR**: (pending)

## Objective

A fast, committed, subset-data integration test that runs the OspreySharp pipeline
end-to-end (`PerFileScoring -> FirstJoin/Percolator -> PerFileRescore -> MergeNode -> blib`)
on tiny inputs in seconds, lifting per-commit coverage (unit-only ~50.9%) toward the
cumulative number (unit + Stellar 3-file + single Astral = 77.1% as of 2026-06-21).
It complements, not replaces, the overnight real-data regression, which stays the
scientific-validity gate.

Key design point: the mzML is not the main cost - the spectral library and Percolator
are. Subset the library `.tsv` together with the mzML so kept peptides still match kept
spectra. The floor is Percolator: too small and it degenerates to zero results, which
skips downstream stages and reduces coverage.

## Tasks

- [ ] msconvert a narrow slice of one Stellar file (2-3 min RT window and/or a few isolation windows)
- [ ] Subset the `.tsv` library to peptides eluting in that window (+ enough for decoys/FDR)
- [ ] Binary-search the size down until Percolator still yields a non-empty, structurally valid `output.blib` (the floor)
- [ ] Commit the subset(s) (target a few MB); add an `OspreySharp.Test` integration test asserting a non-empty, well-formed blib (RefSpectra/RetentionTimes present, sane counts)
- [ ] Wire into the per-commit `-RunTests` suite; confirm runtime stays seconds
- [ ] Repeat with an Astral-style HRAM subset + 2-3 files (`HramStrategy`, `Ms1ScoringByproduct`, MS1/isotope, multi-file reconciliation)
- [ ] Measure delivered coverage vs the full run

## Not Covered (stays with overnight regression)

Format-specific loaders, mode-specific scorers, data-volume branches (cross-file
consensus, gap-fill), and scientific validity.

## Regression Test

- **Test name**: (filled in once written)
- **Test project**: OspreySharp.Test
- **Fails on master**: n/a - this issue adds new coverage rather than fixing a defect;
  the test itself is the deliverable
- **Passes on fix**: (pending)

## Progress Log

### 2026-09-27 - Session Start

Starting work on this issue. Branched in pwiz-work1 off the .NET 10 port branch
(`Skyline/work/20260612_net8_port`, PR #4619) at `1e3f83da34` so the test targets
the ported code.

### 2026-09-27 night - subset fixture + in-process pipeline tests

- Fixture: `Osprey.Test/TestData/StellarSubset.zip` (4.1 MB): window 594.52 (592.52-596.52), RT 7-13 min
  (+0.5 pad), MS1 trimmed to 590.5-600.5, float32 with rounded mantissas; 358-precursor library
  (178 full-run detected + 180 undetected, synthetic 4-peptide proteins) + libdecoy/entrapment
  variant (357 groups x 4). Generator: `ai/scripts/Osprey/SubsetData/build_stellar_subset.py`
  (regenerates the zip byte-identically). Full pipeline ~2.5 s per run.
- Size floor measured: conservative (d+1)/t q-values need >=100 targets per run before the first
  decoy; cross-run consensus is fixed at 1% (ReconciliationConfig.ConsensusFdr). 3 min slice gives
  ~75/run and stops at first pass; 6 min gives 128-154/run.
- Tests: `StellarSubsetPipelineTest` - straight/warm/resume/rehydrate (modes 1,4,2,5), HPC 4-task
  chain (mode 3) == straight at 1e-9 incl. peaks, libdecoy + manifest + model diagnostics + FDRBench
  + --task ModelDiagnostics, option variants (--diagnostics, --input-list, --log-file, gbdt,
  fdr-level peptide/protein). Coverage 59.1% -> 76% with the first two tests alone.
- Production changes for in-process runs: `FdrScoresSidecar.BeginRun()` (write-once guard was per
  process, so an in-process resume failed "written twice in one run"); `Pass2VerifyWorker` re-read
  per access so a test can override it.
- Findings: (1) SecondPassFDR throws when Stage 6 re-scored nothing (tiny data only);
  (2) `--parallel-files 3` diverges from sequential at Stage 7 on the subset (79 vs 11 protein groups)
  but not at full size (counts equal) - sub-agent root-causing; (3) `--report` is never written when
  -o is given (only a stem fallback) though help says "Write TSV report to file"; (4) an Osprey blib as
  library fails with ArgumentException "Labels must contain at least one decoy and one target".

### 2026-09-27 night (cont.) - fixes and findings

- FIXED (0287715d21): `--parallel-files` data race. FrozenModelScorer reused one `_scratch` buffer while the
  Stage 6 per-file second-pass workers (PerFileRescoreTask.cs:985 Parallel.For -> Pass2PerFileWorker ->
  Pass2FdrSidecar.ReadOneFilePass2Inputs -> Score) shared one scorer, so files were scored with each other's
  features. Subset: 5/5 parallel runs corrupted (0-11 peptides vs 177); full Stellar par3 happened not to overlap.
  Now ThreadLocal; TestFrozenModelScorerIsThreadSafe fails round 0 on old code; Stellar regression PASS after fix.
- Coverage (dotCover, all Osprey.Test): 59.1% -> 76% (first two tests) -> 81.6% -> 83.1% (3933c34b0a).
- FINDING, NOT FIXED (needs a decision): reconciled-row peak_sharpness artifact. PeakSharpnessCalc
  (Osprey.Scoring/PeakShapeCalculators.cs:261) measures slopes from the supplied apex; for reconciliation overrides
  PeakDataExtractor keeps the imputed apex (Rust parity, pipeline.rs:7155-7223), which can sit below an edge ->
  negative slope floored to 0, out of distribution for the frozen first-pass model. Repro: subset with replicate 22
  truncated at RT 10.5 -> first pass picks C=100 with sharpness weight -0.98 -> re-scored decoys jump (+13) ->
  0/285 peptides at 1%, EMPTY blib (control 177). Full data: Astral weight -0.06..-0.23 (+0.16..+0.57 to zero-
  sharpness reconciled rows - a quiet bias toward re-scored decoys), Stellar +0.03 (harmless). Proposed fix
  (slopes from ref-XIC max in [Start,End]) at ai/.tmp/night4360/agent3/peak-sharpness-fix.diff: gap repro -> 186
  precursors / 82 groups; first-pass outputs byte-identical; changes reconciled-row features, so goldens move and
  Rust needs the same change. Full `regression-parallel -Dataset All` with the fix running in worktree
  C:\proj\pwiz-sharpfix (log ai/.tmp/night4360/regression-sharpfix.log) for the entrapment FDP evidence.
- Dead code: LibCosineScorer (0%) and BatchScorer (0%) are referenced only by ScoringTest.
- FIXED (07cb4563fb): SecondPassFDR threw when Stage 6 re-scored nothing (single-file search with one charge per
  peptide). FIXED (856448f99d): .blib library without b/y annotations -> plain error; LinearDiscriminant.Fit returns
  null (Rust parity). TestSubsetNothingRescoredAndBlibLibrary covers both. Stellar regression PASS.
- Coverage now 83.3% (611 tests). Subset tests ~46 s total.
- Peak-sharpness: fix + TestSubsetTruncatedReplicate on LOCAL branch `nightlywork/reconciled-peak-sharpness`
  (bbf588e4eb). Full regression with fix: only goldens move; FDP flat; but Stellar -2.7% real detections lost
  (ai/.tmp/night4360/sharpness-impact.md). Needs a design decision - see ai/.tmp/handoff-20260928.md.
- Next: decide peak-sharpness approach; /code-review against the port branch (not master); open PR with
  --base Skyline/work/20260612_net8_port --label osprey.
- 2026-09-28: the --parallel-files race is issue #4706 (Mike, assigned to Brendan). This branch covers its whole
  scope: thread-local scratch (0287715d21), stress test TestFrozenModelScorerIsThreadSafe, comment fixes
  (0287715d21, 599a2df27b), and SubsetPipelineTest --parallel-files legs (stronger than a regression leg: the
  subset reproduces the race every time). PR body: `Fixes #4360` and `Fixes #4706`.
- Mike's PRs: #4708 merges cleanly with this branch (619/619 tests pass); #4715 removes --fdr-method (move the
  gbdt leg to OSPREY_FDR_MODEL, which #4715 should read via GetVariable per access). Merge order: #4708, #4715,
  this branch, #4710.
