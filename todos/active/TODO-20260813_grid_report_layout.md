# TODO-20260813_grid_report_layout.md - Grid windows remember their report in the window layout

## Branch Information
- **Branch**: `Skyline/work/20260813_grid_report_layout`
- **Checkout**: `I:\git_i\sky_exportlayout`
- **Module**: `skyline`
- **Base**: `Skyline/work/20260813_export_import_layout` (rebase onto master once that merges)
- **Created**: 2026-08-13
- **Status**: Paused - implemented and green, but the back-compat design needs redoing (below)
- **GitHub Issue**: (none)
- **PR**: (not opened)

## Objective

A restored layout recreates the Document Grid / Audit Log / Results Grid / list window, but
each comes back on whatever report a **global** setting last held
(`Settings.Default.DocumentGridView`, `AuditLogView`, `ResultsGridActiveViews`), not the one
the layout captured. So the window reappears showing different data than it had.
`FoldChangeGrid` already persists its report; these should too. (The report is `ViewName` in
code, reached through `GetViewName()`.)

## Why this is its own branch

It rode along on `Skyline/work/20260813_export_import_layout` for a while, then was split off
on 2026-08-13 so that branch could stay focused on the two menu items. The split was a
`git branch` at the tip followed by a `git reset --hard` on the layout branch, so **every
commit is preserved here**; nothing needs recovering.

It still sits on top of the export/import work because its test uses that branch's
`ExportLayout` / `ImportLayout` helpers. Rebase onto master after the layout PR merges.

## What is implemented (all green)

**It all lives in `DataboundGridForm`.** A first pass gave each subclass its own
`GetPersistentString` override plus a static parser with a hardcoded part index - five copies
of one idea. The only thing that actually differs between these forms is that `ListGridForm`
writes an extra part and the report has to land after it. That is one virtual hook.

- `GetPersistentString` is **sealed** on the base: window type, then
  `GetPersistentStringParts()`, then the report. Sealing guarantees the report is always last
  and always at the index the parser reads.
- `GetPersistentStringParts()` is the hook, empty by default. `ListGridForm` is the only
  override, returning the list name - still `type|listName|viewName`, and `GetListName` still
  reads part 1.
- `RestoreViewFromPersistentString` reads the report from
  `1 + GetPersistentStringParts().Parts.Count`, so no subclass needs to know an index.
  `SkylineGraphs.RestoreView` just hands it the string.
- `ViewToRestore` is applied once in `OnShown` and cleared, so the user is free to change
  report afterwards.

Every `DataboundGridForm` gets it: `DocumentGridForm`, `AuditLogForm`, `LiveResultsGrid`,
`ListGridForm`, `CandidatePeakForm` and `SpectrumGridForm`.

### The hazard that was found and fixed

`DeserializeForm` tested `Equals(persistentString, typeof(X).ToString())` for
`LiveResultsGrid`/`ResultsGridForm`, `DocumentGridForm`, `AuditLogForm` and
`CandidatePeakForm`. Appending anything makes that comparison fail and the window is then
**silently not restored at all** - no error, it just stops appearing. All became `StartsWith`,
which also keeps older layouts working: they are the bare type name.

### Coverage

`LayoutExportImportTest.TestGridReportRestored`: Document Grid on Precursors, export, switch
to Proteins, import, assert it is back on Precursors. Teeth verified - dropping the persist
override fails it with `Expected:<.Precursors>. Actual:<.Proteins>`, the reported bug.

Only the Document Grid path is covered. The logic lives once in the base class so the others
run the same code; what is untested per-form is `ListGridForm`'s `GetPersistentStringParts`
override, the single place the report's index can move.

## THE OPEN DESIGN PROBLEM: back compatibility

Released Skyline matches these window types with `Equals`, so **any** appended part makes it
drop the window entirely rather than merely restore it on the wrong report. And this is not
confined to the new Export menu item: `SaveLayout` runs on **every document save**
(`SkylineFiles.cs`) and on **Share Document**, which bundles the `.sky.view` into the
`.sky.zip`. So a collaborator on the current release opening a shared document would lose the
window.

### What is in the branch now, and why it is not good enough

`AppendViewName` omits the report when it is "the default" - the first of
`viewContext.GetViewSpecList(ViewGroup.BUILT_IN.Id).ViewSpecs` - so a grid on its default
still persists as the bare type name. Three problems, all confirmed:

1. **The guess is wrong for the Audit Log.** `AuditLogForm.MakeAuditLogForm` passes
   `viewInfos[2].Name` ("All Info") as its default while `viewInfos[0]` is "Undo Redo". So the
   stock default gets written (breaking back compat for that window) and "Undo Redo" gets
   omitted (losing the report). Wrong in both directions.
