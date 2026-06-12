<#
.SYNOPSIS
    OspreySharp performance gate: same-session A/B of a branch build vs the
    pinned pwiz-perfbase baseline. Fails (non-zero exit) on a real per-stage or
    total wall regression.

.DESCRIPTION
    The standing perf companion to the correctness gate (regression.ps1). Where
    regression.ps1 asserts the OUTPUT is unchanged, this asserts the SPEED is not
    degraded by a refactor (the OOP-cleanup cadence is the motivating consumer).

    Why a dedicated A/B and not a number-in-HTML compare: OspreySharp perf is
    environment-sensitive (thermal throttling under sustained load, and a
    build-SDK swap once moved net8.0 stage1to4 ~12% at FIXED source -- see
    ai/todos/backlog/TODO-ospreysharp_sprint_stage1to4_perf_regression.md). A
    single absolute baseline drifts and yields false regressions. The robust
    design the history converged on is a PINNED baseline worktree
    (C:\proj\pwiz-perfbase) measured in the SAME session as the branch, so
    machine/thermal/SDK conditions are shared and cancel:

      1. Build BOTH binaries fresh (identical toolchain) unless -SkipBuild.
      2. Run them INTERLEAVED with alternating order per repeat (rep 1 baseline
         first, rep 2 branch first, ...) so neither side systematically runs
         hotter.
      3. Pair each rep's baseline+branch (they ran adjacently) and take the
         per-rep % delta; the median of those deltas is the headline.
      4. HARD-FAIL on TOTAL wall only -- median per-rep delta over the threshold
         AND every rep agreeing the branch was slower. Heavy stages (stage1to4,
         stage6) report as WARN, never fail: per-stage I/O walls are too noisy,
         and a refactor that moves time between stages at equal total is not a
         regression.

    Rust is NOT needed here: the interleaved same-session A/B already shares the
    environment between baseline and branch. Rust stays the optional change-immune
    ANCHOR for the rare case where a flagged regression needs confirming as code
    vs environment -- re-run that one dataset with Measure-Pipeline.ps1 -Tool Both
    and check the Rust column held flat.

    Dataset paths/resolution come from Dataset-Config.ps1 (shared with
    Measure-Pipeline.ps1, the cross-impl perf-table sibling).

.PARAMETER Dataset
    Stellar (default; fast, unit-resolution), Astral (heavy, hram), or Both.
    Stellar is the routine per-PR gate; run Astral before a perf-sensitive merge.

.PARAMETER Repeats
    Full-pipeline runs per (variant x dataset). Default 3 (median + min/max band).

.PARAMETER WarmupRuns
    Discarded warm-up runs before the measured reps (default 1). Bump on a
    freshly rebooted machine, where the first few runs can be anomalously fast
    until OspreySharp settles -- discarding them keeps the measured reps
    representative of steady state.

.PARAMETER BaselineRoot
    pwiz worktree holding the pinned baseline. Default C:\proj\pwiz-perfbase.

.PARAMETER BranchRoot
    pwiz worktree holding the change under test. Default: auto-detect the sibling
    'pwiz' next to ai/ (same rule as Build-OspreySharp.ps1).

.PARAMETER TotalThresholdPct
    Total-wall regression threshold in percent (the hard-fail gate). Default 4 --
    chosen above the ~2% total noise seen between byte-identical binaries on a
    busy dev machine, so the gate does not false-fail; a real >4% slowdown still
    trips it, and sub-4% drift accrues visibly across the periodic Astral runs.

.PARAMETER StageThresholdPct
    Heavy-stage (stage1to4, stage6) WARN threshold in percent. Heavy-stage
    regressions are reported as warnings, never gate failures. Default 5.

.PARAMETER SkipBuild
    Use the existing Release/net8.0 binaries under each root (skip the two builds).
    Only safe when both binaries are already current.

.PARAMETER Threads
    --threads for each run. Default 16 (matches the other harnesses).

.PARAMETER MaxParallelFiles
    OSPREY_MAX_PARALLEL_FILES. Default -1 = dataset default (1 for Astral, unset
    otherwise), matching Measure-Pipeline.ps1.

