<#
.SYNOPSIS
    Runs Claude Code daily report and emails results.

.DESCRIPTION
    Invokes Claude Code in non-interactive mode to run the daily report.
    Supports splitting into research and email phases for scheduled automation.

    Designed for Windows Task Scheduler automation.

.PARAMETER Recipient
    Email address to send the report to. Default: brendanx@uw.edu

.PARAMETER Model
    Claude model to use. Default: claude-opus-4-5-20251101

.PARAMETER MaxTurns
    Maximum agentic turns. Default varies by phase:
    - research: 100
    - email: 40
    - both: 100

.PARAMETER Phase
    Which phase to run:
    - research: Data collection, investigation, write findings (no email)
    - email: Read findings, compose and send enriched email
    - both: Run everything (backward compatible, default)

.PARAMETER DryRun
    If set, prints the command without executing.

.EXAMPLE
    .\Invoke-DailyReport.ps1
    Runs the full daily report with default settings.

.EXAMPLE
    .\Invoke-DailyReport.ps1 -Phase research
    Runs research phase only (data collection + investigation, no email).

.EXAMPLE
    .\Invoke-DailyReport.ps1 -Phase email
    Runs email phase only (reads research findings, sends email).

.EXAMPLE
    .\Invoke-DailyReport.ps1 -Recipient "team@example.com"
    Sends the report to a different recipient.

.EXAMPLE
    .\Invoke-DailyReport.ps1 -DryRun
    Shows what would be executed without running.

.NOTES
    See ai/docs/scheduled-tasks-guide.md for Task Scheduler setup.

    Scheduled tasks:
    - "Daily Report - Research" at 8:05 AM: -Phase research
    - "Daily Report - Email" at 9:00 AM: -Phase email
#>

