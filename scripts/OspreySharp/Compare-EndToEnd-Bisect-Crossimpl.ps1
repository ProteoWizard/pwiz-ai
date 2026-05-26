<#
.SYNOPSIS
    End-to-end Rust-vs-C# bisection: each side runs the full pipeline
    independently (no frozen-input crossfeeding), then every natural
    boundary output is compared in stage order. Reports PASS/FAIL +
    magnitude per boundary so the first-divergence stage is obvious.

.DESCRIPTION
    Pass 1 of the end-to-end bisection workflow. Both sides run
    straight-through (`-i mzMLs -l lib -o blib`) in separate workdirs.
    The driver then walks every boundary file each impl naturally
    writes during a full pipeline run -- NO sub-stage diagnostic dumps
    are enabled in Pass 1 (those come in Pass 2, after this driver
    localizes the divergence band).

    Boundary walk order (continues through all stages; tracks first
    FAIL as the drill band start):

      Stage 3   <stem>.calibration.json           byte equality
      Stage 5   <stem>.reconciliation.json        byte equality
      Stage 5   <stem>.1st-pass.fdr_scores.bin    SHA-256 equality
      Stage 6   <stem>.scores.parquet (rewritten) parquet_diff 1e-9 per column
      Stage 6b  <stem>.2nd-pass.fdr_scores.bin    SHA-256 equality
      Stage 7   *_stage7_protein_fdr.tsv          Compare-Stage7-Crossimpl 1e-9
      Blib      output.blib                       Compare-Blib-Crossimpl 1e-9

    The Stage 4 boundary is NOT compared here (the .scores.parquet is
    rewritten in place at Stage 6 in a single end-to-end run). If
    Stage 5 boundary FAILs, follow up with a --no-join run pair to
    capture pre-Stage-6 .scores.parquet for Stage 4 isolation.

    Exit codes:
      0 = all boundaries PASS at tolerance
      1 = one or more boundaries FAIL (first-FAIL stage is printed)
      2 = setup error (missing binary, missing data, etc.)

.PARAMETER Dataset
    Stellar (default) or Astral.

.PARAMETER TestBaseDir
    Override dataset root (defaults to OSPREY_TEST_BASE_DIR or
    D:\test\osprey-runs).

.PARAMETER Force
    Wipe any existing workdirs before running.

.PARAMETER SkipRust
    Reuse the existing Rust workdir if outputs are on disk.

.PARAMETER SkipCs
    Symmetric to SkipRust for the C# side.

.PARAMETER Threads
    --threads CLI flag. Default 16.

.EXAMPLE
    pwsh -File ./Compare-EndToEnd-Bisect-Crossimpl.ps1 -Dataset Stellar -Force
#>

