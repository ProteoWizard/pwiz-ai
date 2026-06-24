# TODO-20260505_teardown_hang_fix.md

## Branch Information
- **Branch**: `Skyline/work/20260505_teardown_hang_fix` (merged and deleted)
- **Base**: `master`
- **Created**: 2026-05-05
- **Completed**: 2026-05-06
- **Status**: Completed
- **GitHub Issue**: [#4184](https://github.com/ProteoWizard/pwiz/issues/4184) (closed by merge)
- **PR**: [#4185](https://github.com/ProteoWizard/pwiz/pull/4185) (squash-merged as `2a20cfb4d`)

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

### Fix #2 - `HangDetection.WatchdogLoop` polls for `ThreadExceptionDialog` (no modal hang)

`pwiz_tools/Skyline/TestUtil/HangDetection.cs`:

- `WatchdogLoop` polls `FormUtil.OpenForms` every 500 ms while blocked in
  `InterruptAfter` (i.e. during any `InterruptWhenHung`-wrapped `RunUI` /
  `Invoke` wait, not only during `EndTest`).
- Any `ThreadExceptionDialog` found is logged, recorded in
  `Program.TestExceptions` (so `RunFunctionalTest` calls `Assert.Fail`),
  and dismissed via `CommonActionUtil.SafeBeginInvoke` setting
  `DialogResult = Cancel`.
- New private helpers `DismissThreadExceptionDialogs` and
  `TryGetDialogText` carry the logic.

Initial implementation lived in a standalone
`ThreadExceptionDialogCanceler` class active only during `EndTest`;
folded into `HangDetection` per nickshulman's review feedback (commit
`d6328e2`).

Together: even if a `ThreadExceptionDialog` sneaks past
`Application.ThreadException`, the watchdog will dismiss it within
~500 ms and the test fails with logged context instead of hanging.

## Files Changed

- `pwiz_tools/Skyline/TestUtil/TestFunctional.cs` - guarded `CloseOpenForm`.
- `pwiz_tools/Skyline/TestUtil/HangDetection.cs` - watchdog now also
  polls for `ThreadExceptionDialog` and records/dismisses it.

## Verification

- [x] `Build-Skyline.ps1 -Target TestFunctional` builds clean
- [x] `CodeInspection` test passes
- [x] `ChangeSettingsExplicitModTest` (functional smoke) passes
- [x] All TeamCity PR checks green (Wine x86_64, Skyline PR Perf and Tutorial tests, etc.)
- [ ] Nightly perf run completes without hang (long-running validation, post-merge)

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
