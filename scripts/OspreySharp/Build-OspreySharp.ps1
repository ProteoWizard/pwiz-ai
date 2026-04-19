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

.PARAMETER RunInspection
    Run ReSharper code inspection (jb inspectcode) on OspreySharp.sln
    after building. Requires JetBrains.ReSharper.GlobalTools (install with:
    dotnet tool install -g JetBrains.ReSharper.GlobalTools). Full-solution
    inspection on OspreySharp takes roughly 1-3 minutes. Non-zero exit if
    any warnings are found.

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

.EXAMPLE
    .\Build-OspreySharp.ps1 -Configuration Debug -RunInspection
    Build and run ReSharper inspection; non-zero exit on any warnings
#>

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Release",

    [Parameter(Mandatory=$false)]
    [switch]$RunTests = $false,

    [Parameter(Mandatory=$false)]
    [switch]$RunInspection = $false,

    [Parameter(Mandatory=$false)]
    [string]$TestName = $null,

    [Parameter(Mandatory=$false)]
    [switch]$Summary = $false,

    [Parameter(Mandatory=$false)]
    [ValidateSet("quiet", "minimal", "normal", "detailed", "diagnostic")]
    [string]$Verbosity = "minimal",

    [Parameter(Mandatory=$false)]
    [string]$SourceRoot = $null,

    [Parameter(Mandatory=$false)]
    [ValidateSet("net472", "net8.0")]
    [string]$TargetFramework = "net472"
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
$testDll = Join-Path $ospreyRoot "OspreySharp.Test/bin/$Platform/$Configuration/$TargetFramework/OspreySharp.Test.dll"
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

    # Run ReSharper code inspection if requested
    if ($RunInspection) {
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "Running ReSharper code inspection" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan

        $jbPath = & where.exe jb 2>$null
        if (-not $jbPath) {
            Write-Host ""
            Write-Host "ReSharper command-line tools (jb) not installed" -ForegroundColor Red
            Write-Host "Install with: dotnet tool install -g JetBrains.ReSharper.GlobalTools" -ForegroundColor Yellow
            exit 1
        }

        $tmpDir = Join-Path $aiRoot '.tmp'
        if (-not (Test-Path $tmpDir)) {
            New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
        }
        $cacheDir = Join-Path $tmpDir '.inspectcode-cache'
        if (-not (Test-Path $cacheDir)) {
            New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
        }
        $inspectionOutput = Join-Path $tmpDir 'OspreyInspect.xml'
        $dotSettings = Join-Path $ospreyRoot 'OspreySharp.sln.DotSettings'

        if (-not (Test-Path $dotSettings)) {
            Write-Host "OspreySharp.sln.DotSettings not found at: $dotSettings" -ForegroundColor Red
            exit 1
        }

        Write-Host "Inspecting OspreySharp.sln (typically 1-3 minutes)..." -ForegroundColor Cyan
        $inspectStart = Get-Date

        # Inspection args match TeamCity configuration:
        # --severity WARNING: report warnings and errors only
        # --no-swea: disable solution-wide analysis
        # --no-build: solution already built by MSBuild above
        # --caches-home: persistent cache for faster subsequent runs
        $inspectArgs = @(
            "inspectcode", $slnPath,
            "--profile=$dotSettings",
            "--output=$inspectionOutput",
            "--format=Xml",
            "--severity=WARNING",
            "--no-swea",
            "--no-build",
            "--caches-home=$cacheDir",
            "--properties=Configuration=$Configuration",
            "--verbosity=WARN"
        )
        & jb $inspectArgs
        $inspectDuration = (Get-Date) - $inspectStart

        if (-not (Test-Path $inspectionOutput)) {
            Write-Host "Inspection output not found: $inspectionOutput" -ForegroundColor Red
            exit 1
        }

        # Parse XML results
        [xml]$xml = Get-Content $inspectionOutput
        $issueTypes = $xml.GetElementsByTagName("IssueType")
        $severities = @{}
        foreach ($issueType in $issueTypes) {
            $severities[$issueType.Id] = $issueType.Severity
        }

        $allIssues = @()
        $projects = $xml.GetElementsByTagName("Project")
        foreach ($project in $projects) {
            foreach ($issue in $project.ChildNodes) {
                if ($issue.Name -eq "Issue") {
                    $severity = $severities[$issue.TypeId]
                    if ($severity -eq "WARNING" -or $severity -eq "ERROR") {
                        $allIssues += [PSCustomObject]@{
                            File = $issue.File
                            Line = $issue.Line
                            TypeId = $issue.TypeId
                            Message = $issue.Message
                            Severity = $severity
                        }
                    }
                }
            }
        }

        $errors = @($allIssues | Where-Object { $_.Severity -eq "ERROR" })
        $warnings = @($allIssues | Where-Object { $_.Severity -eq "WARNING" })

        Write-Host ""
        Write-Host "Inspection completed in $($inspectDuration.TotalSeconds.ToString('F1'))s" -ForegroundColor Cyan
        Write-Host "  Errors:   $($errors.Count)" -ForegroundColor Gray
        Write-Host "  Warnings: $($warnings.Count)" -ForegroundColor Gray

        if ($allIssues.Count -gt 0) {
            Write-Host ""
            Write-Host "Top 20 issue types (count / rule):" -ForegroundColor Cyan
            $allIssues | Group-Object TypeId | Sort-Object Count -Descending | Select-Object -First 20 | ForEach-Object {
                "{0,5}  {1}" -f $_.Count, $_.Name | Write-Host -ForegroundColor Yellow
            }

            Write-Host ""
            Write-Host "Top 20 files (count / file):" -ForegroundColor Cyan
            $allIssues | Group-Object File | Sort-Object Count -Descending | Select-Object -First 20 | ForEach-Object {
                "{0,5}  {1}" -f $_.Count, $_.Name | Write-Host -ForegroundColor Yellow
            }

            Write-Host ""
            Write-Host "Full details: $inspectionOutput" -ForegroundColor Gray
            Write-Host ""
            Write-Host "Code inspection FAILED - $($allIssues.Count) issue(s) found" -ForegroundColor Red
            exit 1
        } else {
            Write-Host ""
            Write-Host "Code inspection passed - zero warnings/errors" -ForegroundColor Green
        }
    }

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
