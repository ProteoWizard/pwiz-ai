# TestPeakAreaRelativeAbundanceGraph: Intermittent test failure fix

## Branch Information
- **Branch**: `Skyline/work/20260116_relative_abundance_race_fix`
- **Base**: `master`
- **Created**: 2026-01-16
- **GitHub Issue**: [#3824](https://github.com/ProteoWizard/pwiz/issues/3824)
- **Pull Request**: [#3830](https://github.com/ProteoWizard/pwiz/pull/3830) - MERGED
- **Cherry-pick PR**: [#3831](https://github.com/ProteoWizard/pwiz/pull/3831) to `Skyline/skyline_26_1`

## Objective

Fix the intermittent TestPeakAreaRelativeAbundanceGraph failures where the test expected `CachedNodeCount=0` after document reopen but intermittently saw `CachedNodeCount=125`.

## Status: COMPLETE - Merged to master and cherry-picked to release

- PR #3830 merged to master
- PR #3831 created for cherry-pick to Skyline/skyline_26_1

## Root Cause Analysis

Opening a document triggers 3 DocumentChanged events (OpenFile, ChromatogramManager, LibraryManager). This can cause multiple graph calculations:

1. **Parallel full calculations**: Multiple calculations start before any result is cached - all do full calculation (125 recalculated)
2. **Incremental after full**: If one calculation completes and caches before another starts, subsequent calculations use incremental update (0 recalculated, 125 cached)

The original test checked `pane.CachedNodeCount` on the final result, which could be an incremental update. This was the intermittent failure case.

## Solution

Added cache tracking to `ReplicateCachingReceiver`:
- `TrackCaching` property enables tracking during test
- `CachedSinceTracked` returns all cached results

Updated test to:
- Track all cached results during document reopen
- Assert first result is full calculation (CachedNodeCount=0)
- Allow subsequent results to be either full or incremental
- Enforce invariant: once incremental seen, all remaining must be incremental

## Files Modified

1. **`pwiz_tools/Skyline/Controls/Graphs/ReplicateCachingReceiver.cs`**
   - Added cache tracking region with TrackCaching, CachedSinceTracked, TrackCachedResult()
   - Called TrackCachedResult() when results are cached

2. **`pwiz_tools/Skyline/Controls/Graphs/SummaryRelativeAbundanceGraphPane.cs`**
   - Added WasFullCalculation property to GraphData
   - Added GetDiagnosticInfo() method for assertion messages

3. **`pwiz_tools/Skyline/TestFunctional/PeakAreaRelativeAbundanceGraphTest.cs`**
   - Added using alias for GraphDataCachingReceiver
   - Updated Test 6 to use cache tracking instead of checking final pane state
   - Added logic to handle valid parallel calculation scenarios

## Tasks

- [x] Analyze test failure history and stack traces
- [x] Identify root cause (multiple DocumentChanged events during file open)
- [x] Add cache tracking to ReplicateCachingReceiver
- [x] Add WasFullCalculation and GetDiagnosticInfo to GraphData
- [x] Update test to check first cached result instead of final pane state
- [x] Handle parallel full calculation scenarios
- [x] Test passed 500 times including race condition scenarios
- [x] Create PR #3830
- [x] PR #3830 merged to master
- [x] Cherry-pick PR #3831 created for release branch
- [ ] PR #3831 review and merge

## Related PRs

- PR #3822: Fixed TestPeakPickingTutorial (RTLinearRegressionGraphPane.IsComplete) - MERGED
- PR #3825: Fixed IsComplete race condition - MERGED (didn't fully fix #3824)
- PR #3830: Fixed test to handle multiple cached results - MERGED
- PR #3831: Cherry-pick to Skyline/skyline_26_1 - Ready for review
