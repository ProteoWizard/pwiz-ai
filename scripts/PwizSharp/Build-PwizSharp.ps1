#requires -Version 7.0
<#
.SYNOPSIS
    Build a pwiz-sharp project and optionally run one test project - for LLM-assisted IDE use

.DESCRIPTION
    The pwiz-sharp tree (the C# port of the ProteoWizard core) is built and tested by
    pwiz-sharp/build.bat, which builds the whole solution and runs EVERY test project, and by
    pwiz-sharp/scripts/Run-Tests-Parallel.ps1, which assumes a prior build. Neither fits the
    edit-build-test loop on one vendor test project, which is what this script is for: build one
    project (or the solution), then run one test project with an optional test filter.

    Vendor licenses: the vendor projects gate their real readers on IAgreeToVendorLicenses. It is
    passed automatically when Directory.Build.user.props exists beside Pwiz.sln (created by
    i-agree-to-the-vendor-licenses.bat) or when -VendorLicenses is given; without
    either, vendor readers build in no-vendor mode and vendor tests come back Inconclusive.

.PARAMETER Project
    Project or solution to build, relative to pwiz-sharp/ (default: Pwiz.sln). Building only
    the test project you are about to run is much faster than the solution, e.g.
    pwiz/test/Sciex.Tests/Sciex.Tests.csproj

.PARAMETER RunTests
    Run tests after building. Requires -TestProject unless -Project is itself a test project.

.PARAMETER TestProject
    Test project to run, relative to pwiz-sharp/ (default: -Project when it is a *.Tests.csproj)

.PARAMETER Filter
    dotnet test --filter expression, e.g. "Name~wiff2" or "FullyQualifiedName~ReaderSciexTests"

.PARAMETER Configuration
    Debug or Release (default: Release, matching build.bat and CI)

.PARAMETER VendorLicenses
    Pass -p:IAgreeToVendorLicenses=true even without Directory.Build.user.props

.PARAMETER NoVendorLicenses
    Pass -p:IAgreeToVendorLicenses=false, overriding Directory.Build.user.props, to build the
    way the Linux CI leg does: NativeVendorsAvailable false, vendor readers and their tests
    compiled out. This is the local check for "does it still build without the SDKs".

.PARAMETER Property
    Extra MSBuild properties, passed as -p:<value> to both build and test, e.g.
    -Property TreatWarningsAsErrors=false,MSBuildTreatWarningsAsErrors=false
    to collect every warning in one pass instead of stopping at the first project with one

.PARAMETER Rebuild
    Rebuild everything (--no-incremental). An incremental build does not recompile up-to-date
    projects, so it does not re-report their warnings - use this to confirm a warning-free tree.

.PARAMETER LogFile
    Also write a normal-verbosity MSBuild file log (every warning and error) to this path

.PARAMETER SourceRoot
    Path to the pwiz checkout root (auto-detected if not specified). Pwiz.sln is found at the
    checkout root (current layout) or under pwiz-sharp/ (older branches).

.PARAMETER Summary
    Show only errors, test results and the final line

.EXAMPLE
    .\Build-PwizSharp.ps1 -Project pwiz/test/Sciex.Tests/Sciex.Tests.csproj -RunTests -Filter "Name~wiff2" -Summary
    Build the Sciex test project (and what it references) and run only the wiff2 tests
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$Project = "Pwiz.sln",

    [Parameter(Mandatory=$false)]
    [switch]$RunTests = $false,

    [Parameter(Mandatory=$false)]
    [string]$TestProject = "",

    [Parameter(Mandatory=$false)]
    [string]$Filter = "",

    [Parameter(Mandatory=$false)]
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Release",

    [Parameter(Mandatory=$false)]
    [switch]$VendorLicenses = $false,

    [Parameter(Mandatory=$false)]
    [switch]$NoVendorLicenses = $false,

    [Parameter(Mandatory=$false)]
    [string[]]$Property = @(),

    [Parameter(Mandatory=$false)]
    [switch]$Rebuild = $false,

    [Parameter(Mandatory=$false)]
    [string]$LogFile = $null,

    [Parameter(Mandatory=$false)]
    [string]$SourceRoot = $null,

    [Parameter(Mandatory=$false)]
    [switch]$Summary = $false
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Script location: ai/scripts/PwizSharp/ - target: the directory holding Pwiz.sln, which is the
# pwiz checkout root since #4658 hoisted the C# port out of pwiz-sharp/
$scriptRoot = Split-Path -Parent $PSCommandPath
$aiRoot = Split-Path -Parent (Split-Path -Parent $scriptRoot)

function Find-SharpRoot([string]$checkoutRoot) {
    foreach ($candidate in @($checkoutRoot, (Join-Path $checkoutRoot 'pwiz-sharp'))) {
        if (Test-Path (Join-Path $candidate 'Pwiz.sln')) {
            return $candidate
        }
    }
    return $null
}

# The on-disk casing of a path. A mis-cased checkout path reaches MSBuild's project cache, and
# Roslyn's .editorconfig section matching is case-sensitive, so diagnostics the root
# .editorconfig demotes (WFO1000) come back as errors.
function Get-CanonicalPath([string]$path) {
    $info = [System.IO.DirectoryInfo]::new($path)
    if (-not $info.Parent) {
        return $info.FullName.ToUpperInvariant()
    }
    $name = ($info.Parent.GetFileSystemInfos($info.Name) | Select-Object -First 1).Name
    return Join-Path (Get-CanonicalPath $info.Parent.FullName) $name
}

if ($SourceRoot) {
    $pwizRoot = Get-CanonicalPath (Resolve-Path $SourceRoot).Path
    $sharpRoot = Find-SharpRoot $pwizRoot
    if (-not $sharpRoot) {
        Write-Error "No Pwiz.sln in $pwizRoot or $pwizRoot\pwiz-sharp - is this checkout on a branch that carries pwiz-sharp?"
        exit 1
    }
} else {
    $siblingPath = Join-Path (Split-Path -Parent $aiRoot) 'pwiz'
    $childPath = Split-Path -Parent $aiRoot
    $sharpRoot = (Find-SharpRoot $siblingPath) ?? (Find-SharpRoot $childPath)
    if (-not $sharpRoot) {
        Write-Error "Cannot find Pwiz.sln. Tried:`n  $siblingPath`n  $childPath`nUse -SourceRoot to specify the pwiz checkout root."
        exit 1
    }
}

if ($RunTests -and -not $TestProject) {
    if ($Project -match '\.Tests\.csproj$') {
        $TestProject = $Project
    } else {
        Write-Error "-RunTests needs -TestProject when -Project is not a test project."
        exit 1
    }
}

$userProps = Join-Path $sharpRoot 'Directory.Build.user.props'
$vendorAgreed = -not $NoVendorLicenses -and ($VendorLicenses -or (Test-Path -LiteralPath $userProps))
$props = @("-p:Configuration=$Configuration")
if ($NoVendorLicenses) {
    $props += '-p:IAgreeToVendorLicenses=false'
} elseif ($VendorLicenses) {
    $props += '-p:IAgreeToVendorLicenses=true'
}
foreach ($p in $Property) {
    $props += "-p:$p"
}

if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    Write-Host "dotnet not found on PATH - the .NET SDK is required." -ForegroundColor Red
    exit 1
}

