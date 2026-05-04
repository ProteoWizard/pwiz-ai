<#
.SYNOPSIS
    Per-iteration cross-impl Stage 6 worker (--join-at-pass=1 --no-join)
    byte-parity gate. Operates against a frozen fixture built once by
    Build-Stage6Fixture.ps1.

.DESCRIPTION
    Companion to:
      - Build-Stage6Fixture.ps1            (one-time fixture build)
      - Compare-Stage5-AllFiles.ps1        (Rust v C# in-process Stage 5)
      - Compare-Stage6-Planning.ps1        (Rust v C# in-process Stage 6 planning)
      - Compare-Stage6-Worker.ps1          (Rust-only portability gate)
      - Compare-Percolator.ps1             (Stage 5 Percolator dump diff)

    This script is the FAST iteration loop for Stage 6 development.
    Build-Stage6Fixture.ps1 produces a frozen test fixture once: Stage
    1-4 Snappy parquets + verified-identical Stage 5 sidecars + spectra
    cache + library. Every Stage 6 code change re-runs this script,
    which copies the fixture into a fresh per-iteration workdir and
    runs only --join-at-pass=1 --no-join on each binary against
    byte-identical inputs.

    Per-iteration flow:

      Stage A — Materialize workdir
        Copy <testDir>/_stage6_fixture/<dataset>/ to a fresh
        <testDir>/_stage6_iter/<dataset>_<tool>/ for each tool. Each
        tool gets its own private workdir so output writes don't
        collide.

      Stage B — Run Rust worker
        osprey --join-at-pass=1 --no-join from the Rust workdir, with
        OSPREY_DUMP_PERCOLATOR=1. Captures rust_stage5_percolator.tsv
        plus (when Phases 2+3 of the C# port land) reconciled
        .scores.parquet output.

      Stage C — Run C# worker
        OspreySharp.exe with the same flags + env from the C# workdir.

      Stage D — Compare
        Hand off to Compare-Percolator.ps1 for the post-hydration
        per-precursor q-value / score / PEP diff. PASS iff every
        numeric column is within its threshold and the (file_name,
        entry_id) row sets match.

    Future extensions (post-Phase 3 parquet write-back):
      - Add a parquet content-diff phase after Compare-Percolator
        passes, to validate end-of-Stage-6 reconciled .scores.parquet
        byte parity.

    Per-iteration runtime: ~30s on Stellar (no Stage 5 work, just
    Stage 6 hydrate + compact + rescore). Stage 5 boundary parity is
    locked when Build-Stage6Fixture.ps1 succeeds, so we don't pay for
    it on every Stage 6 iteration.

.PARAMETER Dataset
    Stellar | Astral | Both (default Stellar). The fixture for the
    requested dataset must already exist (run Build-Stage6Fixture.ps1
    first).

.PARAMETER TestBaseDir
    Override test data root.

.PARAMETER CsharpRoot
    pwiz worktree with built OspreySharp.exe. Auto-detect if omitted.

.PARAMETER TargetFramework
    net472 or net8.0 (default net8.0).

.PARAMETER Threads
    --threads value passed to osprey (default 16). Held constant
    across both binaries.

.EXAMPLE
    # Tight per-iteration loop after a C# Stage 6 code change.
    .\Compare-Stage6-Crossimpl.ps1 -Dataset Stellar
#>

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("Stellar", "Astral", "Both")]
    [string]$Dataset = "Stellar",

    [string]$TestBaseDir = $null,

    [string]$CsharpRoot = $null,

    [ValidateSet("net472", "net8.0")]
    [string]$TargetFramework = "net8.0",

    [int]$Threads = 16
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
        [int]$Threads
    )
    $outBlib = Join-Path $WorkDir ("_discard_{0}.blib" -f $Tool.ToLower())
    $args = @("--join-at-pass=1", "--no-join")
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

function Materialize-Workdir {
    param([string]$FixtureDir, [string]$WorkDir)
    if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force }
    New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
    # Copy contents (not the .fixture-version stamp file).
    Get-ChildItem -Path $FixtureDir -File | Where-Object { $_.Name -ne ".fixture-version" } |
        ForEach-Object { Copy-Item -Path $_.FullName -Destination $WorkDir -Force }
}

# Per-dataset loop ----------------------------------------------------

