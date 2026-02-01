# TODO-20260131_viewcontext_null_rowsource.md

## Branch Information
- **Branch**: `Skyline/work/20260131_viewcontext_null_rowsource`
- **Base**: `master`
- **Created**: 2026-01-31
- **Status**: In Progress
- **GitHub Issue**: [#3887](https://github.com/ProteoWizard/pwiz/issues/3887)

## Objective
Fix ArgumentNullException in SkylineViewContext.GetImageIndex when ViewSpec.RowSource is null.

## Root Cause Analysis
`SkylineViewContext.GetImageIndex()` calls `_imageIndexes.TryGetValue(viewSpec.RowSource, ...)` at line 662. `Dictionary.TryGetValue` throws `ArgumentNullException` when the key is null. `ViewSpec.RowSource` can be null when a view is deserialized from XML missing the `rowsource` attribute (`ViewSpec.ReadXml` uses `reader.GetAttribute("rowsource")` which returns null).

## Exception Details
- **Fingerprint**: `6652108b5f24724c`
- **Reports**: 4 from 3 users since May 2025

## Changes Made
- [x] Added null check for `viewSpec.RowSource` before dictionary lookup, returning -1 (the base class default)

## Files Modified
- `pwiz_tools/Skyline/Controls/Databinding/SkylineViewContext.cs` - GetImageIndex()

## Test Plan
- [ ] TeamCity CI passes

## Implementation Notes
- The base class `AbstractViewContext.GetImageIndex` returns -1 as default
- All callers (NavBar.cs, ChooseViewsControl.cs, ExportLiveReportDlg.cs) guard with `imageIndex >= 0` before using the value, so -1 is safe
