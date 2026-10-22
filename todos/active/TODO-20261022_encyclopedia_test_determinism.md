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
  hits (varying counts down); here one borderline peptide flips (always +1).

## Root cause (EncyclopeDIA 2.12.30 source, tag e753f10, plus a capture of a passing and a failing run)

Captured every EncyclopeDIA output from a passing (`<..698, 4907>`) and a failing (`<..699, 4915>`)
multi-threaded run and diffed them (`ai/.tmp/sessions/20261022-encyclopedia/capture/132757_698_4907` vs
`133115_699_4915`):

- Chromatogram-library stage (narrow files): byte-identical.
- Quant stage, `wide_1a ... .first.rt_fit.txt`: the same 338 input points (library RT, actual RT, peptide), but in
  a different row order. 3 fitted RTs differ, all near library RT 32.31 min (ALELEQERK, QDLAYER, EPMQTGIK; ~0.0006
  min). `fitProb` differs slightly on all 338 rows.
- Quant `wide_1a ... features.txt` (Percolator input): same 1,373 rows, same IDs, same sorted order. 5 rows differ
  only in `deltaRT`, by 0.0006-0.0007 (EPMQTGIK, decoyEIGTQMPK, QDLAYER, DVTLENR, LVEAVDGK). From there through
  wide_1b, the concatenated quant Percolator run, and the elib.
- Percolator's input is NOT order-dependent: `AbstractScoringResultsToTSVConsumer` sorts the feature file by
  PSM ID. (This was my earlier guess; it was wrong.)

Mechanism:
1. `Encyclopedia.getRescoringModel` (Encyclopedia.java ~519) builds `passingPSMs` by iterating `data`, which the
   scoring threads fill in completion order. So point order depends on the threads.
2. `ScoredPSMFilter` -> `RetentionTimeFilter.getFilter` -> `TwoDimensionalKDE`: `stampDistribution` adds each
   point's float kernel into a 3000x3000 `float` grid (`twoDimensionalHistogram[x][y] += stamp[i][j]`). Float
   addition is not associative, so a different point order leaves a cell differing in its last bits.
3. `TwoDimensionalKDE.trace()` walks the density ridge using exact float comparisons (`northeast == max`,
   `east == north`, argmax). A last-bit difference changes one step, which moves a local stretch of the
   `LinearInterpolatedFunction` knots. The mixture model fit on the deltas then shifts slightly everywhere.
4. The shifted RT warp changes `deltaRT`, a Percolator feature, for peptides in that stretch. One target peptide
   sits on the 1% q-value boundary and flips.

So the defect is order-sensitive float accumulation in the KDE alignment fed in thread-completion order. It is
not Percolator randomness. Upstream fix options: sort `passingPSMs`, or the KDE input points, by a stable key
(e.g. peptide + charge) before fitting; or accumulate the grid in double.

## Experiment

`NumberOfThreadsUsed = 1` via `searchDlg.SetAdditionalSetting`: 12 of 12 runs exact (`<366, 698, 698, 4907>`),
229-312 s each - no slower than multi-threaded on this machine. Only side effect: the tutorial audit log records
the thread count (32 -> 1, two places).

## Changes

- [x] `TestPerf/EncyclopeDiaSearchTutorialTest.cs`: pin EncyclopeDIA to one thread, with a comment on why
- [x] `TestTutorial/TutorialAuditLogs/en/TestEncyclopeDiaSearchTutorialDraft.log`: re-recorded (only 32 -> 1)
- [x] fr/ja/tr/zh baselines of the same log: 32 -> 1 in both places (Copilot review; 1526b5215c). Verified with
      a French run (passed, 217 s)
- [x] No screenshot or tutorial text shows the thread count (it is an additional setting, not on the settings
      page; no tutorial HTML for this draft in the repo)
- [x] Gates: build 0 warnings, CodeInspection passed, final normal-mode soak 3/3
- [ ] PR

## Not changed (deliberately)

- `TestFunctional/EncyclopeDiaSearchTest.cs` (`TestEncyclopeDiaSearch`) has the same pattern (exact
  `FinalTargetCounts` {33, 35, 35, 140} after a real search) but no failure history, a small search (fewer
  borderline peptides), and skips without a Koina server. Left unpinned to minimize changes (developer's call). If
  it ever flakes, the same one-line `NumberOfThreadsUsed = 1` applies.
- Upstream: the order-dependent KDE RT alignment (see Root cause) is worth reporting to the Searle lab, as
  #4840 did with MSAmanda#9, if Brendan agrees.
