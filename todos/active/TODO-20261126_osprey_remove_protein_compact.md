# TODO-20261126_osprey_remove_protein_compact.md

Remove the protein-compact second pass from Osprey

## Branch Information
- **Branch**: `Skyline/work/20261126_osprey_remove_protein_compact`
- **Base**: `master`
- **Created**: 2026-11-26
- **Status**: In Progress - code and docs removed (5230a7472e, b26d2a7871, pushed); unit gate and the
  Stellar regression pass; `regression-parallel.ps1 -Dataset All` running (2026-11-26). Then /code-review,
  PR, TeamCity. Protein-best validation is MACS2's work, not this PR's.
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

## Progress (2026-11-26)

5230a7472e (code, tests, resources, help pages) and b26d2a7871 (docs): 65 files, +489 / -5,818 against
master. Largest: `Pass2FdrSidecar.cs` -1,280, `StreamingFdr.cs` -947, `FdrTest.cs` -842,
`Pass2CompetitionDecoys.cs` deleted.
- Unit gate: 669/669 (was 681; 12 tests covered only the removed competition), inspection clean. Log
  `ai/.tmp/sessions/20261125-diag/pc-test2.log`.
- `regression.ps1 -Dataset Stellar`: 5 of 5 legs pass against the committed goldens, 497.5 s. Log
  `ai/.tmp/sessions/20261125-diag/pc-regression-stellar-20261126b.log`.
- `-Dataset All` (the only run that checks the three `diagnostics.tsv` goldens): log
  `ai/.tmp/sessions/20261125-diag/pc-regression-all-20261126.log`.

Decisions made while removing:
- `--protein-boost compact` is an invalid argument value; `OSPREY_PASS2_QVALUE=protein-compact` is an
  unrecognized-value startup error. `OSPREY_PASS2_QVALUE` stays with `transfer` as its only value: the
  `ai/scripts` runners set it from `-Pass2Mode`, and `;pass2=transfer` is in the validity keys.
- Validity keys are byte-identical: the removed `;pass2strata=2` term was empty under transfer.
- The four stratum fields of the co-assignment report data (`ExperimentCutoffInStratum`,
  `ExperimentCutoffOffStratum`, `AcceptedInStratum`, `AcceptedOffStratum`) stay at their transfer values
  (NaN, NaN, 0, 0): they are serialized today and pinned in all three `diagnostics.tsv` goldens.
  **Open for Brendan**: drop them here (re-records four lines per pass in each golden) or later.
- Retained decoys, decoy consensus and `FilePlanner`'s `reconcileDecoys` parameter are untouched; the
  caller now passes `false`, its value under transfer. They change the reconciled stub's rows, so they go
  with the stub PR.
- Also removed, unread once the competition is gone: the `FirstPassPercolatorModel` byproduct,
  `EnsureFrozenFirstPassPublished`, `Pass1ScalarSeeder`, `FdrScoresSidecar.ReadScalars`, 30 resource strings.
- `SecondPassFDR` no longer reads gap-fill entry ids from `<stem>.reconciliation.json` (only the
  competition fold used them); it still requires the file's stamp and declares it an input.
- Kept: the transfer path that scores with an analysis-wide frozen model (`TransferOneFile`,
  `FirstPassModelIO.LoadForAnalysis` / `Save`, ...). No production caller since #5070, but not
  protein-compact code; `ModelViewFromArtifacts` still calls `LoadForAnalysis` until the per-run Model tab.

Follow-ups outside this PR:
- `ai/scripts` runners still offer `-Pass2Mode protein-compact` (`OspreyDatasetRun.psm1`, `Run-SeaAd.ps1`,
  `Run-Chs.ps1`, `Run-CohortArms.ps1`); those arms have failed at startup since #5070.
- The diagnostics branch changes adjacent rows of the help pages and `docs/20-command-line.md`: expect a
  conflict, and regenerate the help pages by running the tests after merging.
- `docs/12` and `DIVERGENCES.md` say the C# port has no protein-compact; the Rust tree was not checked.

## Justification

