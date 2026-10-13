<#
.SYNOPSIS
    CarafeSharp code coverage: the unit tests, then the unit tests plus regression.ps1,
    merged into one dotCover report.

.DESCRIPTION
    The CarafeSharp counterpart of ai/scripts/Osprey/Measure-CumulativeCoverage.ps1.

      1. Unit leg      -- build.ps1 -Coverage -RequireData (Release, CPU) -> unit.dcvr.
      2. Isolated leg  -- regression.ps1 -NoBuild under `dotCover cover`   -> isolated.dcvr.
      3. Chained leg   -- regression.ps1 -NoBuild -Leg Chained              -> chained.dcvr.
      4. Merge and report, per assembly: unit alone, each leg, and the cumulative total.

    dotCover covers pwsh and its children, but /ProcessFilters keeps only the CarafeSharp processes, so
    the regression comparator (RegressionTest, run through dotnet test) does not add the
    production code it calls to the regression legs. The unit leg is the only place test
    processes count. Osprey.exe (chained leg) is outside the module filter.

    Everything runs on the CPU build so the snapshots are of one set of binaries. The chained
    leg needs Osprey built in the same checkout (pwiz_tools/Osprey/build.ps1 -NoTests).

.PARAMETER SourceRoot
    The pwiz checkout (default <project root>\pwiz).

.PARAMETER Dataset
    Stellar (default) or Astral, for the isolated leg.

.PARAMETER SkipUnit
    Skip the unit leg (reuse nothing; regression legs only).

.PARAMETER SkipChained
    Skip the chained leg.

.PARAMETER OutDir
    Where the snapshots and reports go (default ai\.tmp\carafesharp-cumcov-<timestamp>).
#>
param(
    [string]$SourceRoot,
    [ValidateSet('Stellar', 'Astral')] [string]$Dataset = 'Stellar',
    [switch]$SkipUnit,
    [switch]$SkipChained,
    [string]$OutDir
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$scriptDir = Split-Path -Parent $PSCommandPath
$projectRoot = (Resolve-Path (Join-Path $scriptDir '..\..\..')).Path   # ai/scripts/CarafeSharp -> root
if (-not $SourceRoot) { $SourceRoot = Join-Path $projectRoot 'pwiz' }
$carafeRoot = Join-Path $SourceRoot 'pwiz_tools\CarafeSharp'
$buildPs1 = Join-Path $carafeRoot 'build.ps1'
$regressionPs1 = Join-Path $carafeRoot 'regression.ps1'
foreach ($p in $buildPs1, $regressionPs1) {
    if (-not (Test-Path $p)) { throw "Not found: $p (is -SourceRoot a checkout with CarafeSharp?)" }
}

$dotCover = @(& (Join-Path $SourceRoot 'scripts\Ensure-DotCover.ps1') -ManifestDir $carafeRoot)[-1]
$stamp = (Get-Date).ToString('yyyyMMdd_HHmmss')
if (-not $OutDir) { $OutDir = Join-Path $projectRoot "ai\.tmp\carafesharp-cumcov-$stamp" }
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$pwshExe = (Get-Command pwsh).Source
$filters = '/Filters=+:module=CarafeSharp*;-:module=CarafeSharp.Test'

Write-Host ""
Write-Host "=== CarafeSharp cumulative coverage ($SourceRoot) ===" -ForegroundColor Cyan
Write-Host "  dotCover : $dotCover"
Write-Host "  out dir  : $OutDir"

$legs = [ordered]@{}

function Get-Report([string]$snapshot) {
    $json = [IO.Path]::ChangeExtension($snapshot, '.json')
    & $dotCover report "/Source=$snapshot" "/Output=$json" '/ReportType=JSON' | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $json)) { throw "dotCover report failed for $snapshot" }
    return Get-Content -Raw $json | ConvertFrom-Json
}

