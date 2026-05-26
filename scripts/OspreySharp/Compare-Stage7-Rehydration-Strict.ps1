<#
.SYNOPSIS
    Strict bit-parity test for the full HPC rehydration chain vs
    straight-through Rust truth.

.DESCRIPTION
    Walks the four-step HPC distribution chain with REAL mzML files
    + REAL .calibration.json sidecars and confirms the final blib +
    Stage 7 protein FDR dump bit-match a straight-through
    `osprey -i mzML` baseline on the same inputs.

    Companion to the older `Compare-Stage7-Rehydration.ps1`. That
    earlier test had a fundamental weakness uncovered 2026-05-18:

    1. It used STUB (empty) mzML files in the rehydrate workdirs
       (`New-Item -ItemType File ... .mzML`).
    2. It did NOT copy `.calibration.json` sidecars into the rehydrate
       workdirs.
    3. With both missing, Stage 6 silently produced zero reconciliation
       actions and zero rescore work in BOTH compared runs.
    4. Both runs converged on the same broken-relative-to-truth
       45153-precursor blib on Stellar 3-file.
    5. SHA-256 matched between the two broken outputs -> the gate
       passed despite the chain producing 25% fewer precursors than
       a straight-through `-i mzML` run (60373).

    This script removes those weaknesses:

      Phase 0 (TRUTH): `osprey -i mzML ... ` — fresh straight-through.
        Produces the reference `output.blib` + `rust_stage7_protein_fdr.tsv`
        + per-file reconciled `.scores.parquet`.

      Phase 1 (HPC worker, raw): `osprey -i mzML ... --no-join`
        Per-file Stage 1-4 fan-out. Each worker produces
        `<stem>.scores.parquet` + `<stem>.calibration.json` next to
        the input mzML, then exits.

      Phase 2 (HPC merge, 1st-join): `osprey --join-at-pass=1 --join-only
                                       --input-scores <all 3 parquets> -l ...`
        Reads all per-file Stage 4 parquets; runs first-pass FDR +
        reconciliation planning; writes `<stem>.1st-pass.fdr_scores.bin`
        sidecars and `<stem>.reconciliation.json` per file; exits before
        Stage 6. The merge node does NOT need mzML files.

      Phase 3 (HPC worker, rescore): per file:
        `osprey --join-at-pass=1 --no-join --input-scores <single parquet>
                -l ...`
        Each per-file worker rescores at the reconciled boundaries it
        loads from `reconciliation.json`, using the local sibling mzML
        + .calibration.json + .1st-pass.fdr_scores.bin + parquet, and
        writes a reconciled `<stem>.scores.parquet` (overwriting the
        raw Stage 4 parquet that arrived from Phase 1).

      Phase 4 (HPC merge, 2nd-join): `osprey --join-at-pass=2
                                       --input-scores <all 3 reconciled> -l ...`
        Reads reconciled parquets; runs 2nd-pass Percolator FDR on the
        rescored entries; runs protein parsimony + picked-protein FDR;
        writes the final `output.blib` + `output.proteins.csv`. The
        merge node does NOT need mzML files.

    Pass criterion: Phase 4's `output.blib` + `rust_stage7_protein_fdr.tsv`
    match Phase 0's same artifacts at SHA-256 byte equality (Stage 7 dump)
    + 1e-9 absolute on numeric blib columns (Compare-Blib-Crossimpl).

    Fail criterion: any divergence between the HPC chain end and the
    straight-through end. The chain SHOULD reproduce the straight-through
    pipeline exactly.

.PARAMETER Dataset
    Stellar (default; Astral support after Stellar passes).

.PARAMETER TestBaseDir
    Override dataset root (defaults to $env:OSPREY_TEST_BASE_DIR or
    D:\test\osprey-runs).

.PARAMETER Force
    Wipe any existing strict-test working dirs before running.

.PARAMETER SkipTruth
    Reuse the existing Phase 0 truth run if its blib + stage7 dump
    are still on disk. Useful for iterating on chain bugs after truth
    is settled.

.PARAMETER StopAtPhase
    Stop after the named phase (truth | phase1 | phase2 | phase3 | phase4).
    Default 'phase4' (run everything + compare). Earlier values are
    useful for stage-by-stage bisection.

