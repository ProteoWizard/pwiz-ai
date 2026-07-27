<#
.SYNOPSIS
    Run a series of SEA-AD arms back to back, one at a time.

.DESCRIPTION
    An 82-file run peaks near 50 GB private working set, so only ONE Osprey fits on a
    64 GB box. Every comparison this dataset exists for needs at least two runs, which
    means queueing them rather than launching them together.

    This waits for any Osprey already running to exit, then walks the cross-product of
    -DecoyModes x -Ratios x -Pass2Modes through Run-SeaAd.ps1, sequentially. All arms go
    through the same runner with the same logging, which is what makes them comparable.

    It deliberately does NOT stop on a failed arm: if the first arm dies you still want
    the rest, and a failure is visible in that arm's own run.log and in the chain log.

.PARAMETER WaitForIdle
    Wait for an already-running Osprey to finish before starting. On by default -- the
    normal use is queueing behind a run that is already going.

.PARAMETER MaxWaitHours
    Give up waiting (and run nothing) after this long. Guards against queueing behind a
    hung process forever.

.EXAMPLE
    # The decoy A/B: both arms at the same ratio, which is the only way they compare on IDs.
    .\Invoke-SeaAdChain.ps1 -DecoyModes libdecoy,gendecoy -Ratios 0.1

.EXAMPLE
    # The pass-2 q-value A/B, launched detached behind whatever is running now.
    Start-Process pwsh -ArgumentList '-NoProfile','-File',
      'C:/proj/ai/scripts/Osprey/SEA-AD/Invoke-SeaAdChain.ps1',
      '-Pass2Modes','percolator,transfer' -WindowStyle Hidden
#>
#requires -Version 7
param(
    [string[]]$DecoyModes = @('libdecoy'),
    [string[]]$Ratios = @('1.0'),
    [string[]]$Pass2Modes = @('percolator'),
    [int]$NumFiles = 82,
    [int]$Threads = 30,
    [string]$Tag = '',
    [string]$ChainLog,
    [int]$PollSeconds = 120,
    [int]$MaxWaitHours = 14,
    [switch]$NoWaitForIdle,
    [switch]$Fresh,
    [switch]$Resume,
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
$runner = Join-Path $PSScriptRoot 'Run-SeaAd.ps1'
if (-not (Test-Path $runner)) { throw "Run-SeaAd.ps1 not found beside this script." }

if (-not $ChainLog) {
    $ChainLog = Join-Path $PSScriptRoot ("..\..\..\.tmp\seaad-chain-{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
}
New-Item -ItemType Directory -Force -Path (Split-Path $ChainLog) | Out-Null

function Write-Chain {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format s), $Message
    Write-Host $line
    Add-Content -Path $ChainLog -Value $line
}

$plan = foreach ($d in $DecoyModes) {
    foreach ($r in $Ratios) {
        foreach ($p in $Pass2Modes) {
            [pscustomobject]@{ DecoyMode = $d; Ratio = $r; Pass2Mode = $p }
        }
    }
}
$plan = @($plan)

# Forwarded verbatim to every arm so the whole chain shares one from-scratch/resume
# decision, rather than half of it adopting caches.
$passThrough = @()
if ($Fresh) { $passThrough += '-Fresh' }
if ($Resume) { $passThrough += '-Resume' }

Write-Chain ("chain start: {0} arm(s) at {1} files, threads {2}" -f $plan.Count, $NumFiles, $Threads)
foreach ($a in $plan) { Write-Chain ("  planned: {0} r={1} pass2={2}" -f $a.DecoyMode, $a.Ratio, $a.Pass2Mode) }

if ($WhatIf) {
    foreach ($a in $plan) {
        Write-Host ""
        & pwsh -NoProfile -File $runner -DecoyMode $a.DecoyMode -Ratio $a.Ratio `
            -Pass2Mode $a.Pass2Mode -NumFiles $NumFiles -Threads $Threads -Tag $Tag `
            @passThrough -WhatIf
    }
    Write-Chain "-WhatIf: nothing run."
    return
}

if (-not $NoWaitForIdle) {
    $deadline = (Get-Date).AddHours($MaxWaitHours)
    $waited = $false
    while (Get-Process Osprey -ErrorAction SilentlyContinue) {
        $waited = $true
        if ((Get-Date) -gt $deadline) {
            Write-Chain "ABORT: an Osprey was still running after $MaxWaitHours h; ran nothing."
            exit 1
        }
        Start-Sleep -Seconds $PollSeconds
    }
    if ($waited) { Write-Chain "the running Osprey exited; starting the chain" }
}

$failed = 0
foreach ($a in $plan) {
    Write-Chain ("START {0} r={1} pass2={2}" -f $a.DecoyMode, $a.Ratio, $a.Pass2Mode)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    & pwsh -NoProfile -File $runner -DecoyMode $a.DecoyMode -Ratio $a.Ratio `
        -Pass2Mode $a.Pass2Mode -NumFiles $NumFiles -Threads $Threads -Tag $Tag @passThrough
    $code = $LASTEXITCODE
    $sw.Stop()
    if ($code -ne 0) { $failed++ }
    Write-Chain ("DONE  {0} r={1} pass2={2} exit={3} elapsed={4}min" -f
                 $a.DecoyMode, $a.Ratio, $a.Pass2Mode, $code, [int]$sw.Elapsed.TotalMinutes)
}

Write-Chain ("chain finished: {0} of {1} arm(s) failed" -f $failed, $plan.Count)
exit $failed
