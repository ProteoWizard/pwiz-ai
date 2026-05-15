<#
.SYNOPSIS
    OspreySharp same-impl regression test against a frozen snapshot.
    Asserts that the current OspreySharp build produces the same
    output at every pipeline stage as a previously-captured baseline.
    Pass/fail with structured per-stage diagnostics.

.DESCRIPTION
    Sibling of Test-Regression.ps1 — same five-stage walk
    (stage1to4 -> stage5 -> stage6 -> stage7 -> blib), same per-stage
    isolation env vars, same freeze-and-march flow — but the
    "ground truth" side is a snapshot directory captured from a
    known-good earlier OspreySharp build instead of a parallel run
    of Rust osprey. Used as the safety net for the OspreySharp
    pipeline-task rearchitecture sprint (see ai/todos/active/
    TODO-20260509_osprey_pipeline_tasks.md).

    Two modes:

    1. Default (compare):
         pwsh -File Test-Snapshot.ps1
       Runs the current OspreySharp build at every stage and compares
       against $TestBaseDir/<dataset>/_snapshots/<tag>/<stage>/. Fails
       on any mismatch.

    2. -CreateSnapshot:
         pwsh -File Test-Snapshot.ps1 -CreateSnapshot
       Runs the current OspreySharp build at every stage and copies
       its outputs into the snapshot directory as the new baseline.
       Records the source commit SHA, branch, and binary SHA-256 in
       a manifest at the snapshot root. Use this once on master HEAD
       before starting any rearchitecture work; refresh it only when
       you intentionally accept a behavior change.

    Stage walk: stage1to4 -> stage5 -> stage6 -> stage7 -> blib.

    Stage isolation matrix (matches Test-Regression.ps1):

      Stage      CLI extras                                         Exit hook
      ---------  -------------------------------------------------  -----------------------------
      stage1to4  --no-join                                          (--no-join exits after Stage 4)
      stage5     --join-at-pass=1 --input-scores <frozen.parquet>   OSPREY_PERCOLATOR_ONLY=1
      stage6     --join-at-pass=1 --input-scores <frozen.parquet>   OSPREY_STAGE7_PROTEIN_FDR_ONLY=1
      stage7     --join-at-pass=2 --input-scores <frozen.parquet>   OSPREY_STAGE7_PROTEIN_FDR_ONLY=1
      blib       --join-at-pass=2 --input-scores <frozen.parquet>   (none — full pipeline)

    Comparators (tightened relative to Test-Regression.ps1 because
    same-impl removes the documented Rust<->C# xcorr / sg_weighted_xcorr
    ~1e-7 drift from the f32 HRAM cache):

      stage1to4  SHA-256 byte equality on per-file .scores.parquet
                 (vs. inspect_parquet.py 1e-6 in cross-impl mode)
      stage5     SHA-256 byte equality on standardizer/subsample/
                 svm_weights/percolator dumps
      stage6     SHA-256 byte equality on multicharge/consensus/
                 reconciliation/rescored dumps + reconciled parquet
                 + FDR sidecars
      stage7     Compare-Stage7-Crossimpl.ps1 (column-tolerance,
                 reused with snapshot path passed as -RustTsv)
      blib       Compare-Blib-Crossimpl.ps1 (per-table tolerance,
                 reused with snapshot path passed as -RustBlib)

    Snapshot location:

      $TestBaseDir/<dataset>/_snapshots/<Tag>/
        manifest.json
        stage1to4/  (per-file .scores.parquet + .calibration.json)
        stage5/     (cs_*_<dump>.tsv files)
        stage6/     (dumps + reconciled parquet + FDR sidecars +
                     reconciliation.json)
        stage7/     (cs_stage7_protein_fdr.tsv)
        blib/       (output.blib)

    Default tag is 'main'. Use -Tag to keep multiple named baselines
    (e.g., 'pre-rearchitecture', 'phase-a-checkpoint').

.PARAMETER Dataset
    Stellar | Astral. Default Stellar.

.PARAMETER Files
    'Single' (default — first file), 'All', or comma-separated stems.

.PARAMETER StartStage
    Where to start. Default 'stage1to4'. Mid-march start requires the
    previous stage's frozen inputs to exist (run a full march at
    least once first, or use -Force to refresh).

.PARAMETER StopAfterStage
    Last stage to run. Default 'blib'.

.PARAMETER CreateSnapshot
    Capture mode: copy current cs outputs into the snapshot dir as
    the new baseline. Skips comparison. Records source commit + SHA.

