---
description: Daily report research phase — collect data, investigate, write findings (no email)
---

# Daily Report — Research Phase

Collect data, investigate exceptions/failures/leaks, and write all findings to files.
This is Phase 1 of the two-phase daily report pipeline. **Do NOT send email.**

**Read**: [ai/docs/daily-report-guide.md](../../ai/docs/daily-report-guide.md) for full instructions.

## Arguments

- **Date**: YYYY-MM-DD (optional, defaults to auto-calculated)

## Output

All MCP tools write to `ai/.tmp/` with date-stamped filenames (e.g., `nightly-report-YYYYMMDD.md`).
After this phase completes, `Invoke-DailyReport.ps1` runs a consolidation step that moves these
files into `ai/.tmp/daily/YYYY-MM-DD/` with the date suffix stripped.

The final output is a manifest file: `ai/.tmp/daily-manifest-YYYYMMDD.json`
(consolidated to `ai/.tmp/daily/YYYY-MM-DD/manifest.json`)

---

## Required Reading

Read these documents before starting. They provide the domain knowledge needed to interpret and investigate findings.

1. **[ai/docs/daily-report-guide.md](../../ai/docs/daily-report-guide.md)** — Full workflow, email format, investigation methodology
2. **[ai/docs/release-cycle-guide.md](../../ai/docs/release-cycle-guide.md)** — Current release phase, version numbering, git tags, how to check if a bug is fixed
3. **[ai/docs/debugging-principles.md](../../ai/docs/debugging-principles.md)** — Investigation methodology: reproduce, measure, bisect, isolate
4. **[ai/docs/mcp/exceptions.md](../../ai/docs/mcp/exceptions.md)** — Exception triage tools and workflow
5. **[ai/docs/mcp/nightly-tests.md](../../ai/docs/mcp/nightly-tests.md)** — Nightly test tools, folder structure, anomaly detection
6. **[ai/docs/leak-debugging-guide.md](../../ai/docs/leak-debugging-guide.md)** — Handle/memory leak investigation (read if leaks are found)

---

## Phase 1: Data Collection (Steps 1-5)

**1. Determine Dates**
- Nightly: Today (if after 8 AM) or yesterday
- Exceptions: Yesterday
- Support: 1 day lookback

**2. Load Ignored Computers**
- Read `ai/.tmp/daily/history/computer-status.json`
- Check for due alarms

**3. Read Inbox Emails**
```
search_emails(query="in:inbox from:skyline@proteinms.net newer_than:2d")
```
Read each email with `read_email(messageId)`. Extract TestResults, hang alerts, exception digests.

**Do NOT archive emails** — that happens in the email phase.

**4. Generate MCP Reports (REQUIRED - must succeed)**
```
get_daily_test_summary(report_date="YYYY-MM-DD")
save_exceptions_report(report_date="YYYY-MM-DD")
get_support_summary(days=1)
```

Read generated reports from `ai/.tmp/`:
- `nightly-report-YYYYMMDD.md`
- `exceptions-report-YYYYMMDD.md`
- `support-report-YYYYMMDD.md`

**5. Backfill History Databases**
```
backfill_nightly_history()
backfill_exception_history()
```

---

## Phase 2: Analysis (Steps 6-9)

**6. Fetch Failure Details and Fingerprints**
For each test failure:
```
get_run_failures(run_id, container_path)
```
Also save detailed failures:
```
save_daily_failures(report_date="YYYY-MM-DD")
```

**7. Check Computer Status and Alarms**
```
check_computer_alarms()
list_computer_status(container_path="/home/development/Nightly x64")
```

**8. Analyze Patterns**
```
analyze_daily_patterns(report_date="YYYY-MM-DD", days_back=7)
```

**9. Save Daily Summary JSON**
```
save_daily_summary(report_date, nightly_summary, nightly_failures, ...)
```

---

## Phase 3: Investigation

This is the most valuable phase. Investigate every failure, exception, and anomaly.

**Write findings progressively** to `ai/.tmp/suggested-actions-YYYYMMDD.md` after each investigation. The session may terminate at any moment.

### Cross-Reference First

Before investigating any issue:

**1. Check GitHub issues**
```bash
gh issue list --state all --limit 30 --json number,title,state,createdAt
```

**2. Check past suggested-actions files**
Read recent files (last 3-5 days) to see what was previously identified.

**3. Check exception/test history via MCP**
```
query_test_history(test_name="TestName")
query_exception_history()
```

### Investigation Work Items

Each item below is independent and can be investigated in parallel.
When swarm agents are available, start a swarm assigning one item per agent.
Otherwise, investigate sequentially by priority.

