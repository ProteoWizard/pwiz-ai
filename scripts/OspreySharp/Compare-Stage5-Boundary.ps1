<#
.SYNOPSIS
    Cross-impl Stage 5 → Stage 6 boundary-file byte-parity gate.

.DESCRIPTION
    Runs both Rust osprey and OspreySharp in --join-at-pass=1 --join-only
    mode against the pre-generated .scores.rust.parquet files in a dataset.
    Each tool stops at the Stage 5 / reconciliation-planning boundary and
    writes two sidecars per input file:

        <stem>.1st-pass.fdr_scores.bin   (binary; SVM score + 4 q-values + PEP per entry)
        <stem>.reconciliation.json       (text; non-Keep actions, gap-fill targets, refined RT cal)

    The sidecars are then byte-compared (SHA-256) between the two
    implementations. PASS when all sidecars are bit-identical; FAIL on
    any divergence.

    Stage 6 work in --join-at-pass=1 --no-join mode (next sprint) consumes
    these files. When this gate is green, Stage 5 is "locked down" and a
    Stage 6 worker can be developed and validated against the persisted
    boundary on a single mzML at a time, without re-running Stage 5.

    Run Generate-AllScoresParquet.ps1 first to produce the rust parquets
    that this gate consumes.

.PARAMETER Dataset
    Stellar | Astral | Both (default Stellar).

.PARAMETER CsharpRoot
    pwiz worktree with built OspreySharp.exe (auto-detect if omitted).

.PARAMETER TargetFramework
    net472 or net8.0 (default net8.0).

.PARAMETER TestBaseDir
    Override test data root (defaults to OSPREY_TEST_BASE_DIR or D:\test\osprey-runs).

.PARAMETER Clean
    Force a fresh staged workdir (re-stage parquets, discard any sidecars
    from prior runs). Use before a full validation run.

.EXAMPLE
    # Stellar lockdown gate.
    .\Compare-Stage5-Boundary.ps1 -Dataset Stellar -Clean

.EXAMPLE
    # Both datasets after iterating on the C# side.
    .\Compare-Stage5-Boundary.ps1 -Dataset Both
