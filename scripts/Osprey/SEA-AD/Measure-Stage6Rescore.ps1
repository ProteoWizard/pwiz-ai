<#
.SYNOPSIS
    Measure Stage-6 (PerFileRescoring) resident memory as a function of file count.

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
    [string]$SourceRoot,
    [string]$Exe,
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

$counts = @($FileCounts -split '[,\s]+' | Where-Object { $_ } | ForEach-Object {
    $v = 0
    if (-not [int]::TryParse($_, [ref]$v) -or $v -lt 1) { throw "-FileCounts must be positive integers like '4,8,16'; got '$_'." }
    $v
} | Sort-Object -Unique)
if (-not $counts) { throw "-FileCounts resolved to nothing; expected something like '4,8,16'." }

if (-not $WorkRoot) { $WorkRoot = Join-Path (Split-Path $dataDir -Parent) 'stage6' }
$maxN    = ($counts | Measure-Object -Maximum).Maximum
$phaseDir = Join-Path $WorkRoot "stage6-${maxN}files"

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
        Write-Host ("  4. rm *.2nd-pass.fdr_scores.bin *.scores-reconciled.parquet; --task PerFileRescoring --input-scores <{0} parquets> (OSPREY_LOG_MEMORY=1)" -f $n)
    }
    return
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
    param([string[]]$CliArgs, [string]$LogName, [switch]$LogMemory)
    $prev = $env:OSPREY_LOG_MEMORY
    if ($LogMemory) { $env:OSPREY_LOG_MEMORY = '1' }
    Push-Location $phaseDir
    try {
        $sw = [Diagnostics.Stopwatch]::StartNew()
        & $ospreyExe @CliArgs 2>&1 | Out-Null
        $exit = $LASTEXITCODE
        $sw.Stop()
    } finally {
        Pop-Location
        $env:OSPREY_LOG_MEMORY = $prev
    }
    if ($exit -ne 0) { throw "Osprey $($CliArgs[1]) exited $exit (see $(Join-Path $phaseDir $LogName))" }
    return $sw.Elapsed
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
foreach ($n in $counts) {
    Write-Host ("--- Stage 6: PerFileRescoring, {0} files ---" -f $n) -ForegroundColor Cyan
    # The self-gate (PerFileRescoreTask.Run:240-248) turns this task into a no-op when ANY
    # pass-2 sidecar exists. Without this the 2nd..Nth measurement silently does nothing.
    Get-ChildItem $phaseDir -Filter '*.2nd-pass.fdr_scores.bin' -File -ErrorAction SilentlyContinue | Remove-Item -Force
    Get-ChildItem $phaseDir -Filter '*.scores-reconciled.parquet' -File -ErrorAction SilentlyContinue | Remove-Item -Force

    $log = "stage6-${n}f.log"
    $a = @('--task', 'PerFileRescoring') + ((& $scoresFor $n) | ForEach-Object { @('--input-scores', $_.Name) } | ForEach-Object { $_ }) + @(
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
