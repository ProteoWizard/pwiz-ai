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

## Regression Test

- **Test name**: `SubsetPipelineTest.TestSubsetOptionVariants` (transfer arm: `[PATH]
  second-pass-join: per-run` + every 2nd-pass sidecar stamped PerFileRescoring);
  `TestSubsetTrainingExportSingleRun` (no-work single-run analysis completes under both modes,
  osprey.rescored=0 asserted, sidecar from PerFileRescoring, export selects pass 2)
- **Test project**: Osprey.Test
- **Fails on master**: yes - `missing [PATH] second-pass-join: per-run`
  (ai/.tmp/sessions/20261009-4665/red-master.log); single-run hit the #4729 error on master
- **Passes on fix**: yes (tests-1.log 648/649 before the single-run rewrite; tests-2.log)
