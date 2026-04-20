<#
.SYNOPSIS
    Ground-truth Stages 1-4 scoring benchmark for Osprey performance and
    memory. Compares upstream Rust, fork Rust, and OspreySharp C# on Stellar
    or Astral data.

.DESCRIPTION
    For each implementation:
      1. Warmup / cold run (no library cache, not timed in medians)
      2. N timed iterations (clean score caches between runs, keep library cache)
      3. Report median per-stage timing AND median peak RSS with consistency check

    Peak RSS is reported on every run (polled 500 ms via Process.WorkingSet64).
    Timing and memory are always shown together: a "faster" implementation that
    pays for its speed with ballooning memory is not actually faster.

    Fork Rust and C# exit after Stage 4 via OSPREY_EXIT_AFTER_SCORING.
    Upstream Rust runs full pipeline; Stage 1-4 timing extracted from log
    timestamps (memory peak is from the full pipeline, which is usually
    dominated by the scoring stage anyway).

    C# does not have a binary library cache. Its Stage 1 always includes TSV parsing.
    Rust Stage 1 uses the library cache after warmup.

    In multi-file mode (-Files All), all 3 mzML files are passed to each tool.
    C# processes files in parallel (Parallel.For); Rust processes them sequentially.
    Per-stage breakdowns are not shown in multi-file mode because C# overlaps stages
    across files. Only wall-clock total, peak RSS, and entries are reported.

    An optional -BaselineBin adds a 4th measurement row, labeled with
    -BaselineLabel, for A/B comparison (e.g. origin/main vs a proposed branch
    during PR validation).

.PARAMETER Dataset
    Which test dataset: Stellar or Astral (default: Stellar)

.PARAMETER Files
    Which mzML files to benchmark: Single (first file only) or All (all 3).
    Default: Single. Use All to measure parallel file processing.

.PARAMETER Iterations
    Number of timed iterations per tool (default: 3)

.PARAMETER SkipUpstream
    Skip the upstream Rust (osprey-mm) benchmark.

.PARAMETER SkipFork
    Skip the fork Rust (osprey) benchmark.

