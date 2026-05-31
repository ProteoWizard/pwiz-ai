# TODO: Decompose PerFileScoringTask.RunCalibrationScoringPass

**Status**: In Review
**Branch**: `Skyline/work/20260531_ospreysharp_decompose_calscoringpass`
**PR**: [#4257](https://github.com/ProteoWizard/pwiz/pull/4257)
**Date**: 2026-05-31

## Objective

Beyond the three originally-named Tasks-layer mega-methods (now done:
#4254 ExecuteRescore, #4255 FirstJoinTask.Run, #4256 PerFileScoringTask.Run),
`PerFileScoringTask` has large parity-sensitive calibration methods. This PR
decomposes `RunCalibrationScoringPass` (~480 lines — one calibration scoring
pass: preprocess → parallel score → LDA + 1% FDR → S/N collect → mass-error
aggregate → LOESS fit). Pure, behavior-preserving extraction, bit-identical
at the 1e-9 cross-impl gate.

## Approach

Verbatim lifts of the distinct phases; the LDA train + LOESS fit stay in the
orchestrator (single calls + result assembly):

- [x] `PreprocessWindowsForXcorr` — f32 unit-bin XCorr preprocessing per window.
- [x] `ScoreCalibrationMatches` — the `Parallel.ForEach` scoring loop; returns
      (matches, snrByEntryId, matchRts); emits the timing + match-count logs.
- [x] `CollectCalibrationPoints` — 1% FDR + S/N>=5 filter → (libRts, measuredRts);
      emits the S/N-filter + point-count logs.
- [x] `AggregateMassCalibrations` — MS1/MS2 mass-error aggregate + single-level
      cal + MS2 cal-errors dump + logs.

`RunCalibrationScoringPass` body drops ~290→~150 lines. (Removed the now-unused
`resolution` local from the orchestrator; the score helper reads it.)

## Verification

- [x] Pre-commit gate: `Build-OspreySharp.ps1 -RunInspection -RunTests` — Build OK, 345/347, inspection 0/0.
- [x] Regression gate (C#-only): precursor delta 0, Stage 7 + blib content 1e-9 PASS (C# wall 16:51). PR #4257.
- [x] Copilot review addressed (`/pw-respond`) — COMMENTED, no inline comments,
      no actionable findings; nothing to fix.
- [x] Fresh-context self-review addressed (`/pw-self-review`) — APPROVE, no
      defects. Verified byte-identical parallel-scoring determinism, the
      order-imposing sort still gating downstream reads, all matchArray loop
      predicates, log order, out-params, early returns, diagnostics, the
      resolution-local removal, and complete ctx→_ctx. Follow-up (early-return
      branches verified by inspection vs. exercised on Astral) is a non-issue
      for a verbatim lift.

## Remaining calibration decomposition (assessed)

- `ScoreCalibrationEntry` (~410 lines): per-entry scoring (XIC extract / peak
  detect / 4-feature compute) — candidate for a follow-up PR (PR5); read +
  assess seams before splitting (per-entry algorithms can be cohesive).
- `RunCalibration` (~244 lines): cohesive 2-pass orchestrator that already
  delegates to RunCalibrationScoringPass; low decomposition value, leaving as is.

## Progress Log

### 2026-05-31 - Started (autonomous night session)

Branch off master @ 9eee47851f. Four phase-helpers extracted as verbatim lifts.
