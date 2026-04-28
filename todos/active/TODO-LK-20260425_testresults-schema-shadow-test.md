# TODO-20260425_testresults-schema-shadow-test.md

## Branch Information
- **Branch**: TBD (test plan, not a code branch)
- **Created**: 2026-04-25
- **Status**: Substantively complete (2026-04-28).
  - Phases 0–3 done.
  - Phase 4 skipped — no usable test server (current test server has an
    outdated DB without the custom queries).
  - Phase 5 cleanup mostly done; findings filed into:
    - `TODO-LK-20260326_testresults-migrate-actions.md` Phase 7 (deployment
      plan)
    - `TODO-20260428_labkey_mcp_shadow-fixes.md` (MCP PR — the 3
      regressions caught here; blocks testresults production deployment)
    - `TODO-20260428_labkey_mcp_dev-target.md` (MCP PR — env-var
      dev-target support; the feature that enabled this shadow test)
  - Schema shadowing verified working in all three tested states.
  - 13/13 read-only smoke tools byte-identical across phases.
  - 2/2 write tools work post-refactor (after MCP-side fixes).
  - 3 MCP-side regressions caught and fixed.
  - 1 deployment-plan finding: enable `TestResults` module in
    `/home/development`.
- **Related PRs**:
  - Refactor (UserSchema registration): [#622](https://github.com/LabKey/MacCossLabModules/pull/622)
  - Container filtering: separate PR (out of scope here)

## Objective

- Verify that registering `testresults` as a UserSchema correctly shadows the
  existing External Schema with the same name.
- Verify that custom queries authored against the External Schema continue to
  resolve under the UserSchema.
- The MCP nightly tools must keep working through the transition.
- Phases 0–3 test shadowing on a dev machine seeded from a real production DB
  dump; Phase 4 is a follow-up against the actual deployed test-server build.

## Out of Scope

- Container filter overrides on `testresults` child tables — branch
  `26.3_fb_testresults-container-filter`, separate PR.
- Issues / wiki / support / announcement schemas — only `testresults` is
  affected by the UserSchema registration.

## Reference

- `todos/active/TODO-LK-20260326_testresults-migrate-actions.md` — refactor
  TODO, Phase 7.
- `mcp/LabKeyMcp/queries/nightly/*.sql` — saved-query source of truth.
- `mcp/LabKeyMcp/queries/README.md` — table mapping queries to MCP tools.

## Phase 0: Dev Machine Setup

- [x] Provision a local LabKey instance with the same module set as production
  (release-branch checkout running on `localhost:8080`).
- [x] Restore production DB dump into local PostgreSQL
  (`labkey-test-results` DB) using a filtered TOC. Skipped data for
  `testresults.testpasses` and `core.documents`; restored DB ~13 GB. See
  "Notes" for the command.
- [x] Log into the local LK UI with the production password (restored
  `core.logins` has production hashes); reset to a known dev password and
  changed site look-and-feel so dev is visually distinct.
- [x] Point the MCP at the dev box via env vars, then **fully restart Claude
  Code** — `/mcp` reconnect alone re-spawns with the cached launch config.
  Verified via `current_target` MCP tool.

  ```bash
  # Switch to dev
  claude mcp remove labkey -s local
  claude mcp add labkey -e LABKEY_SERVER=localhost:8080 -e LABKEY_USE_SSL=false \
    -- python C:/Users/vsharma/WORK/pwiz-ai/mcp/LabKeyMcp/server.py

  # Switch back to production
  claude mcp remove labkey -s local
  claude mcp add labkey \
    -- python C:/Users/vsharma/WORK/pwiz-ai/mcp/LabKeyMcp/server.py
  ```

  - Forward slashes in the `server.py` path — Git Bash mangles backslashes.
  - Restart Claude Code after either form; `/mcp` reconnect alone is not enough.
- [x] Add a `machine localhost` entry to `~/_netrc` with the same
  `<claude-user>@uw.edu` credentials as the production entry. Port is
  stripped before netrc lookup, so `localhost` (not `localhost:8080`).
- [x] No new account or container creation needed — both came in via the
  restore.

## Phase 1: Baseline — External Schema Only (pre-refactor)

The restored DB already contains the External Schema and all 14 saved
queries (the 4 MCP-critical ones are what the smoke tests exercise), so
the only active work is deploying the pre-refactor code and capturing the
baseline MCP output.

- [x] Check out a commit prior to the testresults UserSchema registration;
  deploy.
- [x] Confirm Schema Browser shows `testresults` as External in
  `/home/development/Nightly x64` and lists the four MCP-critical queries.
- [x] Smoke-test the MCP tools that hit testresults schema or module actions;
  output saved to `ai/.tmp/shadow-test-baseline.md`.

  **Read-only (testresults schema or module actions):**
  - [x] `query_test_runs` — `testruns_detail`
  - [x] `get_run_failures` — `testresults.testfails`
  - [x] `get_run_leaks` — `testresults.memoryleaks`, `handleleaks`
  - [x] `get_run_toolsets` — `testresults.testruns`
  - [x] `get_daily_test_summary` — `testruns_detail`, `expected_computers`,
    `failures_by_date`, `leaks_by_date`
  - [x] `list_computer_status` — `all_computers`
  - [x] `save_run_log` — `testresults-viewLog.view`
  - [x] `save_run_xml` — `testresults-viewXml.view` (returns `[nightly: null]`;
    pre-existing `ParseAndStoreXML` bug, not a tool failure)
  - [x] `save_run_metrics_csv` — `testruns_detail`
  - [x] `save_test_failure_history` — `failures_by_date`, direct `testfails`
    reads
  - [x] `save_test_leak_history` — `leaks_history`
  - [x] `save_daily_failures` — `failures_with_traces_by_date`
  - [x] `backfill_nightly_history` — `failures_history`, `leaks_history`,
    `hangs_history` (reports 4-of-6 folders queried; watch in Phase 2)

  **Write tools — deferred to Phase 2** (no pre-refactor baseline):
  - `deactivate_computer`, `reactivate_computer` call
    `testresults-setUserActive.view`, refactored to Spring binding in PR #622.

  **Excluded — needs `testresults.testpasses` data (skipped in restore):**
  - `save_run_comparison` (uses `compare_run_timings`)
  - `save_leakcheck_stats` (uses `leakcheck_stats`)

  **Excluded — local-file only, doesn't hit testresults:**
  - `check_computer_alarms`, `analyze_daily_patterns`, `query_test_history`,
    `record_test_fix`, `record_test_issue`, `save_daily_summary`

## Phase 2: Shadow — External + User Schema Coexist

- [x] Check out the refactor branch's schema-registration commit; deploy.
- [x] **Do NOT delete the External Schema yet** — both must coexist.
- [x] Re-run the Phase 1 read-only smoke tests; results must match the baseline.
  - 13/13 byte-identical to Phase 1 (after fix below).
  - For `save_run_xml`, expect the same `[nightly: null]` output on existing
    runs — the refactor fixes saving new XMLs, not historical rows.
  - **Regression found and fixed:** `save_run_log` and `save_run_xml`
    initially returned `{ }` (empty JSON).
    - Root cause: refactor switched `ViewLogAction`/`ViewXmlAction` to
      `RunIdForm.setRunId` (camelCase); MCP was sending `?runid=` (lowercase);
      Spring binding is case-sensitive → form null →
      `ApiSimpleResponse("log", null)` → `{ }`.
    - Fix: updated MCP to send `?runId=` in `tools/nightly.py` (3 occurrences).
    - JSPs were already updated as part of the original refactor; the MCP
      was the only remaining caller.
- [x] Test the two write tools (no pre-refactor baseline):
  - [x] `deactivate_computer("BOSS-PC")` → 50 active / 3 inactive, BOSS-PC
    listed under INACTIVE with reason+date annotation.
  - [x] `reactivate_computer("BOSS-PC")` → back to 51 active / 2 inactive,
    net-zero state change.
  - **Two regressions found and fixed:**
    1. `SetUserActive` ignored URL params under JSON content-type.
       - With `Content-Type: application/json`, `BaseApiAction.populateForm()`
         reads only the JSON body and ignores URL query params.
       - MCP was sending `?userId=99&active=false` with `{}` body → form
         null → `{"Message": "userId is required"}` with HTTP 200.
       - Fix: `_set_computer_active` now sends `userId`/`active` in the
         JSON body.
    2. MCP collapsed in-action failures into success.
       - Action returns HTTP 200 with error in `Message`; MCP only checked
         status code.
       - Fix: `_set_computer_active` now requires `Message == "Success"`.
       - Verified by `deactivate_computer("AEROWORK")` correctly reporting
         `User not found id=100` (AEROWORK has no userdata row in
         Nightly x64).
  - Also surfaced (and fixed alongside): non-200 error extraction in
    `computers.py` and `wiki.py` was reading the legacy `error` key and
    missing LabKey's framework `exception` envelope. Tracked in
    `TODO-20260428_labkey_mcp_shadow-fixes.md` Fix 3.
- [x] Schema Browser shows the testresults saved custom queries; the 4
  MCP-critical ones verified as visible:
  - `testruns_detail`, `expected_computers`, `failures_by_date`,
    `leaks_by_date` all visible in the tree.
  - `testruns_detail` "View Data" prompts for `StartDate`/`EndDate`
    (resolves correctly).
  - Only one `testresults` entry in the schema list — UserSchema cleanly
    shadows External.

## Phase 3: User Schema Only

- [x] Delete the External Schema via Admin → Schema Administration →
  testresults → DELETE.
  - Delete had to be done in `/home/development` AND each of the 6
    sub-folders (7 total per `query.externalschema`).
  - Delete does not propagate from the parent.
- [x] **Deployment prerequisite:** enable the `TestResults` module in
  `/home/development` before/after deleting the External Schema there.
  - Saved queries are stored in `query.querydef` with
    `container = /home/development`; sub-folders see them via inheritance.
  - Read paths (the MCP) work either way — LabKey resolves the schema in
    the leaf-folder context where the module IS enabled.
  - But the saved-query authoring/editing UI (Schema Browser
    Jump-to-Definition, query create/edit pages) operates in
    `/home/development` where the queries actually live. Without the
    `TestResults` module enabled there, the parent has no `testresults`
    UserSchema → "Missing Schema" in those UIs, blocking edits.
  - **That's why the module must be enabled in `/home/development`** even
    though the MCP nightly flow doesn't require it.
  - Captured in `TODO-LK-20260326_testresults-migrate-actions.md` Phase 7.
- [x] Re-run the MCP smoke tests; results must match Phase 1.
  - Byte-identical: all 13 read-only tools match `phase1-baseline/` exactly.
  - Only `nightly-history.json` differs by `_last_updated` /
    `_backfill_date` (same date drift as Phase 2).
  - Snapshot in `ai/.tmp/phase3-baseline/`.
- [x] **Authoring control test** (deferred from Phase 2): user authored a
  new saved query under `testresults` in `/home/development` with
  "Available in child folders = Yes", verified it appears in sub-folders.
  Proves saved-query authoring + child inheritance work under
  UserSchema-only state.
- [ ] Optional cleanup: delete the user-authored test query if no longer
  needed. Not blocking.

## Phase 4: Real-Data Verification on Test Server

Reduced in scope — Phases 0–3 already exercise real production-shape data on
the dev box. This phase validates that the deployed test-server build
behaves the same.

- [ ] Confirm `<claude-user>@uw.edu` authenticates against the test server.
- [ ] Recreate the 4 MCP-critical saved queries on the test server (the
  test server's 2025-12-01 production sync predates them).
- [ ] Run the MCP smoke tests against dates with data (try `2025-12-01` and
  earlier).
- [ ] Diff against the dev-machine baseline.

## Phase 5: Cleanup and Findings

- [x] File any regressions under `TODO-LK-20260403_testresults-bugs.md`.
  - No new testresults *module* bugs surfaced; the pre-existing
    `ParseAndStoreXML` bug is fixed by the refactor PR.
  - All findings were MCP-side or LabKey-framework behavior — captured below.
- [x] MCP-side issues for follow-up:
  - Auth failures masked as permission errors on saved-query reads
    (Guest-fallback path).
  - `get_daily_test_summary` masking 401/404 as "0 runs".
  - Counter-example: `SetUserActive` correctly returns HTTP 403 with the
    framework `exception` envelope — the auth-masking issue is specifically
    about the saved-query read path.
- [x] Update Phase 7 of `TODO-LK-20260326_testresults-migrate-actions.md`
  with the outcome.
  - Added: shadow-test summary, deployment step to enable the `TestResults`
    module in `/home/development`, the per-container External Schema delete
    requirement, pointer to `TODO-20260428_labkey_mcp_shadow-fixes.md`
    (regression PR) and `TODO-20260428_labkey_mcp_dev-target.md` (feature PR).
- [ ] **Deferred per user:** tear down the dev instance and switch the
  labkey MCP back to production. Action item for whoever closes this TODO,
  once `TODO-20260428_labkey_mcp_shadow-fixes.md` is merged.

## Notes

- Saved queries live in `query.QueryDef` keyed by
  `(container, schema_name, query_name)`. The shadow question: does LabKey
  resolve them by schema *name* (port for free) or by schema *identity*
  (lost on registration)? Phase 2 is the empirical answer.
- The MCP picks its target from `LABKEY_SERVER` / `LABKEY_USE_SSL` env vars
  (set in `claude mcp add`; see `mcp/LabKeyMcp/README.md`). Auth via
  `~/.netrc` / `~/_netrc`; the `machine` line must match `LABKEY_SERVER`.
- **Claude Code MCP launch-config caching gotcha:** Claude Code stores the
  MCP launch parameters at session start. After `claude mcp add` with new
  env vars, `/mcp` reconnect re-spawns using the cached parameters. New env
  vars only take effect after a full Claude Code restart. Verify with
  `current_target`.

### DB restore command (for reference / re-running)

The dump was 31.6 GB. Filtered TOC excludes data for the two largest tables
(MCP shadow-test queries don't read them):

| Table | On-disk size | Why skip data |
|---|---|---|
| `testresults.testpasses` | 110 GB | 700M+ rows; not read by any MCP shadow-test query |
| `core.documents` | 11 GB | ~99.9% TOAST (attachment blobs); not in the shadow-test path |

```bash
PGBIN='/c/Program Files/PostgreSQL/18/bin'
DUMP='/c/Users/vsharma/WORK/labkey/skyline-labkey-db_20260427.dump'
TOC='/c/Users/vsharma/WORK/pwiz-ai/ai/.tmp/restore-list.txt'

"$PGBIN/pg_restore" -l "$DUMP" \
    | grep -vE 'TABLE DATA testresults testpasses|TABLE DATA core documents' \
    > "$TOC"

PGPASSWORD=postgres "$PGBIN/dropdb"   -h localhost -U postgres "labkey-test-results"
PGPASSWORD=postgres "$PGBIN/createdb" -h localhost -U postgres -E UTF-8 "labkey-test-results"
PGPASSWORD=postgres "$PGBIN/pg_restore" -h localhost -U postgres -d "labkey-test-results" \
    -j 4 --verbose -L "$TOC" "$DUMP"
```

- Restore took ~6 min on this machine.
- The 530 "role 'labkey' does not exist" errors are cosmetic — objects all
  get created and end up owned by `postgres`.

### Harmless-but-loud LK startup errors after restore

- `Encryption: Encryption key test failed` / `AEADBadTagException: Tag mismatch`
  — encrypted properties were encrypted with production's
  `context.encryptionKey`; dev has the default key. None of the shadow-test
  path uses encrypted properties.
- `FileContentServiceImpl: site-wide file root \data\labkey\files does not
  exist. Falling back to ...` — production's site-wide file root path doesn't
  exist on dev; LK already fell back to a working dev path.


## Follow-ups (not blocking)

- [ ] **Wrapper scripts for MCP target switching.**
  - Each switch between dev and production currently requires
    `claude mcp remove labkey -s local` +
    `claude mcp add labkey [-e ...] -- python <path>/server.py` + `/mcp`
    reconnect.
  - Wrap the remove+add pair in `mcp-labkey-dev.cmd` /
    `mcp-labkey-production.cmd` (or a single
    `mcp-labkey-switch.ps1 dev|production`) so the only manual step is the
    reconnect.
  - Considered a runtime `switch_target` MCP tool but rejected — it would
    mutate session state and reintroduce silent-production-vs-dev confusion.