.PARAMETER Tag
    Snapshot identifier. Default 'main'. Each tag has its own
    snapshot dir and its own _test_snapshot_<Tag> workdir, so
    iterations don't cross-contaminate.

.PARAMETER Force
    Discard existing workdir and start clean.

.PARAMETER Continue
    Don't stop on first FAIL; run all requested stages.

.PARAMETER TestBaseDir
    Override dataset root.

.OUTPUTS
    Exit code: 0 = all requested stages PASS (or capture succeeded);
    1 = any FAIL; 2 = setup error.

.EXAMPLE
    # End-to-end snapshot regression on a single Stellar file.
    pwsh -File ./Test-Snapshot.ps1

.EXAMPLE
    # Capture a fresh baseline from current cs build.
    pwsh -File ./Test-Snapshot.ps1 -CreateSnapshot -Files All

.EXAMPLE
    # After editing C#: re-run only the suspect stage.
    pwsh -File ./Test-Snapshot.ps1 -StartStage stage5 -StopAfterStage stage5

.EXAMPLE
    # Capture a named pre-rearchitecture baseline before starting work.
    pwsh -File ./Test-Snapshot.ps1 -CreateSnapshot -Tag pre-rearchitecture -Files All
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

    [switch]$CreateSnapshot,

    [string]$Tag = 'main',

    [switch]$Force,
    [switch]$Continue,

    [string]$TestBaseDir = $null
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$scriptDir = Split-Path -Parent $PSCommandPath
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

$projRoot = (Resolve-Path (Join-Path $ospDir '..\..\..')).Path
$csBin = Join-Path $projRoot 'pwiz\pwiz_tools\OspreySharp\OspreySharp\bin\x64\Release\net8.0\OspreySharp.exe'
if (-not (Test-Path $csBin)) {
    Write-Host "[Test-Snapshot] OspreySharp.exe not found: $csBin" -ForegroundColor Red
    Write-Host "  Build first: pwsh -File ./ai/scripts/OspreySharp/Build-OspreySharp.ps1" -ForegroundColor Yellow
    exit 2
}
$csSha = (Get-FileHash $csBin -Algorithm SHA256).Hash.ToLower()

# Source commit SHA (best-effort; used only in -CreateSnapshot manifest).
$pwizDir = Join-Path $projRoot 'pwiz'
$sourceCommit = $null
$sourceBranch = $null
if (Test-Path (Join-Path $pwizDir '.git')) {
    Push-Location $pwizDir
    try {
        $sourceCommit = (git rev-parse HEAD 2>$null)
        $sourceBranch = (git rev-parse --abbrev-ref HEAD 2>$null)
    } finally { Pop-Location }
}

# ----------------------------------------------------------------------
# Workdir + snapshot dir
# ----------------------------------------------------------------------

$workRoot   = Join-Path $datasetRoot ("_test_snapshot_" + $Tag)
$inputsDir  = Join-Path $workRoot 'inputs'
$snapshotRoot = Join-Path $datasetRoot '_snapshots'
$snapshotDir  = Join-Path $snapshotRoot $Tag