.PARAMETER TestBaseDir
    Where the datasets live. Default: Dataset-Config.ps1 default.

.PARAMETER OutputDir
    Per-run logs + the markdown verdict. Default ai\.tmp\perf-gate\<UTC stamp>\.

.EXAMPLE
    # Routine per-PR gate: Stellar, branch vs pwiz-perfbase, build both.
    pwsh -File ./ai/scripts/OspreySharp/Test-PerfGate.ps1

.EXAMPLE
    # Heavier check before a perf-sensitive merge.
    pwsh -File ./ai/scripts/OspreySharp/Test-PerfGate.ps1 -Dataset Both

.EXAMPLE
    # Re-judge from already-built binaries (no rebuild).
    pwsh -File ./ai/scripts/OspreySharp/Test-PerfGate.ps1 -SkipBuild

.NOTES
    Disk: Astral needs ~30 GB free per run for workdir caches (cleaned between
    runs). Total wall: Stellar 3-rep A/B ~30 min (6 cold runs); Astral much more.
    Advance the baseline (and rebuild it) only on a reviewed, intentional perf
    change: check out the new master HEAD in pwiz-perfbase and re-run with no
    -SkipBuild.
#>

param(
    [ValidateSet('Stellar','Astral','Both')]
    [string]$Dataset = 'Stellar',

    [int]$Repeats = 3,

    [int]$WarmupRuns = 1,

    [string]$BaselineRoot = 'C:\proj\pwiz-perfbase',

    [string]$BranchRoot = $null,

    [double]$TotalThresholdPct = 4.0,

    [double]$StageThresholdPct = 5.0,

    [switch]$SkipBuild,

    [int]$Threads = 16,

    [int]$MaxParallelFiles = -1,

    [string]$TestBaseDir = $null,

    [string]$OutputDir = $null
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$scriptDir = Split-Path -Parent $PSCommandPath
. (Join-Path $scriptDir 'Dataset-Config.ps1')

$aiRoot   = Split-Path -Parent (Split-Path -Parent $scriptDir)   # ai/
$projRoot = Split-Path -Parent $aiRoot                            # C:\proj

# Resolve the branch worktree (sibling 'pwiz' by default, same rule as Build-OspreySharp.ps1).
if (-not $BranchRoot) {
    $sibling = Join-Path $projRoot 'pwiz'
    if (Test-Path (Join-Path $sibling 'pwiz_tools')) {
        $BranchRoot = $sibling
    } else {
        throw "Cannot auto-detect the branch pwiz root; pass -BranchRoot."
    }
}

# Stages emitted by both impls, in pipeline order. The heavy stages are the ones
# a scoring/per-file refactor can plausibly move; they get the per-stage gate.
$expectedStages = @('stage1to4','stage5','stage6','stage7','blib')
$heavyStages    = @('stage1to4','stage6')

# The two variants under test: a pinned baseline and the branch.
$variants = [ordered]@{
    baseline = @{ Label = 'baseline'; Root = $BaselineRoot }
    branch   = @{ Label = 'branch';   Root = $BranchRoot }
}

function Get-OspreyBin {
    param([string]$Root)
    return Join-Path $Root 'pwiz_tools\OspreySharp\OspreySharp\bin\x64\Release\net8.0\OspreySharp.exe'
}

if (-not $OutputDir) {
    $ts = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmssZ')
    $OutputDir = Join-Path $projRoot "ai\.tmp\perf-gate\$ts"
}
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

$datasetsToRun = if ($Dataset -eq 'Both') { @('Stellar','Astral') } else { @($Dataset) }

Write-Host ""
Write-Host "=== Test-PerfGate (branch vs pwiz-perfbase) ===" -ForegroundColor Cyan
Write-Host ("Baseline:  {0}" -f $BaselineRoot)
Write-Host ("Branch:    {0}" -f $BranchRoot)
Write-Host ("Datasets:  {0}" -f ($datasetsToRun -join ', '))
Write-Host ("Repeats:   {0}   Threads: {1}" -f $Repeats, $Threads)
Write-Host ("Threshold: total >{0}%, heavy stage >{1}% (with non-overlapping bands)" -f $TotalThresholdPct, $StageThresholdPct)
Write-Host ("Output:    {0}" -f $OutputDir)
Write-Host ""

# --- Build both binaries (identical toolchain, same session) ------------------
if (-not $SkipBuild) {
    $buildScript = Join-Path $scriptDir 'Build-OspreySharp.ps1'
    foreach ($key in $variants.Keys) {
        $root = $variants[$key].Root
        Write-Host ("Building {0} (Release/net8.0): {1}" -f $key, $root) -ForegroundColor Cyan
        & $buildScript -SourceRoot $root -Configuration Release -TargetFramework net8.0 -Summary
        if ($LASTEXITCODE -ne 0) { throw "Build failed for ${key} at $root (exit $LASTEXITCODE)" }
    }
}
# Stage BOTH binaries into a common parent (<OutputDir>\bin\<variant>) and run
# from there, so neither side can differ by PATH -- disk, OS image caching, or
# any path-scoped policy. This is cheap symmetry hygiene, NOT the main control:
# the dominant measurement noise is machine contention (run on an idle machine),
# and the paired per-rep judging below is what cancels it. (An earlier guess
# blamed a path-asymmetric Defender scan for a ~13% gap between byte-identical
# binaries; that was wrong -- both trees are scan-excluded, and the "gap" was
# transient load: the same binary measured both faster AND slower than its twin
# across runs, a ~17% run-to-run swing on stage1to4. Kept anyway because removing
# a path variable is still correct.)
$stagedBinRoot = Join-Path $OutputDir 'bin'
foreach ($key in $variants.Keys) {
    $srcBin = Get-OspreyBin -Root $variants[$key].Root
    if (-not (Test-Path $srcBin)) { throw "Missing ${key} binary: $srcBin (build first, or drop -SkipBuild)" }
    $srcDir  = Split-Path -Parent $srcBin
    $destDir = Join-Path $stagedBinRoot $key
    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    Copy-Item (Join-Path $srcDir '*') $destDir -Recurse -Force
    $variants[$key].Bin = Join-Path $destDir (Split-Path -Leaf $srcBin)
}

# --- One full-pipeline run: invoke the binary, parse [STAGE-WALL] walls --------
# Slim C#-only sibling of Measure-Pipeline.ps1's Invoke-PipelineRun: no Rust, no
# cross-impl stage5/6 alignment (both variants share C# labeling, so raw walls
# compare apples-to-apples), no HTML.
function Invoke-PerfRun {
    param(
        [string]$BinPath,
        [string]$VariantKey,
        [string]$DatasetName,
        [int]$RunIdx
    )
    $ds = Get-DatasetConfig $DatasetName -TestBaseDir $TestBaseDir
    $datasetRoot = $ds.TestDir
    $files = @($ds.AllFiles)

    $tag = "perfgate-$($DatasetName.ToLower())-$VariantKey-run$RunIdx"
    $workdir = Join-Path $datasetRoot "_$tag"
    if (Test-Path $workdir) { Remove-Item $workdir -Recurse -Force }
    New-Item -ItemType Directory -Path $workdir -Force | Out-Null

    # Copy inputs into the workdir, preserving mtime (the library identity hash
    # includes mtime; a fresh copy time could spuriously invalidate caches).
    foreach ($f in $files) {
        Copy-Item (Join-Path $datasetRoot $f) (Join-Path $workdir $f)
    }
    Copy-Item (Join-Path $datasetRoot $ds.Library) (Join-Path $workdir $ds.Library)
    $libcache = Join-Path $datasetRoot ($ds.Library + '.libcache')
    if (Test-Path $libcache) {
        Copy-Item $libcache (Join-Path $workdir ($ds.Library + '.libcache'))
    }

    $cliArgs = @()
    foreach ($f in $files) { $cliArgs += @('-i', $f) }
    $cliArgs += @('-l', $ds.Library, '-o', 'output.blib',
                  '--resolution', $ds.Resolution, '--protein-fdr', '0.01',
                  '--threads', $Threads.ToString())

    # Scrub every diagnostic OSPREY_DUMP_* / *_ONLY hook so we measure the
    # production path (dumps add 30s+ to stage5). Pattern-based so the list can't
    # rot. Functional OSPREY_* vars (e.g. OSPREY_MAX_PARALLEL_FILES) are untouched.
    Get-ChildItem env: | Where-Object {
        $_.Name -like 'OSPREY_DUMP_*' -or $_.Name -like 'OSPREY_*_ONLY' -or $_.Name -eq 'OSPREY_TRACE_PEPTIDE'
    } | ForEach-Object { Remove-Item ("env:" + $_.Name) -ErrorAction SilentlyContinue }

    $mpf = $MaxParallelFiles
    if ($mpf -lt 0) { $mpf = if ($DatasetName -eq 'Astral') { 1 } else { 0 } }
    if ($mpf -gt 0) {
        [Environment]::SetEnvironmentVariable('OSPREY_MAX_PARALLEL_FILES', $mpf.ToString())
    } elseif (Test-Path 'env:OSPREY_MAX_PARALLEL_FILES') {
        Remove-Item env:OSPREY_MAX_PARALLEL_FILES
    }

    $logPath = Join-Path $OutputDir ("{0}-{1}-run{2}.log" -f $VariantKey, $DatasetName, $RunIdx)
    Push-Location $workdir
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
        & $BinPath @cliArgs *>&1 | Tee-Object -FilePath $logPath | Out-Null
        $exit = $LASTEXITCODE
    } finally {
        Pop-Location
    }
    $sw.Stop()

    $stages = @{}
    foreach ($line in [System.IO.File]::ReadAllLines($logPath)) {
        if ($line -match '\[STAGE-WALL\]\s+(\S+):\s+([0-9.]+)s') {
            $stages[$Matches[1]] = [double]$Matches[2]
        }
    }
    # Fold C#'s separate second-pass-fdr marker into stage7 (matches the regression
    # harness's stage7 = 2nd-pass FDR + protein accounting).
    if ($stages.ContainsKey('second-pass-fdr')) {
        if ($stages.ContainsKey('stage7')) { $stages['stage7'] += $stages['second-pass-fdr'] }
        else { $stages['stage7'] = $stages['second-pass-fdr'] }
        $stages.Remove('second-pass-fdr') | Out-Null
    }

    Remove-Item $workdir -Recurse -Force -ErrorAction SilentlyContinue

    if ($exit -ne 0) { throw "${VariantKey}/${DatasetName}/run${RunIdx}: OspreySharp exited $exit (see $logPath)" }
    $missing = @($expectedStages | Where-Object { -not $stages.ContainsKey($_) })
    if ($missing.Count -gt 0) {
        Write-Host ("    [warn] missing [STAGE-WALL] markers: {0}" -f ($missing -join ', ')) -ForegroundColor Yellow
    }
    $stageStr = ($expectedStages | ForEach-Object {
        if ($stages.ContainsKey($_)) { "{0}={1:F1}s" -f $_, $stages[$_] } else { "{0}=MISS" -f $_ }
    }) -join '  '
    Write-Host ("    [{0}/{1}/run{2}] {3}  total={4:F1}s" -f $VariantKey, $DatasetName, $RunIdx, $stageStr, $sw.Elapsed.TotalSeconds) -ForegroundColor DarkGray

    return [pscustomobject]@{
        Variant = $VariantKey
        Dataset = $DatasetName
        RunIdx  = $RunIdx
        Stages  = $stages
        Total   = $sw.Elapsed.TotalSeconds
    }
}

