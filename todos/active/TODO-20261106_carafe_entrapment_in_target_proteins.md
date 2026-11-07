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
