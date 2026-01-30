# Scheduled Tasks Guide

This guide covers running Claude Code automatically on a schedule using Windows Task Scheduler.

## Overview

Claude Code can run non-interactively using the `-p` (print) flag:

```bash
claude -p "Read .claude/commands/pw-daily.md and follow it"
```

This enables automated daily reports without manual intervention.

**Note:** Slash commands (`/pw-daily`) and Skills don't work in `-p` mode. See [Non-Interactive Mode Limitations](#non-interactive-mode-limitations) for workarounds.

## Prerequisites

- Claude Code installed and authenticated
- Gmail MCP configured (see `ai/docs/mcp/gmail.md`)
- LabKey MCP configured for skyline.ms access
- PowerShell 7 (`pwsh`)
- **MCP permissions configured** (see below)

## CRITICAL: MCP Permissions for Command-Line Automation

MCP tools require explicit permission to work in non-interactive mode. There are two ways to grant this:

1. **Via `--allowedTools` parameter** (preferred for scheduled tasks) - specified in the automation script
2. **Via `.claude/settings.local.json`** - for interactive sessions or as fallback

**IMPORTANT**: Wildcards (e.g., `mcp__labkey__*`) do NOT work. Each tool must be listed explicitly by name.

### Daily Report Tool Permissions

The daily report uses `--allowedTools` in the automation script. The authoritative list is maintained in:

**`ai/scripts/Invoke-DailyReport.ps1`** (version controlled)

This includes:
- **LabKey MCP**: `get_daily_test_summary`, `save_exceptions_report`, `get_support_summary`, `get_run_failures`, `get_run_leaks`, `save_test_failure_history`, `analyze_daily_patterns`, `save_daily_summary`, `check_computer_alarms`
- **Gmail MCP**: `search_emails`, `read_email`, `send_email`, `modify_email`, `batch_modify_emails`

When adding new MCP functionality to `/pw-daily`, update the `$AllowedTools` array in `Invoke-DailyReport.ps1`.

Note: Destructive tools like `delete_email`, `update_wiki_page` are intentionally excluded.

### Custom Automation Permissions

For other automated tasks, configure `.claude/settings.local.json`:

1. Start an interactive Claude Code session in your project
2. Describe the command-line operation you want to automate
3. Ask Claude to write the necessary `permissions.allow` entries
4. Review the list - remove any tools with unwanted side effects

### Verification

Test from command line before relying on scheduled tasks:

```powershell
claude -p "Call mcp__labkey__get_daily_test_summary with today's date and tell me how many test runs it found"
```

If it returns actual run counts (not a permission error), the configuration is working.

## Non-Interactive Mode Limitations

When running Claude Code with `-p` (print/non-interactive mode), several features don't work:

| Feature | Works in `-p` mode? | Workaround |
|---------|---------------------|------------|
| Slash commands (`/pw-daily`) | ❌ No | Read the command file directly and follow instructions |
| Skills (`Skill(name)`) | ❌ No | Include relevant documentation reading in the prompt |
| Interactive approval | ❌ No | Pre-authorize tools in `.claude/settings.local.json` |
| MCP wildcards | ❌ No | List each tool explicitly |
| CLAUDE.md auto-loading | ⚠️ Partial | Explicitly instruct to read it in the prompt |

### Prompt Design for Non-Interactive Mode

Structure your prompts to work around these limitations:

```
You are running as a scheduled automation task. Slash commands and skills do not work.

FIRST: Read ai/CLAUDE.md to understand project rules.
THEN: Read .claude/commands/your-command.md and follow those instructions.

Key points:
- Use pwsh (not powershell) for shell commands
- MCP tools are pre-authorized: [list relevant tools]
- [Any other context the session needs]
```

## Command-Line Options for Automation

Key flags for scheduled tasks:

| Flag | Purpose | Example |
|------|---------|---------|
| `-p "prompt"` | Run non-interactively | `claude -p "Read .claude/commands/pw-daily.md and follow it"` |
| `--output-format json` | Structured output for parsing | |
| `--allowedTools "..."` | Auto-approve specific tools | `--allowedTools "Read,Glob,Grep"` |
| `--max-turns N` | Limit iterations | `--max-turns 20` |
| `--model` | Specify model | `--model claude-sonnet-4-20250514` |

## Output Locations

All outputs stay within the project under `ai/.tmp/`:

| Type | Location | Pattern | Phase |
|------|----------|---------|-------|
| Nightly report | `ai/.tmp/` | `nightly-report-YYYYMMDD.md` | Research |
| Exceptions report | `ai/.tmp/` | `exceptions-report-YYYYMMDD.md` | Research |
| Support report | `ai/.tmp/` | `support-report-YYYYMMDD.md` | Research |
| Daily failures | `ai/.tmp/` | `failures-YYYYMMDD.md` | Research |
| Suggested actions | `ai/.tmp/` | `suggested-actions-YYYYMMDD.md` | Research |
| Daily summary | `ai/.tmp/history/` | `daily-summary-YYYYMMDD.json` | Research |
| Manifest | `ai/.tmp/` | `daily-manifest-YYYYMMDD.json` | Research |
| Automation logs | `ai/.tmp/scheduled/` | `daily-{phase}-YYYYMMDD-HHMM.log` | Both |

## The Daily Report Script

The script `ai/scripts/Invoke-DailyReport.ps1` handles:
- Pulling latest pwiz-ai and pwiz master branches
- Running Claude Code with the appropriate command file
- Phase-specific tool permissions and turn budgets
- Logging to `ai/.tmp/scheduled/`
- Auto-cleanup of logs older than 30 days

### Two-Task Architecture

The daily report is split into two phases that run as separate scheduled tasks:

| Phase | Schedule | What It Does | Turn Budget |
|-------|----------|-------------|-------------|
| **Research** | 8:05 AM | Collect MCP data, investigate exceptions/failures/leaks, write findings | 100 |
| **Email** | 9:00 AM | Read findings, compose enriched HTML email, send, archive inbox | 40 |

**Why split?** The research phase is compute-heavy and benefits from a high turn budget. The email phase is predictable and needs fewer turns. Splitting also enables independent failure recovery — if research fails, the email phase sends what it can.

### Tool Permissions by Phase

| Tool Category | Research | Email | Both |
|---------------|----------|-------|------|
| Read/Write/Edit/Glob/Grep | Yes | Read/Glob/Grep only | Yes |
| Bash (git/gh) | Yes | No | Yes |
| LabKey MCP (data) | Yes | No | Yes |
| LabKey MCP (investigation) | Yes | No | Yes |
| Gmail read | Yes | Yes | Yes |
| Gmail send/modify | No | Yes | Yes |

### Usage

```powershell
# Run research phase only (no email)
pwsh -Command "& './ai/scripts/Invoke-DailyReport.ps1' -Phase research"

# Run email phase only (reads research findings)
pwsh -Command "& './ai/scripts/Invoke-DailyReport.ps1' -Phase email"

# Run both phases (backward compatible, default)
pwsh -Command "& './ai/scripts/Invoke-DailyReport.ps1'"

# Preview without executing
pwsh -Command "& './ai/scripts/Invoke-DailyReport.ps1' -Phase research -DryRun"
```

### Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-Recipient` | `brendanx@uw.edu` | Email address for the report |
| `-Model` | `claude-opus-4-5-20251101` | Claude model to use |
| `-MaxTurns` | Phase-dependent (100/40/100) | Maximum agentic turns |
| `-Phase` | `both` | `research`, `email`, or `both` |
| `-DryRun` | (switch) | Print command without executing |

## Task Scheduler Setup

### Step 1: Test the Script Manually

```powershell
cd C:\proj
# Test research phase
pwsh -Command "& './ai/scripts/Invoke-DailyReport.ps1' -Phase research -DryRun"

# Test email phase
pwsh -Command "& './ai/scripts/Invoke-DailyReport.ps1' -Phase email -DryRun"

# Test combined (backward compatible)
pwsh -Command "& './ai/scripts/Invoke-DailyReport.ps1' -DryRun"
```

Then run without `-DryRun` to verify each phase works.

### Step 2: Create Scheduled Tasks

**Option A: PowerShell (recommended)**

Run as Administrator. Creates two tasks: research at 8:05 AM, email at 9:00 AM.

```powershell
$taskSettings = New-ScheduledTaskSettingsSet `
    -RunOnlyIfNetworkAvailable `
    -StartWhenAvailable `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries

# Task 1: Research phase (8:05 AM)
$researchAction = New-ScheduledTaskAction `
    -Execute "pwsh" `
    -Argument "-NoProfile -File C:\proj\ai\scripts\Invoke-DailyReport.ps1 -Phase research" `
    -WorkingDirectory "C:\proj"

$researchTrigger = New-ScheduledTaskTrigger -Daily -At 8:05AM

$researchTask = New-ScheduledTask `
    -Action $researchAction `
    -Trigger $researchTrigger `
    -Settings $taskSettings `
    -Description "Daily report research: collect data, investigate exceptions/failures, write findings"

Register-ScheduledTask `
    -TaskName "Daily Report - Research" `
    -InputObject $researchTask `
    -User "$env:USERNAME" `
    -RunLevel Highest

# Task 2: Email phase (9:00 AM)
$emailAction = New-ScheduledTaskAction `
    -Execute "pwsh" `
    -Argument "-NoProfile -File C:\proj\ai\scripts\Invoke-DailyReport.ps1 -Phase email" `
    -WorkingDirectory "C:\proj"

