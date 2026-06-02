<#
.SYNOPSIS
    Stage-by-stage bit-parity bisection: C# straight-through (in-memory)
    pipeline vs C# 4-step HPC chain (with sidecar files + rehydration).

.DESCRIPTION
    C#-only mirror of Compare-Stage7-Rehydration-Strict.ps1 (Rust-only
    variant), but instead of only comparing the end-to-end output, this
    script gates at every stage boundary so any divergence is
    immediately localized to the stage at which it first appears. No
    re-hydration is exercised on the in-memory side; the HPC side
    re-hydrates through sidecars per phase, exactly as a multi-computer
    distribution would. If they agree at every boundary, C#'s in-memory
    and HPC-chain paths are internally consistent; if not, the failing
    boundary is the stage where the bug lives.

    Built in response to a Measure-Pipeline finding where C# in-memory
    produced ~1294 passing precursors on Astral all-files while Rust
    produced ~165K. Cross-impl HPC-chain Test-Regression passes at
    every stage on the same data, so the divergence must be between
    C# in-memory and C# HPC-chain.

    Pipeline shape:

      Phase 0 (TRUTH, in-memory):     OspreySharp -i mzML -l lib ...     -> writes ALL stage artifacts in one dir
      Phase 1 (HPC raw workers):      OspreySharp -i mzML ... --no-join  -> Stage 1-4 outputs
      Phase 2 (HPC 1st-join):         OspreySharp --join-at-pass=1 --join-only ...  -> Stage 5 sidecar pair
      Phase 3 (HPC rescore worker):   OspreySharp --join-at-pass=1 --no-join ...    -> Stage 6 reconciled parquet (per file)
      Phase 4 (HPC 2nd-join):         OspreySharp --join-at-pass=2 ...              -> Stage 7 + blib

    Stage boundaries compared (GATED in order; STOP on first FAIL):

      Stage 5 boundary -- truth vs ph2:
          *.1st-pass.fdr_scores.bin    (SHA-256 byte equality)
          *.reconciliation.json        (SHA-256 byte equality)
      Stage 6 boundary -- truth vs ph3:
          *.scores-reconciled.parquet  (parquet_diff.py --tolerance 0; bit-exact column-wise)
          *.scores.parquet original survived (Stage 6 no longer overwrites it)
      Stage 7 boundary -- truth vs ph4:
          cs_stage7_protein_fdr.tsv    (Compare-Stage7-Crossimpl.ps1 per-column 1e-9)
          output.blib                  (Compare-Blib-Crossimpl.ps1 SQL row+col 1e-9)
          precursor count from logs

    Stage 4 boundary is NOT gated: same code, deterministic, has been
    repeatedly confirmed identical between in-memory and worker mode.

.PARAMETER Dataset
    Stellar (default; Astral on demand once Stellar localizes the bug).

.PARAMETER TestBaseDir
    Override dataset root (defaults to $env:OSPREY_TEST_BASE_DIR or
    D:\test\osprey-runs).

.PARAMETER Force
    Wipe any existing strict-test working dirs before running.

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
$scriptDir = Split-Path -Parent $PSCommandPath          # .../Compare/archive
$compareDir = Split-Path -Parent $scriptDir             # .../Compare
$ospreyDir  = Split-Path -Parent $compareDir            # .../OspreySharp
. (Join-Path $ospreyDir 'Dataset-Config.ps1')

$projRoot = (Resolve-Path (Join-Path $ospreyDir '..\..\..')).Path
$ospreyShExe = Join-Path $projRoot 'pwiz\pwiz_tools\OspreySharp\OspreySharp\bin\x64\Release\net472\OspreySharp.exe'
if (-not (Test-Path $ospreyShExe)) {
    Write-Host "OspreySharp.exe not found at $ospreyShExe -- build first:" -ForegroundColor Red
    exit 2
}
$parquetDiffPy = Join-Path $scriptDir 'parquet_diff.py'
if (-not (Test-Path $parquetDiffPy)) {
    Write-Host "parquet_diff.py not found at $parquetDiffPy" -ForegroundColor Red
    exit 2
}
# Use the same Python we used earlier; Windows Store python3 alias doesn't work.
$pythonExe = 'C:\Program Files\Python312\python.exe'
if (-not (Test-Path $pythonExe)) {
    Write-Host "Python not found at $pythonExe (needed for parquet_diff.py)" -ForegroundColor Red
    exit 2
}

