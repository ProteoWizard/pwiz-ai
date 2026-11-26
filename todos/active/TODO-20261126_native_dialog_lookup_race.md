# TODO-20261126_native_dialog_lookup_race.md

## Branch Information
- **Branch**: `Skyline/work/20261126_native_dialog_lookup_race`
- **Base**: `master`
- **Created**: 2026-11-26
- **Status**: In Progress
- **Module**: `skyline`
- **PR**: [#5082](https://github.com/ProteoWizard/pwiz/pull/5082)
- **Related**: TestNativeMessageBox intermittent on TeamCity bt209 (31 of 709 runs since #4799, on ~25
  PRs and master), e.g. build 4281937

## Objective

Stop the AI connector reporting "Form not found" for a native dialog it has just named. ResolveForm
re-finds a form from scratch and skipped a native dialog that was momentarily not ready to drive
(the shell re-lays a file dialog out after showing it), throwing at once with no retry.

## Done

- [x] `JsonUiService.ResolveForm`: when no drivable window has the id but a native dialog with it is
      open, wait for it (until ready, closed, cancelled, or 10 s); never wait on the main window's
      thread; a bad id still fails at once with the same message
- [x] `NativeDialog.IsAnyOpenWithId`: finds a dialog with the id whether or not it can be driven
- [x] `NativeMessageBoxTest`: hides the Save dialog's Save button before SetFormValue and re-shows it
      300 ms later (red: "Form not found: Dialog:Save As" every run; green 5/5)
- [x] 25 MCP connector tests and CodeInspection pass

## Progress Log

### 2026-11-26 - Root cause and fix

All TeamCity failures carry the same trace (SetFormValue, or GetModalNestingCount in older runs,
throwing from FindFormById right after ClickMainMenuItem named the dialog); none in nightly.
Sampling every #32770 in the process locally showed the Save dialog is built hidden (first with the
Open dialog's combo 1148, then the Save Edit 1001) and shown complete, then briefly hides its
file-name field again after showing. The exact transient TeamCity hits was not caught locally, even
under CPU load; the test stands in for it by hiding the commit button, which is what
`NativeFileDialog.IsOpenComplete` keys on.

### 2026-11-26 - Code review and PR

/code-review medium: 10 findings. Fixed: wait loop polls only native dialogs (no main-window Invoke
per poll); IsAnyOpenWithId reuses FindDialogHandles (shown only, so a hidden leftover cannot stall a
bad id) and a shared FormId helper; test hides the button 1 s and joins in finally. Dropped: other
UI threads (native dialogs are main-thread only), GetOpenForms/DialogWatcher (report state, caller
re-queries), monotonic Create via remembered hwnds (global state, hwnd reuse), Save->Open
reclassification (combo swap only while hidden), test IDOK constant. Re-verified red/green; PR #5082.
