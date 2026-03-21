# Full scan heatmap: precursor m/z line always visible

## Branch Information
- **Branch**: `Skyline/work/20260321_precursor_line_always_visible`
- **Base**: `master`
- **Created**: 2026-03-21
- **Status**: In Progress
- **GitHub Issue**: [#4086](https://github.com/ProteoWizard/pwiz/issues/4086)
- **PR**: (pending)

## Objective

In the Full Scan heatmap view (ion mobility drift time vs m/z), the vertical line marking
the precursor m/z disappears when the m/z axis is zoomed out to a wide range.

The extraction `BoxObj` for each transition has a width of `ExtractionWidth` in m/z data
units. When the x-axis spans a wide range, this box becomes sub-pixel wide and ZedGraph
stops rendering it. Since the border is `Color.Transparent`, there is no fallback outline.

Fix: add a `LineObj` at `transition.ProductMz` alongside each extraction box. A `LineObj`
is always at least 1 pixel wide regardless of zoom level.

## Tasks

- [x] Investigate root cause
- [x] Add `LineObj` at `transition.ProductMz` in extraction box loop (`GraphFullScan.cs`)
- [ ] Build and verify visually
- [ ] Commit and push
- [ ] Create PR

## Progress Log

### 2026-03-21 - Session Start

Investigated sporadic precursor vertical line visibility in heatmap view.
Root cause: `BoxObj` with m/z-unit width goes sub-pixel when zoomed out.
Fix applied in `CreateGraph()` extraction box loop.
