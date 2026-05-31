# TODO: Decompose PerFileRescoreTask.ExecuteRescore

**Status**: In Review
**Branch**: `Skyline/work/20260530_ospreysharp_decompose_executerescore`
**PR**: [#4254](https://github.com/ProteoWizard/pwiz/pull/4254)
**Date**: 2026-05-30

## Objective

Continue the OspreySharp Tasks-layer mega-method decomposition program
(see backlog `TODO-ospreysharp_task_layer_decomposition.md`). This PR is
the first of the three remaining mega-methods: `PerFileRescoreTask.ExecuteRescore`
(~520 lines). Pure, behavior-preserving extraction along the existing
per-file-loop seams, proven bit-identical at the 1e-9 cross-impl gate.

## Approach

Verbatim lifts, keeping the per-file loop and all its `continue`
early-exits exactly in place (lowest parity risk; the #4252 pattern):

- [x] `GroupReconciliationActionsByFile` (static) — the pre-grouping pass
- [x] `BuildFileNameToIndex` (static) — stem → input-files index map
- [x] `BuildScoringSubset` (static) — boundary_overrides + subset library
- [x] `OverlayRescoredEntries` (static) — two-pass overlay → (nOverlay, nNoPeak)
- [x] `RunGapFillTwoPass` (instance) — CWT + forced gap-fill → (nGapCwt, nGapForced)

`ExecuteRescore` drops from ~520 to a ~230-line orchestrator.

## Verification

- [x] Pre-commit gate: `Build-OspreySharp.ps1 -RunInspection -RunTests` —
      Build OK, 345/347 (2 skipped), inspection clean.
- [x] Regression gate (C#-only, straight-through multi-file vs cached Rust):
      `Compare-EndToEnd-Crossimpl.ps1 -Dataset Astral -Files All -SkipRust`
      — precursor delta 0, Stage 7 + blib content 1e-9 PASS (C# wall 17:11).
- [x] Copilot review addressed (`/pw-respond`) — COMMENTED, no inline
      comments, no actionable findings; nothing to fix or resolve.
- [x] Fresh-context self-review addressed (`/pw-self-review`) — clean
      verdict, no defects at any severity; all five extractions confirmed
      verbatim (log order, sentinels, reference semantics, accumulators,
      parameter threading). One non-defect follow-up (static-vs-instance
      split): keeping the gap-fill timing logs co-located with the timed
      `RunCoelutionScoring` work is the deliberate choice to keep it a
      pure lift, hence the instance method.

## Progress Log

### 2026-05-30 - Started (autonomous night session)

Branch created off master @ 9eee47851f. Five helpers extracted as
verbatim lifts; orchestrator re-verified for flow + log-order parity.
Pre-commit gate green. Regression gate PASS (precursor delta 0, Stage 7
+ blib content 1e-9). PR #4254 opened. Copilot clean; fresh-context
self-review clean. Review chain complete — awaiting morning merge approval.
