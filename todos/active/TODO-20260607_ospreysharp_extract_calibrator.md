# TODO: OspreySharp — extract calibration out of PerFileScoringTask into a Calibrator

**Status**: Backlog (not started)
**Priority**: Medium — largest single readability win, lowest risk of the three;
good first step before the scoring decomposition
**Type**: Architecture / separation of concerns
**Source**: OOP review of `pwiz_tools/OspreySharp` (2026-06-06), Separation-of-
concerns lens + Top Recommendation #1

## Problem

`OspreySharp/Tasks/PerFileScoringTask.cs` (2,828 LOC) owns at least four distinct
concerns in one class:

- library + decoy loading — `LoadLibraryAndDecoys` (`:592`)
- **RT/mass calibration** — roughly `:1581–2782` (~1,200 LOC, ~40% of the file)
- per-file scoring orchestration — `ProcessFile` (`:1152`), `ScoreOrLoadForFile`
  (`:1016`)
- parquet/sidecar I/O and feature dumps — `WriteFeatureDump` (`:1453`),
  `TryLoadStubsAndCalibration` (`:1081`)

Calibration is a self-contained subsystem with its own private result type
(`CalibrationPassResult`, `:80`) and has no reason to live inside the scoring task.
The methods that move together:

- `RunCalibration` (`:1581`)
- `RunCalibrationScoringPass` (`:1825`)
- `PreprocessWindowsForXcorr` (`:2012`)
- `CollectCalibrationPoints` (`:2100`)
- `AggregateMassCalibrations` (`:2157`)
- `SampleLibraryForCalibration` (`:2207`)
- `ScoreCalibrationEntry` (`:2377`, ~300 LOC)
- `ScorePeaksByCorrelation` (`:2677`)
- `CollectMs2FragmentErrors` (`:2720`)
- `ComputeMs1MassError` (`:2782`)
- the `CalibrationPassResult` private type (`:80`)

## Desired design

Move the cluster into a `Calibrator` collaborator (in `OspreySharp` or
`OspreySharp.Chromatography` — see open question) that `PerFileScoringTask`
constructs and calls. The task is left as clean orchestration:
**load → calibrate → score → persist**.

- `Calibrator` owns the calibration passes and returns an `RTCalibration` +
  mass-calibration result; `CalibrationPassResult` becomes its internal type.
- It takes its inputs (sampled library entries, spectra, config, tolerances) and
  an injected diagnostics sink (see `TODO-ospreysharp_diagnostics_di.md`) rather
  than reaching for statics or `_ctx`.
- `PerFileScoringTask` drops from 2,828 LOC toward ~1,600 LOC of readable
  orchestration; calibration becomes **independently testable**, which it is not
  today.

## Constraints (osprey)

- This is a **pure relocation** — byte-for-byte identical calibration output
  required. Calibration feeds RT prediction, which feeds scoring, so a drift here
  cascades into the feature vectors.
- Gate: the C#-side refactor regression on Stellar + Astral (expect exact for a
  clean move) -- the multi-file straight-through run reusing the cached Rust
  reference: `Compare-EndToEnd-Crossimpl.ps1 -Files All -SkipRust`, plus the
  pre-commit `Build-OspreySharp.ps1 -Configuration Debug -RunTests -RunInspection`.
  (Cached Rust reference must match the `-Files` set; no `-Force` with `-SkipRust`.)
- Preserve the calibration diagnostic-dump call order exactly (the Stage-cal dumps
  are bisection seams); the dumps move with the code.
- net8.0 canonical for parity. Do not loosen a gate to land it.
- Skyline conventions apply (no async/await, resource strings, `_camelCase`
  privates, CRLF, helpers after public methods).

## Open design questions

- Home for `Calibrator`: keep in the `OspreySharp` exe alongside the task, or
  promote to `OspreySharp.Chromatography` (which already houses `RTCalibration`,
  `MzCalibration`, `LoessRegression`, `CalibrationParams`)? Promotion gives a
  cleaner module boundary but widens what `Chromatography` must reference — check
  the dependency direction stays a DAG.
- Does the `s_calXcorrScorer` / `CAL_TOP_N_FRAGMENTS` calibration config
  (currently `internal` on `AbstractScoringTask`, `:67`/`:132`) move onto
  `Calibrator` too? Likely yes — it is calibration-only state.

## Relationship to sibling TODOs

- Do this **before** `TODO-ospreysharp_modular_scoring_context.md`: it shrinks the
  biggest file and removes a whole concern, making the (riskier) scoring
  decomposition easier to reason about.
- Pairs with `TODO-ospreysharp_diagnostics_di.md`: the extracted `Calibrator`
  should receive an injected diagnostics sink rather than calling the static class.
