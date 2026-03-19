# TODO: Reorganize ai/.tmp/ into Per-Date Daily Folders

**Created**: 2026-01-30
**Completed**: 2026-01-30
**Status**: Complete
**Branch**: master (committed directly to pwiz-ai)
**Commits**: 298c7ea, 7c9dbba, 13842c1

## Summary

Reorganized `ai/.tmp/` from a flat namespace with 100+ files into a structured layout:

```
ai/.tmp/
├── daily/                        # ALL valuable daily output
│   ├── history/                  # Persistent state (DO NOT DELETE — cannot regenerate)
│   │   ├── computer-status.json
│   │   ├── exception-history.json
│   │   └── nightly-history.json
│   ├── summaries/                # Daily summary JSONs (used by analyze_daily_patterns)
│   │   └── daily-summary-YYYYMMDD.json
│   ├── 2026-01-30/               # Per-date folders
│   │   ├── nightly-report.md
│   │   ├── exceptions-report.md
│   │   ├── support-report.md
│   │   ├── suggested-actions.md
│   │   ├── manifest.json
│   │   ├── research-0805.log
│   │   └── email-0900.log
│   └── ...
└── (transient top-level files — auto-cleaned after 14 days)
```

## What Was Done

### Daily report split (298c7ea)
- Created `pw-daily-research.md` and `pw-daily-email.md` commands
- Updated `Invoke-DailyReport.ps1` with `-Phase` parameter (research/email/both)
- Updated `pw-daily.md`, `daily-report-guide.md`, `scheduled-tasks-guide.md`
- Enhanced `release-cycle-guide.md` with version format, git tags, fix investigation
- Added required reading list to `pw-daily-research.md`
- Registered two scheduled tasks: "Daily Report - Research" (8:05 AM), "Daily Report - Email" (9:00 AM)

### File reorganization and MCP updates (7c9dbba)
- Created `Move-DailyReports.ps1` — moves dated files into `daily/YYYY-MM-DD/`
- Migrated 92 historical dated files into 37 date folders
- Moved persistent state to `daily/history/`, summary JSONs to `daily/summaries/`
- Updated MCP server: `common.py`, `computers.py`, `exceptions.py`, `nightly_history.py`, `patterns.py`
- Added consolidation step to `Invoke-DailyReport.ps1` (runs after research phase)
- Updated `pw-daily-email.md` with dual-path fallback (new location then old)
- Updated `pw-daily-research.md` with consolidation docs and corrected paths

### Automatic cleanup (13842c1)
- Created `Clean-TmpFiles.ps1` — deletes top-level .tmp/ files older than 14 days
- Preserves `active-project.json` and `daily/` directory tree
- Hooked into `Invoke-DailyReport.ps1` to run after each daily report
- Ran initial cleanup: deleted 45 stale files (5.7 MB)
