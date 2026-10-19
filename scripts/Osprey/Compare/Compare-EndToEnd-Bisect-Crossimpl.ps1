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

      Stage 3   <stem>.calibration.json           content (calibration_diff.py)
      Stage 4   <stem>.scores.parquet             parquet_diff 1e-9 per column
      Stage 6   <stem>.reconciliation.json        content (reconciliation_diff.py)
      Stage 5   FDR score sidecars, both passes   Compare-FdrSidecars-Crossimpl 1e-9
                (reported once, at Stage 5; its log names the pass that differs)
      Stage 6   reconciled scores parquet         parquet_diff 1e-9 per column
      Stage 7   *_stage7_protein_fdr.tsv          Compare-Stage7-Crossimpl 1e-9
      Blib      output.blib                       Compare-Blib-Crossimpl 1e-9

    The two sides keep their scores parquets differently. Rust rewrites
    <stem>.scores.parquet IN PLACE at Stage 6, so its end-to-end run holds
    no Stage 4 parquet; C# leaves <stem>.scores.parquet as the Stage 4
    output and writes Stage 6 to <stem>.scores-reconciled.parquet. So:

      Stage 4  an extra Rust run with --no-join (stops after Stage 4, in
               rust_stage4/) against the C# end-to-end run's
               .scores.parquet, over the shared entry_ids.
      Stage 6  Rust's rewritten .scores.parquet against C#'s
               .scores-reconciled.parquet. C# keeps only the survivors, so
               every C# row must be in Rust (--b-subset); the Rust-only rows
               are the non-survivors and do not fail the boundary.

    Both ignore modified_sequence (UniMod vs +mass notation, never parity)
    and Stage 6 ignores score_index (a C#-only row ordinal).

    Exit codes:
      0 = all boundaries PASS at tolerance
      1 = one or more boundaries FAIL (first-FAIL stage is printed)
      2 = setup error (missing binary, missing data, etc.)

.PARAMETER Dataset
    Stellar (default) or Astral.

.PARAMETER TestBaseDir
    Override dataset root (defaults to the regression data tree,
    <Downloads>\Perftests\osprey-testfiles-mzML-v2, as Compare-EndToEnd-Crossimpl.ps1).
    Work goes to pwiz_tools/Osprey/TestResults/crossbisect-<dataset>.

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
    [int]$Threads = 16,
    [string]$CsExe,
    [string]$RustExe
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $PSCommandPath
$configCandidates = @(
    (Join-Path $scriptDir 'Dataset-Config.ps1'),
    (Join-Path $scriptDir '..\Dataset-Config.ps1')
)
foreach ($c in $configCandidates) { if (Test-Path $c) { . $c; break } }

$ospreyExe = if ($RustExe) { $RustExe } else { Get-OspreyRustExe }
if (-not (Test-Path $ospreyExe)) {
    Write-Host "osprey.exe not found at $ospreyExe -- build first." -ForegroundColor Red
    exit 2
}
$ospreyShExe = if ($CsExe) { $CsExe } else { Get-OspreyExe }
if (-not (Test-Path $ospreyShExe)) {
    Write-Host "Osprey.exe not found at $ospreyShExe -- build first." -ForegroundColor Red
    exit 2
}

# The read-only data tree regression.ps1 and Compare-EndToEnd-Crossimpl.ps1 use
# (<Downloads>\Perftests\osprey-testfiles-mzML-v2, acquired skip-if-present).
. (Join-Path (Get-PwizRoot) 'pwiz_tools/Osprey/Regression/RegressionData.ps1')
if ([string]::IsNullOrEmpty($TestBaseDir)) {
    $dataUrl = 'https://panoramaweb.org/_webdav/MacCoss/software/%40files/perftests/osprey-testfiles-mzML-v2.zip'
    $TestBaseDir = Get-RegressionData -Url $dataUrl
}
$ds = Get-DatasetConfig $Dataset -TestBaseDir $TestBaseDir
$mzmls = @($ds.AllFiles)
$libraryName = $ds.Library
$resolution = $ds.Resolution
$datasetRoot = $ds.TestDir

# Workdirs under the C# checkout's gitignored TestResults, beside the gate's crossimpl-*
# dirs; the data tree gets nothing written into it (inputs are copied in per side).
$rootDir = Join-Path (Get-PwizRoot) ("pwiz_tools/Osprey/TestResults/crossbisect-" + $Dataset.ToLowerInvariant())
$rustDir = Join-Path $rootDir "rust"
$rustStage4Dir = Join-Path $rootDir "rust_stage4"
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
    # Rust logs "Wrote N precursors"; C# "Wrote N library spectra ..." (as the gate reads it).
    $m = Select-String -Path $LogPath -Pattern 'Wrote\s+(\d[\d,]*)\s+(?:\w+\s+)?(?:precursors|spectra)' -AllMatches | Select-Object -Last 1
    if ($m -and $m.Matches.Count -gt 0) { return [int]($m.Matches[0].Groups[1].Value -replace ',', '') }
    return -1
}

