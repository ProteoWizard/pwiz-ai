<#
.SYNOPSIS
    Symmetric cross-impl smoke test for Osprey Bug B port: the C#
    side WRITES the v2 reconciliation.json envelope, and Rust must
    read it and accept the C#-computed join-wide reconciliation hash.

.DESCRIPTION
    Companion to Test-CrossImpl-Phase3.ps1, which exercised the
    C# READ side of Bug B (Rust planner → C# worker → Rust merge).

    Here we exercise the C# WRITE side:

      Phase 1 (raw workers, --no-join):                        Rust  osprey.exe
      Phase 2 (first-join, --join-at-pass=1 --join-only):      C#    Osprey.exe   <-- writes v2 envelope
      Phase 3 (per-file rescore, --join-at-pass=1 --no-join):  Rust  osprey.exe        <-- reads v2 envelope
      Phase 4 (second-join, --join-at-pass=2):                 Rust  osprey.exe        <-- validates hash

    Success criteria (in order):
      1. Phase 2 C# planner emits reconciliation.json with
         `format_version=2` and a populated `file_stems` field
         (verified by inline JSON inspection).
      2. Phase 3 Rust workers consume the C#-written envelopes without
         deserialization errors and stamp the join-wide
         reconciliation_hash that comes from the C# `file_stems` set.
      3. Phase 4 Rust merge validates the stamped hash and completes
         without "reconciliation hash mismatch" errors.

    If any of these fail, the C# Bug B WRITE side has a defect (likely
    in FirstJoinTask.BuildReconciliationFile or
    OspreyConfig.ReconciliationParameterHashForStems on the C# side).

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

$workDir = Join-Path $dsDir '_crossimpl_planner'
if ($Force -and (Test-Path $workDir)) {
    Write-Host "[CrossImpl-Planner] Removing $workDir ..." -ForegroundColor Yellow
    Remove-Item $workDir -Recurse -Force
}
$phase1Dir = Join-Path $workDir 'phase1_raw_rust'
$phase2Dir = Join-Path $workDir 'phase2_first_join_csharp'
$phase3Dir = Join-Path $workDir 'phase3_rust_workers'
$phase4Dir = Join-Path $workDir 'phase4_second_join_rust'

foreach ($d in @($phase1Dir, $phase2Dir, $phase3Dir, $phase4Dir)) {
    New-Item -ItemType Directory -Force -Path $d | Out-Null
}

function Format-Duration([TimeSpan]$ts) {
    "{0:00}:{1:00}" -f [int]$ts.TotalMinutes, $ts.Seconds
}

Write-Host "=== Test-CrossImpl-Planner ===" -ForegroundColor Cyan
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

# ---------- PHASE 2: C# first-join (--join-at-pass=1 --join-only) ----------
Write-Host "[Phase 2] C# first-join (--join-at-pass=1 --join-only) ..." -ForegroundColor Cyan
# Stage the phase 1 outputs + sibling .calibration.json + .mzML into phase2 dir
foreach ($p in $parquets) {
    $stem = [System.IO.Path]::GetFileNameWithoutExtension([System.IO.Path]::GetFileNameWithoutExtension($p))
    Copy-Item $p (Join-Path $phase2Dir ([System.IO.Path]::GetFileName($p))) -Force
    $sourceCal = Join-Path $phase1Dir "$stem.calibration.json"
    if (Test-Path $sourceCal) { Copy-Item $sourceCal (Join-Path $phase2Dir "$stem.calibration.json") -Force }
    $sourceMzML = Join-Path $phase1Dir "$stem.mzML"
    if (Test-Path $sourceMzML) { Copy-Item $sourceMzML (Join-Path $phase2Dir "$stem.mzML") -Force }
}
$phase2Parquets = Get-ChildItem $phase2Dir -Filter '*.scores.parquet' | ForEach-Object { $_.FullName }

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$phase2OutBlib = Join-Path $phase2Dir 'phase2_unused.blib'
$a = @('--join-at-pass=1', '--join-only',
       '-l', $library, '-o', $phase2OutBlib,
       '--resolution', $resolution,
       '--threads', $Threads, '--protein-fdr', '0.01',
       '--input-scores') + $phase2Parquets
