<#
.SYNOPSIS
    OspreySharp cross-impl pipeline regression test. Asserts that
    Rust osprey and OspreySharp produce the same output at every
    pipeline stage on a chosen file or set of files. Pass/fail with
    structured per-stage diagnostics for quick localization of any
    regression.

.DESCRIPTION
    A regression test, not an audit script. Companion to Test-Features.ps1
    (which compares the 21 Stage 1-4 PIN features for a single file):
    Test-Regression.ps1 covers the **whole pipeline** end-to-end and
    every per-stage cross-impl gate the project relies on.

    Stage walk: stage1to4 -> stage5 -> stage6 -> stage7 -> blib.
    Per stage:
      1. Prepare inputs (from previous stage's frozen output, or from
         dataset for stage1to4).
      2. Run requested side(s) with the appropriate CLI + early-exit
         env var so each stage emits only its dumps and stops.
      3. Compare outputs (per-stage comparator below).
      4. PASS  -> freeze stage's outputs as inputs for next stage.
      5. FAIL  -> stop (or continue under -Continue) and print the
         exact follow-up command for tight cycle iteration on the
         failing stage.

    Exit code: 0 if every requested stage PASSes; 1 on any FAIL.
    Suitable as a CI gate or as a developer's local regression check
    before commit.

    Stage isolation matrix:

      Stage      CLI extras                                         Exit hook
      ---------  -------------------------------------------------  -----------------------------
      stage1to4  --no-join                                          (--no-join exits after Stage 4)
      stage5     --join-at-pass=1 --input-scores <frozen.parquet>   OSPREY_PERCOLATOR_ONLY=1
      stage6     --join-at-pass=1 --input-scores <frozen.parquet>   OSPREY_RESCORED_ONLY=1
      stage7     --join-at-pass=1 --input-scores <frozen.parquet>   OSPREY_STAGE7_PROTEIN_FDR_ONLY=1
      blib       --join-at-pass=1 --input-scores <frozen.parquet>   (none — full pipeline)

    Stage-input policy: After stage1to4, downstream stages are run
    with shared input (Rust's frozen .scores.parquet) so each
    downstream stage tests its own logic, not propagated upstream
    drift. This is the right shape for regression iteration: the
    moment you change Stage N's code, you can re-run only Stage N
    against the existing frozen inputs without paying for upstream.

    Comparators:

      stage1to4  inspect_parquet.py --diff   (per-column with row alignment)
      stage5     SHA-256 byte equality on standardizer/subsample/svm_weights/percolator
      stage6     SHA-256 byte equality on rescored dump + reconciliation.json action counts
      stage7     Compare-Stage7-Crossimpl.ps1 (existing per-column tolerance)
      blib       Compare-Blib-Crossimpl.ps1  (existing per-table tolerance)

.PARAMETER Dataset
    Stellar | Astral. Default Stellar.

.PARAMETER Files
    'Single' (default — first file in dataset; useful when most things are
    broken), 'All' (all dataset files), or a comma-separated list of
    file stems (e.g. "Ste-..._20,Ste-..._21").

.PARAMETER StartStage
    Where to start the march. Default 'stage1to4'. Use 'stage5' etc.
    to skip earlier stages. Requires the previous stage's frozen
    inputs to exist in the workdir (run a full march at least once
    first, or use -Force to refresh).

.PARAMETER StopAfterStage
    Last stage to run. Default 'blib'.

.PARAMETER Side
    'both' (default), 'rust', or 'cs'. Use -Side cs after editing C#
    to skip rust re-runs (saves ~80s of library loading per file).

.PARAMETER Continue
    Don't stop on first FAIL. Run all requested stages. Useful for a
    full-picture regression sweep where you want to see how broken
    everything is.

.PARAMETER Force
    Discard existing frozen inputs and re-run from StartStage.

.PARAMETER Tag
    Workdir suffix. Default: 'main' (a single shared workdir per dataset
    so iterations accumulate). Pass an explicit tag to run an
    isolated experiment.

.PARAMETER TestBaseDir
    Override dataset root.

.OUTPUTS
    Exit code: 0 = all requested stages PASS; 1 = at least one FAIL;
    2 = setup error.

.EXAMPLE
    # First run: end-to-end march on a single Stellar file. Will stop at
    # whatever's first broken and leave the workdir ready for tight
    # iteration on that stage.
    pwsh -File ./Test-Regression.ps1

.EXAMPLE
    # After editing C# code: re-run only the broken stage on the cs
    # side, reusing the rust outputs and frozen inputs from the previous
    # run. ~30-60s cycle.
    pwsh -File ./Test-Regression.ps1 -StartStage stage5 -StopAfterStage stage5 -Side cs

.EXAMPLE
    # All Stellar files, full march, don't stop on first fail.
    pwsh -File ./Test-Regression.ps1 -Files All -Continue
#>

[CmdletBinding()]
param(
    [ValidateSet('Stellar','Astral')]
    [string]$Dataset = 'Stellar',

    [string]$Files = 'Single',

    [ValidateSet('stage1to4','stage5','stage6','stage7','blib')]
    [string]$StartStage = 'stage1to4',

    [ValidateSet('stage1to4','stage5','stage6','stage7','blib')]
    [string]$StopAfterStage = 'blib',

    [ValidateSet('both','rust','cs')]
    [string]$Side = 'both',

    [switch]$Continue,
    [switch]$Force,

    [string]$Tag = 'main',

    [string]$TestBaseDir = $null
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$scriptDir = Split-Path -Parent $PSCommandPath
# This script lives in ai/scripts/OspreySharp/ alongside the
# Compare-* / Test-* / Build-* scripts and the Python helpers.
$ospDir    = $scriptDir
. (Join-Path $ospDir 'Dataset-Config.ps1')

$ds = Get-DatasetConfig $Dataset -TestBaseDir $TestBaseDir
$datasetRoot = $ds.TestDir
$libraryName = $ds.Library
$resolution  = $ds.Resolution

# Resolve which files to use.
$allDatasetFiles = @($ds.AllFiles)
$selectedFiles = switch ($Files) {
    'Single' { ,@($allDatasetFiles[0]) }
    'All'    { $allDatasetFiles }
    default  {
        $stems = $Files -split ','
        # Allow user to pass either stems or full mzML names; normalize
        # to the dataset's mzML filenames.
        $resolved = @()
        foreach ($s in $stems) {
            $s = $s.Trim()
            if (-not $s) { continue }
            $match = $allDatasetFiles | Where-Object {
                $_ -eq $s -or
                ([System.IO.Path]::GetFileNameWithoutExtension($_)) -eq $s
            } | Select-Object -First 1
            if (-not $match) {
                throw "File '$s' not in dataset $Dataset"
            }
            $resolved += $match
        }
        ,$resolved
    }
}
$selectedStems = @($selectedFiles | ForEach-Object {
    [System.IO.Path]::GetFileNameWithoutExtension($_)
})

# ----------------------------------------------------------------------
# Binary identity
# ----------------------------------------------------------------------

# ospDir = ai/scripts/OspreySharp; project root is three parents up.
$projRoot = (Resolve-Path (Join-Path $ospDir '..\..\..')).Path
$rustBin = Join-Path $projRoot 'osprey\target\release\osprey.exe'
$csBin   = Join-Path $projRoot 'pwiz\pwiz_tools\OspreySharp\OspreySharp\bin\x64\Release\net8.0\OspreySharp.exe'
foreach ($b in @($rustBin, $csBin)) {
    if (-not (Test-Path $b)) { throw "Binary missing: $b" }
}
$rustSha = (Get-FileHash $rustBin -Algorithm SHA256).Hash.ToLower()
$csSha   = (Get-FileHash $csBin -Algorithm SHA256).Hash.ToLower()

# ----------------------------------------------------------------------
# Workdir
# ----------------------------------------------------------------------

$workRoot = Join-Path $datasetRoot ("_test_regression_" + $Tag)
$inputsDir = Join-Path $workRoot 'inputs'

if ($Force -and (Test-Path $workRoot)) {
    Write-Host "[Test-Regression] -Force: removing $workRoot" -ForegroundColor DarkYellow
    Remove-Item $workRoot -Recurse -Force
}

if (-not (Test-Path $workRoot)) {
    New-Item -ItemType Directory -Path $workRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $inputsDir -Force | Out-Null
    foreach ($mzml in $selectedFiles) {
        Copy-Item (Join-Path $datasetRoot $mzml) (Join-Path $inputsDir (Split-Path $mzml -Leaf))
    }
    Copy-Item (Join-Path $datasetRoot $libraryName) (Join-Path $inputsDir $libraryName)
    $libcache = Join-Path $datasetRoot ($libraryName + '.libcache')
    if (Test-Path $libcache) {
        Copy-Item $libcache (Join-Path $inputsDir ($libraryName + '.libcache'))
    }
}

# Top-level manifest (refreshed each run; binary identity may change)
$topManifest = [ordered]@{
    tag         = $Tag
    dataset     = $Dataset
    files       = [string[]]$selectedStems
    library     = $libraryName
    resolution  = $resolution
    rust_bin    = @{ path = $rustBin; sha256 = $rustSha }
    cs_bin      = @{ path = $csBin;   sha256 = $csSha }
    last_run_at = (Get-Date).ToString('o')
}
$topManifest | ConvertTo-Json -Depth 6 |
    Set-Content -Path (Join-Path $workRoot 'manifest.json') -Encoding UTF8

Write-Host ""
Write-Host "=== Test-Regression ===" -ForegroundColor Cyan
Write-Host ("Dataset:    {0}" -f $Dataset)
Write-Host ("Files:      {0}" -f ($selectedStems -join ', '))
Write-Host ("Workdir:    {0}" -f $workRoot)
Write-Host ("Sides:      {0}" -f $Side)
Write-Host ("Range:      {0} -> {1}{2}" -f $StartStage, $StopAfterStage,
    $(if ($Continue) { '  (continue on fail)' } else { '  (stop on first fail)' }))
Write-Host ("Rust:       sha {0}" -f $rustSha.Substring(0,12))
Write-Host ("C#:         sha {0}" -f $csSha.Substring(0,12))
Write-Host ""

# ----------------------------------------------------------------------
# Stage execution helpers
# ----------------------------------------------------------------------

$stageOrder = @('stage1to4','stage5','stage6','stage7','blib')
$stageIdx = @{}
for ($i = 0; $i -lt $stageOrder.Count; $i++) { $stageIdx[$stageOrder[$i]] = $i }
$startIdx = $stageIdx[$StartStage]
$stopIdx  = $stageIdx[$StopAfterStage]
if ($startIdx -gt $stopIdx) {
    throw "StartStage ($StartStage) is after StopAfterStage ($StopAfterStage)"
}

function Get-StageInputDir { param([string]$Stage) Join-Path $workRoot ($Stage + '\inputs') }
function Get-StageRustDir  { param([string]$Stage) Join-Path $workRoot ($Stage + '\rust') }
function Get-StageCsDir    { param([string]$Stage) Join-Path $workRoot ($Stage + '\cs') }
function Get-StageStatusPath { param([string]$Stage) Join-Path $workRoot ($Stage + '\status.json') }

function Reset-StageDir {
    param([string]$Dir, [bool]$KeepInputs)
    if (Test-Path $Dir) {
        if ($KeepInputs) {
            Get-ChildItem $Dir -File | Remove-Item -Force
            Get-ChildItem $Dir -Directory | Where-Object { $_.Name -ne 'inputs' } |
                Remove-Item -Recurse -Force
        } else {
            Remove-Item $Dir -Recurse -Force
        }
    }
    New-Item -ItemType Directory -Path $Dir -Force | Out-Null
}

function Invoke-Tool {
    param(
        [string]$Bin, [string]$WorkDir,
        [string[]]$CliArgs, [hashtable]$EnvVars
    )
    # Defensively unset every OSPREY_* dump/exit hook from prior stages
    # before applying this stage's env. PowerShell's Environment.SetEnv
    # restore-to-null is brittle; clearing the union of all stage hooks
    # at the start removes leak-between-stages bugs entirely.
    $allHooks = @(
        'OSPREY_DUMP_STANDARDIZER','OSPREY_DUMP_SUBSAMPLE',
        'OSPREY_DUMP_SVM_WEIGHTS','OSPREY_DUMP_PERCOLATOR',
        'OSPREY_PERCOLATOR_ONLY',
        'OSPREY_DUMP_RECONCILIATION','OSPREY_RECONCILIATION_ONLY',
        'OSPREY_DUMP_RESCORED','OSPREY_RESCORED_ONLY',
        'OSPREY_DUMP_STAGE6_PROTEIN_FDR','OSPREY_STAGE6_PROTEIN_FDR_ONLY',
        'OSPREY_DUMP_PROTEIN_FDR','OSPREY_PROTEIN_FDR_ONLY',
        'OSPREY_DUMP_STAGE7_PROTEIN_FDR','OSPREY_STAGE7_PROTEIN_FDR_ONLY',
        'OSPREY_DUMP_CONSENSUS','OSPREY_CONSENSUS_ONLY',
        'OSPREY_DUMP_MULTICHARGE','OSPREY_MULTICHARGE_ONLY',
        'OSPREY_DUMP_CALIBRATION','OSPREY_CALIBRATION_ONLY',
        'OSPREY_DUMP_LOESS_INPUT','OSPREY_LOESS_INPUT_ONLY',
        'OSPREY_DUMP_LOESS_FIT','OSPREY_LOESS_FIT_ONLY',
        'OSPREY_DUMP_INV_PREDICT','OSPREY_INV_PREDICT_ONLY',
        'OSPREY_DUMP_BLIB_QVALUES','OSPREY_DUMP_BLIB_ADMISSION',
        'OSPREY_DUMP_REFIT','OSPREY_DUMP_PREDICT_RT',
        'OSPREY_DUMP_MP_INPUTS','OSPREY_DUMP_CWT_PATH'
    )
    # PowerShell quirk: [Environment]::SetEnvironmentVariable($k, $null)
    # sets the var to "" rather than unsetting. The OSPREY binaries
    # treat "" as set (IsOne handler accepts any non-"0" value), so an
    # empty-string leak still triggers early-exit hooks. Remove-Item on
    # the env: PSDrive really unsets.
    foreach ($k in $allHooks) {
        if (Test-Path "env:$k") { Remove-Item "env:$k" }
    }
    foreach ($k in $EnvVars.Keys) {
        [Environment]::SetEnvironmentVariable($k, $EnvVars[$k])
    }
    $logPath = Join-Path $WorkDir 'stdout.log'
    $sw = [Diagnostics.Stopwatch]::StartNew()
    Push-Location $WorkDir
    try {
        & $Bin @CliArgs *>&1 | Tee-Object -FilePath $logPath | Out-Null
        $exit = $LASTEXITCODE
    } finally {
        Pop-Location
        # No env restore here: the next Invoke-Tool clears all stage
        # hooks defensively at the start. Leaving them set briefly is
        # harmless within this script's own scope.
    }
    $sw.Stop()
    return [pscustomobject]@{ exit = $exit; wall = $sw.Elapsed }
}

# ----------------------------------------------------------------------
# Stage 1-4: end-to-end --no-join
# ----------------------------------------------------------------------

function Stage-Inputs-Stage1to4 {
    # Stage 1-4 inputs are the dataset mzML + library; no upstream
    # frozen output. We rebuild side dirs from the inputs/ snapshot.
    $sIn = Get-StageInputDir 'stage1to4'
    Reset-StageDir $sIn -KeepInputs:$false
    foreach ($mzml in $selectedFiles) {
        Copy-Item (Join-Path $inputsDir (Split-Path $mzml -Leaf)) `
            (Join-Path $sIn (Split-Path $mzml -Leaf))
    }
    Copy-Item (Join-Path $inputsDir $libraryName) (Join-Path $sIn $libraryName)
    $cache = Join-Path $inputsDir ($libraryName + '.libcache')
    if (Test-Path $cache) { Copy-Item $cache (Join-Path $sIn ($libraryName + '.libcache')) }
}

function Run-Stage1to4 {
    param([string]$SideName, [string]$Bin)
    $sIn  = Get-StageInputDir 'stage1to4'
    $sOut = if ($SideName -eq 'rust') { Get-StageRustDir 'stage1to4' } else { Get-StageCsDir 'stage1to4' }
    Reset-StageDir $sOut -KeepInputs:$false
    # Copy inputs to side dir (each side runs in its own dir)
    foreach ($f in (Get-ChildItem $sIn -File)) {
        Copy-Item $f.FullName (Join-Path $sOut $f.Name)
    }
    $cliArgs = @()
    foreach ($mzml in $selectedFiles) { $cliArgs += '-i'; $cliArgs += (Split-Path $mzml -Leaf) }
    $cliArgs += @('-l', $libraryName, '-o', 'unused.blib',
                  '--resolution', $resolution,
                  '--protein-fdr', '0.01', '--threads', '16',
                  '--no-join')
    $env = @{}  # no per-stage dumps needed; we compare the parquet directly
    $r = Invoke-Tool -Bin $Bin -WorkDir $sOut -CliArgs $cliArgs -EnvVars $env
    Write-Host ("  [run] {0,-4} stage1to4  exit={1} wall={2:mm\:ss}" -f $SideName, $r.exit, $r.wall) `
        -ForegroundColor $(if ($r.exit -eq 0) { 'DarkGreen' } else { 'DarkRed' })
    return $r
}

function Compare-Stage1to4 {
    $rustDir = Get-StageRustDir 'stage1to4'
    $csDir   = Get-StageCsDir 'stage1to4'
    $allOk = $true
    $details = @()
    foreach ($stem in $selectedStems) {
        $rPq = Join-Path $rustDir ($stem + '.scores.parquet')
        $cPq = Join-Path $csDir   ($stem + '.scores.parquet')
        if ((-not (Test-Path $rPq)) -or (-not (Test-Path $cPq))) {
            $details += @{ file=$stem; status='MISSING'; rust=$rPq; cs=$cPq }
            $allOk = $false
            continue
        }
        $py = Join-Path $scriptDir 'inspect_parquet.py'
        $diffLog = Join-Path $rustDir ('..\diff_' + $stem + '.log')
        # Stage 1-4 is gated at 1e-6 absolute (matches Test-Features.ps1
        # PIN-feature threshold). xcorr/sg_weighted_xcorr have
        # documented sub-1e-6 algorithmic drift; tighter gates would
        # block on known noise. A real regression here would either
        # exceed 1e-6 (caught) or change the row set (always caught).
        & python $py $rPq -B $cPq --tolerance 1e-6 *>&1 | Tee-Object -FilePath $diffLog | Out-Null
        $exit = $LASTEXITCODE
        $details += @{
            file = $stem
            status = if ($exit -eq 0) { 'PASS' } else { 'FAIL' }
            log = $diffLog
        }
        if ($exit -ne 0) { $allOk = $false }
    }
    return [pscustomobject]@{ ok = $allOk; details = $details }
}

function Freeze-Stage1to4 {
    # Freeze: copy rust's .scores.parquet + calibration JSON to
    # stage5/inputs as the canonical Stage 5 input. Stage the library
    # + libcache. Also stage the mzMLs because Stage 6 rescore re-
    # extracts spectra from them (Stage 5 itself ignores mzMLs, so
    # carrying them costs nothing on Stage 5 and saves a refetch later).
    $rustDir = Get-StageRustDir 'stage1to4'
    $next = Get-StageInputDir 'stage5'
    Reset-StageDir $next -KeepInputs:$false
    foreach ($stem in $selectedStems) {
        Copy-Item (Join-Path $rustDir ($stem + '.scores.parquet')) `
            (Join-Path $next ($stem + '.scores.parquet'))
        $cal = Join-Path $rustDir ($stem + '.calibration.json')
        if (Test-Path $cal) { Copy-Item $cal (Join-Path $next ($stem + '.calibration.json')) }
    }
    foreach ($mzml in $selectedFiles) {
        $src = Join-Path $inputsDir (Split-Path $mzml -Leaf)
        if (Test-Path $src) { Copy-Item $src (Join-Path $next (Split-Path $mzml -Leaf)) }
    }
    Copy-Item (Join-Path $inputsDir $libraryName) (Join-Path $next $libraryName)
    $cache = Join-Path $inputsDir ($libraryName + '.libcache')
    if (Test-Path $cache) { Copy-Item $cache (Join-Path $next ($libraryName + '.libcache')) }
}

# ----------------------------------------------------------------------
# Generic stage runner for stage5/6/7/blib (--input-scores driven)
# ----------------------------------------------------------------------

# Per-stage env+dump configuration.
$stageConfig = @{
    'stage5' = @{
        envVars = @{
            OSPREY_DUMP_STANDARDIZER = '1'; OSPREY_DUMP_SUBSAMPLE = '1'
            OSPREY_DUMP_SVM_WEIGHTS = '1';  OSPREY_DUMP_PERCOLATOR = '1'
            OSPREY_PERCOLATOR_ONLY = '1'
        }
        compareDumps = @('standardizer','subsample','svm_weights','percolator')
    }
    'stage6' = @{
        envVars = @{
            OSPREY_DUMP_RECONCILIATION = '1'; OSPREY_DUMP_RESCORED = '1'
            OSPREY_RESCORED_ONLY = '1'
        }
        compareDumps = @('reconciliation','rescored')
    }
    'stage7' = @{
        envVars = @{
            OSPREY_DUMP_STAGE7_PROTEIN_FDR = '1'
            OSPREY_STAGE7_PROTEIN_FDR_ONLY = '1'
        }
        compareDumps = @()  # uses Compare-Stage7-Crossimpl.ps1 (TSV-aware)
    }
    'blib' = @{
        envVars = @{}
        compareDumps = @()  # uses Compare-Blib-Crossimpl.ps1
    }
}

function Run-PostStage4 {
    param([string]$Stage, [string]$SideName, [string]$Bin)
    $sIn  = Get-StageInputDir $Stage
    $sOut = if ($SideName -eq 'rust') { Get-StageRustDir $Stage } else { Get-StageCsDir $Stage }
    Reset-StageDir $sOut -KeepInputs:$false
    foreach ($f in (Get-ChildItem $sIn -File)) {
        Copy-Item $f.FullName (Join-Path $sOut $f.Name)
    }
    $cliArgs = @('--join-at-pass=1')
    foreach ($stem in $selectedStems) {
        $cliArgs += '--input-scores'
        $cliArgs += ($stem + '.scores.parquet')
    }
    $cliArgs += @('-l', $libraryName, '-o', 'output.blib',
                  '--resolution', $resolution,
                  '--protein-fdr', '0.01', '--threads', '16')
    $env = $stageConfig[$Stage].envVars
    $r = Invoke-Tool -Bin $Bin -WorkDir $sOut -CliArgs $cliArgs -EnvVars $env
    Write-Host ("  [run] {0,-4} {1,-9} exit={2} wall={3:mm\:ss}" -f $SideName, $Stage, $r.exit, $r.wall) `
        -ForegroundColor $(if ($r.exit -eq 0) { 'DarkGreen' } else { 'DarkRed' })
    return $r
}

function Compare-DumpSha {
    param([string]$Stage)
    $rustDir = Get-StageRustDir $Stage
    $csDir   = Get-StageCsDir $Stage
    $allOk = $true
    $details = @()
    foreach ($tag in $stageConfig[$Stage].compareDumps) {
        # Per-file or flat naming: try flat first, then per-stem.
        $rustFile = $null; $csFile = $null
        $flatRust = Get-ChildItem $rustDir -Filter ("rust_*_{0}.tsv" -f $tag) -File -ErrorAction SilentlyContinue
        $flatCs   = Get-ChildItem $csDir   -Filter ("cs_*_{0}.tsv"   -f $tag) -File -ErrorAction SilentlyContinue
        if (-not $flatRust -or -not $flatCs) {
            $details += @{ tag=$tag; status='MISSING' }
            $allOk = $false
            continue
        }
        # Compare each pair (filenames must match by suffix)
        foreach ($rf in $flatRust) {
            $cf = $flatCs | Where-Object {
                ($_.Name -replace '^cs_','rust_') -eq $rf.Name
            } | Select-Object -First 1
            if (-not $cf) { $details += @{ tag=$tag; status='ASYMMETRIC'; rust=$rf.Name }; $allOk = $false; continue }
            $rSha = (Get-FileHash $rf.FullName -Algorithm SHA256).Hash
            $cSha = (Get-FileHash $cf.FullName -Algorithm SHA256).Hash
            $st = if ($rSha -eq $cSha) { 'PASS' } else { 'FAIL' }
            if ($st -eq 'FAIL') { $allOk = $false }
            $details += @{ tag=$tag; file=$rf.Name; status=$st;
                rust_sha=$rSha.Substring(0,12); cs_sha=$cSha.Substring(0,12);
                rust_size=$rf.Length; cs_size=$cf.Length }
        }
    }
    return [pscustomobject]@{ ok = $allOk; details = $details }
}

function Compare-Stage7-Wrap {
    $rustDir = Get-StageRustDir 'stage7'
    $csDir   = Get-StageCsDir 'stage7'
    $rTsv = Join-Path $rustDir 'rust_stage7_protein_fdr.tsv'
    $cTsv = Join-Path $csDir   'cs_stage7_protein_fdr.tsv'
    if ((-not (Test-Path $rTsv)) -or (-not (Test-Path $cTsv))) {
        return [pscustomobject]@{ ok = $false; details = @(@{status='MISSING'; rust=$rTsv; cs=$cTsv}) }
    }
    $diffLog = Join-Path $workRoot 'stage7\diff.log'
    & pwsh -File (Join-Path $ospDir 'Compare-Stage7-Crossimpl.ps1') -RustTsv $rTsv -CsTsv $cTsv `
        *>&1 | Tee-Object -FilePath $diffLog | Out-Null
    $exit = $LASTEXITCODE
    return [pscustomobject]@{ ok = ($exit -eq 0);
        details = @(@{status=$(if ($exit -eq 0) { 'PASS' } else { 'FAIL' }); log=$diffLog}) }
}

function Compare-Blib-Wrap {
    $rustDir = Get-StageRustDir 'blib'
    $csDir   = Get-StageCsDir 'blib'
    $rBlib = Join-Path $rustDir 'output.blib'
    $cBlib = Join-Path $csDir   'output.blib'
    if ((-not (Test-Path $rBlib)) -or (-not (Test-Path $cBlib))) {
        return [pscustomobject]@{ ok = $false; details = @(@{status='MISSING'; rust=$rBlib; cs=$cBlib}) }
    }
    $diffLog = Join-Path $workRoot 'blib\diff.log'
    & pwsh -File (Join-Path $ospDir 'Compare-Blib-Crossimpl.ps1') -RustBlib $rBlib -CsBlib $cBlib `
        *>&1 | Tee-Object -FilePath $diffLog | Out-Null
    $exit = $LASTEXITCODE
    return [pscustomobject]@{ ok = ($exit -eq 0);
        details = @(@{status=$(if ($exit -eq 0) { 'PASS' } else { 'FAIL' }); log=$diffLog}) }
}

function Freeze-PostStage4 {
    param([string]$FromStage, [string]$ToStage)
    # By default, freeze rust's outputs as the next stage's inputs.
    $next = Get-StageInputDir $ToStage
    Reset-StageDir $next -KeepInputs:$false
    # Copy from prior stage's inputs (the .scores.parquet that fed
    # both sides) — those are the canonical Stage 4 outputs and
    # downstream stages re-use them at every step.
    $prev = Get-StageInputDir $FromStage
    foreach ($f in (Get-ChildItem $prev -File)) {
        Copy-Item $f.FullName (Join-Path $next $f.Name)
    }
}

# ----------------------------------------------------------------------
# Walk
# ----------------------------------------------------------------------

$results = @()
$fail = $false

for ($i = $startIdx; $i -le $stopIdx; $i++) {
    $stage = $stageOrder[$i]
    Write-Host ""
    Write-Host ("--- {0} ---" -f $stage) -ForegroundColor Cyan

    # Verify inputs are available for this stage (for stages > stage1to4,
    # the previous stage must have frozen its outputs, OR we're starting
    # mid-march and the user must have previously run earlier stages).
    if ($stage -ne 'stage1to4') {
        $sIn = Get-StageInputDir $stage
        if (-not (Test-Path $sIn) -or @(Get-ChildItem $sIn -File).Count -eq 0) {
            Write-Host ("  ERROR: no frozen inputs at {0}. Run from earlier stage first." -f $sIn) -ForegroundColor Red
            $fail = $true
            $results += @{ stage = $stage; status = 'NO_INPUTS' }
            break
        }
    } else {
        Stage-Inputs-Stage1to4
    }

    # Run sides
    $runR = $true; $runC = $true
    if ($Side -eq 'rust') { $runC = $false }
    if ($Side -eq 'cs')   { $runR = $false }

    if ($runR) {
        if ($stage -eq 'stage1to4') { Run-Stage1to4 -SideName 'rust' -Bin $rustBin | Out-Null }
        else                         { Run-PostStage4 -Stage $stage -SideName 'rust' -Bin $rustBin | Out-Null }
    }
    if ($runC) {
        if ($stage -eq 'stage1to4') { Run-Stage1to4 -SideName 'cs'   -Bin $csBin   | Out-Null }
        else                         { Run-PostStage4 -Stage $stage -SideName 'cs'   -Bin $csBin   | Out-Null }
    }

    # Compare
    $cmp = switch ($stage) {
        'stage1to4' { Compare-Stage1to4 }
        'stage5'    { Compare-DumpSha -Stage 'stage5' }
        'stage6'    { Compare-DumpSha -Stage 'stage6' }
        'stage7'    { Compare-Stage7-Wrap }
        'blib'      { Compare-Blib-Wrap }
    }

    $statusPath = Get-StageStatusPath $stage
    @{ stage = $stage; ok = $cmp.ok; details = $cmp.details;
       last_run_at = (Get-Date).ToString('o') } |
        ConvertTo-Json -Depth 6 | Set-Content -Path $statusPath -Encoding UTF8

    if ($cmp.ok) {
        Write-Host ("  [PASS] {0}" -f $stage) -ForegroundColor Green
    } else {
        Write-Host ("  [FAIL] {0}" -f $stage) -ForegroundColor Red
        foreach ($d in $cmp.details) {
            $msg = ($d | ConvertTo-Json -Compress)
            Write-Host ("    {0}" -f $msg) -ForegroundColor Red
        }
        $fail = $true
    }
    $results += @{ stage = $stage; status = $(if ($cmp.ok) { 'PASS' } else { 'FAIL' }) }

    # Freeze for next stage if appropriate
    if ($cmp.ok -and ($i -lt $stopIdx)) {
        $nextStage = $stageOrder[$i + 1]
        if ($stage -eq 'stage1to4') { Freeze-Stage1to4 }
        else                         { Freeze-PostStage4 -FromStage $stage -ToStage $nextStage }
        Write-Host ("  [freeze] inputs prepared for {0}" -f $nextStage) -ForegroundColor DarkGray
    }

    if ((-not $cmp.ok) -and (-not $Continue)) {
        Write-Host ""
        Write-Host ("STOP: {0} failed; halting march. Iterate with: " -f $stage) -ForegroundColor Yellow
        Write-Host ("  pwsh -File Test-Regression.ps1 -StartStage {0} -StopAfterStage {0} -Side cs" -f $stage) -ForegroundColor Yellow
        break
    }
}

# ----------------------------------------------------------------------
# Summary
# ----------------------------------------------------------------------

Write-Host ""
Write-Host "--- Summary ---" -ForegroundColor Cyan
foreach ($r in $results) {
    $color = switch ($r.status) {
        'PASS' { 'Green' } 'FAIL' { 'Red' } default { 'DarkYellow' }
    }
    Write-Host ("  {0,-10} {1}" -f $r.stage, $r.status) -ForegroundColor $color
}

exit $(if ($fail) { 1 } else { 0 })