#>

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("Stellar", "Astral", "Both")]
    [string]$Dataset = "Stellar",

    [string]$CsharpRoot = $null,

    [ValidateSet("net472", "net8.0")]
    [string]$TargetFramework = "net8.0",

    [string]$TestBaseDir = $null,

    [switch]$Clean
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
    foreach ($c in @("pwiz", "pwiz-work1", "pwiz-work2")) {
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

$totalStart = [Diagnostics.Stopwatch]::StartNew()
$allResults = @()

foreach ($dsName in $datasets) {
    $ds = Get-DatasetConfig $dsName -TestBaseDir $TestBaseDir
    $testDir = $ds.TestDir
    $library = Join-Path $testDir $ds.Library

    Write-Host ("=== {0} (TestDir: {1}) ===" -f $ds.Name, $testDir) -ForegroundColor Cyan

    # Verify staged parquet inputs exist (produced by Generate-AllScoresParquet.ps1).
    $parquets = @()
    foreach ($mzmlName in $ds.AllFiles) {
        $stem = [IO.Path]::GetFileNameWithoutExtension($mzmlName)
        $rustParquet = Join-Path $testDir "$stem.scores.rust.parquet"
        if (-not (Test-Path $rustParquet)) {
            Write-Host ("  missing rust parquet for {0} -- run Generate-AllScoresParquet.ps1 first" -f $stem) -ForegroundColor Red
            continue
        }
        $parquets += $rustParquet
    }
    if ($parquets.Count -ne $ds.AllFiles.Count) {
        Write-Host "  skipping dataset (incomplete parquet inputs)" -ForegroundColor Red
        continue
    }

    # Per-dataset workdir holds two side-by-side sidecar trees: rust_outputs/
    # and cs_outputs/. The parquets themselves are staged once at the workdir
    # root so both tools see the same paths.
    $workDir = Join-Path $testDir ("_stage5_boundary\{0}" -f $ds.Name)
    if ($Clean -and (Test-Path $workDir)) {
        Write-Host ("  -Clean: removing {0}" -f $workDir) -ForegroundColor DarkGray
        Remove-Item $workDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $workDir -Force | Out-Null

    $stagedMarker = Join-Path $workDir ".staged"
    $stagedParquets = @()
    if (-not (Test-Path $stagedMarker)) {
        Write-Host ("  staging {0} parquet(s) + calibration JSON(s)" -f $parquets.Count) -ForegroundColor DarkGray
        foreach ($srcParquet in $parquets) {
            $srcStem = [IO.Path]::GetFileNameWithoutExtension($srcParquet)
            $srcStem = $srcStem -replace '\.scores\.rust$', ''
            $stagedPq = Join-Path $workDir "$srcStem.scores.parquet"
            $stagedCal = Join-Path $workDir "$srcStem.calibration.json"
            $srcCal = Join-Path (Split-Path -Parent $srcParquet) "$srcStem.calibration.json"
            Copy-Item -Path $srcParquet -Destination $stagedPq
            if (Test-Path $srcCal) { Copy-Item -Path $srcCal -Destination $stagedCal }
            $stagedParquets += $stagedPq
        }
        Set-Content -Path $stagedMarker -Value (Get-Date -Format o)
    } else {
        Write-Host ("  reusing staged workdir {0}" -f $workDir) -ForegroundColor DarkGray
        foreach ($srcParquet in $parquets) {
            $srcStem = [IO.Path]::GetFileNameWithoutExtension($srcParquet)
            $srcStem = $srcStem -replace '\.scores\.rust$', ''
            $stagedParquets += Join-Path $workDir "$srcStem.scores.parquet"
        }
    }

    $rustOut = Join-Path $workDir "rust_outputs"
    $csOut   = Join-Path $workDir "cs_outputs"
    Remove-Item -Path $rustOut -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $csOut   -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $rustOut -Force | Out-Null
    New-Item -ItemType Directory -Path $csOut   -Force | Out-Null

    function Invoke-Stage5JoinOnly {
        param([string]$Tool, [string]$Binary, [string[]]$ParquetPaths, [string]$Library, [string]$Resolution, [string]$WorkDir)
        # The boundary sidecars land sibling to each --input-scores parquet
        # by file stem. Both runs use the same stems and the same parquet
        # locations, so we run each tool in turn and snapshot the outputs
        # to the per-tool subdir before the next run can clobber them.
        $outBlib = Join-Path $WorkDir ("_discard_{0}.blib" -f $Tool.ToLower())
        $inputArgs = @()
        foreach ($p in $ParquetPaths) { $inputArgs += "--input-scores"; $inputArgs += $p }
        $sw = [Diagnostics.Stopwatch]::StartNew()
        Push-Location $WorkDir
        try {
            & $Binary --join-at-pass=1 --join-only @inputArgs `
                -l $Library --output $outBlib --resolution $Resolution --protein-fdr 0.01 2>&1 | Out-Null
            $exit = $LASTEXITCODE
        } finally { Pop-Location }
        $sw.Stop()
        return [PSCustomObject]@{ Tool = $Tool; ExitCode = $exit; ElapsedSec = [math]::Round($sw.Elapsed.TotalSeconds, 2) }
    }

    function Move-Sidecars {
        param([string]$Tool, [string]$WorkDir, [string]$DestDir, [string[]]$Stems)
        foreach ($stem in $Stems) {
            foreach ($ext in @("1st-pass.fdr_scores.bin", "reconciliation.json")) {
                $src = Join-Path $WorkDir "$stem.$ext"
                $dst = Join-Path $DestDir "$stem.$ext"
                if (Test-Path $src) { Move-Item -Path $src -Destination $dst -Force }
            }
        }
    }

    $stems = $ds.AllFiles | ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_) }

    Write-Host "  Running Rust --join-at-pass=1 --join-only..." -ForegroundColor Yellow
    $rustResult = Invoke-Stage5JoinOnly -Tool "rust" -Binary $rustBinary `
        -ParquetPaths $stagedParquets -Library $library -Resolution $ds.Resolution -WorkDir $workDir
    Move-Sidecars -Tool "rust" -WorkDir $workDir -DestDir $rustOut -Stems $stems
    Write-Host ("    Rust: {0}s (exit {1})" -f $rustResult.ElapsedSec, $rustResult.ExitCode)

    Write-Host "  Running C# --join-at-pass=1 --join-only..." -ForegroundColor Yellow
    $csResult = Invoke-Stage5JoinOnly -Tool "cs" -Binary $csharpBinary `
        -ParquetPaths $stagedParquets -Library $library -Resolution $ds.Resolution -WorkDir $workDir
    Move-Sidecars -Tool "cs" -WorkDir $workDir -DestDir $csOut -Stems $stems
    Write-Host ("    C# : {0}s (exit {1})" -f $csResult.ElapsedSec, $csResult.ExitCode)

    Write-Host "  Comparing per-file boundary sidecars..." -ForegroundColor Yellow
    foreach ($stem in $stems) {
        foreach ($ext in @("1st-pass.fdr_scores.bin", "reconciliation.json")) {
            $rustPath = Join-Path $rustOut "$stem.$ext"
            $csPath   = Join-Path $csOut   "$stem.$ext"
            $rustExists = Test-Path $rustPath
            $csExists   = Test-Path $csPath
            if (-not $rustExists -or -not $csExists) {
                $status = if (-not $rustExists -and -not $csExists) { "BOTH MISSING" }
                          elseif (-not $rustExists)                 { "RUST MISSING" }
                          else                                       { "CS MISSING" }
                $allResults += [PSCustomObject]@{ Dataset = $ds.Name; Stem = $stem; Ext = $ext; Status = $status; Bytes = 0 }
                continue
            }
            $rustHash = (Get-FileHash -Path $rustPath -Algorithm SHA256).Hash
            $csHash   = (Get-FileHash -Path $csPath   -Algorithm SHA256).Hash
            $bytes    = (Get-Item $rustPath).Length
            $status   = if ($rustHash -eq $csHash) { "PASS" } else { "FAIL" }
            $allResults += [PSCustomObject]@{ Dataset = $ds.Name; Stem = $stem; Ext = $ext; Status = $status; Bytes = $bytes }
        }
    }

    Write-Host ""
}

$totalStart.Stop()

Write-Host "--- Summary ---" -ForegroundColor Cyan
Write-Host ""
$allResults | Format-Table -AutoSize Dataset, Stem, Ext, Status, Bytes

$pass = ($allResults | Where-Object { $_.Status -eq "PASS" }).Count
$total = $allResults.Count
$timeStr = "{0:mm\:ss}" -f $totalStart.Elapsed
Write-Host ("{0}/{1} sidecar pairs byte-identical at the Stage 5 boundary.  Total: {2}" -f $pass, $total, $timeStr) `
    -ForegroundColor $(if ($pass -eq $total) { "Green" } else { "Yellow" })

if ($pass -eq $total) {
    Write-Host ""
    Write-Host "Stage 5 is locked down. Stage 6 worker (next sprint) can be developed against these outputs." -ForegroundColor Green
    exit 0
} else {
    Write-Host ""
    Write-Host "Stage 5 boundary is NOT yet bit-identical. See FAIL rows above." -ForegroundColor Yellow
    exit 1
}
