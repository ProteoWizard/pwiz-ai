# TODO-20261015_export_flag_color.md - Note color in the Document Grid, editable and importable

## Branch Information
- **Branch**: `Skyline/work/20261015_export_flag_color` (checkout `C:\skygit\sky_exportflagcolor`,
  a worktree of `C:\skygit\pwiz`; pushed 2026-10-15)
- **Base**: `master`
- **Module**: `skyline`
- **Created**: 2026-10-15
- **Status**: In Progress
- **GitHub Issue**: (none)
- **Support thread**: https://skyline.ms/home/support/announcements-thread.view?rowId=76085
  (earlier ask: rowId=74176). Requested by Darcy.
- **PR**: (pending)

## Objective
Users flag Targets tree nodes with a note color (`Annotations.ColorIndex`, indexing
`Annotations.COLOR_BRUSHES`) to mark good/bad peaks, and want to export it in reports.

* Show the note color as a Document Grid column on Targets tree entities.
* Edit it in the grid with a dropdown of color names.
* Export it in reports and import it with File > Import > Annotations.
* Color names display in the current UI language (English, Chinese, Japanese).

## Decisions (Nick, 2026-10-15)
- Levels: Protein, Peptide/Molecule, Precursor, Transition only (not result notes).
- Exported value is the color name: localized in a localized report, invariant `Name`
  in an invariant report (`NoteColor.ToString`, same as `StandardType`). Annotation CSVs
  write the invariant `Name` (precedent: `StandardType`/`SampleType` formatters) and read
  the name or a title in any of en/ja/zh-Hans, case-insensitive.
- A flag only exists when the node has a note or annotation (`Annotations.IsEmpty`), and
  a color alone is not saved. So setting a color on a node with no note sets the note to
  the localized placeholder "Flagged" (`NoteColor.PlaceholderNote`). Removing the color
  clears the note only if it still equals the placeholder in any language.
- `NoteColor` is a `sealed record` with a private constructor (asked for record on .NET 10).
- Only English resx strings added; ja/zh-Hans come through the translation workflow
  (`IncrementalUpdateResxFiles` would revert hand-added translations).
- Ad hoc testing through the Skyline MCP instead of a new functional test for the grid.

## Design notes
- `Annotations.NoteColor` returns what the tree draws: null when `IsEmpty`, else
  `ColorIndex` clamped (so -1 shows as Orange Red). `ChangeNoteColor` is a no-op when the
  drawn color does not change, which keeps -1 notes from becoming 0 on an annotation
  round trip (`TestImportAnnotations` checks document equality).
- Choosing the blank dropdown entry on a node with a user note sets `ColorIndex` to -1,
  which still draws Orange Red, so the cell shows Orange Red afterwards.
- Import order matters for a hand-made CSV: NoteColor before a blank Note would add the
  placeholder and then clear it. Exported CSVs put Note before NoteColor.
- `ExportAnnotationSettings.AllAnnotations` (tests only) now includes NoteColor.

## Tasks
- [x] Fixed ArgumentException in NumericColorScheme when a colored report column
      contains infinity (exception report, unrelated to the support request but same branch)
- [x] NoteColor column on Protein, Peptide, Precursor, Transition
- [x] Dropdown editor (`NoteColorDataGridViewColumn`) with localized color names
- [x] Report export and import via File > Import > Annotations
- [x] Unit test `TestNoteColor`; `TestImportAnnotations` round-trips colors
- [ ] Ad hoc testing via Skyline MCP (grid dropdown, Targets tree flag, export/import)
- [ ] `/code-review max` before opening the PR
- [ ] Open PR, reply on the support thread

## Progress Log
- 2026-10-15: NumericColorScheme fix + ColorSchemeTest committed (b1b8317d7f).
- 2026-10-15: Note Color column committed (4a4af19859). Passing: TestNoteColor,
  TestImportAnnotations, TestCommandLineImportAnnotations, the four column caption/tooltip
  tests, TestEditNote, AnnotationMergeTest, TestNumericColorScheme, CodeInspection.
  Branch pushed (needed `git -c http.version=HTTP/1.1 push`; HTTP/2 push kept resetting).
