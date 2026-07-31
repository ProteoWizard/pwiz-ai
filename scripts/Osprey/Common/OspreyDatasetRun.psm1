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
#>
function Resolve-LibraryVariant {
    param(
        [string]$LibRoot,
        [string]$DecoyMode,
        [string]$Ratio,
        [string]$Readme
    )
    $variant = if ($DecoyMode -eq 'gendecoy') {
        "target+entrapment-r$Ratio-gendecoy"
    } elseif ($Ratio -eq '1.0') {
        'target+decoy+entrapment'
    } else {
        "target+decoy+entrapment-r$Ratio"
    }

    $libDir = Join-Path $LibRoot $variant
    if (-not (Test-Path $libDir)) {
        if (Test-Path (Join-Path $LibRoot 'carafe_spectral_library.tsv')) {
            $libDir = $LibRoot
        } else {
            throw ("No library variant '$variant' under '$LibRoot', and '$LibRoot' is not " +
                   "itself a library directory. Build it with New-SeaAdLibrary.ps1 -Ratio " +
                   "$Ratio -DecoyMode $DecoyMode, or pass -LibraryDir/-Library explicitly. " +
                   "See $Readme.")
        }
    }
    return $libDir
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
      DefaultNumFiles      cohort size when -NumFiles is not passed
      DefaultExcludePattern  regex applied when -ExcludePattern is not passed
      DefaultFdrBenchPass  'none' | '1' | '2' | 'both' when -FdrBenchPass is not passed
      MissingCacheNote     extra line printed when caches are missing

.PARAMETER PickLda
    Use the learned resolution-keyed linear peak-pick model (OSPREY_PICK_LDA=1) instead of
    the default product-form pick (coelution * rt_penalty * ln_intensity).

    This MOVES THE DISCOVERY SET - it is a different peak choice, not a different report -
    so it is recorded in the banner and the run.log START line. Nothing Osprey logs says
    which pick model a run used, so without that record a finished run is unattributable.
    OSPREY_PICK_LDA is also cleared when this is off, so an exported shell variable cannot
    silently apply it to an arm that did not ask for it.

.PARAMETER Pass2Mode
    percolator      : default. Second-pass Percolator retrain on the reconciled pool.
    transfer        : frozen first-pass model, TRIC-style q-value fill-in, no retrain.
                      NOTE: forces the RESIDENT first-pass pool (O(files)) - see README.
    transfer-compete: frozen model, then a fresh target-decoy competition over the full
                      reconciled population (non-depleted null).
    protein-compact : frozen model, competition CONSTRAINED to peptides of proteins detected
                      in the first pass (>= 2 peptides), target+decoy pairs kept.
    Passed through OSPREY_PASS2_QVALUE, which this function clears first so a stale shell
    variable can never silently change an arm.

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
        [ValidateSet('percolator', 'transfer', 'transfer-compete', 'protein-compact')]
        [string]$Pass2Mode = 'percolator',
        [switch]$PickLda,
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
        [int]$Threads = 30,
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
    $EXE_UNDER_ROOT = 'pwiz_tools\Osprey\Osprey\bin\x64\Release\net8.0\Osprey.exe'
    if ($SourceRoot -and -not $Exe) {
        if (-not (Test-Path $SourceRoot)) { throw "-SourceRoot does not exist: '$SourceRoot'." }
        $Exe = Join-Path $SourceRoot $EXE_UNDER_ROOT
        if (-not (Test-Path $Exe)) {
            throw "No Release/net8.0 Osprey.exe under -SourceRoot '$SourceRoot'. Build it there first."
        }
    }
    $repoExe = Join-Path $PSScriptRoot "..\..\..\..\pwiz\$EXE_UNDER_ROOT"
    $ospreyExe = Resolve-DatasetLocation -Explicit $Exe -EnvName 'OSPREY_EXE' `
        -Fallbacks @($repoExe) -What 'Osprey.exe (build Release/net8.0 first)' `
        -DatasetName $dsName -Readme $readme

    $libRoot = Resolve-DatasetLocation -Explicit $LibraryDir -EnvName $Dataset.EnvLibVar `
        -Fallbacks @() -What 'library directory' -DatasetName $dsName -Readme $readme
    $libDir = Resolve-LibraryVariant -LibRoot $libRoot -DecoyMode $DecoyMode -Ratio $Ratio -Readme $readme

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
    $manifest = Join-Path $libDir 'osprey_library_db_pairing.tsv'
    if ($DecoyMode -eq 'libdecoy' -and -not (Test-Path $manifest)) {
        throw ("-DecoyMode libdecoy needs the pairing manifest '$manifest'. It ships with the " +
               "target+decoy+entrapment libraries; see $readme.")
    }

    $allInputs = @(Get-ChildItem -Path $dataDir -Filter "*.$ext" -File | Sort-Object Name)
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
    $inputs = @($allInputs | Select-Object -Skip $SkipFirstFiles -First $NumFiles |
                ForEach-Object { $_.FullName })
    if ($inputs.Count -eq 0) { throw "No .$ext files found in '$dataDir'." }
    if ($inputs.Count -lt $NumFiles) {
        throw ("Only $($inputs.Count) .$ext available in '$dataDir' after skipping " +
               "$SkipFirstFiles, need $NumFiles. See $readme.")
    }

    # .spectra.bin beside the data is the difference between a run that streams and one that
    # also pays the parse. Worth saying out loud rather than discovering at hour six.
    $cacheProbeDir = if ($CacheDir) { $CacheDir } else { $dataDir }
    $cached = @(Get-ChildItem -Path $cacheProbeDir -Filter '*.spectra.bin' -File -ErrorAction SilentlyContinue).Count

    if (-not $OutDir) {
        # The dataset root is the data directory's PARENT and every run goes under its runs\,
        # so someone on another machine finds a run without being told where to look. (The old
        # SEA-AD runner walked two levels up, which contradicted its own README and resolved
        # OUTSIDE the dataset root on a <root>\<dataset>\<data> layout.) -RunsRoot overrides.
        $runsRootResolved = if ($RunsRoot) { $RunsRoot } else { Join-Path (Split-Path $dataDir -Parent) 'runs' }
        $pick = if ($PickLda) { '-picklda' } else { '' }
        $name = "$($Dataset.Key)-$($inputs.Count)files-$DecoyMode-r$Ratio-$Pass2Mode$pick$Tag"
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
    $cliArgs = @('-i') + $inputs + @(
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
    if ($CacheDir) { $cliArgs += @('--cache-dir', $CacheDir) }
    if ($DecoyMode -eq 'libdecoy') { $cliArgs += @('--decoys-in-library', '--decoy-pairing-manifest', $manifest) }
    $mdiag = -not $NoModelDiagnostics
    if ($mdiag) { $cliArgs += '--model-diagnostics' }

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
    if ($cached -lt $inputs.Count) {
        Write-Host "  NOTE: not every file has a spectra cache; expect a per-file parse cost." -ForegroundColor Yellow
        if ($Dataset.ContainsKey('MissingCacheNote')) {
            Write-Host ("        {0}" -f $Dataset.MissingCacheNote) -ForegroundColor Yellow
        }
    }
    Write-Host ("  library  : {0}" -f $libraryPath)
    Write-Host ("  arm      : {0}  r={1}" -f $DecoyMode, $Ratio)
    Write-Host ("  pass 2   : {0}   fdrbench pass {1}   model-diagnostics {2}" -f
                $Pass2Mode, $FdrBenchPass, $(if ($mdiag) { 'on' } else { 'OFF' }))
    # Nothing Osprey logs records the pick model, so this banner line and the run.log START
    # line are the only provenance a finished run carries.
    Write-Host ("  peak pick: {0}" -f $(if ($PickLda) {
                'LEARNED linear model (OSPREY_PICK_LDA=1) - moves the discovery set' }
                else { 'default product form (coelution * rt_penalty * ln_intensity)' }))
    if ($FdrBenchPass -eq '1') {
        Write-Host "  WARNING: --fdrbench-pass 1 forces the RESIDENT first-pass pool, which grows" -ForegroundColor Yellow
        Write-Host "           O(files) and does not scale to a large cohort. See the README." -ForegroundColor Yellow
    } elseif ($FdrBenchPass -ne 'none') {
        Write-Host ("  NOTE: --fdrbench-pass {0} currently yields only the pass-2 TSV; the pass-1" -f $FdrBenchPass) -ForegroundColor Yellow
        Write-Host "        pool is not emitted off the projection path. Pass-1 FDP comes from the" -ForegroundColor Yellow
        Write-Host "        --model-diagnostics report instead." -ForegroundColor Yellow
    }
    if ($Pass2Mode -eq 'transfer') {
        Write-Host "  WARNING: OSPREY_PASS2_QVALUE=transfer forces the RESIDENT first-pass pool" -ForegroundColor Yellow
        Write-Host "           (O(files)). The other frozen-model modes do not." -ForegroundColor Yellow
    }
    if (-not $mdiag) {
        Write-Host "  NOTE: no --model-diagnostics, so this run yields NO pass-1 FDP - and pass 1 is" -ForegroundColor Yellow
        Write-Host "        the number to quote (pass-2 recalibration inflates FDP)." -ForegroundColor Yellow
    }
    Write-Host ("  out dir  : {0}" -f $OutDir)
    Write-Host ""

    if ($WhatIf) {
        Write-Host "-WhatIf: not running. Command would be:" -ForegroundColor Yellow
        Write-Host ("  {0} {1}" -f $ospreyExe, ($cliArgs -join ' '))
        return
    }

    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    $OutDir = (Resolve-Path $OutDir).Path

    # Optional Stage 1-4 hard-link resume (same-file-set source only).
    if ($LinkFrom) {
        if (-not (Test-Path $LinkFrom)) { throw "LinkFrom dir not found: $LinkFrom" }
        $suffixes = @(
            '.calibration.json', '.calibration.json.PerFileScoring.osprey.task',
            '.scores.parquet', '.scores.parquet.PerFileScoring.osprey.task'
        )
        $linked = 0; $missing = 0
        foreach ($f in $inputs) {
            $stem = [IO.Path]::GetFileNameWithoutExtension($f)
            foreach ($suf in $suffixes) {
                $s = Join-Path $LinkFrom ($stem + $suf)
                $d = Join-Path $OutDir ($stem + $suf)
                if (-not (Test-Path $s)) { $missing++; continue }
                if (Test-Path $d) { Remove-Item $d -Force }
                New-Item -ItemType HardLink -Path $d -Target $s | Out-Null
                $linked++
            }
        }
        Write-Host ("LinkFrom: hard-linked {0} stage1-4 file(s), {1} missing, from {2}" -f $linked, $missing, $LinkFrom)
    }

    # Strip every experimental lever that must NOT influence this run. A stale env var from an
    # earlier experiment in the same shell is invisible in the output and silently changes the
    # result, so the arms set exactly what they mean and clear the rest. OSPREY_PICK_LDA and
    # OSPREY_PICK_LDA_MODEL are in this list because the pick model is nowhere in Osprey's log:
    # an inherited one would be both silent AND unrecoverable after the fact.
    foreach ($k in 'OSPREY_EXIT_AFTER_CALIBRATION', 'OSPREY_CAL_SAMPLE_SIZE',
                   'OSPREY_CAL_MEDIANPOLISH', 'OSPREY_PASS2_QVALUE',
                   'OSPREY_PICK_LDA', 'OSPREY_PICK_LDA_MODEL',
                   'OSPREY_PROTEIN_COMPACT_RETRAIN',
                   'OSPREY_DECOY_SAME_ION_MAP', 'OSPREY_DECOY_PRECURSOR_SHIFT_UNITS',
                   'OSPREY_DECOY_MAX_FRAG_OVERLAP', 'OSPREY_DECOY_MAX_SEQ_IDENTITY') {
        Remove-Item "Env:\$k" -ErrorAction SilentlyContinue
    }
    if ($Pass2Mode -ne 'percolator') { $env:OSPREY_PASS2_QVALUE = $Pass2Mode }
    if ($PickLda) { $env:OSPREY_PICK_LDA = '1' }

    $log = Join-Path $OutDir 'run.log'
    ("[{0}] START dataset=$($Dataset.Key) arm=$DecoyMode r=$Ratio pass2=$Pass2Mode " +
     "picklda=$([bool]$PickLda) files=$($inputs.Count) threads=$Threads mdiag=$mdiag " +
     "fdrbench=$FdrBenchPass linkfrom='$LinkFrom'") -f (Get-Date -Format s) |
        Set-Content -Path $log
    "Exe: $ospreyExe" | Add-Content -Path $log
    "Library: $libraryPath" | Add-Content -Path $log
    "OutDir: $OutDir" | Add-Content -Path $log

    Write-Host "Logging to $log" -ForegroundColor Cyan
    $sw = [Diagnostics.Stopwatch]::StartNew()
    & $ospreyExe @cliArgs *>&1 | Tee-Object -FilePath $log -Append
    $exit = $LASTEXITCODE
    $sw.Stop()
    ("[{0}] DONE dataset=$($Dataset.Key) arm=$DecoyMode r=$Ratio pass2=$Pass2Mode " +
     "picklda=$([bool]$PickLda) exit=$exit elapsed=$([int]$sw.Elapsed.TotalMinutes)min") -f (Get-Date -Format s) |
        Add-Content -Path $log
    Write-Host ("Osprey exited {0} after {1:hh\:mm\:ss}" -f $exit, $sw.Elapsed) `
        -ForegroundColor $(if ($exit -eq 0) { 'Green' } else { 'Red' })
    return $exit
}

Export-ModuleMember -Function Invoke-OspreyDatasetRun
