# TODO-osprey_confidence_axes_overlap.md -- Reproducibility frontier vs protein-compact: do the two confidence axes overlap?

## Status
**Backlog / not started.** Design spec ready; needs a night-session-scale run. No branch yet.
Grew out of the PR #4446 / maccoss/osprey#57 review discussion with Brendan (2026-07-23).

## The question
Osprey now has (or is prototyping) **two orthogonal-looking priors** that increase detection
confidence beyond a per-precursor q threshold:

1. **Cross-sample reproducibility** -- the iso-FDR "frontier" (PR #4428, merged): hold
   entrapment-measured FDP at target, float the q-cutoff up as the required run-count rises.
   Peak at **K>=3 runs**; on SEA-AD 82-file Astral it accepts **45,129 @ 1.0% FDP** vs the
   experiment-wide-q standard's **37,174 @ 0.84%** (~+18% at matched FDP). "Reproducibility, not
   the q statistic, is the dominant selector" (per-run vs exp-wide optimal sets ~94% identical).
   Currently a **1st-pass diagnostic**, NOT a reporting rule -- and decoy-anti-conservative
   (decoy-picked 1% -> entrapment truth ~1.24% exp-wide / ~1.89% per-run), so not yet shippable.
2. **Protein context** -- `OSPREY_PASS2_QVALUE=protein-compact` (PR #4446 / osprey#57): admit
   peptides of proteins detected in the 1st pass by >=2 distinct peptides, reconcile + rescore +
   report them under a stratum-constrained target-decoy competition (paired decoys kept). A
   **reporting mode**, decoy-calibrated + entrapment-validated (0.75% Stellar / 0.80% Astral).

Do they rescue the SAME peptides or DIFFERENT ones? Prediction: a correlated easy core (peptides
that are both reproducible AND from strong proteins) plus real orthogonal wings --
protein-compact-unique = strong-protein peptides seen in only 1-2 runs (frontier fails K>=3;
frontier is not single-run-capable); frontier-unique = reproducible peptides of orphan / single-hit
proteins (protein-compact excludes them by the >=2-peptide rule).

## Why it matters
- If largely **orthogonal**, the two priors are complementary -> a future combined prior is a bigger
  honest gain than either alone, and both axes should stay modular (don't bake one in as "the" rule).
- If **highly overlapping**, one may subsume the other and the choice is which is better-calibrated.
- Directly informs the pass-2 default-flip decision: protein-compact is defaultable NOW
  (decoy-calibrated); the reproducibility frontier waits on solving its decoy calibration.

## Experiment (all inputs already exist)
Dataset: SEA-AD Pilot-MTG 82-file Astral-DIA, the run where the frontier was validated:
`D:\test\Pilot-MTG-Tissue-May2026\runs\pass2ab-82file-...` (1st-pass sidecars + parquet
protein_ids for the entrapment class + `lib\...\osprey_library_db_pairing.tsv`). See
[[project_sead_pilot_mtg_dataset]].

1. **Baseline** set: standard experiment-wide q <= 1% reported peptides.
2. **Frontier-add** set: peptides admitted at the frontier peak (K>=3, loosest Q*) from the
   un-gated 1st-pass joint (per-run q x run-count) distribution the frontier already computes.
3. **Protein-compact-add** set: a full 82-file `OSPREY_PASS2_QVALUE=protein-compact` run's reported
   set minus the baseline. (Needs the #4446 build; watch memory -- 82-file mdiag OOMs the 64GB box,
   use no-mdiag + fdrbench per [[project_osprey_pass2_per_run_qvalue]].)
4. **Venn** (2) vs (3); characterize the uniques by (n-runs-detected, protein peptide count, SVM
   score distribution).
5. **The real test:** entrapment-oracle FDP of the **union** of (2)+(3) -- does stacking the two
   priors still control FDP, or do they double-count? Also each unique subset's FDP.

## Deliverable
A short findings note (+ maybe a diagnostics card) quantifying overlap, the character of each axis's
uniques, and whether the union is honestly FDP-controlled. Feeds the "combine the axes" decision and
the journal/MCP reproducibility-standard discussion.

## References
- [[project_osprey_pass2_default_flip_and_confidence_axes]] (the umbrella direction)
- `completed/TODO-20260716_osprey_diag_reproducibility_frontier.md` (frontier method + numbers)
- `project_osprey_pass2_per_run_qvalue`, `project_osprey_libdecoy_vs_gendecoy_calibration`
  (decoys anti-conservative -- consistent with the frontier decoy finding).
