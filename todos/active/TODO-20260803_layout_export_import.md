# TODO-20260803_layout_export_import.md - File > Import/Export > Layout (+ MCP view-layout repro)

## Branch Information
- **Branch**: `Skyline/work/20260803_layout_export_import`
- **Module**: `skyline`
- **Base**: `master`
- **Created**: 2026-08-03
- **Status**: In Progress
- **GitHub Issue**: (none yet)
- **PR**: (pending)

## Objective

Let a user save and load a window layout (`.view`) without saving the whole
document, and make loading a layout robust when it references windows the
current document cannot show.

## Background - two framings of the same problem

This TODO started life as `TODO-mcp_tutorial_view_layout.md`, written from the
MCP tutorial-testing side. That framing is preserved below as Phase 2, but the
primary work is now the product feature.

**The product gap.** Skyline has always had `.sky.view` layout files, but there
is no user-facing way to produce or consume one:

- `SkylineWindow.SaveLayout(fileName)` is **private** (`SkylineFiles.cs`) and is
  called only from document save and from Share (which copies the layout into
  the `.sky.zip`).
- Loading only happens **implicitly**, in `UpdateGraphUI` (`SkylineGraphs.cs`),
  when a document is opened and a sibling `<doc>.sky.view` exists.

So the only way to capture a hand-arranged dock layout today is to save a
document and then go find/rename the `.sky.view` artifact next to it. That is
exactly how the tutorial `.view` assets were authored, and it is why an ordinary
user cannot move a favorite layout between documents at all.

**The MCP gap.** The tutorial-testing runbook proved the MCP can drive a tutorial
end-to-end but cannot reproduce screenshots whose layout is a hand-arranged dock
composite. Concretely MethodRefine **s-21**
(`TODO-20260609_native_file_dialog_automation-tests/TEST-MethodRefine.md`
Finding #1): the sub-agent loaded the right data and verified every graph
individually, but the tutorial docks Peak Areas right and RT-Comparison bottom by
**mouse drag**, and there is no MCP drag/drag-to-dock verb, so the composite
window cannot be assembled.

**Why the product feature mostly subsumes the MCP feature.** PR #4313 (native
file dialog automation + generic form verbs) merged as `a840067e8`. With Import
Layout reachable from the main menu, the MCP can drive it through the *already
merged* `skyline_click_main_menu_item` + native-file-dialog automation - no new
`skyline_load_view_layout` verb is needed. What remains MCP-specific is
`skyline_set_window_bounds` and the `pNN.view` -> `s-NN.view` renaming.

## Phase 1 - File > Import > Layout and File > Export > Layout (this branch)

### Menu items

Both go in the existing File submenus, matching the surrounding items
(title case, mnemonic, trailing ellipsis because both open a file dialog):

| Menu | Item | Name | Mnemonic |
|------|------|------|----------|
| File > Import | `&Window Layout...` | `importLayoutMenuItem` | `W` is unused in that dropdown |
| File > Export | `&Window Layout...` | `exportLayoutMenuItem` | `W` is unused in that dropdown |

"Layout" alone was too vague next to Annotations/Document/Report. The field and
method names stay `Layout` (unambiguous in code); only the user-visible text and
the dialog titles ("Import Window Layout" / "Export Window Layout") say "Window
Layout".

Placement: last in each dropdown, after Annotations. Both are document-state
independent (a layout can be exported from an empty document), so neither needs
`fileMenu_DropDownOpening` enable/disable logic.

### Behavior

- **Export Layout** - `SaveFileDialog` filtered to `*.sky.view` **with no
  all-files entry** (`FILTER_SKY_VIEW`, built with `TextUtil.FileDialogFilter`,
  not `FileDialogFiltersAll`). This is a safety requirement, not cosmetics:
  Windows suggests matching existing file names as the user types, so an
  unrestricted filter makes it easy to save a layout over the `.sky` document.
  Default file name derived from the current document name. Refactor the
  existing private `SaveLayout(fileName)` (which appends `.view` via
  `GetViewFile`) into a `SaveLayoutToFile(viewFilePath)` that writes an exact
  path; `SaveLayout` becomes a one-line caller. Same `FileSaver` +
  `dockPanel.SaveAsXml` + UTF-8-without-BOM path as document save, so exported
  files are byte-identical to the ones save produces.
