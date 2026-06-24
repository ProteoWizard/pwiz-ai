<#
.SYNOPSIS
    Generate the STABLE Rust cross-impl reference set that the occasional
    cross-impl gate (Compare-CrossImpl-Reference.ps1) compares OspreySharp
    against -- without needing a live Rust build at gate time.

.DESCRIPTION
    Rust osprey is archived/frozen (its implementation has not changed since
    the parity high-water mark a56498ca78; the only later commits are CLI /
    license, non-algorithmic). So a one-time capture of its per-stage outputs
    is a durable reference.

    Two passes per the "freeze the Stage-4 parquet, then run through" approach
    (Stage 4 is per-file deterministic and rehydrate-from-parquet == straight-
    through, so the Stage-4 parquet is a safe freeze point):

      Pass 1  osprey ... --no-join          -> <stem>.scores.parquet IS the
                                               Stage-4 output (no Stage-6 overwrite).
                                               Copied to <stem>.scores.stage4.parquet.
      Pass 2  osprey ... (straight-through) -> <stem>.scores.parquet is overwritten
                                               in place with the RECONCILED set, plus
                                               reconciliation.json, the 1st/2nd-pass
                                               fdr_scores.bin sidecars, the Stage 7
                                               protein-FDR dump, and output.blib.

    Note the deliberate OspreySharp divergence (commit #4261): OspreySharp does
    NOT overwrite scores.parquet at Stage 6 -- it writes a separate
    .scores-reconciled.parquet. Rust still overwrites in place. So the gate maps
    OspreySharp's Stage-4 scores.parquet to THIS set's .scores.stage4.parquet
    (like stage to like stage), not to the reconciled .scores.parquet.

.PARAMETER Dataset      Stellar (default) or Astral.
.PARAMETER TestBaseDir  Override dataset root (defaults to OSPREY_TEST_BASE_DIR).
.PARAMETER Force        Wipe an existing reference set before regenerating.
.PARAMETER Threads      --threads (default 16).
#>
param(
    [ValidateSet('Stellar','Astral')]
    [string]$Dataset = 'Stellar',
    [string]$TestBaseDir,
    [switch]$Force,
    [int]$Threads = 16
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $PSCommandPath
foreach ($c in @((Join-Path $scriptDir 'Dataset-Config.ps1'),
                 (Join-Path $scriptDir '..\Dataset-Config.ps1'))) {
    if (Test-Path $c) { . $c; break }
}

$ospreyExe = Get-OspreyExe
if (-not (Test-Path $ospreyExe)) {
    Write-Host "osprey.exe not found at $ospreyExe -- build Rust first (Build-OspreyRust.ps1)." -ForegroundColor Red
    exit 2
}

$ds          = Get-DatasetConfig $Dataset -TestBaseDir $TestBaseDir
$mzmls       = @($ds.AllFiles)
$libraryName = $ds.Library
$resolution  = $ds.Resolution
$datasetRoot = $ds.TestDir
$stems       = @($mzmls | ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_) })

