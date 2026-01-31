# TODO-20260130_placepane_bounds_check.md

## Branch Information
- **Branch**: `Skyline/work/20260130_placepane_bounds_check`
- **Base**: `master`
- **Created**: 2026-01-30
- **Status**: In Progress
- **GitHub Issue**: [#3910](https://github.com/ProteoWizard/pwiz/issues/3910)

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
- [x] Added bounds check at top of PlacePane: `if (row >= listTiles.Count || col >= listTiles[row].Count) return`

## Files Modified
- `pwiz_tools/Skyline/SkylineGraphs.cs` - PlacePane() at line 5926

## Test Plan
- [ ] TeamCity CI passes

## Implementation Notes
- The `Bottom` alignment path always uses `col=0` (every row has at least 1 column), so the `previousForm` access at `listTiles[row-1][col]` is safe for normal calls
- The `Right` alignment path uses `col-1` which is always >= 0 since the loop starts at j=1
- The bounds check is defensive against re-entrant dock panel events, not against the normal calling patterns which are already bounded correctly
