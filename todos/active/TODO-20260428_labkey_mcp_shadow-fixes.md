# TODO-20260428_labkey_mcp_shadow-fixes.md

## Branch Information
- **Branch**: `labkey-mcp-fixes-for-testresults-refactor`
- **Base**: `master`
- **Created**: 2026-04-28
- **Status**: Committed and pushed; awaiting deployment of the testresults Spring-binding refactor on skyline.ms before merge.
- **Related**:
  - `TODO-LK-20260425_testresults-schema-shadow-test.md` — caught these.
  - `TODO-LK-20260326_testresults-migrate-actions.md` Phase 7 — references
    this PR as a deployment prerequisite.
  - `TODO-20260428_labkey_mcp_dev-target.md` — sibling PR (env-var
    dev-target support; the feature that enabled the shadow test).

## Objective

Three MCP-side regressions caused by contract changes in the testresults
Spring-binding refactor (PR
[LabKey/MacCossLabModules#622](https://github.com/LabKey/MacCossLabModules/pull/622)).
Each was caught by exercising a nightly-flow MCP tool against the refactored
module on a dev box and seeing it fail in a way the pre-refactor build did
not.

**Important — must land at the same time as the testresults Spring-binding refactor deployment
on skyline.ms.** Without these fixes, the nightly MCP tools that call
`ViewLogAction` / `ViewXmlAction` / `SetUserActiveAction` will silently
return wrong data (or report success on failure) once the refactor is live.

## Out of Scope

- Env-var-driven target switching → sibling PR
  `TODO-20260428_labkey_mcp_dev-target.md`.

## Files Changed

```
mcp/LabKeyMcp/tools/nightly.py    # 3 lines (runid → runId)
mcp/LabKeyMcp/tools/computers.py  # _set_computer_active rewrite + non-200 extractor
mcp/LabKeyMcp/tools/common.py     # post_json now parses JSON error bodies
```

## Fix 1: `runid` → `runId` URL params (`tools/nightly.py`)

- **Affected tools:** `save_run_log`, `save_run_xml`.
- **Symptom (post-refactor):** tools returned `{ }` (empty JSON) instead of
  log/XML content.
- **Root cause:** the refactor switched `ViewLogAction` and `ViewXmlAction`
  to `RunIdForm.setRunId` (camelCase). Spring data binding is case-sensitive,
  and `BaseApiAction.populateForm()` matches setter names against query
  params exactly. The MCP was sending `?runid=...` (lowercase). Pre-refactor
  these two actions used `request.getParameter("runid")` directly, which is
  case-insensitive, so the MCP/server mismatch was hidden.
- **Fix:** changed three URL builders in `tools/nightly.py` from
  `runid={run_id}` to `runId={run_id}`. 

## Fix 2: JSON body + Message check (`tools/computers.py`)

- **Affected tools:** `deactivate_computer`, `reactivate_computer`.
- **Symptom (post-refactor):** the action returned HTTP 200 with
  `{"Message": "userId is required"}` and the MCP reported success.
- **Root cause (two layered bugs):**
  1. The refactor switched `SetUserActiveAction` to use `SetUserActiveForm`.
     With `Content-Type: application/json`, `BaseApiAction.populateForm()`
     reads the JSON body and **ignores URL query params**. The MCP was
     sending `?userId=99&active=false` with a `{}` body, so the form was
     never populated → `userId is required` → in-action error returned with
     HTTP 200.
  2. The MCP only checked HTTP status and treated 200 as success, so the
     in-action error was reported back as a successful state change.
- **Fix:**
  - `_set_computer_active` now sends `userId` and `active` in the JSON body
    (`session.post_json(url, {"userId": ..., "active": ...})`).
  - Treats anything other than `Message == "Success"` as a failure and
    extracts the actual `Message` for the error report.
- **Verification:** `deactivate_computer("AEROWORK")` correctly reports
  `User not found id=100` (AEROWORK has no userdata row in Nightly x64).
  `deactivate_computer` / `reactivate_computer` round-trip on a real account
  is net-zero (51 active before, 51 after).

## Fix 3: `exception` over `error` for non-200 responses (`tools/computers.py`, `tools/common.py`)

- **Affected tool:** `_set_computer_active` (used by `deactivate_computer`,
  `reactivate_computer`) when a non-200 response is returned by the
  testresults `SetUserActive` action.
- **Symptom:** error messages from LabKey's standard error response
  (which uses `"exception"`, e.g. on 403 Forbidden) showed up as a
  generic fallback or raw payload rather than the actual error string.
- **Root cause (two layers):**
  1. `LabKeySession.post_json` in `tools/common.py` caught
     `urllib.error.HTTPError` and wrapped the response body as
     `{"error": "<raw body string>"}`. So even when LabKey returned a
     structured JSON error envelope (e.g. `{"exception": "...",
     "success": false}`), the caller saw the JSON-as-string under
     `error`, never as a parsed dict.
  2. `_set_computer_active` only read `error` from the result, so on
     a non-200 it surfaced the raw JSON blob to the user instead of
     the actual exception text.
- **Fix:**
  - `post_json` now tries to parse the error body as JSON and returns
    the parsed dict if it parses; falls back to the existing
    `{"error": "<raw body>"}` shape only for non-JSON bodies. Every
    caller benefits.
  - `_set_computer_active` reads
    `result.get("exception") or result.get("error") or str(result)[:200]`,
    with an `isinstance(result, dict)` guard for safety.

> The same call-site pattern existed in `tools/wiki.py` and was fixed
> in the dev-target PR (`TODO-20260428_labkey_mcp_dev-target.md`).
> The `post_json` fix here makes that path even cleaner once the two
> PRs are merged together.

## Verification

All verification was done **on the dev box** (a local LabKey running the
refactored testresults code, with data restored from a production DB
dump). It cannot be done on production yet — the testresults refactor
is not deployed there.

Covered by the shadow test (see
`TODO-LK-20260425_testresults-schema-shadow-test.md` Phases 1–3):

- 13/13 read-only nightly MCP tools byte-identical across the three
  shadow-test states (External-only / External+UserSchema / UserSchema-only).
- `deactivate_computer("BOSS-PC")` reduced active count 51 → 50;
  `reactivate_computer("BOSS-PC")` returned it to 51. Net-zero
  round-trip on a real account.
- `deactivate_computer("AEROWORK")` correctly reported `User not found
  id=100` (AEROWORK has no userdata row in Nightly x64) — confirms the
  Message-check fix surfaces in-action errors instead of silently
  reporting success.

### Fix 3 verification (post_json JSON parsing)

Reproduced before-and-after by removing the +claude account's update
role on a testresults container, then calling
`testresults-setUserActive.view` directly through `LabKeySession.post_json`:

- **Before fix:** `post_json` returned
  `{'error': '{\n  "exception" : "User does not have permission...",\n  "success" : false\n}'}`
  — the whole error envelope dumped as a string under `error`. The
  caller's extractor would have surfaced this raw JSON blob to the user.
- **After fix:** `post_json` returned
  `{'exception': 'User does not have permission...', 'success': False}`
  — parsed dict, `exception` field directly accessible.

Test script: `ai/.tmp/test_post_json.py` (not committed).

### Post-deployment verification (on production)

Once the testresults Spring-binding refactor is deployed on
skyline.ms, re-run the same set against production to confirm the
fixes work on the real deployment. That's the open item for whoever
ships the refactor.

## Notes

- The Spring binding case-sensitivity that surfaced Fix 1 was visible
  because `ViewLogAction` / `ViewXmlAction` previously used
  `request.getParameter("runid")` while every other run-id action in the
  controller already used `runId`. Pre-refactor inconsistency in the
  controller masked the inconsistency in the MCP caller.
