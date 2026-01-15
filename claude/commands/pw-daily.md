---
description: Generate consolidated daily report (nightly tests, exceptions, support)
---

# Daily Consolidated Report

Generate a consolidated daily report covering nightly tests, exceptions, and support activity.

**Read**: [ai/docs/daily-report-guide.md](../../ai/docs/daily-report-guide.md) for full instructions.

## Arguments

- **Date**: YYYY-MM-DD (optional, defaults to auto-calculated)

## Expected Behavior

1. **Send email** — The minimum checkpoint (Phase 1-2)
2. **Investigate everything** — Every failure, exception, and anomaly (Phase 3)
3. **Document findings** — Write to `suggested-actions-YYYYMMDD.md`

**Don't stop after sending the email.** The exploration phase is where the real value is.

## Quick Reference

### Phase 1: Data Collection (Steps 1-4)

**1. Determine Dates**
- Nightly: Today (if after 8 AM) or yesterday
- Exceptions: Yesterday
- Support: 1 day lookback

**2. Load Ignored Computers**
- Read `ai/.tmp/history/computer-status.json`
- Check for due alarms

**3. Read Inbox Emails**
```
search_emails(query="in:inbox from:skyline@proteinms.net newer_than:2d")
```

**4. Generate MCP Reports (REQUIRED - must succeed)**
```
get_daily_test_summary(report_date="YYYY-MM-DD")
save_exceptions_report(report_date="YYYY-MM-DD")
get_support_summary(days=1)
```

### Phase 2: Analysis & Email (Steps 5-9)

**5. Check Computer Alarms**
```
check_computer_alarms()
```

**6. Analyze Patterns**
```
analyze_daily_patterns(report_date="YYYY-MM-DD", days_back=7)
```

**7. Save Daily Summary JSON**
```
save_daily_summary(report_date, nightly_summary, nightly_failures, ...)
```

**8. Send HTML Email**
- Subject: `Skyline Daily Summary - Month DD, YYYY`
- Use `mimeType="multipart/alternative"` with `htmlBody`
- Recipient: brendanx@proteinms.net
- **Section order**: Summary → Quick Status → Support → Exceptions → Nightly
- **Summary section**: AI analysis of patterns, action items, priorities
- **Link test names directly** (not separate "View" column)
- **Ignored computers**: Show in yellow banner if any filtered

**9. Archive Processed Emails**
```
batch_modify_emails(messageIds=[...], removeLabelIds=["INBOX"])
```

### Phase 3: Exploration — DO NOT SKIP

⚠️ **MANDATORY**: Do not end session after sending email. Keep investigating until you run out of things to look at or hit the turn limit.

**Write findings progressively** to `ai/.tmp/suggested-actions-YYYYMMDD.md` after each investigation. The session may terminate at any moment.

**Investigate Test Failures**

For each test failure in today's report:
```
query_test_history(test_name="TestName")
save_run_log(run_id=XXXXX, part="testrunner")  # if crashed
gh pr list --state merged --search "TestName" --limit 10
```

Questions to answer:
- When did this test start failing? (NEW vs RECURRING)
- Is there a merged PR that might have fixed it?
- Is there a pattern (same machine, same time, same test file)?

→ Write findings to `suggested-actions-YYYYMMDD.md`

**Investigate Exceptions**

For each exception fingerprint:
```
get_exception_details(exception_id=XXXXX)
gh pr list --state merged --search "filename:SomeFile.cs" --limit 10
```

Questions to answer:
- Is this only affecting old versions? (already fixed)
- Is there a PR that touched this code recently?
- Does the user have contact info for follow-up?

→ Write findings to `suggested-actions-YYYYMMDD.md`

**Investigate Infrastructure Issues**

For missing computers or crashed runs:
```
list_computer_status(container_path="/home/development/Nightly x64")
```

Questions to answer:
- Same machine repeatedly crashing? → Hardware issue
- Same test causing crash? → Test bug
- Missing computers expected or unexpected?

→ Write findings to `suggested-actions-YYYYMMDD.md`

## Critical Validation

**FAIL the report if:**
- `get_daily_test_summary()` fails or returns zero runs
- Cannot query fresh MCP data

**NEVER use stale data** - cached files are for historical comparison only.

## Output Files

- `ai/.tmp/nightly-report-YYYYMMDD.md` — MCP report
- `ai/.tmp/exceptions-report-YYYYMMDD.md` — MCP report
- `ai/.tmp/support-report-YYYYMMDD.md` — MCP report
- `ai/.tmp/history/daily-summary-YYYYMMDD.json` — For pattern detection
- `ai/.tmp/suggested-actions-YYYYMMDD.md` — **Investigation findings** (written progressively)

## Related

- [ai/docs/daily-report-guide.md](../../ai/docs/daily-report-guide.md) - Full instructions
- `/pw-nightly` - Nightly tests only
- `/pw-exceptions` - Exceptions only
- `/pw-support` - Support board only
