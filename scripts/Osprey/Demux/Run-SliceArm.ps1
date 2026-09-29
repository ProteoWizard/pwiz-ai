# One slice arm: the tool on the ZT Scan slice (sweeps 247-371, 500-700 m/z) of A1, D1 and G1's
# msconvert mzML with the arm's own flags, then one DIA-NN search of the three (Search-Slices.ps1),
# optionally with DIA-NN's settings pinned. Arms are independent, so several can run at once.
# Output: <run root>\ztscan\slices\<Name>\ and slices\diann\<Name> (Demux-Roots.ps1).
# Example: pwsh -File Run-SliceArm.ps1 -Exe <tool> -Name c7_posmz_l1r2 -Flags '--position-mz --sweep-l1 2 --sweep-l1-refit'
#          -DiannExtra '--window 6 --mass-acc 14 --mass-acc-ms1 17'
param(
    [Parameter(Mandatory)] [string]$Exe,
    [Parameter(Mandatory)] [string]$Name,
    [string]$Flags = '',                # tool flags, space-separated
    [string]$Layout = 'centered:7',
    [string]$DiannExtra = '',           # DIA-NN flags, space-separated
    [int]$Threads = 4,
    [int]$DiannThreads = 6
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Demux-Roots.ps1')
$dir = Join-Path $runRoot "ztscan\slices\$Name"
New-Item -ItemType Directory -Force $dir | Out-Null
$stems = '250814_ZTScan_100spd_A_1_A1', '250814_ZTScan_100spd_A_2_D1', '250814_ZTScan_100spd_A_3_G1'
# @(...): a single flag would otherwise unroll to a string, and splatting a string passes its characters.
$flagArgs = @(if ($Flags) { $Flags -split ' ' })
"$(Get-Date -Format HH:mm) ${Name}: $Layout $Flags"
foreach ($stem in $stems) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    & $Exe --in "$runRoot\ztscan\mzml\$stem.mzML" --out (Join-Path $dir "$stem.mzML") `
        --kernel (Join-Path $PSScriptRoot 'kernels\A1_rt3-8.profile.tsv') --layout $Layout --cycles 247:371 --mz 500:700 `
        --threads $Threads @flagArgs *> (Join-Path $dir "$stem.log")
    $code = $LASTEXITCODE
    '{0} {1}: exit {2}, {3:F0} s' -f $Name, $stem, $code, $sw.Elapsed.TotalSeconds
    if ($code -ne 0) { exit 1 }
}
$files = ($stems | ForEach-Object { Join-Path $dir "$_.mzML" }) -join ','
$search = @('-File', (Join-Path $PSScriptRoot 'Search-Slices.ps1'), '-Arm', $Name, '-Mzml', $files, '-Threads', "$DiannThreads")
if ($DiannExtra) { $search += @('-Extra', $DiannExtra) }
pwsh @search
"$(Get-Date -Format HH:mm) $Name done"
