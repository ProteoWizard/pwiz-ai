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

- [ ] Let the user choose which attribute(s) drive color and which drive symbol (replace the
      hardcoded level 0 -> symbol, level 1 -> color), including color-only or one-attribute-for-both
- [ ] Make the legend usable with many categories (scroll/page/summarize instead of hiding at >=16)
- [ ] Allow custom color and symbol assignment per category, persisted with the view
- [ ] Handle palette exhaustion gracefully so distinct categories stay distinguishable
- [ ] Show percent variance explained on axis labels; consider a scree plot
- [ ] Add hover tooltips and optional point labels (protein / peptide / replicate)
- [ ] Confirm and document the grid<->PCA color relationship
- [ ] Optional: confidence ellipses / group centroids
- [ ] Regression / functional test coverage for the new behavior

## Regression Test

- **Test name**: (filled in once written)
- **Test project**: TestFunctional (likely)
- **Fails on master**: (n/a until written - this is an enhancement, not a bug fix)
- **Passes on fix**: (TBD)

This is an enhancement rather than a bug fix, so there is no master-red baseline. New
functional test(s) will exercise the added color/symbol configuration and legend behavior.

## Progress Log

### 2026-06-12 - Session Start

- Created issue #4296 from investigation of `PcaPlot.cs` and the clustering classes.
- Created branch `Skyline/work/20260612_pca_plot_usability` and this TODO.
- Next: decide scope for first PR (likely user control over color/symbol encoding + legend
  legibility) and design the UI hook (extend the PCA plot controls vs. the ClusteringEditor).

## Context for Next Session

The plot currently reuses clustering header levels with a fixed encoding. The most impactful
first deliverable is probably (a) a control to choose color attribute and symbol attribute, and
(b) a legend that survives many categories. Persistence goes through `PcaChoice` /
`GetPersistentString` in `PcaPlot.cs`.
