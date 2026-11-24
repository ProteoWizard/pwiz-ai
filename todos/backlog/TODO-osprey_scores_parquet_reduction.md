# Shrink the per-run .scores.parquet stub after per-run first-pass models

**Status**: Backlog. Written 2026-11-24 on MACS2 (Brendan), while the SEA-AD and TDP-43 runs of
[#5070](https://github.com/ProteoWizard/pwiz/pull/5070) were going. Starts after #5070 merges: it changes
the stub #5070 introduces.
**Module**: `osprey`
**Related**: #5070 (per-run first-pass models, which made `<stem>.scores.parquet` a stub),
[TODO-20261030_osprey_scoring_library.md](../active/TODO-20261030_osprey_scoring_library.md)

## Why

After #5070 the stub is still most of what Osprey writes beyond the mass spec data. On SEA-AD (82 Astral
runs) #5070 writes 24.9 GB in all, and the stubs are almost all of it, about 258-280 MB per run. One stub
holds a row for every library entry scored in that run, targets and decoys: 4,403,242 rows, of which only
63,188 (1.4%) are at run q 1%. About half of the rows score within 0.1 of the run's median best decoy
(calibrated score -1).

The goal is a stub several times smaller, with the **blib byte-identical**: the same precursors, the
same q-values, the same PEPs and the same per-run peaks.

## What the stub holds (one SEA-AD #5070 stub, written by Parquet.Net)

Per row, in compressed bytes: `fragment_coelution_sum` 7.7, `score` 7.4, `bounds_area` 7.2, `bounds_snr`
6.6, `start_rt` 6.1, `end_rt` 6.1, `apex_rt` 6.1, `protein_best` 3.8, `run_precursor_q` 3.6,
`run_peptide_q` 3.2, `entry_id` 2.8, `scan_number` 2.7, `charge` 0.3, `is_decoy` 0.0. About 58 bytes per
row in all.

| Calibrated score in the run | Rows | Targets | Decoys |
|---|---|---|---|
| all | 4,403,242 | 2,211,049 | 2,192,193 |
| >= -1 (median best decoy) | 2,236,303 | 1,140,206 | 1,096,097 |
| >= -0.5 | 134,279 | 105,596 | 28,683 |
| >= 0 (run q 1%) | 63,307 | 62,571 | 736 |

## Who reads which rows, and what each needs

1. **The experiment q-values in FirstPassFDR** (`PercolatorQValues.ComputeExperimentPrecursorQMap`).
   - Each pair's experiment score is its best over runs. Target-decoy competition keeps one winner per
     pair, and the winners are ranked by score.
   - q at rank i is the backward minimum over j >= i of (D_j + 1) / T_j. That backward minimum is the only
     reason the tail could matter.
   - **A floor is provably exact.** Each run keeps full rows only at calibrated score >= F. Then every
     pair whose experiment score is >= F has its true winner and score. A partner below F in every run
     loses, so the pairs need no keeping; the count of unseen pairs comes from the library.
   - With K winners at or above F and U library pairs never seen, every lower rank has FDR >= L =
     (D_K + 1) / (T_K + U). So every q <= L, and every decision at a threshold below L, is exact. The
     reduce computes L and refuses (or falls back) when L <= the threshold.
   - The peptide q and first-pass protein FDR take the same argument with their own unseen counts. So
     does pass-2 protein FDR, which scores every protein from the first-pass experiment sidecar.
   - Run q is computed in PerFileScoring from the full run, before anything is dropped.
2. **PEP** (`PercolatorQValues.ComputePepWinnerMap`). PEP is a KDE fit over every competition winner, so
   dropping tail rows changes it everywhere. Under the pass-2 q-value transfer, the experiment values come
   from the first-pass experiment sidecar, so first-pass PEP is what `RefSpectra.PrecursorPep` carries.
   Keeping PEP identical means keeping `entry_id` and `score` for every row. Decided 2026-11-24: keep
   them, rather than accept a PEP change.
3. **The per-run peaks of retained precursors.** The blib records a peak for every run of a passing
   precursor (a 3-run test: 120 spectra, 360 peaks). PerFileRescoring carries an unmoved row at its
   first-pass peak, so a retained precursor that scored below F in some run still needs that run's
   first-pass peak (scan, apex/start/end RT and the values the carried row reports). Two ways to get it:
   - keep a few slim peak columns for every row;
   - re-score those entry-run pairs in PerFileRescoring. Scoring is bit-reproducible, so the blib does not
     change; the cost is extra rescoring.
4. **Diagnostics that read every row**: the FDRBench pass-1 TSV and the model-diagnostics report. They
   lose the below-floor values and change, but do not feed the blib.

## Size estimates (pyarrow and zstd rewrites of one stub; Parquet.Net writes the original 15% smaller)

| Layout | Size |
|---|---|
| all columns (pyarrow baseline) | 330.8 MB |
| other columns null below F = -0.5 (134,279 full rows) | 75.1 MB (22.7%) |
| null below F = 0 (63,307 full rows) | 68.3 MB (20.7%) |
| `entry_id`, `score`, `is_decoy`, `charge` only | 62.8 MB |
| the same, delta-encoded ids, byte-stream-split score | 33.1 MB (10%) |

Nulls cost almost nothing, so the floor can sit low for margin. The `score` double dominates;
byte-stream-split keeps every bit (PEP unchanged) and halves it. Not yet measured: the combined layout
(estimated 40-45 MB per run, about 3.5 GB for SEA-AD instead of about 21 GB).

## Open questions, to settle before any code

- Is the transfer's score-to-q mapping a stored table (the run's `.1st-pass.model.json`), or interpolated
  from the stub's (score, run q) rows? If the latter, it reads the tail.
- Do the blib's per-run rows record run q for runs where the precursor did not pass?
- Does Parquet.Net support byte-stream-split and delta-binary-packed encodings?
- What is L at F = -0.5, -0.25 and 0 on SEA-AD and TDP-43? How many retained entry-run pairs fall below
  each F (the rescoring cost of option 3b)?

## Plan

1. From the 82 stubs of the SEA-AD #5070 run (`D:\Users\brendanx\test\osprey-runs\sea-ad\runs\
   seaad-82files-libdecoy-r1.0-defaultpr5070` on MACS2), offline:
   - D_K, T_K, U and L per floor;
   - whether the passing set at experiment q 1% matches the full run exactly;
   - the retained entry-run pairs below each floor.
2. Answer the open questions above in the code.
3. Write the stub with nulls below F and the cheapest encodings Parquet.Net offers; add the L check to
   FirstPassFDR; choose option 3a or 3b by the measured rescoring cost.
4. Gate: regression tests pass unchanged (blib byte-identical); SEA-AD 82-file run with the same blib and a
   measured disk and time change.
