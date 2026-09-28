<#
.SYNOPSIS
    Run Osprey over the 3 regression Astral HeLa files against the SEA-AD entrapment library.

.DESCRIPTION
    regression.ps1's Astral leg searches its own library, which has no entrapment, so Astral
    changes that move the discovery set have no FDP oracle at 3 files. This searches the same
    3 mzML against the SEA-AD Carafe libraries (the ones the large Astral cohorts use), giving
    an Astral counterpart to StellarLibDecoy / StellarGenDecoyEntrap:

        -DecoyMode libdecoy : target+decoy+entrapment            (library decoys)
        -DecoyMode gendecoy : target+entrapment-r1.0-gendecoy    (Osprey-generated decoys)

    Kept out of regression.ps1 for its download size (the library is ~13 GB). Everything else
    is the shared runner (../Common/OspreyDatasetRun.psm1), same parameters as Run-SeaAd.ps1.

    Resolution, first hit wins:
      data    : -DataDir, $env:OSPREY_ASTRAL3_DIR, <Downloads>\Perftests\osprey-testfiles-mzML-v2\astral
                (where regression.ps1 extracts it; SKYLINE_DOWNLOAD_PATH honored)
      library : -LibraryDir, $env:OSPREY_SEAAD_LIB
      runs    : -RunsRoot, else <test base>\astral-entrap-3file\runs
      caches  : -CacheDir, else <test base>\astral-entrap-3file\cache, so the .spectra.bin files
                are not written into the regression download
    <test base> is $env:OSPREY_TEST_BASE_DIR or D:\test\osprey-runs.

.EXAMPLE
    .\Run-AstralEntrap.ps1 -DecoyMode libdecoy -WhatIf
    .\Run-AstralEntrap.ps1 -DecoyMode gendecoy -SvmCTolerance 0
#>
#requires -Version 7
param(
    [ValidateSet('libdecoy', 'gendecoy')] [string]$DecoyMode = 'libdecoy',
    [string]$Ratio = '1.0',
    [ValidateSet('transfer', 'transfer-compete', 'protein-compact')]
    [string]$Pass2Mode = 'protein-compact',
    [switch]$PickProduct,
    [int]$Threads = 30,
    [ValidateSet('none', '1', '2', 'both')] [string]$FdrBenchPass,
    [ValidatePattern('^$|^(0|0?\.\d+)$')] [string]$SvmCTolerance = '',
    [string]$Tag = '',
    [string]$DataDir,
    [string]$LibraryDir,
    [string]$CacheDir,
    [string]$OutDir,
    [string]$RunsRoot,
    [string]$SourceRoot,
    [string]$Exe,
    [string[]]$LinkFrom = @(),
    [switch]$Fresh,
    [switch]$Resume,
    [switch]$NoModelDiagnostics,
    [switch]$NoPerfStats,
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\Common\OspreyDatasetRun.psm1') -Force

# The Downloads folder by regression.ps1's rule (Regression/RegressionData.ps1,
# Get-WindowsDownloadsFolder): SKYLINE_DOWNLOAD_PATH, then the known-folder registry value,
# which honors a relocated Downloads (e.g. on D:), then UserProfile\Downloads.
$downloads = $env:SKYLINE_DOWNLOAD_PATH
if (-not $downloads) {
    try {
        $downloads = [Environment]::ExpandEnvironmentVariables((Get-ItemProperty -ErrorAction Stop `
            -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders' `
            -Name '{374DE290-123F-4565-9164-39C4925E467B}').'{374DE290-123F-4565-9164-39C4925E467B}')
    } catch { }
}
if (-not $downloads) { $downloads = Join-Path $env:USERPROFILE 'Downloads' }
$testBase = if ($env:OSPREY_TEST_BASE_DIR) { $env:OSPREY_TEST_BASE_DIR } else { 'D:\test\osprey-runs' }
$areaRoot = Join-Path $testBase 'astral-entrap-3file'

$dataset = @{
    Key              = 'astral3'
    Name             = 'Astral regression HeLa x SEA-AD entrapment library'
    Extension        = 'mzML'
    InputLabel       = 'mzML dir'
    EnvDataVar       = 'OSPREY_ASTRAL3_DIR'
    EnvLibVar        = 'OSPREY_SEAAD_LIB'
    DataFallbacks    = @(Join-Path $downloads 'Perftests\osprey-testfiles-mzML-v2\astral')
    DefaultNumFiles  = 3
    MissingCacheNote = 'Osprey builds the 3 caches on the first run (a few minutes).'
    Readme           = (Join-Path $PSScriptRoot 'Run-AstralEntrap.ps1')
}

if (-not $PSBoundParameters.ContainsKey('RunsRoot')) { $PSBoundParameters['RunsRoot'] = Join-Path $areaRoot 'runs' }
if (-not $PSBoundParameters.ContainsKey('CacheDir')) {
    $cache = Join-Path $areaRoot 'cache'
    New-Item -ItemType Directory -Force -Path $cache | Out-Null
    $PSBoundParameters['CacheDir'] = $cache
}

$exitCode = Invoke-OspreyDatasetRun -Dataset $dataset @PSBoundParameters
# Propagate Osprey's exit code so a caller does not read a failed run as success.
if ($null -ne $exitCode) { exit $exitCode }
