# TODO-osprey_diagnostics_fdr_plots.md -- Ship the FDR-calibration diagnostic plots we built by hand as first-class Osprey.Diagnostics exports

## Status
Backlog (brendanx67). Not started. Motivated by the 2026-07-03/04 FDR-calibration
sprint: a handful of plots proved decisive for understanding how Osprey's FDR is
performing and where its assumptions fail. They were built as one-off Python against
the sidecar + parquet + manifest; they should become reproducible `-d` diagnostics so
we (and Mike) can generate them for any run without the ad-hoc scripts.

## Why (what each plot told us that nothing else did)
- The **paired decoy-win fraction** is the single most valuable one: target-decoy
  COMPETITION depends on the WITHIN-PAIR ordering, which marginal density plots cannot
  see. Two identical-looking marginals can encode a fair coin (calibrated) or
  target-always-wins (0% reported FDR). Only the win fraction exposes it. It cleanly
  separated the two failure regimes: libdecoy entrapment coin ~50% (valid nulls) vs
  gendecoy ~22% (generated decoys too weak). See
  [[project_osprey_libdecoy_vs_gendecoy_calibration]].
- The **4-class density** (target T / entrapment P / decoy D / p_decoy Pd) is the
  human-eye view: once the target curve is in frame, its left (null) half failing to
  overlay the decoy/entrapment curves is visible -- the gendecoy miscalibration.
- The **entrapment q-q / accepted-set Venn** quantified the cost of doubling a library
  with sample-absent entrapment (net -1,872 real IDs at 1% on Stellar file 20; the
  confident core sharpens, the marginal band sloughs off).
- The **FDRBench q-q with lower_bound + combined** is the external-oracle calibration
  curve (already produced via `Run-FdrBench.ps1`).

## Prototypes (the spec)
Working Python in `ai/.tmp/OspreyFDR/` (NOT committed; reference only):
`winfrac-plot.py` (paired win fraction), `density-plot.py` / `density-plot-gendecoy.py`
(4-class density), `qq-entrapment.py` + `venn-entrapment.py` (library-impact q-q/Venn),
`qq-with-lowerbound.py` (FDRBench oracle q-q). Data sources they use are ALREADY inside
Osprey at diagnostic time: `.1st-pass.fdr_scores.bin` (entry_id -> score + q-values, see
`FdrScoresSidecar`), the per-file `.scores.parquet` (is_decoy, modified_sequence), and the
decoy-pairing manifest (peptide_type target/p_target/decoy/p_decoy). base_id =
entry_id & 0x7FFFFFFF pairs a target-type with its decoy-type.

## Work
1. **Pick the rendering path (open decision).** Osprey.Diagnostics is `-d`-only, off the
   mainline output path ([[project_ospreysharp_output_architecture]]). Decide: (a) emit
   tidy per-plot CSV + a committed plotting script (no C# charting dependency), or
   (b) render PNG in-process. Prefer (a) first -- the data extraction is the hard/valuable
   part; charting can follow. Whatever renders must not pull a charting lib into the
   mainline assemblies.
2. **Win-fraction diagnostic first** (highest value). Emit, per (real-target-pair,
   entrapment-pair): decoy-win fraction vs winner-score bins + the null-band summary +
   the fair-coin reference. Works whenever a pairing manifest is present; degrade
   gracefully to real-target-only when no entrapment.
3. **4-class density** second (needs the manifest for the P/Pd split; without it, T vs D).
4. **Library-impact q-q / Venn** and **FDRBench oracle q-q** as a second tier (these
   compare two runs / an external tool -- more of an analysis harness than a per-run `-d`).
5. Gate behind a `-d` sub-flag (e.g. `--diagnostics-plots`), never on the default path;
   localize any user-facing text ([[no_localizable_string_in_static]]).

## Gates
- No change to non-`-d` output (regression golden unaffected).
- `Build-Osprey.ps1 -RunTests -RunInspection` clean.

## References
- `FdrScoresSidecar.cs` (sidecar format), the scores.parquet schema, the pairing manifest.
- Related: [[project_ospreysharp_output_architecture]] (Diagnostics is -d-only),
  the FDR-calibration understanding in this sprint's TODO history.
- Pairs conceptually with [[TODO-osprey_assumption_failure_detection]] (the plots are the
  human view; that TODO is the automated version).
