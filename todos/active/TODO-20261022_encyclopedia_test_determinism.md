# TODO-20261022_encyclopedia_test_determinism.md

## Branch Information
- **Branch**: `Skyline/work/20261022_encyclopedia_test_determinism`
- **Base**: `master` (a98f401f72)
- **Created**: 2026-10-22
- **Status**: In Progress
- **Module**: `skyline`
- **PR**: [#4903](https://github.com/ProteoWizard/pwiz/pull/4903) (draft)
- **Checkout**: `C:\Dev\BuildTrouble`

## Objective

Stabilize `TestEncyclopeDiaSearchTutorialDraft` (TestPerf), which intermittently fails its `FinalTargetCounts`
check: expected `<366, 698, 698, 4907>`, actual `<366, 699, 699, 4915>` - always that same alternative.

## Evidence

- Nightly Performance Tests: BSPRATT-UW2 2026-10-18 (master 23e870a9b), the only failure since 08-01.
- TeamCity "Skyline PR Perf and Tutorial tests" #15673 (PR #4850), 1 of 6 runs.
- Locally (Release), multi-threaded: 2 of 6 runs on identical code, including back-to-back in one TestRunner
  process (-Loop: run 1 passed, run 2 failed). Not machine- or build-dependent.
- An earlier file-revert bisection blamed master's #4879; it was confounded by the flake (see
  TODO-20261015_skyline_single_build.md, 2026-10-21 entry) - #4879 is not involved.
- Same shape as #4840 (TestDdaSearch / MS Amanda, TODO-20261013_testddasearch_skyline_dev6.md): external search
  tool, count check at AssociateProteinsDlg.NewTargetsFinalSync, BelowNormal priority. Difference: MS Amanda lost
  hits (varying counts down); here one borderline peptide flips (always +1), consistent with EncyclopeDIA's
  embedded Percolator seeing input in thread-dependent order (EncyclopeDiaHelpers: NumberOfThreadsUsed default 32,
  PercolatorThreshold 0.01). Mechanism inside EncyclopeDIA not verified from its source.

## Experiment

`NumberOfThreadsUsed = 1` via `searchDlg.SetAdditionalSetting`: 12 of 12 runs exact (`<366, 698, 698, 4907>`),
229-312 s each - no slower than multi-threaded on this machine. Only side effect: the tutorial audit log records
the thread count (32 -> 1, two places).

## Changes

- [x] `TestPerf/EncyclopeDiaSearchTutorialTest.cs`: pin EncyclopeDIA to one thread, with a comment on why
- [x] `TestTutorial/TutorialAuditLogs/en/TestEncyclopeDiaSearchTutorialDraft.log`: re-recorded (only 32 -> 1)
- [x] No screenshot or tutorial text shows the thread count (it is an additional setting, not on the settings
      page; no tutorial HTML for this draft in the repo)
- [x] Gates: build 0 warnings, CodeInspection passed, final normal-mode soak 3/3
- [ ] PR

## Not changed (deliberately)

- `TestFunctional/EncyclopeDiaSearchTest.cs` (`TestEncyclopeDiaSearch`) has the same pattern (exact
  `FinalTargetCounts` {33, 35, 35, 140} after a real search) but no failure history, a small search (fewer
  borderline peptides), and skips without a Koina server. Left unpinned to minimize changes (developer's call). If
  it ever flakes, the same one-line `NumberOfThreadsUsed = 1` applies.
- Upstream: EncyclopeDIA feeding Percolator in thread-dependent order is worth reporting to the Searle lab, as
  #4840 did with MSAmanda#9, if Brendan agrees it is the mechanism.
