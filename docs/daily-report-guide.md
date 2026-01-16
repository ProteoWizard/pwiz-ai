# Daily Report Guide

Comprehensive guide for generating daily consolidated reports covering nightly tests, exceptions, and support activity.

## Overview

The daily report consolidates three data sources:
1. **Nightly test results** - All 6 test folders (Nightly x64, Release Branch, etc.)
2. **User-submitted exceptions** - Crash reports from skyline.ms
3. **Support board activity** - Unanswered threads needing attention

## Session Goals

The daily report session should:

1. **Send the email** — The minimum viable output (Phase 1-2)
2. **Investigate everything** — Explore all failures and exceptions (Phase 3)
3. **Document findings** — Write to `suggested-actions-YYYYMMDD.md`

**There is no "quick mode".** Every session should investigate as much as possible. The email is just the checkpoint — the real value is the exploration phase.

### What "Done" Looks Like

A session ends when it hits the turn limit or runs out of things to investigate. A thorough session will have:
- Investigated every test failure (checked history, searched PRs)
- Investigated every exception (checked versions, searched for fixes)
- Investigated every crashed/short run (pulled logs, identified cause)
- Documented findings progressively in `suggested-actions-YYYYMMDD.md`

The session should NOT end with a "wrap-up" step — it should be cut off mid-investigation.

---

## Data Sources

This report uses **two complementary data sources**:

### 1. Inbox Emails (Primary for Summary Statistics)

| Email Type | Subject Pattern | Content |
|------------|-----------------|---------|
| TestResults | `TestResults MM/DD - MM/DD ...` | Nightly test summary (8:00 AM) |
| Hang Alert | `[COMPUTER (branch)] !!! TestResults alert` | Log frozen >1 hour |
| Exceptions | `New posts to /home/issues/exceptions` | Exception digest (12:00 AM) |
| Support | Contains support board references | Support digest (if activity) |

### 2. LabKey MCP (Detailed Drill-Down)

| Tool | Purpose |
|------|---------|
| `get_daily_test_summary()` | Detailed per-run data |
| `save_exceptions_report()` | Full stack traces |
| `get_support_summary()` | Support thread details |

---

## Data Validation Requirements

**This report MUST fail if required data cannot be obtained. NEVER substitute stale data.**

### Required Data (MUST have - fail if missing)

| Data Source | Required? | Failure Action |
|-------------|-----------|----------------|
| Nightly test data (MCP) | **YES** | FAIL the report - do not send email |
| Fresh MCP query results | **YES** | FAIL - never use cached files from prior days |

### Optional Data (zero is valid)

| Data Source | Zero Valid? | Notes |
|-------------|-------------|-------|
| Exceptions | Yes (rare) | No exceptions some days is possible |
| Support threads | Yes (common) | No new threads is normal |

### Validation Rules

1. **Nightly tests**: The MCP call `get_daily_test_summary()` MUST succeed and return runs for today's date
   - If MCP call fails: FAIL the report
   - If MCP returns zero runs for today: FAIL (indicates either no tests ran or MCP permission issues)

2. **Never use stale data**: If you cannot query fresh data from MCP:
   - Do NOT fall back to reading old `nightly-report-*.md` files from prior days
   - Do NOT use `daily-summary-*.json` files as the primary data source
   - These files are for historical comparison ONLY, not substitutes for today's data

3. **Failure notification**: If the report cannot complete due to missing data:
   - Send an ERROR email with subject: `[ERROR] Skyline Daily Summary - Month DD, YYYY - Data Unavailable`
   - Body should explain: which data source failed, likely cause (MCP permissions?), how to fix
   - Exit with non-zero status so the scheduled task shows as failed

---

## Ignored Computers

Some computers may be temporarily or permanently removed from the test pool (hardware failure, RMA, repurposing). These should be ignored in daily reports to avoid noise.

### Configuration File

**Location**: `ai/.tmp/history/computer-status.json`

```json
{
  "_schema_version": 1,
  "_last_updated": "2026-01-14",
  "ignored_computers": {
    "COMPUTER-NAME": {
      "reason": "Why this computer is ignored",
      "ignored_since": "2026-01-14",
      "alarm_date": "2026-02-14",
      "alarm_note": "Reminder text when alarm is due"
    }
  }
}
```