Write-Host "pwiz-sharp: $sharpRoot" -ForegroundColor Cyan
Write-Host "  Project: $Project ($Configuration)" -ForegroundColor Gray
Write-Host "  Vendor licenses: $(if ($vendorAgreed) { 'agreed' } else { 'NOT agreed - vendor readers in no-vendor mode' })" -ForegroundColor $(if ($vendorAgreed) { 'Gray' } else { 'Yellow' })
if ($RunTests) {
    $filterText = if ($Filter) { " --filter '$Filter'" } else { "" }
    Write-Host "  Tests: $TestProject$filterText" -ForegroundColor Gray
}

$initialLocation = Get-Location
try {
    Set-Location $sharpRoot

    $buildStart = Get-Date
    $buildArgs = @('build', $Project, '-nologo') + $props + @('-v:minimal')
    if ($Rebuild) {
        $buildArgs += '--no-incremental'
    }
    if ($LogFile) {
        $buildArgs += @('-fl', "-flp:logfile=$([System.IO.Path]::GetFullPath($LogFile, $initialLocation.Path));verbosity=normal")
    }
    Write-Host "`ndotnet build $Project" -ForegroundColor Yellow
    if ($Summary) {
        $buildOutput = & dotnet @buildArgs 2>&1
        $buildExit = $LASTEXITCODE
        $buildOutput | Where-Object { $_ -match ': error |error [A-Z]+\d+:|Build FAILED' } | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    } else {
        & dotnet @buildArgs
        $buildExit = $LASTEXITCODE
    }
    $buildSeconds = [math]::Round(((Get-Date) - $buildStart).TotalSeconds, 1)
    if ($buildExit -ne 0) {
        Write-Host "`n❌ Build FAILED in ${buildSeconds}s (exit $buildExit)" -ForegroundColor Red
        exit $buildExit
    }
    Write-Host "✅ Build succeeded in ${buildSeconds}s" -ForegroundColor Green

    if (-not $RunTests) {
        exit 0
    }

    $testStart = Get-Date
    $testArgs = @('test', $TestProject, '--no-build', '-nologo') + $props + @('--logger:console;verbosity=normal')
    if ($Filter) {
        $testArgs += @('--filter', $Filter)
    }
    Write-Host "`ndotnet test $TestProject" -ForegroundColor Yellow
    if ($Summary) {
        $testOutput = & dotnet @testArgs 2>&1
        $testExit = $LASTEXITCODE
        # Per-test lines, failure detail, and the totals line
        $testOutput | Where-Object { $_ -match '^\s*(Passed|Failed|Skipped)\s|Error Message|Stack Trace|Assert\.|Inconclusive|^\s*Passed!|^\s*Failed!|Total tests|No test' } | ForEach-Object { Write-Host $_ }
    } else {
        & dotnet @testArgs
        $testExit = $LASTEXITCODE
    }
    $testSeconds = [math]::Round(((Get-Date) - $testStart).TotalSeconds, 1)
    if ($testExit -ne 0) {
        Write-Host "`n❌ Tests FAILED in ${testSeconds}s (exit $testExit)" -ForegroundColor Red
        exit $testExit
    }
    Write-Host "`n✅ Tests passed in ${testSeconds}s" -ForegroundColor Green
    exit 0
}
finally {
    Set-Location $initialLocation
}
