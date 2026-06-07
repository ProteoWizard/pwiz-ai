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

      (OspreySharp CLI; Rust osprey still uses the old --no-join/--join-at-pass flags)
      Stage      CLI extras                                         Exit hook
      ---------  -------------------------------------------------  -----------------------------
      stage1to4  --task PerFileScoring                              (exits after Stage 4)
      stage5     --input-scores <frozen.parquet>                    OSPREY_PERCOLATOR_ONLY=1
      stage6     --input-scores <frozen.parquet>                    OSPREY_STAGE7_PROTEIN_FDR_ONLY=1
      stage7     --task MergeNode --input-scores <frozen.parquet>   OSPREY_STAGE7_PROTEIN_FDR_ONLY=1
      blib       --task MergeNode --input-scores <frozen.parquet>   (none — Stages 7-8 from reconciled)

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
        stage5/     (<tool>_*_<dump>.tsv files; <tool> is cs or rust)
        stage6/     (dumps + reconciled parquet + FDR sidecars +
                     reconciliation.json)
        stage7/     (<tool>_stage7_protein_fdr.tsv)
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

.PARAMETER Tool
    Which implementation to snapshot or compare: CSharp (default,
    OspreySharp.exe at pwiz_tools/OspreySharp/...) or Rust (osprey.exe
    at C:\proj\osprey\target\release\). Same-impl snapshot scope --
    capture once per tool, then compare future runs of the same tool
    against that baseline. Use distinct -Tag values to keep parallel
    CSharp and Rust snapshots without collision (e.g. 'main-cs' and
    'main-rust', or just reuse 'main' under separate tags).

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
    [ValidateSet('Stellar','Astral','AstralLibraryDecoy')]
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

    [string]$TestBaseDir = $null,

    # Same-impl snapshot side: CSharp (OspreySharp.exe) or Rust
    # (osprey.exe from C:\proj\osprey). Default CSharp for backward
    # compatibility with existing tag-less workflows.
    [ValidateSet('CSharp','Rust')]
    [string]$Tool = 'CSharp',

    # Wrap the C# binary in JetBrains dotTrace (Sampling) for the
    # listed stages, save .dtp snapshots under -PerformanceProfileOutputDir.
    # Stage names from the same ValidateSet as StartStage/StopAfterStage.
    # No-op for Tool=Rust (dotTrace is .NET only).
    [ValidateSet('stage1to4','stage5','stage6','stage7','blib')]
    [string[]]$PerformanceProfileStages = @(),

    [string]$PerformanceProfileOutputDir = $null,

    # Sampling is fastest and almost always the right default. Tracing
    # captures per-call timing but is much slower and intrudes on the
    # measured wall time. Timeline adds thread / context data.
    [ValidateSet('Sampling','Tracing','Timeline')]
    [string]$PerformanceProfileType = 'Sampling',

    # Wrap the C# binary in JetBrains dotMemory (Console CLI) for the
    # listed stages, save .dmw workspaces under -MemoryProfileOutputDir.
    # No-op for Tool=Rust. Periodic snapshot trigger + full allocation
    # tracking (--collect-alloc); intended for short-stage runs.
    [ValidateSet('stage1to4','stage5','stage6','stage7','blib')]
    [string[]]$MemoryProfileStages = @(),

    [string]$MemoryProfileOutputDir = $null,

    # Snapshot cadence during the profiled stage. 30s gives ~5 snapshots
    # over a 2:30 Astral stage5 run -- enough to see allocation drift
    # through the parallel SVM training without flooding the workspace.
    [string]$MemoryProfileTimer = '30s',

    [int]$MemoryProfileMaxSnapshots = 10,

    # Production-mode wall measurement: strip OSPREY_DUMP_* env vars from
    # every stage's config so no diagnostic dumps run. *_ONLY exit hooks
    # are preserved so the stage still isolates. Use to get clean
    # production stage5/6/7 wall numbers without diagnostic-write overhead.
    # Implies -Continue (snapshot compare is skipped — production-wall
    # runs intentionally drop the cross-impl artifacts).
    [switch]$NoDumps
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
# Both implementations produce a Windows .exe and a Linux extension-less
# ELF from their respective build systems. -Tool selects which side this
# run targets; the captured snapshot and the workdir are scoped per-tag
# so CSharp and Rust snapshots can coexist (use distinct tags).
$exeSuffix = if ($IsWindows) { '.exe' } else { '' }
switch ($Tool) {
    'CSharp' {
        $toolName        = 'C#'
        $toolPrefix      = 'cs_'      # dump file prefix: cs_*.tsv
        $toolWorkSubdir  = 'cs'       # workdir subdir: <stage>/cs/
        $toolBinName     = "OspreySharp$exeSuffix"
        $toolBin         = Join-Path $projRoot "pwiz\pwiz_tools\OspreySharp\OspreySharp\bin\x64\Release\net8.0\$toolBinName"
        $toolBuildHint   = 'pwsh -File ./ai/scripts/OspreySharp/Build-OspreySharp.ps1 -TargetFramework net8.0'
    }
    'Rust' {
        $toolName        = 'Rust'
        $toolPrefix      = 'rust_'    # dump file prefix: rust_*.tsv
        $toolWorkSubdir  = 'rust'     # workdir subdir: <stage>/rust/
        $toolBinName     = "osprey$exeSuffix"
        $toolBin         = Join-Path $projRoot "osprey\target\release\$toolBinName"
        $toolBuildHint   = 'pwsh -File ./ai/scripts/OspreySharp/Build-OspreyRust.ps1   (or: cd C:\proj\osprey && cargo build --release)'
    }
}
if (-not (Test-Path $toolBin)) {
    Write-Host "[Test-Snapshot] $toolName binary not found: $toolBin" -ForegroundColor Red
    Write-Host "  Build first: $toolBuildHint" -ForegroundColor Yellow
    exit 2
}
$toolSha = (Get-FileHash $toolBin -Algorithm SHA256).Hash.ToLower()

