# Osprey Diagnostic Environment Variables

Quick reference for all diagnostic env vars supported by both Osprey (C#)
and Osprey (Rust). These drive the cross-implementation bisection workflow.

## Cross-impl gating convention

All env vars use `=1` to enable (any other value, or absent = disabled).
One known asymmetry: Rust's `is_dump_enabled` accepts any value as truthy
while C#'s `IsOne` requires `"1"` exactly. Stick to `=1` for portability.

Dumps write to the **current working directory** of the running binary.
For `Compare-EndToEnd-Crossimpl.ps1` runs that's
`<workdir>/rust/` (Rust) and `<workdir>/cs/` (C#).

`*_ONLY=1` companion vars exit the process immediately after the dump
fires — fast bisection. Do NOT combine `*_ONLY=1` with end-to-end
pipeline scripts that expect full output.

Most numerical dumps use the project-wide `format_f64_roundtrip` helper
(`osprey_core::diagnostics` / `pwiz.Osprey.Core.Diagnostics`):
shortest decimal that round-trips back to the same f64 bits across all
magnitudes. Cross-impl byte-equal for any value both sides agree on at
the f64 level. Prefer the `ai/.tmp/diff_*.py` numerical helpers over
raw `diff` (handles CRLF and any residual format differences).

## Osprey `OSPREY_DIAGNOSTICS` master switch (C# only)

Osprey reads `OSPREY_DIAGNOSTICS=1` (until 2026-10-30 the `-d` / `--diagnostics`
argument, moved out of the user-facing help) as a
convenience that turns on the structured cross-impl dump bundle without
setting individual env vars. It enables every `OSPREY_DUMP_*` dump
**except** the per-call firehose `OSPREY_DUMP_MP_INPUTS`, the (currently
disabled) `OSPREY_DUMP_PREDICT_RT`, all `*_ONLY` early-exit gates, and the
`OSPREY_DIAG_*` per-entry selectors (which need specific IDs). For
fine-grained control set the individual env vars below instead -- they
compose with `OSPREY_DIAGNOSTICS` and still work on their own. Internally
the switch is implemented by the `OspreyDiagnostics` facade, which holds the live
`OspreyFileDiagnostics` sink only when a dump is enabled; with neither `OSPREY_DIAGNOSTICS`
nor any env var set, the sink is null and all diagnostics are a no-op.
(Rust osprey has no master switch; use the individual env vars.)

## Calibration Stage (Stage 3)

### OSPREY_DUMP_CAL_SAMPLE=1
Dump calibration sample entries + scalars + grid to `cs_cal_sample.txt` /
`rust_cal_sample.txt`. Format: tab-separated, sorted by entry_id.

### OSPREY_CAL_SAMPLE_ONLY=1
Exit immediately after calibration sample dump. Use with DUMP_CAL_SAMPLE
for fast cycle time.

### OSPREY_DUMP_CAL_WINDOWS=1
Dump per-entry calibration window info (one row per scored entry) during
calibration. Written after the calibration scoring loop completes.

### OSPREY_CAL_WINDOWS_ONLY=1
Exit after calibration window dump.

### OSPREY_DUMP_CAL_MATCH=1
Dump 11-column calibration match features to `cs_cal_match.txt` /
`rust_cal_match.txt`. Columns: entry_id, is_decoy, charge, has_match,
scan, apex_rt, correlation, libcosine, top6, xcorr, snr. F10 precision,
sorted by entry_id for stable diff.

### OSPREY_CAL_MATCH_ONLY=1
Exit after cal_match dump. Fast cycle for calibration feature comparison.

### OSPREY_DIAG_XIC_ENTRY_ID=<id>
Per-entry chromatogram diagnostic. Dumps candidates + extracted XICs for
the specified library entry ID. Includes PASS CALCULATIONS block (lib_rt,
expected_rt, tolerance, rt_window) and CANDIDATES + TOP-6 + XICS tables.
F10 precision. **Exits after write.**

### OSPREY_DIAG_XIC_PASS={1,2}
Select which calibration pass to dump (default: pass 1). Use with
DIAG_XIC_ENTRY_ID.

## LDA / FDR Scoring

### OSPREY_DUMP_LDA_SCORES=1
Dump per-entry LDA discriminant scores to `cs_lda_scores.txt` /
`rust_lda_scores.txt`. Columns: entry_id, is_decoy, discriminant, q_value.
F10 precision, sorted by entry_id.

### OSPREY_LDA_SCORES_ONLY=1
Exit after LDA scores dump.

## LOESS Calibration

### OSPREY_DUMP_LOESS_INPUT=1
Dump LOESS input pairs to `cs_loess_input_pass{N}.txt` /
`rust_loess_input_pass{N}.txt`. Columns: lib_rt, measured_rt. Sorted by
lib_rt ascending, at R (round-trip) precision.

### OSPREY_LOESS_INPUT_ONLY=1
Exit after LOESS input dump.

### OSPREY_LOESS_CLASSICAL_ROBUST=1
Switch LOESS robust iteration mode from Rust-compatible (residuals
computed once from initial fit) to classical Cleveland 1979 (residuals
refreshed per iteration). Supported in both tools.

## Main Search (Stage 4)

### OSPREY_DIAG_SEARCH_ENTRY_IDS=<id1,id2,...>
Dump XIC data for specified entry IDs during the main coelution search.
Does NOT exit - collects all in one run. Writes per-entry files.

### OSPREY_DIAG_MP_SCAN=<scan>
Dump median polish diagnostic for a specific scan number.

### OSPREY_DIAG_XCORR_SCAN=<scan>
Dump xcorr diagnostic for a specific scan number.

## Mass Calibration / MS2 errors

### OSPREY_DUMP_MS2_CAL_ERRORS=1
Dump every per-fragment MS2 mass error consumed by the calibration
Welford running mean. One row per `(entry_id, fragment_index, error_ppm)`.
The Osprey side ships this dump; the Rust side lands it bundled
with the LDA-side-effect-resort fix (maccoss/osprey Bucket 3e).

**When**: MS2 calibration mean/sd drift cross-impl despite bit-equal
`cal_match`. Tells you whether the order fragments arrive at Welford
differs (the historical bug was LDA's score-descending re-sort silently
feeding Welford a different sequence).

### OSPREY_MS2_CAL_ERRORS_ONLY=1
Exit after the MS2 cal errors dump.

### OSPREY_DUMP_CALIBRATION=1
Per-file calibration scalars (mean, sd, adjusted_tolerance for MS1 and
MS2; mad, p20_abs_residual, r_squared, residual_sd for RT) written from
the in-memory calibration that gets persisted to `.calibration.json`.
The authoritative cross-impl boundary check at the end of Stage 4 before
Stage 5 scoring.

### OSPREY_CALIBRATION_ONLY=1
Exit after the calibration summary dump.

### OSPREY_DUMP_PREDICT_RT=1
Two paired dumps: the calibration arrays (input `library_rts` and
`fitted_values`) and the per-call predicted RTs. Lets you tell whether
an `rt_deviation` divergence cross-impl is the arrays differing (JSON
round-trip lossy?) or `predict()` producing different output for byte-
identical inputs.

### OSPREY_DUMP_CWT_PATH=1
Per-spectrum CWT (continuous wavelet transform) peak-detection trace —
candidate peak positions, scores, and the winner. Used to bisect peak-
picking differences when peak boundaries differ cross-impl on the same
spectrum.

### OSPREY_DUMP_MP_INPUTS=1
The Tukey median-polish inputs (per-fragment-per-scan XIC matrix) for
a specific scan selected via `OSPREY_DIAG_MP_SCAN`. Used to bisect
`median_polish_*` PIN-feature divergence on one or two rows.

## Stage 5 — Scoring, standardizer, Percolator input

### OSPREY_DUMP_STANDARDIZER=1
Percolator feature-standardizer scalars (per-feature mean and stddev
across the training set). Confirms both ports computed the same
standardization before the SVM trains.

### OSPREY_STANDARDIZER_ONLY=1
Exit after standardizer dump.

### OSPREY_DUMP_PERCOLATOR=1 (Rust-only)
End-of-Stage-5 per-entry Percolator dump (score, pep, q-values). **Removed from C# Osprey
with the resident first-pass pool (#4821, 2026-10-11); C# refuses the variable at startup.**
Rust still writes it.

### OSPREY_PERCOLATOR_ONLY=1 (Rust-only)
Exit after the Percolator dump. C# refuses it at startup; to stop C# after Stage 5, run
`--task FirstPassFDR`.

### OSPREY_DUMP_PERC_INPUT=1 (C#-only)
Raw (unstandardized) per-entry feature vectors used for Percolator
subsample/scoring. C# diagnostic; maps to Rust's combination of
PERCOLATOR + STANDARDIZER dumps.

### OSPREY_PERC_INPUT_ONLY=1 (C#-only)
Exit after PERC_INPUT dump.

### OSPREY_DUMP_SUBSAMPLE=1
The Percolator subsampled training set — the `(entry_id, is_decoy,
base_id)` tuples kept after best-per-precursor dedup + optional
subsample-by-peptide-group. Verifies the SVM training set is bit-equal
cross-impl.

### OSPREY_SUBSAMPLE_ONLY=1
Exit after subsample dump.

### OSPREY_DUMP_SVM_WEIGHTS=1
Per-fold SVM weight vectors after Percolator training. Direct cross-
impl comparison of the solver output.

### OSPREY_SVM_WEIGHTS_ONLY=1
Exit after SVM weights dump.

## Stage 6 — Reconciliation, multi-charge consensus, refit

### OSPREY_DUMP_RESCORED=1 (Rust-only)
Per-file post-rescore FdrEntry stubs after the Stage 6 reconciliation-
aware re-scoring pass. **Removed from C# Osprey on 2026-10-11**: it pulled
every run's rescored entries at once (O(files x entries)) only to serve a
diagnostic. Rust still writes it; a harness must set it only for the Rust
process.

### OSPREY_RESCORED_ONLY=1 (Rust-only)
Exit after rescored dump. Removed from C# with the dump.

### OSPREY_DUMP_CONSENSUS=1
Per-peptide consensus RT computation (`PeptideConsensusRT`): contributing
detections, weights, median RT, peak widths. The cross-impl boundary
check for `consensus_rt`.

### OSPREY_CONSENSUS_ONLY=1
Exit after consensus dump.

### OSPREY_DUMP_MULTICHARGE=1 (Rust-only)
Multi-charge consensus selection per peptide group — the SVM-score-based
picking among charge states. **Removed from C# Osprey on 2026-10-11**: it
held every run's entries at once (O(files x entries)) only to serve a
diagnostic. Rust still writes it; set it only for the Rust process.

### OSPREY_MULTICHARGE_ONLY=1 (Rust-only)
Exit after multicharge dump. Removed from C# with the dump.

### OSPREY_DUMP_RECONCILIATION=1 (Rust-only)
Stage 6 reconciliation planner output: per-file `(entry_id, action,
new_apex_rt)` tuples telling the rescore loop what to do per stub.
**Removed from C# Osprey on 2026-10-11** for the same reason as
MULTICHARGE. Rust still writes it; set it only for the Rust process.

### OSPREY_RECONCILIATION_ONLY=1 (Rust-only)
Exit after reconciliation dump. Removed from C# with the dump.

### OSPREY_DUMP_REFIT=1 (Rust-only)
Refined per-file RT calibration after consensus rescoring -
`(library_rt, fitted_value, abs_residual)` per refit point.
**Removed from C# Osprey on 2026-10-16**: it wrote every run's refit at once,
and the refit moved into the per-run rescore. Each run's refit is in its own
`reconciliation.json` (`refined_rt_calibration`). Rust still writes it; set it
only for the Rust process.

### OSPREY_REFIT_ONLY=1 (Rust-only)
Exit after refit dump. Removed from C# with the dump.

### OSPREY_DUMP_LOESS_FIT=1 (Rust-only)
Per-point Stage 6 refit RTCalibration state. Lets you bisect a refit
ULP divergence between "stats computation differs" (R^2/SD/MAD computed
differently) vs "LOESS smoother arithmetic differs" (fitted_value
diverges). **Removed from C# Osprey on 2026-10-16** with OSPREY_DUMP_REFIT.

### OSPREY_LOESS_FIT_ONLY=1 (Rust-only)
Exit after LOESS fit dump. Removed from C# with the dump.

### OSPREY_DUMP_INV_PREDICT=1
Reconciliation inverse-predict records (mapping consensus library RTs
back to per-file measured RTs via the per-file refined calibration).
Required for Stage 6 reconciliation bisection.

### OSPREY_INV_PREDICT_ONLY=1
Exit after inverse-predict dump.

## Stage 7 — Protein parsimony + picked-protein FDR

### OSPREY_DUMP_PROTEIN_FDR=1
Stage 6 (first-pass, pre-compaction) protein-FDR per-group dump used
as input to the protein-aware compaction gate.

### OSPREY_PROTEIN_FDR_ONLY=1
Exit after first-pass protein FDR dump.

### OSPREY_DUMP_DETECTED_PEPTIDES=1
Sorted modified_sequence list of target peptides passing the
experiment-FDR gate — the input set handed to `build_protein_parsimony`
for Stage 7. **The first thing to diff** when Stage 7 protein-FDR
diverges cross-impl.

**CRLF caveat**: C# writes CRLF on Windows. Raw `diff` reports every
line as different; strip `\r` first or use `diff_*.py`.

### OSPREY_DUMP_BEST_PEPTIDE_SCORES=1
Per-modified_sequence aggregated max-SVM-score from
`collect_best_peptide_scores`. Sorted by modseq. Surfaces the protein-
FDR input set so upstream aggregation divergences (e.g. different
per-peptide max scores from post-compaction asymmetry) can be diffed
directly. This was the dump that surfaced the decoy gap-fill
duplication bug.

**When**: `compute_protein_fdr` receives bit-equal input modseq-set but
produces different `decoy_score` per group — this dump localizes which
peptide(s) have divergent max scores.

### OSPREY_DUMP_STAGE7_PROTEIN_FDR=1
Per-protein-group state at the end of second-pass picked-protein FDR.
Columns: `accessions`, `n_unique`, `n_shared`, `best_peptide_score`,
`group_qvalue`, `is_target_winner`. Sort order
`(is_target_winner DESC, group_qvalue ASC, accessions ASC)`. The numeric
`group_id` is intentionally NOT a column (HashMap iteration order is
per-run noise); join on `accessions`.

The cross-impl baseline check at the end of Stage 7.

### OSPREY_STAGE7_PROTEIN_FDR_ONLY=1
Exit after Stage 7 protein FDR dump.

### OSPREY_DUMP_STAGE7_WINNERS=1
Full cumulative-FDR winners list (target + decoy together) with `rank`,
`score`, `is_decoy`, `raw_qvalue`, `monotonic_qvalue`. Exposes decoy-
winner scores that the STAGE7_PROTEIN_FDR dump hides (decoy-winner
`best_peptide_score` falls to NaN there).

**When**: `group_qvalue` diverges but per-target-winner columns match —
the divergence is in decoy-side scoring or sort-position interleaving
in the cumulative sweep.

## Output

### OSPREY_DUMP_BLIB_QVALUES=1 (C#-only)
Pre-write q-values being inserted into the BLib RefSpectra /
RetentionTimes rows. No Rust counterpart — Rust's end-to-end output is
verified via `Compare-Blib-Crossimpl.ps1` at the SQL row level instead.

## Trace mode

### OSPREY_TRACE_PEPTIDE=<modseq>[,<modseq>...] (Rust-only)
Per-peptide diagnostic trace log lines. Set to a modified_sequence
(comma-separated for multiple) to emit `[trace]` log lines at first-pass
CWT scoring, `compute_consensus_rts`, `plan_reconciliation`,
`identify_gap_fill_targets`, and both FDR passes. Matches paired decoys
(`DECOY_<target>`) automatically. Zero overhead when unset
(OnceLock-guarded).

**When**: single peptide behaves wrong; lets you follow it through every
stage without dumping the full pipeline.

## Diff helpers (ai/.tmp/)

Python helpers that parse the f64 columns numerically rather than via
byte-equality (sidesteps CRLF and trailing-whitespace noise):

- `diff_winners.py` — `*_stage7_winners.tsv`
- `diff_best_peptide_scores.py` — `*_best_peptide_scores.tsv`
- `diff_ms2_cal_errors.py` — per-fragment MS2 calibration errors
- `diff_calibration_json.py` — calibration scalars bit-diff
- `diff_fdr_sidecars.py` — `.1st-pass.fdr_scores.bin` and
  `.2nd-pass.fdr_scores.bin`
- `diff_per_entry_modseqs.py` — `(entry_id, modseq, is_decoy)`
  cross-impl check derived from `.scores.parquet`

Prefer these over raw `diff` for any column with `format_f64_roundtrip`
output.

## When in doubt

Shortest path from "regression observed" to "diagnostic running":

1. Identify the stage where the divergence first appears (use
   `Compare-EndToEnd-Crossimpl.ps1`'s per-stage comparator output).
2. Find the dump for that stage in the catalog above.
3. Enable both sides with `=1` env var (set in both Rust and Osprey
   invocations).
4. Run with `*_ONLY=1` to exit immediately after the dump for a tight
   bisection cycle.
5. Diff with the matching `diff_*.py` helper, not raw `diff`.

If the dump you need does not exist, the pattern for adding one is in
`crates/osprey-fdr/src/diagnostics.rs` (Rust) or
`pwiz_tools/Osprey/Osprey.FDR/FdrDiagnostics.cs` (C#).
Keep the function name, env-var name, file name, and column order
identical cross-impl so the resulting dumps diff cleanly.

## Shared Calibration

### OSPREY_LOAD_CALIBRATION=<path>
Load calibration from a JSON file instead of computing it. Use to share
Rust's calibration with C# (eliminates independent-calibration noise in
feature comparison). The Test-Features.ps1 script uses this automatically.

## Benchmarking

### OSPREY_EXIT_AFTER_SCORING=1
Exit after Stage 4 scoring (skip FDR, reconciliation, blib output). Used
by Bench-Scoring.ps1 for Stages 1-4 timing.

## Usage Patterns

Prefer `Compare-Diagnostic.ps1` for routine bisection -- it runs both
tools, normalizes filenames, and diffs for you. Walk from earliest to
latest stage until you find the first divergence:

```powershell
# The canonical bisection walk - stop at the first DIVERGENCE
pwsh -File './ai/scripts/Osprey/Compare-Diagnostic.ps1' -Stage CalSample
pwsh -File './ai/scripts/Osprey/Compare-Diagnostic.ps1' -Stage CalWindows
pwsh -File './ai/scripts/Osprey/Compare-Diagnostic.ps1' -Stage CalMatch
pwsh -File './ai/scripts/Osprey/Compare-Diagnostic.ps1' -Stage LdaScores
pwsh -File './ai/scripts/Osprey/Compare-Diagnostic.ps1' -Stage LoessInput

# Iterate faster on C# changes by reusing Rust's dumps
pwsh -File './ai/scripts/Osprey/Compare-Diagnostic.ps1' -Stage CalMatch -SkipRust

# On Astral, or a different test-dir layout
pwsh -File './ai/scripts/Osprey/Compare-Diagnostic.ps1' -Dataset Astral -Stage CalSample
pwsh -File './ai/scripts/Osprey/Compare-Diagnostic.ps1' -Stage CalSample -TestBaseDir 'C:\test\osprey-runs'
```

For ad-hoc dumps (single tool, specific entries, benchmarking), use
`Run-Osprey.ps1` directly:

```powershell
# Main-search feature parity: run both tools through Stage 4 into SEPARATE directories (both
# write <stem>.scores.parquet; --cache-dir keeps the spectra caches out of the data folder), the
# C# run on Rust's calibration (OSPREY_LOAD_CALIBRATION - C# has no --load-calibration flag),
# then diff the per-candidate features column by column over the entry_ids both sides hold.
# (--write-pin and its .cs_features.tsv are gone, #4864.) Verified on Stellar 2026-10-18.
$rust = 'D:\test\osprey-runs\feature-parity\rust'; $cs = 'D:\test\osprey-runs\feature-parity\csharp'
pwsh -File './ai/scripts/Osprey/Run-Osprey.ps1' -Tool Rust -ExitAfterScoring "-ExtraArgs:--output-dir $rust --cache-dir $rust"
$env:OSPREY_LOAD_CALIBRATION = "$rust\<stem>.calibration.json"
pwsh -File './ai/scripts/Osprey/Run-Osprey.ps1' -Tool CSharp -ExitAfterScoring "-ExtraArgs:--output-dir $cs --cache-dir $cs"
Remove-Item Env:OSPREY_LOAD_CALIBRATION
python ./ai/scripts/Osprey/Compare/parquet_diff.py "$rust\<stem>.scores.parquet" "$cs\<stem>.scores.parquet" --tolerance 1e-6 --common-entries
# Reading it: the entry_id line is the candidate-set difference. modified_sequence (UniMod vs
# +mass notation) differs in REPRESENTATION on modified rows and says nothing about parity.
# Expected state (Stellar file 20, pwiz 1be16fdafe vs Rust 64e37ae, 2026-10-18): 0 entry_ids on
# one side only and every other column, fragment lists included, equal at 1e-6. Any further
# difference is drift. (Before Rust #73 there were 11 one-sided entry_ids and ~500 apex changes.)
# Rust writes its log and calibration_debug.csv to the working directory (the data folder) -
# delete them afterwards.

# Benchmark Stages 1-4 only (uses OSPREY_EXIT_AFTER_SCORING internally)
pwsh -File './ai/scripts/Osprey/Bench-Scoring.ps1' -Dataset Stellar
```

Only hand-craft env vars when extending the scripts -- the script
parameters below are the supported interface.

## Script Integration

`Run-Osprey.ps1` exposes each env var through a named switch:

| Parameter | Env Var |
|-----------|---------|
| `-DiagEntryIds` | `OSPREY_DIAG_SEARCH_ENTRY_IDS` |
| `-DiagCalSample` | `OSPREY_DUMP_CAL_SAMPLE` |
| `-DiagCalSampleOnly` | `OSPREY_CAL_SAMPLE_ONLY` |
| `-DiagCalWindows` | `OSPREY_DUMP_CAL_WINDOWS` |
| `-DiagCalWindowsOnly` | `OSPREY_CAL_WINDOWS_ONLY` |
| `-DiagCalPrefilter` | `OSPREY_DUMP_CAL_PREFILTER` |
| `-DiagCalPrefilterOnly` | `OSPREY_CAL_PREFILTER_ONLY` |
| `-DiagCalMatch` | `OSPREY_DUMP_CAL_MATCH` |
| `-DiagCalMatchOnly` | `OSPREY_CAL_MATCH_ONLY` |
| `-DiagLdaScores` | `OSPREY_DUMP_LDA_SCORES` |
| `-DiagLdaOnly` | `OSPREY_LDA_SCORES_ONLY` |
| `-DiagLoessInput` | `OSPREY_DUMP_LOESS_INPUT` |
| `-DiagLoessOnly` | `OSPREY_LOESS_INPUT_ONLY` |
| `-DiagXicEntryId` | `OSPREY_DIAG_XIC_ENTRY_ID` |
| `-DiagXicPass` | `OSPREY_DIAG_XIC_PASS` |
| `-DiagMpScan` | `OSPREY_DIAG_MP_SCAN` |
| `-DiagXcorrScan` | `OSPREY_DIAG_XCORR_SCAN` |

`Compare-Diagnostic.ps1` layers on top of these with a single
`-Stage {CalSample|CalWindows|CalMatch|LdaScores|LoessInput}` switch.

**Coverage gap**: the script wrappers above cover the Stage 3-4 dumps
(calibration discovery / mass cal / LOESS input). The Stage 5+ dumps
listed elsewhere in this doc (PERCOLATOR, RESCORED, SUBSAMPLE,
SVM_WEIGHTS, CONSENSUS, MULTICHARGE, RECONCILIATION, REFIT, LOESS_FIT,
INV_PREDICT, PROTEIN_FDR, DETECTED_PEPTIDES, BEST_PEPTIDE_SCORES,
STAGE7_PROTEIN_FDR, STAGE7_WINNERS, BLIB_QVALUES, MS2_CAL_ERRORS) do
not currently have `Run-Osprey.ps1` switches — set the env vars
directly. `Compare-EndToEnd-Crossimpl.ps1` is the integrated harness
that runs both sides end-to-end and compares Stage 5+ outputs at the
per-column 1e-9 level without per-dump scripting.