2. **Omitting the default means "restore nothing", not "restore the default"**, so the global
   setting wins and the feature is a no-op for the most common case.
3. **"Default" is not stable across documents** - the first built-in view is UI-mode dependent
   (Proteins vs Molecule Lists), so the same file means different things on two machines.

### The intended replacement (designed, not implemented)

Target the format explicitly instead of guessing:

- A static `ThreadLocal` on `DockableFormEx` holding the `.sky.view` format being written.
  `ThreadLocal` is sufficient because `dockPanel.SaveAsXml` calls `GetPersistentString`
  synchronously on the calling thread. Model the scope on
  `CompactFormatOption.SetOverride` / `OverrideScope`, which is the house pattern for an
  ambient serialization override.
- `GetPersistentString` writes the report only when the target format is at least
  `DocumentFormat.VERSION_26_11` (which is `CURRENT`). No default-guessing at all - the report
  is always written in the current format, which also removes problems 2 and 3.
- The only place that needs an older format is `SkylineWindow.ShareDocument`, around its
  `SaveLayout(tempDocumentPath)` call, when
  `shareType.SkylineVersion?.SrmDocumentVersion` is below `VERSION_26_11`. Note
  `ShareType.SkylineVersion` can be null, meaning current - the established idiom is
  `shareType.SkylineVersion?.SrmDocumentVersion ?? doc.FormatVersion` (`SrmDocumentSharing.cs:280`).

### Deferred: localized report names

A layout carries the report's **display** name, which is localized and UI-mode dependent, so a
file written by an English Skyline may not resolve on a Japanese one (and
`DataboundGridControl.ChooseView(ViewName)` returns false, which the restore path currently
discards). The idea of writing the invariant English name and translating on read via
`PersistedViews.GetLocalizedReportNames` was **dropped**: that mapping only covers `main`-group
reports from `GetReportListsByVersion()`, and built-in report names are not from there - they
are set when the `RowSourceInfo`s are created in the view context.

## Outstanding review findings

From `/code-review max` on the combined branch. These belong here, not on the layout branch:

- `GetDefaultViewName()` is wrong for `AuditLogForm` (problem 1 above) - **confirmed by
  reading `MakeAuditLogForm`**. Disappears with the format-targeting design.
- Old Skyline drops the window entirely; exposure includes every document save and Share
  Document, not just the Export menu item.
- Omitting the default means the global setting wins.
- `ChooseView(ViewName)` returns false when the report cannot be resolved; the return value is
  discarded and `ViewToRestore` has already been cleared, so there is no retry and no
  diagnostic. Localized / UI-mode-mismatched / deleted reports all land here silently.
- `OnShown` is the restore trigger, but a form restored hidden or as a non-active tab never
  raises it; the next layout save then writes the report the fresh form happens to be on,
  discarding the staged one.
- `LiveResultsGrid` cannot be expressed by one unqualified `ViewName`: its view context is
  rebuilt per row source from the tree selection, and its report is already remembered per row
  source in `Settings.Default.ResultsGridActiveViews`.
- The `Equals` -> `StartsWith` conversions use a raw prefix with no `|` boundary and no
  `StringComparison.Ordinal`. `AuditLogForm` literally derives from `DocumentGridForm` and
  escapes capture only because it lives in a different namespace.
- Not verified, lower severity: an extra re-bind per grid with no already-on-that-view guard;
  the read index is asymmetric with the sealed write template while `GetListName` hardcodes 1.

## Key Files

- `pwiz_tools/Skyline/Controls/Databinding/DataboundGridForm.cs` - all of it
- `pwiz_tools/Skyline/Controls/Lists/ListGridForm.cs` - the one `GetPersistentStringParts` override
- `pwiz_tools/Skyline/SkylineGraphs.cs` - `RestoreView`, and the `StartsWith` conversions in `DeserializeForm`
- `pwiz_tools/Skyline/TestFunctional/LayoutExportImportTest.cs` - `TestGridReportRestored`
- `pwiz_tools/Skyline/Util/DockableFormEx.cs` - where the format ThreadLocal would go
- `pwiz_tools/Skyline/Model/Serialization/CompactFormatOption.cs` - the ambient-override pattern to copy

## Progress Log

### 2026-08-13 - Session 1
- Implemented on the export/import branch; all targeted tests green.
- `/code-review max` surfaced the back-compat and default-guessing problems above.
- Split onto this branch so the export/import PR stays focused; the format-targeting redesign
  is the next piece of work here.
