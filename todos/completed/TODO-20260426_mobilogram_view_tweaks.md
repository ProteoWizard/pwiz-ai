# TODO-20260426_mobilogram_view_tweaks.md

## Branch Information
- **Branch**: `Skyline/work/20260426_mobilogram_view_tweaks`
- **Base**: `master`
- **Created**: 2026-04-26
- **Status**: In Progress
- **GitHub Issue**: (none - feedback from Brendan after the mobilogram merge)

## Objective

Post-merge polish for the full-scan mobilogram view (PR #4152). Brendan
flagged a small set of issues during initial use; this branch collects
the resulting tweaks.

## Tasks

### Done

- [x] Show drift-time tick labels on the mobilogram pane's Y-axis
      (`CreateMobilogramPane` previously hid them as redundant with the
      heatmap; Brendan asked for values on all scales). Bumped
      `YAxis.MinSpace` from 4 to 50 to leave room for labels.
- [x] Swap stick-plot and mobilogram toolbar button positions in
      `GraphFullScan.Designer.cs` per Brendan's request.

### Open

- [ ] **Intermittent Y-clip on stick pane** (single-pane MS1 mode):
      Y-axis was observed clipped low (e.g., 0-70 with peaks reaching
      the top, no manual zoom). Suspected race in `ResetStickYAxis`
      where `MaxAuto = magnifyBtn.Checked` lets ZedGraph re-fit Y on
      every paint. Hard to repro reliably. Plan: pin Y explicitly
      after curves are populated; for magnify-on behavior, refit on
      X-zoom in the zoom handler.
- [ ] Stick X / heatmap X already line up naturally now that the stick
      X scale labels are visible — keep an eye out for misalignment if
      we ever hide them again.

## Notes / Context

- Earlier in the session the stick X scale was hidden in dual-pane
  mode at Brendan's suggestion (heatmap below shows the same m/z),
  which exposed a chart-width mismatch (ZedGraph stops reserving
  right-edge padding for the last hidden label). That whole change
  was reverted when Brendan switched to "show values on all scales".
- The `PauseTest` in `TestFullScanGraph` (line 214) is left commented
  out; uncomment locally to view the 4-pane layout interactively.
