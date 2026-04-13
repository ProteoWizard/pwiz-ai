<#
.SYNOPSIS
    Ground-truth Stages 1-4 scoring benchmark for Osprey performance optimization.
    Compares upstream Rust, fork Rust, and OspreySharp C# on Stellar file 20.

.DESCRIPTION
    For each implementation:
      1. Warmup run (creates library cache, not timed)
      2. Three timed iterations (clean score caches between runs, keep library cache)
      3. Report median per-stage timing with consistency check

    Fork Rust and C# exit after Stage 4 via OSPREY_EXIT_AFTER_SCORING.
    Upstream Rust runs full pipeline; Stage 1-4 timing extracted from log timestamps.

    C# does not have a binary library cache. Its Stage 1 always includes TSV parsing.
    Rust Stage 1 uses the library cache after warmup.

.PARAMETER Iterations
    Number of timed iterations per tool (default: 3)

.PARAMETER SkipUpstream
    Skip the upstream Rust benchmark (saves ~6 min)
#>
param(
    [int]$Iterations = 3,
    [switch]$SkipUpstream = $false
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$testDir = "D:\test\osprey-runs\stellar"
$mzml = Join-Path $testDir "Ste-2024-12-02_HeLa_4mz_sDIA_400-900_20.mzML"
$library = Join-Path $testDir "hela-filtered-SkylineAI_spectral_library.tsv"
$tempBlib = Join-Path $testDir "_bench_output.blib"

$upstreamBin = "C:\proj\osprey-mm\target\release\osprey.exe"
$forkBin = "C:\proj\osprey\target\release\osprey.exe"
$csharpBin = "C:\proj\pwiz\pwiz_tools\OspreySharp\OspreySharp\bin\x64\Release\pwiz.OspreySharp.exe"

$commonArgs = @("-i", $mzml, "-l", $library, "-o", $tempBlib, "--resolution", "unit")

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
    param([string]$Binary, [string[]]$ToolArgs, [bool]$EarlyExit)

    $savedLoc = Get-Location
    Set-Location $testDir
    Clear-DiagEnv
    $env:RUST_LOG = "info"
    if ($EarlyExit) { $env:OSPREY_EXIT_AFTER_SCORING = "1" }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $output = & $Binary @ToolArgs 2>&1
    $exitCode = $LASTEXITCODE
    $sw.Stop()

    Remove-Item Env:OSPREY_EXIT_AFTER_SCORING -ErrorAction SilentlyContinue
    Set-Location $savedLoc

    $lines = @($output | ForEach-Object { $_.ToString() })
    return @{ Lines = $lines; WallSec = $sw.Elapsed.TotalSeconds; Exit = $exitCode }
}

function Parse-RustStages {
    param([string[]]$Lines, [double]$WallClock = 0)
    $t = @{}
    foreach ($line in $Lines) {
        if ($line -match '^\[(\d+):(\d+)\]\s+(.+)') {
            $sec = [int]$Matches[1] * 60 + [int]$Matches[2]
            $msg = $Matches[3]
            if ($msg -match 'Total library size:')          { $t['s1'] = $sec }
            if ($msg -match 'Loaded \d+ MS2 spectra')       { $t['s2'] = $sec }
            if ($msg -match 'Calibration: \d+ peptides')    { $t['s3'] = $sec }
            if ($msg -match 'Scored (\d+) entries.*for Ste') {
                $t['s4'] = $sec
                $t['entries'] = [int]$Matches[1]
            }
        }
    }
    if (-not $t.ContainsKey('s1') -or -not $t.ContainsKey('s4')) { return $null }
    # Rust timestamps have 1s resolution. S2/S3/S4 are derived from timestamp diffs.
    # S1 is derived from wall clock minus S2+S3+S4 for sub-second accuracy.
    $s2 = [double]($t['s2'] - $t['s1'])
    $s3 = [double]($t['s3'] - $t['s2'])
    $s4 = [double]($t['s4'] - $t['s3'])
    $s234 = $s2 + $s3 + $s4
    $s1 = if ($WallClock -gt 0) { [Math]::Max($WallClock - $s234, 0.0) } else { [double]$t['s1'] }
    return @{
        S1 = $s1
        S2 = $s2; S3 = $s3; S4 = $s4
        Thru4 = if ($WallClock -gt 0) { $WallClock } else { [double]$t['s4'] }
        Entries = $t['entries']
    }
}

