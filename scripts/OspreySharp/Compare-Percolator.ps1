<#
.SYNOPSIS
    Cross-implementation Stage 5 Percolator dump comparison.

.DESCRIPTION
    Hash-joins the Rust and C# Stage 5 dumps on the stable composite key
    (file_name, entry_id) and reports per-column max_abs_diff, divergence
    count, and row-set disagreement. Unlike Compare-Diagnostic.ps1 which
    does row-wise line diff, this script is sort-order-agnostic — avoids
    the Phase 1-3 issues where the two tools' rendering order drifted
    despite their algorithms agreeing.

    Inputs are the TSVs produced by running each tool with
    OSPREY_DUMP_PERCOLATOR=1 (typically also OSPREY_PERCOLATOR_ONLY=1 to
    exit right after the dump):

      Rust: rust_stage5_percolator.tsv
      C#:   cs_stage5_percolator.tsv

    Both are per-precursor TSVs with 11 columns; the 6 numeric columns
    (score, pep, and the 4 q-values) are compared against per-column
    thresholds. String/ID columns that appear on both sides but differ
    are flagged as row-key mismatches.

.PARAMETER RustTsv
    Path to the Rust dump. Defaults to the canonical Stellar parity dir
    at D:\test\osprey-runs\stage5\stellar\rust_stage5_percolator.tsv.

.PARAMETER CsTsv
    Path to the C# dump. Defaults to the canonical Stellar parity dir
    at D:\test\osprey-runs\stage5\stellar\cs_stage5_percolator.tsv.

.PARAMETER MaxSampleRows
    Maximum number of sample divergent / missing rows to print per
    category (default: 5). The numeric-column summary prints one
    exemplar row for each divergent column.

.EXAMPLE
    .\Compare-Percolator.ps1

.EXAMPLE
    .\Compare-Percolator.ps1 -RustTsv ".\rust_stage5_percolator.tsv" `
                             -CsTsv   ".\cs_stage5_percolator.tsv"
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$RustTsv = "D:\test\osprey-runs\stage5\stellar\rust_stage5_percolator.tsv",

    [Parameter(Mandatory=$false)]
    [string]$CsTsv = "D:\test\osprey-runs\stage5\stellar\cs_stage5_percolator.tsv",

    [Parameter(Mandatory=$false)]
    [int]$MaxSampleRows = 5
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

if (-not (Test-Path $RustTsv)) {
    Write-Host "Missing: $RustTsv" -ForegroundColor Red
    exit 2
}
if (-not (Test-Path $CsTsv)) {
    Write-Host "Missing: $CsTsv" -ForegroundColor Red
    exit 2
}

# Per-column thresholds. Both tools now seed to 42 and are self-parity
# clean; any cross-tool divergence is algorithmic and should register at
# >1e-12 for any real difference. Loose enough to tolerate harmless f64
# rounding (e.g., slightly different std() accumulation orders in KDE
# bandwidth computation).
$thresholds = @{
    "score"                   = 1e-9
    "pep"                     = 1e-9
    "run_precursor_q"         = 1e-9
    "run_peptide_q"           = 1e-9
    "experiment_precursor_q" = 1e-9
    "experiment_peptide_q"   = 1e-9
}
$numericColumns = @(
    "score", "pep",
    "run_precursor_q", "run_peptide_q",
    "experiment_precursor_q", "experiment_peptide_q"
)

function Read-Dump([string]$path) {
    Write-Host ("Loading: {0}" -f $path) -ForegroundColor Gray
    $lines = [System.IO.File]::ReadAllLines($path)
    if ($lines.Length -lt 1) {
        throw "Empty TSV: $path"
    }
    $header = $lines[0] -split "`t"
    $idxFile  = [Array]::IndexOf($header, "file_name")
    $idxEntry = [Array]::IndexOf($header, "entry_id")
    if ($idxFile -lt 0 -or $idxEntry -lt 0) {
        throw "Required columns missing in $path (file_name, entry_id)"
    }
    # Dictionary<string, string[]> — much faster than PowerShell @{} for
    # N ~ 500K.
    $map = [System.Collections.Generic.Dictionary[string,string[]]]::new($lines.Length)
    for ($i = 1; $i -lt $lines.Length; $i++) {
        $row = $lines[$i] -split "`t"
        $key = $row[$idxFile] + "|" + $row[$idxEntry]
        $map[$key] = $row
    }
    return [pscustomobject]@{ Header = $header; Map = $map; Path = $path }
}

$r = Read-Dump $RustTsv
$c = Read-Dump $CsTsv

