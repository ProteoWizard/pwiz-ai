# DIA-NN searches of ZT Scan slices: one arm per call, the three replicates together, the same
# library and DIA-NN 2.3.2 as the full-run arms. Output: D:\test\osprey-runs\ztscan\slices\diann\<arm>
param(
    [Parameter(Mandatory)] [string]$Arm,
    [Parameter(Mandatory)] [string]$Mzml,  # comma-separated: pwsh -File cannot pass an array
    [switch]$ScanningSwath,
    [string]$Extra = '',  # extra DIA-NN flags, space-separated
    [int]$Threads = 4
)
$ErrorActionPreference = 'Stop'
$diann = 'C:\DIA-NN\2.3.2\diann.exe'
$lib = 'D:\test\osprey-runs\ztscan\library\ztscan_carafe_lib.parquet'
$outDir = Join-Path 'D:\test\osprey-runs\ztscan\slices\diann' $Arm
New-Item -ItemType Directory -Force (Join-Path $outDir 'tmp') | Out-Null
$argv = @()
foreach ($f in ($Mzml -split ',')) { $argv += @('--f', $f) }
$argv += @('--lib', $lib, '--threads', "$Threads", '--verbose', '1', '--qvalue', '0.01', '--matrices',
    '--out', (Join-Path $outDir 'report.parquet'), '--temp', (Join-Path $outDir 'tmp'))
if ($ScanningSwath) { $argv += '--scanning-swath' }
if ($Extra) { $argv += ($Extra -split ' ') }
$sw = [Diagnostics.Stopwatch]::StartNew()
& $diann @argv *> (Join-Path $outDir 'diann.log')
$sw.Stop()
'{0}: exit {1}, {2:F0} s' -f $Arm, $LASTEXITCODE, $sw.Elapsed.TotalSeconds
