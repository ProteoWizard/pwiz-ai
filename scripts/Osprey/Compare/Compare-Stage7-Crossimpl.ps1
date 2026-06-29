<#
.SYNOPSIS
    Cross-implementation Stage 7 protein-FDR dump comparison.

.DESCRIPTION
    Hash-joins the Rust and C# Stage 7 dumps on the stable key
    `accessions` and reports per-column max_abs_diff, divergence count,
    and row-set disagreement. Mirrors the methodology of
    Compare-Percolator.ps1 for Stage 5 — numeric columns are compared
    against per-column tolerances (typically 1e-9), so format-only
    differences in the canonical f64 -> decimal rendering (e.g. ryu vs
    .NET Framework 4.7.2 G16 banker rounding picking different
    equally-valid round-trip strings for the same f64 bits) cleanly
    pass the gate. Strict byte/SHA-256 comparison is reserved for the
    Rust <-> Rust rehydration gate (Compare-Stage7-Rehydration.ps1)
    where bit parity is the right invariant.

    Inputs are the TSVs produced by running each tool with
    `OSPREY_DUMP_STAGE7_PROTEIN_FDR=1` (typically also
    `OSPREY_STAGE7_PROTEIN_FDR_ONLY=1` to exit right after the dump):

      Rust: rust_stage7_protein_fdr.tsv
      C#:   cs_stage7_protein_fdr.tsv

    Schema (both sides):
      accessions  n_unique  n_shared  best_peptide_score
        group_qvalue  is_target_winner

.PARAMETER RustTsv
    Path to the Rust dump.

.PARAMETER CsTsv
    Path to the C# dump.

.PARAMETER MaxSampleRows
    Maximum number of sample divergent / missing rows to print per
    category (default: 5).

.EXAMPLE
    .\Compare-Stage7-Crossimpl.ps1 `
        -RustTsv "D:\test\osprey-runs\stellar\_stage7_test\run_rust\rust_stage7_protein_fdr.tsv" `
        -CsTsv   "D:\test\osprey-runs\stellar\_stage7_test\run_cs_from_rust\cs_stage7_protein_fdr.tsv"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$RustTsv,

    [Parameter(Mandatory=$true)]
    [string]$CsTsv,

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

# Per-column tolerances. Stage 7 numeric columns are second-pass SVM
# discriminant (best_peptide_score) and Storey-style q-values
# (group_qvalue). 1e-9 absolute is consistent with the Stage 5
# Compare-Percolator gate: tight enough to flag any algorithmic drift,
# loose enough to absorb the f64 -> decimal rendering choice between
# ryu (Rust) and .NET Framework 4.7.2's G16 (C#) when the two pick
# different equally-valid shortest-roundtrip strings for the same
# f64 bits.
$thresholds = @{
    "best_peptide_score" = 1e-9
    "group_qvalue"       = 1e-9
}
$numericColumns = @("best_peptide_score", "group_qvalue")
# Categorical columns must agree exactly. is_target_winner gates
# whether a row appears in either side at all (target winners only),
# but we still compare for safety.
$exactColumns = @("n_unique", "n_shared", "is_target_winner")

function Read-Dump([string]$path) {
    Write-Host ("Loading: {0}" -f $path) -ForegroundColor Gray
    $lines = [System.IO.File]::ReadAllLines($path)
    if ($lines.Length -lt 1) {
        throw "Empty TSV: $path"
    }
    $header = $lines[0] -split "`t"
    $idxKey = [Array]::IndexOf($header, "accessions")
    if ($idxKey -lt 0) {
        throw "Required column 'accessions' missing in $path"
    }
    $map = [System.Collections.Generic.Dictionary[string,string[]]]::new($lines.Length)
    for ($i = 1; $i -lt $lines.Length; $i++) {
        $row = $lines[$i] -split "`t"
        $key = $row[$idxKey]
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
foreach ($col in ($numericColumns + $exactColumns)) {
    $rIdx[$col] = [Array]::IndexOf($r.Header, $col)
    $cIdx[$col] = [Array]::IndexOf($c.Header, $col)
}

$common = [System.Collections.Generic.List[string]]::new($r.Map.Count)
foreach ($k in $r.Map.Keys) {
    if ($c.Map.ContainsKey($k)) { $common.Add($k) }
}

Write-Host ""
Write-Host "=== Column comparison (common keys) ===" -ForegroundColor Cyan
Write-Host ("Common rows: {0}" -f $common.Count) -ForegroundColor Gray

$allPass = ($rOnly.Count -eq 0) -and ($cOnly.Count -eq 0)

# Numeric columns: compare with per-column tolerance
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

# Exact (non-numeric) columns: must match string-for-string
foreach ($col in $exactColumns) {
    $ri = $rIdx[$col]
    $ci = $cIdx[$col]
    if ($ri -lt 0 -or $ci -lt 0) {
        Write-Host ("  {0,-24} MISSING COLUMN (rust={1} cs={2})" -f $col, $ri, $ci) -ForegroundColor Red
        $allPass = $false
        continue
    }
    $nDivergent = 0
    $sampleKey = $null
    $sampleR = $null
    $sampleC = $null
    foreach ($k in $common) {
        $rv = $r.Map[$k][$ri]
        $cv = $c.Map[$k][$ci]
        if ($rv -ne $cv) {
            $nDivergent++
            if (-not $sampleKey) { $sampleKey = $k; $sampleR = $rv; $sampleC = $cv }
        }
    }
    $status = if ($nDivergent -eq 0) { "PASS" } else { "FAIL" }
    $color = if ($nDivergent -eq 0) { "Green" } else { "Red" }
    Write-Host ("  {0,-24} {1,-4}  n_diverg={2}/{3}  (string equality)" -f `
        $col, $status, $nDivergent, $common.Count) -ForegroundColor $color
    if ($nDivergent -gt 0 -and $sampleKey) {
        Write-Host ("    first-diverg: key={0}  rust='{1}'  cs='{2}'" -f `
            $sampleKey, $sampleR, $sampleC) -ForegroundColor Gray
        $allPass = $false
    }
}

Write-Host ""
if ($allPass) {
    Write-Host "OVERALL: PASS (Stage 7 cross-impl numeric parity within tolerance)" -ForegroundColor Green
    exit 0
} else {
    Write-Host "OVERALL: FAIL" -ForegroundColor Red
    exit 1
}
