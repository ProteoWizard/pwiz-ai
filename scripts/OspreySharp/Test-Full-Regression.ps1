<#
.SYNOPSIS
    OspreySharp full regression: drives Test-Snapshot across both
    datasets and reports a single pass/fail summary.

.DESCRIPTION
    Wraps Test-Snapshot.ps1 to make the canonical OspreySharp-alone
    regression a one-command call.  Same-impl frozen-baseline gate --
    no Rust checkout needed, no cross-impl tolerance.  See
    Test-Snapshot.ps1 for the per-stage comparator details (SHA-256
    byte equality on stages 1-6, structured comparators on stage7 and
    blib).

    Modes (mutually exclusive switches):

      -Smoke     Stellar single-file only (~3 min).  Use this as a
                 lightweight pre-commit check after small changes that
                 only touched OspreySharp behavior.

      -Quick     Stellar single + Astral single (~10 min).  Use this
                 before opening a PR for ordinary changes -- exercises
                 both Stellar (unit-resolution) and Astral (HRAM)
                 binaries in single-file mode.

      (default)  Stellar all + Astral all (~70 min).  The full
                 regression gate.  Use this before merging or when an
                 algorithm-level change might cascade across files.

      -CreateSnapshot
                 Refresh the frozen baseline instead of comparing.
                 Use this once on master HEAD after an intentional
                 behavior change lands and the PR has been approved
                 by reviewers.  Records the current OspreySharp
                 binary SHA-256 and the source commit in the
                 manifest at the snapshot root.

    Both datasets always run in the chosen mode -- the user prompt
    behind this script said full regression must cover both Stellar
    and Astral.  If one dataset fails the other still runs (Test-
    Snapshot is invoked with -Continue to gather all failures in
    one pass).

.PARAMETER Smoke
    See modes table above.

.PARAMETER Quick
    See modes table above.

.PARAMETER CreateSnapshot
    See modes table above.

.PARAMETER Tag
    Snapshot tag.  Default 'main'.  See Test-Snapshot.ps1.

.PARAMETER TestBaseDir
    Override the test data root.  Falls through to Test-Snapshot.ps1
    which falls through to Dataset-Config.ps1.

.PARAMETER Force
    Discard existing workdirs before running.  Passed through to
    Test-Snapshot.ps1.

.EXAMPLE
    # Pre-commit gate (small changes)
    pwsh -File ./ai/scripts/OspreySharp/Test-Full-Regression.ps1 -Smoke

.EXAMPLE
    # Pre-PR gate
    pwsh -File ./ai/scripts/OspreySharp/Test-Full-Regression.ps1 -Quick

.EXAMPLE
    # Full pre-merge regression (~70 min)
    pwsh -File ./ai/scripts/OspreySharp/Test-Full-Regression.ps1

.EXAMPLE
    # Refresh the frozen baseline after an approved behavior change
    pwsh -File ./ai/scripts/OspreySharp/Test-Full-Regression.ps1 -CreateSnapshot
#>
[CmdletBinding(DefaultParameterSetName='Default')]
param(
    [Parameter(ParameterSetName='Smoke')] [switch]$Smoke,
    [Parameter(ParameterSetName='Quick')] [switch]$Quick,
    [Parameter(ParameterSetName='CreateSnapshot')] [switch]$CreateSnapshot,

    [string]$Tag = 'main',
    [string]$TestBaseDir = $null,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $PSCommandPath
$testSnapshot = Join-Path $scriptDir 'Test-Snapshot.ps1'
if (-not (Test-Path $testSnapshot)) {
    Write-Host "Test-Snapshot.ps1 not found at $testSnapshot" -ForegroundColor Red
    exit 2
}

# Pick the (Dataset, Files) matrix for the chosen mode.
if ($Smoke) {
    $matrix = @(@{ Dataset='Stellar'; Files='Single' })
    $modeLabel = 'SMOKE (Stellar single)'
} elseif ($Quick) {
    $matrix = @(
        @{ Dataset='Stellar'; Files='Single' },
        @{ Dataset='Astral';  Files='Single' }
    )
    $modeLabel = 'QUICK (Stellar + Astral single)'
} else {
    $matrix = @(
        @{ Dataset='Stellar'; Files='All' },
        @{ Dataset='Astral';  Files='All' }
    )
    $modeLabel = 'FULL (Stellar + Astral all)'
}
if ($CreateSnapshot) {
    $modeLabel = $modeLabel + ' [CAPTURE]'
}

Write-Host ""
Write-Host "=== Test-Full-Regression: $modeLabel ===" -ForegroundColor Cyan
Write-Host "  Tag:        $Tag"
if ($TestBaseDir) { Write-Host "  TestBase:   $TestBaseDir" }
Write-Host ""

$swTotal = [System.Diagnostics.Stopwatch]::StartNew()
$results = @()
foreach ($cell in $matrix) {
    $ds = $cell.Dataset
    $fs = $cell.Files
    Write-Host "--- $ds ($fs) ---" -ForegroundColor Yellow
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $args = @(
        '-File', $testSnapshot,
        '-Dataset', $ds,
        '-Files', $fs,
        '-Tag', $Tag,
        '-Continue'
    )
    if ($CreateSnapshot) { $args += '-CreateSnapshot' }
    if ($Force)          { $args += '-Force' }
    if ($TestBaseDir)    { $args += '-TestBaseDir', $TestBaseDir }
    & pwsh -NoProfile @args
    $exit = $LASTEXITCODE
    $sw.Stop()
    $state = if ($exit -eq 0) { 'PASS' } else { 'FAIL' }
    $color = if ($exit -eq 0) { 'Green' } else { 'Red' }
    Write-Host ("--- {0} ({1}): {2} in {3:N1}s ---" -f $ds, $fs, $state, $sw.Elapsed.TotalSeconds) -ForegroundColor $color
    Write-Host ""
    $results += [pscustomobject]@{
        Dataset = $ds
        Files   = $fs
        State   = $state
        Exit    = $exit
        Seconds = [int]$sw.Elapsed.TotalSeconds
    }
}
$swTotal.Stop()

Write-Host "=== Summary ===" -ForegroundColor Cyan
$results | Format-Table Dataset, Files, State, Exit, Seconds -AutoSize | Out-String | Write-Host
$failed = @($results | Where-Object { $_.State -ne 'PASS' })
if ($failed.Count -gt 0) {
    Write-Host ("Overall: FAIL ({0} of {1} cells failed) in {2:N1}s wall" -f `
        $failed.Count, $results.Count, $swTotal.Elapsed.TotalSeconds) -ForegroundColor Red
    exit 1
}
Write-Host ("Overall: PASS ({0} cells in {1:N1}s wall)" -f `
    $results.Count, $swTotal.Elapsed.TotalSeconds) -ForegroundColor Green
exit 0
