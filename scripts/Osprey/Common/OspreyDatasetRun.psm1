<#
.SYNOPSIS
    Shared engine behind the per-dataset Osprey large-run wrappers.

.DESCRIPTION
    Run-SeaAd.ps1 and Run-Tdp43.ps1 are thin wrappers over Invoke-OspreyDatasetRun.
    Everything that is not dataset-specific lives here exactly once: path resolution,
    the library-variant convention, cohort selection, the output-directory guard, the
    environment hygiene, the banner, -WhatIf, and the run.log.

    A dataset contributes only a DESCRIPTOR (see the -Dataset parameter): what its files
    are called, which environment variables name its locations, what its runs are called,
    and its defaults. Adding a dataset should not mean copying 400 lines of runner.

    Why one engine rather than one script per dataset: the two datasets differ in six
    fields and agree on everything that is easy to get subtly wrong. Two near-identical
    runners drift, and a drift here is invisible in the output - it just makes two runs
    quietly non-comparable.
#>
#requires -Version 7

Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Resolve a location from an explicit value, an environment variable, then fallbacks.

.DESCRIPTION
    A location the caller NAMED must exist. Falling through to the next candidate when an
    explicit path is wrong is how a run spends hours against the wrong data and still
    reports success, so a typo fails here instead.
#>
function Resolve-DatasetLocation {
    param(
        [string]$Explicit,
        [string]$EnvName,
        [string[]]$Fallbacks,
        [string]$What,
        [string]$DatasetName,
        [string]$Readme
    )
    $envValue = [Environment]::GetEnvironmentVariable($EnvName)
    foreach ($named in @(@{ V = $Explicit; S = 'parameter' }, @{ V = $envValue; S = "`$env:$EnvName" })) {
        if ($named.V) {
            if (-not (Test-Path $named.V)) {
                throw "The $DatasetName $What given by $($named.S) does not exist: '$($named.V)'."
            }
            return (Resolve-Path $named.V).Path
        }
    }
    foreach ($c in $Fallbacks) {
        if ($c -and (Test-Path $c)) { return (Resolve-Path $c).Path }
    }
    throw ("Could not locate the $DatasetName $What. Pass it explicitly, or set " +
           "`$env:$EnvName. See $Readme for the source URLs and the fallback paths.")
}

<#
.SYNOPSIS
    Resolve the library variant directory for a decoy arm and entrapment ratio.

.DESCRIPTION
    New-SeaAdLibrary.ps1 owns the naming convention and this reproduces it, which is what
    lets -Ratio and -DecoyMode be plain parameters instead of another path on every command
    line. The variants are shared across datasets - TDP-43 searches the SEA-AD-derived
    entrapment libraries - so this is deliberately NOT part of the dataset descriptor.

    -LibraryDir may name either the root holding the variants or one variant directly, so a
    machine that lays its libraries out differently is not locked out by the convention.

    -Build selects which delivered r=1.0 set the variant derives from, with the same naming
    as New-SeaAdLibrary.ps1 -Build: '' is the original 2026-07-27 'target+decoy+entrapment',
    '20260817' is 'target+decoy+entrapment-20260817' and its derived variants.
#>
function Resolve-LibraryVariant {
    param(
        [string]$LibRoot,
        [string]$DecoyMode,
        [string]$Ratio,
        [string]$Build = '',
        [string]$Readme
    )
    $b = if ($Build) { "-$Build" } else { '' }
    $variant = if ($DecoyMode -eq 'gendecoy') {
        "target+entrapment-r$Ratio$b-gendecoy"
    } elseif ($Ratio -eq '1.0') {
        "target+decoy+entrapment$b"
    } else {
        "target+decoy+entrapment$b-r$Ratio"
    }

    $libDir = Join-Path $LibRoot $variant
    if (-not (Test-Path $libDir)) {
        if (Test-Path (Join-Path $LibRoot 'carafe_spectral_library.tsv')) {
            $libDir = $LibRoot
        } else {
            throw ("No library variant '$variant' under '$LibRoot', and '$LibRoot' is not " +
                   "itself a library directory. Build it with New-SeaAdLibrary.ps1 -Ratio " +
                   "$Ratio -DecoyMode $DecoyMode$(if ($Build) { " -Build $Build" }), or pass -LibraryDir/-Library explicitly. " +
                   "See $Readme.")
        }
    }
    return $libDir
}

<#
.SYNOPSIS
    The Osprey version a completed run directory was written by, or $null when it cannot tell.

.DESCRIPTION
    Every artifact carries its own validity stamp,
    'osprey-validity/1;task=<Task>;version=<version>;key=<key>'. A JSON artifact holds it as
    its FIRST property, "osprey_validity", so reading the head of one .calibration.json is
    enough - no need to parse a document that can be tens of megabytes.

    Directories written before embedded stamps have none; for them this falls back to the
    "version" in the first legacy <artifact>.<Task>.osprey.task sidecar, so -LinkFrom still
    pins and still compares versions across sources from older builds.
#>
function Get-SourceOspreyVersion {
    param([Parameter(Mandatory)] [string]$Directory)

    $stampPattern = '"osprey_validity"\s*:\s*"osprey-validity/1;task=[^;]*;version=([^;"]+);'
    $jsons = @(Get-ChildItem (Join-Path $Directory '*.calibration.json') -File -ErrorAction SilentlyContinue |
               Sort-Object Name | Select-Object -First 3)
    foreach ($json in $jsons) {
        $stream = [System.IO.File]::OpenRead($json.FullName)
        try {
            $buffer = New-Object byte[] ([int][Math]::Min($stream.Length, 8192))
            $read = $stream.Read($buffer, 0, $buffer.Length)
            $head = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $read)
        } finally {
            $stream.Dispose()
        }
        $m = [regex]::Match($head, $stampPattern)
        if ($m.Success) { return $m.Groups[1].Value }
    }

    # Legacy: a directory written before embedded stamps.
    $t = Get-ChildItem (Join-Path $Directory '*.osprey.task') -File -ErrorAction SilentlyContinue |
         Select-Object -First 1
    if (-not $t) { return $null }
    $m = Get-Content $t.FullName -Raw | Select-String -Pattern '\d+\.\d+\.\d+\.\d+' |
         Select-Object -First 1
    if ($m) { return $m.Matches[0].Value }
    return $null
}

<#
.SYNOPSIS
    Run Osprey over one large dataset: decoy arm x ratio x pass-2 mode x pick model.

.PARAMETER Dataset
    Hashtable describing the dataset. Required keys:
      Key                  short slug leading every run directory name, e.g. 'seaad'
      Name                 human name for the banner, e.g. 'SEA-AD Pilot-MTG'
      Extension            input file extension WITHOUT the dot, e.g. 'mzML' or 'raw'
      EnvDataVar           env var naming the data directory
      EnvLibVar            env var naming the library root
      Readme               path to the dataset's README, quoted in every error
    Optional keys:
      InputLabel           banner label for the data dir (default '<Extension> dir')
      DataFallbacks        string[] of last-resort data directories (e.g. a lab share)
      DefaultNumFiles      cohort size when -NumFiles is not passed; 0 (or omitted) means
                           every candidate file, for cohorts defined by a filter not a count
      DefaultExcludePattern  regex applied when -ExcludePattern is not passed
      DefaultFdrBenchPass  'none' | '1' | '2' | 'both' when -FdrBenchPass is not passed
      MissingCacheNote     extra line printed when caches are missing

.PARAMETER PickProduct
    Use the LEGACY product-form pick (coelution * rt_penalty * ln_intensity,
    OSPREY_PICK_LDA=0) instead of the learned resolution-keyed linear model.

    **The default is the learned model, matching Osprey's own default.** This replaces the
    former -PickLda switch, which defaulted OFF and therefore pinned the legacy pick on every
    run that did not opt in - the opposite of what Osprey does, and a silent one: a caller who
    simply wanted "a normal run" got the legacy arm, and its parquets keyed differently from
    an unadorned `Osprey.exe` run, so neither could adopt the other's Stage 1-4 output.

    This MOVES THE DISCOVERY SET - it is a different peak choice, not a different report -
    so it is recorded in the banner and the run.log START line. Nothing Osprey logs says
    which pick model a run used, so without that record a finished run is unattributable.

    OSPREY_PICK_LDA is still exported EXPLICITLY IN BOTH DIRECTIONS - '0' when this switch is
    on, '1' when it is off. That property is unchanged and must stay: clearing the variable is
    not enough, because an inherited value is invisible in the output, and an A/B that only
    exported its ON value would run the same configuration twice under two labels.

