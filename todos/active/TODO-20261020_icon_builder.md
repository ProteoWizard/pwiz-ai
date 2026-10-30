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
5. **Trial capture with the new icons, requested 2026-10-29 (for the DPI session).** The
   assets branch `Skyline/work/20261020_icon_assets` is pushed through 0fbf5d3536 (PR #4887;
   381 PNGs in `Resources/Icons`, manifest at 112 vector / 16 raster). In pwiz1 make a
   throwaway branch from the DPI tip, `git merge origin/Skyline/work/20261020_icon_assets`
   (expect a small conflict in `Skyline.csproj`, both branches touch it; nothing else should
   overlap), build, and run the capture sweep at 100/125/150/200% on the forms that show
   icons. As of 2026-10-29 only SequenceTree, FilesTree, StatementCompletionTextBox and the two
   ViewLibraryDlg images call `DpiUtil.GetIcon`, so only those show the new drawings; toolbars,
   menus and buttons still get WinForms-scaled 16 px bitmaps. Nothing from the throwaway
   branch is pushed; drawing fixes come back through this TODO's gallery.
   DONE 2026-10-29 (DPI session): MethodEdit, LibraryExplorer, CustomReports, GroupedStudies1
   at 150% + MethodEdit at 96 DPI, gallery ai/.tmp/dpi-sweep/tutorials/index-icons.html. The
   wired sites (Targets/Files trees incl. state images, completion list, Library Explorer)
   show the 24 px PNGs; toolbars (main, grids, graphs) and dock tab icons are unchanged =
   the unwired list. Details in TODO-20260820_dpiAwareness.md, entry "Icon-assets trial".
6. **Toolbar, menu and button wiring (DPI side, proposed 2026-10-29).** Designers assign
   `Resources.X` directly and an Image carries no resource name (`Resources.X` returns a new
   bitmap per call, so reference matching fails). Proposed helper, called once per ToolStrip
   after `InitializeComponent`: hash the pixels of every Resources.resx bitmap once (name ->
   hash), walk the strip's items recursively, and replace each matched image with
   `DpiUtil.GetIcon(control, name, native, item.ImageTransparentColor)`. Covers toolbars, menus
   and context menus without per-designer edits. Buttons outside ToolStrips need the same
   lookup on `ButtonBase.Image`.
   DONE on the DPI branch 2026-10-29 (DpiUtil.PrepareIcons, uncommitted pending approval), with
   one addition to the design: ToolStripItem.Image's setter applies ImageTransparentColor to the
   bitmap (the natives are magenta-keyed BMPs), so the lookup keeps one table per key color,
   built by keying the natives the same way. Verified with the assets: main toolbar, grid and
   graph toolbars draw the 24 px PNGs. Shared NavBar items (pwiz.Common resources) stay as they
   are. Details in TODO-20260820_dpiAwareness.md, entry "Toolbar, menu and button icons".

Assets branch commits after the push of 0fbf5d3536: c7443e63f6 (code-review medium fixes:
navigator Delete magenta key, DropDownArrow removed in favor of LiteDropDownList's own arrow,
TileFlipXY in the raster downscale, IconBuilder unknown-name and kind checks; build +
IconResourcesTest green; not pushed yet).

Contract: one call per icon,
`DpiUtil.GetIcon(this, nameof(Resources.Save), Resources.Save, Color.Magenta)`, returning a
32-bit ARGB bitmap of the right pixel size for the control's DPI, or the native at 100%.
The three `DpiUtil` members are owned here; signature changes are coordinated, not made on
the DPI branch.

## Window icons on dock tabs (DigitalRune) - 2026-10-22

The Targets, Files, Immediate, Find Results and Heat map tabs show their form's `Icon`
(inline `$this.Icon` in the form resx; Immediate, Find Results and Heat map equal
Resources\Immediate.ico, FindResults.ico and Cluster.ico). Targets carries 16/32/48 px frames
and Heat map 16-64, so no new artwork; Files, Immediate and Find Results have only 16 px.

