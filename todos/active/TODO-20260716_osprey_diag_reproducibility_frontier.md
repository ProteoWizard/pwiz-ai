# TODO-osprey_diag_reproducibility_frontier.md -- Reproducibility-vs-FDR diagnostics + the iso-FDR "frontier" card (C#-backed)

## Status
**Active (created 2026-07-16).** Branch `Skyline/work/20260716_osprey_diag_reproducibility_frontier`
(pwiz-work2). Grew out of an extended exploration with Brendan on the model-diagnostics
Reproducibility tab, motivated by a journal (MCP) discussion on whether experiment-wide q
should be a *required* FDR-control standard for DIA. Entrapment-validated on Mike's SEA-AD
Pilot-MTG 82-file Astral-DIA run.

## What ships (two parts)

### Part A -- live, template-only (JS), ready
Reproducibility-tab cards computed from data already in the diagnostics JSON:
- **Peptides accepted vs required reproducibility** -- yield vs run-count cutoff at fixed q,
  both scopes on one count axis, solid/faded by FDR-control, ring at the 1% crossing.
- Reorg: the new cards sit after the two Collins/Skyline-style detection plots; the tab's
  per-run / experiment-wide selector drives the toggle-sensitive plots; removed the earlier
  redundant "FDR by reproducibility cutoff" card (subsumed by the yield card).
- Histogram + Union-FDP cards unchanged.

### Part B -- the frontier card (needs C#) -- THIS TASK
**"Yield at fixed FDR vs required reproducibility"**: holding entrapment-measured FDP at the
nominal target and *floating the q-cutoff upward* as the run-count requirement rises. Left axis
= real precursors accepted at that FDR; right axis = the loosest q-cutoff Q* that still holds it.
The curve rises to a peak (~≥3 runs here) then falls -- an efficient-frontier sweet spot.
KPI tiles: max detected, best Q*, best run count, cross-scope overlap, gain vs the standard.

**The finding (entrapment-validated, this dataset):** the experiment-wide-q "standard" accepts
37,174 at 0.84% FDP; the reproducibility peak accepts 45,129 at 1.0% -- the standard forgoes
~18% of achievable, reproducible (>=3-run) detections at matched FDP. Both scopes gain (~+17-21%),
and the per-run and experiment-wide optimal sets are ~94% the SAME peptides -- reproducibility,
not the q statistic, is the dominant selector.

## Why C# (not JS-only like Part A)
The frontier needs the **un-gated 1st-pass joint distribution** of (per-run q x run-count) for
real-target and entrapment precursors -- the q>1% candidates a looser Q would admit. The standard
diagnostic JSON is pre-thresholded at q<=1%, so it cannot be derived in JS. The prototype baked
offline-computed arrays into the demo HTML; the real feature computes them in Osprey.

## Feasibility (confirmed)
`ModelDiagnosticsData.Accumulator.Add(...)` is fed **one scored pre-compaction first-pass row per
(file,row)** with its first-pass q-values (`FdrProjectionSinks`), and already computes
`q.EffectiveRunQvalue` / `EffectiveExperimentQvalue` -- it just gates at `<= _runFdr` before
tallying (Accumulator.cs:195). So the un-gated per-run q is already in hand at the tally point.

## Design
- **Q-grid** (~25 thresholds, 0.001..0.10) in the accumulator.
- Per **target-side** precursor (real + entrapment; skip decoys), accumulate a small
  `byte[qGrid]` "first-qualifies-at-bin b" count across files (b = smallest bin with
  effRunQ <= Q[b]); cumsum over bins => run-count at each Q threshold. (~2.96M precursors x
  25 bytes ~= 74MB, acceptable on the -d-only diagnostics path.) Also keep effective exp-q
  (already in `_best`) and run-count at run-q<=target for the experiment-wide scope.
- At **Build**, port the validated numpy frontier math: per scope, for each run-count K find the
  loosest Q with FDRBench-combined FDP `(1+1/r)*np/(nt+np) <= target`; record yield + Q*; compute
  the apex cross-scope overlap and the best-peak-standard yield. Emit a `Frontier` object.
- **Serialize** as top-level `D.frontier` (1st pass only; NOT under `D.pass2`).
- **Template**: `drawFrontier` reads `D.frontier` (as the prototype does). Remove the "Prototype"
  labeling. **2nd-pass mode: show the panel with no graph + a short explanation** (the loosen-q
  sweep needs the pre-compaction pool the 2nd pass no longer has); **1st-pass: no message**, just
  the graph.

## Tasks
- [ ] Accumulator: Q-grid + per-target-side-precursor run-q-bin accumulation (un-gated).
- [ ] `ModelDiagnosticsData.Frontier` data class (per-scope yield[]/q[], N, target, bestPeak,
      apex overlap, peak K/Q/yield).
- [ ] Build: port the numpy frontier + overlap + standard math; wire into the data object.
- [ ] Serialize `D.frontier` (1st pass only) via ModelDiagnosticsHtml.
- [ ] Template: `drawFrontier` 2nd-pass no-graph + explanation; drop prototype labeling; keep
      KPI tiles + the standard reference line.
- [ ] Validate the C# frontier reproduces the offline numpy numbers (peak K=3, 45,129 / 44,418,
      Q* 0.008 / 0.04, overlap 94%, standard 37,174) on the SEA-AD 82-file run.
- [ ] Gate: Build-Osprey -RunTests -RunInspection; regression.ps1 unaffected (diagnostics output
      is not in the blib golden -- confirm).

## Follow-ups (separate, NOT this PR)
- **Decoy-vs-entrapment calibration check.** "Can this be predicted with decoys instead of an
  entrapment library?" Offline prototype says decoys are anti-conservative on the reproducibility
  frontier: at the decoy-picked 1% point the entrapment truth is ~1.24% (experiment-wide) / ~1.89%
  (per-run). Mechanism: decoys are random and don't reproduce; real interfering false positives
  (entrapment) do -- score-level calibration (q-q plots) does not imply reproducibility-level
  calibration. MAGNITUDE NOT TRUSTED (rough estimator); needs a rigorous real-decoy run-count
  tally + oracle check before shipping. Add as a second frontier curve/KPI once verified.
- **Standalone MCP note**: method + the three findings (+~19% at matched FDR, peak at >=3, 94%
  content overlap) for the journal-guidelines discussion.

## References
- Prototype + validation (numpy, this session): reproduces the diagnostics q<=1% histograms to
  ~2% (independent 1st-pass detections vs reconciled+gap-fill). Data:
  `D:\test\Pilot-MTG-Tissue-May2026\runs\pass2ab-82file-percolator-Bmdiag\` (1st-pass sidecars +
  parquet protein_ids for entrapment class + `lib\...\osprey_library_db_pairing.tsv`).
- Estimator: `ModelDiagnosticsData.cs:1393` (FDRBench combined). Accumulator: Accumulator.cs:195.
- Related: [[project_osprey_libdecoy_vs_gendecoy_calibration]] (decoys anti-conservative -- consistent
  with the frontier decoy finding), [[project_sead_pilot_mtg_dataset]].
