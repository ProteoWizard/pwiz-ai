# TestPeakAreaRelativeAbundanceGraph: IsComplete race condition fix

## Branch Information
- **Branch**: `Skyline/work/20260116_relative_abundance_race_fix`
- **Base**: `master`
- **Created**: 2026-01-16
- **GitHub Issue**: [#3824](https://github.com/ProteoWizard/pwiz/issues/3824)
- **Pull Request**: [#3825](https://github.com/ProteoWizard/pwiz/pull/3825)

## Objective

Fix the intermittent TestPeakAreaRelativeAbundanceGraph failures that started January 2, 2026 after PR #3730 was merged. Same root cause as #3789 (TestPeakPickingTutorial).

## Status: STILL INVESTIGATING

Initial fix (PR #3825) was merged but test still fails intermittently after ~7 hours of looping.
Now adding diagnostic instrumentation to capture more information when the failure occurs.

## Root Cause (Hypothesis)

Multiple graph refreshes may be happening:
- First refresh correctly does full calculation (CachedNodeCount=0)
- Second refresh uses incremental update (CachedNodeCount=125)
- Test sees the second refresh's data

## Current Work: Diagnostic Instrumentation

Added diagnostic fields to `GraphData` class to track:
- **RefreshSequence**: Unique ID for each GraphData created (global counter)
- **WasFullCalculation**: True if CalcDataPositionsFull was called
- **PriorRefreshSequence**: Sequence of prior data if incremental update
- **DocumentIdHash**: RuntimeHelpers.GetHashCode(Document.Id) for identity comparison
- **CreationTime**: When this GraphData was created

Added `GetDiagnosticInfo()` method and `GetGraphDataForDiagnostics()` accessor.

Updated test to dump diagnostics when assertion fails.

## Files Modified (Uncommitted)

1. **`pwiz_tools/Skyline/Controls/Graphs/SummaryRelativeAbundanceGraphPane.cs`**
   - Added diagnostic fields to GraphData class
   - Added GetDiagnosticInfo() method
   - Added GetGraphDataForDiagnostics() accessor
   - Updated constructor to populate diagnostic fields
   - Added `using System.Threading;`

2. **`pwiz_tools/Skyline/TestFunctional/PeakAreaRelativeAbundanceGraphTest.cs`**
   - Added diagnostic dump before assertion
   - Added `using System.Runtime.CompilerServices;`

## Tasks

- [x] Analyze test failure history and stack traces
- [x] Identify race condition (same pattern as #3789)
- [x] Update `IsComplete` to verify `_graphData` is current (PR #3825)
- [x] Build and run TestPeakAreaRelativeAbundanceGraph locally - PASSED
- [x] Commit and create PR
- [ ] **FIX STILL FAILING** - Test failed after 7 hours of looping
- [x] Add diagnostic instrumentation to GraphData
- [x] Update test to dump diagnostics on failure
- [ ] Build and verify diagnostics compile
- [ ] Run test with diagnostics and wait for failure
- [ ] Analyze diagnostic output to understand true root cause

## Related PRs

- PR #3822: Fixed TestPeakPickingTutorial (RTLinearRegressionGraphPane.IsComplete) - MERGED, ~600 runs passed
- PR #3825: Fixed TestPeakAreaRelativeAbundanceGraph (SummaryRelativeAbundanceGraphPane.IsComplete) - MERGED, still fails intermittently