The fork drew them wrong at every DPI: `Graphics.DrawIcon(icon, rect)` stretches the frame the
`Icon` instance was created with (32x32 from the resx) with nearest-neighbor, and
`new Icon(icon, size)` falls back to the next SMALLER frame (measured: 20 and 24 -> 16; 64 -> 48).
Fix written in the fork checkout (`Workspaces/ProteoWiz/developers`, branch
`DigitalRune/work/20261020_dpiScaling`, PR uw-maccosslab/developers #7), also saved as
`TODO-20261020_icon_builder-DigitalRune-IconFrames.patch`: `DpiHelper.SelectFrame` (exact
frame, else smallest larger, else largest smaller), `DpiHelper.DrawIcon` (exact frame via
DrawIcon, otherwise ToBitmap + bicubic), used by DrawDocumentTab, DrawToolWindowTab and the
auto-hide strip (which passed `icon.ToBitmap()` of the 32 frame). Builds clean (one
pre-existing CS0114 warning elsewhere). On PR #7 as f0204f7 (pushed by the DPI session, which
added a117881 listing DpiHelper.cs in the legacy .NET Framework project); next: rebuild the DLL
into #4602 with Build-DigitalRune.ps1. Visual check:
Targets tab at 200% should show the 32 px frame.

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
- [x] Handoff to #4602 applied (2026-10-20, c358532cd3 on the DPI branch, pushed):
      see the Handoff section
- [ ] magnifier_zoom_in: trace a vector if wanted (currently raster)
- [x] #4886 (stacked on the DPI branch) closed; assets re-cut from master as
      `Skyline/work/20261020_icon_assets`, commit f74a028bf2, PR #4887 against master. Build +
      IconResourcesTest green on master's tree. The test is self-contained (own size list and
      suffix lookup) because master has no DpiUtil yet
