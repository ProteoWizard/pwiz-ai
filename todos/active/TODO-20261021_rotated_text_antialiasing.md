# TODO-20261021_rotated_text_antialiasing.md - Anti-alias rotated ZedGraph text

## Branch Information
- **Branch**: `Skyline/work/20261021_rotated_text_antialiasing` (checkout `C:\Dev\Mobiligram`)
- **Base**: `master`
- **Module**: `skyline`
- **Created**: 2026-10-21
- **Status**: In progress
- **Supersedes**: `Skyline/work/20260428_zedgraph_antialiasing` (deleted, never had a PR) - an
  experiment that set `FontSpec.Default.IsAntiAlias = true` globally behind a
  `SKYLINE_ZEDGRAPH_ANTIALIASING` env var / TestRunner `zedgraphantialiasing` switch.

## Problem
Vertical text in ZedGraph graphs renders jagged, with blocky strokes and uneven glyph spacing.
The concern was first raised on the mobilogram Y-axis title in the full-scan view, but the same
applies to every Y-axis title, vertically rotated X-axis labels (`AxisLabelScaler`), and vertical
annotations (unselected peptide labels in `ChromGraphItem`). `FontSpec.Default.IsAntiAlias` is
`false`; only per-font opt-ins (e.g. the selected chromatogram peptide label) were smooth.

## Approach
- `FontSpec.Draw` / `DrawTenPower` now call `AntiAliasIfRotated(g)` after `SetupMatrix`, which
  turns on `TextRenderingHint.AntiAlias` when the final transform has a rotation component
  (`Elements[1] != 0`).
- The check is on the final transform, not `FontSpec.Angle`: Y axes draw in a 90-degree rotated
  frame, so the Y title has `Angle = -180` (appears vertical) and Y tick labels `Angle = 90`
  (appear horizontal).
- Horizontal text keeps the system default (ClearType). Fonts with `IsAntiAlias` unchanged.
- Rejected: global `FontSpec.Default.IsAntiAlias = true` (changes all text and every
  screenshot); per-graph opt-in on the mobilogram only (inconsistent with all other Y titles).
- Shared ZedGraph change, so MSGraph-based graphs get it too. `FontSpec.cs` is a legacy
  (non-UTF-8) encoded file - edit byte-level.

## Tasks
- [x] Implement in `pwiz_tools/Shared/zedgraph/ZedGraph/FontSpec.cs`
- [x] Build; TestFullScanGraph, TestClusteredHeatMap, TestFullScanFilterInteraction pass
- [x] Before/after render of a pane with Y title and rotated X labels (master vs patched DLL)
- [x] /code-review medium: fixed hint-after-measure (now decided before MeasureString, as the
      IsAntiAlias path does) and dropped SmoothingMode for rotated text (glyph hint only, so
      borders/fills unchanged); dropped 180-degree, allocation, design-alternative, screenshot findings
- [x] CodeInspection
- [x] PR [#4892](https://github.com/ProteoWizard/pwiz/pull/4892)
- [ ] TeamCity green, review, merge
- [ ] Look at the real mobilogram in Skyline
- [ ] Tutorial screenshots with vertical text will show diffs at the next screenshot refresh -
      expected, accept them (see ai/docs/screenshot-update-workflow.md "Font Rendering Differences")

## Progress Log
### 2026-10-21
- Merged master into the old experiment branch, then narrowed scope: mobilogram-only, then
  all rotated text. Moved the result onto this fresh branch from master.
