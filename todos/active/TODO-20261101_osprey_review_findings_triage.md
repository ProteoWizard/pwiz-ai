# TODO-20261101_osprey_review_findings_triage.md

## Branch Information
- **Branch**: `Skyline/work/20261101_osprey_review_findings_triage` (worktree `D:\Dev\pwiz-triage`; no commits - nothing to fix)
- **Base**: `master` (728ff3a131)
- **Created**: 2026-11-01
- **Status**: Completed - no PR needed; issue comment posted, ready for Brendan to close #4544
- **GitHub Issue**: [#4544](https://github.com/ProteoWizard/pwiz/issues/4544)
- **Module**: `osprey`
- **PR**: none

Sister TODOs from the same overnight triage:
`TODO-20261101_osprey_4542_findings.md` (#4542) and
`TODO-20261101_osprey_percolator_followups.md` (#4494).

## Objective

Classify every leftover `/code-review max` finding in #4544 (against #4536, the rehydrate
survivor loader) against master 728ff3a131: already fixed, real (fix now), or drop.

## Classification

| # | Finding | Status | Evidence |
|---|---|---|---|
| 1 | Loader keyed by stem; buffer positional | Already fixed | #4646 refuses duplicate input stems at startup (`Program.DuplicateInputStemError`) |
| 2 | `AllowUnfixedResidentUnrecognized` unconsumed | Already fixed | Consumed in #4554; removed with the allowance in #4830 |
| 3 | No check that rebuild matches compaction | Already fixed | `SurvivorCountCheck` (#4820) |
| 4 | `PerFileConsensusTargets` positional, no re-key | Already fixed | Removed (#4838); loader sorts canonically and `SortCanonicalResolved` verifies ParquetIndex |
| 5 | Projection-off resume differs from computed twin | Obsolete | `OSPREY_FDR_PROJECTION=0` removed (#4821) |
| 6 | `TryBuildResumeSurvivorLoader` faults unscoped | Obsolete | Method removed (#4830) |
| - | `ResolveSidecarBasePath` null into `Pass1Path` | Drop | Unreachable from the loader: it errors first when the file has no parquet path |
| - | `RetainedBaseIds` bundle-scoped; 4 "not filed" shape items | Obsolete | Rehydrate arm, `streamingAvailable`, `ConsensusTargetsFromBundle` gone (#4830) |

## Progress Log

### 2026-11-01
- Verified each finding by grep and `git log -S` at 728ff3a131. Every one is fixed or obsolete;
  one residue dropped as unreachable.
- Posted the classification on #4544 as ready to close. No code change, no PR. The empty work
  branch can be deleted.
