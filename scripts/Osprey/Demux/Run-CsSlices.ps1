# The C# Osprey.DemuxTool on the ZT Scan slice (cycles 248-372, 500-700 m/z) of A1, D1 and G1, read
# from the same msconvert mzML as the Python arms, for each layout given, then one DIA-NN arm per
# layout. Output: <run root>\ztscan\slices\cs_<layout>\ and slices\diann\cs_<layout> (Demux-Roots.ps1)
param([string]$Exe = '', [int]$Threads = 6,
    [int]$DiannThreads = 12, [string[]]$Layouts = @('framed:3:1', 'centered:5'), [string]$Extra = '',
    [string]$Suffix = '')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Demux-Roots.ps1')
if (-not $Exe) { $Exe = Join-Path $runRoot '_bin\ztscan-persweep-vendor4\Osprey.DemuxTool.exe' }
$root = Join-Path $runRoot 'ztscan\slices'
$stems = '250814_ZTScan_100spd_A_1_A1', '250814_ZTScan_100spd_A_2_D1', '250814_ZTScan_100spd_A_3_G1'
# @(...): a single flag would otherwise unroll to a string, and splatting a string passes its characters.
$extraArgs = @(if ($Extra) { $Extra -split ' ' })
# pwsh -File passes one string, so layouts may also come comma-separated.
foreach ($layout in ($Layouts | ForEach-Object { $_ -split ',' })) {
    $name = 'cs_' + ($layout -replace ':', '') + $Suffix
    $dir = Join-Path $root $name
    New-Item -ItemType Directory -Force $dir | Out-Null
    foreach ($stem in $stems) {
        $sw = [Diagnostics.Stopwatch]::StartNew()
        & $Exe --in "$runRoot\ztscan\mzml\$stem.mzML" --out (Join-Path $dir "$stem.mzML") `
            --kernel (Join-Path $PSScriptRoot 'kernels\A1_rt3-8.profile.tsv') --layout $layout --cycles 247:371 --mz 500:700 `
            --threads $Threads @extraArgs *> (Join-Path $dir "$stem.log")
        '{0} {1}: exit {2}, {3:F0} s' -f $name, $stem, $LASTEXITCODE, $sw.Elapsed.TotalSeconds
    }
    $files = ($stems | ForEach-Object { Join-Path $dir "$_.mzML" }) -join ','
    pwsh -File (Join-Path $PSScriptRoot 'Search-Slices.ps1') -Arm $name -Mzml $files -Threads $DiannThreads
}
