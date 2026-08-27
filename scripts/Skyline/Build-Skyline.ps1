<#
.SYNOPSIS
    Build and test Skyline projects - for LLM-assisted IDE use

.DESCRIPTION
    Helper script for Cursor, VS Code + Copilot, VS Code + Claude Code to perform
    iterative builds and tests without requiring manual Visual Studio interaction.

.PARAMETER Target
    What to build: Solution, Skyline, SkylineTester, Test, TestData, TestFunctional, TestConnected, TestTutorial, TestPerf, Clean, Rebuild

.PARAMETER Configuration
    Debug or Release (default: Debug)

.PARAMETER RunTests
    Run tests after successful build (default: false)

.PARAMETER Verbosity
    MSBuild verbosity: quiet, minimal, normal, detailed, diagnostic (default: minimal)

.EXAMPLE
    .\Build-Skyline.ps1
    Build entire solution in Debug configuration (default - matches Visual Studio Ctrl+Shift+B)

.EXAMPLE
    .\Build-Skyline.ps1 -Target Skyline
    Build just the Skyline project in Debug configuration

.EXAMPLE
    .\Build-Skyline.ps1 -RunTests
    Build entire solution and run unit tests (Test.dll)

.EXAMPLE
    .\Build-Skyline.ps1 -QuickInspection
    Build and run quick inspection on modified projects only (~1-5 min, ideal for iteration)

.EXAMPLE
    .\Build-Skyline.ps1 -RunInspection
    Build entire solution and run full ReSharper code inspection (~5 min with jb 2026.1.3, pre-commit)

.EXAMPLE
    .\Build-Skyline.ps1 -RunTests -TestName CodeInspection
    Build and run the CodeInspection test specifically

.EXAMPLE
    .\Build-Skyline.ps1 -RunInspection -RunTests -TestName CodeInspection
    Pre-commit validation: Build, run full inspection, and run CodeInspection test

.EXAMPLE
    .\Build-Skyline.ps1 -Configuration Release
    Build entire solution in Release configuration

.NOTES
    Author: LLM-assisted development
    Requires: Visual Studio 2022, initial full build with bs.bat
#>

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("Solution", "Skyline", "SkylineTester", "Test", "TestData", "TestFunctional", "TestConnected", "TestTutorial", "TestPerf", "Clean", "Rebuild")]
    [string]$Target = "Solution",

    [Parameter(Mandatory=$false)]
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Debug",

    [Parameter(Mandatory=$false)]
    [switch]$RunTests = $false,

    [Parameter(Mandatory=$false)]
    [string]$TestName = $null,  # Specific test to run (e.g., "CodeInspection")

    [Parameter(Mandatory=$false)]
    [switch]$RunInspection = $false,  # Run ReSharper code inspection (full solution, ~5 min with jb 2026.1.3)

    [Parameter(Mandatory=$false)]
    [switch]$QuickInspection = $false,  # Run quick inspection on modified projects only (~1-5 min)

    [Parameter(Mandatory=$false)]
    [ValidateSet("quiet", "minimal", "normal", "detailed", "diagnostic")]
    [string]$Verbosity = "minimal",

    [Parameter(Mandatory=$false)]
    [string]$SourceRoot = $null,  # Path to pwiz root (auto-detected if not specified)

    [Parameter(Mandatory=$false)]
    [switch]$Summary = $false,  # Show only errors and final result (suppresses verbose build output)

    [Parameter(Mandatory=$false)]
    [ValidateSet("Auto", "Net472", "Net8")]
    [string]$Framework = "Auto",  # Which build path to use. Auto detects it from Skyline.csproj.

    [Parameter(Mandatory=$false)]
    [switch]$VendorLicenses = $false  # net8 only: pass -p:IAgreeToVendorLicenses=true so the
                                     # pwiz-sharp vendor projects link their real readers
)

# Ensure UTF-8 output for status symbols (must be set before any Write-Host)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Script location: ai/scripts/Skyline/
# Target: pwiz_tools/Skyline/
$scriptRoot = Split-Path -Parent $PSCommandPath
$aiRoot = Split-Path -Parent (Split-Path -Parent $scriptRoot)  # ai/

