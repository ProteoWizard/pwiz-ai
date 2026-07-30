<#
.SYNOPSIS
    Run Osprey over the SEA-AD Pilot-MTG 82-file Astral DIA set.

.DESCRIPTION
    The single runner for this dataset. It replaces the one-off harnesses that produced
    every run under D:\test\Pilot-MTG-Tissue-May2026\runs on the original machine
    (run-82file-decoyarm.ps1, run-82file-gendecoy.ps1, run-pass2ab-82.ps1): they differed
    only in which decoy arm, entrapment ratio and pass-2 mode they selected, so they are
    parameters here rather than separate scripts. Running the arms through ONE script with
    identical logging is what makes them comparable.

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
    percolator      : default. Second-pass Percolator retrain on the reconciled pool.
    transfer        : OSPREY_PASS2_QVALUE=transfer -- frozen first-pass model, TRIC-style
                      q-value fill-in, no second retrain.
    transfer-compete: frozen model, then a fresh target-decoy competition over the full
                      reconciled population (non-depleted null).
    protein-compact : frozen model, competition CONSTRAINED to peptides of proteins detected
                      in the first pass (>= 2 peptides), target+decoy pairs kept.
    The mode is passed through OSPREY_PASS2_QVALUE, which this script clears first so a stale
    shell variable can never silently change an arm.

.PARAMETER LinkFrom
    Optional. Hard-link the Stage 1-4 per-file caches from a COMPLETED run over the same
    file set so this run resumes from Stage 5 (Pass 1 FDR) without re-parsing or
    re-scoring. Only stage 1-4 suffixes are linked, never Stage 5/6 outputs, so the part
    under test is always regenerated.

.PARAMETER NoModelDiagnostics
    Turn OFF the --model-diagnostics HTML report, which is on by default here.

    Leave it on unless you have a reason: it is the only place pass-1 entrapment FDP is
    reported today, and pass 1 is the number worth quoting. The old warning that it OOMs
    a 64 GB box at 82 files is obsolete - it now streams its pass-1 report off the
    projection path instead of holding the whole-run pool resident, and an 82-file mdiag
    run completed in 448 min at ~43 GB peak on 2026-07-26. It DOES still force the
    resident pool on a full resume (every .1st-pass sidecar already present), which is
    the case to avoid at scale.

.PARAMETER SourceRoot
    Checkout to take the Release/net8.0 Osprey.exe from. Prefer this over -Exe when what
    you care about is WHICH TREE: the default is the shared `pwiz` worktree, so a long run
    can silently measure whatever branch a colleague is mid-refactor on, while holding
    those DLLs so their rebuilds fail. Point it at a pinned checkout for a run that must
    not collide with active development.

.PARAMETER Fresh
    Timestamp the output directory name. Use when repeating an arm you have already run:
    Osprey adopts per-file caches it finds in the output directory, so reusing one turns a
    from-scratch run into a silent resume.

.PARAMETER Resume
    Deliberately continue into a non-empty output directory (e.g. after a crash), adopting
    whatever caches are there.

.PARAMETER WhatIf
    Print the resolved paths and the full command line, then stop. Do this first on a new
    machine - it is the cheap way to confirm everything resolved to what you expect
    before committing to a multi-hour run.

.EXAMPLE
    # Prove the wiring on a new machine before trusting it at 82 files.
    .\Run-SeaAd.ps1 -DecoyMode libdecoy -Ratio 1.0 -NumFiles 2 -WhatIf

