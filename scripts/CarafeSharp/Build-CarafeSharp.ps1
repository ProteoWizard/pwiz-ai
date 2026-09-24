<#
.SYNOPSIS
    Build and test CarafeSharp from LLM-assisted IDEs.
.DESCRIPTION
    Builds pwiz_tools/CarafeSharp/CarafeSharp.sln with the .NET SDK and optionally runs the
    CarafeSharp.Test unit tests and a ReSharper inspection. CarafeSharp is net10.0 only, so
    the dotnet CLI builds it on Windows and Linux alike; no Visual Studio MSBuild is needed.

    The libtorch native runtime is chosen at build time (-Torch). The CPU and CUDA packages
    ship identically named native files and cannot share an output folder, so switching
    backends does a clean rebuild of the projects that carry them.
.PARAMETER Configuration
    Debug or Release (default: Release).
.PARAMETER RunTests
    Run CarafeSharp.Test after building.
.PARAMETER TestName
    Run only tests whose fully qualified name contains this text.
.PARAMETER RunInspection
    Run ReSharper code inspection (jb inspectcode) after building. Non-zero exit on any
    warning. Requires JetBrains.ReSharper.GlobalTools.
.PARAMETER Torch
    libtorch backend: cpu (default) or cuda (CUDA 12.8, about 4 GB of native files).
.PARAMETER Summary
    Suppress detailed build output.
.PARAMETER SourceRoot
    Path to the pwiz root. Defaults to the pwiz checkout that is a sibling of this ai/ tree.
    Pass it explicitly in a worktree session, or the build silently tests the other tree.
.EXAMPLE
    pwsh -File ./ai/scripts/CarafeSharp/Build-CarafeSharp.ps1 -Configuration Debug -RunTests
.EXAMPLE
    pwsh -File ./ai/scripts/CarafeSharp/Build-CarafeSharp.ps1 -RunTests -TestName ModelParity
#>
param(
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Release",
    [switch]$RunTests = $false,
    [string]$TestName = $null,
    [switch]$RunInspection = $false,
    [ValidateSet("cpu", "cuda")]
    [string]$Torch = "cpu",
    [switch]$Summary = $false,
    [string]$SourceRoot = $null
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$scriptRoot = Split-Path -Parent $PSCommandPath
$aiRoot = Split-Path -Parent (Split-Path -Parent $scriptRoot)

if ($SourceRoot) {
    $pwizRoot = (Resolve-Path $SourceRoot).Path
} else {
    $siblingPath = Join-Path (Split-Path -Parent $aiRoot) 'pwiz'
    $childPath = Split-Path -Parent $aiRoot
    if (Test-Path (Join-Path $siblingPath 'pwiz_tools')) {
        $pwizRoot = $siblingPath
    } elseif (Test-Path (Join-Path $childPath 'pwiz_tools')) {
        $pwizRoot = $childPath
    } else {
        Write-Error "Cannot find pwiz_tools. Use -SourceRoot to specify the pwiz root directory."
        exit 1
    }
}

$Platform = "x64"
$carafeRoot = Join-Path $pwizRoot 'pwiz_tools/CarafeSharp'
$slnPath = Join-Path $carafeRoot 'CarafeSharp.sln'
$testDll = Join-Path $carafeRoot "CarafeSharp.Test/bin/$Platform/$Configuration/net10.0/CarafeSharp.Test.dll"
if (-not (Test-Path $slnPath)) {
    Write-Error "CarafeSharp.sln not found at: $slnPath"
    exit 1
}
Write-Host "CarafeSharp root: $carafeRoot" -ForegroundColor Gray

# CRLF is the project standard; fix any LF-only files among the modified/added ones.
$fixCrlfScript = Join-Path $aiRoot 'scripts/fix-crlf.ps1'
if (Test-Path $fixCrlfScript) {
    Push-Location $pwizRoot
    try {
        & $fixCrlfScript | Out-Null
    }
    finally {
        Pop-Location
    }
}

# A backend switch leaves the other backend's native files in bin/, where they would be
# loaded instead of the ones this build restored. Record the backend and clean on change.
$backendStamp = Join-Path $carafeRoot "CarafeSharp/obj/torch-backend-$Configuration.txt"
if ((Test-Path $backendStamp) -and ((Get-Content $backendStamp -Raw).Trim() -ne $Torch)) {
    Write-Host "libtorch backend changed to $Torch; cleaning native outputs." -ForegroundColor Yellow
    foreach ($project in @('CarafeSharp', 'CarafeSharp.Test')) {
        $binDir = Join-Path $carafeRoot "$project/bin/$Platform/$Configuration"
        if (Test-Path $binDir) {
            Remove-Item -Recurse -Force $binDir
        }
    }
}

$verbosity = if ($Summary) { "quiet" } else { "minimal" }
Write-Host "Building: CarafeSharp.sln ($Configuration|$Platform, libtorch $Torch)" -ForegroundColor Cyan
$buildStart = Get-Date
$buildArgs = @(
    'build', $slnPath,
    "-c", $Configuration,
    "-p:Platform=$Platform",
    "-p:CarafeSharpTorch=$Torch",
    "-v:$verbosity",
    "-nologo"
)
& dotnet $buildArgs
$buildExit = $LASTEXITCODE
$buildDuration = (Get-Date) - $buildStart
if ($buildExit -ne 0) {
    Write-Host "Build FAILED (exit $buildExit) after $($buildDuration.TotalSeconds.ToString('F1'))s" -ForegroundColor Red
    exit $buildExit
}
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backendStamp) | Out-Null
Set-Content -Path $backendStamp -Value $Torch
Write-Host "Build succeeded in $($buildDuration.TotalSeconds.ToString('F1'))s" -ForegroundColor Green

