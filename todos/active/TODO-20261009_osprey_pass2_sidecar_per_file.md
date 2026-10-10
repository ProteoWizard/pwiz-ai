# PerFileRescoring always writes the per-run 2nd-pass FDR sidecar

## Branch Information
- **Branch**: `Skyline/work/20261009_osprey_pass2_sidecar_per_file`
- **Base**: `master` (af30974a4a, #4809)
- **Created**: 2026-10-09
- **Status**: In Progress
- **GitHub Issue**: [#4665](https://github.com/ProteoWizard/pwiz/issues/4665)
- **Module**: `osprey`
- **Other labels**: `performance`
- **PR**: (pending)

## Objective

Originally: move `Pass2FdrSidecar.TransferOneFile` into `Pass2PerFileWorker` so the
`OSPREY_PASS2_QVALUE=transfer` mode (and mean-best-N through it) stops needing the
whole survivor pool resident in Stage 7.

Widened (issue comment) to a rule: **PerFileRescoring always writes
`<stem>.2nd-pass.fdr_scores.bin`, in every pass-2 mode, and SecondPassFDR writes no
per-run files.**

## Tasks

### transfer
- [ ] `TryCreatePass2Worker` returns a worker for transfer, not only `Pass2ProteinCompact`
- [ ] Move `TransferOneFile` (driven from `TransferPerRunQ` in Stage 7) into `Pass2PerFileWorker`
- [ ] `Stage7StreamAdmittedBeforeRescore` / `CanStreamStage7Join` stop special-casing the pass-2 mode
- [ ] Remove the resident-pool guard's `streamingAvailable` exemption
- [ ] Experiment-q floor fold (#4664): fast path covers every mode; delete the pool fold

### protein-compact, runs with no rescore work
- [ ] `PerFileRescoreTask.RescoreOneFile` `!TryAssembleRescoreTargets` branch calls `CompeteStampAndWrite` after `WriteUnchangedReconciled`
- [ ] Remove `IsFileRescored`'s `osprey.rescored=0` exemption

### Deletions the rule allows
- [ ] `SecondPassFdrTask.Outputs` / `PerFileRescoreTask.Outputs`: per-run sidecar declared unconditionally on PerFileRescoring
- [ ] Stage 7's per-file write in `Pass2FdrSidecar` (`workerWroteFiles` / `writer.Write` branch)
- [ ] Worker-answered vs not split (`WorkerOwnedPass2Sidecars`, `HasWorkerStamp`, `answered=k/N`)
- [ ] `regression.ps1` known-resident table row
- [ ] `Osprey-workflow.html`: drop the per-run caveat on SecondPassFDR's "out: 4 files" tooltip

## Notes

At-scale endpoint: a 446-run transfer run (precedent: 82-file SEA-AD transfer arm,
PR #4508).

## Progress Log

### 2026-10-09 - Session Start

Starting work on this issue from master af30974a4a. Starting points listed in the
second issue comment.

### 2026-10-09 night - Implementation

Also fixes **#4729** (SecondPassFDR fails when Stage 6 re-scores nothing): its proposed
direction - judge currency by stamp, worker writes the answer for no-work runs, Stage 7 writes
no per-run file - is exactly this rule. The `peptide_fdr_pep` branch overlap was waved off
by Brendan (not relevant any more).

Done:
- `Pass2PerFileWorker` has a transfer mode (`TransferAndStamp`: reconciled features by
  score_index -> `TransferOneFile` -> records; no decoys file). Missing features / unreadable
  1st-pass sidecar are throws (were warnings in Stage 7).
- `PerFileRescoreTask`: `CreatePass2Worker` for every mode (throws on unusable model / missing
  stratum); no-work branch calls `WritePass2Answer`; `IsFileRescored` lost the
  `osprey.rescored=0` exemption; Outputs declare Pass2Path always, decoys protein-compact only.
- `Pass2FdrSidecar.ComputeAndPersist`: `RequireWorkerAnswers` (throws, names runs) then
  competition fold or new `ComputePass2TransferFold`; shared `WalkSurvivors` +
  `FoldAndPublishExperimentScope`. Deleted: anyRescoreWork/recompute gate, RestorePass1Scalars,
  ComputePass2Resident, TransferPerRunQ, BuildExperimentScope, WorkerOwnedPass2Sidecars, the
  resident write block, Pass2SidecarWriter writes/tallies, seeder `Seed`/unreadable list,
  `RecordsRescoreWork`, `AnyReconciledParquet`, the Stage 7 per-run source's first-pass overlay.
- `Stage7StreamAdmittedBeforeRescore`: mode term removed - transfer streams.
- `[PATH] second-pass-fold` is now `verify=on|off runs=N` (was `answered=k/N`); regression.ps1
  and SubsetPipelineTest updated. regression.ps1 known-resident table now empty.
- Program.cs refusal of `--training-export` under transfer removed (+ resource, test).
- Docs: 00, 12, 14, 15, DIVERGENCES (#8: no-work cohort now answered; Rust skips pass 2),
  Osprey-workflow.html tooltips.

Finding: the issue's "guard's streamingAvailable exemption" is the Stage 6 handoff guard
(`Stage6ResidentHandoffGuardError`), and it covers projection-off runs, not transfer - left as is.
Finding: the #4664 "pool fold" no longer exists on master (floors applied at source, #4522);
the transfer arm's equivalent was `BuildExperimentScope`, now deleted.

Semantics change (all-no-work cohort only): protein-compact now competes unchanged peaks per
run instead of crashing; Rust keeps pass-1 values there. Recorded in DIVERGENCES.md.

### 2026-10-10 00:31 - Validation

- Code review (medium): 9 findings, 7 fixed (4a20e9eb7f), 2 dropped (#4 unresolved feature
  = defect by construction; #5 unmatched key was already a stop under the default mode).
- regression-parallel.ps1 -Dataset All on ff0b2585df: **48 PASS / 0 FAIL / 0 SKIP**, 51 min
  (pwiz_tools/Osprey/TestResults/regression-lane-*-20261009_205621.log).
- SEA-AD 82-file transfer run (snapshot D:\test\osprey-runs\_bin\pr4665-ff0b2585df), run dir
  D:\test\osprey-runs\sea-ad\runs\seaad-82files-libdecoy-r1.0-transfer-pr4665-20261009_205031:
  3:41:06 total; `[PATH] second-pass-join: per-run runs=82`; SecondPassFDR **5:02, managed
  peak 6.7 GB, private 11.4 GB** (perfviz). Before: the 82-file transfer run of 2026-07-30
  peaked 49.0 GB private in Stage 7 TransferPerRunQ (~13 GB live). PerFileRescoring 67:39
  (worker transfer summary: 7,409,137 unchanged / 6,314,227 moved / 511,551 gap-fill).
  46,728 blib precursors.
- Test-PerfGate.ps1 -Dataset Stellar vs C:\proj\pwiz-perfbase (new worktree, detached at
  af30974a4a): **PASSED**, total -0.1% (2:03 -> 2:02), stage6 +3.5% median (+7.0/-1.1/+3.5,
  noise on 8.6 s), stage7 -3.3% (ai/.tmp/perf-gate/20261010-073217Z/verdict.md).
- Test-PerfGate.ps1 -Dataset Astral: **PASSED**, total -0.3% (7:31 -> 7:30), stage6 +0.2%
  (ai/.tmp/perf-gate/20261010-074753Z/verdict.md).
- New `TestSubsetHpcTaskChainTransfer` (fb0603b9d3): the four-task chain under transfer, phase 4
  shipped no first-pass file, equals the straight run (blib, both passes' sidecars, both
  experiment sidecars byte-identical). 650/650 tests, zero inspection warnings.
- Commits (local, not pushed): ff0b2585df, 4a20e9eb7f, 4a035cf0b2, fb0603b9d3. PR body draft:
  ai/.tmp/sessions/20261009-4665/pr-body.md.
- regression-parallel.ps1 -Dataset All on HEAD fb0603b9d3: **48 PASS / 0 FAIL / 0 SKIP**, 26 min.
- Next (needs Brendan): push the branch, open the PR (`osprey:` prefix, labels osprey + performance,
  Fixes #4665 and #4729), then the TeamCity Perf/Regression gate on pull/<N>.

## Regression Test

- **Test name**: `SubsetPipelineTest.TestSubsetOptionVariants` (transfer arm: `[PATH]
  second-pass-join: per-run` + every 2nd-pass sidecar stamped PerFileRescoring);
  `TestSubsetTrainingExportSingleRun` (no-work single-run analysis completes under both modes,
  osprey.rescored=0 asserted, sidecar from PerFileRescoring, export selects pass 2)
- **Test project**: Osprey.Test
- **Fails on master**: yes - `missing [PATH] second-pass-join: per-run`
  (ai/.tmp/sessions/20261009-4665/red-master.log); single-run hit the #4729 error on master
- **Passes on fix**: yes (tests-1.log 648/649 before the single-run rewrite; tests-2.log)
