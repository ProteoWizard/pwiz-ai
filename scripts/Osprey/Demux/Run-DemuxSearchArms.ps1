#requires -Version 7.0
<#
.SYNOPSIS
    Searches the six Eclipse staggered-window runs with Osprey --demux auto, one arm per
    demultiplexer and Percolator seed, for a replicated demultiplexer comparison.

.DESCRIPTION
    Each arm is <Root>\<Arm>\search. Arms of the same -Impl share <Root>\_cache\<Impl>, so the
    demultiplexed .demux.spectra.bin is built once per implementation and reused by every seed.
    The seed is set through OSPREY_DIAG_SEED, which only a measurement build honours (the knob is
    never shipped, and Osprey does not log its seed). A shipped build would silently run seed 42 for
    every arm, so a seed other than 42 needs a SEED-KNOB file beside -Exe, written by whoever made
    the snapshot from a branch carrying the knob.

    Single-seed arm differences under ~5% are inside the seed spread at the default 300,000-row
    training cap (pwiz #4812); compare n >= 3 seeds, and use -MaxTrainSize 1500000.

    Compare finished arms with:
      python ai/scripts/Osprey/Compare/Compare-DemuxSearches.py --search <name>=<Root>\<Arm>\search ...

.EXAMPLE
    pwsh -File ai/scripts/Osprey/Demux/Run-DemuxSearchArms.ps1 -Impl pwiz -Exe D:\test\osprey-runs\_bin\x\Osprey.exe -Seeds 42,1,2
    pwsh -File ai/scripts/Osprey/Demux/Run-DemuxSearchArms.ps1 -Impl pr4710-msconvert -Engine msconvert -Exe ... -Seeds 42,1,2
#>
param(
    [Parameter(Mandatory)] [string]$Impl,          # demultiplexer name: arm prefix and cache key
    [Parameter(Mandatory)] [string]$Exe,           # Osprey.exe snapshot (built -VendorReader)
    [string]$Seeds = '42',                         # comma-separated Percolator seeds
    [string]$Engine = '',                          # #4710 only: OSPREY_DEMUX_ENGINE (weighted | msconvert)
    [int]$MaxTrainSize = 1500000,                  # OSPREY_MAX_TRAIN_SIZE; 0 = Osprey's default
    [string]$Root = 'D:\test\osprey-runs\pwiz-demux\h2h',
    [string]$RawDir = 'D:\test\osprey-runs\remes-ev',
    [string]$Library = 'D:\test\AstralTest-TargetDecoyLibraries\target+decoy+entrapment\carafe_spectral_library.tsv',
    [string]$Runs = ''                             # comma-separated stems; default every .raw in -RawDir
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path $Exe)) { throw "Osprey.exe not found: $Exe" }
$stems = if ($Runs) { $Runs -split ',' | Where-Object { $_ } } else {
    Get-ChildItem $RawDir -Filter '*.raw' | Sort-Object Name | ForEach-Object { $_.BaseName } }
$seedList = $Seeds -split ',' | Where-Object { $_ } | ForEach-Object { [int]$_ }
if (($seedList | Where-Object { $_ -ne 42 }) -and -not (Test-Path (Join-Path (Split-Path $Exe) 'SEED-KNOB'))) {
    throw "Seeds other than 42 need a build with the OSPREY_DIAG_SEED knob (SEED-KNOB marker beside $Exe)."
}

$cache = Join-Path $Root "_cache\$Impl"
New-Item -ItemType Directory -Force $cache | Out-Null
$summary = Join-Path $Root 'arms-summary.log'

foreach ($seed in $seedList) {
    $arm = "$Impl-s$seed"
    $out = Join-Path $Root "$arm\search"
    New-Item -ItemType Directory -Force $out | Out-Null

    # Every knob is set explicitly per arm, so nothing leaks from the caller's environment.
    foreach ($v in 'OSPREY_DEMUX_ENGINE', 'OSPREY_DEMUX_BLOCK', 'OSPREY_DEMUX_INTERPOLATION',
            'OSPREY_DEMUX_MASS_ERROR_PPM', 'OSPREY_DIAG_SEED', 'OSPREY_MAX_TRAIN_SIZE') {
        Remove-Item "Env:$v" -ErrorAction SilentlyContinue
    }
    if ($Engine) { $env:OSPREY_DEMUX_ENGINE = $Engine }
    if ($seed -ne 42) { $env:OSPREY_DIAG_SEED = "$seed" }
    if ($MaxTrainSize -gt 0) { $env:OSPREY_MAX_TRAIN_SIZE = "$MaxTrainSize" }

    $inputs = foreach ($s in $stems) { '-i'; (Join-Path $RawDir "$s.raw") }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    "[$(Get-Date -Format s)] START $arm exe=$Exe engine=$Engine seed=$seed train=$MaxTrainSize runs=$($stems.Count)" |
        Tee-Object -FilePath $summary -Append
    & $Exe @inputs -l $Library -o (Join-Path $out 'output.blib') --resolution hram --fdr-level precursor `
        --protein-fdr 0.01 --decoys-in-library --demux auto `
        --fdrbench (Join-Path $out 'fdrbench.tsv') --report (Join-Path $out 'report.tsv') `
        --cache-dir $cache --output-dir $out --timestamp --memstamp --perf-stats --verbose `
        --log-file (Join-Path $out 'osprey.log') *> (Join-Path $out 'console.log')
    "[$(Get-Date -Format s)] END $arm exit $LASTEXITCODE, $([math]::Round($sw.Elapsed.TotalSeconds)) s" |
        Tee-Object -FilePath $summary -Append
}
