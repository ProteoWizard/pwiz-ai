<#
.SYNOPSIS
    Measure Stage-6 (PerFileRescoring) and, with -Stage7, Stage-7 (SecondPassFDR)
    resident memory as a function of file count.

.DESCRIPTION
    The characterization harness for GitHub #4472: PerFileRescoreTask holds every file's
    post-compaction survivor FdrEntry lists resident (`_perFileEntries`,
    PerFileRescoreTask.cs:113), so Stage-6 memory is O(files). This script measures that
    slope locally at small file counts instead of waiting 7.5 h for an 82-file run.

    It pays the Stage 1-5 cost ONCE, then re-runs ONLY `--task PerFileRescoring` against
    those artifacts at several file counts. Iteration is minutes, not hours, because the
    rescore worker rehydrates from .scores.parquet and never re-parses an mzML.

    Use it the same way after the fix: the slope should go to ~0 in file count, matching
    what FirstPassFDR now does (PR #4435).

    TWO SILENT TRAPS this script exists to avoid. Both make a broken measurement look
    like a passing one:

    1. ALL FILES IN ONE INVOCATION. The HPC chain (regression.ps1:644) runs this task once
       per stem, so `_perFileEntries` holds exactly ONE file and the band is flat BY
       CONSTRUCTION. Measured that way you would "confirm" a fix that does not exist.
       `--input-scores` takes many parquets (OspreyConfig.InputScores is a List<string>),
       which is what populates the real multi-file buffer.

    2. CLEAR THE PASS-2 SIDECARS BETWEEN REPEATS. PerFileRescoreTask.Run:240-248 self-gates
       to a NO-OP when any *.2nd-pass.fdr_scores.bin is present -- a repeat run then
       measures nothing, prints no error and exits 0. This script deletes them (and the
       reconciled parquets) before every measurement.

    -Stage7 CHAINS THE STAGE-7 MEASUREMENT ONTO EACH POINT (GitHub #4486). Stage 7
    (`--task SecondPassFDR`) is the whole-run memory high point, and every figure that issue
    has ever quoted came from --memstamp, so it has never had a live number. Each file count
    then runs Stage 6 (producing that count's reconciled parquets) and Stage 7 on top of
    them, reporting the post-GC decomposition SecondPassFdrTask now emits:

        stage7-inherited          what Stage 7 is HANDED, before it does any work
        stage7-fragments-released after the library-fragment release
        stage7-pass2-scored       after the 2nd-pass sidecar compute + reload
        stage7-protein-fdr        after parsimony + picked-protein TDC
        stage7-blib-written       after the blib write, i.e. end of stage

    Stage 6 must re-run per point rather than reusing a prefix of a larger run's reconciled
    parquets: reconciliation is a cross-file join, so a file reconciled against 16 files is
    not the file reconciled against 4, and a prefix would understate the slope.

    THREE MORE TRAPS -Stage7 handles, in the same silent-pass family as the two above:

    3. STAGE 7 SELF-GATES ON ITS OWN OUTPUTS. The driver skips a task whose output sidecars
       are already valid, so a repeat measurement against a populated dir exits 0 and
       measures nothing. This deletes output.blib and *.2nd-pass.fdr_scores.bin (and their
       .osprey.task sidecars) before every Stage-7 point.
    4. STAGE 7 IS A REFUSED RESIDENT PATH. --task SecondPassFDR sets ExpectReconciledInput,
       which ResidentPoolTrigger maps to the 'hpc-merge' token, so the run ABORTS unless
       OSPREY_ALLOW_UNFIXED_RESIDENT names it. That refusal is the point of the guard - this
       harness measures the path the token admits, so it sets the token for the Stage-7 leg
       only, and never for the Stage-6 leg (which must stream).
    5. --input-scores TAKES THE RECONCILED PARQUETS. Stage 7 hard-fails on a raw Stage-4
       parquet (osprey.reconciled != "true"), which reads like a harness bug and is not.

    -Stage7 AND -StraightThrough MEASURE DIFFERENT ARMS, AND CONFLATING THEM IS THE EASIEST
    MISTAKE HERE. `--task SecondPassFDR` is the HPC node: it reloads every input file's FULL
    PRE-COMPACTION stub list before compacting, which is the resident pool the 'hpc-merge'
    token names and warns about in the run log. The straight-through pipeline never does
    that - Stage 6 hands Stage 7 the already-compacted buffer in memory. So the two arms
    have different peaks by construction, and the 82-file figures quoted on #4486 are all
    straight-through. -StraightThrough runs Stages 5-7 in one process off the cached Stage
    1-4 artifacts, which is the comparable measurement.

    WHY THE POST-GC PROBE, NOT --memstamp. `--memstamp` reports GC.GetTotalMemory(false),
    which includes uncollected garbage; ProfilerHooks' own docs note two identical runs can
    differ by tens of GB on whether a gen-2 landed before the sample. #4472's slope is a
    LIVE structure, explicitly distinguished from the Server-GC committed "gray" of #4404,
    so the headline number here is the post-GC `[MEM reconciliation-resident] managed_heap=`
    probe (PerFileRescoreTask.cs:593), enabled by OSPREY_LOG_MEMORY. The memstamp trace is
    still captured for ai/scripts/perfviz.html.

.PARAMETER FileCounts
    File counts to measure, e.g. 4,8,16. Artifacts are prepared once for the LARGEST value
    and each smaller count reuses a prefix of them, so extra points cost only a rescore.

.PARAMETER Prepare
    Force the Stage 1-5 preparation even when artifacts already look complete.

.PARAMETER MemoryProfile
    Leave OSPREY_LOG_MEMORY on and print the dotMemory command for the largest count,
    rather than running the sweep. Use when the slope is confirmed and you need to see
    WHICH objects are retained.

.PARAMETER WhatIf
    Resolve everything, print the plan and the exact command lines, then stop.

.EXAMPLE
    # Baseline the slope on master before changing anything.
    .\Measure-Stage6Rescore.ps1 -FileCounts 4,8,16 -WhatIf
    .\Measure-Stage6Rescore.ps1 -FileCounts 4,8,16

.EXAMPLE
    # After the fix: same command, same artifacts. Slope should be ~flat.
    .\Measure-Stage6Rescore.ps1 -FileCounts 4,8,16

.EXAMPLE
    # #4486: the live Stage-7 decomposition and its slope, against the rig #4536 left behind.
    .\Measure-Stage6Rescore.ps1 -Stage7 -FileCounts 4,8,16 `
        -PhaseDir 'D:\test\Pilot-MTG-Tissue-May2026\Astral-DIA\runs\stage6\stage6-16files' `
        -LibraryDir 'D:\test\Pilot-MTG-Tissue-May2026\lib\regression'
#>
#requires -Version 7
param(
    # Deliberately a STRING, not int[]. Through `pwsh -File` (how the README launches these
    # scripts) an array argument arrives as the single token "4,8,16", which PowerShell
    # coerces to an int by reading the commas as thousands separators -- 4816. Parsing it
    # here behaves identically whether called in-process or via -File.
    [string]$FileCounts = '4,8,16',
    [int]$Threads = 30,
    [string]$DataDir,
    [string]$LibraryDir,
    [string]$Ratio = '1.0',
    [string]$WorkRoot,
    # Use an EXISTING phase dir instead of one named for the largest count. Lets a big
    # prep (say 82 files) serve smaller measurements without re-preparing, since each
    # count just takes the first N parquets.
    [string]$PhaseDir,
    [string]$SourceRoot,
    [string]$Exe,
    # Osprey stamps a daily version (YEAR.ORDINAL.BRANCH.DOY) into every .scores.parquet and
    # REFUSES to consume one written by a different daily build. Preparing artifacts on one
    # day and measuring on the next therefore hard-fails with "osprey version mismatch",
    # which looks like a code bug and is not. Pin the version for every Osprey call in the
    # run, the same trick regression.ps1 uses (it pins 26.1.1.0) to keep its committed golden
    # comparable across days. Default: auto-detect from the prepared artifacts.
    [string]$VersionOverride,
    # Run the measured stage with --model-diagnostics. The mdiag report is built from the
    # PRE-compaction entries, so it is the case most likely to reintroduce an O(files) hold;
    # measuring with it ON is the only way to show the streaming feed is actually bounded.
    [switch]$ModelDiagnostics,
    # Chain a `--task SecondPassFDR` measurement onto every file count (#4486). See the
    # -Stage7 block in .DESCRIPTION for the three additional traps this arms.
    [switch]$Stage7,
    # Measure the STRAIGHT-THROUGH arm instead: one process runs Stages 5-7 off the cached
    # Stage 1-4 artifacts, so Stage 7 receives the in-memory handoff rather than reloading
    # every file's pre-compaction stub list. This is the arm the 82-file figures on #4486
    # came from, and it is NOT what -Stage7 measures - see .DESCRIPTION.
    [switch]$StraightThrough,
    [switch]$Prepare,
    # Build the Stage 1-5 artifacts and stop. Stage 1-5 is UPSTREAM of Stage 6, so its
    # artifacts are valid for any build whose changes are confined to Stage 6 -- prepare
    # once with today's binary, then measure repeatedly with a modified one.
    [switch]$PrepareOnly,
    [switch]$MemoryProfile,
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$readme = Join-Path $PSScriptRoot 'README.md'

$LAB_SHARE_MZML = 'M:\home\brendanx\data\MacCoss\SEA-AD\Astral-DIA\mzml'
$REPO_EXE = Join-Path $PSScriptRoot '..\..\..\..\pwiz\pwiz_tools\Osprey\Osprey\bin\x64\Release\net8.0\Osprey.exe'

# Same resolution contract as Run-SeaAd.ps1: a location you NAME must exist, so a typo
# fails here instead of silently searching the wrong tree.
function Resolve-Location {
    param([string]$Explicit, [string]$EnvName, [string[]]$Fallbacks, [string]$What)
    $envValue = [Environment]::GetEnvironmentVariable($EnvName)
    foreach ($named in @(@{ V = $Explicit; S = 'parameter' }, @{ V = $envValue; S = "`$env:$EnvName" })) {
        if ($named.V) {
            if (-not (Test-Path $named.V)) { throw "The SEA-AD $What given by $($named.S) does not exist: '$($named.V)'." }
            return (Resolve-Path $named.V).Path
        }
    }
    foreach ($f in $Fallbacks) {
        if ($f -and (Test-Path $f)) { return (Resolve-Path $f).Path }
    }
    throw "Could not resolve the SEA-AD $What. Set `$env:$EnvName or pass the parameter; see $readme."
}

if ($SourceRoot) { $Exe = Join-Path $SourceRoot 'pwiz_tools\Osprey\Osprey\bin\x64\Release\net8.0\Osprey.exe' }
$ospreyExe = Resolve-Location -Explicit $Exe -EnvName 'OSPREY_EXE' -Fallbacks @($REPO_EXE) -What 'Osprey.exe'
$dataDir   = Resolve-Location -Explicit $DataDir -EnvName 'OSPREY_SEAAD_DIR' -Fallbacks @($LAB_SHARE_MZML) -What 'mzML directory'
$libRoot   = Resolve-Location -Explicit $LibraryDir -EnvName 'OSPREY_SEAAD_LIB' -Fallbacks @() -What 'library directory'

$variant = if ($Ratio -eq '1.0') { 'target+decoy+entrapment' } else { "target+decoy+entrapment-r$Ratio" }
$libDir  = Join-Path $libRoot $variant
if (-not (Test-Path $libDir)) { throw "Library variant '$variant' not found under '$libRoot'. Build it with New-SeaAdLibrary.ps1 -Ratio $Ratio; see $readme." }
$libPath      = Join-Path $libDir 'carafe_spectral_library.tsv'
$manifestPath = Join-Path $libDir 'osprey_library_db_pairing.tsv'
foreach ($p in @($libPath, $manifestPath)) {
    if (-not (Test-Path $p)) { throw "Missing '$p' in library variant '$variant'; see $readme." }
}

if ($Stage7 -and $StraightThrough) {
    throw '-Stage7 and -StraightThrough measure different arms of Stage 7 and cannot be combined: the straight-through run already performs Stage 7 in-process. Run them separately and compare the logs.'
}

$counts = @($FileCounts -split '[,\s]+' | Where-Object { $_ } | ForEach-Object {
    $v = 0
    if (-not [int]::TryParse($_, [ref]$v) -or $v -lt 1) { throw "-FileCounts must be positive integers like '4,8,16'; got '$_'." }
    $v
} | Sort-Object -Unique)
if (-not $counts) { throw "-FileCounts resolved to nothing; expected something like '4,8,16'." }

# Same output root Run-SeaAd.ps1 uses and the README documents: <dataset root>\runs\.
# Do NOT invent a sibling ("stage6\", "_runs\"): someone looking for a run on another
# machine should find every one of them in one predictable place.
if (-not $WorkRoot) { $WorkRoot = Join-Path (Join-Path (Split-Path $dataDir -Parent) 'runs') 'stage6' }
$maxN    = ($counts | Measure-Object -Maximum).Maximum
$phaseDir = if ($PhaseDir) {
    if (-not (Test-Path $PhaseDir)) { throw "-PhaseDir does not exist: '$PhaseDir'." }
    (Resolve-Path $PhaseDir).Path
} else {
    Join-Path $WorkRoot "stage6-${maxN}files"
}

# Resolve the version to pin (see -VersionOverride). Auto-detect from the prep log that
# actually wrote these artifacts, so a measurement run on a later day still matches them.
$script:versionPin = $VersionOverride
if (-not $script:versionPin) {
    $prepLog = Join-Path $phaseDir 'phase1-scoring.log'
    if (Test-Path $prepLog) {
        # The banner is "Osprey v26.1.1.218 (4a8d660c59)" - the 'v' is NOT optional in
        # practice, and an earlier pattern here omitted it, so auto-detect silently found
        # nothing and every cross-day measurement hard-failed on "osprey version mismatch".
        # That failure reads like a code bug, which is exactly what pinning exists to avoid.
        $m = Select-String -Path $prepLog -Pattern 'osprey_version[=: ]+(\d+\.\d+\.\d+\.\d+)|Osprey v?(\d+\.\d+\.\d+\.\d+)' |
             Select-Object -First 1
        if ($m) { $script:versionPin = ($m.Matches[0].Groups | Where-Object { $_.Success -and $_.Value -match '^\d+\.\d+\.\d+\.\d+$' } | Select-Object -First 1).Value }
    }
}
if ($script:versionPin) { Write-Host ("  version   : pinned {0} (matches the prepared artifacts)" -f $script:versionPin) }
else { Write-Host '  version   : NOT pinned - artifacts prepared on another day will be refused' -ForegroundColor Yellow }

$mzmls = @(Get-ChildItem $dataDir -Filter *.mzML -File | Sort-Object Name | Select-Object -First $maxN)
if ($mzmls.Count -lt $maxN) { throw "Need $maxN mzML in '$dataDir' but found $($mzmls.Count); see $readme." }

Write-Host '=== Stage-6 rescore memory sweep (#4472) ===' -ForegroundColor Cyan
Write-Host ("  exe       : {0}" -f $ospreyExe)
Write-Host ("  mzML dir  : {0}  ({1} files selected)" -f $dataDir, $mzmls.Count)
Write-Host ("  library   : {0}" -f $libPath)
Write-Host ("  phase dir : {0}" -f $phaseDir)
Write-Host ("  counts    : {0}" -f ($counts -join ', '))

# Stage inputs by HARD LINK. The regression's HPC chain copies because it simulates
# separate machines; here the caches alone are ~4 GB/file, so copying 16 of them would be
# ~64 GB of pointless I/O. Falls back to a real copy across volumes.
function Add-StagedFile {
    param([string]$Src, [string]$DestDir)
    $dest = Join-Path $DestDir (Split-Path $Src -Leaf)
    if (Test-Path $dest) { return }
    try { New-Item -ItemType HardLink -Path $dest -Target $Src -ErrorAction Stop | Out-Null }
    catch { Copy-Item $Src $dest }
}

$scoresFor = { param($n) @(Get-ChildItem $phaseDir -Filter *.scores.parquet -File | Sort-Object Name | Select-Object -First $n) }

$prepArgs1 = @('--task', 'PerFileScoring') + ($mzmls | ForEach-Object { @('-i', $_.Name) } | ForEach-Object { $_ }) + @(
    '-l', (Split-Path $libPath -Leaf), '-o', 'output.blib', '--resolution', 'hram',
    '--decoys-in-library', '--decoy-pairing-manifest', (Split-Path $manifestPath -Leaf),
    '--protein-fdr', '0.01', '--threads', $Threads.ToString(),
    '--timestamp', '--memstamp', '--perf-stats', '--log-file', 'phase1-scoring.log')

if ($WhatIf) {
    Write-Host ''
    Write-Host '-WhatIf: not running. Plan:' -ForegroundColor Yellow
    Write-Host ("  1. hard-link {0} mzML + .spectra.bin + library into the phase dir" -f $maxN)
    Write-Host ('  2. ' + (Split-Path $ospreyExe -Leaf) + ' ' + ($prepArgs1 -join ' '))
    Write-Host '  3. --task FirstPassFDR --input-scores <all> ...'
    foreach ($n in $counts) {
        if ($StraightThrough) {
            Write-Host ("  4. rm Stage 5-7 outputs (1st-pass/reconciliation/reconciled/2nd-pass/blib); -i <{0} mzML> with no --task, i.e. Stages 5-7 in one process (OSPREY_LOG_MEMORY=1, no resident token)" -f $n)
            continue
        }
        Write-Host ("  4. rm *.2nd-pass.fdr_scores.bin *.scores-reconciled.parquet; --task PerFileRescoring --input-scores <{0} parquets> (OSPREY_LOG_MEMORY=1)" -f $n)
        if ($Stage7) {
            Write-Host ("  5. rm output.blib* *.2nd-pass.fdr_scores.bin*; --task SecondPassFDR --input-scores <{0} reconciled parquets> (OSPREY_LOG_MEMORY=1, OSPREY_ALLOW_UNFIXED_RESIDENT=hpc-merge)" -f $n)
        }
    }
    return
}

if ($StraightThrough) {
    Write-Host ''
    Write-Host '-StraightThrough: Stage 1-4 artifacts are reused; Stage 5-7 outputs are cleared per point.' -ForegroundColor DarkGray
}

New-Item -ItemType Directory -Path $phaseDir -Force | Out-Null
foreach ($m in $mzmls) {
    Add-StagedFile -Src $m.FullName -DestDir $phaseDir
    $cache = Join-Path $dataDir ($m.BaseName + '.spectra.bin')
    if (Test-Path $cache) { Add-StagedFile -Src $cache -DestDir $phaseDir }
}
foreach ($p in @($libPath, ($libPath + '.libcache'), $manifestPath)) {
    if (Test-Path $p) { Add-StagedFile -Src $p -DestDir $phaseDir }
}

function Invoke-OspreyTask {
    # -AllowResident names a ResidentPaths token for the ONE leg that needs it. Scoped to a
    # single call rather than exported once at the top, so a Stage-6 leg can never inherit
    # it: Stage 6 must stream, and a blanket token would let a regression back onto the
    # resident handoff pass green. Same argument regression.ps1 makes for stripping an
    # ambient token from every leg of the gate.
    param([string[]]$CliArgs, [string]$LogName, [switch]$LogMemory, [string]$AllowResident)
    $prev = $env:OSPREY_LOG_MEMORY
    $prevVer = $env:OSPREY_VERSION_OVERRIDE
    $prevResident = $env:OSPREY_ALLOW_UNFIXED_RESIDENT
    if ($LogMemory) { $env:OSPREY_LOG_MEMORY = '1' }
    if ($script:versionPin) { $env:OSPREY_VERSION_OVERRIDE = $script:versionPin }
    $env:OSPREY_ALLOW_UNFIXED_RESIDENT = $AllowResident
    Push-Location $phaseDir
    try {
        $sw = [Diagnostics.Stopwatch]::StartNew()
        & $ospreyExe @CliArgs 2>&1 | Out-Null
        $exit = $LASTEXITCODE
        $sw.Stop()
    } finally {
        Pop-Location
        $env:OSPREY_LOG_MEMORY = $prev
        $env:OSPREY_VERSION_OVERRIDE = $prevVer
        $env:OSPREY_ALLOW_UNFIXED_RESIDENT = $prevResident
    }
    if ($exit -ne 0) { throw "Osprey $($CliArgs[1]) exited $exit (see $(Join-Path $phaseDir $LogName))" }
    return $sw.Elapsed
}

# Post-GC live-set probes: "[MEM <label>] managed_heap=<n> GB ...". Returns $null when the
# label is absent, which the caller reports rather than silently rendering as 0.
function Get-ProbeGB {
    param([string[]]$Lines, [string]$Label)
    $m = $Lines | Select-String -Pattern ("\[MEM {0}\] managed_heap=([\d.]+) GB" -f [regex]::Escape($Label)) |
         Select-Object -Last 1
    if (-not $m) { return $null }
    return [double]$m.Matches.Groups[1].Value
}

$needPrep = $Prepare -or (& $scoresFor $maxN).Count -lt $maxN -or
            -not (Get-ChildItem $phaseDir -Filter *.1st-pass.fdr_scores.bin -File -ErrorAction SilentlyContinue)
if ($needPrep) {
    Write-Host '--- Stage 1-4: PerFileScoring (one time) ---' -ForegroundColor Cyan
    $t = Invoke-OspreyTask -CliArgs $prepArgs1 -LogName 'phase1-scoring.log'
    Write-Host ("    done in {0:hh\:mm\:ss}" -f $t)

    Write-Host '--- Stage 5: FirstPassFDR (one time) ---' -ForegroundColor Cyan
    $p2 = @('--task', 'FirstPassFDR') + ((& $scoresFor $maxN) | ForEach-Object { @('--input-scores', $_.Name) } | ForEach-Object { $_ }) + @(
        '-l', (Split-Path $libPath -Leaf), '-o', 'output.blib', '--resolution', 'hram',
        '--decoys-in-library', '--decoy-pairing-manifest', (Split-Path $manifestPath -Leaf),
        '--protein-fdr', '0.01', '--threads', $Threads.ToString(),
        '--timestamp', '--memstamp', '--perf-stats', '--log-file', 'phase2-firstpass.log')
    $t = Invoke-OspreyTask -CliArgs $p2 -LogName 'phase2-firstpass.log'
    Write-Host ("    done in {0:hh\:mm\:ss}" -f $t)
} else {
    Write-Host '--- Stage 1-5 artifacts present; skipping preparation (-Prepare forces) ---' -ForegroundColor DarkGray
}

if ($PrepareOnly) {
    $n = @(Get-ChildItem $phaseDir -Filter *.scores.parquet -File).Count
    $s = @(Get-ChildItem $phaseDir -Filter *.1st-pass.fdr_scores.bin -File).Count
    Write-Host ''
    Write-Host ("Stage 1-5 artifacts ready in {0}: {1} scores.parquet, {2} 1st-pass sidecars." -f $phaseDir, $n, $s) -ForegroundColor Green
    Write-Host 'Measure with: .\Measure-Stage6Rescore.ps1 -FileCounts <n> (same -WorkRoot)'
    return
}

if ($MemoryProfile) {
    Write-Host ''
    Write-Host 'dotMemory: run the largest count under the profiler and read the' -ForegroundColor Yellow
    Write-Host "retention snapshot captured at the 'reconciliation-resident' boundary:" -ForegroundColor Yellow
    Write-Host ("  pwsh -File ai/scripts/Osprey/Profile-Osprey.ps1 -MemoryProfile -Exe '{0}' -WorkDir '{1}'" -f $ospreyExe, $phaseDir)
    return
}

$results = @()
$stage7Results = @()
foreach ($n in $counts) {
    if ($StraightThrough) {
        Write-Host ("--- Straight-through: Stages 5-7 in one process, {0} files ---" -f $n) -ForegroundColor Cyan
        # Everything Stage 5 and later produces has to go, or the driver resumes past the
        # stages being measured and the run reports a peak it never reached. The Stage 1-4
        # artifacts (.scores.parquet, .calibration.json, .spectra.bin) deliberately STAY -
        # they cost 55 minutes to rebuild and are upstream of everything measured here.
        foreach ($pattern in @('*.1st-pass.fdr_scores.bin*', '*.1st-pass.model.json',
                               '*.reconciliation.json*', '*.scores-reconciled.parquet*',
                               '*.2nd-pass.fdr_scores.bin*', 'output.blib*')) {
            Get-ChildItem $phaseDir -Filter $pattern -File -ErrorAction SilentlyContinue | Remove-Item -Force
        }
        $logSt = "straight-${n}f.log"
        $mdiagSt = if ($ModelDiagnostics) { @('--model-diagnostics') } else { @() }
        $aSt = @() + (($mzmls | Select-Object -First $n) | ForEach-Object { @('-i', $_.Name) } | ForEach-Object { $_ }) + $mdiagSt + @(
            '-l', (Split-Path $libPath -Leaf), '-o', 'output.blib', '--resolution', 'hram',
            '--decoys-in-library', '--decoy-pairing-manifest', (Split-Path $manifestPath -Leaf),
            '--protein-fdr', '0.01', '--threads', $Threads.ToString(),
            '--timestamp', '--memstamp', '--perf-stats', '--log-file', $logSt)
        # No -AllowResident: the straight-through arm must not need a token. If it starts
        # demanding one, that is a resident regression to fix, and failing here says so.
        $wallSt = Invoke-OspreyTask -CliArgs $aSt -LogName $logSt -LogMemory

        $linesSt = Get-Content (Join-Path $phaseDir $logSt)
        $writtenSt = ($linesSt | Select-String -Pattern 'Wrote (\d+) library spectra' |
                      ForEach-Object { [int]$_.Matches.Groups[1].Value } | Select-Object -Last 1)
        # Peak working set from the --memstamp trace's second column, i.e. the same
        # category of number as the "45 GB private" figure #4486 was filed on.
        $peakWs = ($linesSt | ForEach-Object { ($_ -split "`t")[2] } |
                   Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ } |
                   Measure-Object -Maximum).Maximum
        $stage7Results += [pscustomobject]@{
            Files       = $n
            Stage6GB    = Get-ProbeGB -Lines $linesSt -Label 'reconciliation-resident'
            InheritedGB = Get-ProbeGB -Lines $linesSt -Label 'stage7-inherited'
            FragRelGB   = Get-ProbeGB -Lines $linesSt -Label 'stage7-fragments-released'
            Pass2GB     = Get-ProbeGB -Lines $linesSt -Label 'stage7-pass2-scored'
            ProteinGB   = Get-ProbeGB -Lines $linesSt -Label 'stage7-protein-fdr'
            BlibGB      = Get-ProbeGB -Lines $linesSt -Label 'stage7-blib-written'
            PeakWsGB    = [math]::Round($peakWs / 1024.0, 2)
            Spectra     = $writtenSt
            WallSec     = [int]$wallSt.TotalSeconds
        }
        $lastSt = $stage7Results[-1]
        Write-Host ("    stage6 {0} GB -> inherited {1} GB -> blib {2} GB   peak_ws {3} GB   spectra {4}   {5:hh\:mm\:ss}" `
            -f $lastSt.Stage6GB, $lastSt.InheritedGB, $lastSt.BlibGB, $lastSt.PeakWsGB, $writtenSt, $wallSt)
        continue
    }

    Write-Host ("--- Stage 6: PerFileRescoring, {0} files ---" -f $n) -ForegroundColor Cyan
    # The self-gate (PerFileRescoreTask.Run:240-248) turns this task into a no-op when ANY
    # pass-2 sidecar exists. Without this the 2nd..Nth measurement silently does nothing.
    Get-ChildItem $phaseDir -Filter '*.2nd-pass.fdr_scores.bin' -File -ErrorAction SilentlyContinue | Remove-Item -Force
    Get-ChildItem $phaseDir -Filter '*.scores-reconciled.parquet' -File -ErrorAction SilentlyContinue | Remove-Item -Force

    $log = if ($ModelDiagnostics) { "stage6-${n}f-mdiag.log" } else { "stage6-${n}f.log" }
    $mdiagArgs = if ($ModelDiagnostics) { @('--model-diagnostics') } else { @() }
    $a = @('--task', 'PerFileRescoring') + ((& $scoresFor $n) | ForEach-Object { @('--input-scores', $_.Name) } | ForEach-Object { $_ }) + $mdiagArgs + @(
        '-l', (Split-Path $libPath -Leaf), '-o', 'output.blib', '--resolution', 'hram',
        '--decoys-in-library', '--decoy-pairing-manifest', (Split-Path $manifestPath -Leaf),
        '--protein-fdr', '0.01', '--threads', $Threads.ToString(),
        '--timestamp', '--memstamp', '--perf-stats', '--log-file', $log)
    $wall = Invoke-OspreyTask -CliArgs $a -LogName $log -LogMemory

    $logPath = Join-Path $phaseDir $log
    $lines = Get-Content $logPath
    # Post-GC live-set probe: the number that answers "will this fit".
    $resident = ($lines | Select-String -Pattern '\[MEM reconciliation-resident\] managed_heap=([\d.]+) GB' |
                 ForEach-Object { [double]$_.Matches.Groups[1].Value } | Measure-Object -Maximum).Maximum
    # Guard against the no-op: a real rescore always reports its entry count.
    $rescored = ($lines | Select-String -Pattern 'Reconciliation rescore: (\d+) entries' |
                 ForEach-Object { [int]$_.Matches.Groups[1].Value } | Select-Object -Last 1)
    $results += [pscustomobject]@{
        Files = $n; ResidentGB = $resident; Rescored = $rescored; WallSec = [int]$wall.TotalSeconds
    }
    Write-Host ("    resident {0} GB   rescored {1}   {2:hh\:mm\:ss}" -f $resident, $rescored, $wall)

    if (-not $Stage7) { continue }

    Write-Host ("--- Stage 7: SecondPassFDR, {0} files ---" -f $n) -ForegroundColor Cyan
    # Stage 7 self-gates on ITS OWN outputs the way Stage 6 does on the pass-2 sidecars:
    # the driver skips a task whose output sidecar is already valid, so a second point
    # would exit 0 having measured nothing. The .osprey.task stamps go with the outputs -
    # deleting the blib alone leaves the stamp that declares it current.
    foreach ($pattern in @('output.blib*', '*.2nd-pass.fdr_scores.bin*')) {
        Get-ChildItem $phaseDir -Filter $pattern -File -ErrorAction SilentlyContinue | Remove-Item -Force
    }
    $reconciled = @(Get-ChildItem $phaseDir -Filter *.scores-reconciled.parquet -File | Sort-Object Name)
    if ($reconciled.Count -ne $n) {
        throw ("Stage 6 left {0} reconciled parquets for a {1}-file point in '{2}'. Stage 7 " +
               "must consume exactly the files Stage 6 reconciled together, so this is not " +
               "safe to measure." -f $reconciled.Count, $n, $phaseDir)
    }

    $log7 = if ($ModelDiagnostics) { "stage7-${n}f-mdiag.log" } else { "stage7-${n}f.log" }
    $a7 = @('--task', 'SecondPassFDR') + ($reconciled | ForEach-Object { @('--input-scores', $_.Name) } | ForEach-Object { $_ }) + $mdiagArgs + @(
        '-l', (Split-Path $libPath -Leaf), '-o', 'output.blib', '--resolution', 'hram',
        '--decoys-in-library', '--decoy-pairing-manifest', (Split-Path $manifestPath -Leaf),
        '--protein-fdr', '0.01', '--threads', $Threads.ToString(),
        '--timestamp', '--memstamp', '--perf-stats', '--log-file', $log7)
    # 'hpc-merge' is the ResidentPaths token for ExpectReconciledInput; without it the run
    # is refused outright. Granted here and nowhere else - see Invoke-OspreyTask.
    $wall7 = Invoke-OspreyTask -CliArgs $a7 -LogName $log7 -LogMemory -AllowResident 'hpc-merge'

    $lines7 = Get-Content (Join-Path $phaseDir $log7)
    # Guard against a silent no-op the same way the Stage-6 point does: a real Stage 7
    # always reports what it wrote to the blib.
    $written = ($lines7 | Select-String -Pattern 'Wrote (\d+) library spectra' |
                ForEach-Object { [int]$_.Matches.Groups[1].Value } | Select-Object -Last 1)
    $stage7Results += [pscustomobject]@{
        Files       = $n
        InheritedGB = Get-ProbeGB -Lines $lines7 -Label 'stage7-inherited'
        FragRelGB   = Get-ProbeGB -Lines $lines7 -Label 'stage7-fragments-released'
        Pass2GB     = Get-ProbeGB -Lines $lines7 -Label 'stage7-pass2-scored'
        ProteinGB   = Get-ProbeGB -Lines $lines7 -Label 'stage7-protein-fdr'
        BlibGB      = Get-ProbeGB -Lines $lines7 -Label 'stage7-blib-written'
        Spectra     = $written
        WallSec     = [int]$wall7.TotalSeconds
    }
    $last = $stage7Results[-1]
    Write-Host ("    inherited {0} GB -> pass2 {1} GB -> blib {2} GB   spectra {3}   {4:hh\:mm\:ss}" `
        -f $last.InheritedGB, $last.Pass2GB, $last.BlibGB, $written, $wall7)
}

Write-Host ''
Write-Host '=== Stage-6 resident memory vs file count ===' -ForegroundColor Cyan
$results | Format-Table -AutoSize
foreach ($r in $results) {
    if (-not $r.Rescored) {
        Write-Host ("WARNING: {0}-file run rescored 0 entries -- the self-gate no-op fired; the number above is meaningless." -f $r.Files) -ForegroundColor Red
    }
}
if ($results.Count -ge 2 -and ($results | Where-Object { $_.ResidentGB })) {
    $a = $results[0]; $b = $results[-1]
    if ($b.Files -ne $a.Files -and $a.ResidentGB -and $b.ResidentGB) {
        $slope = ($b.ResidentGB - $a.ResidentGB) / ($b.Files - $a.Files)
        Write-Host ("slope: {0:F3} GB/file  ->  500-file projection {1:F1} GB" -f $slope, ($b.ResidentGB + $slope * (500 - $b.Files)))
        Write-Host 'Goal: slope ~0 (flat in files), as FirstPassFDR is after PR #4435.'
    }
}

if ($stage7Results.Count) {
    Write-Host ''
    $arm = if ($StraightThrough) { 'straight-through' } else { '--task SecondPassFDR (hpc-merge)' }
    Write-Host ("=== Stage-7 live set vs file count (post-GC, #4486, arm: {0}) ===" -f $arm) -ForegroundColor Cyan
    $stage7Results | Format-Table -AutoSize
    foreach ($r in $stage7Results) {
        if (-not $r.Spectra) {
            Write-Host ("WARNING: {0}-file Stage 7 wrote 0 library spectra -- the task self-gated; the numbers above are meaningless." -f $r.Files) -ForegroundColor Red
        }
        if ($null -eq $r.InheritedGB) {
            Write-Host ("WARNING: {0}-file Stage 7 logged no [MEM stage7-inherited] probe. Either OSPREY_LOG_MEMORY did not reach the process, or this binary predates the probes." -f $r.Files) -ForegroundColor Red
        }
    }
    # Two slopes, because they answer different questions. INHERITED is what Stage 7 is
    # handed and can only be moved upstream; BLIB minus INHERITED is what Stage 7 itself
    # adds, which is the only part a lever inside SecondPassFdrTask could remove.
    $withProbe = @($stage7Results | Where-Object { $null -ne $_.InheritedGB -and $null -ne $_.BlibGB })
    if ($withProbe.Count -ge 2) {
        $a7 = $withProbe[0]; $b7 = $withProbe[-1]
        $dFiles = $b7.Files - $a7.Files
        if ($dFiles -ne 0) {
            $slopeIn = ($b7.InheritedGB - $a7.InheritedGB) / $dFiles
            $slopeOwn = (($b7.BlibGB - $b7.InheritedGB) - ($a7.BlibGB - $a7.InheritedGB)) / $dFiles
            Write-Host ("inherited slope: {0:F3} GB/file  ->  163-file projection {1:F1} GB" `
                -f $slopeIn, ($b7.InheritedGB + $slopeIn * (163 - $b7.Files)))
            Write-Host ("stage-7 own slope: {0:F3} GB/file (blib - inherited)" -f $slopeOwn)
            Write-Host 'A lever inside SecondPassFdrTask can only move the second one.'
        }
    }
}
