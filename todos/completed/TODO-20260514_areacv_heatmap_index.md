# TODO: Fix IndexOutOfRangeException in AreaCV 2D histogram heat map

- **Branch:** `Skyline/work/20260514_areacv_heatmap_index` (BugFix checkout)
- **Base:** `master`
- **Created:** 2026-05-14
- **Status:** Completed
- **GitHub Issue:** [#4209](https://github.com/ProteoWizard/pwiz/issues/4209)
- **PR:** [#4210](https://github.com/ProteoWizard/pwiz/pull/4210) (merged 2026-06-29 as `9df40fb0`)

## Objective

Fix `IndexOutOfRangeException` thrown from `HeatMapGraphPane.GraphHeatMap`
when displaying the Peak Area CV 2D histogram graph.

## Source

Exception report skyline.ms #74715
- Version: 26.1.1.097-922725ca01
- `IndexOutOfRangeException` at `HeatMapGraphPane.cs:51` (release-build line
  attribution; method body of `GraphHeatMap`)
- Triggered by activating the AreaCV 2D histogram dock pane
  (`GraphSummary_VisibleChanged` -> `UpdateGraph`).

## Root cause

In `GraphHeatMap` the heat-intensity color scale is built from
`maxZValue = Math.Log(heatMapData.MaxPoint.Point.Z)` and
`fullScale = (_heatMapColors.Length - 1.0) / maxZValue`.

When the maximum histogram frequency is exactly 1 (no bin has more than one
peptide), `Math.Log(1) == 0`, so `fullScale` becomes `+Infinity`.

In the discrete-legend branch the per-point color remap computes
`colorIndex = Math.Min((int)(intensity / scale * fullScale), curves.Length - 1)`.
For `intensity == 0` this is `0 * +Infinity == NaN`. On .NET Framework
`(int)NaN` yields `int.MinValue` (the x86 `cvttsd2si` "integer indefinite"
result), and `Math.Min` does not clamp the lower bound, so
`_heatMapColors[int.MinValue]` throws.

Related fragility in the same method: `(int)` casts of `Infinity`/`NaN`
elsewhere also collapse to `int.MinValue`; degenerate frequency values
(`Z <= 0`, fractional `Z`) make `maxZValue`/`scale`/`fullScale` non-finite
or negative.

## Plan

- [x] Guard the color-scale math in `GraphHeatMap` against degenerate
      `maxZValue` (<= 0, producing non-positive/non-finite `fullScale`/`scale`).
- [x] Clamp `colorIndex` (and any other computed array index) to a valid
      range instead of relying on `Math.Min` upper-bound only.
- [x] Add a regression test exercising the AreaCV 2D histogram with a
      data set whose maximum bin frequency is 1.
- [x] Build + run affected tests.

## Implementation

### Changes Made

1. **HeatMapGraphPane.cs** - Added guards against degenerate scale values:
   - Guard `maxZValue <= 0` or non-finite values, fallback to `1.0`
   - Guard `scale` non-finite or <= 0, fallback to `1.0`  
   - Clamp `intensity` calculation with `Math.Max(0, Math.Min(...))`
   - Clamp `colorIndex` calculation with `Math.Max(0, Math.Min(...))`

2. **AreaCVHistogramTest.cs** - Added regression test:
   - `TestAreaCVHeatMapIndexOutOfRangeRegression()` documents the crash condition
   - Tests the mathematical edge case where `Math.Log(1) = 0` → `fullScale = +Infinity`
   - Verifies `(int)NaN` behavior across .NET versions
   - Confirms `GraphHeatMap` handles the problematic data without crashing

### Testing Results

- ✅ `TestAreaCVHeatMapIndexOutOfRangeRegression` - Regression test passes
- ✅ `TestAreaCVHistograms` - Existing AreaCV functionality unchanged  
- ✅ `ClusteredHeatMapTest` - Related heat map functionality unchanged

The fix prevents the `IndexOutOfRangeException` while preserving all existing
heat map behavior.

## Notes

- File: `pwiz_tools/Shared/MSGraph/HeatMapGraphPane.cs`
- Caller: `pwiz_tools/Skyline/Controls/Graphs/AreaCVHistogram2DGraphPane.cs`
- `pwiz_tools/Shared/MSGraph/HeatMapData.cs` `Cell._maxPoint` can be null
  for all-zero-Z cells; `Cell.GetPoints` can `Add(null)` for a degenerate
  root cell (separate latent NRE risk, note while here).

## Progress Log

### 2026-06-29 - Merged

PR #4210 merged to master as commit `9df40fb0` (squash). Shipped:
- `GraphHeatMap` guards: clamp `maxZValue` (`<= 0` / NaN / Infinity -> 1.0)
  *before* deriving `fullScale`/`scale` so both stay positive, and bound every
  computed color index with `Math.Max(0, Math.Min(..., Length - 1))`.
- `MaxPoint == null` early return for all-Z<=0 data — closes the latent NRE
  noted above.
- Per-point `Z <= 0` skip (added at rita-gwen's review request; defensive,
  since `HeatMapData.Cell` already filters `Z <= 0`).
- Regression test `TestHeatMapCrashRegression` folded into the existing
  `TestAreaCVHistograms` `[TestMethod]`; reproduces the frequency=1 crash
  (red-without-fix verified) and asserts a point was actually plotted.

Visually verified the all-frequency-1 render (single blue point, "Frequency 1"
legend — no crash). Reviews all addressed/resolved: self-review (3 passes),
Copilot (negative-log-scale, folded into the `maxZValue <= 0` clamp), human
(rita-gwen, `Z <= 0` guard). Not cherry-picked to release.