function Get-Median {
    param([double[]]$Values)
    if ($Values.Count -eq 0) { return [double]::NaN }
    $sorted = @($Values | Sort-Object)
    $mid = [int][Math]::Floor($sorted.Count / 2.0)
    if ($sorted.Count % 2 -eq 1) { return $sorted[$mid] }
    return ($sorted[$mid - 1] + $sorted[$mid]) / 2.0
}

# One stage's wall (or total) from a single run; $null if absent.
function Get-StageVal {
    param([object]$Run, [string]$Stage)
    if ($null -eq $Run) { return $null }
    if ($Stage -eq 'total') { return $Run.Total }
    if ($Run.Stages.ContainsKey($Stage)) { return $Run.Stages[$Stage] }
    return $null
}

# Median of one variant's stage walls across its runs (display only).
function Get-StageMedian {
    param([object[]]$Runs, [string]$Stage)
    $vals = @($Runs | ForEach-Object { Get-StageVal $_ $Stage } | Where-Object { $_ -ne $null })
    if ($vals.Count -eq 0) { return [double]::NaN }
    return (Get-Median -Values $vals)
}

# --- Execute: interleaved, alternating order per repeat ------------------------
$allRuns = New-Object System.Collections.Generic.List[object]
foreach ($dsName in $datasetsToRun) {
    Write-Host ("Dataset {0}: {1} discarded warmup(s) + {2} interleaved A/B repeats" -f $dsName, $WarmupRuns, $Repeats) -ForegroundColor Cyan
    # Discarded warmup(s): warm the OS page cache for this dataset's mzML AND
    # absorb the post-reboot "fast first runs, then settle" transient, so no
    # MEASURED run pays a cold-disk or not-yet-settled penalty. Bump -WarmupRuns
    # on a freshly rebooted box where settling takes more than one run.
    for ($w = 1; $w -le $WarmupRuns; $w++) {
        $null = Invoke-PerfRun -BinPath $variants['baseline'].Bin -VariantKey 'warmup' -DatasetName $dsName -RunIdx $w
    }
    for ($r = 1; $r -le $Repeats; $r++) {
        # Alternate which variant runs first each repeat so neither side is
        # systematically the hotter (later) run within a repeat.
        $order = if ($r % 2 -eq 1) { @('baseline','branch') } else { @('branch','baseline') }
        foreach ($vKey in $order) {
            $run = Invoke-PerfRun -BinPath $variants[$vKey].Bin -VariantKey $vKey -DatasetName $dsName -RunIdx $r
            $allRuns.Add($run) | Out-Null
        }
    }
}