# Auto-detect pwiz root location
if ($SourceRoot) {
    # Resolve to absolute path (relative paths break after Set-Location)
    $pwizRoot = (Resolve-Path $SourceRoot).Path
} else {
    # Try sibling mode first: ai/ and pwiz/ are siblings under common parent
    $siblingPath = Join-Path (Split-Path -Parent $aiRoot) 'pwiz'
    # Then try child mode: ai/ is inside pwiz/
    $childPath = Split-Path -Parent $aiRoot

    if (Test-Path (Join-Path $siblingPath 'pwiz_tools')) {
        $pwizRoot = $siblingPath
    } elseif (Test-Path (Join-Path $childPath 'pwiz_tools')) {
        $pwizRoot = $childPath
    } else {
        Write-Error "Cannot find pwiz_tools. Tried:`n  Sibling mode: $siblingPath`n  Child mode: $childPath`nUse -SourceRoot to specify the pwiz root directory."
        exit 1
    }
}
$skylineRoot = Join-Path $pwizRoot 'pwiz_tools/Skyline'
$initialLocation = Get-Location

# Register this build as in flight. The marker is removed in the finally block
# below, so one that outlives the process marks a build killed by a restart --
# which is what the next session start reports. Never fatal.
$runMarker = $null
try {
    $stateScript = Join-Path $aiRoot 'scripts/session/SessionState.ps1'
    if (Test-Path -LiteralPath $stateScript) {
        . $stateScript
        $runMarker = Write-PwizRunMarker -Kind 'build' -Name $Target `
            -Checkout (Get-PwizCheckoutName $pwizRoot) `
            -CommandLine "$PSCommandPath $($MyInvocation.BoundParameters.GetEnumerator() | ForEach-Object { "-$($_.Key) $($_.Value)" })"
    }
}
catch { }

try {
    Set-Location $skylineRoot

    # Synchronize ReSharper DotSettings (canonical baseline Skyline -> batch tools)
    $syncScript = Join-Path $scriptRoot 'scripts/Sync-DotSettings.ps1'
    if (Test-Path $syncScript) {
        Write-Host 'Synchronizing DotSettings...' -ForegroundColor Cyan
        & $syncScript -SourceRoot $pwizRoot
    } else {
        Write-Host 'Sync-DotSettings.ps1 not found; skipping settings sync.' -ForegroundColor Yellow
    }

# Fix line endings in modified files (CRLF is project standard, but LLM tools may introduce LF-only)
# This is fast because it only processes files in 'git status' (modified/added)
# Run from repo root so git status works correctly
$repoRoot = (git rev-parse --show-toplevel 2>$null)
if ($repoRoot) {
    $fixCrlfScript = Join-Path $repoRoot "ai\scripts\fix-crlf.ps1"
    if (Test-Path $fixCrlfScript) {
        Write-Host "Checking line endings in modified files..." -ForegroundColor Cyan
        Push-Location $repoRoot
        try {
            & $fixCrlfScript
            if ($LASTEXITCODE -ne 0) {
                Write-Host "`n⚠️  Line ending fix failed - some files may still have LF-only line endings" -ForegroundColor Yellow
                Write-Host "This may cause large Git diffs. Consider running: .\ai\scripts\fix-crlf.ps1`n" -ForegroundColor Gray
            }
        }
        finally {
            Pop-Location
        }
    }
}

# Check for running test processes that would block the build
# Only block on processes running from THIS build directory (not other installations like D:\Nightly)
# Exclude SkylineMcpServer - it does not lock build outputs and killing it breaks active MCP sessions
$testProcesses = Get-Process -Name 'SkylineTester', 'TestRunner', 'Skyline*' -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -ne 'SkylineMcpServer' }
$blockingProcesses = @()
$skylineRootNormalized = $skylineRoot.Replace('/', '\').TrimEnd('\').ToLower()

foreach ($proc in $testProcesses) {
    try {
        $procPath = $proc.MainModule.FileName
        if ($procPath) {
            $procPathNormalized = $procPath.Replace('/', '\').ToLower()
            if ($procPathNormalized.StartsWith($skylineRootNormalized)) {
                $blockingProcesses += $proc
            }
        }
    } catch {
        # Can't get path (access denied, etc.) - skip this process
    }
}

if ($blockingProcesses) {
    $processNames = ($blockingProcesses | Select-Object -ExpandProperty Name -Unique) -join ', '
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host "⚠️  BUILD BLOCKED - Running processes detected" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "The following processes may lock build output files:" -ForegroundColor Yellow
    $blockingProcesses | ForEach-Object {
        Write-Host "  - $($_.Name) (PID: $($_.Id))" -ForegroundColor Gray
    }
    Write-Host ""
    Write-Host "[LLM-AGENT-ACTION-REQUIRED]" -ForegroundColor Cyan
    Write-Host "Ask the developer: 'May I stop $processNames to proceed with the build?'" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "If approved, run:" -ForegroundColor Gray
    Write-Host "  Get-Process -Name 'SkylineTester','TestRunner','Skyline*' -ErrorAction SilentlyContinue | Where-Object { `$_.Name -ne 'SkylineMcpServer' } | Stop-Process -Force" -ForegroundColor White
    Write-Host ""
    exit 2  # Special exit code indicating process block (not build failure)
}

$isNet8 = $false
if ($Framework -eq 'Net8') {
    $isNet8 = $true
} elseif ($Framework -eq 'Auto') {
    $skylineCsprojPath = Join-Path $skylineRoot 'Skyline.csproj'
    if (Test-Path -LiteralPath $skylineCsprojPath) {
        # Any modern (SDK-style) TFM, not a literal net8.0 - the tree already moved
        # net8 -> net10 once and a hard-coded match silently fell back to net472.
        if ((Get-Content -LiteralPath $skylineCsprojPath -Raw) -match '<TargetFrameworks?>[^<]*(net(?:[5-9]|\d{2,})\.0[^;<]*)') {
            $isNet8 = $true
            $script:SdkTfm = $Matches[1]
        }
    }
}

# MSBuild discovery is the net472 path only. On net8 we shell out to dotnet, and a
# machine with the .NET SDK but no Visual Studio is precisely what that path is for -
# running vswhere there would hard-exit before reaching the build that would have worked.
if (-not $isNet8) {
    # Find MSBuild using vswhere
    $vswherePath = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $vswherePath)) {
        Write-Error "vswhere.exe not found. Is Visual Studio 2022 installed?"
        exit 1
    }

    $vsPath = & $vswherePath -latest -products * -requires Microsoft.Component.MSBuild -property installationPath
    if (-not $vsPath) {
        Write-Error "Visual Studio 2022 with MSBuild not found"
        exit 1
    }

    $msbuild = "$vsPath\MSBuild\Current\Bin\amd64\MSBuild.exe"
    if (-not (Test-Path $msbuild)) {
        Write-Error "MSBuild not found at: $msbuild"
        exit 1
    }

    Write-Host "Using MSBuild: $msbuild" -ForegroundColor Cyan
} else {
    Write-Host "Framework: net8 (detected: $Framework); building with dotnet" -ForegroundColor Cyan
}

