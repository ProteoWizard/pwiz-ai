<#
.SYNOPSIS
    Cross-impl Stage 5 byte-parity across every mzML file in a dataset.

.DESCRIPTION
    For each file in $ds.AllFiles, runs both Rust osprey and OspreySharp
    in --join-at-pass=1 mode against the pre-generated .scores.rust.parquet
    with all four Stage 5 dump env vars set:

        OSPREY_DUMP_STANDARDIZER = 1
        OSPREY_DUMP_SUBSAMPLE    = 1
        OSPREY_DUMP_SVM_WEIGHTS  = 1
        OSPREY_DUMP_PERCOLATOR   = 1
        OSPREY_PERCOLATOR_ONLY   = 1   (exit after last dump)

    Each tool writes rust_stage5_*.tsv / cs_stage5_*.tsv into a per-file
    working directory under <testDir>\_stage5\<stem>\. The four dump
    pairs are then compared byte-for-byte via SHA-256. Pass = all four
    pairs match; fail = any mismatch.

    Run Generate-AllScoresParquet.ps1 first to produce the rust Parquets.

.PARAMETER Dataset
    Stellar | Astral | Both (default Both).

.PARAMETER CsharpRoot
    pwiz worktree with built OspreySharp.exe (auto-detect if omitted).

.PARAMETER TargetFramework
    net472 (default) or net8.0.

.PARAMETER TestBaseDir
    Override test data root.

.PARAMETER KeepWorkDirs
    Preserve per-file _stage5/<stem>/ dirs after the run (default: keep).
    Pass -KeepWorkDirs:$false to delete them on exit.

.EXAMPLE
    .\Compare-Stage5-AllFiles.ps1

.EXAMPLE
    .\Compare-Stage5-AllFiles.ps1 -Dataset Stellar
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
$dumpNames = @("standardizer","subsample","svm_weights","percolator")

function Invoke-StageFiveDump {
    param(
        [string]$Tool,       # "Rust" or "C#"
        [string]$Binary,
        [string]$Parquet,
        [string]$Library,
        [string]$Resolution,
        [string]$WorkDir
    )
    $outBlib = Join-Path $WorkDir ("_discard_{0}.blib" -f $Tool.ToLower())
    $sw = [Diagnostics.Stopwatch]::StartNew()
    Push-Location $WorkDir
    try {
        & $Binary --join-at-pass=1 --input-scores $Parquet -l $Library --output $outBlib `
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

    foreach ($mzmlName in $ds.AllFiles) {
        $stem = [IO.Path]::GetFileNameWithoutExtension($mzmlName)
        $rustParquet = Join-Path $testDir "$stem.scores.rust.parquet"
        if (-not (Test-Path $rustParquet)) {
            Write-Host ("  {0}: missing rust Parquet — run Generate-AllScoresParquet.ps1 first" -f $stem) -ForegroundColor Red
            continue
        }

        $workDir = Join-Path $testDir "_stage5\$stem"
        if (Test-Path $workDir) { Remove-Item $workDir -Recurse -Force }
        New-Item -ItemType Directory -Path $workDir -Force | Out-Null

        Write-Host ("--- {0} ---" -f $stem) -ForegroundColor Yellow

        $env:OSPREY_DUMP_STANDARDIZER = "1"
        $env:OSPREY_DUMP_SUBSAMPLE    = "1"
        $env:OSPREY_DUMP_SVM_WEIGHTS  = "1"
        $env:OSPREY_DUMP_PERCOLATOR   = "1"
        $env:OSPREY_PERCOLATOR_ONLY   = "1"

        try {
            $rustRun = Invoke-StageFiveDump -Tool "Rust" -Binary $rustBinary -Parquet $rustParquet `
                -Library $library -Resolution $ds.Resolution -WorkDir $workDir
            $csRun = Invoke-StageFiveDump -Tool "C#" -Binary $csharpBinary -Parquet $rustParquet `
                -Library $library -Resolution $ds.Resolution -WorkDir $workDir
        } finally {
            Remove-Item Env:\OSPREY_DUMP_STANDARDIZER -ErrorAction Ignore
            Remove-Item Env:\OSPREY_DUMP_SUBSAMPLE -ErrorAction Ignore
            Remove-Item Env:\OSPREY_DUMP_SVM_WEIGHTS -ErrorAction Ignore
            Remove-Item Env:\OSPREY_DUMP_PERCOLATOR -ErrorAction Ignore
            Remove-Item Env:\OSPREY_PERCOLATOR_ONLY -ErrorAction Ignore
        }

        $row = [ordered]@{
            Dataset = $ds.Name
            File = $stem
            RustSec = $rustRun.ElapsedSec
            CsSec = $csRun.ElapsedSec
        }

        $allPass = $true
        foreach ($dump in $dumpNames) {
            $rustDump = Join-Path $workDir "rust_stage5_$dump.tsv"
            $csDump   = Join-Path $workDir "cs_stage5_$dump.tsv"
            $status = "MISSING"
            if ((Test-Path $rustDump) -and (Test-Path $csDump)) {
                $hRust = (Get-FileHash $rustDump -Algorithm SHA256).Hash
                $hCs   = (Get-FileHash $csDump -Algorithm SHA256).Hash
                if ($hRust -eq $hCs) { $status = "PASS" } else { $status = "FAIL"; $allPass = $false }
            } else {
                $allPass = $false
            }
            $row[$dump] = $status
        }
        $row["Overall"] = if ($allPass) { "PASS" } else { "FAIL" }
        $allResults += [PSCustomObject]$row

        $color = if ($allPass) { "Green" } else { "Red" }
        Write-Host ("  dumps: std={0}  sub={1}  svm={2}  perc={3}  =>  {4}  (rust {5}s, C# {6}s)" `
            -f $row.standardizer, $row.subsample, $row.svm_weights, $row.percolator, $row.Overall, `
               $rustRun.ElapsedSec, $csRun.ElapsedSec) -ForegroundColor $color

        if (-not $KeepWorkDirs -and $allPass) {
            Remove-Item $workDir -Recurse -Force
        }
    }
    Write-Host ""
}

$totalStart.Stop()

Write-Host "--- Summary ---" -ForegroundColor Cyan
$allResults | Format-Table -AutoSize

$total = $allResults.Count
$pass = ($allResults | Where-Object { $_.Overall -eq "PASS" }).Count
$summaryColor = if ($pass -eq $total -and $total -gt 0) { "Green" } else { "Red" }
Write-Host ("{0}/{1} files byte-identical on all four Stage 5 dumps.  Total: {2:mm\:ss}" `
    -f $pass, $total, $totalStart.Elapsed) -ForegroundColor $summaryColor

if ($pass -ne $total) { exit 1 }
