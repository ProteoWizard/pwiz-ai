<#
.SYNOPSIS
    Run Osprey over the CHS-SeerData cohort (UW-Floyd Lab, Seer nanoparticle plasma).

.DESCRIPTION
    A thin wrapper over ../Common/OspreyDatasetRun.psm1, like Run-SeaAd.ps1 and
    Run-Tdp43.ps1. Read README.md in this folder before a multi-hour run.

    This dataset exists in the test set for a REASON the other two cannot serve: its
    samples differ in composition from each other, which is what stresses Stage 6
    reconciliation and cross-run consensus RT. SEA-AD and TDP-43 are cohorts of
    comparable material and structurally cannot fail that way.

.PARAMETER Plates
    Which plates to search, e.g. '0059','0060','0061' for the staged 3-plate cohort.
    The source directory is FLAT - 446 files, no per-plate subfolders - and the plate is
    a digit run in the stem (EXP25033_2025us0059aX10_A.raw), so this composes an
    -IncludePattern rather than relying on the layout. Omit to search whatever is present.

.EXAMPLE
    # Prove the wiring first - it prints every resolved path and the exact command line
    .\Run-Chs.ps1 -Plates 0059 -NumFiles 2 -WhatIf

.EXAMPLE
    # The staged 3-plate cohort
    .\Run-Chs.ps1 -Plates 0059,0060,0061 -DecoyMode libdecoy -Ratio 1.0 -Pass2Mode protein-compact
#>
#requires -Version 7
param(
    [string[]]$Plates,
    [ValidateSet('libdecoy', 'gendecoy')] [string]$DecoyMode = 'libdecoy',
    [string]$Ratio = '1.0',
    [ValidateSet('transfer', 'transfer-compete', 'protein-compact')]
    [string]$Pass2Mode = 'protein-compact',
    [switch]$PickProduct,
    [switch]$LogMemory,
    [string]$ExperimentAgg = '',
    [ValidateSet('run', 'experiment')] [string]$QualifyBy = 'run',
    [int]$NumFiles,
    [int]$SkipFirstFiles = 0,
    [int]$EveryNthFile = 1,
    [string]$ExcludePattern,
    [string]$IncludePattern,
    [int]$Threads = 30,
    [int]$ParallelFiles = 0,
    [ValidateSet('none', '1', '2', 'both')] [string]$FdrBenchPass,
    [ValidateSet('SpectraCache', 'PerFileScoring', 'FirstPassFDR', 'PerFileRescoring',
                 'CompactPerFileRescoring', 'SecondPassFDR')]
    [string]$Task,
    [string]$Tag = '',
    [string]$DataDir,
    [string]$LibraryDir,
    [string]$OutDir,
    [string]$RunsRoot,
    [string]$SourceRoot,
    [string]$Exe,
    [string[]]$LinkFrom = @(),
    [switch]$Fresh,
    [switch]$Resume,
    [switch]$NoModelDiagnostics,
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\Common\OspreyDatasetRun.psm1') -Force

# -Plates composes the include regex so a cohort is expressible as an ARM rather than as a
# hand-listed set of inputs. Both may be given; -IncludePattern then wins and is used as-is.
if ($Plates -and -not $IncludePattern) {
    $IncludePattern = 'us(' + ($Plates -join '|') + ')'
    $null = $PSBoundParameters.Remove('Plates')
    $PSBoundParameters['IncludePattern'] = $IncludePattern
    # The run directory name carries the file COUNT but not the arm that selected them, and
    # the plates are near-identical in size (0059/0061 are both 86 files). Two single-plate
    # runs would resolve to ONE directory, where the guard rejects the second - or -Resume
    # silently overlays it on the first. Name the plates unless the caller named something.
    if (-not $Tag) {
        $Tag = '-p' + ($Plates -join '_')
        $PSBoundParameters['Tag'] = $Tag
    }
} elseif ($Plates) {
    $null = $PSBoundParameters.Remove('Plates')
}

$dataset = @{
    Key                 = 'chs'
    Name                = 'CHS-SeerData (UW-Floyd)'
    Extension           = 'raw'
    InputLabel          = 'raw dir'
    EnvDataVar          = 'OSPREY_CHS_DIR'
    EnvLibVar           = 'OSPREY_CHS_LIB'
    DataFallbacks       = @('D:\test\osprey-runs\chs-seer\raw')
    # No default cohort size: the plate selection is the cohort here, and a silent default
    # would make -Plates look like it had no effect.
    DefaultNumFiles     = 0
    DefaultFdrBenchPass = 'none'
    MissingCacheNote    = ('These caches are built from .raw by a VENDOR-enabled build ' +
                           '(_bin\26.1.1.233-vendor-20260822 or later). A missing one is ' +
                           'rebuilt at ~2.5 min/file; see README.md.')
    Readme              = (Join-Path $PSScriptRoot 'README.md')
}

$exitCode = Invoke-OspreyDatasetRun -Dataset $dataset @PSBoundParameters
# Propagate Osprey's exit code, so a failed run is not read as success by a harness.
if ($null -ne $exitCode) { exit $exitCode }
