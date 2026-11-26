# TODO-20261126_osprey_remove_protein_compact.md

Remove the protein-compact second pass from Osprey

## Branch Information
- **Branch**: `Skyline/work/20261126_osprey_remove_protein_compact`
- **Base**: `master`
- **Created**: 2026-11-26
- **Status**: In Progress - branch created in `C:\proj\pwiz` from 1134bd96e9; justification drafted below;
  no code removed yet. Two control runs proposed to Brendan (see "Gaps worth closing").
- **Module**: `osprey`
- **PR**: (pending)

Split out of [TODO-20261125_osprey_diagnostics_after_per_run_models.md](TODO-20261125_osprey_diagnostics_after_per_run_models.md)
(Brendan, 2026-11-25): its own PR, ahead of the smaller stub. Removing the mode also removes the reasons
decoys are retained past the first pass, which is what lets the stub drop peak columns for most rows.

## What is removed

`OSPREY_PASS2_QVALUE=protein-compact` and `--protein-boost compact`. Unreachable since #5070 (aa864c3d2e):
`PerFileScoringTask` refuses the mode before any run is scored, because it competes every survivor under
one first-pass model for the analysis and each run now trains its own
(`PerFileRescoreTask.OwnModelsProteinCompactMessage`); `--protein-boost compact` already behaves as `off`.
So the PR changes no result: every golden must stay byte-identical.

Footprint (grep on master, about 60 files): the stratum (`ProteinCompactStratum`,
`BuildProteinCompactStratum`, `<blib-stem>.1st-pass.stratum.json` in `FirstPassModelIO`), the stratum clause
in `ComputeFirstPassBaseIds`, the stratified competition (`StreamingFdr`, `PercolatorQValues`),
`Pass2CompetitionDecoys` and `<stem>.2nd-pass.fdr_decoys.bin`, the frozen-competition paths of
`Pass2FdrSidecar` / `Pass2PerFileWorker`, the split acceptance boundary in
`ModelDiagnosticsData.CoAssignment`, `reconcileDecoys` and decoy consensus (transfer never moves a decoy),
validity-key terms (`Pass2StrataValidityKeySuffix`), tests (`FdrTest`, `FirstPassModelIoTest`,
`ModelDiagnosticsDataTest`, `TaskValidityKeyTest`, the `protein-compact-refused` leg of `SubsetPipelineTest`),
resources, and docs 00, 07, 12, 14, 20, `protein-shuffled-entrapment.md`, `Osprey-workflow.html`.

To decide while removing: whether `--protein-boost compact` becomes a usage error or stays as a refused
value for one release; whether retained decoys go in this PR or the stub PR (they change the reconciled
stub's rows, so not byte-identical: likely the stub PR).

## Justification (for Mike)

Mike's warning (via Brendan, 2026-11-25): he and Bill Noble have seen introduced features let the model
learn target from decoy without adding detection value; protein-best could be one.

Two separate claims, with different strength of evidence.

**A. Protein-compact reports more false discoveries than its q-values claim. Well supported.**
Sources: TODO-20260727_osprey_pass2_fdr_default (P2D), TODO-20260804_osprey_pass2_ab_and_library_production
(AB), TODO-20261028_osprey_diann_fdr_gap (DG), TODO-20261030_osprey_scoring_library (SL) and its -phase1/-phase2,
TODO-20261106_carafe_entrapment_in_target_proteins (CE).
- At a reported q of 1%, true FDP read 1.51% (82 SEA-AD files, July, P2D), 1.16% against 0.77% for the
  transfer with the same pass 1 (82 files, August, AB), 1.29% on the on-target split (82 files, November,
  SL:383; q 2% reads 2.55%, q 5% reads 6.26%), 1.29% on ZT Scan against 0.98% (DG:698), 1.29-1.59% on
  Astral HeLa with natural Arabidopsis entrapment against ~1.03% (DG:243).
- Those are lower bounds: standard entrapment sits on its own proteins, which the stratum never admits
  (P2D:292). A protein-shuffle audit moved entrapment on detected proteins from 37 to 291 at q 1%
  (SL-phase1:215).
- Cause: the stratum takes ~87% of high-scoring targets and ~15% of high-scoring decoys (SL-phase2:39).
  #4993 fixed the complement; the in-stratum excess stayed (1.4% SVM, 1.9% GBDT on the shuffled library).
  Mike's own summary: "the targets and decoys are not treated consistently, which is why it is not
  controlled" (DG:707).
- Its 3-file results looked calibrated (0.90% / 0.77%, P2D); the error grows with run count.

This claim alone justifies the removal: if protein-best failed Mike's test, the fallback would be
`--protein-boost off` (the transfer alone), not protein-compact.

**B. Protein-best does not have that defect. Supported by one kind of audit on one cohort.**
- Design: a candidate reads the best first-round score of the OTHER peptides of its protein; a decoy reads
  exactly its paired target's value. The column is identical within a target/decoy pair, so it cannot
  separate a target from its own decoy (code reading, SL:207).
- Audit that can see it: the #5011 split, where half the entrapment peptides are filed under target
  proteins. On-target FDP at q 1% with protein-best: 0.91-1.03% at 3 files, 0.91-1.03% at 20 (five seeds),
  1.02% at 62, 0.93-0.99% at 82 (SL:142-190, 448; TODO-20261110_osprey_feature_set:244-255, 665-678;
  TODO-20261121_osprey_per_file_fdr:82-92). Same split, protein-compact: 1.29-1.55%.
- Detection value at matched on-target FDP 1%: +6.6% precursors at 3 files, +9.7% at 62, about +7% at 82.
- Together they double count: protein-best with protein-compact read 1.47% at q 1% (SL:142), which is why
  the pair was already refused.

## Gaps a skeptical reader would raise

1. **The negative control has no number on record.** `OSPREY_PROTEIN_BEST_SHUFFLE` (accessions permuted
   among peptides) is recorded only as "shuffle control flat" (SL:129): no dataset, ids or FDP. This is the
   direct test of Mike's concern: a column that only teaches target from decoy keeps its gain when the
   protein membership is scrambled; a column carrying protein evidence loses it.
2. **Every on-target audit of protein-best used shuffle (anagram) entrapment on SEA-AD Astral.** Natural
   Arabidopsis split libraries exist (SL:74) and were searched only with protein-compact (CE:72-116).
3. **No valid audit at unit resolution**, where protein-best is now the default: the Stellar numbers are
   own-protein entrapment, which under-reads any protein boost (TODO-20261121_osprey_per_file_fdr:594-600).
   `docs/20-command-line.md` still says compact "will be removed once Stellar data is measured on a larger
   cohort"; that measurement is not on record.
4. Entrapment cannot see a wrong peak for a peptide that is present (AB:104); no independent confirmation
   (two-organism sample, DIA-NN overlap at matched FDP) that the added identifications are real.
5. No peptide- or protein-level entrapment FDP for protein-best.
6. Unexplained: pass 1 differs between the 1:1 split and unsplit Arabidopsis libraries (34,682 vs 33,978
   targets at q 1%, CE:119), though pass 1 then carried no protein information.

Gaps 2-6 are about protein-best and do not bear on removing protein-compact. Gap 1 and gap 2 are cheap:

## Gaps worth closing (proposed, not started)

- 3 SEA-AD files, #5011 size-weighted split library: `--protein-boost off`, `best`, and `best` with
  `OSPREY_PROTEIN_BEST_SHUFFLE=1`; precursors at q 1% and at on-target FDP 1%, on-target and own-half FDP.
- The same three arms on the natural Arabidopsis 1:1 split library (3 files).
