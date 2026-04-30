<#
.SYNOPSIS
    Cross-implementation diagnostic-dump comparison for one bisection stage.

.DESCRIPTION
    Runs both Rust Osprey and OspreySharp (C#) with the diagnostic dump
    flags for a single calibration-pipeline stage, then diffs the resulting
    dump files and reports IDENTICAL or the first N divergent lines. This
    is the routine bisection walk used to find where cross-implementation
    parity first breaks.

    Stages walk from earliest (CalSample) through the calibration pipeline
    and stop at the first divergence: CalSample -> CalWindows -> CalMatch
    -> LdaScores -> LoessInput. Only the stage's own dumps are compared;
    each run exits early via the ONLY env var for fast cycle time.

    File naming is consistent on the Rust side (flat `rust_*.txt`). On the
    C# side, `cs_cal_sample.txt` is prefixed with the mzML file stem; all
    other C# dumps are flat. This script normalizes both conventions.

.PARAMETER Dataset
    Stellar or Astral (default: Stellar)

.PARAMETER Stage
    Which bisection stage to compare. One of:
      CalSample   - Cal sample list + cal grid + cal scalars (earliest)
      CalWindows  - Per-entry calibration window info
      CalMatch    - Calibration-phase match features (4 feats + SNR)
      LdaScores   - LDA discriminant scores + q-values
      LoessInput  - (lib_rt, measured_rt) pairs fed to LOESS

.PARAMETER SkipRust
    Reuse the existing rust_*.txt files from a previous invocation. Useful
    when iterating on C# while the Rust side is known-stable.

.PARAMETER MaxDivergent
    Maximum number of divergent line pairs to print per file (default: 20)

.PARAMETER TestBaseDir
    Override the test data base directory. Defaults to
    $env:OSPREY_TEST_BASE_DIR if set, otherwise "D:\test\osprey-runs".

.EXAMPLE
    .\Compare-Diagnostic.ps1 -Stage CalSample
    Run both tools with cal-sample dump; diff rust_cal_sample.txt etc.

.EXAMPLE
    .\Compare-Diagnostic.ps1 -Stage CalMatch -SkipRust
    Reuse Rust's cal_match from a prior run and just redo C# + diff.

.EXAMPLE
    .\Compare-Diagnostic.ps1 -Stage LoessInput -Dataset Astral
    Walk to the LOESS-input stage on Astral.
#>

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("Stellar","Astral")]
    [string]$Dataset = "Stellar",

    [Parameter(Mandatory=$true)]
    [ValidateSet("CalSample","CalWindows","CalMatch","LdaScores","LoessInput")]
    [string]$Stage,

    [Parameter(Mandatory=$false)]
    [switch]$SkipRust = $false,

    [Parameter(Mandatory=$false)]
    [int]$MaxDivergent = 20,

    [Parameter(Mandatory=$false)]
    [string]$TestBaseDir = $null
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$scriptRoot = Split-Path -Parent $PSCommandPath
. "$scriptRoot\Dataset-Config.ps1"
$ds = Get-DatasetConfig $Dataset -TestBaseDir $TestBaseDir
$testDir = $ds.TestDir
$fileStem = [System.IO.Path]::GetFileNameWithoutExtension($ds.SingleFile)

if (-not (Test-Path $testDir)) {
    Write-Error "Test data directory not found: $testDir"
    exit 1
}

