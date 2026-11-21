<#
.SYNOPSIS
    Install (or refresh) the daily Windows Scheduled Task that snapshots Claude usage on
    THIS machine and re-combines the team CSV.

.DESCRIPTION
    Run once per machine. Registers a per-user task that each day runs
    Snapshot-ClaudeUsage.ps1 then Combine-ClaudeUsage.ps1 from this repo folder
    (ai\scripts\Usage). Runs only while logged on (no stored password) and uses
    -StartWhenAvailable, so a missed day is caught up at next logon. Re-running updates
    the task in place.

    The task opens no window. Each run appends one result line to
    ai\.tmp\usage\<TaskName>.log; that line, not the task's Last Run Result, says whether the
    run worked. See UsageTask.ps1.

.PARAMETER At
    Time of day to run. Default 13:00 UTC, which is 06:00 Pacific daylight time and 05:00
    Pacific standard time: the same instant on every machine, half an hour before the charts
    are drawn. A local value such as '06:00' is stored as the instant it names today.
.PARAMETER TaskName
    Scheduled task name. Default 'ClaudeUsageSnapshot'.
.PARAMETER RunNow
    Also trigger the task immediately after registering, and print its result line.
#>
[CmdletBinding()]
param(
    [datetime]$At = '13:00Z',
    [string]$TaskName = 'ClaudeUsageSnapshot',
    [switch]$RunNow
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'UsageTask.ps1')

Register-UsageDailyTask -TaskName $TaskName -At $At `
    -Script 'Snapshot-ClaudeUsage.ps1', 'Combine-ClaudeUsage.ps1' -RunNow:$RunNow
