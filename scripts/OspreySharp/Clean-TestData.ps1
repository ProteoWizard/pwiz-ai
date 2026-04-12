<#
.SYNOPSIS
    Clean cached and diagnostic files from test data directories

.PARAMETER TestDataDir
    Path to the test data directory (default: D:\test\osprey-runs\stellar)

.PARAMETER DiagOnly
    Only clean diagnostic dumps, keep caches

.EXAMPLE
    .\Clean-TestData.ps1
    Clean all caches and diagnostic files

.EXAMPLE
    .\Clean-TestData.ps1 -DiagOnly
    Clean only diagnostic dump files (keep parquet/calibration caches)
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$TestDataDir = "D:\test\osprey-runs\stellar",

    [Parameter(Mandatory=$false)]
    [switch]$DiagOnly = $false
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $TestDataDir)) {
    Write-Error "Directory not found: $TestDataDir"
    exit 1
}

$removed = 0

if (-not $DiagOnly) {
    # Cache files
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

# Diagnostic dumps
$diagPatterns = @(
    "rust_search_xic_entry_*.txt",
    "cs_search_xic_entry_*.txt",
    "rust_xic_entry_*.txt",
    "cs_xic_entry_*.txt",
    "rust_cal_match.txt",
    "cs_cal_match.txt",
    "rust_cal_windows.txt",
    "cs_cal_windows.txt",
    "rust_lda_scores.txt",
    "cs_lda_scores.txt",
    "cs_loess_input.txt",
    "rust_loess_input.txt",
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
