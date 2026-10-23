#requires -Version 7.0
<#
.SYNOPSIS
    Demultiplexes the three replicates of one Stellar method with Osprey.DemuxTool --scheme staggered, optionally
    centroids the profile output with Centrix, then optionally searches the result with Osprey (Run-StellarSearch.ps1).

.DESCRIPTION
    Each run goes to <Root>\tool\<Arm>\<stem>.demux.mzML with its log beside it; a run whose output exists is skipped,
    so a stopped arm resumes. A non-overlapping method (2Th, 4Th) passes through the same pipeline unchanged, which
    makes it the control for the same reading, thinning (--thin) and centroiding.

    -Centrix runs Centrix (maccoss/centrix, the Stellar profile centroider) in WSL on each profile output, writing
    <stem>.demux.centrix.mzML, which is what is then searched. Centrix is installed in WSL (~/.cargo/bin/centrix);
    -CentrixArgs passes its options (the profile peak sigma of these runs is 0.33 Th: --sigma-ms2 0.33).
    With -SearchExe the arm is searched as <Root>\<Arm>\search.

.EXAMPLE
    pwsh -File ai/scripts/Osprey/Demux/Run-StellarTool.ps1 -Tool D:\test\osprey-runs\_bin\x\Osprey.DemuxTool.exe `
        -Method 4Th-50pctOverlap -Kind profile -Arm 50pct-profile-makima-centrix `
        -ToolArgs '--profile --channel-th 0.09 --ions' -Centrix -CentrixArgs '--sigma-ms2 0.33' `
        -SearchExe D:\test\osprey-runs\_bin\stellar-base-vendor\Osprey.exe
#>
param(
    [Parameter(Mandatory)] [string]$Tool,          # Osprey.DemuxTool.exe snapshot (built -VendorReader)
    [Parameter(Mandatory)]
    [ValidateSet('2Th', '4Th', '4Th-50pctOverlap', '4Th-SuperOverlap')]   # 2Th/4Th: no overlap, for controls (--thin, centroiding)
    [string]$Method,
    [Parameter(Mandatory)] [string]$Arm,
    [ValidateSet('centroid', 'profile')]
    [string]$Kind = 'centroid',                    # profile reads the _profile acquisitions (pass --profile in -ToolArgs)
    [string]$ToolArgs = '',                        # extra tool arguments, space-separated
    [int]$Threads = 0,                             # 0 = the tool's default (all)
    [switch]$Centrix,                              # centroid each profile output with Centrix (WSL) before searching
    [string]$CentrixArgs = '--sigma-ms2 0.33',
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

function ConvertTo-WslPath([string]$path) {
    $full = [IO.Path]::GetFullPath($path)
    '/mnt/' + $full.Substring(0, 1).ToLowerInvariant() + $full.Substring(2).Replace('\', '/')
}

foreach ($r in $Runs -split ',' | Where-Object { $_ }) {
    $stem = "20261009_Stellar_WWopt_${Method}_400-900mz_24min${suffix}_$r"
    $raw = Join-Path $Root "raw\$stem.raw"
    $out = Join-Path $outDir "$stem.demux.mzML"
    if (Test-Path $out) {
        "skip $out (exists)"
    }
    else {
        $sw = [Diagnostics.Stopwatch]::StartNew()
        "[$(Get-Date -Format s)] TOOL START $Arm $stem tool=$Tool args=$ToolArgs" | Tee-Object -FilePath $summary -Append
        & $Tool --in $raw --out $out --scheme staggered @extra *> (Join-Path $outDir "$stem.log")
        "[$(Get-Date -Format s)] TOOL END $Arm $stem exit $LASTEXITCODE, $([math]::Round($sw.Elapsed.TotalSeconds)) s" |
            Tee-Object -FilePath $summary -Append
        if ($LASTEXITCODE -ne 0) { throw "Osprey.DemuxTool failed on $stem (see $outDir\$stem.log)" }
    }
    if (-not $Centrix) { continue }
    $centroided = Join-Path $outDir "$stem.demux.centrix.mzML"
    if (Test-Path $centroided) { "skip $centroided (exists)"; continue }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    "[$(Get-Date -Format s)] CENTRIX START $Arm $stem args=$CentrixArgs" | Tee-Object -FilePath $summary -Append
    $log = ConvertTo-WslPath (Join-Path $outDir "$stem.centrix.log")
    wsl -e bash -c "~/.cargo/bin/centrix run -i '$(ConvertTo-WslPath $out)' -o '$(ConvertTo-WslPath $outDir)' $CentrixArgs > '$log' 2>&1"
    $exit = $LASTEXITCODE
    "[$(Get-Date -Format s)] CENTRIX END $Arm $stem exit $exit, $([math]::Round($sw.Elapsed.TotalSeconds)) s" |
        Tee-Object -FilePath $summary -Append
    if ($exit -ne 0 -or -not (Test-Path $centroided)) { throw "Centrix failed on $stem (see $outDir\$stem.centrix.log)" }
}

if ($SearchExe) {
    $searchSuffix = if ($Centrix) { '.demux.centrix.mzML' } else { '.demux.mzML' }
    pwsh -NoProfile -File (Join-Path $PSScriptRoot 'Run-StellarSearch.ps1') -Exe $SearchExe -Method $Method -Kind $Kind `
        -Arm $Arm -CacheKey "tool-$Arm" -InputDir $outDir -InputSuffix $searchSuffix -Runs $Runs -Root $Root
}