$ds = Get-DatasetConfig $Dataset -TestBaseDir $TestBaseDir
$mzmls = @($ds.AllFiles)
$libraryName = $ds.Library
$resolution = $ds.Resolution
$datasetRoot = $ds.TestDir

$rootDir   = Join-Path $datasetRoot "_strict_rehydration_csharp"
$truthDir  = Join-Path $rootDir "phase0_truth"
$ph1Dir    = Join-Path $rootDir "phase1_raw_workers"
$ph2Dir    = Join-Path $rootDir "phase2_first_join"
$ph4Dir    = Join-Path $rootDir "phase4_second_join"

if ($Force -and (Test-Path $rootDir)) {
    Write-Host "[Strict-CSharp] -Force: removing $rootDir" -ForegroundColor DarkYellow
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

function Invoke-OspreySharp {
    param([string]$WorkDir, [string[]]$CliArgs, [string]$LogName = 'ospreysharp.log')
    $logPath = Join-Path $WorkDir $LogName
    Push-Location $WorkDir
    try {
        $sw = [Diagnostics.Stopwatch]::StartNew()
        & $ospreyShExe @CliArgs 2>&1 | Tee-Object -FilePath $logPath | Out-Null
        $exit = $LASTEXITCODE
        $sw.Stop()
        if ($exit -ne 0) {
            Write-Host ("  OspreySharp exited {0}; see {1}" -f $exit, $logPath) -ForegroundColor Red
            throw "OspreySharp failed (exit=$exit). See $logPath."
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

function Format-Duration { param([TimeSpan]$T) ('{0:mm\:ss}' -f $T) }

function Compare-FileSha {
    param([string]$A, [string]$B, [string]$Label)
    if (-not (Test-Path $A)) { Write-Host "  [$Label] MISSING truth: $A" -ForegroundColor Red; return $false }
    if (-not (Test-Path $B)) { Write-Host "  [$Label] MISSING chain: $B" -ForegroundColor Red; return $false }
    $sa = (Get-FileHash $A -Algorithm SHA256).Hash
    $sb = (Get-FileHash $B -Algorithm SHA256).Hash
    $ok = ($sa -eq $sb)
    $aLen = (Get-Item $A).Length; $bLen = (Get-Item $B).Length
    Write-Host ("    {0}  {1}  truth={2}/{3}b  chain={4}/{5}b" -f `
        $(if ($ok) { 'PASS' } else { 'FAIL' }), $Label,
        $sa.Substring(0,12), $aLen, $sb.Substring(0,12), $bLen) `
        -ForegroundColor $(if ($ok) { 'Green' } else { 'Red' })
    return $ok
}

function Compare-ReconciledParquet {
    param([string]$A, [string]$B, [string]$Label)
    if (-not (Test-Path $A)) { Write-Host "  [$Label] MISSING truth: $A" -ForegroundColor Red; return $false }
    if (-not (Test-Path $B)) { Write-Host "  [$Label] MISSING chain: $B" -ForegroundColor Red; return $false }
    # Try SHA first (cheap, definitive).
    $sa = (Get-FileHash $A -Algorithm SHA256).Hash
    $sb = (Get-FileHash $B -Algorithm SHA256).Hash
    if ($sa -eq $sb) {
        Write-Host ("    PASS  {0}  SHA identical ({1})" -f $Label, $sa.Substring(0,12)) -ForegroundColor Green
        return $true
    }
    # SHA differs -- fall back to column-wise bit-exact via parquet_diff.py.
    # (Parquet metadata or codec block boundaries can differ even with
    # identical row data, so SHA mismatch isn't always a real divergence.)
    $diffLog = "$B.diff_vs_truth.log"
    & $pythonExe $parquetDiffPy $A $B --tolerance 0 *>&1 | Tee-Object -FilePath $diffLog | Out-Null
    $exit = $LASTEXITCODE
    $ok = ($exit -eq 0)
    Write-Host ("    {0}  {1}  SHA differs; parquet_diff --tolerance 0: {2}  ({3})" -f `
        $(if ($ok) { 'PASS' } else { 'FAIL' }), $Label,
        $(if ($ok) { 'columns bit-identical' } else { 'columns differ -- see log' }), $diffLog) `
        -ForegroundColor $(if ($ok) { 'Green' } else { 'Red' })
    return $ok
}

Write-Host ""
Write-Host "=== Compare-Stage7-Rehydration-Strict-CSharp (stage-by-stage bisection) ===" -ForegroundColor Cyan
Write-Host ("Dataset: {0} ({1} files)" -f $Dataset, $mzmls.Count)
Write-Host ("Workdir: {0}" -f $rootDir)
Write-Host ""

# ----- PHASE 0: TRUTH (straight-through in-memory C# pipeline) -----
$truthBlib = Join-Path $truthDir 'output.blib'
$truthDump = Join-Path $truthDir 'cs_stage7_protein_fdr.tsv'

if (Test-Path $truthDir) { Remove-Item $truthDir -Recurse -Force }
New-Item -ItemType Directory -Path $truthDir -Force | Out-Null
Stage-DatasetFiles -Dir $truthDir
Write-Host "[Phase 0] TRUTH (-i mzML, in-memory straight-through) ..." -ForegroundColor Cyan
$args0 = @()
foreach ($f in $mzmls) { $args0 += @('-i', $f) }
$args0 += @('-l', $libraryName, '-o', 'output.blib',
            '--resolution', $resolution,
            '--protein-fdr', '0.01', '--threads', $Threads.ToString())
$env:OSPREY_DUMP_STAGE7_PROTEIN_FDR = '1'
try {
    $r0 = Invoke-OspreySharp -WorkDir $truthDir -CliArgs $args0
} finally {
    Remove-Item Env:OSPREY_DUMP_STAGE7_PROTEIN_FDR -ErrorAction SilentlyContinue
}
$truthPrecursors = Get-PrecursorCount -LogPath $r0.logPath
Write-Host ("  Phase 0 wall: {0}; precursors: {1}; blib: {2}" -f `
    (Format-Duration $r0.wall), $truthPrecursors, (Get-Item $truthBlib).Length) -ForegroundColor Green

# ----- PHASE 1: per-file raw workers (Stage 1-4 only) -----
if (Test-Path $ph1Dir) { Remove-Item $ph1Dir -Recurse -Force }
New-Item -ItemType Directory -Path $ph1Dir -Force | Out-Null
Stage-DatasetFiles -Dir $ph1Dir
Write-Host "[Phase 1] HPC raw workers (--no-join, Stage 1-4) ..." -ForegroundColor Cyan
$args1 = @()
foreach ($f in $mzmls) { $args1 += @('-i', $f) }
$args1 += @('-l', $libraryName, '-o', 'output.blib',
            '--resolution', $resolution,
            '--protein-fdr', '0.01', '--threads', $Threads.ToString(),
            '--no-join')
$r1 = Invoke-OspreySharp -WorkDir $ph1Dir -CliArgs $args1
Write-Host ("  Phase 1 wall: {0}" -f (Format-Duration $r1.wall)) -ForegroundColor Green
# Stage 4 boundary not gated -- known deterministic; user-confirmed.

# ----- PHASE 2: HPC 1st-join merge (Stage 5) -----
if (Test-Path $ph2Dir) { Remove-Item $ph2Dir -Recurse -Force }
New-Item -ItemType Directory -Path $ph2Dir -Force | Out-Null
foreach ($f in $mzmls) {
    $stem = [IO.Path]::GetFileNameWithoutExtension($f)
    Copy-Item (Join-Path $ph1Dir ($stem + '.scores.parquet'))  (Join-Path $ph2Dir ($stem + '.scores.parquet'))
    Copy-Item (Join-Path $ph1Dir ($stem + '.calibration.json'))(Join-Path $ph2Dir ($stem + '.calibration.json'))
    New-Item -ItemType File -Path (Join-Path $ph2Dir ($stem + '.mzML')) -Force | Out-Null
}
Stage-DatasetFiles -Dir $ph2Dir -IncludeMzml:$false
Write-Host "[Phase 2] HPC 1st-join merge (--join-at-pass=1 --join-only, Stage 5) ..." -ForegroundColor Cyan
$args2 = @('--join-at-pass=1', '--join-only')
foreach ($f in $mzmls) {
    $stem = [IO.Path]::GetFileNameWithoutExtension($f)
    $args2 += @('--input-scores', ($stem + '.scores.parquet'))
}
$args2 += @('-l', $libraryName, '-o', 'output.blib',
            '--resolution', $resolution,
            '--protein-fdr', '0.01', '--threads', $Threads.ToString())
$r2 = Invoke-OspreySharp -WorkDir $ph2Dir -CliArgs $args2
Write-Host ("  Phase 2 wall: {0}" -f (Format-Duration $r2.wall)) -ForegroundColor Green

# ----- GATE: Stage 5 boundary (truth vs ph2) -----
Write-Host ""
Write-Host "=== Stage 5 boundary check (in-memory vs HPC ph2) ===" -ForegroundColor Cyan
$stage5Ok = $true
foreach ($f in $mzmls) {
    $stem = [IO.Path]::GetFileNameWithoutExtension($f)
    $stage5Ok = (Compare-FileSha `
        (Join-Path $truthDir ($stem + '.1st-pass.fdr_scores.bin')) `
        (Join-Path $ph2Dir   ($stem + '.1st-pass.fdr_scores.bin')) `
        ("$stem .1st-pass.fdr_scores.bin")) -and $stage5Ok
    $stage5Ok = (Compare-FileSha `
        (Join-Path $truthDir ($stem + '.reconciliation.json')) `
        (Join-Path $ph2Dir   ($stem + '.reconciliation.json')) `
        ("$stem .reconciliation.json")) -and $stage5Ok
}
if (-not $stage5Ok) {
    Write-Host ""
    Write-Host "STOP: Stage 5 boundary FAIL -- bisection localized to Stage 5 (or earlier). Skipping Stages 6/7." -ForegroundColor Red
    exit 1
}
Write-Host "Stage 5 boundary: PASS" -ForegroundColor Green

# ----- PHASE 3: per-file rescore workers (Stage 6) -----
Write-Host ""
Write-Host "[Phase 3] HPC rescore workers (--join-at-pass=1 --no-join, Stage 6, per-file) ..." -ForegroundColor Cyan
$ph3Roots = @()
$ph3Total = [TimeSpan]::Zero
foreach ($f in $mzmls) {
    $stem = [IO.Path]::GetFileNameWithoutExtension($f)
    $ph3Dir = Join-Path $rootDir ("phase3_worker_" + $stem)
    $ph3Roots += $ph3Dir
    if (Test-Path $ph3Dir) { Remove-Item $ph3Dir -Recurse -Force }
    New-Item -ItemType Directory -Path $ph3Dir -Force | Out-Null
    Copy-Item (Join-Path $datasetRoot $f) (Join-Path $ph3Dir $f)
    Copy-Item (Join-Path $ph1Dir ($stem + '.scores.parquet')) (Join-Path $ph3Dir ($stem + '.scores.parquet'))
    Copy-Item (Join-Path $ph1Dir ($stem + '.calibration.json')) (Join-Path $ph3Dir ($stem + '.calibration.json'))
    Copy-Item (Join-Path $ph2Dir ($stem + '.1st-pass.fdr_scores.bin')) (Join-Path $ph3Dir ($stem + '.1st-pass.fdr_scores.bin'))
    Copy-Item (Join-Path $ph2Dir ($stem + '.reconciliation.json')) (Join-Path $ph3Dir ($stem + '.reconciliation.json'))
    Stage-DatasetFiles -Dir $ph3Dir -IncludeMzml:$false
    Write-Host ("  -- worker for {0} ..." -f $stem) -ForegroundColor DarkCyan
    $args3 = @('--join-at-pass=1', '--no-join',
               '--input-scores', ($stem + '.scores.parquet'),
               '-l', $libraryName, '-o', 'output.blib',
               '--resolution', $resolution,
               '--protein-fdr', '0.01', '--threads', $Threads.ToString())
    $r3 = Invoke-OspreySharp -WorkDir $ph3Dir -CliArgs $args3
    $ph3Total += $r3.wall
}
Write-Host ("  Phase 3 total wall (serial): {0}" -f (Format-Duration $ph3Total)) -ForegroundColor Green

# ----- GATE: Stage 6 boundary (truth vs ph3 reconciled parquets) -----
Write-Host ""
Write-Host "=== Stage 6 boundary check (in-memory vs HPC ph3 reconciled parquets) ===" -ForegroundColor Cyan
$stage6Ok = $true
foreach ($f in $mzmls) {
    $stem = [IO.Path]::GetFileNameWithoutExtension($f)
    $ph3Dir = Join-Path $rootDir ("phase3_worker_" + $stem)
    # Stage 6 now writes a SEPARATE <stem>.scores-reconciled.parquet
    # (it no longer overwrites the Stage 4 <stem>.scores.parquet).
    $stage6Ok = (Compare-ReconciledParquet `
        (Join-Path $truthDir ($stem + '.scores-reconciled.parquet')) `
        (Join-Path $ph3Dir   ($stem + '.scores-reconciled.parquet')) `
        ("$stem .scores-reconciled.parquet")) -and $stage6Ok
    # Original-survival: the Stage 4 <stem>.scores.parquet must still
    # exist intact (proves the overwrite is gone). Both the in-memory
    # truth and the HPC worker must have left it in place.
    foreach ($d in @($truthDir, $ph3Dir)) {
        $orig = Join-Path $d ($stem + '.scores.parquet')
        if (-not (Test-Path $orig)) {
            Write-Host ("    {0}  MISSING original Stage 4 parquet in {1} (overwrite regression?)" -f $stem, $d) -ForegroundColor Red
            $stage6Ok = $false
        }
    }
}
if (-not $stage6Ok) {
    Write-Host ""
    Write-Host "STOP: Stage 6 boundary FAIL -- bisection localized to Stage 6. Skipping Stage 7." -ForegroundColor Red
    exit 1
}
Write-Host "Stage 6 boundary: PASS" -ForegroundColor Green

# ----- PHASE 4: 2nd-join merge node (Stage 7) -----
if (Test-Path $ph4Dir) { Remove-Item $ph4Dir -Recurse -Force }
New-Item -ItemType Directory -Path $ph4Dir -Force | Out-Null
foreach ($f in $mzmls) {
    $stem = [IO.Path]::GetFileNameWithoutExtension($f)
    $ph3Dir = Join-Path $rootDir ("phase3_worker_" + $stem)
    # The merge node consumes the RECONCILED parquet (Stage 6 output),
    # not the original Stage 4 parquet. --join-at-pass=2 also requires
    # osprey.reconciled="true", which only the reconciled file carries.
    Copy-Item (Join-Path $ph3Dir ($stem + '.scores-reconciled.parquet')) (Join-Path $ph4Dir ($stem + '.scores-reconciled.parquet'))
    Copy-Item (Join-Path $ph3Dir ($stem + '.1st-pass.fdr_scores.bin')) (Join-Path $ph4Dir ($stem + '.1st-pass.fdr_scores.bin'))
    Copy-Item (Join-Path $ph3Dir ($stem + '.calibration.json')) (Join-Path $ph4Dir ($stem + '.calibration.json'))
    Copy-Item (Join-Path $ph3Dir ($stem + '.reconciliation.json')) (Join-Path $ph4Dir ($stem + '.reconciliation.json'))
    $pass2 = Join-Path $ph3Dir ($stem + '.2nd-pass.fdr_scores.bin')
    if (Test-Path $pass2) { Copy-Item $pass2 (Join-Path $ph4Dir ($stem + '.2nd-pass.fdr_scores.bin')) }
    # Stub mzML for path derivation only (mirrors the Rust strict-
    # rehydration script). The merge node MUST NOT read spectra at
    # --join-at-pass=2 because in production HPC the merge node ships
    # only sidecars + reconciled parquets, never mzMLs. If the merge
    # binary tries to open this 0-byte file, that's a bug to fix in the
    # binary, not the test.
    New-Item -ItemType File -Path (Join-Path $ph4Dir ($stem + '.mzML')) -Force | Out-Null
}
Stage-DatasetFiles -Dir $ph4Dir -IncludeMzml:$false
Write-Host ""
Write-Host "[Phase 4] HPC 2nd-join merge (--join-at-pass=2, Stage 7) ..." -ForegroundColor Cyan
$args4 = @('--join-at-pass=2')
foreach ($f in $mzmls) {
    $stem = [IO.Path]::GetFileNameWithoutExtension($f)
    $args4 += @('--input-scores', ($stem + '.scores-reconciled.parquet'))
}
$args4 += @('-l', $libraryName, '-o', 'output.blib',
            '--resolution', $resolution,
            '--protein-fdr', '0.01', '--threads', $Threads.ToString())
$env:OSPREY_DUMP_STAGE7_PROTEIN_FDR = '1'
try {
    $r4 = Invoke-OspreySharp -WorkDir $ph4Dir -CliArgs $args4
} finally {
    Remove-Item Env:OSPREY_DUMP_STAGE7_PROTEIN_FDR -ErrorAction SilentlyContinue
}
$chainBlib = Join-Path $ph4Dir 'output.blib'
$chainDump = Join-Path $ph4Dir 'cs_stage7_protein_fdr.tsv'
$chainPrecursors = Get-PrecursorCount -LogPath $r4.logPath
Write-Host ("  Phase 4 wall: {0}; precursors: {1}; blib: {2}" -f `
    (Format-Duration $r4.wall), $chainPrecursors, (Get-Item $chainBlib).Length) -ForegroundColor Green

# ----- GATE: Stage 7 boundary (truth vs ph4) -----
Write-Host ""
Write-Host "=== Stage 7 boundary check (in-memory vs HPC ph4) ===" -ForegroundColor Cyan
$precursorOk = ($truthPrecursors -eq $chainPrecursors)
Write-Host ("    {0}  precursors: truth={1}  chain={2}  delta={3}" -f `
    $(if ($precursorOk) { 'PASS' } else { 'FAIL' }),
    $truthPrecursors, $chainPrecursors, ($chainPrecursors - $truthPrecursors)) `
    -ForegroundColor $(if ($precursorOk) { 'Green' } else { 'Red' })

$stage7Cmp = Join-Path $compareDir 'Compare-Stage7-Crossimpl.ps1'
$stage7Log = Join-Path $ph4Dir 'stage7_compare.log'
& pwsh -File $stage7Cmp -RustTsv $truthDump -CsTsv $chainDump *>&1 |
    Tee-Object -FilePath $stage7Log | Out-Null
$stage7DumpOk = ($LASTEXITCODE -eq 0)
Write-Host ("    {0}  Stage 7 protein FDR dump (per-col 1e-9; full log: {1})" -f `
    $(if ($stage7DumpOk) { 'PASS' } else { 'FAIL' }), $stage7Log) `
    -ForegroundColor $(if ($stage7DumpOk) { 'Green' } else { 'Red' })

$blibCmp = Join-Path $compareDir 'Compare-Blib-Crossimpl.ps1'
$blibLog = Join-Path $ph4Dir 'blib_compare.log'
& pwsh -File $blibCmp -RustBlib $truthBlib -CsBlib $chainBlib *>&1 |
    Tee-Object -FilePath $blibLog | Out-Null
$blibOk = ($LASTEXITCODE -eq 0)
Write-Host ("    {0}  Blib content (SQL row+col 1e-9; full log: {1})" -f `
    $(if ($blibOk) { 'PASS' } else { 'FAIL' }), $blibLog) `
    -ForegroundColor $(if ($blibOk) { 'Green' } else { 'Red' })

$stage7Ok = $precursorOk -and $stage7DumpOk -and $blibOk

Write-Host ""
if ($stage7Ok) {
    Write-Host "OVERALL: PASS  -- C# in-memory and C# HPC chain are bit-parity on $Dataset $($mzmls.Count)-file at every gated stage boundary" -ForegroundColor Green
    exit 0
} else {
    Write-Host "Stage 7 boundary: FAIL  -- divergence localized to Stage 7 (Stages 5+6 matched)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Most likely candidate: PerFileScoringTask bundle-hydration nulls Features (line ~710)," -ForegroundColor Yellow
    Write-Host "MergeNodeTask Bug C reloads them from parquet -- in the in-memory path Features are" -ForegroundColor Yellow
    Write-Host "not nulled, the reload overwrites valid in-memory Features with parquet Features, and" -ForegroundColor Yellow
    Write-Host "ParquetIndex may not align cleanly after Stage 6's WriteReconciledParquet." -ForegroundColor Yellow
    exit 1
}
