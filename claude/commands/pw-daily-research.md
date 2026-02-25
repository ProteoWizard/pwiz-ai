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

## Phase 1.5: Upgrade Tracked Issues to Fixed

After reading the exception and failure reports, check all "Already Handled" items that show
**"Tracked as GitHub #XXXX"** (not yet recorded as fixed). For each one:

```bash
# Check if the tracking issue is closed
gh issue view XXXX --repo ProteoWizard/pwiz --json state,closedAt --jq '{state, closedAt}'
```

If closed, find the fixing PR:

```bash
# Get timeline events to find the cross-referenced PR that closed it
gh api repos/ProteoWizard/pwiz/issues/XXXX/timeline --paginate \
  --jq '.[] | select(.event == "cross-referenced") | .source.issue.number'
# Then check if that number is a merged PR
gh pr view NNNN --repo ProteoWizard/pwiz --json number,title,state,mergedAt,mergeCommit \
  --jq '{number, state, mergedAt, mergeCommit: .mergeCommit.oid}'
```

If a merged PR is found, record the fix:

```
record_exception_fix(fingerprint="...", pr_number="NNNN", commit="...", merge_date="...")
# or
record_test_fix(test_name="...", fix_type="failure", pr_number="NNNN", ...)
```

**Why this matters**: Without this step, items stay as "Tracked" indefinitely even after the
issue is closed and fixed. The email then says "Tracked in #XXXX" when it should say
"FIXED by PR#NNNN" — a significant difference for the reader.

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
Check both locations (pre- and post-consolidation):
```bash
ls ai/.tmp/suggested-actions-*.md
ls ai/.tmp/daily/*/suggested-actions.md
```

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

**IMPORTANT: Skip already-handled items.** Both the exception report and failures report
separate "Needs Attention" from "Already Handled." Only investigate items in "Needs Attention."
"Already Handled" items have recorded fixes or tracked GitHub issues and need no further work.

#### Exception Work Items

For each exception in the **"Needs Attention"** section of the exception report:

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
  5. If fixed on master, check cherry-pick to release branch:
     gh pr list --state all --base Skyline/skyline_26_1 --search "Cherry pick of #NNNN" --json number,title,state,mergedAt
  6. Write findings to ai/.tmp/suggested-actions-YYYYMMDD.md
- Priority: [HIGH if user provided email, MEDIUM otherwise]
```

**For each exception** — follow the investigation steps from [daily-report-guide.md](../../ai/docs/daily-report-guide.md):
- Get stack trace via `get_exception_details`
- Read the code at the stack trace location
- Use `git blame` to understand context
- Classify: user-actionable (catch + friendly error) vs programming defect (fix the logic)
- **Both categories are bugs that need code changes and GitHub issues.** Never classify an exception as "user-environment / no code change needed." If a team member responded with a workaround, the code should show that same guidance automatically.
- Formulate root cause
- Create GitHub issue

#### Test Failure Work Items

For each test failure in the **"Needs Attention"** section of the failures report:

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

#### Leak and Failure Regression Detection

**Before investigating individual leaks or failures, check for regressions.**

A regression introduced by one commit can cause dozens of tests to fail or leak.
Once the fix merges, machines still running the old code produce **echoes** — failures
or leaks that look new but are just the same regression on pre-fix runs.

For **failures**, echo detection is automatic: the fingerprint system groups by stack
trace, so recording one fix covers all machines.

For **leaks**, there are no fingerprints. Echo detection must be done by **git hash**:
if the leaking runs are on a known regression hash and clean runs exist on the fix hash,
ALL leaks on the regression hash are echoes. Do not investigate or record them individually.

##### Red Flags (any one = probable regression, Priority HIGH)

These apply to both leaks and failures:

1. **More than 2 leaks on any single machine** — normal is 0-2 sporadic.
2. **Same tests affected on multiple machines with the same git hash** — a code change
   is the cause, not machine-specific issues.
3. **Extreme count** — 10+ distinct tests affected at once is never chronic.

##### When Red Flags Are Present

**Step 1 — Check if these are echoes of a known regression.**
Read the previous day's suggested-actions (`ai/.tmp/daily/YYYY-MM-DD/suggested-actions.md`).
If it describes this regression with a fix PR already merged, compare git hashes:
- Leaking runs on the regression hash (or between regression and fix) → echoes
- Clean runs on the fix hash → fix confirmed

If echoes:
```markdown
### REGRESSION ECHOES: [N] leaks across [M] machines — already FIXED
- Regression: PR #NNNN ([causing_hash]) — identified [date]
- Fix: PR #MMMM ([fix_hash]) — merged [date]
- Echoes: [M] machines on [causing_hash] show [N] leaks (pre-fix runs)
- Proof: [K] machines on [fix_hash] show 0 leaks
- Status: Fix confirmed. All future runs expected clean.
- Priority: RESOLVED — do not investigate individual tests
```

**Step 2 — If this is a new regression** (not in previous findings):
```markdown
### LEAK REGRESSION: [N] tests leaking across [M] machines
- Git hash: [hash from nightly report]
- Machines affected: [list]
- Steps:
  1. Compare against previous day: did these tests leak yesterday?
     query_test_runs(days=3, container_path="...")
  2. Check if later runs in today's window are clean (fix already landed?)
  3. Identify the causing commit range:
     git log --oneline <clean_hash>..<leaking_hash>
  4. Find the causing PR:
     gh pr list --state merged --search "merged:YYYY-MM-DD" --limit 20
  5. Focus on PRs touching test infrastructure, IDisposable, static fields,
     or resource management
  6. Write findings to ai/.tmp/suggested-actions-YYYYMMDD.md
- Priority: HIGH — regression drowns out all other signal until fixed
```

##### Chronic Leaks (no red flags)

If leaks are 1-2 per machine, different tests on different machines, and
`query_test_history` confirms they've been present for weeks:

```markdown
### Leak: [test name] on [computer]
- Run ID: [id]
- Steps:
  1. get_run_leaks(run_id=XXXXX)
  2. query_test_history(test_name="TestName") — confirm chronic (30+ days)
  3. Write findings to ai/.tmp/suggested-actions-YYYYMMDD.md
- Priority: LOW (chronic, monitoring)
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
