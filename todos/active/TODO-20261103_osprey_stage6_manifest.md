# TODO-20261103_osprey_stage6_manifest.md

## Branch Information
- **Branch**: `Skyline/work/20261103_osprey_stage6_manifest`
- **Base**: `master` (049d045e98)
- **Created**: 2026-11-03
- **Status**: In Progress - Step 1 measured; the work manifest (i) and the driver stamp (ii) are
  NOT built, because master no longer has the shape the issue describes (see Step 1). What is
  left to build is the shrinking-work-set key-change check (iii). Decision for Brendan: close
  #4601 once that lands, with (iv) as the design note below.
- **GitHub Issue**: [#4601](https://github.com/ProteoWizard/pwiz/issues/4601)
- **Module**: `osprey`
- **PR**: [#4985](https://github.com/ProteoWizard/pwiz/pull/4985)
- **Worktree**: `C:\proj\wt-manifest` (night-session agent E, round 2 of the backlog wave)

## Objective

Finish #4601 (Stage 6 completion encoded as a missing file) and fold in the backlog TODO
`TODO-task_file_contract_from_declarations.md` (git rm'd in the same pwiz-ai commit as this file).

## Step 1 - measured against 049d045e98

### Backlog TODO (task file contract) - all delivered by #4898 and earlier

| Task | State on master | Where |
|---|---|---|
| 1. per-file vs join | done, as `IsPerFileWorker` | `Osprey.Tasks/OspreyTask.cs:87`, overrides in `PerFileScoringTask.cs:99`, `PerFileRescoreTask.cs:165`, `SpectraCacheTask.cs:63` |
| 2. print the contract | done, as `--task-files` (not `--help-files`) | `Osprey/Program.cs:790` (`PrintTaskFiles`) |
| 3. stage from declarations | done in both harnesses, missing declared input fails | `regression.ps1:1865` (`Get-DeclaredTaskFiles`), `ai/scripts/Osprey/Common/OspreyDatasetRun.psm1:827-884` (`-LinkFrom`) |
| 4. audit `<each>.calibration.json` on SecondPassFDR | done: no longer declared, with the reason | `SecondPassFdrTask.cs:146-150` |
| 4. audit `<each>.reconciliation.json` on SecondPassFDR | still declared, and correctly: READ on the default path | see below |
| wrinkle: model.json per-file name, analysis-wide content | done: `<blib-stem>.1st-pass.model.json` + `.1st-pass.stratum.json`, one each per analysis | `FirstPassModelIO.cs:61-80` |
| wrinkle: 0-byte mzML stubs | not re-measured (out of this item's scope) | |

`<each>.reconciliation.json` is now PerFileRescoring's OUTPUT (`PerFileRescoreTask.cs:270-276`,
since #4863 moved planning onto the worker) and SecondPassFDR reads it on every run:
`Pass2FdrSidecar.RequireWorkerAnswers` -> `HasWorkerStamp` requires its stamp to match the
reconciled parquet's (`Pass2FdrSidecar.cs:165`, `:484-498`), and `ReadWorkerContribution` loads
its gap-fill entry ids (`Pass2FdrSidecar.cs:649`, `:673-683`). The declaration is honest; nothing
to remove.

### #4601 checkboxes

| Checkbox | State | Evidence |
|---|---|---|
| Every Stage 6 unit positively declares completion, incl. no-work files | done (#4621/#4646, option (a)) | no-work run writes `WriteUnchangedReconciled` + its pass-2 answer, `PerFileRescoreTask.cs:1388-1400` |
| `AnyReconciledParquet` from the recorded fact | done (#4646) | issue comment 2026-09-18 |
| `EffectiveScoresPathFromScoresPath` re-sourced | done: the method is gone | no hits in `pwiz_tools/Osprey` |
| (i) Stage 5 publishes the Stage 6 work manifest | **premise gone; not built** | see below |
| (ii) driver stamps only outputs it produced | **closed by #4809** | see below |
| (iii) two-runs-one-directory shrinking-work-set check | **open - built here** | `SubsetPipelineTest.cs:1915-1933` covers a key change that does NOT shrink the set |
| (iv) option (b) sidecar-only attestation | design note below | |

**(i) The work manifest.** The issue's argument was that Stage 5 computes the Stage 6 work set
and discards it. Since #4863 it does not compute it. FirstPassFDR writes only the cross-run
reductions (`<blib-stem>.1st-pass.consensus.json`, `Stage6ConsensusFile.cs:52-60`: "This file
is what lets planning leave the join"), and each PerFileRescoring worker plans its own run from
them: multi-charge consensus, reconciliation actions and gap-fill are all assembled in
`TryAssembleRescoreTargets` from that run's survivors (`PerFileRescoreTask.cs:1890-1903`). The
work set is first known on the worker. And the scheduling payoff the manifest was for is gone
too: since #4665 every run, work or no work, gets its reconciled parquet and its 2nd-pass answer
from the worker (`PerFileRescoreTask.cs:1388-1400`), so the Stage 6 fan-out is every run
regardless. A manifest written by FirstPassFDR would mean moving per-run planning back onto the
join node (the cost #4863 removed) to publish a set no scheduler can use to skip a node.
Conservative call: not built. If an informational per-run "had work" fact is ever wanted, the
right writer is the worker (a footer fact beside `osprey.rescored`), not the join.

**(ii) The driver stamp.** `AnalysisPipeline.WriteTaskSidecars` no longer exists: #4809 replaced
the `.osprey.task` sidecars with a stamp embedded in each artifact by the code that writes it.
The driver only READS stamps (`TaskContext.CanRehydrate`, `Shared/CommonUtil/Pipeline/TaskContext.cs:283-295`;
`AnalysisPipeline.WarnOtherBuildOutputs`, `Osprey/AnalysisPipeline.cs:226-252`), and `OnStarting`
clears nothing (`:162-170`). A file this run did not write keeps the stamp it was written
under, so channel A's step 3 cannot happen.

**(iii) The check.** `AssertKeyChangeRecomputes` (#4764) flips `OSPREY_PASS2_QVALUE`, which
rewrites every run and leaves the work set unchanged - the issue's own example of a safe key
change. Nothing runs the dangerous shape: same directory, PerFileRescoring key changed, fewer
runs with Stage 6 work.

**Where the check goes.** The brief asked for an opt-in `regression.ps1` mode. Not done there:
`regression.ps1`'s header (lines 8-24) and the osprey-development skill both put pipeline
behavior (resume, validity keys, which files a run writes) in `SubsetPipelineTest`, and #4728
moved such legs out. The check is a subset-test step instead: on every commit, in seconds, with
no TeamCity change. Brendan may revisit.

## Tasks

- [x] Step 1 measurement (above)
- [x] Subset check: same-directory key change that shrinks the Stage 6 work set, blib equal to a
      clean-directory run under the same key, then a warm re-run adopts everything
- [x] Build-Osprey Debug -RunTests -RunInspection: 649 passed, inspection clean
      (`C:\proj\ai\.tmp\sessions\20261103-agentE\precommit2.log`, after the review fixes)
- [x] regression.ps1 -Dataset Stellar and -Dataset StellarLibDecoy: both PASSED, goldens unchanged
      (`...\20261103-agentE\regression-Stellar.log`, `regression-StellarLibDecoy.log`; Release built
      from 057b91bff4 - the review-fix commit after it touches only the test file)
- [x] /code-review medium, triage (below)
- [x] PR #4985 opened; TeamCity Perf/Regression not triggered (the parent session queues it)

## Left open (not this item)

- The straight-path-global vs worker-per-file compaction risk folded into #4601 from #4597 was
  not re-measured here.
- The 0-byte mzML stub wrinkle from the backlog TODO was not re-measured.

## Design note: option (b), sidecar-only attestation

What (b) would buy now: a no-work run's `.scores-reconciled.parquet` is a full copy of its Stage
4 parquet (`WriteUnchangedReconciled`), so (b) saves that copy's disk and stage-in bytes. It no
longer saves a node: the run still needs its 2nd-pass answer from the worker (#4665). Cost: Stage
7 and `--task SecondPassFDR` read one artifact per run today (`<stem>.scores-reconciled.parquet`,
#4486); (b) puts the Stage 4 parquet back on SecondPassFDR's input list for those runs and needs
a stamped attestation (the reconciliation.json already carries the worker's stamp and is read by
`HasWorkerStamp`, so it is the natural carrier: an empty plan under the current stamp is the
attestation). Not worth doing until a cohort's duplicated no-work parquets are measured to
matter; all four regression datasets have work in every run.

## What was built

`SubsetPipelineTest.TestSubsetStraightThroughAndReruns` gains a last step,
`AssertShrinkingWorkSetRecomputes`: the finished three-run directory is searched again with run
`_20` alone. That changes every post-scoring key (the reconciliation hash covers the input stems)
and leaves `_20` with no Stage 6 work, where the three-run analysis re-scored it. Asserts: `_20`
had work before; none after; its reconciled parquet was re-stamped under the new key; the library
equals a clean directory's one-run library; a warm re-run adopts every task and leaves the blib
byte-identical (the third run in the directory, where channel A used to stick).

First tried `--run-fdr 0.001` as the shrinking key: on the subset it removed every detection
(no blib) without shrinking the work set, so the input-set change is the knob.

Mutation check: with `WriteUnchangedReconciled` changed to keep any EXISTING reconciled parquet
(the issue's existence-only adoption), the step fails - the one-run search stops with a pass-2
pool-size mismatch against the stale parquet. Log:
`C:\proj\ai\.tmp\sessions\20261103-agentE\test-mutation.log`. Reverted.

## Review (/code-review medium) triage

- Fixed: precondition counted re-scored runs of any kind, not `_20` itself -> now looks for `_20`
  in the "Re-scoring file" line of the full analysis.
- Fixed: the no-work assertion now says the setup stopped being the no-work case, and the doc
  comment no longer claims the consensus is cross-run only (multi-charge consensus is per run).
- Fixed: asserts the reconciled parquet's stamp key changed, not only the blib.
- Fixed: the keyed task list shared by both key-change steps is one `KEYED_TASKS` field.
- Dropped: "remove the warm re-run as redundant with mode 4" - it is the third run under the new
  key, which is exactly where the issue's channel A made a stale file durable; mode 4 never
  follows a key change.

## Progress Log

### 2026-11-03 - Step 1
- Measured the backlog TODO and #4601 against 049d045e98 (tables above). Two of the four
  expected open items are not open; one is built here.
- Built `AssertShrinkingWorkSetRecomputes`, mutation-checked it, ran the gates, reviewed.
  Commits 057b91bff4, fcb179d980.
