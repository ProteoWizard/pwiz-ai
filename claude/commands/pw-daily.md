---
description: Generate consolidated daily report (nightly tests, exceptions, support)
---

# Daily Consolidated Report

Generate a consolidated daily report covering nightly tests, exceptions, and support activity.

**Read**: [ai/docs/daily-report-guide.md](../../ai/docs/daily-report-guide.md) for full instructions.

## Arguments

- **Date**: YYYY-MM-DD (optional, defaults to auto-calculated)
- **Effort**: `quick` | `standard` | `deep` (optional, defaults to `standard`)

## Effort Levels

| Level | Duration | Scope |
|-------|----------|-------|
| `quick` | ~1-2 min | Report + email only |
| `standard` | ~15-30 min | Report + investigate NEW issues + git blame |
| `deep` | Full session | Comprehensive analysis, learn from developer emails |

## Quick Reference

### 1. Determine Dates
- Nightly: Today (if after 8 AM) or yesterday
- Exceptions: Yesterday
- Support: 1 day lookback

### 2. Load Ignored Computers
- Read `ai/.tmp/history/computer-status.json`
- Check for due alarms

### 3. Read Inbox Emails
```
search_emails(query="in:inbox from:skyline@proteinms.net newer_than:2d")
```

### 4. Generate MCP Reports (REQUIRED - must succeed)
```
get_daily_test_summary(report_date="YYYY-MM-DD")
save_exceptions_report(report_date="YYYY-MM-DD")
get_support_summary(days=1)
```

### 5. Check Computer Alarms
```
check_computer_alarms()
```

### 6. Analyze Patterns
```
analyze_daily_patterns(report_date="YYYY-MM-DD", days_back=7)
```

### 7. Save Daily Summary JSON
```
save_daily_summary(report_date, nightly_summary, nightly_failures, ...)
```

### 8. Send HTML Email
- Subject: `Skyline Daily Summary - Month DD, YYYY`
- Use `mimeType="multipart/alternative"` with `htmlBody`
- Recipient: brendanx@proteinms.net
- **Section order**: Summary → Quick Status → Support → Exceptions → Nightly
- **Summary section**: AI analysis of patterns, action items, priorities
- **Link test names directly** (not separate "View" column)
- **Ignored computers**: Show in yellow banner if any filtered

### 9. Archive Processed Emails
```
batch_modify_emails(messageIds=[...], removeLabelIds=["INBOX"])
```

### 10. Self-Improvement Reflection (Required)
- Read TODO at `ai/todos/active/TODO-20251228_daily_report_improvements.md`
- Vote on 1-3 backlog items
- Record in session log

### 11. Write Execution Log
- Save to `ai/.tmp/logs/daily-session-YYYYMMDD.md`

### 12. Exploration Phase (continues until limit)
- Write findings to `ai/.tmp/suggested-actions-YYYYMMDD.md`

## Critical Validation

**FAIL the report if:**
- `get_daily_test_summary()` fails or returns zero runs
- Cannot query fresh MCP data

**NEVER use stale data** - cached files are for historical comparison only.

## Output Files

- `ai/.tmp/nightly-report-YYYYMMDD.md`
- `ai/.tmp/exceptions-report-YYYYMMDD.md`
- `ai/.tmp/support-report-YYYYMMDD.md`
- `ai/.tmp/history/daily-summary-YYYYMMDD.json`
- `ai/.tmp/history/computer-status.json` (config, not per-day)
- `ai/.tmp/logs/daily-session-YYYYMMDD.md`
- `ai/.tmp/suggested-actions-YYYYMMDD.md`

## Related

- [ai/docs/daily-report-guide.md](../../ai/docs/daily-report-guide.md) - Full instructions
- `/pw-nightly` - Nightly tests only
- `/pw-exceptions` - Exceptions only
- `/pw-support` - Support board only
