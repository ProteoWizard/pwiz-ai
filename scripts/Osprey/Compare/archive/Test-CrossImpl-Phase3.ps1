<#
.SYNOPSIS
    Cross-impl smoke test for Osprey Bug B port (file_stems +
    reconciliation hash override).

.DESCRIPTION
    Drives an HPC chain run that splits the work across implementations:

      Phase 1 (raw workers, --no-join):           Rust  osprey.exe
      Phase 2 (first-join, --join-at-pass=1 --join-only): Rust  osprey.exe
      Phase 3 (per-file rescore, --join-at-pass=1 --no-join): C# Osprey.exe
      Phase 4 (second-join, --join-at-pass=2):    Rust  osprey.exe

    The premise: Rust Phase 2 writes reconciliation.json with the v2
    `file_stems` field. The C# Phase 3 worker reads that field and
    stamps each reconciled .scores.parquet with the JOIN-WIDE
    reconciliation hash via `ReconciliationParameterHashForStems`. The
    Rust Phase 4 merge node validates that hash on read; if it
    matches, the C# Bug B port has successfully threaded the
    multi-file stems set from envelope to parquet metadata. If it
    fails, the Rust merge errors with "reconciliation hash mismatch".

    No truth comparison is required for this smoke test — the success
    signal is Phase 4 completing without hash-mismatch errors and
    producing a valid blib. For a stricter check, re-run after the
    test passes and compare the resulting blib to a same-config Rust-
    only Phase 4 output.

.PARAMETER Dataset
    Stellar or Astral.

.PARAMETER TestBaseDir
    Override dataset root (defaults to OSPREY_TEST_BASE_DIR or
    D:\test\osprey-runs).

.PARAMETER Force
    Wipe any existing workdirs before running.

.PARAMETER Threads
    --threads CLI flag. Default 16.
#>

param(
    [ValidateSet('Stellar','Astral')]
    [string]$Dataset = 'Stellar',
    [string]$TestBaseDir,
    [switch]$Force,
    [int]$Threads = 16
)

$ErrorActionPreference = 'Stop'
$projRoot = 'C:\proj'

. "$PSScriptRoot\Dataset-Config.ps1"

$ds = Get-DatasetConfig $Dataset -TestBaseDir $TestBaseDir
$dsDir = $ds.TestDir
$library = Join-Path $dsDir $ds.Library
$resolution = $ds.Resolution

$ospreyExe = Join-Path $projRoot 'osprey\target\release\osprey.exe'
if (-not (Test-Path $ospreyExe)) { throw "osprey.exe not found at $ospreyExe" }

$ospreyShExe = Join-Path $projRoot 'pwiz\pwiz_tools\Osprey\Osprey\bin\x64\Release\net472\Osprey.exe'
if (-not (Test-Path $ospreyShExe)) { throw "Osprey.exe not found at $ospreyShExe" }

$inputFiles = @($ds.AllFiles | ForEach-Object { Join-Path $dsDir $_ })
if ($inputFiles.Count -lt 2) { throw "Need at least 2 input files; got $($inputFiles.Count)" }
foreach ($f in $inputFiles) {
    if (-not (Test-Path $f)) { throw "Missing input mzML: $f" }
}
if (-not (Test-Path $library)) { throw "Missing library: $library" }

$workDir = Join-Path $dsDir '_crossimpl_phase3'
if ($Force -and (Test-Path $workDir)) {
    Write-Host "[CrossImpl] Removing $workDir ..." -ForegroundColor Yellow
    Remove-Item $workDir -Recurse -Force
}
$phase1Dir = Join-Path $workDir 'phase1_raw_rust'
$phase2Dir = Join-Path $workDir 'phase2_first_join_rust'
$phase3Dir = Join-Path $workDir 'phase3_csharp_worker'
$phase4Dir = Join-Path $workDir 'phase4_second_join_rust'

foreach ($d in @($phase1Dir, $phase2Dir, $phase3Dir, $phase4Dir)) {
    New-Item -ItemType Directory -Force -Path $d | Out-Null
}

function Format-Duration([TimeSpan]$ts) {
    "{0:00}:{1:00}" -f [int]$ts.TotalMinutes, $ts.Seconds
}

