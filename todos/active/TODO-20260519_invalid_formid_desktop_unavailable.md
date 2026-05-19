# TestJsonToolServer expects ArgumentException but gets denial message when desktop unavailable

## Branch Information
- **Branch**: `Skyline/work/20260519_invalid_formid_desktop_unavailable`
- **Base**: `master`
- **Created**: 2026-05-19
- **Status**: In Progress
- **GitHub Issue**: [#4229](https://github.com/ProteoWizard/pwiz/issues/4229)
- **PR**: (pending)
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

- [ ] Restructure `JsonUiService.GetFormImage` and `GetFormImageBytes` so
      that form existence is validated on the UI thread before
      `CheckScreenCaptureAvailability` runs.
- [ ] Add a regression assertion to `TestScreenCapturePermissionDlg`
      that an invalid formId still throws `ArgumentException` after the
      session has been denied (covers the "input validation must come
      before environment check" contract without requiring desktop-state
      manipulation).
- [ ] Run `TestJsonToolServer` end-to-end and confirm it passes locally.
- [ ] Confirm `TestSkylineMcp` still passes.
- [ ] Confirm `CodeInspection` still passes.

## Regression Test

- **Test name**: `TestScreenCapturePermissionDlg` (new assertion within the
  existing test in `JsonToolServerTest.cs`)
- **Test project**: TestFunctional
- **Fails on master**: yes, on machines where `IsDesktopAvailable()` is false.
  Locally I can't easily force that without test infrastructure, but the
  contract is verifiable by running the invalid-formId assertion against the
  session-denied state — under the bug, denied wins; under the fix,
  `ArgumentException` wins regardless.
- **Passes on fix**: pending verification.

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
