# Fix aggressive label sampling in Volcano / Relative Abundance plots

## Branch Information
- **Branch**: `Skyline/work/20260521_labelSamplingFix` (pwiz1)
- **Base**: `master`
- **Created**: 2026-07-21
- **Status**: In Progress
- **GitHub Issue**: [#4330](https://github.com/ProteoWizard/pwiz/issues/4330)
- **PR**: [#4495](https://github.com/ProteoWizard/pwiz/pull/4495)

## Objective

On the Peak Areas - Relative Abundance and Volcano plots, a
`ProteinName: sp\|Q` labeled rule (repro:
PeakBoundaryImputationTutorial screen 5; also
`ProteoBugs/NotEnoughLabels/ExtracellularVesicalMagNet.sky`) yields
only **3 labels** on a plot with ~1500 candidates. The pre-annealer
sampler in `LabelLayoutRunner` was too aggressive, and the annealer
itself never culls, so at high density labels also overlap each other
and the point markers.

## Root cause

`SamplePointsByDensityGrid`
(`pwiz_tools/Skyline/Controls/Graphs/LabelLayoutRunner.cs`) computed
the per-point keep probability as the **product** of two independent
conservative caps:

    P = cutoff * areaSamplingRate
    areaSamplingRate = chartArea / avgLabelArea * ratio / pointCount
    cutoff           = min(1, MAX_LABELS_PER_CELL / cellPointCount)

Each cap was designed to be sufficient alone; multiplying them stacked
two reductions (~0.037 combined at N=1500), starving the plot. The
simulated-annealing solver
(`LabelLayout.ComputePlacementsSimulatedAnnealing`) places every point
it is given and never culls, so on dense plots labels also land on top
of one another and on the data-point markers.

## Approach (final)

Three parts:

1. **Sampler cap: product -> min.** `LabelLayoutRunner.cs`:
   `P = Math.Min(cutoff, areaSamplingRate)`. Honors both caps as hard
   limits instead of compounding them. (`max` was tried first and
   produced label soup - it takes the looser cap per cell.) The
   sampler's global cap keeps the kept count near chart capacity
   regardless of N.

2. **Post-annealer overlap prune.** New
   `LabelLayout.PruneOverlappingLabels(g)`, called from the runner's
   fresh-compute completion path only (saved-layout restoration is
   untouched). Walks the annealer's *final* label rects and hides a
   non-selected label if it either (a) overlaps an already-kept label,
   or (b) covers the center of a *foreign* point marker (its own
   marker is excluded - the connector ties them). Deterministic order
   (selected first, then stable text hash) so two runs prune the same
   labels. Uses a spatial hash keyed on label-sized buckets. Pruned
   labels are hidden, connectors removed, and dropped from the layout
   (so not persisted). Marker rectangle extraction was factored into a
   shared `EnumerateMarkerRectangles()` used by both the density grid
   and the pruner.

3. **Hit-test visibility fix.** `GraphObjList.FindPoint` did not check
   `IsVisible`, so hidden labels (sampled-out or pruned, still in
   `GraphObjList`) intercepted mouse-over and screened the visible
   label underneath - the cursor would not change. Added an
   `IsVisible` guard, mirroring the draw path. Fixes the reported
   cursor issue for both sampler-hidden and prune-hidden labels.

Tuning: `MAX_LABEL_AREA_RATIO` lowered 0.5 -> 0.3 (developer) to feed
fewer, better-placed labels to the annealer.

## Measured on the repro (ExtracellularVesicalMagNet volcano)

- Strict "no label may touch any marker": 28 -> 3 kept (too aggressive
  on a dense marker cloud).
- Chosen threshold prune (foreign-marker-center + own-marker
  excluded): 28 -> 10 kept, survivors placed around the cloud
  periphery with leader lines.

## Files changed

- `pwiz_tools/Skyline/Controls/Graphs/LabelLayoutRunner.cs` - min cap;
  call `PruneOverlappingLabels` after `ApplyLabelLayout`.
- `pwiz_tools/Shared/zedgraph/ZedGraph/LabelLayout.cs` -
  `PruneOverlappingLabels` + helpers (`CoversForeignMarker`,
  `OverlapsKept`, `AddToBuckets`, `BucketKey(s)`, `StableTextHash`,
  `LabelRect`); `EnumerateMarkerRectangles` refactor.
- `pwiz_tools/Shared/zedgraph/ZedGraph/GraphObjList.cs` - `IsVisible`
  guard in `FindPoint`.
- `pwiz_tools/Skyline/TestFunctional/LabelLayoutTest.cs` - re-snapshot
  (`EXPECTED_POINT_COUNT = 13`, `EXPECTED_RANDOM_POINTS` indices).

## Verification

- [x] Sampler cap product -> min.
- [x] Post-annealer prune (label-label + foreign-marker-center).
- [x] Hit-test `IsVisible` guard.
- [x] `LabelLayoutTest.TestLabelLayoutDeterminism` re-snapshotted to
  13 labels; passes with visible UI; two runs byte-identical
  (determinism holds).
- [x] `TestVolcanoPlotFormatting`, `TestVolcanoPlotLayout`,
  `TestPeakAreaRelativeAbundanceGraph` all green (prune does not break
  formatting or the `remainingObjs` invariant; saved-layout path
  unaffected).
- [x] Repro driven in Skyline UI: volcano went from a wall of
  overlapping labels to ~10 readable labels off the marker cloud.
- [ ] Pre-push: clean `Build-Skyline.ps1`, `CodeInspection` test,
  QuickInspection.
- [ ] Interactive confirm from developer that mouse-over cursor now
  changes over visible labels (driver cannot reliably capture cursor
  shape).

## Notes

- The annealer already soft-avoids markers via the density grid
  (`EvaluateLabelBaseCost` sums marker density over the label's cells
  and adds `TARGET_OVERLAP_PENALTY` for the own marker), but on a
  dense cloud it cannot fully separate; the prune is the hard-invariant
  cleanup on final positions.
- Marker rectangles are symbol-sized (`pixPt +/- symbolSize*scale`),
  not oversized.
