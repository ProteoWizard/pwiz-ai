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

### 2026-06-13 -- items #1 + #2 committed on `Skyline/work/20260613_ospreysharp_scoring_helpers_cleanup`
Branch off master `a57cac690d`. `pwiz-perfbase` advanced to `a57cac690d` (no longer stale).
- **Item #1 (warm-up nits)** -- `61ef4416b9`: `IScoringDiagnostics` `--d`->`-d` doc; widened
  `WriteCwtPathRow` -> `IReadOnlyList<XicData>` (OspreyFileDiagnostics bridges via is-List zero-copy);
  fixed stale `PerFileRescoreTask` restore-breadcrumb (-> `CoelutionScorer`). Pre-commit 382 + zero-warn.
- **Item #2 (consolidate top-N-select + closest-peak)** -- `6ad83d430c`: added
  `TopFragmentExtractor.SelectTopFragmentIndices` (stable top-N by RelativeIntensity) +
  `FindClosestPeakInWindow` (closest peak by m/z, returns index). Rewired `ExtractTopNFragmentXics`,
  `ExtractFragmentXics`, `CountTop6Matches`, and `Calibrator.CollectMs2FragmentErrors` (net -67 lines).
  Note: `FindClosestPeakInWindow` returns -1 on null/empty mzs (Calibrator previously assumed non-null) --
  strictly safer, identical on real data. Gates: pre-commit 382 + zero-warn; Stellar golden + resume
  PASS @ 1e-9 (blib byte-identical); perf +0.6% total (no regression).
- **Also**: cleaned stray working-tree noise (idpicker `.nuget/.nuget/` bootstrap dir + BullseyeSharp
  submodule `obj/`); both regenerate on build, not gitignored -- dev will durably ignore later.
### 2026-06-13 -- item #3 committed
- **Item #3 (relocate `s_calXcorrScorer`)** -- `2246194fe9`: moved the unit-resolution calibration
  `SpectralScorer` off the `AbstractScoringTask` god-class onto `Calibrator` (its only runtime consumer;
  `AbstractScoringTask` never used it). Updated the 3 Calibrator call sites, the `CalibrationTest`
  bin-config invariant (now `Calibrator.s_calXcorrScorer`), and Calibrator's stale class-doc.
  **Design deviation from the TODO wording**: the TODO said "shared XCorr-resources holder"; with a
  single consumer a dedicated holder class is YAGNI, so it now lives on `Calibrator` (highest cohesion).
  Flag for review if a separate holder was intended. Gates: pre-commit 382 + zero-warn; Stellar golden +
  resume PASS @ 1e-9 (blib byte-identical). Perf: deferred to a single final full-stack run (pure field
  relocation, no hot-path change).
**Branch state**: 3 validated commits (#1 `61ef4416b9`, #2 `6ad83d430c`, #3 `2246194fe9`) off master
`a57cac690d`.

### 2026-06-13 -- PR #4299 opened (items #1-3)
https://github.com/ProteoWizard/pwiz/pull/4299. Final full-stack perf gate PASSED (Stellar; -10.1% median
total is baseline-side noise, gate verdict `ok`). Fresh-context self-review clean -- 2 LOW doc-only findings
(Calibrator null-guard widening = dead path in practice, goldens byte-identical; `OrderByDescending` uses
`float.CompareTo` vs Rust `total_cmp`, preserved verbatim, NaN/signed-zero only). Both captured in the PR body;
no code changes. **Next**: await Copilot review -> `/pw-respond 4299` (resolve threads BEFORE final TeamCity)
-> overnight TeamCity -> `/pw-complete`.

### 2026-06-13 -- rec #2 done: PR #4300 opened (parallel, orthogonal to #4299)
Branch `Skyline/work/20260613_ospreysharp_close_coupling_escapes` off master `a57cac690d` (NOT stacked on
#4299 -- only shared file is `PerFileRescoreTask.cs`, non-overlapping regions). Closes the last named
3rd-OOP-review finding (rec #2: the two coupling escapes). https://github.com/ProteoWizard/pwiz/pull/4300
- `3069eea26d` -- `DidPlan` -> `PlanningPerformed` typed byproduct; `PerFileRescore` reads the gate via
  `ctx.Get<PlanningPerformed>()` instead of `ctx.Demand<FirstJoinTask>().DidPlan()`; dead `DidPlan` removed.
- `dc09b553f3` -- `PercolatorFdr.BuildTrainingSubset` owns the dedup+subsample policy once; direct
  (`RunPercolator`) + streaming (`RunPercolatorStreaming`) paths rewired onto it; `[COUNT]` lines preserved.
- `8313cc41c6` -- self-review comment tweak (planning-gate read).
- Gates: pre-commit 382 + zero-warn (per commit); **regression `-Dataset All` PASS** -- Stellar (direct path)
  + Astral (streaming path), golden + resume @ 1e-9, all blibs byte-identical; perf +0.5% total (stage5 -0.2%);
  fresh-context self-review clean (2 LOW: 1 comment fixed, 1 acceptable).
- **Deferred follow-up**: targeted `ByproductContextTest` for the `didPlan==true` branch through
  `ctx.Get<PlanningPerformed>()` (guards the co-production ordering; e2e regression covers it today).
- **After both PRs merge -> trigger the 4th blind `/pw-oop-review`.** Item #4 task-layer decomposition
  (`PerFileScoringTask.ProcessFile`, `MergeNodeTask.Run` god-methods) is multi-sprint; the 4th review
  re-prioritizes it -- not a prerequisite.
**Next**: await Copilot on #4299 + #4300 -> `/pw-respond` each (resolve threads BEFORE final TeamCity) ->
overnight TeamCity validates both -> `/pw-complete` each -> 4th OOP review.

### 2026-06-14 -- PR #4299 MERGED
PR #4299 squash-merged to master as `27f5586e0a` (TeamCity 20/20 green, Copilot clean). Items #1-3 shipped:
the diagnostics-seam nits, the consolidated `TopFragmentExtractor.SelectTopFragmentIndices` +
`FindClosestPeakInWindow` helpers, and the `s_calXcorrScorer` relocation onto `Calibrator`. `scoring_helpers_cleanup`
work branch deleted; local master synced. **This phase TODO stays active** (covers the still-open rec #2 PR
#4300 and the path to the 4th OOP review) -- it moves to `completed/` only when the whole phase wraps.
**Remaining**: #4300 (rec #2) merge -> then 4th blind `/pw-oop-review`.