.EXAMPLE
    # The reference arm, detached so a harness reap cannot kill it.
    Start-Process pwsh -ArgumentList '-NoProfile','-File',
      'C:/proj/ai/scripts/Osprey/SEA-AD/Run-SeaAd.ps1','-DecoyMode','libdecoy','-Ratio','1.0' `
      -WindowStyle Hidden
#>
#requires -Version 7
param(
    [ValidateSet('libdecoy', 'gendecoy')] [string]$DecoyMode = 'libdecoy',
    [string]$Ratio = '1.0',
    [ValidateSet('percolator', 'transfer', 'transfer-compete', 'protein-compact')]
    [string]$Pass2Mode = 'percolator',
    [int]$NumFiles = 82,
    # Take the $NumFiles files AFTER skipping this many, so cohorts of the same size can be
    # drawn from disjoint slices of the dataset (replicate cohorts for a size-vs-effect study).
    # Pass -Tag to keep the run directories apart: the name only carries the file COUNT.
    [int]$SkipFirstFiles = 0,
    # Keep every Nth file instead of a contiguous block. Name order tracks acquisition order in
    # this dataset, and instrument response drifts across it, so a contiguous first-F cohort is
    # also the EARLIEST (best) F files -- size and quality are confounded. -EveryNthFile 2 draws
    # a cohort that spans the whole acquisition at half the size, separating the two.
    [int]$EveryNthFile = 1,
    # Drop files whose name matches this regex (e.g. 'pool' for the pooled QC injections, which
    # sort last and therefore only enter the largest cohorts).
    [string]$ExcludePattern = '',
    [int]$Threads = 30,
    [ValidateSet('1', '2', 'both')] [string]$FdrBenchPass = 'both',
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
    # ON by default, matching the harness that produced the recorded runs. It is also the
    # ONLY source of pass-1 FDP today (see -NoModelDiagnostics), and it no longer forces
    # the resident first-pass pool on a straight-through run. See README.
    [switch]$NoModelDiagnostics,
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$readme = Join-Path $PSScriptRoot 'README.md'

# Last-resort fallbacks. Named once here so the README and the code cannot drift apart.
$LAB_SHARE_MZML = 'M:\home\brendanx\data\MacCoss\SEA-AD\Astral-DIA\mzml'
$REPO_EXE = Join-Path $PSScriptRoot '..\..\..\..\pwiz\pwiz_tools\Osprey\Osprey\bin\x64\Release\net8.0\Osprey.exe'

function Resolve-Location {
    param([string]$Explicit, [string]$EnvName, [string[]]$Fallbacks, [string]$What)
    # A location the caller NAMED must exist. Falling through to the next candidate when
    # an explicit path is wrong is how a run spends 7.5 h against the wrong data and still
    # reports success, so a typo fails here instead.
    $envValue = [Environment]::GetEnvironmentVariable($EnvName)
    foreach ($named in @(@{ V = $Explicit; S = 'parameter' }, @{ V = $envValue; S = "`$env:$EnvName" })) {
        if ($named.V) {
            if (-not (Test-Path $named.V)) {
                throw "The SEA-AD $What given by $($named.S) does not exist: '$($named.V)'."
            }
            return (Resolve-Path $named.V).Path
        }
    }
    foreach ($c in $Fallbacks) {
        if ($c -and (Test-Path $c)) { return (Resolve-Path $c).Path }
    }
    throw ("Could not locate the SEA-AD $What. Pass it explicitly, or set `$env:$EnvName. " +
           "See $readme for the source URLs and the lab-share path.")
}

$dataDir = Resolve-Location -Explicit $DataDir -EnvName 'OSPREY_SEAAD_DIR' `
                            -Fallbacks @($LAB_SHARE_MZML) -What 'mzML directory'

# -SourceRoot names a checkout; the exe is at its usual place inside it. Prefer this to
# -Exe when you want a specific TREE, e.g. a pinned worktree rather than the shared
# default one that other sessions are actively building in. See the banner warning below.
$EXE_UNDER_ROOT = 'pwiz_tools\Osprey\Osprey\bin\x64\Release\net8.0\Osprey.exe'
if ($SourceRoot -and -not $Exe) {
    if (-not (Test-Path $SourceRoot)) { throw "-SourceRoot does not exist: '$SourceRoot'." }
    $Exe = Join-Path $SourceRoot $EXE_UNDER_ROOT
    if (-not (Test-Path $Exe)) {
        throw "No Release/net8.0 Osprey.exe under -SourceRoot '$SourceRoot'. Build it there first."
    }
}
$ospreyExe = Resolve-Location -Explicit $Exe -EnvName 'OSPREY_EXE' `
                              -Fallbacks @($REPO_EXE) -What 'Osprey.exe (build Release/net8.0 first)'

