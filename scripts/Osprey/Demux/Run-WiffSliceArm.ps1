# One slice arm read from the vendor .wiff2 instead of msconvert's mzML: the tool on the slice (sweeps
# 247-371, 500-700 m/z) of A1, D1 and G1, the three in parallel, with the arm's own flags (for instance
# '--centroid events', or '--raw --centroid events' for an undemultiplexed control), then one DIA-NN search
# of the three (Search-Slices.ps1). Output: <run root>\ztscan\slices\<Name>\ and slices\diann\<Name>.
param(
    [Parameter(Mandatory)] [string]$Exe,
    [Parameter(Mandatory)] [string]$Name,
    [string]$Flags = '',                # tool flags, space-separated
    [string]$Layout = 'centered:7',
    [string]$DiannExtra = '',           # DIA-NN flags, space-separated
    [switch]$ScanningSwath,
    [int]$Threads = 4,
    [int]$DiannThreads = 6
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Demux-Roots.ps1')
$dir = Join-Path $runRoot "ztscan\slices\$Name"
New-Item -ItemType Directory -Force $dir | Out-Null
$stems = '250814_ZTScan_100spd_A_1_A1', '250814_ZTScan_100spd_A_2_D1', '250814_ZTScan_100spd_A_3_G1'
"$(Get-Date -Format HH:mm) ${Name}: $Layout $Flags (from .wiff2)"
$sw = [Diagnostics.Stopwatch]::StartNew()
$procs = foreach ($stem in $stems) {
    $argv = @('--in', "$dataRoot\ZenoTOF8600-ZTScan\$stem.wiff2", '--out', (Join-Path $dir "$stem.mzML"),
        '--kernel', (Join-Path $PSScriptRoot 'kernels\A1_rt3-8.profile.tsv'), '--layout', $Layout,
        '--cycles', '247:371', '--mz', '500:700', '--threads', "$Threads")
    if ($Flags) { $argv += ($Flags -split ' ') }
    Start-Process -FilePath $Exe -PassThru -NoNewWindow -ArgumentList $argv `
        -RedirectStandardOutput (Join-Path $dir "$stem.log") -RedirectStandardError (Join-Path $dir "$stem.err")
}
foreach ($p in $procs) { $p.WaitForExit() }
"$(Get-Date -Format HH:mm) $Name tool done in $([math]::Round($sw.Elapsed.TotalSeconds)) s, exits: $(($procs | ForEach-Object { $_.ExitCode }) -join ',')"
if ($procs | Where-Object { $_.ExitCode -ne 0 }) { exit 1 }
$files = ($stems | ForEach-Object { Join-Path $dir "$_.mzML" }) -join ','
$search = @('-File', (Join-Path $PSScriptRoot 'Search-Slices.ps1'), '-Arm', $Name, '-Mzml', $files, '-Threads', "$DiannThreads")
if ($DiannExtra) { $search += @('-Extra', $DiannExtra) }
if ($ScanningSwath) { $search += '-ScanningSwath' }
pwsh @search
"$(Get-Date -Format HH:mm) $Name done"