- [x] Inline designer glyphs centralized (2026-10-27, 83134adcc1 on the assets branch, pushed):
      the five binding-navigator bitmaps, the EditPepModsDlg/EditSpectrumFilterDlg combo chevron
      and the ConfigureToolsDlg macro arrow moved from base64 in 15 form resx files to
      Resources/*.png + Resources.resx entries; designers assign the typed properties; the
      navigator delete buttons reuse Resources.Delete; vectors, manifest lines and 20/24/32 px
      outputs added (127 manifest entries). Left as is: 12 uses of the WinForms designer
      placeholder image across 10 controls (see inline-icons.csv in ai/.tmp/icon-gallery)
- [ ] Address review on #4887 (artwork); drawing fixes go through the gallery -> XAML ->
      IconBuilder re-run -> commit on the assets branch
- [x] Gallery review round 3 (2026-10-27/28, `choices-round3.txt`): 21 vectors revised (thinner
      plus signs, square-cut red X, stepped chromatogram peaks, Note gradient, Panorama rings
      right-shifted, Open arrow, Print turned, ProtDB cylinder, UIModeProteomic wavy ribbon with
      hq2x chosen so the manifest flips it to raster) and FindResults, Immediate,
      magnifier_zoom_in traced for the gallery only. Uncommitted in pwiz2 with round 4
- [x] Gallery review round 4 (2026-10-29, `choices-round4.txt`): the 1x blur has one cause,
      WPF draws a Rectangle's stroke inside its box, so a 2-unit frame at Left 5 covers units
      5..7 and straddles two device pixels at 1x (one pixel = two units); Trash was sharp because
      it uses Paths and filled rectangles. Frames moved onto even units in IrtCalculator (sharp
      corners, transparent interior), MethodFile, ViewFile, AuditLog, Comment, Copy_Bitmap, OptDB;
      Immediate's exclamation mark and FindResults' binoculars (shorter, specular column, equal
      text rows) retraced on the pixel grid; TransitionGroupDecoy/LibDecoy traced from the native
      pixels (stepped, native colors); TransitionGroupLib's glyph bars aligned with FragmentLib's;
      MoleculeList shows fluorene; Open's arrow curls around the page corner; Print at 90%; the
      Wand's white end cap; Panorama rings toward 255,211,63; UIModeProteomic ribbon highlights.
      `Scan-Alignment.py <VectorDir>` (session folder) lists off-grid edges: 70 of 129 files
      still have some, mostly gradient/1-unit-stroke art that cannot be crisp at 1x anyway.
      Gallery rows FilesTreeForm__Icon, FindResultsForm__Icon, ImmediateWindow__Icon now show the
      FilesTree, FindResults and Immediate vectors (alias table in Build-IconGallery.ps1)
- [x] Round 5 one-by-one fixes from marked-up screenshots (2026-10-29) and the commit of rounds
      3-5: 0fbf5d3536 on the assets branch (138 files; pushed 2026-10-29). Print, FindResults'
      binoculars, Find, FindNext and the new FilesTree folder are traced from the native pixels
      on the 2-unit grid (`Trace-Pixels.py` + `Dump-Pixels.ps1` in the session folder turn a
      bitmap into merged rectangle runs); Immediate's mark on rows 6-11/13-14 with the window one
      row shorter; ViewFile and IrtCalculator carry the native's 10% interior tint; the Wand ends
      in a squared-off point in the corner; MoleculeList's fluorene points left; OpenFolder's
      arrow lowered off the top edge. Manifest resynced to `choices-round5.txt`: 112 vector,
      16 raster (Find, FindNext, MethodFile, Open, magnifier_zoom_in -> vector; Pinleftlight,
      UIModeMixed -> raster). 381 outputs verified square 32-bit ARGB at their named sizes; no C#
      changed, so no build was run for this commit
- [ ] pwiz.Common icons (2026-10-29): the first inventory covered only Skyline/Resources, so
      the Edit Report dialog (all of `Shared/Common/DataBinding/Controls/Editor`) and the
      Document Grid bar were missed. 33 small images in `Shared/Common/Resources`; only Skyline
      shows pwiz.Common UI (BiblioSpecUtil/ProteomeDb reference it for utilities only).
      Gallery has 33 `Common_` rows (same file and storage keys). Drawings, uncommitted, in
      `IconBuilder/Icons/Vector/Common/` from `Write-CommonVectors.py` (session folder): 9
      traced orthogonal (Cluster, FreezeCells, HiddenColumns, PivotColumn, SublistColumn,
      maximize, restore, agg_max, agg_min), 16 hand-drawn (agg_groupby and MatchCase redrawn
      after the traced versions looked pixelated at 2x: trace only pure orthogonal art), (close,
      agg_sum/mean/median/count/stddev, Number/Text/Bool/LinkColumn, UnknownUiMode, Pivot,
      PivotAndFilter, Alphabetical), Delete/Filter/up/down copied from Skyline (pixel-identical
      natives), DataColumn/PlainLayout/agg_blank empty (transparent natives),
      DropImageNoBackground (10x4, recolored at run time by LiteDropDownList) not drawn.
      Next: dev review in the gallery; then decide with the DPI session where the loader lives
      (pwiz.Common cannot call Skyline's DpiUtil: move the lookup into pwiz.Common taking the
      owning assembly, DpiUtil.GetIcon wraps it), add an IconBuilder per-assembly output and
      embed `Shared/Common/Resources/Icons` in Common.csproj
- [x] pwiz.Common assets (2026-10-29, assets branch, not pushed): 95ea7739b7 the 32 drawings;
      850292a452 `common.manifest` (31 entries, all vector except Filter, raster; directives
      `@vector/@raster/@output`, IconBuilder builds every *.manifest by default), 93 PNGs in
      `Shared/Common/Resources/Icons` embedded by Common.csproj, unused `Filter1` resource and
      `agg_blank` drawing removed, `TestEmbeddedCommonIconSizes` added (green with build)
- [ ] DPI side: a loader pwiz.Common can call. pwiz.Common cannot reference Skyline, so the
      name/size lookup (today `DpiUtil.GetIcon` reading `typeof(DpiUtil).Assembly`) needs a
      home in pwiz.Common taking the owning assembly, with DpiUtil wrapping it; PrepareIcons
      pixel matching must also index pwiz.Common Resources.resx for the Edit Report dialog and
      Document Grid bar. Sizes follow `GetIconSizes` (MatchCase is 15 px: 16 px size set)
- [ ] pwiz.Common inline images: NavBar.resx (10) and ViewEditor.resx (7) embed their images
      base64 (Alphabetical, HiddenColumns, Cluster among them; same art as the Resources
      .bmp files, alpha instead of magenta). Move them into pwiz.Common Resources.resx as
      83134adcc1 did for Skyline so PrepareIcons can match them; add any undrawn ones to the
      gallery
- [ ] Window icons (FindResults, Immediate, FilesTree): an .ico output kind in IconBuilder and a
      DpiUtil path for Form.Icon before their vectors can ship; gallery choices still open
- [ ] After #4602 and #4887 are both on master: point IconResourcesTest at
      DpiUtil.GetIconSizes / GetIconResourceName (ten-line cleanup)
- [ ] README for the tool is written; mention in ai/docs/github-repo-guide.md if a script
      wrapper is added

## Notes

- The 14 px tree icons (Blank, PeakBlank, ChromLib, AllIonsStatusButton, FragmentS,
  FragmentLibS, LabKey, RedXTransparentBackground) scale to 14/18/21/28, not 16/20/24/32.
- 41 Resources bitmaps are opaque with white backgrounds (tree glyphs, UI mode icons); their
  vector versions draw the glyph only on transparent, which the gallery shows.
