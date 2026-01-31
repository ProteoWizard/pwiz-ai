# TODO-20260130_placepane_bounds_check.md

## Branch Information
- **Branch**: `Skyline/work/20260130_placepane_bounds_check`
- **Base**: `master`
- **Created**: 2026-01-30
- **Status**: In Progress
- **GitHub Issue**: [#3910](https://github.com/ProteoWizard/pwiz/issues/3910)
- **PR**: [#3918](https://github.com/ProteoWizard/pwiz/pull/3918)

## Objective
Fix ArgumentOutOfRangeException in SkylineWindow.PlacePane during graph arrangement.

## Root Cause Analysis
`ArrangeGraphsGrouped` builds a `listTiles` structure with variable column counts per row (line 5892: `columns = columnsShort + (iRow < longRows ? 1 : 0)`). The `PlacePane` method accesses `listTiles[row][col]` without bounds checking.

While the calling loops appear to bound their indices correctly, `dockableForm.Show()` at line 5935 modifies dock panel state during iteration, which can trigger re-entrant events that invalidate the graph list. This causes subsequent PlacePane calls to find row/col indices out of bounds.

The issue is long-standing (versions 21.2 through 26.0.9) and affects two call paths:
- `ArrangeGraphsGrouped` (fingerprint `d1b83c9a97a288fe`)
- `ArrangeGraphs` (fingerprint `2b5b2a631cfc87a1`)

## Exception Details
- **Fingerprint**: `d1b83c9a97a288fe` (5 reports, 5 users)
- **Related fingerprint**: `2b5b2a631cfc87a1` (5 reports, 3 users)
- **Versions**: 21.2 through 26.0.9.021

## Changes Made
- [x] Added bounds check for row and col against listTiles dimensions
- [x] Extracted previousIndex (row-1 or col-1) and guarded against negative values
- [x] Added cross-row column bounds check for Bottom alignment (previous row may have fewer columns)
- [x] Refactored previousForm access to use previousIndex variable

## Files Modified
- `pwiz_tools/Skyline/SkylineGraphs.cs` - PlacePane() at line 5926

## Test Plan
- [x] ArrangeGraphsTest passes
- [ ] TeamCity CI passes

## Implementation Notes
- The calling loops bound their indices correctly, but .NET does not include the actual index in ArgumentOutOfRangeException messages, so the original exception report does not reveal which access failed
- Three listTiles access patterns are guarded: direct row/col, previousIndex (row-1 or col-1), and cross-row column access for Bottom alignment
- The Right alignment path accesses the same row at previousIndex, which is already bounds-checked, so no extra cross-row check is needed
