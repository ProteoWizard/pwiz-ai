<#
.SYNOPSIS
    Build and test OspreySharp from LLM-assisted IDEs

.DESCRIPTION
    PowerShell script for building OspreySharp and running unit tests.
    Designed for use in Claude Code and other LLM-assisted development environments.

.PARAMETER Configuration
    Build configuration: Debug or Release (default: Release)

.PARAMETER RunTests
    Run OspreySharp.Test unit tests after building

.PARAMETER TestName
    Specific test method name to run (optional, runs all tests if not specified)

.PARAMETER Summary
    Suppress detailed build output, show only summary

.PARAMETER Verbosity
    MSBuild verbosity: quiet, minimal, normal, detailed, diagnostic (default: minimal)

.PARAMETER SourceRoot
    Path to pwiz root (auto-detected if not specified)

.EXAMPLE
    .\Build-OspreySharp.ps1
    Build OspreySharp in Release configuration

.EXAMPLE
    .\Build-OspreySharp.ps1 -RunTests
    Build and run all 167 unit tests

.EXAMPLE
    .\Build-OspreySharp.ps1 -RunTests -TestName TestXcorrPerfectMatch
    Build and run a specific test

.EXAMPLE
    .\Build-OspreySharp.ps1 -Configuration Debug -RunTests -Summary
    Debug build + tests with minimal output
#>

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Release",

    [Parameter(Mandatory=$false)]
    [switch]$RunTests = $false,

    [Parameter(Mandatory=$false)]
    [string]$TestName = $null,

    [Parameter(Mandatory=$false)]
    [switch]$Summary = $false,

    [Parameter(Mandatory=$false)]
    [ValidateSet("quiet", "minimal", "normal", "detailed", "diagnostic")]
    [string]$Verbosity = "minimal",

    [Parameter(Mandatory=$false)]
    [string]$SourceRoot = $null
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Script location: ai/scripts/OspreySharp/
$scriptRoot = Split-Path -Parent $PSCommandPath
$aiRoot = Split-Path -Parent (Split-Path -Parent $scriptRoot)  # ai/

# Auto-detect pwiz root location
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
$ospreyRoot = Join-Path $pwizRoot 'pwiz_tools/OspreySharp'
$slnPath = Join-Path $ospreyRoot 'OspreySharp.sln'
$testDll = Join-Path $ospreyRoot "OspreySharp.Test/bin/$Platform/$Configuration/pwiz.OspreySharp.Test.dll"
$initialLocation = Get-Location

if (-not (Test-Path $slnPath)) {
    Write-Error "OspreySharp.sln not found at: $slnPath"
    exit 1
}

try {
    Set-Location $ospreyRoot

    # Find MSBuild
    $vswherePath = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $vswherePath)) {
        Write-Host "MSBuild not found via vswhere - Visual Studio 2022 may not be installed" -ForegroundColor Red
        exit 1
    }

    $vsPath = & $vswherePath -latest -requires Microsoft.Component.MSBuild -property installationPath
    $msbuildPath = Join-Path $vsPath "MSBuild\Current\Bin\MSBuild.exe"
    if (-not (Test-Path $msbuildPath)) {
        Write-Host "MSBuild not found at $msbuildPath" -ForegroundColor Red
        exit 1
    }

    if (-not $Summary) {
        Write-Host "Using MSBuild: $msbuildPath" -ForegroundColor Cyan
        Write-Host ""
    }

    # Build entire solution (MSBuild skips up-to-date projects)
    Write-Host "Building: OspreySharp.sln ($Configuration|$Platform)" -ForegroundColor Cyan
    $buildStart = Get-Date

    $buildArgs = @(
        $slnPath,
        "/p:Configuration=$Configuration",
        "/p:Platform=$Platform",
        "/nologo",
        "/verbosity:$Verbosity"
    )

    & $msbuildPath @buildArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Build failed with exit code $LASTEXITCODE" -ForegroundColor Red
        exit $LASTEXITCODE
    }

    $buildDuration = (Get-Date) - $buildStart
    Write-Host ""
    Write-Host "Build succeeded in $($buildDuration.TotalSeconds.ToString('F1'))s" -ForegroundColor Green

    # Run tests if requested
    if ($RunTests) {
        Write-Host ""

        $vstestPath = Join-Path $vsPath "Common7\IDE\CommonExtensions\Microsoft\TestWindow\vstest.console.exe"
        if (-not (Test-Path $vstestPath)) {
            $vstestPath = Join-Path $vsPath "Common7\IDE\Extensions\TestPlatform\vstest.console.exe"
        }
        if (-not (Test-Path $vstestPath)) {
            Write-Host "vstest.console.exe not found" -ForegroundColor Red
            exit 1
        }

        if (-not (Test-Path $testDll)) {
            Write-Host "Test assembly not found: $testDll" -ForegroundColor Red
            exit 1
        }

        $testStart = Get-Date
        if ($TestName) {
            Write-Host "Running test: $TestName" -ForegroundColor Cyan
            & $vstestPath $testDll /Platform:$Platform /Tests:$TestName
        } else {
            Write-Host "Running all OspreySharp unit tests..." -ForegroundColor Cyan
            & $vstestPath $testDll /Platform:$Platform
        }
        $testExitCode = $LASTEXITCODE
        $testDuration = (Get-Date) - $testStart

        Write-Host ""
        if ($testExitCode -eq 0) {
            Write-Host "All tests passed in $($testDuration.TotalSeconds.ToString('F1'))s" -ForegroundColor Green
        } else {
            Write-Host "Tests FAILED in $($testDuration.TotalSeconds.ToString('F1'))s" -ForegroundColor Red
            exit $testExitCode
        }
    }

    Write-Host ""
    Write-Host "All operations completed successfully" -ForegroundColor Green
}
finally {
    Set-Location $initialLocation
}
