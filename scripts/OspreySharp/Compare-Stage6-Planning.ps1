<#
.SYNOPSIS
    Cross-impl Stage 6 planning-checkpoint byte-parity gate.

.DESCRIPTION
    Runs both Rust osprey and OspreySharp in --join-only mode against all
    pre-generated .scores.rust.parquet files in a dataset, with each of
    three Stage 6 planning dump env-vars set in turn:

        OSPREY_DUMP_CONSENSUS    + OSPREY_CONSENSUS_ONLY
        OSPREY_DUMP_MULTICHARGE  + OSPREY_MULTICHARGE_ONLY
        OSPREY_DUMP_REFIT        + OSPREY_REFIT_ONLY

    Each pair triggers an early exit after the corresponding dump.
    The dump file pairs (rust_stage6_<name>.tsv vs cs_stage6_<name>.tsv)
    are then compared byte-for-byte via SHA-256.

    Pass = all three pairs match across both datasets; fail = any mismatch.

    Run Generate-AllScoresParquet.ps1 first to produce the rust Parquets.

.PARAMETER Dataset
    Stellar | Astral | Both (default Both).

.PARAMETER CsharpRoot
    pwiz worktree with built OspreySharp.exe (auto-detect if omitted).

.PARAMETER TargetFramework
    net472 or net8.0 (default net8.0).

.PARAMETER TestBaseDir
    Override test data root.

.PARAMETER KeepWorkDirs
    Preserve _stage6_planning/ work dir after the run (default true).

.EXAMPLE
    .\Compare-Stage6-Planning.ps1 -Dataset Stellar
#>

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("Stellar", "Astral", "Both")]
    [string]$Dataset = "Both",

    [string]$CsharpRoot = $null,

    [ValidateSet("net472", "net8.0")]
    [string]$TargetFramework = "net8.0",

    [string]$TestBaseDir = $null,

    [bool]$KeepWorkDirs = $true
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

. "$PSScriptRoot\Dataset-Config.ps1"

$scriptRoot = Split-Path -Parent $PSCommandPath
$aiRoot = Split-Path -Parent (Split-Path -Parent $scriptRoot)
$projRoot = Split-Path -Parent $aiRoot

$rustBinary = Join-Path $projRoot "osprey\target\release\osprey.exe"
if (-not (Test-Path $rustBinary)) { Write-Error "Rust binary not found: $rustBinary"; exit 1 }

$csharpRelBin = "pwiz_tools\OspreySharp\OspreySharp\bin\x64\Release\$TargetFramework\OspreySharp.exe"
if ($CsharpRoot) { $csharpBase = $CsharpRoot } else {
    $csharpBase = $null
    foreach ($c in @("pwiz-work1", "pwiz", "pwiz-work2")) {
        $p = Join-Path $projRoot $c
        if (Test-Path (Join-Path $p $csharpRelBin)) { $csharpBase = $p; break }
    }
    if (-not $csharpBase) { $csharpBase = Join-Path $projRoot "pwiz" }
}
$csharpBinary = Join-Path $csharpBase $csharpRelBin
if (-not (Test-Path $csharpBinary)) { Write-Error "OspreySharp binary not found: $csharpBinary"; exit 1 }

Write-Host "Rust binary: $rustBinary" -ForegroundColor DarkGray
Write-Host "C#   binary: $csharpBinary" -ForegroundColor DarkGray
Write-Host ""

$datasets = if ($Dataset -eq "Both") { @("Stellar","Astral") } else { @($Dataset) }

