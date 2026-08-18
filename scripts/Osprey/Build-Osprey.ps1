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

.PARAMETER TargetFramework
    Which test assembly to RUN. Note this does NOT limit what is COMPILED -
    Osprey.sln builds every target framework the projects declare, so a
    solution build compiles all of them regardless of this value.

    Which frameworks exist depends on the branch: Osprey multi-targeted
    net472;net8.0 until the ProteoWizard .NET 8 port (issue #4497) made it
    net8.0 only. Rather than pin a default that is wrong on one side of that,
    both this parameter and the ReSharper inspection's per-framework passes are
    reconciled against what pwiz_tools/Osprey/Directory.Build.props DECLARES.

    Declared, not discovered from bin/: switching to a branch that dropped a
    framework leaves the old bin/<tfm>/ output in place, and a test run against
    a stale assembly passes while testing code that is no longer in the tree.
    That is a silent green, which is worse than the error it would replace.

.PARAMETER VendorReader
    Build WITH vendor instrument-file reading. What that takes depends on the
    branch, and the switch resolves it from the frameworks Osprey declares:

      net8.0 only (issue #4497)  -> /p:IAgreeToVendorLicenses=true, which lets
        pwiz-sharp extract its encrypted vendor SDK archives. Nothing to stage:
        pwiz-sharp is a managed ProjectReference. Without the switch the vendor
        readers still compile, and a .raw fails at run time with "Thermo .raw
        reading requires the vendor SDK".

      still multi-targeting net472 -> the pwiz_data_cli path described below.

    Off by default either way.

    The net472 path (issue #4496): builds the net472 configuration WITH the
    ProteoWizard vendor-raw reader (/p:OspreyVendorReader=true), so Osprey
    otherwise builds with no ProteoWizard dependency at all.

    Requires pwiz_tools/Shared/ProteowizardWrapper to be built for x64 and its
    obj/x64 staged with pwiz_data_cli, which comes from a bjam build via the
    tracked quickbuild.bat (the exact invocation is printed if it is missing).
    This script verifies that up front and builds the wrapper for x64 if only
    that step is missing, because the failure mode otherwise is ~20 CS0234
    "namespace CLI does not exist" errors that say nothing about the real cause.

    It does NOT deploy the vendor runtime (the vendor APIs, the C/C++ runtimes
    and msparser) next to Osprey.exe - only the bjam target
    pwiz_tools/Osprey//Osprey installs those. So -VendorReader COMPILES the
    reader but the resulting Osprey cannot read a raw file until that target has
    run once in the checkout; it fails with "Could not load file or assembly
    'pwiz_data_cli.dll' or one of its dependencies". After one bjam run, this
    script is the fast way to iterate - the installed runtime files survive.

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

.EXAMPLE
    .\Build-Osprey.ps1 -VendorReader -RunTests
    Build with vendor raw reading enabled (needs a prior bjam build) and test
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
    [string]$CoverageOutputPath = "",

    [Parameter(Mandatory=$false)]
    [switch]$VendorReader = $false
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
# Projects place outputs under a TFM subdirectory: bin/x64/Release/net8.0/
# (and bin/x64/Release/net472/ on a branch that still multi-targets). Which ones
# this branch actually builds comes from Directory.Build.props - see the
# TargetFramework parameter notes for why this is not read off disk.
$testBinDir = Join-Path $ospreyRoot "Osprey.Test/bin/$Platform/$Configuration"
$declaredTfms = @()
$buildPropsPath = Join-Path $ospreyRoot 'Directory.Build.props'
if (Test-Path $buildPropsPath) {
    $buildPropsText = Get-Content -Path $buildPropsPath -Raw
    $tfmMatch = [regex]::Match($buildPropsText, '<TargetFrameworks?>([^<]+)</TargetFrameworks?>')
    if ($tfmMatch.Success) {
        $declaredTfms = @($tfmMatch.Groups[1].Value -split ';' |
            ForEach-Object { $_.Trim() } | Where-Object { $_ })
    }
}
if (-not $declaredTfms) {
    $declaredTfms = @($TargetFramework)
}
if ($TargetFramework -notin $declaredTfms) {
    # Never silently: a run on the framework you did not ask for is worth a line.
    Write-Host "Osprey does not target $TargetFramework on this branch; using $($declaredTfms[0])." -ForegroundColor Yellow
    $TargetFramework = $declaredTfms[0]
}
$testDll = Join-Path $testBinDir "$TargetFramework/Osprey.Test.dll"
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

    if ($VendorReader -and 'net472' -notin $declaredTfms) {
        # ProteoWizard .NET 8 port (issue #4497): Osprey reads pwiz-sharp directly,
        # as a managed ProjectReference. There is no wrapper to build and nothing to
        # stage - the only thing the switch still has to do is agree to the vendor
        # licenses, which is what unlocks pwiz-sharp's encrypted vendor SDK archives.
        # Without it the vendor readers compile in NO_VENDOR_SUPPORT mode and a .raw
        # fails at run time with "Thermo .raw reading requires the vendor SDK".
        $buildArgs += "/p:IAgreeToVendorLicenses=true"
        if (-not $Summary) {
            Write-Host "Vendor SDKs: ENABLED (pwiz-sharp, --i-agree-to-the-vendor-licenses)" -ForegroundColor Cyan
        }
    }
    elseif ($VendorReader) {
        # Vendor raw reading references the x64 ProteowizardWrapper build, which in
        # turn resolves pwiz_data_cli and the vendor assemblies out of its obj\x64.
        # Only a bjam build stages those, so check before handing MSBuild a build
        # that would fail with a wall of CS0234s naming none of this.
        $wrapperDir = Join-Path $pwizRoot 'pwiz_tools/Shared/ProteowizardWrapper'
        $stagedCli = Join-Path $wrapperDir "obj/$Platform/pwiz_data_cli.dll"
        if (-not (Test-Path $stagedCli)) {
            $addressModel = if ($Platform -eq 'x64') { 64 } else { 32 }
            $variant = if ($Configuration -eq 'Debug') { 'debug' } else { 'release' }
            Write-Host "-VendorReader needs pwiz_data_cli staged, but it is missing:" -ForegroundColor Red
            Write-Host "  $stagedCli"
            Write-Host ""
            Write-Host "Stage it with the tracked bjam entry point (from the pwiz root):" -ForegroundColor Yellow
            # quickbuild.bat is in the repo; b.bat / bs.bat are personal shortcuts
            # (gitignored) and do not exist on a fresh clone or on TeamCity, so the
            # portable invocation is spelled out here.
            #
            # This MUST be the Osprey target, not pwiz_data_cli. Building
            # pwiz\utility\bindings\CLI//pwiz_data_cli puts the DLL in build-nt-x86
            # and nothing under pwiz\ ever copies it to ProteowizardWrapper\obj -
            # so that command leaves the very check above still failing. The Osprey
            # target stages obj (through Skyline's install-native-dependencies),
            # builds the wrapper, and installs the vendor runtime next to
            # Osprey.exe, which is the part -VendorReader alone cannot do.
            Write-Host "  quickbuild.bat pwiz_tools\Osprey//Osprey ``"
            Write-Host "      --i-agree-to-the-vendor-licenses -j$env:NUMBER_OF_PROCESSORS ``"
            Write-Host "      toolset=msvc-14.5 address-model=$addressModel $variant --without-compassxtract"
            Write-Host ""
            Write-Host "Add --incremental --force-generate-version to skip the submodule" -ForegroundColor DarkGray
            Write-Host "update; --incremental alone disables Version.cpp generation and the" -ForegroundColor DarkGray
            Write-Host "build then fails on a missing Version.cpp. A full Skyline build" -ForegroundColor DarkGray
            Write-Host "stages obj too, as a side effect of install-native-dependencies." -ForegroundColor DarkGray
            exit 1
        }

        # The wrapper is a plain csproj that must be built for x64 separately: an
        # SDK-style project cannot pass Platform across a ProjectReference to an
        # old-style one, so Osprey.IO references the built DLL and it has to exist
        # first. Always invoke the build and let its own up-to-date check decide
        # (a couple of seconds when current). Do NOT try to outsmart it by
        # timestamping against the staged CLI: that misses edits to the wrapper's
        # own sources, which is how a stale ProteowizardWrapper.dll silently
        # invalidated a parity comparison during #4496.
        if (-not $Summary) {
            Write-Host "Building ProteowizardWrapper ($Configuration|$Platform) for -VendorReader" -ForegroundColor Cyan
        }
        & $msbuildPath (Join-Path $wrapperDir 'ProteowizardWrapper.csproj') `
            "/p:Configuration=$Configuration" "/p:Platform=$Platform" "/nologo" "/verbosity:$Verbosity"
        if ($LASTEXITCODE -ne 0) {
            Write-Host "ProteowizardWrapper build failed with exit code $LASTEXITCODE" -ForegroundColor Red
            exit $LASTEXITCODE
        }

        $buildArgs += "/p:OspreyVendorReader=true"
        if (-not $Summary) {
            Write-Host "Vendor raw reading: ENABLED (net472 only)" -ForegroundColor Cyan
        }
    }

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

        Write-Host "Inspecting Osprey.sln, one pass per target framework (typically 2-5 minutes)..." -ForegroundColor Cyan
        $inspectStart = Get-Date

        # inspectcode defaults to --target-framework "all frameworks", analyzing
        # every file once per framework in a single parallel pass. When it does that,
        # whether a file's inline "// ReSharper disable" region is honored comes out
        # nondeterministic: this gate reported either 0 or 9 warnings, at random, on an
        # unchanged SystemMemory.cs (measured ~47% red over 43 project-scope runs, and
        # never a partial count - the suppressions are applied wholesale or not at all).
        # Inspecting one framework per pass gives each pass a single preprocessor
        # context, which removes the race: 0/30 red measured. No suppression form in the
        # source fixes this - inline comments, [SuppressMessage], and even a compiler
        # #pragma are all dropped on a racing run. See GitHub issue #4379.
        #
        # The per-framework results are unioned below, so extra passes cost time but
        # lose no coverage: each pass reports its own branch of an #if, and together
        # they report exactly what a single all-frameworks pass reports. On a
        # single-target branch (net8.0 only, issue #4497) that is one pass and the
        # race cannot arise at all.
        #
        # Read from Directory.Build.props rather than hardcoded, because the set
        # differs by branch - see the TargetFramework parameter notes.
        $targetFrameworks = $declaredTfms

        # Inspection args otherwise match TeamCity configuration:
        # --severity WARNING: report warnings and errors only
        # --no-swea: disable solution-wide analysis
        # --no-build: solution already built by MSBuild above
        # --caches-home: persistent cache for faster subsequent runs
        $inspectionOutputs = @()
        foreach ($tfm in $targetFrameworks) {
            $tfmOutput = [System.IO.Path]::ChangeExtension($inspectionOutput, ".$tfm.xml")
            $inspectArgs = @(
                "inspectcode", $slnPath,
                "--profile=$dotSettings",
                "--output=$tfmOutput",
                "--format=Xml",
                "--severity=WARNING",
                "--no-swea",
                "--no-build",
                "--caches-home=$cacheDir",
                "--properties=Configuration=$Configuration",
                "--target-framework=$tfm",
                "--verbosity=WARN"
            )
            Write-Host "  target framework: $tfm" -ForegroundColor Gray
            & jb $inspectArgs

            if (-not (Test-Path $tfmOutput)) {
                Write-Host "Inspection output not found: $tfmOutput" -ForegroundColor Red
                exit 1
            }
            $inspectionOutputs += $tfmOutput
        }
        $inspectDuration = (Get-Date) - $inspectStart

        # Parse and union the XML results from every per-framework pass. Code shared by
        # both frameworks is reported once per pass, so de-duplicate on file/line/rule/
        # message; that keeps the counts a developer sees the same as before this became
        # a two-pass inspection. Issues that exist in only one framework's branch of an
        # #if survive because only exact duplicates are dropped.
        $allIssues = @()
        $seenIssues = @{}
        foreach ($outputPath in $inspectionOutputs) {
            [xml]$xml = Get-Content $outputPath
            $issueTypes = $xml.GetElementsByTagName("IssueType")
            $severities = @{}
            foreach ($issueType in $issueTypes) {
                $severities[$issueType.Id] = $issueType.Severity
            }

            $projects = $xml.GetElementsByTagName("Project")
            foreach ($project in $projects) {
                foreach ($issue in $project.ChildNodes) {
                    if ($issue.Name -eq "Issue") {
                        $severity = $severities[$issue.TypeId]
                        if ($severity -eq "WARNING" -or $severity -eq "ERROR") {
                            $issueKey = "$($issue.File)|$($issue.Line)|$($issue.TypeId)|$($issue.Message)"
                            if (-not $seenIssues.ContainsKey($issueKey)) {
                                $seenIssues[$issueKey] = $true
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
            Write-Host "Full details: $($inspectionOutputs -join ', ')" -ForegroundColor Gray
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