foreach ($dsName in $datasets) {
    $ds = Get-DatasetConfig $dsName -TestBaseDir $TestBaseDir
    $testDir = $ds.TestDir
    $stems = $ds.AllFiles | ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_) }

    Write-Host ("=== {0} (TestDir: {1}) ===" -f $ds.Name, $testDir) -ForegroundColor Cyan

    $fixtureDir = Join-Path $testDir ("_stage6_fixture\{0}" -f $ds.Name)
    if (-not (Test-Path (Join-Path $fixtureDir ".fixture-version"))) {
        Write-Host ("  Missing fixture at {0}" -f $fixtureDir) -ForegroundColor Red
        Write-Host "  Run Build-Stage6Fixture.ps1 first." -ForegroundColor Red
        $allResults += [PSCustomObject]@{
            Dataset = $ds.Name; Status = "FIXTURE_MISSING"
        }
        continue
    }

    $rustWorkDir = Join-Path $testDir ("_stage6_iter\{0}_rust" -f $ds.Name)
    $csWorkDir   = Join-Path $testDir ("_stage6_iter\{0}_cs"   -f $ds.Name)

    # Stage A: materialize per-tool workdirs from the fixture.
    Write-Host "  Stage A: materializing workdirs from fixture..." -ForegroundColor Yellow
    $matStart = [Diagnostics.Stopwatch]::StartNew()
    Materialize-Workdir -FixtureDir $fixtureDir -WorkDir $rustWorkDir
    Materialize-Workdir -FixtureDir $fixtureDir -WorkDir $csWorkDir
    $matStart.Stop()
    Write-Host ("    Stage A: {0:F1}s" -f $matStart.Elapsed.TotalSeconds)

    $parquetNames = $stems | ForEach-Object { "$_.scores.parquet" }

    # Stage B: Rust worker with OSPREY_DUMP_PERCOLATOR=1.
    Write-Host "  Stage B: Rust worker..." -ForegroundColor Yellow
    $env:OSPREY_DUMP_PERCOLATOR = "1"
    try {
        $rustRun = Invoke-Worker -Tool "Rust" -Binary $rustBinary -WorkDir $rustWorkDir `
            -ParquetNames $parquetNames -LibraryName $ds.Library `
            -Resolution $ds.Resolution -Threads $Threads
    } finally { Remove-Item Env:\OSPREY_DUMP_PERCOLATOR -ErrorAction Ignore }
    Write-Host ("    Stage B: {0}s (exit {1})" -f $rustRun.ElapsedSec, $rustRun.ExitCode)

    # Stage C: C# worker with OSPREY_DUMP_PERCOLATOR=1.
    Write-Host "  Stage C: C# worker..." -ForegroundColor Yellow
    $env:OSPREY_DUMP_PERCOLATOR = "1"
    try {
        $csRun = Invoke-Worker -Tool "Cs" -Binary $csharpBinary -WorkDir $csWorkDir `
            -ParquetNames $parquetNames -LibraryName $ds.Library `
            -Resolution $ds.Resolution -Threads $Threads
    } finally { Remove-Item Env:\OSPREY_DUMP_PERCOLATOR -ErrorAction Ignore }
    Write-Host ("    Stage C: {0}s (exit {1})" -f $csRun.ElapsedSec, $csRun.ExitCode)
    # Note: the C# worker exits non-zero today (rescore engine stub
    # after Phase 1) AFTER writing the dump. That's fine for parity —
    # the dump is what we compare here.

    $rustDump = Join-Path $rustWorkDir "rust_stage5_percolator.tsv"
    $csDump   = Join-Path $csWorkDir   "cs_stage5_percolator.tsv"

    if (-not (Test-Path $rustDump)) {
        Write-Host ("  Missing dump: {0}" -f $rustDump) -ForegroundColor Red
        $allResults += [PSCustomObject]@{
            Dataset = $ds.Name; Status = "RUST_DUMP_MISSING"
        }
        continue
    }
    if (-not (Test-Path $csDump)) {
        Write-Host ("  Missing dump: {0}" -f $csDump) -ForegroundColor Red
        $allResults += [PSCustomObject]@{
            Dataset = $ds.Name; Status = "CS_DUMP_MISSING"
        }
        continue
    }

    # Stage D: compare via the existing Compare-Percolator.ps1 harness.
    Write-Host "  Stage D: Compare-Percolator.ps1..." -ForegroundColor Yellow
    $compareScript = Join-Path $scriptRoot "Compare-Percolator.ps1"
    & pwsh -File $compareScript -RustTsv $rustDump -CsTsv $csDump
    $compareExit = $LASTEXITCODE
    $allResults += [PSCustomObject]@{
        Dataset = $ds.Name
        Status = if ($compareExit -eq 0) { "PASS" } else { "FAIL" }
        RustSec = $rustRun.ElapsedSec
        CsSec = $csRun.ElapsedSec
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
