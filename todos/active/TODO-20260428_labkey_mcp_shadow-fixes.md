# TODO-20260428_labkey_mcp_shadow-fixes.md

## Branch Information
- **Branch**: TBD (suggested: `26.4_fb_labkey-mcp-shadow-fixes`)
- **Base**: `master`
- **Created**: 2026-04-28
- **Status**: Ready to commit (working tree only).
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
mcp/LabKeyMcp/tools/wiki.py       # non-200 extractor in update_wiki_page
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

## Fix 3: `exception` over `error` for non-200 responses (`tools/computers.py`, `tools/wiki.py`)

- **Affected tools:** any non-200 response in the wiki and computers flows.
- **Symptom:** error messages from the LabKey framework error envelope
  (which uses `"exception"`, e.g. on 403 Forbidden via
  `ApiResponseWriter.toJSON(Throwable)`) showed up as a generic fallback or
  raw payload rather than the actual error string.
- **Root cause:** the MCP's non-200 extractor only checked the legacy
  `"error"` key. LabKey's framework error envelope uses `"exception"` for
  thrown-exception responses (the canonical envelope on permission denials,
  etc.), and only some custom actions populate `"error"`.
- **Fix:** in both files, the extractor now reads
  `result.get("exception") or result.get("error") or str(result)[:200]`,
  with an `isinstance(result, dict)` guard for safety.

## Verification

Already covered by the shadow test:

- 13/13 read-only nightly MCP tools byte-identical across the three
  shadow-test states (External-only / External+UserSchema / UserSchema-only)
  on a dev box restored from a production DB dump. See
  `TODO-LK-20260425_testresults-schema-shadow-test.md` Phases 1–3.
- Both write tools (`deactivate_computer`, `reactivate_computer`) verified
  against the dev box post-refactor with the fixes applied.

## Notes

- The Spring binding case-sensitivity that surfaced Fix 1 was visible
  because `ViewLogAction` / `ViewXmlAction` previously used
  `request.getParameter("runid")` while every other run-id action in the
  controller already used `runId`. Pre-refactor inconsistency in the
  controller masked the inconsistency in the MCP caller.