- **Import Layout** - `OpenFileDialog` filtered to `*.view` (`FILTER_VIEW`, also
  no all-files entry). Wider than the save filter on purpose: `*.view` matches
  both `Doc.sky.view` and the single-extension `pNN.view` files the tutorial
  tests ship, which Phase 2 wants to open. Then `LoadLayout(stream)`, wrapped in
  the same failure message the implicit load path uses so a corrupt file reports
  rather than throws.

### Reporting windows that could not be restored

Previously a window that failed to restore was silently dropped, and a whole-file
exception produced only "rename or delete this file". Now `LoadLayout` collects
the persist string of every window it could not create, and `ShowLayoutProblems`
reports them in one message. **Both entry points call it**, so opening a document
and File > Import > Window Layout complain identically:

- `UpdateGraphUI` calls it after the dock panel layout lock is released (the
  `deserialized` flag had to be hoisted out of the `using` block to reach it).
- `ImportLayout` calls it after its `CloseInapplicableForms` pass.

**The two entry points differ in strictness** (`LayoutProblems`,
`Controls/LayoutProblems.cs`). Each window that could not be restored is
classified:

| `LayoutProblemType` | Meaning | Open document | Import Layout |
|---------------------|---------|---------------|---------------|
| `error` | Threw while restoring | report | report |
| `unrecognized` | Persist string matched nothing Skyline knows | report | report |
| `not_applicable` | Known window kind, does not apply to this document (list, replicate, group comparison missing; `MAX_GRAPH_CHROM` cap) | **silent** | report |

Rationale: the layout beside a document describes *that* document, so an
inapplicable window there is not worth interrupting for, while an unrecognized
one means the file is wrong ("clearly not a .sky.view file"). An imported layout
was just picked by the user and may belong to a different document, so every
window it did not get is worth saying.

`RestoreDockableForm` grew an `out bool recognized`, set true at the top and
false only at the single fall-through `return null`, so classification costs two
assignments rather than one per branch. The `GraphChromatogram` branch had to
gain an explicit `return null` - it previously fell through to that same
fall-through and would have been misreported as `unrecognized`.

`FoldChangeForm.CloseInapplicableForms` now returns the persist strings it
closed, and `ImportLayout` folds them in as `not_applicable`. Those forms are
restored *before* anyone checks whether their group comparison exists, so they
are invisible to `DeserializeForm` and would otherwise vanish unreported.
`ListGridForm.CloseInapplicableForms` needed no such change - `CreateListForm`
now returns null up front, so the form is never created.

The message lists raw persist strings; `CommonAlertDlg` scrolls, so a long list
is not a problem.

### Robustness when the layout references windows this document cannot show

`LoadLayoutLocked` is a **full replace**: it destroys every dockable form and
then rebuilds from the XML via `DeserializeForm`. Reading a layout captured
against a *different* document is now a first-class user action, so the paths
that were previously only exercised by "open a doc next to its own .view" need
hardening:

- `DeserializeForm` (`SkylineGraphs.cs`) already returns `null` for panes it
  cannot build (unknown persist strings, chromatogram graphs for replicates not
  in the document, `MAX_GRAPH_CHROM` overflow). But a single throwing branch
  aborts the whole `LoadFromXml` and can leave the dock panel half-torn-down.
  Make a failure to restore *one* pane skip that pane instead of the layout.
- `ListGridForm` for a list not in this document: `CreateListForm(listName)`
  returns `new ListGridForm(this, listName)` without checking
  `DataSettings.Lists`.
- The implicit load path relies on `UpdateGraphUI` calling
  `FoldChangeForm.CloseInapplicableForms` / `ListGridForm.CloseInapplicableForms`
  *after* the load. A menu-driven import does not go through `UpdateGraphUI`, so
  it must call them itself.

### Task Checklist

#### Completed
- [x] `EXT_VIEW` / `FILTER_VIEW` constants next to `GetViewFile` in `SkylineFiles.cs`
- [x] Refactor `SaveLayout` -> `SaveLayoutToFile(viewFilePath)`
- [x] `ExportLayout(path)` / `ImportLayout(path)` public methods + menu click handlers
- [x] `importLayoutMenuItem` / `exportLayoutMenuItem` in `Skyline.Designer.cs` + `Skyline.resx`
- [x] Resource strings (filter description, error messages) in `SkylineResources.resx` + `.designer.cs`
- [x] Robustness: per-pane failure isolation in `DeserializeForm`; `CreateListForm` returns null
      for a list not in the document; `CloseInapplicableForms` after a manual import