if ($Force -and (Test-Path $workRoot)) {
    Write-Host "[Test-Snapshot] -Force: removing $workRoot" -ForegroundColor DarkYellow
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

# When creating, ensure snapshot dirs exist (and are empty for stages we'll write).
if ($CreateSnapshot -and -not (Test-Path $snapshotDir)) {
    New-Item -ItemType Directory -Path $snapshotDir -Force | Out-Null
}

# In compare mode, the snapshot dir must exist or we have nothing to compare against.
if (-not $CreateSnapshot -and -not (Test-Path $snapshotDir)) {
    Write-Host "[Test-Snapshot] No snapshot at $snapshotDir" -ForegroundColor Red
    Write-Host "  Capture one first: -CreateSnapshot -Tag $Tag" -ForegroundColor Yellow
    exit 2
}

# Top-level workdir manifest (refreshed each run).
$workManifest = [ordered]@{
    tag             = $Tag
    dataset         = $Dataset
    files           = [string[]]$selectedStems
    library         = $libraryName
    resolution      = $resolution
    cs_bin          = @{ path = $csBin; sha256 = $csSha }
    snapshot_dir    = $snapshotDir
    create_snapshot = [bool]$CreateSnapshot
    source_commit   = $sourceCommit
    source_branch   = $sourceBranch
    last_run_at     = (Get-Date).ToString('o')
}
$workManifest | ConvertTo-Json -Depth 6 |
    Set-Content -Path (Join-Path $workRoot 'manifest.json') -Encoding UTF8

Write-Host ""
Write-Host "=== Test-Snapshot ===" -ForegroundColor Cyan
Write-Host ("Dataset:    {0}" -f $Dataset)
Write-Host ("Files:      {0}" -f ($selectedStems -join ', '))
Write-Host ("Workdir:    {0}" -f $workRoot)
Write-Host ("Snapshot:   {0}" -f $snapshotDir)
Write-Host ("Mode:       {0}" -f $(if ($CreateSnapshot) { 'CAPTURE (writes snapshot)' } else { 'COMPARE (reads snapshot)' }))
Write-Host ("Range:      {0} -> {1}{2}" -f $StartStage, $StopAfterStage,
    $(if ($Continue) { '  (continue on fail)' } else { '  (stop on first fail)' }))
Write-Host ("C#:         sha {0}" -f $csSha.Substring(0,12))
if ($sourceCommit) {
    Write-Host ("Source:     {0} ({1})" -f $sourceCommit.Substring(0,12), $sourceBranch)
}
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

function Get-StageInputDir    { param([string]$Stage) Join-Path $workRoot ($Stage + '\inputs') }
function Get-StageCsDir       { param([string]$Stage) Join-Path $workRoot ($Stage + '\cs') }
function Get-StageSnapshotDir { param([string]$Stage) Join-Path $snapshotDir $Stage }
function Get-StageStatusPath  { param([string]$Stage) Join-Path $workRoot ($Stage + '\status.json') }

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
    # Defensively unset every OSPREY_* dump/exit hook from prior stages.
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
    }
    $sw.Stop()
    return [pscustomobject]@{ exit = $exit; wall = $sw.Elapsed }
}

# ----------------------------------------------------------------------
# Per-stage env + comparator config (shape mirrors Test-Regression.ps1
# but each stage emits cs_* dumps; the snapshot dir holds the captured
# baseline of those same cs_* files plus the artifacts downstream
# stages need.)
# ----------------------------------------------------------------------

$stageConfig = @{
    'stage5' = @{
        envVars = @{
            OSPREY_DUMP_STANDARDIZER = '1'; OSPREY_DUMP_SUBSAMPLE = '1'
            OSPREY_DUMP_SVM_WEIGHTS  = '1'; OSPREY_DUMP_PERCOLATOR = '1'
            OSPREY_PERCOLATOR_ONLY   = '1'
        }
        compareDumps = @('standardizer','subsample','svm_weights','percolator')
    }
    'stage6' = @{
        envVars = @{
            OSPREY_DUMP_MULTICHARGE        = '1'
            OSPREY_DUMP_CONSENSUS          = '1'
            OSPREY_DUMP_RECONCILIATION     = '1'
            OSPREY_DUMP_RESCORED           = '1'
            OSPREY_STAGE7_PROTEIN_FDR_ONLY = '1'
        }
        compareDumps = @('multicharge','consensus','reconciliation','rescored')
    }
    'stage7' = @{
        envVars = @{
            OSPREY_DUMP_STAGE7_PROTEIN_FDR = '1'
            OSPREY_STAGE7_PROTEIN_FDR_ONLY = '1'
        }
        compareDumps = @()  # uses Compare-Stage7-Crossimpl.ps1
        useJoinAtPass2 = $true
    }
    'blib' = @{
        envVars = @{}
        compareDumps = @()  # uses Compare-Blib-Crossimpl.ps1
        useJoinAtPass2 = $true
    }
}

# Artifacts that downstream stages need to enter at the right pipeline
# checkpoint. Same patterns as Freeze-PostStage4 in Test-Regression.ps1.
$downstreamArtifactPatterns = @(
    '*.scores.parquet',
    '*.calibration.json',
    '*.1st-pass.fdr_scores.bin',
    '*.2nd-pass.fdr_scores.bin',
    '*.reconciliation.json'
)

# ----------------------------------------------------------------------
# Stage 1-4 runner
# ----------------------------------------------------------------------

