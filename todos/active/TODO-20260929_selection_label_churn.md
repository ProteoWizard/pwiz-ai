# Selection changes churn the dot plot labels

## Branch Information
- **Branch**: TBD - piggybacking on `Skyline/work/20260521_labelSamplingFix` (pwiz2), per the developer
- **Module**: `skyline`
- **Base**: PR [#4495](https://github.com/ProteoWizard/pwiz/pull/4495)
- **Created**: 2026-09-29
- **Status**: Design agreed, not yet implemented

## Objective

Changing the selection makes the dot plots rebuild from scratch. The developer's concern is **not** latency -
it is unnecessary UI churn that is disorienting: labels elsewhere on the plot blink in and out when the user
clicks a protein that has nothing to do with them.

## Measured, on ExtracellularVesicalMagNet.sky, Relative Abundance, label-everything rule

Ten consecutive protein selections, recording the visible label set after each and diffing consecutive sets.
Anything appearing or disappearing other than the two proteins whose selection state actually changed is
counted as unexpected:

```
select TRFE:  17 labels, +3/-1 UNEXPECTED   appeared DCTN1, SCYL2, RIN3 | vanished TPP1
select LIPL:  17 labels, +4/-4 UNEXPECTED   appeared TPP1, CSK2B, VPS53, AL3A2 | vanished SNX6, EI2BG, TM263, LEG8
select SYWC:  17 labels, +3/-3 UNEXPECTED   appeared EI2BG, TM263, LEG8 | vanished HV353, QSOX1, SCYL2
select PUR8:  15 labels, +3/-5 UNEXPECTED   appeared QSOX1, DERM, SCYL2 | vanished CSK2B, AGAL, RIN3, NIF3L
select STAT1: 15 labels, +3/-3 UNEXPECTED   appeared RIN3, NIF3L, MCUR1 | vanished AL3A2, RMC1, PEX16
```

**Roughly a quarter of the visible labels change identity on every click**, and they oscillate - TPP1
vanishes and returns, SCYL2 and RIN3 appear, vanish, reappear. This is the number to beat: after the fix it
should be 0 unexpected.

## Why the set moves

The rebuild re-runs `SamplePointsByDensityGrid`, whose keep test is
`hash / maxHash <= Math.Min(cutoff, areaSamplingRate)`. Three inputs depend on what is selected, because a
selected point is labeled unconditionally and rendered large:

* **`maxHash`** is the maximum hash over the candidate set. Adding one candidate can raise it, which
  rescales `hash / maxHash` for **every** point at once. This is why labels move in groups.
* **`pointCells.Count`** shifts by one, moving `areaSamplingRate`.
* **`points.Average(p => p.LabelArea)`** shifts because the selected label is large.

So a point that is force-kept anyway sets the threshold every other label is judged against.

## Agreed design (developer, 2026-09-29)

Not "make the recompute stable" - **do not recompute**. Stabilising the sampler would leave a recompute in
place that any future change could destabilise again.

1. **The layout excludes the selected label from its calculations, and that happens once.** The sampler and
   annealer see only the non-selected, rule-labeled points. The selected point's label is not part of the
   layout's world.
2. **A selection change moves labels between the labeled and unlabeled collections as needed** - the
   previously selected point returns to whichever collection its rules put it in, the newly selected one
   moves into the selected handling - and nothing else is touched. No sampler run, no annealer run, no
   teardown of curves or labels.
3. Any other change (document, formatting, results index, replicate display) still does a full rebuild.

## Tried and rejected: excluding selected labels from the layout, on its own

Point 1 of the design was implemented alone, to see how much it bought: `StartLabelLayoutAsync` was fed
`_labeledPoints.Where(lp => !lp.IsSelected)` instead of `_labeledPoints`, at all four call sites. Built
clean, measured with the same harness:

| | unexpected labels per selection change |
|---|---|
| before | +3/-1, +4/-4, +3/-3, +3/-5, +3/-3 |
| after | +2/-1, +1/-4, +4/-1, +5/-6, +4/-1 |

**No improvement.** Excluding selected points does not make the candidate set constant - it changes which
points are in it. Each selection change still moves one point out of the set and another in, and because
the keep test normalizes by `maxHash`, the maximum over the candidate set, one membership change still
rescales the decision for every label at once.

The change was reverted. The lesson: **stabilizing the layout's inputs does not work while the layout is
recomputed at all.** Any ±1 in the candidate set perturbs `maxHash`. The only inputs-based fix that would
hold is normalizing the hash by a constant (`uint.MaxValue`) instead of the sample maximum, which changes
the absolute keep rate and so re-opens the tuning that PR #4495 settled. Not worth it - go straight to not
recomputing.

## Implementation notes gathered so far

* `SummaryRelativeAbundanceGraphPane.UpdateGraph(bool selectionChanged)` already receives a
  `selectionChanged` flag - **but it is unusable as a signal**: `GraphSummary.UpdateUI(bool
  selectionChanged = true)` defaults it to true, so document and settings changes arrive with it set. The
  pane must snapshot what it last rendered (document, graph data, formatting, results index, replicate
  display, selection set) and compare, or the fast path will show a stale plot.
* Selected points currently enter the layout through
  `AddPoints(selectedPoints, GraphSummary.ColorSelected, large, labeled: true, symbol, selected: true)`,
  which creates their `TextObj` and adds a `LabeledPoint` to `_labeledPoints`. Separating them means
  `_labeledPoints` stops being "everything with a label".
* Marker style is a property of the `LineItem`, not the point, so changing one point's appearance means
  moving its `PointPair` between curves. Appending within a curve is invisible for scatter points. Leave
  emptied curves in place rather than removing them, so indices stay stable - the volcano plot's
  `MatchedPointsStartIndex` derives cutoff-line offsets from a selected curve at index 0.
* `_labeledPoints` is also read by hit-testing and `DotPlotUtil.AdjustLabelLocations`; both need checking
  against the new split.
* `FoldChangeVolcanoPlot` has the same structure and the same problem, and should get the same treatment.

## Verification

Re-run the churn measurement (temporary `TestSelectionChangeTiming` in `LabelLayoutSweep.cs`, gated on
`SKYLINE_SELECTION_TIMING`) and require 0 unexpected appearances or disappearances. That harness is
throwaway; a permanent version asserting zero churn would be a good regression test.
