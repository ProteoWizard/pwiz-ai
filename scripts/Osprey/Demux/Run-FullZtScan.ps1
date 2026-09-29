# Full-run ZT Scan demux with Osprey.DemuxTool, read directly from the .wiff2 (vendor-centroided),
# weighted per-sweep solve, centered:5 layout, then one DIA-NN search of the three replicates.
# Output: <run root>\ztscan\full\cs_centered5\ and slices\diann\full_cs_centered5 (Demux-Roots.ps1)
param([string]$Exe = '', [int]$Threads = 10,
    [int]$DiannThreads = 16, [string]$Layout = 'centered:5')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Demux-Roots.ps1')
if (-not $Exe) { $Exe = Join-Path $runRoot '_bin\ztscan-persweep-vendor2\Osprey.DemuxTool.exe' }
$name = 'cs_' + ($Layout -replace ':', '')
$out = Join-Path $runRoot "ztscan\full\$name"
New-Item -ItemType Directory -Force $out | Out-Null
$stems = '250814_ZTScan_100spd_A_1_A1', '250814_ZTScan_100spd_A_2_D1', '250814_ZTScan_100spd_A_3_G1'
foreach ($stem in $stems) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    & $Exe --in "$dataRoot\ZenoTOF8600-ZTScan\$stem.wiff2" --out (Join-Path $out "$stem.mzML") `
        --kernel (Join-Path $PSScriptRoot 'kernels\A1_rt3-8.profile.tsv') --layout $Layout --threads $Threads *> (Join-Path $out "$stem.log")
    '{0}: exit {1}, {2:F0} s' -f $stem, $LASTEXITCODE, $sw.Elapsed.TotalSeconds
}
$files = ($stems | ForEach-Object { Join-Path $out "$_.mzML" }) -join ','
pwsh -File (Join-Path $PSScriptRoot 'Search-Slices.ps1') -Arm "full_$name" -Mzml $files -Threads $DiannThreads
