# TODO-LK-20260425_testresults-container-filter.md

## Branch
- **Branch**: `26.3_fb_testresults-container-filter` (MacCossLabModules)
- **Base**: `release26.3-SNAPSHOT`
- **PR**: [#645](https://github.com/LabKey/MacCossLabModules/pull/645) (open)
- **Status**: Tested green; Copilot review addressed (3 follow-up commits pushed). PR awaiting human review/merge.
- **Related**: split from `TODO-LK-20260403_testresults-bugs.md`.

## Review status (Copilot)
- **#3 null container** -> fixed: `getUsers` throws on null container (commit `d71d8aa`).
- **blank computer name + nullability** -> fixed: `ParseAndStoreXML` rejects a blank `id`; `@NotNull`/`@Nullable` added (commit `fa01688`). From the repo review catalog (fail-fast §13, null-safety §2).
- **#1/#2 `List.getFirst()` JDK compat** -> DECLINED + resolved: repo is Java 25 (`gradle.properties` sourceCompatibility/targetCompatibility=25), so `getFirst()` (Java 21+) is fine. Reply posted on both threads; both resolved.
- Catalog-based review (against `docs/labkey/code-review-feedback-catalog.md`) found no High issues; remaining items (table-name constants §4, test container-path style) deemed optional / house-style.

## What the fix does
Scope the `testresults` tables to the folder being viewed (query-layer only, no DB change). Several
tables have no folder column, so the query browser showed rows from every folder.
- Child tables (`testpasses`, `testfails`, `handleleaks`, `memoryleaks`, `hangs`, `trainruns`): filter
  to the current folder by matching back to `testruns`.
- `user` table: show only computers with a run in the folder. Also fixes the User dropdown and
  Training Data tab, which used to list computers from all folders.
- The folder-scoping rule lives in one place (`TestResultsSchema.createUserTable()` /
  `createRunChildTable()`). `getUsers()` (server-rendered pages) reads the filtered `user` query table
  and layers on per-folder training stats; run ingestion uses `findUserIdByName()` (see below).

## Tests
- `TestResultsTest.testContainerFiltering`: one folder's rows are not visible in another.
- Covered: `testpasses`, `testfails`, `trainruns`, `user` (query API), and the User-page dropdown
  (`getUsers()` path) via `assertUserDropdownContains`.
- **Gap**: `handleleaks`, `memoryleaks`, `hangs` are filtered but not tested. Leaks are easy (existing
  sample file); hangs needs a new sample file.

## Why run ingestion uses a direct lookup (not the filter)
`PostAction` is `@RequiresNoPermission` (SkylineNightly posts anonymously), so the find-or-create
computer lookup runs as guest. It must match a computer by exact name regardless of folder, and a
computer's first post to a folder has no run there yet — so any container filter is wrong (`AllFolders`
matches nothing as guest; `Current` misses the first post). It uses `findUserIdByName()` — a direct,
unscoped `SELECT id FROM testresults.user WHERE username = ?`.
- Context: SkylineNightly posts to a hardcoded `.../home/development/<folder>/post.view`, folder chosen
  by run mode (`Nightly.cs:1015-1031`); the same computer posts to several folders over time, which is
  why `user` has no home container.
- The anonymous endpoint is a separate security gap, tracked in
  `TODO-LK-20260616_authenticate-skylinenightly-post.md`.

## Impact on the LabKey MCP server (`pwiz-ai/mcp/LabKeyMcp`)
The MCP reads these tables through the query API, so it sees the filtering. Tools that join back to
`testruns` (`query_test_runs`, `get_daily_test_summary`, `save_*_history`, `backfill_nightly_history`,
etc.) are unaffected.
- **Narrow risk**: `get_run_failures` (nightly.py:245), `get_run_leaks` (nightly.py:472),
  `save_run_comparison` (nightly.py:1515) look up a child table by run id with no `testruns` join, so
  they return nothing if the run is in a folder other than the one passed (default `Nightly x64`).
  Optional fix: add `container_filter='AllFolders'` (run ids are unique).
- **Computer status is per-folder, and the tools already handle it**: `list_computer_status`,
  `deactivate_computer`, `reactivate_computer` pass the same `container_path` to both the `user`-table
  lookup and the `setUserActive` write, so they resolve and flip the per-folder `userdata.active` flag
  in the folder you target — no change needed. Caveats: the lookup now finds a computer only if it has
  a run in that folder (always true for an active nightly tester, since `testruns` rows are historical);
  and don't pass `AllFolders` to `list_computer_status` (its `userdata` join would duplicate rows).
- **Where it surfaces**: `pw-daily-research` and `pw-daily` are the smoke-test targets (they call
  `list_computer_status` + the by-run-id tools). Only `list_computer_status` is wired into a command;
  `deactivate_computer`/`reactivate_computer` are ad hoc — test directly.

## Next steps
1. PR #645: await human review, then merge. (Shares the test file with the bug-fixes branch;
   whichever merges second needs a keep-both merge of `release26.3-SNAPSHOT`.)
2. Optional: add the `AllFolders` fix to the 3 by-runId MCP tools.
3. Add the missing leak/hang filter tests.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260616_testresults-container-filter.md` before starting work.
