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

- **Test name**: `regression.ps1` **mode 5** ("Stage-5 rehydrate self-consistency")
  plus `AssertBatchOverlayRejectsLeanStubs` in
  `IOTest.TestRescoreHydrationStreamingMatchesResidentCompaction`
- **Test project**: `pwiz_tools/Osprey/regression.ps1` + Osprey.Test
- **Fails on master**: YES - verified before any C# change, on `Stellar`:
  `Osprey exited 1`, `HydrateReconciliationOverlay: failed to overlay
  .1st-pass.fdr_scores.bin for Ste-2024-12-02_HeLa_4mz_sDIA_400-900_20`.
  Log: `ai/.tmp/mode5-master-red.log`
- **Passes on fix**: YES on `Stellar` - `mode5 (rehydrate entered + cache hits): PASS`,
  `mode5 (rehydrate==straight): PASS`, and every pre-existing leg still green
  (mode1 / mode2 / mode3 / mode4). Log: `ai/.tmp/mode5-fix-green.log`.
  `-Dataset All` (which is where the mdiag datasets live - Stellar has
  `ModelDiagnostics = $false`) pending.

Mode 5 invalidates ONLY the SecondPassFDR task (`Invoke-SecondPassOnlyInvalidation`: the blib +
its `SecondPassFDR` stamp), which is the one state that enters
`FirstJoinTask.Rehydrate`. It asserts the rehydrate marker line, the blib against
the pristine straight-through one at 1e-9, and the re-emitted mdiag report against
the same golden mode 1b uses - with **no** `OSPREY_ALLOW_UNFIXED_RESIDENT` opt-in.

## Findings

### The bug is bigger than the issue describes: this path is broken today, mdiag or not

Running mode 5 on unmodified master fails on **Stellar**, which has
`ModelDiagnostics = $false`. So `FirstJoin.Rehydrate` is broken for EVERY lean
resume, not just mdiag ones:

* Stage 5 takes the lean load unless `NeedsResidentPool`, publishing one EMPTY
  stub list per scored file (`PerFileScoringTask.cs:728`).
* `LoadOwnReconciliationBundle` handed those to the batch
  `HydrateReconciliationOverlay`, whose `FdrScoresSidecar.TryRead` superset
  contract cannot be met by a list of zero entries -> `InvalidDataException`,
  `ExitCode=1`.
* `--model-diagnostics` was the only thing that ever made this work, and only by
  accident: `mdiagFullResume` forced the RESIDENT pool, which happened to give the
  overlay real stubs. Removing that term without fixing the overlay is exactly why
  attempt 1 hard-failed (issue comment, finding 2).

No leg of the standing gate reached it: mode 2 deletes the `FirstPassFDR` stamp so
FirstJoin RUNS, and mode 4 invalidates nothing so nothing demands FirstJoin's
state. That is the coverage hole mode 5 closes.

### Fix

