# TODO-20261101_osprey_resume_validity.md

## Branch Information
- **Branch**: `Skyline/work/20261101_osprey_resume_validity` (worktree `D:\Dev\pwiz-resume`)
- **Base**: `master` (cut at 728ff3a131)
- **Created**: 2026-11-01
- **Status**: Completed
- **GitHub Issue**: [#4764](https://github.com/ProteoWizard/pwiz/issues/4764), [#4373](https://github.com/ProteoWizard/pwiz/issues/4373)
  (and the already-resolved [#4731](https://github.com/ProteoWizard/pwiz/issues/4731),
  [#4732](https://github.com/ProteoWizard/pwiz/issues/4732), [#4733](https://github.com/ProteoWizard/pwiz/issues/4733))
- **Module**: `osprey`
- **PR**: [#4959](https://github.com/ProteoWizard/pwiz/pull/4959) (merged 2026-11-03)

Folds in `todos/backlog/TODO-osprey_resume_validity_gates.md` (removed in the same pwiz-ai commit).

## Objective

Make Osprey resume refuse artifacts it should have invalidated: a build-version change and a
validity-key change must re-run the stage, never adopt; a pinned `OSPREY_VERSION_OVERRIDE` resume
(the `-LinkFrom` case) must still adopt; and the log must say when an artifact is rejected for its
build version, naming both versions.

## Finding at session start: most of the planned work already landed on master

The issues and the backlog TODO predate two merged PRs. Verified against the code at 728ff3a131:

| Item | State on master | Landed in |
|---|---|---|
| #4764 / #4373: version never compared | `ArtifactStamp.IsCurrent` compares task, version AND key; `TaskValiditySidecar` is deleted | #4809 (af30974a4a) |
| Backlog #2: `PerFileRescoreTask.Pass2SidecarCurrent` format-only, RefillOnly, driver re-stamp | Gone. `IsFileRescored` = reconciled parquet current (key) + `HasWorkerStamp`; the driver writes nothing | #4809 |
| Backlog #3: transfer-mode `recomputed` gate in `Pass2FdrSidecar` | Gone. `RequireWorkerAnswers` stamp-checks every run before any fold, in every pass-2 mode; Stage 7 writes no per-run file | #4809, #4665 |
| Backlog: `TrainingExportWriter.RunQPath` on presence only | `HasWorkerStamp` requires sidecar, plan and (protein-compact) decoys to carry the reconciled parquet's exact stamp | #4809 |
| #4731: driver stamps outputs another task wrote | `AnalysisPipeline.WriteTaskSidecars` deleted; stamps are written inside each artifact by its writer | #4809 |
| #4732: no-work run never writes `.2nd-pass.fdr_decoys.bin` | The worker answers every run, including the no-work one (`WritePass2Answer` after `WriteUnchangedReconciled`) | #4665 |
| #4733: every sidecar lists every run's inputs | The `inputs` list no longer exists (stamps are `task;version;key`); `OspreyTask.OutputInputs` removed as dead | #4809 |

Still missing, and the substance of this branch:
- The log is silent when an artifact is rejected for its build version. A resume after a build day
  re-runs hours of work with nothing saying why (the issue's main operator complaint).
- `OspreyVersion.Current` is `static readonly`, so `OSPREY_VERSION_OVERRIDE` cannot be exercised
  in-process; no `SubsetPipelineTest` covers a cross-build resume or a pinned one, and none covers a
  validity-key change in one output directory.
- Stale comment in `TrainingExportWriter.RunQPath` (still describes the pre-#4665 no-work path).

Decision (no Brendan available): ONE PR instead of two. PR 2's three issues need no code; a
second, test-only PR would cost a review and a TeamCity round for nothing. The one-run no-work
re-run assertion for #4732 goes into this PR. Issues #4731/#4732/#4733 are listed in the PR body as
resolved by #4809/#4665 and left for Brendan to close (not auto-closed by this PR).

Not doing (backlog "Not doing #1", unchanged): the `--task` join validates scores parquets by
footer version/hashes only; a fix needs a footer marker mirrored in Rust.

## Tasks

- [x] `OspreyVersion.Current` / `InformationalVersion` read the override through
      `OspreyEnvironment`'s test-override seam (assembly version cached), so a test can pin it
- [x] Driver logs a version rejection: before a task runs, if any declared output carries this
      task's stamp from another build, warn naming both versions and `OSPREY_VERSION_OVERRIDE`
      (`OspreyPipelineDriver.WarnOtherBuildOutputs`, AnalysisPipeline.cs; resource in OspreyResources)
- [x] Fix `RunQPath` comment
- [x] SubsetPipelineTest: key change in one directory re-runs (not adopts) and returns to the
      straight-through library; another build's artifacts re-run with the warning; pinned
      version adopts; one-run no-work analysis re-run skips every task (#4732)
      (`AssertKeyChangeRecomputes`, `AssertOtherBuildRecomputes` at the end of
      `TestSubsetStraightThroughAndReruns`, 8 s total; `TestSubsetTrainingExportSingleRun`)
- [x] Build-Osprey -RunTests -RunInspection (Debug): 646/646, inspection 0 warnings
      (log `ai/.tmp/sessions/20261101-resume/gate1.log`); committed 5f1daeb4ee
- [x] regression.ps1 -Dataset Stellar PASSED (498 s of phases; slow because three other agents
      shared the box) and -Dataset StellarLibDecoy PASSED (mode 2, mode 3 HPC chain included;
      1923 s), both on 5f1daeb4ee. Logs `ai/.tmp/sessions/20261101-resume/regr-stellar.log`,
      `regr-libdecoy.log`
- [x] Code review, medium. NOTE: the `/code-review` skill could not be used: this session's cwd
      is pinned to C:\proj\ai (the worktree is outside the session's working directories) and
      `Deny-CodeReviewInAiRepo.ps1` correctly blocks it there. Ran an unanchored general-purpose
      review agent on `git -C D:/Dev/pwiz-resume diff origin/master...HEAD` instead. Triage:
  - FIXED: the warning counted outputs whose KEY also differed and advised a pin that would
    reuse nothing (and then stamp recomputed files with a version that did not write them);
    now counts only outputs current for this task and key under another version, one line per
    earlier version
  - DROPPED: one extra stamp read per declared output when a task starts - only when the task is
    about to run (hours at scale), and the first not-current output already stops `CanRehydrate`
- [x] PR [#4959](https://github.com/ProteoWizard/pwiz/pull/4959) opened (commits 5f1daeb4ee,
      38c5e9684a). Re-ran regression.ps1 -Dataset Stellar on the final HEAD: PASSED
      (`regr-stellar2.log`). TeamCity Perf/Regression NOT triggered (Brendan's call).

## Next steps (for Brendan)
- Close #4731, #4732, #4733 as resolved by #4809/#4665 (the PR lists them; it does not auto-close them).
- No PR 2: its three issues needed no code. The planned branch
  `Skyline/work/20261101_osprey_sidecar_authorship` was not created.

## Progress Log

### 2026-11-01
- Read issues, backlog TODO, #4809's completed TODO; verified each item in code (table above).
- Implemented, gated (646/646, 0 inspection), committed 5f1daeb4ee; Stellar + StellarLibDecoy PASS.
- Review fix (key-aware warning) in a second commit after its own gate.

### 2026-11-03 - Merged

TeamCity Perf/Regression gate build #353 (4248192) passed on 38c5e9684a: all four datasets plus the
CarafeSharp pass. PR #4959 merged as commit d66538cb41. Shipped: the other-build warning with the
OSPREY_VERSION_OVERRIDE hint, the override seam, and the four resume test legs plus the
no-Stage-6-work assertion. Issues #4764 and #4373 closed by the merge; #4731, #4732 and #4733
closed by Brendan the same day on the evidence recorded above (#4809, #4665). Still not done, by
choice: the backlog's "Not doing #1" (the --task join validates scores parquets by footer only), and
same-day builds sharing a version string still reuse each other's outputs (#4764's residue).