# The library ROOT holds the variants; New-SeaAdLibrary.ps1 owns their naming and this
# reproduces it. Resolving the variant by convention is what lets -Ratio and -DecoyMode
# be plain parameters instead of another path to pass on every command line.
$libRoot = Resolve-Location -Explicit $LibraryDir -EnvName 'OSPREY_SEAAD_LIB' `
                            -Fallbacks @() -What 'library directory'
$variant = if ($DecoyMode -eq 'gendecoy') {
    "target+entrapment-r$Ratio-gendecoy"
} elseif ($Ratio -eq '1.0') {
    'target+decoy+entrapment'
} else {
    "target+decoy+entrapment-r$Ratio"
}

# -LibraryDir may name either the root holding the variants or one variant directly, so a
# machine that lays its libraries out differently is not locked out by the convention.
$libDir = Join-Path $libRoot $variant
if (-not (Test-Path $libDir)) {
    if (Test-Path (Join-Path $libRoot 'carafe_spectral_library.tsv')) {
        $libDir = $libRoot
    } else {
        throw ("No library variant '$variant' under '$libRoot', and '$libRoot' is not " +
               "itself a library directory. Build it with New-SeaAdLibrary.ps1 -Ratio $Ratio " +
               "-DecoyMode $DecoyMode, or pass -LibraryDir/-Library explicitly. See $readme.")
    }
}

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

$allMzml = @(Get-ChildItem -Path $dataDir -Filter '*.mzML' -File | Sort-Object Name)
if ($ExcludePattern) {
    $before = $allMzml.Count
    $allMzml = @($allMzml | Where-Object { $_.Name -notmatch $ExcludePattern })
    Write-Host ("  excluded : $($before - $allMzml.Count) file(s) matching '$ExcludePattern'")
}
if ($EveryNthFile -gt 1) {
    $keep = @(0..($allMzml.Count - 1) | Where-Object { $_ % $EveryNthFile -eq 0 })
    $allMzml = @($keep | ForEach-Object { $allMzml[$_] })
    Write-Host ("  every    : $EveryNthFile-th file -> $($allMzml.Count) candidate(s)")
}
$mzmls = @($allMzml | Select-Object -Skip $SkipFirstFiles -First $NumFiles |
           ForEach-Object { $_.FullName })
if ($mzmls.Count -eq 0) { throw "No .mzML files found in '$dataDir'." }
if ($mzmls.Count -lt $NumFiles) {
    throw ("Only $($mzmls.Count) mzML available in '$dataDir' after skipping $SkipFirstFiles, " +
           "need $NumFiles. Convert-SeaAdRaw.ps1 builds them.")
}

# .spectra.bin beside the mzML is the difference between a ~7.5 h run and one that also
# pays ~4.5 min/file of parsing. Worth saying out loud rather than discovering at hour six.
$cached = @(Get-ChildItem -Path $dataDir -Filter '*.spectra.bin' -File).Count

if (-not $OutDir) {
    # Default beside the data: <dataset root>\runs, the layout the original runs used.
    # $dataDir is <root>\Astral-DIA\mzml, so the root is two up.
    $runsRootResolved = if ($RunsRoot) { $RunsRoot } else { Join-Path (Split-Path (Split-Path $dataDir -Parent) -Parent) 'runs' }
    $name = "seaad-$($mzmls.Count)files-$DecoyMode-r$Ratio-$Pass2Mode$Tag"
    if ($Fresh) { $name += '-' + (Get-Date -Format 'yyyyMMdd_HHmmss') }
    $OutDir = [System.IO.Path]::GetFullPath((Join-Path $runsRootResolved $name))
}

# Osprey ADOPTS per-file caches it finds in the output directory, so re-running an arm
# into the same directory silently resumes instead of running from scratch - which is
# invisible in the output and quietly invalidates a from-scratch memory or timing
# measurement. Make the caller say which one they meant.
if ((Test-Path $OutDir) -and @(Get-ChildItem -Path $OutDir -File -ErrorAction SilentlyContinue).Count -gt 0 `
    -and -not $Resume -and -not $LinkFrom) {
    throw ("Output directory already has files: '$OutDir'. Osprey would adopt its caches " +
           "and skip stages. Pass -Fresh for a timestamped from-scratch directory, " +
           "-Resume to deliberately continue this one, or -OutDir to name another.")
}

