<#
.SYNOPSIS
    Cumulative OspreySharp code coverage across everything TeamCity runs --
    the unit tests AND the end-to-end regression pipeline -- merged into one
    dotCover report.

.DESCRIPTION
    Unit tests alone cover ~45% of OspreySharp; the DIA pipeline (scoring,
    calibration, LOESS/KDE, SVM, FDR, blib) is near-zero under unit tests but is
    exercised heavily by the regression run. dotCover accumulates coverage across
    separate processes via `merge`, so this captures a snapshot from each test
    process and merges them:

      1. Unit leg     -- Build-OspreySharp.ps1 -Coverage -> unit .dcvr (+ JSON).
      2. Regression   -- OspreySharp.exe run under `dotcover cover`, once
         straight  straight-through (cold pipeline) -> straight .dcvr.
      3. Regression   -- the same command re-run after invalidating the Stage 5
         resume      join + blib, so the rehydrate paths fire -> resume .dcvr.
      4. Merge        -- dotcover merge all snapshots -> cumulative .dcvr.
      5. Report       -- dotcover report (JSON) -> Summarize-Coverage.ps1.

    The regression mode-1/mode-2 *comparisons* are PowerShell and add no
    OspreySharp coverage, so this runs OspreySharp.exe directly (same flags the
    regression uses) rather than `regression.ps1` -- no change to the pwiz
    scripts, which exist only to run on TeamCity.

    Mirrors Skyline TestRunner's GenerateCoverageReport (snapshot-per-process +
    merge + report). Uses the slash-style dotCover CLI (works <= 2025.1.x;
    Build-OspreySharp.ps1 refuses >= 2025.3.0 until updated).

.PARAMETER Dataset
    Stellar (default; unit resolution, fast), Astral (hram, much slower under
    instrumentation), or All (both -- the full TeamCity regression set). With
    -Files All this is "everything the nightly runs", and is correspondingly
    slow under dotCover instrumentation (hours).

.PARAMETER Files
    Single (one mzML, fastest) or All (3-file, what the nightly runs). Default Single.

.PARAMETER SkipUnit
    Skip the unit-test leg (regression coverage only).

.PARAMETER SkipResume
    Skip the resume leg (straight-through only).

.PARAMETER Threads
    --threads for the pipeline runs (default 16).

.PARAMETER DataRoot
    Extracted regression data root (default:
    <Downloads>\Perftests\osprey-testfiles-mzML, resolved like the regression
    harness). Must already be present (this does not download).

.PARAMETER OutDir
    Where snapshots + the merged report land (default: ai\.tmp\osprey-cumcov-<ts>).

.EXAMPLE
    .\Measure-CumulativeCoverage.ps1
    Unit + Stellar single-file straight+resume, merged; prints the cumulative %.

.EXAMPLE
    .\Measure-CumulativeCoverage.ps1 -Dataset All -Files All
    The full picture: unit + Stellar(3-file) + Astral(3-file, hram), each
    straight-through + resume -- everything the TeamCity regression runs, merged.
    Slow under instrumentation (hours); this is the real cumulative number.
