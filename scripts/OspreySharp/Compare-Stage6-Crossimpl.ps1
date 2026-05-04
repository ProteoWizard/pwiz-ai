<#
.SYNOPSIS
    Cross-impl Stage 6 worker (--join-at-pass=1 --no-join) byte-parity gate.

.DESCRIPTION
    Companion to:
      - Compare-Stage5-AllFiles.ps1   (Rust v C# in-process Stage 5)
      - Compare-Stage6-Planning.ps1   (Rust v C# in-process Stage 6 planning)
      - Compare-Stage6-Worker.ps1     (Rust-only portability gate)

    This script closes the missing matrix cell: Rust v C# at the
    Stage 6 worker (--join-at-pass=1 --no-join) entry point. Drives
    both binaries against the same Stage 4 parquets + boundary file
    pair, captures the Stage 5 Percolator dump from each, and compares
    via Compare-Percolator.ps1.

    Workflow per dataset:

      Phase A — Stage:
        Stage Stage 4 parquets (from Generate-AllScoresParquet.ps1
        outputs), mzML, calibration JSON, spectra cache, library +
        libcache into _stage6_crossimpl\<Dataset>\.

      Phase B — Write boundary (Rust --join-at-pass=1 --join-only):
        Generate the .1st-pass.fdr_scores.bin v3 + .reconciliation.json
        sibling to each parquet. Both workers will consume these in
        Phase C / D.

      Phase C — Rust worker:
        Restore Stage 4 parquets (in case any prior phase touched
        them). Run osprey --join-at-pass=1 --no-join with
        OSPREY_DUMP_PERCOLATOR=1; capture rust_stage5_percolator.tsv.

      Phase D — C# worker:
        Restore Stage 4 parquets. Run OspreySharp.exe with the same
        flags + env; capture cs_stage5_percolator.tsv.

      Phase E — Compare:
        Invoke Compare-Percolator.ps1 on the two TSVs. PASS iff every
        numeric column is within its threshold and every (file_name,
        entry_id) row appears on both sides.

    Today the C# worker stops after hydration + compaction (the
    per-file rescore engine isn't ported), so the dump is the only
    signal at this seam. Once the rescore engine lands on both
    sides, additional dump pairs (median-polish inputs, predict_rt,
    reconciled parquet content) can be folded into the same Phase E
    invocation.

.PARAMETER Dataset
    Stellar | Astral | Both (default Stellar).

.PARAMETER TestBaseDir
    Override test data root.

.PARAMETER CsharpRoot
    pwiz worktree with built OspreySharp.exe. Auto-detect if omitted.

.PARAMETER TargetFramework
    net472 or net8.0 (default net8.0).

.PARAMETER Threads
    --threads value passed to osprey (default 16). Held constant
    across both binaries.

.PARAMETER Clean
    Force a fresh staged work dir.

.EXAMPLE
    .\Compare-Stage6-Crossimpl.ps1 -Dataset Stellar -Clean
#>

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("Stellar", "Astral", "Both")]
    [string]$Dataset = "Stellar",

    [string]$TestBaseDir = $null,

    [string]$CsharpRoot = $null,

    [ValidateSet("net472", "net8.0")]
    [string]$TargetFramework = "net8.0",

    [int]$Threads = 16,

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
if ($CsharpRoot) {
    $csharpBase = $CsharpRoot
} else {
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
Write-Host "Threads:     $Threads"     -ForegroundColor DarkGray
Write-Host ""

$datasets = if ($Dataset -eq "Both") { @("Stellar","Astral") } else { @($Dataset) }
$totalStart = [Diagnostics.Stopwatch]::StartNew()
$allResults = @()

# Helpers -------------------------------------------------------------

function Invoke-Worker {
    param(
        [string]$Tool,
        [string]$Binary,
        [string]$WorkDir,
        [string[]]$ParquetNames,
        [string]$LibraryName,
        [string]$Resolution,
        [int]$Threads,
        [bool]$JoinOnly  # true = --join-only (Phase B), false = --no-join (Phase C/D)
    )
    $outBlib = Join-Path $WorkDir ("_discard_{0}.blib" -f $Tool.ToLower())
    $args = @("--join-at-pass=1")
    if ($JoinOnly) { $args += "--join-only" } else { $args += "--no-join" }
    foreach ($p in $ParquetNames) { $args += "--input-scores"; $args += $p }
    $args += @("-l", $LibraryName, "--output", $outBlib,
               "--resolution", $Resolution, "--protein-fdr", "0.01",
               "--threads", $Threads.ToString())
    $sw = [Diagnostics.Stopwatch]::StartNew()
    Push-Location $WorkDir
    try {
        & $Binary @args 2>&1 | Out-Null
        $exit = $LASTEXITCODE
    } finally { Pop-Location }
    $sw.Stop()
    return [PSCustomObject]@{
        Tool = $Tool; ExitCode = $exit
        ElapsedSec = [math]::Round($sw.Elapsed.TotalSeconds, 2)
    }
}

function Stage-WorkDir {
    param([string]$WorkDir, [string[]]$RustParquets, [string]$TestDir, [string]$Library)
    New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
    foreach ($srcParquet in $RustParquets) {
        $stem = ([IO.Path]::GetFileNameWithoutExtension($srcParquet)) -replace '\.scores\.rust$', ''
        Copy-Item -Path $srcParquet -Destination (Join-Path $WorkDir "$stem.scores.parquet")
        foreach ($ext in @("mzML", "calibration.json", "spectra.bin")) {
            $src = Join-Path $TestDir "$stem.$ext"
            if (Test-Path $src) {
                Copy-Item -Path $src -Destination (Join-Path $WorkDir "$stem.$ext")
            }
        }
    }
    Copy-Item -Path (Join-Path $TestDir $Library) -Destination (Join-Path $WorkDir $Library)
    $libcache = Join-Path $TestDir ($Library + ".libcache")
    if (Test-Path $libcache) {
        Copy-Item -Path $libcache -Destination (Join-Path $WorkDir ($Library + ".libcache"))
    }
}

function Snapshot-Stage4Parquets {
    param([string]$WorkDir, [string[]]$Stems)
    $snapDir = Join-Path $WorkDir ".stage4_snapshot"
    if (Test-Path $snapDir) { Remove-Item $snapDir -Recurse -Force }
    New-Item -ItemType Directory -Path $snapDir -Force | Out-Null
    foreach ($stem in $Stems) {
        Copy-Item -Path (Join-Path $WorkDir "$stem.scores.parquet") `
                  -Destination (Join-Path $snapDir "$stem.scores.parquet") -Force
    }
    return $snapDir
}

function Restore-Stage4Parquets {
    param([string]$SnapDir, [string]$WorkDir, [string[]]$Stems)
    foreach ($stem in $Stems) {
        Copy-Item -Path (Join-Path $SnapDir "$stem.scores.parquet") `
                  -Destination (Join-Path $WorkDir "$stem.scores.parquet") -Force
    }
}

# Phases --------------------------------------------------------------

foreach ($dsName in $datasets) {
    $ds = Get-DatasetConfig $dsName -TestBaseDir $TestBaseDir
    $testDir = $ds.TestDir
    $stems = $ds.AllFiles | ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_) }

    Write-Host ("=== {0} (TestDir: {1}) ===" -f $ds.Name, $testDir) -ForegroundColor Cyan

    $rustParquets = @()
    foreach ($stem in $stems) {
        $rustParquet = Join-Path $testDir "$stem.scores.rust.parquet"
        if (-not (Test-Path $rustParquet)) {
            Write-Host ("  missing rust parquet for {0} -- run Generate-AllScoresParquet.ps1 first" -f $stem) -ForegroundColor Red
            continue
        }
        $rustParquets += $rustParquet
    }
    if ($rustParquets.Count -ne $stems.Count) {
        Write-Host "  skipping dataset (incomplete parquet inputs)" -ForegroundColor Red
        continue
    }

    $workDir = Join-Path $testDir ("_stage6_crossimpl\{0}" -f $ds.Name)
    if ($Clean -and (Test-Path $workDir)) {
        Write-Host ("  -Clean: removing {0}" -f $workDir) -ForegroundColor DarkGray
        Remove-Item $workDir -Recurse -Force
    }
    $stagedMarker = Join-Path $workDir ".staged"
    if (-not (Test-Path $stagedMarker)) {
        Write-Host ("  Phase A: staging {0} parquet(s) + mzML + cal JSON + spectra cache + library into {1}" `
            -f $rustParquets.Count, $workDir) -ForegroundColor Yellow
        Stage-WorkDir -WorkDir $workDir -RustParquets $rustParquets -TestDir $testDir -Library $ds.Library
        Set-Content -Path $stagedMarker -Value (Get-Date -Format o)
    } else {
        Write-Host ("  Phase A: reusing staged dir {0}" -f $workDir) -ForegroundColor DarkGray
    }

    $parquetNames = $stems | ForEach-Object { "$_.scores.parquet" }
    $stage4Snap = Snapshot-Stage4Parquets -WorkDir $workDir -Stems $stems

    # Phase B: write boundary via Rust --join-only
    Write-Host "  Phase B: write boundary (Rust --join-at-pass=1 --join-only)..." -ForegroundColor Yellow
    $phaseB = Invoke-Worker -Tool "RustJoinOnly" -Binary $rustBinary -WorkDir $workDir `
        -ParquetNames $parquetNames -LibraryName $ds.Library `
        -Resolution $ds.Resolution -Threads $Threads -JoinOnly $true
    Write-Host ("    Phase B: {0}s (exit {1})" -f $phaseB.ElapsedSec, $phaseB.ExitCode)
    if ($phaseB.ExitCode -ne 0) {
        Write-Host "  Phase B failed; cannot continue." -ForegroundColor Red
        $allResults += [PSCustomObject]@{ Dataset = $ds.Name; Status = "PHASE_B_FAIL" }
        continue
    }

    # Phase C: Rust worker with dump
    Restore-Stage4Parquets -SnapDir $stage4Snap -WorkDir $workDir -Stems $stems
    $rustDump = Join-Path $workDir "rust_stage5_percolator.tsv"
    $csDump   = Join-Path $workDir "cs_stage5_percolator.tsv"
    if (Test-Path $rustDump) { Remove-Item $rustDump -Force }
    if (Test-Path $csDump)   { Remove-Item $csDump   -Force }

    Write-Host "  Phase C: Rust worker (--no-join + OSPREY_DUMP_PERCOLATOR=1)..." -ForegroundColor Yellow
    $env:OSPREY_DUMP_PERCOLATOR = "1"
    try {
        $phaseC = Invoke-Worker -Tool "RustWorker" -Binary $rustBinary -WorkDir $workDir `
            -ParquetNames $parquetNames -LibraryName $ds.Library `
            -Resolution $ds.Resolution -Threads $Threads -JoinOnly $false
    } finally {
        Remove-Item Env:\OSPREY_DUMP_PERCOLATOR -ErrorAction Ignore
    }
    Write-Host ("    Phase C: {0}s (exit {1})" -f $phaseC.ElapsedSec, $phaseC.ExitCode)

    # Phase D: C# worker with dump
    Restore-Stage4Parquets -SnapDir $stage4Snap -WorkDir $workDir -Stems $stems

    Write-Host "  Phase D: C# worker (--no-join + OSPREY_DUMP_PERCOLATOR=1)..." -ForegroundColor Yellow
    $env:OSPREY_DUMP_PERCOLATOR = "1"
    try {
        $phaseD = Invoke-Worker -Tool "CsWorker" -Binary $csharpBinary -WorkDir $workDir `
            -ParquetNames $parquetNames -LibraryName $ds.Library `
            -Resolution $ds.Resolution -Threads $Threads -JoinOnly $false
    } finally {
        Remove-Item Env:\OSPREY_DUMP_PERCOLATOR -ErrorAction Ignore
    }
    Write-Host ("    Phase D: {0}s (exit {1})" -f $phaseD.ElapsedSec, $phaseD.ExitCode)
    # Note: C# worker exits non-zero today (rescore engine stub) AFTER
    # writing the dump. That's fine for parity — the dump is the only
    # output we compare here.

    if (-not (Test-Path $rustDump)) {
        Write-Host ("  Missing dump: {0}" -f $rustDump) -ForegroundColor Red
        $allResults += [PSCustomObject]@{ Dataset = $ds.Name; Status = "RUST_DUMP_MISSING" }
        continue
    }
    if (-not (Test-Path $csDump)) {
        Write-Host ("  Missing dump: {0}" -f $csDump) -ForegroundColor Red
        $allResults += [PSCustomObject]@{ Dataset = $ds.Name; Status = "CS_DUMP_MISSING" }
        continue
    }

    # Phase E: compare via the existing Compare-Percolator.ps1 harness
    Write-Host "  Phase E: Compare-Percolator.ps1..." -ForegroundColor Yellow
    $compareScript = Join-Path $scriptRoot "Compare-Percolator.ps1"
    & pwsh -File $compareScript -RustTsv $rustDump -CsTsv $csDump
    $compareExit = $LASTEXITCODE
    $allResults += [PSCustomObject]@{
        Dataset = $ds.Name
        Status = if ($compareExit -eq 0) { "PASS" } else { "FAIL" }
        RustSec = $phaseC.ElapsedSec
        CsSec = $phaseD.ElapsedSec
    }

    Write-Host ""
}

$totalStart.Stop()

Write-Host "--- Summary ---" -ForegroundColor Cyan
Write-Host ""
$allResults | Format-Table -AutoSize Dataset, Status, RustSec, CsSec

$pass = ($allResults | Where-Object { $_.Status -eq "PASS" }).Count
$total = $allResults.Count
$timeStr = "{0:mm\:ss}" -f $totalStart.Elapsed
Write-Host ("{0}/{1} dataset(s) passed cross-impl Stage 6 worker parity. Total: {2}" `
    -f $pass, $total, $timeStr) `
    -ForegroundColor $(if ($pass -eq $total) { "Green" } else { "Yellow" })

exit $(if ($pass -eq $total) { 0 } else { 1 })