# --output-dir, NOT --work-dir: --work-dir would also relocate the .spectra.bin cache,
# so a share that already has the caches would rebuild all 82 of them. Artifacts go to
# the run dir; the cache stays beside the input unless -CacheDir says otherwise (which
# is what a genuinely read-only input directory without caches needs).
$blib = Join-Path $OutDir 'out.blib'
$cliArgs = @('-i') + $mzmls + @(
    '-l', $libraryPath,
    '-o', $blib,
    '--resolution', 'hram',
    '--fdr-level', 'precursor',
    '--threads', "$Threads",
    '--timestamp', '--memstamp',
    '--output-dir', $OutDir,
    '--fdrbench', (Join-Path $OutDir 'fdrbench.tsv'), '--fdrbench-pass', $FdrBenchPass
)
if ($CacheDir) { $cliArgs += @('--cache-dir', $CacheDir) }
if ($DecoyMode -eq 'libdecoy') { $cliArgs += @('--decoys-in-library', '--decoy-pairing-manifest', $manifest) }
$mdiag = -not $NoModelDiagnostics
if ($mdiag) { $cliArgs += '--model-diagnostics' }

# Which TREE the binary came from matters as much as which flags ran. A multi-hour run
# against whatever a colleague happens to have built in a shared worktree is measuring
# their mid-refactor branch, not master - and the run holds those DLLs, blocking their
# rebuilds. Both directions of that collision are silent, so name the branch out loud.
$exeBranch = $null
$exeRepo = Split-Path $ospreyExe -Parent
try {
    $exeBranch = (& git -C $exeRepo rev-parse --abbrev-ref HEAD 2>$null)
    if ($LASTEXITCODE -ne 0) { $exeBranch = $null }
} catch { $exeBranch = $null }

Write-Host ""
Write-Host "=== SEA-AD Pilot-MTG run ===" -ForegroundColor Cyan
Write-Host ("  exe      : {0}" -f $ospreyExe)
Write-Host ("  built    : {0}{1}" -f (Get-Item $ospreyExe).LastWriteTime.ToString('yyyy-MM-dd HH:mm'),
            $(if ($exeBranch) { "   branch: $exeBranch" } else { '' }))
if ($exeBranch -and $exeBranch -ne 'master') {
    Write-Host ("  WARNING: that build is branch '{0}', not master. A run this long against " -f $exeBranch) -ForegroundColor Yellow
    Write-Host "           someone else's in-progress build measures their branch, and holds" -ForegroundColor Yellow
    Write-Host "           its DLLs so they cannot rebuild. Pass -SourceRoot <pinned checkout>" -ForegroundColor Yellow
    Write-Host "           to use a tree nobody is actively building in." -ForegroundColor Yellow
}
Write-Host ("  mzML dir : {0}" -f $dataDir)
# The lab-share fallback is a convenience for a one-off, but a multi-hour run reading every
# spectrum over SMB is I/O-bound on the network and silently much slower than local disk -
# and nothing in the output says so, which is how a machine ends up running the whole set
# off the share without anyone noticing. Say it out loud.
if ($dataDir -like '\\\\*' -or (@('A','B','C','D') -notcontains $dataDir[0] -and
    (Get-PSDrive $dataDir[0] -ErrorAction SilentlyContinue).DisplayRoot)) {
    Write-Host ("  WARNING: that is a NETWORK path. Every spectrum read crosses the wire; a" ) -ForegroundColor Yellow
    Write-Host ("           full run will be markedly slower than from local disk. Copy the" ) -ForegroundColor Yellow
    Write-Host ("           mzML + .spectra.bin locally and set `$env:OSPREY_SEAAD_DIR to it" ) -ForegroundColor Yellow
    Write-Host ("           for repeated runs; see the README." ) -ForegroundColor Yellow
}
Write-Host ("  files    : {0}; {1} .spectra.bin cache(s) present" -f $mzmls.Count, $cached)
if ($cached -lt $mzmls.Count) {
    Write-Host "  NOTE: not every file has a spectra cache; expect ~4.5 min/file extra parse." -ForegroundColor Yellow
}
Write-Host ("  library  : {0}" -f $libraryPath)
Write-Host ("  arm      : {0}  r={1}" -f $DecoyMode, $Ratio)
Write-Host ("  pass 2   : {0}   fdrbench pass {1}   model-diagnostics {2}" -f
            $Pass2Mode, $FdrBenchPass, $(if ($mdiag) { 'on' } else { 'OFF' }))
