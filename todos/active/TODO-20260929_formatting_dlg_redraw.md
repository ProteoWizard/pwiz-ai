# Opening the formatting dialog for one dot plot redraws the other one

## Branch Information
- **Branch**: `Skyline/work/20260929_formatting_dlg_redraw` (pwiz3 as of 2026-09-29)
- **Module**: `skyline`
- **Base**: `master` (`05b8c93b3a`)
- **Created**: 2026-09-29
- **Status**: In Progress
- **GitHub Issue**: none yet
- **PR**: none yet
- **Commit**: `b2116a5de5` (local, not pushed)

## Objective

With both the volcano plot and the Relative Abundance (protein abundance) plot open, opening the formatting
dialog for either one makes the **other** plot flash with a full redraw. Nothing about the other plot has
changed, so it should not repaint at all.

Reported by the developer 2026-09-29 while looking at
`ProteoBugs/NotEnoughLabels/ExtracellularVesicalMagNet.sky`. Unrelated to the label sampling work on PR
#4495, though it was found alongside it.

## Root cause

One dialog class serves both plots - `SummaryRelativeAbundanceGraphPane.cs:277` and
`FoldChangeVolcanoPlot.cs:864` both construct `VolcanoPlotFormattingDlg` - and its constructor initializes
the "avoid label overlap" checkbox from the shared setting:

```csharp
// VolcanoPlotFormattingDlg.cs:180, in the constructor
layoutLabelsBox.Checked = Settings.Default.GroupComparisonAvoidLabelOverlap;
```

`layoutLabelsBox` has no `Checked` value in the designer, so it starts `false`, and the designer has already
wired its handler (`VolcanoPlotFormattingDlg.Designer.cs:80`). When the setting is `true` - the normal state
for these plots - that assignment flips `false -> true` and **fires `CheckedChanged` during construction**:

```csharp
// VolcanoPlotFormattingDlg.cs:732
private void layoutLabelsBox_CheckedChanged(object sender, EventArgs e)
{
    Settings.Default.GroupComparisonAvoidLabelOverlap = layoutLabelsBox.Checked;   // writes true over true
    _updateGraph(ResultList);
}
```

The write is a no-op in value but not in effect: `ApplicationSettingsBase` raises `PropertyChanged` on every
set, not only on a change. Both plots subscribe to it, by design, because the "avoid label overlap" item is
a shared right-click menu item:

* `FoldChangeVolcanoPlot.OnLabelOverlapPropertyChange` (`FoldChangeVolcanoPlot.cs:825`) - `_labelsLayouts.Clear(); UpdateGraph();`
* `SummaryRelativeAbundanceGraphPane.OnLabelOverlapPropertyChange` (`SummaryRelativeAbundanceGraphPane.cs:320`) - `_labelsLayout = null; GraphSummary.UpdateUI();`

So merely opening the dialog rebuilds the other plot's graph **and** discards its saved label layout, forcing
a fresh simulated-annealing run. That is the flash. It happens in both directions, since one dialog class
serves both plots.

## Fix options

1. **Do not fire the handler while initializing** - set `layoutLabelsBox.Checked` before the handler is
   wired, or guard the handler with a loading flag. Smallest change, fixes the reported symptom exactly.
2. **Do not write an unchanged value** - `if (Settings.Default.GroupComparisonAvoidLabelOverlap != layoutLabelsBox.Checked)`
   before assigning. Also stops any other caller from broadcasting a no-op, so it is worth doing regardless
   of option 1.

Both are worth taking; 1 alone leaves the redundant-broadcast hazard, 2 alone leaves the constructor calling
`_updateGraph` for no reason.

## Design decision (settled 2026-09-29)

**The setting stays global: toggling the checkbox updates both graphs.** Developer's call. So the scope is
only to stop the *spurious* broadcast - the one the constructor causes by writing the setting its own value -
and NOT to give each plot its own setting. The shared right-click menu item and the
"Detect changes in settings shared with ..." comments in both panes stay correct.

Do not "separate the event handlers" in the sense of making label-overlap per-plot. The cross-plot
notification is wanted; only the no-op that triggers it on dialog open is not.

## Fix applied

`_initializing` flag on the dialog, set for the body of the private constructor and checked by both
`CheckedChanged` handlers - the `_inUpdate` convention already used in `Controls/` (`PcaPlot`,
`CalibrationGraphControl`, `RTLinearRegressionGraphPane`).

`advancedCheckBox` had the same shape and is guarded too, but note what that does and does not fix. Its
handler only calls `UpdateAdvancedColumns()`, which the constructor already calls explicitly on the next
line, so the guard stops the duplicate call. It does **not** stop the redundant settings write, because
`UpdateAdvancedColumns` writes the setting inside its own assignment chain:

```csharp
_symbolCombo.Visible = _pointSizeCombo.Visible =
    Settings.Default.ShowAdvancedVolcanoPlotFormatting = advancedCheckBox.Checked;
```

So opening the dialog still writes `ShowAdvancedVolcanoPlotFormatting` its own value once. That is harmless
today - nothing redraws on that setting - and untangling the chained assignment is not worth doing on this
branch. Worth knowing if anything ever starts listening to it.

## Verification

The symptom cannot be seen in a screenshot. The layout is deterministic (that is what
`TestLabelLayoutDeterminism` pins), so a discarded layout is recomputed to the same placements and the plot
looks identical with or without the bug - it only repaints. So the test asserts the **mechanism**: count
`Settings.PropertyChanged` notifications for `GroupComparisonAvoidLabelOverlap` while the dialog opens and
closes, and require zero.