# ---------------------------------------------------------------------------
# net472 vs net8 build path.
#
# Auto-detection keys on Skyline.csproj declaring a net8 target framework: true on
# the pwiz-sharp branch, false on master. On net8 we build the same explicit project
# list pwiz_tools/Skyline/build.bat uses, because Skyline.sln also carries the net472
# leg, which that branch does not keep green.
# ---------------------------------------------------------------------------
# Determine MSBuild target
$Platform = "x64"
$buildArgs = @(
    "Skyline.sln"
)

# Add target parameter only for specific targets
# "Solution" builds entire solution (default Visual Studio behavior - no /t: parameter)
if ($Target -ne "Solution") {
    $msbuildTarget = switch ($Target) {
        "Skyline" { "Skyline" }
        "SkylineTester" { "SkylineTester" }
        "Test" { "Test" }
        "TestData" { "TestData" }
        "TestFunctional" { "TestFunctional" }
        "TestConnected" { "TestConnected" }
        "TestTutorial" { "TestTutorial" }
        "TestPerf" { "TestPerf" }
        "Clean" { "Clean" }
        "Rebuild" { "Rebuild" }
    }
    $buildArgs += "/t:$msbuildTarget"
}

# Add common build parameters
$buildArgs += @(
    "/p:Configuration=$Configuration"
    "/p:Platform=$Platform"
    "/nologo"
    "/verbosity:$Verbosity"
)

if ($isNet8) {
    $verbLabel = if ($Target -eq 'Clean') { "dotnet clean" } elseif ($Target -eq 'Rebuild') { "dotnet build --no-incremental" } else { "dotnet build" }
    Write-Host "`n$Target ($Configuration, $SdkTfm) via $verbLabel" -ForegroundColor Yellow
} else {
    Write-Host "`nBuilding: $Target ($Configuration|$Platform)" -ForegroundColor Yellow
    Write-Host "Command: & `"$msbuild`" $($buildArgs -join ' ')`n" -ForegroundColor Gray
}

