# TODO-20260813_export_import_layout.md - File > Export/Import > Window Layout

## Branch Information
- **Branch**: `Skyline/work/20260813_export_import_layout`
- **Checkout**: `I:\git_i\sky_exportlayout`
- **Module**: `skyline`
- **Base**: `master`
- **Created**: 2026-08-13
- **Status**: In Progress
- **GitHub Issue**: (none)
- **PR**: (not opened)

## Objective

Two menu items, and nothing more:

- **File > Export > Window Layout...** - write the current dock layout to a `.view` file.
- **File > Import > Window Layout...** - read one back.

## Why this exists

Skyline has always had `.sky.view` layout files, but no user-facing way to produce or
consume one:

- `SkylineWindow.SaveLayout(fileName)` was **private** and called only from document save
  and from Share (which copies the layout into the `.sky.zip`).
- Loading only happened **implicitly**, in `UpdateGraphUI`, when a document is opened and a
  sibling `<doc>.sky.view` exists.

So the only way to capture a hand-arranged dock layout was to save a document and then go
find/rename the `.sky.view` artifact next to it. An ordinary user cannot move a favorite
layout between documents at all.

## Deliberately restarted small

An earlier attempt at this (`TODO-20260803_layout_export_import.md`, branch
`Skyline/work/20260803_layout_export_import`) grew a layout-preview parser, a typed
problem-classification model with two strictness levels, per-pane failure isolation in
`DeserializeForm`, and a rebuilt `DigitalRune.Windows.Docking.dll` in the `developers`
repo. That is far more machinery than two menu items warrant, so this branch starts over
from master and keeps only what the menu items need. **Nothing from that branch is
reused.**

What was dropped, and why it is affordable:

| Dropped | Why |
|---------|-----|
| `LayoutPreview` / `LayoutWindowId` / `LayoutProblems` | Predicting which windows a layout names, and classifying what could not be restored, is a second copy of the restore decision tree. `DeserializeForm` already returns null for a pane it cannot build, and those panes are simply skipped, exactly as they always were when opening a document beside its `.sky.view`. |
| Two strictness levels for open-document vs. import | Only exists to feed the reporting above. |
| `DockPanelLayout.Load` / `Validate` in DigitalRune | A cross-repo binary rebuild to validate index cross-references. The cheap root-element check below covers the one case that actually matters (pointing the dialog at a `.sky` document). |
| Per-pane try/catch in `DeserializeForm` | Existing behavior, unchanged by this feature. |

## What is here

### Menu items

Both are last in their File submenu, after Annotations, with mnemonic `W` (unused in both
dropdowns). "Window Layout" rather than "Layout", which is too vague next to
Annotations/Document/Report; code names stay `Layout`. Neither needs
`fileMenu_DropDownOpening` enable/disable logic - a layout can be exported from an empty
document.

### Export

`SaveFileDialog` -> `SaveLayoutToFile(viewFilePath)`, which is the existing private
`SaveLayout` with the `GetViewFile` name-building factored out, so an exported file is
byte-identical to the one document save produces (same `FileSaver` + `dockPanel.SaveAsXml`
+ UTF-8-without-BOM). Default file name is `<document>.sky.view`.

### Import

`OpenFileDialog` -> `LoadLayout(stream)`, wrapped in the same failure message the implicit
load path already uses. Same `FILTER_SKY_VIEW` as Export, so the file list never shows a
bare `.view`. (The tutorial tests' single-extension `pNN.view` assets are loaded
programmatically by `RestoreViewOnScreen`, never through this dialog, so nothing needs the
wider filter.)

### The two pieces of "sanity checking"

**1. `FILTER_SKY_VIEW` is the two-part `.sky.view`, for both dialogs, with no all-files
entry.**

Only `.sky.view` is offered or listed: a layout belongs beside the document it came from,
and the dialogs should not encourage any other name. No all-files entry because Windows
suggests matching existing file names as the user types, so an unrestricted filter makes it
easy to save a layout over the `.sky` document. That stops the dialog *listing or
suggesting* a document; it does not stop a fully typed document name.