$emailTrigger = New-ScheduledTaskTrigger -Daily -At 9:00AM

$emailTask = New-ScheduledTask `
    -Action $emailAction `
    -Trigger $emailTrigger `
    -Settings $taskSettings `
    -Description "Daily report email: compose enriched email from research findings, send"

Register-ScheduledTask `
    -TaskName "Daily Report - Email" `
    -InputObject $emailTask `
    -User "$env:USERNAME" `
    -RunLevel Highest
```

**Option B: Task Scheduler GUI**

Create two tasks:

**Task 1: "Daily Report - Research"**
1. Trigger: Daily at 8:05 AM
2. Action: Start a program
   - Program: `pwsh`
   - Arguments: `-NoProfile -File C:\proj\ai\scripts\Invoke-DailyReport.ps1 -Phase research`
   - Start in: `C:\proj`
3. Settings: Run with highest privileges, run only when network available

**Task 2: "Daily Report - Email"**
1. Trigger: Daily at 9:00 AM
2. Action: Start a program
   - Program: `pwsh`
   - Arguments: `-NoProfile -File C:\proj\ai\scripts\Invoke-DailyReport.ps1 -Phase email`
   - Start in: `C:\proj`
3. Settings: Run with highest privileges, run only when network available

### Migrating from Single Task

If you have the old `Claude-Daily-Report` single task:

```powershell
# Remove old single task
Unregister-ScheduledTask -TaskName "Claude-Daily-Report" -Confirm:$false

# Then create the two new tasks above
```

## Configuration Options

### Change Recipients

Pass the `-Recipient` parameter to the email phase:

```powershell
$emailAction = New-ScheduledTaskAction `
    -Execute "pwsh" `
    -Argument "-NoProfile -File C:\proj\ai\scripts\Invoke-DailyReport.ps1 -Phase email -Recipient 'team@example.com'" `
    -WorkingDirectory "C:\proj"
```

### Change Schedule

The research phase should start early enough for findings to be ready by email time. Default: research at 8:05 AM, email at 9:00 AM (55 minutes between).

```powershell
# Adjust timing
$researchTrigger = New-ScheduledTaskTrigger -Daily -At 7:30AM
$emailTrigger = New-ScheduledTaskTrigger -Daily -At 8:30AM
```

## Troubleshooting

### Task Runs but No Email

1. Check log file in `ai/.tmp/scheduled/`
2. Verify Gmail MCP is configured: `claude mcp list`
3. Test email manually: ask Claude to send a test email

### Task Doesn't Run

1. Check Task Scheduler history (right-click task → History)
2. Ensure user has "Log on as batch job" permission
3. Verify network connectivity at scheduled time
4. Check that `pwsh` is in the system PATH

### Claude Code Errors

1. Check API key is valid: `claude --version`
2. Verify working directory exists
3. Check `--allowedTools` includes all needed tools

### MCP Connection Issues

1. Re-authenticate Gmail MCP: `npx @gongrzhe/server-gmail-autoauth-mcp auth`
2. Check LabKey MCP: `claude mcp list`

## Log Management

The script auto-deletes logs older than 30 days. Logs are kept in `ai/.tmp/scheduled/` which is gitignored.

To view recent logs:

```powershell
Get-ChildItem ai/.tmp/scheduled/*.log | Sort-Object LastWriteTime -Descending | Select-Object -First 5
```

## Security Considerations

- Script runs with user credentials
- API keys stored in Claude Code's secure storage
- Gmail OAuth tokens in `~/.gmail-mcp/`
- LabKey credentials in `~/.netrc`

## Related

- `ai/scripts/Invoke-DailyReport.ps1` - The automation script (supports `-Phase research|email|both`)
- `ai/docs/daily-report-guide.md` - Full daily report guide
- `ai/docs/mcp/gmail.md` - Gmail MCP setup
- `ai/docs/mcp/nightly-tests.md` - Nightly test data
- `ai/docs/mcp/exceptions.md` - Exception triage
- `ai/docs/mcp/support.md` - Support board access
- `.claude/commands/pw-daily.md` - Combined daily report command
- `.claude/commands/pw-daily-research.md` - Research phase command
- `.claude/commands/pw-daily-email.md` - Email phase command
