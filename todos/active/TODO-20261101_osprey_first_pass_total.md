# TODO-20261101_osprey_first_pass_total.md

## Branch Information
- **Branch**: `Skyline/work/20261101_osprey_first_pass_total`
- **Base**: `master`
- **Created**: 2026-11-01
- **Status**: In Progress
- **GitHub Issue**: [#4463](https://github.com/ProteoWizard/pwiz/issues/4463)
- **Module**: `osprey`
- **PR**: [#4957](https://github.com/ProteoWizard/pwiz/pull/4957)
- **Worktree**: `D:\Dev\pwiz-unimod` (night-session worktree of `C:\proj\pwiz`, after PR #4956)

## Objective

Replace the first-pass console line `Total: N precursors pass run-level FDR across M files` (a sum
of per-file run-level counts, so a precursor counts once per file) with an experiment-level count
of distinct precursors.

## Where the count is available

The issue asked whether the experiment-level count exists at the first-pass FDR point or only
after reconciliation. It exists: `FirstPassFdrTask.RunFirstPassProjection` holds an
`FdrExperimentAccumulator` filled during the streaming score pass with one record per distinct
entry_id (base precursor id + decoy bit), each carrying the final experiment precursor and peptide
q-values (best-of-runs floors already applied in `ExperimentScope.Resolve`). Protein FDR, which runs
after the log line, only sets the protein q. The same records are written to the first-pass
experiment intermediate file, which the new test reads as its oracle.

## Change

- `LogFirstPassResultsProjection` takes the accumulator; `LogExperimentLevelTotal` (replacing
  `LogRunLevelTotal`) logs `Across {0:N0} files: {1:N0} of {2:N0} target precursors at {3:P1}
  experiment-level {4} FDR` - passing over all scored targets (rule 7: the denominator), at the
  configured `--fdr-level` (`FdrLevel.GetLocalizedString()`), threshold `ExperimentFdr`. Still
  omitted for one file. Peptide count (Rust printed one too) not added: the first pass holds the
  entry peptides only in the sink, and one count answers the issue.
- `FdrExperimentRecord.IsDecoy` and `EffectiveExperimentQvalue(FdrLevel)`.
- Resource replaced in `OspreyTasksResources.resx` + Designer; the stale ja/zh-Hans translations of
  the old line removed (the new one falls back to English until translated).
- `SubsetPipelineTest.TestSubsetStraightThroughAndReruns` asserts the exact line, recomputed from
  the first-pass experiment intermediate file.

## Tasks

- [x] Implement + test
- [x] Gate: Build-Osprey -RunTests -RunInspection: 646/646, inspection zero
  (`C:\proj\ai\.tmp\sessions\20261101-unimod\gate-pr2.log`)
- [x] Review at medium (fresh reviewer agent over the saved diff; the `/code-review` skill is
  blocked by `Deny-CodeReviewInAiRepo.ps1` since this session's cwd is pinned to `C:\proj\ai`).
  No defects; checks confirmed (q final at the log point, one record per precursor, resume paths,
  FdrLevel.Both, test glob). Two optional cleanups: Designer blank line made to match the
  generator (fixed); third copy of the FdrLevel switch in `FdrExperimentRecord` dropped - three
  lines, the existing copies follow the same pattern.
- [x] PR opened (see Branch Information)

Stellar regression not run: log-only change (no output path touched); unit tests + inspection per
the task brief.

## Progress Log

### 2026-11-01
- Implemented and gated as above.
