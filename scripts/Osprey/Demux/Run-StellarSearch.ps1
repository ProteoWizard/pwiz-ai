#requires -Version 7.0
<#
.SYNOPSIS
    Searches one Stellar window-width method (three replicate runs) with Osprey, one arm per call,
    for the Stellar demultiplexing comparison (2Th, 4Th, 4Th-50pctOverlap, 4Th-SuperOverlap).

.DESCRIPTION
    The runs are Lauren's 2026-10-09 HeLa set (24 min, 400-900 m/z, three replicates per method,
    each acquired once centroided and once in profile), downloaded from Panorama
    MacCoss/Lauren/20261009_Stellar-Centroiding-for-Mike/RawFiles into <Root>\raw.

    The arm is <Root>\<Arm>\search. The .spectra.bin and .demux.spectra.bin of a method and kind
    are shared by every arm with the same -CacheKey (default: method, kind and demux mode), so a
    cache is built once and reused; give a new -CacheKey whenever the demultiplexer changes.

    Compare finished arms with:
      python ai/scripts/Osprey/Compare/Compare-DemuxSearches.py --search <name>=<Root>\<Arm>\search ...

.EXAMPLE
    pwsh -File ai/scripts/Osprey/Demux/Run-StellarSearch.ps1 -Exe D:\test\osprey-runs\_bin\stellar-base-vendor\Osprey.exe -Method 2Th
    pwsh -File ai/scripts/Osprey/Demux/Run-StellarSearch.ps1 -Exe ... -Method 4Th-50pctOverlap -Demux auto -Arm 50pct-base
    pwsh -File ai/scripts/Osprey/Demux/Run-StellarSearch.ps1 -Exe ... -Method 4Th-50pctOverlap -Arm 50pct-elution `
        -InputDir D:\test\osprey-runs\stellar-demux\tool\50pct-elution -InputSuffix .demux.mzML
#>
param(
    [Parameter(Mandatory)] [string]$Exe,           # Osprey.exe snapshot (built -VendorReader)
    [Parameter(Mandatory)]
    [ValidateSet('2Th', '4Th', '4Th-50pctOverlap', '4Th-SuperOverlap')]
    [string]$Method,
    [ValidateSet('centroid', 'profile')]
    [string]$Kind = 'centroid',                    # which acquisition: centroided, or profile (read through vendor centroiding)
    [ValidateSet('off', 'auto')]
    [string]$Demux = 'off',
    [string]$Arm = '',                             # default <Method>-<Kind>[-demux]
    [string]$CacheKey = '',                        # default <Method>-<Kind>-<Demux>
    [string]$Env = '',                             # extra environment, 'NAME=value,NAME=value'
    [string]$ExtraArgs = '',                       # extra Osprey arguments, space-separated
    [string]$Runs = 'TR01,TR02,TR03',
    [string]$InputDir = '',                        # default <Root>\raw; e.g. Osprey.DemuxTool's output folder
    [string]$InputSuffix = '.raw',                 # e.g. .demux.mzML for the tool's output
    [string]$Root = 'D:\test\osprey-runs\stellar-demux',
    [string]$Library = "$env:USERPROFILE\Downloads\Perftests\osprey-testfiles-mzML-v2\stellar\hela-filtered-SkylineAI_spectral_library.tsv"
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path $Exe)) { throw "Osprey.exe not found: $Exe" }
if (-not (Test-Path $Library)) { throw "Library not found: $Library (the Stellar test library from regression.ps1's mzML bundle)" }
$suffix = if ($Kind -eq 'profile') { '_profile' } else { '' }
if (-not $Arm) { $Arm = "$Method-$Kind" + $(if ($Demux -ne 'off') { "-demux" } else { '' }) }
if (-not $CacheKey) { $CacheKey = "$Method-$Kind-$Demux" }

$rawDir = if ($InputDir) { $InputDir } else { Join-Path $Root 'raw' }
$inputs = foreach ($r in $Runs -split ',' | Where-Object { $_ }) {
    $path = Join-Path $rawDir "20261009_Stellar_WWopt_${Method}_400-900mz_24min${suffix}_$r$InputSuffix"
    if (-not (Test-Path $path)) { throw "Run not found: $path" }
    '-i'; $path
}
$cache = Join-Path $Root "_cache\$CacheKey"
$out = Join-Path $Root "$Arm\search"
New-Item -ItemType Directory -Force $cache, $out | Out-Null
$summary = Join-Path $Root 'arms-summary.log'

# Every demux knob is set explicitly, so nothing leaks from the caller's environment.
foreach ($v in 'OSPREY_DEMUX_ENGINE', 'OSPREY_DEMUX_BLOCK', 'OSPREY_DEMUX_INTERPOLATION', 'OSPREY_DEMUX_OUTPUT') {
    Remove-Item "Env:$v" -ErrorAction SilentlyContinue
}
foreach ($pair in $Env -split ',' | Where-Object { $_ }) {
    $name, $value = $pair -split '=', 2
    Set-Item "Env:$name" $value
}
$extra = $ExtraArgs -split ' ' | Where-Object { $_ }

$sw = [Diagnostics.Stopwatch]::StartNew()
"[$(Get-Date -Format s)] START $Arm exe=$Exe method=$Method kind=$Kind demux=$Demux cache=$CacheKey input=$rawDir\*$InputSuffix env=$Env extra=$ExtraArgs" |
    Tee-Object -FilePath $summary -Append
# -Env is cleared afterwards: a caller running several arms with & shares this process, and a setting left behind
# would silently apply to its next arm.
try {
    & $Exe @inputs -l $Library -o (Join-Path $out 'output.blib') --resolution unit --fdr-level precursor `
        --protein-fdr 0.01 --demux $Demux `
        --cache-dir $cache --output-dir $out --timestamp --memstamp --verbose `
        --log-file (Join-Path $out 'osprey.log') @extra *> (Join-Path $out 'console.log')
}
finally {
    foreach ($pair in $Env -split ',' | Where-Object { $_ }) {
        Remove-Item "Env:$(($pair -split '=', 2)[0])" -ErrorAction SilentlyContinue
    }
}
"[$(Get-Date -Format s)] END $Arm exit $LASTEXITCODE, $([math]::Round($sw.Elapsed.TotalSeconds)) s" |
    Tee-Object -FilePath $summary -Append
