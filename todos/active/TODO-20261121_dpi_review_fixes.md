# TODO-20261121_dpi_review_fixes.md

## Branch Information
- **Branch**: `Skyline/work/20261121_dpi_review_fixes`
- **Base**: `master`
- **Created**: 2026-11-21
- **Status**: In Progress
- **Module**: `skyline`
- **PR**: (to be created)
- **Related**: issue #4599 (DPI awareness), #4602 (system-DPI-aware Skyline), #4887 (IconBuilder and
  per-DPI icons); uw-maccosslab/developers master (DigitalRune docking source)

## Objective

Fix the high-DPI problems found in a code review of owner-drawn controls, image lists and
code-built layouts after #4887, and in Brendan's test-and-fix pass at 150% and 250% on
2026-11-21. Every change is a no-op at 100% except the deliberate ones: the Upload to Panorama
window icon, the code-built Share dialog's layout, and the leak fixes (no visible change).

## Done (tested by hand at high DPI by Brendan)

- [x] Narrow dialogs (EditListDlg, EditEnzymeDlg, GenerateDecoysDlg, ...): `CommonFormEx`
      records the designed client size and resets it after the first autoscaling. Windows clamps
      a form to `MinWindowTrackSize` (device pixels, 324 at 250%) while InitializeComponent still
      sets 96-DPI sizes, and autoscaling then scales the clamp as well; about 20 floating dialogs
      were designed narrower than that. Reproduced without Skyline code
      (`ai/.tmp/sessions/20261118-pr4887/minsize_repro*.ps1`)
- [x] List views: `DpiScale.ScaleColumnWidths` (ColumnHeader is not a control, so autoscaling
      skips it) in BaseFileDialogNE (Details view, plus the literal 200) and PanoramaFilePicker
      (plus the literal 60); BaseFileDialogNE `TileSize`
- [x] Image list icons by key: `DpiIcons.LoadKeyedIcon` tries the other size set (14 px icons
      stretched to 16 in a list) and falls back to every loaded assembly (PanoramaClient's
      folder browser uses Skyline's files); publish dialogs add their tree images under their
      resource names
- [x] Panorama: Open From Panorama file list shows the Skyline document icon the way the Targets
      dock tab does (`DpiFormIcons.GetFrameImage`, a copy of SkylineDoc.ico in PanoramaClient);
      window icon from the PanoramaDownload drawing (`DpiIcons.LoadIcon(name, ...)`); Upload to
      Panorama window icon is PanoramaPublish (`DpiFormIcons.CreateIcon`) at every DPI, so its
      100% screenshots change; `Panorama.24.xaml` hinted for 24 px
- [x] DigitalRune: window-list/options and scroll triangles drawn as shapes above 100%
      (developers master, on top of f5d20c1)
- [x] ShareListDlg<TItem> (EditListDlg Share): laid out in 96-DPI units with AutoScaleMode.Font,
      sizable, anchored
- [x] Leaks: StatementCompletionForm (ImageList bitmap per paint), ImageListBox (brush),
      FindResultsForm and StatementCompletionForm (bold font per paint), TextRendererHelper
      (constructor font replaced by every caller)

## Follow-ups

- [ ] Hardklor workflow: `FullScanSettingsControl.cs:1097` and
      `BuildPeptideSearchLibraryControl.cs:618` set `Top = 12` in device pixels (6 px high at
      150%); take the position from a designer-placed control
- [ ] Reports Edit List Share exports the selected reports only, with no hint in the UI; open the
      ShareListDlg checklist with the selection checked, or name the count
- [ ] Merge ShareListDlg<TItem> with the designer-built ShareListDlg<TList, TItem>
      (Select / deselect all), which needs a common serializer path
- [ ] Panorama.20.xaml (125%); ArdiaIcon has no vector; File/UnknownFile and places-bar icons
- [ ] Success message icon (32 px in a 48 px space) not checked
- [ ] Follow-ups from TODO-20261020_icon_builder.md (completed) still open: tutorial covers,
      .ico size sets, soft raster icons, DigitalRune restyle, TreeViewMS plus/minus

## Progress Log

### 2026-11-21 - Review and fixes

Code review of owner-drawn controls, image lists, self-painting controls and code-built
layouts across pwiz_tools/Skyline and pwiz_tools/Shared, then fixes as Brendan tested each
area at 150% and 250%. Most review candidates turned out fine in practice (Full-Scan tab is
AutoSize, node tooltips, column-type drop-down, message box Copy button).
