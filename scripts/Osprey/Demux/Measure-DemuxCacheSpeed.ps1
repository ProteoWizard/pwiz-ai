#requires -Version 7.0
<#
.SYNOPSIS
    Times Osprey --task SpectraCache --demux auto (vendor file to .demux.spectra.bin) for several
    demultiplexer arms, interleaved, a fresh cache every repetition.

.DESCRIPTION
    Each arm is NAME=EXE or NAME=EXE=ENGINE (ENGINE sets OSPREY_DEMUX_ENGINE, #4710 only). Arms run
    round-robin, so a drift in machine load lands on every arm rather than on one. Run on an idle
    machine: no searches, no builds, no nightly. Results go to <Root>\speed.tsv (one row per run,
    wall seconds and peak working set) and each run's osprey.log beside it.

.EXAMPLE
    pwsh -File ai/scripts/Osprey/Demux/Measure-DemuxCacheSpeed.ps1 -Reps 3 -Arms `
        'pwiz=D:\test\osprey-runs\_bin\x\Osprey.exe,pr4710-weighted=D:\...\Osprey.exe=weighted,pr4710-msconvert=D:\...\Osprey.exe=msconvert'
#>
param(
    [Parameter(Mandatory)] [string]$Arms,          # comma-separated NAME=EXE[=ENGINE]
    [int]$Reps = 3,
    [string]$Raw = 'D:\test\osprey-runs\remes-ev\Ecl_2022_0705_Beads_EV13_SAXN_12mz_10.raw',
    [string]$Library = 'D:\test\AstralTest-TargetDecoyLibraries\target+decoy+entrapment\carafe_spectral_library.tsv',
    [string]$Root = 'D:\test\osprey-runs\pwiz-demux\speed',
    [int]$Threads = 0                               # 0 = Osprey's default (all logical processors)
)
$ErrorActionPreference = 'Stop'
$armList = foreach ($a in ($Arms -split ',' | Where-Object { $_ })) {
    $parts = $a -split '='
    if ($parts.Count -lt 2) { throw "Arm '$a' is not NAME=EXE[=ENGINE]" }
    if (-not (Test-Path $parts[1])) { throw "Osprey.exe not found: $($parts[1])" }
    [pscustomobject]@{ Name = $parts[0]; Exe = $parts[1]; Engine = $(if ($parts.Count -gt 2) { $parts[2] } else { '' }) }
}
New-Item -ItemType Directory -Force $Root | Out-Null
$tsv = Join-Path $Root 'speed.tsv'
if (-not (Test-Path $tsv)) { "time`tarm`trep`texit`twall_s`tpeak_ws_gb`texe`tengine" | Set-Content $tsv }

for ($rep = 1; $rep -le $Reps; $rep++) {
    foreach ($arm in $armList) {
        $dir = Join-Path $Root "$($arm.Name)-r$rep"
        Remove-Item -Recurse -Force $dir -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Force (Join-Path $dir 'cache'), (Join-Path $dir 'out') | Out-Null
        foreach ($v in 'OSPREY_DEMUX_ENGINE', 'OSPREY_DEMUX_BLOCK', 'OSPREY_DEMUX_INTERPOLATION',
                'OSPREY_DEMUX_MASS_ERROR_PPM', 'OSPREY_DIAG_SEED', 'OSPREY_MAX_TRAIN_SIZE') {
            Remove-Item "Env:$v" -ErrorAction SilentlyContinue
        }
        if ($arm.Engine) { $env:OSPREY_DEMUX_ENGINE = $arm.Engine }
        $argList = @('-i', $Raw, '-l', $Library, '-o', (Join-Path $dir 'out\output.blib'), '--resolution', 'hram',
            '--decoys-in-library', '--demux', 'auto', '--task', 'SpectraCache',
            '--cache-dir', (Join-Path $dir 'cache'), '--output-dir', (Join-Path $dir 'out'),
            '--timestamp', '--memstamp', '--log-file', (Join-Path $dir 'out\osprey.log'))
        if ($Threads -gt 0) { $argList += @('--threads', "$Threads") }

        $sw = [Diagnostics.Stopwatch]::StartNew()
        $p = Start-Process -FilePath $arm.Exe -ArgumentList $argList -NoNewWindow -PassThru `
            -RedirectStandardOutput (Join-Path $dir 'out\console.log') -RedirectStandardError (Join-Path $dir 'out\console.err')
        $peak = 0
        while (-not $p.HasExited) {
            try { $p.Refresh(); if ($p.PeakWorkingSet64 -gt $peak) { $peak = $p.PeakWorkingSet64 } } catch { }
            Start-Sleep -Milliseconds 250
        }
        $sw.Stop()
        $line = @((Get-Date -Format s), $arm.Name, $rep, $p.ExitCode, ('{0:F1}' -f $sw.Elapsed.TotalSeconds),
            ('{0:F2}' -f ($peak / 1GB)), $arm.Exe, $arm.Engine) -join "`t"
        Add-Content $tsv $line
        Write-Host $line
    }
}
