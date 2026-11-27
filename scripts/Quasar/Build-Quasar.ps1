<#
.SYNOPSIS
    Builds Quasar (pwiz_tools/Quasar), optionally runs its tests and the ReSharper
    zero-warning inspection. The pre-commit gate for Quasar work.

.DESCRIPTION
    Delegates the build and the tests to the in-repo pwiz_tools/Quasar/build.ps1, so a local
    run and a standalone pwiz build do the same thing, and adds what only a developer machine
    needs: checkout selection (-SourceRoot) and the ReSharper inspection, run the way
    Build-Osprey.ps1 runs it for Osprey (one target framework, warnings and errors only,
    no solution-wide analysis, per-checkout cache).

    The inspection reports issues in the Osprey projects Quasar.sln includes as well; only
    issues in Quasar's own files fail the gate here, since Osprey has its own gate.

.PARAMETER SourceRoot
    The pwiz checkout to build. Required in practice: Quasar lives on its own worktree
    (C:\Dev\pwiz-quasar on the machine where it started), not in the default checkout.

.PARAMETER Configuration
    Debug (default) or Release.

.PARAMETER RunTests
    Run Quasar.Test after the build.

.PARAMETER IAgreeToVendorLicenses
    Build pwiz-sharp's real vendor readers so Quasar can read raw files (passed to build.ps1).

.PARAMETER TestFilter
    A dotnet test filter, for example "FullyQualifiedName~EmgTest".

.PARAMETER ShowTestOutput
    Print what the tests write to the console, for diagnostics.

.PARAMETER RunInspection
    Run ReSharper inspectcode on Quasar.sln and fail on any warning or error in Quasar files.

.EXAMPLE
    pwsh -File ./ai/scripts/Quasar/Build-Quasar.ps1 -SourceRoot C:/Dev/pwiz-quasar -RunTests -RunInspection
#>
param(
    [string]$SourceRoot = $null,
    [ValidateSet('Debug','Release')] [string]$Configuration = 'Debug',
    [switch]$RunTests,
    [switch]$IAgreeToVendorLicenses,
    [string]$TestFilter = '',
    [switch]$ShowTestOutput,
    [switch]$RunInspection
)

$ErrorActionPreference = 'Stop'
$aiRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

if (-not $SourceRoot) {
    $SourceRoot = Join-Path (Split-Path -Parent $aiRoot) 'pwiz'
    Write-Host "No -SourceRoot given; using $SourceRoot" -ForegroundColor Yellow
}
$pwizRoot = (Resolve-Path $SourceRoot).Path
$quasarRoot = Join-Path $pwizRoot 'pwiz_tools/Quasar'
$buildScript = Join-Path $quasarRoot 'build.ps1'
if (-not (Test-Path $buildScript)) {
    Write-Error "No Quasar build script at $buildScript. Is $pwizRoot the checkout holding the Quasar branch?"
    exit 2
}

Write-Host "Quasar checkout: $pwizRoot" -ForegroundColor Cyan
$buildArgs = @('-NoProfile', '-File', $buildScript, '-Configuration', $Configuration, '-NoTests')
if ($IAgreeToVendorLicenses) {
    $buildArgs += '-IAgreeToVendorLicenses'
}
pwsh @buildArgs
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

