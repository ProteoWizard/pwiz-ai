# TODO: Reorganize ai/.tmp/ into Per-Date Daily Folders

**Created**: 2026-01-30
**Status**: In Progress — migration done, remaining work below
**Branch**: master (committed directly to pwiz-ai)
**Priority**: Medium

## What's Done

### Daily report split (committed as 298c7ea)
- Created `pw-daily-research.md` and `pw-daily-email.md` commands
- Updated `Invoke-DailyReport.ps1` with `-Phase` parameter (research/email/both)
- Updated `pw-daily.md`, `daily-report-guide.md`, `scheduled-tasks-guide.md`
- Enhanced `release-cycle-guide.md` with version format, git tags, fix investigation
- Added required reading list to `pw-daily-research.md`
- Registered two scheduled tasks: "Daily Report - Research" (8:05 AM), "Daily Report - Email" (9:00 AM)
- First split run completed successfully on 2026-01-30

### File migration (done in session, not yet committed)
- Created `ai/scripts/Move-DailyReports.ps1` — moves dated files from `.tmp/` to `daily/YYYY-MM-DD/`
- Ran `-MigrateAll`: moved 92 dated report files into 37 date folders
- Moved `history/` contents:
  - DB files (exception-history.json, nightly-history.json, computer-status.json) → `daily/history/`
  - daily-summary-*.json files → `daily/summaries/`
- Moved `scheduled/` logs into date folders (e.g., `session-0830.log`, `research-0805.log`)
- Deleted old `history/` and `scheduled/` directories
- Deleted stale exception-history backup files

### MCP server updates (done in session, not yet committed)
- Added `get_daily_dir()`, `get_daily_history_dir()`, `get_daily_summaries_dir()` to `common.py`
- Updated `computers.py` → reads/writes `daily/history/computer-status.json`
- Updated `exceptions.py` → reads/writes `daily/history/exception-history.json`
- Updated `nightly_history.py` → reads/writes `daily/history/nightly-history.json`
- Updated `patterns.py` → reads/writes `daily/summaries/daily-summary-YYYYMMDD.json`

### Invoke-DailyReport.ps1 updates (done in session, not yet committed)
- Logs now write to `daily/YYYY-MM-DD/{phase}-{HHMM}.log`
- Cleanup now removes date folders older than 30 days (not log files)

## Current Structure

```
ai/.tmp/
├── daily/                        # ALL valuable daily output
│   ├── history/                  # Persistent state (DO NOT DELETE — cannot regenerate)
│   │   ├── computer-status.json
│   │   ├── exception-history.json
│   │   └── nightly-history.json
│   ├── summaries/                # Daily summary JSONs (used by analyze_daily_patterns)
│   │   └── daily-summary-YYYYMMDD.json (31 files)
│   ├── 2026-01-30/               # Per-date folders (37 total)
│   │   ├── nightly-report.md
│   │   ├── exceptions-report.md
│   │   ├── support-report.md
│   │   ├── suggested-actions.md
│   │   ├── manifest.json
│   │   ├── research-0805.log
│   │   └── email-0900.log
│   └── ...
└── (102 one-off files at top level — truly transient)
```

## Remaining Work

### Must do (for the pipeline to work end-to-end)

1. **Add consolidation step to `Invoke-DailyReport.ps1`** — call `Move-DailyReports.ps1` after research phase to move MCP output from `.tmp/` into `daily/YYYY-MM-DD/`
2. **Update `pw-daily-email.md`** — read from `daily/YYYY-MM-DD/` first, fall back to `.tmp/` flat paths
3. **Update `pw-daily-research.md`** — document that consolidation runs post-research; update manifest path docs and daily_summary path to `daily/summaries/`
4. **Commit and push** all uncommitted changes (MCP, scripts, Move-DailyReports.ps1)
5. **Restart MCP server** — the Python path changes require reloading

### Nice to have

- Update `Move-DailyReports.ps1` to also handle `daily-summary-YYYYMMDD.json` written to `.tmp/` by MCP (currently writes to `daily/summaries/` directly via updated MCP code)
- Move investigation artifacts (`run-comparison-*.md`, `testrun-log-*.txt`, `test-failures-*.md`) to a subfolder
- Move one-off diagnostic scripts to a subfolder
- Clean up remaining 102 top-level files manually
- Update `scheduled-tasks-guide.md` output locations table
- Update `daily-report-guide.md` file path references

## Future Work

- LabKey backup/mirror script (upload daily folders to skyline.ms for backup)
- Rollover policy documentation (30-day local retention, LabKey is permanent)
