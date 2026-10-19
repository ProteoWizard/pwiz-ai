<#
.SYNOPSIS
    Union every teammate/machine's usage_<MACHINE>.csv into one usage_combined.csv.

.DESCRIPTION
    Tooling in pwiz-ai (ai\scripts\Usage); DATA on Google Drive (located via
    Resolve-UsageStore). Concatenates all per-machine CSVs in the store's data folder into
    usage_combined.csv — the file the R/ggplot2 charts read — and prints per-user,
    per-machine, and recent-day summaries.

.PARAMETER DataDir
    Data folder. Default: <resolved Google Drive store>\data
#>
[CmdletBinding()]
param(
    [string]$DataDir = ''
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Resolve-UsageStore.ps1')

if (-not $DataDir) { $DataDir = Join-Path (Resolve-UsageStore) 'data' }
$DataDir = (Resolve-Path $DataDir).Path

$files = Get-ChildItem -Path $DataDir -Filter 'usage_*.csv' |
         Where-Object { $_.Name -ne 'usage_combined.csv' }
if (-not $files) { throw "No per-machine usage_*.csv files found in $DataDir" }

$rows = foreach ($f in $files) { Import-Csv $f.FullName }

# --- Attribution overrides: <store>\user_overrides.csv (machine,user,from,to; dates inclusive,
# blank = open-ended). For a shared Windows login that is not the person doing the work
# (e.g. SKYLINE-DEV6 logged in as maccoss). Applied here, not in Snapshot, so it holds even
# though the machine's own task keeps re-deriving its user from $env:USERNAME.
$overridesPath = Join-Path (Split-Path $DataDir -Parent) 'user_overrides.csv'
if (Test-Path $overridesPath) {
    $overrides = @(Import-Csv $overridesPath)
    foreach ($r in $rows) {
        foreach ($o in $overrides) {
            if ($r.machine -ne $o.machine) { continue }
            if ($o.from -and $r.date -lt $o.from) { continue }
            if ($o.to   -and $r.date -gt $o.to)   { continue }
            $r.user = $o.user
        }
    }
    Write-Host ("Applied {0} attribution override(s) from {1}" -f $overrides.Count, $overridesPath)
}

$rows = $rows | Sort-Object date, user, machine, model

$combined = Join-Path $DataDir 'usage_combined.csv'
$tmp = "$combined.tmp"
$rows | Export-Csv -Path $tmp -NoTypeInformation -Encoding UTF8
Move-Item -Path $tmp -Destination $combined -Force

Write-Host ("Combined {0} machine file(s) -> {1} rows" -f $files.Count, $rows.Count)
Write-Host ("Output: {0}" -f $combined)

$summary = {
    param($grouped, $label)
    Write-Host ''
    Write-Host "--- per $label ---"
    $grouped | ForEach-Object {
        [pscustomobject]@{
            $label   = $_.Name
            days     = ($_.Group | Select-Object -ExpandProperty date -Unique).Count
            tokens   = ($_.Group | Measure-Object total_tokens -Sum).Sum
            est_cost = [math]::Round(($_.Group | Measure-Object est_cost_usd -Sum).Sum, 2)
        }
    } | Format-Table -AutoSize
}
& $summary ($rows | Group-Object user)    'user'
& $summary ($rows | Group-Object machine) 'machine'

Write-Host '--- last 7 active days (all users) ---'
$rows | Group-Object date | Sort-Object Name | Select-Object -Last 7 | ForEach-Object {
    [pscustomobject]@{
        date     = $_.Name
        users    = ($_.Group | Select-Object -ExpandProperty user -Unique).Count
        tokens   = ($_.Group | Measure-Object total_tokens -Sum).Sum
        est_cost = [math]::Round(($_.Group | Measure-Object est_cost_usd -Sum).Sum, 2)
    }
} | Format-Table -AutoSize
