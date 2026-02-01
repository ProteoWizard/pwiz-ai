# TODO-20260131_alignmentform_null_rtsource.md

## Branch Information
- **Branch**: `Skyline/work/20260131_alignmentform_null_rtsource`
- **Base**: `master`
- **Created**: 2026-01-31
- **Status**: In Progress
- **GitHub Issue**: [#3827](https://github.com/ProteoWizard/pwiz/issues/3827)
- **PR**: [#3923](https://github.com/ProteoWizard/pwiz/pull/3923)

## Objective
Fix NullReferenceException in AlignmentForm when RetentionTimeSource is null.

## Root Cause Analysis
`AlignmentForm.GetRows()` accesses `targetKey.Value.RetentionTimeSource` without null-checking. This flows into the `DataRow` constructor where `Assume.IsNotNull(target)` fires at line 357. `RetentionTimeSource` can be null if the library is unloaded or the source is removed while the AlignmentForm is open and the user changes the combo box selection.

## Exception Details
- **Exception ID**: 73754
- **Version**: 26.0.9.004

## Changes Made
- [x] Extracted `targetKey.Value.RetentionTimeSource` into local `target` variable
- [x] Added null check returning empty array when `target` is null
- [x] Used `target` variable for both the name comparison and DataRow constructor

## Files Modified
- `pwiz_tools/Skyline/Controls/Graphs/AlignmentForm.cs` - GetRows()

## Test Plan
- [ ] TeamCity CI passes

## Implementation Notes
- Returns empty DataRow array on null, same as the existing `!targetKey.HasValue` guard above
- The combo box will simply show no alignment rows until a valid source is selected
