<#
.SYNOPSIS
    Cross-implementation FDR score comparison, reconstructing Rust's
    fused per-file record from the C# scope-split pair.

.DESCRIPTION
    Compares the nine per-observation FDR values written by a Rust run
    against the ones written by a C# run of the same dataset, field by
    field at 1e-9, matched by file stem and then by entry_id.

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

    FUSED COMPARISON (issue #4486). The two sides no longer write the
    same artifact. Rust fuses both scopes into one 68-byte per-file
    record; the C# v5 layout splits them into a 36-byte per-file
    run-scope file plus ONE analysis-wide experiment-scope file per
    pass. So there is no byte-level comparison left to make, and the
    comparison rebuilds Rust's per-observation view from the C# pair
    instead - run scope from the matched per-file record, experiment
    scope joined by entry_id from the analysis-wide file.

    That join carries the actual behavioural difference. A fused record
    answers "this entry's experiment-wide q" once per OBSERVATION and
    can therefore give one entry different answers in different runs of
    the same analysis; the C# side answers it once per ANALYSIS and
    made the disagreement unrepresentable. Until the Rust side reads
    its pass-1 experiment values per ENTRY rather than per file (the
    protein-compact map-back in osprey/crates/osprey/src/pipeline.rs),
    expect this to name experiment-scope fields on exactly the rows
    Stage 6 synthesized or moved. That is the gate reporting a known
    Rust-side defect, not drift introduced by the C# split.

    Decoding is delegated to the pwiz-side Regression/FdrSidecars.ps1
    so both byte layouts are described in exactly one place, shared
    with regression.ps1's four-task-chain leg.

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

# The file existing is no longer enough: the fused comparison arrived with the v5 scope split
# (issue #4486), so a pwiz checkout that predates it has FdrSidecars.ps1 but not this function.
# Same reasoning as the file check above - "this checkout cannot run this comparison" is a SKIP,
# not a failure, and calling a missing function would instead abort with a CommandNotFound that
# names nothing useful.
if (-not (Get-Command Compare-FdrSidecarsFused -ErrorAction SilentlyContinue)) {
    Write-Host "SKIPPED: this pwiz checkout's FdrSidecars.ps1 has no Compare-FdrSidecarsFused" `
        -ForegroundColor Yellow
    Write-Host "  It predates the v5 FDR sidecar scope split (issue #4486), so its C# side"
    Write-Host "  still writes the fused 68-byte record and there is nothing to reconstruct."
    exit 3
}

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
# The comparison itself is symmetric, but the two sides' ARTIFACTS are not: only the C# side
# has an analysis-wide experiment file, so the reconstruction runs in one direction.
$anyFail = $false
foreach ($pass in @(1, 2)) {
    $result = Compare-FdrSidecarsFused -RustDir $RustDir -CsDir $CsDir `
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
    Write-Host "OVERALL: FAIL -- the two implementations record different FDR values" `
        -ForegroundColor Red
    Write-Host "  A 1st-pass failure means the runs already diverged before reconciliation;"
    Write-Host "  fix that first, since it makes any 2nd-pass reading meaningless."
    Write-Host "  A 2nd-pass-only failure is a divergence in what pass 2 persists."
    Write-Host "  An experiment_* field differing on a SMALL number of 2nd-pass records is the"
    Write-Host "  known Rust-side per-file experiment-q lookup (issue #4486): Rust reads the"
    Write-Host "  entry's pass-1 experiment q from THIS file's sidecar, so a row Stage 6"
    Write-Host "  synthesized or moved misses and keeps its reset default. Confirm by reading"
    Write-Host "  the same entry_id across the run's sibling files before treating it as new."
    exit 1
}
Write-Host "OVERALL: PASS -- FDR values agree at $Tolerance" -ForegroundColor Green
exit 0
