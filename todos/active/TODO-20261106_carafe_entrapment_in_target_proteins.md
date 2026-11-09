# TODO-20261106_carafe_entrapment_in_target_proteins.md

## Branch Information
- **Branch**: `Skyline/work/20261106_carafe_split_entrapment`
- **Base**: `master` (ab7c6b21a7)
- **Created**: 2026-11-06
- **Status**: In Review (PR #5011 opened 2026-11-06 22:30 by the night session)
- **Module**: `osprey`
- **PR**: [#5011](https://github.com/ProteoWizard/pwiz/pull/5011)
- **Checkout**: `C:\proj\pwiz`

## Idea (Brendan, 2026-11-05)
Make a low-ratio entrapment arm (e.g. 10%) something every Osprey run can carry, by building it in CarafeSharp,
which already generates entrapment libraries at a chosen percentage and from a foreign-species FASTA.

The new option: assign each entrapment peptide to a random target protein (its decoy follows its paired target),
instead of keeping it on its own entrapment protein. This is the design of the protein-shuffled entrapment audit
(`pwiz_tools/Osprey/docs/protein-shuffled-entrapment.md`, `ai/scripts/Osprey/Library/Build-ProteinShuffledEntrapment.py`),
which found that a protein-aware stage boosts targets on detected proteins while entrapment on its own proteins never
gets that boost, so the standard design cannot see protein-aware inflation (37 -> 291 entrapment hits on detected
target proteins at q 1% under pass-2 protein-compact).

## Refinement (Brendan, 2026-11-06, mid-session)
Two independent ratios, not a fraction of one set: the standard entrapment ratio (10% as normal, on its own
entrapment proteins) plus a second ratio of entrapment placed in target proteins (10%, "protein enhancement rate
estimation"), 20% in total - rather than today's only option of 100% matching entrapment with no visibility into
protein enhancement. Exposed in Skyline (Osprey Search and Build Library > Carafe) and as Osprey command-line
parameters; a /feature-demo of both.

## Design points
- Split the entrapment: about half scattered into target proteins (audits precursor q after any protein-aware boost),
  about half on entrapment-only proteins (keeps a protein-group FDP). One library audits both levels.
- Foreign-species peptides, each with its own predicted RT and spectrum, rather than shuffles: a shuffle is an
  anagram of its target, shares fragment masses and over-identifies (~1.6x FDP overestimate vs ~1.1x for natural
  entrapment; ai/docs/osprey-library-generation-guide.md).
- Entrapment runs through every stage, including protein inference, and is stripped only at output, so the audited
  run is the reported run.
- Cost: ~10% more candidates at 10%. Precision: at FDP 0.5% and ~57k IDs a 10% arm expects ~26 entrapment hits
  (about +/-20% on one run) - enough to flag miscalibration at q 1%, not to rank small changes.

## Implementation (this branch)
- **Marking.** Entrapment on a target protein carries the protein's clean accession, so the `_p_target` accession
  substring can no longer be the only mark. `LibraryEntry.IsEntrapment` is set from the manifest's `peptide_type`
  (`DecoyPairingManifest.ApplyToLibrary`) and from the blib `DecoyPairs.IsEntrapment` (`BlibDecoyPairs.MarkEntrapment`);
  `EntrapmentLibraryClassifier.IsEntrapment(LibraryEntry)` = flag or marker, `IsOnEntrapmentProtein` = marker only.
- **CarafeSharp**: `EntrapmentFastaSettings.EntrapmentInTargetsRatio` (own seed 20261101, so existing builds are
  byte-identical), `EntrapmentQuartet.PTargetSources`, `--entrapment-in-targets <ratio>` on both command lines,
  `LibraryBuildConfig.EntrapmentInTargetsRatio` in Osprey.
- **Diagnostics**: `EntrapmentPlacement` (base-ids on target proteins + each half's ratio) threads into the FDP views;
  `FdpView` gains the accepted and expected entrapment counts (expected = q (n_t + n_p) r / (1 + r), read with a
  Poisson interval) and the two halves' combined FDP at their own ratios; `Pass2Data.ProteinEntrapment` is the
  protein-group combined FDP from the entrapment-only groups; two new cards in the report.
- **Output**: `--strip-entrapment` leaves entrapment precursors and entrapment-only protein groups out of the blib
  and the reports after FDRBench and the diagnostics have read them. Default off tonight (goldens and the subset
  test keep today's "entrapment reported as targets"); proposal: default on for the `--fasta --entrapment` route.

## First test (2026-11-06 night)
Libraries derived from `target+decoy+entrapment-arabidopsis` (1:1 foreign-species, Carafe-built) under
`D:\test\osprey-runs\sea-ad\lib\`: `-r0.2` (nested subset) and `-r0.2-split` (half of that entrapment, 10% of
targets, placed on random target proteins; `Build-ProteinShuffledEntrapment.py --in-targets 0.5`), plus `-r0.1`,
`-r0.1-split` and `-split` (1:1). A10_014 runs, exe snapshot `D:\test\osprey-runs\_bin\split-entrap-20261106`:
`runs\seaad-1files-libdecoy-r0.2-protein-compact-arab-split-*`, `...-r0.2-...-arab-*`, `...-r1.0-...-arab-*`.
Compare precursor FDP by placement (pass 1 = negative control, pass 2 protein-compact = the audit) and the
protein-group FDP against the 1:1 run.

## Open items
- Pass-1 protein FDR has no entrapment view yet (pass 2 only).
- `--task ModelDiagnostics` on a completed run re-renders the stored pass-2 product; the protein card is kept from
  the join arm but not rebuilt on the diagnostics-only fold arm.
- Default of `--strip-entrapment` for the one-command route.

## Results (2026-11-06 night, A10_014, Arabidopsis entrapment, exp-wide q 1%)
| library | pass | targets | entrapment on target proteins | on own proteins | combined |
|---|---|---|---|---|---|
| r0.2 split (10% + 10%) | 1 | 37,638 | 32 (FDP 0.97%) | 24 (0.73%) | 56 of 59.9 +/- 15.2 expected, 0.92% |
| r0.2 split | 2 protein-compact | 44,947 | 46 (1.16%) | 0 (0.00%) | 46 of 72.2 expected, 0.63% |
| r0.2 unsplit (20% own) | 1 | 37,638 | - | 56 | 0.92% (identical to split) |
| r0.2 unsplit | 2 | 45,473 | - | 2 | 0.03% |
| 1:1 split (48% + 48%) | 1 | 34,682 | 95 (0.84%) | 94 (0.83%) | 1.10% |
| 1:1 split | 2 | 41,979 | 149 (1.09%) | 0 | 0.72% |
| 1:1 unsplit | 1 | 33,978 | - | 181 | 1.08% |
| 1:1 unsplit | 2 | 43,614 | - | 0 (of 210.9 expected) | 0.00% |

- Pass 1 is the negative control: both halves agree and, at r0.2, the split and unsplit libraries are bit-identical.
- Pass 2 (protein-compact) accepts entrapment only on target proteins: the standard design reads it as FDP 0.03% (r0.2) or 0.00%
  (1:1); the in-target half reads 1.09-1.16% at a reported q of 1%, i.e. about calibrated on target proteins while the
  own-protein half is driven to zero. The plain combined estimate under-reads by about half.
- Before vs after PR #4993 (exe `D:\test\osprey-runs\_bin\before-4993`, #4993's code files reverted): identical counts on this file
  (split 46/0, control 2), as the doc's SVM rows predicted; the fix moved GBDT runs, not the default SVM.
- Run dirs: `D:\test\osprey-runs\sea-ad\runs\seaad-1files-libdecoy-r{0.2,1.0}-protein-compact-arab[-split][-before4993]-20261106_*`;
  reader `C:\proj\ai\.tmp\sessions\20261106-carafe-entrap\read-placement.py <run dir>`.
- Library repair: the Carafe-built Arabidopsis library has 82 rows merging a decoy with an identical target (loader refuses them in
  libdecoy mode); dropped from the manifests of every `-arabidopsis*` variant (`*.merged-rows.orig` beside each), scripts
  `drop-merged-rows*.py`, `find-merged-rows.py` in the session folder.

## Review (code-review medium, 2026-11-06)
Fixed: Build Library page offered the in-target field though a predicted .blib carries no proteins (field removed there);
stripped protein-group report rows (entrapment-only test, empty groups skipped); protein-entrapment sidecar stamped and checked;
cref typo; non-ASCII dash. Dropped: per-replicate protein count in stats.tsv keeps entrapment-only groups under --strip-entrapment
(opt-in, follow-up); strip after protein FDR is the design; `--entrapment --entrapment-in-targets 0.1` refused because the
entrapment ratio defaults to 1 (message could say so); the sidecar is written on every join (needed by the fold arm).

## 3-file result (2026-11-07, first three SEA-AD files, 1:1 Arabidopsis, exp-wide q 1%)
| library | pass | targets | on target proteins | on own proteins | combined |
|---|---|---|---|---|---|
| 1:1 split (48% + 48%) | 1 | 41,221 | 106 (0.79%) | 123 (0.92%) | 229 of 202 +/- 28 expected, 1.13% |
| 1:1 split | 2 protein-compact | 51,384 | 184 (1.10%) | 11 (0.07%) | 195 of 251 expected, 0.77% |
| 1:1 unsplit | 1 | 40,581 | - | 231 | 1.15% |
| 1:1 unsplit | 2 | 52,849 | - | 17 | 0.07% |
Protein groups at protein q 1%: split 5 entrapment-only of 4,626 (0.22%); unsplit 7 of 4,624 (0.30%).
Before #4993 (3 files, split): pass 2 51,851 targets, 219 on target proteins (1.29%), 73 own (0.43%), combined 1.14%;
entrapment-only groups 67 of 5,168 (2.57%). So at 3 files the complement fix removes the own-protein entrapment and the
entrapment-only groups the complement let through across runs (73 -> 11, 67 -> 5), which one file cannot show; the
in-target excess inside the stratum (219 -> 184, about the reported rate) remains.
Run dirs `runs\seaad-3files-libdecoy-r1.0-protein-compact-arab[-split][-before4993]-20261107_*`.

Related: the audit that inspired this (shuffle library, GBDT out-of-fold, 37 -> 291 entrapment on detected target
proteins; #4993's 134 -> 9 under GBDT) is recorded in `TODO-20261030_osprey_scoring_library.md` (2026-11-01 entry and
"#4993 merged"); that TODO's open item "make a protein-shuffled entrapment arm a standard FDRBench check" is what this
branch's placement split provides. With the default SVM first pass the complement fix moves nothing, as its SVM rows
said; the residual is the stratum's own excess.

Build Library > Carafe/Koina (2026-11-07): the predicted .blib now writes protein rows from the document's groups or the
FASTA accessions (CarafeSharp precursor table gained `protein_id`), the in-target field is back on that page, and the
Koina page takes the same information.

## Open questions
- At 1:1 the split and unsplit libraries differ in pass 1 (34,682 vs 33,978 targets at q 1%); at r0.2 they are identical.
  Pass 1 should carry no protein information - find what differs (derived .blib, feature set, training-set pick).
- Protein-group card: the expected count prints 0 because the group q grid near 1% is coarse; show the interval at the
  nearest threshold or on a fixed q grid.
- Feature demo: deck https://claude.ai/artifact/UWjptc8nhWU4zpFq51wLfy and wiki draft
  `C:\proj\ai\.tmp\sessions\20261106-entrap-demo\wiki\EntrapmentInTargetProteins.md`; the two Skyline dialog screenshots need
  the Screen Capture Permission consent in Skyline (launch the Debug Skyline-daily, click Allow, re-run the capture step).
- TestBuildLibraryCarafeWizard fails at line 304 (fine-tuned RT R2 = 0): the training export selects by pass-2 run q and two of the
  three Stellar subset runs end with 0 precursors at q 0.01 after ~115 each at pass 1 (TrainingExportWriter.ReadRunQ /
  PairTargets reading the 2nd-pass sidecar q under protein-compact strata, #4993); one test row, R2 defined 0. Same q-values as
  master by the regression goldens, so master's behavior; failing run kept at C:\proji\.tmp\OspreySearchTest-buildlib-failing-run.
- Protein-group card on master: every picked-protein q is 0 in these libdecoy runs (verified in the stored products: 350
  q points, all 0.0), so the card's q axis is one point and its curve is blank; the counts at "q <= 1%" are all groups.
  This is the defect Nick's PR #4823 fixes (decoys looked up by DECOY_ name, only detected proteins competing, scores
  from the compacted pass-2 pool). #4823 measured the same quantity offline (all-Arabidopsis groups, FDP = 2E/(T+E),
  6.66% on Astral 1:1 before, 0.82% after); this card reports it in the run. Re-measure #4823 on master after #4993:
  the complement fix already dropped the entrapment-only groups 67 -> 5 at 3 files (2.57% -> 0.22% by the card),
  so part of what #4823 measured as 6.66% may have been the complement's survivors.

## Stack result (2026-11-07, master + #4993 + #4823 + #5011, exe D:\test\osprey-runs\_bin\stack-4823-5011, 3 files, 1:1 Arabidopsis)
Precursor level identical to master + #4993 (#4823 does not touch precursor q): split pass 2 184 on target proteins
(1.10%) / 11 own (0.07%), unsplit 17 (0.07%); pass 1 unchanged.
Protein groups at protein q 1%: split 3,887 groups (was 4,626 = every group), 2 entrapment-only (0.10%; expected 19.1 +/- 8.6
under calibration); unsplit 3,870 groups, 0 entrapment-only (0.00%). The protein q axis is now real (distinct q values), so
the card reads: #4823 removes ~740 groups from the 1% set and the entrapment-only groups it keeps are below expectation,
i.e. conservative at the protein level on this cohort. Branch state: Nick's branch ff3ae1afd6 + 9153490876 (goldens),
#5011 head 5182ceabef, PR base = Skyline/work/20261011_osprey_protein_fdr. Observation from the merge: 1,783 of 117,660
accepted Astral precursors carry peptide q > 0.01 under #4823's one-winner-per-peptide competition (one at 1.0).
- Brendan (2026-11-07): the peptide q above 1% with precursor q below it under #4823 is correct multiple-hypothesis
  control, not a defect: every level competes best against best by base id (verified: StreamingFdr.CompetePeptides,
  PercolatorQValues.ComputeExperimentPeptideQMap, LibraryProteinScores), and accepting a peptide when any precursor
  passes would inflate the error rate the way "any peptide passes, so the protein passes" does. Blib consumers filter
  at the level they mean.
- Proposal (Brendan, 2026-11-07): choose the protein-compact stratum by a pass-1 protein q from the full-library
  picked-protein competition (#4823's machinery applied to pass 1), not by the >=2-distinct-detected-target-peptides
  count (FirstPassFdrTask.BuildProteinCompactStratum, target-conditioned, #4581) and never by a per-run q. Intent of
  protein-compact is to recover peptides of proteins already believed present, not to bolster the protein, which a
  max-score protein competition cannot do anyway. Test: 3-file split library, in-target half (184, 1.10%) should fall
  toward the own-protein half (11, 0.07%) with yield held.

## TestBuildLibraryCarafeWizard fix (2026-11-08, PR #5012, branch Skyline/work/20261108_osprey_training_export_q from master)
Bisected with the test: passes at abaf9155af, fails at ab7c6b21a7 (#4993). Cause: TrainingExportWriter selected rows by the
2nd-pass run q, which #4993 made stratified (stratum and complement each vs their own decoys with their own +1); on the
Stellar subset each half is under ~100 targets, so runs 20 and 22 exported 0 rows and run 21 only 102 -> one held-out row,
R2 defined 0. Fix: the export selects by the first-pass run q (the whole-run, undepleted null); run_q_pass footer "1";
wizard test bar 0.99 -> 0.9 (new split: 5 held-out peptides, pretrained 0.9153 -> fine-tuned 0.9598; reviewer's call).
Gates: Osprey 653/653 + zero inspections, Stellar and StellarGenDecoyEntrap PASS (no golden moved), Skyline wizard/search/
CodeInspection green. Must merge ahead of #4823 and #5011 (no merging with a known failure).

TeamCity (2026-11-07/08): #4823 Osprey Perf/Regression 4256392 SUCCESS; #4823 Windows 4256391 fails only RtR2 (above),
TestRInstaller (no r-project.org) and TestNativeMessageBox (flaky Save As lookup). #5011 Windows 4256406 at 745e31dcee fails
only RtR2; #5011 Osprey gate 4256393 green at 85%. #5012: Windows 4256410 and Osprey gate 4256411 queued.
TeamCity final (2026-11-08 03:1x): #5012 Windows 4256410 SUCCESS (TestBuildLibraryCarafeWizard passes), #5012 Osprey
Perf/Regression 4256411 SUCCESS; #5011 Osprey Perf/Regression 4256393 SUCCESS. Brendan accepted the 0.9 RT R2 bar.
Merge order: #5012 first, then master into #4823 and #5011 so their Windows builds lose the RtR2 failure.

### 2026-11-08 - #5012 merged
PR #5012 merged as e78e6b6433 (training export selects rows by the first-pass run q; TestBuildLibraryCarafeWizard fixed,
its RT R2 bar 0.9 accepted by Brendan). All TeamCity checks green on the re-runs (the first Core and Osprey .NET runs failed
only on an Inno Setup download, Docker on that dependency); GitHub's CodeQL csharp check failed on a bundle download 504 and
could not be re-run. Next: merge master into #4823 and #5011 so their Windows builds lose the RtR2 failure.

### 2026-11-08 - Handoff
Branch head 745e31dcee on #4823's branch; #5012 merged on master. Next: merge master into #4823, then #4823 into this branch,
re-trigger the Windows builds, review. Demo deck complete at https://claude.ai/artifact/UWjptc8nhWU4zpFq51wLfy.
**Next session handoff**: For detailed startup protocol, read `ai/.tmp/handoff-20261106_carafe_split_entrapment.md` before starting work.

### 2026-11-08 - Master merged through the stack
Merged origin/master (#5012, e78e6b6433) into Nick's branch (d40c3cf9a4, pushed) and Nick's branch into this one (e7cb10820b,
pushed). Both gates green: Osprey build, 656/656 tests, zero inspections on each branch; on this branch `regression.ps1
-Dataset Stellar` PASS (10 phases, 230 s) and `-Dataset StellarGenDecoyEntrap` PASS (12 phases, 363 s), no golden moved.
TeamCity did not queue a Windows build (bt209) on pull/4823 after the push; manual triggers on pull/4823 and pull/5011
need Brendan's okay. Copilot on #4823 (2026-10-11) was a quota refusal, not a review. Next: review #4823, then #5011.

### 2026-11-08 - Skyline code inspection on #5011
TeamCity bt209 4256438 (e7cb10820b, auto-queued on pull/5011 after the push) was SUCCESS on tests (RtR2 gone) but the
"Skyline code inspection" status failed with 2 InvalidXmlDocComment warnings at BuildLibraryCarafeWizardTest.cs(610): commit
188a853ab5 inserted the Accession helper between ShowAndDismissMessage's summary and its method. Fixed by moving the summary
back onto its method (7b00951ce1, pushed). Local `Build-Skyline.ps1 -RunInspection` no longer lists the file, but reports 432
issues in Shared projects it could not restore (NU1105 "unable to find project information" for CarafeSharp.*, BiblioSpec.IO;
318 in ProteowizardWrapper\MsDataFileImpl.cs) - environmental, TeamCity's inspection is the authority. bt209 did not auto-queue
on pull/4823 after the d40c3cf9a4 push (pull/5011 queued within a minute).

### 2026-11-08 - Review of #4823 (code-review medium, 9 findings, each verified against the code)
Raise with Nick (ordered by weight):
1. ProteinFdr.ComputeLibraryPickedProteinFdr: proteins that parsimony Step 3 dropped as proper subsets are in no group's
   Accessions (dropped, not merged), so `!grouped.Contains(acc)` makes each a unit of its own, scored on the same peptides as
   the retaining group - one peptide yields N+1 correlated winners. The doc says "each library protein in no group" meaning
   never-detected proteins. Calibration (0.82% vs DIA-NN 0.90%) says the net effect is small, but it is a design gap.
2. Same method: a group's score is the best first-pass score over every peptide of its accessions (LibraryProteinScores.ByProtein),
   so config.SharedPeptides (Razor/Unique) no longer affects which peptide a group may win on; pass 1 (ComputeProteinFdr via
   PeptideToGroupMap) still honours it. Design question, not a defect, but the two passes now disagree on the setting.
3. docs/DIVERGENCES.md INTENT rows say the peptide PEP and protein-group PEP are "written to the blib as RefSpectra.PeptidePep /
   Proteins.Pep". OspreyBlibWriter adds PrecursorQValue, PrecursorPep, PeptideQValue and the protein q only (#4848 defined the
   columns; the Osprey write is the follow-up the PR body names). Doc fix.
4. SecondPassFdrTask.ReadFirstPassProteinScores streams `.1st-pass.fdr_experiment.bin` a second time; Pass2FdrSidecar (line 712,
   ReadMap) already holds the same records in pass1Experiment. Efficiency only; one record per scored precursor.
5. Single-file second pass: FinishRecord reports experiment precursor q = run q (ExperimentQ short-circuits on !_multiFile) but
   experiment peptide q from CompetePeptides, which has no single-file shortcut; pass 1 (PercolatorScorer isSingleFile ? rpe) keeps
   exp == run. The FinishRecord comment reads as intentional; worth one sentence of why.
6. ComputeLibraryGroupPeps fits the PEP over every unit including never-detected library proteins. The doc comment states that
   intent; question whether the fit population should be the grouped units.
Dropped (reason): decoy-per-charge split in CompetePeptides - compaction is pair-symmetric by base id (FirstPassFdrTask ~1490),
so a surviving decoy's target survives and TargetPeptideFor names it; null-peptide ArgumentNullException at PercolatorScorer
349 - peptides come from peptideById and are string.Empty, not null, in the stub case, and PercolatorQValues 1044 has used the
same unguarded lookup; LibraryProteinScores.Add ignoring out-of-range ids - documented, and the driver's version stamp check
guards the stale-sidecar case.
PR body still says "Draft, experimental" and leaves the TeamCity Perf/Regression item unchecked although 4256392 was SUCCESS.

### 2026-11-08 - Finishing #4823 for merge (Brendan's call: finish it rather than hand back review comments)
Brendan: both PRs should merge soon; a session stacking on #4850 already uses #5011, and that work is likely to remove the
SecondPassFDR re-competition at every level. The PEP question (fit population, item 6 above) goes to Mike; items 1-2 stay open.
Fixed on Nick's branch (833e1a2a31, pushed): OspreyBlibWriter writes RefSpectra.PeptidePep and Proteins.Pep (the #4848 columns
Osprey had not filled; GroupPeps had reached nothing but a unit test), BlibOutputWriter passes entry.ExperimentPeptidePep and
the group PEP (1.0 with no target winner), IOTest/SubsetPipelineTest/BlibComparer cover them, BlibGolden.ps1 pins them,
regression-parallel.ps1 forwards -CreateGolden (recapture 18:47 wall vs ~2 h serial), 13-blib-output-schema.md lists six paired
columns. Goldens: RefSpectra and Proteins recaptured on all four datasets; verified by stripping the new column and diffing
(0 diffs, 0 empty values; `ai/.tmp/sessions/20261108-pwcontinue/check-goldens.ps1`); protein_fdr.tsv unchanged. Gates: Osprey
656/656 + zero inspections; `regression-parallel.ps1 -Dataset All` 49/49 PASS in 41:59. PR body rewritten (no longer "draft";
test plan current). TeamCity Osprey Perf/Regression triggered on pull/4823: build 4256524.
#5011: merged Nick's branch (8d05d56cda), Osprey gate 656/656 + zero inspections; Stellar + StellarGenDecoyEntrap legs running.

### 2026-11-08 - #4823 merged; #5011 retargeted to master
PR #4823 squash-merged as 61591d866b (TeamCity Osprey Perf/Regression 4256524 SUCCESS at 833e1a2a31; 17/17 checks green).
#5011 retargeted to master (`gh pr edit --base master`), origin/master merged in cleanly (a92323be83), Osprey gate 656/656 + zero
inspections, pushed; Osprey Perf/Regression triggered on pull/5011. Open from the #4823 review, carried here: subset-eliminated
proteins competing as their own units, razor not constraining the group score, and the PEP fit population (Brendan to ask Mike).
