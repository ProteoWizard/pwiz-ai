# Full scan: extraction box always visible when zoomed out

## Branch Information
- **Branch**: `Skyline/work/20260321_precursor_line_always_visible`
- **Base**: `master`
- **Created**: 2026-03-21
- **Completed**: 2026-03-24
- **Status**: Completed - PR merged
- **GitHub Issue**: [#4086](https://github.com/ProteoWizard/pwiz/issues/4086)
- **PR**: [#4087](https://github.com/ProteoWizard/pwiz/pull/4087)

## Objective

In the Full Scan graph views, the shaded extraction box for each transition disappears
when the m/z axis is zoomed out to a wide range.

The extraction `BoxObj` for each transition has a width of `ExtractionWidth` in m/z data
units. When the x-axis spans a wide range, this box becomes sub-pixel wide and ZedGraph
stops rendering it. Since the border is `Color.Transparent`, there is no fallback outline.

Fix: tag each `BoxObj` with `ExtractionBoxInfo` (center m/z, original width), then override
`SetScale` in `FullScanHeatMapGraphPane` to enforce a minimum rendered width of 1 pixel
(computed via `ReverseTransform`) on every zoom change. Applies to both heatmap and stick
graph views.

## Tasks

- [x] Investigate root cause
- [x] Tag extraction boxes with `ExtractionBoxInfo` (center m/z + original width)
- [x] Override `SetScale` to enforce minimum 1-pixel width on zoom changes (heatmap)
- [x] Extend fix to stick graph view (remove `!ShowHeatMap` early return)
- [x] Build and verify visually
- [x] Commit and push
- [x] Create PR — merged 2026-03-24

## Progress Log

### 2026-03-21 - Initial Fix

Investigated sporadic precursor vertical line visibility in heatmap view.
Root cause: `BoxObj` with m/z-unit width goes sub-pixel when zoomed out.
Applied fix using `ExtractionBoxInfo` tag + `SetScale` override in
`FullScanHeatMapGraphPane`. Initially guarded with `if (!ShowHeatMap) return;`.

### 2026-03-24 - Stick Graph Fix

Identified same issue in stick graph view — the `!ShowHeatMap` guard was preventing
the minimum-width enforcement from running. Removed the guard so `SetScale` applies
to both views. PR merged.
