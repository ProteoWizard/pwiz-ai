# TODO-20261020_icon_builder.md

## Branch Information
- **Branch**: `Skyline/work/20261020_icon_assets` (tool, assets, csproj wildcard, test)
- **Base**: `master`
- **Created**: 2026-10-20
- **Status**: In Progress
- **Module**: `skyline`
- **PR**: [#4887](https://github.com/ProteoWizard/pwiz/pull/4887) (artwork review by a human; nothing waits on it)
- **Superseded**: `Skyline/work/20261020_icon_builder` / [#4886](https://github.com/ProteoWizard/pwiz/pull/4886),
  closed 2026-10-20: it was stacked on the DPI branch and carried the loader too. Its
  `DpiUtil.GetIcon` goes into #4602 via `TODO-20261020_icon_builder-DpiUtil-GetIcon.patch`
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

## Deployment design (agreed 2026-10-20)

Generated icons are embedded PNG files looked up by name at run time; no resx entries.

- IconBuilder's default output is `pwiz_tools/Skyline/Resources/Icons/<Name>.<Size>.png`,
  checked in like the native bitmaps. Skyline.csproj (SDK-style) embeds them with one line:
  `<EmbeddedResource Include="Resources\Icons\*.png" />`. Adding an icon or a size never
  touches the project file.
- `DpiUtil` gains the single entry point for DPI-sized icons (name to be settled when written,
  e.g. `DpiUtil.GetIcon(Control control, string name, Image native, Color? transparentKey)`):
  picks the size from the control's DPI factor (20 at 125%, 24 at 150%, 32 at 200%; 18/21/28
  for 14 px icons; other factors take the next larger file bicubic-downscaled), loads the
  embedded stream once into a cache keyed by name and size, and falls back to the existing
  bicubic `ScaleImage` of the native bitmap when no file exists. At 100% it returns the native.
- Call sites pass `nameof(Resources.X)` next to the bitmap they already pass, so names are
  compiler-checked and survive renames. The manifest's source kind is invisible here.
- A test (Test.csproj) walks `Resources` for every 16 and 14 px bitmap and asserts the three
  embedded sizes exist, so a missing or misnamed output fails CI instead of silently blurring.
- Rejected: resx entries (357 entries in Resources.resx and Resources.Designer.cs, regenerated
  and reviewed on every change, for accessors a size-keyed lookup would not use); multi-size
  .ico or sprite files (opaque to review, GDI+ frame selection rules).

## Handoff to the DPI awareness branch (TODO-20260820_dpiAwareness, PR #4602)

Decided 2026-10-20: #4602 ships first and is never blocked by the artwork review, so the two
halves travel separately.

1. **The loader goes into #4602 itself.** DONE 2026-10-20: c358532cd3 on the DPI branch
   (patch applied unchanged; call sites wired; lists prepared by the new
   `ImageListScaler.PrepareForDpi`; the column-select combo glyph stays on `ScaleImage`
   because it is recolored at run time). Details in TODO-20260820_dpiAwareness.md, entry
   "icon_builder handoff applied". `DpiUtil.GetIcon` (plus `GetIconSizes` and
   `GetIconResourceName`) is written and tested; the DPI agent applies
   `TODO-20261020_icon_builder-DpiUtil-GetIcon.patch` (next to this file; a plain diff of
   `pwiz_tools/Skyline/Util/DpiUtil.cs` against the DPI branch tip a7a85a182b, `git apply`)
   and wires the call sites: the three `DpiUtil.ScaleImage` call sites
   (ImportTransitionListColumnSelectDlg, ViewLibraryDlg x2) and the tree image lists
   (SequenceTree, FilesTree, StatementCompletionTextBox `AddNodeImage`/`AddImage`), which
   today add the native 16 px bitmaps directly. Lists must be 32-bit with
   `TransparentColor = Color.Transparent` and `ImageSize` scaled to the DPI. With no embedded
   icons on that branch, `GetIcon` takes its fallback path and behaves exactly like
   `ScaleImage`, so #4602 is unchanged in behavior until the assets land.
2. **The assets go to master on their own PR** (tool, `Resources/Icons`, csproj wildcard,
   `IconResourcesTest` made self-contained so it does not reference `DpiUtil`). Reviewed by a
   human for the artwork, at its own pace. When it merges and the DPI code is on master too,
   the embedded sizes exist and `GetIcon` starts returning them with no further code change.
3. Cleanup once both are on master: make `IconResourcesTest` use `DpiUtil.GetIconSizes` /
   `GetIconResourceName` instead of its private copies.
4. Icon corrections keep flowing through this branch's gallery and manifest; the DPI branch
   never edits drawings.

Contract: one call per icon,
`DpiUtil.GetIcon(this, nameof(Resources.Save), Resources.Save, Color.Magenta)`, returning a
32-bit ARGB bitmap of the right pixel size for the control's DPI, or the native at 100%.
The three `DpiUtil` members are owned here; signature changes are coordinated, not made on
the DPI branch.

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
- [x] Gallery "IconBuilder output" column at 125/150/200% with the manifest kind (2026-10-20)
- [x] Manifest resynced to the round-2 gallery choices (commit 3e49356703): 103 vector, 17 raster
- [x] Default output to `pwiz_tools/Skyline/Resources/Icons`; generated set checked in (360 files)
- [x] Skyline.csproj: `<EmbeddedResource Include="Resources\Icons\*.png" />`
- [x] `DpiUtil.GetIcon(control, name, native, key)` + `GetIconSizes` + `GetIconResourceName`:
      size from DPI factor, resample down between sizes, fallback to `ScaleImage`. No cache:
      each call decodes a 1-2 KB PNG and returns a bitmap the caller owns, same contract as
      `ScaleImage` (native disposed unless returned at 100%)
- [x] `IconResourcesTest` (Test.csproj): every 16/14 px Resources.resx bitmap has its three
      embedded sizes at the right dimensions. First run caught `magnifier_zoom_in` (a .ico the
      Resources-folder inventory had skipped); added as an hq2x raster. Passed 2026-10-20
- [x] Icon names = Resources.resx property names: add_pro32, down_pro32, up_pro32, HomeIcon1,
      Properties_Button renamed in Icons/Vector, Icons/Raster and the manifest; 13 icons have no
      Resources.resx entry (FolderSampleSet, Locked, Trash, ...; other resx or unused) and keep
      their file names
- [x] Handoff to #4602 applied (2026-10-20, c358532cd3 on the DPI branch, not yet pushed):
      see the Handoff section
- [ ] magnifier_zoom_in: trace a vector if wanted (currently raster)
- [x] #4886 (stacked on the DPI branch) closed; assets re-cut from master as
      `Skyline/work/20261020_icon_assets`, commit f74a028bf2, PR #4887 against master. Build +
      IconResourcesTest green on master's tree. The test is self-contained (own size list and
      suffix lookup) because master has no DpiUtil yet
- [ ] Address review on #4887 (artwork); drawing fixes go through the gallery -> XAML ->
      IconBuilder re-run -> commit on the assets branch
- [ ] After #4602 and #4887 are both on master: point IconResourcesTest at
      DpiUtil.GetIconSizes / GetIconResourceName (ten-line cleanup)
- [ ] README for the tool is written; mention in ai/docs/github-repo-guide.md if a script
      wrapper is added

## Notes

- The 14 px tree icons (Blank, PeakBlank, ChromLib, AllIonsStatusButton, FragmentS,
  FragmentLibS, LabKey, RedXTransparentBackground) scale to 14/18/21/28, not 16/20/24/32.
- 41 Resources bitmaps are opaque with white backgrounds (tree glyphs, UI mode icons); their
  vector versions draw the glyph only on transparent, which the gallery shows.