# --- Judge + report (paired per-rep deltas) -----------------------------------
# Each rep ran baseline and branch ADJACENTLY (alternating leader), so their
# ratio shares machine state and cancels the slow thermal/scheduling drift that
# pooling across all runs does not -- we judge on the per-rep delta distribution.
#
# HARD-FAIL is gated on TOTAL wall only: that is what "degraded performance"
# means, and total is far more stable than any single stage. Heavy stages
# (stage1to4, stage6) report as WARN -- a pure refactor that shifts time between
# stages at equal total is not a regression, and per-stage I/O walls are too
# noisy to fail a build on. A heavy-stage WARN with a flat total is a hint to
# look closer (a localized regression masked by a coincidental speedup), not a
# failure.
function Format-Time {
    param([double]$Seconds)
    if ([double]::IsNaN($Seconds)) { return '--' }
    if ($Seconds -lt 60) { return ('{0:F1}s' -f $Seconds) }
    $m = [int][Math]::Floor($Seconds / 60.0)
    $s = $Seconds - ($m * 60.0)
    return ('{0}:{1:00}' -f $m, [int][Math]::Floor($s))
}

# Per-rep % deltas (branch vs baseline) for one stage, pairing runs by RunIdx.
function Get-PairedDelta {
    param([object[]]$BaseRuns, [object[]]$BranchRuns, [string]$Stage, [int]$Reps)
    $perRep = @()
    for ($r = 1; $r -le $Reps; $r++) {
        $bRun = $BaseRuns   | Where-Object { $_.RunIdx -eq $r } | Select-Object -First 1
        $cRun = $BranchRuns | Where-Object { $_.RunIdx -eq $r } | Select-Object -First 1
        $bv = Get-StageVal $bRun $Stage
        $cv = Get-StageVal $cRun $Stage
        if ($null -ne $bv -and $null -ne $cv -and $bv -ne 0) {
            $perRep += (($cv / $bv) - 1.0) * 100.0
        }
    }
    return $perRep
}

