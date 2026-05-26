# TestJsonToolServer expects ArgumentException but gets denial message when desktop unavailable

## Branch Information
- **Branch**: `Skyline/work/20260519_invalid_formid_desktop_unavailable`
- **Base**: `master`
- **Created**: 2026-05-19
- **Status**: Completed
- **GitHub Issue**: [#4229](https://github.com/ProteoWizard/pwiz/issues/4229)
- **PR**: [#4231](https://github.com/ProteoWizard/pwiz/pull/4231) (merged 2026-05-20 as d18cc8f81e)
- **Test Name**: TestJsonToolServer
- **Fix Type**: failure
- **Failure Fingerprint**: `2ecaee9e4b787464`

## Objective

`TestJsonToolServer` is failing on all 9 nightly master machines because
`GetFormImage` short-circuits on `LLM_MSG_SCREEN_CAPTURE_UNAVAILABLE` before
calling `FindFormById`. On a nightly box with a disconnected Remote Desktop
session, `IsDesktopAvailable()` returns false, so the invalid-formId
assertion at `JsonToolServerTest.cs:1395` receives the unavailable message
instead of the expected `ArgumentException`.

This is fallout from PR #4224 (merged 2026-05-18), which moved
`CheckScreenCaptureAvailability()` ahead of `FindFormById` so that bogus
formIds wouldn't trigger a permission prompt. The intent was right;
the ordering left form-existence validation downstream of the desktop check.

## Tasks

- [x] Restructure `JsonUiService.GetFormImage` and `GetFormImageBytes` so
      that form existence is validated on the UI thread before
      `CheckScreenCaptureAvailability` runs.
- [x] Add a regression assertion to `TestScreenCapturePermissionDlg`
      that an invalid formId still throws `ArgumentException` after the
      session has been denied (covers the "input validation must come
      before environment check" contract without requiring desktop-state
      manipulation).
- [x] Run `TestJsonToolServer` end-to-end and confirm it passes locally.
- [x] Confirm `TestSkylineMcp` still passes.
- [x] Confirm `CodeInspection` still passes.
- [x] (Added during review) Guard against null `Program.MainWindow` in
      both image-tool entry points.
- [x] (Added during review) Re-resolve the form inside the capture
      closure rather than reusing a reference captured before the
      pipe-thread permission work, to close the TOCTOU race.
- [x] (Added during self-review) Extend the input-before-environment
      protection to `GetGraphImage` and `GetGraphImageBytes`, factored
      through a shared `CheckImageToolPreflight` helper plus a new
      `EnsureGraphForm` extraction so all four image tools share the
      same validation contract.

## Regression Test

- **Test name**: `TestScreenCapturePermissionDlg` (new assertion within the
  existing test in `JsonToolServerTest.cs`)
- **Test project**: TestFunctional
- **Fails on master**: yes, on machines where `IsDesktopAvailable()` is false.
  Locally I can't easily force that without test infrastructure, but the
  contract is verifiable by running the invalid-formId assertion against the
  session-denied state — under the bug, denied wins; under the fix,
  `ArgumentException` wins regardless.
- **Passes on fix**: yes. `TestJsonToolServer` passed locally on every
  iteration on this branch (foundation + Copilot-review round + self-review
  round). Final nightly verification will land tonight on the previously
  failing master machines.

The deeper guarantee: input validation (formId format + form existence)
must run before any environment check (permission / desktop). The new
assertion exercises one corner of that — invalid formId after Deny — but
the code path is the same one that fires when the desktop is unavailable.

## Approach

```
GetFormImage(formId, filePath):
    ValidateFormIdFormat(formId)              # pipe thread
    form = InvokeOnUiThread(FindFormById)     # UI thread — throws if not found
    denial = CheckScreenCaptureAvailability() # pipe thread
    if denial: return denial
    return InvokeOnUiThread(capture form)     # UI thread — form ref captured in closure
```

The Form reference itself is safe to hold across threads; only its
properties / methods need UI-thread access (which the closure provides).

## Progress Log

### 2026-05-19 - Session Start

Issue read; branch created. Root cause confirmed by re-reading PR #4224's
final state of `JsonUiService.GetFormImage` — `CheckScreenCaptureAvailability`
sits between `ValidateFormIdFormat` and `InvokeOnUiThread(FindFormById)`,
so any environmental failure (denied / pending / desktop-unavailable) wins
over a bad formId.

### 2026-05-19 - Initial fix (commit d4ec0810d6)

Restructured `GetFormImage` and `GetFormImageBytes` so `FindFormById` runs
on the UI thread *before* `CheckScreenCaptureAvailability`. Form reference
captured once and reused in the capture closure. Added regression
assertion in `TestScreenCapturePermissionDlg` that an invalid formId
throws `ArgumentException` even after session denial. All three local
tests (`TestJsonToolServer`, `TestSkylineMcp`, `CodeInspection`) pass.

### 2026-05-19 - Copilot review feedback (commit 137187b3e5)

Two real issues flagged:

- `Assume.IsTrue(Program.MainWindow.InvokeRequired)` inside the generic
  `InvokeOnUiThread<T>` NREs if `Program.MainWindow` is null during
  startup/shutdown. Added a pre-Invoke null guard returning
  `LLM_MSG_SCREEN_CAPTURE_UNAVAILABLE` in both entry points.
- The captured form reference is racy across two Invokes (user could
  close the form while permission is checked on the pipe thread). The
  first `FindFormById` Invoke is now input-validation-only (result
  discarded); the capture closure re-resolves the form inside its own
  Invoke. A close-during-call now surfaces as the same "form not found"
  `ArgumentException` rather than `ObjectDisposedException`.

### 2026-05-19 - Self-review feedback (commit 7467238e92)

Fresh-context Claude agent flagged that the generic `InvokeOnUiThread<T>`
overload lacks the void overload's explicit `ArgumentException`
preservation, and that `GetGraphImage` / `GetGraphImageBytes` did not yet
have any of the new protections. User direction: apply equivalent
protection to all four image tools, DRYed via a sub-function. Refactor:

- New `CheckImageToolPreflight(id, ensureExistsOnUi, requiresScreenCapture)`
  is the single source of truth for the ordering. All four image tools
  call it. Form variants pass `requiresScreenCapture: true`; graph
  variants pass `false`.
- Extracted `EnsureGraphForm(graphId, out form, out graph)` from
  `RenderGraphBitmap` so the cheap "exists and is a graph form" check
  can be used by the preflight without paying for the actual render.
- The helper invokes `ensureExistsOnUi` as `Action`, binding to the
  void overload that preserves `ArgumentException` -- addresses the
  overload-preservation concern.

Findings deferred (worth filing as follow-ups if they bite in practice):

- The MainWindow-null guard is point-in-time; `InvokeOnUiThread` reads
  `Program.MainWindow` directly afterwards. A proper fix means
  reworking `InvokeOnUiThread` itself to snapshot the reference.
- Form-closed-during-call and bad-formId both surface as the same
  "form not found" `ArgumentException`; could be distinguished.
- The MainWindow-null path and the form-closed race remain untested
  (hard to exercise without test seams for `Program.MainWindow`).
- The MainWindow-null message says "Screen capture is not available"
  even for graph variants, which is slightly off wording for graphs.

### 2026-05-20 - Merged

PR #4231 merged as commit d18cc8f81e (squash). Shipped: input-before-
environment ordering for all four image-capture MCP tools (form and
graph), DRYed through a shared `CheckImageToolPreflight` helper, with
the MainWindow-null guard and re-resolve-in-capture race fix added
during review. The nightly TestJsonToolServer failure on 9 master
machines (fingerprint `2ecaee9e4b787464`) should clear on tonight's
run. No follow-up issues filed; the four deferred concerns are
documented above and can be raised later if they bite.
