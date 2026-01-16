# TestPeakPickingTutorial: Systemic failure in CheckPointsTypeRT since Jan 1, 2026

## Branch Information
- **Branch**: `Skyline/work/20260116_peak_picking_tutorial_hang`
- **Base**: `master`
- **Created**: 2026-01-16
- **GitHub Issue**: [#3789](https://github.com/ProteoWizard/pwiz/issues/3789)
- **Pull Request**: [#3822](https://github.com/ProteoWizard/pwiz/pull/3822)

## Objective

Fix the systemic TestPeakPickingTutorial test failure that started January 1, 2026, affecting 3+ machines. The failure is a race condition introduced by PR #3730 which added background threading for RT graph calculations.

## Root Cause Analysis (COMPLETED)

**The actual failure is a NullReferenceException**, not a hang as initially reported in the issue.

Stack trace from failure history:
```
System.NullReferenceException: Object reference not set to an instance of an object.
   at PeakPickingTutorialTest.CheckPointsTypeRT() in PeakPickingTutorialTest.cs:line 544
```

Line 544 is: `Assert.AreEqual(expectedPoints, pane.StatisticsRefined.ListRetentionTimes.Count);`

**Race condition explained:**
1. `WaitForRegression()` waits for `!pane.IsCalculating` (background calculation done, result in cache)
2. But `_data` is only set when `ProductAvailableAction` callback runs on UI thread
3. There's a window where `IsCalculating` is false but `_data` hasn't been set yet
4. Test accesses `pane.StatisticsRefined` which returns null → NullReferenceException

**Evidence:** 11 failures from Jan 1-16, 2026 across 5 machines, all with the same NullReferenceException at line 544.

## Solution Implemented

Added `IsComplete` property to `RTLinearRegressionGraphPane` (following the pattern from `SummaryRelativeAbundanceGraphPane` which was also added in PR #3730):

```csharp
public bool IsComplete
{
    get
    {
        if (_graphDataReceiver.HasError)
            return true;
        if (IsCalculating)
            return false;
        return StatisticsRefined != null;  // Data callback has run
    }
}
```

Updated `WaitForRegression()` to use `pane.IsComplete` instead of `!pane.IsCalculating`.

## Files Modified

1. **`pwiz_tools/Skyline/Controls/Graphs/RTLinearRegressionGraphPane.cs`**
   - Added `IsComplete` property (lines 509-529)

2. **`pwiz_tools/Skyline/TestUtil/TestFunctional.cs`**
   - Changed `WaitForRegression()` to wait for `pane.IsComplete` instead of `!pane.IsCalculating`

3. **`pwiz_tools/Skyline/TestFunctional/NonLinearRegressionTest.cs`**
   - Changed 2 occurrences of `!pane.IsCalculating` to `pane.IsComplete`

4. **`pwiz_tools/Skyline/TestFunctional/RunToRunAlignmentTest.cs`**
   - Changed 2 occurrences of `!scoreToRunGraphPane.IsCalculating` to `scoreToRunGraphPane.IsComplete`

5. **`pwiz_tools/Skyline/TestPerf/PeakBoundaryImputationDiaTutorial.cs`**
   - Changed `WaitForRTRegressionComplete()` to use `scoreToRunGraphPane.IsComplete`

## Tasks

- [x] Review PR #3730 changes to understand the background threading model
- [x] Examine CheckPointsTypeRT in TestPeakPickingTutorial to understand what it validates
- [x] Identify the race condition between background calculation and test validation
- [x] Add `IsComplete` property to `RTLinearRegressionGraphPane`
- [x] Update `WaitForRegression()` to use `IsComplete`
- [x] Update `NonLinearRegressionTest` to use `IsComplete`
- [x] Update `RunToRunAlignmentTest` to use `IsComplete`
- [x] Update `PeakBoundaryImputationDiaTutorial` to use `IsComplete`
- [x] Build and run tests locally to verify fix
- [x] Create PR with fix

## Tests Verified

All 4 affected tests pass locally:
- TestPeakPickingTutorial (the originally failing test)
- TestNonlinearRegression
- TestRunToRunAlignment
- TestPeakBoundaryImputationDiaTutorial

## Progress Log

### 2026-01-16 - Session Start

Starting work on this issue. Will begin by reviewing the PR #3730 changes and the test code to understand the timing issue.

### 2026-01-16 - Root Cause Found

Queried test failure history - found 11 failures since Jan 1, all NullReferenceException at line 544. The "hang" in the issue title was misleading - the actual failure is accessing `StatisticsRefined` when `_data` is null.

### 2026-01-16 - Fix Implemented

- Added `IsComplete` property to `RTLinearRegressionGraphPane` following the pattern from `SummaryRelativeAbundanceGraphPane`
- Updated `WaitForRegression()` and `NonLinearRegressionTest` to use `IsComplete`
- Changes ready for testing

### 2026-01-16 - Session Handoff

Fix is implemented but not yet tested. Next steps: build, run affected tests, create PR.
