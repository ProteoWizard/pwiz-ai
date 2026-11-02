# TODO-20261101_osprey_4542_findings.md

## Branch Information
- **Branch**: `Skyline/work/20261101_osprey_4542_findings` (worktree `D:\Dev\pwiz-triage`)
- **Base**: `master` (728ff3a131)
- **Created**: 2026-11-01
- **Status**: In Progress
- **GitHub Issue**: [#4542](https://github.com/ProteoWizard/pwiz/issues/4542)
- **Module**: `osprey`
- **PR**: (pending)

## Objective

Classify the twelve leftover `/code-review max` findings in #4542 (against #4537, mdiag resume
streaming and regression mode 5) against master 728ff3a131 and fix what is still live.

## Classification

| # | Finding | Status | Evidence / action |
|---|---|---|---|
| 1 | Null diagnostics accumulator falls back to the batch report over the compacted pool | Already fixed | #4830 removed `LogFirstPassResultsAndReport` and the batch `ModelDiagnosticsReport.Write`; only `WriteFromAccumulator` remains, so no accumulator means no report |
| 2 | Mode 5 clobbers `OSPREY_ALLOW_UNFIXED_RESIDENT` | Obsolete | Token and allowance removed (#4830); mode 5 removed (#4739) |
| 3 | Mode 5 tier-2 sanity outside its try/catch | Obsolete | Mode 5 moved to `SubsetPipelineTest` (#4739). Mode 1b's missing-report throw aborts the run by the outer catch's stated design ("Deliberately not per-dataset") |
| 4 | `PerFileScoringTask` twin caller lacks the diagnostics try/catch | Already fixed | #4830 removed the twin (`TallyPreCompaction`/`FeedModelDiagnostics` no longer in `PerFileScoringTask`); the pass-2 caller in `SecondPassFdrTask` is guarded |
| 5 | `OSPREY_DUMP_PERCOLATOR` in one pool decider, not the other | Obsolete | `NeedsResidentPool`/`PreCompactionPoolReason` removed (#4830) |
| 6 | Resident-handoff warning names a token never set | Obsolete | Token removed (#4820/#4830) |
| 7 | Inherited-token restore covers less than the comment promises | Fix now (residue) | The token is gone, but the same shape survives for `OSPREY_SVM_C_TOLERANCE`: cleared near the top, restored only in the `finally` of the dataset loop, so a build failure, staging error, golden-folder `exit 1` or `-StageOnly` (which `regression-parallel.ps1` invokes in-process with `&`) leaves it unset in the caller's session. Moved the clear to immediately before the `try`. |
| 8 | "Tokens REQUIRED" derived from a static table | Obsolete | Summary line removed with the tokens (#4830) |
| 9 | `Invoke-ResumeInvalidation` `-not $targets` passes a partial match | Fix now | Requires both FirstPassFDR's `*.1st-pass.*` products and `output.blib`, naming whichever kind matched nothing |
| 10 | "Second full pass is unavoidable" note | Obsolete | Lean path is counts-only (status 2026-09-18) |
| 11 | `ResidentPaths.cs` comment understates the accumulator | Obsolete | `ResidentPaths.cs` removed (#4830) |
| 12 | GC write-barrier justification | Obsolete | Comment and the skipped null-out loop removed (#4830) |
| s1 | `--` em-dash in `ScoringTaskShared` doc prose | Drop | Pre-existing pattern across the tree; fixing one line is churn |
| s2 | Braceless outer `foreach` in `FirstJoinTask` | Obsolete | `FirstJoinTask.cs` no longer exists |
| s3 | Dead `entry.Features = null` loop in `PerFileScoringTask` | Drop | Not a defect; a micro-cost on a per-file path |

## Progress Log

### 2026-11-01
- Verified each finding by grep and `git log -S` at 728ff3a131.
- Finding 7 residue reproduced: `$env:OSPREY_SVM_C_TOLERANCE='0.5'; & ./regression.ps1 -Dataset
  Stellar -NoBuild -StageOnly` leaves it empty on master, `0.5` with the fix.
- Finding 9: checked `Invoke-ResumeInvalidation` on scratch dirs (both kinds / blib only /
  1st-pass only / neither): deletes the same set when both exist, throws naming the missing kind
  otherwise. Its only caller is mode 2 (`Measure-CumulativeCoverage.ps1` mentions it in a comment
  only).
- Review (fresh general-purpose agent, medium): one comment finding, taken - the new comment
  said nothing above the clear runs Osprey, but `Resolve-DatasetInputs` runs `--export-library`,
  which returns before the variable is read. Also fixed a stale `regression.ps1:298-304`
  citation for `Invoke-ResumeInvalidation` in `docs/19-testing.md` that it pointed out.
- Gates: `Build-Osprey.ps1 -Debug -RunTests -RunInspection` 646/646, zero warnings
  (`ai/.tmp/sessions/20261101-triage/precommit-4542-2.log`). Committed 5ecb6f3e0c.
- Regression: `-Dataset Stellar` PASSED (`regression-4542-Stellar.log`); `-Dataset
  StellarLibDecoy` PASSED incl. mode 2 resume (the invalidation caller) and mode 3 chain
  (`regression-4542-StellarLibDecoy.log`), both in `ai/.tmp/sessions/20261101-triage/`.