$refRoot = Join-Path $datasetRoot ("_crossimpl_reference\" + $Dataset.ToLower())
$refDir  = Join-Path $refRoot 'rust'
$workDir = Join-Path $refRoot '_work'

if ($Force -and (Test-Path $refRoot)) {
    Write-Host "[Ref] -Force: removing $refRoot" -ForegroundColor DarkYellow
    Remove-Item $refRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $refDir  -Force | Out-Null
New-Item -ItemType Directory -Path $workDir -Force | Out-Null

function Stage-Inputs {
    foreach ($f in $mzmls) { Copy-Item (Join-Path $datasetRoot $f) (Join-Path $workDir $f) -Force }
    Copy-Item (Join-Path $datasetRoot $libraryName) (Join-Path $workDir $libraryName) -Force
    $cache = Join-Path $datasetRoot ($libraryName + '.libcache')
    if (Test-Path $cache) { Copy-Item $cache (Join-Path $workDir ($libraryName + '.libcache')) -Force }
}

function Run-Rust {
    param([string[]]$Extra, [string]$LogName)
    $cliArgs = @()
    foreach ($f in $mzmls) { $cliArgs += @('-i', $f) }
    $cliArgs += @('-l', $libraryName, '-o', 'output.blib',
                  '--resolution', $resolution, '--protein-fdr', '0.01',
                  '--threads', $Threads.ToString()) + $Extra
    Push-Location $workDir
    try {
        $env:OSPREY_DUMP_STAGE7_PROTEIN_FDR = '1'
        & $ospreyExe @cliArgs 2>&1 | Tee-Object -FilePath (Join-Path $workDir $LogName) | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Rust exited $LASTEXITCODE; see $LogName" }
    } finally {
        Remove-Item Env:OSPREY_DUMP_STAGE7_PROTEIN_FDR -ErrorAction SilentlyContinue
        Pop-Location
    }
}

Write-Host "=== Build-CrossImplReference ($Dataset, $($mzmls.Count) files) ===" -ForegroundColor Cyan
Write-Host ("Reference dir: {0}" -f $refDir)

# Pass 1: Stage-4 capture (--no-join leaves scores.parquet as the Stage-4 output).
Write-Host "[Pass 1] Rust --no-join (capture Stage-4 scores.parquet) ..." -ForegroundColor Cyan
Stage-Inputs
Run-Rust -Extra @('--no-join') -LogName 'osprey.nojoin.log'
foreach ($stem in $stems) {
    Copy-Item (Join-Path $workDir ($stem + '.scores.parquet')) `
              (Join-Path $refDir ($stem + '.scores.stage4.parquet')) -Force
}
Copy-Item (Join-Path $workDir 'osprey.nojoin.log') (Join-Path $refDir 'osprey.nojoin.log') -Force

# Pass 2: straight-through (reconciled scores.parquet + downstream side-cars + blib).
Write-Host "[Pass 2] Rust straight-through (reconciled + side-cars + blib) ..." -ForegroundColor Cyan
Stage-Inputs
Run-Rust -Extra @() -LogName 'osprey.log'
$capture = @('output.blib', 'rust_stage7_protein_fdr.tsv', 'osprey.log')
foreach ($stem in $stems) {
    $capture += @(($stem + '.scores.parquet'),
                  ($stem + '.reconciliation.json'),
                  ($stem + '.1st-pass.fdr_scores.bin'),
                  ($stem + '.2nd-pass.fdr_scores.bin'))
}
foreach ($f in $capture) {
    $src = Join-Path $workDir $f
    if (Test-Path $src) { Copy-Item $src (Join-Path $refDir $f) -Force }
    else { Write-Host "  WARN: expected reference artifact missing: $f" -ForegroundColor Yellow }
}

Remove-Item $workDir -Recurse -Force -ErrorAction SilentlyContinue

# Provenance for the README.
$rustCommit  = (git -C (Join-Path $scriptDir '..\..\..\osprey') rev-parse HEAD 2>$null)
$rustShort   = (git -C (Join-Path $scriptDir '..\..\..\osprey') rev-parse --short HEAD 2>$null)
$rustSubject = (git -C (Join-Path $scriptDir '..\..\..\osprey') log -1 --format='%s' 2>$null)
$genDate     = (Get-Date -Format 'yyyy-MM-dd HH:mm K')

$readme = @"
# OspreySharp cross-impl reference set -- $Dataset

Frozen Rust ``osprey`` outputs that the occasional cross-impl gate
(``Compare-CrossImpl-Reference.ps1``) compares OspreySharp against, so the gate
needs no live Rust build. Rust is archived/frozen, so this set is stable.

## Provenance
- Rust osprey commit: ``$rustShort`` ($rustCommit)
  - $rustSubject
- Dataset: $Dataset ($($mzmls.Count) files); resolution ``$resolution``; library ``$libraryName``
- Generated: $genDate by ``Build-CrossImplReference.ps1``

## How it was created
Two passes (Stage 4 is per-file deterministic; rehydrate-from-parquet ==
straight-through, so the Stage-4 parquet is a safe freeze point):

1. ``osprey -i <mzMLs> -l <lib> -o output.blib --resolution $resolution --protein-fdr 0.01 --no-join``
   -> each ``<stem>.scores.parquet`` is the **Stage-4** output (no Stage-6
   overwrite). Captured here as ``<stem>.scores.stage4.parquet``.
2. ``osprey ... `` (straight-through, ``OSPREY_DUMP_STAGE7_PROTEIN_FDR=1``)
   -> ``<stem>.scores.parquet`` overwritten in place with the **reconciled**
   set, plus the side-cars and blib below.

## Files
| File | Stage | What |
|------|-------|------|
| ``<stem>.scores.stage4.parquet`` | 4 | per-file scored+deduped candidates (pre-reconciliation) |
| ``<stem>.scores.parquet`` | 6 | reconciled set (Rust overwrites in place) |
| ``<stem>.reconciliation.json`` | 5/6 | reconciliation envelope (rescore-worker side-car) |
| ``<stem>.1st-pass.fdr_scores.bin`` | 5 | first-pass FDR sidecar |
| ``<stem>.2nd-pass.fdr_scores.bin`` | 6 | second-pass FDR sidecar |
| ``rust_stage7_protein_fdr.tsv`` | 7 | protein-FDR dump |
| ``output.blib`` | 9 | final library |

## Gate mapping / parity levels (see Compare-CrossImpl-Reference.ps1)
- OspreySharp Stage-4 ``scores.parquet`` -> this set's ``.scores.stage4.parquet`` (parquet 1e-9). Like stage to like stage: OspreySharp does NOT overwrite scores.parquet at Stage 6 (commit #4261); Rust does.
- ``reconciliation.json`` -> byte/value parity (achieved byte-identical at a56498ca78).
- ``1st/2nd-pass.fdr_scores.bin`` -> value-level (cross-impl ULP; bit-exact given identical input).
- ``rust_stage7_protein_fdr.tsv`` -> per-column 1e-9.
- ``output.blib`` -> SQL row+col 1e-9 (``osprey_version`` whitelisted -- OspreySharp is on the Skyline version scheme intentionally).
- ``calibration.json`` is NOT gated: a Stage-3 bisection-debugging artifact whose VALUES are bit-exact but whose file carries a run timestamp + Rust-only diagnostic keys, so byte-equality was never achievable or required.

## Notes
- Not committed to the repo (large) and not yet on PanoramaWeb; regenerate
  locally with ``Build-CrossImplReference.ps1 -Force`` (needs a built Rust osprey).
- Someday: upload alongside the raw data to PanoramaWeb for any-machine use.
"@
Set-Content -Path (Join-Path $refRoot 'README.md') -Value $readme

Write-Host ""
Write-Host "Reference set written to $refDir" -ForegroundColor Green
Write-Host ("README: {0}" -f (Join-Path $refRoot 'README.md')) -ForegroundColor Green
Get-ChildItem $refDir | ForEach-Object { "  {0,12:n0}  {1}" -f $_.Length, $_.Name }
