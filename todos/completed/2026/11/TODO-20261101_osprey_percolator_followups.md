# TODO-20261101_osprey_percolator_followups.md

## Branch Information
- **Branch**: `Skyline/work/20261101_osprey_percolator_followups` (worktree `D:\Dev\pwiz-triage`)
- **Base**: `master` (728ff3a131)
- **Created**: 2026-11-01
- **Status**: Completed
- **GitHub Issue**: [#4494](https://github.com/ProteoWizard/pwiz/issues/4494)
- **Module**: `osprey`
- **PR**: [#4963](https://github.com/ProteoWizard/pwiz/pull/4963) (merged 2026-11-03)

## Objective

Clear the live follow-ups from the PercolatorFdr decomposition (#4494) by pure code motion,
output-locked by the Stellar regression golden.

## Classification (against master 728ff3a131)

| # | Item | Status | Action / reason |
|---|---|---|---|
| 1a | `PercolatorScorer` <-> `PercolatorTrainer` cycle via `RunStreamingFirstPass` | Fix now | Moved `RunStreamingFirstPass` and the helpers only it uses (`FirstPassDedupRow`, `TryLoadCompletedScores`, `CompletedScoreRecords`, `FoldRowExperimentValues`, `ComputeStreamedScore`, `ScoresBeforeRowLoop`, `ClassifierMismatchMessage`, `RowBuffer`, `ReadFileRows`, `ScoreRows`, `LanesUsed`, `LogBlockReads`, `Pass1File`, `EntryFacts`, `EntryFactsByEntryId`, `ExperimentScope`, `FoldFile`, `LaneCost`, the `LANE1_`/`FOLD_` bucket constants) to `PercolatorEngine`. Scorer no longer references the trainer. Four shared primitives widened private -> internal (`StandardizeFeatureRow`, `BuildContributions`, `AverageGbtScore`, `ResolveGbtModels`). |
| 1b | `GroupIndicesByFileName` belongs in `PercolatorSampling` | Fix now | Moved verbatim. |
| 1c | `QProgress` parks a progress factory on the q-value class | Drop | Five of its six callers are in `PercolatorQValues`; moving it rewrites the exact `using (... QProgress(...))` lines open PR #4955 edits. Not worth a conflict for a cosmetic move. |
| 2 | Stale `PercolatorFdr.cs:NNN` citations in docs | Already fixed | #4690 (0f0c6108ef) rewrote them; `grep PercolatorFdr.cs: pwiz_tools/Osprey/docs ai/docs` finds none. Updated the four `07-fdr-control.md` citations this move made stale (`PercolatorScorer.RunStreamingFirstPass` x3, `PercolatorScorer.cs:63/:272`) to file.method form. |
| 3 | `Combine-Stage5-Profile.ps1` symbol map keys on `PercolatorFdr.*` | Fix now (pwiz-ai) | Now `TargetDecoyCompetition.CompeteFromIndicesInto`, `PercolatorTrainer+<>c__DisplayClass*.<GridSearchC>b__` (display-class number wildcarded), `PercolatorTrainer.RunPercolator`. |
| 4 | `BASE_ID_MASK` defined 8 times | Drop (for this PR) | ~76 uses over 24 files, three of them in open PR #4955; every definition agrees on 0x7FFFFFFF. A Core accessor is the right fix but is its own sweep, not a pure-motion follow-up. Brendan may want it filed or scheduled. |
| 5 | `TrainFoldModels` takes 14 positional parameters | Drop | Deriving the two named ints still leaves 12 positionals on a private single-caller method; the real fix (a parameter object) is not worth the churn. |

## Merge-order note

Open PR #4955 (progress reporter outcome) changes one line inside `RunStreamingFirstPass`
(`ingestProgress.Dispose()` -> `.Complete()`). Whichever PR merges second re-applies that one
line at the method's new location in `PercolatorEngine.cs`.

## Progress Log

### 2026-11-01
- Moved the code with a byte-preserving splice script (CRLF kept), then qualified the
  cross-class calls and updated crefs, `FdrTest`, and two comments in `FdrProjectionOutput.cs`
  and `FdrProjectionSinks.cs`.
- Motion check (`verify_motion.py` in the session folder): with class qualifiers stripped, every
  removed line reappears; the only differences are the four private -> internal widenings and
  two doc comments.
- Review (fresh general-purpose agent, medium): no behavior findings. Took its one nit (the
  `PercolatorEngine` class summary now says it holds the streaming first pass). Left the
  `PercolatorScorer_RunStreamingFirstPass_*` resource keys named after the old class: renaming
  them churns three RESX files for no runtime change.
- Gates: `Build-Osprey.ps1 -Debug -RunTests -RunInspection` 646/646, zero inspection warnings
  (`ai/.tmp/sessions/20261101-triage/precommit-4494-3.log`); `regression.ps1 -Dataset Stellar`
  PASSED, mode 1 vs golden, 1c, 4, 6 (`ai/.tmp/sessions/20261101-triage/regression-4494-Stellar.log`).
- Committed 80b9ed002b, pushed.

### 2026-11-03 - Merged master after #4955 landed
- #4955 (merged a33ca3308d) added Complete() calls inside the code this branch moves, so
  PercolatorScorer.cs conflicted. Resolved by keeping the deletion of the moved block and carrying
  the four calls (ingest, subset load, pass-1 score, fold merge) to RunStreamingFirstPass in
  PercolatorEngine; the branch's diff against master is again the pure code motion
  (7 files, +1430/-1423). Merge commit 56452c6e56, pushed.
- Gates on the merge: Build-Osprey Debug tests + inspection 646/646, 0 warnings
  (`ai/.tmp/sessions/pw-complete-4963/precommit-merge.log`); `regression.ps1 -Dataset Stellar`
  PASSED (`ai/.tmp/sessions/pw-complete-4963/regression-stellar-merge.log`). The TeamCity
  Perf/Regression gate queued as build 4248191 is pinned to the pre-merge head 80b9ed002b.
- Second merge after #4965 (b77cfb0326) landed: its `BuildContributions` signature change
  (`PercolatorResults` in place of fold weights) sat inside the moved block, so the call in
  `PercolatorEngine` took the new signature and the kept `internal` declaration in
  `PercolatorScorer` took it too. Merge commit 27fd6b72ba, pushed. Gates on it: 648/648, 0 inspection
  warnings (`pw-complete-4963/precommit-merge2.log`); Stellar PASSED
  (`pw-complete-4963/regression-stellar-merge2.log`). Diff vs master is still the pure motion.

### 2026-11-03 - Merged

TeamCity Perf/Regression gate build #352 (4248191) passed on the pre-merge head 80b9ed002b: all four
datasets plus the CarafeSharp pass. PR #4963 merged as commit 054f484787. Shipped: the code motion
as described, with #4955's Complete() calls and #4965's BuildContributions signature carried to the
moved code. Issue #4494 closed by the merge; its dropped items (QProgress move, BASE_ID_MASK sweep,
TrainFoldModels parameter trim) are recorded in the classification table above. Brendan's #4967,
#4968 and #4969 edit PercolatorEngine.cs and take a merge from master after this.
