<#
.SYNOPSIS
    Time the mzML -> .spectra.bin conversion (--task SpectraCache) across datasets and
    build configurations.

.DESCRIPTION
    The conversion is the ONE stage the ProteoWizard-only reader changed, and it is the
    stage the perf gate cannot isolate: Test-PerfGate.ps1 measures whole-pipeline stage
    walls across two WORKTREES, so it cannot vary Configuration within one tree, and
    stage1to4 mixes reading with everything else that happens per file.

    This runs only the cache build, deleting the target .spectra.bin before every timed
    run so each one is a real conversion rather than a cache hit.

    Why Configuration is a dimension rather than a fixed Release: pwiz-sharp's mzML read
    was measured REPRODUCIBLY SLOWER in Release than in Debug (45.4s vs 38.2s at n=6),
    the opposite of the vendor path, and unexplained - see
    TODO-20260817_osprey_net8_pwiz_sharp.md, "Perf, settled at n=6". Until Osprey stopped
    deploying Debug assemblies into a Release build, that A/B could not even be expressed
    from one tree; now Configuration propagates across the ProjectReference, so it can.

    Configurations are INTERLEAVED per repeat with alternating order, the same control
    Test-PerfGate.ps1 uses: thermal drift and background load are shared between the two
    legs instead of landing on whichever ran second.

.PARAMETER Dataset
    Stellar (unit), Astral (hram), or Both (default).

.PARAMETER Configuration
    Debug, Release, or Both (default). Both is the point of the script.

.PARAMETER Files
    Single (first file only, default) or All (all three). Single matches how the prior
    net8.0 numbers were taken - "one file each".

.PARAMETER Repeats
    Timed conversions per (dataset x configuration). Default 3. The record this is meant
    to reproduce settled at 6 after 1 and 3 both got the magnitude wrong; use 6 when the
    answer has to stand on its own.

.PARAMETER SourceRoot
    Worktree to build and measure. Default: the sibling 'pwiz' next to ai/.

.PARAMETER SkipBuild
    Measure the binaries already built under each configuration.

.PARAMETER TestBaseDir
    Override the dataset root (else OSPREY_TEST_BASE_DIR, else D:\test\osprey-runs).

.PARAMETER OutputDir
    Per-run logs and the markdown report. Default ai\.tmp\spectra-cache\<UTC stamp>\.

.EXAMPLE
    # Recapture the net8.0 conversion numbers on whatever this tree targets now.
    pwsh -File ./ai/scripts/Osprey/Measure-SpectraCache.ps1 -SourceRoot C:\proj\pwiz-osprey
