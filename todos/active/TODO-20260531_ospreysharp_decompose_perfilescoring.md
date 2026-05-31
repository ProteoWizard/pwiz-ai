# TODO: Decompose PerFileScoringTask.Run

**Status**: In Review
**Branch**: `Skyline/work/20260531_ospreysharp_decompose_perfilescoring`
**PR**: [#4256](https://github.com/ProteoWizard/pwiz/pull/4256)
**Date**: 2026-05-31

## Objective

Third of the OspreySharp Tasks-layer mega-methods (see backlog
`TODO-ospreysharp_task_layer_decomposition.md`): `PerFileScoringTask.Run`
(~580 lines — Stage 1 library load + decoy generation/pairing, then the
Stage 2-4 per-file scoring dispatch). Pure, behavior-preserving extraction,
proven bit-identical at the 1e-9 cross-impl gate.

## Approach

Verbatim lifts; the two with early-exit/`ExitCode` paths return `bool`:

- [x] `LoadLibraryAndDecoys` (bool, out fullLibrary) — Stage 1 library load +
      decoy gen/pairing; sets `_fullLibrary`/`_libraryById`; early exits
      (empty load, no library decoys, bad manifest, low pairing fraction).
- [x] `LoadJoinOnlyScores` (void) — `--input-scores` parquet stub/feature/cal
      load loop (throws InvalidDataException on hash/shape mismatch, as before).
- [x] `HydrateRescoreBundleIfPresent` (bool) — probe-the-disk reconciliation
      bundle hydration + PIN-feature clear.

`Run` drops from ~580 to ~220 lines. The existing helpers (ScoreOrLoadForFile,
ProcessFile, TryLoadStubsAndCalibration) are untouched.

## Verification

- [x] Pre-commit gate: `Build-OspreySharp.ps1 -RunInspection -RunTests` — Build OK, 345/347, inspection 0/0.
- [x] Regression gate (C#-only): precursor delta 0, Stage 7 + blib content 1e-9 PASS (C# wall 17:02). PR #4256.
- [ ] Copilot review addressed (`/pw-respond`).
- [ ] Fresh-context self-review addressed (`/pw-self-review`).

## Follow-up (separate PR)

`PerFileScoringTask` also has large calibration methods —
`RunCalibrationScoringPass` (~480), `ScoreCalibrationEntry` (~410),
`RunCalibration` (~240) — queued as the next decomposition PR.

## Progress Log

### 2026-05-31 - Started (autonomous night session)

Branch off master @ 9eee47851f. Three helpers extracted as verbatim lifts;
Run reduced ~580→~220 lines.