**The rule the shell actually applies**, established by measurement after several wrong
guesses: it appends the selected file type's extension to a name unless the name's **last**
extension matches the filter's. `Doc.sky.view` has last extension `.view`, which is not
`.sky.view`, so it appends.

| Tried | Result |
|-------|--------|
| Filter `*.sky.view`, `dlg.FileName = "Doc.sky.view"` | Offers `Doc.sky.view.sky.view` |
| ...plus `SupportMultiDottedExtensions = true` and `DefaultExt = ".sky.view"` | **Unchanged.** Neither property prevents it |
| Filter `*.sky.view`, `dlg.FileName = "Doc"` (base name only) | Offers `Doc.sky.view` - correct, and this is what ships |
| Filter `*.sky.view`, user TYPES `Name.sky.view` | Saves `Name.sky.view.sky.view` - **accepted**, see below |
| Filter `*.view`, `dlg.FileName = "Doc.sky.view"` | Offers `Doc.sky.view`, but a bare typed name saves `Name.view` |

So `ShowExportLayoutDlg` hands the dialog `Path.GetFileNameWithoutExtension(DocumentFilePath)`
and lets the filter supply the extension. `DefaultExt` and `SupportMultiDottedExtensions`
are **dead config** here and are not set.

**Known and accepted:** a user who types a name that already ends in `.sky.view` gets
`Name.sky.view.sky.view`. No name ending in a two-part extension can satisfy the shell's
comparison, so the only fixes are a narrower filter (rejected - it would list bare `.view`
files) or post-processing `dlg.FileName` to collapse the duplicate (rejected - the
equivalent `EnsureViewFileName` was removed from the earlier branch at the developer's
direction). `LayoutExportImportTest` therefore exports by typing a **base name**, and the
`ExportLayout` helper's doc comment says why, so the next reader does not "fix" the test by
typing a full path.

This also corrects an assumption worth not repeating: Share Document is **not** an example
of a working `*.sky.zip` filter. Its filter is `SrmDocumentSharing.EXT` - the single
`".zip"` - and only its `DefaultExt` and the name it offers carry the two-part
`".sky.zip"`. `SupportMultiDottedExtensions` is not what makes it work.

No all-files entry is a safety choice, not cosmetics: Windows suggests matching existing
file names as the user types, so an unrestricted filter makes it easy to save a layout over
the `.sky` document. It stops the dialog *listing or suggesting* a document; it does not
stop a fully typed document name, and the doc comment on `FILTER_VIEW` says so rather than
claiming a guarantee it does not deliver.

**2. `ImportLayout` puts the current layout back when a load fails.**

`LoadLayoutLocked` is a full replace: it destroys every dockable form and only then rebuilds
from the XML. A file that is not a usable layout therefore left the user with **no windows
at all** - and, offscreen, wedged the test outright, because `WaitForOpenForm` waited
forever for a window nothing was going to create.

`ImportLayout` now captures the current layout to a `MemoryStream` first
(`SaveLayoutToStream`, a sibling of `SaveLayoutToFile`, using
`dockPanel.SaveAsXml(stream, UTF8 no BOM, embedded: true)`), and reloads it in the catch
before reporting. `RestoreLayout` swallows its own failure: if the layout that was already
showing will not reload either, there is nothing better to try and the failure that got us
there is the one worth reporting.

**Import only, deliberately.** A first pass put this in `LoadLayout` so the implicit
load-on-open path would get it too. That is not worth having: the arrangement being replaced
on open belongs to the document being *closed*, so it is no better a fallback for the new
document than the default, and nothing is at risk there anyway - the user can just quit.
Keeping it in `ImportLayout` also leaves `LoadLayout` exactly as it was.

**An earlier `IsLayoutFile` pre-flight check was removed**, at the developer's direction and
for a good reason: a sanity check that rejects the file up front also hides whatever else
the loader cannot cope with, and those are the bugs worth finding. With the restore in
place the check earns nothing - a bad file costs a message and nothing else.

#### How that was established