# ---- 1. Unit leg ----
if (-not $SkipUnit) {
    Write-Host "[unit] build.ps1 -Coverage -RequireData ..." -ForegroundColor Cyan
    & $pwshExe -NoProfile -File $buildPs1 -Coverage -RequireData | Out-Host
    $unitExit = $LASTEXITCODE
    $built = Join-Path $carafeRoot 'TestResults\CarafeSharp.Test-Release-cpu.dcvr'
    if (-not (Test-Path $built)) { throw "Unit coverage snapshot not found at $built" }
    $unitSnap = Join-Path $OutDir 'unit.dcvr'
    Copy-Item $built $unitSnap -Force
    if ($unitExit -ne 0) { Write-Host "  WARNING: unit tests exited $unitExit (FAILED)." -ForegroundColor Yellow }
    $legs['unit'] = $unitSnap
}

# ---- 2/3. Regression legs ----
function Invoke-CoveredRegression([string]$name, [string[]]$regressionArgs) {
    $snap = Join-Path $OutDir "$name.dcvr"
    $log = Join-Path $OutDir "$name.log"
    Write-Host "[$name] regression.ps1 $($regressionArgs -join ' ') under dotCover ..." -ForegroundColor Cyan
    $coverArgs = @('cover', $filters, '/ProcessFilters=+:CarafeSharp*', "/Output=$snap",
        '/ReturnTargetExitCode', '/AnalyzeTargetArguments=false',
        "/TargetWorkingDir=$carafeRoot", "/TargetExecutable=$pwshExe", '--',
        '-NoProfile', '-File', $regressionPs1) + $regressionArgs
    & $dotCover $coverArgs *>&1 | Tee-Object -FilePath $log | Out-Host
    $exit = $LASTEXITCODE
    if (-not (Test-Path $snap)) { throw "dotCover produced no snapshot at $snap" }
    if ($exit -ne 0) { Write-Host "  WARNING: $name exited $exit (FAILED); its coverage is from a red run." -ForegroundColor Yellow }
    $script:legs[$name] = $snap
}

Invoke-CoveredRegression 'isolated' @('-NoBuild', '-Dataset', $Dataset)
if (-not $SkipChained) {
    Invoke-CoveredRegression 'chained' @('-NoBuild', '-Leg', 'Chained')
}

# ---- 4. Merge and report ----
$merged = Join-Path $OutDir 'cumulative.dcvr'
& $dotCover merge "/Source=$(@($legs.Values) -join ';')" "/Output=$merged" | Out-Null
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $merged)) { throw 'dotCover merge failed' }
$legs['cumulative'] = $merged
if ($legs.Contains('isolated') -and $legs.Contains('chained')) {
    $regOnly = Join-Path $OutDir 'regression.dcvr'
    & $dotCover merge "/Source=$($legs['isolated']);$($legs['chained'])" "/Output=$regOnly" | Out-Null
    $legs.Insert(3, 'regression', $regOnly)
}

$reports = [ordered]@{}
foreach ($name in $legs.Keys) { $reports[$name] = Get-Report $legs[$name] }

$assemblies = @($reports['cumulative'].Children | Where-Object { $_.Name -like 'CarafeSharp*' } | ForEach-Object Name | Sort-Object)
$header = '{0,-22}' -f 'Assembly'
foreach ($name in $reports.Keys) { $header += '{0,12}' -f $name }
Write-Host ""
Write-Host $header
foreach ($rowName in @($assemblies) + 'TOTAL') {
    $line = '{0,-22}' -f $rowName
    foreach ($name in $reports.Keys) {
        $node = if ($rowName -eq 'TOTAL') { $reports[$name] } else { $reports[$name].Children | Where-Object Name -eq $rowName }
        $cell = if ($node -and [int]$node.TotalStatements -gt 0) { '{0:F1}%' -f (100.0 * $node.CoveredStatements / $node.TotalStatements) } else { '-' }
        $line += '{0,12}' -f $cell
    }
    Write-Host $line
}
$total = $reports['cumulative']
Write-Host ""
Write-Host ("Cumulative: {0} of {1} statements" -f $total.CoveredStatements, $total.TotalStatements)
Write-Host "Artifacts in: $OutDir" -ForegroundColor Green