# ----------------------------------------------------------------------
# dotTrace setup (when -PerformanceProfileStages is non-empty)
# ----------------------------------------------------------------------
$dotTraceExe = $null
if ($PerformanceProfileStages.Count -gt 0) {
    if ($Tool -ne 'CSharp') {
        Write-Host "[Test-Snapshot] -PerformanceProfileStages requires -Tool CSharp (dotTrace is .NET only); ignoring." -ForegroundColor Yellow
        $PerformanceProfileStages = @()
    } else {
        # On Linux the global tool installs to ~/.dotnet/tools; on Windows
        # Get-Command picks up either the user .dotnet\tools or PATH.
        $candidate = if ($IsLinux) {
            $p = Join-Path $env:HOME '.dotnet/tools/dottrace'
            if (Test-Path $p) { $p } else { $null }
        } else {
            (Get-Command dottrace -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source) ??
            (Join-Path $env:USERPROFILE '.dotnet\tools\dottrace.exe' | Where-Object { Test-Path $_ })
        }
        if (-not $candidate) {
            Write-Host "[Test-Snapshot] dottrace not found. Install: dotnet tool install --global JetBrains.dotTrace.GlobalTools" -ForegroundColor Red
            exit 2
        }
        $dotTraceExe = $candidate
        if (-not $PerformanceProfileOutputDir) {
            # ai/.tmp is the shared session-artifact directory (per ai/CLAUDE.md).
            $PerformanceProfileOutputDir = Join-Path $projRoot 'ai\.tmp\dottrace'
        }
        if (-not (Test-Path $PerformanceProfileOutputDir)) {
            New-Item -ItemType Directory -Path $PerformanceProfileOutputDir -Force | Out-Null
        }
        Write-Host ("[Test-Snapshot] dotTrace {0} -> {1}" -f $PerformanceProfileType, $PerformanceProfileOutputDir) -ForegroundColor Cyan
        Write-Host ("[Test-Snapshot]   profiled stages: {0}" -f ($PerformanceProfileStages -join ', ')) -ForegroundColor Cyan
    }
}

