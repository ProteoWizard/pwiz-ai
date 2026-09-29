# Selecting a protein in the volcano plot leaves the chromatograms empty

## Objective

Clicking a protein in the volcano plot selects it in the Targets tree, but the chromatogram graphs stay
**empty**. Clicking the same protein in the tree populates them. Same end selection, two different results.

Reported by the developer 2026-09-29 on `ProteoBugs/NotEnoughLabels/ExtracellularVesicalMagNet.sky`.
Unrelated to the label sampling work (PR #4495) and to the formatting-dialog redraw
(`TODO-20260929_formatting_dlg_redraw.md`).

## Root cause: NOT established

This is a narrowing, not an answer. Do not start coding from it.

### The path a plain click takes

`FoldChangeVolcanoPlot.ClickSelectedRow` with no modifier key:

```csharp
DotPlotUtil.Select(_skylineWindow, docNode.IdentityPath);
return true; // No need to call UpdateGraph
```

`DotPlotUtil.Select` (`Controls/Graphs/DotPlotUtil.cs:153`):

```csharp
var alreadySelected = IsPathSelected(skylineWindow.SelectedPath, identityPath);
if (alreadySelected)
    skylineWindow.SequenceTree.SelectedNode = null;
skylineWindow.SelectedPath = identityPath;      // -> SequenceTree.SelectedPath -> SelectNode(...)
skylineWindow.UpdateGraphPanes();
```

`SequenceTree.SelectedPath`'s setter calls `SelectNode`, which does
`SelectedNodes.Clear(); AddSelectedNode(...); SelectedNode = SelectedNodes.First();`.

### Ruled out

* **"No chromatogram update is requested."** `SkylineWindow.UpdateGraphPanes()` (`SkylineGraphs.cs:835`)
  builds its update list starting from `_listGraphChrom.Where(g => g.Visible)`, so visible chromatogram
  graphs *are* asked to update.
* **"The protein's tree children are not materialized yet."** A selected protein is expanded through doc
  nodes, not tree children - `PeptidesAndTransitionGroups.Get` iterates `proteinNode.DocNode.Molecules`
  (`PeptidesAndTransitionGroups.cs:109`). Lazy tree population is not the mechanism.

### Where to look first

`GraphChromatogram` derives what to draw from `_stateProvider.SelectedNodes` (the tree-node list), not from
`SelectedPath` - `GraphChromatogram.cs:1272`:

```csharp
return PeptidesAndTransitionGroups.Get(_stateProvider.SelectedNodes, _chromIndex, MaxPeptidesDisplayed);
```

and `PeptidesAndTransitionGroups.Get` opens with a hard gate (`PeptidesAndTransitionGroups.cs:99`):

```csharp
if (!Settings.Default.AllowMultiplePeptideSelection)
    return peptidesAndTransitionGroups;     // empty
```

So an empty chromatogram graph is exactly what this path produces when that setting is off. Note
`GraphChromatogram` also has a single-node path (`GraphChromatogram.cs:870`,
`_stateProvider.SelectedNode as SrmTreeNode`).

**The question to answer first: do the two routes end up on different paths?** Compare, for the same
protein selected each way, `SequenceTree.SelectedNodes` (count and node types), `SelectedNode`, and which
of the two `GraphChromatogram` branches runs. A debugger or the UI driver will settle it in minutes; reading
more code will not, which is why this stops here.

## Note on the sibling selection paths

Worth keeping in view, because it is a real asymmetry even if it is not this bug. `SequenceTree.SelectPath`
(used by `DotPlotUtil.MultiSelect` and `FoldChangeVolcanoPlot.Deselect`, i.e. the ctrl-click routes)
deliberately suppresses the change notification for a *new* node:

```csharp
// SequenceTree.cs:629
_inhibitAfterSelect = !ReferenceEquals(SelectedNode, node);
```

That reads backwards at first glance; the comment explains it is for moving the focused node inside an
existing multi-selection without collapsing it. Both callers compensate with their own
`UpdateGraphPanes()`. The plain-click route in this bug does not go through `SelectPath` at all, so this is
context rather than cause.