.PARAMETER SkipRust
    Skip both Rust benchmarks (C# and optional baseline still run).

.PARAMETER SkipCSharp
    Skip the OspreySharp (C#) run. Useful when comparing two Rust binaries
    (PR validation) and C# numbers aren't needed in the same session.

.PARAMETER BaselineBin
    Optional extra binary to measure (for A/B comparison). Empty = skip.

.PARAMETER BaselineLabel
    Label for the -BaselineBin row (default: "Baseline")

.PARAMETER BaselineType
    Rust or CSharp. Determines how the baseline output is parsed and whether
    library cache is available. Default: Rust.
#>
param(
    [ValidateSet("Stellar", "Astral")]
    [string]$Dataset = "Stellar",
    [ValidateSet("Single", "All")]
    [string]$Files = "Single",
    [ValidateSet("Calibration", "Scoring")]
    [string]$Stage = "Scoring",
    [int]$Iterations = 3,
    [switch]$SkipUpstream = $false,
    [switch]$SkipFork = $false,
    [switch]$SkipRust = $false,
    [switch]$SkipCSharp = $false,
    # 1 = strictly sequential, N>1 = up to N files at once, 0 = default.
    # Applies only to C# (Rust always sequential).
    [int]$MaxParallelFiles = 0,
    [string]$BaselineBin = "",
    [string]$BaselineLabel = "Baseline",
    [ValidateSet("Rust", "CSharp")]
    [string]$BaselineType = "Rust",
    [ValidateSet("net472", "net8.0")]
    [string]$TargetFramework = "net472"
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Load dataset configuration
. "$PSScriptRoot\Dataset-Config.ps1"
$ds = Get-DatasetConfig $Dataset

$testDir = $ds.TestDir
if (-not (Test-Path $testDir)) {
    Write-Error "Test data directory not found: $testDir"
    exit 1
}

$library = Join-Path $testDir $ds.Library
$tempBlib = Join-Path $testDir "_bench_output.blib"

$upstreamBin = "C:\proj\osprey-mm\target\release\osprey.exe"
$forkBin = "C:\proj\osprey\target\release\osprey.exe"
$csharpBin = "C:\proj\pwiz\pwiz_tools\OspreySharp\OspreySharp\bin\x64\Release\$TargetFramework\OspreySharp.exe"

# Build mzML file list based on -Files parameter
$mzmlFiles = if ($Files -eq "Single") {
    @(Join-Path $testDir $ds.SingleFile)
} else {
    $ds.AllFiles | ForEach-Object { Join-Path $testDir $_ }
}
foreach ($f in $mzmlFiles) {
    if (-not (Test-Path $f)) {
        Write-Error "mzML file not found: $f"
        exit 1
    }
}
$multiFile = $Files -eq "All"
$fileCount = $mzmlFiles.Count

# Build common args: -i file1 [-i file2 -i file3] -l library -o output --resolution <res>
$commonArgs = @()
foreach ($f in $mzmlFiles) { $commonArgs += @("-i", $f) }
$commonArgs += @("-l", $library, "-o", $tempBlib, "--resolution", $ds.Resolution,
                 "--protein-fdr", "0.01")

function Clean-ScoreCaches {
    # Clean score/calibration caches but NOT library cache (.libcache)
    $patterns = @("*.scores.parquet", "*.calibration.json", "*.spectra.bin",
                  "*.fdr_scores.bin", "_bench_output*", "osprey_*.log")
    foreach ($p in $patterns) {
        Get-ChildItem -Path $testDir -Filter $p -ErrorAction SilentlyContinue |
            Remove-Item -Force
    }
}

function Clean-ScoreCachesAndLibCache {
    Clean-ScoreCaches
    Get-ChildItem -Path $testDir -Filter "*.libcache" -ErrorAction SilentlyContinue |
        Remove-Item -Force
}

function Clean-AllCaches {
    Clean-ScoreCaches
    Get-ChildItem -Path $testDir -Filter "*.libcache" -ErrorAction SilentlyContinue |
        Remove-Item -Force
}

function Clear-DiagEnv {
    $vars = @('OSPREY_DUMP_CAL_MATCH','OSPREY_CAL_MATCH_ONLY','OSPREY_DUMP_LDA_SCORES',
        'OSPREY_LDA_SCORES_ONLY','OSPREY_DUMP_LOESS_INPUT','OSPREY_LOESS_INPUT_ONLY',
        'OSPREY_DIAG_SEARCH_ENTRY_IDS','OSPREY_DIAG_MP_SCAN','OSPREY_DIAG_XCORR_SCAN',
        'OSPREY_LOAD_CALIBRATION','OSPREY_EXIT_AFTER_SCORING')
    foreach ($v in $vars) { Remove-Item "Env:$v" -ErrorAction SilentlyContinue }
}

function Run-Once {
    param([string]$Binary, [string[]]$ToolArgs, [bool]$EarlyExit, [bool]$IsCSharp = $false)

    $savedLoc = Get-Location
    Set-Location $testDir
    Clear-DiagEnv
    $env:RUST_LOG = "info"
    if ($EarlyExit) {
        switch ($Stage) {
            "Calibration" { $env:OSPREY_EXIT_AFTER_CALIBRATION = "1" }
            "Scoring"     { $env:OSPREY_EXIT_AFTER_SCORING = "1" }
        }
    }
    # File-level parallelism override (C# only).
    if ($IsCSharp -and $MaxParallelFiles -gt 0) {
        $env:OSPREY_MAX_PARALLEL_FILES = "$MaxParallelFiles"
    }

    # Start-Process gives us a Process handle to poll WorkingSet64 in real
    # time. Stdout and stderr are redirected to temp files so the output
    # survives for Parse-*Stages. Using ai/.tmp keeps the scratch under the
    # project-conventional temp dir.
    $tmpOut = [System.IO.Path]::GetTempFileName()
    $tmpErr = [System.IO.Path]::GetTempFileName()

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $proc = Start-Process -FilePath $Binary `
        -ArgumentList $ToolArgs `
        -PassThru -NoNewWindow `
        -RedirectStandardOutput $tmpOut `
        -RedirectStandardError $tmpErr

    $maxRss = 0L
    while (-not $proc.HasExited) {
        try {
            $proc.Refresh()
            $rss = $proc.WorkingSet64
            if ($rss -gt $maxRss) { $maxRss = $rss }
        } catch {}
        Start-Sleep -Milliseconds 500
    }
    $proc.WaitForExit()
    $sw.Stop()

    # Merge stdout + stderr for the parsers (RUST_LOG output goes to stderr).
    $output = @()
    $output += Get-Content $tmpOut -ErrorAction SilentlyContinue
    $output += Get-Content $tmpErr -ErrorAction SilentlyContinue
    Remove-Item $tmpOut, $tmpErr -Force -ErrorAction SilentlyContinue

    Remove-Item Env:OSPREY_EXIT_AFTER_SCORING -ErrorAction SilentlyContinue
    Remove-Item Env:OSPREY_EXIT_AFTER_CALIBRATION -ErrorAction SilentlyContinue
    Remove-Item Env:OSPREY_MAX_PARALLEL_FILES -ErrorAction SilentlyContinue
    Set-Location $savedLoc

    $lines = @($output | ForEach-Object { $_.ToString() })
    $peakMB = [int][math]::Round($maxRss / 1MB, 0)
    return @{
        Lines   = $lines
        WallSec = $sw.Elapsed.TotalSeconds
        Exit    = $proc.ExitCode
        PeakMB  = $peakMB
    }
}

function Parse-RustStages {
    param([string[]]$Lines, [double]$WallClock = 0, [bool]$MultiFile = $false)

    if ($MultiFile) {
        # Multi-file: just collect total entries and wall clock
        $totalEntries = 0
        foreach ($line in $Lines) {
            if ($line -match 'Scored (\d+) entries') {
                $totalEntries += [int]$Matches[1]
            }
        }
        if ($totalEntries -eq 0) { return $null }
        return @{
            S1 = 0; S2 = 0; S3 = 0; S4 = 0
            Thru4 = $WallClock
            Entries = $totalEntries
        }
    }

    # Single-file: parse per-stage timestamps
    $t = @{}
    foreach ($line in $Lines) {
        if ($line -match '^\[(\d+):(\d+)\]\s+(.+)') {
            $sec = [int]$Matches[1] * 60 + [int]$Matches[2]
            $msg = $Matches[3]
            if ($msg -match 'Total library size:')          { $t['s1'] = $sec }
            if ($msg -match 'Loaded \d+ MS2 spectra')       { $t['s2'] = $sec }
            if ($msg -match 'Calibration: \d+ peptides')    { $t['s3'] = $sec }
            if ($msg -match 'Scored (\d+) entries\s+\(.*\)\s+for\s+') {
                $t['s4'] = $sec
                $t['entries'] = [int]$Matches[1]
            }
        }
    }
    if (-not $t.ContainsKey('s1') -or -not $t.ContainsKey('s4')) { return $null }
    # All durations are derived from 1-second stage markers. S1 = timestamp of
    # the first library-size marker (start of Stage 2 begins here). S2/S3/S4
    # are inter-marker durations.
    # Stg 1-4 Total is ALWAYS the Stage 4 marker timestamp -- never wall
    # clock -- so that tools which don't honor OSPREY_EXIT_AFTER_SCORING
    # (running S5 FDR + reconciliation + blib after S4) still report the
    # correct Stage 1-4 time. The caller can compare Thru4 to Wall to detect
    # that the tool did not early-exit (post-S4 overhead).
    $s1 = [double]$t['s1']
    $s2 = [double]($t['s2'] - $t['s1'])
    $s3 = [double]($t['s3'] - $t['s2'])
    $s4 = [double]($t['s4'] - $t['s3'])
    return @{
        S1 = $s1
        S2 = $s2; S3 = $s3; S4 = $s4
        Thru4 = [double]$t['s4']
        Entries = $t['entries']
    }
}

function Parse-CSharpStages {
    param([string[]]$Lines, [double]$WallClock = 0, [bool]$MultiFile = $false)

    if ($MultiFile) {
        # Multi-file: C# runs files in parallel, so per-stage times overlap.
        # Sum entries across files, use wall clock for total.
        $totalEntries = 0
        foreach ($line in $Lines) {
            if ($line -match '\[TIMING\]\s+Coelution scoring:\s+[\d.]+s.*\((\d+) candidates') {
                $totalEntries += [int]$Matches[1]
            }
        }
        if ($totalEntries -eq 0) { return $null }
        return @{
            S1 = 0; S2 = 0; S3 = 0; S4 = 0
            Thru4 = $WallClock
            Entries = $totalEntries
        }
    }

    # Single-file: parse per-stage timing
    $p = @{}
    foreach ($line in $Lines) {
        if ($line -match '\[TIMING\]\s+Library loading \+ decoys:\s+([\d.]+)s')             { $p['s1'] = [double]$Matches[1] }
        if ($line -match '\[TIMING\]\s+mzML parsing:\s+([\d.]+)s')                          { $p['s2'] = [double]$Matches[1] }
        if ($line -match '\[TIMING\]\s+RT calibration:\s+([\d.]+)s')                        { $p['s3'] = [double]$Matches[1] }
        if ($line -match '\[TIMING\]\s+Coelution scoring:\s+([\d.]+)s.*\((\d+) candidates') { $p['s4'] = [double]$Matches[1]; $p['entries'] = [int]$Matches[2] }
        if ($line -match '\[TIMING\]\s+Calibration pass 1 scoring:\s+([\d.]+)s')            { $p['cal_p1'] = [double]$Matches[1] }
        if ($line -match '\[TIMING\]\s+Calibration pass 2 scoring:\s+([\d.]+)s')            { $p['cal_p2'] = [double]$Matches[1] }
    }
    if (-not $p.ContainsKey('s1') -or -not $p.ContainsKey('s4')) { return $null }
    return @{
        S1 = $p['s1']; S2 = $p['s2']; S3 = $p['s3']; S4 = $p['s4']
        Thru4 = $p['s1'] + $p['s2'] + $p['s3'] + $p['s4']
        Entries = $p['entries']
        CalP1 = if ($p.ContainsKey('cal_p1')) { $p['cal_p1'] } else { 0 }
        CalP2 = if ($p.ContainsKey('cal_p2')) { $p['cal_p2'] } else { 0 }
    }
}

function Median {
    param([double[]]$Values)
    # Floor-based index: PowerShell's [int] uses banker's rounding
    # (1.5 -> 2), which picks the max for length-3 instead of the middle.
    $s = $Values | Sort-Object
    $s[[int][Math]::Floor($s.Count / 2)]
}

function Run-Benchmark {
    param([string]$Label, [string]$Binary, [bool]$EarlyExit, [string]$Type)
    $isCSharp = ($Type -ne "Rust")

    Write-Host ""
    Write-Host ("=" * 78) -ForegroundColor Cyan
    Write-Host "  $Label" -ForegroundColor Cyan
    Write-Host ("=" * 78) -ForegroundColor Cyan

    # Cold run: no library cache, measures true Stage 1 cold time
    Write-Host "  Cold (no lib cache)..." -ForegroundColor Gray -NoNewline
    Clean-AllCaches
    $coldRun = Run-Once $Binary $commonArgs $EarlyExit $isCSharp
    if ($coldRun.Exit -ne 0) {
        Write-Host " FAILED (exit $($coldRun.Exit))" -ForegroundColor Red
        return $null
    }
    $coldStages = if ($Type -eq "Rust") { Parse-RustStages $coldRun.Lines $coldRun.WallSec $multiFile }
                  else { Parse-CSharpStages $coldRun.Lines $coldRun.WallSec $multiFile }
    $coldS1 = if ($null -ne $coldStages -and -not $multiFile) { $coldStages.S1 } else { 0 }
    if ($multiFile) {
        Write-Host " $($coldRun.WallSec.ToString('F1'))s peak=$($coldRun.PeakMB)MB" -ForegroundColor Gray
    } else {
        Write-Host " $($coldRun.WallSec.ToString('F1'))s peak=$($coldRun.PeakMB)MB (S1_cold=$($coldS1.ToString('F1')))" -ForegroundColor Gray
    }

    # Early-exit sanity check: if OSPREY_EXIT_AFTER_SCORING was requested
    # but wall clock is materially longer than the Stage 4 marker, this
    # binary didn't honor the exit env var (older main, pre-PR#9). Warn so
    # the user rebuilds with the 1-line patch -- without it the Stg 1-4
    # Total still reports correctly (from the S4 marker) but the wall-clock
    # tail skews any bench that uses WallSec for anything (e.g. a custom
    # harness that ignores Parse-RustStages).
    if ($EarlyExit -and $Type -eq "Rust" -and $null -ne $coldStages -and -not $multiFile) {
        $tail = $coldRun.WallSec - $coldStages.Thru4
        if ($tail -gt 10.0) {
            Write-Host "  WARNING: binary ran $($tail.ToString('F1'))s past Stage 4 marker -- OSPREY_EXIT_AFTER_SCORING ignored (rebuild with PR#9 or the 1-line exit patch for clean comparisons)" -ForegroundColor Yellow
        }
    }

    # Timed iterations (library cache warm after cold run)
    $runs = @()
    for ($iter = 1; $iter -le $Iterations; $iter++) {
        Write-Host "  Run $iter/$Iterations (warm cache)..." -ForegroundColor Gray -NoNewline
        Clean-ScoreCaches
        $result = Run-Once $Binary $commonArgs $EarlyExit $isCSharp
        if ($result.Exit -ne 0) {
            Write-Host " FAILED" -ForegroundColor Red
            continue
        }

        $stages = if ($Type -eq "Rust") { Parse-RustStages $result.Lines $result.WallSec $multiFile }
                  else { Parse-CSharpStages $result.Lines $result.WallSec $multiFile }
        if ($null -eq $stages) {
            Write-Host " parse error" -ForegroundColor Red
            continue
        }
        $stages['Wall'] = $result.WallSec
        $stages['PeakMB'] = $result.PeakMB
        $runs += $stages
        if ($multiFile) {
            Write-Host " $($result.WallSec.ToString('F1'))s peak=$($result.PeakMB)MB ($($stages.Entries.ToString('N0')) entries)" -ForegroundColor Gray
        } else {
            Write-Host " $($result.WallSec.ToString('F1'))s peak=$($result.PeakMB)MB (S1=$($stages.S1) S2=$($stages.S2) S3=$($stages.S3.ToString('F1')) S4=$($stages.S4.ToString('F1')))" -ForegroundColor Gray
        }
    }

    if ($runs.Count -lt 1) {
        Write-Host "  No successful runs" -ForegroundColor Red
        return $null
    }

    # Compute medians
    $med = @{
        Label = $Label
        S1Cold = if ($multiFile) { $coldRun.WallSec } else { $coldS1 }
        S1 = Median ($runs | ForEach-Object { $_.S1 })
        S2 = Median ($runs | ForEach-Object { $_.S2 })
        S3 = Median ($runs | ForEach-Object { $_.S3 })
        S4 = Median ($runs | ForEach-Object { $_.S4 })
        Thru4 = Median ($runs | ForEach-Object { $_.Thru4 })
        Wall = Median ($runs | ForEach-Object { $_.Wall })
        PeakColdMB = $coldRun.PeakMB
        PeakMB = [int](Median ([double[]]($runs | ForEach-Object { $_.PeakMB })))
        Entries = $runs[0].Entries
        HasLibCache = ($Type -eq "Rust")
    }

    # Consistency check: flag if max/min ratio > 1.20 for any stage
    $checkKeys = if ($multiFile) { @('Thru4') } else { @('S1','S2','S3','S4','Thru4') }
    foreach ($key in $checkKeys) {
        $vals = @($runs | ForEach-Object { $_[$key] })
        $mn = ($vals | Measure-Object -Minimum).Minimum
        $mx = ($vals | Measure-Object -Maximum).Maximum
        if ($mn -gt 0 -and ($mx / $mn) -gt 1.20) {
            Write-Host "  WARNING: $key varies by $( (($mx/$mn - 1) * 100).ToString('F0') )% across runs ($(($vals | ForEach-Object { $_.ToString('F1') }) -join ', '))" -ForegroundColor Yellow
        }
    }

    return $med
}

# ===========================================================================
$dsFileLabel = $ds.FileLabel[$Files]
$fileLabel = if ($multiFile) { "$($ds.Name) $fileCount files ($dsFileLabel)" } else { "$($ds.Name) $dsFileLabel" }
$modeLabel = if ($multiFile) { "C# parallel, Rust sequential" } else { "per-stage breakdown" }
Write-Host ""
Write-Host "Osprey Scoring Benchmark: Stages 1-4" -ForegroundColor Yellow
Write-Host "$fileLabel | --resolution unit | $Iterations iterations | median reported" -ForegroundColor Gray
Write-Host "Mode: $modeLabel" -ForegroundColor Gray
Write-Host "Library cache: warm (Rust), cold (C# - no binary cache)" -ForegroundColor Gray
Write-Host ""

$results = @()

if (-not $SkipUpstream -and -not $SkipRust) {
    $results += Run-Benchmark "Upstream Rust (maccoss/osprey)" $upstreamBin $true "Rust"
}
if (-not $SkipFork -and -not $SkipRust) {
    $results += Run-Benchmark "Fork Rust (brendanx67/osprey)" $forkBin $true "Rust"
}
if ($BaselineBin) {
    if (Test-Path $BaselineBin) {
        $results += Run-Benchmark $BaselineLabel $BaselineBin $true $BaselineType
    } else {
        Write-Host "BaselineBin not found: $BaselineBin" -ForegroundColor Yellow
    }
}
if (-not $SkipCSharp) {
    $results += Run-Benchmark "OspreySharp (C#)" $csharpBin $true "CSharp"
}

# ===========================================================================
# Results table
# ===========================================================================

Write-Host ""
Write-Host ("=" * 90) -ForegroundColor Yellow
Write-Host "  MEDIAN Stages 1-4 Timing ($Iterations iterations each)" -ForegroundColor Yellow
Write-Host ("=" * 90) -ForegroundColor Yellow
Write-Host ""

if ($multiFile) {
    # Multi-file table: wall clock + peak RSS + entries only (per-stage not meaningful with parallel C#)
    $fmtM = "{0,-40} {1,10} {2,10} {3,10} {4,12}"
    Write-Host ($fmtM -f "Implementation", "Cold", "Warm", "Peak RSS", "Entries")
    Write-Host ("{0,-40} {1} {2} {3} {4}" -f ("-"*40), ("-"*10), ("-"*10), ("-"*10), ("-"*12))

    foreach ($r in $results) {
        if ($null -eq $r) { continue }
        $coldf = "$($r.S1Cold.ToString('F1'))s"
        $warmf = "$($r.Thru4.ToString('F1'))s"
        $peakf = "$($r.PeakMB) MB"
        $ent = $r.Entries.ToString("N0")
        Write-Host ($fmtM -f $r.Label, $coldf, $warmf, $peakf, $ent)
    }

    # Ratio row
    $rustRef = $results | Where-Object { $_ -ne $null -and $_.Label -match "Upstream|Fork" } | Select-Object -First 1
    $csharp = $results | Where-Object { $_ -ne $null -and $_.Label -match "C#" } | Select-Object -First 1
    if ($rustRef -and $csharp) {
        $shortName = $rustRef.Label -replace '\s*\(.*',''
        $ratioLabel = "C# / $shortName ratio"
        $rc = "$( ($csharp.S1Cold / [Math]::Max($rustRef.S1Cold, 0.5)).ToString('F2') )x"
        $rw = "$( ($csharp.Thru4 / [Math]::Max($rustRef.Thru4, 0.5)).ToString('F2') )x"
        $rm = "$( ($csharp.PeakMB / [Math]::Max($rustRef.PeakMB, 1.0)).ToString('F2') )x"
        Write-Host ""
        Write-Host ($fmtM -f $ratioLabel, $rc, $rw, $rm, "")
    }

    Write-Host ""
    Write-Host "Notes:" -ForegroundColor Gray
    Write-Host "  Cold: no library cache, all tools parse TSV from scratch" -ForegroundColor Gray
    Write-Host "  Warm: library cache present (.libcache for Rust)" -ForegroundColor Gray
    Write-Host "  Peak RSS: max Process.WorkingSet64, polled at 500 ms (median across warm runs)" -ForegroundColor Gray
    Write-Host "  C# processes $fileCount files in parallel (Parallel.For); Rust is sequential" -ForegroundColor Gray
    Write-Host "  All times are wall clock (per-stage not shown - C# overlaps stages across files)" -ForegroundColor Gray
    Write-Host ""
} else {
    # Single-file table: full per-stage breakdown + peak memory
    $fmt = "{0,-40} {1,8} {2,8} {3,8} {4,8} {5,8}   {6,8} {7,10} {8,10}"
    Write-Host ($fmt -f "", "Stage 1", "Stage 1", "Stage 2", "Stage 3", "Stage 4", "Stg 1-4", "Peak RSS", "Entries")
    Write-Host ($fmt -f "Implementation", "Library", "Cached", "mzML", "Calibr.", "Search", "Total", "(MB)", "Scored")
    Write-Host ("{0,-40} {1} {2} {3} {4} {5}   {6} {7} {8}" -f ("-"*40), ("-"*8), ("-"*8), ("-"*8), ("-"*8), ("-"*8), ("-"*8), ("-"*10), ("-"*10))

    foreach ($r in $results) {
        if ($null -eq $r) { continue }
        $s1cf = "$($r.S1Cold.ToString('F1'))s"
        $s1wf = if ($r.HasLibCache) { "$($r.S1.ToString('F1'))s" } else { "n/a" }
        $s2f = "$($r.S2.ToString('F1'))s"
        $s3f = "$($r.S3.ToString('F1'))s"
        $s4f = "$($r.S4.ToString('F1'))s"
        $thf = "$($r.Thru4.ToString('F1'))s"
        $peakf = "$($r.PeakMB)"
        $ent = $r.Entries.ToString("N0")
        Write-Host ($fmt -f $r.Label, $s1cf, $s1wf, $s2f, $s3f, $s4f, $thf, $peakf, $ent)
    }

    # Ratio row (C# vs first Rust result)
    $rustRef = $results | Where-Object { $_ -ne $null -and $_.Label -match "Upstream|Fork" } | Select-Object -First 1
    $csharp = $results | Where-Object { $_ -ne $null -and $_.Label -match "C#" } | Select-Object -First 1
    if ($rustRef -and $csharp) {
        $shortName = $rustRef.Label -replace '\s*\(.*',''
        $ratioLabel = "C# / $shortName ratio"
        $r1c = "$( ($csharp.S1Cold / [Math]::Max($rustRef.S1Cold, 0.5)).ToString('F1') )x"
        $r1w = if ($rustRef.HasLibCache) { "n/a" } else { "n/a" }
        $r2 = "$( ($csharp.S2 / [Math]::Max($rustRef.S2, 0.5)).ToString('F1') )x"
        $r3 = "$( ($csharp.S3 / [Math]::Max($rustRef.S3, 0.5)).ToString('F1') )x"
        $r4 = "$( ($csharp.S4 / [Math]::Max($rustRef.S4, 0.5)).ToString('F1') )x"
        $rt = "$( ($csharp.Thru4 / [Math]::Max($rustRef.Thru4, 0.5)).ToString('F1') )x"
        $rm = "$( ($csharp.PeakMB / [Math]::Max($rustRef.PeakMB, 1.0)).ToString('F2') )x"
        Write-Host ""
        Write-Host ($fmt -f $ratioLabel, $r1c, $r1w, $r2, $r3, $r4, $rt, $rm, "")
    }

    Write-Host ""
    Write-Host "Notes:" -ForegroundColor Gray
    Write-Host "  Stage 1 'Library': cold (no .libcache), all tools parse TSV from scratch" -ForegroundColor Gray
    Write-Host "  Stage 1 'Cached': warm (.libcache present); n/a = no binary cache implemented" -ForegroundColor Gray
    Write-Host "  Stg 1-4 Total = Stage 4 marker timestamp (not wall clock) -- correct even if" -ForegroundColor Gray
    Write-Host "    the binary ignores OSPREY_EXIT_AFTER_SCORING and continues into S5+" -ForegroundColor Gray
    Write-Host "  Peak RSS: max Process.WorkingSet64 polled at 500 ms (MB, median across warm runs)" -ForegroundColor Gray
    Write-Host "  All Rust per-stage times have +/-0.5s rounding (1s timestamp resolution)" -ForegroundColor Gray
    Write-Host ""
}

# Cleanup
Clean-ScoreCaches
Remove-Item Env:RUST_LOG -ErrorAction SilentlyContinue
