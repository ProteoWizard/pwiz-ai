# Non-blocking screen-capture permission prompt for skyline_get_form_image

## Branch Information
- **Branch**: `Skyline/work/20260517_nonblocking_screen_capture_permission`
- **Base**: `master`
- **Created**: 2026-05-17
- **Status**: Completed
- **GitHub Issue**: [#4221](https://github.com/ProteoWizard/pwiz/issues/4221)
- **PR**: [#4224](https://github.com/ProteoWizard/pwiz/pull/4224) (merged 2026-05-18 as b34ce170a5)

## Objective

Change `skyline_get_form_image`'s first-time permission flow so the confirmation
dialog is shown via `BeginInvoke` (non-blocking) instead of `ShowDialog` (blocking).
The tool call returns immediately with a clear "user confirmation required" message;
the LLM tells the user to OK the dialog in Skyline; the next call succeeds.

Eliminates a class of confusing hangs where the user is focused on the LLM chat
window and doesn't notice a modal popped up in the Skyline window behind it.

## Tasks

- [x] Replace `ScreenCapture.EnsurePermission` bool return with `PermissionResult` enum (`granted`, `denied`, `pending`).
- [x] Drop the `wasFirstPrompt` out-param.
- [x] Dispatch the permission dialog via `BeginInvoke` and return `pending` immediately.
- [x] Track `_promptPending` (and `_sessionDenied`) so concurrent/retry calls don't open a second dialog and so a denied session stays denied.
- [x] Wire the dialog's `FormClosed` handler to clear `_promptPending` and update `_sessionPermissionGranted` / `_sessionDenied` / `Settings.Default.AllowMcpScreenCapture`.
- [x] Add explicit `Close()` calls to `ScreenCapturePermissionDlg` button handlers so the dialog closes when shown modelessly via `Show()`.
- [x] Map `pending` -> new "Screen capture permission required" message in `JsonUiService.CaptureFormBitmap`; preserve existing `denied` and `granted` paths; drop the `Thread.Sleep(1000)` repaint hack.
- [x] Update `skyline_get_form_image` MCP tool description to document the two-phase handshake.
- [x] Update `TestScreenCapturePermissionDlg` to drive the new async pattern (first call returns Pending, then dialog appears).
- [x] Add coverage: concurrent call while pending returns Pending without opening a second dialog; session-denied state returns Denied without re-prompting.
- [x] Build with zero warnings.
- [x] Run `TestJsonToolServer` (covers `TestScreenCapturePermissionDlg` + `TestFormImage`) and `TestSkylineMcp` end-to-end.
- [x] Run CodeInspection.

## Regression Test

- **Test name**: `TestScreenCapturePermissionDlg` (subtest of `TestJsonToolServer`)
- **Test project**: TestFunctional
- **Fails on master**: yes (by construction). The old `ShowDialog` flow blocks
  inside `server.GetFormImage` on the same thread that has not yet shown the
  dialog; the new test issues the call directly from the test thread and then
  waits for the dialog. Under the old code, the call never returns until the
  dialog is dismissed, so `WaitForOpenForm` would still find the dialog but the
  next line - which expects a `"permission required"` message already returned -
  would never be reached.
- **Passes on fix**: yes. Verified locally on every commit on this branch
  (foundation + Copilot review + self-review rounds); CodeQL on the merge ran
  green; manual end-to-end against the running MCP server verified all three
  states (pending, granted-after-Allow, denied-after-Deny) in two Skyline
  sessions before merge.

The test asserts the non-blocking contract directly: the first
`GetFormImage` call returns synchronously with the new "permission required"
message before the dialog is interacted with, a second call while the dialog
is still open also returns Pending without opening a second dialog, and the
session-denied state suppresses the dialog for the rest of the session.

## Progress Log

### 2026-05-17 - Session Start

Issue read; branch created; TODO drafted.

### 2026-05-17 - Implementation

Files modified:
- `pwiz_tools/Skyline/Util/ScreenCapture.cs` - added `PermissionResult` enum
  (`granted`/`denied`/`pending`), replaced `EnsurePermission(out bool)` with
  parameterless `EnsurePermission()` returning the enum. Tracks
  `_promptPending` and `_sessionDenied` alongside the existing
  `_sessionPermissionGranted`. First-time prompt dispatches
  `ScreenCapturePermissionDlg.Show(Program.MainWindow)` via `BeginInvoke` and
  returns `pending`. The dialog's `FormClosed` handler updates state and
  disposes the (modeless) dialog. `ResetSessionPermission()` now clears all
  three flags.
- `pwiz_tools/Skyline/Alerts/ScreenCapturePermissionDlg.cs` - button handlers
  now call `Close()` after setting `DialogResult` so the modeless dialog
  closes on click (`DialogResult` setter is a no-op for non-modal forms).
- `pwiz_tools/Skyline/ToolsUI/JsonUiService.cs` - `CaptureFormBitmap`
  switches on the new enum, mapping `pending` to a new LLM-facing message
  documenting the two-phase handshake. Dropped the `Thread.Sleep(1000)`
  repaint hack (the dialog is no longer up when capture proceeds, so there's
  nothing to wait for).
- `pwiz_tools/Skyline/Executables/Tools/SkylineMcp/SkylineMcpServer/Tools/SkylineTools.cs` -
  extended the `skyline_get_form_image` tool description to document the
  handshake so the LLM does not treat the first-call Pending message as a
  fatal error.
- `pwiz_tools/Skyline/TestFunctional/JsonToolServerTest.cs` -
  `TestScreenCapturePermissionDlg` rewritten to drive the new flow: first
  call returns Pending immediately, second call while pending returns Pending
  without opening a second dialog, Cancel sets a session-denied state that
  short-circuits without re-prompting, Allow grants, and "Do not ask again"
  persists.

### 2026-05-17 - Verification

- `Build-Skyline.ps1` - succeeded (46.6s).
- `Run-Tests.ps1 -TestName TestJsonToolServer` - passed (16.2s).
- `Run-Tests.ps1 -TestName TestSkylineMcp` - passed (6.3s).
- `Run-Tests.ps1 -TestName CodeInspection` - passed (11.5s).

### 2026-05-17 - Refinement after first review pass

- Reworked the design after the user pointed out that the dialog did not need
  to be modeless: `EnsurePermission` now schedules a *modal* `ShowDialog` on
  the UI thread via `BeginInvoke` from the pipe thread. The dialog's own modal
  pump still services other pipe-thread Invokes (so concurrent calls correctly
  see `_promptPending` and return Pending), and we avoid the modeless-form
  close gymnastics (no explicit `Close()` calls on the dialog, no FormClosed
  handler). `ScreenCapturePermissionDlg.cs` reverted to its master state.
- `CaptureFormBitmap` split into `CheckScreenCaptureAvailability` (pipe
  thread) and `CaptureGrantedForm` (UI thread); `EnsurePermission` now opens
  with `Assume.IsTrue(Program.MainWindow.InvokeRequired)` to enforce the
  background-thread contract.
- Live end-to-end verified against the running MCP server: first call returns
  Pending immediately, dialog appears in Skyline behind the chat window,
  second call returns Pending without opening a second dialog, Allow lets the
  next call capture, Deny + restart returns Denied without re-prompting.

### 2026-05-18 - Copilot review feedback (commit a6bd261288)

- Made `_promptPending` transition atomic via
  `Interlocked.CompareExchange(ref _promptPending, 1, 0)` to close the
  check-and-set race two pipe threads could otherwise lose.
- Routed the dialog dispatch through `CommonActionUtil.SafeBeginInvoke`
  and clear the gate via `Interlocked.Exchange` when it returns false, so
  a shutdown-time handle outage cannot leave the gate stuck.
- Pre-validate `formId` format on the pipe thread (`ValidateFormIdFormat`)
  before any permission prompt, so a malformed ID throws immediately and
  never interrupts the user with a dialog the request cannot use.
- Promoted the three LLM-facing strings to `public static readonly
  LlmInstruction` fields on `JsonUiService` (`LLM_MSG_SCREEN_CAPTURE_*`);
  production code returns them via implicit `LlmInstruction -> string`
  conversion and the tests `AssertEx.AreEqual` against `.Value`, replacing
  brittle English substring assertions.

### 2026-05-18 - Self-review fixes (commit cdaa192cf7)

- Guarded `EnsurePermission` against `Program.MainWindow == null` by
  capturing a local and returning a new `PermissionResult.unavailable`
  state if the field has not yet been (or has already been) set. Prevents
  an NRE on `InvokeRequired` during startup/shutdown.
- Returned `unavailable` (not `pending`) when `SafeBeginInvoke` fails, so
  the LLM is not told to wait on a dialog that will never appear and stop
  looping the false promise.
- `CheckScreenCaptureAvailability` maps the new `unavailable` state to
  `LLM_MSG_SCREEN_CAPTURE_UNAVAILABLE`, sharing the same message the
  desktop-disconnected case already used.
- Reworded the MCP tool description to describe the handshake shape rather
  than quote the exact runtime strings, with a header comment pinning the
  description to `JsonUiService.LLM_MSG_SCREEN_CAPTURE_*` so the two cannot
  drift when `LlmInstruction` is eventually localized.

### 2026-05-18 - Merged

PR #4224 merged as commit b34ce170a5 (squash). The end-to-end fix went in
with all four Copilot inline comments resolved and the four most-severe
self-review findings addressed in follow-up commits. Skyline-unavailable
edge cases (mid-startup/shutdown handle loss) now degrade to the same
"Screen capture is not available" message the desktop-disconnected case
already returned; the LLM never loops on a non-existent dialog. Deferred:
the agent's design note about adding unit-level tests for `ScreenCapture`
with a stubbed `MainWindow` was not pursued - the functional test exercises
the happy paths; the unavailable branches are guarded but un-tested.
