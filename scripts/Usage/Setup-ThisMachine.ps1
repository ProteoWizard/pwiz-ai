<#
.SYNOPSIS
    One-command onboarding for a machine: set transcript retention, register the daily
    usage snapshot task, and take a first snapshot. Run once per machine.

.DESCRIPTION
    Tooling lives in pwiz-ai (ai\scripts\Usage); data lives on Google Drive. Steps:
      1. Sets "cleanupPeriodDays" in ~/.claude/settings.json (backs the file up first) so
         raw transcripts survive long enough to backfill. Existing settings preserved.
      2. Registers/refreshes the daily Scheduled Task (Register-ClaudeUsageTask.ps1).
      3. Triggers it once so the data CSV and charts populate immediately.

    Safe to re-run; every step is idempotent.

.PARAMETER RetentionDays
    Value for cleanupPeriodDays. Default 365.
.PARAMETER At
    Daily run time for the task. Default 06:00.
#>
[CmdletBinding()]
param(
    [int]$RetentionDays = 365,
    [datetime]$At = '06:00'
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Resolve-UsageStore.ps1')

# --- 1. Transcript retention -----------------------------------------------------------
$settingsPath = Join-Path $env:USERPROFILE '.claude\settings.json'
if (Test-Path $settingsPath) {
    Copy-Item $settingsPath "$settingsPath.bak" -Force   # backup before touching it
    $json = Get-Content $settingsPath -Raw | ConvertFrom-Json
} else {
    New-Item -ItemType Directory -Force -Path (Split-Path $settingsPath) | Out-Null
    $json = [pscustomobject]@{}
}
if ($json.PSObject.Properties.Name -contains 'cleanupPeriodDays') {
    $json.cleanupPeriodDays = $RetentionDays
} else {
    $json | Add-Member -NotePropertyName cleanupPeriodDays -NotePropertyValue $RetentionDays
}
$json | ConvertTo-Json -Depth 32 | Set-Content $settingsPath -Encoding UTF8
Write-Host ("[1/3] cleanupPeriodDays = {0} in {1}" -f $RetentionDays, $settingsPath)

# --- 2 & 3. Register the daily task and run it once ------------------------------------
$register = Join-Path $PSScriptRoot 'Register-ClaudeUsageTask.ps1'
if (-not (Test-Path $register)) { throw "Missing $register" }
Write-Host '[2/3] Registering daily task and running a first capture...'
& $register -At $At -RunNow

Write-Host ''
Write-Host '[3/3] Done. This machine now snapshots Claude usage daily into the shared store.'
try { Write-Host ("      Data: {0}" -f (Join-Path (Resolve-UsageStore) 'data')) } catch { Write-Host "      (data store will resolve once the Drive folder is synced)" }
