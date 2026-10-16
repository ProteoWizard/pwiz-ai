<#
.SYNOPSIS
    Build and test the BiblioSpec C# port (pwiz_tools/BiblioSpec) from LLM-assisted IDEs.
.DESCRIPTION
    Builds pwiz_tools/BiblioSpec/test/BiblioSpec.Tests/BiblioSpec.Tests.csproj with the .NET SDK,
    which builds the port's library and its four CLI tools (BlibBuild, BlibFilter, BlibSearch,
    BlibToMs2) before it, and optionally runs the tests.

    Most of the suite runs the tools against the golden inputs under pwiz_tools/BiblioSpec/tests.
    BlibSchemaIdentity, the test that holds the port's BlibSchema and the Shared BiblioSpec.IO copy
    (the schema Osprey and CarafeSharp write .blib files through) identical member by member,
    needs nothing else, so an edit to either schema copy is gated with
    -RunTests -TestName BlibSchemaIdentity.

    The direct dotnet build/test commands are blocked in an AI session (Deny-DirectBuildTest.ps1);
    this script is the sanctioned route, as Build-CarafeSharp.ps1 is for CarafeSharp.
.PARAMETER Configuration
    Debug or Release (default: Release).
.PARAMETER RunTests
    Run BiblioSpec.Tests after building.
.PARAMETER TestName
    Run only tests whose fully qualified name contains this text.
.PARAMETER Summary
    Suppress detailed build output.
.PARAMETER SourceRoot
    Path to the pwiz root. Defaults to the pwiz checkout that is a sibling of this ai/ tree.
    Pass it explicitly in a worktree session, or the build silently tests the other tree.
.EXAMPLE
    pwsh -File ./ai/scripts/BiblioSpec/Build-BiblioSpec.ps1 -RunTests -TestName BlibSchemaIdentity
.EXAMPLE
    pwsh -File ./ai/scripts/BiblioSpec/Build-BiblioSpec.ps1 -Configuration Debug -RunTests
#>
param(
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Release",
    [switch]$RunTests = $false,
    [string]$TestName = $null,
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

$testProject = Join-Path $pwizRoot 'pwiz_tools/BiblioSpec/test/BiblioSpec.Tests/BiblioSpec.Tests.csproj'
if (-not (Test-Path $testProject)) {
    Write-Error "BiblioSpec.Tests.csproj not found at: $testProject"
    exit 1
}
Write-Host "BiblioSpec port: $(Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $testProject)))" -ForegroundColor Gray

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

$verbosity = if ($Summary) { "quiet" } else { "minimal" }

Write-Host "Building: BiblioSpec.Tests.csproj ($Configuration)" -ForegroundColor Cyan
$buildStart = Get-Date
$buildArgs = @('build', $testProject, '-c', $Configuration, "-v:$verbosity", '-nologo')
& dotnet $buildArgs
$buildExit = $LASTEXITCODE
$buildDuration = (Get-Date) - $buildStart
if ($buildExit -ne 0) {
    Write-Host "Build FAILED (exit $buildExit) after $($buildDuration.TotalSeconds.ToString('F1'))s" -ForegroundColor Red
    exit $buildExit
}
Write-Host "Build succeeded in $($buildDuration.TotalSeconds.ToString('F1'))s" -ForegroundColor Green

if ($RunTests) {
    $testArgs = @('test', $testProject, '-c', $Configuration, '--no-build', '--nologo')
    if ($TestName) {
        $testArgs += @('--filter', "FullyQualifiedName~$TestName")
    }
    if ($Summary) {
        $testArgs += @('--logger', 'console;verbosity=minimal')
    } else {
        $testArgs += @('--logger', 'console;verbosity=normal')
    }
    Write-Host "Running tests: BiblioSpec.Tests$(if ($TestName) { " ($TestName)" })" -ForegroundColor Cyan
    & dotnet $testArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Tests FAILED" -ForegroundColor Red
        exit $LASTEXITCODE
    }
    Write-Host "All tests passed" -ForegroundColor Green
}
exit 0
