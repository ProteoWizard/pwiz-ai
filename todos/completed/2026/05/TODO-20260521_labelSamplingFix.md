# Fix aggressive label sampling in Volcano / Relative Abundance plots

## Branch Information
- **Branch**: `Skyline/work/20260521_labelSamplingFix` (pwiz2 as of 2026-09-22)
- **Module**: `skyline`
- **Base**: `master`
- **Created**: 2026-07-21
- **Status**: Completed - merged 2026-10-05 as `93b88ee0c8`
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

## 2026-09-22 - Picked back up

Moved the working checkout to `pwiz2` and merged `origin/master` (58 commits behind, clean merge, no
conflicts; the PR diff is intact). Build clean, and `TestLabelLayoutDeterminism`, `TestVolcanoPlotFormatting`,
`TestVolcanoPlotLayout` and `TestPeakAreaRelativeAbundanceGraph` all pass in en offscreen.

Build gotcha in a fresh checkout of this branch: `CommonMsData` now pulls `Microsoft.Extensions.Http` 9.0.4 as
a NuGet `PackageReference`, so a checkout with no restored packages fails with `CS0234 Microsoft.Extensions`
and `IHttpClientFactory` not found. `MSBuild Skyline.sln /t:Restore` fixes it; no code change needed.
Note also that MSBuild now resolves to Visual Studio 18 Community on this machine, where earlier builds in
this checkout used 2022.

PR state: all review threads resolved, CI green, no approval yet, and the merge above clears the BEHIND
status. Still open from the list below: the interactive cursor confirmation.

## 2026-09-22 - Sampler still too aggressive on dense marker clouds

Developer reported the Relative Abundance panel of
`ProteoBugs/NotEnoughLabels/ExtracellularVesicalMagNet.sky` showing only 3-4 labels with both formatted series
marked as labeled, while most of the plot was empty.

Root cause: the per-cell cap in `SamplePointsByDensityGrid` divided by `GridCell.PointCount`, which
`LabelLayout.FillDensityGrid` increments once per **data point marker**, not per label candidate. So
`MAX_LABELS_PER_CELL = 4` really meant "4 divided by the marker density under this label". On a plot whose
labeled points sit on a ribbon of ~1600 markers, a cell covering 30 markers gives a keep probability of 4/30,
independent of how much free space the chart has - which is what starved the plot.

It was also double counting: marker density is already handled downstream twice, by the annealer's
`EvaluateLabelBaseCost` and by the pruner's foreign-marker check.

Fix: count label candidates per cell (a histogram of the cells already computed for the candidates) and cap on
that. `MAX_LABEL_AREA_RATIO` left at 0.3 - the developer confirmed the plot looks right without raising it.

