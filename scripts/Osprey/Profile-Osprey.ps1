<#
.SYNOPSIS
    Profile Osprey with dotTrace to identify performance hot spots.

.DESCRIPTION
    Runs Osprey under JetBrains dotTrace CLI profiler on Stellar or Astral
    data, captures a performance snapshot (.dtp), generates an XML report, and
    displays the top hot spots by own time and total time.

    -Stage controls the early-exit gate (matches Bench-Scoring.ps1):
      Calibration (1-3) | Scoring (1-4) | Full

.PARAMETER Dataset
    Which test dataset: Stellar or Astral (default: Stellar)

.PARAMETER Stage
    Pipeline stages to profile: Calibration (Stage 1-3),
    Scoring (Stage 1-4, default), or Full pipeline.

.PARAMETER ProfilingType
    dotTrace profiling type: Sampling (default, low overhead) or Timeline (detailed)

.PARAMETER OutputPath
    Path for the .dtp snapshot file (default: ai/.tmp/osprey-profile-<timestamp>.dtp)

.PARAMETER TopN
    Number of top hot spots to display (default: 20)

.PARAMETER MaxWindows
    Cap the number of isolation windows scored in Stage 4. Sets
    OSPREY_MAX_SCORING_WINDOWS. Use small values (1-2) for fast iteration
    on Astral profiling cycles.

.PARAMETER ScopeToMainSearch
    Drive dotTrace via the API so the .dtp snapshot contains only the
    main-search loop (bracketed by ProfilerHooks.Start/SaveAndStop).
    Requires Osprey to be built with the JetBrains.Profiler.Api
    reference.

.PARAMETER MemoryProfile
    Retention mode. Drive JetBrains dotMemory (Console CLI) instead of
    dotTrace and emit a .dmw workspace, with snapshots captured at
    Osprey's forced-GC memory boundaries (perfile-scored-live for
    single-file scoring; stage5-start-live / first-pass-fdr-live /
    reconciliation-floor for multi-file joins). Answers "what is being
    HELD and who holds it", the complement to the printf [MEM ...]
    sizing layer. Forces net8.0 (the memory-run runtime) unless
    -TargetFramework is given, and requires dotMemory installed via
    ai/scripts/Install-DotMemory.ps1. This is a SCOPED diagnosis run --
    NOT the full 82-file / 6-8 h batch, which stays the [MEM ...]
    layer's job. Emits the workspace and stops; open it in the dotMemory
    GUI for retention paths / dominators (human-in-the-loop).

.EXAMPLE
    .\Profile-Osprey.ps1
    Profile Stellar Stages 1-4 with sampling, show top 20 hot spots

.PARAMETER TrackAllocations
    Allocation-traffic variant of -MemoryProfile. Drives dotMemory with
    -c (collect allocations) instead of --use-api, so the workspace shows
    WHAT ALLOCATES the transient managed peak (traffic by type + method) --
    the complement to the retention snapshot's "what is held". Allocation
    tracking is heavy, so it forces a small -MaxWindows default (the
    allocator ranking is representative even at a few windows).

.EXAMPLE
    .\Profile-Osprey.ps1 -Dataset Astral -MemoryProfile
    Retention profile of ONE Astral file through Stage 1-4 scoring under
    dotMemory; open the .dmw and read the 'perfile-scored-live' snapshot
    to see what one file's scoring holds resident.

.EXAMPLE
    .\Profile-Osprey.ps1 -Dataset Astral -MemoryProfile -TrackAllocations
    Allocation-traffic profile of ONE Astral file (auto-capped windows);
    open the .dmw's Memory Allocations view to name the types/methods
    churning the transient managed peak.

.EXAMPLE
    .\Profile-Osprey.ps1 -Dataset Astral -Stage Calibration
    Profile Astral Stages 1-3 (calibration only)