#>
#requires -Version 7
param(
    [ValidateSet('Stellar','Astral','Both')] [string]$Dataset = 'Both',
    [ValidateSet('Debug','Release','Both')]  [string]$Configuration = 'Both',
    [ValidateSet('Single','All')]            [string]$Files = 'Single',
    [int]$Repeats = 3,
    [string]$SourceRoot = $null,
    [switch]$SkipBuild,
    [string]$TestBaseDir = $null,
    [string]$OutputDir = $null
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$scriptDir = Split-Path -Parent $PSCommandPath
. (Join-Path $scriptDir 'Dataset-Config.ps1')

$aiRoot   = Split-Path -Parent (Split-Path -Parent $scriptDir)
$projRoot = Split-Path -Parent $aiRoot
if (-not $SourceRoot) { $SourceRoot = Join-Path $projRoot 'pwiz' }
if (-not (Test-Path -LiteralPath $SourceRoot)) { throw "SourceRoot not found: $SourceRoot" }

if (-not $OutputDir) {
    $stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmssZ')
    $OutputDir = Join-Path $projRoot "ai\.tmp\spectra-cache\$stamp"
}
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

# The TFM is read from the tree, not taken as a parameter - same rule as
# Test-PerfGate.ps1 and Build-Osprey.ps1, so a retarget needs no edit here.
function Get-OspreyTfm {
    param([string]$Root)
    $props = Join-Path $Root 'pwiz_tools\Osprey\Directory.Build.props'
    if (Test-Path -LiteralPath $props) {
        $m = [regex]::Match((Get-Content -LiteralPath $props -Raw),
                            '<TargetFrameworks?>([^<]+)</TargetFrameworks?>')
        if ($m.Success) {
            $modern = @($m.Groups[1].Value -split ';' |
                        ForEach-Object { $_.Trim() } |
                        Where-Object { $_ -match '^net(\d+)\.0' } |
                        Sort-Object { [int]([regex]::Match($_, '^net(\d+)\.0').Groups[1].Value) })
            if ($modern.Count -gt 0) { return $modern[-1] }
        }
    }
    return 'net8.0'
}

$tfm = Get-OspreyTfm $SourceRoot
$configs  = if ($Configuration -eq 'Both') { @('Debug','Release') } else { @($Configuration) }
$datasets = if ($Dataset -eq 'Both') { @('Stellar','Astral') } else { @($Dataset) }

# Same data the perf gate and regression.ps1 use, acquired the same way (download +
# extract, skip-if-present). NOT the D:\test\osprey-runs layout Dataset-Config defaults
# to - that tree does not carry these mzML on every machine, and pointing at two
# different copies is how two harnesses stop being comparable.
. (Join-Path $SourceRoot 'pwiz_tools/Osprey/Regression/RegressionData.ps1')
if ([string]::IsNullOrEmpty($TestBaseDir)) {
    $dataUrl = 'https://panoramaweb.org/_webdav/MacCoss/software/%40files/perftests/osprey-testfiles-mzML-v2.zip'
    $TestBaseDir = Get-RegressionData -Url $dataUrl
}

# Per-run scratch off the read-only data tree, mirroring Test-PerfGate.ps1's convention
# (leading underscore = "not a dataset").
$scratchBase = if ($env:OSPREY_TEST_BASE_DIR) { $env:OSPREY_TEST_BASE_DIR }
               elseif ($IsLinux) { '/mnt/d/test/osprey-runs' }
               else { 'D:\test\osprey-runs' }
$ScratchRoot = Join-Path $scratchBase '_spectracache'

Write-Host ""
Write-Host "=== Measure-SpectraCache (mzML -> .spectra.bin) ===" -ForegroundColor Cyan
Write-Host ("Tree:      {0}  ({1})" -f $SourceRoot, $tfm)
Write-Host ("Datasets:  {0}" -f ($datasets -join ', '))
Write-Host ("Configs:   {0}" -f ($configs -join ', '))
Write-Host ("Files:     {0}   Repeats: {1}" -f $Files, $Repeats)
Write-Host ("Output:    {0}" -f $OutputDir)
Write-Host ""

if (-not $SkipBuild) {
    foreach ($cfg in $configs) {
        Write-Host ("Building {0} ({1})" -f $cfg, $tfm) -ForegroundColor Cyan
        # net8.0 is a floor, not a pin: Build-Osprey.ps1 reads the declared TFM off disk
        # and corrects a request the branch does not target.
        & (Join-Path $scriptDir 'Build-Osprey.ps1') -SourceRoot $SourceRoot `
            -Configuration $cfg -TargetFramework net8.0 -Summary
        if ($LASTEXITCODE -ne 0) { throw "Build failed for $cfg (exit $LASTEXITCODE)" }
    }
}

function Get-Exe {
    param([string]$Cfg)
    $exe = Join-Path $SourceRoot ("pwiz_tools\Osprey\Osprey\bin\x64\{0}\{1}\Osprey.exe" -f $Cfg, $tfm)
    if (-not (Test-Path -LiteralPath $exe)) { throw "Osprey.exe not found for ${Cfg}: $exe" }
    return $exe
}

# One timed conversion into FRESH scratch. --work-dir relocates both the .spectra.bin cache
# and every derived artifact, so each run is guaranteed cold without deleting anything - and
# the shared Perftests tree stays read-only, the same discipline Test-PerfGate.ps1 keeps.
function Invoke-Conversion {
    param([string]$Cfg, [hashtable]$Ds, [string[]]$MzmlPaths, [string]$LogPath, [string]$Scratch)

    if (Test-Path -LiteralPath $Scratch) { Remove-Item -LiteralPath $Scratch -Recurse -Force }
    New-Item -ItemType Directory -Path $Scratch -Force | Out-Null

    $osprey = Get-Exe $Cfg
    $ospreyArgs = @()
    foreach ($p in $MzmlPaths) { $ospreyArgs += @('-i', $p) }
    $ospreyArgs += @('-l', (Join-Path $Ds.TestDir $Ds.Library))
    $ospreyArgs += @('-o', (Join-Path $Scratch 'measure.blib'))
    $ospreyArgs += @('--resolution', $Ds.Resolution)
    $ospreyArgs += @('--work-dir', $Scratch)
    $ospreyArgs += @('--task', 'SpectraCache')

    $sw = [Diagnostics.Stopwatch]::StartNew()
    & $osprey @ospreyArgs *>> $LogPath
    $exit = $LASTEXITCODE
    $sw.Stop()
    if ($exit -ne 0) { throw "Osprey --task SpectraCache failed for $Cfg (exit $exit); see $LogPath" }

    Remove-Item -LiteralPath $Scratch -Recurse -Force -ErrorAction SilentlyContinue
    return [math]::Round($sw.Elapsed.TotalSeconds, 1)
}

$results = @{}
foreach ($dsName in $datasets) {
    $ds = Get-DatasetConfig $dsName -TestBaseDir $TestBaseDir
    $mzmlDir = if ($ds.MzmlDir) { $ds.MzmlDir } else { $ds.TestDir }
    $names = if ($Files -eq 'All') { $ds.AllFiles } else { @($ds.SingleFile) }
    $paths = @($names | ForEach-Object { Join-Path $mzmlDir $_ })
    foreach ($p in $paths) {
        if (-not (Test-Path -LiteralPath $p)) { throw "mzML not found: $p" }
    }

    foreach ($cfg in $configs) { $results["$dsName/$cfg"] = @() }

    for ($r = 1; $r -le $Repeats; $r++) {
        # Alternate which configuration runs first so neither systematically runs hotter.
        $order = if ($r % 2 -eq 1) { $configs } else { @($configs | Sort-Object -Descending) }
        foreach ($cfg in $order) {
            $log = Join-Path $OutputDir ("{0}-{1}-run{2}.log" -f $dsName, $cfg, $r)
            $scratch = Join-Path $ScratchRoot ("{0}-{1}-run{2}" -f $dsName, $cfg, $r)
            $secs = Invoke-Conversion -Cfg $cfg -Ds $ds -MzmlPaths $paths -LogPath $log -Scratch $scratch
            $results["$dsName/$cfg"] += $secs
            Write-Host ("    [{0}/{1}/run{2}] {3}s" -f $dsName, $cfg, $r, $secs)
        }
    }
}

function Get-Median {
    param([double[]]$V)
    $s = @($V | Sort-Object)
    if ($s.Count -eq 0) { return 0 }
    if ($s.Count % 2 -eq 1) { return $s[[int](($s.Count - 1) / 2)] }
    return [math]::Round(($s[$s.Count / 2 - 1] + $s[$s.Count / 2]) / 2, 1)
}

$md = @()
$md += "# Measure-SpectraCache"
$md += ""
$md += "- Tree: ``$SourceRoot`` ($tfm)"
$md += "- Files: $Files, repeats: $Repeats, configurations interleaved with alternating order"
$md += ""
$md += "| Dataset | Configuration | Median | Range | vs Debug |"
$md += "|---|---|---:|---|---:|"
foreach ($dsName in $datasets) {
    $dbgMed = if ($results.ContainsKey("$dsName/Debug")) { Get-Median $results["$dsName/Debug"] } else { 0 }
    foreach ($cfg in $configs) {
        $v = $results["$dsName/$cfg"]
        if (-not $v -or $v.Count -eq 0) { continue }
        $med = Get-Median $v
        $rel = if ($dbgMed -gt 0 -and $cfg -ne 'Debug') {
            '{0:+0.0;-0.0}%' -f ((($med - $dbgMed) / $dbgMed) * 100)
        } else { '-' }
        $stats = $v | Measure-Object -Minimum -Maximum
        $range = "{0} - {1}s" -f $stats.Minimum, $stats.Maximum
        $md += "| $dsName | $cfg | ${med}s | $range | $rel |"
    }
}
$md += ""

$reportPath = Join-Path $OutputDir 'spectra-cache.md'
$md -join "`r`n" | Set-Content -LiteralPath $reportPath -Encoding utf8
Write-Host ""
$md | ForEach-Object { Write-Host $_ }
Write-Host ""
Write-Host "Report written: $reportPath" -ForegroundColor Green
