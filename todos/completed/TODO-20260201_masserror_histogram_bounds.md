# TODO-20260201_masserror_histogram_bounds.md

## Branch Information
- **Branch**: `Skyline/work/20260201_masserror_histogram_bounds`
- **Base**: `master`
- **Created**: 2026-02-01
- **Status**: Completed
- **GitHub Issue**: [#3909](https://github.com/ProteoWizard/pwiz/issues/3909)
- **PR**: [#3927](https://github.com/ProteoWizard/pwiz/pull/3927)
- **Cherry-pick**: [#3930](https://github.com/ProteoWizard/pwiz/pull/3930)

## Objective
Fix IndexOutOfRangeException in MassErrorHistogram2DGraphPane.AddChromInfo histogram binning.

## Root Cause Analysis
The issue description assumed the exception was at `nodeGroup.Results[replicateIndex]` (line 221-222), but the stack trace clearly shows it at line 252 — the `counts2D` array indexing in the binning pass.

The histogram uses a two-pass approach: first pass collects min/max bounds (`_minX`, `_maxX`, `_minMass`, `_maxMass`), second pass bins data into `counts2D`. The binning calculation:
```csharp
int x = (int) Math.Floor((xVal - _minX)/((_maxX - _minX)/xAxisBins));
```
When `_maxX == _minX` (single x value, e.g., one precursor with one retention time), `(_maxX - _minX)` is zero, causing division by zero. `(int)Math.Floor(NaN)` produces undefined results. Additionally, floating point precision could produce slightly negative `x` or `y` values even with valid ranges.

The original code only guarded against values exceeding the upper bound (`Math.Min(x, length-1)`) but not against negative values.

The user reported: "The PRM RAW file was a trial run and only contained result for 1 precursor" — confirming the degenerate single-point data scenario.

## Exception Details
- **Fingerprint**: `cb9d826a1a13e45d`
- **Exception ID**: 73835
- **Version**: 24.1.0.414

## Changes Made
- [x] Extracted x-axis range into `xRange` variable, guard division by zero (use bin 0 when range is zero)
- [x] Added `Math.Max(0, ...)` lower bound clamping for both x and y indices
- [x] Separated index calculation from array access for clarity
- [x] Added axis padding in Graph() when min == max so single data point renders visibly
- [x] Added regression test that strips document to single iRT peptide, reproducing the degenerate case

## Files Modified
- `pwiz_tools/Skyline/Controls/Graphs/MassErrorHistogram2DGraphPane.cs` - AddChromInfo binning logic, Graph axis padding
- `pwiz_tools/Skyline/TestFunctional/MassErrorGraphsTest.cs` - Degenerate single-precursor test

## Test Plan
- [x] MassErrorGraphsTest passes
- [x] Test reproduces IndexOutOfRangeException without fix, passes with fix
- [x] TeamCity CI passes

## Implementation Notes
- The `_maxMass == _minMass` case (single mass error value) doesn't cause the same issue because `_binSizePpm` is a user setting (never zero)
- The point rendering at line 207 divides `(_maxX - _minX)` by `xAxisBins` (constant 100), producing `binSizeX = 0` for degenerate data, which correctly places all points at `_minX`
- ZedGraph renders a blank graph when axis min == max (zero range). Axis padding of ±1 (x) and ±_binSizePpm (y) ensures the single data point is visible