function Stage-Inputs-Stage1to4 {
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
    $sIn  = Get-StageInputDir 'stage1to4'
    $sOut = Get-StageCsDir 'stage1to4'
    Reset-StageDir $sOut -KeepInputs:$false
    foreach ($f in (Get-ChildItem $sIn -File)) {
        Copy-Item $f.FullName (Join-Path $sOut $f.Name)
    }
    $cliArgs = @()
    foreach ($mzml in $selectedFiles) { $cliArgs += '-i'; $cliArgs += (Split-Path $mzml -Leaf) }
    $cliArgs += @('-l', $libraryName, '-o', 'unused.blib',
                  '--resolution', $resolution,
                  '--protein-fdr', '0.01', '--threads', '16',
                  '--no-join')
    $r = Invoke-Tool -Bin $csBin -WorkDir $sOut -CliArgs $cliArgs -EnvVars @{}
    Write-Host ("  [run] cs   stage1to4  exit={0} wall={1:mm\:ss}" -f $r.exit, $r.wall) `
        -ForegroundColor $(if ($r.exit -eq 0) { 'DarkGreen' } else { 'DarkRed' })
    return $r
}

# Stage 1-4 comparator: row-aligned content equality via
# inspect_parquet.py --diff at tolerance 0. Byte-level equality on
# the full parquet file is unreliable: Parquet.Net's ZSTD
# compression path (IronCompress + ZstdSharp) is non-deterministic
# at the byte level for at least the boolean is_decoy column —
# same logical data compresses to subtly different bytes across
# same-binary runs (a one-byte page-size shift cascades across
# every subsequent column). The LOGICAL data is fully deterministic
# (verified column-by-column), so an exact-tolerance diff over the
# decoded columns is the right gate: catches every regression in
# stored values without flagging compression noise. Row order is
# deterministic because RunCoelutionScoring writes per-window
# results into a pre-allocated array indexed by window position,
# then flattens in window-index order (AnalysisPipeline.cs ~line 3592).
function Compare-Stage1to4-Snapshot {
    $csDir   = Get-StageCsDir 'stage1to4'
    $snapDir = Get-StageSnapshotDir 'stage1to4'
    $py = Join-Path $scriptDir 'inspect_parquet.py'
    $allOk = $true
    $details = @()
    foreach ($stem in $selectedStems) {
        $cPq = Join-Path $csDir   ($stem + '.scores.parquet')
        $sPq = Join-Path $snapDir ($stem + '.scores.parquet')
        if ((-not (Test-Path $sPq)) -or (-not (Test-Path $cPq))) {
            $details += @{ file=$stem; status='MISSING'; cs=$cPq; snapshot=$sPq }
            $allOk = $false
            continue
        }
        $diffLog = Join-Path $csDir ('diff_' + $stem + '.log')
        & python $py $sPq -B $cPq --tolerance 0 *>&1 | Tee-Object -FilePath $diffLog | Out-Null
        $exit = $LASTEXITCODE
        $st = if ($exit -eq 0) { 'PASS' } else { 'FAIL' }
        if ($st -eq 'FAIL') { $allOk = $false }
        $details += @{ file=$stem; status=$st; log=$diffLog;
            cs_size=(Get-Item $cPq).Length; snap_size=(Get-Item $sPq).Length }
    }
    return [pscustomobject]@{ ok = $allOk; details = $details }
}

# ----------------------------------------------------------------------
# Generic post-stage4 runner
# ----------------------------------------------------------------------

function Run-PostStage4 {
    param([string]$Stage)
    $sIn  = Get-StageInputDir $Stage
    $sOut = Get-StageCsDir $Stage
    Reset-StageDir $sOut -KeepInputs:$false
    foreach ($f in (Get-ChildItem $sIn -File)) {
        Copy-Item $f.FullName (Join-Path $sOut $f.Name)
    }
    $useJP2 = $stageConfig[$Stage].useJoinAtPass2
    $entry = if ($useJP2) { '--join-at-pass=2' } else { '--join-at-pass=1' }
    $cliArgs = @($entry)
    foreach ($stem in $selectedStems) {
        $cliArgs += '--input-scores'
        $cliArgs += ($stem + '.scores.parquet')
    }
    $cliArgs += @('-l', $libraryName, '-o', 'output.blib',
                  '--resolution', $resolution,
                  '--protein-fdr', '0.01', '--threads', '16')
    $env = $stageConfig[$Stage].envVars
    $r = Invoke-Tool -Bin $csBin -WorkDir $sOut -CliArgs $cliArgs -EnvVars $env
    Write-Host ("  [run] cs   {0,-9} exit={1} wall={2:mm\:ss}" -f $Stage, $r.exit, $r.wall) `
        -ForegroundColor $(if ($r.exit -eq 0) { 'DarkGreen' } else { 'DarkRed' })
    return $r
}