Write-Host "=== Test-CrossImpl-Phase3 ===" -ForegroundColor Cyan
Write-Host "Dataset:     $Dataset ($($inputFiles.Count) files)"
Write-Host "WorkDir:     $workDir"
Write-Host "Rust osprey: $ospreyExe"
Write-Host "C# Osprey:   $ospreyShExe"
Write-Host ""

# ---------- PHASE 1: Rust raw workers ----------
Write-Host "[Phase 1] Rust raw workers (--no-join) ..." -ForegroundColor Cyan
$sw = [System.Diagnostics.Stopwatch]::StartNew()
foreach ($f in $inputFiles) {
    $stem = [System.IO.Path]::GetFileNameWithoutExtension($f)
    $stagedMzML = Join-Path $phase1Dir ([System.IO.Path]::GetFileName($f))
    if (-not (Test-Path $stagedMzML)) { Copy-Item $f $stagedMzML }
    $a = @('-i', $stagedMzML, '-l', $library, '--resolution', $resolution,
           '--threads', $Threads, '--protein-fdr', '0.01', '--no-join')
    & $ospreyExe @a | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Phase 1 worker failed for $stem (exit $LASTEXITCODE)" }
}
$sw.Stop()
Write-Host ("  Phase 1 wall: {0}" -f (Format-Duration $sw.Elapsed))

$parquets = Get-ChildItem $phase1Dir -Filter '*.scores.parquet' | ForEach-Object { $_.FullName }
if ($parquets.Count -ne $inputFiles.Count) { throw "Phase 1 produced $($parquets.Count) parquets, expected $($inputFiles.Count)" }

# ---------- PHASE 2: Rust first-join (--join-at-pass=1 --join-only) ----------
Write-Host "[Phase 2] Rust first-join (--join-at-pass=1 --join-only) ..." -ForegroundColor Cyan
# Stage the phase 1 outputs + sibling .calibration.json into phase2 dir
foreach ($p in $parquets) {
    $stem = [System.IO.Path]::GetFileNameWithoutExtension([System.IO.Path]::GetFileNameWithoutExtension($p))
    Copy-Item $p (Join-Path $phase2Dir ([System.IO.Path]::GetFileName($p))) -Force
    $sourceCal = Join-Path $phase1Dir "$stem.calibration.json"
    if (Test-Path $sourceCal) {
        Copy-Item $sourceCal (Join-Path $phase2Dir "$stem.calibration.json") -Force
    }
    $sourceMzML = Join-Path $phase1Dir "$stem.mzML"
    if (Test-Path $sourceMzML) {
        Copy-Item $sourceMzML (Join-Path $phase2Dir "$stem.mzML") -Force
    }
}
$phase2Parquets = Get-ChildItem $phase2Dir -Filter '*.scores.parquet' | ForEach-Object { $_.FullName }

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$phase2OutBlib = Join-Path $phase2Dir 'phase2_unused.blib'
$a = @('--join-at-pass=1', '--join-only',
       '-l', $library, '-o', $phase2OutBlib,
       '--resolution', $resolution,
       '--threads', $Threads, '--protein-fdr', '0.01',
       '--input-scores') + $phase2Parquets
& $ospreyExe @a | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Phase 2 failed (exit $LASTEXITCODE)" }
$sw.Stop()
Write-Host ("  Phase 2 wall: {0}" -f (Format-Duration $sw.Elapsed))

# Verify reconciliation.json carries file_stems (v2 envelope)
$reconJsons = Get-ChildItem $phase2Dir -Filter '*.reconciliation.json'
if ($reconJsons.Count -ne $inputFiles.Count) { throw "Phase 2 produced $($reconJsons.Count) reconciliation.json files, expected $($inputFiles.Count)" }
$firstJson = Get-Content $reconJsons[0].FullName -Raw | ConvertFrom-Json
if (-not $firstJson.file_stems) { throw "Phase 2 reconciliation.json missing 'file_stems' field (Rust Bug B not in binary?)" }
if ($firstJson.format_version -ne 2) { throw "Phase 2 reconciliation.json has format_version=$($firstJson.format_version), expected 2" }
Write-Host ("  Verified v2 envelope: format_version=2, file_stems=[{0}]" -f ($firstJson.file_stems -join ', ')) -ForegroundColor Green

