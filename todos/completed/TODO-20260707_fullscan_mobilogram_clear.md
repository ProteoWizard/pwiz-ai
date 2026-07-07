# TODO: Full Scan mobilogram not cleared with the heatmap

**Branch:** `Skyline/work/20260707_fullscan_mobilogram_clear`
**PR:** [#4384](https://github.com/ProteoWizard/pwiz/pull/4384) (merged 2026-07-07)
**Status:** Completed

## Objective

In the Full Scan graph for ion-mobility data with the mobilogram pane visible, when
the displayed scan is cleared (navigating to a state with no scan to show), the
heatmap (m/z vs drift time) emptied correctly but the mobilogram (intensity vs drift
time) kept its stale trace.

## Root cause

`GraphFullScan.ClearGraph()` reset the combo/labels/title but never touched
`_mobilogramPane`, which is a separate pane in the MasterPane from the heatmap
(`GraphPane => _heatMapPane`). Both clear paths route through `ClearGraph()`:
`LoadScan` when `scanId < 0`, and `ShowSpectrum` with a null scan provider. Only the
heatmap's curves were cleared, so the mobilogram lingered.

## Fix

`ClearGraph()` now clears `_mobilogramPane.CurveList` / `GraphObjList` (guarded on the
pane being present), covering every clear path in one place.

## Done

* One-file fix in `GraphFullScan.ClearGraph()` (+7 lines).
* Verified visually via `CrosslinkImsTest` on-screen (mobilogram clears with the heatmap).
* CodeInspection + ReSharper full-solution — 0 errors / 0 warnings.
* Not applicable to release branch 26.1: mobilogram feature (#4152/#4166) landed after
  the release branch was created (`_mobilogramPane` absent there), so no cherry-pick.

## Remaining / follow-ups

* Separate observation: on the null-scan-provider path in the heatmap+mobilogram
  layout, `SetErrorGraphItem` draws the "Spectrum unavailable" item into the leftmost
  pane (the mobilogram, `MasterPane.PaneList[0]`) rather than the heatmap. Not the
  reported bug and not addressed here.
* Deferred (UX, out of scope): after a clear with the mobilogram visible, the user is
  left with an empty mobilogram frame beside the empty heatmap rather than collapsing
  back to a single heatmap pane. Raised by self-review; left as-is (symmetric with the
  heatmap pane's own clear behavior).

## Progress Log

### 2026-07-07 - Merged

PR #4384 merged as commit c174d2c. Shipped the one-file fix in
`GraphFullScan.ClearGraph()` (+7 lines) that clears `_mobilogramPane.CurveList` /
`GraphObjList` so the mobilogram empties on every clear path. Verified visually via
CrosslinkImsTest; CodeInspection + ReSharper full-solution clean (0/0); Copilot and a
fresh-context self-review both clean (self-review confirmed `GraphObjList.Clear()` is
safe — the persistent Intensity label lives on the spacer pane, not the mobilogram).
No automated test added (reachable HDMSe fixture can't drive the scanId&lt;0 UI path).
Not cherry-picked to 26.1 (mobilogram feature postdates the release branch).
