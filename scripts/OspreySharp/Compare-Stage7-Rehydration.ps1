<#
.SYNOPSIS
    Bit-parity test for `--join-at-pass=2` rehydration: confirm that
    rehydrating reconciled parquets at the Stage 7 entry produces the
    same Stage 7 protein-FDR dump as a straight-through pipeline run.

.DESCRIPTION
    Runs Rust osprey twice on the same Stellar dataset and compares the
    `OSPREY_DUMP_STAGE7_PROTEIN_FDR=1` output via SHA-256.

      RUN A (reference): `--join-at-pass=1 --input-scores <Stage 4>`
        Loads raw post-Stage-4 parquets, runs Stage 5 first-pass FDR,
        Stage 6 reconciliation, second-pass FDR, Stage 7 protein FDR,
        Stage 8 blib output. Writes `rust_stage7_protein_fdr.tsv` (the
        reference dump) and updates the input parquets in place to the
        post-Stage-6 reconciled form, with `.2nd-pass.fdr_scores.bin`
        sidecars next to each.

      RUN B (test): `--join-at-pass=2 --input-scores <reconciled>`
        Reads the reconciled parquets + 2nd-pass sidecars from RUN A's
        output, asserts via `validate_scores_cache` that every input is
        `ValidReconciled`, takes the `can_skip_fdr` path that skips
        Percolator + reconciliation, and runs only Stage 7 protein FDR
        + Stage 8 blib output. Writes its own
        `rust_stage7_protein_fdr.tsv` (the test dump).

    Pass: SHA-256(reference) == SHA-256(test).
    Fail: any divergence -- the Stage 6 reconciled parquet plus the
          2nd-pass score sidecar do NOT capture everything Stage 7 needs,
          and `--join-at-pass=2` is producing a different downstream
          result than the straight-through pipeline.

    This script is the Stage 7 analogue of `Compare-Stage6-Crossimpl.ps1`
    -- it gates the Rust-side rehydration wiring, decoupled from the
    OspreySharp port still in progress.

.PARAMETER Dataset
    Stellar (default; Astral support deferred until Astral Stage 7
    fixture is built).

.PARAMETER TestBaseDir
    Override test data root (defaults to OSPREY_TEST_BASE_DIR or
    D:\test\osprey-runs).

.PARAMETER Force
    Wipe any existing `_stage7_test/` working directory before running.

.EXAMPLE
    pwsh -File ./ai/scripts/OspreySharp/Compare-Stage7-Rehydration.ps1 -Dataset Stellar
#>

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("Stellar")]
    [string]$Dataset = "Stellar",

    [Parameter(Mandatory=$false)]
    [string]$TestBaseDir = $null,

    [switch]$Force = $false
)

$ErrorActionPreference = "Stop"

# Resolve repo + binary
$repoRoot   = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
. (Join-Path $PSScriptRoot "Dataset-Config.ps1")
$ds          = Get-DatasetConfig -Dataset $Dataset -TestBaseDir $TestBaseDir
$ospreyExe   = "C:/proj/osprey/target/release/osprey.exe"
if (-not (Test-Path $ospreyExe)) {
    throw "osprey.exe not found at $ospreyExe -- run Build-OspreyRust.ps1 first."
}

$libraryPath = Join-Path $ds.TestDir $ds.Library
if (-not (Test-Path $libraryPath)) {
    throw "Library not found: $libraryPath"
}

# Set up a clean working directory
$workRoot = Join-Path $ds.TestDir "_stage7_test"
if ($Force -and (Test-Path $workRoot)) {
    Remove-Item -Recurse -Force $workRoot
}
$runADir = Join-Path $workRoot "run_a"
$runBDir = Join-Path $workRoot "run_b"
New-Item -ItemType Directory -Force -Path $runADir | Out-Null
New-Item -ItemType Directory -Force -Path $runBDir | Out-Null

# Stage Stage 4 raw parquets in run_a with canonical naming
Write-Host "Staging Stage 4 raw parquets in $runADir ..." -ForegroundColor Cyan
foreach ($mzml in $ds.AllFiles) {
    $stem  = [IO.Path]::GetFileNameWithoutExtension($mzml)
    $src   = Join-Path $ds.TestDir "$stem.scores.rust.parquet"
    $dst   = Join-Path $runADir   "$stem.scores.parquet"
    if (-not (Test-Path $src)) {
        throw "Missing Stage 4 input: $src (run Generate-AllScoresParquet.ps1 first)"
    }
    Copy-Item $src $dst -Force
    # Synthetic mzML stub (never opened, but synthetic_input_from_parquet
    # expects a sibling .mzML to derive sidecar paths from)
    New-Item -ItemType File -Path (Join-Path $runADir "$stem.mzML") -Force | Out-Null
}