**Build the work item list** from today's data. For each item, follow the structure below.

#### Exception Work Items

For each exception in today's report:

```markdown
### Exception: [fingerprint] - [signature]
- Exception ID: [id]
- Report: exceptions-report-YYYYMMDD.md
- Version: [version] — check code in the relevant pwiz checkout (release branch or master)
- Steps:
  1. get_exception_details(exception_id=XXXXX)
  2. Read code at stack trace location
  3. git blame to understand context
  4. Check if already fixed on master (gh pr list --state merged --search "filename")
  5. Write findings to ai/.tmp/suggested-actions-YYYYMMDD.md
- Priority: [HIGH if user provided email, MEDIUM otherwise]
```

**For each exception** — follow the investigation steps from [daily-report-guide.md](../../ai/docs/daily-report-guide.md):
- Get stack trace via `get_exception_details`
- Read the code at the stack trace location
- Use `git blame` to understand context
- Classify: user-actionable vs programming defect
- Formulate root cause
- Create GitHub issue if warranted

#### Test Failure Work Items

For each test failure:

```markdown
### Test Failure: [test name] on [computer]
- Run ID: [id]
- Container: [path]
- Steps:
  1. get_run_failures(run_id=XXXXX, container_path="...")
  2. Read test file and production code at stack trace
  3. git blame -L for context
  4. query_test_history(test_name="TestName")
  5. Write findings to ai/.tmp/suggested-actions-YYYYMMDD.md
- Priority: [HIGH if NEW/REGRESSION, MEDIUM if RECURRING, LOW if CHRONIC]
```

#### Leak Work Items

For each leak:

```markdown
### Leak: [test name] on [computer]
- Run ID: [id]
- Steps:
  1. get_run_leaks(run_id=XXXXX)
  2. query_test_history(test_name="TestName") — check if chronic
  3. If new leak, read test code to identify resource handling
  4. Write findings to ai/.tmp/suggested-actions-YYYYMMDD.md
- Priority: [HIGH if NEW, LOW if CHRONIC]
```

#### Infrastructure Work Items

For missing computers or crashed runs:

```markdown
### Infrastructure: [computer] missing/crashed
- Steps:
  1. list_computer_status(container_path="...")
  2. For crashed runs: save_run_log(run_id=XXXXX, part="testrunner")
  3. Check if same machine repeatedly (hardware) or same test (test bug)
  4. Write findings to ai/.tmp/suggested-actions-YYYYMMDD.md
- Priority: HIGH
```

### Investigate Each Work Item

Work through all items, writing findings to `ai/.tmp/suggested-actions-YYYYMMDD.md` after each one. Do not accumulate findings in memory.

---

## Phase 4: Write Manifest

After all investigation is complete (or when approaching turn limit), write the manifest:

**File**: `ai/.tmp/daily-manifest-YYYYMMDD.json`

```json
{
  "date": "YYYY-MM-DD",
  "research_completed": true,
  "phases_completed": ["data_collection", "analysis", "investigation"],
  "files": {
    "nightly_report": "ai/.tmp/nightly-report-YYYYMMDD.md",
    "exceptions_report": "ai/.tmp/exceptions-report-YYYYMMDD.md",
    "support_report": "ai/.tmp/support-report-YYYYMMDD.md",
    "daily_failures": "ai/.tmp/failures-YYYYMMDD.md",
    "daily_summary": "ai/.tmp/daily/summaries/daily-summary-YYYYMMDD.json",
    "suggested_actions": "ai/.tmp/suggested-actions-YYYYMMDD.md"
  },
  "summary": {
    "total_runs": 0,
    "failures": 0,
    "leaks": 0,
    "exceptions": 0,
    "exceptions_investigated": 0,
    "issues_created": [],
    "missing_computers": 0
  },
  "investigation_notes": "Brief summary of what was investigated and key findings"
}
```

Fill in actual values from today's data. The `summary` section helps the email phase compose a quick overview without re-reading all files.

If the session is about to hit its turn limit, write the manifest with `research_completed: false` and list only the phases that completed.

---

## Critical Validation

**FAIL the research if:**
- `get_daily_test_summary()` fails or returns zero runs
- Cannot query fresh MCP data

**NEVER use stale data** — cached files are for historical comparison only.

If MCP data is unavailable, write a manifest with `research_completed: false` and a note explaining what failed. The email phase will handle sending an error notification.

## Related

- [ai/docs/daily-report-guide.md](../../ai/docs/daily-report-guide.md) — Full investigation instructions
- [pw-daily-email.md](pw-daily-email.md) — Email phase (reads this output)
- [pw-daily.md](pw-daily.md) — Combined command for interactive use