# Execute build
$buildStart = Get-Date
if ($isNet8) {
    # Same project list pwiz_tools/Skyline/build.bat builds. Skyline.csproj pulls in every
    # ProjectReference; the test projects add the suites; TestRunner is the harness.
    $net8Projects = @(
        'Skyline.csproj'
        'CommonTest\CommonTest.csproj'
        'Test\Test.csproj'
        'TestData\TestData.csproj'
        'TestFunctional\TestFunctional.csproj'
        'TestConnected\TestConnected.csproj'
        'TestRunner\TestRunner.csproj'
    )
    if ($Target -eq 'Skyline') {
        $net8Projects = @('Skyline.csproj')
    } elseif ($Target -notin @('Solution', 'Rebuild', 'Clean')) {
        $net8Projects = @("$Target\$Target.csproj")
    }

    # Clean and Rebuild need real dotnet verbs. Without these, -Target Clean ran a
    # full build and reported success having deleted nothing.
    $net8Verb = 'build'
    $net8Extra = @()
    if ($Target -eq 'Clean') { $net8Verb = 'clean' }
    elseif ($Target -eq 'Rebuild') { $net8Extra = @('--no-incremental') }

    # The vendor projects gate real reader code on this property. Without it some types
    # (e.g. the Waters lockmass refiners) are compiled out, so anything referencing them
    # fails to build. If the developer has already run pwiz-sharp's
    # i-agree-to-the-vendor-licenses.bat, the gitignored props file sets it for us.
    $userProps = Join-Path $pwizRoot 'pwiz-sharp\Directory.Build.user.props'
    $vendorAgreed = $VendorLicenses -or (Test-Path -LiteralPath $userProps)
    # Platform matters as much as Configuration. Without it dotnet builds AnyCPU into
    # bin\<Config>\<TFM>, while Visual Studio builds x64 into bin\x64\<Config>\<TFM> - two output
    # trees for the same source, and code that resolves a sibling project's binary by path then
    # finds whichever one happens to be there. That is how a stale AnyCPU TestRunner satisfied
    # SkylineTester's staging check on 2026-08-26 after an x64 rebuild, so the run used a binary
    # four hours older than the source and failed on an argument it had never heard of.
    $net8Props = @("/p:Configuration=$Configuration", "/p:Platform=$Platform")
    if ($VendorLicenses) {
        $net8Props += '/p:IAgreeToVendorLicenses=true'
    }
    if (-not $vendorAgreed) {
        Write-Host "Vendor support DISABLED - vendor readers build in no-vendor mode." -ForegroundColor Yellow
        Write-Host "Pass -VendorLicenses, or run pwiz-sharp\i-agree-to-the-vendor-licenses.bat once." -ForegroundColor Gray
    }

    if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
        Write-Host "dotnet not found on PATH - the net8 build path needs the .NET SDK." -ForegroundColor Red
        exit 1
    }

    $buildExitCode = 0
    $buildOutput = @()
    foreach ($proj in $net8Projects) {
        Write-Host "dotnet $net8Verb $proj ($Configuration, $SdkTfm)" -ForegroundColor Cyan
        $dotnetArgs = @($net8Verb, $proj, '-f', $SdkTfm, '-nologo') + $net8Extra + $net8Props + @("-v:$Verbosity")
        if ($Summary) {
            $buildOutput += & dotnet $dotnetArgs 2>&1
        } else {
            & dotnet $dotnetArgs
        }
        if ($LASTEXITCODE -ne 0) {
            $buildExitCode = $LASTEXITCODE
            break
        }
    }
} elseif ($Summary) {
    $buildOutput = & $msbuild $buildArgs 2>&1
    $buildExitCode = $LASTEXITCODE
} else {
    & $msbuild $buildArgs
    $buildExitCode = $LASTEXITCODE
}
$buildDuration = (Get-Date) - $buildStart

if ($buildExitCode -ne 0) {
    if ($Summary) {
        # Show only error lines from captured output
        $buildOutput | Where-Object { $_ -match '(^|\s)error(\s+[A-Z]+[0-9]+)?\s*:|Build FAILED' } | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    }
    Write-Host "`n❌ Build FAILED (exit code: $buildExitCode) in $($buildDuration.TotalSeconds.ToString('F1'))s" -ForegroundColor Red
    exit $buildExitCode
}

