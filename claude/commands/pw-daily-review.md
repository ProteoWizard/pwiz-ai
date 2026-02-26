---
description: Review today's daily report findings with a human reviewer
---

# Daily Report — Review Phase

The automated research and email phases have already run. A human reviewer is here
to go through the findings, create GitHub issues, record fixes, and decide next steps.

**Read**: [ai/docs/daily-report-guide.md](../../ai/docs/daily-report-guide.md) §User Review Workflow

## Arguments

- **Date**: YYYY-MM-DD (optional, defaults to auto-calculated)

---

## Step 1: Determine Date and Load Findings

Determine the report date (same logic: before 8 AM → yesterday, after 8 AM → today,
or use provided argument).

**Files are in the consolidated daily folder** (the email phase moves them there):
- `ai/.tmp/daily/YYYY-MM-DD/suggested-actions.md` — Investigation findings (start here)
- `ai/.tmp/daily/YYYY-MM-DD/manifest.json` — Summary stats and file list
- `ai/.tmp/daily/YYYY-MM-DD/nightly-report.md` — Full test results
- `ai/.tmp/daily/YYYY-MM-DD/exceptions-report.md` — Exception details
- `ai/.tmp/daily/YYYY-MM-DD/failures.md` — Failure details with fingerprints

Read `suggested-actions.md` first — this is the primary document for the review.
Read `manifest.json` for the summary stats.

## Step 2: Present Summary

Give the reviewer a concise overview:
- Quick stats (runs, failures, leaks, exceptions)
- Number of items needing attention vs already handled
- Any GitHub issues created during research
- Any fixes recorded during research

## Step 3: Walk Through Action Items

For each item in `suggested-actions.md`:

**GitHub Issues to Create:**
- Present the analysis to the reviewer
- Ask the reviewer who to assign the issue to (common assignees: nickshulman, bspratt, chambm, brendanx67)
- On approval, create the issue with `gh issue create --label bug --label skyline --assignee <handle>`
- Always include both `bug` and `skyline` labels by default
- Record the issue tracking with `record_exception_issue()` or `record_test_issue()`

**Exception Fixes to Record:**
- Verify the fix information is correct
- Call `record_exception_fix()` or `record_test_fix()`

**Items Needing Discussion:**
- Present findings and ask for the reviewer's input
- The reviewer may have context the automated session didn't

## Step 4: Handle Reviewer Requests

The reviewer may ask to:
- **Investigate further** — Drill into a specific failure or exception
- **Create issues** — For items identified during discussion
- **Start implementation** — Use `/pw-startissue` to begin work on an issue
- **Record fixes** — For PRs the reviewer knows about
- **Code review** — Review PRs related to today's findings

## Guidelines

- **Don't re-investigate from scratch.** The research phase already did the work.
  Build on the findings in `suggested-actions.md`.
- **Ask before creating issues.** The reviewer may know context that changes the analysis.
- **Record every fix decision.** If the reviewer says "that's fixed by PR #XXXX",
  call `record_exception_fix()` or `record_test_fix()` before moving on.
- **The reviewer's time is valuable.** Be concise. Lead with the actionable items.

## Related

- [ai/docs/daily-report-guide.md](../../ai/docs/daily-report-guide.md) — Full workflow
- [pw-daily-research.md](pw-daily-research.md) — Research phase
- [pw-daily-email.md](pw-daily-email.md) — Email phase
