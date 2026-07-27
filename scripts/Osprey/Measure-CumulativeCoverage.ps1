<#
.SYNOPSIS
    Cumulative Osprey code coverage across everything TeamCity runs --
    the unit tests AND the end-to-end regression pipeline -- merged into one
    dotCover report.

.DESCRIPTION
    Unit tests alone cover ~45% of Osprey; the DIA pipeline (scoring,
    calibration, LOESS/KDE, SVM, FDR, blib) is near-zero under unit tests but is
    exercised heavily by the regression run. dotCover accumulates coverage across
    separate processes via `merge`, so this captures a snapshot from each test
    process and merges them:

      1. Unit leg     -- Build-Osprey.ps1 -Coverage -> unit .dcvr (+ JSON).
      2. Regression   -- Osprey.exe run under `dotcover cover`, once
         straight  straight-through (cold pipeline) -> straight .dcvr.
      3. Regression   -- the same command re-run after invalidating the Stage 5
         resume      join + blib, so the rehydrate paths fire -> resume .dcvr.
      4. Merge        -- dotcover merge all snapshots -> cumulative .dcvr.
      5. Report       -- dotcover report (JSON) -> Summarize-Coverage.ps1.

    The regression mode-1/mode-2 *comparisons* are PowerShell and add no
    Osprey coverage, so this runs Osprey.exe directly (same flags the
    regression uses) rather than `regression.ps1` -- no change to the pwiz
    scripts, which exist only to run on TeamCity.

    Mirrors Skyline TestRunner's GenerateCoverageReport (snapshot-per-process +
    merge + report). Uses the slash-style dotCover CLI (works <= 2025.1.x;
    Build-Osprey.ps1 refuses >= 2025.3.0 until updated).

.PARAMETER Dataset
    Stellar (default; unit resolution, fast), Astral (hram, much slower under
    instrumentation), or All (both -- the full TeamCity regression set). With
    -Files All this is "everything the nightly runs", and is correspondingly
    slow under dotCover instrumentation (hours).

.PARAMETER Files
    Single (one mzML, fastest), All (3-file, what the nightly runs), or Mixed.
    Mixed = the cheap "tctest + regression estimate": unit-resolution datasets
    (Stellar) run all 3 files while hram datasets (Astral) run a SINGLE file. A
    single Astral file is sequential by definition (no parallel path, no ~44 GB
    blow-up) so it lights up the HRAM-only code (HramStrategy, Ms1ScoringByproduct,
    IsotopeDistribution, LibCosineScorer) that Stellar can never reach, at a
    fraction of a full 3-file Astral run's instrumented wall time. Default Single.

.PARAMETER SkipUnit
    Skip the unit-test leg (regression coverage only).

.PARAMETER SkipResume
    Skip the resume leg (straight-through only).

.PARAMETER Threads
    --threads for the pipeline runs (default 16).

