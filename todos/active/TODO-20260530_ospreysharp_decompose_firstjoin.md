# TODO: Decompose FirstJoinTask.Run

**Status**: In Review
**Branch**: `Skyline/work/20260530_ospreysharp_decompose_firstjoin`
**PR**: [#4255](https://github.com/ProteoWizard/pwiz/pull/4255)
**Date**: 2026-05-30

## Objective

Second of the three remaining OspreySharp Tasks-layer mega-methods
(see backlog `TODO-ospreysharp_task_layer_decomposition.md`):
`FirstJoinTask.Run` (~657 lines, the largest and most coupled — it owns
the Stage 5 first-pass FDR + Stage 6 planning checkpoint and the shared
`_perFileEntries` blackboard). Pure, behavior-preserving extraction along
the existing Stage-boundary seams, proven bit-identical at the 1e-9
cross-impl gate.

## Approach

Verbatim lifts. The two big blocks carry early-exit/`ExitCode` semantics,
so their helpers return a `bool` the orchestrator checks (`if (!helper(...)) return false;`):

- [ ] `LogFirstPassResults` (instance) — per-file + total passing-target log
- [ ] `CompactFirstPass` (instance) — bundle-path delegate vs inline base_id compaction
- [ ] `ReloadSecondPassOverlay` (instance) → bool — 2nd-pass sidecar overlay reload
- [ ] `PlanStage6` (instance) → bool — multi-charge consensus + consensus RTs +
      calibration refit + reconciliation planning + reconciliation.json write;
      sets the `_didPlan`/`_perFileConsensusTargets`/... output fields

`Run` drops from ~657 to a ~120-line orchestrator. Everything below `Run`
(RunPercolatorFdr, WriteReconciliationFiles, BuildReconciliationFile, etc.)
is already well-factored and untouched.

## Verification

- [x] Pre-commit gate: `Build-OspreySharp.ps1 -RunInspection -RunTests` — Build OK, 345/347, inspection 0/0.
- [x] Regression gate (C#-only): precursor delta 0, Stage 7 + blib content 1e-9 PASS (C# wall 17:17).
- [x] Copilot review addressed (`/pw-respond`) — 2 inline doc-accuracy nits
      (XML docs said `ctx.ExitCode`; helpers use `_ctx`). Fixed in 4bb2c7229b
      (now `<see cref="PipelineContext.ExitCode"/>`); both threads resolved.
- [x] Fresh-context self-review addressed (`/pw-self-review`) — clean verdict,
      no defects. Confirmed log order, all ExitCode/return-false paths, the
      PlanStage6 gate, output-field assignments, parameter threading, and the
      complete ctx→_ctx substitution. One non-defect follow-up (mixed
      _ctx-field/config-param convention): config passed explicitly keeps
      helper signatures self-documenting, matching the file's other helpers.

## Progress Log

### 2026-05-30 - Started (autonomous night session)

Branch created off master @ 9eee47851f. Four helpers extracted as verbatim
lifts (LogFirstPassResults, CompactFirstPass, ReloadSecondPassOverlay→bool,
PlanStage6→bool); Run reduced ~657→~165 lines. Pre-commit gate green;
regression gate PASS (bit-identical). PR #4255 opened.
