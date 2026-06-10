<#
.SYNOPSIS
    Install the daily graph-regeneration task on THIS machine (run on ONE always-on host).

.DESCRIPTION
    Registers a per-user task that runs Update-ClaudeUsageGraphs.ps1 once a day at a fixed
    offset AFTER the per-machine snapshot tasks (default 06:30, vs the 06:00 snapshots), so
    it folds in whatever has synced from Google Drive and refreshes the shared charts.

    Run this on only ONE machine — ideally an always-on workstation (not a laptop that
    sleeps). The snapshot tasks (Register-ClaudeUsageTask / Setup-ThisMachine) still run on
    every machine; this adds the central charting step on the chosen host. Re-running updates
    the task in place. Requires R (Rscript) on this host.

.PARAMETER At
    Time of day to run. Default 06:30.
.PARAMETER TaskName
    Scheduled task name. Default 'ClaudeUsageGraphs'.
.PARAMETER RunNow
    Also trigger once after registering, to verify.
#>
[CmdletBinding()]
param(
    [datetime]$At = '06:30',
    [string]$TaskName = 'ClaudeUsageGraphs',
    [switch]$RunNow
)
$ErrorActionPreference = 'Stop'

$pwsh = (Get-Command pwsh.exe -ErrorAction SilentlyContinue).Source
if (-not $pwsh) { throw 'pwsh.exe (PowerShell 7) not found on PATH.' }

$updater = Join-Path $PSScriptRoot 'Update-ClaudeUsageGraphs.ps1'
if (-not (Test-Path $updater)) { throw "Missing script: $updater" }

$action    = New-ScheduledTaskAction -Execute $pwsh -Argument "-NoProfile -NonInteractive -File `"$updater`""
$trigger   = New-ScheduledTaskTrigger -Daily -At $At
$settings  = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopOnIdleEnd -ExecutionTimeLimit (New-TimeSpan -Minutes 30)
$principal = New-ScheduledTaskPrincipal -UserId ("{0}\{1}" -f $env:USERDOMAIN, $env:USERNAME) -LogonType Interactive -RunLevel Limited

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
    -Settings $settings -Principal $principal -Force | Out-Null

Write-Host ("Registered task '{0}' -> daily at {1:HH:mm} on {2}" -f $TaskName, $At, $env:COMPUTERNAME)
Write-Host ("Action: {0} -NoProfile -NonInteractive -File {1}" -f $pwsh, $updater)

if ($RunNow) {
    Write-Host 'Triggering once now to verify...'
    Start-ScheduledTask -TaskName $TaskName
    Start-Sleep -Seconds 20
    $info = Get-ScheduledTaskInfo -TaskName $TaskName
    Write-Host ("LastRunTime: {0}  LastResult: 0x{1:X}" -f $info.LastRunTime, $info.LastTaskResult)
}