# --fdrbench-pass 1/both asks for a pass-1 TSV that the projection path does not emit
# (Osprey gates the pre-compaction pool on FdrBenchPass == 1 exactly, so the `both`
# bitmask misses it). Say so rather than let an absent file read as a failed run.
if ($FdrBenchPass -ne '2') {
    Write-Host ("  NOTE: --fdrbench-pass {0} currently yields only the pass-2 TSV; the pass-1" -f $FdrBenchPass) -ForegroundColor Yellow
    Write-Host "        pool is not emitted off the projection path. Pass-1 FDP comes from the" -ForegroundColor Yellow
    Write-Host "        --model-diagnostics report instead." -ForegroundColor Yellow
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
    foreach ($f in $mzmls) {
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
# result, so the arms set exactly what they mean and clear the rest.
foreach ($k in 'OSPREY_EXIT_AFTER_CALIBRATION', 'OSPREY_CAL_SAMPLE_SIZE',
               'OSPREY_CAL_MEDIANPOLISH', 'OSPREY_PASS2_QVALUE',
               'OSPREY_DECOY_SAME_ION_MAP', 'OSPREY_DECOY_PRECURSOR_SHIFT_UNITS',
               'OSPREY_DECOY_MAX_FRAG_OVERLAP', 'OSPREY_DECOY_MAX_SEQ_IDENTITY') {
    Remove-Item "Env:\$k" -ErrorAction SilentlyContinue
}
if ($Pass2Mode -ne 'percolator') { $env:OSPREY_PASS2_QVALUE = $Pass2Mode }
# The gendecoy arm's one lever: OSPREY_DECOY_SAME_ION_MAP was the b<->y intensity swap
# fix. The swap was REMOVED from the product on 2026-07-27 (pwiz #4480 / osprey #58), so
# on any build from that day forward same-ion mapping is simply the behaviour and the var
# is a no-op. Kept unset here; set it yourself only when reproducing a pre-fix build.

$log = Join-Path $OutDir 'run.log'
"[{0}] START arm=$DecoyMode r=$Ratio pass2=$Pass2Mode files=$($mzmls.Count) threads=$Threads mdiag=$mdiag linkfrom='$LinkFrom'" -f (Get-Date -Format s) |
    Set-Content -Path $log
"Exe: $ospreyExe" | Add-Content -Path $log
"Library: $libraryPath" | Add-Content -Path $log
"OutDir: $OutDir" | Add-Content -Path $log

Write-Host "Logging to $log" -ForegroundColor Cyan
$sw = [Diagnostics.Stopwatch]::StartNew()
& $ospreyExe @cliArgs *>&1 | Tee-Object -FilePath $log -Append
$exit = $LASTEXITCODE
$sw.Stop()
"[{0}] DONE arm=$DecoyMode r=$Ratio pass2=$Pass2Mode exit=$exit elapsed=$([int]$sw.Elapsed.TotalMinutes)min" -f (Get-Date -Format s) |
    Add-Content -Path $log
Write-Host ("Osprey exited {0} after {1:hh\:mm\:ss}" -f $exit, $sw.Elapsed) `
    -ForegroundColor $(if ($exit -eq 0) { 'Green' } else { 'Red' })
exit $exit
