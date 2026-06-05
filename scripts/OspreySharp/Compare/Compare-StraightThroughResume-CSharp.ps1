<#
.SYNOPSIS
    Straight-through RESUME bit-parity gate: a full cold pipeline run vs a
    warm re-run that exercises the pure load-from-own-outputs Rehydrate paths.

.DESCRIPTION
    The worker-mode strict gate (Compare-Stage7-Rehydration-Strict-CSharp.ps1)
    exercises the --input-scores / --join-at-pass worker rehydration paths, but
    NOT the straight-through-RESUME deferrals: PerFileScoring (InputScores
    empty), FirstJoin (bundle == null), and PerFileRescore
    (!ExpectReconciledInput). Those fire only when the driver skips a task
    because its own outputs are already valid on disk (CanRehydrate) and a
    downstream task is the first to Demand its state. PR-D replaced those three
    Run-inside-Rehydrate deferrals with true load-from-own-outputs paths; this
    gate is their coverage.

    Shape:
      Phase COLD: OspreySharp -i mzML -l lib ...   (cold dir; runs every stage,
                  writes ALL stage outputs + output.blib)  -> output_cold.blib
      Phase WARM: delete output.blib (+ its validity sidecar), re-run the SAME
                  command in the SAME dir. The driver skips PerFileScoring /
                  FirstJoin / PerFileRescore (outputs valid), MergeNode re-runs
                  and Demands RescoredEntries -> the three pure Rehydrate paths
                  fire down the chain.                       -> output.blib

    Gate: output_cold.blib vs the warm output.blib must be byte / 1e-9 identical
    (Compare-Blib-Crossimpl.ps1). The warm run must also be MUCH faster than the
    cold run (it loads rather than computes) -- reported for a sanity check that
    the rehydrate paths actually replaced compute.

    CURRENT STATUS (2026-06-05): this gate intentionally EXPOSES the known,
    pre-existing straight-through-resume RT bug
    (ai/todos/backlog/TODO-ospreysharp_straightthrough_resume_1stpass_rt.md):
    on resume PerFileRescore leaves the buffer at the post-compaction (1st-pass)
    state, so MergeNode writes 1st-pass RTs to the blib (~11K/59768 entries diverge
    by ~1.3 min; warm blib 52,486,144 vs cold 52,514,816 on Stellar 3-file). PR-D
    (the typed-byproduct resume Rehydrate purification) is deliberately
    behavior-preserving and does NOT fix that bug, so this gate FAILS today. It is
    committed now as the standing gate that the resume-RT fix must turn green.

.PARAMETER Dataset
    Stellar (default, fast) or Astral (3-file, exercises multi-file rehydrate).

.PARAMETER TestBaseDir
    Override dataset root (defaults to Dataset-Config.ps1 default).

.PARAMETER Force
    Wipe any existing resume-test working dir before running.

.PARAMETER Threads
    --threads CLI flag. Default 16.

.PARAMETER Framework
    net8.0 (default) or net472.
#>

param(
    [ValidateSet('Stellar','Astral')]
    [string]$Dataset = 'Stellar',
    [string]$TestBaseDir,
    [switch]$Force,
    [int]$Threads = 16,
    [ValidateSet('net8.0','net472')]
    [string]$Framework = 'net8.0'
)

$ErrorActionPreference = 'Stop'
$compareDir = Split-Path -Parent $PSCommandPath
$ospreyDir  = Split-Path -Parent $compareDir
. (Join-Path $ospreyDir 'Dataset-Config.ps1')

$ospreyShExe = Get-OspreySharpExe -Framework $Framework
if (-not (Test-Path $ospreyShExe)) {
    Write-Host "OspreySharp.exe ($Framework) not found at $ospreyShExe -- build first." -ForegroundColor Red
    exit 2
}

$ds = Get-DatasetConfig $Dataset -TestBaseDir $TestBaseDir
$mzmls = @($ds.AllFiles)
$libraryName = $ds.Library
$resolution = $ds.Resolution
$datasetRoot = $ds.TestDir

$rootDir = Join-Path $datasetRoot "_resume_smoke_csharp_$Framework"
$workDir = Join-Path $rootDir 'run'
$coldBlib = Join-Path $rootDir 'output_cold.blib'

if ($Force -and (Test-Path $rootDir)) {
    Write-Host "[Resume] -Force: removing $rootDir" -ForegroundColor DarkYellow
    Remove-Item $rootDir -Recurse -Force
}
New-Item -ItemType Directory -Path $workDir -Force | Out-Null

# Stage inputs (mzML + library + libcache) into the work dir.
foreach ($f in $mzmls) { Copy-Item (Join-Path $datasetRoot $f) (Join-Path $workDir $f) }
Copy-Item (Join-Path $datasetRoot $libraryName) (Join-Path $workDir $libraryName)
$libcache = Join-Path $datasetRoot ($libraryName + '.libcache')
if (Test-Path $libcache) { Copy-Item $libcache (Join-Path $workDir ($libraryName + '.libcache')) }

