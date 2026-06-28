<#
.SYNOPSIS
    ULP-strict cross-impl Stage 1-4 comparison via --no-join + all
    Stage 1-3 calibration dumps. Targets bit-equality (1 ULP) at
    every diagnostic checkpoint, exposing drift that Test-Regression's
    1e-6 stage1to4 gate masks.

.DESCRIPTION
    Test-Regression runs stage1to4 cross-impl at 1e-6 tolerance, then
    freezes the Rust output and feeds it to BOTH sides for subsequent
    stages. So any Stage 1-4 cross-impl drift up to 1e-6 is invisible
    to the downstream gates -- but in real end-to-end runs, that drift
    feeds the C# Stage 5 input and can compound through Percolator.

    This script reverses the design: per side, --no-join with every
    Stage 1-3 diagnostic dump enabled, then compare every paired
    output file at the strictest possible tolerance (bit-equal for
    binary parquet content, near-ULP for floating-point TSV content).

    The dump checkpoints in stage order:

      Stage 2:
        CAL_SAMPLE     -> rust_cal_sample.txt  vs <stem>.cs_cal_sample.txt
                        + rust_cal_scalars.txt vs cs_cal_scalars.txt
                        + rust_cal_grid.txt    vs cs_cal_grid.txt
        CAL_WINDOWS    -> rust_cal_windows.txt vs cs_cal_windows.txt
        CAL_MATCH      -> rust_cal_match.txt   vs cs_cal_match.txt

      Stage 3:
        LDA_SCORES     -> rust_lda_scores.txt  vs cs_lda_scores.txt
        LOESS_INPUT    -> rust_loess_input.txt vs cs_loess_input.txt
        calibration.json (boundary file; tolerance-JSON-diff at 1e-15)

      Stage 4:
        .scores.parquet per file (parquet_diff --tolerance 0)

    Per-entry (DIAG_SEARCH_ENTRY_IDS) and per-scan (DIAG_MP_SCAN /
    DIAG_XCORR_SCAN) dumps are NOT enabled in this script -- they
    require pre-knowing which entries/scans diverge. Once this script
    localizes a band, a follow-up can enable those for the failing
    rows.

.PARAMETER Dataset
    Stellar (default) or Astral.

.PARAMETER Files
    Single (default) or All. Single = first file; All = every file in
    Dataset-Config's AllFiles.

.PARAMETER TestBaseDir
    Override dataset root (defaults to OSPREY_TEST_BASE_DIR or
    D:\test\osprey-runs).

.PARAMETER Force
    Wipe any existing workdir before running.

.PARAMETER SkipRust / -SkipCs
    Reuse the existing rust/ or cs/ subdir if outputs are present.

.PARAMETER Threads
    --threads CLI flag (default 16).

.PARAMETER Framework
    Target framework for the C# build: net472 (default; canonical
    Skyline distribution) or net8.0. .NET 8.0 uses the Eisel-Lemire
    IEEE-correct double parser which eliminates parser-driven 1-2 ULP
    cascades in apex_rt, peak boundaries, and downstream peak shape
    features. Use net8.0 to verify a divergence is real f64 cascade
    vs a .NET Framework parser artifact.

.EXAMPLE
    pwsh -File ./Compare-Stage1to4-Strict.ps1 -Dataset Stellar -Files Single -Force

.EXAMPLE
    # Verify a divergence isn't a .NET Framework parser artifact:
    pwsh -File ./Compare-Stage1to4-Strict.ps1 -Dataset Stellar -Files Single -Force -Framework net8.0
#>