Write-Host "`n✅ Build succeeded in $($buildDuration.TotalSeconds.ToString('F1'))s" -ForegroundColor Green

# Run tests if requested
if ($RunTests -and $Target -ne "Clean") {
    # The SDK-style leg runs from the flat staging directory, produced by staging rather
    # than by the build. Stage-Tests.ps1 is the branch's own script - build.bat
    # calls it the same way before every test pass.
    if ($isNet8) {
        $outputDir = "bin\staging\$Configuration"
        $stageScript = Join-Path $skylineRoot 'Stage-Tests.ps1'
        if (-not (Test-Path -LiteralPath $stageScript)) {
            # Fail rather than fall through: without staging the run silently uses whatever
            # is already in the output dir, i.e. the previous build.
            Write-Host "Staging script not found: $stageScript" -ForegroundColor Red
            exit 1
        }
        Write-Host "Staging test binaries..." -ForegroundColor Cyan
        & pwsh -NoProfile -File $stageScript -Configuration $Configuration
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Stage-Tests.ps1 failed (exit $LASTEXITCODE)" -ForegroundColor Red
            exit 1
        }
    } else {
        $outputDir = "bin\$Platform\$Configuration"
    }
    $testRunner = "$outputDir\TestRunner.exe"
    
    if (-not (Test-Path $testRunner)) {
        Write-Warning "TestRunner.exe not found at: $testRunner"
        Write-Warning "Build the TestRunner project first or skip -RunTests"
        exit 1
    }
    
    # Determine which test DLL to run
    $testDll = switch ($Target) {
        "Solution" { "Test.dll" }  # Default to fast unit tests when building entire solution
        "Test" { "Test.dll" }
        "TestData" { "TestData.dll" }
        "TestFunctional" { "TestFunctional.dll" }
        "TestConnected" { "TestConnected.dll" }
        "TestTutorial" { "TestTutorial.dll" }
        "TestPerf" { "TestPerf.dll" }
        default { "Test.dll" }
    }
    
    # If specific test name provided, use it; otherwise run all tests in DLL
    $testParam = if ($TestName) { "test=$TestName" } else { "test=$testDll" }
    
    $testLogName = $testDll -replace '\.dll$', '.log'
    $testLog = "$outputDir\$testLogName"
    
    if ($TestName) {
        Write-Host "`nRunning specific test: $TestName" -ForegroundColor Yellow
    } else {
        Write-Host "`nRunning tests: $testDll" -ForegroundColor Yellow
    }
    Write-Host "Test log: $testLog`n" -ForegroundColor Gray
    
    Push-Location $outputDir
    try {
        $testStart = Get-Date
        if ($Summary) {
            & .\TestRunner.exe log=$testLogName buildcheck=1 $testParam > $null 2>&1
        } else {
            & .\TestRunner.exe log=$testLogName buildcheck=1 $testParam
        }
        $testExitCode = $LASTEXITCODE
        $testDuration = (Get-Date) - $testStart

        if ($testExitCode -ne 0) {
            Write-Host "`n❌ Tests FAILED (exit code: $testExitCode) in $($testDuration.TotalSeconds.ToString('F1'))s" -ForegroundColor Red
            Write-Host "Log file: $testLog" -ForegroundColor Gray
            if ($Summary) {
                # Show only failure lines and first exception from log
                Get-Content $testLogName | Where-Object { $_ -match 'FAILED|Exception:|Assert\.' } |
                    Select-Object -First 10 | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
            }
            exit $testExitCode
        }

        Write-Host "`n✅ All tests passed in $($testDuration.TotalSeconds.ToString('F1'))s" -ForegroundColor Green
    }
    finally {
        Pop-Location
    }
}

# Helper function to get modified projects from git
function Get-ProjectNameFromPath {
    param(
        [string]$FullPath,
        [string]$RepoRoot
    )

    $currentDir = Split-Path $FullPath -Parent
    while ($currentDir -and $currentDir.StartsWith($RepoRoot)) {
        $folderName = Split-Path $currentDir -Leaf
        if (-not [string]::IsNullOrWhiteSpace($folderName)) {
            $candidateCsproj = Join-Path $currentDir "$folderName.csproj"
            if (Test-Path $candidateCsproj) {
                return $folderName
            }
        }
        $parentDir = Split-Path $currentDir -Parent
        if ($parentDir -eq $currentDir) {
            break
        }
        $currentDir = $parentDir
    }

    return $null
}