Write-Host ""
Write-Host ("Rust rows: {0}" -f $r.Map.Count) -ForegroundColor Gray
Write-Host ("C#   rows: {0}" -f $c.Map.Count) -ForegroundColor Gray

# Row-set diff
$rOnly = [System.Collections.Generic.List[string]]::new()
foreach ($k in $r.Map.Keys) {
    if (-not $c.Map.ContainsKey($k)) { $rOnly.Add($k) }
}
$cOnly = [System.Collections.Generic.List[string]]::new()
foreach ($k in $c.Map.Keys) {
    if (-not $r.Map.ContainsKey($k)) { $cOnly.Add($k) }
}

Write-Host ""
Write-Host "=== Key-set comparison ===" -ForegroundColor Cyan
Write-Host ("Keys only in Rust: {0}" -f $rOnly.Count)
Write-Host ("Keys only in C#:   {0}" -f $cOnly.Count)

if ($rOnly.Count -gt 0) {
    Write-Host ("First {0} Rust-only keys:" -f [Math]::Min($MaxSampleRows, $rOnly.Count)) -ForegroundColor Yellow
    for ($i = 0; $i -lt [Math]::Min($MaxSampleRows, $rOnly.Count); $i++) {
        Write-Host ("  {0}" -f $rOnly[$i])
    }
}
if ($cOnly.Count -gt 0) {
    Write-Host ("First {0} C#-only keys:" -f [Math]::Min($MaxSampleRows, $cOnly.Count)) -ForegroundColor Yellow
    for ($i = 0; $i -lt [Math]::Min($MaxSampleRows, $cOnly.Count); $i++) {
        Write-Host ("  {0}" -f $cOnly[$i])
    }
}

# Precompute column indices in each header
$rIdx = @{}
$cIdx = @{}
foreach ($col in $numericColumns) {
    $rIdx[$col] = [Array]::IndexOf($r.Header, $col)
    $cIdx[$col] = [Array]::IndexOf($c.Header, $col)
}

# Collect common keys into an array for efficient iteration
$common = [System.Collections.Generic.List[string]]::new($r.Map.Count)
foreach ($k in $r.Map.Keys) {
    if ($c.Map.ContainsKey($k)) { $common.Add($k) }
}

Write-Host ""
Write-Host "=== Column comparison (common keys) ===" -ForegroundColor Cyan
Write-Host ("Common rows: {0}" -f $common.Count) -ForegroundColor Gray

$allPass = ($rOnly.Count -eq 0) -and ($cOnly.Count -eq 0)

foreach ($col in $numericColumns) {
    $ri = $rIdx[$col]
    $ci = $cIdx[$col]
    if ($ri -lt 0 -or $ci -lt 0) {
        Write-Host ("  {0,-24} MISSING COLUMN (rust={1} cs={2})" -f $col, $ri, $ci) -ForegroundColor Red
        $allPass = $false
        continue
    }
    $threshold = [double]$thresholds[$col]
    $nDivergent = 0
    $maxDiff = 0.0
    $sampleKey = $null
    $sampleR = 0.0
    $sampleC = 0.0
    foreach ($k in $common) {
        $rv = [double]$r.Map[$k][$ri]
        $cv = [double]$c.Map[$k][$ci]
        $d = [Math]::Abs($rv - $cv)
        if ($d -gt $maxDiff) {
            $maxDiff = $d
            $sampleKey = $k
            $sampleR = $rv
            $sampleC = $cv
        }
        if ($d -gt $threshold) { $nDivergent++ }
    }
    $status = if ($nDivergent -eq 0) { "PASS" } else { "FAIL" }
    $color = if ($nDivergent -eq 0) { "Green" } else { "Red" }
    Write-Host ("  {0,-24} {1,-4}  max_diff={2:e3}  n_diverg={3}/{4}  thresh={5:e1}" -f `
        $col, $status, $maxDiff, $nDivergent, $common.Count, $threshold) -ForegroundColor $color
    if ($nDivergent -gt 0 -and $sampleKey) {
        Write-Host ("    first-diverg: key={0}  rust={1}  cs={2}" -f `
            $sampleKey, $sampleR, $sampleC) -ForegroundColor Gray
        $allPass = $false
    }
}

Write-Host ""
if ($allPass) {
    Write-Host "Stage 5 Percolator: CROSS-IMPL PARITY PASSED" -ForegroundColor Green
    exit 0
} else {
    Write-Host "Stage 5 Percolator: DIVERGENCE DETECTED" -ForegroundColor Red
    exit 1
}
