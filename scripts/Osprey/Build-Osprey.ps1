<#
.SYNOPSIS
    Build and test Osprey from LLM-assisted IDEs

.DESCRIPTION
    PowerShell script for building Osprey and running unit tests.
    Designed for use in Claude Code and other LLM-assisted development environments.

.PARAMETER Configuration
    Build configuration: Debug or Release (default: Release)

.PARAMETER RunTests
    Run Osprey.Test unit tests after building

.PARAMETER RunInspection
    Run ReSharper code inspection (jb inspectcode) on Osprey.sln
    after building. Requires JetBrains.ReSharper.GlobalTools (install with:
    dotnet tool install -g JetBrains.ReSharper.GlobalTools). Full-solution
    inspection on Osprey takes roughly 1-3 minutes. Non-zero exit if
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
    .\Build-Osprey.ps1
    Build Osprey in Release configuration

.EXAMPLE
    .\Build-Osprey.ps1 -RunTests
    Build and run all 167 unit tests

.EXAMPLE
    .\Build-Osprey.ps1 -RunTests -TestName TestXcorrPerfectMatch
    Build and run a specific test

.EXAMPLE
    .\Build-Osprey.ps1 -Configuration Debug -RunTests -Summary
    Debug build + tests with minimal output

.EXAMPLE
    .\Build-Osprey.ps1 -Configuration Debug -RunInspection
    Build and run ReSharper inspection; non-zero exit on any warnings

.PARAMETER Coverage
    Run the unit tests under JetBrains dotCover and export a JSON coverage
    report. Implies -RunTests. Requires the dotCover command-line tool
    (install with: dotnet tool install -g JetBrains.dotCover.CommandLineTools).
    Coverage spans the Osprey.* production assemblies (the
    Osprey.Test assembly is excluded). Summarize the JSON with
    Summarize-Coverage.ps1.

.PARAMETER CoverageOutputPath
    Path for the coverage JSON output (default:
    ai\.tmp\osprey-coverage-{timestamp}.json). The matching .dcvr snapshot
    is written alongside it.

.EXAMPLE
    .\Build-Osprey.ps1 -Coverage
    Build, run all unit tests under dotCover, and export a coverage JSON
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
    [string]$TargetFramework = "net472",

    [Parameter(Mandatory=$false)]
    [switch]$Coverage = $false,

    [Parameter(Mandatory=$false)]
    [string]$CoverageOutputPath = ""
)

# Coverage is meaningless without running the tests - imply -RunTests
if ($Coverage) {
    $RunTests = $true
}

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Script location: ai/scripts/Osprey/
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
$ospreyRoot = Join-Path $pwizRoot 'pwiz_tools/Osprey'
$slnPath = Join-Path $ospreyRoot 'Osprey.sln'
# Multi-targeted projects (f14cb74b2) place outputs under a TFM subdirectory:
# bin/x64/Release/net472/ and bin/x64/Release/net8.0/.
$testDll = Join-Path $ospreyRoot "Osprey.Test/bin/$Platform/$Configuration/$TargetFramework/Osprey.Test.dll"
$initialLocation = Get-Location

if (-not (Test-Path $slnPath)) {
    Write-Error "Osprey.sln not found at: $slnPath"
    exit 1
}

