<#
.SYNOPSIS
    Column-level content diff between two .scores.parquet files (or
    directories of them).

.DESCRIPTION
    Originally promoted from ai/.tmp/parquet_diff.py during the
    Stage 6 OspreySharp port. The python helper is the actual
    pyarrow-driven row/column comparator; this script is the
    PowerShell entry point that:

      - accepts either a single pair (-A/-B) or two directories
        (-DirA/-DirB), in which case every *.scores.parquet pair
        with matching filenames is compared
      - prints per-column OK/DIFF lines through a single python
        invocation (the python helper does the heavy lifting)
      - optionally suppresses known-gap columns via
        -ExpectedDiffColumns, so the harness can distinguish
        "documented C# scoring-path limitation" rows from real
        regressions
      - exits 0 iff every non-allowlisted column matches every pair

    Used during the original Rust port to bisect bit-parity
    regressions between Stage 1-4 pipeline-fed runs and Stage 5
    sidecar-fed runs (parquet content was the canonical evidence).
    Reused for the Rust v OspreySharp Stage 6 cross-impl gate.

.PARAMETER A
    First parquet file (single-pair mode). Pair with -B.

.PARAMETER B
    Second parquet file (single-pair mode). Pair with -A.

.PARAMETER DirA
    First directory of *.scores.parquet files (multi-file mode).

.PARAMETER DirB
    Second directory (multi-file mode). Compared by filename.

.PARAMETER ExpectedDiffColumns
    Column names that are allowed to diff without failing the
    overall result. Use for documented gaps (e.g. C# scoring path
    doesn't populate fragment_mzs).

.PARAMETER Quiet
    Suppress per-column lines; print only the per-pair summary.

.EXAMPLE
    .\Diff-Parquet.ps1 -A rust\file20.scores.parquet -B cs\file20.scores.parquet

.EXAMPLE
    # Compare every pair in two iter dirs, ignoring known C# gaps.
    .\Diff-Parquet.ps1 `
        -DirA D:\test\osprey-runs\stellar\_stage6_iter\Stellar_rust `
        -DirB D:\test\osprey-runs\stellar\_stage6_iter\Stellar_cs `
        -ExpectedDiffColumns @(
            'fragment_mzs','fragment_intensities',
            'reference_xic_rts','reference_xic_intensities',
            'bounds_area','bounds_snr')
#>

[CmdletBinding(DefaultParameterSetName="Pair")]
param(
    [Parameter(ParameterSetName="Pair", Mandatory=$true)]
    [string]$A,

    [Parameter(ParameterSetName="Pair", Mandatory=$true)]
    [string]$B,

    [Parameter(ParameterSetName="Dirs", Mandatory=$true)]
    [string]$DirA,

    [Parameter(ParameterSetName="Dirs", Mandatory=$true)]
    [string]$DirB,

    [string[]]$ExpectedDiffColumns = @(),

    # Numeric tolerance for the underlying parquet_diff.py. Mirrors
    # Test-Features.ps1's 1e-6 gate -- any numeric cell where
    # |a-b| <= tolerance counts as matching. Default is the same 1e-6
    # that the rest of the OspreySharp parity tooling uses, so Stage 1-4
    # ULP-level drift (already documented in the Stage 6 TODO open
    # follow-up #2) doesn't show up as cross-impl regression here. Pass
    # 0 for strict bit parity.
    [double]$NumericTolerance = 1e-6,

    [switch]$Quiet
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$pyHelper = Join-Path $PSScriptRoot "parquet_diff.py"
if (-not (Test-Path $pyHelper)) {
    Write-Error "Python helper not found: $pyHelper"
    exit 2
}

# Build pair list ----------------------------------------------------
$pairs = @()
if ($PSCmdlet.ParameterSetName -eq "Pair") {
    if (-not (Test-Path $A)) { Write-Error "Missing: $A"; exit 2 }
    if (-not (Test-Path $B)) { Write-Error "Missing: $B"; exit 2 }
    $pairs += [PSCustomObject]@{ Label = (Split-Path $A -Leaf); A = $A; B = $B }
} else {
    if (-not (Test-Path $DirA)) { Write-Error "Missing: $DirA"; exit 2 }
    if (-not (Test-Path $DirB)) { Write-Error "Missing: $DirB"; exit 2 }
    $aFiles = Get-ChildItem -Path $DirA -Filter "*.scores.parquet" -File
    foreach ($af in $aFiles) {
        $bf = Join-Path $DirB $af.Name
        if (Test-Path $bf) {
            $pairs += [PSCustomObject]@{ Label = $af.Name; A = $af.FullName; B = $bf }
        } else {
            Write-Host ("  [missing in DirB] {0}" -f $af.Name) -ForegroundColor Red
        }
    }
    if ($pairs.Count -eq 0) {
        Write-Error "No matching *.scores.parquet pairs found."
        exit 2
    }
}

# Run helper per pair ------------------------------------------------
$expectedSet = New-Object System.Collections.Generic.HashSet[string]
foreach ($c in $ExpectedDiffColumns) { [void]$expectedSet.Add($c) }

$summary = @()
$overallPass = $true

foreach ($p in $pairs) {
    Write-Host ("=== {0} ===" -f $p.Label) -ForegroundColor Cyan
    $raw = & python $pyHelper $p.A $p.B --tolerance $NumericTolerance 2>&1
    # Parse OK/DIFF lines: "  [OK ] colname: 0 rows differ"
    #                     "  [DIFF] colname: 387 rows differ"
    $diffCols = @()
    $allowedDiffCols = @()
    foreach ($line in $raw) {
        $s = [string]$line
        if ($s -match '^\s*\[(OK |DIFF)\]\s+(\S+):\s+(\d+)\s+rows differ') {
            $marker = $matches[1].Trim()
            $col = $matches[2]
            $n   = [int]$matches[3]
            if ($marker -eq "DIFF") {
                if ($expectedSet.Contains($col)) {
                    $allowedDiffCols += [PSCustomObject]@{ Col=$col; Rows=$n }
                } else {
                    $diffCols += [PSCustomObject]@{ Col=$col; Rows=$n }
                }
            }
        }
        if (-not $Quiet) { Write-Host $s }
    }

    $pairOk = ($diffCols.Count -eq 0)
    if (-not $pairOk) { $overallPass = $false }

    $summary += [PSCustomObject]@{
        File          = $p.Label
        Status        = if ($pairOk) { "PASS" } else { "FAIL" }
        DiffCols      = $diffCols.Count
        AllowedDiffs  = $allowedDiffCols.Count
    }

    if ($pairOk) {
        if ($allowedDiffCols.Count -gt 0) {
            Write-Host ("  PASS ({0} allowlisted diff column(s))" -f $allowedDiffCols.Count) -ForegroundColor Green
        } else {
            Write-Host "  PASS" -ForegroundColor Green
        }
    } else {
        Write-Host ("  FAIL: {0} unexpected diff column(s)" -f $diffCols.Count) -ForegroundColor Red
        foreach ($d in $diffCols) {
            Write-Host ("    {0}: {1} rows" -f $d.Col, $d.Rows) -ForegroundColor Red
        }
    }
}

Write-Host ""
Write-Host "--- Diff-Parquet summary ---" -ForegroundColor Cyan
$summary | Format-Table -AutoSize File, Status, DiffCols, AllowedDiffs

if ($overallPass) {
    Write-Host "All parquet pairs passed (within allowlist)." -ForegroundColor Green
    exit 0
} else {
    Write-Host "One or more parquet pairs FAILED." -ForegroundColor Red
    exit 1
}
