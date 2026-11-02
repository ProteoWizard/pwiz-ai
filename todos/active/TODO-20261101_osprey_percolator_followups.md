# TODO-20261101_osprey_percolator_followups.md

## Branch Information
- **Branch**: `Skyline/work/20261101_osprey_percolator_followups` (worktree `D:\Dev\pwiz-triage`)
- **Base**: `master` (728ff3a131)
- **Created**: 2026-11-01
- **Status**: In Progress
- **GitHub Issue**: [#4494](https://github.com/ProteoWizard/pwiz/issues/4494)
- **Module**: `osprey`
- **PR**: (pending)

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