# Each spec triggers a single dump + early exit. Run all three sequentially
# so each dump is produced in its own clean workdir and dump-only short
# circuits keep wall clock low.
$dumpSpecs = @(
    # Stage 5 percolator dump in 3-file mode is included as a precondition:
    # cross-impl Stage 6 parity is only meaningful when 3-file Stage 5 already
    # agrees byte-for-byte. The dump filename uses the Stage 5 prefix
    # (rust_stage5_percolator.tsv / cs_stage5_percolator.tsv).
    @{ Name = "stage5_percolator"; DumpVar = "OSPREY_DUMP_PERCOLATOR"; OnlyVar = "OSPREY_PERCOLATOR_ONLY"; FilePrefix = "stage5_percolator" },
    @{ Name = "calibration";       DumpVar = "OSPREY_DUMP_CALIBRATION";OnlyVar = "OSPREY_CALIBRATION_ONLY"; FilePrefix = "stage6_calibration" },
    @{ Name = "inv_predict";       DumpVar = "OSPREY_DUMP_INV_PREDICT";OnlyVar = "OSPREY_INV_PREDICT_ONLY"; FilePrefix = "stage6_inv_predict" },
    @{ Name = "consensus";         DumpVar = "OSPREY_DUMP_CONSENSUS";  OnlyVar = "OSPREY_CONSENSUS_ONLY";   FilePrefix = "stage6_consensus" },
    @{ Name = "multicharge";       DumpVar = "OSPREY_DUMP_MULTICHARGE";OnlyVar = "OSPREY_MULTICHARGE_ONLY"; FilePrefix = "stage6_multicharge" },
    @{ Name = "refit";             DumpVar = "OSPREY_DUMP_REFIT";      OnlyVar = "OSPREY_REFIT_ONLY";       FilePrefix = "stage6_refit" }
)

