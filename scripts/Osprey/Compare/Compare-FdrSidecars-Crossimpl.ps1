<#
.SYNOPSIS
    Cross-implementation per-file FDR score sidecar comparison.

.DESCRIPTION
    Compares every <stem>.1st-pass.fdr_scores.bin and
    <stem>.2nd-pass.fdr_scores.bin written by a Rust run against the
    ones written by a C# run of the same dataset, field by field at
    1e-9, matched by file stem and then by entry_id.

    This closes a real blind spot rather than adding redundancy. The
    other cross-impl comparisons read the Stage 7 protein FDR dump
    (per-protein-GROUP columns: accessions, n_unique, n_shared,
    best_peptide_score, group_qvalue, is_target_winner) and the blib.
    Neither carries a per-entry SVM score, and neither carries
    run_protein_qvalue. Issue #4553 is exactly a defect in those two
    fields, present in BOTH implementations, which is why every
    existing gate stayed green while 6.6% of persisted scores were 0.

    The sidecar is not a diagnostic artifact: Stage 7
    (--join-at-pass=2) reads it unconditionally, so a value that is
    wrong here is wrong for any distributed or resumed run.

    Decoding is delegated to the pwiz-side Regression/FdrSidecars.ps1
    so the byte layout is described in exactly one place, shared with
    regression.ps1's four-task-chain leg.

.PARAMETER RustDir
    Directory holding the Rust run's sidecars.

.PARAMETER CsDir
    Directory holding the C# run's sidecars.

.PARAMETER Tolerance
    Per-field absolute tolerance (default 1e-9, matching the other
    cross-impl comparators).

.PARAMETER MaxSampleRows
    Maximum number of per-field issue lines to print (default 12).

.EXAMPLE
    .\Compare-FdrSidecars-Crossimpl.ps1 `
        -RustDir "D:\test\osprey-runs\stellar\_endtoend_crossimpl\rust" `
        -CsDir   "D:\test\osprey-runs\stellar\_endtoend_crossimpl\cs"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$RustDir,

    [Parameter(Mandatory=$true)]
    [string]$CsDir,

    [Parameter(Mandatory=$false)]
    [double]$Tolerance = 1e-9,

    [Parameter(Mandatory=$false)]
    [int]$MaxSampleRows = 12
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $PSCommandPath

# Dot-source Dataset-Config for Get-PwizRoot, from either the top-level
# scripts dir or the parent (when this script lives in Compare/).
$configCandidates = @(
    (Join-Path $scriptDir 'Dataset-Config.ps1'),
    (Join-Path $scriptDir '..\Dataset-Config.ps1')
)
foreach ($c in $configCandidates) { if (Test-Path $c) { . $c; break } }

# The decoder lives with the sidecar writer's own regression gate, in pwiz.
# Duplicating the 60-byte record layout here is how the two copies drift.
#
# ai/ and pwiz move independently, so this script CAN be newer than the pwiz checkout it
# is pointed at -- most obviously while the pwiz side of issue #4553 is still on a branch.
# A missing helper is therefore "this checkout cannot run this comparison", not "the
# comparison failed": exit 3, which the end-to-end driver reports as SKIP rather than
# folding into its overall verdict. Failing here would turn every master checkout red on a
# gate that has nothing wrong with it.
$sidecarHelpers = Join-Path (Get-PwizRoot) 'pwiz_tools\Osprey\Regression\FdrSidecars.ps1'
if (-not (Test-Path $sidecarHelpers)) {
    Write-Host "SKIPPED: FdrSidecars.ps1 not found at $sidecarHelpers" -ForegroundColor Yellow
    Write-Host "  This pwiz checkout predates the sidecar comparison helper (issue #4553)."
    Write-Host "  (set `$env:PWIZ_ROOT if your pwiz checkout is not a sibling of ai/)"
    exit 3
}
. $sidecarHelpers

foreach ($d in @($RustDir, $CsDir)) {
    if (-not (Test-Path $d)) {
        Write-Host "Directory not found: $d" -ForegroundColor Red
        exit 2
    }
}

Write-Host "=== Compare-FdrSidecars-Crossimpl ===" -ForegroundColor Cyan
Write-Host "  Rust: $RustDir"
Write-Host "  C#:   $CsDir"
Write-Host "  Tolerance: $Tolerance"
Write-Host ""

# Rust is the EXPECTED side purely so the issue text reads "rust -> cs".
# The comparison itself is symmetric.
$anyFail = $false
foreach ($pass in @(1, 2)) {
    $result = Compare-FdrSidecars -ExpectedDir $RustDir -ActualDir $CsDir `
        -Pass $pass -Tolerance $Tolerance
    $label = "{0}-pass sidecars" -f $(if ($pass -eq 1) { '1st' } else { '2nd' })
    if ($result.Pass) {
        Write-Host ("  {0}: PASS  ({1} record(s) compared)" -f $label, $result.Compared) `
            -ForegroundColor Green
    } else {
        $anyFail = $true
        Write-Host ("  {0}: FAIL  ({1} issue(s), {2} record(s) compared)" -f `
            $label, $result.Issues.Count, $result.Compared) -ForegroundColor Red
        $result.Issues | Select-Object -First $MaxSampleRows |
            ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
        if ($result.Issues.Count -gt $MaxSampleRows) {
            Write-Host ("    ... {0} more" -f ($result.Issues.Count - $MaxSampleRows)) `
                -ForegroundColor DarkGray
        }
    }
}

Write-Host ""
if ($anyFail) {
    Write-Host "OVERALL: FAIL -- the two implementations write different FDR sidecars" `
        -ForegroundColor Red
    Write-Host "  A 1st-pass failure means the runs already diverged before reconciliation;"
    Write-Host "  fix that first, since it makes any 2nd-pass reading meaningless."
    Write-Host "  A 2nd-pass-only failure is a divergence in what pass 2 persists."
    exit 1
}
Write-Host "OVERALL: PASS -- FDR sidecars agree at $Tolerance" -ForegroundColor Green
exit 0
