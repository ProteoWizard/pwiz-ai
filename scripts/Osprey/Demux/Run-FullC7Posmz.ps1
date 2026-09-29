# The best slice arm over whole runs: A1, D1 and G1 demultiplexed from .wiff2 (centered:7, --position-mz),
# the three in parallel, then one DIA-NN search of the three with the acquired A1 run's settings pinned
# (--window 6 --mass-acc 17 --mass-acc-ms1 19). Output: <run root>\ztscan\full\cs_centered7_posmz,
# DIA-NN arm slices\diann\full_cs_centered7_posmz_fixed (Demux-Roots.ps1).
param(
    [string]$Exe = '',
    [int]$Threads = 4,
    [int]$DiannThreads = 16
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Demux-Roots.ps1')
if (-not $Exe) { $Exe = Join-Path $runRoot '_bin\ztscan-persweep-vendor7\Osprey.DemuxTool.exe' }
$stems = '250814_ZTScan_100spd_A_1_A1', '250814_ZTScan_100spd_A_2_D1', '250814_ZTScan_100spd_A_3_G1'
$out = Join-Path $runRoot 'ztscan\full\cs_centered7_posmz'
New-Item -ItemType Directory -Force $out | Out-Null
$sw = [Diagnostics.Stopwatch]::StartNew()
$procs = foreach ($stem in $stems) {
    Start-Process -FilePath $Exe -PassThru -NoNewWindow `
        -RedirectStandardOutput (Join-Path $out "$stem.log") -RedirectStandardError (Join-Path $out "$stem.err") `
        -ArgumentList '--in', "$dataRoot\ZenoTOF8600-ZTScan\$stem.wiff2", '--out', (Join-Path $out "$stem.mzML"),
            '--kernel', (Join-Path $PSScriptRoot 'kernels\A1_rt3-8.profile.tsv'), '--layout', 'centered:7',
            '--position-mz', '--threads', "$Threads"
}
foreach ($p in $procs) { $p.WaitForExit() }
"$(Get-Date -Format HH:mm) demux done in $([math]::Round($sw.Elapsed.TotalSeconds)) s, exits: $(($procs | ForEach-Object { $_.ExitCode }) -join ',')"
if ($procs | Where-Object { $_.ExitCode -ne 0 }) { exit 1 }
$mzml = ($stems | ForEach-Object { Join-Path $out "$_.mzML" }) -join ','
pwsh -File (Join-Path $PSScriptRoot 'Search-Slices.ps1') -Arm full_cs_centered7_posmz_fixed `
    -Mzml $mzml -Threads $DiannThreads -Extra '--window 6 --mass-acc 17 --mass-acc-ms1 19'
"$(Get-Date -Format HH:mm) search done"
