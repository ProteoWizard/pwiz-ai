<#
.SYNOPSIS
    Re-combine the team CSVs and regenerate the ggplot2 charts (PNGs + PDF).

.DESCRIPTION
    Meant to run on ONE always-on machine, a little after the per-machine snapshot tasks
    (e.g. 06:30), so it folds in whatever has synced from Google Drive and refreshes the
    shared charts in <store>\plots. Data is eventually consistent: a machine that was
    asleep at run time appears in the next day's charts.

    Steps: Combine-ClaudeUsage.ps1 (union latest synced CSVs) -> usage_plots.R via Rscript.
    Locates Rscript on PATH, else the newest C:\Program Files\R\R-*\bin\Rscript.exe.

.PARAMETER DataDir
    Data folder. Default: <resolved Google Drive store>\data
#>
[CmdletBinding()]
param(
    [string]$DataDir = ''
)
$ErrorActionPreference = 'Stop'

# 1. Re-union the per-machine CSVs (picks up whatever has synced).
$combine = Join-Path $PSScriptRoot 'Combine-ClaudeUsage.ps1'
& $combine -DataDir $DataDir | Out-Host

# 2. Locate Rscript.
$rscript = (Get-Command Rscript.exe -ErrorAction SilentlyContinue).Source
if (-not $rscript) {
    $cand = Get-ChildItem 'C:\Program Files\R\R-*\bin\Rscript.exe' -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending | Select-Object -First 1
    if ($cand) { $rscript = $cand.FullName }
}
if (-not $rscript) { throw 'Rscript not found. Install R, or add Rscript.exe to PATH.' }

# 3. Render the charts (PNGs + claude_usage.pdf) into the shared store's plots folder.
$plots = Join-Path $PSScriptRoot 'usage_plots.R'
Write-Host ("Rendering charts with {0}" -f $rscript)
& $rscript $plots
if ($LASTEXITCODE -ne 0) { throw "Rscript failed with exit code $LASTEXITCODE (charts may be incomplete)" }
