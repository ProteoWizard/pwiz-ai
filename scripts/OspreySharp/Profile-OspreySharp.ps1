<#
.SYNOPSIS
    Profile OspreySharp with dotTrace to identify performance hot spots.

.DESCRIPTION
    Runs OspreySharp under JetBrains dotTrace CLI profiler on Stellar or Astral
    data, captures a performance snapshot (.dtp), generates an XML report, and
    displays the top hot spots by own time and total time.

    -Stage controls the early-exit gate (matches Bench-Scoring.ps1):
      Calibration (1-3) | Scoring (1-4) | Full

.PARAMETER Dataset
    Which test dataset: Stellar or Astral (default: Stellar)

.PARAMETER Stage
    Pipeline stages to profile: Calibration (Stage 1-3),
    Scoring (Stage 1-4, default), or Full pipeline.

.PARAMETER ProfilingType
    dotTrace profiling type: Sampling (default, low overhead) or Timeline (detailed)

.PARAMETER OutputPath
    Path for the .dtp snapshot file (default: ai/.tmp/osprey-profile-<timestamp>.dtp)

.PARAMETER TopN
    Number of top hot spots to display (default: 20)

.PARAMETER MaxWindows
    Cap the number of isolation windows scored in Stage 4. Sets
    OSPREY_MAX_SCORING_WINDOWS. Use small values (1-2) for fast iteration
    on Astral profiling cycles.

.PARAMETER ScopeToMainSearch
    Drive dotTrace via the API so the .dtp snapshot contains only the
    main-search loop (bracketed by ProfilerHooks.Start/SaveAndStop).
    Requires OspreySharp to be built with the JetBrains.Profiler.Api
    reference.

.EXAMPLE
    .\Profile-OspreySharp.ps1
    Profile Stellar Stages 1-4 with sampling, show top 20 hot spots

.EXAMPLE
    .\Profile-OspreySharp.ps1 -Dataset Astral -Stage Calibration
    Profile Astral Stages 1-3 (calibration only)

.EXAMPLE
    .\Profile-OspreySharp.ps1 -Dataset Astral -ScopeToMainSearch -MaxWindows 2
    Profile Astral main-search with API-controlled scope, only 2 windows
    (fast iteration for Stage 4 bottleneck hunting).

.EXAMPLE
    .\Profile-OspreySharp.ps1 -ProfilingType Timeline -TopN 30
    Timeline profiling with top 30 hot spots
