# TODO-osprey_pass2_recalibration_fix.md -- Stop pass-2 from re-computing FDR on a decoy-depleted null; decouple from --protein-fdr

## Status
Backlog (brendanx67). Not started as a shippable PR. Experimental instruments
VALIDATED and preserved on branch `Skyline/work/20260704_osprey_pass2_recalibration`
(env-gated, off by default). Grew out of the PR #4353 investigation once the
entrapment oracle overturned that PR's premise (see
[[project_osprey_pass2_recalibration_inflates_fdr]]). Full night write-up:
`ai/.tmp/handoff-20260703-morning.md`; oracle finding: `ai/.tmp/pr2-oracle-finding.md`.

## The problem (measured, not theorized)
The 2nd-pass Percolator runs ONLY when `--protein-fdr` is set (gated at
`MergeNodeTask.cs:127`). It does TWO things:
1. **Re-scores** on reconciled features -- a genuinely better ranking (+~390-690
   real IDs at matched true FDP).
2. **Re-computes q** on the compacted, decoy-DEPLETED null -- anti-conservative.

Compaction keeps only the passing base_ids; a decoy survives only if its PAIRED
TARGET passed, so the 2nd-pass retrains and computes q on a target-selected,
shrunken null and radically underestimates q. This is Brendan's long-standing
a6be3789 concern ("reduce the decoy population to an unusable size / paired
selection by matching ID") made concrete. See
[[project_osprey_hpc_worker_compaction_global_coupling]].

### The numbers (Stellar 3-file libdecoy, precursor, --fragment-tolerance 0.4, one hash-stamped binary)
| variant | reported FDP @1% q | disc @ TRUE 1% FDP | note |
|---|---|---|---|
| A  no --protein-fdr                              | 0.92% | 27,292 | 1st-pass q, no 2nd-pass Percolator |
| B  --protein-fdr (retrain, ship today)           | **1.57%** | **27,682** | anti-conservative q; best ranking |
| C  --protein-fdr + OSPREY_PASS2_NO_RECALIBRATE   | 0.92% | 27,292 | == A exactly (skip recalibration) |
| D  TRANSFER_Q, compacted-null table              | 1.56% | 27,496 | transfer but wrong (depleted) null table -> still bad |
| E  TRANSFER_Q, FULL 1st-pass-null table          | **0.86%** | 27,496 | transfer + full null -> CALIBRATED |
Ground truth = FDRBench entrapment. "disc @ true 1% FDP" is the honest yardstick.

## Decision / direction (Brendan)
Two coupled asks:
1. **The 2nd-pass recalibration must not be tied to `--protein-fdr`.** Whether pass 2
   re-runs Percolator (or how it computes q) is an FDR-calibration decision, orthogonal
   to protein-FDR reporting. Make it an explicit switch, **off by default** (default =
   do NOT recompute q on the depleted null).
2. **The default must be calibrated.** Either skip the recomputation (keep 1st-pass q)
   or transfer/compute q against the FULL 1st-pass null -- never the depleted one.

The science question (which variant becomes the non-default option) is Brendan+Mike's,
and Osprey is now the platform to A/B it rigorously (the 2016 Horowitz-Gelb aim).

## Work
1. **Decouple the switch from `--protein-fdr`.** Add an explicit pass-2 FDR mode
   (e.g. `--pass2-fdr {keep1st|transfer|retrain}` or an env->flag promotion), default
   to the calibrated behavior. `--protein-fdr` reverts to reporting-only (already true
   after #4353's rescue removal).
2. **Land the calibrated default.** Minimum: variant (iii)+full-null [cell E, VALIDATED
   0.86%] -- frozen 1st-pass model on reconciled features + a full-1st-pass-null
   score->q table. Simpler/conservative; recovers only the reconciliation peak-move
   ranking gain.
3. **Prototype + measure variant (vii)** [OSPREY_PASS2_RETRAIN_FULLNULL, best, UNTESTED]:
   keep the 2nd-pass RETRAIN (full score gain) but compute its q against a NON-depleted
   null -- retain decoys in the 2nd-pass FDR null even when their target failed. Target:
   ~27,682 disc @ true 1% at ~1% calibrated. Obstacle: the 2nd-pass model was trained on
   reconciled features that exist only for the compacted set -> scoring full/non-reconciled
   decoys is a feature mismatch; cleanest is to run the q-computation over targets+decoys
   WITHOUT the compaction decoy-drop.
4. **Cross-impl parity.** Mirror the shipped variant in Rust (`pipeline.rs` ~5270) and
   gate with `Compare-EndToEnd-Crossimpl.ps1` (Stellar + Astral). Keep the C#==Rust signal
   alive until Mike breaks parity ([[project_osprey_sidebyside_preservation]]).
5. **Generalize check on Astral** (post-PR4347 Astral pass2 was 0.87%).

## Gotchas (paid for already; do not re-discover)
- **Scale subtlety:** the stored 1st-pass `Score` is per-fold affine-recalibrated
  (`CalibrateScoresBetweenFolds`), a different scale than the raw averaged-model decision
  value. Any score-based transfer must build BOTH the table and the transfer scores on the
  SAME raw model scale.
- **Isotonic score->q envelope needs robust regression:** naive running-min/max collapses
  (one outlier -> constant q). Use quantile bins + per-bin mean q + pool-adjacent-violators.
- **The full-null is the crux:** a score->q table built from compacted (passing-only,
  all-low-q) entries does NOT calibrate (D=1.56%). Must carry the FULL 1st-pass score->q
  (including the failing/high-q region) to Stage 7 (E=0.86%).

## Experimental instruments (preserved, off by default)
Branch `Skyline/work/20260704_osprey_pass2_recalibration`:
- `OSPREY_PASS2_NO_RECALIBRATE` -> cell C (skip 2nd-pass recompute, keep 1st-pass q).
- `OSPREY_PASS2_TRANSFER_Q` -> cell E (frozen-model transfer + full-1st-pass-null table).
- `OSPREY_PASS2_RETRAIN_FULLNULL` -> variant (vii) scaffold.
Touches: `OspreyEnvironment.cs`, `PercolatorEngine.cs` (captureModel hook), `FirstJoinTask.cs`
(publishes FirstPassPercolatorModel + FirstPassScoreQTable byproducts), `Pass2FdrSidecar.cs`
(transfer path + isotonic BuildScoreToQTable), `PipelineByproducts.cs`.

## Gates (judge on the entrapment oracle, one hash-stamped binary)
- `Run-FdrBench.ps1` combined/paired FDP curve per variant; A/B/C/D/E harness in the handoff.
- `regression.ps1 -Dataset Stellar` (then All) -- output change is expected; re-capture golden
  only after the diff is confirmed to be exactly the pass-2 q change.
- `Build-Osprey.ps1 -RunTests -RunInspection` clean; `Test-PerfGate.ps1` no regression.

## References
- `MergeNodeTask.cs` (2nd-pass Percolator gate, ~:127), Rust `pipeline.rs` ~5270.
- Memories: [[project_osprey_pass2_recalibration_inflates_fdr]],
  [[project_osprey_hpc_worker_compaction_global_coupling]],
  [[project_osprey_libdecoy_vs_gendecoy_calibration]].
- Handoffs: `ai/.tmp/handoff-20260703-morning.md`, `ai/.tmp/pr2-oracle-finding.md`.
