<#
.SYNOPSIS
    Run OspreySharp or Rust Osprey on Stellar test data

.DESCRIPTION
    Runs either the C# (OspreySharp) or Rust (Osprey) implementation on the
    Stellar test dataset. Handles cache cleaning, diagnostic env vars, and
    common flags (--resolution unit is always applied for Stellar).

    Test data: D:\test\osprey-runs\stellar\

.PARAMETER Tool
    Which tool to run: CSharp or Rust (default: CSharp)

.PARAMETER Files
    Which mzML files: Single (file 20 only) or All (files 20-22). Default: Single

.PARAMETER Clean
    Clean cached files before running (parquet, calibration, spectra caches)

.PARAMETER WritePin
    Write PIN feature dump for cross-implementation comparison

.PARAMETER DiagEntryIds
    Comma-separated entry IDs for OSPREY_DIAG_SEARCH_ENTRY_IDS diagnostic

.PARAMETER DiagCalMatch
    Set OSPREY_DUMP_CAL_MATCH=1 to dump calibration match features

.PARAMETER DiagCalMatchOnly
    Set OSPREY_CAL_MATCH_ONLY=1 to exit after cal_match dump

.PARAMETER DiagLdaScores
    Set OSPREY_DUMP_LDA_SCORES=1 to dump LDA discriminant scores

.PARAMETER DiagLdaOnly
    Set OSPREY_LDA_SCORES_ONLY=1 to exit after LDA dump

.PARAMETER DiagLoessInput
    Set OSPREY_DUMP_LOESS_INPUT=1 to dump LOESS input pairs

.PARAMETER DiagLoessOnly
    Set OSPREY_LOESS_INPUT_ONLY=1 to exit after LOESS input dump

.PARAMETER ExtraArgs
    Additional arguments to pass to the tool (e.g. "--protein-fdr 0.01")

.PARAMETER TestDataDir
    Path to the Stellar test data directory (default: D:\test\osprey-runs\stellar)

.EXAMPLE
    .\Run-Stellar.ps1
    Run C# on single file (file 20)

.EXAMPLE
    .\Run-Stellar.ps1 -Tool Rust -Files All -Clean
    Clean caches and run Rust on all 3 files

.EXAMPLE
    .\Run-Stellar.ps1 -Clean -WritePin
    Clean and run C# with feature dump

.EXAMPLE
    .\Run-Stellar.ps1 -DiagEntryIds "0,1080,5765,28988"
    Run C# with search XIC diagnostic for specific entries

.EXAMPLE
    .\Run-Stellar.ps1 -Tool Rust -DiagCalMatch -DiagCalMatchOnly
    Run Rust, dump cal_match features, and exit
#>

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("CSharp", "Rust")]
    [string]$Tool = "CSharp",

    [Parameter(Mandatory=$false)]
    [ValidateSet("Single", "All")]
    [string]$Files = "Single",

    [Parameter(Mandatory=$false)]
    [switch]$Clean = $false,

    [Parameter(Mandatory=$false)]
    [switch]$WritePin = $false,

    [Parameter(Mandatory=$false)]
    [switch]$Summary = $false,

    [Parameter(Mandatory=$false)]
    [string]$DiagEntryIds = $null,

    [Parameter(Mandatory=$false)]
    [switch]$DiagCalMatch = $false,

    [Parameter(Mandatory=$false)]
    [switch]$DiagCalMatchOnly = $false,

    [Parameter(Mandatory=$false)]
    [switch]$DiagLdaScores = $false,

    [Parameter(Mandatory=$false)]
    [switch]$DiagLdaOnly = $false,

    [Parameter(Mandatory=$false)]
    [switch]$DiagLoessInput = $false,

    [Parameter(Mandatory=$false)]
    [switch]$DiagLoessOnly = $false,

    [Parameter(Mandatory=$false)]
    [string]$ExtraArgs = $null,

    [Parameter(Mandatory=$false)]
    [string]$TestDataDir = "D:\test\osprey-runs\stellar"
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Validate test data directory
if (-not (Test-Path $TestDataDir)) {
    Write-Error "Test data directory not found: $TestDataDir"
    exit 1
}

