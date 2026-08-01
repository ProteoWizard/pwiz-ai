<#
.SYNOPSIS
    Run Osprey over the TDP-43 Plasma EV-Quant 164-file Astral DIA set.

.DESCRIPTION
    The runner for this dataset. Everything not specific to TDP-43 lives in
    ../Common/OspreyDatasetRun.psm1, shared with Run-SeaAd.ps1 - so the two datasets cannot
    drift apart on the parts that are easy to get subtly wrong (the output-directory guard,
    the environment hygiene, --output-dir vs --work-dir, the library-variant convention).

    This file contributes the descriptor: where the data is, that the inputs are vendor
    .raw rather than mzML, and the defaults.

    Two differences from SEA-AD worth knowing:

      * The inputs are vendor .raw, searched straight from their .spectra.bin caches. Any
        build - including net8.0 with no ProteoWizard at all - reads them, because
        EnsureSpectraCache consults the cache BEFORE it dispatches on file extension. A
        missing or stale cache therefore fails LOUDLY naming the vendor reader; that error
        means "the cache is not where Osprey looked", NOT "use the vendor build".
      * One file is excluded by default. See -ExcludePattern.

    See README.md in this folder.

.PARAMETER ExcludePattern
    Defaults to '-bad\.raw$', which drops
    2025-0724-TDP43-PlasmaEV-PLT2-C03-5112-027-bad.raw. That is an aborted acquisition the
    depositor marked '-bad'; ProteoWizard reports "Corrupt RAW file" on it. It is
    byte-for-byte what Panorama holds, so there is nothing to re-fetch. Excluding it
    explicitly is what makes a full run exit 0. Pass -ExcludePattern '' to include it.

.PARAMETER PickLda
    Use the learned linear peak-pick model instead of the default product-form pick. This
    MOVES THE DISCOVERY SET and is recorded in the banner and run.log, because Osprey logs
    nothing that says which pick model a run used.

.PARAMETER FdrBenchPass
    Defaults to 'none' here. --fdrbench-pass 1 forces the RESIDENT O(files) first-pass pool
    and does not scale to this cohort; 'both' and '2' are memory-safe but emit only the
    pass-2 TSV, and pass-2 FDP is inflated by recalibration. Pass-1 FDP - the number worth
    quoting - comes from --model-diagnostics, which is on by default.

.EXAMPLE
    # Prove the wiring before committing to hours.
    .\Run-Tdp43.ps1 -NumFiles 10 -WhatIf

.EXAMPLE
    # Mike's recommended configuration, 10 files, to eyeball the diagnostics.
    .\Run-Tdp43.ps1 -PickLda -Pass2Mode protein-compact -NumFiles 10

.EXAMPLE
    # The full set, detached so a harness reap cannot kill it.
    Start-Process pwsh -ArgumentList '-NoProfile','-File',
      'C:/proj/ai/scripts/Osprey/TDP43/Run-Tdp43.ps1','-PickLda',
      '-Pass2Mode','protein-compact' -WindowStyle Hidden
#>
#requires -Version 7
param(
    [ValidateSet('libdecoy', 'gendecoy')] [string]$DecoyMode = 'libdecoy',
    [string]$Ratio = '1.0',
    [ValidateSet('percolator', 'transfer', 'transfer-compete', 'protein-compact')]
    [string]$Pass2Mode = 'percolator',
    [switch]$PickLda,
    [int]$NumFiles,
    [int]$SkipFirstFiles = 0,
    [int]$EveryNthFile = 1,
    [string]$ExcludePattern,
    [int]$Threads = 30,
    [int]$ParallelFiles = 0,
    [ValidateSet('SpectraCache','PerFileScoring','FirstPassFDR','PerFileRescoring','SecondPassFDR')]
    [string]$Task,
    [ValidateSet('none', '1', '2', 'both')] [string]$FdrBenchPass,
    [string]$Tag = '',
    [string]$DataDir,
    [string]$LibraryDir,
    [string]$Library,
    [string]$CacheDir,
    [string]$OutDir,
    [string]$RunsRoot,
    [string]$SourceRoot,
    [string]$Exe,
    [string]$LinkFrom = '',
    [switch]$Fresh,
    [switch]$Resume,
    [switch]$NoModelDiagnostics,
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\Common\OspreyDatasetRun.psm1') -Force

$dataset = @{
    Key                   = 'tdp43'
    Name                  = 'TDP-43 Plasma EV-Quant'
    Extension             = 'raw'
    InputLabel            = 'raw dir'
    EnvDataVar            = 'OSPREY_TDP43_DIR'
    EnvLibVar             = 'OSPREY_TDP43_LIB'
    DefaultNumFiles       = 163
    DefaultExcludePattern = '-bad\.raw$'
    # The FDRBench oracle is deliberately off for the baseline at this scale; see the
    # -FdrBenchPass help above and the README.
    DefaultFdrBenchPass   = 'none'
    MissingCacheNote      = ('A missing cache here needs a VENDOR-enabled build to rebuild ' +
                             '(~3.8 min/file). Check the cache location before assuming that.')
    Readme                = (Join-Path $PSScriptRoot 'README.md')
}

$exitCode = Invoke-OspreyDatasetRun -Dataset $dataset @PSBoundParameters
# Propagate Osprey's exit code. Without this a failed run exits 0 and every
# caller - including an overnight harness - reads the failure as success.
if ($null -ne $exitCode) { exit $exitCode }