function Invoke-Run {
    param([string]$LogName)
    $logPath = Join-Path $rootDir $LogName
    $cliArgs = @()
    foreach ($f in $mzmls) { $cliArgs += @('-i', $f) }
    $cliArgs += @('-l', $libraryName, '-o', 'output.blib',
                  '--resolution', $resolution,
                  '--protein-fdr', '0.01', '--threads', $Threads.ToString())
    Push-Location $workDir
    try {
        $sw = [Diagnostics.Stopwatch]::StartNew()
        & $ospreyShExe @cliArgs 2>&1 | Tee-Object -FilePath $logPath | Out-Null
        $exit = $LASTEXITCODE
        $sw.Stop()
    } finally { Pop-Location }
    if ($exit -ne 0) {
        Write-Host "  OspreySharp exited $exit; see $logPath" -ForegroundColor Red
        throw "OspreySharp failed (exit=$exit)."
    }
    return @{ wall = $sw.Elapsed; logPath = $logPath }
}

Write-Host ""
Write-Host "=== Compare-StraightThroughResume-CSharp ($Dataset, $($mzmls.Count) file(s), $Framework) ===" -ForegroundColor Cyan
Write-Host ("Workdir: {0}" -f $workDir)
Write-Host ""

# ----- Phase COLD -----
Write-Host "[COLD] full pipeline (every stage computes) ..." -ForegroundColor Cyan
$rCold = Invoke-Run -LogName 'cold.log'
$blibInWork = Join-Path $workDir 'output.blib'
if (-not (Test-Path $blibInWork)) { Write-Host "COLD produced no output.blib" -ForegroundColor Red; exit 1 }
Copy-Item $blibInWork $coldBlib -Force
Write-Host ("  COLD wall: {0:mm\:ss}; blib: {1} bytes" -f $rCold.wall, (Get-Item $coldBlib).Length) -ForegroundColor Green

# ----- Phase WARM (resume) -----
# Delete only the blib + any blib validity sidecar so MergeNode re-runs while
# every upstream task's outputs stay valid on disk (driver skips them ->
# downstream Demand fires the pure Rehydrate paths).
Remove-Item $blibInWork -Force
Get-ChildItem -Path $workDir -Filter '*.osprey.task' -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like 'output.blib*' -or $_.Name -like '*MergeNode*' } |
    Remove-Item -Force -ErrorAction SilentlyContinue
Write-Host "[WARM] resume re-run (upstream outputs valid -> pure Rehydrate paths) ..." -ForegroundColor Cyan
$rWarm = Invoke-Run -LogName 'warm.log'
if (-not (Test-Path $blibInWork)) { Write-Host "WARM produced no output.blib" -ForegroundColor Red; exit 1 }
Write-Host ("  WARM wall: {0:mm\:ss}; blib: {1} bytes" -f $rWarm.wall, (Get-Item $blibInWork).Length) -ForegroundColor Green

# Sanity: the warm run should be much faster (loaded, not computed).
$speedup = if ($rWarm.wall.TotalSeconds -gt 0) { $rCold.wall.TotalSeconds / $rWarm.wall.TotalSeconds } else { 0 }
Write-Host ("  Speedup (cold/warm): {0:F1}x" -f $speedup) -ForegroundColor Gray

# Evidence that the resume actually skipped per-file scoring (the Run compute
# path logs "===== Processing file" only when ProcessFile runs from spectra).
$warmProcessing = (Select-String -Path $rWarm.logPath -Pattern '===== Processing file' -AllMatches | Measure-Object).Count
Write-Host ("  WARM 'Processing file' (from-spectra) occurrences: {0} (expect 0 on a pure resume)" -f $warmProcessing) -ForegroundColor Gray

# ----- GATE: blib parity (cold vs warm) -----
Write-Host ""
Write-Host "=== Blib parity (COLD vs WARM resume) ===" -ForegroundColor Cyan
$blibCmp = Join-Path $compareDir 'Compare-Blib-Crossimpl.ps1'
$blibLog = Join-Path $rootDir 'blib_compare.log'
& pwsh -File $blibCmp -RustBlib $coldBlib -CsBlib $blibInWork *>&1 |
    Tee-Object -FilePath $blibLog | Out-Null
$blibOk = ($LASTEXITCODE -eq 0)
Write-Host ("  {0}  Blib content (SQL row+col 1e-9; full log: {1})" -f `
    $(if ($blibOk) { 'PASS' } else { 'FAIL' }), $blibLog) `
    -ForegroundColor $(if ($blibOk) { 'Green' } else { 'Red' })

Write-Host ""
if ($blibOk) {
    Write-Host "OVERALL: PASS -- straight-through resume (pure Rehydrate) is blib-identical to the cold run on $Dataset ($Framework)" -ForegroundColor Green
    exit 0
} else {
    Write-Host "OVERALL: FAIL -- resume blib diverged from the cold run; a pure Rehydrate path does not reproduce Run's state." -ForegroundColor Red
    exit 1
}