`VerifyOpeningDialogDoesNotBroadcastOverlapSetting` was added to the existing `VolcanoPlotFormattingTest`
flow rather than as a new `[TestMethod]`, since each functional test carries roughly 15 s of fixed overhead.
It sets the setting **true** first: the checkbox starts unchecked, so only a true setting makes loading it
change the value and fire the handler. A version of this test written without that line passes with the bug
present and is worthless.

Proven by reverting the fix and rebuilding (first attempt at this was invalid - a running Skyline-daily held
the build output, the build was blocked, and the test ran against the previous binary, which still had the
fix; the binary timestamp is the thing to check):

| | with fix | without fix |
|---|---|---|
| `TestVolcanoPlotFormatting` | pass | **fail** - `Expected:<0>. Actual:<1>` |
| `TestVolcanoPlotLayout` | pass | - |
| `TestPeakAreaRelativeAbundanceGraph` | pass | - |
| `TestLabelLayoutDeterminism` | pass | - |

Still unconfirmed by a human: that the flash is visibly gone. Use a document with enough label work to see
it - `ExtracellularVesicalMagNet.sky` with both formatting rules ticked, not a small document like
`BSA-Training.sky`.

## Not a bug: OK-ing the dialog updates both plots when rules changed

Checked during the same session. **Confirmed by the developer that it does not happen when nothing is
changed**, so there is nothing to fix here.

The OK path is a different mechanism from the constructor bug above, which is why the `_initializing` guard
does not touch it. `FoldChangeVolcanoPlot.ShowFormattingDialog` on OK calls

```csharp
EditGroupComparisonDlg.ChangeGroupComparisonDef(true, GroupComparisonModel, GroupComparisonDef);
```

which goes to `Program.MainWindow.ModifyDocument(...)` - a **document** change, and every graph in Skyline
refreshes on those. `GroupComparisonModel.ApplyChangesToDocument` returns the document unmodified when the
definition is unchanged, which is why the no-edit case is already clean.

So a rule edit refreshing the Relative Abundance plot is ordinary architecture, not a defect, even though
that plot shares nothing with the volcano's rules. Making panes ignore document changes they do not care
about is a large architectural change and is not warranted by this.

## pwiz3 checkout note

That checkout had never been brought current: its `pwiz_data_cli.dll` dated from 2021-09-28, so
`ProteowizardWrapper` would not compile against master's C#. Fixed by a full native build
(`...updated 1911 targets...`), plus `MSBuild Skyline.sln /t:Restore` for the WebView2 package references.

Its `build_skyline_64.bat` pinned `toolset=msvc-14.1` (Visual Studio 2017), which is not usable on this
machine - bjam reports "Did not find command for MSVC toolset" and fails 730 targets, while the wrapping
`.bat` still exits 0, so the real verdict is the `...failed updating N targets...` line in `build64.log`.
Changed to `toolset=msvc-14.3` to match pwiz2's copy (the file is untracked in every checkout, so this is a
local change only).

## Out of scope for this branch - selection-change churn

The developer also sees both plots refresh when the **selection** changes, and judged it valid: the selected
point's label formatting legitimately differs from what the rules give it, so the plot showing the selection
has to rebuild. Both plots highlight the selection, so both redrawing is correct. Noted as annoying rather
than wrong.

The developer asked whether the layout refresh could be skipped on selection change, updating only the
formatting of the un/selected pair. **The layout is already incremental - that is not where the cost is.**
`LabelLayout.ComputePlacementsSimulatedAnnealing` splits points by whether they have a saved placement:

```csharp
if (savedPoint != null)
    placements[point] = ClampToAllowed(topCenter, size);   // fixed, never added to movablePoints
else
    movablePoints.Add(point);                              // only labels never placed before
```

and the anneal loop exits on `!movablePoints.Any()`. A selection change restores every existing label at its
saved position and optimizes at most the one label that just appeared.

Where the cost actually is, in order:

1. **Full teardown and rebuild of `CurveList` and `GraphObjList`**, recreating every `TextObj` - 26 in the
   ticked-rules case, 4844 under a label-everything rule. This dominates the visible flash.
2. **An O(N^2) pairwise cost matrix computed before the movable check.** `baseCosts` measures every label
   and `pairCosts` loops every i/j pair, with no early exit when `movablePoints` is empty, so ~7000 pair
   computations run on a 118-label plot only to find nothing can move. Cheap, self-contained fix: return the
   restored placements before the precompute when nothing is movable.
3. The debounce plus worker-thread round trip and the repaint.

So item 2 is a small targeted win, and item 1 is the real one - a rebuild-granularity refactor, not a
one-line guard, which should not ride along with this branch.

**A strict "swap the pair's formatting" shortcut is not sufficient on its own**: selected points are labeled
unconditionally, so selecting a point no rule labels *adds* a label and deselecting *removes* one. The label
set changes, not only its formatting, so any incremental path needs add and remove, not just restyle.

## Related

The same shared-subscription mechanism has a second cost, found by the label layout sweep and recorded in
`TODO-20260521_labelSamplingFix.md`: a **hidden** Peak Areas graph still receives these notifications and
runs a full label layout, because `SkylineWindow.ShowGraphPeakArea(false)` only calls `graph.Hide()` and
`GraphSummary.HideOnClose = true`. Whatever shape the fix takes, gating on pane visibility belongs in the
same pass.
