# Smart Triage for Exceptions and Test Failures — Skip Already-Fixed/Tracked Items

## Branch Information
- **Branch**: `master` (pwiz-ai)
- **Base**: `master`
- **Created**: 2026-02-15
- **Status**: Complete

## Objective

Make the daily report never flag an exception or test failure as needing attention when it already has a recorded fix (and all reports are from pre-fix versions) or a tracked GitHub issue. Both `save_exceptions_report()` and `save_daily_failures()` should separate "Needs Attention" from "Already Handled."

## Tasks

### Exception Report (`ai/mcp/LabKeyMcp/tools/exceptions.py`)
- [x] Add `_parse_version_tuple()` for reliable numeric version comparison
- [x] Fix regression check to use numeric comparison instead of string comparison
- [x] Add `_needs_attention()` classifier (fix → check versions; issue → tracked; else → needs attention)
- [x] Split report body into "Needs Attention" and "Already Handled" sections
- [x] Fix priority items summary to exclude already-handled items

### Daily Failures Report (`ai/mcp/LabKeyMcp/tools/nightly.py`)
- [x] Load nightly history in `save_daily_failures()` and annotate fingerprints
- [x] Add `_failure_needs_attention()` classifier (fix → check dates; issue → tracked; else → needs attention)
- [x] Split report body into "Needs Attention" and "Already Handled" sections
- [x] Add priority items to brief summary

### Prompt Updates
- [x] Update `ai/claude/commands/pw-daily-research.md` — skip-already-handled for both exceptions and failures
- [x] Update `ai/docs/daily-report-guide.md` — skip-already-handled for both investigation sections

## Implementation Details

### `_needs_attention()` Logic (exceptions)

- Has fix AND `first_fixed_version` set → compare today's report versions against fix version
  - ALL versions < fix version → `(False, 'fixed')` — already fixed
  - ANY version >= fix version → `(True, 'regression')`
- Has fix but NO version info → `(False, 'fixed')` — trust the fix record
- Has tracked issue → `(False, 'tracked')`
- Otherwise → `(True, <reason>)` where reason is 'new', 'email', or 'recurring'

### `_failure_needs_attention()` Logic (nightly tests)

Same pattern but using dates instead of versions:
- Has fix AND merge date → compare today's failure dates against merge date
- Has tracked issue → `(False, 'tracked')`
- Otherwise → `(True, <reason>)`

### Report Structure (both)

- **"## Needs Attention"** — full detail for items needing investigation
- **"## Already Handled"** — one-line summaries with reason (e.g., "Fixed in PR#3911", "Tracked as #3979")

## Verification

1. `save_exceptions_report(report_date="2026-02-14")` — fixed exceptions in "Already Handled"
2. `save_daily_failures(report_date="2026-02-15")` — failures with fixes in "Already Handled"
3. Version comparison handles: `"24.1.0.199"`, `"25.1.0.237-7401c644b4"`, `"26.0.9.005"`

## Progress Log

### 2026-02-15 - Planning

Identified the problem after wasting effort on duplicate issue #3983 / PR #3984. Root cause: reports don't filter out already-handled items. Planned consistent fix for both exception and nightly test reporting.

### 2026-02-15 - Implementation Complete

All changes implemented and verified:
- `exceptions.py`: Added `_parse_version_tuple()`, `_needs_attention()`, restructured report into "Needs Attention" / "Already Handled" sections, fixed priority items
- `nightly.py`: Added history loading in `save_daily_failures()`, `_failure_needs_attention()`, same report structure
- `pw-daily-research.md`: Added skip-already-handled instructions
- `daily-report-guide.md`: Added skip-already-handled instructions

Verified with `save_exceptions_report(2026-02-14)` — fingerprint `ee3d3862b1773801` correctly appears in "Already Handled" as "Fixed in PR#3911". Verified with `save_daily_failures(2026-02-15)` — untracked failure correctly appears in "Needs Attention".
