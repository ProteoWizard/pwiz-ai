# TODO-20261020_icon_builder.md

## Branch Information
- **Branch**: `Skyline/work/20261020_icon_builder`
- **Base**: `Skyline/work/20260820_dpiAwareness` (stacked; merge that branch in, never rebase, once a PR exists)
- **Created**: 2026-10-20
- **Status**: In Progress
- **Module**: `skyline`
- **PR**: (pending)
- **Related**: [#4839](https://github.com/ProteoWizard/pwiz/pull/4839) (ImageExtractor sizes), issue #4599 (DPI awareness)

## Objective

Give Skyline per-DPI icon assets (16, 20, 24, 32 px) produced by one developer tool from
one manifest, so the DPI awareness work can stop bicubic-upscaling the 16 px bitmaps at
run time. Each icon has a source of one of two kinds; the tool makes the output uniform.

## Design (agreed 2026-10-20)

New DevTools project `pwiz_tools/Skyline/Executables/DevTools/IconBuilder`:

- `Icons/Vector/<Name>.xaml`: hand-traced 32-unit (28 for 14 px icons) WPF Canvas drawings,
  rendered at every size. Sources today: `ai/.tmp/icon-gallery/vector-src/*.xaml` (119 files).
- `Icons/Raster/<Name>.32.png`: hq2x 2x upscale of the keyed 16 px original, checked in as
  the source for icons that resist tracing (painterly ones: Protein family, Undo/Redo,
  EditLink, Cut, Find, Save, Copy_Bitmap, ...). hq2x is run offline once per source change
  (Python hqx in a venv, Pillow < 11; see `ai/.tmp/sessions/20261006-d785f537/hq2x_icons.py`);
  the tool only copies the 32 and bicubic-downscales to 20 and 24.
- `icons.manifest`: one line per icon: name, source kind (`vector` | `raster`), sizes.
  This records the per-icon choice made in the gallery.
- `Program.cs`: WPF render for vector sources (same code as ImageExtractor's BAML path),
  copy + downscale for raster sources; output `<Name>.<size>.png` per size. The native
  16 px stays the hand-tuned original for both kinds.
- Outputs are checked in like today's resources; the tool runs only when a source changes.

Transparency: keyed on magenta only (top-left pixel magenta); alpha PNGs as-is; opaque
bitmaps as-is. All outputs are 32-bit ARGB; consumers must use 32-bit image lists with a
Transparent key (the DPI branch already does above 100%).

## Decision source

- Gallery: `ai/.tmp/icon-gallery/skyline-icons-2x.html` (bicubic / hq2x / hq2x at 150% /
  vector columns, one choice per row, notes). Choices and notes live in the browser's local
  storage; export with "Show choices and notes" and paste. Round 1 snapshot:
  `ai/.tmp/icon-gallery/choices-round1.txt`.
- Build scripts (session folder `ai/.tmp/sessions/20261006-d785f537/`): `Build-IconGallery.ps1`,
  `Render-VectorIcons.ps1`, `hq2x_icons.py`, `Zoom-Nearest.ps1`, `Build-ContactSheet.ps1`.
  To be folded into the IconBuilder project and `ai/scripts/Skyline` as appropriate.

## Tasks

- [x] Branch created from the DPI branch tip (a7a85a182b)
- [x] Manifest from the round-1 gallery choices: 89 vector, 30 raster (hq2x rows); revise as
      the gallery decisions settle (`ai/.tmp/sessions/20261006-d785f537/New-Manifest.ps1`
      regenerates it from a choices export)
- [x] IconBuilder project: csproj (net10.0-windows, UseWPF + WinForms), Program.cs with the
      manifest reader, WPF vector render and bicubic raster scaling, README, .gitignore
- [x] Vector sources (119 xaml) and hq2x rasters (all 119, so a manifest line can flip) and
      `Tools/hq2x_icons.py` moved into the project
- [x] First full run (2026-10-20): 357 files, 0 failures, all square 32-bit ARGB at the named
      size; log `ai/.tmp/sessions/20261006-d785f537/iconbuilder-run1.log`, sample sheet
      `iconbuilder-sample.png` in the same folder. Output/ is git-ignored until wired in
- [ ] Review the generated set in the gallery at 20/24/32 (add an "IconBuilder output" column)
- [ ] Wire the outputs into Skyline resources on the DPI branch (separate step/PR)
- [ ] README for the tool; mention in ai/docs/github-repo-guide.md if a script wrapper is added

## Notes

- The 14 px tree icons (Blank, PeakBlank, ChromLib, AllIonsStatusButton, FragmentS,
  FragmentLibS, LabKey, RedXTransparentBackground) scale to 14/18/21/28, not 16/20/24/32.
- 41 Resources bitmaps are opaque with white backgrounds (tree glyphs, UI mode icons); their
  vector versions draw the glyph only on transparent, which the gallery shows.
