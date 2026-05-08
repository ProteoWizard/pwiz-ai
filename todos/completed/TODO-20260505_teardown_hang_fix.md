# TODO-20260505_teardown_hang_fix.md

## Branch Information
- **Branch**: `Skyline/work/20260505_teardown_hang_fix`
- **Base**: `master`
- **Created**: 2026-05-05
- **Status**: Complete
- **GitHub Issue**: [#4184](https://github.com/ProteoWizard/pwiz/issues/4184)
- **PR**: [#4185](https://github.com/ProteoWizard/pwiz/pull/4185) (merged 2026-05-06)

## Problem

A perf-pass nightly run (`SKYLINE-DEV6_2026-05-04_01-04-14`) hung in pass 2 at
`TestIonMobility (fr)` during `EndTest` cleanup. The hang detector fired after
30 minutes, dumped threads, and aborted.

Root cause chain (from log thread dump):

1. `EndTest` calls `RunUI(SkylineWindow.Close)` which goes through
   `HangDetection.InterruptWhenHung(() => form.Invoke(act))`.
2. The UI thread closes a form (`<>c__DisplayClass37_0.b__0` from
   `CloseOpenForm`'s lambda) which triggers `Form.WmClose`.
3. Inside `WmClose`, `EventWaitHandle.Set()` throws
   `ObjectDisposedException: Safe handle has been closed` — the modal-event
   `SafeWaitHandle` was already disposed (race during teardown).
4. WinForms catches the exception via `Control.WndProcException` and calls
   `Application.ThreadContext.OnThreadException`. For unclear reasons our
   registered `Application.ThreadException` handler is bypassed and a
   `ThreadExceptionDialog` appears.
5. The dialog's `ShowDialog` runs a nested message loop on the UI thread.
   The test thread is parked in `Control.Invoke` waiting on a `WaitHandle`
   that won't fire until the UI thread returns. Hang.
6. After 30 minutes `HangDetection` interrupts the test thread with
   `ThreadInterruptedException`, but the UI thread is still wedged. Process
   exits with code -1.

The closing list before the hang shows a `ThreadExceptionDialog` was already
in `OpenForms`, meaning an *earlier* exception had already popped a dialog.
The cleanup cascade then tried to `Form.Close()` it, which re-triggered the
SafeHandle race.

## Goals

1. Avoid the race condition where possible.
2. Replace the modal-dialog hang with a logged failure so the test runner
   exits promptly with diagnostic info instead of waiting 30 minutes.

## Approach

Implemented per the design from a Claude.ai consultation
(https://claude.ai/share/7eb3e731-aaa8-4493-81e7-e9818283031d):

### Fix #1 - Defensive `CloseOpenForm` (race avoidance)

`pwiz_tools/Skyline/TestUtil/TestFunctional.cs`:

- Added `IsDisposed` pre-check before calling `Form.Close()` so we don't
  re-trigger `WmClose` on a form whose internal handles are already gone.
- Added explicit `ObjectDisposedException` and `InvalidOperationException`
  catches in addition to the existing generic catch.
- Special-cased `ThreadExceptionDialog`: dismiss via
  `DialogResult = DialogResult.Cancel` (which uses `PostMessage` internally)
  instead of `Form.Close()` (which uses synchronous `SendMessage`). This
  keeps any subsequent exception out of the test thread's call stack.

### Fix #2 - `ThreadExceptionDialogCanceler` watchdog (no modal hang)

New file `pwiz_tools/Skyline/TestUtil/ThreadExceptionDialogCanceler.cs`:

- Background thread (`ActionUtil.RunAsync`) modeled on
  `LongWaitDialogCanceler`. Polls `FormUtil.OpenForms` every 500 ms.
- Any `ThreadExceptionDialog` found is logged, recorded in
  `Program.TestExceptions` (so the test fails with a clear message), and
  dismissed via `CommonActionUtil.SafeBeginInvoke` setting
  `DialogResult = Cancel`.
- Disposed at end of `EndTest` via a `using` declaration.

Together: even if a `ThreadExceptionDialog` sneaks past
`Application.ThreadException`, the canceler will dismiss it within ~500 ms
and the test fails with logged context instead of hanging.

## Files Changed

- `pwiz_tools/Skyline/TestUtil/TestFunctional.cs` - guarded `CloseOpenForm`,
  added canceler `using` in `EndTest`.
- `pwiz_tools/Skyline/TestUtil/TestUtil.csproj` - registered new file.
- `pwiz_tools/Skyline/TestUtil/ThreadExceptionDialogCanceler.cs` - NEW.

## Verification

- [x] `Build-Skyline.ps1 -Target TestFunctional` builds clean
- [x] `CodeInspection` test passes
- [x] `ChangeSettingsExplicitModTest` (functional smoke) passes
- [ ] Nightly perf run completes without hang (long-running validation)

## Notes

- The original `ObjectDisposedException` on `EventWaitHandle.Set` is still a
  real bug in some form's teardown ordering — this fix does not address its
  root cause, only the failure mode. The first nightly that catches it again
  with the guard in place will give us cleaner diagnostics (the dialog text
  is now captured in `Program.TestExceptions`).
- Optional follow-up: hook
  `AppDomain.CurrentDomain.FirstChanceException` during `EndTest` to log
  the original exception that opens the first `ThreadExceptionDialog`.
  Skipped for this fix to keep scope tight; can be added when the next
  nightly catches a recurrence.

## Progress Log

### 2026-05-06 - Merged

PR [#4185](https://github.com/ProteoWizard/pwiz/pull/4185) "Guarded test teardown against modal-dialog hang" merged to `master` as commit `2a20cfb`. Closes issue #4184.

## Resolution

**Status**: Complete (PR #4185 merged 2026-05-06)

Both pieces of the design landed:

* `CloseOpenForm` in `TestFunctional.cs` now pre-checks `IsDisposed`, catches `ObjectDisposedException` / `InvalidOperationException` explicitly, and dismisses any `ThreadExceptionDialog` via `DialogResult = Cancel` (PostMessage) rather than synchronous `Form.Close()` — closing the race window that triggered the hang.
* New `ThreadExceptionDialogCanceler` runs as a background watchdog during the test, polling `FormUtil.OpenForms` every 500 ms; any `ThreadExceptionDialog` is logged into `Program.TestExceptions` and dismissed, so a stray modal dialog now causes a logged test failure instead of a 30-minute hang.

Underlying `ObjectDisposedException` on `EventWaitHandle.Set` during teardown is not addressed by this PR — the failure mode is now safe, but the root-cause race is still in the codebase. Optional `FirstChanceException` follow-up was deferred per the Notes above.