.PARAMETER Pass2Mode
    transfer        : frozen first-pass model, TRIC-style q-value fill-in, no retrain.
                      Bounded like the default since pwiz #4438 (first pass) and #4665
                      (Stage 7 join).
    transfer-compete: frozen model, then a fresh target-decoy competition over the full
                      reconciled population (non-depleted null).
    protein-compact : default. Frozen model, competition CONSTRAINED to peptides of proteins
                      detected in the first pass (>= 2 peptides), target+decoy pairs kept.
    Passed through OSPREY_PASS2_QVALUE, which this function clears first so a stale shell
    variable can never silently change an arm, and then ALWAYS sets - see below.

    `percolator` is gone. Osprey removed the second-pass Percolator retrain and now raises a
    startup ERROR on an unrecognized OSPREY_PASS2_QVALUE, so it is out of the ValidateSet
    here too: a caller that still asks for it fails at parameter binding, in a second,
    instead of after Stage 1-5. Historical run directories carrying a `-percolator` name
    component are from before that removal and are not reproducible with a current binary.

.PARAMETER FdrBenchPass
    'none' writes no FDRBench TSV at all. '1' forces the RESIDENT first-pass pool, which
    grows O(files) and does not scale - see the README before using it on a large cohort.
#>
function Invoke-OspreyDatasetRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [hashtable]$Dataset,
        [ValidateSet('libdecoy', 'gendecoy')] [string]$DecoyMode = 'libdecoy',
        [string]$Ratio = '1.0',
        [ValidateSet('transfer', 'transfer-compete', 'protein-compact')]
        [string]$Pass2Mode = 'protein-compact',
        [switch]$PickProduct,
        # Emit Osprey's post-GC [MEM ...] probes (OSPREY_LOG_MEMORY=1). Those probes are what
        # answer "will it fit" - --memstamp includes uncollected garbage and shows shape, not
        # magnitude - but each one forces a GC.Collect() pair, so a large run pays real wall
        # time for them (999 probes on the 163-file TDP-43 baseline). OFF by default so timings
        # are clean; turn it on when the question is memory rather than speed. Exported in BOTH
        # directions and recorded, because two arms that differ in it are NOT comparable on
        # either axis and nothing in Osprey's output says which one a finished run had.
        [switch]$LogMemory,
        # 0 means every candidate file that survived the include/exclude filters, not none.
        [int]$NumFiles,
        # Take the $NumFiles files AFTER skipping this many, so cohorts of the same size can
        # be drawn from disjoint slices of the dataset (replicate cohorts for a size-vs-effect
        # study). Pass -Tag to keep the run directories apart: the name carries only the COUNT.
        [int]$SkipFirstFiles = 0,
        # Keep every Nth file instead of a contiguous block. Name order tracks acquisition order
        # in these datasets and instrument response drifts across it, so a contiguous first-F
        # cohort is also the EARLIEST (best) F files -- size and quality are confounded.
        [int]$EveryNthFile = 1,
        [string]$ExcludePattern,
        # Keep ONLY files matching this regex, applied before -ExcludePattern. For a
        # dataset whose cohort structure lives in the FILENAME rather than in subfolders -
        # CHS-SeerData is a flat directory of 446 files whose plate is a digit run in the
        # stem - selecting a plate any other way means hand-listing inputs, which is how a
        # run stops being reproducible from its own directory name.
        [string]$IncludePattern,
        [int]$Threads = 30,
        # OUTER parallelism: how many input files are scored at once. 0 leaves it off
        # (Osprey's default, one file at a time). NOTE that --threads is a PER-FILE budget
        # DIVIDED across concurrent files, so this does not add cores - it overlaps the
        # per-file work that does not saturate them. On this dataset calibration (31% of
        # per-file scoring time) and the parquet write (14%) are the candidates; the main
        # search (55%) should be roughly throughput-neutral.
        [int]$ParallelFiles = 0,
        # Per-stage overrides of -ParallelFiles (--parallel-files-caching / -scoring / -rescoring),
        # each for its stage only; 0 = not passed, so the stage falls back to -ParallelFiles. The
        # stages scale differently: a Thermo decode is single-threaded (TDP-43: 8 caching lanes
        # ~3.2x over sequential), while one scoring file already keeps the CPU at 80-96%.
        [int]$ParallelFilesCaching = 0,
        [int]$ParallelFilesScoring = 0,
        [int]$ParallelFilesRescoring = 0,
        # HPC split: run exactly ONE pipeline task instead of the whole run. Combined with
        # -LinkFrom this makes a single-phase re-measurement cost only that phase - e.g. Stage 5
        # at 163 files is ~75 min instead of the 18 h a full run takes.
        [ValidateSet('SpectraCache', 'PerFileScoring', 'FirstPassFDR', 'PerFileRescoring',
                     'SecondPassFDR', 'ModelDiagnostics', 'TrainingExport')]
        [string]$Task,
        # Link the stages up to AND INCLUDING -Task, instead of strictly before it.
        #
        # The default (strictly before) is right when the task under test is meant to REGENERATE
        # its outputs - that is what a single-phase re-measurement is. It is wrong for a
        # diagnostics-only re-entry, where the whole point is that the task adopts a completed
        # pass rather than recomputing it: with its own outputs (each carrying its embedded
        # validity stamp) absent, the task cannot see that it has already run and does the
        # work again. That
        # failure is SILENT and expensive - the re-run produces the RIGHT report, so only the
        # log line separates a 4h46m recompute from a minutes-long fold.
        [switch]$LinkThroughTask,
        # Link every stage strictly BEFORE this one, independently of -Task. The switch a
        # STRAIGHT-THROUGH resume needs, and the only way to express it: with no -Task the
        # link loop stops before FirstPassFDR, so a `-LinkFrom` run re-does Stage 5 and the
        # whole Stage 6 rescore - hours at cohort scale - to reach a Stage 7 that was the
        # only thing being measured. -Task SecondPassFDR links exactly the right set but
        # also puts `--task SecondPassFDR` on the command line, which is the HPC MERGE
        # route, a different arm of the code from the ordinary `-i ... --output-dir` run an
        # operator types.
        #
        # `-LinkUpTo SecondPassFDR` with no -Task is therefore the ordinary run resumed at a
        # completed bed: every pre-Stage-7 artifact hard-linked in, nothing on the command
        # line but the inputs. That is the shape the 446-run 91.1 GB Stage-7 measurement was
        # taken on (issue #4486), so it is the shape its re-measurement has to use.
        [ValidateSet('SpectraCache', 'PerFileScoring', 'FirstPassFDR', 'PerFileRescoring',
                     'SecondPassFDR', 'ModelDiagnostics', 'TrainingExport')]
        [string]$LinkUpTo,
        [ValidateSet('none', '1', '2', 'both')] [string]$FdrBenchPass,
        # First-pass EXPERIMENT-score aggregation: '' (the max default) or 'mean-best-<N>'.
        # A first-class parameter rather than a caller-exported OSPREY_EXPERIMENT_AGG because
        # an N-curve is a series of arms that differ in NOTHING ELSE - same files, same
        # parquets, same pass-2 mode - so an unrecorded value makes finished arms literally
        # indistinguishable from each other. This lands in the banner, the run.log START line,
        # and the default output-directory name.
        [string]$ExperimentAgg = '',
        # Which q-value qualifies a peptide as DETECTED for the protein-compact >=2 gate:
        # 'run' (the shipped default, the union over runs) or 'experiment'. A first-class
        # parameter for exactly the reason -ExperimentAgg is one: the two arms differ in
        # NOTHING else - same files, same parquets, same pass-2 mode, same pick - so a value
        # that reached Osprey only through a caller-exported environment variable would leave
        # two finished runs indistinguishable. Lands in the banner, the run.log START line and
        # the default output-directory name. Only meaningful with -Pass2Mode protein-compact.
        [ValidateSet('run', 'experiment')] [string]$QualifyBy = 'run',
        # First-pass SVM C-selection tolerance (OSPREY_SVM_C_TOLERANCE, pwiz #4703). Empty (the
        # default) leaves the variable unset so Osprey uses its own default; '0' is the strict
        # maximum of the inner-CV counts. A parameter, not an inherited variable, for the same
        # reason as -QualifyBy: the arms differ in nothing else, and the variable is stripped
        # below. Lands in the banner, the run.log START/DONE lines and the directory name.
        [ValidatePattern('^$|^(0|0?\.\d+)$')] [string]$SvmCTolerance = '',
        # EXPERIMENTAL first-pass C grid (OSPREY_SVM_C_VALUES), e.g. '0.1' fixes C. Empty leaves
        # Osprey's grid. Same reasoning as -SvmCTolerance: a parameter, stripped otherwise, and
        # recorded in the banner, run.log and the directory name (-cvals<value>).
        [ValidatePattern('^$|^[0-9.eE+-]+(,[0-9.eE+-]+)*$')] [string]$SvmCValues = '',
        # FirstPassFDR file-lane count (OSPREY_FDR_FILE_LANES). 0 (the default) leaves it to
        # Osprey's FdrLaneResolver. Changes wall clock and memory only, never output. A
        # parameter for the same reason as -SvmCTolerance: stripped below, recorded in the
        # banner, run.log START/DONE lines and the directory name (-fplanes<N>).
        [ValidateRange(0, 64)] [int]$FdrFileLanes = 0,
        [string]$Tag = '',
        [string]$DataDir,
        [string]$LibraryDir,
        # Which delivered r=1.0 set the library variant derives from (see Resolve-LibraryVariant).
        # '' keeps the original naming, so runners that do not pass it are unchanged.
        [string]$LibraryBuild = '',
        [string]$Library,
        [string]$CacheDir,
        [string]$OutDir,
        [string]$RunsRoot,
        [string]$SourceRoot,
        [string]$Exe,
        # Run from the build tree instead of a snapshot. Only reason to pass this is a run short
        # enough that locking the build tree does not matter; see the snapshot block below.
        [switch]$NoSnapshotExe,
        # More than one source is allowed, probed in order with the first hit winning. A cohort
        # can be scored in per-plate legs and then joined once: the per-file stages are the
        # expensive half and are cohort-INDEPENDENT (the peak-pick model is hardcoded and
        # resolution-keyed, not trained on the cohort), so linking their output from several
        # legs gives the join exactly what one big run would have produced.
        [string[]]$LinkFrom = @(),
        [switch]$Fresh,
        [switch]$Resume,
        [switch]$NoModelDiagnostics,
        # --training-export: PerFileRescoring writes each run's <stem>.training.parquet (the
        # per-run training data CarafeSharp fine-tunes on). Off by default. To regenerate the
        # exports of a finished run without re-analysis, use -Task TrainingExport -Resume.
        [switch]$TrainingExport,
        [switch]$NoPerfStats,
        # Run Osprey under dotTrace sampling and save the snapshot here (a .dtp path). The run is
        # otherwise identical - same environment, same command line - so a cohort-scale stage
        # (e.g. -Task FirstPassFDR -LinkFrom <run>) can be profiled without a hand-built copy of
        # this runner's environment. Analyse with Reporter.exe as Profile-Osprey.ps1 does.
        [string]$ProfileTo,
        [switch]$WhatIf
    )

    $ErrorActionPreference = 'Stop'
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

    foreach ($k in 'Key', 'Name', 'Extension', 'EnvDataVar', 'EnvLibVar', 'Readme') {
        if (-not $Dataset.ContainsKey($k)) { throw "Dataset descriptor is missing required key '$k'." }
    }
    $readme = $Dataset.Readme
    $dsName = $Dataset.Name
    $ext = $Dataset.Extension
    $inputLabel = if ($Dataset.ContainsKey('InputLabel')) { $Dataset.InputLabel } else { "$ext dir" }
    $dataFallbacks = if ($Dataset.ContainsKey('DataFallbacks')) { [string[]]$Dataset.DataFallbacks } else { @() }

    # Descriptor defaults apply only where the caller said nothing, so an explicit -NumFiles 0
    # or -ExcludePattern '' still means what it says.
    if (-not $PSBoundParameters.ContainsKey('NumFiles')) {
        $NumFiles = if ($Dataset.ContainsKey('DefaultNumFiles')) { [int]$Dataset.DefaultNumFiles } else { 0 }
    }
    if (-not $PSBoundParameters.ContainsKey('ExcludePattern')) {
        $ExcludePattern = if ($Dataset.ContainsKey('DefaultExcludePattern')) { [string]$Dataset.DefaultExcludePattern } else { '' }
    }
    if (-not $PSBoundParameters.ContainsKey('FdrBenchPass')) {
        $FdrBenchPass = if ($Dataset.ContainsKey('DefaultFdrBenchPass')) { [string]$Dataset.DefaultFdrBenchPass } else { 'both' }
    }

    $dataDir = Resolve-DatasetLocation -Explicit $DataDir -EnvName $Dataset.EnvDataVar `
        -Fallbacks $dataFallbacks -What $inputLabel -DatasetName $dsName -Readme $readme

    # -SourceRoot names a checkout; the exe is at its usual place inside it. Prefer this to
    # -Exe when you want a specific TREE, e.g. a pinned worktree rather than a shared one that
    # other sessions are actively building in. See the banner warning below.
    # net10.0, the one framework Osprey builds (same value as OSPREY_TARGET_FRAMEWORK in
    # Dataset-Config.ps1). A leftover Release\net8.0 folder is a stale build, never a fallback.
    $EXE_UNDER_ROOT = 'pwiz_tools\Osprey\Osprey\bin\x64\Release\net10.0\Osprey.exe'
    if ($SourceRoot -and -not $Exe) {
        if (-not (Test-Path $SourceRoot)) { throw "-SourceRoot does not exist: '$SourceRoot'." }
        $Exe = Join-Path $SourceRoot $EXE_UNDER_ROOT
        if (-not (Test-Path $Exe)) {
            throw "No Release/net10.0 Osprey.exe under -SourceRoot '$SourceRoot'. Build it there first."
        }
    }
    $repoExe = Join-Path $PSScriptRoot "..\..\..\..\pwiz\$EXE_UNDER_ROOT"
    $ospreyExe = Resolve-DatasetLocation -Explicit $Exe -EnvName 'OSPREYDEV_EXE' `
        -Fallbacks @($repoExe) -What 'Osprey.exe (build Release/net10.0 first)' `
        -DatasetName $dsName -Readme $readme

    # Windows locks a running .exe, so a multi-hour run out of the BUILD TREE blocks every build
    # and unit-test cycle until it finishes. The rule was "snapshot the exe first, pass -Exe" and
    # it kept being forgotten, which costs a whole session's ability to build - so do it here
    # instead of relying on the caller to remember. The copy is ~200 MB and about a second.
    #
    # The snapshot is keyed by the exe's own version + build time, so repeat runs of the same
    # binary reuse one directory rather than littering. Reading a running exe is permitted on
    # Windows, so this is safe even when another run already holds the build tree.
    #
    # -NoSnapshotExe opts out; an explicit -Exe / OSPREYDEV_EXE is already a deliberate choice of
    # binary and is left alone.
    if (-not $NoSnapshotExe -and -not $Exe -and -not $env:OSPREYDEV_EXE) {
        $exeItem = Get-Item $ospreyExe
        $ver = $exeItem.VersionInfo.FileVersion
        if (-not $ver) { $ver = 'unknown' }
        # NOT $tag: PowerShell variable names are case-insensitive, so $tag IS the caller's -Tag
        # parameter. Naming this $tag silently overwrote it and appended the snapshot stamp to the
        # run-directory name, which is both wrong and how this was caught.
        $snapTag = ('{0}-{1}' -f $ver, $exeItem.LastWriteTime.ToString('yyyyMMdd-HHmm'))
        $snapDir = Join-Path 'D:\test\osprey-runs\_bin' $snapTag
        $snapExe = Join-Path $snapDir (Split-Path -Leaf $ospreyExe)
        try {
            if (-not (Test-Path $snapExe)) {
                New-Item -ItemType Directory -Path $snapDir -Force | Out-Null
                Copy-Item (Join-Path (Split-Path $ospreyExe -Parent) '*') $snapDir -Recurse -Force
            }
            $ospreyExe = $snapExe
            Write-Host ("  exe snap : {0} (build tree left free to rebuild)" -f $snapDir) -ForegroundColor Cyan
        }
        catch {
            # A snapshot failure must not block the science run - fall back to the build tree and
            # say so, because the caller then knows builds will fail for the duration.
            Write-Host ("  WARNING: could not snapshot the exe ({0}); running from the BUILD TREE, " +
                        "which will block builds until this run finishes." -f $_.Exception.Message) -ForegroundColor Yellow
        }
    }

    $libRoot = Resolve-DatasetLocation -Explicit $LibraryDir -EnvName $Dataset.EnvLibVar `
        -Fallbacks @() -What 'library directory' -DatasetName $dsName -Readme $readme
    $libDir = Resolve-LibraryVariant -LibRoot $libRoot -DecoyMode $DecoyMode -Ratio $Ratio `
        -Build $LibraryBuild -Readme $readme

    # Exactly-one-.tsv unless named: a library folder also holds the pairing manifest and a
    # FASTA, so guessing the first .tsv is how you silently search the wrong one.
    if ($Library) {
        $libraryPath = Join-Path $libDir $Library
        if (-not (Test-Path $libraryPath)) { throw "Library not found: $libraryPath" }
    } else {
        $named = Join-Path $libDir 'carafe_spectral_library.tsv'
        if (Test-Path $named) {
            $libraryPath = $named
        } else {
            $tsv = @(Get-ChildItem -Path $libDir -Filter '*.tsv' -File |
                     Where-Object { $_.Name -notlike '*pairing*' })
            if ($tsv.Count -ne 1) {
                throw ("Expected one spectral library .tsv in '$libDir' but found $($tsv.Count). " +
                       "Pass -Library <name> to choose.")
            }
            $libraryPath = $tsv[0].FullName
        }
    }
    # Size + write time of the library file, cheap on a 12 GB TSV where a hash is not. It goes in
    # the banner and run.log so two machines' runs can be checked for the same library from the
    # logs alone - the folder name did not catch two different builds sharing a date tag.
    $libItem = Get-Item $libraryPath
    $libFingerprint = '{0} bytes, written {1:yyyy-MM-ddTHH:mm:ssZ}' -f $libItem.Length, $libItem.LastWriteTimeUtc
    $manifest = Join-Path $libDir 'osprey_library_db_pairing.tsv'
    if ($DecoyMode -eq 'libdecoy' -and -not (Test-Path $manifest)) {
        throw ("-DecoyMode libdecoy needs the pairing manifest '$manifest'. It ships with the " +
               "target+decoy+entrapment libraries; see $readme.")
    }

    # A source that is GONE but cached is still an input. Osprey searches from .spectra.bin
    # alone (pwiz #4616), which is what lets a staged cohort delete its sources and roughly
    # halve the disk it needs - but then nothing is left in the data directory to enumerate,
    # so the cohort the feature exists to serve would resolve to zero files right here. The
    # synthesized path is the one the source WOULD have had, not the cache's own: Osprey never
    # stats it, and SpectraCache resolves the cache from its input's DIRECTORY.
    $cacheProbeDir = if ($CacheDir) { $CacheDir } else { $dataDir }
    $allCaches = @(Get-ChildItem -Path $cacheProbeDir -Filter '*.spectra.bin' -File -ErrorAction SilentlyContinue)
    $cached = $allCaches.Count
    $sourcesOnDisk = @(Get-ChildItem -Path $dataDir -Filter "*.$ext" -File)
    $sourceStems = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]@($sourcesOnDisk | ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_.Name) }),
        [StringComparer]::OrdinalIgnoreCase)
    # "{stem}.spectra.bin" - strip the whole compound suffix, not one extension.
    $cacheOnlyInputs = @($allCaches |
        ForEach-Object { $_.Name.Substring(0, $_.Name.Length - '.spectra.bin'.Length) } |
        Where-Object { -not $sourceStems.Contains($_) } |
        ForEach-Object {
            [pscustomobject]@{ Name = "$_.$ext"; FullName = (Join-Path $dataDir "$_.$ext") }
        })
    $allInputs = @(@($sourcesOnDisk) + $cacheOnlyInputs | Sort-Object Name)
    if ($IncludePattern) {
        $before = $allInputs.Count
        $allInputs = @($allInputs | Where-Object { $_.Name -match $IncludePattern })
        Write-Host ("  included : $($allInputs.Count) of $before file(s) matching '$IncludePattern'")
        if ($allInputs.Count -eq 0) {
            throw "-IncludePattern '$IncludePattern' matched none of the $before .$ext file(s) in '$dataDir'."
        }
    }
    if ($ExcludePattern) {
        $before = $allInputs.Count
        $allInputs = @($allInputs | Where-Object { $_.Name -notmatch $ExcludePattern })
        Write-Host ("  excluded : $($before - $allInputs.Count) file(s) matching '$ExcludePattern'")
    }
    if ($EveryNthFile -gt 1) {
        $keep = @(0..($allInputs.Count - 1) | Where-Object { $_ % $EveryNthFile -eq 0 })
        $allInputs = @($keep | ForEach-Object { $allInputs[$_] })
        Write-Host ("  every    : $EveryNthFile-th file -> $($allInputs.Count) candidate(s)")
    }
    # NumFiles 0 means the WHOLE candidate set, not none. A dataset whose cohort is defined by
    # a filter rather than a count (CHS: -Plates composes an -IncludePattern) has no number to
    # state, and a descriptor default above the cohort size would only be a guess that breaks
    # when the cohort grows. Select-Object -First 0 returns nothing, so unlimited has to skip
    # -First entirely rather than pass it a sentinel.
    $selected = $allInputs | Select-Object -Skip $SkipFirstFiles
    if ($NumFiles -gt 0) { $selected = $selected | Select-Object -First $NumFiles }
    $inputs = @($selected | ForEach-Object { $_.FullName })
    if ($inputs.Count -eq 0) {
        throw "No .$ext files, and no .spectra.bin without one, found in '$dataDir'."
    }
    # Counted from the selection, not the directory: which files were kept is what decides
    # whether THIS run reads a source at all.
    $cacheOnlySelected = @($inputs | Where-Object { -not (Test-Path -LiteralPath $_) }).Count
    if ($inputs.Count -lt $NumFiles) {
        throw ("Only $($inputs.Count) .$ext available in '$dataDir' after skipping " +
               "$SkipFirstFiles, need $NumFiles. See $readme.")
    }

    # .spectra.bin beside the data is the difference between a run that streams and one that
    # also pays the parse ($cached / $cacheProbeDir are counted with the inputs above, since
    # the cache list is now part of resolving what the inputs even are). Worth saying out loud
    # rather than discovering at hour six.

    if (-not $OutDir) {
        # The dataset root is the data directory's PARENT and every run goes under its runs\,
        # so someone on another machine finds a run without being told where to look. (The old
        # SEA-AD runner walked two levels up, which contradicted its own README and resolved
        # OUTSIDE the dataset root on a <root>\<dataset>\<data> layout.) -RunsRoot overrides.
        $runsRootResolved = if ($RunsRoot) { $RunsRoot } else { Join-Path (Split-Path $dataDir -Parent) 'runs' }
        # Tag the NON-default arm. The learned model is the default now, so a bare run
        # directory means the learned model and '-pickproduct' marks the legacy arm.
        $pick = if ($PickProduct) { '-pickproduct' } else { '' }
        # The aggregation is part of the NAME, not just the log: an N-curve runs many arms that
        # are identical in every other naming component, so without this they would all resolve
        # to one directory and the guard below would reject arm 2 (or -Resume would silently
        # overlay it onto arm 1's artifacts).
        $agg = if ($ExperimentAgg) { "-$ExperimentAgg" } else { '' }
        # Empty on the shipped 'run' default, so this does not rename a single existing arm.
        $qual = if ($QualifyBy -eq 'experiment') { '-qualifyexp' } else { '' }
        # Empty when unset, so existing arms keep their names.
        $csel = if ($SvmCTolerance) { "-csel$SvmCTolerance" } else { '' }
        if ($SvmCValues) { $csel += "-cvals$($SvmCValues -replace ',', '_')" }
        if ($FdrFileLanes -gt 0) { $csel += "-fplanes$FdrFileLanes" }
        $name = "$($Dataset.Key)-$($inputs.Count)files-$DecoyMode-r$Ratio-$Pass2Mode$pick$agg$qual$csel$Tag"
        if ($Fresh) { $name += '-' + (Get-Date -Format 'yyyyMMdd_HHmmss') }
        $OutDir = [System.IO.Path]::GetFullPath((Join-Path $runsRootResolved $name))
    }

    # Osprey ADOPTS per-file caches it finds in the output directory, so re-running an arm into
    # the same directory silently resumes instead of running from scratch - invisible in the
    # output, and it quietly invalidates a from-scratch memory or timing measurement.
    if ((Test-Path $OutDir) -and @(Get-ChildItem -Path $OutDir -File -ErrorAction SilentlyContinue).Count -gt 0 `
        -and -not $Resume -and -not $LinkFrom) {
        throw ("Output directory already has files: '$OutDir'. Osprey would adopt its caches " +
               "and skip stages. Pass -Fresh for a timestamped from-scratch directory, " +
               "-Resume to deliberately continue this one, or -OutDir to name another.")
    }

    # --output-dir, NOT --work-dir: --work-dir ALSO sets CacheDir (OspreyCommandArgs.cs), and an
    # explicit CacheDir wins outright in ArtifactPaths.ResolveCacheDir - so --work-dir makes
    # existing .spectra.bin beside the data invisible and a non-vendor build dies on file 1
    # naming the vendor reader. Artifacts go to the run dir; the cache stays beside the data
    # unless -CacheDir says otherwise (what a genuinely read-only data directory needs).
    $blib = Join-Path $OutDir 'out.blib'
    # The HPC per-task modes AFTER PerFileScoring read per-file ARTIFACTS rather than
    # spectra, so they still need those artifacts staged - but they are named the same way
    # every other task names its runs. --input-scores used to take their place on the
    # command line ('--input-scores $OutDir'); it retired, and -i plus --output-dir says the
    # same thing: these runs, artifacts over there. Osprey accepts an input that is absent
    # when its scores parquet is on disk, which is the state a staged phase directory is in.
    $POST_SCORING_TASKS = @('FirstPassFDR', 'PerFileRescoring', 'SecondPassFDR',
                            'ModelDiagnostics', 'TrainingExport')
    $useScores = $Task -and ($POST_SCORING_TASKS -contains $Task)
    if ($useScores -and -not $LinkFrom -and -not $Resume) {
        throw ("-Task $Task consumes per-file artifacts, not raw input. Pass -LinkFrom <a completed " +
               "run over the same files> so every stage BEFORE $Task is hard-linked into the output " +
               "directory first, or -Resume into a directory that already has them.")
    }
    # Windows caps a command line at 32,767 characters. The 446-file CHS cohort under a long data
    # path (E:\Users\...\chs-seer\raw) needs ~35,500 with -i and fails at CreateProcess with an
    # error that never says "too many inputs". Past a safe margin, hand Osprey the list in a file
    # instead: --input-list paths are indistinguishable from -i paths once parsed (OspreyCommandArgs).
    # The file is written into the output directory once it exists (below), and named in the banner.
    $inputListPath = $null
    $inputChars = ($inputs | Measure-Object -Property Length -Sum).Sum + $inputs.Count
    if ($inputChars -gt 24000) {
        $inputListPath = Join-Path $OutDir 'inputs.txt'
        $cliArgs = @('--input-list', $inputListPath)
    }
    else {
        $cliArgs = @('-i') + $inputs
    }
    $cliArgs += @(
        '-l', $libraryPath,
        '-o', $blib,
        '--resolution', 'hram',
        '--fdr-level', 'precursor',
        '--threads', "$Threads",
        '--timestamp', '--memstamp',
        '--output-dir', $OutDir
    )
    if ($FdrBenchPass -ne 'none') {
        $cliArgs += @('--fdrbench', (Join-Path $OutDir 'fdrbench.tsv'), '--fdrbench-pass', $FdrBenchPass)
    }
    if ($Task) { $cliArgs += @('--task', $Task) }
    if ($ParallelFiles -gt 0) { $cliArgs += @('--parallel-files', "$ParallelFiles") }
    if ($ParallelFilesCaching -gt 0) { $cliArgs += @('--parallel-files-caching', "$ParallelFilesCaching") }
    if ($ParallelFilesScoring -gt 0) { $cliArgs += @('--parallel-files-scoring', "$ParallelFilesScoring") }
    if ($ParallelFilesRescoring -gt 0) { $cliArgs += @('--parallel-files-rescoring', "$ParallelFilesRescoring") }
    # --cache-dir only when -CacheDir is given. A post-scoring --task leg names its runs by
    # their data files (the -i paths in the data directory), and Osprey resolves each
    # .spectra.bin beside its source on its own (ai/docs/osprey-run-layout.md: the cache "is
    # not a separate tree"), so the runner used to pass --cache-dir <data dir> only as a
    # restatement of that default. It was not harmless: --cache-dir also moves the library's
    # .libcache lookup, so a post-scoring leg missed the .libcache the straight run wrote
    # beside the library and re-parsed the 13 GB SEA-AD TSV - without the retained-fragment
    # skip - writing a second 2.2 GB .libcache into the data directory.
    if ($CacheDir) { $cliArgs += @('--cache-dir', $CacheDir) }
    if ($DecoyMode -eq 'libdecoy') { $cliArgs += @('--decoys-in-library', '--decoy-pairing-manifest', $manifest) }
    $mdiag = -not $NoModelDiagnostics
    if ($mdiag) { $cliArgs += '--model-diagnostics' }
    if ($TrainingExport) { $cliArgs += '--training-export' }
    # The [PATH] / [COUNT] / [STAGE-WALL] lines are the only route and count evidence a run
    # leaves (the READMEs' route checks, Get-MemoryReport.ps1, Measure-CoAssignmentScaling.py
    # read them), and they print only under --perf-stats. -NoPerfStats is for a run whose
    # purpose is to read the default log a user sees.
    if (-not $NoPerfStats) { $cliArgs += '--perf-stats' }

    # Which TREE the binary came from matters as much as which flags ran. A multi-hour run
    # against whatever a colleague happens to have built in a shared worktree measures their
    # mid-refactor branch, not master - and the run holds those DLLs, blocking their rebuilds.
    # Both directions of that collision are silent, so name the branch out loud.
    $exeBranch = $null
    $exeRepo = Split-Path $ospreyExe -Parent
    try {
        $exeBranch = (& git -C $exeRepo rev-parse --abbrev-ref HEAD 2>$null)
        if ($LASTEXITCODE -ne 0) { $exeBranch = $null }
    } catch { $exeBranch = $null }

    Write-Host ""
    Write-Host "=== $dsName run ===" -ForegroundColor Cyan
    Write-Host ("  exe      : {0}" -f $ospreyExe)
    Write-Host ("  built    : {0}{1}" -f (Get-Item $ospreyExe).LastWriteTime.ToString('yyyy-MM-dd HH:mm'),
                $(if ($exeBranch) { "   branch: $exeBranch" } else { '' }))
    if ($exeBranch -and $exeBranch -ne 'master') {
        Write-Host ("  WARNING: that build is branch '{0}', not master. A run this long against " -f $exeBranch) -ForegroundColor Yellow
        Write-Host "           someone else's in-progress build measures their branch, and holds" -ForegroundColor Yellow
        Write-Host "           its DLLs so they cannot rebuild. Pass -SourceRoot <pinned checkout>" -ForegroundColor Yellow
        Write-Host "           to use a tree nobody is actively building in." -ForegroundColor Yellow
    }
    Write-Host ("  {0,-9}: {1}" -f $inputLabel, $dataDir)
    # A multi-hour run reading every spectrum over SMB is I/O-bound on the network and silently
    # much slower than local disk, with nothing in the output saying so.
    if ($dataDir -like '\\*' -or (@('A', 'B', 'C', 'D') -notcontains $dataDir[0] -and
        (Get-PSDrive $dataDir[0] -ErrorAction SilentlyContinue).DisplayRoot)) {
        Write-Host "  WARNING: that is a NETWORK path. Every spectrum read crosses the wire; a" -ForegroundColor Yellow
        Write-Host "           full run will be markedly slower than from local disk. Copy the" -ForegroundColor Yellow
        Write-Host "           data + .spectra.bin locally and set the env var to it; see the README." -ForegroundColor Yellow
    }
    Write-Host ("  files    : {0}; {1} .spectra.bin cache(s) in {2}" -f $inputs.Count, $cached, $cacheProbeDir)
    if ($cacheOnlySelected -gt 0) {
        # Provenance, not decoration: a run whose sources are gone cannot rebuild a cache that
        # later turns out to be wrong, and the fingerprint check that would have caught a
        # mismatched one is skipped precisely because there is nothing left to compare to.
        Write-Host ("  CACHE-ONLY: {0} of {1} input(s) have no .$ext on disk and will be read from" -f
                    $cacheOnlySelected, $inputs.Count) -ForegroundColor Cyan
        Write-Host "             their .spectra.bin. Osprey logs the same count; the two must agree." -ForegroundColor Cyan
        Write-Host "             Validate caches with ..\Test-SpectraCaches.ps1 BEFORE deleting sources -" -ForegroundColor Cyan
        Write-Host "             once they are gone a stale cache is trusted silently." -ForegroundColor Cyan
    }
    if ($cached -lt $inputs.Count) {
        Write-Host "  NOTE: not every file has a spectra cache; expect a per-file parse cost." -ForegroundColor Yellow
        if ($Dataset.ContainsKey('MissingCacheNote')) {
            Write-Host ("        {0}" -f $Dataset.MissingCacheNote) -ForegroundColor Yellow
        }
    }
    Write-Host ("  library  : {0}" -f $libraryPath)
    Write-Host ("  lib file : {0}" -f $libFingerprint)
    Write-Host ("  arm      : {0}  r={1}" -f $DecoyMode, $Ratio)
    Write-Host ("  files at once: {0}   threads {1}{2}" -f
                $(if ($ParallelFiles -gt 0) { $ParallelFiles } else { '1 (sequential)' }), $Threads,
                $(if ($ParallelFiles -gt 1) {
                    " -> ~$([int]($Threads / $ParallelFiles)) per file (--threads is DIVIDED across them)" }
                  else { '' }))
    if ($ParallelFilesCaching -gt 0 -or $ParallelFilesScoring -gt 0 -or $ParallelFilesRescoring -gt 0) {
        $stageText = { param($n) if ($n -gt 0) { "$n" } else { 'shared' } }
        Write-Host ("  per stage: caching {0}   scoring {1}   rescoring {2}  (shared = the files-at-once count above)" -f
                    (& $stageText $ParallelFilesCaching), (& $stageText $ParallelFilesScoring),
                    (& $stageText $ParallelFilesRescoring))
    }
    Write-Host ("  pass 2   :{0}   fdrbench pass {1}   model-diagnostics {2}   training-export {3}" -f
                $Pass2Mode, $FdrBenchPass, $(if ($mdiag) { 'on' } else { 'OFF' }),
                $(if ($TrainingExport -or $Task -eq 'TrainingExport') { 'on' } else { 'off' }))
    # Nothing Osprey logs records the pick model, so this banner line and the run.log START
    # line are the only provenance a finished run carries.
    Write-Host ("  peak pick: {0}" -f $(if ($PickProduct) {
                'LEGACY product form (OSPREY_PICK_LDA=0) - moves the discovery set' }
                else { 'default learned linear model (OSPREY_PICK_LDA=1, Osprey default)' }))
    # Same reasoning as the pick model: which runs trained the peak model is not in Osprey's
    # log either, so the banner states it. The runner clears OSPREY_TRAIN_PICK_RUN, so this
    # is a guarantee about the run, not a report of a variable.
    Write-Host ("  memprobe : {0}" -f $(if ($LogMemory) {
                'post-GC [MEM] probes ON (OSPREY_LOG_MEMORY=1) - forces GCs, do NOT compare wall time to an arm without it' }
                else { 'off (default) - --memstamp shape only, no [MEM]-probe GCs' }))
    Write-Host "  train set: one run per precursor (pickrun3 default; OSPREY_TRAIN_PICK_RUN cleared)"
    Write-Host ("  exp agg  : {0}" -f $(if ($ExperimentAgg) {
                "$ExperimentAgg (OSPREY_EXPERIMENT_AGG) - moves the experiment-wide discovery set" }
                else { 'max (default, best of runs)' }))
    Write-Host ("  qualify  : {0}" -f $(if ($QualifyBy -eq 'experiment') {
                'EXPERIMENT-wide q (OSPREY_PROTEIN_COMPACT_QUALIFY) - shrinks the protein-compact stratum' }
                else { 'per-run q (default, the union over runs)' }))
    Write-Host ("  svm C sel: {0}" -f $(if ($SvmCTolerance) {
                "OSPREY_SVM_C_TOLERANCE=$SvmCTolerance - moves the first-pass model" }
                else { "Osprey's default (OSPREY_SVM_C_TOLERANCE cleared)" }))
    Write-Host ("  svm C grid: {0}" -f $(if ($SvmCValues) {
                "OSPREY_SVM_C_VALUES=$SvmCValues (EXPERIMENTAL) - moves the first-pass model" }
                else { "Osprey's default (OSPREY_SVM_C_VALUES cleared)" }))
    Write-Host ("  fdr lanes: {0}" -f $(if ($FdrFileLanes -gt 0) {
                "OSPREY_FDR_FILE_LANES=$FdrFileLanes (forced; wall clock and memory only)" }
                else { "Osprey's FdrLaneResolver (OSPREY_FDR_FILE_LANES cleared)" }))
    # Since pwiz #4507 (2026-09-12) every pass selection streams: pass 1 is emitted off the
    # per-file 1st-pass sidecars, so `1` no longer forces the resident pool and `both` really
    # writes .pass1 and .pass2. The two yellow banners that stood here - a resident-pool
    # WARNING for `1`, and a NOTE that `both` yielded only pass 2 - described the defect and
    # are gone with it; the "pass 2" banner line above already names the selection. An exe
    # older than that fix still has both behaviours; the run dir's bench file set (one .tsv
    # vs .pass1/.pass2) says which you got.
    if (-not $mdiag) {
        Write-Host "  NOTE: no --model-diagnostics, so this run yields NO pass-1 FDP - and pass 1 is" -ForegroundColor Yellow
        Write-Host "        the number to quote (pass-2 recalibration inflates FDP)." -ForegroundColor Yellow
    }
    Write-Host ("  out dir  : {0}" -f $OutDir)
    Write-Host ""

    # -WhatIf still walks the -LinkFrom block below, in probe mode: it reports what WOULD link
    # without creating anything. Returning here instead would leave the one step whose failure
    # is most expensive - a source that contributes nothing, so the join quietly runs short of
    # the cohort its directory name claims - as the only step the dry run never exercises.
    if (-not $WhatIf) {
        New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
        $OutDir = (Resolve-Path $OutDir).Path
        if ($inputListPath) {
            Set-Content -Path $inputListPath -Value $inputs -Encoding utf8
        }
    }
    if ($inputListPath) {
        Write-Host ("  inputs   : {0} paths ({1:N0} chars) passed with --input-list {2}" -f $inputs.Count, $inputChars, $inputListPath)
    }

    # -Resume continues a directory whose artifacts carry the version of the build that wrote
    # them - which, after a -LinkFrom start, is the PINNED source version, not this exe's own.
    # Unpinned, a resume of an interrupted -LinkFrom run sees every artifact as stale and
    # recomputes from Stage 1 (observed: a 12-file SEA-AD resume restarted PerFileScoring).
    # Pin from the directory's own stamps, as -LinkFrom does from its sources.
    if ($Resume -and -not $LinkFrom -and -not $env:OSPREY_VERSION_OVERRIDE -and (Test-Path $OutDir)) {
        $resumeVer = Get-SourceOspreyVersion -Directory $OutDir
        if ($resumeVer) {
            $env:OSPREY_VERSION_OVERRIDE = $resumeVer
            Write-Host ("  Resume: pinned OSPREY_VERSION_OVERRIDE={0} from the run directory" -f $resumeVer)
        }
    }

    # Optional hard-link resume (same-file-set source only). How MUCH is linked depends on
    # -Task: enough to reach the task under test, and never the task's own outputs.
    if ($LinkFrom) {
        # ';' is also accepted as a separator INSIDE one element, because `pwsh -File` cannot
        # pass an array at all: it hands arguments over literally, so -LinkFrom a,b arrives as
        # the single string "a,b" and -LinkFrom a b binds b to whatever parameter comes next
        # (a ValidateSet error naming an unrelated parameter, which is a puzzle to read). Both
        # detached launches and Start-Process use -File, so one quoted 'a;b;c' is the form that
        # works everywhere; -LinkFrom a,b still works when dot-invoking from a pwsh prompt.
        $LinkFrom = @($LinkFrom | ForEach-Object { $_ -split ';' } |
                      Where-Object { $_ -and $_.Trim() } | ForEach-Object { $_.Trim() })
        foreach ($src in $LinkFrom) {
            if (-not (Test-Path $src)) { throw "LinkFrom dir not found: $src" }
        }
        # Osprey stamps a daily version into every artifact's embedded validity stamp (and,
        # before embedded stamps, into every .osprey.task sidecar) and refuses to reuse
        # artifacts from a different build - it recomputes them, or fails outright. A
        # -LinkFrom re-run on a newer binary is EXACTLY that case, so pin the source's version
        # unless the caller already chose one. Without this the linked bed is silently
        # recomputed, or the failure reads like a code bug.
        #
        # Get-SourceOspreyVersion reads the embedded stamp first and falls back to a legacy
        # .osprey.task, so a source written before embedded stamps still pins (its artifacts
        # read as stale under a new build regardless - that is accepted - but the version
        # agreement check below still means something for it).
        #
        # With SEVERAL sources the version has to AGREE across them. Pinning whichever one was
        # read first would let legs built on different days into one join, and only the odd
        # ones out would fail - as an "osprey version mismatch" naming a file, hours in, with
        # nothing pointing at the real cause. Refuse up front instead.
        $srcVers = [ordered]@{}
        foreach ($src in $LinkFrom) {
            $v = Get-SourceOspreyVersion -Directory $src
            if ($v) { $srcVers[$src] = $v }
        }
        $distinct = @($srcVers.Values | Sort-Object -Unique)
        if ($distinct.Count -gt 1) {
            throw ("-LinkFrom sources were produced by different Osprey builds, so they cannot be " +
                   "joined: " + (($srcVers.Keys | ForEach-Object { "$($srcVers[$_]) $_" }) -join '; ') +
                   ". Re-run the odd legs on one build, or pin OSPREY_VERSION_OVERRIDE yourself if " +
                   "you are certain the artifacts are compatible.")
        }
        if (-not $env:OSPREY_VERSION_OVERRIDE -and $distinct.Count -eq 1) {
            $env:OSPREY_VERSION_OVERRIDE = $distinct[0]
            Write-Host ("  LinkFrom: pinned OSPREY_VERSION_OVERRIDE={0} from the source run(s)" -f $distinct[0])
        }
        # WHAT to link comes from the tasks' own declarations (`--task-files`, which prints each
        # task's Inputs and Outputs and runs nothing), not from a table kept here. The table this
        # replaced linked every earlier stage's artifacts cumulatively and drifted twice: it
        # once filed the per-run 2nd-pass sidecar under its old producer, so `-Task
        # SecondPassFDR -LinkFrom` staged neither it nor its decoys and two Stage-7 A/B
        # measurements both ran the same fallback; and it once omitted the analysis-wide
        # experiment sidecar, which Osprey reads past with an [ERROR] and finishes
        # success-shaped hours later. A declaration is the one list the pipeline itself owns,
        # so this and regression.ps1's HPC chain stage from the same source
        # (TODO-task_file_contract_from_declarations.md).
        #
        # Two shapes:
        #   * -Task <stage>: an HPC node. Link exactly that task's declared inputs, and with
        #     -LinkThroughTask its declared outputs too - a re-entry has to find its own outputs
        #     to see that it already ran. One --task-files call.
        #   * an ordinary run resumed at a boundary (-LinkUpTo, else FirstPassFDR; -Task
        #     ModelDiagnostics / TrainingExport, which re-enter a completed analysis, at the
        #     end): the outputs of every stage before the boundary, which is what lets the
        #     driver skip those stages, plus the boundary stage's own declared inputs - the
        #     analysis-wide files FirstPassFDR writes without declaring them as outputs (the
        #     model, the stratum) are inputs of the stages that read them. One call per stage.
        # Only files that resolve into the output directory are linked: the library, the data
        # files and their spectra caches are read where they are.
        if ($LinkUpTo -and $LinkThroughTask) {
            throw '-LinkUpTo names the boundary itself; drop -LinkThroughTask.'
        }
        $PIPELINE = @('PerFileScoring', 'FirstPassFDR', 'PerFileRescoring', 'SecondPassFDR')
        $nodeTask = if (-not $LinkUpTo -and $Task -and ($PIPELINE -contains $Task)) { $Task } else { $null }
        $upTo = if ($LinkUpTo) { $LinkUpTo } elseif ($Task) { $Task } else { 'FirstPassFDR' }
        if ($upTo -eq 'SpectraCache' -or ($upTo -eq 'PerFileScoring' -and -not $LinkThroughTask)) {
            throw ("-Task/-LinkUpTo $upTo is the FIRST pipeline stage, so there is nothing earlier to link. " +
                   "Drop -LinkFrom and run it against the raw input.")
        }

        # The declarations under THIS run's command line and pass-2 mode (the stratum is
        # declared only under protein-compact), with --task <stage> in place of the run's own.
        $printArgs = [System.Collections.Generic.List[string]]::new()
        for ($i = 0; $i -lt $cliArgs.Count; $i++) {
            if ($cliArgs[$i] -eq '--task') { $i++; continue }
            $printArgs.Add($cliArgs[$i])
        }
        $printList = $null
        if ($inputListPath -and -not (Test-Path $inputListPath)) {
            # -WhatIf has not written the list yet; print from a temporary copy.
            $printList = [IO.Path]::GetTempFileName()
            Set-Content -Path $printList -Value $inputs -Encoding utf8
            $printArgs[$printArgs.IndexOf($inputListPath)] = $printList
        }
        $outDirExisted = Test-Path $OutDir
        $priorPass2 = $env:OSPREY_PASS2_QVALUE
        $env:OSPREY_PASS2_QVALUE = $Pass2Mode
        $declaredByStage = @{}
        try {
            $stagesToPrint = if ($nodeTask) { @($nodeTask) } else { $PIPELINE }
            foreach ($stage in $stagesToPrint) {
                $lines = @(& $ospreyExe @printArgs '--task' $stage '--task-files' 2>&1 | ForEach-Object { "$_" })
                if ($LASTEXITCODE -ne 0) {
                    throw ("-LinkFrom: Osprey --task $stage --task-files failed, so the declared files to " +
                           "link are unknown: " + ($lines -join ' | '))
                }
                # The last three tab-separated fields: --timestamp / --memstamp prepend columns.
                $declaredByStage[$stage] = @(foreach ($line in $lines) {
                    $f = $line.Split("`t")
                    if ($f.Count -ge 3 -and ($f[-3] -eq 'input' -or $f[-3] -eq 'output') -and $f[-2] -eq $stage) {
                        [pscustomobject]@{ Kind = $f[-3]; Path = [IO.Path]::GetFullPath($f[-1].Trim()) }
                    }
                })
            }
        } finally {
            $env:OSPREY_PASS2_QVALUE = $priorPass2
            if ($printList) { Remove-Item $printList -ErrorAction SilentlyContinue }
            # Printing resolves --output-dir and may create it; a dry run leaves no trace.
            if ($WhatIf -and -not $outDirExisted -and (Test-Path $OutDir) -and
                @(Get-ChildItem $OutDir -Force).Count -eq 0) {
                Remove-Item $OutDir -ErrorAction SilentlyContinue
            }
        }
        function Select-Declared([string]$Stage, [string]$Kind) {
            @($declaredByStage[$Stage] | Where-Object { $_.Kind -eq $Kind } | ForEach-Object { $_.Path })
        }
        $wanted = [System.Collections.Generic.List[string]]::new()
        if ($nodeTask) {
            $own = Select-Declared $nodeTask 'output'
            foreach ($p in (Select-Declared $nodeTask 'input')) { if ($own -notcontains $p) { $wanted.Add($p) } }
            if ($LinkThroughTask) { foreach ($p in $own) { $wanted.Add($p) } }
            $through = if ($LinkThroughTask) { "inputs and outputs of $nodeTask" } else { "inputs of $nodeTask" }
        } else {
            $b = [array]::IndexOf($PIPELINE, $upTo)
            if ($b -lt 0) { $b = $PIPELINE.Count }   # ModelDiagnostics / TrainingExport: the whole analysis
            for ($s = 0; $s -lt $b; $s++) {
                foreach ($p in (Select-Declared $PIPELINE[$s] 'output')) { $wanted.Add($p) }
            }
            $boundaryStages = if ($b -lt $PIPELINE.Count) { @($PIPELINE[$b]) } else { $PIPELINE }
            foreach ($stage in $boundaryStages) {
                $own = if ($b -lt $PIPELINE.Count) { Select-Declared $stage 'output' } else { @() }
                foreach ($p in (Select-Declared $stage 'input')) { if ($own -notcontains $p) { $wanted.Add($p) } }
            }
            $through = if ($b -lt $PIPELINE.Count) { "stages before $upTo, and its inputs" } else { 'whole analysis' }
        }
        $outFull = [IO.Path]::GetFullPath($OutDir).TrimEnd('\')
        $wanted = @($wanted | Sort-Object -Unique |
                    Where-Object { [IO.Path]::GetDirectoryName($_).TrimEnd('\') -eq $outFull })

        # Analysis-wide files are named for the output blib's stem, which a source run need not
        # share, so one not found under its own name is looked up under the SOURCE's blib stem,
        # read off the analysis-wide file every source past Stage 4 has. Not a glob on the rest
        # of the name: '*.blib' also matches the derived <library-leaf>.blib a run leaves beside
        # its artifacts, and would link the library as the output.
        $blibStem = [IO.Path]::GetFileNameWithoutExtension($blib)
        $sourceStem = @{}
        foreach ($src in $LinkFrom) {
            foreach ($marker in '.1st-pass.fdr_experiment.bin', '.1st-pass.retained_base_ids.bin') {
                $hit = Get-ChildItem (Join-Path $src ('*' + $marker)) -File -ErrorAction SilentlyContinue |
                       Select-Object -First 1
                if ($hit) { $sourceStem[$src] = $hit.Name.Substring(0, $hit.Name.Length - $marker.Length); break }
            }
        }
        $linked = 0
        $missingFiles = [System.Collections.Generic.List[string]]::new()
        # Per-source tally, so a leg that contributed NOTHING is visible. Silence there is the
        # expensive mistake: the join would just run short by that leg's files and report a
        # smaller cohort than the directory name claims.
        $linkedBySource = [ordered]@{}
        foreach ($src in $LinkFrom) { $linkedBySource[$src] = 0 }
        foreach ($d in $wanted) {
            $leaf = Split-Path -Leaf $d
            $s = $null
            # First source holding this artifact wins; the legs are disjoint by construction
            # (each scored a different plate), so order only matters if they overlap.
            foreach ($src in $LinkFrom) {
                $cand = Join-Path $src $leaf
                if (Test-Path -LiteralPath $cand) { $s = $cand; $linkedBySource[$src]++; break }
            }
            if (-not $s -and $leaf.StartsWith($blibStem + '.')) {
                $suffix = $leaf.Substring($blibStem.Length)
                foreach ($src in $LinkFrom) {
                    if (-not $sourceStem.ContainsKey($src)) { continue }
                    $cand = Join-Path $src ($sourceStem[$src] + $suffix)
                    if (Test-Path -LiteralPath $cand) { $s = $cand; $linkedBySource[$src]++; break }
                }
                if ($s) { Write-Host ("  analysis-wide: {0} <- {1}" -f $leaf, $s) }
            }
            if (-not $s) {
                $missingFiles.Add($leaf)
                continue
            }
            if (-not $WhatIf) {
                if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Force }
                New-Item -ItemType HardLink -Path $d -Target $s | Out-Null
            }
            $linked++
        }

        $verb = if ($WhatIf) { 'WOULD hard-link' } else { 'hard-linked' }
        Write-Host ("LinkFrom: {0} {1} declared file(s), the {2}, from {3} source(s)" -f
                    $verb, $linked, $through, @($LinkFrom).Count)
        foreach ($src in $LinkFrom) {
            $n = $linkedBySource[$src]
            $color = if ($n -eq 0) { 'Yellow' } else { 'Gray' }
            Write-Host ("  {0,7} from {1}" -f $n, $src) -ForegroundColor $color
        }
        # A declared file no source holds FAILS here, before the run. A short bed used to be a
        # warning, because the table could not tell a legitimately absent artifact from a
        # missing one; the declarations carry the conditions the task reads under, so a
        # declared file is one the run needs, and an hour into the run is the wrong place to
        # find that out.
        if ($missingFiles.Count -gt 0) {
            throw ("-LinkFrom: {0} declared file(s) are in none of the sources: {1}{2}" -f
                   $missingFiles.Count, (($missingFiles | Select-Object -First 10) -join ', '),
                   $(if ($missingFiles.Count -gt 10) { ', ...' } else { '' }))
        }
    }

    if ($WhatIf) {
        Write-Host ""
        Write-Host "-WhatIf: not running. Command would be:" -ForegroundColor Yellow
        Write-Host ("  {0} {1}" -f $ospreyExe, ($cliArgs -join ' '))
        return
    }

    # Strip every experimental lever that must NOT influence this run. A stale env var from an
    # earlier experiment in the same shell is invisible in the output and silently changes the
    # result, so the arms set exactly what they mean and clear the rest. OSPREY_PICK_LDA and
    # OSPREY_PICK_LDA_MODEL are in this list because the pick model is nowhere in Osprey's log:
    # an inherited one would be both silent AND unrecoverable after the fact.
    # OSPREY_TRAIN_PICK_RUN is cleared but has no switch, unlike OSPREY_PICK_LDA below it.
    # The one-run-per-precursor sampler (pickrun3, pwiz #4593) is the settled default, and
    # '0' exists only as an emergency revert - there is no arm here that wants it. It still
    # has to be STRIPPED rather than merely left alone, because which runs trained the model
    # is nowhere in Osprey's log: an inherited '0' would silently train the old way and be
    # unrecoverable after the fact, exactly the pick-model failure described below. If a
    # sampler A/B is ever wanted, add a switch and set this in both directions.
    # OSPREY_SVM_C_TOLERANCE is stripped for the same reason: an inherited 0 (the pre-#4703
    # strict-maximum C selection) would train the cohort under the old rule behind a banner
    # that claims defaults. -SvmCTolerance sets it on purpose.
    foreach ($k in 'OSPREY_EXIT_AFTER_CALIBRATION', 'OSPREY_CAL_SAMPLE_SIZE',
                   'OSPREY_CAL_MEDIANPOLISH', 'OSPREY_PASS2_QVALUE',
                   'OSPREY_TRAIN_PICK_RUN', 'OSPREY_SVM_C_TOLERANCE', 'OSPREY_SVM_C_VALUES',
                   'OSPREY_FDR_FILE_LANES',
                   'OSPREY_PICK_LDA', 'OSPREY_PICK_LDA_MODEL',
                   'OSPREY_PROTEIN_COMPACT_RETRAIN', 'OSPREY_EXPERIMENT_AGG',
                   'OSPREY_PROTEIN_COMPACT_QUALIFY',
                   'OSPREY_DECOY_SAME_ION_MAP', 'OSPREY_DECOY_PRECURSOR_SHIFT_UNITS',
                   'OSPREY_DECOY_MAX_FRAG_OVERLAP', 'OSPREY_DECOY_MAX_SEQ_IDENTITY') {
        Remove-Item "Env:\$k" -ErrorAction SilentlyContinue
    }
    # Both levers are set UNCONDITIONALLY, in both directions. Leaving a variable unset used to
    # mean "the old default", and both defaults have since flipped - OSPREY_PASS2_QVALUE unset is
    # now protein-compact and OSPREY_PICK_LDA unset is now the learned model. An arm that only
    # exported its ON value would therefore run a DIFFERENT configuration than its banner and
    # run.log claim, and the two arms of an A/B would be the same run under two labels.
    $env:OSPREY_PASS2_QVALUE = $Pass2Mode
    $env:OSPREY_PICK_LDA = if ($PickProduct) { '0' } else { '1' }
    $env:OSPREY_LOG_MEMORY = if ($LogMemory) { '1' } else { '0' }
    if ($ExperimentAgg) { $env:OSPREY_EXPERIMENT_AGG = $ExperimentAgg }
    # OSPREY_PROTEIN_COMPACT_QUALIFY and OSPREY_SVM_C_VALUES are read by no Osprey build (C# or
    # Rust) any more, so -QualifyBy experiment and -SvmCValues ran the default arm while naming
    # the directory after the other one. C# Osprey refuses an OSPREY_* variable it does not
    # read (2026-10-11), so they are no longer exported, and asking for either arm is refused
    # here rather than filed under a name it did not run.
    if ($QualifyBy -ne 'run' -or $SvmCValues) {
        throw "-QualifyBy experiment and -SvmCValues select arms no Osprey build implements any more (their variables are read by neither C# nor Rust). Omit them."
    }
    # Only when given: unset is Osprey's own default, and the variable was stripped above.
    if ($SvmCTolerance) { $env:OSPREY_SVM_C_TOLERANCE = $SvmCTolerance }
    if ($FdrFileLanes -gt 0) { $env:OSPREY_FDR_FILE_LANES = "$FdrFileLanes" }

    $log = Join-Path $OutDir 'run.log'
    # NEVER truncate an existing run.log - rotate it to run-<stamp>.log first. A run.log is the
    # ONLY record of a run's timing and memory profile, it is not reproducible without spending
    # the hours again, and the START line below is a Set-Content: one -Resume into the wrong
    # directory silently destroyed an 18-hour run's 1.8 MB log this way. Recovered that time
    # only because a human happened to have it open in an editor.
    #
    # The stamp is the OLD log's last-write time, not "now": it names when that run ENDED,
    # which is what someone looking for a particular run is actually searching by.
    if (Test-Path $log) {
        $stamp = (Get-Item $log).LastWriteTime.ToString('yyyyMMdd_HHmmss')
        $rotated = Join-Path $OutDir "run-$stamp.log"
        # Two runs finishing inside the same second is unlikely but a collision would resume
        # the data loss this whole block exists to prevent, so disambiguate rather than clobber.
        $n = 1
        while (Test-Path $rotated) {
            $rotated = Join-Path $OutDir "run-$stamp-$n.log"
            $n++
        }
        Move-Item -Path $log -Destination $rotated
        Write-Host ("  rotated previous run.log -> {0}" -f (Split-Path $rotated -Leaf)) -ForegroundColor Cyan
    }
    ("[{0}] START dataset=$($Dataset.Key) arm=$DecoyMode r=$Ratio pass2=$Pass2Mode " +
     "pick=$(if ($PickProduct) { 'product' } else { 'lda' }) trainpick=run logmem=$(if ($LogMemory) { 'on' } else { 'off' }) expagg='$(if ($ExperimentAgg) { $ExperimentAgg } else { 'max' })' " +
     "qualify=$QualifyBy csel='$SvmCTolerance' cvals='$SvmCValues' fdrlanes=$FdrFileLanes files=$($inputs.Count) threads=$Threads " +
     "parallelfiles=$ParallelFiles pfcache=$ParallelFilesCaching pfscore=$ParallelFilesScoring pfrescore=$ParallelFilesRescoring task='$Task' mdiag=$mdiag trainexport=$([bool]$TrainingExport) perfstats=$(-not $NoPerfStats) " +
     "fdrbench=$FdrBenchPass linkfrom='$($LinkFrom -join ';')'") -f (Get-Date -Format s) |
        Set-Content -Path $log
    "Exe: $ospreyExe" | Add-Content -Path $log
    "Library: $libraryPath" | Add-Content -Path $log
    "LibraryFile: $libFingerprint" | Add-Content -Path $log
    "OutDir: $OutDir" | Add-Content -Path $log

    Write-Host "Logging to $log" -ForegroundColor Cyan
    $sw = [Diagnostics.Stopwatch]::StartNew()
    # Out-Host, or Tee-Object's pipeline output becomes this function's return value and
    # the caller's `exit $exitCode` receives the whole transcript instead of the code.
    if ($ProfileTo) {
        $dotTrace = Get-Command 'dottrace' -ErrorAction SilentlyContinue
        if (-not $dotTrace) {
            throw 'dottrace not found. Install: dotnet tool install --global JetBrains.dotTrace.GlobalTools'
        }
        "Profile: $ProfileTo" | Add-Content -Path $log
        $traceArgs = @('start', '--profiling-type=Sampling', "--save-to=$ProfileTo", '--overwrite',
                       '--propagate-exit-code', $ospreyExe, '--') + $cliArgs
        & $dotTrace.Source @traceArgs *>&1 | Tee-Object -FilePath $log -Append | Out-Host
    }
    else {
        & $ospreyExe @cliArgs *>&1 | Tee-Object -FilePath $log -Append | Out-Host
    }
    $exit = $LASTEXITCODE
    $sw.Stop()
    ("[{0}] DONE dataset=$($Dataset.Key) arm=$DecoyMode r=$Ratio pass2=$Pass2Mode " +
     "pick=$(if ($PickProduct) { 'product' } else { 'lda' }) trainpick=run logmem=$(if ($LogMemory) { 'on' } else { 'off' }) expagg='$(if ($ExperimentAgg) { $ExperimentAgg } else { 'max' })' " +
     "qualify=$QualifyBy csel='$SvmCTolerance' cvals='$SvmCValues' fdrlanes=$FdrFileLanes parallelfiles=$ParallelFiles pfcache=$ParallelFilesCaching pfscore=$ParallelFilesScoring pfrescore=$ParallelFilesRescoring exit=$exit elapsed=$([int]$sw.Elapsed.TotalMinutes)min") -f (Get-Date -Format s) |
        Add-Content -Path $log
    Write-Host ("Osprey exited {0} after {1:hh\:mm\:ss}" -f $exit, $sw.Elapsed) `
        -ForegroundColor $(if ($exit -eq 0) { 'Green' } else { 'Red' })
    return $exit
}

Export-ModuleMember -Function Invoke-OspreyDatasetRun
