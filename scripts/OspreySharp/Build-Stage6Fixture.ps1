<#
.SYNOPSIS
    Build a frozen Stage 6 test fixture: Stage 1-4 Snappy parquets +
    verified-identical Stage 5 sidecar pair + spectra cache + library.

.DESCRIPTION
    Once-per-version-bump script that produces the immutable input
    fixture for the per-iteration Stage 6 Rust-vs-C# comparison loop
    (`Compare-Stage6-Crossimpl.ps1`). The fixture is the contract:
    every Stage 6 iteration consumes an exact byte-identical copy of
    these files on both binaries, so the only variable across runs is
    Stage 6 code.

    Build pipeline:

      1. Confirm Stage 1-4 parquets exist under
         <testDir>/<stem>.scores.rust.parquet
         (`Generate-AllScoresParquet.ps1` produces these).
      2. Run `Compare-Stage5-Boundary.ps1` to confirm the Stage 5
         boundary file pair (.1st-pass.fdr_scores.bin v3 +
         .reconciliation.json) is byte-identical between Rust and C#
         on the current binary versions. Refuse to build the fixture
         if Stage 5 has drifted — Stage 6 testing only makes sense
         when its inputs are locked.
      3. Snapshot into <testDir>/_stage6_fixture/<dataset>/:
           - <stem>.scores.parquet         (Snappy, from Stage 4)
           - <stem>.1st-pass.fdr_scores.bin (verified-identical sidecar)
           - <stem>.reconciliation.json    (verified-identical sidecar)
           - <stem>.calibration.json       (Stage 1-2 RT/MS2/MS1 cal)
           - <stem>.spectra.bin            (Stage 1 spectra cache)
           - <stem>.mzML                   (synthetic input, never opened)
           - <library>.tsv + <library>.tsv.libcache
      4. Write a .fixture-version file recording (osprey version,
         OspreySharp version, build timestamp) so iteration-time
         scripts can detect a stale fixture.

.PARAMETER Dataset
    Stellar | Astral | Both (default Stellar).

.PARAMETER TestBaseDir
    Override test data root (defaults to OSPREY_TEST_BASE_DIR or
    D:\test\osprey-runs).

.PARAMETER CsharpRoot
    pwiz worktree with built OspreySharp.exe (auto-detect if omitted).

.PARAMETER TargetFramework
    net472 or net8.0 (default net8.0).

.PARAMETER Force
    Rebuild the fixture even if one already exists.

.EXAMPLE
    # Build Stellar fixture after a v26.x bump.
    .\Build-Stage6Fixture.ps1 -Dataset Stellar -Force
#>

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("Stellar", "Astral", "Both")]
    [string]$Dataset = "Stellar",

    [string]$TestBaseDir = $null,

    [string]$CsharpRoot = $null,

    [ValidateSet("net472", "net8.0")]
    [string]$TargetFramework = "net8.0",

    [switch]$Force
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

. "$PSScriptRoot\Dataset-Config.ps1"

$scriptRoot = Split-Path -Parent $PSCommandPath

$datasets = if ($Dataset -eq "Both") { @("Stellar","Astral") } else { @($Dataset) }
$totalStart = [Diagnostics.Stopwatch]::StartNew()