function Parse-CSharpStages {
    param([string[]]$Lines)
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

function Median { param([double[]]$Values) $s = $Values | Sort-Object; $s[[int]($s.Count / 2)] }

function Run-Benchmark {
    param([string]$Label, [string]$Binary, [bool]$EarlyExit, [string]$Type)

    Write-Host ""
    Write-Host ("=" * 78) -ForegroundColor Cyan
    Write-Host "  $Label" -ForegroundColor Cyan
    Write-Host ("=" * 78) -ForegroundColor Cyan

    # Cold run: no library cache, measures true Stage 1 cold time
    Write-Host "  Cold (no lib cache)..." -ForegroundColor Gray -NoNewline
    Clean-AllCaches
    $coldRun = Run-Once $Binary $commonArgs $EarlyExit
    if ($coldRun.Exit -ne 0) {
        Write-Host " FAILED (exit $($coldRun.Exit))" -ForegroundColor Red
        return $null
    }
    $coldStages = if ($Type -eq "Rust") { Parse-RustStages $coldRun.Lines $coldRun.WallSec }
                  else { Parse-CSharpStages $coldRun.Lines }
    $coldS1 = if ($null -ne $coldStages) { $coldStages.S1 } else { 0 }
    Write-Host " $($coldRun.WallSec.ToString('F1'))s (S1_cold=$($coldS1.ToString('F1')))" -ForegroundColor Gray

    # Timed iterations (library cache warm after cold run)
    $runs = @()
    for ($iter = 1; $iter -le $Iterations; $iter++) {
        Write-Host "  Run $iter/$Iterations (warm cache)..." -ForegroundColor Gray -NoNewline
        Clean-ScoreCaches
        $result = Run-Once $Binary $commonArgs $EarlyExit
        if ($result.Exit -ne 0) {
            Write-Host " FAILED" -ForegroundColor Red
            continue
        }

        $stages = if ($Type -eq "Rust") { Parse-RustStages $result.Lines $result.WallSec }
                  else { Parse-CSharpStages $result.Lines }
        if ($null -eq $stages) {
            Write-Host " parse error" -ForegroundColor Red
            continue
        }
        $stages['Wall'] = $result.WallSec
        $runs += $stages
        Write-Host " $($result.WallSec.ToString('F1'))s (S1=$($stages.S1) S2=$($stages.S2) S3=$($stages.S3.ToString('F1')) S4=$($stages.S4.ToString('F1')))" -ForegroundColor Gray
    }

    if ($runs.Count -lt 2) {
        Write-Host "  Not enough successful runs" -ForegroundColor Red
        return $null
    }

    # Compute medians
    $med = @{
        Label = $Label
        S1Cold = $coldS1
        S1 = Median ($runs | ForEach-Object { $_.S1 })
        S2 = Median ($runs | ForEach-Object { $_.S2 })
        S3 = Median ($runs | ForEach-Object { $_.S3 })
        S4 = Median ($runs | ForEach-Object { $_.S4 })
        Thru4 = Median ($runs | ForEach-Object { $_.Thru4 })
        Wall = Median ($runs | ForEach-Object { $_.Wall })
        Entries = $runs[0].Entries
        HasLibCache = ($Type -eq "Rust")
    }

    # Consistency check: flag if max/min ratio > 1.20 for any stage
    foreach ($key in @('S1','S2','S3','S4','Thru4')) {
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
Write-Host ""
Write-Host "Osprey Scoring Benchmark: Stages 1-4" -ForegroundColor Yellow
Write-Host "Stellar file 20 | --resolution unit | $Iterations iterations | median reported" -ForegroundColor Gray
Write-Host "Library cache: warm (Rust), cold (C# - no binary cache)" -ForegroundColor Gray
Write-Host ""

$results = @()

if (-not $SkipUpstream) {
    $results += Run-Benchmark "Upstream Rust (maccoss/osprey v26.1.3)" $upstreamBin $false "Rust"
}
$results += Run-Benchmark "Fork Rust (brendanx67/osprey)" $forkBin $true "Rust"
$results += Run-Benchmark "OspreySharp (C#)" $csharpBin $true "CSharp"

# ===========================================================================
# Results table
# ===========================================================================

Write-Host ""
Write-Host ("=" * 90) -ForegroundColor Yellow
Write-Host "  MEDIAN Stages 1-4 Timing ($Iterations iterations each)" -ForegroundColor Yellow
Write-Host ("=" * 90) -ForegroundColor Yellow
Write-Host ""

$fmt = "{0,-24} {1,8} {2,8} {3,8} {4,8} {5,8}   {6,8} {7,10}"
Write-Host ($fmt -f "", "Stage 1", "Stage 1", "Stage 2", "Stage 3", "Stage 4", "Stg 1-4", "Entries")
Write-Host ($fmt -f "Implementation", "Library", "Cached", "mzML", "Calibr.", "Search", "Total", "Scored")
Write-Host ("{0,-24} {1} {2} {3} {4} {5}   {6} {7}" -f ("-"*24), ("-"*8), ("-"*8), ("-"*8), ("-"*8), ("-"*8), ("-"*8), ("-"*10))

foreach ($r in $results) {
    if ($null -eq $r) { continue }
    $s1cf = "$($r.S1Cold.ToString('F1'))s"
    $s1wf = if ($r.HasLibCache) { "$($r.S1.ToString('F1'))s" } else { "n/a" }
    $s2f = "$($r.S2.ToString('F1'))s"
    $s3f = "$($r.S3.ToString('F1'))s"
    $s4f = "$($r.S4.ToString('F1'))s"
    $thf = "$($r.Thru4.ToString('F1'))s"
    $ent = $r.Entries.ToString("N0")
    Write-Host ($fmt -f $r.Label, $s1cf, $s1wf, $s2f, $s3f, $s4f, $thf, $ent)
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
    Write-Host ""
    Write-Host ($fmt -f $ratioLabel, $r1c, $r1w, $r2, $r3, $r4, $rt, "")
}

Write-Host ""
Write-Host "Notes:" -ForegroundColor Gray
Write-Host "  Stage 1 'Library': cold (no .libcache), all tools parse TSV from scratch" -ForegroundColor Gray
Write-Host "  Stage 1 'Cached': warm (.libcache present); n/a = no binary cache implemented" -ForegroundColor Gray
Write-Host "  Stg 1-4 Total = wall clock for fork/C# (early exit); timestamp-derived for upstream" -ForegroundColor Gray
Write-Host "  Rust S1 derived from wall_clock - (S2+S3+S4) for sub-second accuracy" -ForegroundColor Gray
Write-Host "  Rust S2/S3/S4 have +/-0.5s rounding (1s timestamp resolution)" -ForegroundColor Gray
Write-Host ""

# Cleanup
Clean-ScoreCaches
Remove-Item Env:RUST_LOG -ErrorAction SilentlyContinue