param(
    [ValidateSet('Stellar','Astral')]
    [string]$Dataset = 'Stellar',
    [string]$TestBaseDir,
    [switch]$Force,
    [switch]$SkipRust,
    [switch]$SkipCs,
    [int]$Threads = 16
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $PSCommandPath
. (Join-Path $scriptDir 'Dataset-Config.ps1')

$projRoot = (Resolve-Path (Join-Path $scriptDir '..\..\..')).Path
$ospreyExe = Join-Path $projRoot 'osprey\target\release\osprey.exe'
if (-not (Test-Path $ospreyExe)) {
    Write-Host "osprey.exe not found at $ospreyExe -- build first." -ForegroundColor Red
    exit 2
}
$ospreyShExe = Join-Path $projRoot 'pwiz\pwiz_tools\OspreySharp\OspreySharp\bin\x64\Release\net472\OspreySharp.exe'
if (-not (Test-Path $ospreyShExe)) {
    Write-Host "OspreySharp.exe not found at $ospreyShExe -- build first." -ForegroundColor Red
    exit 2
}

$ds = Get-DatasetConfig $Dataset -TestBaseDir $TestBaseDir
$mzmls = @($ds.AllFiles)
$libraryName = $ds.Library
$resolution = $ds.Resolution
$datasetRoot = $ds.TestDir

$rootDir = Join-Path $datasetRoot "_endtoend_bisect"
$rustDir = Join-Path $rootDir "rust"
$csDir   = Join-Path $rootDir "cs"
$cmpDir  = Join-Path $rootDir "compare_logs"

if ($Force -and (Test-Path $rootDir)) {
    Write-Host "[Bisect] -Force: removing $rootDir" -ForegroundColor DarkYellow
    Remove-Item $rootDir -Recurse -Force
}
New-Item -ItemType Directory -Path $rootDir -Force | Out-Null
New-Item -ItemType Directory -Path $cmpDir  -Force | Out-Null

function Stage-DatasetFiles {
    param([string]$Dir)
    foreach ($f in $mzmls) {
        Copy-Item (Join-Path $datasetRoot $f) (Join-Path $Dir $f)
    }
    Copy-Item (Join-Path $datasetRoot $libraryName) (Join-Path $Dir $libraryName)
    $cache = Join-Path $datasetRoot ($libraryName + '.libcache')
    if (Test-Path $cache) {
        Copy-Item $cache (Join-Path $Dir ($libraryName + '.libcache'))
    }
}

function Invoke-Tool {
    param([string]$Exe, [string]$WorkDir, [string[]]$CliArgs, [string]$LogName)
    $logPath = Join-Path $WorkDir $LogName
    Push-Location $WorkDir
    try {
        $sw = [Diagnostics.Stopwatch]::StartNew()
        & $Exe @CliArgs 2>&1 | Tee-Object -FilePath $logPath | Out-Null
        $exit = $LASTEXITCODE
        $sw.Stop()
        if ($exit -ne 0) {
            throw "Tool exited $exit; see $logPath."
        }
        return @{ wall = $sw.Elapsed; logPath = $logPath }
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

function Get-Sha256 {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    return (Get-FileHash -Path $Path -Algorithm SHA256).Hash
}

# ============================================================
#                       RUN BOTH SIDES
# ============================================================

Write-Host ""
Write-Host "=== Compare-EndToEnd-Bisect-Crossimpl (Pass 1: major outputs only) ===" -ForegroundColor Cyan
Write-Host ("Dataset: {0} ({1} files)" -f $Dataset, $mzmls.Count)
Write-Host ("Workdir: {0}" -f $rootDir)
Write-Host ""

function Run-Side {
    param([string]$SideName, [string]$Exe, [string]$Dir, [switch]$Skip)
    $logName = if ($SideName -eq 'rust') { 'osprey.log' } else { 'ospreysharp.log' }
    $logPath = Join-Path $Dir $logName
    $blibPath = Join-Path $Dir 'output.blib'
    if ($Skip -and (Test-Path $blibPath) -and (Test-Path $logPath)) {
        Write-Host ("[{0}] -Skip: reusing existing outputs in {1}" -f $SideName, $Dir) -ForegroundColor DarkGray
        return @{ wall = [TimeSpan]::Zero; logPath = $logPath }
    }
    if (Test-Path $Dir) { Remove-Item $Dir -Recurse -Force }
    New-Item -ItemType Directory -Path $Dir -Force | Out-Null
    Stage-DatasetFiles -Dir $Dir
    Write-Host ("[{0}] {1} -i mzMLs ... (full pipeline) ..." -f $SideName, (Split-Path -Leaf $Exe)) -ForegroundColor Cyan
    $cliArgs = @()
    foreach ($f in $mzmls) { $cliArgs += @('-i', $f) }
    $cliArgs += @('-l', $libraryName, '-o', 'output.blib',
                  '--resolution', $resolution,
                  '--protein-fdr', '0.01', '--threads', $Threads.ToString())
    # Only Stage 7 dump enabled in Pass 1 (it doesn't produce a file
    # otherwise). All other boundary files are written naturally.
    $env:OSPREY_DUMP_STAGE7_PROTEIN_FDR = '1'
    try {
        $r = Invoke-Tool -Exe $Exe -WorkDir $Dir -CliArgs $cliArgs -LogName $logName
    } finally {
        Remove-Item Env:OSPREY_DUMP_STAGE7_PROTEIN_FDR -ErrorAction SilentlyContinue
    }
    $prec = Get-PrecursorCount -LogPath $r.logPath
    Write-Host ("  {0} wall: {1}; precursors: {2}" -f $SideName, (Format-Duration $r.wall), $prec) -ForegroundColor Green
    return $r
}

$rustResult = Run-Side -SideName 'rust' -Exe $ospreyExe   -Dir $rustDir -Skip:$SkipRust
$csResult   = Run-Side -SideName 'cs'   -Exe $ospreyShExe -Dir $csDir   -Skip:$SkipCs
$rustWall = $rustResult.wall
$csWall   = $csResult.wall

# ============================================================
#                    BOUNDARY WALK (PASS 1)
# ============================================================

# Track each stage outcome for the summary table.
$results = New-Object System.Collections.Generic.List[object]
$firstFailStage = $null

function Record-Stage {
    param([string]$Stage, [string]$Boundary, [bool]$Pass, [string]$Detail)
    $script:results.Add([pscustomobject]@{
        Stage    = $Stage
        Boundary = $Boundary
        Pass     = $Pass
        Detail   = $Detail
    }) | Out-Null
    if (-not $Pass -and $null -eq $script:firstFailStage) {
        $script:firstFailStage = $Stage
    }
    $marker = if ($Pass) { 'PASS' } else { 'FAIL' }
    $color = if ($Pass) { 'Green' } else { 'Red' }
    Write-Host ("  [{0}] {1,-32} {2}  {3}" -f $marker, $Boundary, $Stage, $Detail) -ForegroundColor $color
}

Write-Host ""
Write-Host "=== Boundary walk (each side's own end-to-end outputs, no crossfeeding) ===" -ForegroundColor Cyan

# Resolve per-file stems.
$stems = @($mzmls | ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_) })

# --- Stage 3: calibration.json (byte equality) ---
foreach ($stem in $stems) {
    $r = Join-Path $rustDir ($stem + '.calibration.json')
    $c = Join-Path $csDir   ($stem + '.calibration.json')
    if ((Test-Path $r) -and (Test-Path $c)) {
        $rH = Get-Sha256 $r
        $cH = Get-Sha256 $c
        if ($rH -eq $cH) {
            Record-Stage -Stage 'stage3' -Boundary ("calibration.json[{0}]" -f $stem) `
                -Pass $true -Detail ("sha equal {0}" -f $rH.Substring(0,12))
        } else {
            $rLen = (Get-Item $r).Length
            $cLen = (Get-Item $c).Length
            Record-Stage -Stage 'stage3' -Boundary ("calibration.json[{0}]" -f $stem) `
                -Pass $false -Detail ("sha differ; sizes rust={0} cs={1}" -f $rLen, $cLen)
        }
    } else {
        Record-Stage -Stage 'stage3' -Boundary ("calibration.json[{0}]" -f $stem) `
            -Pass $false -Detail "missing on one side"
    }
}

# --- Stage 5: reconciliation.json (byte equality) ---
foreach ($stem in $stems) {
    $r = Join-Path $rustDir ($stem + '.reconciliation.json')
    $c = Join-Path $csDir   ($stem + '.reconciliation.json')
    if ((Test-Path $r) -and (Test-Path $c)) {
        $rH = Get-Sha256 $r
        $cH = Get-Sha256 $c
        if ($rH -eq $cH) {
            Record-Stage -Stage 'stage5' -Boundary ("reconciliation.json[{0}]" -f $stem) `
                -Pass $true -Detail ("sha equal {0}" -f $rH.Substring(0,12))
        } else {
            $rLen = (Get-Item $r).Length
            $cLen = (Get-Item $c).Length
            Record-Stage -Stage 'stage5' -Boundary ("reconciliation.json[{0}]" -f $stem) `
                -Pass $false -Detail ("sha differ; sizes rust={0} cs={1}" -f $rLen, $cLen)
        }
    } else {
        Record-Stage -Stage 'stage5' -Boundary ("reconciliation.json[{0}]" -f $stem) `
            -Pass $false -Detail "missing on one side"
    }
}

# --- Stage 5: 1st-pass.fdr_scores.bin (SHA equality) ---
foreach ($stem in $stems) {
    $r = Join-Path $rustDir ($stem + '.1st-pass.fdr_scores.bin')
    $c = Join-Path $csDir   ($stem + '.1st-pass.fdr_scores.bin')
    if ((Test-Path $r) -and (Test-Path $c)) {
        $rH = Get-Sha256 $r
        $cH = Get-Sha256 $c
        if ($rH -eq $cH) {
            Record-Stage -Stage 'stage5' -Boundary ("1st-pass.fdr_scores.bin[{0}]" -f $stem) `
                -Pass $true -Detail ("sha equal {0}" -f $rH.Substring(0,12))
        } else {
            $rLen = (Get-Item $r).Length
            $cLen = (Get-Item $c).Length
            Record-Stage -Stage 'stage5' -Boundary ("1st-pass.fdr_scores.bin[{0}]" -f $stem) `
                -Pass $false -Detail ("sha differ; sizes rust={0} cs={1}" -f $rLen, $cLen)
        }
    } else {
        Record-Stage -Stage 'stage5' -Boundary ("1st-pass.fdr_scores.bin[{0}]" -f $stem) `
            -Pass $false -Detail "missing on one side"
    }
}

# --- Stage 6: reconciled scores.parquet (parquet_diff 1e-9 per column) ---
$parquetDiff = Join-Path $scriptDir 'parquet_diff.py'
foreach ($stem in $stems) {
    $r = Join-Path $rustDir ($stem + '.scores.parquet')
    $c = Join-Path $csDir   ($stem + '.scores.parquet')
    if ((Test-Path $r) -and (Test-Path $c)) {
        $logPath = Join-Path $cmpDir ("stage6_parquet_{0}.log" -f $stem)
        python $parquetDiff $r $c --tolerance 1e-9 *>&1 |
            Tee-Object -FilePath $logPath | Out-Null
        $ok = ($LASTEXITCODE -eq 0)
        # Pull a short summary line for the detail column.
        $summary = (Get-Content $logPath | Select-String -Pattern '^(===|\[DIFF\]|ROW COUNT)' | Select-Object -First 3) -join '; '
        if (-not $summary) { $summary = 'all columns within 1e-9' }
        Record-Stage -Stage 'stage6' -Boundary ("scores.parquet[{0}]" -f $stem) `
            -Pass $ok -Detail ("see {0}" -f (Split-Path -Leaf $logPath))
    } else {
        Record-Stage -Stage 'stage6' -Boundary ("scores.parquet[{0}]" -f $stem) `
            -Pass $false -Detail "missing on one side"
    }
}

# --- Stage 6b: 2nd-pass.fdr_scores.bin (SHA equality) ---
foreach ($stem in $stems) {
    $r = Join-Path $rustDir ($stem + '.2nd-pass.fdr_scores.bin')
    $c = Join-Path $csDir   ($stem + '.2nd-pass.fdr_scores.bin')
    if ((Test-Path $r) -and (Test-Path $c)) {
        $rH = Get-Sha256 $r
        $cH = Get-Sha256 $c
        if ($rH -eq $cH) {
            Record-Stage -Stage 'stage6b' -Boundary ("2nd-pass.fdr_scores.bin[{0}]" -f $stem) `
                -Pass $true -Detail ("sha equal {0}" -f $rH.Substring(0,12))
        } else {
            $rLen = (Get-Item $r).Length
            $cLen = (Get-Item $c).Length
            Record-Stage -Stage 'stage6b' -Boundary ("2nd-pass.fdr_scores.bin[{0}]" -f $stem) `
                -Pass $false -Detail ("sha differ; sizes rust={0} cs={1}" -f $rLen, $cLen)
        }
    } else {
        Record-Stage -Stage 'stage6b' -Boundary ("2nd-pass.fdr_scores.bin[{0}]" -f $stem) `
            -Pass $false -Detail "missing on one side"
    }
}

# --- Stage 7: protein FDR dump (Compare-Stage7-Crossimpl 1e-9) ---
$rustDump = Join-Path $rustDir 'rust_stage7_protein_fdr.tsv'
$csDump   = Join-Path $csDir   'cs_stage7_protein_fdr.tsv'
if ((Test-Path $rustDump) -and (Test-Path $csDump)) {
    $stage7Log = Join-Path $cmpDir 'stage7_compare.log'
    & pwsh -File (Join-Path $scriptDir 'Compare-Stage7-Crossimpl.ps1') `
        -RustTsv $rustDump -CsTsv $csDump *>&1 |
        Tee-Object -FilePath $stage7Log | Out-Null
    $ok = ($LASTEXITCODE -eq 0)
    Record-Stage -Stage 'stage7' -Boundary 'stage7_protein_fdr.tsv' `
        -Pass $ok -Detail ("see {0}" -f (Split-Path -Leaf $stage7Log))
} else {
    Record-Stage -Stage 'stage7' -Boundary 'stage7_protein_fdr.tsv' `
        -Pass $false -Detail "dump missing on one side"
}

# --- Blib (Compare-Blib-Crossimpl 1e-9) ---
$rustBlib = Join-Path $rustDir 'output.blib'
$csBlib   = Join-Path $csDir   'output.blib'
if ((Test-Path $rustBlib) -and (Test-Path $csBlib)) {
    $blibLog = Join-Path $cmpDir 'blib_compare.log'
    & pwsh -File (Join-Path $scriptDir 'Compare-Blib-Crossimpl.ps1') `
        -RustBlib $rustBlib -CsBlib $csBlib *>&1 |
        Tee-Object -FilePath $blibLog | Out-Null
    $ok = ($LASTEXITCODE -eq 0)
    Record-Stage -Stage 'blib' -Boundary 'output.blib' `
        -Pass $ok -Detail ("see {0}" -f (Split-Path -Leaf $blibLog))
} else {
    Record-Stage -Stage 'blib' -Boundary 'output.blib' `
        -Pass $false -Detail "missing on one side"
}

# ============================================================
#                      SUMMARY
# ============================================================

Write-Host ""
Write-Host "=== Summary ===" -ForegroundColor Cyan
Write-Host ("  Walls: Rust {0}, C# {1}" -f (Format-Duration $rustWall), (Format-Duration $csWall))

$nPass = ($results | Where-Object Pass).Count
$nFail = ($results | Where-Object { -not $_.Pass }).Count
Write-Host ("  Boundaries: {0} PASS, {1} FAIL (of {2} compared)" -f $nPass, $nFail, $results.Count)

if ($firstFailStage) {
    # Find the last passing stage BEFORE the first-fail.
    $stageOrder = @('stage3','stage5','stage6','stage6b','stage7','blib')
    $firstFailIdx = $stageOrder.IndexOf($firstFailStage)
    $lastPassStage = if ($firstFailIdx -gt 0) { $stageOrder[$firstFailIdx - 1] } else { '(none -- divergence starts at first compared stage)' }
    Write-Host ""
    Write-Host "  First divergence band:" -ForegroundColor Yellow
    Write-Host ("    last passing stage : {0}" -f $lastPassStage)
    Write-Host ("    first failing stage: {0}" -f $firstFailStage)
    Write-Host "  Pass 2 should enable OSPREY_DUMP_* env-vars within this band to localize further." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "OVERALL: FAIL" -ForegroundColor Red
    exit 1
} else {
    Write-Host ""
    Write-Host "OVERALL: PASS -- Rust and C# end-to-end in-memory bit-parity at every boundary on $Dataset $($mzmls.Count)-file" -ForegroundColor Green
    exit 0
}