No regression test (developer's call - not a critical bug). Note for anyone re-checking: the four existing
tests pass identically before and after the fix, so none of them covers this behavior. Reproducing it needs a
document whose labeled points sit on a large marker cloud, which `Rat_Plasma.sky` is not.

## 2026-09-29 - Label layout sweep, one plot at a time

`TestPerf/LabelLayoutSweep.cs` (diagnostic tool, off unless `SKYLINE_LABEL_SWEEP=1`) now sweeps the volcano
plot and the Relative Abundance plot **separately**, since both drive the same `LabelLayoutRunner` and with
both open no row can be attributed. A `PlotTarget` abstraction holds the per-plot differences (how to open,
size, redraw, and where the labeling rules live); the sweep opens one, sweeps 3 rule sets x 4 window sizes x
3 zooms, closes it, then does the other. `LabelLayout.SamplerReport` now reports the `GraphPane` as well, so
each row is checked against the pane under test.

Full clean run: 72 rows, 558 s, 0 failures, every pruner invariant held.
Output: `ai/.tmp/sessions/20260929-labelsweep/label-layout-sweep.csv` (+ `sweep-run.log`).

### Results at zoom 1.0 (full data range)

| plot | rules | chart | candidates | sampler kept | visible | coverage |
|---|---|---|---|---|---|---|
| volcano | saved | 1000x700 | 125 | 40 | 19 | 16.03% |
| volcano | saved | 1280x900 | 125 | 69 | 40 | 16.36% |
| volcano | saved | 1680x1050 | 125 | 104 | 72 | 18.43% |
| volcano | saved | 1920x1200 | 125 | 125 | 91 | 17.29% |
| rel-abundance | saved-all-labeled | 1000x700 | 26 | 26 | 16 | 7.29% |
| rel-abundance | saved-all-labeled | 1920x1200 | 26 | 26 | 17 | 2.06% |
| rel-abundance | label-everything | 1000x700 | 4844 | 74 | 43 | 19.62% |
| rel-abundance | label-everything | 1920x1200 | 4844 | 249 | 118 | 14.56% |

**The volcano behaves as the fix intended.** The sampler stops being the constraint as the chart grows
(40/125 at 1000x700 up to 125/125 at 1920x1200), the pruner takes it from there, and coverage holds steady
near 16-18% against `MAX_LABEL_AREA_RATIO = 0.3` - roughly half the pipeline's own area target.

**Relative Abundance has the opposite shape and is where to look next.** With 26 candidates all passing the
sampler, quadrupling the chart area buys one extra label (16 -> 17) and coverage collapses 7.29% -> 2.06%.
With 4844 candidates the sampler keeps 1.5-5% and coverage still falls as the chart grows (19.6% -> 14.6%).
The binding constraint there is local clustering under the pruner's non-overlap rule, not global chart area,
which matches the original "most of the plot was empty" report.

### Two handoff notes corrected

* A `MatchRgbHexColor` with an empty `Expression` is **not** filtered out. `MatchExpression.Parse("")`
  returns an expression with no match options and `Matches` returns true when the option list is empty, so
  it matches every point: the `label-everything` rule set produced 127 labels on the volcano and all 4844 on
  Relative Abundance.
* On the volcano `saved` and `saved-all-labeled` are identical in all 12 pairs - its one saved rule already
  has `Labeled = true`. On Relative Abundance neither saved rule is labeled, so `saved` creates exactly one
  label (the selected protein, labeled unconditionally).

### Product observation, not part of this PR

`SkylineWindow.ShowGraphPeakArea(false)` only calls `graph.Hide()`, and `GraphSummary.HideOnClose = true`
(`GraphSummary.Designer.cs:79`), so a hidden Peak Areas graph keeps its pane subscribed to
`Settings.Default.PropertyChanged`. Toggling "avoid label overlap" therefore runs a full simulated-annealing
layout on a graph nobody can see - the sweep caught it as sampler reports arriving from
`AreaRelativeAbundanceGraphPane` while the volcano was under test. The sweep works around it by closing the
form for real (`HideOnClose = false; Close()`). Worth deciding separately whether the product should gate
`StartLabelLayoutAsync` on pane visibility.

### Three defects the sweep had, all found by running it

1. **Zoom compounded.** The fraction was applied to the live axis scale and `ZoomOutAll` was trusted to reset
   at zoom 1.0, but the volcano pins `MinAuto/MaxAuto = false` (`FoldChangeVolcanoPlot.cs:479`) so zooming
   out restores nothing. The view shrank monotonically across the whole sweep (125 candidates down to 1 by
   the seventh combination). Now the auto-scaled range is captured once at `Open()` and every fraction is
   measured from that.
2. **Linear zoom math on a log axis.** The Relative Abundance y axis spans 1e4 to 1e12; halving that range
   linearly leaves only the top decade, and at fraction 1.0 it computed `min ~ 0`, invalid for `LogScale`.
   Now narrowed in log space.
3. **Measurement raced the layout.** The wait was "a layout exists and is non-empty", which is satisfied by
   the *previous* run's layout while the current run has already re-shown every sampled label at its
   unplaced position - reading as a pile of overlapping labels and failing the invariant check. The runner
   installs a **new** `LabelLayout` instance per run and prunes in the same UI callback
   (`GraphPane.ApplyLabelLayout`, `GraphPane.cs:1556`), so the wait is now for a different instance, plus a
   settle check that no later run supersedes it.

Bounded waits throughout (`READY_WAIT_MS` 60 s, `SAMPLER_WAIT_MS` 15 s, `LAYOUT_WAIT_MS` 60 s) via
`TryWaitForConditionUI`. A combination that legitimately yields no labels is now a recorded zero row with a
reason line instead of a 360 s timeout.

### The hook is Debug only (developer's call)

`LabelLayout.SamplerReport` is wrapped in `#if DEBUG`, as is its one call site in `LabelLayoutRunner`, so it
is compiled out of the shipped executable. This matches what `LabelLayout.cs` already does with its
annealing CSV log. Consequence: **the sweep needs a Debug build**; in Release the test prints that and
returns. Verified Release builds warning-free with the hook absent and Debug builds warning-free with it
present.

### The sweep no longer needs -ShowUI

`ResizeFormOnScreen` returns before resizing when `Program.SkylineOffscreen` is set, because the
`FormEx.ForceOnScreen` that follows would drag a deliberately offscreen window back onto the desktop. That
is why the sweep previously demanded `-ShowUI` and took over the developer's screen for its whole run.
Offscreen mode only repositions the main window (`Program.cs:389`), so the resize itself is valid either
way: `PlotTarget.Resize` now sets the frame size directly when offscreen and skips only `ForceOnScreen`.
`ResizeFormOnScreen` itself is left alone - its early return is deliberate for screenshot tests.

Added `VerifySizeAxisApplied`, which warns if every window size measured the same chart, so a resize that
silently fails can never be reported as data.

Runs, all passing, all 72 rows:

| build | mode | wall time |
|---|---|---|
| Release | onscreen | 558 s |
| Debug | onscreen | 988 s |
| Debug | offscreen | 951 s |

The volcano rows are identical in all three. The Relative Abundance rows differ by a few labels offscreen
(`saved-all-labeled` 17/21/20/18 vs 16/19/16/17; `label-everything` 40/67/95/113 vs 43/64/91/118) because
its floating frame's chart rectangle comes out a few pixels different. That is the same legitimate
geometry sensitivity the multi-language work above established, not a defect, and every trend is unchanged -
including `saved-all-labeled` refusing to scale across a 3x area increase.

CSVs: `label-layout-sweep.csv` (Release onscreen), `-debug.csv`, `-offscreen.csv` in
`ai/.tmp/sessions/20260929-labelsweep/`.

## 2026-10-01 - Ready to merge, waiting on master

The PR is down to just the fix and is otherwise merge-ready:

* Sweep tool reverted off this branch (`9d2b659573`) - the net diff is four files: `LabelLayout.cs`,
  `LabelLayoutRunner.cs`, `GraphObjList.cs`, `LabelLayoutTest.cs`. The tool is parked on
  `Skyline/work/20260929_labelLayoutSweep`, which is based on this branch and will need
  `git merge origin/master` after the squash-merge before its own PR shows a sensible diff.
* Three code inspection warnings the tool introduced are fixed (`a254c29857`); QuickInspection locally
  reports 0 errors, 0 warnings.
* PR title now carries the module prefix - `skyline: Fixed sparse and marker-overlapping labels on the
  dot plots` - and the `skyline` label was added. The PR had **no labels at all** before.
* Merged master twice to clear BEHIND, most recently `d6f5df17` (#4748). Build clean and the four plot
  tests pass locally after each merge.

**Blocked on two things, neither ours:**

1. **Master is red.** `TestNativeMessageBox` fails on `d6f5df17` (bt209 build #22078) with
   `System.ArgumentException: Setting values is not supported for native dialog Dialog:Save As` at
   `NativeDialog.SetValueCore`, `NativeDialog.cs:320`. That is #4748's own area (off-screen rendering for
   form images and error-report screenshots), unrelated to label layout. Because master was merged into
   this branch, the PR inherits the failure. Developer's call: wait for the fix rather than overlap it,
   and merge when master is clear.
2. **No approving review.** All four reviews on the PR are `COMMENTED`, including Nick's two rounds, so
   `reviewDecision` is empty and `mergeStateStatus` is `BLOCKED`. An author cannot approve their own PR;
   it needs Brendan or Nick to pick **Approve** in Files changed -> Review changes, or
   `gh pr review 4495 --approve`.

Squash-merge message agreed:

```
skyline: Fixed sparse and marker-overlapping labels on the dot plots (#4495)

* Capped the label sampler on the min of its two rates, not their product
* Counted label candidates per density cell rather than data point markers
* Added a post-annealer prune for overlapping and marker-covering labels
* Made GraphObjList.FindPoint respect IsVisible for hidden labels

See TODO-20260521_labelSamplingFix.md in pwiz-ai/todos

Co-Authored-By: Claude <noreply@anthropic.com>
```

`Fixes #4330` is already in the PR description, so the squash message does not repeat it.

## 2026-10-05 - Merged

Squash-merged as `93b88ee0c8`. Master had been red on `TestNativeMessageBox` (from #4748, unrelated); once
that cleared, CI went green and both layout PRs were merged together.

Shipped: sampler cap uses the min of its two rates rather than their product, the per-cell cap counts label
candidates instead of data point markers, a post-annealer prune hides labels that overlap another label or
cover a foreign marker, and `GraphObjList.FindPoint` respects `IsVisible`.

**Follow-up left open:** the label layout sweep tool is parked on `Skyline/work/20260929_labelLayoutSweep`,
branched from this PR before the revert. It needs `git merge origin/master` now that the squash has landed,
after which its PR shows only the tool's own diff. See `TODO-label_layout_sweep_tool.md` in the backlog.

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
