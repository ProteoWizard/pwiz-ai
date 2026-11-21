<#
.SYNOPSIS
    Install the daily graph-regeneration task on THIS machine (run on ONE always-on host).

.DESCRIPTION
    Registers a per-user task that runs Update-ClaudeUsageGraphs.ps1 once a day at a fixed
    offset AFTER the per-machine snapshot tasks (default 13:30 UTC, vs the 13:00 UTC
    snapshots), so it folds in whatever has synced from Google Drive and refreshes the shared
    charts.

    Run this on only ONE machine — ideally an always-on workstation (not a laptop that
    sleeps). The snapshot tasks (Register-ClaudeUsageTask / Setup-ThisMachine) still run on
    every machine; this adds the central charting step on the chosen host. Re-running updates
    the task in place. Requires R (Rscript) on this host.

    The task opens no window. Each run appends one result line, with any warnings, to
    ai\.tmp\usage\<TaskName>.log; that line, not the task's Last Run Result, says whether the
    run worked. See UsageTask.ps1.

.PARAMETER At
    Time of day to run. Default 13:30 UTC, which is 06:30 Pacific daylight time and 05:30
    Pacific standard time. A local value such as '06:30' is stored as the instant it names
    today.
.PARAMETER TaskName
    Scheduled task name. Default 'ClaudeUsageGraphs'.
.PARAMETER RunNow
    Also trigger once after registering, and print its result line.
#>
[CmdletBinding()]
param(
    [datetime]$At = '13:30Z',
    [string]$TaskName = 'ClaudeUsageGraphs',
    [switch]$RunNow
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'UsageTask.ps1')

# Rendering the charts in R takes far longer than a snapshot, so wait longer for the result.
Register-UsageDailyTask -TaskName $TaskName -At $At `
    -Script 'Update-ClaudeUsageGraphs.ps1' -RunNow:$RunNow -RunNowTimeoutSeconds 600
