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

Add a **Relative Abundance Comparison** graph to Skyline's Peak Areas graphs, accessible
via **View > Peak Areas > Relative Abundance Comparison**. This plot uses box-and-whisker
plots to provide an overview of the same abundance data points shown in the existing
**Relative Abundance** plot, but summarized as distributions -- either across all
replicates together or per-replicate. Where the Relative Abundance plot shows individual
peptides ranked by Log Peak Area for a single view, the Relative Abundance Comparison
shows how those points are distributed, enabling quick comparison across replicates.

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
Provide a distributional overview of the same abundance data shown in the Relative
Abundance plot. The Relative Abundance plot (see `ai/.tmp/screenshots/relative_abundance_graph.png`)
shows individual peptides ranked by Log Peak Area, with the selected peptide highlighted.
The Relative Abundance Comparison plot summarizes these points as box-and-whisker plots:
- **All replicates**: A single box plot showing the overall distribution
- **Per replicate**: One box per replicate, enabling quick visual comparison

This enables:
- Quick visual comparison of abundance distributions between replicates
- Detection of batch effects or systematic biases
- Assessment of normalization effectiveness
- Identification of outlier replicates

### Data Source
- **Same data as Relative Abundance**: Peptide/protein abundance values that appear as
  individual dots in the Relative Abundance plot
- **Per replicate**: Collect abundance values using `Protein.GetProteinAbundances()` for
  each molecule group in the document