# Stage 5/6 dump comparator: SHA-256 byte equality on cs_*_<tag>.tsv
# files. Both the live cs run and the captured snapshot use the cs_*
# prefix (since both are produced by the C# side); we compare files
# that share a name across the two directories.
function Compare-DumpSha-Snapshot {
    param([string]$Stage)
    $csDir   = Get-StageCsDir $Stage
    $snapDir = Get-StageSnapshotDir $Stage
    $allOk = $true
    $details = @()
    foreach ($tag in $stageConfig[$Stage].compareDumps) {
        $csFiles   = Get-ChildItem $csDir   -Filter ("cs_*_{0}.tsv" -f $tag) -File -ErrorAction SilentlyContinue
        $snapFiles = Get-ChildItem $snapDir -Filter ("cs_*_{0}.tsv" -f $tag) -File -ErrorAction SilentlyContinue
        # Symmetric absence (both sides skipped writing this dump) is
        # equivalent agreement. Single-file Stage 6 may legitimately
        # produce no consensus dump; if neither side wrote one, that's
        # not a regression.
        if (-not $csFiles -and -not $snapFiles) {
            $details += @{ tag=$tag; status='PASS'; note='symmetric absence' }
            continue
        }
        if (-not $csFiles -or -not $snapFiles) {
            $details += @{ tag=$tag; status='MISSING';
                cs_present=([bool]$csFiles); snap_present=([bool]$snapFiles) }
            $allOk = $false
            continue
        }
        foreach ($cf in $csFiles) {
            $sf = $snapFiles | Where-Object { $_.Name -eq $cf.Name } | Select-Object -First 1
            if (-not $sf) {
                $details += @{ tag=$tag; status='ASYMMETRIC'; cs=$cf.Name }
                $allOk = $false
                continue
            }
            $cSha = (Get-FileHash $cf.FullName -Algorithm SHA256).Hash
            $sSha = (Get-FileHash $sf.FullName -Algorithm SHA256).Hash
            $st = if ($cSha -eq $sSha) { 'PASS' } else { 'FAIL' }
            if ($st -eq 'FAIL') { $allOk = $false }
            $details += @{ tag=$tag; file=$cf.Name; status=$st;
                cs_sha=$cSha.Substring(0,12); snap_sha=$sSha.Substring(0,12);
                cs_size=$cf.Length; snap_size=$sf.Length }
        }
    }
    return [pscustomobject]@{ ok = $allOk; details = $details }
}

# Stage 6 rewrites .scores.parquet (content-equality via
# inspect_parquet.py to absorb ZSTD compression noise — see
# Compare-Stage1to4-Snapshot for the rationale) and emits FDR
# sidecars (.1st-pass.fdr_scores.bin, .2nd-pass.fdr_scores.bin) plus
# .reconciliation.json. The sidecars and JSON have shown stable
# byte equality across runs (no compression on those paths), so
# SHA-256 stays appropriate for them.
function Compare-Stage6-Artifacts {
    $csDir   = Get-StageCsDir 'stage6'
    $snapDir = Get-StageSnapshotDir 'stage6'
    $py = Join-Path $scriptDir 'inspect_parquet.py'
    $allOk = $true
    $details = @()
    foreach ($stem in $selectedStems) {
        # .scores.parquet: content-equality via inspect_parquet.py
        $name = $stem + '.scores.parquet'
        $cPath = Join-Path $csDir   $name
        $sPath = Join-Path $snapDir $name
        if ((Test-Path $cPath) -and (Test-Path $sPath))
        {
            $diffLog = Join-Path $csDir ('diff_' + $stem + '.parquet.log')
            & python $py $sPath -B $cPath --tolerance 0 *>&1 | Tee-Object -FilePath $diffLog | Out-Null
            $exit = $LASTEXITCODE
            $st = if ($exit -eq 0) { 'PASS' } else { 'FAIL' }
            if ($st -eq 'FAIL') { $allOk = $false }
            $details += @{ file=$name; status=$st; log=$diffLog }
        }
        else
        {
            $cExists = Test-Path $cPath
            $sExists = Test-Path $sPath
            if (-not $cExists -and -not $sExists) {
                $details += @{ file=$name; status='PASS'; note='symmetric absence' }
            } else {
                $details += @{ file=$name; status='MISSING';
                    cs_present=$cExists; snap_present=$sExists }
                $allOk = $false
            }
        }

        # FDR sidecars + reconciliation.json: SHA-256 byte equality
        foreach ($suffix in @('.1st-pass.fdr_scores.bin',
                              '.2nd-pass.fdr_scores.bin',
                              '.reconciliation.json')) {
            $name = $stem + $suffix
            $cPath = Join-Path $csDir   $name
            $sPath = Join-Path $snapDir $name
            $cExists = Test-Path $cPath
            $sExists = Test-Path $sPath
            if (-not $cExists -and -not $sExists) {
                $details += @{ file=$name; status='PASS'; note='symmetric absence' }
                continue
            }
            if (-not $cExists -or -not $sExists) {
                $details += @{ file=$name; status='MISSING';
                    cs_present=$cExists; snap_present=$sExists }
                $allOk = $false
                continue
            }
            $cSha = (Get-FileHash $cPath -Algorithm SHA256).Hash
            $sSha = (Get-FileHash $sPath -Algorithm SHA256).Hash
            $st = if ($cSha -eq $sSha) { 'PASS' } else { 'FAIL' }
            if ($st -eq 'FAIL') { $allOk = $false }
            $details += @{ file=$name; status=$st;
                cs_sha=$cSha.Substring(0,12); snap_sha=$sSha.Substring(0,12) }
        }
    }
    return [pscustomobject]@{ ok = $allOk; details = $details }
}

