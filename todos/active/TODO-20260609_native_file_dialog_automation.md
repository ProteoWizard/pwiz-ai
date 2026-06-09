# TODO-20260609_native_file_dialog_automation.md -- Drive the native OpenFileDialog via UI Automation, and surface it to the MCP

## Status

Active -- on the feature branch: initial implementation + base/subclass refactor
landed (2 commits). PR not yet opened.

## Branch Information

- **pwiz branch**: `Skyline/work/20260609_native_file_dialog_automation`
- **PR**: TBD
- **ai branch**: `master`

## Background

Automated tests (and, ultimately, the Skyline MCP server -- see
[#4089](https://github.com/ProteoWizard/pwiz/issues/4089)) need to interact
with Skyline's File > Open command the way a user does. The native Windows
common file dialog is not a WinForms form, so it never appears in
`FormUtil.OpenForms` and cannot be introspected or driven the way the rest
of Skyline's UI is. UI Automation (Accessibility) is the mechanism that can
reach it.

## Objective

1. Let tests open a document through the real File > Open UI instead of
   calling `SkylineWindow.OpenFile` directly.
2. Make the native OpenFileDialog a first-class citizen of the MCP's generic
   UI-introspection layer: it shows up in `get_open_forms` and
   `get_form_image` works on it.

## Done (this commit)

* `SkylineWindow.ShowOpenFileDialog()` extracted from `openMenuItem_Click`
  so the menu code path is callable.
* Shared product code (not test-only) that drives the native dialog via UI
  Automation, split into a base class and a subclass:
  * `NativeDialogAutomation` (abstract base) -- instance-based; drives any
    native `#32770` dialog: `WaitForDialog`, `GetOpenDialogs`, `Cancel`
    (WM_CLOSE), `PressEnter`, the off-UI-thread enumeration, and the
    `WaitFor`/`WaitForElement` plumbing. Subclasses override `IsMatch`.
  * `OpenFileDialogAutomation : NativeDialogAutomation` -- identifies the
    dialog by its file-name combo (AutomationId `1148`) and adds
    `EnterPathAndAccept(path)`.
* `AbstractFunctionalTest.OpenDocument(path)` -- posts the dialog with
  `BeginInvoke`, drives it, waits for the new document. LiveReportsTutorialTest
  migrated to it.
* MCP discovery: `JsonUiService.GetOpenForms` enumerates native dialogs
  (`FormInfo.IsNative`, `Type="FileDialog"`); `GetFormImage`/`GetFormImageBytes`
  capture a native window by HWND. MCP server `skyline_get_open_forms` adds an
  `IsNative` column.
* `NativeFileDialogTest` -- covers discovery, image capture, cancel, and open.

## Key findings (hard-won; keep for the MCP work)

* `InvokePattern.Invoke` on the common file dialog's buttons is **unreliable**
  (it is a DirectUI surface) -- it silently no-ops. Drive the dialog with
  window messages instead: a posted **Enter** (`WM_KEYDOWN`/`WM_KEYUP`,
  `VK_RETURN`) to accept, `WM_CLOSE` to cancel.
* Set the path on the **Edit** control inside the "File name" combo box
  (AutomationId `1148`), not on the combo box -- the combo auto-completes and
  discards the directory portion. Setting the full path on the Edit + Enter
  navigates and opens in one action, regardless of the dialog's current folder.
* Native dialogs appear in the UIA tree as a top-level window or a direct
  child of the owner window -- enumerate via top-level windows + their direct
  children, never a full `Subtree` walk (prohibitively slow over Skyline's
  control tree).
* The UIA scan must run off the UI thread (the modal dialog holds the UI
  thread in its own message loop); the WinForms enumeration still marshals to
  the UI thread.

## Remaining work

* Migrate remaining tutorial/functional tests from `SkylineWindow.OpenFile`
  to `OpenDocument` incrementally (not all at once).
* MCP Phase 3: route `get_form_state` / `set_form_values` /
  `click_form_button` to the native automation when `IsNative` is set, so the
  dialog is fully operable through the generic tools (this PR only adds
  discovery + image).

## Verification

* `NativeFileDialogTest` (discovery + image + cancel + open) -- passes,
  stable across repeated runs (~1-2s).
* `LiveReportsTutorialTest` -- passes (~20s), exercises `OpenDocument`.
* `SkylineMcpTest`, `CodeInspection` -- pass. Solution builds clean.