# Stage -> (Run-Osprey switch-pair, list of file-pair comparisons).
$stageMap = @{
    CalSample = @{
        DumpSwitch = "DiagCalSample"
        OnlySwitch = "DiagCalSampleOnly"
        Files = @(
            @{ Label = "cal_sample";  Rust = "rust_cal_sample.txt";   CS = "$fileStem.cs_cal_sample.txt" },
            @{ Label = "cal_scalars"; Rust = "rust_cal_scalars.txt";  CS = "cs_cal_scalars.txt" },
            @{ Label = "cal_grid";    Rust = "rust_cal_grid.txt";     CS = "cs_cal_grid.txt" }
        )
    }
    CalWindows = @{
        DumpSwitch = "DiagCalWindows"
        OnlySwitch = "DiagCalWindowsOnly"
        Files = @(
            @{ Label = "cal_windows"; Rust = "rust_cal_windows.txt";  CS = "cs_cal_windows.txt" }
        )
    }
    CalMatch = @{
        DumpSwitch = "DiagCalMatch"
        OnlySwitch = "DiagCalMatchOnly"
        Files = @(
            @{ Label = "cal_match";   Rust = "rust_cal_match.txt";    CS = "cs_cal_match.txt" }
        )
    }
    LdaScores = @{
        DumpSwitch = "DiagLdaScores"
        OnlySwitch = "DiagLdaOnly"
        Files = @(
            @{ Label = "lda_scores";  Rust = "rust_lda_scores.txt";   CS = "cs_lda_scores.txt" }
        )
    }
    LoessInput = @{
        DumpSwitch = "DiagLoessInput"
        OnlySwitch = "DiagLoessOnly"
        Files = @(
            @{ Label = "loess_input"; Rust = "rust_loess_input.txt";  CS = "cs_loess_input.txt" }
        )
    }
}

$entry = $stageMap[$Stage]
$initialLocation = Get-Location
$runOspreyPath = Join-Path $scriptRoot "Run-Osprey.ps1"
$filterPattern = '\[BISECT\]|\[COUNT\]|Wrote calibration|Wrote LOESS|Wrote LDA|aborting|ERROR|completed in'

# Build a hashtable with the two diagnostic switches that can be splatted
# into Run-Osprey.ps1 (`@diagSwitches`). This works where a positional
# array-splat does not -- each entry becomes -SwitchName:$true.
$diagSwitches = @{
    $entry.DumpSwitch = $true
    $entry.OnlySwitch = $true
}