function Invoke-Stage6Dump {
    param(
        [string]$Tool,
        [string]$Binary,
        [string[]]$ParquetPaths,
        [string]$Library,
        [string]$Resolution,
        [string]$WorkDir
    )
    $outBlib = Join-Path $WorkDir ("_discard_{0}.blib" -f $Tool.ToLower())
    # Repeat --input-scores once per parquet (both Rust clap and the C# arg
    # parser accept multi-occurrence flags).
    $inputArgs = @()
    foreach ($p in $ParquetPaths) {
        $inputArgs += "--input-scores"
        $inputArgs += $p
    }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    Push-Location $WorkDir
    try {
        & $Binary --join-only @inputArgs -l $Library --output $outBlib `
            --resolution $Resolution --protein-fdr 0.01 2>&1 | Out-Null
        $exit = $LASTEXITCODE
    } finally { Pop-Location }
    $sw.Stop()
    return [PSCustomObject]@{
        Tool = $Tool
        ExitCode = $exit
        ElapsedSec = [math]::Round($sw.Elapsed.TotalSeconds, 2)
    }
}

$allResults = @()
$totalStart = [Diagnostics.Stopwatch]::StartNew()

foreach ($dsName in $datasets) {
    $ds = Get-DatasetConfig $dsName -TestBaseDir $TestBaseDir
    $testDir = $ds.TestDir
    $library = Join-Path $testDir $ds.Library

    Write-Host ("=== {0} (TestDir: {1}) ===" -f $ds.Name, $testDir) -ForegroundColor Cyan

    $parquets = @()
    foreach ($mzmlName in $ds.AllFiles) {
        $stem = [IO.Path]::GetFileNameWithoutExtension($mzmlName)
        $rustParquet = Join-Path $testDir "$stem.scores.rust.parquet"
        if (-not (Test-Path $rustParquet)) {
            Write-Host ("  missing rust parquet for {0} — run Generate-AllScoresParquet.ps1 first" -f $stem) -ForegroundColor Red
            continue
        }
        $parquets += $rustParquet
    }
    if ($parquets.Count -ne $ds.AllFiles.Count) {
        Write-Host "  skipping dataset (incomplete parquet inputs)" -ForegroundColor Red
        continue
    }

    foreach ($spec in $dumpSpecs) {
        $workDir = Join-Path $testDir "_stage6_planning\$($spec.Name)"
        if (Test-Path $workDir) { Remove-Item $workDir -Recurse -Force }
        New-Item -ItemType Directory -Path $workDir -Force | Out-Null

        Write-Host ("--- {0} ---" -f $spec.Name) -ForegroundColor Yellow

        # Stage parquets + calibration JSON siblings in the workdir under
        # canonical names (.scores.parquet, .calibration.json) so both
        # tools' synthetic-input derivation finds the calibration files.
        # The test layout uses .scores.rust.parquet to keep the Rust- and
        # C#-generated parquets distinct in the test data dir.
        $stagedParquets = @()
        foreach ($srcParquet in $parquets) {
            $srcStem = [IO.Path]::GetFileNameWithoutExtension($srcParquet)
            $srcStem = $srcStem -replace '\.scores\.rust$', ''  # strip .scores.rust
            $stagedPq = Join-Path $workDir "$srcStem.scores.parquet"
            $stagedCal = Join-Path $workDir "$srcStem.calibration.json"
            $srcCal = Join-Path (Split-Path -Parent $srcParquet) "$srcStem.calibration.json"
            Copy-Item -Path $srcParquet -Destination $stagedPq
            if (Test-Path $srcCal) { Copy-Item -Path $srcCal -Destination $stagedCal }
            $stagedParquets += $stagedPq
        }

        Set-Item "Env:$($spec.DumpVar)" "1"
        Set-Item "Env:$($spec.OnlyVar)" "1"

        try {
            $rustRun = Invoke-Stage6Dump -Tool "Rust" -Binary $rustBinary -ParquetPaths $stagedParquets `
                -Library $library -Resolution $ds.Resolution -WorkDir $workDir
            $csRun = Invoke-Stage6Dump -Tool "C#" -Binary $csharpBinary -ParquetPaths $stagedParquets `
                -Library $library -Resolution $ds.Resolution -WorkDir $workDir
        } finally {
            Remove-Item "Env:$($spec.DumpVar)" -ErrorAction Ignore
            Remove-Item "Env:$($spec.OnlyVar)" -ErrorAction Ignore
        }

        $rustDump = Join-Path $workDir ("rust_{0}.tsv" -f $spec.FilePrefix)
        $csDump   = Join-Path $workDir ("cs_{0}.tsv"  -f $spec.FilePrefix)
        $status = "MISSING"
        $rowCount = -1
        if ((Test-Path $rustDump) -and (Test-Path $csDump)) {
            $hRust = (Get-FileHash $rustDump -Algorithm SHA256).Hash
            $hCs   = (Get-FileHash $csDump -Algorithm SHA256).Hash
            $rowCount = (Get-Content $rustDump | Measure-Object -Line).Lines - 1
            if ($hRust -eq $hCs) { $status = "PASS" } else { $status = "FAIL" }
        }

        $row = [PSCustomObject]@{
            Dataset = $ds.Name
            Dump    = $spec.Name
            Rows    = $rowCount
            RustSec = $rustRun.ElapsedSec
            CsSec   = $csRun.ElapsedSec
            Status  = $status
        }
        $allResults += $row

        $color = if ($status -eq "PASS") { "Green" } else { "Red" }
        Write-Host ("  {0}: {1}  rust={2}s  cs={3}s  ({4} rows)" -f `
            $spec.Name, $status, $rustRun.ElapsedSec, $csRun.ElapsedSec, $rowCount) -ForegroundColor $color

        if (-not $KeepWorkDirs -and $status -eq "PASS") {
            Remove-Item $workDir -Recurse -Force
        }
    }
    Write-Host ""
}

$totalStart.Stop()

Write-Host "--- Summary ---" -ForegroundColor Cyan
$allResults | Format-Table -AutoSize

$total = $allResults.Count
$pass = ($allResults | Where-Object { $_.Status -eq "PASS" }).Count
$summaryColor = if ($pass -eq $total -and $total -gt 0) { "Green" } else { "Red" }
Write-Host ("{0}/{1} dump pairs byte-identical at the Stage 6 planning checkpoint.  Total: {2:mm\:ss}" `
    -f $pass, $total, $totalStart.Elapsed) -ForegroundColor $summaryColor

if ($pass -ne $total) { exit 1 }
