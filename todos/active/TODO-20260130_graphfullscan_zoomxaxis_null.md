# TODO-20260130_graphfullscan_zoomxaxis_null.md

## Branch Information
- **Branch**: `Skyline/work/20260130_graphfullscan_zoomxaxis_null`
- **Base**: `master`
- **Created**: 2026-01-30
- **Status**: In Progress
- **GitHub Issue**: [#3888](https://github.com/ProteoWizard/pwiz/issues/3888)

## Objective
Fix NullReferenceException in GraphFullScan.ZoomXAxis when _requestedRange not initialized.

## Root Cause Analysis
`GraphFullScan.ZoomXAxis()` accesses `_requestedRange.Min` and `_requestedRange.Max` (line 1216-1217) in the `else` branch when `magnifyBtn` is not checked. The field `_requestedRange` is a reference type (`MzRange` class) that defaults to null and is only initialized in `SetSpectraUI()` (line 180) after scan data loads asynchronously.

When the user clicks the zoom toolbar button before scan data loads, `_requestedRange` is still null, causing the NullReferenceException.

Call paths that reach ZoomXAxis before data loads:
- `magnifyBtn_CheckedChanged` -> `ZoomToSelection` -> `ZoomXAxis()`
- `graphControl_MouseClick` -> `ZoomXAxis()`
- `SetMzScale` -> `ZoomXAxis()`

## Exception Details
- **Fingerprint**: `fceac746bf4b350b`
- **Reports**: 7 from 6 users since August 2025

## Changes Made
- [x] Changed `else` to `else if (_requestedRange != null)` in ZoomXAxis() to skip scale-setting when no range data exists yet

## Files Modified
- `pwiz_tools/Skyline/Controls/Graphs/GraphFullScan.cs` - ZoomXAxis() at line 1214

## Test Plan
- [ ] TeamCity CI passes

## Implementation Notes
- When `_requestedRange` is null, there is no valid range data to display, so skipping the scale-setting is correct
- Once data loads and `SetSpectraUI()` initializes `_requestedRange`, `ZoomXAxis()` is called again with the proper range
- The `magnifyBtn.Checked` branch (lines 1206-1213) also dereferences `_msDataFileScanHelper` properties but those are set earlier in the lifecycle
