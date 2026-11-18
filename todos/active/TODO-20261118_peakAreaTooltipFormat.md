# Format the Peak Areas replicate comparison tooltip

## Branch Information
- **Branch**: `Skyline/work/20261118_peakAreaTooltipFormat` (pwiz1)
- **Base**: `master`
- **Created**: 2026-11-18
- **Status**: In Progress
- **Module**: `skyline`
- **PR**: [#5055](https://github.com/ProteoWizard/pwiz/pull/5055)

## Objective

The bar tooltip in Peak Areas - Replicate Comparison lists each ion's value as an unformatted
float (`0.###`). Show values with exactly 3 decimals and a thousands separator, and add a
second column with each ion's percent of the replicate total.

## Tasks

- [x] Format values `#,0.000` (current culture); `0.000e0` with Use power of ten
- [x] Add a right-aligned percent-of-total column wherever the Total row is shown
      (not Ratio to Label, not Total normalization; skipped when the total is 0)
- [x] Remove the index-0 special case (first replicate showed shares instead of areas,
      present since the tooltip was added in #2708)
- [x] Add a tooltip check to TestPeakAreaDotpGraph (default normalization, replicate 0)
- [x] Build; run TestPeakAreaDotpGraph in en, fr, ja
- [x] Inspection (inspectcode + CodeInspection test) before push

## Files

- `Controls/Graphs/AreaReplicateGraphPane.cs` - PopulateTooltip formatting and percent column
- `Controls/Graphs/SummaryBarGraphPaneBase.cs` - `ToolTipImplementation.AddLine` with a third cell
- `TestFunctional/TestPeakAreaDotpGraph.cs` - `VerifyAreaTooltip`

## Progress Log

### 2026-11-18 - Implemented formatting and percent column

- Debug Solution build OK; TestPeakAreaDotpGraph passed in en, fr and ja.
- Developer screenshot: TIC normalization showed raw areas with a % sign (x100). TIC divides
  by TicArea/median TIC, so values stay in area units. Collapsed the branch chain: only Maximum
  and Total use percent format; all other methods (TIC, global standards, calibrated, which
  previously got empty cells) use the number format. Added a TIC check to the test; rebuilt and
  passed en, fr, ja.
- Committed c420e152a0; CodeInspection test passed, inspectcode clean for the changed files;
  pushed and opened PR #5055.
