# TODO: Decompose ScoreCalibrationEntry's separable phases

**Status**: In Review
**Branch**: `Skyline/work/20260531_ospreysharp_decompose_scorecalentry`
**PR**: [#4258](https://github.com/ProteoWizard/pwiz/pull/4258)
**Date**: 2026-05-31

## Objective

Last of the large `PerFileScoringTask` calibration methods. `ScoreCalibrationEntry`
(~393 lines) scores one library entry for calibration (window select → candidate
filter → XIC extract → peak detect → correlation score → apex/ref-XIC → SNR →
4 LDA features → MS2/MS1 mass errors → CalibrationMatch). The XIC→apex→features
core is a **cohesive per-entry pipeline** with heavily-shared local state and many
early-exit guards — deliberately NOT split. This PR extracts only the genuinely-
separable peripheral phases. Pure, behavior-preserving; bit-identical at 1e-9.

## Approach

Verbatim lifts of the separable concerns:

- [x] `ScorePeaksByCorrelation(peaks, xics)` → (bestPeak, bestCorrSum) — the
      pairwise-XIC-correlation peak scorer (the null + MIN_COELUTION_CORR_SCORE
      check stays in the caller).
- [x] `CollectMs2FragmentErrors(entry, apexSpectrum, config)` → List<double> —
      top-6 fragment mass-error collection at apex.
- [x] `ComputeMs1MassError(entry, ms1Spectra, apexRt, config)` → double? —
      M+0 precursor mass error at the nearest MS1 scan.

`ScoreCalibrationEntry` drops ~393→~290. The cohesive core (candidate/XIC/apex/
feature computation) stays intact — splitting it would thread ~10 locals through
helpers and convert clean early-returns into out-param dances, hurting readability.

## Verification

- [x] Pre-commit gate: `Build-OspreySharp.ps1 -RunInspection -RunTests` — Build OK, 345/347, inspection 0/0.
- [x] Regression gate (C#-only): precursor delta 0, Stage 7 + blib content 1e-9 PASS (C# wall 17:20). PR #4258.
- [x] Copilot review addressed (`/pw-respond`) — COMMENTED, no inline comments,
      no actionable findings.
- [x] Fresh-context self-review addressed (`/pw-self-review`) — APPROVE, no defects.
      Mechanical whitespace-normalized diffs: cohesive core byte-identical (exit 0),
      all 3 helpers faithful lifts (only added `return` statements), caller threading
      + relocated CalibrationMatch initializer field-for-field identical. Follow-up
      (migrate other call sites onto the new reusable helpers) is a forward-looking
      design Q, not a defect — ScoreCalibrationEntry is deliberately the sole caller;
      any migration needs its own parity verification.

## Note on remaining calibration code

`RunCalibration` (~244 lines) is a cohesive 2-pass orchestrator already delegating
to RunCalibrationScoringPass (#4257); low decomposition value, left as is. After
this PR, the Tasks-layer decomposition program is complete (all large methods either
decomposed or assessed-and-left-cohesive).

## Progress Log

### 2026-05-31 - Started (autonomous night session)

Branch off master @ 9eee47851f. Three peripheral-phase helpers extracted as
verbatim lifts; cohesive scoring core left intact.
