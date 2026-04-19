<#
.SYNOPSIS
    Run OspreySharp or Rust Osprey on test data (Stellar or Astral)

.DESCRIPTION
    Runs either the C# (OspreySharp) or Rust (Osprey) implementation on a
    test dataset. Handles cache cleaning, diagnostic env vars, and
    dataset-specific flags (resolution, library, file names).

.PARAMETER Dataset
    Which test dataset: Stellar or Astral (default: Stellar)

.PARAMETER Tool
    Which tool to run: CSharp or Rust (default: CSharp)

.PARAMETER RustTree
    When -Tool Rust, which tree to run: Fork (C:\proj\osprey, default) or
    Upstream (C:\proj\osprey-mm, = maccoss/osprey). Ignored for CSharp.

.PARAMETER Files
    Which mzML files: Single (first file only) or All (all 3). Default: Single

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

.PARAMETER DiagCalSample
    Set OSPREY_DUMP_CAL_SAMPLE=1 to dump calibration sample entries/scalars/grid

.PARAMETER DiagCalSampleOnly
    Set OSPREY_CAL_SAMPLE_ONLY=1 to exit after cal_sample dump

.PARAMETER DiagCalWindows
    Set OSPREY_DUMP_CAL_WINDOWS=1 to dump per-entry calibration window info

.PARAMETER DiagCalWindowsOnly
    Set OSPREY_CAL_WINDOWS_ONLY=1 to exit after cal_windows dump

.PARAMETER DiagCalPrefilter
    Set OSPREY_DUMP_CAL_PREFILTER=1 to dump pre-filter candidates (Rust-only)

.PARAMETER DiagCalPrefilterOnly
    Set OSPREY_CAL_PREFILTER_ONLY=1 to exit after cal_prefilter dump

.PARAMETER DiagXicEntryId
    Set OSPREY_DIAG_XIC_ENTRY_ID=<id> for per-entry calibration XIC diagnostic.
    Exits after writing.

.PARAMETER DiagXicPass
    Set OSPREY_DIAG_XIC_PASS=<1|2> to select calibration pass (use with DiagXicEntryId)

.PARAMETER DiagMpScan
    Set OSPREY_DIAG_MP_SCAN=<scan> for median polish diagnostic at a specific scan

.PARAMETER DiagXcorrScan
    Set OSPREY_DIAG_XCORR_SCAN=<scan> for xcorr diagnostic at a specific scan

.PARAMETER ExitAfterCalibration
    Set OSPREY_EXIT_AFTER_CALIBRATION=1 to exit after Stage 3 (produces the
    full calibration.json + spectra cache; skips main search and FDR).

.PARAMETER ExitAfterScoring
    Set OSPREY_EXIT_AFTER_SCORING=1 to exit after Stage 4 (produces the
    scores.parquet; skips FDR / reconciliation / blib output). Matches
    what Test-Features.ps1 and Bench-Scoring.ps1 use internally.

.PARAMETER ExtraArgs
    Additional arguments to pass to the tool (e.g. "--protein-fdr 0.01")

.PARAMETER Summary
    Show only key output lines (timing, calibration, results)

.PARAMETER TestBaseDir
    Override the test data base directory. Defaults to
    $env:OSPREY_TEST_BASE_DIR if set, otherwise "D:\test\osprey-runs".

.EXAMPLE
    .\Run-Osprey.ps1
    Run C# on Stellar single file

.EXAMPLE
    .\Run-Osprey.ps1 -Dataset Astral -Tool Rust -Files All -Clean
    Clean caches and run Rust on all 3 Astral files

.EXAMPLE
    .\Run-Osprey.ps1 -Dataset Astral -Clean -WritePin
    Clean and run C# on Astral with feature dump

.EXAMPLE
    .\Run-Osprey.ps1 -DiagEntryIds "0,1080,5765,28988"
    Run C# on Stellar with search XIC diagnostic for specific entries
#>

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("Stellar", "Astral")]
    [string]$Dataset = "Stellar",

    [Parameter(Mandatory=$false)]
    [ValidateSet("CSharp", "Rust")]
    [string]$Tool = "CSharp",

    [Parameter(Mandatory=$false)]
    [ValidateSet("Fork", "Upstream")]
    [string]$RustTree = "Fork",

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
    [switch]$DiagCalSample = $false,

    [Parameter(Mandatory=$false)]
    [switch]$DiagCalSampleOnly = $false,

    [Parameter(Mandatory=$false)]
    [switch]$DiagCalWindows = $false,

    [Parameter(Mandatory=$false)]
    [switch]$DiagCalWindowsOnly = $false,

    [Parameter(Mandatory=$false)]
    [switch]$DiagCalPrefilter = $false,

    [Parameter(Mandatory=$false)]
    [switch]$DiagCalPrefilterOnly = $false,

    [Parameter(Mandatory=$false)]
    [string]$DiagXicEntryId = $null,

    [Parameter(Mandatory=$false)]
    [string]$DiagXicPass = $null,

    [Parameter(Mandatory=$false)]
    [string]$DiagMpScan = $null,

    [Parameter(Mandatory=$false)]
    [string]$DiagXcorrScan = $null,

    [Parameter(Mandatory=$false)]
    [switch]$ExitAfterCalibration = $false,

    [Parameter(Mandatory=$false)]
    [switch]$ExitAfterScoring = $false,

    [Parameter(Mandatory=$false)]
    [string]$ExtraArgs = $null,

    [Parameter(Mandatory=$false)]
    [string]$TestBaseDir = $null,

    [Parameter(Mandatory=$false)]
    [ValidateSet("net472", "net8.0")]
    [string]$TargetFramework = "net472"
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Load dataset configuration
. "$PSScriptRoot\Dataset-Config.ps1"
$ds = Get-DatasetConfig $Dataset -TestBaseDir $TestBaseDir

