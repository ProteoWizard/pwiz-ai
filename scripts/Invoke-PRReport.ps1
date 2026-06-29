<#
.SYNOPSIS
    Runs Claude Code PR-activity report and emails results.

.DESCRIPTION
    Invokes Claude Code in non-interactive mode to generate a daily report on
    developer activity: open PRs (especially those needing your review), recent
    issue activity, stale PRs/issues, author "pile-up" patterns, and the health
    of ai/todos/ (active and backlog).

    Mirrors the two-phase architecture of Invoke-DailyReport.ps1:
      - research: collect data, write findings to files (no email)
      - email:    read findings, compose enriched HTML email, send

    Can register itself as a Windows Task Scheduler task with -Schedule.

.PARAMETER Recipient
    Email address to send the report to. Default: brendanx@proteinms.net
    (This is a personal management report by default — review the data before
    broadcasting to a team alias.)

.PARAMETER Model
    Claude model to use. Default: claude-opus-4-6

.PARAMETER MaxTurns
    Maximum agentic turns per phase. Default varies by phase:
    - research: 80
    - email:    30
    When Phase is "both", each phase uses its own default.

.PARAMETER Phase
    Which phase to run:
    - research: Data collection + investigation, write findings (no email)
    - email:    Read findings, compose and send enriched email
    - both:     Run research then email sequentially (default)

.PARAMETER Date
    Report date in YYYY-MM-DD or YYYYMMDD format. Default: today.
    Use this to backfill reports for missed days.

