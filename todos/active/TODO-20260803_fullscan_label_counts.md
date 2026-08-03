# Make FullScanGraphTest ion counts independent of the screen

## Branch Information
- **Branch**: `Skyline/work/20260803_fullscan_label_counts` (sky_fixes)
- **Base**: `master`
- **Created**: 2026-08-03
- **Module**: `skyline`
- **Status**: In Progress
- **PR**: (pending)

## Objective

`FullScanGraphTest` asserted the number of ion labels actually painted on the
Full Scan graph. That count is a property of the rendering, not of the data, so
it had drifted into a three-way constant:

```csharp
private static int ExpectedLabelCount(int offscreenCount, int onscreenEnCount, int onscreenJaCount)
```

70/20/15 at one call site and 48/2/2 at the other. Onscreen counts survive
MSGraphPane's label-overlap pass, which depends on the pixel size of the chart -
screen resolution, DPI and font metrics - so the onscreen constants are machine
properties, not expectations. The comment in the file already recorded one
instance of them shifting when an unrelated change (moving the "Intensity" and
"Drift Time" axis titles into other panes) shrank the heatmap Y-axis area.

## Approach

1. **Assert the data, not the paint.** Both call sites now check
   `SkylineWindow.GraphFullScan.SpectrumInfo.PeaksMatched.Count()` (70 and 48) -
   the matched ion list the labels are drawn from. Same intent ("the show
   settings select this many ions"), no rendering dependency, one constant per
   call site instead of three.
2. **`ExpectedLabelCount` removed** along with its offscreen/culture branching.
   `TestAnnotations` still checks `IonLabels`, but as a containment check on a
   handful of specific label strings, which does not depend on how many labels
   fit.
3. **Race in `ClickChromatogram`** (`TestUtil/AbstractFunctionalTestEx.cs`): the
   click was issued in its own `RunUI` after the mouse-move loop. The clicked
   time comes from the full-scan tracking dot
   (`GraphChromatogram.FireClickedChromatogram` reads
   `CurveList[FULLSCAN_TRACKING_INDEX][0].X`), so a graph update landing between
   the move and the click recreates the curve holding that dot, resets its
   position, and the click is discarded silently
   (`GetValidPeakBoundaryTime` returns zero and the handler returns). The move
   and the click now happen in a single UI action.

## Files changed

- `pwiz_tools/Skyline/TestFunctional/FullScanGraphTest.cs` - `PeaksMatched`
  assertions; `ExpectedLabelCount` deleted.
- `pwiz_tools/Skyline/TestUtil/AbstractFunctionalTestEx.cs` - move + click in
  one `RunUI` in `ClickChromatogram`.

## Verification

- [x] `Build-Skyline.ps1 -Target TestFunctional` clean.
- [x] `TestFullScanGraph` offscreen (en) - 0 failures.
- [x] `TestFullScanGraph` onscreen (en) - 0 failures. This is the case the
  deleted onscreen constants existed for.
- [x] `TestFullScanGraph` onscreen (ja) - 0 failures. Covers the third constant
  the helper carried.
- [x] CodeInspection green.
- [ ] `/code-review max` findings settled (developer-invoked; blocks the PR).

## Notes

- `ClickChromatogram` is shared test infrastructure, so the race fix affects
  every functional test that clicks a chromatogram to open the Full Scan graph,
  not only this one. TeamCity coverage on the PR is the check for that.