# ----------------------------------------------------------------------
# dotMemory setup (when -MemoryProfileStages is non-empty)
# ----------------------------------------------------------------------
$dotMemoryExe = $null
if ($MemoryProfileStages.Count -gt 0) {
    if ($Tool -ne 'CSharp') {
        Write-Host "[Test-Snapshot] -MemoryProfileStages requires -Tool CSharp (dotMemory is .NET only); ignoring." -ForegroundColor Yellow
        $MemoryProfileStages = @()
    } elseif (-not $IsWindows) {
        # dotMemory Console exists for Linux but our installer lays it
        # down only on Windows; skip rather than try to find it.
        Write-Host "[Test-Snapshot] -MemoryProfileStages currently wired for Windows only; ignoring." -ForegroundColor Yellow
        $MemoryProfileStages = @()
    } else {
        # Mirror Run-Tests.ps1: prefer ~/.claude-tools/dotMemory then NuGet cache.
        $claudeToolsRoot = Join-Path $env:USERPROFILE ".claude-tools\dotMemory"
        if (Test-Path $claudeToolsRoot) {
            $latest = Get-ChildItem $claudeToolsRoot -Directory | Sort-Object Name -Descending | Select-Object -First 1
            if ($latest) {
                $cand = Join-Path $latest.FullName "tools\dotMemory.exe"
                if (Test-Path $cand) { $dotMemoryExe = $cand }
            }
        }
        if (-not $dotMemoryExe) {
            $nugetCache = Join-Path $env:USERPROFILE ".nuget\packages\jetbrains.dotmemory.console.windows-x64"
            if (Test-Path $nugetCache) {
                $latest = Get-ChildItem $nugetCache -Directory | Sort-Object Name -Descending | Select-Object -First 1
                if ($latest) {
                    $cand = Join-Path $latest.FullName "tools\dotMemory.exe"
                    if (Test-Path $cand) { $dotMemoryExe = $cand }
                }
            }
        }
        if (-not $dotMemoryExe) {
            Write-Host "[Test-Snapshot] dotMemory.exe not found. Install: pwsh -File ./ai/scripts/Install-DotMemory.ps1" -ForegroundColor Red
            exit 2
        }
        if (-not $MemoryProfileOutputDir) {
            $MemoryProfileOutputDir = Join-Path $projRoot 'ai\.tmp\dotmemory'
        }
        if (-not (Test-Path $MemoryProfileOutputDir)) {
            New-Item -ItemType Directory -Path $MemoryProfileOutputDir -Force | Out-Null
        }
        Write-Host ("[Test-Snapshot] dotMemory -> {0}" -f $MemoryProfileOutputDir) -ForegroundColor Cyan
        Write-Host ("[Test-Snapshot]   profiled stages: {0}  timer={1}  max_snapshots={2}" -f `
            ($MemoryProfileStages -join ', '), $MemoryProfileTimer, $MemoryProfileMaxSnapshots) -ForegroundColor Cyan
    }
}

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
# -NoDumps skips compare entirely (production-wall measurement), so the snapshot
# dir is not required for that mode.
if (-not $CreateSnapshot -and -not $NoDumps -and -not (Test-Path $snapshotDir)) {
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
    tool            = $Tool
    tool_bin        = @{ path = $toolBin; sha256 = $toolSha }
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
Write-Host ("Tool:       {0}" -f $toolName)
Write-Host ("Binary:     sha {0}" -f $toolSha.Substring(0,12))
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
function Get-StageToolDir     { param([string]$Stage) Join-Path $workRoot ("$Stage\$toolWorkSubdir") }
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
        [string[]]$CliArgs, [hashtable]$EnvVars,
        [string]$Stage = ''
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
        $shouldMemProfile = ($Stage -ne '') -and ($script:dotMemoryExe) -and
                            ($script:MemoryProfileStages -contains $Stage)
        $shouldProfile = ($Stage -ne '') -and ($script:dotTraceExe) -and
                         ($script:PerformanceProfileStages -contains $Stage) -and
                         (-not $shouldMemProfile)
        if ($shouldMemProfile) {
            $dmwName = "{0}-{1}-{2}-{3}-{4}.dmw" -f $Tool, $Dataset, $Files, $Stage,
                        (Get-Date -Format 'yyyyMMdd-HHmmss')
            $dmwPath = Join-Path $script:MemoryProfileOutputDir $dmwName
            # --trigger-on-activation grabs a baseline at attach;
            # --trigger-timer adds periodic snapshots through the stage;
            # -c enables full per-stack allocation tracking (heavy but
            # exactly the signal we want for GC-pressure analysis).
            $memArgs = @(
                'start',
                '--trigger-on-activation',
                ('--trigger-timer=' + $script:MemoryProfileTimer),
                ('--trigger-max-snapshots=' + $script:MemoryProfileMaxSnapshots),
                '-c',
                ('--save-to-file=' + $dmwPath),
                '--overwrite',
                $Bin,
                '--'
            ) + $CliArgs
            Write-Host ("  [memprofile] dotMemory -> {0}" -f $dmwPath) -ForegroundColor DarkMagenta
            & $script:dotMemoryExe @memArgs *>&1 | Tee-Object -FilePath $logPath | Out-Null
            $exit = $LASTEXITCODE
        } elseif ($shouldProfile) {
            $dtpName = "{0}-{1}-{2}-{3}-{4}.dtp" -f $Tool, $Dataset, $Files, $Stage,
                        (Get-Date -Format 'yyyyMMdd-HHmmss')
            $dtpPath = Join-Path $script:PerformanceProfileOutputDir $dtpName
            # `--` separator stops dottrace's argument parser from
            # consuming `--key=value` items meant for the wrapped binary
            # (e.g. `--task=PerFileScoring` would otherwise be eaten as a
            # dottrace option).
            # Linux JetBrains.dotTrace.GlobalTools 2026.x requires
            # --framework=NetCore to disambiguate Mono vs .NET Core targets;
            # Windows dotTrace 2025.x (current JetBrains Toolbox / Rider
            # build) auto-detects and rejects --framework as unknown.
            $profArgs = @('start')
            if ($IsLinux) { $profArgs += '--framework=NetCore' }
            $profArgs += @(
                ('--profiling-type=' + $script:PerformanceProfileType),
                ('--save-to=' + $dtpPath),
                '--propagate-exit-code',
                '--overwrite',
                $Bin,
                '--'
            ) + $CliArgs
            Write-Host ("  [profile] dottrace -> {0}" -f $dtpPath) -ForegroundColor DarkCyan
            & $script:dotTraceExe @profArgs *>&1 | Tee-Object -FilePath $logPath | Out-Null
            $exit = $LASTEXITCODE
        } else {
            & $Bin @CliArgs *>&1 | Tee-Object -FilePath $logPath | Out-Null
            $exit = $LASTEXITCODE
        }
    } finally {
        Pop-Location
    }
    $sw.Stop()
    return [pscustomobject]@{ exit = $exit; wall = $sw.Elapsed }
}

# ----------------------------------------------------------------------
# Per-stage env + comparator config (shape mirrors Test-Regression.ps1
# but each stage emits $toolPrefix* dumps; the snapshot dir holds the
# captured baseline of those same prefix files plus the artifacts downstream
# stages need.)
# ----------------------------------------------------------------------

$stageConfig = @{
    'stage5' = @{
        envVars = if ($NoDumps) {
            @{ OSPREY_PERCOLATOR_ONLY = '1' }
        } else {
            @{
                OSPREY_DUMP_STANDARDIZER = '1'; OSPREY_DUMP_SUBSAMPLE = '1'
                OSPREY_DUMP_SVM_WEIGHTS  = '1'; OSPREY_DUMP_PERCOLATOR = '1'
                OSPREY_PERCOLATOR_ONLY   = '1'
            }
        }
        # standardizer/subsample/svm_weights stay on SHA-256: they
        # carry no transcendentals, so same-impl runs match bit-for-bit
        # cross-OS. percolator is dispatched separately to the
        # content-tolerance path -- its 6 numeric columns (score, pep,
        # and the 4 q-values) inherit ULP-level libm drift when
        # the underlying scoring pipeline crossed OSes.
        compareDumps = @('standardizer','subsample','svm_weights')
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
# .osprey.task validity sidecars are included so the resume-aware
# gates in PerFileScoring / FirstJoin / PerFileRescore / MergeNode see
# their per-task signals at the next stage boundary instead of seeing
# bare binaries with no metadata to validate.
$downstreamArtifactPatterns = @(
    '*.scores.parquet',
    '*.scores-reconciled.parquet',
    '*.calibration.json',
    '*.1st-pass.fdr_scores.bin',
    '*.2nd-pass.fdr_scores.bin',
    '*.reconciliation.json',
    '*.osprey.task'
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
    $sOut = Get-StageToolDir 'stage1to4'
    Reset-StageDir $sOut -KeepInputs:$false
    foreach ($f in (Get-ChildItem $sIn -File)) {
        Copy-Item $f.FullName (Join-Path $sOut $f.Name)
    }
    $cliArgs = @()
    foreach ($mzml in $selectedFiles) { $cliArgs += '-i'; $cliArgs += (Split-Path $mzml -Leaf) }
    $cliArgs += @('-l', $libraryName, '-o', 'unused.blib',
                  '--resolution', $resolution,
                  '--protein-fdr', '0.01', '--threads', '16')
    # OspreySharp uses --task PerFileScoring for the Stage 1-4 worker;
    # Rust osprey keeps the retired --no-join flag.
    $cliArgs += if ($Tool -eq 'CSharp') { @('--task', 'PerFileScoring') } else { @('--no-join') }
    $r = Invoke-Tool -Bin $toolBin -WorkDir $sOut -CliArgs $cliArgs -EnvVars @{} -Stage 'stage1to4'
    Write-Host ("  [run] {0,-4} stage1to4  exit={1} wall={2:mm\:ss}" -f $toolWorkSubdir, $r.exit, $r.wall) `
        -ForegroundColor $(if ($r.exit -eq 0) { 'DarkGreen' } else { 'DarkRed' })
    return $r
}

# Stage 1-4 comparator: row-aligned content equality via
# inspect_parquet.py --diff. Byte-level equality on the full parquet
# file is unreliable: Parquet.Net's ZSTD compression path
# (IronCompress + ZstdSharp) is non-deterministic at the byte level
# for at least the boolean is_decoy column — same logical data
# compresses to subtly different bytes across same-binary runs (a
# one-byte page-size shift cascades across every subsequent column).
# The LOGICAL data is deterministic same-OS (verified column-by-
# column), so a column-level diff is the right gate. Row order is
# deterministic because RunCoelutionScoring writes per-window
# results into a pre-allocated array indexed by window position,
# then flattens in window-index order (AnalysisPipeline.cs ~line 3592).
#
# Tolerance 1e-6: the 4 median-polish columns (cosine, residual_ratio,
# min_fragment_r2, residual_correlation) inherit ULP-level drift
# (~1e-14 max) from Math.Log / Math.Exp when comparing across OSes,
# because .NET 8 delegates these to the host libm (Linux glibc) vs
# ucrt (Windows). Math.Sqrt is bit-equal cross-OS, so the rest of
# the 37 columns pass exact. The 1e-6 ceiling matches the threshold
# Test-Features.ps1 has used for cross-OS / cross-impl parity since
# the April 2026 net8 migration (TODO-20260418_osprey_sharp_net8.md
# Phase 3, max observed delta 2.2e-13). User sign-off 2026-05-16
# on this WSL parity sprint; if a future change introduces drift
# above 1e-6 the comparator will flag it.
function Compare-Stage1to4-Snapshot {
    $toolDir = Get-StageToolDir 'stage1to4'
    $snapDir = Get-StageSnapshotDir 'stage1to4'
    $py = Join-Path $scriptDir 'inspect_parquet.py'
    $allOk = $true
    $details = @()
    foreach ($stem in $selectedStems) {
        $cPq = Join-Path $toolDir   ($stem + '.scores.parquet')
        $sPq = Join-Path $snapDir ($stem + '.scores.parquet')
        if ((-not (Test-Path $sPq)) -or (-not (Test-Path $cPq))) {
            $details += @{ file=$stem; status='MISSING'; cs=$cPq; snapshot=$sPq }
            $allOk = $false
            continue
        }
        $diffLog = Join-Path $toolDir ('diff_' + $stem + '.log')
        & python $py $sPq -B $cPq --tolerance 1e-6 *>&1 | Tee-Object -FilePath $diffLog | Out-Null
        $exit = $LASTEXITCODE
        $st = if ($exit -eq 0) { 'PASS' } else { 'FAIL' }
        if ($st -eq 'FAIL') { $allOk = $false }
        $details += @{ file=$stem; status=$st; log=$diffLog;
            tool_size=(Get-Item $cPq).Length; snap_size=(Get-Item $sPq).Length }
    }
    return [pscustomobject]@{ ok = $allOk; details = $details }
}

# ----------------------------------------------------------------------
# Generic post-stage4 runner
# ----------------------------------------------------------------------

function Run-PostStage4 {
    param([string]$Stage)
    $sIn  = Get-StageInputDir $Stage
    $sOut = Get-StageToolDir $Stage
    Reset-StageDir $sOut -KeepInputs:$false
    foreach ($f in (Get-ChildItem $sIn -File)) {
        Copy-Item $f.FullName (Join-Path $sOut $f.Name)
    }
    $useJP2 = $stageConfig[$Stage].useJoinAtPass2
    # OspreySharp: pass-2 entry (Stages 7-8 from reconciled parquets) is
    # --task MergeNode; pass-1 entry (Stages 5-8 from scores) is the default
    # pipeline driven purely by --input-scores (no --task). Rust osprey keeps
    # the retired --join-at-pass flags.
    # Type-constrain to [string[]] so the empty-CSharp-pass-1 case stays an
    # array. A bare `$cliArgs = if (...) { ... } else { @() }` would make the
    # else-branch's empty array collapse to $null (scriptblock output drops
    # zero-length arrays), and the first `+=` below would then start STRING
    # concatenation instead of array-append -- jamming every token together
    # (`--input-scoresFILE--input-scores...`), which the binary rejects.
    [string[]]$cliArgs = @()
    if ($Tool -eq 'CSharp') {
        if ($useJP2) { $cliArgs += @('--task', 'MergeNode') }
    } else {
        if ($useJP2) { $cliArgs += '--join-at-pass=2' } else { $cliArgs += '--join-at-pass=1' }
    }
    # The C# --task MergeNode stages (stage7, blib) consume the Stage-6
    # reconciled parquets, not the raw Stage-4 scores: MergeNode rejects a
    # parquet whose osprey.reconciled metadata is 'false'. Before #4261 Stage 6
    # overwrote the raw .scores.parquet in place so the same name carried
    # reconciled data; now the reconciled output is a distinct sibling. Rust's
    # --join-at-pass=2 path is unchanged (it still keys off .scores.parquet).
    $inputScoresSuffix = if ($useJP2 -and $Tool -eq 'CSharp') { '.scores-reconciled.parquet' } else { '.scores.parquet' }
    foreach ($stem in $selectedStems) {
        $cliArgs += '--input-scores'
        $cliArgs += ($stem + $inputScoresSuffix)
    }
    $cliArgs += @('-l', $libraryName, '-o', 'output.blib',
                  '--resolution', $resolution,
                  '--protein-fdr', '0.01', '--threads', '16')
    $env = $stageConfig[$Stage].envVars
    $r = Invoke-Tool -Bin $toolBin -WorkDir $sOut -CliArgs $cliArgs -EnvVars $env -Stage $Stage
    Write-Host ("  [run] {0,-4} {1,-9} exit={2} wall={3:mm\:ss}" -f $toolWorkSubdir, $Stage, $r.exit, $r.wall) `
        -ForegroundColor $(if ($r.exit -eq 0) { 'DarkGreen' } else { 'DarkRed' })
    return $r
}

# Stage 5/6 dump comparator: SHA-256 byte equality on $toolPrefix*_<tag>.tsv
# files (cs_* for CSharp, rust_* for Rust). Both the live run and the
# captured snapshot use the same prefix (snapshot directory holds the
# tool's own captured output); we compare files that share a name
# across the two directories.
function Compare-DumpSha-Snapshot {
    param([string]$Stage)
    $toolDir = Get-StageToolDir $Stage
    $snapDir = Get-StageSnapshotDir $Stage
    $allOk = $true
    $details = @()
    foreach ($tag in $stageConfig[$Stage].compareDumps) {
        $toolFiles   = Get-ChildItem $toolDir   -Filter ("$($toolPrefix)*_{0}.tsv" -f $tag) -File -ErrorAction SilentlyContinue
        $snapFiles = Get-ChildItem $snapDir -Filter ("$($toolPrefix)*_{0}.tsv" -f $tag) -File -ErrorAction SilentlyContinue
        # Symmetric absence (both sides skipped writing this dump) is
        # equivalent agreement. Single-file Stage 6 may legitimately
        # produce no consensus dump; if neither side wrote one, that's
        # not a regression.
        if (-not $toolFiles -and -not $snapFiles) {
            $details += @{ tag=$tag; status='PASS'; note='symmetric absence' }
            continue
        }
        if (-not $toolFiles -or -not $snapFiles) {
            $details += @{ tag=$tag; status='MISSING';
                tool_present=([bool]$toolFiles); snap_present=([bool]$snapFiles) }
            $allOk = $false
            continue
        }
        foreach ($cf in $toolFiles) {
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
                tool_sha=$cSha.Substring(0,12); snap_sha=$sSha.Substring(0,12);
                tool_size=$cf.Length; snap_size=$sf.Length }
        }
    }
    return [pscustomobject]@{ ok = $allOk; details = $details }
}

# Stage 5 percolator dump: content-tolerance comparison via
# Compare-Percolator.ps1 with -Tolerance 1e-6. Same justification as
# Compare-Stage1to4-Snapshot: the 6 numeric columns (score, pep, and
# the 4 q-values) inherit libm-ULP drift cross-OS via Math.Log /
# Math.Exp; 1e-6 is the threshold Test-Features.ps1 uses for cross-OS
# parity and the same ceiling stage1to4 uses on its parquet content
# diff. Row-set parity (file_name, entry_id) is still required exactly
# (Compare-Percolator.ps1 fails if either side has only-in-A or
# only-in-B keys).
function Compare-Percolator-Snapshot {
    $toolDir = Get-StageToolDir 'stage5'
    $snapDir = Get-StageSnapshotDir 'stage5'
    $name = "$($toolPrefix)stage5_percolator.tsv"
    $cTsv = Join-Path $toolDir $name
    $sTsv = Join-Path $snapDir $name
    $cExists = Test-Path $cTsv
    $sExists = Test-Path $sTsv
    if (-not $cExists -and -not $sExists) {
        return [pscustomobject]@{ ok = $true;
            details = @(@{ tag='percolator'; status='PASS'; note='symmetric absence' }) }
    }
    if (-not $cExists -or -not $sExists) {
        return [pscustomobject]@{ ok = $false;
            details = @(@{ tag='percolator'; status='MISSING';
                tool_present=$cExists; snap_present=$sExists;
                tool=$cTsv; snapshot=$sTsv }) }
    }
    # Same-impl snapshot: prefer SHA-256 byte equality. The percolator dump is
    # byte-identical run-to-run on the same impl (confirmed). The tolerance
    # comparator Compare-Percolator.ps1 (now under Compare/archive/) was for the
    # CROSS-impl / cross-OS libm-ULP case; reach for it only if a cross-OS
    # snapshot is ever compared. (Was invoking the moved script at a stale path,
    # which produced a false FAIL on every run.)
    $cSha = (Get-FileHash $cTsv -Algorithm SHA256).Hash
    $sSha = (Get-FileHash $sTsv -Algorithm SHA256).Hash
    $st = if ($cSha -eq $sSha) { 'PASS' } else { 'FAIL' }
    return [pscustomobject]@{ ok = ($st -eq 'PASS');
        details = @(@{ tag='percolator'; file=$name; status=$st;
            tool_sha=$cSha.Substring(0,12); snap_sha=$sSha.Substring(0,12);
            tool_size=(Get-Item $cTsv).Length; snap_size=(Get-Item $sTsv).Length }) }
}

# Stage 6 rewrites .scores.parquet (content-equality via
# inspect_parquet.py to absorb ZSTD compression noise — see
# Compare-Stage1to4-Snapshot for the rationale and the 1e-6 cross-OS
# tolerance justification) and emits FDR sidecars (.1st-pass.fdr_scores.bin,
# .2nd-pass.fdr_scores.bin) plus .reconciliation.json. The sidecars
# and JSON have shown stable byte equality across runs (no
# compression on those paths), so SHA-256 stays appropriate for
# them same-OS; cross-OS results from the same sidecars may also
# drift via libm Math.Log/Exp paths in downstream Stage 6 code,
# which is flagged below at compare time.
function Compare-Stage6-Artifacts {
    $toolDir = Get-StageToolDir 'stage6'
    $snapDir = Get-StageSnapshotDir 'stage6'
    $py = Join-Path $scriptDir 'inspect_parquet.py'
    $allOk = $true
    $details = @()
    foreach ($stem in $selectedStems) {
        # .scores.parquet: content-equality via inspect_parquet.py
        $name = $stem + '.scores.parquet'
        $cPath = Join-Path $toolDir   $name
        $sPath = Join-Path $snapDir $name
        if ((Test-Path $cPath) -and (Test-Path $sPath))
        {
            $diffLog = Join-Path $toolDir ('diff_' + $stem + '.parquet.log')
            & python $py $sPath -B $cPath --tolerance 1e-6 *>&1 | Tee-Object -FilePath $diffLog | Out-Null
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
                    tool_present=$cExists; snap_present=$sExists }
                $allOk = $false
            }
        }

        # FDR sidecars + reconciliation.json: SHA-256 byte equality
        foreach ($suffix in @('.1st-pass.fdr_scores.bin',
                              '.2nd-pass.fdr_scores.bin',
                              '.reconciliation.json')) {
            $name = $stem + $suffix
            $cPath = Join-Path $toolDir   $name
            $sPath = Join-Path $snapDir $name
            $cExists = Test-Path $cPath
            $sExists = Test-Path $sPath
            if (-not $cExists -and -not $sExists) {
                $details += @{ file=$name; status='PASS'; note='symmetric absence' }
                continue
            }
            if (-not $cExists -or -not $sExists) {
                $details += @{ file=$name; status='MISSING';
                    tool_present=$cExists; snap_present=$sExists }
                $allOk = $false
                continue
            }
            $cSha = (Get-FileHash $cPath -Algorithm SHA256).Hash
            $sSha = (Get-FileHash $sPath -Algorithm SHA256).Hash
            $st = if ($cSha -eq $sSha) { 'PASS' } else { 'FAIL' }
            if ($st -eq 'FAIL') { $allOk = $false }
            $details += @{ file=$name; status=$st;
                tool_sha=$cSha.Substring(0,12); snap_sha=$sSha.Substring(0,12) }
        }
    }
    return [pscustomobject]@{ ok = $allOk; details = $details }
}

function Compare-Stage7-Snapshot {
    $toolDir = Get-StageToolDir 'stage7'
    $snapDir = Get-StageSnapshotDir 'stage7'
    $cTsv = Join-Path $toolDir   "$($toolPrefix)stage7_protein_fdr.tsv"
    $sTsv = Join-Path $snapDir "$($toolPrefix)stage7_protein_fdr.tsv"
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
        details = @(@{status=$st; tool_sha=$cSha.Substring(0,12); snap_sha=$sSha.Substring(0,12)}) }
}

function Compare-Blib-Snapshot {
    $toolDir = Get-StageToolDir 'blib'
    $snapDir = Get-StageSnapshotDir 'blib'
    $cBlib = Join-Path $toolDir   'output.blib'
    $sBlib = Join-Path $snapDir 'output.blib'
    if ((-not (Test-Path $sBlib)) -or (-not (Test-Path $cBlib))) {
        return [pscustomobject]@{ ok = $false; details = @(@{status='MISSING'; cs=$cBlib; snapshot=$sBlib}) }
    }
    # Reuse Compare-Blib-Crossimpl.ps1 with the snapshot path passed
    # as -RustBlib. The comparator does table-level row+column
    # comparison; a same-impl run should pass at exact equality on
    # every table the script checks.
    $diffLog = Join-Path $workRoot 'blib\diff.log'
    # Compare-Blib-Crossimpl.ps1 lives under Compare/ (was invoked at a stale
    # top-level path, producing a false FAIL on every run).
    & pwsh -File (Join-Path (Join-Path $ospDir 'Compare') 'Compare-Blib-Crossimpl.ps1') -RustBlib $sBlib -CsBlib $cBlib `
        *>&1 | Tee-Object -FilePath $diffLog | Out-Null
    $exit = $LASTEXITCODE
    return [pscustomobject]@{ ok = ($exit -eq 0);
        details = @(@{status=$(if ($exit -eq 0) { 'PASS' } else { 'FAIL' }); log=$diffLog}) }
}

# ----------------------------------------------------------------------
# Snapshot capture (-CreateSnapshot mode)
# ----------------------------------------------------------------------

# Copy a stage's cs outputs into the snapshot dir. Captures both the
# observation dumps ($toolPrefix*_<tag>.tsv) and the downstream artifacts
# (parquets, sidecars, reconciliation.json) that the next stage's
# inputs are built from. For stage1to4 also captures the per-file
# .calibration.json (Freeze step needs it for stage5+).
function Capture-Snapshot {
    param([string]$Stage)
    $toolDir = Get-StageToolDir $Stage
    $snapDir = Get-StageSnapshotDir $Stage
    if (Test-Path $snapDir) {
        Get-ChildItem $snapDir -File | Remove-Item -Force
    } else {
        New-Item -ItemType Directory -Path $snapDir -Force | Out-Null
    }
    # Copy all dumps.
    foreach ($p in @("$($toolPrefix)*.tsv", "$($toolPrefix)*.json")) {
        foreach ($f in (Get-ChildItem $toolDir -Filter $p -File -ErrorAction SilentlyContinue)) {
            Copy-Item $f.FullName (Join-Path $snapDir $f.Name) -Force
        }
    }
    # Copy stage-specific artifacts.
    foreach ($p in $downstreamArtifactPatterns) {
        foreach ($f in (Get-ChildItem $toolDir -Filter $p -File -ErrorAction SilentlyContinue)) {
            Copy-Item $f.FullName (Join-Path $snapDir $f.Name) -Force
        }
    }
    # Copy .blib for the blib stage.
    if ($Stage -eq 'blib') {
        $blib = Join-Path $toolDir 'output.blib'
        if (Test-Path $blib) { Copy-Item $blib (Join-Path $snapDir 'output.blib') -Force }
    }
    # Stage 7's protein FDR dump.
    if ($Stage -eq 'stage7') {
        $tsv = Join-Path $toolDir "$($toolPrefix)stage7_protein_fdr.tsv"
        if (Test-Path $tsv) { Copy-Item $tsv (Join-Path $snapDir "$($toolPrefix)stage7_protein_fdr.tsv") -Force }
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

    if ($NoDumps) {
        # Production-wall measurement: no dumps -> nothing to compare.
        # Record the wall time and move on.
        $results += @{ stage = $stage; status = 'WALL_ONLY';
                       wall = $runResult.wall.ToString() }
    } elseif ($CreateSnapshot) {
        # Capture mode: write cs outputs to snapshot dir, no comparison.
        Capture-Snapshot -Stage $stage
        $capturedStages += $stage
        $results += @{ stage = $stage; status = 'CAPTURED' }
    } else {
        $cmp = switch ($stage) {
            'stage1to4' { Compare-Stage1to4-Snapshot }
            'stage5'    {
                # SHA-256 on standardizer/subsample/svm_weights (no
                # transcendentals -> bit-equal cross-OS); content-tolerance
                # on percolator (6 numeric cols inherit libm ULP drift
                # cross-OS via Math.Log/Exp). 1e-6 ceiling matches the
                # stage1to4 parquet gate, justified at the same place.
                $dumpCmp = Compare-DumpSha-Snapshot -Stage 'stage5'
                $percCmp = Compare-Percolator-Snapshot
                [pscustomobject]@{
                    ok = ($dumpCmp.ok -and $percCmp.ok)
                    details = @($dumpCmp.details + $percCmp.details)
                }
            }
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
        tool            = $Tool
        tool_bin        = @{ path = $toolBin; sha256 = $toolSha }
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
