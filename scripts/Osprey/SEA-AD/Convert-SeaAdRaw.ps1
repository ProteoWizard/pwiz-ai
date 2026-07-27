<#
.SYNOPSIS
    Convert SEA-AD Pilot-MTG DIA .raw files to mzML with Mike MacCoss's msconvert settings.

.DESCRIPTION
    Only needed if you are starting from the .raw files. The lab share already holds the
    converted mzML AND their .spectra.bin caches, which skips both this step and the
    first-run cache build -- prefer it when you can reach it (see README).

    Idempotent and re-runnable: skips 0-byte files, files still downloading (a
    present-day timestamp -- WinSCP restores the source date only on completion), and any
    .raw that already has an .mzML beside it. Run it now for the ready files and again
    later to sweep up the rest.

    The actual command line lives in convert-one.cmd beside this script, unchanged from
    the original, because its titleMaker quoting is cmd-specific and does not survive
    translation to PowerShell.

.PARAMETER Root
    Dataset root holding Astral-DIA\. Defaults to $env:OSPREY_SEAAD_ROOT, else the parent
    of $env:OSPREY_SEAAD_DIR.

.PARAMETER MsConvert
    Full path to msconvert.exe. Defaults to $env:MSCONVERT, else PATH, else the newest
    ProteoWizard install found in the usual locations.

.PARAMETER Throttle
    Concurrent conversions. 4 is what the original runs used; going wider is disk-bound
    on a single spindle and gains little.

.EXAMPLE
    .\Convert-SeaAdRaw.ps1 -WhatIf     # what would convert, and with which msconvert
#>
#requires -Version 7
param(
    [string]$Root,
    [string]$MsConvert,
    [int]$Throttle = 4,
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
$readme = Join-Path $PSScriptRoot 'README.md'

if (-not $Root) { $Root = [Environment]::GetEnvironmentVariable('OSPREY_SEAAD_ROOT') }
if (-not $Root) {
    $mzml = [Environment]::GetEnvironmentVariable('OSPREY_SEAAD_DIR')
    # $env:OSPREY_SEAAD_DIR points at <root>\Astral-DIA\mzml, so the root is two up.
    if ($mzml -and (Test-Path $mzml)) { $Root = Split-Path (Split-Path $mzml -Parent) -Parent }
}
if (-not $Root -or -not (Test-Path $Root)) {
    throw "Could not locate the SEA-AD dataset root. Pass -Root, or set `$env:OSPREY_SEAAD_ROOT. See $readme."
}
$Root = (Resolve-Path $Root).Path

if (-not $MsConvert) { $MsConvert = [Environment]::GetEnvironmentVariable('MSCONVERT') }
if (-not $MsConvert) { $MsConvert = (Get-Command msconvert.exe -ErrorAction SilentlyContinue)?.Source }
if (-not $MsConvert) {
    $candidates = @(
        "$env:LOCALAPPDATA\Apps\ProteoWizard*\msconvert.exe"
        "$env:ProgramFiles\ProteoWizard\*\msconvert.exe"
        "${env:ProgramFiles(x86)}\ProteoWizard\*\msconvert.exe"
    )
    $MsConvert = @(Get-ChildItem -Path $candidates -ErrorAction SilentlyContinue |
                   Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
}
if (-not $MsConvert -or -not (Test-Path $MsConvert)) {
    throw ("msconvert.exe not found. Pass -MsConvert, set `$env:MSCONVERT, or put it on PATH. " +
           "It ships with ProteoWizard.")
}
$MsConvert = (Resolve-Path $MsConvert).Path

$cmd = Join-Path $PSScriptRoot 'convert-one.cmd'
if (-not (Test-Path $cmd)) { throw "convert-one.cmd not found beside this script." }
$logDir = Join-Path $Root '_convert-logs'
$master = Join-Path $logDir 'master.log'
$today = (Get-Date).Date

$dirs = @(
    (Join-Path $Root 'Astral-DIA'),
    (Join-Path $Root 'Astral-DIA\Library')
)

$eligible = foreach ($d in $dirs) {
    if (Test-Path $d) {
        Get-ChildItem $d -Filter *.raw -File | Where-Object {
            $_.Length -gt 0 -and
            $_.LastWriteTime.Date -lt $today -and
            -not (Test-Path (Join-Path $_.DirectoryName ($_.BaseName + '.mzML')))
        }
    }
}
$eligible = @($eligible)

Write-Host ""
Write-Host "=== SEA-AD raw conversion ===" -ForegroundColor Cyan
Write-Host ("  root      : {0}" -f $Root)
Write-Host ("  msconvert : {0}" -f $MsConvert)
Write-Host ("  eligible  : {0} file(s), throttle {1}" -f $eligible.Count, $Throttle)
Write-Host ""

if ($WhatIf) {
    $eligible | ForEach-Object { Write-Host ("  would convert: {0}" -f $_.FullName) }
    Write-Host "-WhatIf: nothing converted." -ForegroundColor Yellow
    return
}
if ($eligible.Count -eq 0) {
    Write-Host "Nothing to do." -ForegroundColor Green
    return
}

New-Item -ItemType Directory -Force -Path $logDir | Out-Null
"[{0}] Starting run: {1} eligible file(s), throttle {2}, msconvert {3}" -f
    (Get-Date -Format s), $eligible.Count, $Throttle, $MsConvert |
    Tee-Object -FilePath $master -Append

$results = $eligible | ForEach-Object -ThrottleLimit $Throttle -Parallel {
    $cmd = $using:cmd
    $logDir = $using:logDir
    $msconvert = $using:MsConvert
    $raw = $_.FullName
    $out = $_.DirectoryName
    $mz = Join-Path $out ($_.BaseName + '.mzML')
    $log = Join-Path $logDir ($_.BaseName + '.log')
    $start = Get-Date
    & $cmd $raw $out $msconvert *>&1 | Out-File -FilePath $log -Encoding utf8
    $code = $LASTEXITCODE
    [pscustomobject]@{
        Name    = $_.Name
        Ok      = ($code -eq 0 -and (Test-Path $mz))
        Exit    = $code
        Minutes = [math]::Round(((Get-Date) - $start).TotalMinutes, 1)
        SizeMB  = if (Test-Path $mz) { [math]::Round((Get-Item $mz).Length / 1MB, 1) } else { 0 }
    }
}

$okCount = @($results | Where-Object Ok).Count
$failCount = @($results).Count - $okCount
foreach ($r in $results | Sort-Object Name) {
    $tag = if ($r.Ok) { 'OK  ' } else { "FAIL(exit=$($r.Exit))" }
    "[{0}] {1} {2} ({3} min, {4} MB)" -f (Get-Date -Format s), $tag, $r.Name, $r.Minutes, $r.SizeMB |
        Tee-Object -FilePath $master -Append
}
"[{0}] Done. {1} OK, {2} FAILED." -f (Get-Date -Format s), $okCount, $failCount |
    Tee-Object -FilePath $master -Append
if ($failCount -gt 0) { exit 1 }
