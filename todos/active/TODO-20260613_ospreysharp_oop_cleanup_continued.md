# TODO-20260613_ospreysharp_oop_cleanup_continued.md

Continue paying down OspreySharp OOP / structural tech-debt from the **3rd OOP review**,
one gated PR at a time, until the codebase is ready for a **4th OOP review**. This is the
working record for the phase after the `AbstractScoringTask` god-class decomposition.

The decomposition (rec #1) + the diagnostics-bleed fix (rec #3) just landed -- see
`completed/TODO-20260611_ospreysharp_decouple_abstractscoring.md` (PRs #4290-#4295, #4298,
all byte-parity 1e-9 + perf gated).

## Goal
Iteratively decompose / clean remaining structural debt (one gated PR per item, or one PR
with several validated commits) until the dominant debt is paid down enough to warrant the
next blind OOP review. Cadence rationale: [[project_osprey_organic_growth_needs_iterative_oop_review]].

## Candidate work (rough priority; triage at session start)
1. **Deferred IScoringDiagnostics nits** (small; from #4298 Copilot, deferred): doc `--d` -> `-d`;
   widen `IScoringDiagnostics.WriteCwtPathRow(List<XicData>)` -> `IReadOnlyList<XicData>` (match the
   sibling `WriteSearchXicDump`, update `OspreyFileDiagnostics` to suit); fix the stale
   `PerFileRescoreTask.cs:779` restore-breadcrumb (still points at AbstractScoringTask; now in
   `CoelutionScorer`). Behavior-neutral -> a small warm-up PR.
2. **Consolidate the triplicated top-N-select + closest-peak-by-m/z loop** -- now in
   `TopFragmentExtractor.ExtractTopNFragmentXics` + `.ExtractFragmentXics` + open-coded in
   `Calibrator.CollectMs2FragmentErrors`. Extract a shared `SelectTopFragmentIndices` + XIC-probe
   helper. Parity-sensitive (stable tie-break) -> own gated PR.
3. **Relocate `s_calXcorrScorer`** (the calibration unit-resolution `SpectralScorer`) out of
   `AbstractScoringTask` into a shared XCorr-resources holder. Note the `CalibrationTest`
   bin-config invariant that asserts it.
4. **Remaining OOP-review-findings items** -- backlog [[TODO-ospreysharp_oop_review_findings.md]]
   (rec #2 `DidPlan`/`BuildTrainingSubset` coupling escapes; anything past #1/#3) and the
   task-layer decomposition backlog (`backlog/brendanx67/TODO-ospreysharp_task_layer_decomposition.md`).

## Standing gates (every structural PR) -- see ai/scripts/OspreySharp/PRE-COMMIT.md
- **Pre-commit**: `Build-OspreySharp.ps1 -Configuration Debug -RunTests -RunInspection` (zero-warning).
- **Correctness**: `regression.ps1 -Dataset Stellar` (golden + resume @ 1e-9; `-Dataset All` before a
  behavior/perf-sensitive merge).
- **Perf**: `Test-PerfGate.ps1 -Dataset Stellar` vs pinned `pwiz-perfbase`. **perfbase is STALE** --
  pinned at `9035c425fc`; master is now `a57cac690d` (#4298) or later. ADVANCE `pwiz-perfbase` to the
  current master HEAD + rebuild (Release net8.0) before the first perf gate.
- **Diagnostics-touching changes**: the 1e-9 gate runs diagnostics-OFF; add a diagnostics-ON
  dump-parity check (master vs branch, dumps enabled) -- see the diag-parity approach in the completed
  decomposition TODO. [[feedback_ospreysharp_csharp_regression_gate]]

## Workflow notes / lessons
- Review chain: `/pw-self-review` (local) -> open PR -> **address Copilot + resolve threads** -> THEN
  let the overnight TeamCity regression run. Do NOT wait for final TeamCity with Copilot comments still
  open (developer preference, 2026-06-13).
- Prefer fewer, larger PRs (the per-stage ones were smaller than the dev normally does): one PR with
  several validated commits, gates run between commits, is the preferred shape.
- Stacked PRs: never `--delete-branch` mid-cascade -- it auto-closes the dependent PR.
  [[feedback_stacked_pr_no_delete_branch]]
- Injected diagnostics use a nullable interface + `diag?.X()` (mirrors the old `Sink?.X()`; no
  hot-path cost) rather than a no-op singleton.

## Progress Log

### 2026-06-13 -- created (continuation of the decomposition phase)
`AbstractScoringTask` decomposition + diagnostics-bleed landed (#4298 squashed as `a57cac690d`).
This TODO carries the remaining 3rd-OOP-review cleanup forward toward a 4th review.
**Next session handoff**: for the detailed startup protocol, read `ai/.tmp/handoff-20260613.md`
before starting work.
