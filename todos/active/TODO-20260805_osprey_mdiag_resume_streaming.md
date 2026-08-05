# TODO-20260805_osprey_mdiag_resume_streaming.md

## Branch Information
- **Branch**: `Skyline/work/20260805_osprey_mdiag_resume_streaming`
- **Base**: `master` (at `b554ce6f0d`, i.e. after #4530)
- **Created**: 2026-08-05
- **Status**: In Progress
- **GitHub Issue**: [#4505](https://github.com/ProteoWizard/pwiz/issues/4505)
- **Module**: `osprey`
- **PR**: (pending)

## Problem

`--model-diagnostics` on a FULL resume was the last mdiag path that forced the O(files)
resident first-pass pool. When every `<stem>.1st-pass.fdr_scores.bin` is on disk, FirstJoin
skips its score pass, so `ModelDiagnosticsData.Accumulator` was never fed and the report fell
back to the batch `ModelDiagnosticsReport.Write`, which reads the RESIDENT per-file entries.

The gate armed it explicitly:

```csharp
bool mdiagFullResume = config.ModelDiagnostics && FirstPassSidecarsPresent(config);
bool needsResidentPool = NeedsResidentPool(config) || mdiagFullResume;
```

This was NOT the scale case - #4420 streamed mdiag off the projection path, so straight-through
and `-LinkFrom` runs already needed no opt-in. Only the full-resume batch report remained, and
it was the LAST blanket-hatch dependency in the standing `regression.ps1` gate.

## Fix

`FirstJoinTask.WriteModelDiagnosticsFromSidecars`: on a resume with no accumulator, stream each
file's 1st-pass sidecar (score + q-values, in stored row order) joined with its parquet scalars
(entry_id / charge / is_decoy / modseq, same row order) into the SAME
`ModelDiagnosticsData.Accumulator` the projection path uses, then render through
`WriteFromAccumulator`. The sidecar carries the same per-row score + q the overlay would have
assigned each stub, so the report is the same reduction without the pool.

Then drop `--model-diagnostics` from the Stage-5 resident-pool gate, and with it:

* `ResidentPaths.MDIAG_FULL_RESUME` - **the ratchet SHRINKS**, which is the direction it is
  allowed to move. Five tokens to four (plus `compacted-entries-buffer` from #4530).
* the `mdiagFullResume` parameter threaded through `GuardResidentPool` /
  `ResidentPoolGuardError` / `ResidentPoolTrigger`, and the now-unused
  `FirstPassSidecarsPresent` helper.
* **`regression.ps1` mode 2's scoped opt-in.** The standing gate now runs end to end with NO
  memory hatch set anywhere. Leaving it unset is the point: a scoped opt-in would mask exactly
  the regression this leg is best placed to catch.

### The prerequisite the issue flagged, resolved

#4505 called out "verify the `FirstJoin.Rehydrate` lean-stub question first". Answer: the lean
resume path is ALREADY the default for every resume that is not mdiag, so making mdiag lean
puts it on a well-trodden path rather than a new one. The fat pool existed solely to feed the
mdiag batch write, which the streamer replaces.

### Recovered, not reinvented

The approach is the one parked on the closed #4437 branch (`bb7ee88e99`), which was closed
UNMERGED because its main subject - the transfer score->q table - was superseded by #4438. The
patch no longer applied (2.5 weeks of drift plus #4484, #4528 and #4530 rewrote `FirstJoinTask`),
so this is a PORT, not a cherry-pick. Two API drifts fixed: `BuildModelDiagnosticsAccumulator`
now takes `libraryById` + `logInfo`, and `ResolveSidecarBasePath` moved to `ScoringTaskShared`
in #4530. The Copilot-review improvement from that branch is kept: a per-file row-count
mismatch is skipped with a warning BEFORE any of its rows reach the shared accumulator, so one
bad file corrupts neither the report nor the remaining files.

## Regression Test

- **Test name**: `ResidentPoolGuardTest` (updated - pins the shrunken token list and that mdiag
  is no longer a trigger); byte parity via `regression.ps1`
- **Fails on master**: n/a - this removes a trigger rather than fixing a wrong value
- **Passes on fix**: 574/574, zero inspections

The real gate is `regression.ps1`: mode 2 IS the `--model-diagnostics` full-resume leg, and it
now runs with no opt-in. `-Dataset All` mode1b compares the mdiag report itself against a
golden, which is the direct byte-identity check for this change.

## Progress Log

### 2026-08-05 - Implemented

Ported the streamer, dropped the gate/token/hatch. `regression.ps1 -Dataset Stellar`: all five
legs PASS with the exact golden blib and NO hatch set - previously mode 2 could not run without
naming `mdiag-full-resume`.