function Get-ModifiedProjects {
    try {
        # Get modified files from git (excluding deleted files)
        $modifiedFiles = git diff --name-only HEAD 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Not a git repository or git not available - inspecting all projects"
            return $null
        }
        
        if (-not $modifiedFiles) {
            Write-Host "No modified files detected in git working directory" -ForegroundColor Yellow
            return @()
        }

        $repoRoot = (git rev-parse --show-toplevel 2>$null)
        if (-not $repoRoot) {
            Write-Warning "Unable to determine repository root - inspecting all projects"
            return $null
        }
        $repoRoot = [System.IO.Path]::GetFullPath($repoRoot.Trim())
        
        # Directories to skip (documentation, build artifacts)
        $skipDirs = @('ai', 'bin', 'obj', 'Executables')
        
        # Map files to project names
        $projects = @{}
        foreach ($file in $modifiedFiles) {
            # Only consider C# source files
            if ($file -notmatch '\.(cs|csproj|resx)$') {
                continue
            }
            
            # Normalize to forward slashes and skip obvious non-code directories
            $normalizedPath = $file -replace '\\', '/'
            if ($normalizedPath -match '^pwiz_tools/Skyline/(ai|bin|obj)/') {
                continue
            }
            
            $fullPath = if ([System.IO.Path]::IsPathRooted($file)) {
                [System.IO.Path]::GetFullPath($file)
            }
            else {
                [System.IO.Path]::GetFullPath((Join-Path $repoRoot $file))
            }

            if (-not (Test-Path $fullPath)) {
                continue
            }

            $projectName = Get-ProjectNameFromPath -FullPath $fullPath -RepoRoot $repoRoot

            if (-not $projectName) {
                # As a fallback, try to map files under Skyline root to the Skyline project
                if ($normalizedPath -match '^pwiz_tools/Skyline/' -or $normalizedPath -notmatch '^pwiz_tools/') {
                    $projectName = "Skyline"
                }
            }

            if ($projectName -and ($skipDirs -notcontains $projectName)) {
                $projects[$projectName] = $true
            }
        }
        
        $projectList = @($projects.Keys)
        if ($projectList.Count -gt 0) {
            Write-Host "Detected $($projectList.Count) modified project(s): $($projectList -join ', ')" -ForegroundColor Cyan
        }
        else {
            Write-Host "No C# code changes detected (only documentation/artifacts modified)" -ForegroundColor Yellow
        }
        return $projectList
    }
    catch {
        Write-Warning "Error detecting modified projects: $_"
        return $null
    }
}