function Compare-Stage7-Snapshot {
    $csDir   = Get-StageCsDir 'stage7'
    $snapDir = Get-StageSnapshotDir 'stage7'
    $cTsv = Join-Path $csDir   'cs_stage7_protein_fdr.tsv'
    $sTsv = Join-Path $snapDir 'cs_stage7_protein_fdr.tsv'
    if ((-not (Test-Path $sTsv)) -or (-not (Test-Path $cTsv))) {
        return [pscustomobject]@{ ok = $false; details = @(@{status='MISSING'; cs=$cTsv; snapshot=$sTsv}) }
    }
    # Same-impl: prefer SHA-256. Compare-Stage7-Crossimpl exists for
    # the cross-impl tolerance comparator; for snapshot mode the
    # tighter byte gate is the right default.
    $cSha = (Get-FileHash $cTsv -Algorithm SHA256).Hash
    $sSha = (Get-FileHash $sTsv -Algorithm SHA256).Hash
    $st = if ($cSha -eq $sSha) { 'PASS' } else { 'FAIL' }
    return [pscustomobject]@{ ok = ($st -eq 'PASS');
        details = @(@{status=$st; cs_sha=$cSha.Substring(0,12); snap_sha=$sSha.Substring(0,12)}) }
}

function Compare-Blib-Snapshot {
    $csDir   = Get-StageCsDir 'blib'
    $snapDir = Get-StageSnapshotDir 'blib'
    $cBlib = Join-Path $csDir   'output.blib'
    $sBlib = Join-Path $snapDir 'output.blib'
    if ((-not (Test-Path $sBlib)) -or (-not (Test-Path $cBlib))) {
        return [pscustomobject]@{ ok = $false; details = @(@{status='MISSING'; cs=$cBlib; snapshot=$sBlib}) }
    }
    # Reuse Compare-Blib-Crossimpl.ps1 with the snapshot path passed
    # as -RustBlib. The comparator does table-level row+column
    # comparison; a same-impl run should pass at exact equality on
    # every table the script checks.
    $diffLog = Join-Path $workRoot 'blib\diff.log'
    & pwsh -File (Join-Path $ospDir 'Compare-Blib-Crossimpl.ps1') -RustBlib $sBlib -CsBlib $cBlib `
        *>&1 | Tee-Object -FilePath $diffLog | Out-Null
    $exit = $LASTEXITCODE
    return [pscustomobject]@{ ok = ($exit -eq 0);
        details = @(@{status=$(if ($exit -eq 0) { 'PASS' } else { 'FAIL' }); log=$diffLog}) }
}

# ----------------------------------------------------------------------
# Snapshot capture (-CreateSnapshot mode)
# ----------------------------------------------------------------------

# Copy a stage's cs outputs into the snapshot dir. Captures both the
# observation dumps (cs_*_<tag>.tsv) and the downstream artifacts
# (parquets, sidecars, reconciliation.json) that the next stage's
# inputs are built from. For stage1to4 also captures the per-file
# .calibration.json (Freeze step needs it for stage5+).
function Capture-Snapshot {
    param([string]$Stage)
    $csDir   = Get-StageCsDir $Stage
    $snapDir = Get-StageSnapshotDir $Stage
    if (Test-Path $snapDir) {
        Get-ChildItem $snapDir -File | Remove-Item -Force
    } else {
        New-Item -ItemType Directory -Path $snapDir -Force | Out-Null
    }
    # Copy all dumps.
    foreach ($p in @('cs_*.tsv', 'cs_*.json')) {
        foreach ($f in (Get-ChildItem $csDir -Filter $p -File -ErrorAction SilentlyContinue)) {
            Copy-Item $f.FullName (Join-Path $snapDir $f.Name) -Force
        }
    }
    # Copy stage-specific artifacts.
    foreach ($p in $downstreamArtifactPatterns) {
        foreach ($f in (Get-ChildItem $csDir -Filter $p -File -ErrorAction SilentlyContinue)) {
            Copy-Item $f.FullName (Join-Path $snapDir $f.Name) -Force
        }
    }
    # Copy .blib for the blib stage.
    if ($Stage -eq 'blib') {
        $blib = Join-Path $csDir 'output.blib'
        if (Test-Path $blib) { Copy-Item $blib (Join-Path $snapDir 'output.blib') -Force }
    }
    # Stage 7's protein FDR dump.
    if ($Stage -eq 'stage7') {
        $tsv = Join-Path $csDir 'cs_stage7_protein_fdr.tsv'
        if (Test-Path $tsv) { Copy-Item $tsv (Join-Path $snapDir 'cs_stage7_protein_fdr.tsv') -Force }
    }
    Write-Host ("  [capture] {0} snapshot updated" -f $Stage) -ForegroundColor DarkCyan
}

# ----------------------------------------------------------------------
# Freeze: stage N -> stage N+1 inputs. Source dir is the snapshot dir
# (the captured baseline is the canonical input for downstream
# stages, regardless of whether we're in capture or compare mode —
# in capture mode we just wrote it).
# ----------------------------------------------------------------------

function Freeze-Stage1to4 {
    $src  = Get-StageSnapshotDir 'stage1to4'
    $next = Get-StageInputDir 'stage5'
    Reset-StageDir $next -KeepInputs:$false
    foreach ($stem in $selectedStems) {
        $pq = Join-Path $src ($stem + '.scores.parquet')
        if (Test-Path $pq) { Copy-Item $pq (Join-Path $next ($stem + '.scores.parquet')) }
        $cal = Join-Path $src ($stem + '.calibration.json')
        if (Test-Path $cal) { Copy-Item $cal (Join-Path $next ($stem + '.calibration.json')) }
    }
    foreach ($mzml in $selectedFiles) {
        $s = Join-Path $inputsDir (Split-Path $mzml -Leaf)
        if (Test-Path $s) { Copy-Item $s (Join-Path $next (Split-Path $mzml -Leaf)) }
    }
    Copy-Item (Join-Path $inputsDir $libraryName) (Join-Path $next $libraryName)
    $cache = Join-Path $inputsDir ($libraryName + '.libcache')
    if (Test-Path $cache) { Copy-Item $cache (Join-Path $next ($libraryName + '.libcache')) }
}

function Freeze-PostStage4 {
    param([string]$FromStage, [string]$ToStage)
    $next = Get-StageInputDir $ToStage
    Reset-StageDir $next -KeepInputs:$false
    $prev = Get-StageInputDir $FromStage
    foreach ($f in (Get-ChildItem $prev -File)) {
        Copy-Item $f.FullName (Join-Path $next $f.Name)
    }
    # Overlay artifacts written by the prior stage from the snapshot.
    $src = Get-StageSnapshotDir $FromStage
    if (Test-Path $src) {
        foreach ($pattern in $downstreamArtifactPatterns) {
            foreach ($f in (Get-ChildItem $src -Filter $pattern -File -ErrorAction SilentlyContinue)) {
                Copy-Item $f.FullName (Join-Path $next $f.Name) -Force
            }
        }
    }
}

# ----------------------------------------------------------------------
# Walk
# ----------------------------------------------------------------------

$results = @()
$fail = $false
$capturedStages = @()

for ($i = $startIdx; $i -le $stopIdx; $i++) {
    $stage = $stageOrder[$i]
    Write-Host ""
    Write-Host ("--- {0} ---" -f $stage) -ForegroundColor Cyan

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

    $runResult = if ($stage -eq 'stage1to4') { Run-Stage1to4 } else { Run-PostStage4 -Stage $stage }

    if ($runResult.exit -ne 0) {
        # Binary failed. Don't capture or freeze — the outputs are
        # incomplete and propagating them would silently corrupt the
        # snapshot and any downstream stage.
        Write-Host ("  [run-fail] {0} exited with code {1}; see {2}\stage{3}\cs\stdout.log" -f `
            $stage, $runResult.exit, $workRoot, $stage) -ForegroundColor Red
        $results += @{ stage = $stage; status = 'RUN_FAIL'; exit = $runResult.exit }
        $fail = $true
        if (-not $Continue) {
            Write-Host ""
            Write-Host ("STOP: {0} run failed; halting." -f $stage) -ForegroundColor Yellow
            break
        }
        continue
    }

    if ($CreateSnapshot) {
        # Capture mode: write cs outputs to snapshot dir, no comparison.
        Capture-Snapshot -Stage $stage
        $capturedStages += $stage
        $results += @{ stage = $stage; status = 'CAPTURED' }
    } else {
        $cmp = switch ($stage) {
            'stage1to4' { Compare-Stage1to4-Snapshot }
            'stage5'    { Compare-DumpSha-Snapshot -Stage 'stage5' }
            'stage6'    {
                # Stage 6 has BOTH dumps and rewritten artifacts; check both.
                $dumpCmp = Compare-DumpSha-Snapshot -Stage 'stage6'
                $artCmp = Compare-Stage6-Artifacts
                [pscustomobject]@{
                    ok = ($dumpCmp.ok -and $artCmp.ok)
                    details = @($dumpCmp.details + $artCmp.details)
                }
            }
            'stage7'    { Compare-Stage7-Snapshot }
            'blib'      { Compare-Blib-Snapshot }
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
    }

    # Freeze for next stage. In capture mode the snapshot was just
    # written; in compare mode it was written previously. Either
    # way the snapshot is the canonical source.
    $shouldFreeze = ($CreateSnapshot -or ($results[-1].status -eq 'PASS')) -and ($i -lt $stopIdx)
    if ($shouldFreeze) {
        $nextStage = $stageOrder[$i + 1]
        if ($stage -eq 'stage1to4') { Freeze-Stage1to4 }
        else                         { Freeze-PostStage4 -FromStage $stage -ToStage $nextStage }
        Write-Host ("  [freeze] inputs prepared for {0}" -f $nextStage) -ForegroundColor DarkGray
    }

    if ((-not $CreateSnapshot) -and $fail -and (-not $Continue)) {
        Write-Host ""
        Write-Host ("STOP: {0} failed; halting march. Iterate with: " -f $stage) -ForegroundColor Yellow
        Write-Host ("  pwsh -File Test-Snapshot.ps1 -StartStage {0} -StopAfterStage {0}" -f $stage) -ForegroundColor Yellow
        break
    }
}

