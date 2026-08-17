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
- [x] Pre-push: clean `Build-Skyline.ps1`, `CodeInspection` test,
  QuickInspection (run for round 2 in commit `2bc19d2`).
- [x] Review round 2 pushed (`2bc19d2`); Nick's inline thread replied
  and resolved; snapshot-refactor reply posted as PR comment.
- [x] Developer confirmed the test passes cleanly in SkylineTester
  (all languages as one batch).
- [ ] Interactive confirm from developer that mouse-over cursor now
  changes over visible labels (driver cannot reliably capture cursor
  shape).

## Review feedback round 2 (2026-08-16)

Two comments from Nick Shulman on PR #4495:

1. **LabelLayoutTest fails in fr/zh/ja onscreen** (inline thread on
   `LabelLayoutTest.cs:35`). Reproduced in ja locally: the run-to-run
   determinism comparison passed; what failed was the absolute pinned
   snapshot (`EXPECTED_RANDOM_POINTS` index 7 was `SNSMVTLGCLVK`
   instead of `MLSGFIPLKPTVK`). Root cause: localized axis titles and
   fonts change the chart rectangle, which legitimately changes which
   labels the sampler/pruner keep - the pins encode English-only
   geometry. Fix: gate `EXPECTED_POINT_COUNT`/`EXPECTED_RANDOM_POINTS`
   on English (`GetFolderNameForLanguage`); keep the determinism
   comparison in all languages; add `VerifyLayoutInvariants()` - a
   culture-independent verifier that no two visible labels overlap and
   no visible label covers a foreign marker center (mirrors the pruner
   semantics via `LineItem.GetCoords`).

2. **`catch (InvalidOperationException)` blocks in LabelLayout.cs**
   (review body, no inline thread). The catches papered over the
   worker thread iterating `_graph.CurveList` while the UI mutates it.
   Refactor per Nick's suggestion: the `LabelLayout` constructor (UI
   thread only) now captures an immutable `MarkerInfo[]` snapshot
   (marker rect from `GetCoords` + transformed point center); the
   density grid, `GetPointMarkerRectangle`, and the pruner read only
   the snapshot. All `InvalidOperationException`/
   `ArgumentOutOfRangeException` catches and `GetMarkerLinesSnapshot`
   removed; the worker-thread `new LabelLayout` fallback in
   `LabelLayoutRunner` removed (the runner always creates the layout
   in `StartDebounced` on the UI thread). Marker rects and match
   semantics are byte-identical to before, so layout results are
   unchanged.

### Batch multi-language follow-up

Running all languages as a SkylineTester batch (one process) failed the
new invariant check on the second pass ("Label 'IFPENNIK' covers a
foreign point marker") while single-language runs passed. Root cause
chain, proven with a temporary prune-decision log:
`SummaryRelativeAbundanceGraphPane._labelsLayout` is **static** (by
design - survives pane recreation), so pass 2 restores pass 1's layout
as fixed placements under different localized geometry; `IFPENNIK` is a
**selected** label in Rat_Plasma.sky, and the pruner never prunes
selected labels (it logged `covers=True` and kept it correctly, while
pruning non-selected `VLIVEPEGIK` on the same run). Product behavior is
correct on every path; the test invariant was stricter than the
pruner's actual guarantee. Fix: the invariant check now mirrors the
pruner exactly - selected labels are exempt as subjects (both-selected
overlaps allowed, coverage checked only for non-selected labels), and
non-selected labels must not overlap ANY visible label nor cover a
foreign marker center. Also note for stack traces: `RunUI` rethrows on
the test thread with the call-site line, so failures inside the lambda
report the `RunUI(...)` line, not the assert line.

With the exemption in place the batch then failed one step later, at
the determinism comparison: run 1 of a pass computes its layout seeded
by the PREVIOUS pass's static saved layout and then overwrites the
static, so run 2 starts from different saved state than run 1 - the
two runs were no longer identical experiments (singles pass because
run 1 starts empty and restoring under identical geometry is a fixed
point). Fix: `OpenDocumentAndGraph` now toggles
`GroupComparisonAvoidLabelOverlap` off/on with the pane alive, which
clears the static saved layout via `OnLabelOverlapPropertyChange`
(product path, no reflection), so every capture measures a fresh
layout. Verified: en/ja/fr/zh batch onscreen (SkylineTester scenario),
en single onscreen (pins intact), en+ja offscreen batch, volcano +
rel-abundance tests - all green.

## Notes

- The annealer already soft-avoids markers via the density grid
  (`EvaluateLabelBaseCost` sums marker density over the label's cells
  and adds `TARGET_OVERLAP_PENALTY` for the own marker), but on a
  dense cloud it cannot fully separate; the prune is the hard-invariant
  cleanup on final positions.
- Marker rectangles are symbol-sized (`pixPt +/- symbolSize*scale`),
  not oversized.
- Developer notes the layout copying back and forth (UI-thread marker
  snapshot -> worker -> UI apply) as a possible slowdown; acceptable
  for now. Measured reasoning: the snapshot is one pass per layout run
  while the annealer runs max(700, N*75) iterations, and the old code
  re-derived the same data per lookup (ToArray per call, TransformCoord
  per candidate, GetCoords string round-trips), so the refactor should
  be a net win. If profiling ever says otherwise, first cheap fix:
  compute marker rects directly from symbol size instead of parsing
  the GetCoords "x1,y1,x2,y2" string at snapshot time.
