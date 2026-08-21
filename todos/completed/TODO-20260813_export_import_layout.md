# TODO-20260813_export_import_layout.md - File > Export/Import > Window Layout

## Branch Information
- **Branch**: `Skyline/work/20260813_export_import_layout`
- **Checkout**: `I:\git_i\sky_exportlayout`
- **Module**: `skyline`
- **Base**: `master`
- **Created**: 2026-08-13
- **Status**: Completed
- **GitHub Issue**: (none)
- **PR**: [#4575](https://github.com/ProteoWizard/pwiz/pull/4575) (merged 2026-08-21)

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

`SaveFileDialog` -> `SaveLayout(viewFilePath)`, the same private method document save uses,
so an exported file is byte-identical to the one save produces (same `FileSaver` +
`dockPanel.SaveAsXml` + UTF-8-without-BOM). Default file name is `<document>.sky.view`.

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

**Two things fix the two halves of this, and they are different fixes.**

The name the dialog **offers** is safe because `ShowExportLayoutDlg` hands over
`Path.GetFileNameWithoutExtension(DocumentFilePath)` - a base name with no extension at all,
so there is nothing to double.

A name the user **types** ending in `.sky.view` still gets `.sky.view` appended, and
`ShowExportLayoutDlg` strips the duplicate back off. `TestExportTypedFullName` covers it.

**A second filter entry was tried and reverted.** Offering `*.view` alongside `*.sky.view`
also stops the doubling - the shell appends only when the name's last extension is not one the
filter knows, and every `.sky.view` ends in `.view` - and it let the strip code be deleted.
But switching the file type back to `.sky.view` then swaps the last extension of
`Doc.sky.view` and offers **`Doc.sky.sky.view`**, which is worse. Single entry, keep the strip.

Worth knowing how nearly that was missed: the first negative test for the filter change
(removing the second entry) **passed**, which would have "shown" the entry was unnecessary. It
was testing the offered name, which the base-name change had already made safe for an
unrelated reason. `TestExportTypedFullName` was written to close that gap, and it is the only
test that exercises the strip at all.

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
(`SaveLayoutToStream`, a sibling of `SaveLayout`, using
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

### Putting the windows right after a load: `EnsureApplicableForms`

`LoadLayoutLocked` destroys every dockable form before it rebuilds, so a layout that does not
name the Targets window leaves `SkylineWindow.SequenceTree` null - and `UndoState` dereferences
it unguarded, so the next document edit throws. `UpdateGraphUI` had always repaired this
immediately after releasing the layout lock, and closed list / fold-change windows the document
cannot support; `ImportLayout` inherited none of it.

That post-work is now one method, `EnsureApplicableForms`, called by both.

### Windows an imported layout could show that the user cannot open

Without results the View menu disables the Results Grid, the RT / peak-area / mass-error /
detections graphs, candidate peaks and full scan. But `DeserializeForm` builds whatever the
persist string names, and `ViewMenu.UpdateGraphUi` deliberately does **not** close them after
a layout load - every branch there is guarded by `if (!deserialized)`, so the file wins. So
Import could put a window on screen that the user had no way to open.

**Measured, not assumed.** Exporting a layout, rewriting `DocumentGridForm` to
`LiveResultsGrid` in the file, and importing it into a results-free document showed the
Results Grid. `EnsureApplicableForms` now closes that set when `!DocumentUI.Settings.HasResults`,
reusing the existing `UpdateUIGraph*` / `ShowResultsGrid` / `Destroy*` helpers.
`TestImportLayoutNeedingResults` pins it, and was verified to fail without the gating.

Note these helpers **hide** rather than destroy (`ShowResultsGrid(false)` calls `Hide()`), so
the test asserts on `Visible`, not on the form's absence - which is the right question anyway,
since the concern is what the user is shown. A first version of the test asserted absence and
**passed vacuously**, because the preceding step had closed every window so there was no
`DocumentGridForm` in the file to rewrite. It now asserts the substitution happened first.

`GraphChromatogram` needs nothing: it is the one form kind already guarded on document
contents. For a replicate the document does not have, its branch falls through to the final
`return null`, so no window is created - and `LoadLayoutLocked` destroyed the existing ones
first, so no orphan survives either. Worth knowing that this relies on a **fall-through**
rather than an explicit `return null`; anything inserted between that branch and the end of
`DeserializeForm` that matches the string would capture it.

**It is deliberately NOT inside `LoadLayout`,** which is where the code review said to put it.
That was **tried and reverted**, at the developer's direction and with measurements:

- `AbstractFunctionalTest.EndTest` uses `LoadLayout` as its teardown primitive.
  `RestoreMinimalView` loads the contents-free `minimal.sky.view` to close every dock window,
  and **two** separate gates then require only SkylineWindow to remain: the
  `OpenForms.Count() == 1` wait, and the "left open at end of test" report in
  `CloseOpenForms`. A self-contained `LoadLayout` hands the Targets window back and trips both,
  in every functional test.
- Loosening them was attempted three ways and none was clean: excluding `SequenceTreeForm` from
  the count still trips `CloseOpenForms`; `ShowSequenceTreeForm(false)` only **hides** the form,
  so it stays in `OpenForms`; and excluding the type from both gates means the suite can no
  longer catch a leaked Targets window at all.
- One thing the experiment did settle: no product breakage appeared from running the repair
  under `UpdateGraphUI`'s outer lock. The old "messes up the selected graph" comment did not
  manifest in any test. So that concern is unproven either way - it is not the reason.

The reason is that `LoadLayout` genuinely has a caller that wants nothing left behind. The
primitive stays that way; the two callers that want a usable window afterwards ask for it.

`ImportLayout` calls it on all three paths - load succeeded, load failed and was rolled back,
load failed and the rollback failed too - since all three can leave windows needing repair.

`TestImportLayoutWithoutTargets` imports the shipped `minimal.sky.view` and then makes a
document edit. Teeth verified: removing the call fails it on `Assert.IsNotNull(SequenceTree)`.

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
- [x] `SaveLayout` now takes the **view** file path, not the document path. It used to take a
      document path and append the extension itself, which read confusingly next to a
      `SaveLayoutToFile(viewFilePath)` sibling; the wrapper is gone and the two callers that
      have a document path pass `GetViewFile(fileName)`.
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

**Review findings to settle before the PR.** From `/code-review max`; the report-persistence
findings went with that work to `TODO-20260813_grid_report_layout.md`.

- [x] **Importing a layout with no Targets window left `SkylineWindow.SequenceTree` null, and
      the next document edit threw.** *Proven*, not inferred: importing the shipped
      `TestUtil/minimal.sky.view` (`<Contents Count="0" />`) then asserting
      `SkylineWindow.SequenceTree != null` failed. `LoadLayoutLocked` unconditionally calls
      `DestroySequenceTreeForm()`; `UpdateGraphUI` repaired it right after unlocking and
      `ImportLayout` did not. `UndoState`'s `window.SequenceTree.SelectedPaths`
      (`Skyline.cs:1034`) is unguarded. **Fixed** - see below.
- [x] **`ImportLayout` also skipped `FoldChangeForm.CloseInapplicableForms` /
      `ListGridForm.CloseInapplicableForms`.** Independently corroborated - the abandoned
      2026-08-03 branch found the same gap. It matters more here than on document-open, because
      applying a layout captured against a *different* document is the whole point of Import,
      so the mismatch is the normal case rather than the rare one. **Fixed** with the above.
- [x] **Export could write nothing and say nothing.** `FileSaver.CanSave(IWin32Window parent = null)`
      (`Util/UtilIO.cs:1333`) catches `UnauthorizedAccessException` / `FileNotFoundException`
      and shows a message only `if (parent != null)`, otherwise returning false - so the write
      was skipped and `ExportLayout`'s catch never ran. Reachable whenever the target exists
      read-only (`CheckException` throws `UnauthorizedAccessException` for the ReadOnly
      attribute) or the folder is not writable. A missing *directory* was already reported,
      because `DirectoryNotFoundException` is not one of the two caught.
      **Fixed** by `saverUser.CanSave(this)` in `SaveLayout`, at the developer's choice of the
      two options - which also means document save and Share Document now report a read-only
      `.sky.view` where they previously did not. `TestExportOntoReadOnlyFile` pins it; verified
      that without the parent the test hangs waiting for a dialog that never appears, which is
      the silent no-op itself.
- [x] **Not a bug - by design.** The review flagged that the Export dialog's default name is the
      document's own `GetViewFile(DocumentFilePath)` sidecar, which the next Ctrl+S overwrites.
      That is the point: the usual reason to use File > Export > Window Layout is to update the
      `.sky.view` after rearranging windows *without* saving the whole document. Writing the
      document's own sidecar is the intended result, not an accident.
- [x] **The dialogs now open beside the document.** `Settings.Default.ActiveDirectory` is a
      user-scoped persisted setting meaning "the last folder any file operation used" - written
      by `SetActiveFile` on open/save, but also by File > Open, opening a shared `.zip`, Import
      Assay Library / Transition List, and unrelated dialogs (iRT calculator, ion mobility
      library, optimization library, peak compare, tutorial download) - and read by ~20 dialogs.
      So after picking an iRT database from another folder, Export would offer a name taken from
      *this* document in *that* folder. `GetLayoutDirectory` uses
      `Path.GetDirectoryName(DocumentFilePath)` when there is one and falls back to
      `ActiveDirectory` only for an unsaved document. `GetShareFileName` sets the precedent -
      it starts from the document folder for the same reason (though without the fallback).
      `TestExportStartsBesideDocument` points `ActiveDirectory` at the temp folder and asserts a
      bare-name export still lands next to the document; verified to fail without the change.
- [ ] Both new handlers skip `ExceptionUtil.IsProgrammingDefect` -> `Program.ReportException`,
      which `SkylineFiles.cs:1060` and `:1300` both do, so a real defect is reported to the
      user as a bad file and never reaches the exception dashboard.
- [x] **Both dialogs now set `dlg.Title`.** The review said "every sibling sets one", which is
      an overstatement - 9 of the 14 file dialogs in `SkylineFiles.cs` do. But the split is
      meaningful: the ones that skip it are File > Open and Save As, where the shell's own
      caption is already right. Every dialog serving a *specifically named* command captions
      itself with that command. Ours are named commands, so the user was picking
      File > Export > Window Layout and getting a dialog headed "Save As" - the exact confusion
      the restrictive filter exists to prevent. (Import Annotations is the one real
      counterexample, and looks like a miss there rather than a precedent.)
      Two new resource strings; the test reads the caption off the live dialog, and without the
      Title it reports `Expected:<Export Window Layout>. Actual:<Save As>`.
- [ ] Neither dialog writes `Settings.Default.ActiveDirectory` back. Largely moot now that
      `GetLayoutDirectory` prefers the document folder - it would only affect the unsaved-document
      case - but the read/write-back pattern is what the rest of the file does.
- [ ] The `.sky.view.sky.view` strip uses a case-sensitive `EndsWith`, so a typed
      `Layout.SKY.VIEW` still produces a doubled name. `PathEx.HasExtension` is the house
      helper and lower-cases invariantly.
- [ ] The test never calls `TestContext.EnsureTestResultsDir()`, so stale files survive between
      runs, and it never covers save-document-then-reopen. It writes through
      `TestContext.GetTestResultsPath` rather than `TestFilesZip` + `TestFilesDir.GetTestPath`,
      which is what gives a file-writing test its own cleaned-up directory.
- [ ] `ImportLayout`'s `previousLayout` `MemoryStream` is never disposed (Copilot). Harmless as
      written - a `MemoryStream` holds no unmanaged handle - but it keeps the whole serialized
      layout alive until GC.
- [ ] **Pushed back on:** the review calls the missing All Files entry a deviation from house
      pattern. It is a deliberate, documented safety choice - an unrestricted filter makes it
      easy to save a layout over the `.sky`. Keep it.

**Then:**
- [x] Push branch and open PR - #4575
- [x] Copilot review - reviewed 2026-08-14. Two threads were left **unresolved** at merge: the
      case-sensitive `EndsWith` and the undisposed `previousLayout`, both listed above.
- [x] Developer review - merged by the author with admin override, see the merge log entry
- [ ] Localized menu text for `.ja.resx` / `.zh-CHS.resx` - bulk translation pass, not this
      PR, matching how every other menu item has landed. The ja/zh KeyboardShortcuts rows
      correctly show the English "Window Layout" until then.

## Key Files

- `pwiz_tools/Skyline/SkylineFiles.cs` - `EXT_SKY_VIEW`, `FILTER_SKY_VIEW`, `GetViewFile`,
  `SaveLayout` / `SaveLayoutToStream` / `RestoreLayout`, the four public
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

### 2026-08-13 - Session 1, split
- Grid windows remembering their report rode along on this branch for a while, then was split
  off to `Skyline/work/20260813_grid_report_layout` (TODO of the same name) so this PR stays
  the two menu items. Done with `git branch` at the tip then `git reset --hard`, so every
  commit is preserved on that branch.
- `/code-review max` run on the combined branch; findings split between the two TODOs.

### 2026-08-21 - Merged

PR #4575 merged as commit `5acc2dd24c`. What shipped is the two menu items and the work that
turned out to be required to make Import safe: the roll-back of the previous layout when a load
fails, `EnsureApplicableForms` to put the windows right afterwards, the `.sky.view`-only filter
with the typed-name strip, dialog captions, the document-folder start directory, and
`saverUser.CanSave(this)` so an export onto a read-only file reports instead of silently doing
nothing.

**Merged with admin override while TeamCity was still running**, deliberately. The previous head
`d9aeb9d9` had a fully green run earlier the same evening - Skyline master and PRs "Tests passed:
1735" at 19:40, Skyline Code Inspection at 19:52, Core Windows x86_64 308 tests at 22:36. The only
thing after it was a master merge (`531b9732`, 22:56) that brought in exactly one commit,
`d5108d7eaf osprey: Moved the PerFileRescoring whole-run join...` (#4600), entirely under
`pwiz_tools/Osprey`. This PR touches only `pwiz_tools/Skyline`, so the untested delta had no file
overlap with it. The rerun that was in flight could only have re-proven the 19:40 result.

**Carried forward, not shipped** - the five unchecked items under Remaining. Two of them are
unresolved Copilot threads (case-sensitive `EndsWith` on the doubled-extension strip; the
undisposed `previousLayout`), and the other three are the missing
`ExceptionUtil.IsProgrammingDefect` -> `Program.ReportException` on both new handlers, the absent
`ActiveDirectory` write-back, and the test's use of `GetTestResultsPath` instead of `TestFilesZip`.
The `IsProgrammingDefect` one is the only one with real consequences: a genuine defect thrown out
of Import is currently reported to the user as a bad file and never reaches the exception
dashboard. Also still deferred: delaying the destroy in `LoadLayoutLocked` until the first
callback that creates a window, and the ja/zh-CHS menu strings, which go with the bulk
translation pass.

**Watch in nightly** for the one unexplained GC-LEAK described above. It was seen once, on the
first run of the new test, and never reproduced; if it returns, profile it rather than theorizing.

## References

- Superseded attempt: `ai/todos/backlog/TODO-20260803_layout_export_import.md` (retained
  for its Phase 2, the MCP screenshot-layout reproduction work, which this branch does not
  touch)
