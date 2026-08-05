# TODO: Decompose PerFileScoringTask.Run

**Status**: Completed
**Branch**: `Skyline/work/20260531_ospreysharp_decompose_perfilescoring`
**PR**: [#4256](https://github.com/ProteoWizard/pwiz/pull/4256) (merged 2026-05-31 as 85d9a3279e)
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
- [x] Copilot review addressed (`/pw-respond`) — 3 doc-accuracy nits
      (LoadJoinOnlyScores "skips Stages 1-4" → Stage 2-4; stale "side data not
      loaded" comment; Hydrate "throws" → InvalidDataException). Fixed in
      13a5bd18cf; all 3 threads resolved.
- [x] Fresh-context self-review addressed (`/pw-self-review`) — clean verdict,
      no defects. Confirmed log order, out-param/early-return ExitCode mapping,
      throws-propagation, caller threading, and complete ctx→_ctx substitution.
      Follow-up (swLibrary scope) is a non-issue: Stop() immediately followed
      the decoy block originally, so the timing span is identical.

## Follow-up (separate PR)

`PerFileScoringTask` also has large calibration methods —
`RunCalibrationScoringPass` (~480), `ScoreCalibrationEntry` (~410),
`RunCalibration` (~240) — queued as the next decomposition PR.

## Progress Log

### 2026-05-31 - Started (autonomous night session)

Branch off master @ 9eee47851f. Three helpers extracted as verbatim lifts;
Run reduced ~580→~220 lines.