.PARAMETER Threads
    --threads CLI flag. Default 16.

.EXAMPLE
    pwsh -File .\Compare-Stage7-Rehydration-Strict.ps1 -Force
.EXAMPLE
    pwsh -File .\Compare-Stage7-Rehydration-Strict.ps1 -SkipTruth -StopAtPhase phase2
#>

param(
    [ValidateSet('Stellar','Astral')]
    [string]$Dataset = 'Stellar',

    [string]$TestBaseDir = $null,

    [switch]$Force,
    [switch]$SkipTruth,

    [ValidateSet('truth','phase1','phase2','phase3','phase4')]
    [string]$StopAtPhase = 'phase4',

    [int]$Threads = 16
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$scriptDir = Split-Path -Parent $PSCommandPath
. (Join-Path $scriptDir 'Dataset-Config.ps1')

$projRoot = (Resolve-Path (Join-Path $scriptDir '..\..\..')).Path
$ospreyExe = Join-Path $projRoot 'osprey\target\release\osprey.exe'
if (-not (Test-Path $ospreyExe)) {
    Write-Host "osprey.exe not found at $ospreyExe -- build first:" -ForegroundColor Red
    Write-Host "  pwsh -File ./ai/scripts/OspreySharp/Build-OspreyRust.ps1" -ForegroundColor Yellow
    exit 2
}

$ds = Get-DatasetConfig $Dataset -TestBaseDir $TestBaseDir
$mzmls = @($ds.AllFiles)
$libraryName = $ds.Library
$resolution = $ds.Resolution
$datasetRoot = $ds.TestDir

# Strict-test workdir hierarchy under $datasetRoot
$rootDir   = Join-Path $datasetRoot "_strict_rehydration"
$truthDir  = Join-Path $rootDir "phase0_truth"
$ph1Dir    = Join-Path $rootDir "phase1_raw_workers"
$ph2Dir    = Join-Path $rootDir "phase2_first_join"
$ph3Roots  = @()  # one workdir per file for Phase 3, populated below
$ph4Dir    = Join-Path $rootDir "phase4_second_join"

if ($Force -and (Test-Path $rootDir)) {
    Write-Host "[Strict] -Force: removing $rootDir" -ForegroundColor DarkYellow
    Remove-Item $rootDir -Recurse -Force
}
New-Item -ItemType Directory -Path $rootDir -Force | Out-Null

function Stage-DatasetFiles {
    param([string]$Dir, [string[]]$Files = $mzmls, [bool]$IncludeMzml = $true, [bool]$IncludeLibcache = $true)
    if ($IncludeMzml) {
        foreach ($f in $Files) {
            Copy-Item (Join-Path $datasetRoot $f) (Join-Path $Dir $f)
        }
    }
    Copy-Item (Join-Path $datasetRoot $libraryName) (Join-Path $Dir $libraryName)
    if ($IncludeLibcache) {
        $cache = Join-Path $datasetRoot ($libraryName + '.libcache')
        if (Test-Path $cache) {
            Copy-Item $cache (Join-Path $Dir ($libraryName + '.libcache'))
        }
    }
}

function Invoke-Osprey {
    param([string]$WorkDir, [string[]]$CliArgs, [string]$LogName = 'osprey.log')
    $logPath = Join-Path $WorkDir $LogName
    Push-Location $WorkDir
    try {
        $sw = [Diagnostics.Stopwatch]::StartNew()
        & $ospreyExe @CliArgs 2>&1 | Tee-Object -FilePath $logPath | Out-Null
        $exit = $LASTEXITCODE
        $sw.Stop()
        if ($exit -ne 0) {
            Write-Host ("  osprey exited {0}; see {1}" -f $exit, $logPath) -ForegroundColor Red
            throw "osprey failed (exit=$exit). See $logPath."
        }
        return @{ exit = $exit; wall = $sw.Elapsed; logPath = $logPath }
    } finally {
        Pop-Location
    }
}

function Get-PrecursorCount {
    param([string]$LogPath)
    $m = Select-String -Path $LogPath -Pattern 'Wrote\s+(\d+)\s+precursors' -AllMatches | Select-Object -Last 1
    if ($m -and $m.Matches.Count -gt 0) { return [int]$m.Matches[0].Groups[1].Value }
    return -1
}

function Format-Duration {
    param([TimeSpan]$T)
    return ('{0:mm\:ss}' -f $T)
}

Write-Host ""
Write-Host "=== Compare-Stage7-Rehydration-Strict ===" -ForegroundColor Cyan
Write-Host ("Dataset: {0} ({1} files)" -f $Dataset, $mzmls.Count)
Write-Host ("Truth dir:        {0}" -f $truthDir)
Write-Host ("Phase 1 dir:      {0}" -f $ph1Dir)
Write-Host ("Phase 2 dir:      {0}" -f $ph2Dir)
Write-Host ("Phase 3 dirs:     {0}/phase3_worker_<stem>/  (one per file)" -f $rootDir)
Write-Host ("Phase 4 dir:      {0}" -f $ph4Dir)
Write-Host ("Stop at:          {0}" -f $StopAtPhase)
Write-Host ""

# ----- PHASE 0: TRUTH (straight-through -i mzML) -----
$truthBlib  = Join-Path $truthDir 'output.blib'
$truthDump  = Join-Path $truthDir 'rust_stage7_protein_fdr.tsv'
$truthLog   = Join-Path $truthDir 'osprey.log'
$truthPrecursors = -1

if ($SkipTruth -and (Test-Path $truthBlib) -and (Test-Path $truthDump)) {
    Write-Host "[Phase 0] -SkipTruth: reusing $truthBlib" -ForegroundColor DarkGray
    if (Test-Path $truthLog) { $truthPrecursors = Get-PrecursorCount -LogPath $truthLog }
} else {
    if (Test-Path $truthDir) { Remove-Item $truthDir -Recurse -Force }
    New-Item -ItemType Directory -Path $truthDir -Force | Out-Null
    Stage-DatasetFiles -Dir $truthDir
    Write-Host "[Phase 0] TRUTH (-i mzML, straight-through) ..." -ForegroundColor Cyan
    $args0 = @()
    foreach ($f in $mzmls) { $args0 += @('-i', $f) }
    $args0 += @('-l', $libraryName, '-o', 'output.blib',
                '--resolution', $resolution,
                '--protein-fdr', '0.01', '--threads', $Threads.ToString())
    # Stage 7 protein FDR dump for the parity comparison.
    $env:OSPREY_DUMP_STAGE7_PROTEIN_FDR = '1'
    try {
        $r0 = Invoke-Osprey -WorkDir $truthDir -CliArgs $args0
    } finally {
        Remove-Item Env:OSPREY_DUMP_STAGE7_PROTEIN_FDR -ErrorAction SilentlyContinue
    }
    $truthPrecursors = Get-PrecursorCount -LogPath $r0.logPath
    Write-Host ("  Phase 0 wall: {0}; precursors: {1}; blib: {2}" -f `
        (Format-Duration $r0.wall), $truthPrecursors, (Get-Item $truthBlib).Length) -ForegroundColor Green
}
if ($StopAtPhase -eq 'truth') {
    Write-Host "Stopping after truth (per -StopAtPhase truth)." -ForegroundColor DarkGray
    exit 0
}

# ----- PHASE 1: per-file raw workers (--no-join) -----
if (Test-Path $ph1Dir) { Remove-Item $ph1Dir -Recurse -Force }
New-Item -ItemType Directory -Path $ph1Dir -Force | Out-Null
Stage-DatasetFiles -Dir $ph1Dir
Write-Host "[Phase 1] HPC raw workers (--no-join, per-file Stage 1-4) ..." -ForegroundColor Cyan
# Single process with all 3 -i; -no-join exits after Stage 4.
# (Equivalent to N parallel single-file workers — the binary doesn't care
# whether you fan out N processes or run them serially in one for the
# Stage 4 parquet output.)
$args1 = @()
foreach ($f in $mzmls) { $args1 += @('-i', $f) }
$args1 += @('-l', $libraryName, '-o', 'output.blib',
            '--resolution', $resolution,
            '--protein-fdr', '0.01', '--threads', $Threads.ToString(),
            '--no-join')
$r1 = Invoke-Osprey -WorkDir $ph1Dir -CliArgs $args1

# Sanity: confirm Stage 1-4 outputs were produced
foreach ($f in $mzmls) {
    $stem = [IO.Path]::GetFileNameWithoutExtension($f)
    foreach ($ext in @('.scores.parquet', '.calibration.json')) {
        $p = Join-Path $ph1Dir ($stem + $ext)
        if (-not (Test-Path $p)) { throw "Phase 1 did not produce $p" }
    }
}
Write-Host ("  Phase 1 wall: {0}; per-file .scores.parquet + .calibration.json: OK" -f `
    (Format-Duration $r1.wall)) -ForegroundColor Green
if ($StopAtPhase -eq 'phase1') {
    Write-Host "Stopping after phase 1 (per -StopAtPhase phase1)." -ForegroundColor DarkGray
    exit 0
}

# ----- PHASE 2: merge node 1st-join (--join-at-pass=1 --join-only) -----
# Stage Phase 1's outputs into Phase 2 workdir. Merge node only needs
# the .scores.parquet (raw) + .calibration.json sibling + the library.
# No mzML required at the merge node.
if (Test-Path $ph2Dir) { Remove-Item $ph2Dir -Recurse -Force }
New-Item -ItemType Directory -Path $ph2Dir -Force | Out-Null
foreach ($f in $mzmls) {
    $stem = [IO.Path]::GetFileNameWithoutExtension($f)
    Copy-Item (Join-Path $ph1Dir ($stem + '.scores.parquet'))  (Join-Path $ph2Dir ($stem + '.scores.parquet'))
    Copy-Item (Join-Path $ph1Dir ($stem + '.calibration.json'))(Join-Path $ph2Dir ($stem + '.calibration.json'))
    # synthetic_input_from_parquet expects a sibling .mzML stub for path
    # derivation, even though the merge node never opens it.
    New-Item -ItemType File -Path (Join-Path $ph2Dir ($stem + '.mzML')) -Force | Out-Null
}
Stage-DatasetFiles -Dir $ph2Dir -IncludeMzml:$false
Write-Host "[Phase 2] HPC 1st-join merge (--join-at-pass=1 --join-only) ..." -ForegroundColor Cyan
$args2 = @('--join-at-pass=1', '--join-only')
foreach ($f in $mzmls) {
    $stem = [IO.Path]::GetFileNameWithoutExtension($f)
    $args2 += @('--input-scores', ($stem + '.scores.parquet'))
}
$args2 += @('-l', $libraryName, '-o', 'output.blib',
            '--resolution', $resolution,
            '--protein-fdr', '0.01', '--threads', $Threads.ToString())
$r2 = Invoke-Osprey -WorkDir $ph2Dir -CliArgs $args2

# Sanity: confirm Stage 5 outputs were produced
foreach ($f in $mzmls) {
    $stem = [IO.Path]::GetFileNameWithoutExtension($f)
    foreach ($ext in @('.1st-pass.fdr_scores.bin', '.reconciliation.json')) {
        $p = Join-Path $ph2Dir ($stem + $ext)
        if (-not (Test-Path $p)) { throw "Phase 2 did not produce $p" }
    }
}
Write-Host ("  Phase 2 wall: {0}; per-file .1st-pass.fdr_scores.bin + .reconciliation.json: OK" -f `
    (Format-Duration $r2.wall)) -ForegroundColor Green
if ($StopAtPhase -eq 'phase2') {
    Write-Host "Stopping after phase 2 (per -StopAtPhase phase2)." -ForegroundColor DarkGray
    exit 0
}

# ----- PHASE 3: per-file rescore workers (--join-at-pass=1 --no-join) -----
# Each worker gets ITS file's mzML + .scores.parquet + .calibration.json
# + .1st-pass.fdr_scores.bin + .reconciliation.json + the library.
# The worker rescores at reconciled boundaries and overwrites the .scores.parquet
# with reconciled content.
Write-Host "[Phase 3] HPC rescore workers (--join-at-pass=1 --no-join, per-file) ..." -ForegroundColor Cyan
$ph3Total = [TimeSpan]::Zero
foreach ($f in $mzmls) {
    $stem = [IO.Path]::GetFileNameWithoutExtension($f)
    $ph3Dir = Join-Path $rootDir ("phase3_worker_" + $stem)
    $ph3Roots += $ph3Dir
    if (Test-Path $ph3Dir) { Remove-Item $ph3Dir -Recurse -Force }
    New-Item -ItemType Directory -Path $ph3Dir -Force | Out-Null
    # Real mzML this worker will re-read for rescore feature extraction.
    Copy-Item (Join-Path $datasetRoot $f) (Join-Path $ph3Dir $f)
    # Phase 1 Stage 4 parquet -- about to be OVERWRITTEN with reconciled version.
    Copy-Item (Join-Path $ph1Dir ($stem + '.scores.parquet')) (Join-Path $ph3Dir ($stem + '.scores.parquet'))
    Copy-Item (Join-Path $ph1Dir ($stem + '.calibration.json')) (Join-Path $ph3Dir ($stem + '.calibration.json'))
    # Phase 2 stage 5 outputs (boundary file pair)
    Copy-Item (Join-Path $ph2Dir ($stem + '.1st-pass.fdr_scores.bin')) (Join-Path $ph3Dir ($stem + '.1st-pass.fdr_scores.bin'))
    Copy-Item (Join-Path $ph2Dir ($stem + '.reconciliation.json')) (Join-Path $ph3Dir ($stem + '.reconciliation.json'))
    # Library
    Stage-DatasetFiles -Dir $ph3Dir -IncludeMzml:$false
    Write-Host ("  -- worker for {0} ..." -f $stem) -ForegroundColor DarkCyan
    $args3 = @('--join-at-pass=1', '--no-join',
               '--input-scores', ($stem + '.scores.parquet'),
               '-l', $libraryName, '-o', 'output.blib',
               '--resolution', $resolution,
               '--protein-fdr', '0.01', '--threads', $Threads.ToString())
    $r3 = Invoke-Osprey -WorkDir $ph3Dir -CliArgs $args3
    $ph3Total += $r3.wall
}
Write-Host ("  Phase 3 total wall (serial): {0}; per-file reconciled .scores.parquet: OK" -f `
    (Format-Duration $ph3Total)) -ForegroundColor Green
if ($StopAtPhase -eq 'phase3') {
    Write-Host "Stopping after phase 3 (per -StopAtPhase phase3)." -ForegroundColor DarkGray
    exit 0
}

# ----- PHASE 4: 2nd-join merge node (--join-at-pass=2) -----
# Reconciled parquets from each Phase 3 worker get staged together; merge
# node doesn't need mzMLs (per design).
if (Test-Path $ph4Dir) { Remove-Item $ph4Dir -Recurse -Force }
New-Item -ItemType Directory -Path $ph4Dir -Force | Out-Null
foreach ($f in $mzmls) {
    $stem = [IO.Path]::GetFileNameWithoutExtension($f)
    $ph3Dir = Join-Path $rootDir ("phase3_worker_" + $stem)
    # Reconciled scores parquet
    Copy-Item (Join-Path $ph3Dir ($stem + '.scores.parquet')) (Join-Path $ph4Dir ($stem + '.scores.parquet'))
    # 1st-pass sidecar (--join-at-pass=2 may read it; harmless if not used)
    Copy-Item (Join-Path $ph3Dir ($stem + '.1st-pass.fdr_scores.bin')) (Join-Path $ph4Dir ($stem + '.1st-pass.fdr_scores.bin'))
    Copy-Item (Join-Path $ph3Dir ($stem + '.calibration.json')) (Join-Path $ph4Dir ($stem + '.calibration.json'))
    # 2nd-pass sidecar might exist (resume cache); copy if present
    $pass2 = Join-Path $ph3Dir ($stem + '.2nd-pass.fdr_scores.bin')
    if (Test-Path $pass2) {
        Copy-Item $pass2 (Join-Path $ph4Dir ($stem + '.2nd-pass.fdr_scores.bin'))
    }
    # stub mzML for path derivation
    New-Item -ItemType File -Path (Join-Path $ph4Dir ($stem + '.mzML')) -Force | Out-Null
}
Stage-DatasetFiles -Dir $ph4Dir -IncludeMzml:$false
Write-Host "[Phase 4] HPC 2nd-join merge (--join-at-pass=2) ..." -ForegroundColor Cyan
$args4 = @('--join-at-pass=2')
foreach ($f in $mzmls) {
    $stem = [IO.Path]::GetFileNameWithoutExtension($f)
    $args4 += @('--input-scores', ($stem + '.scores.parquet'))
}
$args4 += @('-l', $libraryName, '-o', 'output.blib',
            '--resolution', $resolution,
            '--protein-fdr', '0.01', '--threads', $Threads.ToString())
$env:OSPREY_DUMP_STAGE7_PROTEIN_FDR = '1'
try {
    $r4 = Invoke-Osprey -WorkDir $ph4Dir -CliArgs $args4
} finally {
    Remove-Item Env:OSPREY_DUMP_STAGE7_PROTEIN_FDR -ErrorAction SilentlyContinue
}

$chainBlib = Join-Path $ph4Dir 'output.blib'
$chainDump = Join-Path $ph4Dir 'rust_stage7_protein_fdr.tsv'
$chainPrecursors = Get-PrecursorCount -LogPath $r4.logPath
Write-Host ("  Phase 4 wall: {0}; precursors: {1}; blib: {2}" -f `
    (Format-Duration $r4.wall), $chainPrecursors, (Get-Item $chainBlib).Length) -ForegroundColor Green

# ----- COMPARE -----
Write-Host ""
Write-Host "=== Comparison: Phase 4 HPC chain vs Phase 0 straight-through truth ===" -ForegroundColor Cyan
Write-Host ("  precursors: truth={0}  chain={1}  delta={2}" -f `
    $truthPrecursors, $chainPrecursors, ($chainPrecursors - $truthPrecursors)) `
    -ForegroundColor $(if ($truthPrecursors -eq $chainPrecursors) { 'Green' } else { 'Red' })

$shaTd = (Get-FileHash $truthDump -Algorithm SHA256).Hash
$shaCd = (Get-FileHash $chainDump -Algorithm SHA256).Hash
$dumpMatch = ($shaTd -eq $shaCd)
Write-Host ("  Stage 7 protein FDR dump: truth=$($shaTd.Substring(0,16))  chain=$($shaCd.Substring(0,16))  {0}" -f `
    $(if ($dumpMatch) { 'IDENTICAL' } else { 'DIFFER' })) `
    -ForegroundColor $(if ($dumpMatch) { 'Green' } else { 'Red' })

# Run Compare-Blib-Crossimpl for full row+column blib content diff (1e-9 tolerance)
$blibCmp = Join-Path $scriptDir 'Compare-Blib-Crossimpl.ps1'
$blibLog = Join-Path $ph4Dir 'blib_compare.log'
Write-Host "  Running Compare-Blib-Crossimpl.ps1 ..." -ForegroundColor DarkGray
& pwsh -File $blibCmp -RustBlib $truthBlib -CsBlib $chainBlib *>&1 |
    Tee-Object -FilePath $blibLog | Out-Null
$blibExit = $LASTEXITCODE
$blibOk = ($blibExit -eq 0)
Write-Host ("  Blib content (SQL row+col 1e-9): {0}  (full log: {1})" -f `
    $(if ($blibOk) { 'PASS' } else { 'FAIL' }), $blibLog) `
    -ForegroundColor $(if ($blibOk) { 'Green' } else { 'Red' })

Write-Host ""
if ($truthPrecursors -eq $chainPrecursors -and $dumpMatch -and $blibOk) {
    Write-Host "OVERALL: PASS  -- HPC chain reproduces straight-through truth on $Dataset $($mzmls.Count)-file" -ForegroundColor Green
    exit 0
} else {
    Write-Host "OVERALL: FAIL -- HPC chain diverges from straight-through truth" -ForegroundColor Red
    Write-Host "  See per-phase logs under $rootDir for bisection." -ForegroundColor Yellow
    exit 1
}