# Auto-detect project root
$scriptRoot = Split-Path -Parent $PSCommandPath
$aiRoot = Split-Path -Parent (Split-Path -Parent $scriptRoot)
$projRoot = Split-Path -Parent $aiRoot

# Tool binaries
$csharpBinary = Join-Path $projRoot "pwiz\pwiz_tools\OspreySharp\OspreySharp\bin\x64\Release\pwiz.OspreySharp.exe"
$rustBinary = Join-Path $projRoot "osprey\target\release\osprey.exe"

$binary = if ($Tool -eq "CSharp") { $csharpBinary } else { $rustBinary }
if (-not (Test-Path $binary)) {
    Write-Error "$Tool binary not found at: $binary`nRun Build-OspreySharp.ps1 or Build-OspreyRust.ps1 first."
    exit 1
}

# Library
$library = Join-Path $TestDataDir "hela-filtered-SkylineAI_spectral_library.tsv"
if (-not (Test-Path $library)) {
    Write-Error "Library not found: $library"
    exit 1
}

# mzML files
$mzmlFiles = if ($Files -eq "Single") {
    @(Join-Path $TestDataDir "Ste-2024-12-02_HeLa_4mz_sDIA_400-900_20.mzML")
} else {
    @(
        (Join-Path $TestDataDir "Ste-2024-12-02_HeLa_4mz_sDIA_400-900_20.mzML"),
        (Join-Path $TestDataDir "Ste-2024-12-02_HeLa_4mz_sDIA_400-900_21.mzML"),
        (Join-Path $TestDataDir "Ste-2024-12-02_HeLa_4mz_sDIA_400-900_22.mzML")
    )
}
foreach ($f in $mzmlFiles) {
    if (-not (Test-Path $f)) {
        Write-Error "mzML file not found: $f"
        exit 1
    }
}

$initialLocation = Get-Location

