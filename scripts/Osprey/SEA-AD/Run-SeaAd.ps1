<#
.SYNOPSIS
    Run Osprey over the SEA-AD Pilot-MTG 82-file Astral DIA set.

.DESCRIPTION
    The single runner for this dataset. It replaces the one-off harnesses that produced
    every run under D:\test\osprey-runs\sea-ad\runs on the original machine
    (run-82file-decoyarm.ps1, run-82file-gendecoy.ps1, run-pass2ab-82.ps1): they differed
    only in which decoy arm, entrapment ratio and pass-2 mode they selected, so they are
    parameters here rather than separate scripts. Running the arms through ONE script with
    identical logging is what makes them comparable.

    Everything not specific to SEA-AD now lives in ../Common/OspreyDatasetRun.psm1, shared
    with the other large-dataset runners (TDP-43). This file contributes the descriptor:
    where the data is, what the files are called, and the defaults.

    Nothing is hardcoded. Data, library and Osprey.exe are resolved (parameter, then
    environment variable, then a known fallback) and the run hard-fails with the README
    pointer if any of them cannot be found, rather than searching a wrong or empty
    directory for hours.

    See README.md in this folder for where the data lives, how to build the library
    variants, and the measured facts (wall time, disk, the --model-diagnostics OOM trap).

.PARAMETER DecoyMode
    libdecoy : the library supplies Carafe decoys; adds --decoys-in-library and the
               pairing manifest. No decoy-construction knobs. This is the reference arm.
    gendecoy : the library has NO decoy rows (stripped); Osprey generates its own.

.PARAMETER Ratio
    Entrapment ratio of the library to search, as it appears in the library folder name.
    '1.0' is the unsuffixed 1:1 set. ID yield rises as the ratio shrinks, so two arms are
    only comparable on ID counts when they share a ratio. See README.

.PARAMETER Pass2Mode
    transfer / transfer-compete / protein-compact, defaulting to protein-compact. See the
    module's help; `transfer` is the one that forces the resident O(files) first-pass pool.
    `percolator` was removed from Osprey and is no longer accepted here.

.PARAMETER PickProduct
    Use the LEGACY product-form pick instead of the learned linear model. The default is the
    learned model, matching Osprey's own default - this replaces the former -PickLda, which
    defaulted OFF and so pinned the legacy pick on every run that did not opt in. This MOVES
    THE DISCOVERY SET and is recorded in the banner and run.log, because Osprey logs nothing
    that says which pick model a run used. The module still exports OSPREY_PICK_LDA in both
    directions, so the arm is pinned rather than inherited.

.PARAMETER ExperimentAgg
    First-pass EXPERIMENT-score aggregation. Empty (the default) means max - the best score
    over runs. 'mean-best-<N>' scores a precursor as the mean of its best N per-run scores
    (OSPREY_EXPERIMENT_AGG). This MOVES THE DISCOVERY SET, so it is recorded in the banner,
    the run.log START line, and the output-directory name.

    It has to be a PARAMETER, not an inherited environment variable: the module clears
    OSPREY_EXPERIMENT_AGG along with every other experimental lever and re-exports it only
    from this argument, so a caller that merely sets the env var before invoking this script
    gets a run silently aggregated as `max` while its directory name claims otherwise.

    Validated against '^mean-best-\d+$' HERE rather than left to Osprey: an unrecognized value
    only WARNS and falls back to max, which for a measurement flag corrupts the comparison
    instead of failing it.

.PARAMETER QualifyBy
    Which q-value qualifies a peptide as DETECTED for protein-compact's >=2-distinct-peptides
    gate: 'run' (default, the shipped behavior - the UNION of each file's 1% detections over
    every run) or 'experiment' (experiment-wide peptide q). Only meaningful with
    -Pass2Mode protein-compact.

    This MOVES THE DISCOVERY SET, so like -PickProduct and -ExperimentAgg it is a parameter rather
    than an inherited environment variable: the module clears OSPREY_PROTEIN_COMPACT_QUALIFY
    and re-exports it from this argument, and records it in the banner, the run.log START line
    and the output-directory name. At 82 files the run-level union is 12.95% false where the
    experiment-wide q is 0.79%, which is the whole point of the arm.