### Fields

| Field | Required | Description |
|-------|----------|-------------|
| `reason` | Yes | Why the computer is being ignored |
| `ignored_since` | Yes | Date when ignore started (YYYY-MM-DD) |
| `alarm_date` | No | Date to remind about this computer (YYYY-MM-DD) |
| `alarm_note` | No | Text to show when alarm is due |

### Report Behavior

When a computer is in `ignored_computers`:

1. **Missing computers**: Do not include in "Missing" count or warnings
2. **Failures/leaks**: Still collect data but filter from "Key Findings"
3. **Alarms**: Check `alarm_date` at report start; if due/overdue, include reminder in email
4. **Historical data**: Continue saving to daily-summary JSON for historical record

### Managing Ignored Computers

**To ignore a computer**: Add entry to `computer-status.json` with reason and optional alarm

**To restore a computer**: Remove entry from `ignored_computers` object

**To update alarm**: Edit the `alarm_date` and `alarm_note` fields

---

## Default Date Logic

Each report type has different day boundaries:

| Report | Window | Default Date |
|--------|--------|--------------|
| Nightly | 8:01 AM to 8:00 AM next day | Today (if after 8 AM) or yesterday |
| Exceptions | 12:00 AM to 11:59 PM | Yesterday (complete 24h) |
| Support | Last N days | 1 day |

---

## Step-by-Step Instructions

The daily report has **three phases**:
1. **Data Collection** (Steps 1-4) — Gather all data from MCP and email
2. **Analysis & Email** (Steps 5-9) — Analyze, send email, archive
3. **Exploration** (no steps - keep going) — **MANDATORY** investigation until turn limit

⚠️ **DO NOT END SESSION after sending email.** The exploration phase is the most valuable part. Keep investigating until you run out of things to look at or hit the turn limit.

---

### Phase 1: Data Collection

### Step 1: Determine Dates

If user provided a date argument, use it for all reports.

If no date provided, calculate defaults:
- For nightly: Current time before 8 AM -> yesterday's date; after 8 AM -> today's date
- For exceptions: Yesterday's date
- For support: 1 day lookback

### Step 2: Load Ignored Computers

Read `ai/.tmp/history/computer-status.json` to get the list of ignored computers.

```python
# Pseudocode
ignored_computers = load_json("ai/.tmp/history/computer-status.json")["ignored_computers"]
# Check for due alarms
for computer, config in ignored_computers.items():
    if config.get("alarm_date") and config["alarm_date"] <= today:
        due_alarms.append((computer, config["alarm_note"]))
```

If file doesn't exist, proceed with empty ignored list.

### Step 3: Read Inbox Emails

Search the Gmail inbox for today's notification emails:

```
search_emails(query="in:inbox from:skyline@proteinms.net newer_than:2d")
```

For each email found, use `read_email(messageId)` to get full content.

**From TestResults email, extract:**
- Subject line summary: Err/Warn/Pass/Missing counts, total tests
- Per-computer table with: Computer, Memory, Tests, PostTime, Duration, Failures, Leaks, Git hash
- Failure/Leak/Hang matrix showing which tests failed on which computers
- "(hang)" notation in Duration column
- Missing computers list

