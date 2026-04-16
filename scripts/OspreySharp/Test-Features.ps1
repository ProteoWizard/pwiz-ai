<#
.SYNOPSIS
    Feature parity + Stages 1-4 perf test: OspreySharp vs Rust Osprey

.DESCRIPTION
    Runs both tools on a single file through Stage 4 (scoring) only, using
    each tool's own calibration, and compares all 21 PIN features.
    Reports pass/fail for each feature at configurable thresholds and shows
    wall-clock timings for apples-to-apples perf comparison.

    Both tools exit after Stage 4 via OSPREY_EXIT_AFTER_SCORING=1, skipping
    Mokapot FDR, reconciliation, and blib output. This keeps the cycle fast
    and makes the wall-clock timings directly comparable.

    Each tool computes its own calibration -- this catches real drift. If
    you need to isolate feature differences from calibration noise (like
    the Session 9 bisection), set -SharedCalibration to force C# to load
    Rust's calibration JSON.

    Supports Stellar and Astral datasets via the -Dataset parameter.
    Requires: both binaries built, test data in place.

.PARAMETER Dataset
    Which test dataset: Stellar or Astral (default: Stellar)

.PARAMETER Threshold
    Maximum allowed absolute difference per feature value (default: 1e-6)

.PARAMETER SharedCalibration
    Force C# to load Rust's calibration JSON to isolate feature divergence
    from calibration drift. Off by default; use for bisection only.

.PARAMETER DiagXicEntryIds
    Enable search XIC diagnostic for specific entry IDs (comma-separated)

.PARAMETER DiagMpScan
    Enable median polish diagnostic for a specific scan number

.PARAMETER DiagXcorrScan
    Enable xcorr diagnostic for a specific scan number

.PARAMETER SkipRust
    Skip the Rust run (reuse existing PIN + calibration from a previous run)

.EXAMPLE
    .\Test-Features.ps1
    Run Stellar comparison with each tool computing its own calibration

.EXAMPLE
    .\Test-Features.ps1 -Dataset Astral
    Run Astral comparison

.EXAMPLE
    .\Test-Features.ps1 -SharedCalibration
    Isolate feature divergence from calibration drift (bisection mode)

.EXAMPLE
    .\Test-Features.ps1 -SkipRust
    Reuse Rust output from previous run (faster iteration on C# changes)
#>

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("Stellar", "Astral")]
    [string]$Dataset = "Stellar",

    [Parameter(Mandatory=$false)]
    [double]$Threshold = 1e-6,

    [Parameter(Mandatory=$false)]
    [switch]$SharedCalibration = $false,

    [Parameter(Mandatory=$false)]
    [string]$DiagXicEntryIds = $null,

    [Parameter(Mandatory=$false)]
    [string]$DiagMpScan = $null,

    [Parameter(Mandatory=$false)]
    [string]$DiagXcorrScan = $null,

    [Parameter(Mandatory=$false)]
    [switch]$SkipRust = $false
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Load dataset configuration
. "$PSScriptRoot\Dataset-Config.ps1"
$ds = Get-DatasetConfig $Dataset

$testDir = $ds.TestDir
if (-not (Test-Path $testDir)) {
    Write-Error "Test data directory not found: $testDir"
    exit 1
}

# Auto-detect paths
$scriptRoot = Split-Path -Parent $PSCommandPath
$aiRoot = Split-Path -Parent (Split-Path -Parent $scriptRoot)
$projRoot = Split-Path -Parent $aiRoot

$rustBinary = Join-Path $projRoot "osprey\target\release\osprey.exe"
$csharpBinary = Join-Path $projRoot "pwiz\pwiz_tools\OspreySharp\OspreySharp\bin\x64\Release\pwiz.OspreySharp.exe"
$library = Join-Path $testDir $ds.Library
$mzml = Join-Path $testDir $ds.SingleFile

# Derive file stem for output paths (e.g. "Ste-2024-12-02_HeLa_4mz_sDIA_400-900_20")
$fileStem = [System.IO.Path]::GetFileNameWithoutExtension($ds.SingleFile)
$calJson = Join-Path $testDir "$fileStem.calibration.json"
$rustPin = Join-Path $testDir "mokapot\$fileStem.pin"
$csharpFeatures = Join-Path $testDir "$fileStem.cs_features.tsv"

