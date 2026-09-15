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
    passed automatically when pwiz-sharp\Directory.Build.user.props exists (created by
    pwiz-sharp\i-agree-to-the-vendor-licenses.bat) or when -VendorLicenses is given; without
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

.PARAMETER SourceRoot
    Path to the pwiz checkout root (auto-detected if not specified)

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
    [string]$SourceRoot = $null,

    [Parameter(Mandatory=$false)]
    [switch]$Summary = $false
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Script location: ai/scripts/PwizSharp/ - target: <pwiz root>/pwiz-sharp/
$scriptRoot = Split-Path -Parent $PSCommandPath
$aiRoot = Split-Path -Parent (Split-Path -Parent $scriptRoot)

if ($SourceRoot) {
    $pwizRoot = (Resolve-Path $SourceRoot).Path
} else {
    $siblingPath = Join-Path (Split-Path -Parent $aiRoot) 'pwiz'
    $childPath = Split-Path -Parent $aiRoot
    if (Test-Path (Join-Path $siblingPath 'pwiz-sharp')) {
        $pwizRoot = $siblingPath
    } elseif (Test-Path (Join-Path $childPath 'pwiz-sharp')) {
        $pwizRoot = $childPath
    } else {
        Write-Error "Cannot find pwiz-sharp. Tried:`n  $siblingPath`n  $childPath`nUse -SourceRoot to specify the pwiz checkout root."
        exit 1
    }
}
$sharpRoot = Join-Path $pwizRoot 'pwiz-sharp'
if (-not (Test-Path (Join-Path $sharpRoot 'Pwiz.sln'))) {
    Write-Error "No Pwiz.sln under $sharpRoot - is this checkout on a branch that carries pwiz-sharp?"
    exit 1
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