| Condition | Result |
|-----------|--------|
| No guard, no restore, offscreen | **Hangs.** 3 runs killed at 5-10 min |
| No guard, no restore, offscreen, `MoveLayoutOffScreen` bypassed | Still hangs - that method is **not** the cause, despite being the only offscreen-conditional code on the path |
| No guard, no restore, on-screen (`-ShowUI`) | Failed at the message assert in 4.5 s, before reaching the window check - so the on-screen/offscreen split was about which assert fired first, not a real behavioral difference |
| No guard, **with restore**, offscreen | **Passes**, 11 s. `TestImportNotALayoutFile` reaches `WaitForOpenForm<DocumentGridForm>()` and finds the window back |

Note for whoever runs this: `Program.SkylineOffscreen` is set only in
`TestRunnerLib/RunTests.cs`, from TestRunner's `offscreen` argument. Running the test from
Test Explorer or ReSharper never goes through `RunTests`, so it runs **on-screen** and will
not reproduce anything offscreen-specific.

## Grid forms remember the report they were showing

Folded into this branch on the developer's call: a restored layout recreates the Document
Grid / Audit Log / Results Grid / list window, but each came back on whatever report a
*global* setting last held (`Settings.Default.DocumentGridView`, `AuditLogView`,
`ResultsGridActiveViews`), not the one the layout captured. So the window reappears showing
different data than it had. `FoldChangeGrid` already did this correctly; these four now
follow it. (The report is `ViewName` in code, reached through `GetViewName()`.)

**It all lives in `DataboundGridForm`.** A first pass gave each subclass its own
`GetPersistentString` override plus a static parser with a hardcoded part index - five copies
of one idea. There was no reason for it: the only thing that actually differs between these
forms is that `ListGridForm` writes an extra part, and the report has to land after it. That
is one virtual hook, not five overrides.

- `GetPersistentString` is **sealed** on the base: window type, then
  `GetPersistentStringParts()`, then the report. Sealing is what guarantees the report is
  always last and always at the index the parser reads.
- `GetPersistentStringParts()` is the hook, empty by default. `ListGridForm` is the only
  override, returning the list name - so it is still `type|listName|viewName` and
  `GetListName` still reads part 1.
- `RestoreViewFromPersistentString` reads the report from `1 + GetPersistentStringParts().Parts.Count`,
  so no subclass needs to know an index. `SkylineGraphs.RestoreView` just hands it the string.
- `ViewToRestore` is applied once in `OnShown` and cleared, so the user is free to change
  report afterwards.

Every `DataboundGridForm` therefore gets this for free: `DocumentGridForm`, `AuditLogForm`,
`LiveResultsGrid`, `ListGridForm`, `CandidatePeakForm` **and** `SpectrumGridForm`.

**One caveat on `SpectrumGridForm`:** it now *writes* its report, but it is still never
restored - `DeserializeForm` has no branch for it at all, and only
`ViewMenu.ShowSpectrumGridForm` ever creates one. So the report it writes is currently read
by nobody. Giving it a restore branch is a separate change, and a behavioral one: that window
would start reappearing from layouts where today it silently does not.

`FoldChangeGrid` is **not** a `DataboundGridForm` (it derives from `FoldChangeForm`), so it
keeps its own copy of this and, unlike these, does not suppress the default report.

### The default report is deliberately NOT written

`AppendViewName` leaves the report off when it is the default - the first of
`viewContext.GetViewSpecList(ViewGroup.BUILT_IN.Id).ViewSpecs`. A grid on its default report
therefore still persists as the bare window type, which is what Skyline versions **before**
this change require: they match the window type with an exact comparison, so any appended
part makes them drop the window silently. Leaving the default off keeps the common case of a
".sky.view" readable by them.

### The hazard: three of these were matched by exact equality

`DeserializeForm` tested `Equals(persistentString, typeof(X).ToString())` for
`LiveResultsGrid`/`ResultsGridForm`, `DocumentGridForm` and `AuditLogForm`. Appending
anything makes that comparison fail, and the window is then **silently not restored at all**
- no error, it just stops appearing. All three became `StartsWith`, which also keeps layouts
saved before this change working: they are the bare type name, and
`ParsePersistedViewName` returns null when the part is not there.