.PARAMETER DataRoot
    Extracted regression data root (default:
    <Downloads>\Perftests\osprey-testfiles-mzML-v2, resolved like the regression
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
    # Passed straight through to regression.ps1; keep this ValidateSet in step with
    # ITS ValidateSet (the only remaining coupling, and it fails loudly, not silently).
    [ValidateSet('Stellar', 'StellarLibDecoy', 'StellarGenDecoyEntrap', 'Astral', 'All')] [string]$Dataset = 'All',
    [switch]$SkipUnit,
    [switch]$SkipResume,
    [switch]$SkipHpcChain,
    [string]$OutDir
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$scriptDir = Split-Path -Parent $PSCommandPath
$projectRoot = (Resolve-Path (Join-Path $scriptDir '..\..\..')).Path   # ai/scripts/Osprey -> root
$pwizRoot = Join-Path $projectRoot 'pwiz'
$ospreyBinDir = Join-Path $pwizRoot 'pwiz_tools\Osprey\Osprey\bin\x64\Release\net8.0'
$ospreyExe = Join-Path $ospreyBinDir 'Osprey.exe'
$buildScript = Join-Path $scriptDir 'Build-Osprey.ps1'
$summarizeScript = Join-Path $scriptDir 'Summarize-Coverage.ps1'
$regressionDataPs1 = Join-Path $pwizRoot 'pwiz_tools\Osprey\Regression\RegressionData.ps1'

# Dot-source at SCRIPT scope for the downloads-folder helper. The regression leg
# now invokes regression.ps1 directly, so this script no longer reimplements the
# resume invalidation or the dataset layout - the pwiz harness owns both.

# Coverage filter: Osprey.* production assemblies, drop the test assembly.
# (Same filter Build-Osprey.ps1 -Coverage uses for the unit leg.)
$coverFilters = @('/Filters=+:module=Osprey*', '/Filters=-:module=Osprey.Test')

# --- dotCover resolution (mirror Build-Osprey.ps1) ----------------------
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
# Invalidate the Stage 5 join + blib so a re-run resumes (mirror regression.ps1).
# Invoke-ResumeInvalidation comes from RegressionData.ps1 (dot-sourced above),
# the same definition regression.ps1 mode 2 uses. Do NOT reintroduce a local
# copy here.

# ----------------------------------------------------------------------------
if (-not (Test-Path $ospreyExe)) {
    throw "Osprey.exe not found at $ospreyExe -- build Release/net8.0 first (Build-Osprey.ps1)."
}
$dotCover = Resolve-DotCover
$stamp = (Get-Date).ToString('yyyyMMdd_HHmmss')
if (-not $OutDir) { $OutDir = Join-Path $projectRoot "ai\.tmp\osprey-cumcov-$stamp" }
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null


Write-Host ""
Write-Host "=== Osprey cumulative coverage (regression -Dataset $Dataset + unit tests) ===" -ForegroundColor Cyan
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

# Serialize file processing for ALL coverage legs -- for DETERMINISM under dotCover.
# Osprey now processes files sequentially by default, so this =1 is
# belt-and-suspenders: it pins sequential explicitly (independent of the default)
# and keeps the back-compat env cap path exercised. (Pre-2026-06-23 the default was
# parallel via Parallel.For up to ProcessorCount, which is why this was required.)
# On 2026-06-11 a 3-file Stellar straight-through died at the blib write with
# "could not load ... System.Transactions.Local / System.Runtime.Intrinsics ... the
# system cannot find the file specified" -- both are shared-framework assemblies the
# UNinstrumented exe loads fine, so it is dotCover-specific. The failure is
# INTERMITTENT and parallel-correlated, NOT a hard memory wall: a prior
# -Dataset All run completed BOTH Stellar 3-file parallel legs (straight + resume,
# blibs written) at ~85% machine memory before reaching Astral. The mechanism is not
# fully pinned -- either a transient memory spike crossing the line under parallel
# load, or a dotCover assembly-resolution race when parallel threads first-load the
# same framework assembly at once. A sequential MergeNode-resume repro wrote the blib
# fine, confirming serial is RELIABLE but not isolating the cause. =1 takes the
# strictly-sequential path (reliable, deterministic), a no-op for single-file legs;
# each file still gets the full --threads inner budget so per-file scoring code is
# covered identically. Cost: the outer Parallel.For *scheduling* branch (~a dozen
# lines of glue) goes uncovered -- acceptable vs. an intermittently crashing run.
# Astral (hram, ~44 GB) needs serial regardless. See
# TODO-20260611_ospreysharp_serialize_astral_runners.md.
$env:OSPREY_MAX_PARALLEL_FILES = '1'

# ---- 2. Regression leg: cover the EXACT command TeamCity runs --------------
# tctest.bat runs `regression.ps1 -TeamCity -Dataset All`. We cover that literal
# command rather than re-implementing its runs, because re-implementing them is
# what made this script silently wrong before: it kept its own dataset table and
# flag list, and went on reporting a number that excluded the entrapment datasets,
# --model-diagnostics, the Stage-7 protein dump and the whole mode-3 HPC chain long
# after the harness grew them. There is now nothing here to keep in sync - add a
# dataset or a mode to regression.ps1 and this measurement picks it up for free.
#
# dotCover instruments the target process AND its children, so covering pwsh
# captures every Osprey.exe the harness spawns, including the four --task worker
# phases of the HPC chain that no straight-through run can reach. Verified: a
# single covered Stellar mode-1 run reported Osprey.Scoring 69%, Osprey.FDR 43%,
# Osprey.Tasks 50% etc., and dotCover logged "Merging snapshots" (>1 process).
$regressionPs1 = Join-Path $projectRoot (Join-Path "pwiz" (Join-Path "pwiz_tools" (Join-Path "Osprey" "regression.ps1")))
if (-not (Test-Path $regressionPs1)) { throw "regression.ps1 not found at $regressionPs1" }
$pwshExe = (Get-Command pwsh).Source

$regressionArgs = @("-NoProfile", "-File", $regressionPs1, "-Dataset", $Dataset, "-NoBuild")
if ($SkipResume)   { $regressionArgs += "-SkipResume" }
if ($SkipHpcChain) { $regressionArgs += "-SkipHpcChain" }

Write-Host ("[regression] {0} -Dataset {1} under dotCover ..." -f (Split-Path -Leaf $regressionPs1), $Dataset) -ForegroundColor Cyan
Write-Host  "  (this is the tctest.bat command; expect it to take as long as the TeamCity leg, plus instrumentation)"
$regSnap = Join-Path $OutDir "regression.dcvr"
# No embedded quotes on the pwsh path: the call operator quotes each array element
# itself, and a literal quote makes dotCover reject the value outright
# ("Invalid character '"' (U+0022) in path at index 0").
$coverArgs = @("cover") + $coverFilters + @(
    "/Output=$regSnap",
    "/ReturnTargetExitCode",
    "/AnalyzeTargetArguments=false",
    "/TargetWorkingDir=$(Split-Path -Parent $regressionPs1)",
    "/TargetExecutable=$pwshExe",
    "--") + $regressionArgs
& $dotCover $coverArgs | Out-Host
$regExit = $LASTEXITCODE
if (-not (Test-Path $regSnap)) { throw "dotCover produced no regression snapshot at $regSnap" }
# A red regression still yields a valid snapshot; report the coverage but say so,
# because a failed run covers less code and the number would otherwise mislead.
if ($regExit -ne 0) {
    Write-Host "  WARNING: regression.ps1 exited $regExit (FAILED). Coverage below is from a RED run." -ForegroundColor Yellow
}
$snapshots.Add($regSnap)

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
