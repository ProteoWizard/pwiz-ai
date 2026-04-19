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

Prefer `Compare-Diagnostic.ps1` for routine bisection -- it runs both
tools, normalizes filenames, and diffs for you. Walk from earliest to
latest stage until you find the first divergence:

```powershell
# The canonical bisection walk - stop at the first DIVERGENCE
pwsh -File './ai/scripts/OspreySharp/Compare-Diagnostic.ps1' -Stage CalSample
pwsh -File './ai/scripts/OspreySharp/Compare-Diagnostic.ps1' -Stage CalWindows
pwsh -File './ai/scripts/OspreySharp/Compare-Diagnostic.ps1' -Stage CalMatch
pwsh -File './ai/scripts/OspreySharp/Compare-Diagnostic.ps1' -Stage LdaScores
pwsh -File './ai/scripts/OspreySharp/Compare-Diagnostic.ps1' -Stage LoessInput

# Iterate faster on C# changes by reusing Rust's dumps
pwsh -File './ai/scripts/OspreySharp/Compare-Diagnostic.ps1' -Stage CalMatch -SkipRust

# On Astral, or a different test-dir layout
pwsh -File './ai/scripts/OspreySharp/Compare-Diagnostic.ps1' -Dataset Astral -Stage CalSample
pwsh -File './ai/scripts/OspreySharp/Compare-Diagnostic.ps1' -Stage CalSample -TestBaseDir 'C:\test\osprey-runs'
```

For ad-hoc dumps (single tool, specific entries, benchmarking), use
`Run-Osprey.ps1` directly:

```powershell
# Share Rust calibration for main-search feature comparison
pwsh -File './ai/scripts/OspreySharp/Run-Osprey.ps1' -Tool Rust  -Clean -WritePin
pwsh -File './ai/scripts/OspreySharp/Run-Osprey.ps1' -Tool CSharp -WritePin `
     -ExtraArgs "--load-calibration file.calibration.json"

# Benchmark Stages 1-4 only (uses OSPREY_EXIT_AFTER_SCORING internally)
pwsh -File './ai/scripts/OspreySharp/Bench-Scoring.ps1' -Dataset Stellar
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