# ---------- PHASE 3: C# rescore worker (per file) ----------
Write-Host "[Phase 3] C# rescore workers (--join-at-pass=1 --no-join, per-file) ..." -ForegroundColor Cyan
$sw = [System.Diagnostics.Stopwatch]::StartNew()
foreach ($p in $phase2Parquets) {
    $stem = [System.IO.Path]::GetFileNameWithoutExtension([System.IO.Path]::GetFileNameWithoutExtension($p))
    Write-Host "  -- C# worker for $stem ..." -ForegroundColor Gray
    $workerDir = Join-Path $phase3Dir "worker_$stem"
    New-Item -ItemType Directory -Force -Path $workerDir | Out-Null
    # Stage this worker's parquet + sibling sidecars (matches what an HPC
    # job would receive). The C# worker reads reconciliation.json and
    # .1st-pass.fdr_scores.bin alongside the parquet.
    foreach ($ext in @('.scores.parquet', '.calibration.json', '.reconciliation.json',
                       '.1st-pass.fdr_scores.bin', '.mzML', '.spectra.bin')) {
        $srcFile = Join-Path $phase2Dir "$stem$ext"
        if (Test-Path $srcFile) {
            Copy-Item $srcFile (Join-Path $workerDir "$stem$ext") -Force
        }
    }
    $stagedParquet = Join-Path $workerDir "$stem.scores.parquet"
    $stagedOut = Join-Path $workerDir "$stem.unused.blib"
    $a = @('--join-at-pass=1', '--no-join',
           '-l', $library, '-o', $stagedOut,
           '--resolution', $resolution,
           '--threads', $Threads, '--protein-fdr', '0.01',
           '--input-scores', $stagedParquet)
    & $ospreyShExe @a | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Phase 3 C# worker failed for $stem (exit $LASTEXITCODE)" }
}
$sw.Stop()
Write-Host ("  Phase 3 total wall (serial): {0}" -f (Format-Duration $sw.Elapsed))

# ---------- PHASE 4: Rust second-join ----------
Write-Host "[Phase 4] Rust 2nd-join (--join-at-pass=2) ..." -ForegroundColor Cyan
# Stage all per-file C#-reconciled outputs (+ sidecars) into phase4 dir.
foreach ($p in $phase2Parquets) {
    $stem = [System.IO.Path]::GetFileNameWithoutExtension([System.IO.Path]::GetFileNameWithoutExtension($p))
    $workerDir = Join-Path $phase3Dir "worker_$stem"
    foreach ($ext in @('.scores.parquet', '.calibration.json', '.reconciliation.json',
                       '.1st-pass.fdr_scores.bin', '.mzML', '.spectra.bin')) {
        $srcFile = Join-Path $workerDir "$stem$ext"
        if (Test-Path $srcFile) {
            Copy-Item $srcFile (Join-Path $phase4Dir "$stem$ext") -Force
        }
    }
}
$phase4Parquets = Get-ChildItem $phase4Dir -Filter '*.scores.parquet' | ForEach-Object { $_.FullName }
$outBlib = Join-Path $phase4Dir "crossimpl.blib"
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$a = @('--join-at-pass=2',
       '-l', $library, '--resolution', $resolution,
       '--threads', $Threads, '--protein-fdr', '0.01',
       '-o', $outBlib,
       '--input-scores') + $phase4Parquets
& $ospreyExe @a | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Phase 4 failed (exit $LASTEXITCODE) -- this is the failure mode for hash mismatch if Bug B C# port is broken" }
$sw.Stop()
Write-Host ("  Phase 4 wall: {0}" -f (Format-Duration $sw.Elapsed))
if (-not (Test-Path $outBlib)) { throw "Phase 4 did not produce output blib at $outBlib" }
$blibSize = (Get-Item $outBlib).Length
Write-Host ("  Output blib: {0} bytes" -f $blibSize) -ForegroundColor Green

Write-Host ""
Write-Host "OVERALL: PASS  -- C# Phase 3 worker stamped a join-wide reconciliation hash that Rust Phase 4 accepted." -ForegroundColor Green
Write-Host "  This proves the C# Bug B port (file_stems envelope + ReconciliationParameterHashForStems) works end-to-end in a cross-impl chain."
