<#
.SYNOPSIS
    Generate per-file .scores.rust.parquet + .scores.cs.parquet for every
    mzML in a dataset via --no-join (Stage 4 exit).

.DESCRIPTION
    Iterates Dataset-Config.ps1's $ds.AllFiles, running Rust osprey and
    OspreySharp with --no-join on each file. Each tool's output lands at
    <stem>.scores.parquet and is renamed to <stem>.scores.rust.parquet /
    <stem>.scores.cs.parquet so both survive.

    Each tool computes its own calibration (no SharedCalibration here —
    this is a pure per-file Stage 1-4 smoke test + Parquet generation for
    the Stage 5 cross-impl parity walk).

.PARAMETER Dataset
    Stellar | Astral | Both (default Both).

.PARAMETER SkipRust
    Skip Rust runs (reuse existing .scores.rust.parquet).

.PARAMETER SkipCs
    Skip C# runs (reuse existing .scores.cs.parquet).

.PARAMETER CsharpRoot
    pwiz worktree with built OspreySharp.exe (auto-detect if omitted).

.PARAMETER TargetFramework
    net472 (default) or net8.0.

.PARAMETER TestBaseDir
    Override test data root (default $env:OSPREY_TEST_BASE_DIR, then
    D:\test\osprey-runs).

.EXAMPLE
    .\Generate-AllScoresParquet.ps1

.EXAMPLE
    .\Generate-AllScoresParquet.ps1 -Dataset Stellar -SkipRust
#>

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("Stellar", "Astral", "Both")]
    [string]$Dataset = "Both",

    [switch]$SkipRust = $false,
    [switch]$SkipCs = $false,

    [string]$CsharpRoot = $null,

    [ValidateSet("net472", "net8.0")]
    [string]$TargetFramework = "net8.0",

    [string]$TestBaseDir = $null
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

. "$PSScriptRoot\Dataset-Config.ps1"

$scriptRoot = Split-Path -Parent $PSCommandPath
$aiRoot = Split-Path -Parent (Split-Path -Parent $scriptRoot)
$projRoot = Split-Path -Parent $aiRoot

$rustBinary = Join-Path $projRoot "osprey\target\release\osprey.exe"
if (-not (Test-Path $rustBinary)) {
    Write-Error "Rust binary not found: $rustBinary (run Build-OspreyRust.ps1 first)"
    exit 1
}

$csharpRelBin = "pwiz_tools\OspreySharp\OspreySharp\bin\x64\Release\$TargetFramework\OspreySharp.exe"
if ($CsharpRoot) {
    $csharpBase = $CsharpRoot
} else {
    $csharpBase = $null
    foreach ($candidate in @("pwiz-work1", "pwiz", "pwiz-work2")) {
        $p = Join-Path $projRoot $candidate
        if (Test-Path (Join-Path $p $csharpRelBin)) { $csharpBase = $p; break }
    }
    if (-not $csharpBase) { $csharpBase = Join-Path $projRoot "pwiz" }
}
$csharpBinary = Join-Path $csharpBase $csharpRelBin
if (-not (Test-Path $csharpBinary)) {
    Write-Error "OspreySharp binary not found: $csharpBinary (run Build-OspreySharp.ps1 first)"
    exit 1
}

Write-Host "Rust binary: $rustBinary" -ForegroundColor DarkGray
Write-Host "C#   binary: $csharpBinary" -ForegroundColor DarkGray
Write-Host ""

$datasets = if ($Dataset -eq "Both") { @("Stellar","Astral") } else { @($Dataset) }

$totalStart = [Diagnostics.Stopwatch]::StartNew()

foreach ($dsName in $datasets) {
    $ds = Get-DatasetConfig $dsName -TestBaseDir $TestBaseDir
    $testDir = $ds.TestDir
    $library = Join-Path $testDir $ds.Library

    Write-Host ("=== {0} (TestDir: {1}) ===" -f $ds.Name, $testDir) -ForegroundColor Cyan

    foreach ($mzmlName in $ds.AllFiles) {
        $stem = [IO.Path]::GetFileNameWithoutExtension($mzmlName)
        $mzml = Join-Path $testDir $mzmlName
        if (-not (Test-Path $mzml)) {
            Write-Host ("  {0}: mzML missing — skipping" -f $stem) -ForegroundColor Red
            continue
        }
        $defaultParquet = Join-Path $testDir "$stem.scores.parquet"
        $rustParquet    = Join-Path $testDir "$stem.scores.rust.parquet"
        $csParquet      = Join-Path $testDir "$stem.scores.cs.parquet"

        Write-Host ("--- {0} ---" -f $stem) -ForegroundColor Yellow

        if (-not $SkipRust) {
            if (Test-Path $defaultParquet) { Remove-Item $defaultParquet -Force }
            $sw = [Diagnostics.Stopwatch]::StartNew()
            Push-Location $testDir
            try {
                & $rustBinary --no-join --parquet-compression snappy `
                    -i $mzml -l $library --resolution $ds.Resolution --protein-fdr 0.01 2>&1 | Out-Null
            } finally { Pop-Location }
            $sw.Stop()
            if (-not (Test-Path $defaultParquet)) {
                Write-Host ("  Rust FAILED: no {0} produced" -f [IO.Path]::GetFileName($defaultParquet)) -ForegroundColor Red
                exit 1
            }
            Move-Item $defaultParquet $rustParquet -Force
            Write-Host ("  Rust -> {0} ({1}s)" -f [IO.Path]::GetFileName($rustParquet), [math]::Round($sw.Elapsed.TotalSeconds,1)) -ForegroundColor Green
        }

        if (-not $SkipCs) {
            if (Test-Path $defaultParquet) { Remove-Item $defaultParquet -Force }
            $sw = [Diagnostics.Stopwatch]::StartNew()
            Push-Location $testDir
            try {
                & $csharpBinary --no-join `
                    -i $mzml -l $library --resolution $ds.Resolution --protein-fdr 0.01 2>&1 | Out-Null
            } finally { Pop-Location }
            $sw.Stop()
            if (-not (Test-Path $defaultParquet)) {
                Write-Host ("  C# FAILED: no {0} produced" -f [IO.Path]::GetFileName($defaultParquet)) -ForegroundColor Red
                exit 1
            }
            Move-Item $defaultParquet $csParquet -Force
            Write-Host ("  C#   -> {0} ({1}s)" -f [IO.Path]::GetFileName($csParquet), [math]::Round($sw.Elapsed.TotalSeconds,1)) -ForegroundColor Green
        }
    }
    Write-Host ""
}

$totalStart.Stop()
Write-Host ("Done in {0:mm\:ss}." -f $totalStart.Elapsed) -ForegroundColor Green