& $ospreyShExe @a | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Phase 2 (C#) failed (exit $LASTEXITCODE)" }
$sw.Stop()
Write-Host ("  Phase 2 wall: {0}" -f (Format-Duration $sw.Elapsed))

# Verify reconciliation.json carries file_stems (v2 envelope from C#)
$reconJsons = Get-ChildItem $phase2Dir -Filter '*.reconciliation.json'
if ($reconJsons.Count -ne $inputFiles.Count) { throw "C# Phase 2 produced $($reconJsons.Count) reconciliation.json files, expected $($inputFiles.Count)" }
$firstJson = Get-Content $reconJsons[0].FullName -Raw | ConvertFrom-Json
if (-not $firstJson.file_stems) { throw "C# Phase 2 reconciliation.json missing 'file_stems' field (Bug B C# WRITE side broken)" }
if ($firstJson.format_version -ne 2) { throw "C# Phase 2 reconciliation.json has format_version=$($firstJson.format_version), expected 2" }
Write-Host ("  Verified C# v2 envelope: format_version=2, file_stems=[{0}]" -f ($firstJson.file_stems -join ', ')) -ForegroundColor Green

# Cross-check: all sibling reconciliation.json files carry the same file_stems set.
$expectedStems = $firstJson.file_stems | Sort-Object
for ($i = 1; $i -lt $reconJsons.Count; $i++) {
    $sibling = Get-Content $reconJsons[$i].FullName -Raw | ConvertFrom-Json
    $siblingStems = $sibling.file_stems | Sort-Object
    if (-not $sibling.file_stems -or @(Compare-Object $expectedStems $siblingStems).Count -ne 0) {
        throw "C# Phase 2: sibling reconciliation.json $($reconJsons[$i].Name) has divergent file_stems"
    }
}
Write-Host "  Verified C# v2 envelope: all $($reconJsons.Count) reconciliation.json siblings carry the same file_stems set" -ForegroundColor Green

# ---------- PHASE 3: Rust rescore workers (per file) ----------
Write-Host "[Phase 3] Rust rescore workers (--join-at-pass=1 --no-join, per-file) ..." -ForegroundColor Cyan
$sw = [System.Diagnostics.Stopwatch]::StartNew()
foreach ($p in $phase2Parquets) {
    $stem = [System.IO.Path]::GetFileNameWithoutExtension([System.IO.Path]::GetFileNameWithoutExtension($p))
    Write-Host "  -- Rust worker for $stem ..." -ForegroundColor Gray
    $workerDir = Join-Path $phase3Dir "worker_$stem"
    New-Item -ItemType Directory -Force -Path $workerDir | Out-Null
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
    & $ospreyExe @a | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Phase 3 Rust worker failed for $stem (exit $LASTEXITCODE) -- check if Rust deserialized the C#-written reconciliation.json correctly" }
}
$sw.Stop()
Write-Host ("  Phase 3 total wall (serial): {0}" -f (Format-Duration $sw.Elapsed))

# ---------- PHASE 4: Rust second-join ----------
Write-Host "[Phase 4] Rust 2nd-join (--join-at-pass=2) ..." -ForegroundColor Cyan
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
$outBlib = Join-Path $phase4Dir "crossimpl_planner.blib"
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$a = @('--join-at-pass=2',
       '-l', $library, '--resolution', $resolution,
       '--threads', $Threads, '--protein-fdr', '0.01',
       '-o', $outBlib,
       '--input-scores') + $phase4Parquets
& $ospreyExe @a | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Phase 4 failed (exit $LASTEXITCODE) -- this is the failure mode if the C#-stamped reconciliation_hash in any reconciled parquet does not match the join-wide hash" }
$sw.Stop()
Write-Host ("  Phase 4 wall: {0}" -f (Format-Duration $sw.Elapsed))
if (-not (Test-Path $outBlib)) { throw "Phase 4 did not produce output blib at $outBlib" }
$blibSize = (Get-Item $outBlib).Length
Write-Host ("  Output blib: {0} bytes" -f $blibSize) -ForegroundColor Green

Write-Host ""
Write-Host "OVERALL: PASS  -- C# Phase 2 planner wrote a v2 reconciliation.json that Rust workers + merge consumed without error." -ForegroundColor Green
Write-Host "  This proves the C# Bug B WRITE side (FirstJoinTask.BuildReconciliationFile populating file_stems + sibling consistency)"
Write-Host "  produces an envelope that Rust's strict deserializer (deny_unknown_fields) accepts, and that the join-wide reconciliation"
Write-Host "  hash computed by Rust workers from the C# envelope matches what Rust merge expects."
