# Times the demux tool before and after a change on a short cycle range of the A1 .wiff2, one after the
# other, and diffs the outputs. Usage: pwsh -File Run-TimingAB.ps1 -Old <exe> -New <exe> [-Cycles 300:335]
param(
    [Parameter(Mandatory = $true)][string]$Old,
    [Parameter(Mandatory = $true)][string]$New,
    [string]$Cycles = '300:335',
    [string]$Layout = 'framed:3:1',
    [int]$Threads = 4
)
$ErrorActionPreference = 'Stop'
$out = 'D:\test\osprey-runs\ztscan\timing'
New-Item -ItemType Directory -Force $out | Out-Null
$wiff = 'D:\demux-test-data\ZenoTOF8600-ZTScan\250814_ZTScan_100spd_A_1_A1.wiff2'
$kernel = Join-Path $PSScriptRoot 'kernels\A1_rt3-8.profile.tsv'
foreach ($arm in @(@{ Name = 'new'; Exe = $New }, @{ Name = 'old'; Exe = $Old })) {
    $mzml = Join-Path $out "$($arm.Name).mzML"
    $log = Join-Path $out "$($arm.Name).log"
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    & $arm.Exe --in $wiff --out $mzml --kernel $kernel --layout $Layout --threads $Threads --cycles $Cycles *> $log
    "$($arm.Name): exit $LASTEXITCODE, $([math]::Round($clock.Elapsed.TotalSeconds)) s"
}
python (Join-Path $PSScriptRoot 'Diff-Mzml.py') (Join-Path $out 'old.mzML') (Join-Path $out 'new.mzML')
