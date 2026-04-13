<#
.SYNOPSIS
    Profile OspreySharp with dotTrace to identify performance hot spots.

.DESCRIPTION
    Runs OspreySharp under JetBrains dotTrace CLI profiler on Stellar file 20,
    captures a performance snapshot (.dtp), generates an XML report, and
    displays the top hot spots by own time and total time.

    Uses OSPREY_EXIT_AFTER_SCORING=1 to profile only Stages 1-4.

.PARAMETER ProfilingType
    dotTrace profiling type: Sampling (default, low overhead) or Timeline (detailed)

.PARAMETER OutputPath
    Path for the .dtp snapshot file (default: ai/.tmp/osprey-profile-<timestamp>.dtp)

.PARAMETER TopN
    Number of top hot spots to display (default: 20)

.PARAMETER FullPipeline
    Profile the full pipeline instead of Stages 1-4 only

.EXAMPLE
    .\Profile-OspreySharp.ps1
    Profile Stages 1-4 with sampling, show top 20 hot spots

.EXAMPLE
    .\Profile-OspreySharp.ps1 -ProfilingType Timeline -TopN 30
    Timeline profiling with top 30 hot spots
#>
param(
    [ValidateSet("Sampling", "Timeline")]
    [string]$ProfilingType = "Sampling",

    [string]$OutputPath = "",

    [int]$TopN = 20,

    [switch]$FullPipeline = $false
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Paths
$testDir = "D:\test\osprey-runs\stellar"
$mzml = Join-Path $testDir "Ste-2024-12-02_HeLa_4mz_sDIA_400-900_20.mzML"
$library = Join-Path $testDir "hela-filtered-SkylineAI_spectral_library.tsv"
$tempBlib = Join-Path $testDir "_profile_output.blib"
$csharpBin = "C:\proj\pwiz\pwiz_tools\OspreySharp\OspreySharp\bin\x64\Release\pwiz.OspreySharp.exe"

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
if (-not $FullPipeline) {
    $env:OSPREY_EXIT_AFTER_SCORING = "1"
}

# Clear diagnostic env vars
$diagVars = @('OSPREY_DUMP_CAL_MATCH','OSPREY_CAL_MATCH_ONLY','OSPREY_DUMP_LDA_SCORES',
    'OSPREY_LDA_SCORES_ONLY','OSPREY_DUMP_LOESS_INPUT','OSPREY_LOESS_INPUT_ONLY',
    'OSPREY_DIAG_SEARCH_ENTRY_IDS','OSPREY_DIAG_MP_SCAN','OSPREY_DIAG_XCORR_SCAN',
    'OSPREY_LOAD_CALIBRATION')
foreach ($v in $diagVars) { Remove-Item "Env:$v" -ErrorAction SilentlyContinue }

# Build dotTrace command
$appArgs = @("-i", $mzml, "-l", $library, "-o", $tempBlib, "--resolution", "unit")

$dotTraceArgs = @(
    "start",
    "--profiling-type=$ProfilingType",
    "--save-to=$OutputPath",
    "--overwrite",
    "--propagate-exit-code",
    $csharpBin,
    "--"
) + $appArgs

Write-Host ""
Write-Host "OspreySharp Performance Profile" -ForegroundColor Yellow
Write-Host "  Profiling type: $ProfilingType" -ForegroundColor Gray
Write-Host "  Scope: $(if ($FullPipeline) { 'Full pipeline' } else { 'Stages 1-4 only' })" -ForegroundColor Gray
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
