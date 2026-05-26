# TODO-20260317_volcano_plot_lines.md

## Branch Information
- **Branch**: `Skyline/work/20260317_volcano_plot_lines`
- **Base**: `master`
- **Created**: 2026-03-17
- **Status**: Completed
- **GitHub Issue**: [#4052](https://github.com/ProteoWizard/pwiz/issues/4052)
- **PR**: [#4075](https://github.com/ProteoWizard/pwiz/pull/4075)

## Summary

Dotted reference lines (fold-change and p-value cutoff lines) disappear from
`FoldChangeVolcanoPlot` after the user opens `VolcanoPlotPropertiesDlg` and
makes any adjustment (e.g. toggles the log checkbox).

## Tasks

- [x] Add repro assertion to `GroupComparisonVolcanoPlotTest.DoTest()` after
      the log-checkbox `OpenVolcanoPlotProperties` block
- [x] Run the test locally to confirm it fails (reproduces the bug)
- [x] Investigate root cause in `FoldChangeVolcanoPlot.UpdateGraph()`
- [x] Fix the root cause
- [x] Confirm test passes after fix
- [x] Create PR

## Progress Log

### 2026-03-25 - Merged

PR [#4075](https://github.com/ProteoWizard/pwiz/pull/4075) merged into master.
Merge commit: `5e2b54817b8014249bf7c535bc4f7cf9ffbac8b5`

## Resolution

**Status**: Merged 2026-03-25

Fixed volcano plot reference lines disappearing after opening `VolcanoPlotPropertiesDlg`.
Root cause was `AdjustLocations()` only being called inside the `if (_dataChanged)` block;
added an `else` branch to call it directly when only cutoff settings changed.

## Root Cause

`FoldChangeVolcanoPlot.UpdateGraph()` rebuilds the curve list and creates new
reference line `LineItem`s with placeholder coordinates `(Y=[0,0]` for
fold-change lines, `X=[0,0]` for the p-value line). `AdjustLocations()` is
responsible for setting real axis-spanning coordinates, but it was only invoked
via `AxisChange()` inside the `if (_dataChanged)` block. When only cutoff
settings changed (not the underlying data), `_dataChanged` was `false`,
`AxisChange()` was skipped, `AdjustLocations()` was never called, and the
reference lines remained as invisible zero-length segments.

## Fix

Added an `else` branch in `FoldChangeVolcanoPlot.UpdateGraph()` to call
`AdjustLocations(zedGraphControl.GraphPane)` directly when `_dataChanged` is
`false`:

```csharp
else
{
    // Only cutoff settings changed; AxisChange() was not called so reposition
    // the reference lines manually to span the current axis range (issue #4052).
    AdjustLocations(zedGraphControl.GraphPane);
}
```

## Key Files

- `pwiz_tools/Skyline/TestFunctional/GroupComparisonVolcanoPlotTest.cs` — repro test (`AssertCutoffLinesVisible`)
- `pwiz_tools/Skyline/Controls/GroupComparison/FoldChangeVolcanoPlot.cs` — fix location: `UpdateGraph()`, after the `if (_dataChanged)` block
