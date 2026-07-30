<#
.SYNOPSIS
    Run a series of Osprey cohort arms serially, one at a time, resumable.

.DESCRIPTION
    Each job is "<files>:<N>[:<skip>]" where N=0 means the max / best-of-runs baseline. For each
    job this launches Run-SeaAd.ps1 with -LinkFrom (so Stage 1-4 caches are adopted and only the
    FDR stage re-runs), waits for the pass-1 model-diagnostics data.json, kills that arm, and
    moves on. Arms whose mdiag already exists are skipped, so re-running fills only what is
    missing.

    -EveryNthFile / -ExcludePattern apply to every job in the invocation and define a
    content-shaped cohort; pair them with -TagPrefix so the arms get their own cohort label
    (e.g. -EveryNthFile 5 -TagPrefix spread yields '-spread17n0', which the Python harvest
    recognises as a distinct cohort rather than a plain 17-file one).

    Harvest with ai/scripts/Osprey/CohortAnalysis/mbn_surface.py (see README.md).

.PARAMETER Jobs
    Job specs, e.g. '40:0','40:2','40:0:30'. N=0 is max; N>=2 sets OSPREY_EXPERIMENT_AGG.

.PARAMETER WaitForLog
    Optional log of a queue this one must run behind. The pattern is ANCHORED on purpose: these
    scripts print the pattern they are waiting for, so an unanchored match would hit the waiting
    script's own line and two Osprey runs would contend.

.EXAMPLE
    pwsh -File ./Run-CohortArms.ps1 -Jobs '20:0','20:2','20:0:20','20:2:20'

.EXAMPLE
    pwsh -File ./Run-CohortArms.ps1 -Jobs '75:0','75:2' -ExcludePattern pool -TagPrefix nopool
#>
#requires -Version 7
# PositionalBinding=$false so a stray value can never slide into the next parameter: with
# positional binding, `-Jobs 20:0 20:2` bound "20:2" to -EveryNthFile and failed obscurely.
[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(Mandatory = $true)] [string[]]$Jobs,
    [int]$EveryNthFile = 1,
    [string]$ExcludePattern = '',
    [string]$TagPrefix = 'f',
    [string]$RunsDir = 'D:\test\Pilot-MTG-Tissue-May2026\runs',
    [string]$LinkFrom = 'D:/test/Pilot-MTG-Tissue-May2026/runs/pass2ab-82file-percolator-5day',
    [string]$DataDir = 'D:/test/Pilot-MTG-Tissue-May2026/Astral-DIA/mzml',
    [string]$LibraryDir = 'D:/test/Pilot-MTG-Tissue-May2026/lib/regression',
    [string]$Exe,
    [string]$VersionOverride = '26.1.1.199',
    [int]$Threads = 30,
    [string]$WaitForLog = '',
    [string]$WaitForPattern = '^=== (QUEUE|JOBS|GRID|CONTENT) ALL DONE'
)
$ErrorActionPreference = 'Continue'
# `pwsh -File script.ps1 -Jobs a,b` hands the whole list over as ONE string, and
# `-Jobs a b` binds only the first - both silently produce a wrong arm (this bit us for real:
# "30:0,30:2,40:0,40:2" parsed as f=30 N=30 and ran a bogus arm). Normalise every form here.
$Jobs = @($Jobs | ForEach-Object { $_ -split '[,\s]+' } | Where-Object { $_ })
$driver = Join-Path $PSScriptRoot '..\SEA-AD\Run-SeaAd.ps1'
if ($VersionOverride) { $env:OSPREY_VERSION_OVERRIDE = $VersionOverride }

