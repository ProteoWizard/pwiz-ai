# Non-blocking screen-capture permission prompt for skyline_get_form_image

## Branch Information
- **Branch**: `Skyline/work/20260517_nonblocking_screen_capture_permission`
- **Base**: `master`
- **Created**: 2026-05-17
- **Status**: In Progress
- **GitHub Issue**: [#4221](https://github.com/ProteoWizard/pwiz/issues/4221)
- **PR**: (pending)

## Objective

Change `skyline_get_form_image`'s first-time permission flow so the confirmation
dialog is shown via `BeginInvoke` (non-blocking) instead of `ShowDialog` (blocking).
The tool call returns immediately with a clear "user confirmation required" message;
the LLM tells the user to OK the dialog in Skyline; the next call succeeds.

Eliminates a class of confusing hangs where the user is focused on the LLM chat
window and doesn't notice a modal popped up in the Skyline window behind it.

## Tasks

- [ ] Replace `ScreenCapture.EnsurePermission` bool return with `PermissionResult` enum (`Granted`, `Denied`, `Pending`).
- [ ] Drop the `wasFirstPrompt` out-param.
- [ ] Dispatch the permission dialog via `BeginInvoke` (or the project's standard non-blocking UI pattern) and return `Pending` immediately.
- [ ] Track `_promptPending` so concurrent/retry calls don't open a second dialog.
- [ ] Wire the dialog's `FormClosing` handler to clear `_promptPending` and update `_sessionPermissionGranted` / `Settings.Default.AllowMcpScreenCapture`.
- [ ] Map `Pending` -> new LLM instruction in `JsonUiService.GetFormImage`; preserve existing `Denied` and `Granted` paths.
- [ ] Add the new LLM-visible string to `LlmInstruction` alongside the other instructions.
- [ ] Update `skyline_get_form_image` tool description to document the two-phase handshake.
- [ ] Update tool description in the MCP server to match.
- [ ] Update `TestScreenCapturePermissionDlg` to drive the new async pattern.
- [ ] Add tests: first call -> `Pending`; second call while pending -> `Pending` without dialog; OK -> next call captures; Cancel -> subsequent calls return `Denied`; "do not ask again" persists.
- [ ] Run `TestSkylineMcp` and `TestScreenCapturePermissionDlg` end-to-end.

## Regression Test

- **Test name**: (filled in once written)
- **Test project**: TestFunctional (uses `TestScreenCapturePermissionDlg` infrastructure)
- **Fails on master**: (yes/no, with run log path or SHA when verified)
- **Passes on fix**: (yes/no, with run log path or SHA when verified)

The hang behavior on the JSON-RPC pipe thread is the failure to reproduce on
master. A test that issues a tool call while permission is unresolved and
asserts the call returns within a bounded time (rather than blocking on the
modal) is the natural regression guard. Existing `TestScreenCapturePermissionDlg`
covers the dialog itself; we need to extend it (or add a sibling test) to assert
the non-blocking tool-call contract.

## Progress Log

### 2026-05-17 - Session Start

Issue read; branch created; TODO drafted. Next: locate `ScreenCapture.cs`,
`JsonUiService.cs`, and `LlmInstruction` to map current vs target shape before
editing.
