<#
.SYNOPSIS
    Production-mode performance measurement for OspreySharp (C#) vs osprey (Rust).

.DESCRIPTION
    Sibling of Test-Snapshot.ps1. Test-Snapshot.ps1 is for cross-impl PARITY
    (per-stage isolation, dump TSVs, byte-for-byte comparisons). This script
    is for PERFORMANCE — runs the full pipeline as a single process per
    (tool x dataset) with no diagnostic dumps, captures per-stage walls from
    matched [STAGE-WALL] log lines emitted by both impls, and emits the
    Osprey-workflow.html perf table rows ready to paste.

    Why a separate script:
      - Stage isolation in Test-Snapshot.ps1 adds process-startup + file-copy
        overhead between stages, which is right for parity but pollutes wall.
      - Test-Snapshot.ps1 sets OSPREY_DUMP_* env vars to produce comparison
        artifacts; those add 30s+ to stage5 alone (FormatF64Roundtrip vs ryu).
      - Production users never set those env vars; their wall is the headline.

    Both impls emit one log line per of the five named stages:
      [STAGE-WALL] stage1to4: X.Xs
      [STAGE-WALL] stage5:    X.Xs
      [STAGE-WALL] stage6:    X.Xs
      [STAGE-WALL] stage7:    X.Xs
      [STAGE-WALL] blib:      X.Xs

    Total wall is measured externally (wrapper time around the binary).

.PARAMETER Dataset
    Stellar, Astral, or Both (default). Matches Dataset-Config.ps1 entries.

.PARAMETER Tool
    CSharp, Rust, or Both (default).

.PARAMETER Repeats
    Number of full-pipeline runs per (tool x dataset). Default 1.
    With Repeats > 1 the report shows median across runs + min/max as the
    variance indicator. Run-to-run variance on Windows native is typically
    < 5% per stage.

.PARAMETER OutputDir
    Directory for per-run logs and the aggregated report. Default:
    ai\.tmp\measure-pipeline\<UTC timestamp>\.

.PARAMETER MaxParallelFiles
    File parallelism for the C# leg, passed as --parallel-files. Default -1 =
    dataset default reproducing the recorded Osprey-workflow.html conditions:
    3 (parallel) for Stellar, 1 (sequential) for Astral (hram, ~3 GB/file). Rust
    is single-file-per-process and ignores this.

.PARAMETER Threads
    --threads CLI flag. Default 16 (matches the existing Test-Snapshot harness).

.PARAMETER TestBaseDir
    Where the datasets live. Default uses Dataset-Config.ps1 default
    (D:\test\osprey-runs on Windows native).

.PARAMETER KeepWorkdir
    Do not delete per-run workdirs at the end. Useful for inspecting outputs
    when a run produces unexpected numbers. Default: workdirs are cleaned to
    free disk between runs.

.EXAMPLE
    # Quick smoke test on Stellar only, 1 run, both tools.
    pwsh -File .\Measure-Pipeline.ps1 -Dataset Stellar -Repeats 1

.EXAMPLE
    # Full perf-table refresh for Osprey-workflow.html: 3 runs each.
    pwsh -File .\Measure-Pipeline.ps1 -Repeats 3

.EXAMPLE
    # Just C# Astral, 5 runs for variance characterization.
    pwsh -File .\Measure-Pipeline.ps1 -Dataset Astral -Tool CSharp -Repeats 5

.NOTES
    Disk: Astral requires ~30 GB free per run for workdir caches. The
    script cleans workdirs between runs unless -KeepWorkdir is set.

    Cold cache: first run after a binary swap typically has slightly higher
    wall because Windows hasn't paged the new binary yet. With -Repeats >= 3
    the median masks this; for -Repeats 1 results, expect 1-2s noise on
    fast stages (stage7, blib).
#>

param(
    [ValidateSet('Stellar','Astral','Both')]
    [string]$Dataset = 'Both',

    [ValidateSet('CSharp','Rust','Both')]
    [string]$Tool = 'Both',

    [int]$Repeats = 1,

    [string]$OutputDir = $null,

    [int]$MaxParallelFiles = -1,  # -1 means: use dataset default (1 for Astral, unset otherwise)

    [int]$Threads = 16,

    [string]$TestBaseDir = $null,

    [switch]$KeepWorkdir
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$scriptDir = Split-Path -Parent $PSCommandPath
. (Join-Path $scriptDir 'Dataset-Config.ps1')

# Resolve project root for binary paths
$projRoot = (Resolve-Path (Join-Path $scriptDir '..\..\..')).Path
$exeSuffix = if ($IsWindows) { '.exe' } else { '' }

# Resolve binary paths and verify they exist
$tools = @{
    'CSharp' = @{
        Name = 'C#'
        BinName = "OspreySharp$exeSuffix"
        Bin = Join-Path $projRoot "pwiz\pwiz_tools\OspreySharp\OspreySharp\bin\x64\Release\net8.0\OspreySharp$exeSuffix"
        BuildHint = 'pwsh -File ./ai/scripts/OspreySharp/Build-OspreySharp.ps1 -TargetFramework net8.0'
    }
    'Rust' = @{
        Name = 'Rust'
        BinName = "osprey$exeSuffix"
        Bin = Join-Path $projRoot "osprey\target\release\osprey$exeSuffix"
        BuildHint = 'pwsh -File ./ai/scripts/OspreySharp/Build-OspreyRust.ps1'
    }
}

# Determine which tools and datasets to run
$toolsToRun = if ($Tool -eq 'Both') { @('CSharp','Rust') } else { @($Tool) }
$datasetsToRun = if ($Dataset -eq 'Both') { @('Stellar','Astral') } else { @($Dataset) }

# Verify all requested binaries exist before starting the long-running loop
foreach ($t in $toolsToRun) {
    if (-not (Test-Path $tools[$t].Bin)) {
        Write-Host "[Measure-Pipeline] $($tools[$t].Name) binary not found: $($tools[$t].Bin)" -ForegroundColor Red
        Write-Host "  Build first: $($tools[$t].BuildHint)" -ForegroundColor Yellow
        exit 2
    }
}

# Output dir for logs + the aggregated report. Per-run logs land in
# subdirs by tool+dataset+run-idx so a re-run won't clobber prior data.
if (-not $OutputDir) {
    $ts = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmssZ')
    $OutputDir = Join-Path $projRoot "ai\.tmp\measure-pipeline\$ts"
}
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

Write-Host ""
Write-Host "=== Measure-Pipeline ===" -ForegroundColor Cyan
Write-Host ("Tools:       {0}" -f ($toolsToRun -join ', '))
Write-Host ("Datasets:    {0}" -f ($datasetsToRun -join ', '))
Write-Host ("Repeats:     {0}" -f $Repeats)
Write-Host ("Output:      {0}" -f $OutputDir)
Write-Host ("Threads:     {0}" -f $Threads)
Write-Host ""

# Stages we expect to see in the log output, in pipeline order.
$expectedStages = @('stage1to4','stage5','stage6','stage7','blib')

# Some impls emit additional STAGE-WALL markers between stage6 and
# stage7. C# OspreySharp emits `[STAGE-WALL] second-pass-fdr` for the
# 2nd-pass Percolator (which Rust folds into its `stage7` marker
# along with protein parsimony + protein FDR). For apples-to-apples
# stage7 comparison we add the time from any of these "extra"
# markers to stage7 when present. If an impl emits the work under
# the `stage7` marker directly, this is a no-op.
$stage7MergeMarkers = @('second-pass-fdr')

# Single (tool, dataset, run_idx) -> per-stage wall (seconds) + total wall.
# Returns a PSCustomObject with .stages (hashtable stage -> seconds), .total
# (seconds, wrapper-measured), .exit (process exit code), .logPath (string).
function Invoke-PipelineRun {
    param(
        [string]$ToolKey,
        [string]$DatasetName,
        [int]$RunIdx
    )

    $t = $tools[$ToolKey]
    $ds = Get-DatasetConfig $DatasetName -TestBaseDir $TestBaseDir
    $datasetRoot = $ds.TestDir
    $library = $ds.Library
    $resolution = $ds.Resolution
    $files = @($ds.AllFiles)

    # Per-run workdir under a perf-only prefix so we don't collide with
    # Test-Snapshot.ps1's _test_snapshot_* tags.
    $tag = "perf-$($DatasetName.ToLower())-$($ToolKey.ToLower())-run$RunIdx"
    $workdir = Join-Path $datasetRoot "_measure_$tag"

    if (Test-Path $workdir) {
        Write-Host ("  [{0}/{1}/{2}] removing stale workdir" -f $ToolKey, $DatasetName, $RunIdx) -ForegroundColor DarkYellow
        Remove-Item $workdir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $workdir -Force | Out-Null

    # Stage inputs: copy mzML + library into workdir. Use -p semantics so
    # mtimes are preserved (Rust's library_identity_hash includes file
    # mtime; rapid recopying could otherwise spuriously invalidate caches).
    foreach ($f in $files) {
        Copy-Item (Join-Path $datasetRoot $f) (Join-Path $workdir $f)
    }
    Copy-Item (Join-Path $datasetRoot $library) (Join-Path $workdir $library)
    $libcache = Join-Path $datasetRoot ($library + '.libcache')
    if (Test-Path $libcache) {
        Copy-Item $libcache (Join-Path $workdir ($library + '.libcache'))
    }

    # Build CLI args. Full pipeline (no --task), no diagnostic
    # dumps -- production wall.
    $cliArgs = @()
    foreach ($f in $files) {
        $cliArgs += '-i'
        $cliArgs += $f
    }
    $cliArgs += @('-l', $library, '-o', 'output.blib',
                  '--resolution', $resolution,
                  '--protein-fdr', '0.01',
                  '--threads', $Threads.ToString())

    # Pre-run env scrub: remove every OSPREY_DUMP_* / *_ONLY hook so the
    # binary executes the production path. Then set the few env vars this
    # measurement intentionally controls.
    $diagEnvVars = @(
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
        'OSPREY_DUMP_MP_INPUTS','OSPREY_DUMP_CWT_PATH',
        'OSPREY_TRACE_PEPTIDE'
    )
    foreach ($k in $diagEnvVars) {
        if (Test-Path "env:$k") { Remove-Item "env:$k" }
    }

    # Per-dataset file parallelism, pinned to the conditions the
    # Osprey-workflow.html numbers were recorded under: Stellar with 3 files in
    # parallel, Astral (hram, ~3 GB spectra/file) sequential. OspreySharp's
    # default is now sequential, so pin it explicitly via the first-class
    # --parallel-files argument on the C# leg. Rust is single-file-per-process
    # and has no file-parallelism control, so it gets no such flag.
    $mpfApplied = $MaxParallelFiles
    if ($mpfApplied -lt 0) {
        $mpfApplied = if ($DatasetName -eq 'Stellar') { 3 } else { 1 }
    }
    if ($ToolKey -eq 'CSharp' -and $mpfApplied -ge 1) {
        $cliArgs += @('--parallel-files', $mpfApplied.ToString())
    }
    # Scrub any stale env cap so it cannot shadow the explicit argument (the
    # argument wins when both are set, but keep the environment clean anyway).
    if (Test-Path 'env:OSPREY_MAX_PARALLEL_FILES') { Remove-Item env:OSPREY_MAX_PARALLEL_FILES }

    $logPath = Join-Path $OutputDir ("{0}-{1}-run{2}.log" -f $ToolKey, $DatasetName, $RunIdx)
    Write-Host ("  [{0}/{1}/{2}] {3} ..." -f $ToolKey, $DatasetName, $RunIdx, (Split-Path $t.Bin -Leaf)) -ForegroundColor Cyan
    Write-Host ("    workdir: {0}" -f $workdir) -ForegroundColor DarkGray
    Write-Host ("    log:     {0}" -f $logPath) -ForegroundColor DarkGray

    Push-Location $workdir
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
        & $t.Bin @cliArgs *>&1 | Tee-Object -FilePath $logPath | Out-Null
        $exit = $LASTEXITCODE
    } finally {
        Pop-Location
    }
    $sw.Stop()
    $wallSec = $sw.Elapsed.TotalSeconds

    # Parse [STAGE-WALL] lines.
    $stages = @{}
    # C#-only [TIMING] sub-stages we need for the stage5/stage6 boundary
    # alignment described below. Captured here from the same log scan.
    $percolatorSec = $null
    $proteinFdrSec = $null
    foreach ($line in [System.IO.File]::ReadAllLines($logPath)) {
        if ($line -match '\[STAGE-WALL\]\s+(\S+):\s+([0-9.]+)s') {
            $stages[$Matches[1]] = [double]$Matches[2]
        }
        elseif ($line -match '\[TIMING\]\s+Percolator/Simple FDR:\s+([0-9.]+)s') {
            $percolatorSec = [double]$Matches[1]
        }
        elseif ($line -match '\[TIMING\]\s+First-pass protein FDR:\s+([0-9.]+)s') {
            $proteinFdrSec = [double]$Matches[1]
        }
    }
    # Fold extra markers (e.g. C#'s separate `second-pass-fdr`) into
    # stage7 so cross-impl comparison covers the same work.
    foreach ($extra in $stage7MergeMarkers) {
        if ($stages.ContainsKey($extra)) {
            $stages['stage7'] = ($stages['stage7'] | ForEach-Object { if ($_) { $_ } else { 0.0 } }) + $stages[$extra]
            $stages.Remove($extra) | Out-Null
        }
    }
    # Stage 5/6 boundary alignment for C#.
    #
    # Rust labels:
    #   stage5 = 1st-pass percolator FDR + 1st-pass protein FDR
    #   stage6 = reconciliation planning + per-file rescore + gap-fill
    # C# labels (default emission from FirstJoinTask + PerFileRescore):
    #   stage5 = 1st-pass percolator + protein FDR + reconciliation planning
    #   stage6 = per-file rescore + gap-fill (no reconciliation)
    # The work content of stage5+stage6 is identical cross-impl; the
    # boundary placement is the difference. When the C# `[TIMING]
    # Percolator/Simple FDR` and `[TIMING] First-pass protein FDR` lines
    # are present (always emitted by OspreySharp in --no-bundle production
    # mode), we can derive the reconciliation portion as
    # stage5_total - percolator - protein_fdr and shift it into stage6.
    # The result: aligned stage5/stage6 match the Rust split exactly,
    # making cross-impl per-stage comparison apples-to-apples.
    #
    # Rust logs do not contain these TIMING markers, so this block is a
    # no-op on the Rust side.
    if ($percolatorSec -ne $null -and $stages.ContainsKey('stage5')) {
        $protein = if ($proteinFdrSec -ne $null) { $proteinFdrSec } else { 0.0 }
        $stage5Total = $stages['stage5']
        $reconciliationSec = $stage5Total - $percolatorSec - $protein
        if ($reconciliationSec -gt 0.5) {
            # Stage 5 aligned = percolator + protein FDR only.
            $stages['stage5'] = $percolatorSec + $protein
            # Stage 6 aligned += reconciliation portion previously in
            # stage5. If stage6 wasn't emitted (e.g. --task FirstJoin exit),
            # we just publish reconciliation alone under stage6.
            if ($stages.ContainsKey('stage6')) {
                $stages['stage6'] = $stages['stage6'] + $reconciliationSec
            } else {
                $stages['stage6'] = $reconciliationSec
            }
        }
    }

    # Per-dataset disk hygiene: workdir holds Stellar ~10 GB / Astral ~30+ GB.
    # Without cleanup, 12 runs at -Repeats 3 would fill any disk.
    if (-not $KeepWorkdir) {
        try {
            Remove-Item $workdir -Recurse -Force -ErrorAction Stop
        } catch {
            Write-Host ("    [warn] failed to clean workdir {0}: {1}" -f $workdir, $_.Exception.Message) -ForegroundColor Yellow
        }
    }

    $missing = @($expectedStages | Where-Object { -not $stages.ContainsKey($_) })
    if ($missing.Count -gt 0) {
        Write-Host ("    [warn] missing [STAGE-WALL] markers: {0}" -f ($missing -join ', ')) -ForegroundColor Yellow
    }
    if ($exit -ne 0) {
        Write-Host ("    [FAIL] exit code {0}; see log: {1}" -f $exit, $logPath) -ForegroundColor Red
    } else {
        $stageStr = ($expectedStages | ForEach-Object {
            if ($stages.ContainsKey($_)) { "{0}={1:F1}s" -f $_, $stages[$_] } else { "{0}=MISS" -f $_ }
        }) -join '  '
        Write-Host ("    {0}  total={1:F1}s" -f $stageStr, $wallSec) -ForegroundColor Green
    }

    return [pscustomobject]@{
        Tool      = $ToolKey
        Dataset   = $DatasetName
        RunIdx    = $RunIdx
        Stages    = $stages    # hashtable stage -> seconds
        Total     = $wallSec
        Exit      = $exit
        LogPath   = $logPath
    }
}

# Execute all runs. Order: dataset-outer, tool-inner, repeat-innermost.
# Same order on each repeat batch so any system-warmup effect is shared.
$allResults = New-Object System.Collections.Generic.List[object]
$runIdxByCombo = @{}
foreach ($ds in $datasetsToRun) {
    foreach ($tk in $toolsToRun) {
        for ($r = 1; $r -le $Repeats; $r++) {
            $res = Invoke-PipelineRun -ToolKey $tk -DatasetName $ds -RunIdx $r
            $allResults.Add($res) | Out-Null
        }
    }
}

# Aggregate: per (tool, dataset, stage), compute median across repeats.
# Also collect min / max so we can sanity-check stability before publishing.
function Get-Median {
    param([double[]]$Values)
    if ($Values.Count -eq 0) { return [double]::NaN }
    $sorted = $Values | Sort-Object
    # Use [Math]::Floor to get integer division -- PowerShell's [int]
    # cast applies banker's rounding (`[int]1.5 -> 2`), which for odd
    # counts of 3 or 7 would jump past the true middle index and
    # return the wrong element (specifically the max for Count=3).
    $mid = [int][Math]::Floor($sorted.Count / 2.0)
    if ($sorted.Count % 2 -eq 1) { return $sorted[$mid] }
    return ($sorted[$mid - 1] + $sorted[$mid]) / 2.0
}

# Build a flat table of medians indexed by (Dataset, Tool, Stage).
$summary = @{}  # key = "$Dataset|$Tool|$Stage" -> @{ median; min; max; n }
foreach ($ds in $datasetsToRun) {
    foreach ($tk in $toolsToRun) {
        $runs = $allResults | Where-Object { $_.Dataset -eq $ds -and $_.Tool -eq $tk -and $_.Exit -eq 0 }
        foreach ($stage in $expectedStages) {
            $vals = @($runs | ForEach-Object {
                if ($_.Stages.ContainsKey($stage)) { $_.Stages[$stage] } else { $null }
            } | Where-Object { $_ -ne $null })
            $summary["$ds|$tk|$stage"] = @{
                median = (Get-Median -Values $vals)
                min    = if ($vals.Count -gt 0) { ($vals | Measure-Object -Minimum).Minimum } else { [double]::NaN }
                max    = if ($vals.Count -gt 0) { ($vals | Measure-Object -Maximum).Maximum } else { [double]::NaN }
                n      = $vals.Count
            }
        }
        # Total wall = sum of stage medians (close enough; wrapper-measured
        # total includes startup + tear-down which we want to ignore).
        $totalVals = @($runs | ForEach-Object { $_.Total })
        $summary["$ds|$tk|total_wrapper"] = @{
            median = (Get-Median -Values $totalVals)
            min    = if ($totalVals.Count -gt 0) { ($totalVals | Measure-Object -Minimum).Minimum } else { [double]::NaN }
            max    = if ($totalVals.Count -gt 0) { ($totalVals | Measure-Object -Maximum).Maximum } else { [double]::NaN }
            n      = $totalVals.Count
        }
    }
}

function Format-Time {
    param([double]$Seconds)
    if ([double]::IsNaN($Seconds)) { return '--' }
    if ($Seconds -lt 60) { return ('{0:F1}s' -f $Seconds) }
    # [int] does banker's rounding (1.5 -> 2); use Math.Floor for true truncation
    # so 117.9s formats as 1:58 not 2:-02.
    $m = [int][Math]::Floor($Seconds / 60.0)
    $s = $Seconds - ($m * 60.0)
    return ('{0}:{1:00}' -f $m, [int][Math]::Floor($s))
}

# ----- Report 1: markdown summary -----
$mdLines = New-Object System.Collections.Generic.List[string]
$mdLines.Add("# Measure-Pipeline report") | Out-Null
$mdLines.Add("") | Out-Null
$mdLines.Add("- Generated: $((Get-Date).ToString('o'))") | Out-Null
$mdLines.Add("- Repeats per cell: $Repeats (median reported)") | Out-Null
$mdLines.Add("- Threads: $Threads") | Out-Null
$mdLines.Add("- Output dir: ``$OutputDir``") | Out-Null
$mdLines.Add("") | Out-Null

foreach ($ds in $datasetsToRun) {
    $mdLines.Add("## $ds") | Out-Null
    $mdLines.Add("") | Out-Null
    $header = "| Stage |"
    $sep    = "|-------|"
    foreach ($tk in $toolsToRun) {
        $header += " $($tools[$tk].Name) |"
        $sep    += "-------:|"
    }
    if ($toolsToRun.Count -eq 2) {
        $header += " C#/Rust |"
        $sep    += "-------:|"
    }
    $mdLines.Add($header) | Out-Null
    $mdLines.Add($sep) | Out-Null

    $stagesPlusTotal = $expectedStages + @('total_wrapper')
    foreach ($stage in $stagesPlusTotal) {
        $row = "| $stage |"
        foreach ($tk in $toolsToRun) {
            $row += " $(Format-Time $summary["$ds|$tk|$stage"].median) |"
        }
        if ($toolsToRun.Count -eq 2) {
            $csMed = $summary["$ds|CSharp|$stage"].median
            $rsMed = $summary["$ds|Rust|$stage"].median
            if ([double]::IsNaN($csMed) -or [double]::IsNaN($rsMed) -or $rsMed -eq 0) {
                $row += " -- |"
            } else {
                $ratio = $csMed / $rsMed
                $row += (" {0:F2}x |" -f $ratio)
            }
        }
        $mdLines.Add($row) | Out-Null
    }
    $mdLines.Add("") | Out-Null
    # Variance summary (only useful with Repeats > 1)
    if ($Repeats -gt 1) {
        $mdLines.Add("### Variance ($ds, min .. max across $Repeats runs)") | Out-Null
        $mdLines.Add("") | Out-Null
        $vh = "| Stage |"
        $vs = "|-------|"
        foreach ($tk in $toolsToRun) {
            $vh += " $($tools[$tk].Name) min..max |"
            $vs += "----:|"
        }
        $mdLines.Add($vh) | Out-Null
        $mdLines.Add($vs) | Out-Null
        foreach ($stage in $stagesPlusTotal) {
            $row = "| $stage |"
            foreach ($tk in $toolsToRun) {
                $s = $summary["$ds|$tk|$stage"]
                $row += " $(Format-Time $s.min) .. $(Format-Time $s.max) |"
            }
            $mdLines.Add($row) | Out-Null
        }
        $mdLines.Add("") | Out-Null
    }
}

# ----- Report 2: HTML <tr> rows ready to paste into Osprey-workflow.html -----
# Mirrors the existing column layout in that file:
#   <th>Stage</th>
#   <th>Stellar Rust</th> <th>Stellar C#</th> <th>C#/Rust</th>
#   <th>Astral Rust</th>  <th>Astral C#</th>  <th>C#/Rust</th>
# Only emit when both datasets and both tools are present, so the row
# structure matches the existing HTML schema.
$emitHtml = ($datasetsToRun -contains 'Stellar') -and ($datasetsToRun -contains 'Astral') `
            -and ($toolsToRun -contains 'CSharp') -and ($toolsToRun -contains 'Rust')

if ($emitHtml) {
    $htmlLines = New-Object System.Collections.Generic.List[string]
    $htmlLines.Add('<!-- Paste into Osprey-workflow.html, replacing the existing <tbody> rows. -->') | Out-Null
    $htmlLines.Add('<!-- Schema: Stage | Stellar Rust | Stellar C# | C#/Rust | Astral Rust | Astral C# | C#/Rust -->') | Out-Null
    $stageLabels = @(
        @{ Key='stage1to4'; Label='stage1to4' },
        @{ Key='stage5';    Label='stage5 (1st-pass FDR + plan)' },
        @{ Key='stage6';    Label='stage6 (rescore + gap-fill)' },
        @{ Key='stage7';    Label='stage7 (2nd-pass FDR + protein)' },
        @{ Key='blib';      Label='blib write' }
    )
    function Format-Ratio {
        param([double]$Cs, [double]$Rust)
        if ([double]::IsNaN($Cs) -or [double]::IsNaN($Rust) -or $Rust -eq 0) { return '--' }
        $r = $Cs / $Rust
        if ($r -lt 0.95) { return ('{0:F2}x (C# faster)' -f $r) }
        if ($r -le 1.05) { return ('{0:F2}x (~tied)' -f $r) }
        return ('{0:F2}x' -f $r)
    }
    function Ratio-Color {
        param([double]$Cs, [double]$Rust)
        if ([double]::IsNaN($Cs) -or [double]::IsNaN($Rust) -or $Rust -eq 0) { return '' }
        $r = $Cs / $Rust
        if ($r -lt 0.95) { return ' color: #1a7f37;' }
        if ($r -gt 1.10) { return ' color: #b54708;' }
        return ''
    }
    foreach ($s in $stageLabels) {
        $stage = $s.Key
        $sRust = $summary["Stellar|Rust|$stage"].median
        $sCs   = $summary["Stellar|CSharp|$stage"].median
        $aRust = $summary["Astral|Rust|$stage"].median
        $aCs   = $summary["Astral|CSharp|$stage"].median
        $sRatio = Format-Ratio -Cs $sCs -Rust $sRust
        $aRatio = Format-Ratio -Cs $aCs -Rust $aRust
        $sColor = Ratio-Color -Cs $sCs -Rust $sRust
        $aColor = Ratio-Color -Cs $aCs -Rust $aRust
        $tr  = '      <tr>'
        $tr += "<td style=`"padding: 1px 12px 1px 0;`">$($s.Label)</td>"
        $tr += "<td style=`"text-align: right; padding: 1px 12px;`">$(Format-Time $sRust)</td>"
        $tr += "<td style=`"text-align: right; padding: 1px 12px;`">$(Format-Time $sCs)</td>"
        $tr += "<td style=`"text-align: right; padding: 1px 12px;$sColor`">$sRatio</td>"
        $tr += "<td style=`"text-align: right; padding: 1px 12px;`">$(Format-Time $aRust)</td>"
        $tr += "<td style=`"text-align: right; padding: 1px 12px;`">$(Format-Time $aCs)</td>"
        $tr += "<td style=`"text-align: right; padding: 1px 12px;$aColor`">$aRatio</td>"
        $tr += '</tr>'
        $htmlLines.Add($tr) | Out-Null
    }
    # Total row: sum of stage medians per (dataset, tool). Use sum not
    # wrapper-total so the columns add up cleanly when read by a human.
    function Sum-Stages {
        param([string]$Ds, [string]$Tk)
        $sum = 0.0
        foreach ($s in $stageLabels) {
            $v = $summary["$Ds|$Tk|$($s.Key)"].median
            if (-not [double]::IsNaN($v)) { $sum += $v }
        }
        return $sum
    }
    $tRust = Sum-Stages -Ds 'Stellar' -Tk 'Rust'
    $tCs   = Sum-Stages -Ds 'Stellar' -Tk 'CSharp'
    $aRust = Sum-Stages -Ds 'Astral'  -Tk 'Rust'
    $aCs   = Sum-Stages -Ds 'Astral'  -Tk 'CSharp'
    $tRatio = Format-Ratio -Cs $tCs -Rust $tRust
    $aRatio = Format-Ratio -Cs $aCs -Rust $aRust
    $tColor = Ratio-Color -Cs $tCs -Rust $tRust
    $aColor = Ratio-Color -Cs $aCs -Rust $aRust
    $totalTr  = '      <tr style="border-top: 1px solid #888;">'
    $totalTr += '<td style="padding: 1px 12px 1px 0;"><strong>Total</strong></td>'
    $totalTr += "<td style=`"text-align: right; padding: 1px 12px;`"><strong>$(Format-Time $tRust)</strong></td>"
    $totalTr += "<td style=`"text-align: right; padding: 1px 12px;`"><strong>$(Format-Time $tCs)</strong></td>"
    $totalTr += "<td style=`"text-align: right; padding: 1px 12px;$tColor`"><strong>$tRatio</strong></td>"
    $totalTr += "<td style=`"text-align: right; padding: 1px 12px;`"><strong>$(Format-Time $aRust)</strong></td>"
    $totalTr += "<td style=`"text-align: right; padding: 1px 12px;`"><strong>$(Format-Time $aCs)</strong></td>"
    $totalTr += "<td style=`"text-align: right; padding: 1px 12px;$aColor`"><strong>$aRatio</strong></td>"
    $totalTr += '</tr>'
    $htmlLines.Add($totalTr) | Out-Null

    $htmlPath = Join-Path $OutputDir 'osprey-workflow-rows.html'
    $htmlLines | Out-File -FilePath $htmlPath -Encoding UTF8
    Write-Host ("[Measure-Pipeline] HTML rows written: {0}" -f $htmlPath) -ForegroundColor Cyan
}

$mdPath = Join-Path $OutputDir 'report.md'
$mdLines | Out-File -FilePath $mdPath -Encoding UTF8
Write-Host ("[Measure-Pipeline] Markdown report: {0}" -f $mdPath) -ForegroundColor Cyan
Write-Host ""
$mdLines | ForEach-Object { Write-Host $_ }