# ----------------------------------------------------------------------
# Snapshot manifest (capture mode only)
# ----------------------------------------------------------------------

if ($CreateSnapshot) {
    $manifest = [ordered]@{
        tag             = $Tag
        dataset         = $Dataset
        files           = [string[]]$selectedStems
        library         = $libraryName
        resolution      = $resolution
        cs_bin          = @{ path = $csBin; sha256 = $csSha }
        source_commit   = $sourceCommit
        source_branch   = $sourceBranch
        captured_stages = [string[]]$capturedStages
        captured_at     = (Get-Date).ToString('o')
    }
    $manifest | ConvertTo-Json -Depth 6 |
        Set-Content -Path (Join-Path $snapshotDir 'manifest.json') -Encoding UTF8
    Write-Host ""
    Write-Host ("Snapshot manifest: {0}" -f (Join-Path $snapshotDir 'manifest.json')) -ForegroundColor DarkCyan
}

# ----------------------------------------------------------------------
# Summary
# ----------------------------------------------------------------------

Write-Host ""
Write-Host "--- Summary ---" -ForegroundColor Cyan
foreach ($r in $results) {
    $color = switch ($r.status) {
        'PASS'      { 'Green' }
        'CAPTURED'  { 'DarkCyan' }
        'FAIL'      { 'Red' }
        default     { 'DarkYellow' }
    }
    Write-Host ("  {0,-10} {1}" -f $r.stage, $r.status) -ForegroundColor $color
}

exit $(if ($fail) { 1 } else { 0 })
