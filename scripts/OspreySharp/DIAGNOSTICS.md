# OspreySharp Diagnostic Environment Variables

Quick reference for all diagnostic env vars supported by both OspreySharp (C#)
and Osprey (Rust). These drive the cross-implementation bisection workflow.

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

```bash
# Compare calibration features (fast cycle)
OSPREY_DUMP_CAL_MATCH=1 OSPREY_CAL_MATCH_ONLY=1 osprey ...
OSPREY_DUMP_CAL_MATCH=1 OSPREY_CAL_MATCH_ONLY=1 pwiz.OspreySharp.exe ...
diff <(tr -d '\r' < rust_cal_match.txt) <(tr -d '\r' < cs_cal_match.txt)

# Compare LDA scores
OSPREY_DUMP_LDA_SCORES=1 OSPREY_LDA_SCORES_ONLY=1 osprey ...
OSPREY_DUMP_LDA_SCORES=1 OSPREY_LDA_SCORES_ONLY=1 pwiz.OspreySharp.exe ...

# Share Rust calibration for main-search feature comparison
osprey -i file.mzML -l lib.tsv -o rust.blib --resolution unit --write-pin
OSPREY_LOAD_CALIBRATION=file.calibration.json pwiz.OspreySharp.exe \
  -i file.mzML -l lib.tsv -o cs.blib --resolution unit --write-pin

# Benchmark Stages 1-4 only
OSPREY_EXIT_AFTER_SCORING=1 pwiz.OspreySharp.exe ...
```

## Script Integration

The `Run-Osprey.ps1` script exposes many of these via parameters:

| Parameter | Env Var |
|-----------|---------|
| `-DiagEntryIds` | `OSPREY_DIAG_SEARCH_ENTRY_IDS` |
| `-DiagCalMatch` | `OSPREY_DUMP_CAL_MATCH` |
| `-DiagCalMatchOnly` | `OSPREY_CAL_MATCH_ONLY` |
| `-DiagLdaScores` | `OSPREY_DUMP_LDA_SCORES` |
| `-DiagLdaOnly` | `OSPREY_LDA_SCORES_ONLY` |
| `-DiagLoessInput` | `OSPREY_DUMP_LOESS_INPUT` |
| `-DiagLoessOnly` | `OSPREY_LOESS_INPUT_ONLY` |