try {
    Set-Location $testDir

    Write-Host ""
    Write-Host "=== Bisection stage: $Stage  (dataset: $($ds.Name), file: $fileStem) ===" -ForegroundColor Cyan

    # Clean the dumps for this stage so stale files from a prior run can't
    # masquerade as this run's output. Keep caches (calibration.json etc)
    # so -SkipRust can reuse them.
    foreach ($pair in $entry.Files) {
        if (-not $SkipRust) {
            Remove-Item (Join-Path $testDir $pair.Rust) -Force -ErrorAction SilentlyContinue
        }
        Remove-Item (Join-Path $testDir $pair.CS) -Force -ErrorAction SilentlyContinue
    }

    # Run Rust
    if (-not $SkipRust) {
        Write-Host ""
        Write-Host "Rust..." -ForegroundColor Cyan
        $rustStart = Get-Date
        & $runOspreyPath -Dataset $Dataset -Tool Rust -Clean -TestBaseDir $TestBaseDir @diagSwitches 2>&1 |
            Where-Object { $_ -match $filterPattern } | ForEach-Object {
                Write-Host ("  " + $_.ToString().Trim()) -ForegroundColor Gray
            }
        Write-Host ("  (wall clock: {0:F1}s)" -f ((Get-Date) - $rustStart).TotalSeconds) -ForegroundColor DarkGray
    } else {
        Write-Host ""
        Write-Host "Rust skipped (reusing existing dumps)" -ForegroundColor Yellow
    }

    # Run C#. -Clean wipes caches but leaves the stage dumps we care about.
    Write-Host ""
    Write-Host "OspreySharp..." -ForegroundColor Cyan
    $csStart = Get-Date
    & $runOspreyPath -Dataset $Dataset -Tool CSharp -Clean -TestBaseDir $TestBaseDir @diagSwitches 2>&1 |
        Where-Object { $_ -match $filterPattern } | ForEach-Object {
            Write-Host ("  " + $_.ToString().Trim()) -ForegroundColor Gray
        }
    Write-Host ("  (wall clock: {0:F1}s)" -f ((Get-Date) - $csStart).TotalSeconds) -ForegroundColor DarkGray

    # Diff each file pair
    Write-Host ""
    Write-Host "=== Diff ===" -ForegroundColor Cyan
    $allIdentical = $true
    foreach ($pair in $entry.Files) {
        Write-Host ""
        Write-Host ("{0}: {1}  vs  {2}" -f $pair.Label, $pair.Rust, $pair.CS) -ForegroundColor Cyan

        # Resolve against $testDir - child Run-Osprey.ps1's finally block
        # can restore CWD to its own $initialLocation, so we can't rely on
        # relative paths here.
        $rustPath = Join-Path $testDir $pair.Rust
        $csPath   = Join-Path $testDir $pair.CS

        if (-not (Test-Path $rustPath)) {
            Write-Host ("  MISSING: {0}" -f $rustPath) -ForegroundColor Red
            $allIdentical = $false
            continue
        }
        if (-not (Test-Path $csPath)) {
            Write-Host ("  MISSING: {0}" -f $csPath) -ForegroundColor Red
            $allIdentical = $false
            continue
        }

        # Normalize CRLF -> LF and split to lines. Trailing empty line
        # (common in POSIX-style dumps) is trimmed for fair count.
        $rustLines = [System.IO.File]::ReadAllText($rustPath).Replace("`r","").TrimEnd("`n").Split("`n")
        $csLines   = [System.IO.File]::ReadAllText($csPath).Replace("`r","").TrimEnd("`n").Split("`n")

        $rustCount = $rustLines.Count
        $csCount = $csLines.Count

        if ($rustCount -ne $csCount) {
            Write-Host ("  Line count differs: Rust={0}, C#={1}" -f $rustCount, $csCount) -ForegroundColor Yellow
            $allIdentical = $false
        } else {
            Write-Host ("  Line count: {0}" -f $rustCount) -ForegroundColor Gray
        }

        $common = [Math]::Min($rustCount, $csCount)
        $divergentCount = 0
        $firstDivergent = @()

        for ($i = 0; $i -lt $common; $i++) {
            if ($rustLines[$i] -cne $csLines[$i]) {
                $divergentCount++
                if ($firstDivergent.Count -lt $MaxDivergent) {
                    $firstDivergent += [PSCustomObject]@{
                        Line = $i + 1
                        Rust = $rustLines[$i]
                        CS   = $csLines[$i]
                    }
                }
            }
        }

        if ($divergentCount -eq 0 -and $rustCount -eq $csCount) {
            Write-Host "  IDENTICAL" -ForegroundColor Green
        } else {
            $allIdentical = $false
            if ($common -gt 0) {
                $pct = [math]::Round($divergentCount * 100.0 / $common, 2)
                Write-Host ("  DIVERGENT: {0}/{1} lines ({2}%)" -f $divergentCount, $common, $pct) -ForegroundColor Red
            } else {
                Write-Host "  DIVERGENT: empty file on one side" -ForegroundColor Red
            }
            foreach ($d in $firstDivergent) {
                Write-Host ("  L{0}:" -f $d.Line) -ForegroundColor Yellow
                Write-Host ("    Rust: {0}" -f $d.Rust) -ForegroundColor Gray
                Write-Host ("    C#:   {0}" -f $d.CS) -ForegroundColor Gray
            }
            if ($divergentCount -gt $firstDivergent.Count) {
                Write-Host ("  ... {0} more divergent lines (use -MaxDivergent to show more)" -f ($divergentCount - $firstDivergent.Count)) -ForegroundColor DarkGray
            }
        }
    }

    Write-Host ""
    if ($allIdentical) {
        Write-Host "Stage ${Stage}: ALL FILES IDENTICAL" -ForegroundColor Green
        exit 0
    } else {
        Write-Host "Stage ${Stage}: DIVERGENCE DETECTED  (first point of breakage)" -ForegroundColor Red
        exit 1
    }
}
finally {
    Set-Location $initialLocation
}