# Kill ONLY the arm this queue launched, identified by its output-dir tag. Never blanket-kill
# Osprey: another queue's arm may be mid-run, and losing one costs the whole arm.
function Stop-Arm([string]$armTag) {
    Get-CimInstance Win32_Process -Filter "Name='Osprey.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like "*percolator$armTag*" } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}

if ($WaitForLog) {
    Write-Host "=== QUEUE waiting on $WaitForLog $(Get-Date -Format o) ==="
    while ((Test-Path $WaitForLog) -and
           -not (Select-String -Path $WaitForLog -Pattern $WaitForPattern -Quiet)) {
        Start-Sleep 60
    }
    Start-Sleep 5
}

Write-Host "=== QUEUE START $(Get-Date -Format o) : $($Jobs.Count) arms ==="
$done = 0; $skipped = 0; $failed = 0
foreach ($job in $Jobs) {
    $parts = $job.Split(':')
    $files = [int]$parts[0]
    $n = [int]$parts[1]
    $skip = if ($parts.Count -ge 3) { [int]$parts[2] } else { 0 }

    if ($n -ge 2) { $env:OSPREY_EXPERIMENT_AGG = "mean-best-$n" }
    else { Remove-Item Env:\OSPREY_EXPERIMENT_AGG -ErrorAction SilentlyContinue }

    $tag = "-$TagPrefix$files" + "n$n" + $(if ($skip) { "s$skip" } else { '' })
    $dir = Join-Path $RunsDir "seaad-${files}files-libdecoy-r1.0-percolator$tag"
    $djson = Join-Path $dir 'out.model-diagnostics.data.json'
    if (Test-Path $djson) {
        Write-Host "=== ARM $tag already has mdiag; skipping ==="
        $skipped++
        continue
    }

    Write-Host "=== ARM $tag START $(Get-Date -Format o) ==="
    $a = @('-NoProfile', '-File', $driver, '-DecoyMode', 'libdecoy', '-Ratio', '1.0',
           '-Pass2Mode', 'percolator', '-NumFiles', "$files", '-SkipFirstFiles', "$skip",
           '-Threads', "$Threads", '-FdrBenchPass', '2', '-LinkFrom', $LinkFrom,
           '-DataDir', $DataDir, '-LibraryDir', $LibraryDir, '-Tag', $tag)
    if ($Exe) { $a += @('-Exe', $Exe) }
    if ($EveryNthFile -gt 1) { $a += @('-EveryNthFile', "$EveryNthFile") }
    if ($ExcludePattern) { $a += @('-ExcludePattern', $ExcludePattern) }
    Start-Process pwsh -ArgumentList $a -WindowStyle Hidden `
        -RedirectStandardOutput (Join-Path $RunsDir "arm$tag-launcher.log") `
        -RedirectStandardError  (Join-Path $RunsDir "arm$tag-launcher.err") | Out-Null

    # 3x the measured cost model (~0.38 min/file + 2.5 min), floor 20 min: a hung arm must not
    # eat the night, but a slow large arm must not be killed either.
    $limit = [Math]::Max(1200, [int](3 * (0.38 * $files + 2.5) * 60))
    $waited = 0
    while (-not (Test-Path $djson)) {
        Start-Sleep 20
        $waited += 20
        $alive = @(Get-CimInstance Win32_Process -Filter "Name='Osprey.exe'" -ErrorAction SilentlyContinue |
                   Where-Object { $_.CommandLine -like "*percolator$tag*" }).Count
        if ($alive -eq 0 -and -not (Test-Path $djson)) {
            Write-Host "=== ARM $tag Osprey EXITED WITHOUT data.json $(Get-Date -Format o) ==="
            break
        }
        if ($waited -gt $limit) {
            Write-Host "=== ARM $tag TIMEOUT after $([int]($limit / 60)) min $(Get-Date -Format o) ==="
            break
        }
    }
    if (Test-Path $djson) {
        Write-Host "=== ARM $tag MDIAG WRITTEN $(Get-Date -Format o) ==="
        $done++
    }
    else { $failed++ }
    Stop-Arm $tag
    Start-Sleep 4
}
Write-Host "=== QUEUE ALL DONE done=$done skipped=$skipped failed=$failed $(Get-Date -Format o) ==="