# Run ReSharper code inspection if requested
if (($RunInspection -or $QuickInspection) -and $Target -ne "Clean") {
    $isQuickMode = $QuickInspection -and -not $RunInspection
    $modeLabel = if ($isQuickMode) { "Quick inspection (modified projects only)" } else { "Full solution inspection" }
    
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Running ReSharper code inspection" -ForegroundColor Cyan
    Write-Host "Mode: $modeLabel" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    
    # Check for ReSharper .NET global tool (jb command)
    try {
        $jbPath = & where.exe jb 2>$null
        if (-not $jbPath) {
            throw "jb command not found"
        }
    } catch {
        Write-Host "`n❌ ReSharper command-line tools not installed" -ForegroundColor Red
        Write-Host "`nTo enable code inspection, install ReSharper CLI tools:" -ForegroundColor Yellow
        Write-Host "  dotnet tool install -g JetBrains.ReSharper.GlobalTools" -ForegroundColor Cyan
        Write-Host "`nDocumentation: https://www.jetbrains.com/help/resharper/ReSharper_Command_Line_Tools.html" -ForegroundColor Gray
        Write-Host "`nSkipping code inspection...`n" -ForegroundColor Yellow
    }
    
    if ($jbPath) {
        
        # The net472 path builds into bin\<Platform>\<Config>; the net8 path stages into
        # bin\staging\<Config> and never creates the former. Writing the report into a
        # directory the build did not create was half of why this block used to refuse to run on
        # net8 at all.
        $inspectionOutput = if ($isNet8) {
            "bin\staging\$Configuration\InspectCodeOutput.xml"
        } else {
            "bin\$Platform\$Configuration\InspectCodeOutput.xml"
        }
        $inspectionOutputDir = Split-Path -Parent $inspectionOutput
        if (-not (Test-Path $inspectionOutputDir)) {
            New-Item -ItemType Directory -Path $inspectionOutputDir -Force | Out-Null
        }
        $dotSettings = "Skyline.sln.DotSettings"

        # The other half of the old refusal was "jb --no-build against Skyline.sln, which the net8
        # path never builds". That one is real, and worse than it sounds: inspectcode reports the
        # UNION of every TargetFramework a project declares, so it analyses the net472 leg too -
        # and on this branch the net472 leg does not resolve, because the pwiz-sharp vendor
        # projects (Thermo, Waters, Sciex, Agilent, Bruker, Shimadzu, UIMF, UNIFI, ...) are only
        # built for net8. Measured without the pin below: 161,478 issues, of which 149,436 were
        # CSharpErrors - "Cannot resolve symbol", "type is defined in an assembly that is not
        # referenced" - i.e. 92% of the report was one broken leg, and the 4,585
        # RedundantUsingDirective hits were the same cascade wearing a different hat (a using
        # looks unused when the types behind it will not resolve).
        #
        # So pin the analysis to the framework this build path actually produced. That is the
        # only leg this branch keeps green, and an unpinned run is not a baseline, it is noise.
        $net8InspectionTfm = $SdkTfm
        if ($isNet8) {
            $inspectArgsTfm = "--properties=TargetFramework=$net8InspectionTfm"
            Write-Host "Pinning inspection to TargetFramework=$net8InspectionTfm" -ForegroundColor Gray
            Write-Host "  (inspectcode analyses every declared TFM; the net472 leg of this branch" -ForegroundColor Gray
            Write-Host "   does not resolve, and swamps the report with unresolved-symbol errors.)" -ForegroundColor Gray
        }
        
        # Set up persistent cache directory for faster subsequent runs
        # Located in bin/ so it's automatically ignored by git and cleaned by clean.bat
        $cacheDir = "bin\.inspectcode-cache"
        if (-not (Test-Path $cacheDir)) {
            New-Item -ItemType Directory -Path $cacheDir | Out-Null
            Write-Host "Created inspection cache directory: $cacheDir" -ForegroundColor Gray
        }
        
        # Determine which projects to inspect
        $projectFilter = @()
        if ($isQuickMode) {
            $modifiedProjects = Get-ModifiedProjects
            if ($modifiedProjects -eq $null) {
                # Git detection failed, fall back to full inspection
                Write-Warning "Falling back to full solution inspection"
            }
            elseif ($modifiedProjects.Count -eq 0) {
                Write-Host "No modified projects - skipping inspection" -ForegroundColor Yellow
                $jbPath = $null  # Skip inspection
            }
            else {
                $projectFilter = $modifiedProjects
            }
        }
        
        if ($jbPath) {
            $inspectStart = Get-Date
            $perProjectEstimate = 2
            $skylineEstimate = 4   # Measured ~4.2 min for --project=Skyline alone, jb 2026.1.3 (full solution is ~5 min)
            $estimatedTime = if ($projectFilter.Count -gt 0) {
                $hasSkyline = $projectFilter -contains "Skyline"
                if ($hasSkyline) {
                    $totalEstimate = $skylineEstimate + ($projectFilter.Count - 1) * $perProjectEstimate
                    "~${skylineEstimate} minutes for Skyline + ~${perProjectEstimate} minutes per additional project (~$totalEstimate minutes total for $($projectFilter.Count) project(s))"
                }
                else {
                    $totalEstimate = [Math]::Max($perProjectEstimate, $projectFilter.Count * $perProjectEstimate)
                    "~${perProjectEstimate} minutes per project (~$totalEstimate minutes total for $($projectFilter.Count) project(s))"
                }
            } else {
                # Measured ~5 minutes for full solution with jb (JetBrains.ReSharper.GlobalTools) 2026.1.3,
                # cold or warm cache (the persistent --caches-home cache showed no measurable speedup).
                # Older tool versions were much slower (the prior "20-25 minutes" estimate); re-measure if jb is upgraded/downgraded.
                "typically ~5 minutes for full solution (jb 2026.1.3)"
            }
            Write-Host "`nRunning ReSharper code inspection ($estimatedTime)..." -ForegroundColor Cyan
            
            # Build inspectcode command
            $inspectArgs = @(
                "inspectcode", "Skyline.sln",
                "--profile=$dotSettings",
                "--output=$inspectionOutput",
                "--format=Xml",
                "--severity=WARNING",
                "--no-swea",
                "--no-build",  # Solution already built by MSBuild above
                "--caches-home=$cacheDir",  # Enable persistent caching
                "--properties=Configuration=$Configuration",
                "--verbosity=WARN"
            )

            if ($inspectArgsTfm) {
                $inspectArgs += $inspectArgsTfm
            }

            # Add project filters for quick mode
            if ($projectFilter.Count -gt 0) {
                foreach ($project in $projectFilter) {
                    $inspectArgs += "--project=$project"
                }
            }
            
            # Run inspection matching TeamCity configuration:
            # --severity WARNING: Only report warnings and errors (not suggestions/hints)
            # --format Xml: machine-readable output for the result parser below
            # --profile: Use solution settings, which automatically discovers project-specific .DotSettings
            #   (SkylineTester.csproj.DotSettings and TestRunner.csproj.DotSettings disable localization)
            # --no-swea: Disable solution-wide analysis (not needed for warnings)
            # --no-build: Skip build phase (solution already built by MSBuild above)
            # --caches-home: Use persistent cache for faster subsequent runs (IDE-like performance)
            # --project: Filter to specific projects (quick inspection mode only)
            # NOTE: Removed --no-buildin-settings to allow project-specific .DotSettings to be respected
            & jb $inspectArgs
            
            $inspectExitCode = $LASTEXITCODE
            $inspectDuration = (Get-Date) - $inspectStart

            # A crashed inspector leaves an empty report, and an empty report parses as "no
            # issues". jb has been seen to die inside CSharpErrorStageProcess and write a
            # zero-byte file; the batch-tool scripts then printed "All operations completed
            # successfully". That is the same green-gate-that-inspected-nothing this block used to
            # refuse to run on net8 for - so refuse here too, rather than only there.
            $inspectionSize = if (Test-Path $inspectionOutput) { (Get-Item $inspectionOutput).Length } else { -1 }
            if ($inspectExitCode -ne 0 -or $inspectionSize -le 0) {
                Write-Host "`n❌ Code inspection did not produce a usable report" -ForegroundColor Red
                if ($inspectionSize -lt 0) {
                    Write-Host "   $inspectionOutput was never written" -ForegroundColor Gray
                } elseif ($inspectionSize -eq 0) {
                    Write-Host "   $inspectionOutput is empty - the inspector exited before writing results" -ForegroundColor Gray
                }
                Write-Host "   jb exit code: $inspectExitCode" -ForegroundColor Gray
                exit 1
            }
        }
    }
    
    if ($jbPath) {
        
        # Validate inspection output. TeamCity's old OutputParser.exe
        # (Executables/LocalizationHelper) was retired in #4125 -- its checks were
        # folded into CodeInspectionTest. This parser enforces the same rule TeamCity
        # applies: fail on any WARNING- or ERROR-severity issue (zero tolerance).
        if (Test-Path $inspectionOutput) {
            try {
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

                Write-Host "`nInspection Results:" -ForegroundColor Cyan
                Write-Host "  Errors: $($errors.Count), Warnings: $($warnings.Count)" -ForegroundColor Gray

                if ($errors.Count -gt 0 -or $warnings.Count -gt 0) {
                    ($allIssues | Select-Object -First 20) | ForEach-Object {
                        $loc = if ($_.Line) { "$($_.File):$($_.Line)" } else { $_.File }
                        $color = if ($_.Severity -eq "ERROR") { "Red" } else { "Yellow" }
                        Write-Host "  [$($_.Severity)] $loc - $($_.Message)" -ForegroundColor $color
                    }
                    Write-Host "`n❌ Code inspection FAILED - $($errors.Count + $warnings.Count) issue(s) found in $($inspectDuration.TotalSeconds.ToString('F1'))s" -ForegroundColor Red
                    exit 1
                } else {
                    Write-Host "`n✅ Code inspection passed - zero warnings/errors in $($inspectDuration.TotalSeconds.ToString('F1'))s" -ForegroundColor Green
                }
            } catch {
                # Not a warning: an unparseable report means the gate has no result, and
                # continuing would report success on the strength of nothing.
                Write-Host "❌ Failed to parse inspection output: $_" -ForegroundColor Red
                exit 1
            }
        }
    }
}

    Write-Host "`n✅ All operations completed successfully" -ForegroundColor Green
    exit 0
}
finally {
    Set-Location $initialLocation
    if ($runMarker) { Remove-PwizRunMarker -Path $runMarker }
}

