# Window layout dialogs filter on ".view", not ".sky.view"

## Branch Information
- **Branch**: `Skyline/work/20260916_layout_view_extension`
- **Checkout**: `I:\git_i\sky_tutorial`
- **Base**: `master`
- **Created**: 2026-09-16
- **Status**: In Progress
- **GitHub Issue**: (none; noted under "Minor" in #4671)
- **Module**: `skyline`
- **PR**: [#4678](https://github.com/ProteoWizard/pwiz/pull/4678)

## Objective

File > Export/Import > Window Layout used ".sky.view" as the file dialogs' extension and filter.
The shell compares only a typed name's LAST extension with the filter's, so a name typed as
"exported-layout.view" came out as "exported-layout.view.sky.view" (Brendan's MethodEdit run), and a
name typed with the full ".sky.view" needed a strip-the-duplicate workaround in ShowExportLayoutDlg.

Now, at Nick's direction, the extension is ".view" everywhere the dialogs are concerned: the filter
is "Window Layout Files (*.view)", DefaultExt is ".view", and the export dialog suggests the
document's own layout name "<document>.sky.view" as a whole file name. The workaround is gone.

## Tasks
- [x] `EXT_VIEW`, `FILTER_VIEW`; export and import dialogs use them; suggested name from GetViewFile
- [x] `LayoutExportImportTest` updated: base names now pick up ".view"; typed "Name.sky.view" and
      "Name.view" both come out as typed
- [x] Build Release, run TestLayoutExportImport and CodeInspection
- [x] Commit, push, PR #4678 (EXT_SKY_VIEW removed and the restating comments dropped at Nick's
      direction before opening)

## Progress Log

### 2026-09-16
- Split out of the #4671 work at the point Nick asked what the double extension was.