`CandidatePeakForm` was in the same shape and got the same treatment. `SpectrumGridForm` has
no branch to fix.

### Coverage

`LayoutExportImportTest.TestGridReportRestored` covers both halves:

- **Restore.** Document Grid on Precursors, export, switch to Proteins, import, assert it is
  back on Precursors. Teeth verified: dropping the `DocumentGridForm.GetPersistentString`
  override fails it with `Expected:<.Precursors>. Actual:<.Proteins>` - the reported bug.
- **Default suppressed.** The exported file must contain `PersistString="<type>|` while on
  Precursors, and `PersistString="<type>"` while on Proteins (the default). Teeth verified:
  removing the default check from `AppendViewName` fails the second assertion.

**Only the Document Grid path is covered.** Since the logic now lives once in the base class,
the others run the very same code; what is untested per-form is only `ListGridForm`'s
`GetPersistentStringParts` override, which is the single place the report's index can move.
That is the test worth adding if anyone adds one.

#### Still open

Deferred, and less urgent now that a failure is recoverable: **delay destroying the current
windows until the first callback that creates a new one.** That would avoid the destroy /
rebuild churn entirely rather than undoing it, but it is a real change to
`LoadLayoutLocked`'s structure and was explicitly left for later.

The exposure is new to Import, which is why this did not need solving before: the implicit
load path in `UpdateGraphUI` only ever sees a `.sky.view` Skyline itself wrote beside the
document. Import is the first time a user can aim the loader at an arbitrary file.

#### A wrong turn worth not repeating

Two intermediate conclusions in this investigation were stated too confidently and then
refuted:

1. *"A `catch` is not enough, the guard is required."* Drawn from the offscreen hang before
   the restore existed. True of the code as it stood, but it framed a workaround as a
   requirement instead of asking why the failure was unrecoverable.
2. *"`MoveLayoutOffScreen` causes the hang."* Inferred because it was the only
   offscreen-conditional code on the path. Bypassing it changed nothing. The actual cause -
   every window destroyed and none recreated, so the test's `WaitForOpenForm` never
   returned - came from the developer, not from the measurement.

### UNEXPLAINED: one GC-LEAK on the first run of the new test, never reproduced

The very first run of `LayoutExportImportTest` failed with "Objects not garbage collected
after test: SkylineWindow, SrmDocument". It has not been seen since.

**A first pass wrongly blamed - and "fixed" - the wrong thing.** The theory was that
`ShowImportLayoutDlg` showed its `MessageDlg` from *inside* the
`using (var dlg = new OpenFileDialog())` block, so a modal ran with an undisposed
`FileDialog` on the stack; both `Show...LayoutDlg` methods were restructured to read
`dlg.FileName` into a local, close the `using`, and only then do the work. That looked
confirmed because the run after the change was green.

**The negative test refutes it.** Restoring the exact "leaking" form and running it 10
times - 8 in a loop, plus one from a wiped `TestResults` folder to rule out a first-run
effect - produced 10 clean runs. The restructure fixed nothing, so it was reverted; the
click handlers now call into the work from inside the `using`, which is what
`importAnnotationsMenuItem_Click` and the rest of the File menu already do.

So the failure is **unexplained**, and the evidence for it is a single observation. What
is known:

- It is not GC timing. `GarbageCollectionTracker.CheckAfterTest` already retries 3 times
  with a 500 ms sleep and a full `FlushMemory` between tries, so a reported leak survived
  four collection cycles over ~1.5 s.
- The subsets are clean too: export-only and export-plus-successful-import both passed
  during the bisect, and every configuration since has passed.
- Nothing was learned about *what* was holding `SkylineWindow`. Per the leak-debugging
  skill, that answer comes from dotMemory Key Retention Paths on a run that actually
  leaks - and there is no reproduction to profile.

**Watch for it in nightly.** If it recurs, run under `-MemoryProfile
-MemoryProfileWaitRuns 0` and read the retention path rather than theorizing again.

## Task Checklist

