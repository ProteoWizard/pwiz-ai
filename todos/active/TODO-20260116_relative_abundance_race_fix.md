# TestPeakAreaRelativeAbundanceGraph: IsComplete race condition fix

## Branch Information
- **Branch**: `Skyline/work/20260116_relative_abundance_race_fix`
- **Base**: `master`
- **Created**: 2026-01-16
- **GitHub Issue**: [#3824](https://github.com/ProteoWizard/pwiz/issues/3824)
- **Pull Request**: [#3825](https://github.com/ProteoWizard/pwiz/pull/3825)

## Objective

Fix the intermittent TestPeakAreaRelativeAbundanceGraph failures that started January 2, 2026 after PR #3730 was merged. Same root cause as #3789 (TestPeakPickingTutorial).

## Root Cause

Race condition in `SummaryRelativeAbundanceGraphPane.IsComplete`:
- Test waits for `pane.IsComplete` then accesses `pane.CachedNodeCount`
- `IsComplete` checks that the receiver has a cached product matching current document
- But `CachedNodeCount` reads from `_graphData` which is only set when `ProductAvailableAction` callback runs
- Window exists where receiver has product but `_graphData` is still stale

## Solution

Updated `IsComplete` to also verify that `_graphData` has been populated and matches the current document/settings:

```csharp
// Verify _graphData has been updated (ProductAvailableAction callback has run)
// This prevents race where receiver has product but _graphData is still stale
return _graphData != null &&
       ReferenceEquals(_graphData.Document, currentDoc) &&
       Equals(_graphData.GraphSettings, currentSettings);
```

## Files Modified

1. **`pwiz_tools/Skyline/Controls/Graphs/SummaryRelativeAbundanceGraphPane.cs`**
   - Updated `IsComplete` property to verify `_graphData` is current

## Tasks

- [x] Analyze test failure history and stack traces
- [x] Identify race condition (same pattern as #3789)
- [x] Update `IsComplete` to verify `_graphData` is current
- [x] Build and run TestPeakAreaRelativeAbundanceGraph locally
- [x] Commit and create PR

## Test Results

- TestPeakAreaRelativeAbundanceGraph: PASSED (16 sec)
