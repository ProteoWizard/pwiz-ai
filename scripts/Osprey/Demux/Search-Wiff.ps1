# DIA-NN 2.3.2 on the SCIEX vendor file itself (.wiff, which reads the shared .wiff.scan through
# Clearcore2), with the same library and flags as the mzML arms. Waits for a running DIA-NN process first.
# Output: <run root>\ztscan\diann\<Arm> (Demux-Roots.ps1). Quant files go to <Arm>\tmp, not beside the data.
param(
    [string]$Arm = 'W_wiff_scanning',
    [string]$Runs = '250814_ZTScan_100spd_A_1_A1',  # comma-separated run stems
    [string]$Extension = '.wiff',
    [switch]$Plain,
    [int]$Threads = 8,
    [int]$WaitForPid = 0,
    [string]$Diann = '',
    [string]$Extra = ''  # extra DIA-NN flags, space-separated (e.g. pinned settings)
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Demux-Roots.ps1')
if (-not $Diann) { $Diann = Join-Path $runRoot '_bin\diann-2.3.2-sciex\diann.exe' }
if ($WaitForPid -gt 0) {
    while (Get-Process -Id $WaitForPid -ErrorAction SilentlyContinue) { Start-Sleep 30 }
}
$lib = Join-Path $runRoot 'ztscan\library\ztscan_carafe_lib.parquet'
$outDir = Join-Path $runRoot "ztscan\diann\$Arm"
New-Item -ItemType Directory -Force (Join-Path $outDir 'tmp') | Out-Null
$argv = @()
foreach ($stem in ($Runs -split ',')) { $argv += @('--f', "$dataRoot\ZenoTOF8600-ZTScan\$stem$Extension") }
$argv += @('--lib', $lib, '--threads', "$Threads", '--verbose', '1', '--qvalue', '0.01', '--matrices',
    '--out', (Join-Path $outDir 'report.parquet'), '--temp', (Join-Path $outDir 'tmp'))
if (-not $Plain) { $argv += '--scanning-swath' }
if ($Extra) { $argv += ($Extra -split ' ') }
$sw = [Diagnostics.Stopwatch]::StartNew()
& $Diann @argv *> (Join-Path $outDir 'diann.log')
$sw.Stop()
'{0}: exit {1}, {2:F0} s' -f $Arm, $LASTEXITCODE, $sw.Elapsed.TotalSeconds
