#requires -Version 7.0
<#
.SYNOPSIS
    Demultiplexes the three replicates of one Stellar overlapped method with Osprey.DemuxTool --scheme staggered, then
    optionally searches the demultiplexed mzML with Osprey (Run-StellarSearch.ps1).

.DESCRIPTION
    Each run goes to <Root>\tool\<Arm>\<stem>.demux.mzML with its log beside it; a run whose mzML exists is skipped,
    so a stopped arm resumes. With -SearchExe the arm is then searched as <Root>\<Arm>\search.

.EXAMPLE
    pwsh -File ai/scripts/Osprey/Demux/Run-StellarTool.ps1 -Tool D:\test\osprey-runs\_bin\stellar-elution2-demuxtool\Osprey.DemuxTool.exe `
        -Method 4Th-50pctOverlap -Arm 50pct-elution -ToolArgs '--channel-th 0.4 --fill-time-ions 400 --elution-fwhm 5.1' `
        -SearchExe D:\test\osprey-runs\_bin\stellar-base-vendor\Osprey.exe
#>
param(
    [Parameter(Mandatory)] [string]$Tool,          # Osprey.DemuxTool.exe snapshot (built -VendorReader)
    [Parameter(Mandatory)]
    [ValidateSet('4Th-50pctOverlap', '4Th-SuperOverlap')]
    [string]$Method,
    [Parameter(Mandatory)] [string]$Arm,
    [ValidateSet('centroid', 'profile')]
    [string]$Kind = 'centroid',                    # profile reads the _profile acquisitions (pass --profile in -ToolArgs)
    [string]$ToolArgs = '',                        # extra tool arguments, space-separated
    [int]$Threads = 0,                             # 0 = the tool's default (all)
    [string]$Runs = 'TR01,TR02,TR03',
    [string]$SearchExe = '',                       # Osprey.exe snapshot: search the arm when given
    [string]$Root = 'D:\test\osprey-runs\stellar-demux'
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path $Tool)) { throw "Osprey.DemuxTool.exe not found: $Tool" }
$suffix = if ($Kind -eq 'profile') { '_profile' } else { '' }
$outDir = Join-Path $Root "tool\$Arm"
New-Item -ItemType Directory -Force $outDir | Out-Null
$summary = Join-Path $Root 'arms-summary.log'
$extra = @($ToolArgs -split ' ' | Where-Object { $_ })
if ($Threads -gt 0) { $extra += @('--threads', "$Threads") }

foreach ($r in $Runs -split ',' | Where-Object { $_ }) {
    $stem = "20261009_Stellar_WWopt_${Method}_400-900mz_24min${suffix}_$r"
    $raw = Join-Path $Root "raw\$stem.raw"
    $out = Join-Path $outDir "$stem.demux.mzML"
    if (Test-Path $out) { "skip $out (exists)"; continue }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    "[$(Get-Date -Format s)] TOOL START $Arm $stem tool=$Tool args=$ToolArgs" | Tee-Object -FilePath $summary -Append
    & $Tool --in $raw --out $out --scheme staggered @extra *> (Join-Path $outDir "$stem.log")
    "[$(Get-Date -Format s)] TOOL END $Arm $stem exit $LASTEXITCODE, $([math]::Round($sw.Elapsed.TotalSeconds)) s" |
        Tee-Object -FilePath $summary -Append
    if ($LASTEXITCODE -ne 0) { throw "Osprey.DemuxTool failed on $stem (see $outDir\$stem.log)" }
}

if ($SearchExe) {
    pwsh -NoProfile -File (Join-Path $PSScriptRoot 'Run-StellarSearch.ps1') -Exe $SearchExe -Method $Method -Kind $Kind `
        -Arm $Arm -CacheKey "tool-$Arm" -InputDir $outDir -InputSuffix '.demux.mzML' -Runs $Runs -Root $Root
}