$testDir = $ds.TestDir
if (-not (Test-Path $testDir)) {
    Write-Error "Test data directory not found: $testDir"
    exit 1
}

# Auto-detect project root
$scriptRoot = Split-Path -Parent $PSCommandPath
$aiRoot = Split-Path -Parent (Split-Path -Parent $scriptRoot)
$projRoot = Split-Path -Parent $aiRoot

# Tool binaries (Bench-Scoring.ps1 naming: upstream = osprey-mm, fork = osprey)
$csharpBinary = Join-Path $projRoot "pwiz\pwiz_tools\OspreySharp\OspreySharp\bin\x64\Release\$TargetFramework\OspreySharp.exe"
$rustForkBinary = Join-Path $projRoot "osprey\target\release\osprey.exe"
$rustUpstreamBinary = Join-Path $projRoot "osprey-mm\target\release\osprey.exe"
$rustBinary = if ($RustTree -eq "Upstream") { $rustUpstreamBinary } else { $rustForkBinary }

$binary = if ($Tool -eq "CSharp") { $csharpBinary } else { $rustBinary }
if (-not (Test-Path $binary)) {
    Write-Error "$Tool binary not found at: $binary`nRun Build-OspreySharp.ps1 or Build-OspreyRust.ps1 first."
    exit 1
}

# Library
$library = Join-Path $testDir $ds.Library
if (-not (Test-Path $library)) {
    Write-Error "Library not found: $library"
    exit 1
}

# mzML files
$mzmlFiles = if ($Files -eq "Single") {
    @(Join-Path $testDir $ds.SingleFile)
} else {
    $ds.AllFiles | ForEach-Object { Join-Path $testDir $_ }
}
foreach ($f in $mzmlFiles) {
    if (-not (Test-Path $f)) {
        Write-Error "mzML file not found: $f"
        exit 1
    }
}

$initialLocation = Get-Location

