<#
.SYNOPSIS
    Clean cached and diagnostic files from a test data directory.

.DESCRIPTION
    Removes score caches, calibration JSON, spectra caches, FDR score
    sidecars, and all the cross-implementation diagnostic dump files
    produced by Run-Osprey.ps1 / Compare-Diagnostic.ps1.

    The target directory is resolved via Dataset-Config.ps1 by default,
    which honors $env:OSPREY_TEST_BASE_DIR. Pass -TestDataDir to override.

.PARAMETER Dataset
    Stellar or Astral (default: Stellar). Selects the TestDir from
    Dataset-Config.ps1.

.PARAMETER TestDataDir
    Explicit path override. When set, -Dataset is ignored.

.PARAMETER TestBaseDir
    Override the Dataset-Config.ps1 base directory. Honors
    $env:OSPREY_TEST_BASE_DIR if not passed. Ignored when -TestDataDir
    is set.

.PARAMETER DiagOnly
    Only clean diagnostic dumps; keep cache files (score parquet,
    calibration JSON, spectra bin, FDR score sidecar).

.EXAMPLE
    .\Clean-TestData.ps1
    Clean all caches and diag dumps from the Stellar test dir.

.EXAMPLE
    .\Clean-TestData.ps1 -Dataset Astral -DiagOnly
    Clean only diag dumps from the Astral test dir (keep caches).

.EXAMPLE
    .\Clean-TestData.ps1 -TestDataDir "C:\scratch\stellar"
    Clean a custom directory.
#>

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("Stellar", "Astral")]
    [string]$Dataset = "Stellar",

    [Parameter(Mandatory=$false)]
    [string]$TestDataDir = $null,

    [Parameter(Mandatory=$false)]
    [string]$TestBaseDir = $null,

    [Parameter(Mandatory=$false)]
    [switch]$DiagOnly = $false
)

$ErrorActionPreference = "Stop"

# Resolve target directory. Explicit TestDataDir wins; otherwise use
# Dataset-Config.ps1, which honors OSPREY_TEST_BASE_DIR.
if ([string]::IsNullOrEmpty($TestDataDir)) {
    . "$PSScriptRoot\Dataset-Config.ps1"
    $TestDataDir = (Get-DatasetConfig $Dataset -TestBaseDir $TestBaseDir).TestDir
}

if (-not (Test-Path $TestDataDir)) {
    Write-Error "Directory not found: $TestDataDir"
    exit 1
}

$removed = 0

if (-not $DiagOnly) {
    # Cache files produced during normal runs
    $cachePatterns = @(
        "*.scores.parquet",
        "*.calibration.json",
        "*.spectra.bin",
        "*.fdr_scores.bin",
        "*.mzML.spectra.bin"
    )
    foreach ($pattern in $cachePatterns) {
        $files = Get-ChildItem -Path $TestDataDir -Filter $pattern -ErrorAction SilentlyContinue
        foreach ($f in $files) {
            Remove-Item $f.FullName -Force
            $removed++
        }
    }
}

# Diagnostic dump files. Rust names are flat (rust_*.txt). On the C#
# side, cal_sample is prefixed with the mzML stem (OspreyDiagnostics.cs
# line 164) while the other dumps are flat. The prefixed-glob wildcard
# catches any file stem.
$diagPatterns = @(
    # Cal sample + grid + scalars
    "rust_cal_sample.txt", "*.cs_cal_sample.txt",
    "rust_cal_scalars.txt", "cs_cal_scalars.txt",
    "rust_cal_grid.txt", "cs_cal_grid.txt",
    # Cal windows
    "rust_cal_windows.txt", "cs_cal_windows.txt",
    # Cal prefilter (Rust-only)
    "rust_cal_prefilter.txt",
    # Cal match
    "rust_cal_match.txt", "cs_cal_match.txt",
    # LDA scores + q-values
    "rust_lda_scores.txt", "cs_lda_scores.txt",
    # LOESS input pairs
    "rust_loess_input.txt", "cs_loess_input.txt",
    # Per-entry XIC + search diagnostics
    "rust_search_xic_entry_*.txt", "cs_search_xic_entry_*.txt",
    "rust_xic_entry_*.txt", "cs_xic_entry_*.txt",
    # Median-polish + XCorr per-scan diagnostics
    "rust_mp_diag.txt", "cs_mp_diag.txt",
    "rust_xcorr_diag.txt", "cs_xcorr_diag.txt",
    # C# feature-dump TSV (end-to-end parity check output)
    "*.cs_features.tsv"
)
foreach ($pattern in $diagPatterns) {
    $files = Get-ChildItem -Path $TestDataDir -Filter $pattern -ErrorAction SilentlyContinue
    foreach ($f in $files) {
        Remove-Item $f.FullName -Force
        $removed++
    }
}

# Mokapot PIN files
$pinDir = Join-Path $TestDataDir "mokapot"
if (Test-Path $pinDir) {
    $pins = Get-ChildItem -Path $pinDir -Filter "*.pin" -ErrorAction SilentlyContinue
    foreach ($f in $pins) {
        Remove-Item $f.FullName -Force
        $removed++
    }
}

$label = if ($DiagOnly) { "diagnostic" } else { "cache + diagnostic" }
Write-Host "Cleaned $removed $label files from $TestDataDir" -ForegroundColor Green