.EXAMPLE
    .\Profile-Osprey.ps1 -Dataset Astral -ScopeToMainSearch -MaxWindows 2
    Profile Astral main-search with API-controlled scope, only 2 windows
    (fast iteration for Stage 4 bottleneck hunting).

.EXAMPLE
    .\Profile-Osprey.ps1 -ProfilingType Timeline -TopN 30
    Timeline profiling with top 30 hot spots
#>
param(
    [ValidateSet("Stellar", "Astral")]
    [string]$Dataset = "Stellar",

    [ValidateSet("Calibration", "Scoring", "Full")]
    [string]$Stage = "Scoring",

    [ValidateSet("Sampling", "Timeline")]
    [string]$ProfilingType = "Sampling",

    [string]$OutputPath = "",

    [int]$TopN = 20,

    # Cap the number of isolation windows scored in Stage 4. When > 0,
    # sets OSPREY_MAX_SCORING_WINDOWS so Astral profiling doesn't need the
    # full ~15 min wall-clock to produce a representative snapshot.
    [int]$MaxWindows = 0,

    # When set, drives dotTrace via the API: the profiler attaches but
    # does not start collecting until Osprey's ProfilerHooks.Start-
    # Measure bracket around the main-search loop. Produces a snapshot
    # that contains only Stage 4, not calibration + setup.
    [switch]$ScopeToMainSearch,

    # Retention mode: drive dotMemory instead of dotTrace to answer
    # "what is being HELD in memory" (retention paths / dominators),
    # not "where is time spent". Emits a .dmw workspace with snapshots
    # taken at Osprey's forced-GC memory boundaries (via ProfilerHooks),
    # then stops for a human to read in the dotMemory GUI. A SCOPED
    # diagnosis run (single file / small subset), NOT the full batch.
    [switch]$MemoryProfile,

    # Allocation-tracking variant of -MemoryProfile: drive dotMemory with
    # -c (collect allocations) instead of --use-api, so the workspace shows
    # WHAT ALLOCATES the transient managed peak (memory traffic by type +
    # method), the complement to the retention snapshot's "what is held".
    # Allocation tracking is heavy, so this forces a small -MaxWindows
    # default; the allocator RANKING is representative even at a few windows.
    [switch]$TrackAllocations,

    [ValidateSet("net472", "net8.0")]
    [string]$TargetFramework = "net472"
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Load dataset configuration for parity with Bench-Scoring.ps1
. "$PSScriptRoot\Dataset-Config.ps1"
$ds = Get-DatasetConfig $Dataset

$testDir = $ds.TestDir
if (-not (Test-Path $testDir)) {
    Write-Error "Test data directory not found: $testDir"
    exit 1
}

$mzml = Join-Path $testDir $ds.SingleFile
$library = Join-Path $testDir $ds.Library
$tempBlib = Join-Path $testDir "_profile_output.blib"
$csharpBin = Get-OspreyExe -Framework $TargetFramework

$scriptRoot = Split-Path -Parent $PSCommandPath
$aiRoot = Split-Path -Parent (Split-Path -Parent $scriptRoot)
$aiTmpDir = Join-Path $aiRoot ".tmp"

# -----------------------------------------------------------------------------
# Retention mode (-MemoryProfile): drive dotMemory instead of dotTrace.
#
# Answers "what is being HELD, and how much of the per-file peak is live vs
# uncollected garbage", NOT "where is time spent". Osprey's ProfilerHooks take a
# dotMemory snapshot at every forced-GC memory boundary (perfile-scored-live for
# the single-file scoring envelope; stage5-start-live / first-pass-fdr-live /
# reconciliation-floor for multi-file joins) when OSPREY_LOG_MEMORY is set AND a
# --use-api dotMemory session is attached -- both of which this block turns on.
# The paired [MEM ...] lines print the pre-GC working_set/managed peak (the
# sawtooth crest) next to the post-GC floor (the live set), so the crest-vs-floor
# gap separates retention from GC heap-growth churn.
#
# SCOPED diagnosis run only -- a single file (memory is stable file-to-file, so
# one file captures the whole envelope). NOT the full 82-file / 6-8 h batch,
# which stays the printf [MEM ...] layer's job (see osprey-development-guide.md).
# Emits the .dmw and stops for a human to open in the dotMemory GUI.
# -----------------------------------------------------------------------------
if ($MemoryProfile) {
    # net8.0 is the memory-run runtime (Server GC + the net8.0-only GCMemoryInfo
    # fields the [MEM ...] lines print); force it unless the caller was explicit.
    if (-not $PSBoundParameters.ContainsKey('TargetFramework')) {
        $TargetFramework = 'net8.0'
    }
    $csharpBin = Get-OspreyExe -Framework $TargetFramework
    if (-not (Test-Path $csharpBin)) {
        Write-Error "Osprey ($TargetFramework) not built: $csharpBin"
        exit 1
    }

    $dotMemoryExe = Get-DotMemoryExe
    if (-not $dotMemoryExe) {
        Write-Host (Get-DotMemoryInstallHint) -ForegroundColor Red
        exit 1
    }

    # Allocation tracking (-c) intercepts every allocation and is far heavier
    # than snapshot mode, so cap the scoring windows unless the caller was
    # explicit -- the allocator RANKING is representative even at a few windows.
    if ($TrackAllocations -and $MaxWindows -le 0) {
        $MaxWindows = 6
        Write-Host "  (-TrackAllocations defaulting -MaxWindows 6 to keep -c tractable)" -ForegroundColor DarkGray
    }

    if ([string]::IsNullOrEmpty($OutputPath)) {
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        if (-not (Test-Path $aiTmpDir)) { New-Item -ItemType Directory -Path $aiTmpDir -Force | Out-Null }
        $dmwPrefix = if ($TrackAllocations) { "osprey-alloc" } else { "osprey-memory" }
        $OutputPath = Join-Path $aiTmpDir "$dmwPrefix-$timestamp.dmw"
    }

    # Cold, quiet start: same score-cache clean + diagnostic-env clear the
    # dotTrace path uses below.
    $patterns = @("*.scores.parquet", "*.calibration.json", "*.spectra.bin",
                  "*.fdr_scores.bin", "_profile_output*")
    foreach ($p in $patterns) {
        Get-ChildItem -Path $testDir -Filter $p -ErrorAction SilentlyContinue | Remove-Item -Force
    }
    $diagVars = @('OSPREY_DUMP_CAL_MATCH','OSPREY_CAL_MATCH_ONLY','OSPREY_DUMP_LDA_SCORES',
        'OSPREY_LDA_SCORES_ONLY','OSPREY_DUMP_LOESS_INPUT','OSPREY_LOESS_INPUT_ONLY',
        'OSPREY_DIAG_SEARCH_ENTRY_IDS','OSPREY_DIAG_MP_SCAN','OSPREY_DIAG_XCORR_SCAN',
        'OSPREY_LOAD_CALIBRATION')
    foreach ($v in $diagVars) { Remove-Item "Env:$v" -ErrorAction SilentlyContinue }

    # OSPREY_LOG_MEMORY arms both the [MEM ...] boundary probes AND the paired
    # ProfilerHooks.CaptureRetentionSnapshot calls.
    $env:OSPREY_LOG_MEMORY = "1"
    $env:RUST_LOG = "info"
    if ($MaxWindows -gt 0) { $env:OSPREY_MAX_SCORING_WINDOWS = "$MaxWindows" }

    # Single file through Stage 1-4 scoring (the per-file envelope) unless -Stage
    # overrides; Calibration/Full behave as in the dotTrace path.
    $memAppArgs = @("-i", $mzml, "-l", $library, "-o", $tempBlib, "--resolution", $ds.Resolution)
    switch ($Stage) {
        "Calibration" { $env:OSPREY_EXIT_AFTER_CALIBRATION = "1" }
        "Scoring"     { $memAppArgs += @("--task", "PerFileScoring") }
    }

    if ($TrackAllocations) {
        # -c collects the allocation call tree (memory traffic). It is mutually
        # exclusive with --use-api, so the in-process boundary snapshots do not
        # fire in this mode; --trigger-on-activation grabs a baseline and the
        # timer adds periodic snapshots whose diff shows what was allocated.
        $dotMemoryArgs = @(
            "start",
            "-c",
            "--trigger-on-activation",
            "--trigger-timer=20s",
            "--trigger-max-snapshots=10",
            "--save-to-file=$OutputPath",
            "--overwrite",
            $csharpBin, "--") + $memAppArgs
    }
    else {
        # --use-api: snapshots are driven by MemoryProfiler.GetSnapshot in-process
        # (ProfilerHooks), not a wall-clock timer, so they land exactly on the
        # forced-GC memory boundaries.
        $dotMemoryArgs = @(
            "start",
            "--use-api",
            "--save-to-file=$OutputPath",
            "--overwrite",
            $csharpBin, "--") + $memAppArgs
    }

    $modeLabel = if ($TrackAllocations) { "Allocation Traffic" } else { "Retention" }
    Write-Host ""
    Write-Host "Osprey Memory $modeLabel Profile (dotMemory)" -ForegroundColor Yellow
    Write-Host "  Dataset: $($ds.Name) ($($ds.Resolution)), file: $($ds.SingleFile)" -ForegroundColor Gray
    $scopeNote = if ($MaxWindows -gt 0) { "$Stage, max_windows=$MaxWindows" } else { $Stage }
    Write-Host "  Runtime: $TargetFramework   Scope: $scopeNote" -ForegroundColor Gray
    Write-Host "  Workspace: $OutputPath" -ForegroundColor Gray
    Write-Host "  NOTE: scoped single-file diagnosis run -- NOT the full 82-file batch." -ForegroundColor DarkGray
    Write-Host ""

    $savedLoc = Get-Location
    Set-Location $testDir
    $runNote = if ($TrackAllocations) { "allocation tracking (-c); heavier, hence -MaxWindows" } else { "snapshots at forced-GC memory boundaries" }
    Write-Host "Running under dotMemory ($runNote)..." -ForegroundColor Cyan
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    & $dotMemoryExe @dotMemoryArgs
    $exitCode = $LASTEXITCODE
    $sw.Stop()
    Set-Location $savedLoc

    Remove-Item Env:OSPREY_LOG_MEMORY -ErrorAction SilentlyContinue
    Remove-Item Env:OSPREY_EXIT_AFTER_CALIBRATION -ErrorAction SilentlyContinue
    Remove-Item Env:OSPREY_MAX_SCORING_WINDOWS -ErrorAction SilentlyContinue
    Remove-Item Env:RUST_LOG -ErrorAction SilentlyContinue
    if (Test-Path $tempBlib) { Remove-Item $tempBlib -Force -ErrorAction SilentlyContinue }

    Write-Host ""
    Write-Host "dotMemory run completed in $($sw.Elapsed.TotalSeconds.ToString('F1'))s (exit code: $exitCode)" -ForegroundColor $(if ($exitCode -eq 0) { "Green" } else { "Red" })
    if (-not (Test-Path $OutputPath)) {
        Write-Host "Workspace file not created: $OutputPath" -ForegroundColor Red
        exit 1
    }
    $dmwSize = (Get-Item $OutputPath).Length / 1MB
    Write-Host "Workspace: $OutputPath ($($dmwSize.ToString('F1')) MB)" -ForegroundColor Gray
    Write-Host ""
    if ($TrackAllocations) {
        Write-Host "Next (human-in-the-loop allocation-traffic read):" -ForegroundColor Cyan
        Write-Host "  1. Open the workspace in the dotMemory GUI: $OutputPath" -ForegroundColor Gray
        Write-Host "  2. Open the Memory Allocations / traffic view (diff a later snapshot vs baseline)." -ForegroundColor Gray
        Write-Host "  3. Sort by Bytes Allocated, group by Type then by allocating method." -ForegroundColor Gray
        Write-Host "  4. The top types/methods are the churn behind the transient managed peak;" -ForegroundColor Gray
        Write-Host "     pool/reuse those to lower the orange line without a GC-config trade-off." -ForegroundColor Gray
    }
    else {
        Write-Host "Next (human-in-the-loop retention read):" -ForegroundColor Cyan
        Write-Host "  1. Open the workspace in the dotMemory GUI: $OutputPath" -ForegroundColor Gray
        Write-Host "  2. Select the 'perfile-scored-live' snapshot (single file's post-GC live set)." -ForegroundColor Gray
        Write-Host "  3. Biggest Retained Types / Dominators -> what is holding the heap." -ForegroundColor Gray
        Write-Host "  4. Retention paths on the top objects -> who holds them (the reference chain)." -ForegroundColor Gray
        Write-Host "  Compare the snapshot's live size against the paired pre-GC [MEM ...] working_set" -ForegroundColor Gray
        Write-Host "  peak above: a big gap = GC heap-growth churn (allocate less); a small gap = live" -ForegroundColor Gray
        Write-Host "  retention (hold less)." -ForegroundColor Gray
    }
    Write-Host ""
    exit $exitCode
}

# Verify tools
$dotTraceExe = Get-Command "dottrace" -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty Source
if (-not $dotTraceExe) {
    Write-Host "dottrace not found. Install: dotnet tool install --global JetBrains.dotTrace.GlobalTools" -ForegroundColor Red
    exit 1
}

# Find Reporter.exe
$reporterExe = $null
$jetBrainsDir = Join-Path $env:LOCALAPPDATA "JetBrains\Installations"
if (Test-Path $jetBrainsDir) {
    $dirs = @(
        (Get-ChildItem -Path $jetBrainsDir -Directory -Filter "dotTrace*" -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending | Select-Object -First 1),
        (Get-ChildItem -Path $jetBrainsDir -Directory -Filter "ReSharperPlatform*" -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending | Select-Object -First 1)
    )
    foreach ($d in $dirs) {
        if ($d) {
            $rp = Join-Path $d.FullName "Reporter.exe"
            if (Test-Path $rp) { $reporterExe = $rp; break }
        }
    }
}

# Output path
if ([string]::IsNullOrEmpty($OutputPath)) {
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    if (-not (Test-Path $aiTmpDir)) { New-Item -ItemType Directory -Path $aiTmpDir -Force | Out-Null }
    $OutputPath = Join-Path $aiTmpDir "osprey-profile-$timestamp.dtp"
}

# Clean score caches (keep library cache for warm Stage 1 comparison)
$patterns = @("*.scores.parquet", "*.calibration.json", "*.spectra.bin",
              "*.fdr_scores.bin", "_profile_output*")
foreach ($p in $patterns) {
    Get-ChildItem -Path $testDir -Filter $p -ErrorAction SilentlyContinue |
        Remove-Item -Force
}

# Set up environment
$env:RUST_LOG = "info"
# Calibration uses an env var (no CLI analog yet); Scoring uses
# --task PerFileScoring (Stages 1-4, replaces the retired
# OSPREY_EXIT_AFTER_SCORING env var). Full sets neither.
$extraAppArgs = @()
switch ($Stage) {
    "Calibration" { $env:OSPREY_EXIT_AFTER_CALIBRATION = "1" }
    "Scoring"     { $extraAppArgs += @("--task", "PerFileScoring") }
}
if ($MaxWindows -gt 0) { $env:OSPREY_MAX_SCORING_WINDOWS = "$MaxWindows" }

# Clear diagnostic env vars
$diagVars = @('OSPREY_DUMP_CAL_MATCH','OSPREY_CAL_MATCH_ONLY','OSPREY_DUMP_LDA_SCORES',
    'OSPREY_LDA_SCORES_ONLY','OSPREY_DUMP_LOESS_INPUT','OSPREY_LOESS_INPUT_ONLY',
    'OSPREY_DIAG_SEARCH_ENTRY_IDS','OSPREY_DIAG_MP_SCAN','OSPREY_DIAG_XCORR_SCAN',
    'OSPREY_LOAD_CALIBRATION')
foreach ($v in $diagVars) { Remove-Item "Env:$v" -ErrorAction SilentlyContinue }

# Build dotTrace command
$appArgs = @("-i", $mzml, "-l", $library, "-o", $tempBlib, "--resolution", $ds.Resolution) + $extraAppArgs

$dotTraceArgs = @(
    "start",
    "--profiling-type=$ProfilingType",
    "--save-to=$OutputPath",
    "--overwrite",
    "--propagate-exit-code"
)
if ($ScopeToMainSearch) {
    # Use API mode: Osprey's ProfilerHooks.StartMeasure /
    # SaveAndStopMeasure brackets the main-search loop, so the .dtp
    # snapshot contains only Stage 4 timing.
    $dotTraceArgs += @("--use-api", "--collect-data-from-start=off")
}
$dotTraceArgs += @($csharpBin, "--") + $appArgs

$scopeLabel = switch ($Stage) {
    "Calibration" { "Stages 1-3 (calibration only)" }
    "Scoring"     { "Stages 1-4 (calibration + main search)" }
    "Full"        { "Full pipeline" }
}

Write-Host ""
Write-Host "Osprey Performance Profile" -ForegroundColor Yellow
Write-Host "  Dataset: $($ds.Name) ($($ds.Resolution))" -ForegroundColor Gray
Write-Host "  Profiling type: $ProfilingType" -ForegroundColor Gray
Write-Host "  Scope: $scopeLabel" -ForegroundColor Gray
Write-Host "  Snapshot: $OutputPath" -ForegroundColor Gray
Write-Host ""

$savedLoc = Get-Location
Set-Location $testDir

Write-Host "Running under dotTrace..." -ForegroundColor Cyan
$sw = [System.Diagnostics.Stopwatch]::StartNew()
& $dotTraceExe @dotTraceArgs
$exitCode = $LASTEXITCODE
$sw.Stop()

Set-Location $savedLoc

# Cleanup
Remove-Item Env:OSPREY_EXIT_AFTER_CALIBRATION -ErrorAction SilentlyContinue
Remove-Item Env:OSPREY_MAX_SCORING_WINDOWS -ErrorAction SilentlyContinue
Remove-Item Env:RUST_LOG -ErrorAction SilentlyContinue
if (Test-Path $tempBlib) { Remove-Item $tempBlib -Force -ErrorAction SilentlyContinue }

Write-Host ""
Write-Host "Profiling completed in $($sw.Elapsed.TotalSeconds.ToString('F1'))s (exit code: $exitCode)" -ForegroundColor $(if ($exitCode -eq 0) { "Green" } else { "Red" })

if (-not (Test-Path $OutputPath)) {
    Write-Host "Snapshot file not created" -ForegroundColor Red
    exit 1
}

$snapshotSize = (Get-Item $OutputPath).Length / 1MB
Write-Host "Snapshot: $OutputPath ($($snapshotSize.ToString('F1')) MB)" -ForegroundColor Gray

# Generate XML report
if ($reporterExe) {
    $patternFile = Join-Path $aiTmpDir "dottrace-osprey-pattern.xml"
    if (-not (Test-Path $patternFile)) {
        @"
<Patterns>
  <Pattern PrintCallstacks="Full">pwiz\.Osprey\..*</Pattern>
  <Pattern PrintCallstacks="Full">pwiz\.Osprey\.Scoring\..*</Pattern>
  <Pattern PrintCallstacks="Full">pwiz\.Osprey\.Chromatography\..*</Pattern>
  <Pattern PrintCallstacks="Full">pwiz\.Osprey\.ML\..*</Pattern>
  <Pattern PrintCallstacks="Full">pwiz\.Osprey\.FDR\..*</Pattern>
  <Pattern PrintCallstacks="Full">pwiz\.Osprey\.IO\..*</Pattern>
  <Pattern PrintCallstacks="Full">pwiz\.Osprey\.Core\..*</Pattern>
</Patterns>
"@ | Out-File -FilePath $patternFile -Encoding UTF8
    }

    $reportFile = $OutputPath -replace '\.dtp$', '-report.xml'
    Write-Host ""
    Write-Host "Generating XML report..." -ForegroundColor Cyan
    & $reporterExe report $OutputPath --pattern=$patternFile --save-to=$reportFile --overwrite 2>&1 | Out-Null

    if (Test-Path $reportFile) {
        Write-Host "Report: $reportFile" -ForegroundColor Gray

        try {
            [xml]$report = Get-Content $reportFile
            $allFunctions = $report.Report.Function

            # Top N by OwnTime (where the CPU actually spends time)
            $byOwnTime = $allFunctions |
                Where-Object { $_.FQN -like "pwiz.Osprey*" } |
                Sort-Object { [double]$_.OwnTime } -Descending |
                Select-Object -First $TopN

            if ($byOwnTime) {
                Write-Host ""
                Write-Host "Top $TopN Hot Spots by OWN TIME (pwiz.Osprey.*):" -ForegroundColor Yellow
                Write-Host ("{0,-70} {1,10} {2,10}" -f "Method", "Own (ms)", "Total (ms)")
                Write-Host ("{0,-70} {1,10} {2,10}" -f ("-"*70), ("-"*10), ("-"*10))
                foreach ($fn in $byOwnTime) {
                    $name = $fn.FQN -replace '^pwiz\.Osprey\.', ''
                    if ($name.Length -gt 70) { $name = $name.Substring(0, 67) + "..." }
                    $own = [math]::Round([double]$fn.OwnTime, 0)
                    $total = [math]::Round([double]$fn.TotalTime, 0)
                    Write-Host ("{0,-70} {1,10} {2,10}" -f $name, $own, $total)
                }
            }

            # Top N by TotalTime (call tree perspective)
            $byTotalTime = $allFunctions |
                Where-Object { $_.FQN -like "pwiz.Osprey*" } |
                Sort-Object { [double]$_.TotalTime } -Descending |
                Select-Object -First $TopN

            if ($byTotalTime) {
                Write-Host ""
                Write-Host "Top $TopN Hot Spots by TOTAL TIME (pwiz.Osprey.*):" -ForegroundColor Yellow
                Write-Host ("{0,-70} {1,10} {2,10}" -f "Method", "Total (ms)", "Own (ms)")
                Write-Host ("{0,-70} {1,10} {2,10}" -f ("-"*70), ("-"*10), ("-"*10))
                foreach ($fn in $byTotalTime) {
                    $name = $fn.FQN -replace '^pwiz\.Osprey\.', ''
                    if ($name.Length -gt 70) { $name = $name.Substring(0, 67) + "..." }
                    $own = [math]::Round([double]$fn.OwnTime, 0)
                    $total = [math]::Round([double]$fn.TotalTime, 0)
                    Write-Host ("{0,-70} {1,10} {2,10}" -f $name, $own, $total)
                }
            }
        }
        catch {
            Write-Host "(Could not parse report: $($_.Exception.Message))" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "Reporter.exe did not generate report" -ForegroundColor Yellow
    }
}
else {
    Write-Host ""
    Write-Host "To analyze:" -ForegroundColor Cyan
    Write-Host "  1. Open dotTrace GUI" -ForegroundColor Gray
    Write-Host "  2. File > Open > $OutputPath" -ForegroundColor Gray
    Write-Host "  3. Analyze hot spots and call tree" -ForegroundColor Gray
}

Write-Host ""