- [x] Functional test `LayoutExportImportTest` - menu wiring, dock-state round trip,
      unrecognized window skipped, list window absent from the document
- [x] Build + CodeInspection clean; ListClustering / SummaryGraphVisibility /
      TreeRestoration / FilesTreeForm still pass

- [x] Drove both menu items in the running app over the MCP connector - see the
      dialog-extension finding below

- [x] Regenerated `Documentation/Help/{en,ja,zh-CHS}/KeyboardShortcuts.html` - see below

#### Remaining
- [ ] Nothing known; ready for /code-review then a PR
- [ ] Localized menu text for `.ja.resx` / `.zh-CHS.resx` (bulk translation pass, not this PR -
      matches how every other menu item has landed)
- [ ] Push branch and open PR

### File dialogs cannot handle a two-part extension

Found by running the app, not by any test. With `Filter` = `*.sky.view` and
`DefaultExt` = `.sky.view`, the default file name came up as
`Bereman_5proteins_spikein.sky.view.sky.view`: a file dialog only understands the
**last** extension of a name, so it does not recognize that a ".sky.view" name
already ends in the extension, and appends it again.

Share Document has the same two-part extension (`.sky.zip`) and has always worked
around it the same way, which is the fix adopted here:

**Filter uses the single `.view`**, so the dialog sees the name already ends in
the filter extension and leaves it alone. `DefaultExt` was removed: with a single
filter that carries an extension, the dialog always uses the filter's and never
the default, so it was dead config. A name typed without an extension therefore
gets ".view", which is equally a layout file.

An earlier pass added an `EnsureViewFileName` that forced ".sky.view" onto
whatever the dialog returned. **Removed at the developer's direction** - keeping
the all-files entry out of the filter is the point, so the dialog cannot make a
dangerous name easy; a user who deliberately wants another name may have one.

### What the filter does and does not protect (measured, not assumed)

Driven live over the MCP connector against a document named like the developer's
screenshot:

| Action | Result |
|--------|--------|
| Open Export dialog | default `Bereman_5proteins_spikein.sky.view` - single, bug fixed |
| Save with the default | wrote that file, `.sky` untouched |
| Type a bare `BareName` | saved `BareName.view` (filter's extension, not `DefaultExt`) |
| Type the document's full path `...spikein.sky` | overwrite prompt, then **the document was overwritten with layout XML** |
| Import a layout naming an unknown window | warning naming the file and the window |

So the filter stops the dialog *listing or suggesting* a document, which closes
the accidental path the developer raised. It does **not** stop a fully typed
document name - that is accepted as typed, and Skyline writes the layout over it.
That is the accepted trade-off, and the doc comment on `FILTER_VIEW` says so
rather than claiming a guarantee it does not deliver.

**The doubled extension IS reachable from a test after all.** `RunNativeDlg` /
`RunLongNativeDlg` in `AbstractFunctionalTest` drive a real native file dialog
(added with the connector work in #4313, so almost no test uses them yet). The
test now calls `ShowExportLayoutDlg` / `ShowImportLayoutDlg` - the real menu
handlers - instead of the `ExportLayout` / `ImportLayout` methods underneath, and
`TestDefaultExportFileName` reads the dialog's file-name box and asserts it holds
`Doc.sky.view`. Verified to have teeth: restoring the ".sky.view" filter makes it
fail with `Expected:<DefaultName.sky.view>. Actual:<DefaultName.sky.view.sky.view>`,
the developer's screenshot reproduced automatically.

Two things learned about driving these dialogs:
- The layout warning is raised by `ShowImportLayoutDlg` **after** the file dialog
  closes but **before** the call returns, so it holds the UI thread. `RunNativeDlg`
  waits for that call to return and deadlocks; the import has to use
  `RunLongNativeDlg` and dismiss the `MessageDlg` from the test thread.
- The export deletes its target first, or a second local run hits the dialog's own
  overwrite prompt.

### Adding a main-menu item requires regenerating the help HTML

`HelpDocumentationContentTest.TestKeyboardShortcutsHelpDocumentation` asserts that
`Documentation/Help/{en,ja,zh-CHS}/KeyboardShortcuts.html` matches the HTML
generated from the live menu strip, so **any new item under `menuMain` fails it
until the file is regenerated**. This is a build gate, not an optional docs
chore - it was missed for several rounds because the regression sweeps did not
include that test.

To regenerate: set `IsRecordMode => true` in `HelpDocumentationContentTest`, run
the test (it rewrites all three languages, then deliberately fails on
`Assert.IsFalse(IsRecordMode, "Set IsRecordMode to false before commit")`), set it
back to false, and re-run to confirm green. The ja/zh rows show the English
"Window Layout" because the localized resx are not translated yet, which is
correct - the generated file reflects what the menu actually shows.

No other documentation applies. There is no per-menu-item reference page; the
tutorials document workflows, and none of them arrange windows through these
menu items. Phase 2 will reference Import Window Layout from the
tutorial-testing README when it uses it.

## Phase 2 - MCP screenshot-layout reproduction (follow-up, not this branch)

Retained from the original TODO. Re-scoped now that #4313 has merged and Phase 1
provides a menu path.

### How the existing pieces work

- **View files:** `pwiz_tools/Skyline/TestTutorial/{Tutorial}Views.data/pNN.view`
  - XML `DockPanel` snapshots (full layout: dock portions, per-pane
  `PersistString`, floating/hidden). ~11 tutorials ship a `*Views.data` folder.
- **Load path:** `TestFunctional.RestoreViewOnScreen(int pageNum)` ->
  `p{N:0#}.view` -> `SkylineWindow.LoadLayout(stream)`. The `int` is a **tutorial
  page number**, "originally associated with Word docs/PDFs... could be any
  numbers" (code comment) - **decoupled from the screenshot number.**
- **Screenshot naming:** a shared `ScreenshotCounter` -> `s-NN.png` via
  `_shotManager.ScreenshotDestFile(counter)`, advanced by every screenshot method
  (`PauseForScreenShot`, `PauseForScreenShot<T>`, `PauseForGraphScreenShot`, and
  the connector path `SaveMcpConnectorScreenShot`).
- **Window sizing (already exists):** `SetSkylineWindowSize(w,h)` (sets
  `SkylineWindow.Bounds`, centers it), `MaximizeSkylineWindow()`; cover shots
  assert 1200x800 @ 100% DPI.

**pNN->sNN is not a bijection.** A view load feeds the *first* screenshot after it
and is reused by later screenshots until the next load (e.g. `p09` -> the
regression shot, then the 0.95-threshold and zoomed-out shots reuse it; `p13` ->
one shot, then two reuse it). Some sections take screenshots with no preceding
load; cover-shot mode (`IsCoverShotMode`) loads `cover.view` and returns early.
Because `.view` files are **full** snapshots, the runner rule is simply: **for
`s-NN`, load the nearest preceding `s-<=NN.view`** - always the correct full
layout, no per-shot duplication needed.

### A. Derive the mapping + rename (independent of Phase 1, lands on master)
1. Instrument the shared `ScreenshotCounter` increment and `RestoreViewOnScreen`
   to emit, per tutorial, `(pageNum -> s-NN of the first screenshot after the
   load)`. Run all tutorial tests in record mode; collect the tables. The
   diagnostic is authoritative - it resolves cover-mode early-return, reused-view
   runs, and any counter-vs-tutorial-HTML drift at optional/skipped sections
   (e.g. MethodRefine s-03).
2. Bulk-rename `pNN.view`->`s-NN.view` in every `*Views.data/` (Git-light: content
   unchanged). Update `RestoreViewOnScreen` call-site args (`pNN`->`s-NN`) and the
   format string `p{0:0#}`->`s-{0:0#}` (keep `cover.view` as-is). Confirm the
   tutorial tests still pass (identical layout content, renamed key).
   - Verify the mapping is **language-independent** (layout, not text; the counter
     order should match across en/ja/zh) so one rename serves all languages.

### B. Remaining MCP verb
3. `skyline_set_window_bounds` (size and/or position; option to center /
   maximize-without-maximized-state) - wraps `SkylineWindow.Bounds` /
   `SetSkylineWindowSize`. Dual purpose: screenshot fidelity **and** positioning
   Skyline so nothing overlaps the capture (fixes the cyan-overlap failure).
   - `skyline_load_view_layout` is **dropped**: Phase 1's Import Layout menu item
     is drivable via the merged `skyline_click_main_menu_item` + native file
     dialog automation.

### C. Delivery + integration
4. Fetch `s-NN.view` from the pwiz GitHub repo pinned to the running version
   (mirror `skyline_get_tutorial`), so the agent has a local file to point the
   Import Layout dialog at.
5. Update the tutorial-testing README section 4: at a screenshot checkpoint, set
   window bounds, import the nearest-preceding `s-NN.view` if one exists, then
   capture; note this resolves MethodRefine Finding #1. Re-run MethodRefine s-21
   to confirm a pixel-faithful composite.

### Open questions
- Decide whether reused-view screenshots stay file-less (nearest-preceding rule,
  recommended) or get duplicate `s-NN.view` copies for self-containment.

## Key Files

- `pwiz_tools/Skyline/SkylineFiles.cs` - `GetViewFile`, `SaveLayout`, menu handlers
- `pwiz_tools/Skyline/SkylineGraphs.cs` - `LoadLayout`, `LoadLayoutLocked`, `DeserializeForm`
- `pwiz_tools/Skyline/Skyline.Designer.cs`, `Skyline.resx` - File > Import/Export menus
- `pwiz_tools/Skyline/TestUtil/TestFunctional.cs` - `RestoreViewOnScreen`, `ScreenshotCounter` (Phase 2)
- `pwiz_tools/Skyline/TestTutorial/*Views.data/` (Phase 2)

## Progress Log

### 2026-08-03 - Session 1
- Re-read the original backlog TODO with the developer; its MCP framing buried the
  simpler product gap. Reframed around File > Import/Export > Layout and moved the
  MCP work to Phase 2.
- Confirmed PR #4313 merged (`a840067e8`), which makes the original TODO's whole
  branch-sequencing table obsolete and drops the need for a dedicated
  `skyline_load_view_layout` verb.
- Created branch `Skyline/work/20260803_layout_export_import`; starting Phase 1.
- Implemented Phase 1. Notable decisions:
  - `ImportLayout` reuses the existing
    `SkylineWindow_UpdateGraphUI_Failure_attempting_to_load_the_window_layout_file__0__`
    resource rather than adding a second wording for the same failure.
  - `DeserializeForm` became a try/catch wrapper around a renamed `RestoreDockableForm`,
    so one unrestorable window cannot abort the whole `LoadFromXml`.
  - `CreateListForm` now returns null for a list the document does not define. `ShowList`
    got a null guard to match.
  - Localized `.resx` files deliberately untouched - `Skyline.ja.resx` /
    `Skyline.zh-CHS.resx` are updated in bulk translation passes (last: PR #4227).
- All tests green (see checklist).

### 2026-08-03 - Session 1, follow-up review
Three changes from the developer's review of the first pass:
1. **Report windows that could not be restored**, with the same message when
   opening a document and when importing - see the section above. The old
   behavior (silently drop the window) hid real problems.
2. **Menu text is now "Window Layout"**, not "Layout" - too vague beside
   Annotations / Document / Report. Code names stay `Layout`.
3. **Save filter is `*.sky.view` only, no all-files entry.** Rationale recorded
   above; the functional test asserts `FILTER_SKY_VIEW` contains no `*.*` so the
   guard cannot be silently undone.

### 2026-08-03 - Session 1, second review round
Split the warning into two strictness levels (table above), on the developer's
point that opening a document should only complain about a file that is wrong,
while Import Layout should complain about anything it could not honor.

`TestOpenDocumentStrictness` pins the difference with one file: a layout naming a
list window, given to a document without that list. Opening is silent; importing
the very same file warns. The test was verified to have teeth - flipping
`severeOnly` to false in `UpdateGraphUI` makes it fail (unclosed `MessageDlg`
timeout), which is the regression it exists to catch.

Regression risk taken on: documents that open with a `.sky.view` can now show a
warning where they were previously silent - but only for an exception or an
unrecognized window, which narrows it a lot compared to the first pass. Verified
against ListClustering, SummaryGraphVisibility, TreeRestoration, FilesTreeForm,
DocumentFileLocking, GroupComparison, FoldChangeGrid, MethodRefinement /
ExistingQuantitativeExperiments / GroupedStudies tutorials, and CodeInspection.
**A full nightly is still the gate** - any test data whose `.sky.view` names a
window this Skyline does not recognize will now pop a dialog.

## References

- Original backlog file: `TODO-mcp_tutorial_view_layout.md` (renamed to this file)
- Need discovered: `ai/todos/active/TODO-20260609_native_file_dialog_automation-tests/TEST-MethodRefine.md` (Finding #1)
- Connector dependency (merged): `TODO-20260609_native_file_dialog_automation.md`