try {
    Set-Location $TestDataDir

    # Clean caches if requested
    if ($Clean) {
        Write-Host "Cleaning cached files..." -ForegroundColor Cyan
        $patterns = @("*.scores.parquet", "*.calibration.json", "*.spectra.bin",
                      "*.fdr_scores.bin", "*.mzML.spectra.bin")
        foreach ($pattern in $patterns) {
            Get-ChildItem -Path $TestDataDir -Filter $pattern -ErrorAction SilentlyContinue |
                Remove-Item -Force
        }
        # Also clean diagnostic dumps
        Get-ChildItem -Path $TestDataDir -Filter "rust_search_xic_entry_*.txt" -ErrorAction SilentlyContinue |
            Remove-Item -Force
        Get-ChildItem -Path $TestDataDir -Filter "cs_search_xic_entry_*.txt" -ErrorAction SilentlyContinue |
            Remove-Item -Force
        Write-Host "Caches cleaned" -ForegroundColor Green
    }

    # Set diagnostic env vars
    $envVarsSet = @()
    if ($DiagEntryIds) {
        $env:OSPREY_DIAG_SEARCH_ENTRY_IDS = $DiagEntryIds
        $envVarsSet += "OSPREY_DIAG_SEARCH_ENTRY_IDS=$DiagEntryIds"
    }
    if ($DiagCalMatch) {
        $env:OSPREY_DUMP_CAL_MATCH = "1"
        $envVarsSet += "OSPREY_DUMP_CAL_MATCH=1"
    }
    if ($DiagCalMatchOnly) {
        $env:OSPREY_CAL_MATCH_ONLY = "1"
        $envVarsSet += "OSPREY_CAL_MATCH_ONLY=1"
    }
    if ($DiagLdaScores) {
        $env:OSPREY_DUMP_LDA_SCORES = "1"
        $envVarsSet += "OSPREY_DUMP_LDA_SCORES=1"
    }
    if ($DiagLdaOnly) {
        $env:OSPREY_LDA_SCORES_ONLY = "1"
        $envVarsSet += "OSPREY_LDA_SCORES_ONLY=1"
    }
    if ($DiagLoessInput) {
        $env:OSPREY_DUMP_LOESS_INPUT = "1"
        $envVarsSet += "OSPREY_DUMP_LOESS_INPUT=1"
    }
    if ($DiagLoessOnly) {
        $env:OSPREY_LOESS_INPUT_ONLY = "1"
        $envVarsSet += "OSPREY_LOESS_INPUT_ONLY=1"
    }
    if ($Tool -eq "Rust") {
        $env:RUST_LOG = "info"
        $envVarsSet += "RUST_LOG=info"
    }

    # Build command arguments
    $args = @()
    foreach ($f in $mzmlFiles) {
        $args += "-i"
        $args += $f
    }
    $args += "-l"
    $args += $library
    $args += "-o"
    # Use temp file for output (NUL doesn't work for SQLite blib writes)
    $tempBlib = Join-Path $TestDataDir "_temp_output.blib"
    $args += $tempBlib
    $args += "--resolution"
    $args += "unit"
    if ($WritePin) {
        $args += "--write-pin"
    }

    # Parse and add extra args
    if ($ExtraArgs) {
        $args += $ExtraArgs.Split(' ', [StringSplitOptions]::RemoveEmptyEntries)
    }

    # Display what we're running
    $fileLabel = if ($Files -eq "Single") { "file 20" } else { "files 20-22" }
    Write-Host ""
    Write-Host "Running $Tool on Stellar $fileLabel" -ForegroundColor Cyan
    Write-Host "Binary: $binary" -ForegroundColor Gray
    if ($envVarsSet.Count -gt 0) {
        Write-Host "Env: $($envVarsSet -join ', ')" -ForegroundColor Gray
    }
    Write-Host ""

    $runStart = Get-Date

    if ($Summary) {
        # Capture output and filter to key lines
        $output = & $binary @args 2>&1
        $exitCode = $LASTEXITCODE
        $patterns = @(
            '\[BISECT\]', '\[TIMING\]', 'calibrated frag', 'Coelution search RT',
            'Applying MS2', 'First-pass RT tolerance', 'Refined RT tolerance',
            'Wrote feature', 'precursors at', 'Coelution analysis complete',
            'MS2 calibration \(pass', 'Confident peptides', 'Coelution scored',
            'Analysis complete'
        )
        foreach ($line in $output) {
            $text = $line.ToString()
            foreach ($p in $patterns) {
                if ($text -match [regex]::Escape($p)) {
                    Write-Host $text
                    break
                }
            }
        }
    } else {
        & $binary @args
        $exitCode = $LASTEXITCODE
    }

    $runDuration = (Get-Date) - $runStart

    Write-Host ""
    if ($exitCode -eq 0) {
        Write-Host "$Tool completed in $($runDuration.TotalSeconds.ToString('F1'))s" -ForegroundColor Green
    } else {
        Write-Host "$Tool failed with exit code $exitCode in $($runDuration.TotalSeconds.ToString('F1'))s" -ForegroundColor Red
    }

    exit $exitCode
}
finally {
    # Clean temp output
    if ($tempBlib -and (Test-Path $tempBlib)) {
        Remove-Item $tempBlib -Force -ErrorAction SilentlyContinue
    }
    # Clean up env vars
    Remove-Item Env:OSPREY_DIAG_SEARCH_ENTRY_IDS -ErrorAction SilentlyContinue
    Remove-Item Env:OSPREY_DUMP_CAL_MATCH -ErrorAction SilentlyContinue
    Remove-Item Env:OSPREY_CAL_MATCH_ONLY -ErrorAction SilentlyContinue
    Remove-Item Env:OSPREY_DUMP_LDA_SCORES -ErrorAction SilentlyContinue
    Remove-Item Env:OSPREY_LDA_SCORES_ONLY -ErrorAction SilentlyContinue
    Remove-Item Env:OSPREY_DUMP_LOESS_INPUT -ErrorAction SilentlyContinue
    Remove-Item Env:OSPREY_LOESS_INPUT_ONLY -ErrorAction SilentlyContinue
    Remove-Item Env:RUST_LOG -ErrorAction SilentlyContinue
    Set-Location $initialLocation
}
