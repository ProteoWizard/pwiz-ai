# TODO-20260328_abundance_box_plot.md

## Branch Information
- **Branch**: `Skyline/work/20260328_abundance_box_plot`
- **Base**: `master`
- **Created**: 2026-03-28
- **Status**: In Progress
- **GitHub Issue**: (pending)
- **PR**: (pending)
- **Prior Work**: [PR #3603](https://github.com/ProteoWizard/pwiz/pull/3603) by Eduardo (no longer on team)

## Objective

Add an **Abundance Box Plot** graph type to Skyline's Peak Areas graphs. This plot
visualizes the distribution of protein (or peptide) abundances across replicates as
box-and-whisker plots, enabling quick assessment of data quality, batch effects, and
normalization effectiveness.

## Prior Work Assessment (PR #3603)

Eduardo created an initial implementation in Sep-Oct 2025 (6 commits, branch
`Skyline/work/2025_09_17_CreateReplicateAbundanceBoxPlot`). That branch is 379 commits
behind master. Key findings from code review:

### Salvageable Code
- **BoxPlotBarItem.cs** (293 lines) - Custom ZedGraph box plot rendering. ZedGraph has
  no native box plot support, so this extends `HiLowBarItem` to draw whiskers, caps,
  median line, and outlier circles. Well-structured rendering code.
- **BoxPlotDataUtil** - Statistical calculations: Q1, Q3, IQR, whiskers at 1.5*IQR
  boundaries, outlier detection. Correct implementation.
- **BoxPlotTag / BoxPlotData** - Data structures for box plot statistics.

### Needs Rework
- **Wrong integration pattern**: Used `DataboundGraph` (standalone floating form)
  instead of the `GraphSummary` / `GraphTypeSummary` pattern used by all other Peak Area
  graphs (Replicate Comparison, Peptide Comparison, Relative Abundance, CV Histogram,
  2D Histogram). Must be rewritten to follow the canonical pattern.
- **Hardcoded English strings**: "Group By", "Normalized To", "Replicate", "Log2 Peak
  Area" violate the localization requirement. All user-facing text must use
  `GraphsResources.resx`.
- **No tests**: No functional or unit tests were written.
- **Copy Data incomplete**: `BoxPlotBarItemDataHandler` has commented-out code and does
  not produce useful output.
- **Code quality issues**: Casual comments, `camelCase` method names instead of
  `PascalCase`, unused `Google.Protobuf.WellKnownTypes` import.
- **Integration files**: ViewMenu, SkylineGraphs.cs, Skyline.Designer.cs changes cannot
  be merged due to 379-commit divergence and conflicting changes.

### Decision
**Start fresh from master**, porting the BoxPlotBarItem rendering and BoxPlotDataUtil
statistics code. Rewrite the integration using the GraphSummary pattern.

## Feature Specification

### Purpose
Display box-and-whisker plots showing the distribution of protein/peptide abundance
values across replicates. Each replicate gets one box plot showing the spread of all
protein abundances measured in that replicate. This enables:
- Quick visual comparison of abundance distributions between replicates
- Detection of batch effects or systematic biases
- Assessment of normalization effectiveness
- Identification of outlier replicates

### Data Source
- **Per replicate**: Collect all protein abundance values using
  `Protein.GetProteinAbundances()` for each molecule group in the document
- **Log2 transform**: Display as log2(abundance + 1) for better visualization of the
  typically log-normal distribution
- **One box per replicate**: Each box represents the distribution of all protein
  abundances in that replicate

### Visualization
- **Box**: Q1 (25th percentile) to Q3 (75th percentile), filled with color
- **Median line**: Horizontal line inside box at the 50th percentile
- **Whiskers**: Extend to the most extreme data points within 1.5 * IQR of the box
- **Caps**: Horizontal lines at whisker endpoints
- **Outliers**: Open circles for data points beyond the whiskers
- **X-axis**: Replicate names (rotated 90 degrees for readability)
- **Y-axis**: Log2 Peak Area

### Integration Pattern (GraphSummary approach)
Follow the same pattern as Relative Abundance, Replicate Comparison, etc.:

1. **Add `GraphTypeSummary.box_plot`** enum value in `GraphSummary.cs`
2. **Create `SummaryBoxPlotGraphPane`** extending `SummaryGraphPane`:
   - Implements `UpdateGraph(bool selectionChanged)`
   - Uses `BoxPlotBarItem` for rendering
   - Handles document change updates
3. **Register in `AreaGraphController.OnUpdateGraph()`** to instantiate the pane
4. **Add to `BuildAreaGraphMenu()`** in `SkylineGraphs.cs` for context menu integration
5. **Add View menu item** under Peak Areas submenu
6. **Add localization string** in `GraphsResources.resx` and update `CustomToString()`
7. **Settings persistence** via `Settings.Default.AreaGraphTypes`

### Context Menu Features
- **Group By**: Group replicates by annotation values (e.g., Condition, BioReplicate).
  When grouped, boxes are colored by group and legend is shown.
- **Normalize**: Support existing `NormalizeOption` values used by other Peak Area
  graphs, plus median normalization (shift each replicate's distribution so medians
  align with the global median).
- **Copy Data**: Tab-separated output with columns: Replicate, Min, Q1, Median, Q3,
  Max, Outliers.

### Localization
All user-facing strings must be in `GraphsResources.resx` with corresponding entries in
`GraphsResources.ja.resx` and `GraphsResources.zh-CHS.resx` (Japanese and Chinese
translations can be placeholder copies initially).

### Testing
- Create a functional test (e.g., `TestAbundanceBoxPlotGraph`) following the pattern of
  `TestPeakAreaRelativeAbundanceGraph`
- Verify: graph creation, data correctness, group-by behavior, normalization,
  copy data output
- All test assertions must use resource strings, not English text

## Progress

### Completed
- [x] Checked out PR #3603 branch for code review (in pwiz-work1)
- [x] Assessed salvageable vs. needs-rework code
- [x] Created new branch from master (`Skyline/work/20260328_abundance_box_plot`)
- [x] Created this TODO with feature specification

### Remaining
- [ ] Port `BoxPlotBarItem` rendering code from PR #3603 (clean up naming, imports)
- [ ] Port `BoxPlotDataUtil` statistics code (rename to PascalCase)
- [ ] Add `GraphTypeSummary.box_plot` enum value
- [ ] Create `SummaryBoxPlotGraphPane` extending `SummaryGraphPane`
- [ ] Register in `AreaGraphController.OnUpdateGraph()`
- [ ] Add View menu item under Peak Areas
- [ ] Add context menu integration via `BuildAreaGraphMenu()`
- [ ] Add localization strings to `GraphsResources.resx`
- [ ] Implement Group By support
- [ ] Implement Normalize support
- [ ] Implement Copy Data handler
- [ ] Create functional test
- [ ] Build succeeds
- [ ] All tests pass
- [ ] Run CodeInspection
- [ ] Create PR

## Key Files
- `pwiz_tools/Skyline/Controls/Graphs/BoxPlotBarItem.cs` (new - port from PR #3603)
- `pwiz_tools/Skyline/Controls/Graphs/SummaryBoxPlotGraphPane.cs` (new)
- `pwiz_tools/Skyline/Controls/Graphs/GraphSummary.cs` (add enum value)
- `pwiz_tools/Skyline/Controls/Graphs/GraphsResources.resx` (add strings)
- `pwiz_tools/Skyline/Controls/Graphs/AreaGraphController.cs` (register pane)
- `pwiz_tools/Skyline/SkylineGraphs.cs` (menu item, show method)
- `pwiz_tools/Skyline/Menus/ViewMenu.cs` (menu click handler)
