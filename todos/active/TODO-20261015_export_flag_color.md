# TODO-20261015_export_flag_color.md - Note color in the Document Grid, editable and importable

## Branch Information
- **Branch**: `Skyline/work/20261015_export_flag_color` (checkout `C:\skygit\sky_exportflagcolor`)
- **Base**: `master`
- **Module**: `skyline`
- **Created**: 2026-10-15
- **Status**: In Progress
- **GitHub Issue**: (none)
- **Support thread**: https://skyline.ms/home/support/announcements-thread.view?rowId=76085
  (earlier ask: rowId=74176)
- **PR**: (pending)

## Objective
Users flag Targets tree nodes with a note color (`Annotations.ColorIndex`, indexing
`Annotations.COLOR_BRUSHES`) to mark good/bad peaks, and want to export it in reports.

* Show the note color as a Document Grid column on Targets tree entities.
* Edit it in the grid with a dropdown of color names.
* Export it in reports and import it with File > Import > Annotations.
* Color names display in the current UI language (English, Chinese, Japanese).

## Tasks
- [x] Fixed ArgumentException in NumericColorScheme when a colored report column
      contains infinity (exception report, unrelated to the support request but same branch)
- [ ] Note color column on Protein, Peptide, Precursor, Transition (results levels TBD)
- [ ] Dropdown editor with localized color names
- [ ] Report export value (invariant) and import via File > Import > Annotations
- [ ] Tests

## Progress Log
- 2026-10-15: NumericColorScheme fix + ColorSchemeTest committed.
