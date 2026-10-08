# TODO-20261008_testnativemessagebox.md

## Branch Information
- **Branch**: `Skyline/work/20261008_testnativemessagebox` (`I:\git_i\sky_testnativemessagebox`)
- **Base**: `master`
- **Created**: 2026-10-08
- **Status**: PR open, awaiting TeamCity
- **Module**: `skyline`
- **PR**: (see below)

## Objective

Fix the intermittent TeamCity failure of TestNativeMessageBox (about 1.5% of Windows runs):
"Setting values is not supported for native dialog Dialog:Save As". A second attempt after PR #4655,
which was closed because it broke the dialog watcher's snapshot and made other tests fail.

## Root cause

The common Save dialog is built on the classic template. It starts out with the Open dialog's file-name
combo (control id 1148), destroys it, and creates its own file-name Edit (control id 1001) 50-100 ms later.
In between, `NativeDialog.Create` fell through to the generic message box, which is ready as soon as its
window is shown and refuses to take a file name. Both wrappers have the FormId "Dialog:Save As", so the
error text does not reveal which one was returned.

Measured 2026-10-08 with a throwaway probe test that classified the dialog every ~1 ms while Save As opened
(20 opens per run):
- master: a generic NativeDialog in the gap in 20/20 opens
- fix: null in the gap in 20/20 opens, never a generic NativeDialog

On Windows 11 the whole gap passes while the window is still hidden, and every lookup filters to visible
windows, so the failure does not reproduce locally. The failing agent ran Windows 10.0.17763 (Server 2019),
whose shell presumably shows the dialog during the gap sometimes (inferred, not observed).

## Fix

- File dialogs are recognized by the classic file list (lst1, ListBox id 1120) they carry for their whole
  life, and classified as Open, Save, or null while neither file-name field exists
- The generic dialog is ready only once it shows a visible button
- `DialogWatcher.PerformActionAndWait` snapshots raw visible top-level handles
  (`StandaloneWindow.GetTopLevelWindowHandles`) so a window that is briefly unclassifiable is never later
  reported as a new modal (the #4655 regression)

## Testing

- [x] TestNativeMessageBox -Loop 50
- [x] 24 connector/native-dialog functional tests + TestNativeMessageBox + CodeInspection, -Loop 3
- [ ] TeamCity

## Progress log

### 2026-10-08
- Ported the never-committed redo from sky_fixes onto .NET 10 master; probe evidence above; PR opened