function Invoke-Osprey {
    param(
        [string]$WorkDir,
        [int]$JoinAtPass,
        [string]$Library,
        [string]$Resolution
    )
    $parquets = Get-ChildItem -Path $WorkDir -Filter "*.scores.parquet" |
                ForEach-Object { $_.FullName }
    $logPath  = Join-Path $WorkDir "osprey.log"
    $env:OSPREY_DUMP_STAGE7_PROTEIN_FDR = "1"
    Push-Location $WorkDir
    try {
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $argList = @(
            "--join-at-pass=$JoinAtPass",
            "--input-scores"
        ) + $parquets + @(
            "-l", $Library,
            "-o", "output.blib",
            "--resolution", $Resolution,
            "--protein-fdr", "0.01"
        )
        & $ospreyExe @argList 2>&1 | Tee-Object -FilePath $logPath
        $sw.Stop()
        if ($LASTEXITCODE -ne 0) {
            throw "osprey --join-at-pass=$JoinAtPass exited $LASTEXITCODE -- see $logPath"
        }
        Write-Host ("  osprey --join-at-pass=$JoinAtPass elapsed: {0}" `
            -f $sw.Elapsed.ToString('mm\:ss')) -ForegroundColor Green
    } finally {
        Pop-Location
        Remove-Item Env:OSPREY_DUMP_STAGE7_PROTEIN_FDR -ErrorAction SilentlyContinue
    }
}

Write-Host ""
Write-Host "RUN A (reference): --join-at-pass=1 from raw Stage 4 ..." -ForegroundColor Cyan
Invoke-Osprey -WorkDir $runADir -JoinAtPass 1 -Library $libraryPath -Resolution $ds.Resolution

$dumpA = Join-Path $runADir "rust_stage7_protein_fdr.tsv"
if (-not (Test-Path $dumpA)) {
    throw "RUN A produced no Stage 7 dump at $dumpA"
}
$shaA = (Get-FileHash $dumpA -Algorithm SHA256).Hash

# Copy run_a's reconciled output (parquets + sidecars + calibration) into run_b
Write-Host ""
Write-Host "Staging RUN A's reconciled output in $runBDir ..." -ForegroundColor Cyan
$candidateExts = @(
    ".scores.parquet",
    ".1st-pass.fdr_scores.bin",
    ".2nd-pass.fdr_scores.bin",
    ".calibration.json",
    ".reconciliation.json"
)
foreach ($mzml in $ds.AllFiles) {
    $stem = [IO.Path]::GetFileNameWithoutExtension($mzml)
    foreach ($ext in $candidateExts) {
        $src = Join-Path $runADir "$stem$ext"
        if (Test-Path $src) {
            Copy-Item $src (Join-Path $runBDir "$stem$ext") -Force
        }
    }
    # mzML stub
    New-Item -ItemType File -Path (Join-Path $runBDir "$stem.mzML") -Force | Out-Null
}

Write-Host ""
Write-Host "RUN B (test): --join-at-pass=2 from RUN A's reconciled parquets ..." -ForegroundColor Cyan
Invoke-Osprey -WorkDir $runBDir -JoinAtPass 2 -Library $libraryPath -Resolution $ds.Resolution

$dumpB = Join-Path $runBDir "rust_stage7_protein_fdr.tsv"
if (-not (Test-Path $dumpB)) {
    throw "RUN B produced no Stage 7 dump at $dumpB"
}
$shaB = (Get-FileHash $dumpB -Algorithm SHA256).Hash

Write-Host ""
Write-Host "--- Stage 7 dump SHA-256 ---" -ForegroundColor Yellow
Write-Host "  RUN A (reference, --join-at-pass=1): $shaA"
Write-Host "  RUN B (test,      --join-at-pass=2): $shaB"
if ($shaA -eq $shaB) {
    Write-Host ""
    Write-Host "PASS: Stage 7 dumps are byte-identical." -ForegroundColor Green
    exit 0
} else {
    Write-Host ""
    Write-Host "FAIL: Stage 7 dumps DIFFER. The reconciled parquet + 2nd-pass" -ForegroundColor Red
    Write-Host "      sidecar do NOT fully capture the Stage 6 boundary needed" -ForegroundColor Red
    Write-Host "      by Stage 7. Inspect with:" -ForegroundColor Red
    Write-Host "        diff $dumpA $dumpB | head -40"
    exit 1
}
