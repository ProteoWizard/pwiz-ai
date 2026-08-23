<#
.SYNOPSIS
    Finds tests that leak state between executions in one process (class-1 flakes).

.DESCRIPTION
    Runs the suite SERIALLY with loop=2 so every test executes twice in the SAME process,
    then reports tests that passed their first execution and failed a later one. That
    signature is a state leak, not a race: something the first execution left behind broke
    the second.

    Serial matters. Under parallelmode=server two executions of the same test can land on
    different worker processes, which is exactly the condition this is trying to create.

    This is the cheapest and most certain sweep in ai/docs/test-flakiness-method.md - it
    makes an otherwise invisible class of failure deterministic, for about the cost of two
    single-language suite runs. It would have caught TestWatersConnectExportMethodDlg
    (45% of executions overnight) with no soak and no statistics.

.PARAMETER SourceRoot
    Path to the pwiz checkout. Use forward slashes.

.PARAMETER Language
    Language to sweep. One is enough for state leaks; default en.

.PARAMETER TestName
    Optional subset (comma-separated) instead of the full test list.

.PARAMETER AnalyzeOnly
    Skip the run and just analyze an existing log. Use with -LogPath.

.PARAMETER LogPath
    Log to analyze. Defaults to the log the run writes.

.EXAMPLE
    pwsh -File ./ai/scripts/Skyline/Find-StateLeakTests.ps1 -SourceRoot C:/proj/pwiz-work1

.EXAMPLE
    pwsh -File ./ai/scripts/Skyline/Find-StateLeakTests.ps1 -SourceRoot C:/proj/pwiz-work1 -AnalyzeOnly -LogPath .\statesweep.log
#>
param(
    [Parameter(Mandatory=$false)][string]$SourceRoot = "C:/proj/pwiz-work1",
    [Parameter(Mandatory=$false)][string]$Language = "en",
    [Parameter(Mandatory=$false)][string]$TestName = "",
    [Parameter(Mandatory=$false)][switch]$AnalyzeOnly,
    [Parameter(Mandatory=$false)][string]$LogPath = ""
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not $LogPath) {
    $stagingDir = Join-Path $SourceRoot "pwiz_tools/Skyline/bin/staging-net8/Debug"
    $LogPath = Join-Path $stagingDir "StateLeakSweep.log"
}

if (-not $AnalyzeOnly) {
    $runArgs = @(
        '-File', (Join-Path $scriptDir 'Run-Tests.ps1'),
        '-SourceRoot', $SourceRoot,
        '-Language', $Language,
        '-Loop', '2',
        '-Summary'
    )
    if ($TestName) {
        $runArgs += @('-TestName', $TestName)
    } else {
        $runArgs += '-UseTestList'
    }

    Write-Host "Sweeping for state leaks: serial, loop=2, language=$Language" -ForegroundColor Cyan
    Write-Host "This runs every test twice in one process. Expect roughly two suite runs of wall clock."
    & pwsh @runArgs
    Write-Host ""
}

if (-not (Test-Path $LogPath)) {
    Write-Host "No log at $LogPath - pass -LogPath to point at the run's log." -ForegroundColor Yellow
    exit 1
}

# Test result lines look like:
#   [21:29] 2.14   SomeTestName    (en)   0 failures, 3.07/11.40/67.6 MB, 54/609 handles, 1 sec.
# The leading number before the dot is the PASS. The "N failures" field is a per-worker
# RUNNING TOTAL, not this execution's result, so it cannot be used to decide pass/fail -
# a rising total is what marks the execution where a failure occurred.
$linePattern = '^\s*\[[^\]]+\]\s+(?<pass>\d+)\.(?<idx>\d+)\s+(?<test>\S+)\s+\((?<lang>[^)]+)\)\s+(?<total>\d+) failures,'

$byTest = @{}
foreach ($line in Get-Content -LiteralPath $LogPath) {
    if ($line -match $linePattern) {
        $test = $Matches['test']
        $pass = [int]$Matches['pass']
        $total = [int]$Matches['total']
        if (-not $byTest.ContainsKey($test)) { $byTest[$test] = New-Object System.Collections.ArrayList }
        [void]$byTest[$test].Add([pscustomobject]@{ Pass = $pass; RunningTotal = $total })
    }
}

$leaks = New-Object System.Collections.ArrayList
$everFailed = New-Object System.Collections.ArrayList
foreach ($test in $byTest.Keys) {
    $execs = $byTest[$test] | Sort-Object Pass
    if ($execs.Count -lt 2) { continue }
    $first = $execs[0]
    $later = $execs[1..($execs.Count - 1)]
    # A rise in the running total on a later execution means that execution failed
    $laterFailed = $false
    $prev = $first.RunningTotal
    foreach ($e in $later) {
        if ($e.RunningTotal -gt $prev) { $laterFailed = $true }
        $prev = $e.RunningTotal
    }
    if ($laterFailed) {
        [void]$everFailed.Add($test)
        # First execution clean, a later one not: the state-leak signature
        if ($first.RunningTotal -eq 0) { [void]$leaks.Add($test) }
    }
}

Write-Host "Tests executed at least twice: $($byTest.Keys.Count)" -ForegroundColor Cyan
Write-Host "Tests where a later execution failed: $($everFailed.Count)"
Write-Host ""
if ($leaks.Count -eq 0) {
    Write-Host "No state-leak signatures found." -ForegroundColor Green
} else {
    Write-Host "STATE LEAK SUSPECTS - passed first, failed later in the same process:" -ForegroundColor Red
    $leaks | Sort-Object | ForEach-Object { Write-Host "  $_" }
    Write-Host ""
    Write-Host "Confirm one with:" -ForegroundColor Cyan
    Write-Host "  pwsh -File ./ai/scripts/Skyline/Run-Tests.ps1 -SourceRoot $SourceRoot -TestName <name> -Loop 3 -Summary"
    Write-Host "A confirmed leak fails deterministically from the second execution, not intermittently."
}