- **Log scale**: Display on log scale (matching Relative Abundance's Log Peak Area axis)
- **One box per replicate**: Each box represents the distribution of all protein
  abundances in that replicate

### Visualization
- **Box**: Q1 (25th percentile) to Q3 (75th percentile), filled with color
- **Median line**: Horizontal line inside box at the 50th percentile
- **Whiskers**: Extend to the most extreme data points within 1.5 * IQR of the box
- **Caps**: Horizontal lines at whisker endpoints
- **Outliers**: Open circles for data points beyond the whiskers
- **X-axis**: Replicate names (rotated 90 degrees for readability)
- **Y-axis**: Log Peak Area (matching the Relative Abundance plot's Y-axis)

### Relationship to Relative Abundance Plot
The existing Relative Abundance plot (View > Peak Areas > Relative Abundance) shows
individual peptides ranked by Log Peak Area for the currently active replicate. Each
dot is one peptide's abundance. Switching replicates changes which abundance values
are shown. The Relative Abundance Comparison will show the distribution of those
same points as box plots, providing a bird's-eye comparison across replicates.

Reference screenshot: `ai/.tmp/screenshots/relative_abundance_graph.png`

### Shared Data Architecture
The Relative Abundance graph's data pipeline was extensively optimized in a 12-phase
performance sprint (PR [#3730](https://github.com/ProteoWizard/pwiz/pull/3730), see
`ai/todos/completed/2025/12/TODO-20251221_relative_abundance_perf.md`). It uses:

- **`SummaryRelativeAbundanceGraphPane.GraphData`** - Background-computed, immutable
  result containing all abundance points with per-replicate values
  (`GraphPointData.ReplicateAreas`)
- **`ReplicateCachingReceiver`** - Caches results per replicate with stale-while-
  revalidate, completion listeners, and identity-based invalidation
- **Incremental updates** - Two-phase change detection using `ReferenceEquals` on
  immutable DocNodes, O(n + k log k) merge for small changes
- **Normalization-aware cache invalidation** - Smart handling of EQUALIZE_MEDIANS,
  GLOBAL_STANDARDS, etc.

The Relative Abundance Comparison graph should **share this same `GraphData`** rather
than computing abundance values independently. The `GraphData` already contains
`GraphPointData.ReplicateAreas` (a lookup from replicate index to abundance values)
for every peptide/protein.

**Key difference from the existing Relative Abundance plot**: The dot-plot only needs
one replicate at a time (or the sum of all replicates), so it uses
`ReplicateCachingReceiver` to cache and display a single set of points. The Relative
Abundance Comparison plot needs **all replicates simultaneously** to show one box per
replicate. It should begin calculating all replicates and update the graph as each
replicate's points become available. The `ReplicateCachingReceiver` infrastructure
already supports this -- calculations continue in the background even when switching
away, and results are cached per replicate.

**Efficient box plot construction**: The abundance values in `GraphData` are already
sorted (the Relative Abundance plot sorts by Y value for ranking). Since the values
are pre-sorted, median and quartile calculations are O(1) index lookups, and outlier
detection is O(n) linear scan. No additional sorting is needed.

**Shared settings**: When the user changes a setting that affects the Relative
Abundance plot (e.g., switching between peptide and protein mode, changing
normalization method), the same change automatically applies to this plot because
both views consume the same underlying `GraphData`.

### Integration Pattern (GraphSummary approach)
Follow the same pattern as Relative Abundance, Replicate Comparison, etc.:

1. **Add `GraphTypeSummary.abundance_comparison`** enum value in `GraphSummary.cs`
2. **Create `SummaryAbundanceComparisonGraphPane`** extending or reusing
   `SummaryRelativeAbundanceGraphPane`'s data pipeline:
   - Shares the same `GraphData` / `ReplicateCachingReceiver` infrastructure
   - Kicks off computation for **all replicates** simultaneously, updating the
     graph progressively as each replicate's `GraphData` becomes available
   - Uses `BoxPlotBarItem` for rendering box-and-whisker plots
   - Computes Q1/median/Q3/whiskers from pre-sorted abundance values (O(1) per
     quartile, O(n) for outliers -- no additional sorting needed)
3. **Register in `AreaGraphController.OnUpdateGraph()`** to instantiate the pane
4. **Add to `BuildAreaGraphMenu()`** in `SkylineGraphs.cs` for context menu integration
5. **Add View > Peak Areas > Relative Abundance Comparison** menu item
6. **Add localization string** in `GraphsResources.resx` and update `CustomToString()`
7. **Settings persistence** via `Settings.Default.AreaGraphTypes`

### Context Menu Features
- **Group By**: Group replicates by annotation values (e.g., Condition, BioReplicate).
  When grouped, boxes are colored by group and legend is shown.
- **Normalize**: Support existing `NormalizeOption` values used by other Peak Area
  graphs (the graph inherits normalization handling from the shared data pipeline).
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
- [x] Port `BoxPlotBarItem` rendering code from PR #3603 (clean up naming, imports)
- [x] Port `BoxPlotDataUtil` statistics code (renamed to `BoxPlotStatistics`, PascalCase)
- [x] Add `GraphTypeSummary.abundance_comparison` enum value
- [x] Create `AreaAbundanceComparisonGraphPane` (POC - synchronous UI-thread computation)
- [x] Register in `AreaGraphController.OnUpdateGraph()`
- [x] Add View > Peak Areas > Relative Abundance Comparison menu item
- [x] Add context menu integration via `BuildAreaGraphMenu()`
- [x] Add localization strings to `GraphsResources.resx`, `Skyline.resx`, `ViewMenu.resx`
- [x] Implement Copy Data handler (`BoxPlotBarItemDataHandler`)
- [x] Log-space statistics for symmetric outlier detection on log-normal abundance data
- [x] Log/linear scale toggle (shares `RelativeAbundanceLogScale` setting with dot-plot)
- [x] Y-axis anchored at zero in linear mode (via `Draw()` override)
- [x] Null safety during document loading
- [x] Context menu cleanup (removed inapplicable items, CV Values from RA dot-plot)
- [x] Fixed graph relocation bug: existing visible graphs now just Activate() instead
      of being relocated to another pane
- [x] Sibling co-location: abundance graphs prefer each other when newly created
- [x] HideOnClose forms correctly restore to remembered position
- [x] Build succeeds

### Remaining
- [ ] Refactor to share `ReplicateCachingReceiver` data pipeline with
      `SummaryRelativeAbundanceGraphPane` (background computation, incremental updates)
- [ ] Implement Group By support (replicate annotations)
- [ ] Implement Normalize support (via shared data pipeline)
- [ ] Create functional test
- [ ] All tests pass
- [ ] Run CodeInspection
- [ ] Create PR

## Key Files
- `pwiz_tools/Skyline/Controls/Graphs/BoxPlotBarItem.cs` (new - port from PR #3603)
- `pwiz_tools/Skyline/Controls/Graphs/AreaAbundanceComparisonGraphPane.cs` (new)
- `pwiz_tools/Skyline/Controls/Graphs/GraphSummary.cs` (enum value, CustomToString)
- `pwiz_tools/Skyline/Controls/Graphs/GraphsResources.resx` (localization strings)
- `pwiz_tools/Skyline/Controls/Graphs/AreaGraphController.cs` (register pane)
- `pwiz_tools/Skyline/SkylineGraphs.cs` (menu, show method, co-location, context menu)
- `pwiz_tools/Skyline/Menus/ViewMenu.cs` (menu click handler, checked state)
- `pwiz_tools/Skyline/Skyline.Designer.cs` (context menu item)
- `pwiz_tools/Skyline/Skyline.resx` (context menu text)

## Related TODOs
- `ai/todos/completed/2025/12/TODO-20251221_relative_abundance_perf.md` - 12-phase
  performance sprint that built the background computation, `ReplicateCachingReceiver`,
  incremental updates, and normalization-aware caching used by the Relative Abundance
  graph. This feature should share that infrastructure.
