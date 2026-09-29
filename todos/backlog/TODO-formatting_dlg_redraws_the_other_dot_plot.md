# Opening the formatting dialog for one dot plot redraws the other one

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

## Design question to settle first

The developer asked to "separate those event handlers". Note that a *genuine* change to
`GroupComparisonAvoidLabelOverlap` arguably **should** update both plots - the setting is deliberately shared
(both handlers carry the comment "Detect changes in settings shared with ..." naming the other plot) and the
menu item appears on both. So decide whether the intent is:

* keep the setting global and only stop the spurious no-op broadcasts (options 1 + 2), or
* make label-overlap a per-plot setting, which is a larger behavior change: two settings, two menu items,
  and the shared-menu comments in both panes stop being true.

## Related

The same shared-subscription mechanism has a second cost, found by the label layout sweep and recorded in
`TODO-20260521_labelSamplingFix.md`: a **hidden** Peak Areas graph still receives these notifications and
runs a full label layout, because `SkylineWindow.ShowGraphPeakArea(false)` only calls `graph.Hide()` and
`GraphSummary.HideOnClose = true`. Whatever shape the fix takes, gating on pane visibility belongs in the
same pass.
