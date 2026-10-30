# TODO-20261020_skylinetester_hidden_window.md

## Branch Information
- **Status**: Completed - #4882 merged 2026-10-20
- **Branch**: `Skyline/work/20261020_skylinetester_hidden_window`
- **Base**: `master`
- **Module**: `skyline`
- **Created**: 2026-10-20
- **PR**: [#4882](https://github.com/ProteoWizard/pwiz/pull/4882)
- **Objective**: SkylineTester shows the Skyline main window again in Screenshot, Auto-Screenshot
  and Cover shot modes on .NET 10.

## Root cause

`SkylineTester/CommandShell.cs` `CreateProcess` started TestRunner with
`WindowStyle = ProcessWindowStyle.Hidden` (since 2013). Windows applies a hidden startup window
style to the first window a GUI child shows normally, and on .NET 10 that is the Skyline main
window. WinForms still reports `Visible=True`; `IsWindowVisible` is false. Test and Demo modes were
unaffected because `FormEx.ShowWithoutActivation` is true when `PauseSeconds == 0`, so the window is
shown with `SW_SHOWNOACTIVATE`, which Windows does not override. Run-Tests.ps1 was unaffected because
it does not set a hidden window style.

Confirmed with a standalone experiment (child process started with and without `WindowStyle.Hidden`,
forms shown normally and without activation) and with visibility logging in an instrumented run.
Diagnosed during the PR #4602 review; the same fix is in that PR's commit 8346379152.

## Fix

Removed `WindowStyle = ProcessWindowStyle.Hidden`; `CreateNoWindow = true` still hides consoles.

## Tasks
- [x] Fix and verify (main window shows from SkylineTester in Screenshot mode)
- [x] PR merged

## Progress Log

### 2026-10-20 - Merged

PR #4882 squash-merged to `master` as `f1156f1019`.

## Resolution

**Status**: Completed (merged 2026-10-20)

SkylineTester no longer starts TestRunner with a hidden window style, so the Skyline main window shows in Screenshot, Auto-Screenshot and Cover shot modes on .NET 10.
