# TODO-LK-20260425_testresults-container-filter.md

## Branch
- **Branch**: `26.3_fb_testresults-container-filter` (MacCossLabModules)
- **Base**: `release26.3-SNAPSHOT`
- **Status**: Fix done and tested. PR not opened yet.
- **Related**: split from `TODO-LK-20260403_testresults-bugs.md`.
- **Handoff**: read `.tmp/handoff-20260614_testresults.md` before starting.

## Objective
- Make the `testresults` tables show only the rows for the folder you are viewing.
- Several tables had no folder column, so the query browser showed rows from every folder.
- Query-layer fix only — no database change.

## What the fix does
- Tables with no folder column (`testpasses`, `testfails`, `handleleaks`, `memoryleaks`, `hangs`, `trainruns`): filter to the current folder by matching back to `testruns` (which has the folder).
- `user` table: show only computers that have a run in the folder.
- Also fixes the User dropdown and Training Data tab, which used to list computers from all folders.

## Tests
- `TestResultsTest.testContainerFiltering` checks that one folder's rows are not visible in another.
- Covered: `testpasses`, `testfails`, `trainruns`, `user`.
- **Gap**: `handleleaks`, `memoryleaks`, `hangs` are filtered but not yet tested. Leaks are easy to add (existing leak sample file); hangs needs a new sample file.

## Impact on the LabKey MCP server (`pwiz-ai/mcp/LabKeyMcp`)
The MCP reads these tables through the query API, so it sees the new filtering. The daily report and history backfill are unaffected. 3 tools have a narrow risk; 2 change behavior.

### Unaffected — these join back to `testruns`, so results are unchanged
| Tools | Query |
|---|---|
| `query_test_runs`, `save_run_metrics_csv`, `get_daily_test_summary` | `testruns_detail` |
| daily summary, `save_test_failure_history` | `failures_by_date` |
| daily summary | `leaks_by_date` |
| `save_daily_failures` | `failures_with_traces_by_date` |
| `backfill_nightly_history` | `failures_history`, `leaks_history`, `hangs_history` |
| `save_leakcheck_stats` | `leakcheck_stats` |

### Risk — look up a child table by run id with no join to `testruns`
Returns nothing if the run is in a different folder than the one passed (default `Nightly x64`).
| Tool | File |
|---|---|
| `get_run_failures` | `nightly.py:245` |
| `get_run_leaks` | `nightly.py:472` |
| `save_run_comparison` | `nightly.py:1515` |

Fix: add `container_filter='AllFolders'` to these three. Run ids are unique, so it always finds the run.

### Behavior change — now per-folder (assumed intended; no fix needed)
| Tool | Change |
|---|---|
| `list_computer_status` | Lists only computers with runs in the folder (was: all folders) |
| `_get_user_id`, `deactivate_computer`, `reactivate_computer` | Resolve a computer within the folder |

A computer's active flag is stored per folder (in `userdata`). We are **assuming that is intentional** (not 100% confirmed). Under that assumption these tools are correct as-is: de/activating or listing a computer is a per-folder action, and the lookup succeeds because the computer has runs in the folder you are acting on. Just pass the folder you mean (the MCP defaults to `Nightly x64`).

- No module fix needed for now. Revisit if active is later decided to be per-computer.
- If cross-folder coverage is ever wanted, loop over folders — do not use `AllFolders` here, since `list_computer_status` joins `userdata` (per folder) and would show duplicates.

## Design note: two user-filtering paths (by design, not a bug)
The current-folder filter for computers is enforced in two independent places, because
two different surfaces read the computer list:
- **`getUsers()`** (`TestResultsController.java`) backs the server-rendered pages — the
  user page/dropdown, Training Data tab, and notification email. It returns full computer
  objects with their training stats joined in.
- **The `user` query table** (`TestResultsSchema.createUserTable`) backs the query API:
  the LabKey Schema Browser, any `LABKEY.Query` grid/report, and the LabKey MCP server.
  The dropdown never goes through this path, so it needs its own folder filter.

Both now carry the same "computers that have a run in this folder" rule, written twice, so
they can drift apart if only one is edited. Collapsing them would mean re-driving the
dropdown off the query table, but `getUsers()` also stitches in per-computer training
stats used across the controller and email, so that is a sizable refactor.
**Likely won't be done** — captured here only so it isn't re-discovered and re-litigated.

## Next steps
1. Open the PR. (This branch and the bug-fixes branch touch the same test file, so whichever merges second needs a small keep-both fix — merge `release26.3-SNAPSHOT` in to resolve.)
2. Optional: add the `AllFolders` fix to the 3 MCP tools.
3. Add the missing leak/hang filter tests.