### Completed
- [x] `EXT_VIEW` / `EXT_SKY_VIEW` / `FILTER_SKY_VIEW` next to `GetViewFile` in `SkylineFiles.cs`
- [x] `SaveLayout` -> `SaveLayoutToFile(viewFilePath)` refactor
- [x] `ShowExportLayoutDlg` / `ExportLayout`, `ShowImportLayoutDlg` / `ImportLayout`,
      and the two menu click handlers
- [x] `ImportLayout` captures the current layout and restores it if the load fails
      (`SaveLayoutToStream` / `RestoreLayout` in `SkylineFiles.cs`); `LoadLayout` unchanged
- [x] `importLayoutMenuItem` / `exportLayoutMenuItem` in `Skyline.Designer.cs` + `Skyline.resx`
- [x] Three resource strings in `SkylineResources.resx` + `.designer.cs` (filter description,
      save-failure message, not-a-layout message); the load-failure message is the existing
      `SkylineWindow_UpdateGraphUI_Failure_attempting_to_load_the_window_layout_file__0__`
- [x] Investigated the one-off GC-LEAK; negative test refuted the first explanation, no
      reproduction found (above)
- [x] `LayoutExportImportTest` - default export file name, dock-state round trip through the
      real menu handlers and their native file dialogs (the export types a base name, which
      also pins that the filter supplies ".sky.view"), not-a-layout file reported and the
      layout left alone
- [x] Regenerated `Documentation/Help/{en,ja,zh-CHS}/KeyboardShortcuts.html` (record mode);
      any new `menuMain` item fails `TestKeyboardShortcutsHelpDocumentation` until this is done
- [x] Build clean; CodeInspection, HelpDocumentationContentTest (all 3),
      TestLayoutExportImport, TestTreeRestoration, TestListClustering, TestFilesTreeForm,
      TestNativeFileDialog, TestSummaryGraphVisibility all pass

### Remaining
- [ ] Developer review
- [ ] Push branch and open PR
- [ ] Localized menu text for `.ja.resx` / `.zh-CHS.resx` - bulk translation pass, not this
      PR, matching how every other menu item has landed. The ja/zh KeyboardShortcuts rows
      correctly show the English "Window Layout" until then.

## Key Files

- `pwiz_tools/Skyline/SkylineFiles.cs` - `EXT_SKY_VIEW`, `FILTER_SKY_VIEW`, `GetViewFile`,
  `SaveLayout` / `SaveLayoutToFile` / `SaveLayoutToStream` / `RestoreLayout`, the four public
  methods and two click handlers
- `pwiz_tools/Skyline/SkylineGraphs.cs` - `LoadLayout` (unchanged; `ImportLayout` calls it)
- `pwiz_tools/Skyline/Skyline.Designer.cs`, `Skyline.resx` - File > Import/Export menus
- `pwiz_tools/Skyline/SkylineResources.resx` / `.designer.cs`
- `pwiz_tools/Skyline/TestFunctional/LayoutExportImportTest.cs`
- `pwiz_tools/Skyline/Documentation/Help/{en,ja,zh-CHS}/KeyboardShortcuts.html`

## Progress Log

### 2026-08-13 - Session 1
- Restarted from master on a fresh branch at the developer's direction; the 2026-08-03
  attempt had grown well past what two menu items justify (see the table above).
- Implemented both menu items, the filter, and the root-element check.
- Hit a GC-LEAK on the first test run, blamed the modal-inside-undisposed-FileDialog
  pattern, and changed the product code. The negative test then showed the original form
  passes 10/10, so the change was reverted and the failure stands unexplained.
- Regenerated the keyboard-shortcut help for all three languages.
- Settled the two-part-extension question by measurement (table above) after the developer
  pushed back on the first answer: the filter is `*.sky.view` for both dialogs, and the
  Export dialog is handed a base name.
- All targeted tests green. **A full nightly is still the gate.**

## References

- Superseded attempt: `ai/todos/backlog/TODO-20260803_layout_export_import.md` (retained
  for its Phase 2, the MCP screenshot-layout reproduction work, which this branch does not
  touch)