**Color coding meanings** (see ai/docs/mcp/nightly-tests.md for details):
- Green (#caff95): All metrics normal
- Yellow (#ffffca): 3-4 SDs from trained mean
- Red (#ffcaca): Failures/leaks/hangs OR >4 SDs from mean
- Gray (#cccccc): Unexpected computer reported

**From Hang alert emails, extract:**
- Computer name and branch from subject
- Timestamp of the alert
- End of log showing last test before hang

**From Exceptions email, extract:**
- Each exception entry with location, version, Installation ID, timestamp, stack trace
- Group by Installation ID (same user hitting repeatedly vs different users)

### Step 4: Generate MCP Reports

Run these three MCP calls:

```
get_daily_test_summary(report_date="YYYY-MM-DD")
save_exceptions_report(report_date="YYYY-MM-DD")
get_support_summary(days=1)
```

**Validate each call succeeded** - see Data Validation Requirements above.

Read generated reports from `ai/.tmp/`:
- `nightly-report-YYYYMMDD.md`
- `exceptions-report-YYYYMMDD.md`
- `support-report-YYYYMMDD.md`

---

### Phase 2: Analysis & Email

### Step 5: Fetch Failure Details and Fingerprints

For each test failure, fetch detailed stack trace:

```
get_run_failures(run_id, container_path)
```

Extract: exception type, message, location, fingerprint.

**Build failure URLs** using pattern:
```
https://skyline.ms/home/development/{folder}/testresults-showFailures.view?end={MM}%2F{DD}%2F{YYYY}&failedTest={TestName}
```

### Step 6: Check Computer Status and Alarms

Check both MCP alarms and local ignored computer alarms:

```
# MCP alarms (if available)
check_computer_alarms()

# Local alarms from Step 2
for computer, note in due_alarms:
    # Include in email: "Reminder: {computer} - {note}"
```

For missing computers, filter out ignored computers before reporting:
```python
missing = [c for c in mcp_missing if c not in ignored_computers]
```

For failures/leaks, filter out ignored computers from Key Findings:
```python
key_failures = {test: computers for test, computers in failures.items()
                if any(c not in ignored_computers for c in computers)}
```

### Step 7: Analyze Patterns

**First, check release cycle context** by reading `ai/docs/release-cycle-guide.md`:
- If FEATURE COMPLETE, both master and release branch run nightly tests
- Early after branch creation, same failure on both = single issue, not "systemic"

Use the pattern analysis tool:

```
analyze_daily_patterns(report_date="YYYY-MM-DD", days_back=7)
```

This detects:
- **NEW**: First time ever in history
- **SYSTEMIC**: Affects 3+ machines
- **RECURRING**: Seen before, returned after absence
- **REGRESSION**: Failing again after recorded fix
- **CHRONIC**: Intermittent spanning 30+ days
- **EXTERNAL**: Involves external service (Koina, Panorama)

### Step 8: Save Daily Summary JSON

```
save_daily_summary(
    report_date="YYYY-MM-DD",
    nightly_summary='{"errors": N, "warnings": N, "passed": N, "missing": N, "total_tests": N}',
    nightly_failures='{"TestName": {"computers": ["COMPUTER1"], "fingerprint": "abc123...", "exception_type": "...", "exception_brief": "...", "location": "File.cs:123"}}',
    nightly_leaks='{"TestName": ["COMPUTER1"]}',
    nightly_hangs='{"TestName": ["COMPUTER1"]}',
    missing_computers='["COMPUTER1", "COMPUTER2"]',
    exception_count=N,
    exception_signatures='{"ExceptionType at File.cs:line": {"count": N, "installation_ids": ["id1"]}}',
    support_threads=N
)
```

### Step 9: Archive Processed Emails

```
batch_modify_emails(messageIds=[...], removeLabelIds=["INBOX"])
```

---

### Phase 3: Exploration (MANDATORY)

⚠️ **DO NOT END SESSION AFTER EMAIL.** Keep investigating until you run out of things to look at or hit the turn limit. This is where the automated session provides real value.

**Write findings progressively** to `ai/.tmp/suggested-actions-YYYYMMDD.md` after **each** investigation. The session may terminate at any moment — never accumulate findings in memory.

### Investigate Test Failures

For **each test failure** with a stack trace:

**A. Get the failure details**
```
get_run_failures(run_id=XXXXX, container_path="...")
```

**B. Read the code** — Start at the stack trace

- Read the test file to understand what it's testing
- Read the production code where the exception was thrown
- Understand what the test expected vs what happened

**C. Git blame to find context**
```bash
git blame -L 100,120 pwiz_tools/path/to/TestFile.cs
git log --oneline -10 -- "**/TestName*"
```

**D. Check failure history**
```
query_test_history(test_name="TestName")
```
- Is this NEW (first time ever)?
- Is this RECURRING (seen before, came back)?
- When did it start failing? (correlate with git log)

**E. For crashed/short runs, get the log**
```
save_run_log(run_id=XXXXX, part="testrunner")
# Read the last 100 lines to see what crashed
```

**F. Questions to answer:**
- Is there a merged PR that might have caused this? (regression)
- Is there a merged PR that might have fixed this? (stale echo)
- Is it machine-specific? (hardware/config issue)
- Is it time-specific? (intermittent/flaky)

**→ Write findings to `suggested-actions-YYYYMMDD.md` immediately**

### Investigate Exceptions

For **each exception** with a stack trace (user-reported or nightly test failure):

#### Exception Classification

**Important**: Every exception that reaches the exception reporting form is a bug. There are no "user errors" in exception reports.

If an exception appears to be caused by user action (missing file, network unavailable), it is **still a bug** because:
1. The application failed to show a friendly error message to the user
2. Instead, the user saw the exception reporting form (which they may perceive as a "crash")
3. The application should have caught the exception and displayed helpful guidance

**User-actionable exceptions** (should be caught and shown as friendly error):
- `FileNotFoundException` for a template file → Should show: "Template file not found. Please select a valid file."
- `IOException` for network path unavailable → Should show: "Cannot access network location. Check your connection."

**Programming defects** (code bug to fix, not catch-and-display):
- `ArgumentException`, `ArgumentOutOfRangeException` → Usually means calling code passed invalid value
- `NullReferenceException`, `IndexOutOfBoundsException` → Code logic error
- These require fixing the code that produced the invalid state, not adding error handling

**The fix pattern for user-actionable exceptions** (from PR#3812):
```csharp
try
{
    // Operation that might fail due to external factors (file, network, etc.)
}
catch (Exception ex)
{
    ExceptionUtil.DisplayOrReportException(this, ex,
        Resources.FriendlyErrorMessage_OperationFailed);
}
```

This shows a friendly error for expected failures while still reporting unexpected exceptions.

**A. Get the stack trace**
```
get_exception_details(exception_id=XXXXX)
```

**B. Read the code** — This is what developers do first. Always.

Start at the top of the stack trace and read:
```bash
# Read the file where exception was thrown
# Read the method, understand what it's trying to do
# Read the exception class definition
# Read nearby catch blocks that should have handled it
```

**C. Use git blame to understand context**
```bash
# Who touched this code recently? When?
git blame -L 250,270 pwiz_tools/path/to/File.cs
git log --oneline -10 -- pwiz_tools/path/to/File.cs
```

This often leads to:
- A TODO file for work in progress
- A recent PR that introduced/fixed something
- The developer who knows this area

**D. Follow the trail**
```bash
# If git blame shows recent work, find the TODO or PR
grep -r "SomeFile.cs\|SomeException" ai/todos/
gh pr list --state merged --search "filename:SomeFile.cs" --limit 10
```

**E. Check version distribution** (helps prioritize)
- Only in old versions? → Likely already fixed
- Only in newest version? → Recent regression
- Across many versions? → Long-standing bug

**F. Formulate root cause**

Not just "what failed" but "why":
- Why wasn't this caught by existing error handling?
- Are there similar exceptions that ARE handled correctly?
- What pattern was used elsewhere that should apply here?

**G. Draft a GitHub issue** if this is a real bug:
- Clear title
- Stack trace from exception report
- Root cause analysis (the WHY)
- Suggested fix with specific file/line references

**→ Write findings to `suggested-actions-YYYYMMDD.md` immediately**

#### Example: Good Exception Investigation

```markdown
## Exception: PanoramaImportErrorException (#73737)

**Stack trace points to:** PanoramaClient.cs:262, PanoramaPublishUtil.cs:313

**Code reading revealed:**
- `PanoramaImportErrorException` inherits from `Exception` (line 580)
- `ExceptionUtil.IsProgrammingDefect()` only recognizes `IOException` as user-actionable
- Catch block at PanoramaPublishUtil.cs:329 checks `IsProgrammingDefect` BEFORE
  checking for `PanoramaImportErrorException`

**Git blame showed:** PanoramaUtil.cs recently modified by PR #3658

**Following the trail:** PR #3658 fixed `PanoramaServerException` the same way
(changed it to inherit from `IOException`), but missed `PanoramaImportErrorException`

**Root cause:** `PanoramaImportErrorException` should inherit from `IOException`
like `PanoramaServerException` does, so it's recognized as user-actionable.

**Suggested fix:** Create `PanoramaException : IOException` base class

**Action:** Create GitHub issue with root cause and suggested fix
```

### Investigate Infrastructure Issues

For **missing computers** or **crashed runs**:

**A. Check computer status**
```
list_computer_status(container_path="/home/development/Nightly x64")
```

**B. For crashed runs, analyze the pattern**
- Same machine repeatedly? → Hardware issue
- Same test causing crash? → Test bug
- Same time of day? → External interference

**→ Write findings to `suggested-actions-YYYYMMDD.md` immediately**

---

## Email Format

**Use HTML formatting, not Markdown.** Gmail does not render Markdown.

```
draft_email(
    ...
    body="Plain text fallback",
    htmlBody="<p>HTML formatted version</p>",
    mimeType="multipart/alternative"
)
```

**Subject**: `Skyline Daily Summary - Month DD, YYYY`

### Section Order

The email has 3 major sections in this order (shortest/most urgent first):

1. **Support Board** - Real users waiting for answers (highest priority)
2. **Exceptions** - Bugs impacting real users
3. **Nightly Testing** - Longest section, includes failures, leaks, and infrastructure

### Email Structure

```
## Summary
[AI analysis of what's most important - patterns, action items, context]

## Quick Status
- Support: X threads needing attention
- Exceptions: X new (Y already fixed, Z users affected)
- Nightly: Err: X | Warn: X | Pass: X | Missing: X | N tests

[Ignored computers note if any - yellow banner]

## Support Board
[Threads needing response, with linked titles]

## Exceptions
[Table: Issue (linked), Location, Version, Status]

## Nightly Testing
### Test Failures (N)
[Table: Test (linked), Computer, Issue]

### Leaks (N)
[Table: Test (linked), Computer, Type]

### Missing Computers
[List by folder]
```

### Summary Section Guidelines

The Summary section provides AI analysis of the day's data. Include:

1. **Infrastructure issues** - Ignored computers, crashed runs, missing machines
2. **Patterns** - Multiple failures on same machine, related leaks, systemic issues
3. **Action items** - Things that need human intervention (corrupt files, re-downloads)
4. **Context** - Already-fixed exceptions, stale echoes from old commits
5. **Priorities** - What should a developer look at first?

Example:
```html
<div class="summary-box">
<p><strong>Infrastructure:</strong> Two machines returning to Dell (i9-14800 damage).</p>
<p><strong>BRENDANX-UW7:</strong> 3 failures today — may indicate machine-specific issues.</p>
<p><strong>Action needed:</strong> WatersIMSImportTest needs zip file re-downloaded.</p>
<p><strong>Already fixed:</strong> GetMedianPeak NullRef fixed by PR#3785.</p>
</div>
```

### Required Links

**Link test names directly** - no separate "View" column:
```html
<td><a href="https://skyline.ms/home/development/{FOLDER}/testresults-showFailures.view?end={MM}%2F{DD}%2F{YYYY}&failedTest={TEST_NAME}">{TEST_NAME}</a></td>
```
Where FOLDER is URL-encoded (e.g., `Nightly%20x64`, `Performance%20Tests`).

The linked page has radio buttons for Failures/Leaks/Hangs views, plus date range expansion.

**Exception links** (link the exception type):
```html
<td><a href="https://skyline.ms/home/issues/exceptions/announcements-thread.view?rowId={ROW_ID}">{ExceptionType}</a></td>
```
ROW_ID comes from the `row_id` field in exception reports (e.g., 73730).

**Support thread links** (link the thread title):
```html
<a href="https://skyline.ms/home/support/announcements-thread.view?rowId={THREAD_ID}">{Thread Title}</a>
```

**PR fix links** (link the PR number in "FIXED by PR#XXXX"):
```html
<span class="fixed"><a href="https://github.com/ProteoWizard/pwiz/pull/{PR_NUMBER}">FIXED by PR#{PR_NUMBER}</a></span>
```

**Has email links** (link to the exception report that has the email):
```html
<span class="has-email"><a href="https://skyline.ms/home/issues/exceptions/announcements-thread.view?rowId={ROW_ID}">Has email</a></span>
```
ROW_ID is the specific report with the email contact, from `row_id` in exception history.

### Detecting Early Terminations

Runs that terminate before their expected duration indicate crashes or infrastructure problems. The MCP report flags these in the Anomaly column as `short (N min)`.

**Normal duration**: 540 minutes (9 hours) for most computers.

**Flag as "Crashed"**: Any run with `short` in the Anomaly column. Include in Key Findings:

```html
<h3>Runs Terminated Early (Crashed)</h3>
<ul>
  <li><strong>COMPUTER</strong> - 80 min (expected 540) - investigate crash cause</li>
</ul>
```

**Priority**: Early terminations are HIGH priority - they may indicate:
- Test runner crash
- Machine reboot/shutdown
- Infrastructure failure
- Unhandled exception in test harness

### Investigating Early Terminations

For each crashed run, pull the log and analyze:

```
# 1. Find run IDs for crashed runs
query_test_runs(container_path="/home/development/Nightly x64", days=2)
# Look for runs with Duration < 540

# 2. Pull testrunner section for crashed run
save_run_log(run_id=XXXXX, part="testrunner")
# Saves to ai/.tmp/testrun-log-XXXXX-testrunner.txt

# 3. View end to see crash context (not failure summaries)
tail -50 ai/.tmp/testrun-log-XXXXX-testrunner.txt
```

**What to look for in the log tail**:
- `# Process TestRunner had nonzero exit code -1073741819` = ACCESS_VIOLATION (native crash)
- `Unhandled Exception:` followed by stack trace = .NET crash with diagnostics
- Last test name before crash = which test was running when it died
- No exception = sudden termination (machine reboot, kill, power loss)

**Common exit codes**:
| Exit Code | Meaning |
|-----------|---------|
| -1073741819 | ACCESS_VIOLATION (0xC0000005) - native memory corruption |
| -1073740791 | Stack overflow |
| -1 | General failure |

**Pattern analysis**: Compare crashed runs for common factors:
- Same machine? → Machine-specific issue (hardware, drivers, configuration)
- Same test? → Test bug causing crash
- Same toolchain? → Compiler/runtime issue (e.g., VS 2026 vs VS 2022)
- Same time of day? → Scheduled task interference

Document findings in `ai/.tmp/suggested-actions-YYYYMMDD.md` under "Infrastructure Issues".

**Test failure format** (HTML):
```html
<li><strong>TestName</strong> - COMPUTER
  <br><code>Exception message</code>
  <br>at File.cs:line
  <br><a href="...">View full stack trace</a>
</li>
```

---

## Output Files

| Location | File | Purpose |
|----------|------|---------|
| `ai/.tmp/` | `nightly-report-YYYYMMDD.md` | MCP report - full test results |
| `ai/.tmp/` | `exceptions-report-YYYYMMDD.md` | MCP report - exception details |
| `ai/.tmp/` | `support-report-YYYYMMDD.md` | MCP report - support summary |
| `ai/.tmp/history/` | `daily-summary-YYYYMMDD.json` | Structured data for pattern detection |
| `ai/.tmp/` | `suggested-actions-YYYYMMDD.md` | **Investigation findings** (written progressively) |

---

## Suggested Actions File Format

```markdown
# Suggested Actions - YYYY-MM-DD

## GitHub Issues to Create

### 1. PanoramaImportErrorException shows crash dialog instead of friendly error

**Exception ID**: 73737
**Version**: 26.0.9.004

**Root Cause Analysis**:
`PanoramaImportErrorException` inherits from `Exception`, not `IOException`.
This causes `ExceptionUtil.IsProgrammingDefect()` to return true, so the
exception is re-thrown before reaching the user-friendly error handling
at PanoramaPublishUtil.cs:332.

**Evidence**:
- `PanoramaServerException` was fixed the same way in PR #3658 (inherits from IOException)
- `PanoramaImportErrorException` at PanoramaUtil.cs:580 still inherits from Exception
- Catch block at PanoramaPublishUtil.cs:329 checks IsProgrammingDefect BEFORE
  checking for PanoramaImportErrorException in InnerException

**Suggested Fix**:
Create `PanoramaException : IOException` base class, have both
`PanoramaServerException` and `PanoramaImportErrorException` inherit from it.

**Draft Issue Title**:
PanoramaImportErrorException treated as programming defect instead of showing user-friendly error

**Files to Change**:
- pwiz_tools/Shared/PanoramaClient/PanoramaUtil.cs

---

## Exception Fixes to Record

### 1. [Exception Name] - Already fixed by PR #XXXX
**Fingerprint**: `abc123...`
**Evidence**: PR #XXXX merged on YYYY-MM-DD, touches the exact line in stack trace
**Action**: `record_exception_fix(fingerprint="...", pr_number="XXXX")`

---

## Tests to Monitor
[Low-priority items - intermittent failures, watch for patterns]
```

**Quality bar**: A good suggested-actions entry has root cause analysis that
explains *why* something failed, not just *what* failed. The goal is GitHub-issue-quality
analysis that a developer can review and act on.

### User Review Workflow

When the user runs `/resume` on the scheduled session:
1. Claude reads `ai/.tmp/suggested-actions-YYYYMMDD.md`
2. Presents each suggested action for approval
3. User can approve, modify, or skip each action
4. Approved actions are executed (record_exception_fix, gh issue create, etc.)

**Key principle**: The automated session does research and prepares actions. The human reviews and approves before any permanent changes.

---

## Follow-up Investigation Tools

| Tool | Purpose |
|------|---------|
| `analyze_daily_patterns(report_date)` | Compare with history |
| `query_test_history(test_name)` | All failures/leaks for a test |
| `record_test_fix(test_name, fix_type, pr_number, ...)` | Record fix for regression detection |
| `list_computer_status(container_path)` | Active/inactive computers |
| `check_computer_alarms()` | Due reactivation reminders |
| `save_test_failure_history(test_name, start_date)` | Historical failures |
| `save_run_log(run_id, part)` | Test log by section (full/git/build/testrunner/failures) |
| `get_exception_details(exception_id)` | Exception stack trace |
| `get_support_thread(thread_id)` | Full support thread |
| `save_run_comparison(run_id_before, run_id_after)` | Compare test timing |

### Investigating Test Count Drops

When test count drops significantly (especially Performance Tests):

```
save_run_comparison(
    run_id_before=79482,  # Baseline
    run_id_after=79497,   # Changed
    container_path="/home/development/Performance Tests"
)
```

Review `ai/.tmp/run-comparison-{before}-{after}.md` for:
- NEW/REMOVED tests
- SLOWDOWNS (>50% slower)
- Top impacts on time

### Recording Fixes with Multi-Branch Tracking

When recording a fix, track both the master and release branch PRs. Cherry-picks create different commits, so we track both for accurate version correlation.

**Finding cherry-pick PRs**:
```bash
# Find PRs that mention the original PR number
gh pr list --state merged --search "3785"

# Shows:
# 3787  [cherry-pick] Fix exception when...  Skyline/skyline_26_1  MERGED
# 3785  Fix exception when...                master                MERGED
```

**Recording with full tracking**:
```python
record_exception_fix(
    fingerprint="abc123def456...",
    pr_number="3785",
    commit="a2a7f96a1f75bbd90dd3d11e85a0e3057efde325",
    merge_date="2026-01-10",
    release_branch="Skyline/skyline_26_1",
    release_pr="3787",
    release_commit="4381a5d39ef01968f9704a421d9c6d40cc2975ea",
    release_merge_date="2026-01-10"
)
```

**Finding first fixed version** (after release is tagged):
```bash
# Find which tags contain the release branch commit
git tag --contains 4381a5d39ef01968f9704a421d9c6d40cc2975ea
# Returns: 26.0.9.005 (or empty if not yet tagged)
```

The `first_fixed_version` can be null initially and updated later when the fix is included in a release.

---

## Scheduled Session Configuration

**Prompt**: `/pw-daily`

**Default recipient**: brendanx@proteinms.net

**Expected behavior**: Send email, then investigate every issue found. Session should use available turns to explore — don't stop early.

---

## Related

- [mcp/nightly-tests.md](mcp/nightly-tests.md) - Nightly test MCP tools
- [mcp/exceptions.md](mcp/exceptions.md) - Exception MCP tools
- [mcp/support.md](mcp/support.md) - Support board MCP tools
- [release-cycle-guide.md](release-cycle-guide.md) - Release phase context