$md = New-Object System.Collections.Generic.List[string]
$md.Add("# Test-PerfGate verdict") | Out-Null
$md.Add("") | Out-Null
$md.Add("- Generated: $((Get-Date).ToString('o'))") | Out-Null
$md.Add("- Baseline: ``$BaselineRoot``") | Out-Null
$md.Add("- Branch: ``$BranchRoot``") | Out-Null
$md.Add("- Repeats: $Repeats (paired per-rep deltas; median reported)") | Out-Null
$md.Add("- HARD-FAIL on total >$TotalThresholdPct% (every rep agrees); heavy stages >$StageThresholdPct% = WARN only") | Out-Null
$md.Add("") | Out-Null

$overallFail = $false
foreach ($dsName in $datasetsToRun) {
    $baseRuns   = @($allRuns | Where-Object { $_.Dataset -eq $dsName -and $_.Variant -eq 'baseline' })
    $branchRuns = @($allRuns | Where-Object { $_.Dataset -eq $dsName -and $_.Variant -eq 'branch' })

    $md.Add("## $dsName") | Out-Null
    $md.Add("") | Out-Null
    $md.Add("| Stage | Baseline med | Branch med | Delta % (median) | per-rep % | Gate |") | Out-Null
    $md.Add("|-------|-------------:|-----------:|-----------------:|-----------|:----:|") | Out-Null

    foreach ($stage in ($expectedStages + @('total'))) {
        $perRep    = Get-PairedDelta -BaseRuns $baseRuns -BranchRuns $branchRuns -Stage $stage -Reps $Repeats
        $baseMed   = Get-StageMedian -Runs $baseRuns   -Stage $stage
        $branchMed = Get-StageMedian -Runs $branchRuns -Stage $stage
        if ($perRep.Count -eq 0 -or [double]::IsNaN($baseMed)) {
            $md.Add(("| {0} | -- | -- | -- | -- | -- |" -f $stage)) | Out-Null
            continue
        }
        $medDelta = Get-Median -Values $perRep
        # Sign-consistent: every rep saw the branch slower (cancels one noisy
        # rep), combined with the median exceeding the threshold.
        $allSlower = @($perRep | Where-Object { $_ -le 0 }).Count -eq 0

        $isTotal = ($stage -eq 'total')
        $isHeavy = ($heavyStages -contains $stage)
        $threshold = if ($isTotal) { $TotalThresholdPct } else { $StageThresholdPct }
        $exceeds = ($medDelta -gt $threshold) -and $allSlower

        $gateCell =
            if ($isTotal) { if ($exceeds) { $overallFail = $true; 'FAIL' } else { 'ok' } }
            elseif ($isHeavy) { if ($exceeds) { 'warn' } else { 'ok' } }
            else { 'info' }

        $perRepStr = ($perRep | ForEach-Object { '{0:+0.0;-0.0;0.0}' -f $_ }) -join ', '
        $md.Add(("| {0} | {1} | {2} | {3:+0.0;-0.0;0.0} | {4} | {5} |" -f `
            $stage, (Format-Time $baseMed), (Format-Time $branchMed), $medDelta, $perRepStr, $gateCell)) | Out-Null
    }
    $md.Add("") | Out-Null
}

$verdictPath = Join-Path $OutputDir 'verdict.md'
$md | Out-File -FilePath $verdictPath -Encoding UTF8

Write-Host ""
$md | ForEach-Object { Write-Host $_ }
Write-Host ""
Write-Host ("Verdict written: {0}" -f $verdictPath) -ForegroundColor Cyan
Write-Host ""
if ($overallFail) {
    Write-Host "PERF GATE FAILED -- branch total wall regressed beyond threshold, every rep agreeing." -ForegroundColor Red
    Write-Host "Confirm code vs environment: re-run that dataset with Measure-Pipeline.ps1 -Tool Both and check Rust (the change-immune anchor) held flat." -ForegroundColor Yellow
    exit 1
}
Write-Host "PERF GATE PASSED -- no real total-wall regression vs baseline." -ForegroundColor Green
exit 0