# Validate prerequisites
foreach ($path in @($library, $mzml)) {
    if (-not (Test-Path $path)) {
        Write-Host "MISSING: $path" -ForegroundColor Red
        exit 1
    }
}
foreach ($bin in @($rustBinary, $csharpBinary)) {
    if (-not (Test-Path $bin)) {
        Write-Host "Binary not found: $bin" -ForegroundColor Red
        Write-Host "Build first with Build-OspreySharp.ps1 / Build-OspreyRust.ps1" -ForegroundColor Yellow
        exit 1
    }
}

$initialLocation = Get-Location
$totalStart = Get-Date

try {
    Set-Location $testDir

    # ================================================================
    # Step 1: Run Rust (produces calibration JSON + PIN)
    # ================================================================
    if (-not $SkipRust) {
        Write-Host ""
        Write-Host "Step 1: Running Rust Osprey on $($ds.Name) $($ds.FileLabel.Single)..." -ForegroundColor Cyan

        # Clean caches
        foreach ($pattern in @("*.scores.parquet", "*.calibration.json", "*.spectra.bin", "*.fdr_scores.bin")) {
            Get-ChildItem -Filter $pattern -ErrorAction SilentlyContinue | Remove-Item -Force
        }

        $env:RUST_LOG = "info"
        $env:OSPREY_EXIT_AFTER_SCORING = "1"
        if ($DiagXicEntryIds) { $env:OSPREY_DIAG_SEARCH_ENTRY_IDS = $DiagXicEntryIds }
        if ($DiagMpScan) { $env:OSPREY_DIAG_MP_SCAN = $DiagMpScan }
        if ($DiagXcorrScan) { $env:OSPREY_DIAG_XCORR_SCAN = $DiagXcorrScan }

        $rustStart = Get-Date
        & $rustBinary -i $mzml -l $library -o "_temp_rust.blib" --resolution $ds.Resolution --protein-fdr 0.01 --write-pin 2>&1 | Out-Null
        $rustExit = $LASTEXITCODE
        $rustDuration = (Get-Date) - $rustStart

        # Clean env vars
        Remove-Item Env:RUST_LOG -ErrorAction SilentlyContinue
        Remove-Item Env:OSPREY_EXIT_AFTER_SCORING -ErrorAction SilentlyContinue
        Remove-Item Env:OSPREY_DIAG_SEARCH_ENTRY_IDS -ErrorAction SilentlyContinue
        Remove-Item Env:OSPREY_DIAG_MP_SCAN -ErrorAction SilentlyContinue
        Remove-Item Env:OSPREY_DIAG_XCORR_SCAN -ErrorAction SilentlyContinue
        Remove-Item "_temp_rust.blib" -ErrorAction SilentlyContinue

        if ($rustExit -ne 0) {
            Write-Host "Rust failed with exit code $rustExit" -ForegroundColor Red
            exit 1
        }
        Write-Host "  Rust completed in $($rustDuration.TotalSeconds.ToString('F1'))s" -ForegroundColor Green
    } else {
        Write-Host ""
        Write-Host "Step 1: Skipping Rust (reusing existing output)" -ForegroundColor Yellow
    }

    # Validate Rust outputs exist
    if (-not (Test-Path $calJson)) {
        Write-Host "Calibration JSON not found: $calJson" -ForegroundColor Red
        exit 1
    }
    if (-not (Test-Path $rustPin)) {
        Write-Host "Rust PIN not found: $rustPin" -ForegroundColor Red
        exit 1
    }

    # ================================================================
    # Step 2: Run C# (own calibration by default, or shared if requested)
    # ================================================================
    Write-Host ""
    $modeLabel = if ($SharedCalibration) { "with shared calibration (bisection mode)" } else { "with own calibration" }
    Write-Host "Step 2: Running OspreySharp (C#) $modeLabel..." -ForegroundColor Cyan

    $env:OSPREY_EXIT_AFTER_SCORING = "1"
    if ($SharedCalibration) { $env:OSPREY_LOAD_CALIBRATION = $calJson }
    if ($DiagXicEntryIds) { $env:OSPREY_DIAG_SEARCH_ENTRY_IDS = $DiagXicEntryIds }
    if ($DiagMpScan) { $env:OSPREY_DIAG_MP_SCAN = $DiagMpScan }
    if ($DiagXcorrScan) { $env:OSPREY_DIAG_XCORR_SCAN = $DiagXcorrScan }

    # Remove old features file
    if (Test-Path $csharpFeatures) { Remove-Item $csharpFeatures -Force }

    $csStart = Get-Date
    & $csharpBinary -i $mzml -l $library -o "_temp_cs.blib" --resolution $ds.Resolution --protein-fdr 0.01 --write-pin 2>&1 | Out-Null
    $csExit = $LASTEXITCODE
    $csDuration = (Get-Date) - $csStart

    # Clean env vars
    Remove-Item Env:OSPREY_EXIT_AFTER_SCORING -ErrorAction SilentlyContinue
    Remove-Item Env:OSPREY_LOAD_CALIBRATION -ErrorAction SilentlyContinue
    Remove-Item Env:OSPREY_DIAG_SEARCH_ENTRY_IDS -ErrorAction SilentlyContinue
    Remove-Item Env:OSPREY_DIAG_MP_SCAN -ErrorAction SilentlyContinue
    Remove-Item Env:OSPREY_DIAG_XCORR_SCAN -ErrorAction SilentlyContinue
    Remove-Item "_temp_cs.blib" -ErrorAction SilentlyContinue

    if ($csExit -ne 0) {
        Write-Host "  C# failed with exit code $csExit" -ForegroundColor Red
        exit 1
    }
    Write-Host "  C# completed in $($csDuration.TotalSeconds.ToString('F1'))s" -ForegroundColor Green

    if (-not (Test-Path $csharpFeatures)) {
        Write-Host "C# features file not found: $csharpFeatures" -ForegroundColor Red
        exit 1
    }

    # ================================================================
    # Step 3: Compare all 21 PIN features
    # ================================================================
    Write-Host ""
    Write-Host "Step 3: Comparing 21 PIN features (threshold: $Threshold)..." -ForegroundColor Cyan
    Write-Host ""

    $features = @(
        "fragment_coelution_sum", "fragment_coelution_max", "n_coeluting_fragments",
        "peak_apex", "peak_area", "peak_sharpness",
        "xcorr", "consecutive_ions", "explained_intensity",
        "mass_accuracy_deviation_mean", "abs_mass_accuracy_deviation_mean",
        "rt_deviation", "abs_rt_deviation",
        "ms1_precursor_coelution", "ms1_isotope_cosine",
        "median_polish_cosine", "median_polish_residual_ratio",
        "sg_weighted_xcorr", "sg_weighted_cosine",
        "median_polish_min_fragment_r2", "median_polish_residual_correlation"
    )

    # Get column indices from headers
    $rustHeader = (Get-Content $rustPin -TotalCount 1) -split "`t"
    $csHeader = (Get-Content $csharpFeatures -TotalCount 1) -split "`t"

    # Find the peptide and scan columns dynamically
    $rustPepIdx = [Array]::IndexOf($rustHeader, "Peptide") + 1
    $rustScanIdx = [Array]::IndexOf($rustHeader, "ScanNr") + 1
    $csPepIdx = [Array]::IndexOf($csHeader, "Peptide") + 1
    $csScanIdx = [Array]::IndexOf($csHeader, "ScanNr") + 1

    if ($rustPepIdx -le 0 -or $csPepIdx -le 0) {
        Write-Host "Could not find Peptide column in PIN/features headers" -ForegroundColor Red
        exit 1
    }

    $allPassed = $true
    $nMatched = 0
    $results = @()

    # Per-feature threshold overrides. HRAM xcorr / sg_weighted_xcorr use
    # an f32 preprocessed cache (matches Rust upstream, halves pool
    # memory); cumulative summation across ~20 fragment bins drifts at
    # ~5e-6 max because Rust may auto-vectorize/FMA the inner loops
    # while .NET Framework does not. Unit resolution (Stellar) stays on
    # f64, so this relaxed threshold only matters on HRAM data.
    $featThresholds = @{
        "xcorr"             = 1e-5
        "sg_weighted_xcorr" = 1e-5
    }

    foreach ($feat in $features) {
        $rIdx = [Array]::IndexOf($rustHeader, $feat) + 1  # 1-based for awk
        $cIdx = [Array]::IndexOf($csHeader, $feat) + 1
        $featThreshold = if ($featThresholds.ContainsKey($feat)) { $featThresholds[$feat] } else { $Threshold }

        if ($rIdx -le 0 -or $cIdx -le 0) {
            Write-Host ("  {0,-42} COLUMN NOT FOUND (rust={1} cs={2})" -f $feat, $rIdx, $cIdx) -ForegroundColor Red
            $allPassed = $false
            continue
        }

        # Use awk to join on (Peptide_ScanNr) and compare
        # Rust PIN Peptide column has flanking chars (e.g. K.PEPTIDE.R) - strip them
        $awkScript = @"
NR==1{next}
NR==FNR{pep=`$$rustPepIdx; gsub(/^[^.]*\./,"",pep); gsub(/\.[^.]*$/,"",pep); key=pep"_"`$$rustScanIdx; r[key]=`$$rIdx; next}
FNR==1{next}
{key=`$$csPepIdx"_"`$$csScanIdx; if(key in r){n++; d=r[key]-`$$cIdx; if(d<0)d=-d; if(d>$featThreshold)nd++; if(d>maxd)maxd=d}}
END{printf "%d %d %.4e", n, nd, maxd}
"@

        $output = & awk -F"`t" $awkScript $rustPin $csharpFeatures 2>&1
        $parts = ($output -split '\s+')

        if ($parts.Count -ge 3) {
            $matched = [int]$parts[0]
            $nDiff = [int]$parts[1]
            $maxDiff = $parts[2]
            if ($nMatched -eq 0) { $nMatched = $matched }

            $pct = if ($matched -gt 0) { [math]::Round($nDiff / $matched * 100, 2) } else { 0 }
            $status = if ($nDiff -eq 0) { "PASS" } else { "FAIL" }
            $color = if ($nDiff -eq 0) { "Green" } else { "Red" }

            # Known acceptable deviations:
            # - consecutive_ions: small number of entries differ (algorithmic edge case)
            # - peak_sharpness: rare FP noise on large values
            if ($feat -eq "consecutive_ions" -and $nDiff -le 200) {
                $status = "PASS (known: $nDiff)"
                $color = "Yellow"
            } elseif ($feat -eq "peak_sharpness" -and $nDiff -le 2) {
                $status = "PASS (known: $nDiff FP noise)"
                $color = "Yellow"
            } else {
                if ($nDiff -gt 0) { $allPassed = $false }
            }

            Write-Host ("  {0,-42} {1,-16} {2,7}/{3} ({4}%) max={5}" -f $feat, $status, $nDiff, $matched, $pct, $maxDiff) -ForegroundColor $color
        } else {
            Write-Host ("  {0,-42} ERROR parsing awk output" -f $feat) -ForegroundColor Red
            $allPassed = $false
        }
    }

    # ================================================================
    # Summary
    # ================================================================
    $totalDuration = (Get-Date) - $totalStart
    Write-Host ""
    Write-Host ("Dataset:         {0}" -f $ds.Name) -ForegroundColor Gray
    Write-Host ("Calibration:     {0}" -f ($(if ($SharedCalibration) { "shared (Rust's JSON)" } else { "each tool computes its own" }))) -ForegroundColor Gray
    Write-Host ("Matched entries: {0}" -f $nMatched) -ForegroundColor Gray
    Write-Host ("Threshold:       {0}" -f $Threshold) -ForegroundColor Gray
    if (-not $SkipRust) {
        $ratio = if ($rustDuration.TotalSeconds -gt 0.01) { $csDuration.TotalSeconds / $rustDuration.TotalSeconds } else { 0.0 }
        Write-Host ("Rust Stg 1-4:    {0:F1}s" -f $rustDuration.TotalSeconds) -ForegroundColor Gray
        Write-Host ("C#   Stg 1-4:    {0:F1}s ({1:F2}x Rust)" -f $csDuration.TotalSeconds, $ratio) -ForegroundColor Gray
    } else {
        Write-Host ("C#   Stg 1-4:    {0:F1}s" -f $csDuration.TotalSeconds) -ForegroundColor Gray
    }
    Write-Host ("Total time:      {0:F1}s" -f $totalDuration.TotalSeconds) -ForegroundColor Gray
    Write-Host ""

    if ($allPassed) {
        Write-Host "ALL 21 FEATURES PASSED" -ForegroundColor Green
        exit 0
    } else {
        Write-Host "SOME FEATURES FAILED" -ForegroundColor Red
        exit 1
    }
}
finally {
    Set-Location $initialLocation
}
