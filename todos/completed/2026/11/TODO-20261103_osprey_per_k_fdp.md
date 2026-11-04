# TODO-20261103_osprey_per_k_fdp.md

## Branch Information
- **Branch**: `Skyline/work/20261103_osprey_per_k_fdp`
- **Base**: `master`
- **Created**: 2026-11-03
- **Status**: Completed
- **GitHub Issue**: [#4489](https://github.com/ProteoWizard/pwiz/issues/4489)
- **Module**: `osprey`
- **PR**: [#4987](https://github.com/ProteoWizard/pwiz/pull/4987) (merged 2026-11-03)
- **Worktree**: `C:\proj\wt-progress` (second branch in agent A's night-session worktree)

## Objective

Add a decoy-based per-k FDP to the `--model-diagnostics` run-count histogram, so the
per-slice contamination estimate exists on every dataset, not only on entrapment libraries.
Diagnostics only: JSON keys additive, pipeline output unchanged.

## Design (as built)

- `ModelDiagnosticsData.CrossRunView` gains `DecoyRunCountHistogram`, `DecoyFdpByRunCount`
  (FDP(k) = N_D(k) / N_T(k)) and `DecoyFdpAtLeastRunCount` (FDP(>=k), tails summed from k to N).
  N_T = real targets + entrapment (the decoys are drawn against both); target:decoy ratio 1
  (one decoy per target-side entry), so no ratio factor. NaN where a slice/tail holds no target.
- Symmetric run count: a decoy enters a run's set iff its OWN run q (and for the experiment
  view its own experiment q) clears the same gate the targets use; never its paired target's.
- Both producers: the batch `BuildCrossRunDetection` (test oracle) and the streamed
  `Accumulator` (production), sharing `AssembleCrossRunView` -> `SetDecoyFdpByRunCount`.
  `TestStreamingAccumulatorMatchesBatch` (JSON equality) covers the new keys.
  Memory: two more `CrossRunStream`s, O(distinct passing decoys) ~ FDR x targets.
- Report template: dashed indigo decoy-FDP curve on the histogram's right axis beside the
  amber entrapment curve (legend toggles both), tooltip counts, a decoy k=1 vs k=N note, and a
  new card "Decoy-estimated FDP vs required reproducibility" plotting FDP(>=k) for both scopes
  with KPIs.
- Definition: new section "Decoy-based FDP by run count" in
  `pwiz_tools/Osprey/docs/fractional-entrapment.md` (the diagnostics page) + README index line.

## Decisions Brendan might revisit

- Plain D/T (no +1 correction, no pi0): a per-slice descriptive estimate, not a q-value. The
  issue asked for "the identical ratio / pi0 / paired conventions Osprey applies to its reported
  q"; Osprey's q uses competition counts with no pi0, and per-slice +1 would dominate small
  slices, so it was left out.
- Peptide/protein levels: the view follows the configured `--fdr-level` gate exactly as the
  existing target histogram does; no separate per-level decoy views were added.

## Measured: decoy vs entrapment per-k FDP (pass 1, Stellar 3 runs)

From the regression straight-through reports
(`pwiz_tools/Osprey/TestResults/regression-20261103_150453_164332/StellarLibDecoy/straight/` and
`regression-20261103_155102_163368/StellarGenDecoyEntrap/straight/output.model-diagnostics.html`,
read with `ai/.tmp/sessions/20261103-agentA/read_decoy_fdp.py`). k = 1, 2, 3:

| Dataset | scope | entrapment FDP(k) | decoy FDP(k) | decoy FDP(>=k) |
|---|---|---|---|---|
| StellarLibDecoy | per-run | 6.13%, 1.03%, 0.13% | 6.26%, 1.60%, 0.26% | 1.78%, 0.56%, 0.26% |
| StellarLibDecoy | experiment | 3.41%, 0.84%, 0.12% | 3.76%, 1.32%, 0.25% | 1.00%, 0.48%, 0.25% |
| StellarGenDecoyEntrap | per-run | 8.68%, 1.96%, 0.32% | 6.29%, 1.42%, 0.27% | 1.79%, 0.53%, 0.27% |
| StellarGenDecoyEntrap | experiment | 4.60%, 1.41%, 0.32% | 3.93%, 1.15%, 0.26% | 1.00%, 0.46%, 0.26% |

The two curves agree in shape and closely in level: library decoys track the entrapment line
within ~1.0-1.3x at k=1; generated decoys read ~0.7-0.85x of it. Not investigated which side
is off (the library guide notes shuffle entrapment over-identifies, if that is what this library
carries). Experiment-wide FDP(>=1) = 1.00% on both, the nominal 1%.

## Code review (/code-review medium, 2026-11-03)

Eight findings, triaged:
- FIXED (design change): pass-2 symmetry is broken by Stage 6 gap-fill (targets that passed are
  re-scored into the runs they missed; decoys only ride along with their target), so a pass-2
  decoy curve would be biased low at high k / high at k=1. The pass-2 views now carry no decoy
  FDP (`WithoutDecoyFdp`); pass 1 keeps it. Tested in TestStreamingAccumulatorMatchesBatchPass2.
  **Brendan may want this revisited** (e.g. exclude gap-filled rows and keep a pass-2 curve).
- FIXED (doc): a precursor's k mixes true detections with null wins in runs where it is absent,
  which blurs the estimate between slices. Documented as an approximation ("read as a trend").
- FIXED (doc + comments): "never conditioned on the paired target" overstated it - run q is
  winner-only per file, so a decoy only counts in runs where it won its competition. Restated in
  TDC terms in the doc, code comment and report text.
- FIXED: memory comment claimed O(FDR x targets); per-run null decoys are mostly fresh, so it
  grows with run count, bounded by the decoy library. Comment corrected, and the decoy streams
  now keep only the run-count tally (`CrossRunStream(n, runCountOnly: true)`, no union/intersection).
- FIXED: the right FDP axis was amber with only the indigo decoy curve on it; it now takes the
  decoy color when no entrapment curve is present.
- FIXED: the own-run-count test fixture had target and decoy both winning run 1, which
  winner-only run q cannot produce; now T wins run 1 and D2 wins runs 2-3.
- DROPPED: indigo means "decoy FDP" on the histogram and "experiment-wide" on the floor card;
  the floor card follows the existing union-FDP card's convention (accent = experiment-wide,
  decoy red = per-run), and the cards are read separately.
- DROPPED: three near-identical NaN-breaking polyline helpers in the template; each panel in
  this template owns its drawing helpers, and a shared one is a template-wide refactor.

## Tasks

- [x] Data model + both producers
- [x] Unit tests (ModelDiagnosticsDataTest.TestCrossRunDetection: own-run-count symmetry, NaN
      slices, entrapment in the denominator, at-least tail)
- [x] Template overlay + card; inline JS passes `node --check`
- [x] Docs definition
- [x] Osprey gate: 650/650, inspection zero (`ai/.tmp/sessions/20261103-agentA/gate-i2b.log`)
- [x] regression.ps1 Stellar, StellarLibDecoy, StellarGenDecoyEntrap - all PASSED, goldens
      unchanged (`.../regress-item2-<Dataset>.log`)
- [x] Read the decoy and entrapment curves (table above)
- [x] /code-review medium, triage (above)
- [x] PR #4987 opened (TeamCity Perf/Regression gate NOT triggered - parent session queues it)

## Progress Log

### 2026-11-03 - Session 1 (night agent A)
- Implemented the estimator, tests, report overlay + card and doc section.

### 2026-11-03 - Merged

PR #4987 merged as commit 8f7c835d99. Shipped: decoyRunCountHistogram, decoyFdpByRunCount and decoyFdpAtLeastRunCount on every pass-1 crossRun view from both the batch oracle and the streamed accumulator, the dashed decoy-FDP curve and the FDP-vs-reproducibility card, definitions in docs/fractional-entrapment.md; goldens unchanged on Stellar, StellarLibDecoy and StellarGenDecoyEntrap. Deferred by design: no pass-2 decoy curve (gap-fill bias), plain D/T estimator without +1 or pi0, no separate peptide or protein-level views. The PR's Fixes line closed #4489.
