# TODO-LK-20260403_testresults-bugs.md

## Branch
- **Branch**: `26.3_fb_testresults-bug-fixes` (MacCossLabModules)
- **Base**: `release26.3-SNAPSHOT`
- **PR**: [#646](https://github.com/LabKey/MacCossLabModules/pull/646) (open) — "TestResults module bugfixes"
- **Status**: PR #646 open, awaiting review/merge.
- **Related**: container scoping split out to `TODO-LK-20260425_testresults-container-filter.md`.
- **Handoff**: read `.tmp/handoff-20260614_testresults.md` before starting.

## Objective
- Fix bugs in the `testresults` module (the nightly test dashboard on skyline.ms) found while writing Selenium tests.

## Bugs fixed

| Bug | Fix |
|---|---|
| Bad dates were accepted (`13/45/2026` quietly became a valid date) | Parse dates strictly and reject invalid ones |
| Removing a computer's last training run left old stats on the Training Data page | Recompute the computer's stats; remove the row when no training runs remain |
| Deleting a run with handle leaks (or one in the training set) failed | Delete all child rows first, then refresh the computer's training stats |
| Failure chart threw a JavaScript error when there were no dates to plot | Set the chart date range only when dates exist |

## Still to do

| Item | Notes |
|---|---|
| `SendEmailNotificationAction` review | Permission already locked down (PR #622). Confirm nothing calls it, then remove. |

## Tests
- `TestResultsTest`: added a strict-date check, a delete-with-child-rows test, and tightened the training-data test.
- Full class passes (15 of 15).

## Next steps
1. Run `/pw-self-review` on this branch (not yet done), fix anything it finds.
2. Open the PR.