param(
    [string]$Recipient = "brendanx@uw.edu",
    [string]$Model = "claude-opus-4-5-20251101",
    [int]$MaxTurns = 0,
    [ValidateSet("research", "email", "both")]
    [string]$Phase = "both",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

# Ensure UTF-8 encoding throughout the pipeline
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# Configuration
# Sibling mode: C:\proj contains both ai/ (pwiz-ai) and pwiz/ subdirectories
$WorkDir = "C:\proj"
$DateFolder = Get-Date -Format "yyyy-MM-dd"
$TimeStamp = Get-Date -Format "HHmm"
$LogDir = Join-Path $WorkDir "ai\.tmp\daily\$DateFolder"
$LogFile = Join-Path $LogDir "$Phase-$TimeStamp.log"

# Ensure log directory exists
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

# Phase-specific defaults for MaxTurns
if ($MaxTurns -eq 0) {
    $MaxTurns = switch ($Phase) {
        "research" { 100 }
        "email"    { 40 }
        "both"     { 100 }
    }
}

# Build phase-specific prompt
switch ($Phase) {
    "research" {
        $CommandFile = ".claude/commands/pw-daily-research.md"
        $Prompt = @"
You are running as a scheduled automation task. Slash commands and skills do not work in non-interactive mode.

FIRST: Read ai/CLAUDE.md to understand project rules (especially: use pwsh not powershell, backslashes for file paths).

THEN: Read $CommandFile and follow those instructions to run the research phase of the daily report.

Key points:
- Use MCP tools directly (mcp__labkey__*, mcp__gmail__*) - they are pre-authorized
- Use pwsh (not powershell) for any shell commands
- The report date is the date in your environment info
- Do NOT send email - only collect data and write findings to files
- Write the manifest file at the end: ai/.tmp/daily-manifest-YYYYMMDD.json
- If MCP tools fail, write a manifest with research_completed: false
"@
    }
    "email" {
        $CommandFile = ".claude/commands/pw-daily-email.md"
        $Prompt = @"
You are running as a scheduled automation task. Slash commands and skills do not work in non-interactive mode.

FIRST: Read ai/CLAUDE.md to understand project rules (especially: use pwsh not powershell, backslashes for file paths).

THEN: Read $CommandFile and follow those instructions to compose and send the daily report email.

Email recipient: $Recipient

Key points:
- Read research findings from ai/.tmp/daily/YYYY-MM-DD/ first (consolidated location)
- Fall back to ai/.tmp/ flat files if consolidation hasn't run
- If research files are missing, send what you can with a note about incomplete data
- Use Gmail MCP tools to send the email and archive processed inbox emails
- If data is completely missing, send an ERROR email as specified in the command file
"@
    }
    "both" {
        $CommandFile = ".claude/commands/pw-daily.md"
        $Prompt = @"
You are running as a scheduled automation task. Slash commands and skills do not work in non-interactive mode.

FIRST: Read ai/CLAUDE.md to understand project rules (especially: use pwsh not powershell, backslashes for file paths).

THEN: Read $CommandFile and follow those instructions to generate the daily report.

Email recipient: $Recipient

Key points:
- Use MCP tools directly (mcp__labkey__*, mcp__gmail__*) - they are pre-authorized
- Use pwsh (not powershell) for any shell commands
- The report date is the date in your environment info
- Include key findings in the email body
- If MCP tools fail, send an ERROR email as specified in pw-daily.md
"@
    }
}

# Build phase-specific allowed tools list
# Wildcards don't work - each tool must be listed explicitly
switch ($Phase) {
    "research" {
        # Research phase: All LabKey MCP, Bash (git/gh), Read/Write/Glob/Grep
        # NO Gmail send/modify (inbox reading allowed for data collection)
        $AllowedTools = @(
            # File operations
            "Read",
            "Write",
            "Edit",
            "Glob",
            "Grep",
            # Bash - granular read-only operations for investigation
            "Bash(git blame:*)",
            "Bash(git log:*)",
            "Bash(git show:*)",
            "Bash(git -C:*)",
            "Bash(grep:*)",
            "Bash(gh issue list:*)",
            "Bash(gh issue view:*)",
            "Bash(gh issue create:*)",
            "Bash(gh pr list:*)",
            "Bash(gh pr view:*)",
            # LabKey MCP - data collection
            "mcp__labkey__check_computer_alarms",
            "mcp__labkey__get_daily_test_summary",
            "mcp__labkey__save_exceptions_report",
            "mcp__labkey__get_support_summary",
            "mcp__labkey__get_run_failures",
            "mcp__labkey__get_run_leaks",
            "mcp__labkey__save_test_failure_history",
            "mcp__labkey__analyze_daily_patterns",
            "mcp__labkey__save_daily_summary",
            "mcp__labkey__save_daily_failures",
            "mcp__labkey__query_test_history",
            # LabKey MCP - investigation
            "mcp__labkey__backfill_nightly_history",
            "mcp__labkey__backfill_exception_history",
            "mcp__labkey__get_exception_details",
            "mcp__labkey__query_exception_history",
            "mcp__labkey__record_exception_issue",
            "mcp__labkey__record_exception_fix",
            "mcp__labkey__record_test_issue",
            "mcp__labkey__record_test_fix",
            "mcp__labkey__get_support_thread",
            "mcp__labkey__save_run_log",
            "mcp__labkey__query_test_runs",
            "mcp__labkey__list_computer_status",
            "mcp__labkey__save_run_metrics_csv",
            # Gmail MCP - read-only (for inbox data collection)
            "mcp__gmail__search_emails",
            "mcp__gmail__read_email"
        ) -join ","
    }
    "email" {
        # Email phase: Gmail send/modify, Read/Glob for reading findings
        # NO Bash, NO LabKey investigation tools
        $AllowedTools = @(
            # File operations (read-only + Glob for finding files)
            "Read",
            "Glob",
            "Grep",
            # Gmail MCP - read inbox, send report, archive
            "mcp__gmail__search_emails",
            "mcp__gmail__read_email",
            "mcp__gmail__send_email",
            "mcp__gmail__modify_email",
            "mcp__gmail__batch_modify_emails"
        ) -join ","
    }
    "both" {
        # Full access - backward compatible
        $AllowedTools = @(
            # File operations
            "Read",
            "Write",
            "Edit",
            "Glob",
            "Grep",
            # Bash - granular read-only operations for Phase 3 investigation
            "Bash(git blame:*)",
            "Bash(git log:*)",
            "Bash(git show:*)",
            "Bash(git -C:*)",
            "Bash(grep:*)",
            "Bash(gh issue list:*)",
            "Bash(gh issue view:*)",
            "Bash(gh issue create:*)",
            "Bash(gh pr list:*)",
            "Bash(gh pr view:*)",
            # LabKey MCP - nightly tests (Phase 1-2)
            "mcp__labkey__check_computer_alarms",
            "mcp__labkey__get_daily_test_summary",
            "mcp__labkey__save_exceptions_report",
            "mcp__labkey__get_support_summary",
            "mcp__labkey__get_run_failures",
            "mcp__labkey__get_run_leaks",
            "mcp__labkey__save_test_failure_history",
            "mcp__labkey__analyze_daily_patterns",
            "mcp__labkey__save_daily_summary",
            "mcp__labkey__save_daily_failures",
            "mcp__labkey__query_test_history",
            # LabKey MCP - Phase 3 investigation
            "mcp__labkey__backfill_nightly_history",
            "mcp__labkey__backfill_exception_history",
            "mcp__labkey__get_exception_details",
            "mcp__labkey__query_exception_history",
            "mcp__labkey__record_exception_issue",
            "mcp__labkey__record_exception_fix",
            "mcp__labkey__record_test_issue",
            "mcp__labkey__record_test_fix",
            "mcp__labkey__get_support_thread",
            "mcp__labkey__save_run_log",
            "mcp__labkey__query_test_runs",
            "mcp__labkey__list_computer_status",
            "mcp__labkey__save_run_metrics_csv",
            # Gmail MCP - read notifications, send report, archive
            "mcp__gmail__search_emails",
            "mcp__gmail__read_email",
            "mcp__gmail__send_email",
            "mcp__gmail__modify_email",
            "mcp__gmail__batch_modify_emails"
        ) -join ","
    }
}

# Build the command
$ClaudeArgs = @(
    "-p", $Prompt,
    "--allowedTools", $AllowedTools,
    "--max-turns", $MaxTurns,
    "--model", $Model
)

if ($DryRun) {
    Write-Host "Would execute:" -ForegroundColor Cyan
    Write-Host "  Phase: $Phase"
    Write-Host "  Working directory: $WorkDir"
    Write-Host "  Command file: $CommandFile"
    Write-Host "  Max turns: $MaxTurns"
    Write-Host "  Git pull ai/: git pull origin master"
    Write-Host "  Git pull pwiz/: git pull origin master"
    Write-Host "  Log file: $LogFile"
    Write-Host "  Command: claude $($ClaudeArgs -join ' ')"
    Write-Host ""
    Write-Host "Allowed tools:" -ForegroundColor Yellow
    $AllowedTools -split "," | ForEach-Object { Write-Host "  - $_" }
    exit 0
}

# Log start
$StartTime = Get-Date
"[$StartTime] Starting Claude Code daily report (phase: $Phase)" | Out-File -FilePath $LogFile -Encoding UTF8

# Pull latest pwiz-ai (ai/) master
"[$(Get-Date)] Pulling latest ai/ (pwiz-ai) master..." | Out-File -FilePath $LogFile -Append -Encoding UTF8
Push-Location (Join-Path $WorkDir "ai")
try {
    $GitOutput = git pull origin master 2>&1
    $GitOutput | Out-File -FilePath $LogFile -Append -Encoding UTF8
    if ($LASTEXITCODE -ne 0) {
        "[$(Get-Date)] WARNING: ai/ git pull failed, continuing with existing version" | Out-File -FilePath $LogFile -Append -Encoding UTF8
    } else {
        "[$(Get-Date)] ai/ git pull successful" | Out-File -FilePath $LogFile -Append -Encoding UTF8
    }
}
finally {
    Pop-Location
}

# Pull latest pwiz master
"[$(Get-Date)] Pulling latest pwiz/ master..." | Out-File -FilePath $LogFile -Append -Encoding UTF8
Push-Location (Join-Path $WorkDir "pwiz")
try {
    $GitOutput = git pull origin master 2>&1
    $GitOutput | Out-File -FilePath $LogFile -Append -Encoding UTF8
    if ($LASTEXITCODE -ne 0) {
        "[$(Get-Date)] WARNING: pwiz/ git pull failed, continuing with existing version" | Out-File -FilePath $LogFile -Append -Encoding UTF8
    } else {
        "[$(Get-Date)] pwiz/ git pull successful" | Out-File -FilePath $LogFile -Append -Encoding UTF8
    }
}
finally {
    Pop-Location
}

# Change to project directory
Push-Location $WorkDir

try {
    # Run Claude Code with real-time logging
    "[$(Get-Date)] Starting Claude Code (phase: $Phase, max-turns: $MaxTurns)..." | Out-File -FilePath $LogFile -Append -Encoding UTF8
    & claude @ClaudeArgs 2>&1 | ForEach-Object {
        $_ | Out-File -FilePath $LogFile -Append -Encoding UTF8
    }
    $ExitCode = $LASTEXITCODE

    # Log completion
    $EndTime = Get-Date
    $Duration = $EndTime - $StartTime
    "[$EndTime] Completed with exit code $ExitCode (duration: $($Duration.TotalMinutes.ToString('F1')) minutes)" | Out-File -FilePath $LogFile -Append -Encoding UTF8

    # Consolidate MCP output into daily/YYYY-MM-DD/ folder
    if ($Phase -eq "research" -or $Phase -eq "both") {
        $ConsolidateScript = Join-Path $WorkDir "ai\scripts\Move-DailyReports.ps1"
        if (Test-Path $ConsolidateScript) {
            "[$(Get-Date)] Consolidating daily reports into $DateFolder/..." | Out-File -FilePath $LogFile -Append -Encoding UTF8
            try {
                & $ConsolidateScript 2>&1 | Out-File -FilePath $LogFile -Append -Encoding UTF8
                "[$(Get-Date)] Consolidation complete" | Out-File -FilePath $LogFile -Append -Encoding UTF8
            }
            catch {
                "[$(Get-Date)] WARNING: Consolidation failed: $_" | Out-File -FilePath $LogFile -Append -Encoding UTF8
            }
        }
    }

    if ($ExitCode -ne 0) {
        Write-Error "Claude Code exited with code $ExitCode. See log: $LogFile"
    }
}
finally {
    Pop-Location
}

# Clean up old date folders (keep 30 days)
$DailyRoot = Join-Path $WorkDir "ai\.tmp\daily"
Get-ChildItem -Path $DailyRoot -Directory |
    Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}$' -and $_.Name -lt (Get-Date).AddDays(-30).ToString("yyyy-MM-dd") } |
    Remove-Item -Recurse -Force

# Clean up stale top-level transient files (keep 14 days)
$CleanupScript = Join-Path $WorkDir "ai\scripts\Clean-TmpFiles.ps1"
if (Test-Path $CleanupScript) {
    & $CleanupScript
}

exit $ExitCode