function Format-Duration { param([TimeSpan]$T) ('{0:mm\:ss}' -f $T) }

# ============================================================
#                       RUN BOTH SIDES
# ============================================================

Write-Host ""
Write-Host "=== Compare-EndToEnd-Bisect-Crossimpl (Pass 1: major outputs only) ===" -ForegroundColor Cyan
Write-Host ("Dataset: {0} ({1} files)" -f $Dataset, $mzmls.Count)
Write-Host ("Workdir: {0}" -f $rootDir)
Write-Host ""

function Run-Side {
    param([string]$SideName, [string]$Exe, [string]$Dir, [switch]$Skip, [string[]]$Extra = @())
    $logName = if ($SideName -eq 'cs') { 'osprey-cs.log' } else { 'osprey.log' }
    $logPath = Join-Path $Dir $logName
    # A --no-join run stops after Stage 4 and writes no library; its last output is the
    # final run's scores parquet.
    $stage4Only = $Extra -contains '--no-join'
    $lastOutput = if ($stage4Only) {
        Join-Path $Dir ([System.IO.Path]::GetFileNameWithoutExtension($mzmls[-1]) + '.scores.parquet')
    } else {
        Join-Path $Dir 'output.blib'
    }
    if ($Skip -and (Test-Path $lastOutput) -and (Test-Path $logPath)) {
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
    $cliArgs += $Extra
    # Only Stage 7 dump enabled in Pass 1 (it doesn't produce a file
    # otherwise). All other boundary files are written naturally.
    $env:OSPREY_DUMP_STAGE7_PROTEIN_FDR = '1'
    # Both implementations keep the most regularized first-pass SVM C within 1% of the best
    # (C# #4703, Rust #69); an inherited OSPREY_SVM_C_TOLERANCE would split them at Stage 5.
    Remove-Item Env:OSPREY_SVM_C_TOLERANCE -ErrorAction SilentlyContinue
    try {
        $r = Invoke-Tool -Exe $Exe -WorkDir $Dir -CliArgs $cliArgs -LogName $logName
    } finally {
        Remove-Item Env:OSPREY_DUMP_STAGE7_PROTEIN_FDR -ErrorAction SilentlyContinue
        Remove-Item Env:OSPREY_SVM_C_TOLERANCE -ErrorAction SilentlyContinue
    }
    if ($stage4Only) {
        Write-Host ("  {0} wall: {1}; stopped after Stage 4" -f $SideName, (Format-Duration $r.wall)) -ForegroundColor Green
    } else {
        $prec = Get-PrecursorCount -LogPath $r.logPath
        Write-Host ("  {0} wall: {1}; precursors: {2}" -f $SideName, (Format-Duration $r.wall), $prec) -ForegroundColor Green
    }
    return $r
}

$rustResult = Run-Side -SideName 'rust' -Exe $ospreyExe   -Dir $rustDir -Skip:$SkipRust
# Rust's end-to-end run rewrites its Stage 4 parquet at Stage 6; this run keeps one.
$null       = Run-Side -SideName 'rust_stage4' -Exe $ospreyExe -Dir $rustStage4Dir -Skip:$SkipRust -Extra @('--no-join')
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

# --- Stage 3: calibration.json (content) ---
# Never byte-comparable: C# writes a validity stamp and its report's calibration-view row
# (model_diagnostics), and both sides time-stamp the run. calibration_diff.py drops those and
# compares every calibration value exactly.
$calDiff = Join-Path $scriptDir 'calibration_diff.py'
foreach ($stem in $stems) {
    $r = Join-Path $rustDir ($stem + '.calibration.json')
    $c = Join-Path $csDir   ($stem + '.calibration.json')
    if ((Test-Path $r) -and (Test-Path $c)) {
        # Capture all output first: piping straight into Select-Object -First 1 stops the
        # pipeline before $LASTEXITCODE is set, so a failing diff read as the previous PASS.
        $out = @(python $calDiff $r $c 2>&1)
        $ok = ($LASTEXITCODE -eq 0)
        Record-Stage -Stage 'stage3' -Boundary ("calibration.json[{0}]" -f $stem) `
            -Pass $ok -Detail ([string]($out | Select-Object -First 1))
    } else {
        Record-Stage -Stage 'stage3' -Boundary ("calibration.json[{0}]" -f $stem) `
            -Pass $false -Detail "missing on one side"
    }
}

# --- Stage 4 / Stage 6: scores parquets (parquet_diff 1e-9 per column) ---
$parquetDiff = Join-Path $scriptDir 'parquet_diff.py'
function Compare-ScoresParquet {
    param([string]$Stage, [string]$Stem, [string]$RustPath, [string]$CsPath, [string[]]$DiffArgs)
    $boundary = "{0}[{1}]" -f (Split-Path -Leaf $CsPath).Substring($Stem.Length + 1), $Stem
    if (-not ((Test-Path $RustPath) -and (Test-Path $CsPath))) {
        Record-Stage -Stage $Stage -Boundary $boundary -Pass $false -Detail "missing on one side"
        return
    }
    $logPath = Join-Path $cmpDir ("{0}_parquet_{1}.log" -f $Stage, $Stem)
    python $parquetDiff $RustPath $CsPath --tolerance 1e-9 @DiffArgs *>&1 |
        Tee-Object -FilePath $logPath | Out-Null
    Record-Stage -Stage $Stage -Boundary $boundary `
        -Pass ($LASTEXITCODE -eq 0) -Detail ("see {0}" -f (Split-Path -Leaf $logPath))
}

foreach ($stem in $stems) {
    Compare-ScoresParquet -Stage 'stage4' -Stem $stem `
        -RustPath (Join-Path $rustStage4Dir ($stem + '.scores.parquet')) `
        -CsPath   (Join-Path $csDir ($stem + '.scores.parquet')) `
        -DiffArgs @('--common-entries', '--ignore-columns', 'modified_sequence')
}

# --- Stage 6 plan: reconciliation.json (content) ---
# C# v4 dropped four fields Rust still writes and adds a validity stamp, so the files are no
# longer byte-comparable; reconciliation_diff.py drops those and compares the rest exactly.
$reconDiff = Join-Path $scriptDir 'reconciliation_diff.py'
foreach ($stem in $stems) {
    $r = Join-Path $rustDir ($stem + '.reconciliation.json')
    $c = Join-Path $csDir   ($stem + '.reconciliation.json')
    if ((Test-Path $r) -and (Test-Path $c)) {
        $out = @(python $reconDiff $r $c 2>&1)
        $ok = ($LASTEXITCODE -eq 0)
        Record-Stage -Stage 'stage5' -Boundary ("reconciliation.json[{0}]" -f $stem) `
            -Pass $ok -Detail ([string]($out | Select-Object -First 1))
    } else {
        Record-Stage -Stage 'stage5' -Boundary ("reconciliation.json[{0}]" -f $stem) `
            -Pass $false -Detail "missing on one side"
    }
}

# --- Stage 5 / 6b: FDR score sidecars, both passes (Compare-FdrSidecars-Crossimpl 1e-9) ---
# Not byte-comparable since #4486: Rust fuses run and experiment scope into one record per
# file, C# splits them into a per-file and an analysis-wide file. The comparator rebuilds
# Rust's view from the C# pair and compares field by field; its log names the pass.
$sidecarLog = Join-Path $cmpDir 'fdr_sidecar_compare.log'
& pwsh -File (Join-Path $scriptDir 'Compare-FdrSidecars-Crossimpl.ps1') `
    -RustDir $rustDir -CsDir $csDir *>&1 |
    Tee-Object -FilePath $sidecarLog | Out-Null
Record-Stage -Stage 'stage5' -Boundary 'fdr_scores sidecars (1st+2nd pass)' `
    -Pass ($LASTEXITCODE -eq 0) -Detail ("see {0}" -f (Split-Path -Leaf $sidecarLog))

# --- Stage 6: reconciled scores (Rust rewrites in place; C# writes the survivors apart) ---
foreach ($stem in $stems) {
    Compare-ScoresParquet -Stage 'stage6' -Stem $stem `
        -RustPath (Join-Path $rustDir ($stem + '.scores.parquet')) `
        -CsPath   (Join-Path $csDir ($stem + '.scores-reconciled.parquet')) `
        -DiffArgs @('--b-subset', '--ignore-columns', 'modified_sequence,score_index')
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
    $stageOrder = @('stage3','stage4','stage5','stage6','stage7','blib')
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
