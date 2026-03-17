# TODO-20260317_volcano_plot_lines.md

## Branch Information
- **Branch**: `Skyline/work/20260317_volcano_plot_lines`
- **Base**: `master`
- **Created**: 2026-03-17
- **Status**: In Progress
- **GitHub Issue**: [#4052](https://github.com/ProteoWizard/pwiz/issues/4052)
- **PR**: (pending)

## Summary

Dotted reference lines (fold-change and p-value cutoff lines) disappear from
`FoldChangeVolcanoPlot` after the user opens `VolcanoPlotPropertiesDlg` and
makes any adjustment (e.g. toggles the log checkbox).

## Tasks

- [x] Add repro assertion to `GroupComparisonVolcanoPlotTest.DoTest()` after
      the log-checkbox `OpenVolcanoPlotProperties` block
- [ ] Run the test locally to confirm it fails (reproduces the bug)
- [ ] Investigate root cause in `FoldChangeVolcanoPlot.UpdateGraph()` /
      `VolcanoPlotPropertiesDlg.FormClosing`
- [ ] Fix the root cause
- [ ] Confirm test passes after fix
- [ ] Create PR

## Key Files

- `pwiz_tools/Skyline/TestFunctional/GroupComparisonVolcanoPlotTest.cs` — repro test
- `pwiz_tools/Skyline/Controls/GroupComparison/FoldChangeVolcanoPlot.cs` — plot logic
- `pwiz_tools/Skyline/Controls/GroupComparison/VolcanoPlotPropertiesDlg.cs` — settings dialog

## Technical Notes

The repro assertion was inserted after line 86 (end of log-checkbox toggle block):

```csharp
// Repro for issue #4052: after modifying settings the dotted reference lines must
// still be visible. CurveCount == 5 means fold-change and p-value cutoff lines are present.
WaitForVolcanoPlotPointCount(grid, 125);
RunUI(() => AssertVolcanoPlotCorrect(volcanoPlot, true, 1, 42, 82));
```

`AssertVolcanoPlotCorrect(volcanoPlot, showingBounds=true, ...)` checks
`Assert.AreEqual(5, curveCounts.CurveCount)` — the 3 cutoff lines must be present.

`UpdateGraph()` only adds reference lines when `CutoffSettings.FoldChangeCutoffValid` /
`PValueCutoffValid` — suspect the dialog's `FormClosing` triggers `UpdateGraph(bool filter)`
which under some condition defers the full redraw, leaving `CurveList` cleared.