try {
    Set-Location $testDir

    # Clean caches if requested
    if ($Clean) {
        Write-Host "Cleaning cached files..." -ForegroundColor Cyan
        $patterns = @("*.scores.parquet", "*.calibration.json", "*.spectra.bin",
                      "*.fdr_scores.bin", "*.mzML.spectra.bin")
        foreach ($pattern in $patterns) {
            Get-ChildItem -Path $testDir -Filter $pattern -ErrorAction SilentlyContinue |
                Remove-Item -Force
        }
        # Also clean diagnostic dumps
        Get-ChildItem -Path $testDir -Filter "rust_search_xic_entry_*.txt" -ErrorAction SilentlyContinue |
            Remove-Item -Force
        Get-ChildItem -Path $testDir -Filter "cs_search_xic_entry_*.txt" -ErrorAction SilentlyContinue |
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
    if ($DiagCalSample) {
        $env:OSPREY_DUMP_CAL_SAMPLE = "1"
        $envVarsSet += "OSPREY_DUMP_CAL_SAMPLE=1"
    }
    if ($DiagCalSampleOnly) {
        $env:OSPREY_CAL_SAMPLE_ONLY = "1"
        $envVarsSet += "OSPREY_CAL_SAMPLE_ONLY=1"
    }
    if ($DiagCalWindows) {
        $env:OSPREY_DUMP_CAL_WINDOWS = "1"
        $envVarsSet += "OSPREY_DUMP_CAL_WINDOWS=1"
    }
    if ($DiagCalWindowsOnly) {
        $env:OSPREY_CAL_WINDOWS_ONLY = "1"
        $envVarsSet += "OSPREY_CAL_WINDOWS_ONLY=1"
    }
    if ($DiagCalPrefilter) {
        $env:OSPREY_DUMP_CAL_PREFILTER = "1"
        $envVarsSet += "OSPREY_DUMP_CAL_PREFILTER=1"
    }
    if ($DiagCalPrefilterOnly) {
        $env:OSPREY_CAL_PREFILTER_ONLY = "1"
        $envVarsSet += "OSPREY_CAL_PREFILTER_ONLY=1"
    }
    if ($DiagXicEntryId) {
        $env:OSPREY_DIAG_XIC_ENTRY_ID = $DiagXicEntryId
        $envVarsSet += "OSPREY_DIAG_XIC_ENTRY_ID=$DiagXicEntryId"
    }
    if ($DiagXicPass) {
        $env:OSPREY_DIAG_XIC_PASS = $DiagXicPass
        $envVarsSet += "OSPREY_DIAG_XIC_PASS=$DiagXicPass"
    }
    if ($DiagMpScan) {
        $env:OSPREY_DIAG_MP_SCAN = $DiagMpScan
        $envVarsSet += "OSPREY_DIAG_MP_SCAN=$DiagMpScan"
    }
    if ($DiagXcorrScan) {
        $env:OSPREY_DIAG_XCORR_SCAN = $DiagXcorrScan
        $envVarsSet += "OSPREY_DIAG_XCORR_SCAN=$DiagXcorrScan"
    }
    if ($ExitAfterCalibration) {
        $env:OSPREY_EXIT_AFTER_CALIBRATION = "1"
        $envVarsSet += "OSPREY_EXIT_AFTER_CALIBRATION=1"
    }
    if ($ExitAfterScoring) {
        $env:OSPREY_EXIT_AFTER_SCORING = "1"
        $envVarsSet += "OSPREY_EXIT_AFTER_SCORING=1"
    }
    if ($Tool -eq "Rust") {
        $env:RUST_LOG = "info"
        $envVarsSet += "RUST_LOG=info"
    }

    # Build command arguments
    $toolArgs = @()
    foreach ($f in $mzmlFiles) {
        $toolArgs += "-i"
        $toolArgs += $f
    }
    $toolArgs += "-l"
    $toolArgs += $library
    $toolArgs += "-o"
    $tempBlib = Join-Path $testDir "_temp_output.blib"
    $toolArgs += $tempBlib
    $toolArgs += "--resolution"
    $toolArgs += $ds.Resolution
    $toolArgs += "--protein-fdr"
    $toolArgs += "0.01"
    if ($WritePin) {
        $toolArgs += "--write-pin"
    }

    # Parse and add extra args
    if ($ExtraArgs) {
        $toolArgs += $ExtraArgs.Split(' ', [StringSplitOptions]::RemoveEmptyEntries)
    }

    # Display what we're running
    $fileLabel = $ds.FileLabel[$Files]
    Write-Host ""
    Write-Host "Running $Tool on $($ds.Name) $fileLabel" -ForegroundColor Cyan
    Write-Host "Binary: $binary" -ForegroundColor Gray
    Write-Host "Resolution: $($ds.Resolution)" -ForegroundColor Gray
    if ($envVarsSet.Count -gt 0) {
        Write-Host "Env: $($envVarsSet -join ', ')" -ForegroundColor Gray
    }
    Write-Host ""

    $runStart = Get-Date

    if ($Summary) {
        # Capture output and filter to key lines
        $output = & $binary @toolArgs 2>&1
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
        & $binary @toolArgs
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
    Remove-Item Env:OSPREY_EXIT_AFTER_CALIBRATION -ErrorAction SilentlyContinue
    Remove-Item Env:OSPREY_EXIT_AFTER_SCORING -ErrorAction SilentlyContinue
    Remove-Item Env:OSPREY_DUMP_CAL_MATCH -ErrorAction SilentlyContinue
    Remove-Item Env:OSPREY_CAL_MATCH_ONLY -ErrorAction SilentlyContinue
    Remove-Item Env:OSPREY_DUMP_LDA_SCORES -ErrorAction SilentlyContinue
    Remove-Item Env:OSPREY_LDA_SCORES_ONLY -ErrorAction SilentlyContinue
    Remove-Item Env:OSPREY_DUMP_LOESS_INPUT -ErrorAction SilentlyContinue
    Remove-Item Env:OSPREY_LOESS_INPUT_ONLY -ErrorAction SilentlyContinue
    Remove-Item Env:OSPREY_DUMP_CAL_SAMPLE -ErrorAction SilentlyContinue
    Remove-Item Env:OSPREY_CAL_SAMPLE_ONLY -ErrorAction SilentlyContinue
    Remove-Item Env:OSPREY_DUMP_CAL_WINDOWS -ErrorAction SilentlyContinue
    Remove-Item Env:OSPREY_CAL_WINDOWS_ONLY -ErrorAction SilentlyContinue
    Remove-Item Env:OSPREY_DUMP_CAL_PREFILTER -ErrorAction SilentlyContinue
    Remove-Item Env:OSPREY_CAL_PREFILTER_ONLY -ErrorAction SilentlyContinue
    Remove-Item Env:OSPREY_DIAG_XIC_ENTRY_ID -ErrorAction SilentlyContinue
    Remove-Item Env:OSPREY_DIAG_XIC_PASS -ErrorAction SilentlyContinue
    Remove-Item Env:OSPREY_DIAG_MP_SCAN -ErrorAction SilentlyContinue
    Remove-Item Env:OSPREY_DIAG_XCORR_SCAN -ErrorAction SilentlyContinue
    Remove-Item Env:RUST_LOG -ErrorAction SilentlyContinue
    Set-Location $initialLocation
}
