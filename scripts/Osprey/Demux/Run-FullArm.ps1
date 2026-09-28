# One whole-run arm: A1, D1 and G1 demultiplexed from .wiff2 with the arm's own flags, the three in
# parallel, then one DIA-NN search of the three with the acquired A1 run's settings pinned
# (--window 6 --mass-acc 17 --mass-acc-ms1 19). Run-FullC7Posmz.ps1 is this with centered:7 and
# --position-mz. Output: <run root>\ztscan\full\<Name>\, DIA-NN arm slices\diann\full_<Name> (Demux-Roots.ps1).
param(
    [Parameter(Mandatory)] [string]$Exe,
    [Parameter(Mandatory)] [string]$Name,
    [string]$Flags = '',                # tool flags, space-separated
    [string]$Layout = 'centered:7',
    [string]$DiannExtra = '--window 6 --mass-acc 17 --mass-acc-ms1 19',
    [int]$Threads = 4,
    [int]$DiannThreads = 16
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Demux-Roots.ps1')
$stems = '250814_ZTScan_100spd_A_1_A1', '250814_ZTScan_100spd_A_2_D1', '250814_ZTScan_100spd_A_3_G1'
$out = Join-Path $runRoot "ztscan\full\$Name"
New-Item -ItemType Directory -Force $out | Out-Null
"$(Get-Date -Format HH:mm) ${Name}: $Layout $Flags"
$sw = [Diagnostics.Stopwatch]::StartNew()
$procs = foreach ($stem in $stems) {
    $argv = @('--in', "$dataRoot\ZenoTOF8600-ZTScan\$stem.wiff2", '--out', (Join-Path $out "$stem.mzML"),
        '--kernel', (Join-Path $PSScriptRoot 'kernels\A1_rt3-8.profile.tsv'), '--layout', $Layout, '--threads', "$Threads")
    if ($Flags) { $argv += ($Flags -split ' ') }
    Start-Process -FilePath $Exe -PassThru -NoNewWindow -ArgumentList $argv `
        -RedirectStandardOutput (Join-Path $out "$stem.log") -RedirectStandardError (Join-Path $out "$stem.err")
}
foreach ($p in $procs) { $p.WaitForExit() }
"$(Get-Date -Format HH:mm) demux done in $([math]::Round($sw.Elapsed.TotalSeconds)) s, exits: $(($procs | ForEach-Object { $_.ExitCode }) -join ',')"
if ($procs | Where-Object { $_.ExitCode -ne 0 }) { exit 1 }
$mzml = ($stems | ForEach-Object { Join-Path $out "$_.mzML" }) -join ','
$search = @('-File', (Join-Path $PSScriptRoot 'Search-Slices.ps1'), '-Arm', "full_$Name", '-Mzml', $mzml,
    '-Threads', "$DiannThreads")
if ($DiannExtra) { $search += @('-Extra', $DiannExtra) }
pwsh @search
"$(Get-Date -Format HH:mm) search done"
