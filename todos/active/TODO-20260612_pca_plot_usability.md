# Make PCA plots easier to use and more useful

## Branch Information
- **Branch**: `Skyline/work/20260612_pca_plot_usability`
- **Base**: `master`
- **Created**: 2026-06-12
- **Status**: In Progress
- **GitHub Issue**: [#4296](https://github.com/ProteoWizard/pwiz/issues/4296)
- **PR**: (pending)

## Objective

Make PCA plots easier to interpret and more useful by giving users control over how
points are encoded (color/symbol) and making the plot legible when there are many
categories.

## Background (from investigation)

Key files:
- `pwiz_tools/Skyline/Controls/Clustering/PcaPlot.cs` - plot UI, point/color/symbol assignment
- `pwiz_tools/Shared/Common/DataBinding/Clustering/ReportColorScheme.cs` - color assignment shared with the clustered grid
- `pwiz_tools/Shared/Common/DataBinding/Controls/ClusteringEditor.cs` - clustering configuration UI
- `pwiz_tools/Shared/Common/DataBinding/Clustering/Clusterer.cs`, `ClusteringSpec.cs`, `ClusteredProperties.cs`

Findings:
- Color/symbol mapping is hardcoded in `PcaPlot.UpdateGraph` (`symbolHeaderLevel = 0`,
  `colorHeaderLevel = 1`): header level 0 -> symbol shape, level 1 -> color. No user control.
- Point colors come from the same `ReportColorScheme` that colors the grid header cells, so
  colors *are* consistent with the grid -- but only the second header column's colors line up,
  because the first header column is encoded as a *symbol shape* instead of a color.
- Legend is hidden when `CurveList.Count >= 16` (`PcaPlot.cs:263`), i.e. it disappears exactly
  in the dense case where it is needed.
- Only 10 symbol shapes (reused via modulo); discrete colors auto-assigned. Collisions when
  there are many categories.
- No custom per-category color/symbol assignment. No percent-variance-explained / scree plot.
  No hover tooltips or optional point labels.

## Tasks

- [x] Let the user choose which attribute(s) drive color and which drive symbol (replace the
      hardcoded level 0 -> symbol, level 1 -> color), including color-only or one-attribute-for-both
- [x] Make the legend usable with many categories (rebuilt from distinct color + symbol values so
      legend size is the sum, not the product, of categories; no longer hidden at >=16)
- [ ] Replace the ZedGraph built-in legend with a custom legend control: own panel beside the graph,
      vertical scrollbar, grouped swatch/shape entries, and click-to-select the replicates/peptides
      for the points sharing a value (uses the IdentityPath/ReplicateName already on each point)
- [ ] Allow custom color and symbol assignment per category, persisted with the view
- [ ] Handle palette exhaustion gracefully so distinct categories stay distinguishable
- [ ] Show percent variance explained on axis labels; consider a scree plot
- [ ] Add hover tooltips and optional point labels (protein / peptide / replicate)
- [ ] Confirm and document the grid<->PCA color relationship
- [ ] Optional: confidence ellipses / group centroids
- [ ] Regression / functional test coverage for the new behavior

## Regression Test

- **Test name**: ClusteredHeatMapTest.TestClusteredHeatMap (extended)
- **Test project**: TestFunctional
- **Fails on master**: n/a (enhancement, no master-red baseline)
- **Passes on fix**: yes - 0 failures, 36s (2026-06-12)

This is an enhancement rather than a bug fix, so there is no master-red baseline. The existing
PCA coverage in ClusteredHeatMapTest was extended to set a non-default encoding (both channels
off), confirm it renders (curve count does not grow) and that the new SymbolLevel/ColorLevel
persist through a document save/reopen round-trip.

## Progress Log

### 2026-06-12 - Session Start

- Created issue #4296 from investigation of `PcaPlot.cs` and the clustering classes.
- Created branch `Skyline/work/20260612_pca_plot_usability` and this TODO.
- Next: decide scope for first PR (likely user control over color/symbol encoding + legend
  legibility) and design the UI hook (extend the PCA plot controls vs. the ClusteringEditor).

### 2026-06-12 - Session 1: encoding control + legend (commit 0ed2a5ff8)

Implemented the first slice (color/symbol control + legend), all in the PCA plot's own controls
(no ClusteringEditor change needed):

- `PcaPlot.PcaChoice` gained `SymbolLevel` and `ColorLevel` (defaults 0 and 1 to preserve the old
  behavior; `LEVEL_NONE = -1` disables a channel). Persistence appends two ints; `ParsePersistentString`
  accepts both the old 3-part and new 5-part strings, so existing saved views still load.
- `UpdateGraph` now reads the available header-level captions for the current dataset, constrains
  the choice, and populates two new combo boxes (`comboColorBy`, `comboSymbolBy`, "Color by:" /
  "Symbol by:" on a second control row; the graph moved down to y=90).
- `BuildCurvesAndLegend` draws the data points (real curves now carry empty labels so they stay out
  of the legend) and builds the legend from distinct color values and distinct symbol values via
  zero-point "legend-only" curves. When one attribute drives both channels they merge into one
  group. Legend size is now sum-of-categories, not product, and it is no longer force-hidden at >=16.
- Added `ClusteringResources.PcaPlot_Encoding_None` = "(None)".
- Gotcha hit and fixed: `LineItem.Label.FontSpec` is null by default in ZedGraph, so a header entry
  cannot set bold there (NRE). Group headers are symbol-less entries instead.

Build: green (full solution). Tests: ClusteredHeatMapTest 0 failures (36s), PcaTest 0 failures.

Not yet done / next: the remaining issue scope (custom per-category color/symbol assignment,
palette exhaustion, % variance explained / scree plot, tooltips/labels, ellipses).

### 2026-06-12 - Session 2: visual verification + custom legend direction

- Verified the encoding + legend slice in the running app on `Rat_plasma.sky` (Color by = Condition,
  Symbol by = SubjectId). Two-group legend renders correctly (Condition: Diseased/Healthy color
  swatches; SubjectId: per-subject shapes); combos and graph layout look right, no clipping.
- New direction from Nick (issue comment): replace the ZedGraph built-in legend with a custom legend
  CONTROL - own panel beside the graph, vertical scrollbar for many entries, and click-to-select the
  replicates/peptides for the points sharing a clicked value. The per-point PointInfo (IdentityPath +
  ReplicateName) is already available to drive that selection. This supersedes the ZedGraph legend.
- Open decision: fold the custom legend into this branch before any PR, vs. ship the current slice as
  PR #1 and do the custom legend as PR #2.

## Context for Next Session

The plot currently reuses clustering header levels with a fixed encoding. The most impactful
first deliverable is probably (a) a control to choose color attribute and symbol attribute, and
(b) a legend that survives many categories. Persistence goes through `PcaChoice` /
`GetPersistentString` in `PcaPlot.cs`.
