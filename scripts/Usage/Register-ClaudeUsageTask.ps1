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

.PARAMETER At
    Time of day to run. Default 06:00.
.PARAMETER TaskName
    Scheduled task name. Default 'ClaudeUsageSnapshot'.
.PARAMETER RunNow
    Also trigger the task immediately after registering, to verify it works.
#>
[CmdletBinding()]
param(
    [datetime]$At = '06:00',
    [string]$TaskName = 'ClaudeUsageSnapshot',
    [switch]$RunNow
)
$ErrorActionPreference = 'Stop'

$pwsh = (Get-Command pwsh.exe -ErrorAction SilentlyContinue).Source
if (-not $pwsh) { throw 'pwsh.exe (PowerShell 7) not found on PATH.' }

$snapshot = Join-Path $PSScriptRoot 'Snapshot-ClaudeUsage.ps1'
$combine  = Join-Path $PSScriptRoot 'Combine-ClaudeUsage.ps1'
foreach ($p in @($snapshot, $combine)) { if (-not (Test-Path $p)) { throw "Missing script: $p" } }

$cmd = "& '$snapshot'; & '$combine'"
$action = New-ScheduledTaskAction -Execute $pwsh -Argument "-NoProfile -NonInteractive -Command `"$cmd`""

$trigger   = New-ScheduledTaskTrigger -Daily -At $At
$settings  = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopOnIdleEnd -ExecutionTimeLimit (New-TimeSpan -Minutes 30)
$principal = New-ScheduledTaskPrincipal -UserId ("{0}\{1}" -f $env:USERDOMAIN, $env:USERNAME) -LogonType Interactive -RunLevel Limited

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
    -Settings $settings -Principal $principal -Force | Out-Null

Write-Host ("Registered task '{0}' -> daily at {1:HH:mm} on {2}" -f $TaskName, $At, $env:COMPUTERNAME)
Write-Host ("Action: {0} -NoProfile -NonInteractive -Command <snapshot; combine>" -f $pwsh)

if ($RunNow) {
    Write-Host 'Triggering once now to verify...'
    Start-ScheduledTask -TaskName $TaskName
    Start-Sleep -Seconds 8
    $info = Get-ScheduledTaskInfo -TaskName $TaskName
    Write-Host ("LastRunTime: {0}  LastResult: 0x{1:X}" -f $info.LastRunTime, $info.LastTaskResult)
}
