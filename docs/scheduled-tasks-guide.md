# Scheduled Tasks Guide

This guide covers running Claude Code automatically on a schedule using Windows Task Scheduler.

## Overview

Claude Code can run non-interactively using the `-p` (print) flag:

```bash
claude -p "Read .claude/commands/pw-daily-research.md and follow it"
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
| Slash commands (`/pw-daily`) | No | Read the command file directly and follow instructions |
| Skills (`Skill(name)`) | No | Include relevant documentation reading in the prompt |
| Interactive approval | No | Pre-authorize tools in `.claude/settings.local.json` |
| MCP wildcards | No | List each tool explicitly |
| CLAUDE.md auto-loading | Partial | Explicitly instruct to read it in the prompt |

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
| `-p "prompt"` | Run non-interactively | `claude -p "Read .claude/commands/pw-daily-research.md and follow it"` |
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
| Automation logs | `ai/.tmp/daily/YYYY-MM-DD/` | `{phase}-HHMM.log` | Both |

## The Daily Report Script

The script `ai/scripts/Invoke-DailyReport.ps1` handles:
- Pulling latest pwiz-ai and pwiz master branches
- Running Claude Code with the appropriate command file
- Phase-specific tool permissions and turn budgets
- Logging to `ai/.tmp/daily/YYYY-MM-DD/`
- Auto-cleanup of logs older than 30 days
- Self-scheduling via `-Schedule` parameter

### Sequential Two-Phase Architecture

When `-Phase both` (the default), the script runs two sequential Claude sessions:

| Order | Phase | What It Does | Turn Budget |
|-------|-------|-------------|-------------|
| 1 | **Research** | Collect MCP data, investigate exceptions/failures/leaks, write findings | 100 |
| 2 | **Email** | Read findings, compose enriched HTML email, send, archive inbox | 40 |

The email session starts immediately after research completes. Each session has independent turn limits and tool permissions — research cannot send email, email cannot run LabKey queries.

**Why sequential sessions?** The research phase is compute-heavy and benefits from a high turn budget. The email phase is predictable and needs fewer turns. Session isolation prevents research from consuming turns meant for email delivery. If research fails, email still runs and sends what it can.

### Tool Permissions by Phase

| Tool Category | Research | Email |
|---------------|----------|-------|
| Read/Write/Edit/Glob/Grep | Yes | Read/Glob/Grep only |
| Bash (git/gh) | Yes | No |
| LabKey MCP (data) | Yes | No |
| LabKey MCP (investigation) | Yes | No |
| Gmail read | Yes | Yes |
| Gmail send/modify | No | Yes |

### Usage

```powershell
# Run both phases sequentially (default)
pwsh -Command "& './ai/scripts/Invoke-DailyReport.ps1'"

# Run research phase only (no email)
pwsh -Command "& './ai/scripts/Invoke-DailyReport.ps1' -Phase research"

# Run email phase only (reads research findings)
pwsh -Command "& './ai/scripts/Invoke-DailyReport.ps1' -Phase email"

# Preview without executing
pwsh -Command "& './ai/scripts/Invoke-DailyReport.ps1' -DryRun"
```

### Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-Recipient` | `brendanx@uw.edu` | Email address for the report |
| `-Model` | `claude-opus-4-5-20251101` | Claude model to use |
| `-MaxTurns` | Phase-dependent (100/40) | Maximum agentic turns per phase |
| `-Phase` | `both` | `research`, `email`, or `both` |
| `-Schedule` | (none) | Register as daily Task Scheduler task at given time |
| `-DryRun` | (switch) | Print command without executing |

## Task Scheduler Setup

### Option A: Self-Scheduling (Recommended)

The script can register itself as a Windows Task Scheduler task. Run from an elevated (Administrator) PowerShell prompt:

```powershell
# Schedule default (both phases sequentially) at 8:05 AM
pwsh -Command "& './ai/scripts/Invoke-DailyReport.ps1' -Schedule '8:05AM'"

# Schedule with custom recipient
pwsh -Command "& './ai/scripts/Invoke-DailyReport.ps1' -Schedule '8:05AM' -Recipient 'team@example.com'"

# Schedule individual phases separately (if needed)
pwsh -Command "& './ai/scripts/Invoke-DailyReport.ps1' -Phase research -Schedule '8:05AM'"
pwsh -Command "& './ai/scripts/Invoke-DailyReport.ps1' -Phase email -Schedule '9:00AM'"
```

The `-Schedule` parameter:
- Validates the time format
- Requires elevation (errors if not admin)
- Removes any existing task(s) covered by the phase before creating:
  - `research` removes "Daily Report - Research"
  - `email` removes "Daily Report - Email"
  - `both` removes all three ("Daily Report - Research", "- Email", "- Both")
- Creates a daily trigger at the specified time
- Sets 3-hour execution time limit
- Enables "start when available" for missed runs

### Option B: Task Scheduler GUI

Create one task:

**Task: "Daily Report - Both"**
1. Trigger: Daily at 8:05 AM
2. Action: Start a program
   - Program: `pwsh`
   - Arguments: `-NoProfile -File <project root>\ai\scripts\Invoke-DailyReport.ps1`
   - Start in: `<your project root>`
3. Settings: Allow start if on batteries, start when available

### Step 1: Test First

```powershell
cd <your project root>
# Preview what will run
pwsh -Command "& './ai/scripts/Invoke-DailyReport.ps1' -DryRun"

# Run manually to verify
pwsh -Command "& './ai/scripts/Invoke-DailyReport.ps1'"
```

### Migrating from Two-Task Setup

If you have the old separate research and email tasks:

```powershell
# The -Schedule parameter with -Phase both handles this automatically:
# it removes "Daily Report - Research", "Daily Report - Email", and "Daily Report - Both"
pwsh -Command "& './ai/scripts/Invoke-DailyReport.ps1' -Schedule '8:05AM'"
```

Or manually:

```powershell
Unregister-ScheduledTask -TaskName "Daily Report - Research" -Confirm:$false
Unregister-ScheduledTask -TaskName "Daily Report - Email" -Confirm:$false
# Then schedule the combined task
```

## Configuration Options

### Change Recipients

Pass the `-Recipient` parameter:

```powershell
pwsh -Command "& './ai/scripts/Invoke-DailyReport.ps1' -Schedule '8:05AM' -Recipient 'team@example.com'"
```

### Change Schedule

Simply re-run with the new time — existing tasks are removed automatically:

```powershell
pwsh -Command "& './ai/scripts/Invoke-DailyReport.ps1' -Schedule '7:30AM'"
```

## Troubleshooting

### Task Runs but No Email

1. Check log file in `ai/.tmp/daily/YYYY-MM-DD/`
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

The script auto-deletes daily folders older than 30 days. Logs are in `ai/.tmp/daily/YYYY-MM-DD/` which is gitignored.

To view recent logs:

```powershell
Get-ChildItem ai/.tmp/daily/*/*.log | Sort-Object LastWriteTime -Descending | Select-Object -First 5
```

## Security Considerations

- Script runs with user credentials
- API keys stored in Claude Code's secure storage
- Gmail OAuth tokens in `~/.gmail-mcp/`
- LabKey credentials in `~/.netrc`

## Related

- `ai/scripts/Invoke-DailyReport.ps1` - The automation script (supports `-Phase research|email|both` and `-Schedule`)
- `ai/docs/daily-report-guide.md` - Full daily report guide
- `ai/docs/mcp/gmail.md` - Gmail MCP setup
- `ai/docs/mcp/nightly-tests.md` - Nightly test data
- `ai/docs/mcp/exceptions.md` - Exception triage
- `ai/docs/mcp/support.md` - Support board access
- `.claude/commands/pw-daily.md` - Combined daily report command (interactive)
- `.claude/commands/pw-daily-research.md` - Research phase command
- `.claude/commands/pw-daily-email.md` - Email phase command