if ($RunInspection) {
    $dotSettings = Join-Path $carafeRoot 'CarafeSharp.sln.DotSettings'
    $tmpDir = Join-Path $aiRoot '.tmp'
    $cacheDir = Join-Path $tmpDir '.inspectcode-cache'
    New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
    $inspectionOutput = Join-Path $tmpDir 'CarafeSharpInspect.xml'
    Write-Host "Inspecting CarafeSharp.sln..." -ForegroundColor Cyan
    $inspectArgs = @(
        "inspectcode", $slnPath,
        "--output=$inspectionOutput",
        "--format=Xml",
        "--severity=WARNING",
        "--no-swea",
        "--no-build",
        "--caches-home=$cacheDir",
        "--properties=Configuration=$Configuration;Platform=$Platform;CarafeSharpTorch=$Torch",
        "--target-framework=net10.0",
        "--verbosity=WARN"
    )
    if (Test-Path $dotSettings) {
        $inspectArgs += "--profile=$dotSettings"
    }
    & jb $inspectArgs
    if (-not (Test-Path $inspectionOutput)) {
        Write-Host "Inspection output not found: $inspectionOutput" -ForegroundColor Red
        exit 1
    }
    [xml]$xml = Get-Content $inspectionOutput
    $severities = @{}
    foreach ($issueType in $xml.GetElementsByTagName("IssueType")) {
        $severities[$issueType.Id] = $issueType.Severity
    }
    $issues = @()
    foreach ($project in $xml.GetElementsByTagName("Project")) {
        foreach ($issue in $project.ChildNodes) {
            if ($issue.Name -eq "Issue" -and $severities[$issue.TypeId] -in @("WARNING", "ERROR")) {
                $issues += "{0}:{1} [{2}] {3}" -f $issue.File, $issue.Line, $issue.TypeId, $issue.Message
            }
        }
    }
    if ($issues.Count -gt 0) {
        $issues | Select-Object -First 50 | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
        Write-Host "Code inspection FAILED - $($issues.Count) issue(s). Full details: $inspectionOutput" -ForegroundColor Red
        exit 1
    }
    Write-Host "Code inspection passed - zero warnings/errors" -ForegroundColor Green
}

if ($RunTests) {
    if (-not (Test-Path $testDll)) {
        Write-Host "Test assembly not found: $testDll" -ForegroundColor Red
        exit 1
    }
    $testArgs = @('test', $testDll, '--nologo')
    if ($TestName) {
        $testArgs += @('--filter', "FullyQualifiedName~$TestName")
    }
    # A single named test shows its TestContext output (parity numbers); a full run stays terse.
    if ($Summary) {
        $testArgs += @('--logger', 'console;verbosity=minimal')
    } elseif ($TestName) {
        $testArgs += @('--logger', 'console;verbosity=detailed')
    } else {
        $testArgs += @('--logger', 'console;verbosity=normal')
    }
    Write-Host "Running tests: $testDll" -ForegroundColor Cyan
    & dotnet $testArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Tests FAILED" -ForegroundColor Red
        exit $LASTEXITCODE
    }
    Write-Host "All tests passed" -ForegroundColor Green
}
exit 0