`LoadOwnReconciliationBundle` now picks the hydrate from what upstream actually
loaded (zero resident stubs across all files == the lean load's signature) and
routes the lean case through `HydrateCompactedStreaming`, loading each file's stubs
from its own parquet and feeding the mdiag accumulator + passing-target tally from
the per-file hook that already reads every sidecar. No second join, no second I/O
pass, no `resumeFromSidecars` flag - the design the attempt-1 review recommended.

## Progress Log

### 2026-08-05 - Session Start

Starting work on this issue. Attempt 2, after PR #4533 was closed unmerged.
Branch created from master @ `df3e43364c`.

### 2026-08-05 - Test red on master, fix in

1. Added `Invoke-SecondPassOnlyInvalidation` (Regression/RegressionData.ps1),
   `Test-LogMarker` + mode 5 (regression.ps1). Ran on master: RED, with the exact
   `InvalidDataException` above.
2. `FirstJoinTask.LoadOwnReconciliationBundle` + new
   `StreamOwnReconciliationBundle`; `TallyPreCompaction` / `FeedModelDiagnostics`
   moved to `ScoringTaskShared` (both hydrate callers share them now).
3. Dropped `mdiagFullResume` from the Stage-5 gate, the guard, and
   `ResidentPoolTrigger`; removed `MDIAG_FULL_RESUME` from
   `ResidentPaths.KNOWN_UNFIXED` (the ratchet shrinking).
4. Removed the `OSPREY_ALLOW_UNFIXED_RESIDENT=mdiag-full-resume` opt-in from
   regression.ps1 mode 2 - the gate now sets it on NO leg.
5. Skipped the OSPREY_DUMP_PERCOLATOR Stage 5 dump (with a warning naming the
   reason) when the hydrate streamed, so it cannot emit post-compaction survivors
   under a name that means pre-compaction.
6. `Build-Osprey -RunTests -RunInspection`: 575/575, zero inspections.

### 2026-08-05 - Stellar green, then `-Dataset All` found one real discrepancy

`-Dataset Stellar`: every leg PASS, including both new mode-5 assertions.

`-Dataset All` (the mdiag datasets - Stellar has `ModelDiagnostics = $false`):
mode 5's blib and cache-hit assertions PASS on all four datasets, and the mdiag
comparison flagged exactly ONE metric on each mdiag dataset:

```
diagnostics: featureCount golden=21 run=0 diff=2.100e+001 (tol 1e-009)
```

Everything else the report carries - `nTarget`, `nDecoy`, `fileCount`,
`densityRatio.*`, `winFraction.*`, and pass-1 AND pass-2 `experiment` FDP /
accepted / entrapmentRatio at the reported q - matched the straight-through
golden at 1e-9. That is the streamed accumulator reproducing the resident
reduction row for row.

`featureCount` is **pre-existing resume behavior, not a property of the streamed
report**, verified in source rather than assumed:

* `FirstJoin.Rehydrate` passes `contributions: null` to
  `LogFirstPassResultsAndDump` - unchanged by this branch (it is context, not a
  `+` line, in the diff).
* Both `ModelDiagnosticsData.Build` (batch) and
  `ModelDiagnosticsData.Accumulator.Build` (streaming) build the model table
  ONLY from `contributions` and leave it empty when it is null. The
  accumulator's own doc says "null on a non-Percolator / rehydrated run -> no
  Model tab".
* So master's resident mdiag full resume produced `featureCount=0` too. A resume
  adopts q-values from the sidecars and never trains Percolator, so there are no
  feature contributions to report and none are persisted anywhere.

Encoded rather than excluded: `Compare-DiagnosticsGolden -NoTrainedModel` PINS
`featureCount` at 0 instead of skipping it, so the comparison stays total - a
straight-through report that lost its feature view would still fail mode 1b, and
a rehydrate that somehow claimed one would fail mode 5.

### 2026-08-05 - `-Dataset All` fully green

`Osprey regression PASSED` - all four datasets, every leg, with
`OSPREY_ALLOW_UNFIXED_RESIDENT` set on NO leg (mode 2's opt-in is gone and
nothing replaced it). Log: `ai/.tmp/mode5-all-green2.log`.

Both new mode-5 assertions pass on all four datasets, and the mdiag comparison
passes on the three that have `ModelDiagnostics` (StellarLibDecoy,
StellarGenDecoyEntrap, Astral). Every pre-existing leg still green.

Gates: `Build-Osprey -RunTests -RunInspection` 575/575 + zero inspections;
`regression.ps1 -Dataset All` PASSED.

### 2026-08-06 - `/code-review max`: 15 findings, all verified, all addressed

Every finding was reproduced or refuted against the code before acting. **All 15
were correct**, including two factual errors in prose written on this branch. Two
were verified by EXECUTION rather than reading:

1. **`-NoTrainedModel`'s failure branch was broken.**
   `$issues.Add(("...") -f $name, $f)` parses as a TWO-argument call (`-f` binds
   tighter than the argument comma), so it threw instead of recording the issue.
   Under `$ErrorActionPreference='Stop'` that escapes into regression.ps1's outer
   catch, which is deliberately NOT per-dataset - the WHOLE gate aborts and every
   remaining dataset is skipped. It fires only when `featureCount != 0`, i.e. the
   exact regression the pin exists to catch, which is why three green runs never
   touched it. Fixed with double parens; re-executed to confirm.
2. **`Invoke-SecondPassOnlyInvalidation`'s guard.** `if (-not $targets)` catches
   only a TOTAL miss; one match is a truthy scalar. Now `$targets.Count -lt 2`,
   exercised through all three arms (0 / 1 / 2 files). While fixing it I
   introduced the SAME format-argument bug in the new message and caught it by
   executing rather than eyeballing.

Structural fixes:

* **Mode 5 moved AFTER mode 2.** Its merge rewrites the 2nd-pass sidecars and the
  diagnostics report, not just the blib, and `Invoke-ResumeInvalidation` deletes
  none of them - so the original placement left mode 2 resuming on mode-5 state
  and made mode 2's oracle depend on `-SkipRehydrate`.
* **The marker witnessed the wrong thing.** `Bundle hydration: skipping
  first-pass Percolator` is logged before the bundle SOURCE is known, so a worker
  bundle emits it too, and mode 3's PerFileRescoring phase enters the rehydrate
  arm as well - so "no other leg reaches that arm" was wrong. Mode 5 now asserts
  a line emitted from INSIDE `LoadOwnReconciliationBundle`, and the docs claim
  only that it is the sole leg reaching that LOADER.
* **The documented invariant is now enforced**: regression.ps1 CLEARS an
  inherited `OSPREY_ALLOW_UNFIXED_RESIDENT` at startup (announcing it) instead of
  merely not setting it.
* Parquet faults wrapped to honor the documented error contract; the destructive
  `Clear()` on the published buffer replaced with hydrate-into-local-then-swap;
  a per-index key check so accumulator/rescore key divergence cannot be silent;
  `OSPREY_PERCOLATOR_ONLY` no longer exits 0 having written no dump; the guard
  test now sweeps every legal token so it tracks re-arming rather than spelling.

Pushed back / deferred, with reasons recorded in the code:

* **Stage 6 resident handoff** - real, but pre-existing for the mdiag resume;
  this change widens which runs reach it. Refusing would break a configuration
  that worked before, so it WARNS naming the consumer (matching
  `WarnPreCompactionPool`'s precedent) and the guard's now-false justification
  comment is corrected. Belongs to #4526.
* **Double parquet read on a lean resume** - real. Documented in
  `StreamOwnReconciliationBundle` with the tradeoff stated: one extra sequential
  scan per file buys the O(files) -> O(1-file) pool. Removing it means making the
  Stage 5 lean load lazy about work only `Run` consumes - a separate change.

Re-verified after the fixes: `Build-Osprey -RunTests -RunInspection` 575/575 +
zero inspections; all three PowerShell files parse; `regression.ps1 -Dataset All`
**PASSED** (log: `ai/.tmp/mode5-postreview.log`), with the summary confirming the
new mode 2 -> mode 5 ordering.

### 2026-08-06 - Token required, not just warned; dedicated token, not borrowed

Brendan's rule, now recorded in ai/docs/osprey-development-guide.md:

* **token + warning = good** - the token is the operator's explicit request, the
  warning explains what was granted
* **warning alone on a default path = INSUFFICIENT** - there is no request to
  explain, so it annotates a defect instead of mitigating one
* **a token admits exactly ONE path - never borrow one**
* any token `regression.ps1` REQUIRES must have an open issue to remove it

So the Stage 6 resume handoff is now REFUSED unless named, not merely warned
about: new `PerFileScoringTask.ResumeResidentHandoffGuardError`, called from
`FirstJoin.Rehydrate` BEFORE the expensive load and only on the own-bundle branch
(a worker bundle carries one worker's files, not the all-files buffer).

**The borrowing catch.** The first cut reused `compacted-entries-buffer`, which
names the SAME physical buffer. Brendan caught it: that token also admits
`OSPREY_STAGE6_STREAM_SURVIVORS=0` on the computed path, which #4530 already
FIXED - so any leg naming it to admit this unfixed resume would simultaneously
re-open a closed regression. Now `RESUME_SURVIVOR_HANDOFF` /
`resume-survivor-handoff`, its own token, with the asymmetry pinned in both
directions in `ResidentPoolGuardTest`.

Adding to `KNOWN_UNFIXED` is allowed here under the class's own rule: it names a
path that was previously unnamed AND unguarded, not one that had been fixed -
the same justification `COMPACTED_ENTRIES_BUFFER` used.

`regression.ps1` also prints its outstanding gaps in every run summary, so the
one remaining entry is visible on every GREEN run rather than only in source.

Verified: `Build-Osprey -RunTests -RunInspection` 575/575 + zero inspections;
`regression.ps1 -Dataset All` **PASSED** (log: `ai/.tmp/mode5-token.log`), with
the inventory printing `#4536  token: resume-survivor-handoff`.

**Next**: re-run `/code-review max` (the diff grew ~250 lines of NEW code since
the first review - the guard, the token, the gate inventory - and it is all
failure-path code that green runs never execute), fold findings, then open the PR
with `--label osprey`, title prefixed `osprey:`, and `Fixes #4505`. Ask before
triggering the TeamCity Perf/Regression gate on `pull/<N>`.

Follow-ups filed: #4535 (rename task classes to their task Names), #4536 (Stage 6
resume survivor handoff).