#>
param(
    [ValidateSet("Stellar", "Astral")]
    [string]$Dataset = "Stellar",

    [ValidateSet("Calibration", "Scoring", "Full")]
    [string]$Stage = "Scoring",

    [ValidateSet("Sampling", "Timeline")]
    [string]$ProfilingType = "Sampling",

    [string]$OutputPath = "",

    [int]$TopN = 20,

    # Cap the number of isolation windows scored in Stage 4. When > 0,
    # sets OSPREY_MAX_SCORING_WINDOWS so Astral profiling doesn't need the
    # full ~15 min wall-clock to produce a representative snapshot.
    [int]$MaxWindows = 0,

    # When set, drives dotTrace via the API: the profiler attaches but
    # does not start collecting until OspreySharp's ProfilerHooks.Start-
    # Measure bracket around the main-search loop. Produces a snapshot
    # that contains only Stage 4, not calibration + setup.
    [switch]$ScopeToMainSearch,

    [ValidateSet("net472", "net8.0")]
    [string]$TargetFramework = "net472"
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Load dataset configuration for parity with Bench-Scoring.ps1
. "$PSScriptRoot\Dataset-Config.ps1"
$ds = Get-DatasetConfig $Dataset

$testDir = $ds.TestDir
if (-not (Test-Path $testDir)) {
    Write-Error "Test data directory not found: $testDir"
    exit 1
}

$mzml = Join-Path $testDir $ds.SingleFile
$library = Join-Path $testDir $ds.Library
$tempBlib = Join-Path $testDir "_profile_output.blib"
$csharpBin = "C:\proj\pwiz\pwiz_tools\OspreySharp\OspreySharp\bin\x64\Release\$TargetFramework\OspreySharp.exe"

$scriptRoot = Split-Path -Parent $PSCommandPath
$aiRoot = Split-Path -Parent (Split-Path -Parent $scriptRoot)
$aiTmpDir = Join-Path $aiRoot ".tmp"

# Verify tools
$dotTraceExe = Get-Command "dottrace" -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty Source
if (-not $dotTraceExe) {
    Write-Host "dottrace not found. Install: dotnet tool install --global JetBrains.dotTrace.GlobalTools" -ForegroundColor Red
    exit 1
}

# Find Reporter.exe
$reporterExe = $null
$jetBrainsDir = Join-Path $env:LOCALAPPDATA "JetBrains\Installations"
if (Test-Path $jetBrainsDir) {
    $dirs = @(
        (Get-ChildItem -Path $jetBrainsDir -Directory -Filter "dotTrace*" -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending | Select-Object -First 1),
        (Get-ChildItem -Path $jetBrainsDir -Directory -Filter "ReSharperPlatform*" -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending | Select-Object -First 1)
    )
    foreach ($d in $dirs) {
        if ($d) {
            $rp = Join-Path $d.FullName "Reporter.exe"
            if (Test-Path $rp) { $reporterExe = $rp; break }
        }
    }
}

# Output path
if ([string]::IsNullOrEmpty($OutputPath)) {
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    if (-not (Test-Path $aiTmpDir)) { New-Item -ItemType Directory -Path $aiTmpDir -Force | Out-Null }
    $OutputPath = Join-Path $aiTmpDir "osprey-profile-$timestamp.dtp"
}

# Clean score caches (keep library cache for warm Stage 1 comparison)
$patterns = @("*.scores.parquet", "*.calibration.json", "*.spectra.bin",
              "*.fdr_scores.bin", "_profile_output*")
foreach ($p in $patterns) {
    Get-ChildItem -Path $testDir -Filter $p -ErrorAction SilentlyContinue |
        Remove-Item -Force
}

# Set up environment
$env:RUST_LOG = "info"
switch ($Stage) {
    "Calibration" { $env:OSPREY_EXIT_AFTER_CALIBRATION = "1" }
    "Scoring"     { $env:OSPREY_EXIT_AFTER_SCORING = "1" }
    # "Full" sets neither
}
if ($MaxWindows -gt 0) { $env:OSPREY_MAX_SCORING_WINDOWS = "$MaxWindows" }

# Clear diagnostic env vars
$diagVars = @('OSPREY_DUMP_CAL_MATCH','OSPREY_CAL_MATCH_ONLY','OSPREY_DUMP_LDA_SCORES',
    'OSPREY_LDA_SCORES_ONLY','OSPREY_DUMP_LOESS_INPUT','OSPREY_LOESS_INPUT_ONLY',
    'OSPREY_DIAG_SEARCH_ENTRY_IDS','OSPREY_DIAG_MP_SCAN','OSPREY_DIAG_XCORR_SCAN',
    'OSPREY_LOAD_CALIBRATION')
foreach ($v in $diagVars) { Remove-Item "Env:$v" -ErrorAction SilentlyContinue }

# Build dotTrace command
$appArgs = @("-i", $mzml, "-l", $library, "-o", $tempBlib, "--resolution", $ds.Resolution)

$dotTraceArgs = @(
    "start",
    "--profiling-type=$ProfilingType",
    "--save-to=$OutputPath",
    "--overwrite",
    "--propagate-exit-code"
)
if ($ScopeToMainSearch) {
    # Use API mode: OspreySharp's ProfilerHooks.StartMeasure /
    # SaveAndStopMeasure brackets the main-search loop, so the .dtp
    # snapshot contains only Stage 4 timing.
    $dotTraceArgs += @("--use-api", "--collect-data-from-start=off")
}
$dotTraceArgs += @($csharpBin, "--") + $appArgs

$scopeLabel = switch ($Stage) {
    "Calibration" { "Stages 1-3 (calibration only)" }
    "Scoring"     { "Stages 1-4 (calibration + main search)" }
    "Full"        { "Full pipeline" }
}

Write-Host ""
Write-Host "OspreySharp Performance Profile" -ForegroundColor Yellow
Write-Host "  Dataset: $($ds.Name) ($($ds.Resolution))" -ForegroundColor Gray
Write-Host "  Profiling type: $ProfilingType" -ForegroundColor Gray
Write-Host "  Scope: $scopeLabel" -ForegroundColor Gray
Write-Host "  Snapshot: $OutputPath" -ForegroundColor Gray
Write-Host ""

$savedLoc = Get-Location
Set-Location $testDir

Write-Host "Running under dotTrace..." -ForegroundColor Cyan
$sw = [System.Diagnostics.Stopwatch]::StartNew()
& $dotTraceExe @dotTraceArgs
$exitCode = $LASTEXITCODE
$sw.Stop()

Set-Location $savedLoc

# Cleanup
Remove-Item Env:OSPREY_EXIT_AFTER_SCORING -ErrorAction SilentlyContinue
Remove-Item Env:OSPREY_EXIT_AFTER_CALIBRATION -ErrorAction SilentlyContinue
Remove-Item Env:OSPREY_MAX_SCORING_WINDOWS -ErrorAction SilentlyContinue
Remove-Item Env:RUST_LOG -ErrorAction SilentlyContinue
if (Test-Path $tempBlib) { Remove-Item $tempBlib -Force -ErrorAction SilentlyContinue }

Write-Host ""
Write-Host "Profiling completed in $($sw.Elapsed.TotalSeconds.ToString('F1'))s (exit code: $exitCode)" -ForegroundColor $(if ($exitCode -eq 0) { "Green" } else { "Red" })

if (-not (Test-Path $OutputPath)) {
    Write-Host "Snapshot file not created" -ForegroundColor Red
    exit 1
}

$snapshotSize = (Get-Item $OutputPath).Length / 1MB
Write-Host "Snapshot: $OutputPath ($($snapshotSize.ToString('F1')) MB)" -ForegroundColor Gray

# Generate XML report
if ($reporterExe) {
    $patternFile = Join-Path $aiTmpDir "dottrace-osprey-pattern.xml"
    if (-not (Test-Path $patternFile)) {
        @"
<Patterns>
  <Pattern PrintCallstacks="Full">pwiz\.OspreySharp\..*</Pattern>
  <Pattern PrintCallstacks="Full">pwiz\.OspreySharp\.Scoring\..*</Pattern>
  <Pattern PrintCallstacks="Full">pwiz\.OspreySharp\.Chromatography\..*</Pattern>
  <Pattern PrintCallstacks="Full">pwiz\.OspreySharp\.ML\..*</Pattern>
  <Pattern PrintCallstacks="Full">pwiz\.OspreySharp\.FDR\..*</Pattern>
  <Pattern PrintCallstacks="Full">pwiz\.OspreySharp\.IO\..*</Pattern>
  <Pattern PrintCallstacks="Full">pwiz\.OspreySharp\.Core\..*</Pattern>
</Patterns>
"@ | Out-File -FilePath $patternFile -Encoding UTF8
    }

    $reportFile = $OutputPath -replace '\.dtp$', '-report.xml'
    Write-Host ""
    Write-Host "Generating XML report..." -ForegroundColor Cyan
    & $reporterExe report $OutputPath --pattern=$patternFile --save-to=$reportFile --overwrite 2>&1 | Out-Null

    if (Test-Path $reportFile) {
        Write-Host "Report: $reportFile" -ForegroundColor Gray

        try {
            [xml]$report = Get-Content $reportFile
            $allFunctions = $report.Report.Function

            # Top N by OwnTime (where the CPU actually spends time)
            $byOwnTime = $allFunctions |
                Where-Object { $_.FQN -like "pwiz.OspreySharp*" } |
                Sort-Object { [double]$_.OwnTime } -Descending |
                Select-Object -First $TopN

            if ($byOwnTime) {
                Write-Host ""
                Write-Host "Top $TopN Hot Spots by OWN TIME (pwiz.OspreySharp.*):" -ForegroundColor Yellow
                Write-Host ("{0,-70} {1,10} {2,10}" -f "Method", "Own (ms)", "Total (ms)")
                Write-Host ("{0,-70} {1,10} {2,10}" -f ("-"*70), ("-"*10), ("-"*10))
                foreach ($fn in $byOwnTime) {
                    $name = $fn.FQN -replace '^pwiz\.OspreySharp\.', ''
                    if ($name.Length -gt 70) { $name = $name.Substring(0, 67) + "..." }
                    $own = [math]::Round([double]$fn.OwnTime, 0)
                    $total = [math]::Round([double]$fn.TotalTime, 0)
                    Write-Host ("{0,-70} {1,10} {2,10}" -f $name, $own, $total)
                }
            }

            # Top N by TotalTime (call tree perspective)
            $byTotalTime = $allFunctions |
                Where-Object { $_.FQN -like "pwiz.OspreySharp*" } |
                Sort-Object { [double]$_.TotalTime } -Descending |
                Select-Object -First $TopN

            if ($byTotalTime) {
                Write-Host ""
                Write-Host "Top $TopN Hot Spots by TOTAL TIME (pwiz.OspreySharp.*):" -ForegroundColor Yellow
                Write-Host ("{0,-70} {1,10} {2,10}" -f "Method", "Total (ms)", "Own (ms)")
                Write-Host ("{0,-70} {1,10} {2,10}" -f ("-"*70), ("-"*10), ("-"*10))
                foreach ($fn in $byTotalTime) {
                    $name = $fn.FQN -replace '^pwiz\.OspreySharp\.', ''
                    if ($name.Length -gt 70) { $name = $name.Substring(0, 67) + "..." }
                    $own = [math]::Round([double]$fn.OwnTime, 0)
                    $total = [math]::Round([double]$fn.TotalTime, 0)
                    Write-Host ("{0,-70} {1,10} {2,10}" -f $name, $own, $total)
                }
            }
        }
        catch {
            Write-Host "(Could not parse report: $($_.Exception.Message))" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "Reporter.exe did not generate report" -ForegroundColor Yellow
    }
}
else {
    Write-Host ""
    Write-Host "To analyze:" -ForegroundColor Cyan
    Write-Host "  1. Open dotTrace GUI" -ForegroundColor Gray
    Write-Host "  2. File > Open > $OutputPath" -ForegroundColor Gray
    Write-Host "  3. Analyze hot spots and call tree" -ForegroundColor Gray
}

Write-Host ""