foreach ($dsName in $datasets) {
    $ds = Get-DatasetConfig $dsName -TestBaseDir $TestBaseDir
    $testDir = $ds.TestDir
    $stems = $ds.AllFiles | ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_) }
    $fixtureDir = Join-Path $testDir ("_stage6_fixture\{0}" -f $ds.Name)

    Write-Host ("=== {0} (TestDir: {1}) ===" -f $ds.Name, $testDir) -ForegroundColor Cyan

    # If fixture exists and -Force not passed, sanity-check + skip.
    $fixtureMarker = Join-Path $fixtureDir ".fixture-version"
    if ((Test-Path $fixtureMarker) -and -not $Force)
    {
        Write-Host ("  Fixture already present at {0}." -f $fixtureDir) -ForegroundColor Green
        Write-Host "  Skipping (pass -Force to rebuild)." -ForegroundColor Gray
        continue
    }

    # Step 1: confirm Stage 4 Snappy parquets exist.
    $rustParquets = @()
    foreach ($stem in $stems) {
        $rustParquet = Join-Path $testDir "$stem.scores.rust.parquet"
        if (-not (Test-Path $rustParquet)) {
            Write-Host ("  Missing Stage 4 parquet for {0}." -f $stem) -ForegroundColor Red
            Write-Host "  Run Generate-AllScoresParquet.ps1 first." -ForegroundColor Red
            exit 1
        }
        $rustParquets += $rustParquet
    }

    # Step 2: verify Stage 5 boundary parity. Compare-Stage5-Boundary.ps1
    # is the canonical gate for this; failure means Stage 6 testing
    # would build on drifted Stage 5 outputs and any Stage 6 divergence
    # would be impossible to attribute. Refuse to build the fixture.
    Write-Host "  Step 2: verifying Stage 5 boundary parity..." -ForegroundColor Yellow
    $stage5Args = @("-File", (Join-Path $scriptRoot "Compare-Stage5-Boundary.ps1"),
                    "-Dataset", $ds.Name, "-Clean",
                    "-TargetFramework", $TargetFramework)
    if ($CsharpRoot) { $stage5Args += @("-CsharpRoot", $CsharpRoot) }
    if ($TestBaseDir) { $stage5Args += @("-TestBaseDir", $TestBaseDir) }
    & pwsh @stage5Args
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  Stage 5 boundary parity FAILED. Refusing to build fixture." -ForegroundColor Red
        Write-Host "  Investigate Stage 5 divergence before retrying." -ForegroundColor Red
        exit 1
    }

    # Step 3: build fixture from the verified-identical state.
    Write-Host ("  Step 3: building fixture at {0}..." -f $fixtureDir) -ForegroundColor Yellow
    if (Test-Path $fixtureDir) {
        Remove-Item $fixtureDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $fixtureDir -Force | Out-Null

    $stage5WorkDir = Join-Path $testDir ("_stage5_boundary\{0}" -f $ds.Name)
    $rustOutputs = Join-Path $stage5WorkDir "rust_outputs"

    foreach ($stem in $stems) {
        # Stage 4 parquet (Snappy from Rust).
        Copy-Item -Path (Join-Path $testDir "$stem.scores.rust.parquet") `
                  -Destination (Join-Path $fixtureDir "$stem.scores.parquet")
        # Verified-identical Stage 5 sidecars (from Compare-Stage5-Boundary
        # rust_outputs; equivalent to cs_outputs at this checkpoint).
        Copy-Item -Path (Join-Path $rustOutputs "$stem.1st-pass.fdr_scores.bin") `
                  -Destination (Join-Path $fixtureDir "$stem.1st-pass.fdr_scores.bin")
        Copy-Item -Path (Join-Path $rustOutputs "$stem.reconciliation.json") `
                  -Destination (Join-Path $fixtureDir "$stem.reconciliation.json")
        # Stage 1-2 calibration JSON (RT + MS2/MS1 cal). Worker reads it
        # back at Stage 6 entry to seed the rescore search.
        Copy-Item -Path (Join-Path $stage5WorkDir "$stem.calibration.json") `
                  -Destination (Join-Path $fixtureDir "$stem.calibration.json")
        # Stage 1 spectra cache + the synthetic mzML name. Worker uses
        # cache when present; mzML path is the fallback parser source AND
        # the stem source for path-derivation helpers.
        $spectraCacheSrc = Join-Path $testDir "$stem.spectra.bin"
        if (Test-Path $spectraCacheSrc) {
            Copy-Item -Path $spectraCacheSrc `
                      -Destination (Join-Path $fixtureDir "$stem.spectra.bin")
        }
        $mzmlSrc = Join-Path $testDir "$stem.mzML"
        if (Test-Path $mzmlSrc) {
            Copy-Item -Path $mzmlSrc `
                      -Destination (Join-Path $fixtureDir "$stem.mzML")
        }
    }
    # Library + libcache.
    Copy-Item -Path (Join-Path $testDir $ds.Library) `
              -Destination (Join-Path $fixtureDir $ds.Library)
    $libcache = Join-Path $testDir ($ds.Library + ".libcache")
    if (Test-Path $libcache) {
        Copy-Item -Path $libcache `
                  -Destination (Join-Path $fixtureDir ($ds.Library + ".libcache"))
    }

    # Step 4: stamp the fixture with version info for stale-detection.
    $rustVersion = "unknown"
    $csharpVersion = "unknown"
    try {
        $aiRoot = Split-Path -Parent (Split-Path -Parent $scriptRoot)
        $projRoot = Split-Path -Parent $aiRoot
        $rustBin = Join-Path $projRoot "osprey\target\release\osprey.exe"
        if (Test-Path $rustBin) {
            $verLines = & $rustBin --version 2>&1
            if ($verLines -match "osprey\s+(\S+)") { $rustVersion = $Matches[1] }
        }
        $csharpRelBin = "pwiz_tools\OspreySharp\OspreySharp\bin\x64\Release\$TargetFramework\OspreySharp.exe"
        if ($CsharpRoot) { $csharpBase = $CsharpRoot } else {
            $csharpBase = $null
            foreach ($c in @("pwiz", "pwiz-work1", "pwiz-work2")) {
                $p = Join-Path $projRoot $c
                if (Test-Path (Join-Path $p $csharpRelBin)) { $csharpBase = $p; break }
            }
            if (-not $csharpBase) { $csharpBase = Join-Path $projRoot "pwiz" }
        }
        $csharpBin = Join-Path $csharpBase $csharpRelBin
        if (Test-Path $csharpBin) {
            $verLines = & $csharpBin --version 2>&1
            if ($verLines -match "OspreySharp\s+v?(\S+)") { $csharpVersion = $Matches[1] }
        }
    } catch {
        # version detection is best-effort
    }
    $stamp = [ordered]@{
        BuildTimestamp = (Get-Date -Format o)
        Dataset = $ds.Name
        RustVersion = $rustVersion
        OspreySharpVersion = $csharpVersion
        Files = $stems
    }
    $stamp | ConvertTo-Json | Set-Content -Path $fixtureMarker -Encoding UTF8

    # Done.
    Write-Host ("  Fixture built at {0}" -f $fixtureDir) -ForegroundColor Green
    $size = (Get-ChildItem $fixtureDir -Recurse -File | Measure-Object Length -Sum).Sum
    Write-Host ("  Fixture size: {0:N0} MB" -f ($size / 1MB)) -ForegroundColor DarkGray
    Write-Host ""
}

$totalStart.Stop()
Write-Host ("Build-Stage6Fixture complete in {0:mm\:ss}" -f $totalStart.Elapsed) `
    -ForegroundColor Green
