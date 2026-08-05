# --model-diagnostics on a full resume still loads the O(files) resident first-pass pool

## Branch Information
- **Branch**: `Skyline/work/20260805_osprey_mdiag_resume_overlay`
- **Base**: `master`
- **Created**: 2026-08-05
- **Status**: In Progress
- **GitHub Issue**: [#4505](https://github.com/ProteoWizard/pwiz/issues/4505)
- **Module**: `osprey`
- **PR**: (pending)
- **Prior attempt**: PR #4533 (closed unmerged) - branch
  `Skyline/work/20260805_osprey_mdiag_resume_streaming` is kept on origin as a
  record of what NOT to do

## Objective

`--model-diagnostics` on a **full resume** is the one remaining mdiag path that
loads the O(files) resident first-pass pool. The trigger is the conjunction
`config.ModelDiagnostics && FirstPassSidecarsPresent(config)` in
`PerFileScoringTask.NeedsResidentPool`: when every
`<stem>.1st-pass.fdr_scores.bin` is already on disk, FirstJoin skips its
first-pass score pass, `ModelDiagnosticsData.Accumulator` is never fed, and the
report falls back to the batch `ModelDiagnosticsReport.Write`, which reads the
RESIDENT per-file entries.

This is the last blanket-hatch dependency in the standing gate:
`regression.ps1` mode 2 sets `OSPREY_ALLOW_UNBOUNDED_MEMORY=1` scoped to that
one leg.

## Constraints carried over from the failed attempt 1 (PR #4533)

Read the issue comment in full before writing code. The three that decide the design:

1. **#4437 is a design sketch, not a portable patch.** `FirstJoinTask` was
   rewritten by #4484, #4528, #4530. API drift:
   `BuildModelDiagnosticsAccumulator` now takes `libraryById` + `logInfo`;
   `ResolveSidecarBasePath` moved to `ScoringTaskShared`.
2. **Dropping mdiag from `needsResidentPool` alone HARD-FAILS the resume.** The
   lean loader publishes empty per-file stub lists
   (`PerFileScoringTask.cs:724`), and `FirstJoin.Rehydrate` ->
   `LoadOwnReconciliationBundle` -> `HydrateReconciliationOverlay` ->
   `OverlayFirstPassSidecar` -> `FdrScoresSidecar.TryRead` cannot meet its
   superset contract against 0 entries; `RescoreHydration.cs:562` throws
   `InvalidDataException`. The fix must make the resident stubs unnecessary for
   the **overlay**, not just for the report.
3. **The standing gate does not cover this path.** `Invoke-ResumeInvalidation`
   deletes the `*.FirstPassFDR.osprey.task` validity stamp, so FirstJoin RUNS
   instead of rehydrating (`regression.ps1:1133` asserts exactly that). A fully
   green `-Dataset All` run proved nothing last time.

## Recommended design (from the attempt-1 review's altitude finding)

Do NOT add a second parallel join. `RescoreHydration.HydrateCompactedStreaming`
already takes an `onStubsHydrated` callback that feeds the mdiag accumulator
(wired at `PerFileScoringTask.cs:1282-1293`). Give its batch twin
`HydrateReconciliationOverlay` the same hook: the accumulator is fed from the
pass that ALREADY reads every sidecar and parquet,
`bundle.ModelDiagnosticsAccumulator` gets set, and the existing
`if (mdiagAccumulator != null)` branch in `LogFirstPassResultsAndDump` handles
it. That removes the duplicate join, the second I/O pass, the
`resumeFromSidecars` flag, and the empty-stub problem in one move.

## Tasks

- [ ] Verify the current `Rehydrate` / `HydrateReconciliationOverlay` /
      `LogFirstPassResultsAndDump` shape on master (post #4484/#4528/#4530)
- [ ] **Write the failing regression coverage FIRST**: a test that actually
      reaches `FirstJoin.Rehydrate` with valid 1st-pass sidecars and
      `--model-diagnostics` (overlaps #4473)
- [ ] Add the `onStubsHydrated`-style hook to `HydrateReconciliationOverlay` and
      feed `ModelDiagnosticsData.Accumulator` from it
- [ ] Drop the `ModelDiagnostics && FirstPassSidecarsPresent` term from the
      Stage-5 resident-pool gate
- [ ] Join sidecar records to parquet rows by `entry_id` with subset tolerance
      (never by ordinal) - follow `StreamFirstPassFileScores`
      (`FirstJoinTask.cs:2301`)
- [ ] Do not seed `runNames` slots for skipped files (avoids a plausible-looking
      0 targets / 0 decoys page instead of a visible failure)
- [ ] Keep `ReadRecords`' one-record-resident contract - no whole-file
      `List<FdrScoreRecord>` materialization (~270 MB LOH/file)
- [ ] Verify byte-identical mdiag output resident-vs-streaming (`data.json`,
      `.html`, `.1st-pass.fdr_scores.bin`)
- [ ] Remove the `OSPREY_ALLOW_UNBOUNDED_MEMORY=1` scoping from `regression.ps1`
      mode 2 once the path is fixed and covered
- [ ] `Build-Osprey -RunTests -RunInspection` + `regression.ps1 -Dataset All`
- [ ] `/code-review max` before opening the PR

## Regression Test

- **Test name**: (filled in once written)
- **Test project**: Osprey.Test | regression.ps1 mode | other
- **Fails on master**: (pending)
- **Passes on fix**: (pending)

Attempt 1 shipped no test that reached `Rehydrate`, which is why a fully green
run was a false green. The test is the first deliverable on this branch, not the
last.

## Progress Log

### 2026-08-05 - Session Start

Starting work on this issue. Attempt 2, after PR #4533 was closed unmerged.
Branch created from master @ `df3e43364c`.
