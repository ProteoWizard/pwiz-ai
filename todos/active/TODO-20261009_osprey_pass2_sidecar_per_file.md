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

## Regression Test

- **Test name**: (filled in once written) - `SubsetPipelineTest` transfer arm: assert PerFileRescoring wrote every run's sidecar (stamp names the producer)
- **Test project**: Osprey tests
- **Fails on master**: (pending)
- **Passes on fix**: (pending)

Protein-compact no-work case needs a constructed subset where one run gets no
consensus, reconciliation or gap-fill targets.

At-scale endpoint: a 446-run transfer run (precedent: 82-file SEA-AD transfer arm,
PR #4508).

## Progress Log

### 2026-10-09 - Session Start

Starting work on this issue from master af30974a4a. Starting points listed in the
second issue comment.