.PARAMETER LinkFrom
    Optional. Hard-link the per-file caches from a COMPLETED run over the same file set so
    this run resumes without re-parsing or re-scoring. What is linked is scoped by -Task:
    every stage STRICTLY BEFORE the task under test, never that task's own outputs, so the
    part under test is always regenerated.

    Without -Task (or with -Task FirstPassFDR) that is the Stage 1-4 set and the run resumes
    from Stage 5, which is the historical behavior. With -Task SecondPassFDR it also links
    the Stage 5 sidecars (.1st-pass.fdr_scores.bin, .1st-pass.model.json, .reconciliation.json)
    and the Stage 6 .scores-reconciled.parquet, because a --task SecondPassFDR node consumes
    those. Linking only the Stage 1-4 set there leaves no reconciled parquet, so the frozen
    pass-2 modes fail-fast with "could not run the frozen recompute" - a message that reads
    like a code bug rather than an under-linked input.

    This is what makes a Stage-7-only re-measurement cost ~25 min instead of the ~8.5 h a
    full 82-file run takes.

    SEVERAL sources may be given, probed in order with the first hit winning, so a cohort too
    big to score in one sitting can be scored in legs and joined once. Separate them with ';'
    in a single quoted argument - `pwsh -File` hands arguments over literally and cannot bind
    an array, so -LinkFrom a,b arrives as one string and -LinkFrom a b binds b to the NEXT
    parameter. All sources must carry the same Osprey version stamp or the run refuses to
    start, and the banner tallies what each source contributed so a leg that gave nothing is
    visible before the hours are spent rather than after.

.EXAMPLE
    # Re-measure Stage 7 alone against a completed run (~25 min, not 8.5 h).
    .\Run-SeaAd.ps1 -Task SecondPassFDR -LinkFrom D:\test\...\<completed run> -Fresh

.PARAMETER NoModelDiagnostics
    Turn OFF the --model-diagnostics HTML report, which is on by default here. Leave it on
    unless you have a reason: it is the only place pass-1 entrapment FDP is reported today.

.PARAMETER Fresh
    Timestamp the output directory name. Use when repeating an arm you have already run:
    Osprey adopts per-file caches it finds in the output directory, so reusing one turns a
    from-scratch run into a silent resume.

.PARAMETER WhatIf
    Print the resolved paths and the full command line, then stop. Do this first on a new
    machine - it is the cheap way to confirm everything resolved to what you expect
    before committing to a multi-hour run.

.EXAMPLE
    # Prove the wiring on a new machine before trusting it at 82 files.
    .\Run-SeaAd.ps1 -DecoyMode libdecoy -Ratio 1.0 -NumFiles 2 -WhatIf

.EXAMPLE
    # Mike's recommended configuration (see peak-model-training.md and the pass-2 TODO).
    .\Run-SeaAd.ps1 -Pass2Mode protein-compact
#>
#requires -Version 7
param(
    [ValidateSet('libdecoy', 'gendecoy')] [string]$DecoyMode = 'libdecoy',
    [string]$Ratio = '1.0',
    [ValidateSet('transfer', 'transfer-compete', 'protein-compact')]
    [string]$Pass2Mode = 'protein-compact',
    [switch]$PickProduct,
    [int]$NumFiles,
    [int]$SkipFirstFiles = 0,
    [int]$EveryNthFile = 1,
    [string]$ExcludePattern,
    [int]$Threads = 30,
    [int]$ParallelFiles = 0,
    [ValidateSet('SpectraCache','PerFileScoring','FirstPassFDR','PerFileRescoring',
                 'CompactPerFileRescoring','SecondPassFDR')]
    [string]$Task,
    [ValidateSet('none', '1', '2', 'both')] [string]$FdrBenchPass,
    [ValidatePattern('^$|^mean-best-\d+$')] [string]$ExperimentAgg = '',
    [ValidateSet('run', 'experiment')] [string]$QualifyBy = 'run',
    [string]$Tag = '',
    [string]$DataDir,
    [string]$LibraryDir,
    [string]$Library,
    [string]$CacheDir,
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

# Last-resort fallback, named once so the README and the code cannot drift apart.
$LAB_SHARE_MZML = 'M:\home\brendanx\data\MacCoss\SEA-AD\Astral-DIA\mzml'

$dataset = @{
    Key              = 'seaad'
    Name             = 'SEA-AD Pilot-MTG'
    Extension        = 'mzML'
    InputLabel       = 'mzML dir'
    EnvDataVar       = 'OSPREY_SEAAD_DIR'
    EnvLibVar        = 'OSPREY_SEAAD_LIB'
    DataFallbacks    = @($LAB_SHARE_MZML)
    DefaultNumFiles  = 82
    MissingCacheNote = 'Convert-SeaAdRaw.ps1 builds them; ~4.5 min/file uncached from HDD.'
    Readme           = (Join-Path $PSScriptRoot 'README.md')
}

$exitCode = Invoke-OspreyDatasetRun -Dataset $dataset @PSBoundParameters
# Propagate Osprey's exit code. Without this a failed run exits 0 and every
# caller - including an overnight harness - reads the failure as success.
if ($null -ne $exitCode) { exit $exitCode }