The concern to answer: a feature added to the model can let it learn target from decoy without adding
detection value, and protein-best could be such a feature.

**Order of events, for the PR text.**
- Protein-compact was Osprey's first use of protein information, the kind of boost DIA-NN and Spectronaut
  apply.
- Classical FDRBench accounting (entrapment on its own proteins) cannot see what such a boost does to FDP,
  so a way to measure it was built BEFORE an alternative that also lets the model use protein information:
  the protein-shuffled audit (#4993's `docs/protein-shuffled-entrapment.md`) and the #5011 split came
  first, and protein-best (#4580) was built against them.
- #4993 lowered detection counts, single-peptide proteins most of all (2,114 -> 927 groups on one SEA-AD
  file under GBDT). It merged once #4950 showed another way to close the detection gap with DIA-NN.
- #4993 did not strengthen the boost: it made the complement compete against its own decoys, so the
  own-protein half fell (73 -> 11 hits, Arabidopsis split, 3 files) while the on-target half barely moved
  (219 -> 184). Quote the two halves separately; their ratio mixes boosting detected proteins with
  suppressing the rest.

Two separate claims, with different strength of evidence.

**A. Protein-compact reports more false discoveries than its q-values claim. Well supported.**
Sources: TODO-20260727_osprey_pass2_fdr_default (P2D), TODO-20260804_osprey_pass2_ab_and_library_production
(AB), TODO-20261028_osprey_diann_fdr_gap (DG), TODO-20261030_osprey_scoring_library (SL) and its -phase1/-phase2,
TODO-20261106_carafe_entrapment_in_target_proteins (CE).
- At a reported q of 1%, true FDP read 1.51% (82 SEA-AD files, July, P2D), 1.16% against 0.77% for the
  transfer with the same pass 1 (82 files, August, AB), 1.29% on the on-target split (82 files, November,
  SL:383; q 2% reads 2.55%, q 5% reads 6.26%), 1.29% on ZT Scan against 0.98% (DG:698), 1.29-1.59% on
  Astral HeLa with natural Arabidopsis entrapment against ~1.03% (DG:243).
- Which of those can see a protein boost (Brendan, 2026-11-26: without entrapment on target proteins the
  number is understated even when it is above 1%):
  - Entrapment on its own proteins, so UNDERSTATED: the July 1.51% and the August 1.16% (SEA-AD
    libdecoy r1.0, before the #5011 split existed).
  - Entrapment on target proteins: the November 1.29% (size-weighted split, on-target half); 3 SEA-AD files
    on the same split 1.30-1.55% (SL:142-153); ZT Scan 1.29% and 1.48% (library re-filed so entrapment
    shares its targets' proteins, DG:692); Astral HeLa 1.29-1.59% (natural Arabidopsis filed under the
    targets' proteins, DG:243); natural Arabidopsis split on-target half 1.09-1.16% at 1 and 3 files, 1.29%
    before #4993 (CE:72-116).
- Standard entrapment sits on its own proteins, which the stratum never admits
  (P2D:292). A protein-shuffle audit moved entrapment on detected proteins from 37 to 291 at q 1%
  (SL-phase1:215).
- Cause: the stratum takes ~87% of high-scoring targets and ~15% of high-scoring decoys (SL-phase2:39).
  #4993 fixed the complement; the in-stratum excess stayed (1.4% SVM, 1.9% GBDT on the shuffled library).
  In short, targets and decoys are not treated consistently, so the FDR is not controlled (DG:707).
- Its 3-file results looked calibrated (0.90% / 0.77%, P2D); the error grows with run count.

This claim alone justifies the removal: if protein-best failed that test, the fallback would be
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
   direct test of the concern: a column that only teaches target from decoy keeps its gain when the
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

Gaps 2-6 are about protein-best and do not bear on removing protein-compact.

**Not run here (Brendan, 2026-11-26)**: MACS2 is testing protein-best beside DIA-NN on SEA-AD and TDP-43,
focused on the validity and effect of protein boosting. The gaps above belong to that work; this PR
runs no control arms and cites its results when they exist.