.PARAMETER GitHubUser
    GitHub login whose review queue and authored PRs/issues are the focus of
    the report. Default: brendanx67
    Ignored in -FanOut mode (each recipient's login comes from the roster).

.PARAMETER FanOut
    Team fan-out mode. Instead of a single -Recipient/-GitHubUser report, run research ONCE
    (team-wide, raw) and then loop the shared opt-in roster, emailing each active subscriber
    a report customized to their GitHub login and reporting level (individual vs team). The
    roster lives in the shared Google Drive store "<drive>:\My Drive\Claude\PRReport"
    (managed via Manage-PRReportRoster.ps1 / /pw-pr-reporting). If the roster has no active
    subscribers, the run is a no-op. See ai/scripts/PRReport/README.md.

.PARAMETER Schedule
    Register as a daily Windows Task Scheduler task at the specified time.
    Requires an elevated (Administrator) PowerShell prompt.
    Removes any existing task(s) covered by the selected phase before creating:
    - research: removes existing "PR Report - Research"
    - email:    removes existing "PR Report - Email"
    - both:     removes all three ("PR Report - Research", "- Email", "- Both")

.PARAMETER DryRun
    If set, prints the command without executing.

.EXAMPLE
    .\Invoke-PRReport.ps1
    Runs research then email sequentially with default settings.

.EXAMPLE
    .\Invoke-PRReport.ps1 -Phase research
    Runs research phase only (data collection + investigation, no email).

.EXAMPLE
    .\Invoke-PRReport.ps1 -Phase email
    Runs email phase only (reads research findings, sends email).

.EXAMPLE
    .\Invoke-PRReport.ps1 -Schedule "9:30AM"
    Registers a daily task at 9:30 AM that runs both phases sequentially.
    Scheduled after Invoke-DailyReport.ps1 (8:05 AM) to avoid resource contention.

.EXAMPLE
    .\Invoke-PRReport.ps1 -Date 2026-05-15
    Backfill the PR report for May 15, 2026.

.EXAMPLE
    .\Invoke-PRReport.ps1 -DryRun
    Shows what would be executed without running.

.NOTES
    See ai/docs/scheduled-tasks-guide.md for Task Scheduler setup.

    Recommended scheduled task:
    - "PR Report - Both" at 9:30 AM (runs after the daily report at 8:05 AM)
#>

param(
    [string]$Recipient = "brendanx@proteinms.net",
    [string]$Model = "claude-opus-4-6",
    [int]$MaxTurns = 0,
    [ValidateSet("research", "email", "both")]
    [string]$Phase = "both",
    [string]$Date,
    [string]$GitHubUser = "brendanx67",
    [switch]$FanOut,
    [string]$Schedule,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

# Ensure UTF-8 encoding throughout the pipeline
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# Configuration
# Derive project root from script location: ai/scripts/Invoke-PRReport.ps1 -> ai/ -> root
$aiRoot = Split-Path -Parent $PSScriptRoot
$WorkDir = Split-Path -Parent $aiRoot

# ─────────────────────────────────────────────────────────────
# Resolve report date
# ─────────────────────────────────────────────────────────────

if ($Date) {
    try {
        $ParsedDate = [DateTime]::ParseExact($Date, [string[]]@("yyyy-MM-dd", "yyyyMMdd"), [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None)
    }
    catch {
        Write-Error "Invalid date format: '$Date'. Use YYYY-MM-DD or YYYYMMDD."
        exit 1
    }
    $DateFolder = $ParsedDate.ToString("yyyy-MM-dd")
    $DateCompact = $ParsedDate.ToString("yyyyMMdd")
} else {
    $DateFolder = Get-Date -Format "yyyy-MM-dd"
    $DateCompact = Get-Date -Format "yyyyMMdd"
}

# ─────────────────────────────────────────────────────────────
# Task Scheduler registration
# ─────────────────────────────────────────────────────────────

if ($Schedule) {
    try {
        $ScheduleTime = [DateTime]::Parse($Schedule)
    }
    catch {
        Write-Error "Invalid time format: '$Schedule'. Use formats like '9:30AM', '09:30', '21:30'."
        exit 1
    }

    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Error "Scheduling requires an elevated (Administrator) PowerShell prompt."
        exit 1
    }

    $TaskPrefix = "PR Report"
    # Fan-out and single-recipient are mutually exclusive task families; removing the other
    # family's tasks here avoids a machine quietly running both (double email, double cost).
    if ($FanOut) {
        $TasksToRemove = @("$TaskPrefix - Fanout", "$TaskPrefix - Research", "$TaskPrefix - Email", "$TaskPrefix - Both")
    } else {
        $TasksToRemove = switch ($Phase) {
            "research" { @("$TaskPrefix - Research", "$TaskPrefix - Fanout") }
            "email"    { @("$TaskPrefix - Email", "$TaskPrefix - Fanout") }
            "both"     { @("$TaskPrefix - Research", "$TaskPrefix - Email", "$TaskPrefix - Both", "$TaskPrefix - Fanout") }
        }
    }

    foreach ($Name in $TasksToRemove) {
        $Existing = Get-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue
        if ($Existing) {
            Unregister-ScheduledTask -TaskName $Name -Confirm:$false
            Write-Host "Removed existing task: $Name"
        }
    }

    $ScriptPath = $PSCommandPath
    if ($FanOut) {
        $TaskName = "$TaskPrefix - Fanout"
        $Arguments = "-NoProfile -WindowStyle Hidden -File `"$ScriptPath`" -FanOut -Phase $Phase -Model `"$Model`""
        $TaskDescription = "Claude Code PR activity report — team fan-out ($Phase phase, per-roster)"
    } else {
        $PhaseCapitalized = (Get-Culture).TextInfo.ToTitleCase($Phase)
        $TaskName = "$TaskPrefix - $PhaseCapitalized"
        $Arguments = "-NoProfile -WindowStyle Hidden -File `"$ScriptPath`" -Phase $Phase -Recipient `"$Recipient`" -Model `"$Model`" -GitHubUser `"$GitHubUser`""
        $TaskDescription = "Claude Code PR activity report ($Phase phase)"
    }

    $Action = New-ScheduledTaskAction -Execute "pwsh" -Argument $Arguments -WorkingDirectory $WorkDir
    $Trigger = New-ScheduledTaskTrigger -Daily -At $ScheduleTime
    $Settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -ExecutionTimeLimit (New-TimeSpan -Hours 2)

    Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger `
        -Settings $Settings -Description $TaskDescription | Out-Null

    Write-Host "Created task: $TaskName at $($ScheduleTime.ToString('h:mm tt')) daily"
    exit 0
}

# ─────────────────────────────────────────────────────────────
# Phase configuration helpers
# ─────────────────────────────────────────────────────────────

function Get-PhasePrompt([string]$PhaseName) {
    switch ($PhaseName) {
        "research" {
            $CommandFile = ".claude/commands/pw-pr-research.md"
            if ($FanOut) {
                @"
You are running as a scheduled automation task. Slash commands and skills do not work in non-interactive mode.

FIRST: Read ai/CLAUDE.md to understand project rules (especially: use pwsh not powershell, backslashes for file paths).

THEN: Read $CommandFile and follow it to run the research phase — in TEAM FAN-OUT MODE (see the "Fan-out mode" section).

Key points:
- Use the gh CLI (pre-authorized) for all GitHub queries
- Use pwsh (not powershell) for any shell commands
- The report date is $DateFolder (use $DateCompact for filenames)
- FAN-OUT: the active subscribers are listed in ai/.tmp/pr-report/$DateFolder/roster-active.json
  (each has email, github_login, level). Gather the team-wide raw data ONCE, AND a personal
  slice for EACH subscriber's github_login (awaiting-their-review, their open PRs with a
  pile-up self-check at 3+ non-draft, their assigned issues, their TODOs). Write each to
  ai/.tmp/pr-report/$DateFolder/subscribers/<github_login>.json (+ .md narrative).
- Do NOT send email - only collect data and write findings to files
- Output directory: ai/.tmp/pr-report/$DateFolder/
- Write the manifest file at the end: ai/.tmp/pr-report/$DateFolder/manifest.json (include a
  "subscribers" list of the github_logins you produced slices for)
- If gh CLI fails, write a manifest with research_completed: false
"@
            } else {
                @"
You are running as a scheduled automation task. Slash commands and skills do not work in non-interactive mode.

FIRST: Read ai/CLAUDE.md to understand project rules (especially: use pwsh not powershell, backslashes for file paths).

THEN: Read $CommandFile and follow those instructions to run the research phase of the PR activity report.

Key points:
- Use the gh CLI (pre-authorized) for all GitHub queries
- Use pwsh (not powershell) for any shell commands
- The report date is $DateFolder (use $DateCompact for filenames)
- The focus user (review queue, authored PRs/issues) is: $GitHubUser
- Do NOT send email - only collect data and write findings to files
- Output directory: ai/.tmp/pr-report/$DateFolder/
- Write the manifest file at the end: ai/.tmp/pr-report/$DateFolder/manifest.json
- If gh CLI fails, write a manifest with research_completed: false
"@
            }
        }
        "email" {
            $CommandFile = ".claude/commands/pw-pr-email.md"
            if ($FanOut) {
                @"
You are running as a scheduled automation task. Slash commands and skills do not work in non-interactive mode.

FIRST: Read ai/CLAUDE.md to understand project rules (especially: use pwsh not powershell, backslashes for file paths).

THEN: Read $CommandFile and follow it to compose and send emails — in TEAM FAN-OUT MODE (see the "Fan-out mode" section).

Key points:
- The report date is $DateFolder
- FAN-OUT: loop ai/.tmp/pr-report/$DateFolder/roster-active.json. For EACH subscriber, read
  the shared team findings AND their personal slice
  (ai/.tmp/pr-report/$DateFolder/subscribers/<github_login>.json) and send ONE email to their
  email address, rendered at their level: "individual" = personal slice + self pile-up
  warning; "team" = the full cross-team report.
- If research files are missing entirely, send ONE error email to each subscriber per the command file
- Use Gmail MCP tools to send the email(s)
- Do NOT archive any inbox emails (this report has no inbox dependency)
"@
            } else {
                @"
You are running as a scheduled automation task. Slash commands and skills do not work in non-interactive mode.

FIRST: Read ai/CLAUDE.md to understand project rules (especially: use pwsh not powershell, backslashes for file paths).

THEN: Read $CommandFile and follow those instructions to compose and send the PR activity report email.

Email recipient: $Recipient

Key points:
- The report date is $DateFolder
- Read research findings from ai/.tmp/pr-report/$DateFolder/
- If research files are missing, send an ERROR email as specified in the command file
- Use Gmail MCP tools to send the email
- Do NOT archive any inbox emails (this report has no inbox dependency)
"@
            }
        }
    }
}

function Get-PhaseTools([string]$PhaseName) {
    switch ($PhaseName) {
        "research" {
            # Research phase: gh CLI (read-only), git (read-only), Read/Write/Glob/Grep
            # NO email send, NO LabKey investigation tools
            @(
                # File operations
                "Read",
                "Write",
                "Edit",
                "Glob",
                "Grep",
                # Bash - read-only git for TODO authorship and history
                "Bash(git log:*)",
                "Bash(git blame:*)",
                "Bash(git show:*)",
                "Bash(git -C:*)",
                "Bash(grep:*)",
                # Bash - read-only gh for PR/issue queries
                "Bash(gh pr list:*)",
                "Bash(gh pr view:*)",
                "Bash(gh pr diff:*)",
                "Bash(gh issue list:*)",
                "Bash(gh issue view:*)",
                "Bash(gh api:*)",
                "Bash(gh search:*)"
            ) -join ","
        }
        "email" {
            # Email phase: Gmail send, Read/Glob/Grep for reading findings
            @(
                "Read",
                "Glob",
                "Grep",
                "mcp__gmail__send_email"
            ) -join ","
        }
    }
}

function Get-PhaseMaxTurns([string]$PhaseName) {
    # In fan-out a single session covers every subscriber, so the budget scales with roster
    # size: research builds N personal slices, email composes+sends N messages. Capped so a
    # runaway roster can't request an unbounded turn budget.
    switch ($PhaseName) {
        "research" {
            if ($FanOut) { [math]::Min(250, 80 + 12 * [math]::Max(1, $ActiveSubscriberCount)) } else { 80 }
        }
        "email" {
            if ($FanOut) { [math]::Min(220, 30 + 15 * [math]::Max(1, $ActiveSubscriberCount)) } else { 30 }
        }
    }
}

# ─────────────────────────────────────────────────────────────
# Determine phases to run
# ─────────────────────────────────────────────────────────────

$PhasesToRun = if ($Phase -eq "both") { @("research", "email") } else { @($Phase) }

# ─────────────────────────────────────────────────────────────
# Fan-out: resolve the active roster (read-only; safe under -DryRun)
# ─────────────────────────────────────────────────────────────

$ActiveSubscribers = @()
$ActiveSubscriberCount = 0
if ($FanOut) {
    . (Join-Path $PSScriptRoot 'PRReport\PRReportStore.ps1')
    $StoreCheck = Test-PRReportStore
    if (-not $StoreCheck.Ok) {
        Write-Error ("Fan-out aborted — not the shared PRReport store: {0}" -f $StoreCheck.Reason)
        exit 1
    }
    $ActiveSubscribers = @(Get-PRReportRoster -ActiveOnly)
    $ActiveSubscriberCount = $ActiveSubscribers.Count
}

$TimeStamp = Get-Date -Format "HHmm"
$LogDir = Join-Path $WorkDir "ai\.tmp\pr-report\$DateFolder"
$LogFile = Join-Path $LogDir "$Phase-$TimeStamp.log"

# ─────────────────────────────────────────────────────────────
# Dry run
# ─────────────────────────────────────────────────────────────

if ($DryRun) {
    Write-Host "Would execute:" -ForegroundColor Cyan
    Write-Host "  Phase: $Phase"
    Write-Host "  Date: $DateFolder"
    if ($FanOut) {
        Write-Host "  Mode: FAN-OUT (per-roster)" -ForegroundColor Cyan
        Write-Host "  Store: $($StoreCheck.Path)"
        Write-Host "  Active subscribers: $ActiveSubscriberCount"
        $ActiveSubscribers | ForEach-Object { Write-Host ("    - {0,-26} {1,-14} {2}" -f $_.email, $_.github_login, $_.level) }
    } else {
        Write-Host "  GitHub user: $GitHubUser"
        Write-Host "  Recipient: $Recipient"
    }
    Write-Host "  Working directory: $WorkDir"
    Write-Host "  Git pull ai/: git pull origin master"
    Write-Host "  Git pull pwiz/: git pull origin master"
    Write-Host "  Log file: $LogFile"
    Write-Host ""
    foreach ($P in $PhasesToRun) {
        $Turns = if ($MaxTurns -gt 0) { $MaxTurns } else { Get-PhaseMaxTurns $P }
        Write-Host "--- Phase: $P (max-turns: $Turns) ---" -ForegroundColor Yellow
        Write-Host "  Command file: .claude/commands/pw-pr-$P.md"
        Write-Host "  Allowed tools:"
        (Get-PhaseTools $P) -split "," | ForEach-Object { Write-Host "    - $_" }
        Write-Host ""
    }
    exit 0
}

# ─────────────────────────────────────────────────────────────
# Main execution
# ─────────────────────────────────────────────────────────────

if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

# Fan-out: no active subscribers => nothing to do. Snapshot the active roster for the phases.
if ($FanOut) {
    if ($ActiveSubscriberCount -eq 0) {
        Write-Host "Fan-out: roster has no active subscribers — nothing to send. Exiting."
        exit 0
    }
    $RosterSnapshot = Join-Path $LogDir "roster-active.json"
    $ActiveSubscribers |
        Select-Object email, github_login, level |
        ConvertTo-Json -Depth 4 -AsArray |
        Out-File -FilePath $RosterSnapshot -Encoding UTF8
}

$StartTime = Get-Date
$ModeLabel = if ($FanOut) { "fan-out, $ActiveSubscriberCount subscriber(s)" } else { "single: $Recipient" }
"[$StartTime] Starting Claude Code PR report (phase: $Phase; $ModeLabel)" | Out-File -FilePath $LogFile -Encoding UTF8

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

Push-Location $WorkDir
$OverallExitCode = 0

try {
    foreach ($CurrentPhase in $PhasesToRun) {
        $PhasePrompt = Get-PhasePrompt $CurrentPhase
        $PhaseTools = Get-PhaseTools $CurrentPhase
        $PhaseTurns = if ($MaxTurns -gt 0) { $MaxTurns } else { Get-PhaseMaxTurns $CurrentPhase }

        "[$(Get-Date)] Starting $CurrentPhase phase (max-turns: $PhaseTurns)..." | Out-File -FilePath $LogFile -Append -Encoding UTF8

        $ClaudeArgs = @(
            "-p", $PhasePrompt,
            "--allowedTools", $PhaseTools,
            "--max-turns", $PhaseTurns,
            "--model", $Model
        )

        # Use "Continue" so claude's stderr status messages don't terminate the script.
        $SavedEAP = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        & claude @ClaudeArgs 2>&1 | ForEach-Object {
            "$_" | Out-File -FilePath $LogFile -Append -Encoding UTF8
        }
        $PhaseExitCode = $LASTEXITCODE
        $ErrorActionPreference = $SavedEAP

        "[$(Get-Date)] Phase '$CurrentPhase' completed with exit code $PhaseExitCode" | Out-File -FilePath $LogFile -Append -Encoding UTF8

        if ($PhaseExitCode -ne 0) {
            $OverallExitCode = $PhaseExitCode
        }
    }
}
finally {
    Pop-Location
}

$EndTime = Get-Date
$Duration = $EndTime - $StartTime
"[$EndTime] Completed (exit code: $OverallExitCode, duration: $($Duration.TotalMinutes.ToString('F1')) minutes)" | Out-File -FilePath $LogFile -Append -Encoding UTF8

if ($OverallExitCode -ne 0) {
    Write-Error "One or more phases failed. See log: $LogFile"
}

# Clean up old date folders (keep 30 days)
$PRReportRoot = Join-Path $WorkDir "ai\.tmp\pr-report"
if (Test-Path $PRReportRoot) {
    Get-ChildItem -Path $PRReportRoot -Directory |
        Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}$' -and $_.Name -lt (Get-Date).AddDays(-30).ToString("yyyy-MM-dd") } |
        Remove-Item -Recurse -Force
}

exit $OverallExitCode