#>
param(
    [ValidateSet('Stellar', 'Astral', 'All')] [string]$Dataset = 'Stellar',
    [ValidateSet('Single', 'All')] [string]$Files = 'Single',
    [switch]$SkipUnit,
    [switch]$SkipResume,
    [int]$Threads = 16,
    [string]$DataRoot,
    [string]$OutDir
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$scriptDir = Split-Path -Parent $PSCommandPath
$projectRoot = (Resolve-Path (Join-Path $scriptDir '..\..\..')).Path   # ai/scripts/OspreySharp -> root
$pwizRoot = Join-Path $projectRoot 'pwiz'
$ospreyBinDir = Join-Path $pwizRoot 'pwiz_tools\OspreySharp\OspreySharp\bin\x64\Release\net8.0'
$ospreyExe = Join-Path $ospreyBinDir 'OspreySharp.exe'
$buildScript = Join-Path $scriptDir 'Build-OspreySharp.ps1'
$summarizeScript = Join-Path $scriptDir 'Summarize-Coverage.ps1'
$regressionDataPs1 = Join-Path $pwizRoot 'pwiz_tools\OspreySharp\Regression\RegressionData.ps1'

# Coverage filter: OspreySharp.* production assemblies, drop the test assembly.
# (Same filter Build-OspreySharp.ps1 -Coverage uses for the unit leg.)
$coverFilters = @('/Filters=+:module=OspreySharp*', '/Filters=-:module=OspreySharp.Test')

# --- dotCover resolution (mirror Build-OspreySharp.ps1) ----------------------
function Resolve-DotCover {
    $globalTool = Join-Path $env:USERPROFILE '.dotnet\tools\dotCover.exe'
    if (Test-Path $globalTool) { return $globalTool }
    $libPath = Join-Path $pwizRoot 'libraries'
    if (Test-Path $libPath) {
        foreach ($dir in Get-ChildItem -Path $libPath -Directory -Filter '*dotcover*commandlinetools*' -ErrorAction SilentlyContinue) {
            $exe = Get-ChildItem -Path $dir.FullName -Recurse -Filter 'dotCover.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($exe) { return $exe.FullName }
        }
    }
    throw "dotCover.exe not found. Install: dotnet tool install -g JetBrains.dotCover.CommandLineTools"
}

# --- Dataset table (mirrors regression.ps1 / Dataset-Config) -----------------
$datasets = @{
    Stellar = @{ Folder = 'stellar'; Resolution = 'unit' }
    Astral  = @{ Folder = 'astral';  Resolution = 'hram' }
}

function Resolve-DataDir {
    param([string]$Folder)
    if (-not $DataRoot) {
        # Reuse the harness's downloads-folder logic when present.
        if (Test-Path $regressionDataPs1) {
            . $regressionDataPs1
            $DataRoot = Join-Path (Get-WindowsDownloadsFolder) 'Perftests\osprey-testfiles-mzML'
        } else {
            $DataRoot = Join-Path (Join-Path $env:USERPROFILE 'Downloads') 'Perftests\osprey-testfiles-mzML'
        }
    }
    $dir = Join-Path $DataRoot $Folder
    if (-not (Test-Path $dir)) {
        throw "Dataset data not found: $dir (run the regression once to download, or pass -DataRoot)."
    }
    return $dir
}

# --- Run OspreySharp.exe once under dotCover -> a .dcvr snapshot --------------
function Invoke-CoveredRun {
    param([string]$DotCover, [string[]]$Mzmls, [string]$Library, [string]$Resolution,
          [string]$WorkDir, [string]$Snapshot)
    New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
    $targetArgs = @()
    foreach ($m in $Mzmls) { $targetArgs += @('-i', $m) }
    $targetArgs += @('-l', $Library, '-o', 'output.blib', '--resolution', $Resolution,
                     '--protein-fdr', '0.01', '--threads', $Threads.ToString(), '--work-dir', $WorkDir)
    # /TargetWorkingDir sets the CWD so -o output.blib + dumps land in the work dir.
    $coverArgs = @('cover') + $coverFilters + @(
        "/Output=$Snapshot",
        '/ReturnTargetExitCode',
        '/AnalyzeTargetArguments=false',
        "/TargetWorkingDir=$WorkDir",
        "/TargetExecutable=$ospreyExe",
        '--') + $targetArgs
    & $DotCover $coverArgs | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Covered OspreySharp run failed (exit $LASTEXITCODE)" }
    if (-not (Test-Path $Snapshot)) { throw "dotCover produced no snapshot at $Snapshot" }
}

# Invalidate the Stage 5 join + blib so a re-run resumes (mirror regression.ps1).
function Invoke-ResumeInvalidation {
    param([string]$WorkDir)
    Get-ChildItem -Path $WorkDir -File | Where-Object {
        $_.Name -like '*.FirstJoin.osprey.task' -or
        $_.Name -eq 'output.blib' -or $_.Name -eq 'output.blib.MergeNode.osprey.task'
    } | Remove-Item -Force
}

# ----------------------------------------------------------------------------
if (-not (Test-Path $ospreyExe)) {
    throw "OspreySharp.exe not found at $ospreyExe -- build Release/net8.0 first (Build-OspreySharp.ps1)."
}
$dotCover = Resolve-DotCover
$stamp = (Get-Date).ToString('yyyyMMdd_HHmmss')
if (-not $OutDir) { $OutDir = Join-Path $projectRoot "ai\.tmp\osprey-cumcov-$stamp" }
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

$selected = if ($Dataset -eq 'All') { @('Stellar', 'Astral') } else { @($Dataset) }

Write-Host ""
Write-Host "=== OspreySharp cumulative coverage (datasets: $($selected -join ', '); files=$Files) ===" -ForegroundColor Cyan
Write-Host "  dotCover : $dotCover"
Write-Host "  out dir  : $OutDir"
Write-Host ""

$snapshots = [System.Collections.Generic.List[string]]::new()

# ---- 1. Unit leg ----
if (-not $SkipUnit) {
    Write-Host "[unit] tests under dotCover ..." -ForegroundColor Cyan
    $unitJson = Join-Path $OutDir 'unit.json'
    # Match the net8.0 Release binaries the regression leg runs, so the merged
    # snapshot is one coherent build (not net472 unit + net8.0 pipeline).
    & $buildScript -Coverage -Configuration Release -TargetFramework net8.0 -CoverageOutputPath $unitJson | Out-Host
    $unitSnap = Join-Path $OutDir 'unit.dcvr'
    if (-not (Test-Path $unitSnap)) { throw "Unit coverage snapshot not found at $unitSnap" }
    $snapshots.Add($unitSnap)
}

# ---- 2. Per-dataset regression legs (straight-through + resume) ----
foreach ($name in $selected) {
    $cfg = $datasets[$name]
    $dataDir = Resolve-DataDir -Folder $cfg.Folder
    $allMzml = @(Get-ChildItem -Path $dataDir -Filter '*.mzML' -File | Sort-Object Name | ForEach-Object { $_.FullName })
    $mzmls = if ($Files -eq 'Single') { @($allMzml[0]) } else { $allMzml }
    $library = @(Get-ChildItem -Path $dataDir -Filter '*.tsv' -File)[0].FullName

    Write-Host ("[$name] straight-through under dotCover ($($mzmls.Count) file(s), $($cfg.Resolution)) ..." ) -ForegroundColor Cyan
    $straightDir = Join-Path $OutDir "$($cfg.Folder)\straight"
    $straightSnap = Join-Path $OutDir "$($cfg.Folder)-straight.dcvr"
    Invoke-CoveredRun -DotCover $dotCover -Mzmls $mzmls -Library $library -Resolution $cfg.Resolution `
        -WorkDir $straightDir -Snapshot $straightSnap
    $snapshots.Add($straightSnap)

    if (-not $SkipResume) {
        Write-Host "[$name] resume under dotCover ..." -ForegroundColor Cyan
        Invoke-ResumeInvalidation -WorkDir $straightDir
        $resumeSnap = Join-Path $OutDir "$($cfg.Folder)-resume.dcvr"
        Invoke-CoveredRun -DotCover $dotCover -Mzmls $mzmls -Library $library -Resolution $cfg.Resolution `
            -WorkDir $straightDir -Snapshot $resumeSnap
        $snapshots.Add($resumeSnap)
    }
}

# ---- 4. Merge ----
Write-Host "[4] Merging $($snapshots.Count) snapshot(s) ..." -ForegroundColor Cyan
$mergedSnap = Join-Path $OutDir 'cumulative.dcvr'
& $dotCover merge "/Source=$($snapshots -join ';')" "/Output=$mergedSnap" | Out-Null
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $mergedSnap)) { throw "dotcover merge failed" }

# ---- 5. Report + summarize ----
Write-Host "[5] Reporting + summarizing ..." -ForegroundColor Cyan
$mergedJson = Join-Path $OutDir 'cumulative.json'
& $dotCover report "/Source=$mergedSnap" "/Output=$mergedJson" '/ReportType=JSON' | Out-Null
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $mergedJson)) { throw "dotcover report failed" }

Write-Host ""
& $summarizeScript -CoverageJsonPath $mergedJson
Write-Host ""
Write-Host "Cumulative coverage artifacts in: $OutDir" -ForegroundColor Green