if ($RunInspection) {
    $jbPath = & where.exe jb 2>$null
    if (-not $jbPath) {
        Write-Host "ReSharper command-line tools (jb) not installed" -ForegroundColor Red
        Write-Host "Install with: dotnet tool install -g JetBrains.ReSharper.GlobalTools" -ForegroundColor Yellow
        exit 1
    }

    $tmpDir = Join-Path $aiRoot '.tmp'
    $checkoutName = Split-Path -Leaf $pwizRoot
    $cacheDir = Join-Path $tmpDir (Join-Path '.inspectcode-cache' $checkoutName)
    New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
    $output = Join-Path $tmpDir "QuasarInspect-$checkoutName.xml"
    $slnPath = Join-Path $quasarRoot 'Quasar.sln'
    $dotSettings = Join-Path $quasarRoot 'Quasar.sln.DotSettings'

    # inspectcode resolves a project outside the solution (Osprey.IO, ProteowizardWrapper,
    # pwiz-sharp) through that project's OUTPUT assembly under bin\x64\<Configuration>. A solution
    # build does not write there (out-of-solution references build AnyCPU), so build the test
    # project, whose references reach every out-of-solution project, as a project build first,
    # the same fix Build-Osprey.ps1 uses.
    $testProj = Join-Path $quasarRoot 'Quasar.Test/Quasar.Test.csproj'
    $prebuildArgs = @($testProj, '/restore', "/p:Configuration=$Configuration", '/p:Platform=x64',
        '/p:NuGetAuditLevel=critical', '/nologo', '/verbosity:quiet')
    if ($IAgreeToVendorLicenses) {
        $prebuildArgs += '/p:IAgreeToVendorLicenses=true'
    }
    Write-Host "Building Quasar.Test.csproj (x64) so out-of-solution references exist where inspectcode resolves them" -ForegroundColor Cyan
    & dotnet msbuild @prebuildArgs | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Pre-inspection build of $testProj failed with exit code $LASTEXITCODE" -ForegroundColor Red
        exit $LASTEXITCODE
    }

    Write-Host "Inspecting Quasar.sln (typically 1-3 minutes)..." -ForegroundColor Cyan
    $inspectStart = Get-Date
    & jb inspectcode $slnPath "--profile=$dotSettings" "--output=$output" '--format=Xml' '--severity=WARNING' `
        '--no-swea' '--no-build' "--caches-home=$cacheDir" "--properties=Configuration=$Configuration;Platform=x64" `
        '--target-framework=net10.0' '--verbosity=WARN'
    if (-not (Test-Path $output)) {
        Write-Host "Inspection output not found: $output" -ForegroundColor Red
        exit 1
    }

    [xml]$xml = Get-Content $output
    $severities = @{}
    foreach ($issueType in $xml.GetElementsByTagName('IssueType')) {
        $severities[$issueType.Id] = $issueType.Severity
    }
    $issues = @()
    foreach ($project in $xml.GetElementsByTagName('Project')) {
        foreach ($issue in $project.ChildNodes) {
            if ($issue.Name -ne 'Issue') {
                continue
            }
            $severity = $severities[$issue.TypeId]
            if (($severity -eq 'WARNING' -or $severity -eq 'ERROR') -and $issue.File -notmatch '^\.\.\\Osprey\\') {
                $issues += [PSCustomObject]@{ File = $issue.File; Line = $issue.Line; TypeId = $issue.TypeId; Message = $issue.Message }
            }
        }
    }

    $seconds = ((Get-Date) - $inspectStart).TotalSeconds
    Write-Host ("Inspection completed in {0:F1}s" -f $seconds) -ForegroundColor Cyan
    if ($issues.Count -gt 0) {
        $issues | ForEach-Object { "{0}:{1}  {2}  {3}" -f $_.File, $_.Line, $_.TypeId, $_.Message } | Write-Host -ForegroundColor Yellow
        Write-Host "Full details: $output" -ForegroundColor Gray
        Write-Host "Code inspection FAILED - $($issues.Count) issue(s) in Quasar files" -ForegroundColor Red
        exit 1
    }
    Write-Host "Code inspection passed - zero warnings/errors in Quasar files" -ForegroundColor Green
}

if ($RunTests) {
    $testArgs = @('-NoProfile', '-File', $buildScript, '-Configuration', $Configuration, '-NoBuild')
    if ($TestFilter) {
        $testArgs += @('-TestFilter', $TestFilter)
    }
    if ($ShowTestOutput) {
        $testArgs += '-ShowTestOutput'
    }
    pwsh @testArgs
    exit $LASTEXITCODE
}
exit 0
