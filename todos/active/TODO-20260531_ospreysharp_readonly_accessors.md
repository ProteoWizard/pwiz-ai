# TODO: Tighten read-only PerFileScoringTask accessors (PR-A, limited)

**Status**: In Review
**Branch**: `Skyline/work/20260531_ospreysharp_readonly_accessors`
**PR**: [#4259](https://github.com/ProteoWizard/pwiz/pull/4259)
**Date**: 2026-05-31

## Objective

The deflated PR-A from the OspreySharp Tasks-layer cleanup
(`TODO-ospreysharp_task_layer_decomposition.md`): make state ownership explicit
on `PerFileScoringTask`'s producer accessors. NOT a freeze of the load-bearing
shared buffer — that idea was walked back (see the REVISED note in the program TODO).

## Scope (limited, by design)

- [x] `GetLibraryById`, `GetPerFileCalibrations`, `GetPerFileParquetPaths` →
      return `IReadOnly*` views (compiler now enforces no external mutation).
      Widened the consuming signatures to match: FirstJoinTask (PlanStage6,
      WriteFdrScoresSidecars, WriteReconciliationFiles, ResolveSidecarBasePath)
      and MergeNodeTask (WriteBlibOutput, WriteBlibFile).
- [x] Documented `_perFileEntries` / `GetPerFileEntries` as a **deliberately
      live, mutable, shared buffer** (Scoring produces → FirstJoin compacts →
      PerFileRescore overlays, all in place on one instance; no-copy is
      load-bearing). Explicit "do not freeze / do not copy."
- [x] `GetFullLibrary`: left `List<LibraryEntry>` with a doc note — read-only by
      contract, but tightening to `IReadOnlyList` cascades across the scoring
      engine + FDR project (RunCoelutionScoring/RunFdr/ProteinFdr/...); deferred
      to a future cross-project sweep, out of proportion to this PR's value.
- [x] Left genuinely-mutating internal uses concrete: `LoadJoinOnlyScores`
      (builds the parquet-paths dict) and `BuildBasicFeatures` (a local dict).

## Verification

- [x] Pre-commit gate: `Build-OspreySharp.ps1 -RunInspection -RunTests` — Build OK, 345/347, inspection 0/0. PR #4259.
- [ ] Copilot review addressed (`/pw-respond`).
- [ ] Fresh-context self-review addressed (`/pw-self-review`).

**No regression gate:** this is a pure type-widening (`Dictionary` → the
`IReadOnly*` interface the concrete types already implement) + comments. The same
instances flow at runtime with identical member dispatch — there is no behavioral
surface for the 1e-9 cross-impl gate to exercise. Build + inspection + 345/347
unit tests is the complete proof.

## Progress Log

### 2026-05-31 - Started (continuation; PR-B + calibration methods already merged #4254-#4258)

Branch off master @ 84e497f356. Three dictionary accessors tightened; cascade
widened via compiler-driven discovery; ownership documented.