param(
    [ValidateSet('Stellar','Astral')]
    [string]$Dataset = 'Stellar',
    [ValidateSet('Single','All')]
    [string]$Files = 'Single',
    [string]$TestBaseDir,
    [switch]$Force,
    [switch]$SkipRust,
    [switch]$SkipCs,
    [int]$Threads = 16,
    # Target framework for the C# build. net472 is the canonical
    # Skyline distribution; net8.0 ships .NET 5+ IEEE-correct double
    # parsing which eliminates parser-driven 1-2 ULP cascades in
    # apex_rt, peak boundaries, and downstream peak shape features.
    [ValidateSet('net472','net8.0')]
    [string]$Framework = 'net472'
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $PSCommandPath
. (Join-Path $scriptDir 'Dataset-Config.ps1')

$projRoot    = (Resolve-Path (Join-Path $scriptDir '..\..\..')).Path
$ospreyExe   = Join-Path $projRoot 'osprey\target\release\osprey.exe'
$ospreyShExe = Join-Path $projRoot ('pwiz\pwiz_tools\Osprey\Osprey\bin\x64\Release\{0}\Osprey.exe' -f $Framework)
foreach ($p in @($ospreyExe, $ospreyShExe)) {
    if (-not (Test-Path $p)) {
        Write-Host "Missing binary: $p" -ForegroundColor Red
        exit 2
    }
}

$ds = Get-DatasetConfig $Dataset -TestBaseDir $TestBaseDir
$mzmls = if ($Files -eq 'Single') { @($ds.SingleFile) } else { @($ds.AllFiles) }
$lib = $ds.Library
$res = $ds.Resolution
$datasetRoot = $ds.TestDir

$rootDir = Join-Path $datasetRoot ("_stage1to4_strict_{0}" -f $Files.ToLower())
$rustDir = Join-Path $rootDir 'rust'
$csDir   = Join-Path $rootDir 'cs'
$cmpDir  = Join-Path $rootDir 'compare_logs'

if ($Force -and (Test-Path $rootDir)) {
    Write-Host "[Stage1to4-Strict] -Force: removing $rootDir" -ForegroundColor DarkYellow
    Remove-Item $rootDir -Recurse -Force
}
New-Item -ItemType Directory $rootDir -Force | Out-Null
New-Item -ItemType Directory $cmpDir  -Force | Out-Null

function Stage-Files { param([string]$Dir)
    foreach ($f in $mzmls) { Copy-Item (Join-Path $datasetRoot $f) (Join-Path $Dir $f) }
    Copy-Item (Join-Path $datasetRoot $lib) (Join-Path $Dir $lib)
    $cache = Join-Path $datasetRoot ($lib + '.libcache')
    if (Test-Path $cache) { Copy-Item $cache (Join-Path $Dir ($lib + '.libcache')) }
}

function Run-Side {
    param([string]$Name, [string]$Exe, [string]$Dir, [switch]$Skip)
    $logName = "$Name.log"
    if ($Skip -and (Test-Path (Join-Path $Dir $logName))) {
        Write-Host ("[{0}] -Skip: reusing $Dir" -f $Name) -ForegroundColor DarkGray
        return [TimeSpan]::Zero
    }
    if (Test-Path $Dir) { Remove-Item $Dir -Recurse -Force }
    New-Item -ItemType Directory $Dir -Force | Out-Null
    Stage-Files -Dir $Dir
    Push-Location $Dir
    try {
        # All Stage 1-3 dumps on; do NOT set any _ONLY flags so the
        # pipeline runs all the way through Stage 4.
        $env:OSPREY_DUMP_CAL_SAMPLE  = '1'
        $env:OSPREY_DUMP_CAL_WINDOWS = '1'
        $env:OSPREY_DUMP_CAL_MATCH   = '1'
        $env:OSPREY_DUMP_LDA_SCORES  = '1'
        $env:OSPREY_DUMP_LOESS_INPUT = '1'
        # Rust-only at present; harmless to enable on C# (just ignored).
        $env:OSPREY_DUMP_CAL_PREFILTER = '1'
        $cliArgs = @()
        foreach ($f in $mzmls) { $cliArgs += @('-i', $f) }
        $cliArgs += @('-l', $lib, '-o', 'unused.blib',
                      '--resolution', $res, '--no-join',
                      '--threads', $Threads.ToString())
        $sw = [Diagnostics.Stopwatch]::StartNew()
        Write-Host ("[{0}] --no-join + all Stage 1-3 dumps ..." -f $Name) -ForegroundColor Cyan
        & $Exe @cliArgs 2>&1 | Tee-Object -FilePath $logName | Out-Null
        $exit = $LASTEXITCODE
        $sw.Stop()
        if ($exit -ne 0) { throw "$Name --no-join failed (exit=$exit); see $logName" }
        Write-Host ("[{0}] wall={1:mm\:ss}" -f $Name, $sw.Elapsed) -ForegroundColor Green
        return $sw.Elapsed
    } finally {
        Remove-Item Env:OSPREY_DUMP_CAL_SAMPLE    -ErrorAction SilentlyContinue
        Remove-Item Env:OSPREY_DUMP_CAL_WINDOWS   -ErrorAction SilentlyContinue
        Remove-Item Env:OSPREY_DUMP_CAL_MATCH     -ErrorAction SilentlyContinue
        Remove-Item Env:OSPREY_DUMP_LDA_SCORES    -ErrorAction SilentlyContinue
        Remove-Item Env:OSPREY_DUMP_LOESS_INPUT   -ErrorAction SilentlyContinue
        Remove-Item Env:OSPREY_DUMP_CAL_PREFILTER -ErrorAction SilentlyContinue
        Pop-Location
    }
}

$rustWall = Run-Side -Name 'rust' -Exe $ospreyExe   -Dir $rustDir -Skip:$SkipRust
$csWall   = Run-Side -Name 'cs'   -Exe $ospreyShExe -Dir $csDir   -Skip:$SkipCs

# -------- COMPARISON --------

$results = New-Object System.Collections.Generic.List[object]
function Record { param([string]$Group, [string]$File, [bool]$Pass, [string]$Detail)
    $script:results.Add([pscustomobject]@{
        Group  = $Group
        File   = $File
        Pass   = $Pass
        Detail = $Detail
    }) | Out-Null
    $marker = if ($Pass) { 'PASS' } else { 'FAIL' }
    $color  = if ($Pass) { 'Green' } else { 'Red' }
    Write-Host ("  [{0}] {1,-10} {2,-44} {3}" -f $marker, $Group, $File, $Detail) `
        -ForegroundColor $color
}

function Get-Sha { param([string]$Path)
    return (Get-FileHash $Path -Algorithm SHA256).Hash
}

function Compare-TxtNumericTolerant {
    # Best-effort: parse each whitespace-separated numeric token, diff
    # at the given tolerance. Non-numeric tokens compared as strings.
    # Returns @{ok=$bool; max=$double; nDiff=$int; sample=$string}
    param([string]$A, [string]$B, [double]$Tol = 0.0)
    $la = [System.IO.File]::ReadAllLines($A)
    $lb = [System.IO.File]::ReadAllLines($B)
    if ($la.Length -ne $lb.Length) {
        return @{ok=$false; max=[double]::NaN; nDiff=-1
                 sample="line count differs: a=$($la.Length) b=$($lb.Length)"}
    }
    $maxDiff = 0.0
    $nDiff = 0
    $sample = $null
    for ($i = 0; $i -lt $la.Length; $i++) {
        if ($la[$i] -eq $lb[$i]) { continue }
        $ta = $la[$i] -split '\s+'
        $tb = $lb[$i] -split '\s+'
        if ($ta.Length -ne $tb.Length) {
            $nDiff++
            if (-not $sample) { $sample = "line $($i+1) token count differs" }
            continue
        }
        for ($j = 0; $j -lt $ta.Length; $j++) {
            if ($ta[$j] -eq $tb[$j]) { continue }
            $av = 0.0; $bv = 0.0
            $aIs = [double]::TryParse($ta[$j], [Globalization.NumberStyles]::Any,
                                       [Globalization.CultureInfo]::InvariantCulture, [ref]$av)
            $bIs = [double]::TryParse($tb[$j], [Globalization.NumberStyles]::Any,
                                       [Globalization.CultureInfo]::InvariantCulture, [ref]$bv)
            if ($aIs -and $bIs) {
                $d = [Math]::Abs($av - $bv)
                if ($d -gt $maxDiff) { $maxDiff = $d }
                if ($d -gt $Tol) {
                    $nDiff++
                    if (-not $sample) {
                        $sample = ("line {0} tok {1}: a={2} b={3} diff={4:e3}" -f ($i+1), $j, $av, $bv, $d)
                    }
                }
            } else {
                # Non-numeric mismatch counts as a structural diff.
                $nDiff++
                if (-not $sample) {
                    $sample = ("line {0} tok {1} text differs: a='{2}' b='{3}'" -f ($i+1), $j, $ta[$j], $tb[$j])
                }
            }
        }
    }
    return @{ok=($nDiff -eq 0); max=$maxDiff; nDiff=$nDiff; sample=$sample}
}

function Compare-Pair {
    param([string]$Group, [string]$Rust, [string]$Cs, [double]$Tol = 0.0)
    if (-not (Test-Path $Rust)) {
        Record -Group $Group -File ([IO.Path]::GetFileName($Rust)) -Pass $false -Detail "rust file missing"
        return
    }
    if (-not (Test-Path $Cs)) {
        Record -Group $Group -File ([IO.Path]::GetFileName($Rust)) -Pass $false -Detail "cs file missing"
        return
    }
    $rH = Get-Sha $Rust
    $cH = Get-Sha $Cs
    if ($rH -eq $cH) {
        Record -Group $Group -File ([IO.Path]::GetFileName($Rust)) -Pass $true -Detail ("sha equal {0}" -f $rH.Substring(0,12))
        return
    }
    # SHA differs -- try numeric tolerance diff.
    $r = Compare-TxtNumericTolerant -A $Rust -B $Cs -Tol $Tol
    if ($r.ok) {
        Record -Group $Group -File ([IO.Path]::GetFileName($Rust)) -Pass $true -Detail ("numeric ok within tol={0:e1}, max_diff={1:e3}" -f $Tol, $r.max)
    } else {
        Record -Group $Group -File ([IO.Path]::GetFileName($Rust)) -Pass $false -Detail ("n_diff={0} max_diff={1:e3}; {2}" -f $r.nDiff, $r.max, $r.sample)
    }
}

Write-Host ""
Write-Host "=== Stage 1-3 dump file comparisons (1 ULP, sha first) ===" -ForegroundColor Cyan

# CAL_SAMPLE subdumps. Rust writes global rust_cal_sample.txt; C# writes
# per-file <stem>.cs_cal_sample.txt. Compare each pair.
foreach ($stem in ($mzmls | ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_) })) {
    Compare-Pair -Group 'CAL_SAMPLE' `
        -Rust (Join-Path $rustDir 'rust_cal_sample.txt') `
        -Cs   (Join-Path $csDir   ($stem + '.cs_cal_sample.txt')) `
        -Tol  0.0
}
Compare-Pair -Group 'CAL_SAMPLE' `
    -Rust (Join-Path $rustDir 'rust_cal_scalars.txt') `
    -Cs   (Join-Path $csDir   'cs_cal_scalars.txt') -Tol 0.0
Compare-Pair -Group 'CAL_SAMPLE' `
    -Rust (Join-Path $rustDir 'rust_cal_grid.txt') `
    -Cs   (Join-Path $csDir   'cs_cal_grid.txt') -Tol 0.0

Compare-Pair -Group 'CAL_WINDOWS' `
    -Rust (Join-Path $rustDir 'rust_cal_windows.txt') `
    -Cs   (Join-Path $csDir   'cs_cal_windows.txt') -Tol 0.0
Compare-Pair -Group 'CAL_MATCH' `
    -Rust (Join-Path $rustDir 'rust_cal_match.txt') `
    -Cs   (Join-Path $csDir   'cs_cal_match.txt') -Tol 0.0
Compare-Pair -Group 'LDA_SCORES' `
    -Rust (Join-Path $rustDir 'rust_lda_scores.txt') `
    -Cs   (Join-Path $csDir   'cs_lda_scores.txt') -Tol 0.0
Compare-Pair -Group 'LOESS_INPUT' `
    -Rust (Join-Path $rustDir 'rust_loess_input.txt') `
    -Cs   (Join-Path $csDir   'cs_loess_input.txt') -Tol 0.0

# calibration.json (boundary file). Use tolerance JSON diff.
$jsonDiff = Join-Path $scriptDir 'json_tol_diff.py'
foreach ($f in $mzmls) {
    $stem = [IO.Path]::GetFileNameWithoutExtension($f)
    $r = Join-Path $rustDir ($stem + '.calibration.json')
    $c = Join-Path $csDir   ($stem + '.calibration.json')
    if ((Test-Path $r) -and (Test-Path $c)) {
        $rH = Get-Sha $r; $cH = Get-Sha $c
        if ($rH -eq $cH) {
            Record -Group 'CAL_JSON' -File ([IO.Path]::GetFileName($r)) -Pass $true `
                -Detail ("sha equal {0}" -f $rH.Substring(0,12))
        } elseif (Test-Path $jsonDiff) {
            $log = Join-Path $cmpDir ("caljson_{0}.log" -f $stem)
            python $jsonDiff $r $c --tolerance 1e-15 *>&1 |
                Tee-Object -FilePath $log | Out-Null
            $ok = ($LASTEXITCODE -eq 0)
            Record -Group 'CAL_JSON' -File ([IO.Path]::GetFileName($r)) -Pass $ok `
                -Detail ("see {0}" -f (Split-Path -Leaf $log))
        } else {
            Record -Group 'CAL_JSON' -File ([IO.Path]::GetFileName($r)) -Pass $false `
                -Detail "sha differs and json_tol_diff.py missing"
        }
    } else {
        Record -Group 'CAL_JSON' -File ([IO.Path]::GetFileName($r)) -Pass $false `
            -Detail "missing one side"
    }
}

Write-Host ""
Write-Host "=== Stage 4 .scores.parquet (parquet_diff --tolerance 0) ===" -ForegroundColor Cyan
$parquetDiff = Join-Path $scriptDir 'parquet_diff.py'
foreach ($f in $mzmls) {
    $stem = [IO.Path]::GetFileNameWithoutExtension($f)
    $r = Join-Path $rustDir ($stem + '.scores.parquet')
    $c = Join-Path $csDir   ($stem + '.scores.parquet')
    if ((Test-Path $r) -and (Test-Path $c)) {
        $log = Join-Path $cmpDir ("stage4_parquet_{0}.log" -f $stem)
        python $parquetDiff $r $c --tolerance 0 *>&1 |
            Tee-Object -FilePath $log | Out-Null
        $ok = ($LASTEXITCODE -eq 0)
        Record -Group 'SCORES_PQ' -File ([IO.Path]::GetFileName($r)) -Pass $ok `
            -Detail ("see {0}" -f (Split-Path -Leaf $log))
    } else {
        Record -Group 'SCORES_PQ' -File ([IO.Path]::GetFileName($r)) -Pass $false `
            -Detail "missing one side"
    }
}

# -------- SUMMARY --------
Write-Host ""
Write-Host "=== Summary ===" -ForegroundColor Cyan
Write-Host ("  Walls: Rust {0:mm\:ss}, C# {1:mm\:ss}" -f $rustWall, $csWall)
$nPass = ($results | Where-Object Pass).Count
$nFail = ($results | Where-Object { -not $_.Pass }).Count
Write-Host ("  Boundaries: {0} PASS, {1} FAIL (of {2})" -f $nPass, $nFail, $results.Count)
if ($nFail -gt 0) {
    Write-Host ""
    Write-Host "  First failure group (in stage order):" -ForegroundColor Yellow
    $order = @('CAL_SAMPLE','CAL_WINDOWS','CAL_MATCH','LDA_SCORES','LOESS_INPUT','CAL_JSON','SCORES_PQ')
    foreach ($g in $order) {
        $gf = $results | Where-Object { $_.Group -eq $g -and -not $_.Pass } | Select-Object -First 1
        if ($gf) {
            Write-Host ("    first FAIL: {0}  {1}" -f $g, $gf.File) -ForegroundColor Yellow
            break
        }
    }
    exit 1
} else {
    Write-Host ""
    Write-Host ("OVERALL: PASS -- Stage 1-4 bit-equal cross-impl at every diagnostic checkpoint on {0} {1}" -f `
        $Dataset, $Files) -ForegroundColor Green
    exit 0
}
