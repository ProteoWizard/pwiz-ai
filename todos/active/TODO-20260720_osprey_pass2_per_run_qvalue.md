# TODO: Pass-2 changes ONLY per-run q -- unify transfer + remodel on the correct invariant

## Branch Information
- **Branch**: `Skyline/work/20260720_osprey_pass2_per_run_qvalue` (off master df9bb0121)
- **Status**: Active (started 2026-07-19 night, autonomous session)
- **Commits**: a98759c72 (redesign) + 14d2782b4 (AssignPerRunQ testable seam + unit test)

### Progress (2026-07-19/20 night, autonomous)
IMPLEMENTED the TRANSFER-path redesign (default percolator unchanged):
- Stage-5 made mode-independent: `OSPREY_PASS2_QVALUE=transfer` no longer forces the resident
  first-pass pool (dropped from `needsResidentFirstPassPool` + `NeedsResidentPool`); it takes the
  same lean projection first pass as default. A `captureModel` hook was threaded through the
  projection path (PercolatorFdr.RunStreamingFirstPass + PercolatorEngine.RunStreamingIntoProjection/
  RunFirstPassStreaming/RunPercolatorFdr-projection) so `FirstPassPercolatorModel` is still published
  (gated on Pass2TransferQ).
- Deleted `BuildFullPopulationScoreQTable` + the `FirstPassScoreQTable` byproduct + `TransferQWithTable`
  (the coarse whole-pool 4-slot flatten). Replaced with `Pass2FdrSidecar.TransferPerRunQ`: per file,
  build (1st-pass score -> run q) tables from that file's OWN `.1st-pass.fdr_scores.bin`, then
  `AssignPerRunQ` classifies each survivor -- UNCHANGED (carry the record verbatim), MOVED (re-map run
  q, carry experiment q), GAP-FILL (table run q + the precursor's cross-file pass-1 experiment q).
- KEY verified fact: both 1st-pass paths store the AVERAGED-model score (no Granholm), == the
  ScoreWithFrozenModel scale, so the sidecar-Score->run-q table is scale-consistent and `newScore ==
  Score1` is a reliable bit-exact MOVED discriminator (unchanged rows stream original features through
  the reconciled parquet). Experiment q is frozen by the best-peak anchor +
  `ClampExperimentQToBestRun` (a floor that only raises to min-run-q; best run untouched).
- GATES ALL GREEN: build net472+net8.0 clean, inspection 0 warnings, 519 unit tests pass (+1
  TestAssignPerRunQCarriesExperimentQ). regression.ps1 -Dataset Stellar mode1/2/3 blib 45,064,192 ==
  golden (default byte-identical).
- ENTRAPMENT ORACLE (deliverable MET, 20-file r=0.97, runs\pass2ab-20file-transfer-perRunOracle):
  Pass-2 exp-wide @q<=1% = 44,287 disc @ 0.87% combined FDP (qmax 1.00) vs coarse 55,555 @ 3.09%
  (qmax 0.95) vs retrain 60,840 @ 3.34%. Pass-2 per-run = 367 distinct q vs coarse 81. => calibrated
  exp-wide (reproduces pass-1 by the carry invariant) + real per-run resolution; the coarse
  quantized-band + q-truncation signature eliminated. Classified 1.39M unchanged / 1.28M moved / 86K
  gap-fill; no fallback. Memory ~30-42 GB (no resident pool). commit c/self-review commit 8a8713f82.
- SELF-REVIEW CLEAN (Critical/High 0, 1 Medium addressed) + Copilot addressed+resolved. PR #4438 open.
- 82-FILE B ARM in flight (runs\pass2ab-82file-transfer-5dayTransferPerRun, ~03:00-03:30 ETA), full-scale.
- BLOCKED: TeamCity Perf/Regression -- classifier enforces the "Brendan gates TC manually" boundary;
  Brendan to trigger pull/4438 manually. Design notes: ai/.tmp/pass2-per-run-qvalue-design.md;
  results handoff: ai/.tmp/handoff-20260720-perrunq-results.md.
- LOW follow-ups (deferred): (a) TransferPerRunQ orchestration lacks a unit test (only oracle-validated);
  (b) each 1st-pass sidecar is read twice (deliberate: gap-fill exp q needs a global-first pass);
  (c) bit-exact newScore==Score1 discriminator is documented + robust-under-misclassification (exp q is
  always the pass-1 carry, so a misclassify only coarsens per-run q, never perturbs experiment q).
- DEFERRED (needs golden regen + Mike): unify the DEFAULT remodel path onto the same invariant.

**Priority**: High -- this is the real fix for the pass-2 recalibration problem; the prior memory
work was treating a symptom of the coarse whole-pool misunderstanding. Supersedes and replaces the
abandoned `completed/TODO-20260719_osprey_transfer_mdiag_resume_streaming.md` (PR #4437, closed unmerged).
**Origin**: Brendan, reasserting the invariant agreed in the original transfer-implementation session
(#4410) that the implementation did NOT actually honor.

## The invariant (first-class design rule)
**Pass-2 reconciliation can change ONLY the per-run q of non-best runs; the experiment q is a pass-1
property carried through UNCHANGED.** Justification (Brendan, best-peak-anchor argument):
- The experiment q is defined by the BEST peak across all runs.
- Reconciliation only ever ADJUSTS the *worse* runs -- moving each to a lower-scoring peak that is
  more credible because it sits at the consensus RT of the best run.
- No adjustment can raise a run above the best run it is anchored to. So the best run's observation
  is untouched, and since experiment q = best-of-runs, re-taking the min over the updated per-run q's
  returns the SAME value. **Experiment q is therefore frozen by construction, not by fiat** -- the
  reconciliation operator is bounded above by the anchor.
- The only thing that can move is a NON-best run's per-run q, and it can only move DOWN (toward higher
  q), as the peak is pulled from a spurious high position to the correct lower one.

## What the current implementation gets wrong
- **remodel** (default `percolator` 2nd pass): retrains Percolator and recomputes a target/decoy null
  on the decoy-DEPLETED reported pool -> re-derives experiment q -> anti-conservative (the FDR
  inflation: 0.90% -> 1.47-1.57%; see `completed/TODO-20260710_osprey_pass2_recalibration_fix.md`).
- **transfer** (`OSPREY_PASS2_QVALUE=transfer`): `Pass2FdrSidecar.TransferQWithTable` flattens ALL
  FOUR slots (precursor/peptide x run/experiment) to one value from a global full-population score->q
  table -- it OVERWRITES the experiment slot with the adjusted peak's own worse-run q. Same root
  error inverted: a peptide well-identified via its best run gets demoted and dropped -> conservative,
  loses IDs (the r=0.5 A/B: 31,586 vs percolator's 64,995 at inflated q). Both violate the invariant.

## Implications (why this collapses the design)
1. **No full-population, experiment-scope score->q table is needed at all.** Experiment q is carried
   verbatim from pass 1. Pass 2 only (re)assigns per-run q for the ADJUSTED minority -- a per-run,
   streaming computation over that run's peaks. (This is why PR #4437's 5.5 GB accumulator and the old
   ~178 GB resident pool were both rebuilding something that, by the invariant, cannot change.)
2. **transfer and remodel converge; Stage-5 / PerFileScoring becomes identical between them.** Both
   carry experiment q from pass 1 and only recompute per-run q for adjusted peaks; they differ solely
   in the tiny per-run-q step (transfer: map the adjusted score through the frozen per-run curve;
   remodel: refit one). No mode-specific resident pool or table build -> `NeedsResidentPool` /
   `needsResidentFirstPassPool` no longer branch on the pass-2 mode.
3. **Fixes both failure modes at once** -- remodel's inflation and coarse-transfer's ID loss share the
   one root (re-deriving experiment q). Matches the recalibration-fix TODO's Design 1 ("keep unchanged
   survivors' Pass-1 q; transfer only gap-filled/moved peaks") and oracle cell E (carry the full
   1st-pass null -> 0.86%), now with a crisp reason.

## Plan (sketch -- flesh out on start)
- Make experiment q (precursor + peptide) at the reported set a pass-1 carry-through: the survivor's
  best-run pass-1 experiment q, never recomputed at pass 2.
- Recompute ONLY per-run q for entries the reconciliation adjusted (the `Features != null` rescored
  set), from that run's calibration; monotone-bounded by the anchor.
- Collapse the transfer/remodel gates so PerFileScoring/Stage-5 is mode-independent.
- Validate against the entrapment FDP oracle (must keep calibration AND recover the coarse transfer's
  lost IDs) + `regression.ps1` (default path). The A/B is percolator-vs-new-transfer vs the old coarse.

## Salvage / deferred from the abandoned PR #4437 (branch `Skyline/work/20260719_osprey_transfer_streaming`)
- **mdiag-on-resume streaming** (was Lever 2): an INDEPENDENT OOM fix -- `--model-diagnostics` on a
  resume (`FirstJoin.Rehydrate`) forced the resident pool for the batch report; the fix streams the
  1st-pass sidecar + parquet into `ModelDiagnosticsData.Accumulator`. Re-land as its own small PR
  ONLY if a `--model-diagnostics` full-resume OOM is actually hit. **First verify the open HIGH
  self-review finding**: does a lean straight-through resume that lands in `FirstJoin.Rehydrate`
  produce non-empty, byte-identical `CompactedEntries` (my trace suggested the bundle-path compaction
  + MergeNode reconstruct from disk, but it was never run end-to-end). Code is preserved in the
  #4437 branch history to cherry-pick.

## References
- `completed/TODO-20260710_osprey_pass2_recalibration_fix.md` (the problem + Design 1 + oracle E).
- `completed/TODO-20260719_osprey_transfer_mdiag_resume_streaming.md` (the abandoned memory work).
- `ai/.tmp/pass2ab-20file-results.md` (coarse transfer conservative / loses IDs).
- `[[project_osprey_pass2_recalibration_inflates_fdr]]`, `[[project_skyline_mprophet_modernization]]`.