try {
    Set-Location $ospreyRoot

    # Fix line endings in modified files (CRLF is project standard, but LLM tools may introduce LF-only).
    # Fast because it only processes files in 'git status' (modified/added). Run from pwiz repo root
    # so git status sees pwiz's modified files. The fix-crlf.ps1 script lives in the sibling ai/ tree.
    $fixCrlfScript = Join-Path $aiRoot 'scripts\fix-crlf.ps1'
    if (Test-Path $fixCrlfScript) {
        if (-not $Summary) {
            Write-Host "Checking line endings in modified files..." -ForegroundColor Cyan
        }
        Push-Location $pwizRoot
        try {
            & $fixCrlfScript
            if ($LASTEXITCODE -ne 0) {
                Write-Host "`n[WARN] Line ending fix failed - some files may still have LF-only line endings" -ForegroundColor Yellow
                Write-Host "This may cause large Git diffs. Consider running: $fixCrlfScript`n" -ForegroundColor Gray
            }
        }
        finally {
            Pop-Location
        }
    }

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
    Write-Host "Building: Osprey.sln ($Configuration|$Platform)" -ForegroundColor Cyan
    $buildStart = Get-Date

    $buildArgs = @(
        $slnPath,
        "/restore",
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
        $dotSettings = Join-Path $ospreyRoot 'Osprey.sln.DotSettings'

        if (-not (Test-Path $dotSettings)) {
            Write-Host "Osprey.sln.DotSettings not found at: $dotSettings" -ForegroundColor Red
            exit 1
        }

        Write-Host "Inspecting Osprey.sln (typically 1-3 minutes)..." -ForegroundColor Cyan
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

        # vstest target arguments (shared by the plain and dotCover-wrapped runs)
        $targetArgs = @($testDll, "/Platform:$Platform")
        if ($TestName) {
            $targetArgs += "/Tests:$TestName"
        }

        # Resolve dotCover and coverage output paths when -Coverage is requested
        $dotCoverExe = $null
        $coverageSnapshot = $null
        if ($Coverage) {
            # Primary: dotCover command-line tool installed as a .NET global tool
            $globalTool = Join-Path $env:USERPROFILE ".dotnet\tools\dotCover.exe"
            if (Test-Path $globalTool) {
                $dotCoverExe = $globalTool
            }
            # Fallback: command-line tools unpacked under pwiz\libraries
            if (-not $dotCoverExe) {
                $libPath = Join-Path $pwizRoot "libraries"
                if (Test-Path $libPath) {
                    $dotCoverDirs = Get-ChildItem -Path $libPath -Directory -Filter "*dotcover*commandlinetools*" -ErrorAction SilentlyContinue
                    foreach ($dir in $dotCoverDirs) {
                        $exePath = Get-ChildItem -Path $dir.FullName -Recurse -Filter "dotCover.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
                        if ($exePath) {
                            $dotCoverExe = $exePath.FullName
                            break
                        }
                    }
                }
            }
            if (-not $dotCoverExe) {
                Write-Host "dotCover.exe not found - coverage requires the JetBrains dotCover command-line tool" -ForegroundColor Red
                Write-Host "Install with: dotnet tool install -g JetBrains.dotCover.CommandLineTools" -ForegroundColor Yellow
                exit 1
            }

            # dotCover 2025.3.0+ replaced the slash-style cover/report syntax used below.
            # This machine runs the older syntax; fail clearly rather than mis-invoking a newer build.
            $dotCoverVersion = & $dotCoverExe --version 2>&1 | Select-String "dotCover" |
                ForEach-Object { if ($_ -match '(\d+\.\d+\.\d+)') { [version]$matches[1] } } | Select-Object -First 1
            if ($dotCoverVersion -and $dotCoverVersion -ge [version]"2025.3.0") {
                Write-Host "dotCover $dotCoverVersion uses the newer CLI syntax this script does not yet support." -ForegroundColor Red
                Write-Host "Update Build-Osprey.ps1 to the 2025.3.0+ 'cover --target-executable' form." -ForegroundColor Yellow
                exit 1
            }

            if ([string]::IsNullOrEmpty($CoverageOutputPath)) {
                $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
                $aiTmpDir = Join-Path $aiRoot ".tmp"
                if (-not (Test-Path $aiTmpDir)) {
                    New-Item -ItemType Directory -Path $aiTmpDir -Force | Out-Null
                }
                $CoverageOutputPath = Join-Path $aiTmpDir "osprey-coverage-$timestamp.json"
            } else {
                $covDir = Split-Path -Parent $CoverageOutputPath
                if ($covDir -and -not (Test-Path $covDir)) {
                    New-Item -ItemType Directory -Path $covDir -Force | Out-Null
                }
            }
            $coverageBaseName = [System.IO.Path]::GetFileNameWithoutExtension($CoverageOutputPath)
            $coverageSnapshot = Join-Path (Split-Path -Parent $CoverageOutputPath) "$coverageBaseName.dcvr"

            Write-Host "Coverage enabled - dotCover: $dotCoverExe" -ForegroundColor Cyan
            Write-Host "  Snapshot: $coverageSnapshot" -ForegroundColor Gray
            Write-Host "  JSON:     $CoverageOutputPath" -ForegroundColor Gray
        }

        $testStart = Get-Date
        if ($Coverage) {
            # Wrap vstest.console.exe with dotCover. Filters keep the Osprey.*
            # production assemblies and drop the test assembly. /TargetWorkingDir must
            # be a writable directory (vstest creates a TestResults folder there).
            Write-Host "Running Osprey unit tests under dotCover..." -ForegroundColor Cyan
            $coverArgs = @(
                "cover",
                "/Filters=+:module=Osprey*",
                "/Filters=-:module=Osprey.Test",
                "/Output=$coverageSnapshot",
                "/ReturnTargetExitCode",
                "/AnalyzeTargetArguments=false",
                "/TargetWorkingDir=$ospreyRoot",
                "/TargetExecutable=$vstestPath",
                "--"
            ) + $targetArgs
            & $dotCoverExe $coverArgs
            $testExitCode = $LASTEXITCODE
        } elseif ($TestName) {
            Write-Host "Running test: $TestName" -ForegroundColor Cyan
            & $vstestPath $targetArgs
            $testExitCode = $LASTEXITCODE
        } else {
            Write-Host "Running all Osprey unit tests..." -ForegroundColor Cyan
            & $vstestPath $targetArgs
            $testExitCode = $LASTEXITCODE
        }
        $testDuration = (Get-Date) - $testStart

        Write-Host ""
        if ($testExitCode -eq 0) {
            Write-Host "All tests passed in $($testDuration.TotalSeconds.ToString('F1'))s" -ForegroundColor Green
        } else {
            Write-Host "Tests FAILED in $($testDuration.TotalSeconds.ToString('F1'))s" -ForegroundColor Red
            exit $testExitCode
        }

        # Export the coverage snapshot to JSON and point at the summarizer
        if ($Coverage -and (Test-Path $coverageSnapshot)) {
            Write-Host ""
            Write-Host "Exporting coverage to JSON..." -ForegroundColor Cyan
            & $dotCoverExe report "/Source=$coverageSnapshot" "/Output=$CoverageOutputPath" "/ReportType=JSON"
            if ($LASTEXITCODE -eq 0 -and (Test-Path $CoverageOutputPath)) {
                Write-Host "Coverage exported:" -ForegroundColor Green
                Write-Host "  JSON:     $CoverageOutputPath" -ForegroundColor Gray
                Write-Host "  Snapshot: $coverageSnapshot" -ForegroundColor Gray
                Write-Host ""
                Write-Host "Summarize with:" -ForegroundColor Cyan
                Write-Host "  pwsh -File ./ai/scripts/Osprey/Summarize-Coverage.ps1 -CoverageJsonPath `"$CoverageOutputPath`"" -ForegroundColor Gray
            } else {
                Write-Host "Failed to export coverage JSON (exit $LASTEXITCODE)" -ForegroundColor Yellow
                Write-Host "Snapshot retained at: $coverageSnapshot" -ForegroundColor Gray
            }
        }
    }

    Write-Host ""
    Write-Host "All operations completed successfully" -ForegroundColor Green
}
finally {
    Set-Location $initialLocation
}
