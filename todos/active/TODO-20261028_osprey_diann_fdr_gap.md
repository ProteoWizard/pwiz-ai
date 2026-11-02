# TODO-20261028_osprey_diann_fdr_gap.md

## Branch Information
- **PR**: [#4950](https://github.com/ProteoWizard/pwiz/pull/4950) (opened 2026-10-30; Auto-fix off)
- **Module**: `osprey`
- **Branch**: `Skyline/work/20261028_osprey_diann_fdr_gap` (pushed; merged with master at 4145709c7d), cut from
  `origin/master` at 406fd374c0 (2026-10-28), which holds all of Brendan's Osprey work to date,
  including the one-command CarafeSharp library build (#4876, #4885) and the `.model.zip` rename (#4895)
- **Checkout**: `D:\Dev\pwiz-osprey-fdr` (new worktree)
- **Base**: `master`
- **Created**: 2026-10-28
- **Status**: Phases 1-3 done and Phase 4 begun (2026-10-28, one day). Headline: Osprey's FDR is NOT too
  conservative - that was an entrapment-design artifact (Finding 2/3); compaction has no effect (Finding 5); the
  real gap is single-run scoring (38-40% at matched FDP). On the branch, 12 XICs + 20 new features + GBDT close a
  third of it (106,630 vs 142,619 at FDP 0.5%; was 88,604) but GBDT's reported q runs ~1.5x anti-conservative.
  #4823 fixes protein FDR. REQUIREMENT (Mike): single-peptide proteins must be detectable, so the default
  >= 2-peptide stratum competition must go (section below). Next: transfer-mode arms, symmetric decoy reconciliation
- **GitHub Issue**: (none)
- **Module**: `osprey`
- **PR**: (none)
- **Continues**: `TODO-20261021_osprey_diann_timing.md` (the matched-FDP comparison; its runner and
  plot scripts are reused here)
- **Machine**: i9-9900K (8 cores / 16 threads), 64 GB, GeForce GTX 1650 (4 GB)

## Goal

Find out why DIA-NN identifies ~20-27% more precursors than Osprey on the Astral test data at the
same entrapment-measured FDP, and fix what is Osprey's to fix. The specific questions:

1. Is Osprey's precursor FDR too conservative, and if so, at which stage (first-pass run, first-pass
   experiment, second-pass run, second-pass experiment)?
2. Does first-pass compaction (before reconciliation and the multi-charge consensus) drop precursors
   that the later stages could have rescued?
3. Is protein-group FDR controlled, with and without Nick's fix (#4823)?
4. What change closes the gap without breaking FDR control?

## REQUIREMENT: single-peptide proteins must be detectable (Mike, 2026-10-28)

"Absolutely not to limiting proteins to multiple peptides. Unless you can detect proteins with only a single
peptide in the protein sequence the method doesn't work for proteomics. Small proteins less than 100 amino acids
are some of the most important in proteomics these days. We absolutely must be able to detect proteins with
single peptides."

- No FDR, compaction or scoring scheme may require, or give an easier competition to, proteins with >= 2
  detected peptides.
- The default second pass violates this: `OSPREY_PASS2_QVALUE=protein-compact` runs its own target-decoy
  competition over the stratum of proteins with >= 2 first-pass peptides. It does not drop single-peptide
  proteins outright - their peptides survive with their pass-1 q - but they need stronger evidence for the
  same q. The +6% pass-2 gain at matched FDP (Finding 3) IS that bias, so it is not a gain we may keep.
- Every protein-informed change gets judged by what it does to single-peptide proteins: report their counts and
  FDP beside the totals.
- The fix direction is a second pass that treats every precursor alike (`transfer`-like), plus reconciliation
  made symmetric for decoys; protein inference must report one-peptide groups (#4823's picked-protein FDR can).

## REQUIREMENT: reconciliation stays, with accurate FDR (Mike, 2026-10-28)

"Reconciliation is essential for quantification. The reconciliation is essential to ensure we are picking the
same signal across different replicates. We need to figure out a way to get accurate FDR control for this."

- Never trade reconciliation away for calibration. The `transfer` second pass keeps it in full (re-picks,
  forced integrations, gap fills) and takes experiment q from the calibrated first pass: identify on the first
  pass, quantify on the reconciled peaks.
- Still to show: that the RUN-level q of a reconciled or gap-filled peak (re-mapped through the run's
  score-to-q table) is accurate, since per-run filtering feeds quantification.

## NOTE: how to describe the `transfer` second pass (Mike, 2026-10-28)

"Transfer" names the mechanism, not the idea. Describe it as: **the second pass maps each re-scored peak through
the first pass's calibrated score-to-q relationship** (per run; plus score-to-PEP once the run PEP is built) and
keeps the first pass's experiment-level q - identify on the first pass, quantify on the reconciled peaks. Short
name: "first-pass calibration". Renaming the `OSPREY_PASS2_QVALUE=transfer` token is Brendan's call (natural moment:
if it becomes the default).

**Next, agreed design - run-level PEP:** each replicate's own first-pass score-to-PEP curve (`PepEstimator` fitted on
that run's target-vs-paired-decoy winners) gives every peak a run PEP at its score - unchanged peaks at their pass-1
score, moved and gap-filled at their new one - stored beside the experiment PEP, exported per run, and validated by
entrapment share per PEP bin for unchanged / moved / gap-filled. Mike expects most gap fills near PEP 1 ("we are
saying those peptides are not in those samples").

## NOTE: DIA-NN on the Stellar (unit resolution) - always these flags (Mike, 2026-10-28)

`--no-ms1 --mass-acc-cal 900` on every DIA-NN search of Stellar data. `--no-ms1`: unit-resolution data does not
work well with DIA-NN's MS1 scoring. `--mass-acc-cal 900`: DIA-NN's default starting calibration (100 ppm) is far
too tight for the Stellar; from 900 it calibrates itself to ~400-550 ppm (leave `--mass-acc` unset). Both are in
the Stellar presets of `Run-DiannComparison.ps1` and `Run-DiannEntrapment.ps1`. DIA-NN still cannot calibrate the
Stellar .raw even with them (20 ppm, 0 IDs in 2.2-2.6.1, TODO-20261021), so DIA-NN reads the msconvert mzML on
Stellar while Osprey reads the .raw - the one exception to the raw-files rule.

**Root cause of the Stellar .raw failure (2026-10-28 night).** Re-tested: DIA-NN 2.6.1 on the three test .raw with
`--no-ms1 --mass-acc-cal 900` (acknowledged: "MS1 information will be ignored") reads the same structure as from the
mzML (97,500 MS2 scans, 780 cycles, 0 MS1), then cannot calibrate, falls back to 20 ppm, 0 IDs
(`fdr-gap\stellar\diann-search-raw\step.log`). Thermo RawFileReader on `_21` (scratchpad `rawscan.ps1`): every MS2
scan is `IsCentroidScan=True`, analyzer ITMS, 236-1,144 peaks in the SEGMENTED scan and **0 peaks in the centroid
stream**. Orbitrap/Astral data carry a centroid stream; Stellar ion-trap scans keep their peaks only in the segmented
scan. A reader that takes the centroid stream (inferred for DIA-NN; closed source) sees empty spectra - which fits
every symptom. msconvert reads the segmented scan. Worth reporting to DIA-NN's developer (fall back to the segmented
scan for centroid scans without a centroid stream); until then DIA-NN needs mzML on Stellar.

## DIRECTION (Mike, 2026-10-29): `transfer` is not the answer for reconciled peaks

"The transfer makes less sense to me as I think about it. We need a better way to capture the null distribution of
the moved and gap filled precursors with the paired decoys." Looking up a re-scored peak in the first-pass
score-to-q / score-to-PEP curve assumes the first pass's mix of true and false (its pi0) - wrong for gap fills
(mostly absent peptides; ~12% FDP at run q 1%). Next FDR work: build the null for moved and gap-filled peaks from
their OWN paired decoys (Osprey already re-integrates / gap-fills each target's decoy alongside it), giving q and
PEP for those peaks from that competition; keep the first-pass experiment q for identification. Parked on 2026-10-29
while Mike looks at the ZT-scan / staggered / super-overlap data first.

## What we already know (from TODO-20261021_osprey_diann_timing.md, Osprey of 2026-10-21)

These measurements predate two weeks of master, so Phase 1 repeats them. They also shape the plan:

- **At matched entrapment FDP, Osprey trails DIA-NN on Astral by 26.6% / 21.6% / 17.6%** (experiment
  precursors at FDP 0.3% / 0.5% / 0.75%: 100,103 vs 136,434; 111,778 vs 142,619; 120,566 vs 146,371).
  Stellar goes the other way (Osprey +5-7%).
- **At each tool's own q <= 1%, the delivered precursor FDP was about the same**: Osprey 0.55%,
  DIA-NN 0.50% (Astral, combined estimator). Both are conservative by about 2x, so conservativeness
  alone accounts for little of the gap. It is still worth fixing: an exactly calibrated Osprey would
  report more at q 1%. Phase 1 re-measures this before we act on it.
- **Protein-group FDR was not controlled**: Osprey 6.60% FDP at q <= 1% on Astral (every group q = 0),
  DIA-NN 1.30%. #4823 reports 0.82% on Astral with its fix.
- **The DIA-NN-only precursors are low-abundance and sit just below Osprey's line**: of 32,739, 98.4%
  were scored by Osprey at DIA-NN's peak, 10,853 have Osprey q 0.015-0.05, and 4,937 never reach the
  FDRBench export (dropped at compaction). Their fragment features look decoy-like to Osprey.
- **The FDRBench pass-2 export is a fair sample only to q ~0.015**: past it, compaction has removed most
  entrapment. Any FDP curve past q 1.5% must come from the pass-1 export.
- A gradient-boosted classifier (`OSPREY_FDR_MODEL=gbdt`) added +2-5% at matched FDP. Features are the
  larger lever, but that is outside this TODO unless Phases 1-3 come up empty.

## How compaction works on master (read 2026-10-28)

`FirstPassFdrTask.ComputeFirstPassBaseIds` (`Osprey.Tasks/FirstPassFdrTask.cs:2597`). A target
base_id, together with its paired decoy, survives into reconciliation and the second pass when, **in any
run**, any of these is true:
- its first-pass run-level **peptide** q <= `--reconciliation-compaction-fdr` (default 0.01);
- its first-pass experiment **protein** q <= `--protein-fdr` (the first-pass protein FDR, which #4823
  does NOT change);
- it is in the protein stratum (proteins with >= 2 peptides passing first-pass protein FDR), under the
  default `OSPREY_PASS2_QVALUE=protein-compact`.

The second pass then scores the survivors with the frozen first-pass model and runs a fresh
target-decoy competition restricted to the stratum (`docs/12-second-pass-fdr.md`). Off-stratum
survivors keep their first-pass q. The stratum gate is target-conditioned, which biases the decoy null
(#4581, open). Loosening compaction was expected to risk anti-conservative second-pass q
(`OspreyConfig.ReconciliationCompactionFdr`); that risk is what the entrapment oracle measures here.

## Design of the evaluation

**Data**: the three Astral HeLa runs (`_49`, `_55`, `_60`), **.raw for both tools** (DIA-NN reads
Astral .raw correctly: 8 ppm calibration, ~138k IDs per run), from
`D:\GitHub-Repo\maccoss\osprey\example_test_data\astral`. FASTA
`uniprot_human_jan2025_yeastENO1_contam_ADpeps.fasta`.

**Entrapment**: natural (foreign-species) entrapment at 1:1: Arabidopsis peptides
(`uniprot_arabidopsis_feb2023.fasta`), mass-matched to each target by Osprey's `--entrapment 1.0
--entrapment-fasta`. Natural entrapment over-estimates FDP by only ~1.1x, against ~1.6x for shuffled
(`ai/docs/osprey-library-generation-guide.md`). Report both the combined estimator
N_e (1 + 1/r) / (N_t + N_e) and the lower bound N_e / (N_t + N_e).

**Arm O (Osprey)**, latest master:
1. Tune: the one command with `--fasta` and `--training-input <_55>` (the middle run), **no
   entrapment**, saving `<stem>.model.zip`. Tuning never sees entrapment.
2. Search: the one command with `--model <that .model.zip> --entrapment 1.0 --entrapment-fasta
   <Arabidopsis>`, `--fdrbench ... --fdrbench-pass both`, `--model-diagnostics`, `--protein-fdr 0.01`.

**Arm D (DIA-NN 2.6.1)**, its own predictions: DIA-NN's predictor on exactly Osprey's target + entrapment
peptides (a peptide FASTA from Osprey's predicted `.blib`, `--cut "" --duplicate-proteins`), then the
search on the .raw with `--reanalyse` (MBR), `--pg-level 0`, `--qvalue 0.05`. Same peptides, so r is the
same for both tools. No fine-tuning for DIA-NN.

**Runner**: `ai/scripts/Osprey/Benchmark/Run-DiannComparison.ps1` (tuning step) and
`Run-DiannEntrapment.ps1` (search steps), analysis `plot_entrapment.py`. Extend them with switches; no
new runner. Runs go to `D:\test\osprey-runs\fdr-gap\astral\<arm>`. Snapshot the exe to
`D:\test\osprey-runs\_bin\fdr-gap-<sha>` before each long run and pass it with `-OspreyExe`.

## Plan

### Phase 0 - setup

- [ ] Settle the uncommitted changes in `D:\Dev\ai` from the 2026-10-21 session
      (`Run-DiannEntrapment.ps1`, `plot_entrapment.py`, `plot_diann_comparison.py`,
      `diann_library_swap.py`, the diann_timing TODO) - commit them, then `git pull --rebase` (ai/ is
      112 commits behind) before editing the scripts
- [ ] Build Osprey from this branch (`Build-Osprey.ps1 -SourceRoot D:/Dev/pwiz-osprey-fdr -Torch cuda`),
      snapshot it
- [ ] Update the runners for master: `.carafemodel` became `.model.zip` (#4895); add `--fdrbench-pass
      both` and `--model-diagnostics`; add a `-OspreyExtraArgs` switch and an arm name, so the sweeps
      below are parameters, not copies

### Phase 1 - baseline and where the conservativeness comes from

- [ ] Arm O tune + search; Arm D library + search
- [ ] IDs at matched FDP 0.3 / 0.5 / 0.75 / 1.0%, experiment and per run, both tools (repeat the 10-21
      table on current master)
- [ ] **Calibration curves**: reported q vs entrapment FDP, q 0-5%, for each Osprey stage - pass-1 run,
      pass-1 experiment, pass-2 run, pass-2 experiment - and for DIA-NN's `Q.Value` and
      `Global.Q.Value`. The pass-1 export covers the full q range; pass 2 only to ~0.015
- [ ] Count what exact calibration would be worth: Osprey IDs at q 1% vs at measured FDP 1%
- [ ] Where conservativeness appears, decompose the q estimator at that stage: the +1 in (D+1)/T, the
      decoy/target ratio, experiment best-of-runs aggregation of decoys, the stratum restriction

### Phase 2 - does compaction cost identifications?

- [ ] **Trace the DIA-NN-only precursors through the pipeline**: for each, kept or dropped at
      compaction (`.1st-pass.retained_base_ids.bin`), pass-1 q, pass-2 q, reconciled or not. Splits the
      gap into "never scored well", "dropped by compaction" and "survived compaction, lost in pass 2"
- [ ] **Compaction sweep**: `--reconciliation-compaction-fdr` 0.01 (baseline), 0.02, 0.05, 0.10, 1.0 (no
      compaction - affordable at 3 runs). Resume each from FirstPassFDR on the baseline's per-file
      scores (pin `OSPREY_VERSION_OVERRIDE` if a build day passes). Per arm: IDs at matched FDP, delivered
      FDP at q 1% (pass 2), survivors and pass-2 decoys, reconciliation re-picks and gap fills
- [ ] **Pass-2 mode**: `OSPREY_PASS2_QVALUE=transfer` against the default `protein-compact`, at the
      baseline compaction and at the best sweep point - isolates the stratum competition (#4581) from
      compaction itself
- [ ] Reading: if IDs at matched FDP rise with a looser gate and FDP at q 1% stays under 1%, compaction
      is a cause and the gate (or what the second pass does with a larger pool) is the fix. If FDP rises
      with the IDs, the second-pass null cannot carry a larger pool, and the fix is in the null, not the gate

### Phase 3 - protein FDR

- [ ] Arm O with #4823 merged locally into a throwaway branch off this one (it conflicts with master in
      `Osprey.IO/FdrScoresSidecar.cs` only); nothing pushed to Nick's branch
- [ ] Protein-group FDP at reported q <= 1% and the calibration curve, against master's and DIA-NN's
- [ ] Does #4823 change the compaction result? Its first-pass protein FDR is unchanged, so the protein
      rescue clause should not move - confirm

### Phase 4 - fix

- [ ] Choose the fix from Phases 1-3 and implement it on this branch, gated by the entrapment oracle:
      delivered FDP at q 1% <= ~1% (combined estimator) on Astral, plus Stellar as the check that the
      instrument where Osprey already leads does not lose
- [ ] Candidates, depending on the findings: a looser compaction default; a DIA-NN-style second pass in
      which a loosened pass-1 set is re-searched against a symmetric (target + paired decoy) pool; a
      corrected q estimator at the conservative stage; the #4581 null fix
- [ ] `regression.ps1 -Dataset All` (via `regression-parallel.ps1`), goldens recaptured where results
      move on purpose; `Build-Osprey.ps1 -Configuration Debug -RunTests -RunInspection`; `/code-review`

## Decisions

- Astral only for the investigation (where the gap is); Stellar only as the regression check for a fix.
- The tuned model is trained without entrapment, then reused for the entrapment search.
- DIA-NN gets no fine-tuning; it predicts the same peptide list Osprey searches.
- Nick's #4823 is measured as a local merge, not pushed or edited (his PR).

## Where it stands (end of 2026-10-28)

Astral, 3 runs, natural 1:1 entrapment filed under the targets' proteins (the only valid measurement for the
default protein-compact pass 2). Experiment-level precursors:

| arm | reported at FDP 0.3% | reported at FDP 0.5% | FDP at reported q 1% (combined / lower) | per run at q 1% |
|---|---|---|---|---|
| DIA-NN 2.6.1 (MBR) | 136,434 | 142,619 | 0.50% / 0.25% | 137,741-138,105 |
| Osprey default | 81,226 | 88,604 | 1.36% / 0.68% | 82,449-84,342 |
| 12 XICs | 88,322 | 94,741 | 1.43% | 91,340-92,525 |
| GBDT | 88,216 | 95,441 | 1.40% | - |
| 12 XICs + GBDT | 94,326 | 100,282 | 1.59% / 0.79% | 95,315-96,986 |
| runner-up + context, GBDT | 92,830 | 100,822 | 1.45% | 94,730-96,957 |
| all 41 features, SVM | 86,737 | 94,769 | 1.37% | 89,715-91,563 |
| all 41 features, GBDT | 94,098 | 101,127 | 1.46% | 97,150-99,277 |
| **all 41 features + 12 XICs + GBDT** | **100,054** | **106,630** | 1.50% / 0.75% | **101,624-102,725** |

The last arm's pass 1: 102,274 at FDP 0.5% (+22%), 1.04% at q 1% - calibrated; the pass-2 drift is new with GBDT.

What did NOT matter: compaction (0.01 / 0.05 / none identical), reconciliation (transfer = pass 1), the
best-of-runs clamp (1,282 of 2.4M raised), DIA-NN's MBR (+2% for DIA-NN), RT (fine-tuned Chronologer,
nothing on the AlphaPeptDeep fallback), fragment tolerance (both ~6-7 ppm), the library (Osprey on DIA-NN's
predictions does slightly worse), peak choice (91% of DIA-NN-only precursors picked at the same peak), a
12-fragment library cap.

Open:
- [ ] **Single-peptide requirement (above): replace the >= 2-peptide stratum competition.** Measure every arm
      in `transfer` mode (no stratum) as well; the stratum's +6% is not ours to keep. Count single-peptide
      proteins at matched FDP for each arm, Osprey and DIA-NN
- [ ] Pass-2 calibration: reported q 1% measures 1.29-1.37% (SVM) and 1.45-1.59% (GBDT) under protein-compact,
      ~1.03% under `transfer`. Mechanism found with Mike (2026-10-28): reconciliation is asymmetric for decoys.
      `ConsensusRts` builds a TARGET's consensus RT only from its qualifying (FDR-passing) detections, so a false
      target's best run is never moved, but its paired DECOY's consensus from ALL its picks (median), so the
      decoy's best noise peak can be moved away - the decoy is weakened exactly where it stands in for a false
      target, and re-competing those scores makes q optimistic. Fix to test: build the decoy's consensus from its
      picks in the runs where its target qualified (or never move a pair's best run); measure against
      reconciliation off
- [x] Ablate with OSPREY_FEATURE_MASK: which of the 20 new features carry the gain. Done 2026-10-30 (leave one
      family out, SVM, Astral / Stellar / ZT): data-dependent, none costs IDs anywhere; keep all 41
- [ ] Stellar check that 12 XICs + features + GBDT do not cost IDs where Osprey already leads
- [ ] Remaining gap (~25% at FDP 0.5%): further Radiant families (alt-charge features, amino-acid counts for
      GBDT), and the classifier (bagged NN like DIA-NN/Radiant)
- [x] Fix `peak_spectrum_cosine_sd.IsReversedScore` (the data says higher is target-like) - 80f7c2469d, with the
      other `/code-review` fixes: OSPREY_RECONCILIATION / OSPREY_PEP_FORMULA keyed, `OSPREY_RECONCILIATION=off`
      removed (failed at rescoring), training-export CORE flags follow the XIC count. Dropped: override-path
      runner-up values (count 1, margins 0; transfer measured calibrated with them unmasked on all three datasets),
      duplicate-bounds margins, reusing the SG sweep's cosines
- [x] Document the new features and per-dataset use: `docs/03-spectral-scoring.md` B.7 (e554304005)
- [ ] Decide with Brendan what becomes default (XIC count, features, classifier); goldens move when it does
- [ ] Entrapment design: Osprey's `--entrapment` files entrapment under its own `_p_target` protein, which
      cannot measure the protein-compact pass 2 (Finding 2). Raise with Brendan/Nick (protein-level FDP needs the
      separate proteins; precursor-level needs them attached)

## Progress Log

### 2026-10-28 - Phase 0 done, Phase 1 baseline (autonomous day session)

Setup: ai/ pending changes committed (c5e98b52) with this TODO (95af6726). Built this branch with
`-VendorReader`, snapshot `D:\test\osprey-runs\_bin\fdr-gap-406fd374c0`. #4823 merged locally into the
throwaway branch `Skyline/work/20261028_osprey_fdr_gap_pr4823` (worktree `D:\Dev\pwiz-osprey-fdr-4823`,
merge 07b7d909f3; the one conflict kept both assignments), 648/648 tests pass, snapshot
`_bin\fdr-gap-pr4823-07b7d909f3`. Runners: `Run-DiannEntrapment.ps1` gained `-FdrBenchPass` (default
both), `--model-diagnostics` on the osprey step, and the `osprey-arm` step (`-Arm`, `-ArmLibrary`,
`-OspreyExtraArgs`, `-OspreyEnv`); `Run-DiannComparison.ps1`'s tuning step got `--output-dir` (it wrote the
tuning search's per-run files into the shared Astral data folder). New `fdr_gap_analysis.py` reproduces
the 10-21 numbers exactly on the 10-21 run. Launchers: `ai/.tmp/sessions/20261028-fdrgap/phase1.ps1`,
`phase2.ps1`; logs `D:\test\osprey-runs\fdr-gap\astral\phase1.log`, `phase2.log`.

Tuning (`astral\tune\osprey-library`, 56.7 min, GPU): MS2 PCC 0.9768 -> 0.9861, RT R2 0.9972 -> 0.9989 on
`_55`; model `osprey.model.zip`. Entrapment search (`astral\osprey`, 47.2 min): 1,414,141 targets, each
with a mass-matched Arabidopsis peptide (median |dm| 0.044 Da); first pass 84,342 / 84,237 / 82,449
precursors at 1% run FDR; compaction kept 3,131,730 of 13,509,914 rows; 192,608 re-picks/imputations;
100,423 peptides at 1% experiment FDR; 8,079 protein groups.

**Finding 1 - the first pass is calibrated; the second pass only LOOKS conservative**
(`astral\analysis-osprey-only\summary.txt`):

| Osprey experiment q | IDs at q <= 1% | FDP combined / lower | IDs at FDP 0.5% |
|---|---|---|---|
| pass 1 (pre-compaction) | 93,549 | 1.03% / 0.51% | 83,561 |
| pass 2 (reported) | 113,483 | 0.54% / 0.27% | 112,897 |

**Finding 2 - entrapment cannot measure the protein-compact second pass.** Osprey files each entrapment
peptide under its own `<target accession>_p_target` protein, so entrapment almost never enters the protein
stratum (proteins with >= 2 first-pass peptides). Splitting pass 2 by an approximate stratum (proteins with
>= 2 pass-1 peptides at q <= 1%; 7,451 proteins, 13 of them entrapment):

| pass 2, q <= 1% | targets | entrapment | FDP combined |
|---|---|---|---|
| in stratum | 112,197 | 34 | 0.06% |
| off stratum | 1,286 | 271 | 34.8% |
| all | 113,483 | 305 | 0.54% |

99% of what Osprey reports comes from a competition entrapment never enters, so the "conservative" 0.54%
says nothing about the stratum's real error rate. The same applies to the 10-21 matched-FDP table:
Osprey's side of it is not a valid FDP. DIA-NN's precursor q is not protein-informed, so its entrapment
FDP stands. Off-stratum survivors (single-protein-hit peptides carrying their pass-1 q) are 35% entrapment
at q <= 1% - a conditioning effect, small in count.

Measurement fix: `astral\attached-library\osprey.attached.blib`, the predicted library with every
entrapment row (and its decoy) filed under its paired target's real accession (41,230 entrapment
proteins remapped, 3,301,180 RefSpectraProteins rows), so a protein detected by real peptides brings its
entrapment peptides into the stratum - the model of a false target inside a present protein. Entrapment
is labeled by sequence (the peptide FASTA), not accession. Protein-level FDP cannot be measured on it.

**Finding 3 - with a valid measurement, Osprey's FDR is NOT conservative, and the gap is ~38-40%**
(`astral\attached`, 18.8 min; `astral\analysis-attached\summary.txt`). DIA-NN 2.6.1 reproduced 10-21
to the precursor (same peptide FASTA, byte-identical; DIA-NN is deterministic).

| Astral, experiment level | IDs at q <= 1% | FDP comb / lower at q 1% | IDs at FDP 0.3% | IDs at FDP 0.5% |
|---|---|---|---|---|
| DIA-NN | 142,538 | 0.50% / 0.25% | 136,434 | 142,619 |
| DIA-NN per run (pooled) | 416,015 | 0.40% / 0.20% | | |
| Osprey pass 1 | 93,549 | 1.04% / 0.52% | 77,948 | 83,561 |
| Osprey reported, attached library | 102,443 | 1.36% / 0.68% | 81,226 | 88,604 |

- Osprey's reported q is calibrated to slightly anti-conservative; DIA-NN is the conservative one. The
  premise "Osprey is more conservative at 1%" came from the entrapment design (Finding 2).
- At matched FDP Osprey trails by 40% (0.3%) and 38% (0.5%), not the 22-27% of 10-21.
- Pass 2 (reconciliation + protein-compact) adds +6% over pass 1 at matched FDP 0.5%, not the +35% the
  unattached measurement suggested. The attached library's stratum carries the entrapment of detected
  proteins (compaction kept 6.26M rows, against 3.13M), so its competition is twice the size.
- The best-of-runs clamp is not a factor: it raised 1,282 of 2,437,828 experiment q-values.
- Trace of the 55,258 DIA-NN-only precursors at FDP 0.5%: 50,485 (91%) survived compaction with pass-2 q
  above Osprey's threshold (median 0.036; 25% under 0.0104), 4,322 (8%) dropped at compaction (median
  pass-1 q 0.19), 451 never scored. **Compaction is at most ~8% of the gap; scoring is the rest.**

**Finding 4 - reconciliation adds nothing measurable; DIA-NN's lead is single-run scoring, not MBR.**
- `astral\transfer` (`OSPREY_PASS2_QVALUE=transfer`, original library, so its FDP is valid): pass 2
  93,528 at q 1% (FDP 1.03%), identical to pass 1 at every matched FDP (83,544 at 0.5%). The re-picks and
  gap fills change nothing at the experiment level; the +6% of the default mode is the stratum
  competition. Protein groups: 8,021 at q 1% with 11.1% FDP (default mode 6.4%).
- `astral\diann-search-nombr` (DIA-NN without `--reanalyse`, 46.6 min): experiment 139,541 at FDP 0.5%
  (MBR 142,619: +2%); per run 126-127k at FDP 0.5% (MBR 141-142k). DIA-NN finds ~127k precursors in a
  single run with no cross-run help; Osprey's first pass ~84k at q 1%.
- Not the fragment tolerance: Osprey calibrates MS2 to +/-5.9-7.0 ppm (log `MS2 mass: ... tolerance`),
  DIA-NN to 6-7 ppm.
- Not RT: the library's RTs are all fine-tuned Chronologer (manifest `rt.model = chronologer,
  fine_tuned = true`; R2 0.9972 -> 0.9989 on `_55`); none of the 2,423,028 target/entrapment peptides has a
  residue or length (6-50) Chronologer cannot encode, so AlphaPeptDeep's RT fallback predicted nothing.

**Finding 5 - compaction has no effect at all.** Attached library, `--reconciliation-compaction-fdr`:

| gate | rows kept | IDs at q 1% | FDP at q 1% | IDs at FDP 0.5% |
|---|---|---|---|---|
| 0.01 (default) | 6,255,773 | 102,443 | 1.36% | 88,604 |
| 0.05 | 6,310,503 | 102,443 | 1.36% | 88,604 |
| 1.0 (none) | 12,787,747 | 102,443 | 1.36% | 88,604 |

Identical at every level: the protein rescue and stratum already keep the peptides of detected proteins,
and an extra survivor keeps its pass-1 q (above 1%). Without compaction the pass-2 export is fair to any q:
97,999 at FDP 1.0% (q 0.0072).

**Finding 5b - the whole gap is present in one run, one pass** (`astral\perrun`, `--fdrbench-per-run`; pass
1 is not protein-informed and DIA-NN without MBR uses no cross-run information, so entrapment is valid for both):

| single run, single pass | IDs at q 1% (49 / 55 / 60) | FDP at q 1% | IDs at FDP 0.5% | IDs at FDP 1.0% |
|---|---|---|---|---|
| Osprey pass 1 | 83,948 / 83,850 / 82,103 | 0.82-0.93% | 75,872 / 77,003 / 76,220 | 84,677 / 85,131 / 83,729 |
| DIA-NN, no MBR | 129,760 / 129,253 / 127,830 | 0.57-0.68% | 126,355 / 127,024 / 126,568 | 133,746 / 133,548 / 132,731 |

Osprey's run q is calibrated; DIA-NN's mildly conservative. At matched FDP a single DIA-NN run finds 37-40%
more precursors than a single Osprey run - before any cross-run or protein step.

**Finding 7 - #4823 fixes protein FDR** (`astral\pr4823`, the local merge 07b7d909f3; original library, whose
separate entrapment proteins are what protein-level FDP needs). Protein groups, reported q vs entrapment FDP:

| | q <= 0.1% | q <= 0.5% | q <= 1% | q <= 2% | q <= 5% | groups at FDP 1% |
|---|---|---|---|---|---|---|
| master | every group q = 0: 7,819 at 6.44% FDP | | | | | - |
| master, `transfer` | every group q = 0: 8,021 at 11.1% | | | | | - |
| + #4823 | 5,759 (0.14%) | 6,560 (0.43%) | 6,848 (0.73%) | 7,187 (1.57%) | 7,595 (3.95%) | 6,990 |
| DIA-NN | 8,200 (0.12%) | 8,529 (0.61%) | 8,702 (1.30%) | 8,907 (3.03%) | 9,206 (6.35%) | 8,635 |

Reproduces the PR's own Astral number (6,815 at 0.82%) on current master with the tuned library. Precursor
results unchanged (100,423 peptides, as master). At matched protein FDP 1% Osprey trails by 19%.

**Finding 8 - not the library: Osprey on DIA-NN's predictions does no better** (`astral\swap-osprey`, 24.2 min:
DIA-NN 2.6.1's predictor on every peptide of Osprey's library, decoys included, converted by
`diann_library_swap.py`, paired through the pairing manifest; pass 1 is valid on the original accessions).
`astral\c0.01` (the `-l` route at default settings) reproduced the one-command baseline byte for byte, so the
arms compare directly.

| Osprey pass 1, experiment | IDs at q 1% | FDP at q 1% | at FDP 0.3% | at FDP 0.5% | at FDP 1.0% | per run at q 1% |
|---|---|---|---|---|---|---|
| fine-tuned CarafeSharp library | 93,549 | 1.03% | 77,948 | 83,561 | 93,100 | 82,449-84,342 |
| DIA-NN's predictions | 90,215 | 0.91% | 74,609 | 82,905 | 91,529 | 79,787-81,131 |

DIA-NN finds ~127k per run from those same predictions. The gap is Osprey's scoring (features and classifier
on the peak it picks), not the predicted spectra or RTs. (DIA-NN's library keeps 12 fragments, Osprey's up to
20; the top-6 XIC features see the top 6 either way.)

**Finding 9 - a better classifier is worth ~8%; the features are the larger gap** (`astral\attached-gbdt`,
`OSPREY_FDR_MODEL=gbdt`, attached library so the FDP is valid):

| | IDs at q 1% (FDP) | at FDP 0.3% | at FDP 0.5% | at FDP 1.0% |
|---|---|---|---|---|
| pass 1, SVM | 93,549 (1.04%) | 77,948 | 83,561 | 92,991 |
| pass 1, GBDT | 100,162 (1.03%) | 81,727 | 90,804 (+8.7%) | 99,770 |
| reported, SVM | 102,443 (1.36%) | 81,226 | 88,604 | 97,999 |
| reported, GBDT | 108,334 (1.40%) | 88,216 | 95,441 (+7.7%) | 104,250 |
| DIA-NN | 142,538 (0.50%) | 136,434 | 142,619 | 149,500 |

GBDT is calibrated like the SVM and closes ~1/7 of the gap at FDP 0.5% (+7k of 54k).

**Fragments (Mike: predict more, score on the top 6-12; DIA-NN uses ~6 for most scores).** Osprey's library
keeps up to 20 predicted fragments per precursor down to 0.1% relative intensity (median 14, 10th-90th 8-20;
DIA-NN's library exactly 12). The search uses them two ways: the CWT peak detection and 13 of the 21 features
(coelution 0-2, peak shape 3-5, median polish 15/16/19/20) run on XICs of the TOP 6
(`TopFragmentExtractor.CAL_TOP_N_FRAGMENTS`), while the apex-spectrum features (xcorr, consecutive ions,
explained intensity, mass accuracy, SG xcorr / cosine) use EVERY library fragment. Experiments queued:
- `attached-top12`: the library predicted with `--lf-top-n-frag 12` (`top12-library`, mean 11.0 fragments,
  max 12), attached - caps what the apex-spectrum features see.
- `attached-xic12`, `attached-xic8`: `OSPREY_XIC_FRAGMENTS` (experiment switch, commit d9ef469191 on this
  branch, snapshot `_bin\fdr-gap-xic-d9ef469191`; unset = 6, 645/645 tests) - the XIC features on 12 / 8
  fragments, calibration and the 2-of-top-6 prefilter unchanged.

Result, `attached-top12` (18.6 min): no change - reported 88,238 at FDP 0.5% (default 88,604), 102,127 at q 1%
(FDP 1.34%); pass 1 82,670 (83,561). The extra low-intensity fragments do not hurt the apex-spectrum features.

Result, `attached-xic12` (21.1 min) - **12 XICs beat 6 by ~7-9%**, as much as the classifier change:

| attached library | per run at q 1% (pass 1) | pass 1 at FDP 0.5% | reported at FDP 0.3% | reported at FDP 0.5% | reported at q 1% |
|---|---|---|---|---|---|
| 6 XICs (default) | 82,449-84,342 | 83,561 | 81,226 | 88,604 | 102,443 (1.36%) |
| 12 XICs | 91,340-92,525 | 90,264 (+8.0%) | 88,322 (+8.7%) | 94,741 (+6.9%) | 108,287 (1.43%) |

| 8 XICs (`attached-xic8`) | 87,032-88,407 | 87,411 (+4.6%) | 85,578 (+5.4%) | 92,594 (+4.5%) | 105,168 (1.33%) |

Pass 1 stays calibrated (1.00% at q 1% for 6, 8 and 12). Gain rises with the count, diminishing.

`attached-xic12-gbdt` (24.4 min) - **the two gains add**: per run 95,315-96,986 at q 1%; pass 1 at FDP 0.5%
97,124 (+16%); reported at FDP 0.3% / 0.5% 94,326 / 100,282 (+16% / +13%), a quarter of the gap to DIA-NN. But
the reported q drifts anti-conservative: 113,701 at q 1% with combined FDP 1.59% (lower bound 0.79%); pass 1
1.11% at q 1%. Matched-FDP numbers already account for it; it must be fixed before any of this is a default.

`attached-xic16` (33.8 min): worse than 12 - per run 88,448-89,222; pass 1 at FDP 0.5% 88,710; reported 93,311
(12: 90,264 / 94,741). **12 XICs is the best of 6 / 8 / 12 / 16** (library median 14 fragments; past 12 the
extra fragments are mostly weak or absent and add noise) - Mike's 6-12 range, at its top.

**Scores DIA-NN-style engines have that Osprey lacks - from Radiant** (seerbio/radiant, Mike's pointer; C++,
`AlgorithmsFFLib/src/CandidateScores.h`, ~250 features into a bagged neural-net ensemble, config
`baggingSize = 10`, `maxAnchorColumnIndex = 6`, `subtractShadows`). Families with no Osprey counterpart:
- runner-up margin: `DiscScore1stRunnerUpDiff`, `DiscScore2ndRunnerUpDiff`, `DiscScoresCount/Mean/StDev` - how
  much the chosen peak beats the other candidates in its window (Osprey drops the alternatives' scores)
- per-fragment-rank evidence for fragments 1-12: `MzFoundMean1..12`, `IntensityFoundMax1..12` (+ normalized),
  `MzFoundStDev1..6` (Osprey: means over all fragments)
- profile similarity to an anchor over 12 fragments: `CosineSimSum100Top12`, `...GreaterThan80`,
  `AllignedMaxIndexesCount`, `PeakShapeRatio1..3` (Osprey: pairwise Pearson over 6 XICs)
- spectrum match at every scan of the peak: `CosineSimSpectrumOverTime`, `CosineSimSpectrumStDev`, `KlDivSpectrum`
- interference subtraction: `ShadowsCosineSimSum`, `subtractShadows`, `ionsSharedToReject`
- the other charge states' score and RT as features: `AltTargetKeyIdDiscScoreCharge1..4`, `...TimeDeltaCharge1..4`
- context: amino-acid counts, length, mass, charge, predicted RT/iRT, theoretical fragment count
- MS1 detail (per-isotope intensity and mass error, averagine); b/y ion-series counts and fractions
License: "Mandatory Grant-Back Apache 2.0 license, as modified by the Commons Clause" - use the ideas; do not
port code into pwiz without checking the terms. Fulcrum (seerbio/fulcrum, `pip install fulcrum-ms`) is Seer's
Spark-based downstream pipeline; Radiant v3.0.0 (2026-10-26) reads Thermo .raw itself
(`radiantdia_3.0.0+amd64.deb`, 103,910,214 bytes; Linux only - WSL2 Ubuntu here).

**Feature work on this branch (Mike: "Yes, start", 2026-10-28 evening).**
- `OSPREY_FEATURE_MASK`: comma-separated feature names to mask (written as 0 - the standardizer gives a
  constant column scale 1 and value 0, so the classifier cannot use it), or `none`. Unset, the new C#-only
  features are masked (`OspreyFeatureCalculators.DEFAULT_MASKED_FEATURES`), so default results are unchanged.
- Commit 31f24282b6 (27 features): runner-up `peak_coelution_margin`, `peak_rank_margin`, `peak_candidate_count`
  (from the extractor's captured candidates, published as `PeakCandidatesByproduct`; boundary-override rows
  report a lone candidate); context `context_peptide_length`, `context_precursor_charge`,
  `context_precursor_mz` (named `context_*` because the parquet already has `charge`/`precursor_mz` columns;
  fragment count and predicted RT left out - decoys are predicted separately, so those could differ from
  their targets for reasons unrelated to the data). 645/645 tests; `regression.ps1 -Dataset Stellar` PASSED vs
  the golden at 1e-9 (worktree `D:\Dev\pwiz-osprey-fdr-gate`, log `D:\test\osprey-runs\fdr-gap-gate-stellar.log`).
  Snapshot `_bin\fdr-gap-feat-31f24282b6`; arms `attached-feat1` (SVM) and `attached-feat1-gbdt` queued (`feat1.ps1`).
- Commit 6ffe5333c4 (39): per-fragment-rank `frag_rank1..6_abs_mass_error` (calibrated-tolerance fallback) and
  `frag_rank1..6_intensity_share` (share of the top-6 apex intensity). Commit 087b2825d9 (41): spectrum across
  the peak, `peak_spectrum_cosine_mean` / `_sd` (the SG sweep's per-scan cosine, now internal, over every scan in
  the bounds). 645/645 tests each; Stellar gate PASSED again on 087b2825d9 (`fdr-gap-gate-stellar-087b.log`).
  Snapshot `_bin\fdr-gap-feat-087b2825d9`; arms `attached-feat3` (SVM), `-gbdt`, `-xic12-gbdt` queued
  (`feat3.ps1`). Mike: the median-polish features already tolerate interference, so shadow subtraction stays last.

Results (attached library):

| arm | per run at q 1% | pass 1 at FDP 0.5% | reported at FDP 0.3% | reported at FDP 0.5% | reported at q 1% |
|---|---|---|---|---|---|
| default 21 features, SVM | 82,449-84,342 | 83,561 | 81,226 | 88,604 | 102,443 (1.36%) |
| `attached-feat1`: + runner-up + context, SVM | 86,331-87,694 | 89,024 (+6.5%) | 86,500 (+6.5%) | 92,585 (+4.5%) | 106,295 (1.29%) |
| `attached-feat1-gbdt`: same, GBDT | 94,730-96,957 | 95,427 (+14%) | 92,830 (+14%) | 100,822 (+14%) | 114,030 (1.45%) |
| `attached-feat3`: all 41 features, SVM | 89,715-91,563 | 90,212 (+8.0%) | 86,737 (+6.8%) | 94,769 (+7.0%) | 108,722 (1.37%) |
| `attached-feat3-gbdt`: all 41, GBDT | 97,150-99,277 | 96,624 (+15.6%) | 94,098 (+15.8%) | 101,127 (+14.1%) | 116,207 (1.46%) |

`attached-feat3` SVM weights: `peak_spectrum_cosine_mean` +0.558 (2nd, behind median_polish_cosine +0.778),
`peak_spectrum_cosine_sd` +0.332 (7th; positive - a real peak's cosine rises and falls with its signal, noise
stays uniformly low; IsReversedScore=true was the wrong guess), `peak_candidate_count` -0.401 (5th),
`context_precursor_mz` +0.279 (9th), `frag_rank1_intensity_share` -0.225 / `frag_rank6_intensity_share` +0.141
(evidence spread over several fragments looks real, one dominant fragment looks like noise); per-rank mass
errors and the margins small.

Pass 1 calibrated (1.00% at q 1%). SVM fold-mean standardized weights: `peak_candidate_count` -0.415 (5th largest;
fewer competing peaks is target-like), `context_precursor_mz` +0.292 (7th); the two margins +0.015 / +0.030 (the
linear model already has that from the coelution features), length +0.026, charge -0.011.

**FDR-control arms (2026-10-28 night, commit ceaab31b0d `OSPREY_RECONCILIATION`; best config = all features + 12
XICs + GBDT, attached library):**
- `best-symdecoy` (decoy consensus only from runs where its target's peptide qualified): re-picks 185,343
  (current 193,841); reported q 1% -> 119,429 at FDP 1.43% / 0.72% (current 119,512 at 1.50% / 0.75%); at FDP
  0.5% 107,150 (106,630). Real but small - the decoy asymmetry is not the main cause of the pass-2 drift.
- `best-reconoff` FAILED: with `Reconciliation.Enabled = false` the first pass writes no reconciliation data but
  PerFileRescoring still requires it ("Cannot resume: 3 of 3 runs still need re-scoring, but the cross-run
  reconciliation data they need is not available"). The config-only switch is not runnable end to end on
  master; not patched (pipeline code, diagnostic only).
- `default-symdecoy` (default config): re-picks 187,956; reported q 1% -> 102,360 at FDP 1.29% (current 102,443 at
  1.36%); at FDP 0.5% 89,133 (88,604). Same ~0.07-point improvement as the best config: the decoy asymmetry is real
  and the fix is worth keeping, but the bulk of the drift is the stratum competition. `default-reconoff` stopped
  (would fail like `best-reconoff`).
- `best-transfer` (OSPREY_PASS2_QVALUE=transfer: no >= 2-peptide stratum, every precursor competes alike):
  **112,206 at reported q 1%, FDP 1.04% / 0.52% - calibrated**; 102,232 at FDP 0.5%, 111,899 at FDP 1.0%. Against
  Osprey today (102,443 at q 1% but FDP 1.36%): ~10% more at a reported 1% that now means 1%. DIA-NN 142,538 at
  q 1% (FDP 0.50%). This is the configuration that satisfies both the FDR-control and single-peptide requirements.

**#4823 + transfer, protein level (original library, local merge c30bcbb9e1; `protein_split.py`):**

| Astral | protein groups at q 1% (FDP) | 1-peptide groups (FDP) | >= 2-peptide (FDP) | precursors at q 1% (FDP) |
|---|---|---|---|---|
| default config, protein-compact (`pr4823`) | 6,873 (0.73%) | 201 (~22%) | 6,672 (0.1%) | 100,423 peptides |
| default config, transfer | 6,890 (1.13%) | 355 (~20%) | 6,535 (0.1%) | 93,528 (1.03%) |
| best config, transfer | 7,879 (1.55%) | 482 (~24%) | 7,397 (0.1%) | 112,206 (1.03%) |

The protein q-values come from the first pass in every mode; what changes is which groups reach the output. The
>= 2-peptide stratum dropped many one-peptide proteins' only peptide in pass 2, which HID the miscalibration of
single-peptide groups (~20-24% FDP at a reported 1%) rather than fixing it. Under the single-peptide requirement
this must be fixed at the protein level: candidate - a separate picked-protein competition (own q) for groups
detected by one peptide, which holds them to their own error rate without blocking them.

**Run-level q of reconciled peaks under transfer (`astralest-transfer-perrun`, `--fdrbench-per-run`; pass-2 rows
classified against pass 1: absent = gap-fill, same score = unchanged, else moved):**

| run-level rows | rows | at run q <= 1% | FDP comb / lower |
|---|---|---|---|
| unchanged | 386,472 | 301,219 | 0.90% / 0.45% |
| moved | 50,214 | 2,619 | 0.76% / 0.38% |
| gap-filled | 18,456 | 728 | **11.6% / 5.8%** |
| all | 455,142 | 304,566 | 0.93% / 0.46% |

- Moved peaks are calibrated: the re-mapped run q holds. A move raises run q in 50.2% of rows and lowers it in 49.5%
  (reconciliation finds a better peak about as often as it forces a worse one).
- Gap-filled peaks are NOT: a gap fill happens only where the precursor is missing from the run, and false IDs are
  disproportionately the one-run ones, so the gap-fill population has a far higher prior of being false than the
  run-wide null the q comes from. Small share (728 of 304,566 passing rows), but per-run filtering for quantification
  would trust them. Options: report gap-fills as quantified-because-identified-elsewhere (flagged, no identification
  q), or give them a run q from a competition among gap-fills and their gap-filled decoys only.

**Run-level PEP (commit f01eea37fe, `OSPREY_DUMP_RUN_PEP`; Astral best config, transfer, attached library;
`run_pep_calibration.py`):** each replicate's first-pass score-to-PEP curve read at every survivor's score. Gap fills
mean run PEP 0.82 (17,483 of 18,456 at 0.5-0.9 - "not in this sample"); moved 0.81; unchanged 0.21. Of the 728 gap
fills passing run q <= 1%, 117 carry PEP 0.2-0.5. No PEP exceeds ~0.86 (the model's pi0 ceiling).

**PEP fails the q-PEP identity - Osprey's PEP is 4-8x too pessimistic (found 2026-10-29).** q at a threshold is the
mean PEP of everything passing it (PEP_k ~ d(k q_k)/dk). Run level: the 304,566 peaks at run q <= 1% average PEP 5.6%
(entrapment FDP 0.93%). Experiment level, the `.blib`'s `RefSpectra.PrecursorPep` (shipped since #4848): mean PEP at
experiment q <= 1% is 0.039 (Astral default), 0.059 (Astral best), 0.038 (Stellar) - 4-8x the identity at 0.1%, 0.5%
and 1% alike. Suspected cause, `PepEstimator.Fit`: `PEP = pi0 fD / (pi0 fD + (1 - pi0) fT)` with pi0 = decoy winners /
target winners and fT the density of ALL target winners - a false+true mixture used as if it were the true-match
density. With paired competition the expected false target winners at s equal the decoy winners there, so
`PEP(s) = (D/T) fD(s) / fT(s)` (capped at 1, monotone). The current form overstates PEP by ~1/(1 - pi0) where true
matches dominate: ~6.7x at a run-level pi0 ~0.85, ~4x at experiment level - the size of the gap. Not yet fixed; it is
shared code (experiment PEP, #4848 / Nick) - fix behind a switch, verify the identity and entrapment on the full
first-pass population, then raise with Nick and Brendan.

**Corrected PEP (commit 2674437153, `OSPREY_PEP_FORMULA=ratio`: PEP(s) = (D/T) fD(s) / fT(s); the dump also writes
each run's PEP curve; `run_pep_calibration.py --pass1`):** Astral best config, transfer, attached library.
- Run level over all 5.97M first-pass target peaks: mean PEP at run q <= 0.1 / 0.5 / 1 / 5% = 0.0010 / 0.0050 /
  0.0100 / 0.0498 - the identity holds; entrapment FDP 0.0012 / 0.0049 / 0.0103 / 0.0534. By PEP bin, mean PEP vs
  entrapment false (combined / lower): <0.01: 0.0013 vs 0.0015 / 0.0008; 0.01-0.05: 0.026 vs 0.025 / 0.012;
  0.05-0.2: 0.111 vs 0.122 / 0.061; 0.2-0.5: 0.349 vs 0.375 / 0.187. Calibrated.
- Experiment level (.blib PrecursorPep) at q <= 0.1 / 0.5 / 1%: 0.0010 / 0.0050 / 0.0100 (was 0.0082 / 0.0343 /
  0.0588); same 83,329 / 104,301 / 112,790 precursors (nothing in Osprey decides on PEP).
- Run PEP by class (corrected): gap fills 92.3% at PEP >= 0.5, median 0.88 ("not in this sample", as Mike expected);
  moved 91.6% >= 0.5; unchanged median 0.002. At run q <= 1%: unchanged 302,585 at mean PEP 0.0094 (entrapment share
  0.0045), moved 2,629 at 0.0101 (0.0038) - calibrated; gap fills 773 at mean PEP 0.0143 but entrapment share 0.058
  (~11-12% false): the replicate curve still underestimates the few gap fills that look present (gap fills are
  mostly absent peptides, a different mix than the run the curve was fitted on).
- Stellar (features + GBDT, 6 XICs): run level over 1.44M first-pass target peaks, mean PEP at run q <= 0.1 / 0.5 /
  1 / 5% = 0.0010 / 0.0050 / 0.0099 / 0.0497, entrapment FDP 0.0011 / 0.0047 / 0.0094 / 0.0516; by bin 0.0009 vs
  0.0010, 0.025 vs 0.023, 0.109 vs 0.108, 0.352 vs 0.371. `.blib` PrecursorPep at q <= 0.1 / 0.5 / 1%: 0.0010 /
  0.0048 / 0.0099 (was 0.0044 / 0.0188 / 0.0350), same 30,715 / 35,448 / 38,156 precursors.
- Rust osprey has the same form (`crates/osprey-ml/src/pep.rs` lines 72, 91-92).
- Note for Nick and Brendan drafted: `ai/.tmp/sessions/20261028-fdrgap/pep-note-draft.md` (not sent).

**Stellar (the three test runs; tune on `_21`: MS2 PCC 0.966 -> 0.984, RT R2 0.9976 -> 0.9989; DIA-NN on mzML
with `--no-ms1 --mass-acc-cal 900`, mass accuracy 707 / 264 / 506 / 219 ppm across its passes):**

| Stellar, attached library | per run at q 1% | at q 1% (FDP) | at FDP 0.3% | at FDP 0.5% |
|---|---|---|---|---|
| DIA-NN 2.6.1 | - | 32,701 (0.37%) | 32,388 | 34,274 |
| Osprey default, protein-compact | 27,168-27,944 | 32,910 (0.98%) | 29,007 | 30,869 (-10%) |
| Osprey default, transfer | 27,168-27,944 | 31,694 (0.71%) | 28,395 | 30,013 |
| best Astral config, transfer | 24,168-25,055 | 31,000 (1.00%) | 28,440 | 29,523 |

- Valid measurement: Osprey trails DIA-NN on Stellar by ~10% at matched FDP; the 10-21 "+5-7%" was the same
  entrapment-design artifact as on Astral. Default reported q is calibrated on Stellar (0.98%).
- The best Astral configuration HURTS on Stellar (per run -11%, matched FDP -2%): suspect 12 XICs at unit
  resolution (0.4 Da windows collect much more interference per weak fragment); GBDT or the features possible.
  Settings this instrument-sensitive have to be resolution-keyed, not global defaults.
- **Stellar ablation (transfer, attached library) - 12 XICs is the culprit; without it Osprey beats DIA-NN:**

| Stellar | per run at q 1% | at q 1% (FDP) | at FDP 0.3% | at FDP 0.5% |
|---|---|---|---|---|
| default | 27,168-27,944 | 31,693 (0.71%) | 28,395 | 30,012 |
| 12 XICs | 20,826-21,582 | 26,313 (0.65%) | 24,300 | 25,413 (-15%) |
| GBDT | 28,052-28,326 | 32,960 (0.88%) | 29,827 | 31,657 (+5%) |
| new features, SVM | 28,379-29,074 | 33,120 (0.77%) | 29,720 | 31,542 (+5%) |
| **new features + GBDT, 6 XICs** | **31,409-32,343** | **37,971 (0.97%)** | **34,005** | **35,562 (+18%)** |
| all + 12 XICs + GBDT | 24,168-25,055 | 31,000 (1.00%) | 28,434 | 29,516 |
| DIA-NN | - | 32,701 (0.37%) | 32,388 | 34,274 |

  At 0.4 Da the extra fragments add mostly interference (the opposite of Astral at 20 ppm). Features + GBDT help on
  both instruments. **XIC count must be resolution-keyed: 12 for HRAM, 6 for unit resolution.** On Stellar,
  features + GBDT (6 XICs) under transfer beat DIA-NN at matched FDP (+3.8% at 0.5%, +5% at 0.3%), calibrated.
- DIA-NN raw: see the NOTE above (root cause found).
- Stellar protein level, #4823 + transfer (original library): default 4,246 groups at FDP 0.89% (1-peptide 660 at
  5.2%); best config 4,400 at 1.59% (1-peptide 812 at 8.6%); DIA-NN 4,876 at 0.70% (1-peptide 870 at 1.4%, plus 173
  groups with no passing peptide at 12.7%). Precursors: default 31,693 at q 1% (0.70%), best 31,000 (0.99%).
  DIA-NN reports ~30% more single-peptide proteins at a quarter of Osprey's error there - the clearest target.

**Stellar window-width set: acquired 2Th / 4Th vs demultiplexed 50% / SuperOverlap (2026-10-29; Mike: look at the
ZT Scan and the staggered / super overlap data before more FDR work).** Lauren's 10-09 HeLa runs (3 replicates per
method; TODO-20261021_osprey_stellar_demux.md), the fine-tuned entrapment library from that work
(`carafe-finetune`, tuned on 2Th TR01) copied with entrapment filed under its targets' proteins
(`stellar-demux\fdr-gap\attached-library`; `attach_entrapment.py` with the manifest also upgrades that library's
pre-contract `DecoyPairs` table - PairID, no TargetRefSpectraID - which current Osprey refuses). Both overlap schemes
are the profile joint demux + in-process Centrix of `super-speed-final` (memfix-demuxtool); the 50% mzMLs had been
deleted and were regenerated with those settings (`tool\50pct-speed-final`, ~37 min per run). Snapshot
`fdr-gap-pep-2674437153`; "best" = all features + GBDT + 6 XICs + transfer. Experiment level, combined entrapment FDP
(r = 0.9948); `stellar-demux\fdrgap-<input>-<config>\search`, summary `stellar-demux\fdr-gap\arms_fdp_summary.txt`
(`ai/.tmp/sessions/20261028-fdrgap/arms_fdp.py`).

| Stellar | default: at q 1% (FDP) | default: at FDP 0.5% | best: at q 1% (FDP) | best: at FDP 0.5% | gain |
|---|---|---|---|---|---|
| 2Th acquired | 44,200 (0.86%) | 41,214 | 47,346 (0.85%) | 45,383 | +10.1% |
| 4Th acquired | 33,448 (0.91%) | 31,443 | 34,784 (0.90%) | 33,087 | +5.2% |
| 4Th 50% overlap, demux | 28,562 (0.94%) | 24,634 | 32,611 (0.83%) | 29,753 | +20.8% |
| 4Th SuperOverlap, demux | 29,489 (**1.11%**) | 24,587 | 32,754 (0.99%) | 28,494 | +15.9% |

- The new scoring helps most on demultiplexed data (+16-21% vs +5-10% acquired): the features separate demux
  interference from signal. Both demuxed sets reach 86-90% of acquired 4Th with it (75-78% at the default).
- The default's protein-compact second pass overshoots on SuperOverlap (1.11%; pass 1 0.93%); transfer keeps the
  calibrated first pass on every input (0.83-0.99%).
- The demux session's 2Th "47,405 at 0.49%" was entrapment in its own proteins (Finding 2); valid: 44,200 at 0.86%.
- Run-StellarSearch.ps1 leaked `-Env` into its caller (several arms run with `&` in one process): the first 4Th and
  SuperOverlap "default" arms ran the best settings. Fixed (cleared in a `finally`) and those arms rerun.

**ZT Scan (demultiplexed mzMLs of 2026-10-27, D1-tuned Osprey library re-filed so entrapment shares its targets'
proteins; `ztscan-full-20261027\fdr-gap\<arm>`, summary `fdr-gap\arms_fdp_summary.txt`; r = 1.0010).** Caveat: the
library tuning command carried `--entrapment`, so tuning may have seen entrapment peptides.

| ZT Scan | at q 1% (FDP) | at FDP 0.5% | at FDP 1% |
|---|---|---|---|
| default, protein-compact | 36,111 (**1.29%**) | 31,215 | 34,709 |
| default, transfer | 29,236 (0.98%) | 20,450 | 29,370 |
| features + GBDT + 12 XICs, transfer | 33,200 (**1.14%**) | 28,915 | 32,561 |
| features + GBDT + 6 XICs, transfer | 27,975 (0.82%) | 24,402 | 29,248 |
| features + GBDT + 12 XICs, protein-compact | 39,386 (**1.48%**) | 33,917 | 37,276 |
| DIA-NN 2.6.1, own library, .wiff | 50,627 (0.45%) | ~51,274 | - |
| DIA-NN on our demux | 58,280 (0.43%) | - | - |

- Osprey is at about half of DIA-NN on ZT Scan (Astral: 0.72x, Stellar: ahead) - the largest gap of any dataset.
- Here protein-compact earns its place: +52% at matched FDP 0.5% over transfer, +18% at 1% - but its q runs ~1.3x
  optimistic (Mike: the targets and decoys are not treated consistently, which is why it is not controlled).
- The new scoring is worth +41% at FDP 0.5% under transfer, and 12 XICs beat 6 (+18%) as on Astral (HRAM). Its GBDT
  first pass is optimistic on ZT (1.14% at q 1%; the first pass at the top of the list: q 0.41% at FDP 0.5%), unlike
  Stellar and Astral.
- Both together (`best12-compact`, Mike: "Yes, run it"): 33,917 at FDP 0.5%, +8.7% over protein-compact with the
  default scoring and +17% over the new scoring under transfer - the gains add only partly. Its reported q is the
  most optimistic of any arm: 1.48% at q 1% (pass 1 1.14%; q 0.33% at FDP 0.5%). Still 0.66x DIA-NN at matched FDP.

**ZT ablation of the new scoring (2026-10-30; Mike asked whether some new features hurt, from the 6-XIC row).** All 6
XICs + transfer; summary `fdr-gap\arms_fdp_ablation.txt`. The last two arms reused `best6-transfer`'s per-file scores
by hard link (their validity key holds neither the FDR model nor the training size); launchers
`ai\.tmp\sessions\20261028-fdrgap\ztscan-ablation*.ps1`.

| ZT Scan, 6 XICs, transfer | at q 1% (FDP) | at FDP 0.5% | at FDP 1% |
|---|---|---|---|
| 21 features, SVM (default) | 29,236 (0.98%) | 20,450 | 29,370 |
| 21 features, GBDT | 25,158 (0.79%) | 21,953 | 26,441 |
| 41 features, SVM | 31,944 (0.88%) | 28,004 | 32,708 |
| 41 features, GBDT | 27,975 (0.82%) | 24,402 | 29,248 |
| 41 features, GBDT, `OSPREY_MAX_TRAIN_SIZE=3000000` | 36,151 (**1.26%**) | 30,338 | 34,840 |
| 41 features, SVM, **12 XICs** (scores of `best12-transfer`) | 30,811 (**1.19%**) | 21,501 | 28,826 |
| 41 features, SVM, strict-max C (`OSPREY_SVM_C_TOLERANCE=0`) | 31,297 (0.92%) | 23,994 | 31,769 |
| 41 features, SVM, 12 XICs, strict-max C | 31,117 (**1.18%**) | 21,266 | 29,565 |

- 12 XICs HURT the SVM on ZT (-23% at FDP 0.5%, -12% at 1%, and optimistic) while they helped GBDT (+18%). Its fold
  C picks were 1 / 0.1 / 0.1 against 1 / 0.1 / 1 at 6 XICs, so the SVM's C selection (the noise-level pick of
  #4703) may be part of it; not separated. "12 XICs for HRAM" holds for GBDT on ZT and for the 21-feature SVM on
  Astral, not yet for the 41-feature SVM.
- C check (Mike: "fix the code first then run the c check"): both XIC counts rerun with the strict-max C, the old
  exe on the same hard-linked scores (`ztscan-csel0.ps1`). Picks 1 / 1 / 0.1 at 12 XICs, 1 / 10 / 1 at 6. Under one
  C rule 12 XICs still lose: -11% at FDP 0.5%, -7% at 1%, and stay optimistic (1.18% vs 0.92%) - so about half the
  0.5% gap was the C pick and the rest, plus the miscalibration, is the XIC count. The C rule alone moved the 6-XIC arm
  by -14% at FDP 0.5% (-3% at 1%): on ZT one fold's C pick is as large as the effects being compared, so a single-run
  ZT difference under ~15% at FDP 0.5% is not resolved; FDP 1% is steadier. Every ZT arm trains on about 750
  confident targets (0.5% of the 300,000-peak sample passes 1% FDR), which is why C is so loosely determined.
- **Defect on this branch:** the feature mask and the XIC count change the per-file scores but are not in their
  validity key (search hash identical across `attached-transfer`, `best6-transfer`, `best12-transfer`), so a resume
  with either changed reuses the wrong scores silently. The mask is applied only while scoring
  (`CoelutionScorer`), so masked features are stored as 0. Fix before a PR: key the XIC count, and apply the mask
  where the FDR stage loads features so the scores always hold all 41 (that also makes a feature ablation FDR-only).
  **Fixed** in fbab5a883c: `PinFeatureMask` zeros masked features in `LoadPinFeaturesFromParquet`; `;xic=N` in every
  task's key and `;featmask=` in FirstPassFDR / PerFileRescoring / SecondPassFDR. Old scores do not match the new key,
  so the next build rescores once. Unit tests 646/646, inspection clean, Stellar regression PASSED.

- The new features help, not hurt: +37% at FDP 0.5% and +11% at 1% under the SVM, +11% at both under GBDT. The 6-XIC
  row looked flat because GBDT at the default training size costs about what the features gain.
- GBDT is short of confident targets on ZT: the 9.08M-precursor library leaves 0.4-0.7% of the 150k training targets
  at 1% FDR (about 900). At 10x the training set it beats the 41-feature SVM by 8% at FDP 0.5% and 6.5% at 1% - but
  its q runs optimistic (1.26% at q 1%) and the first-pass FDR took 3.3 h against about 15 min.
- The 41-feature SVM is the best calibrated arm (0.88% at q 1%). The GBDT arms that find the most are the optimistic
  ones, so a flexible model may be learning what tells this library's decoys from targets rather than what tells
  right from wrong. Not tested.
- The older run folders `ztscan-full-20261025`, `ztscan-centrix`, `ztscan-portable` and `demux-speed-20261026` moved
  to `\\maccoss-nas\storage\osprey-runs-archive\osprey-runs` (T:) on 2026-10-30 to free D:.

**Leave-one-family-out ablation (2026-10-30; Mike: "Start ablations", answering whether all 41 features are needed
for every data type).** Fixed build fbab5a883c (snapshot `_bin\fdr-gap-featmask-fbab5a883c`), 41-feature SVM,
transfer, attached library; per dataset one full search with every feature (`fam-all41`), then FDR-only arms on its
hard-linked scores (every one logged `PerFileScoring:skipping`). Families: runner-up (3), context (3),
per-fragment-rank (12), spectrum across the peak (2); `fam-default21` = mask unset. Launcher
`ai\.tmp\sessions\20261028-fdrgap\family-ablation.ps1`, log `D:\test\osprey-runs\fdr-gap\family-ablation.log`, arms
`<dataset root>\fam-*`. Experiment level, combined entrapment FDP. The Stellar `fam-all41` reproduced the old-build
`feat-transfer` exactly (33,120 / 31,542), so moving the mask to load time changed nothing unmasked.

| Astral, 12 XICs | fold C | at q 1% (FDP) | at FDP 0.5% | at FDP 1% |
|---|---|---|---|---|
| all 41 | 0.01 / 0.1 / 0.01 | 106,064 (1.04%) | 96,270 | 105,498 |
| no runner-up | 0.1 / 1 / 0.1 | 105,387 (1.10%) | 96,006 (-0.3%) | 104,473 (-1.0%) |
| no context | 0.1 / 0.01 / 0.1 | 105,065 (1.05%) | 95,694 (-0.6%) | 104,536 (-0.9%) |
| no per-fragment-rank | 0.01 / 0.1 / 0.1 | 106,178 (1.05%) | 97,117 (+0.9%) | 105,718 (+0.2%) |
| no spectrum across peak | 0.1 / 0.01 / 0.1 | 101,845 (1.00%) | 93,438 (-2.9%) | 101,879 (-3.4%) |
| 21 (all new out) | 0.1 / 0.1 / 0.1 | 100,071 (1.01%) | 90,238 (-6.3%) | 99,946 (-5.3%) |

| Stellar, 6 XICs | fold C | at q 1% (FDP) | at FDP 0.5% | at FDP 1% |
|---|---|---|---|---|
| all 41 | 0.01 / 0.01 / 0.01 | 33,120 (0.77%) | 31,542 | 34,360 |
| no runner-up | 0.01 / 0.01 / 0.01 | 33,001 (0.74%) | 31,664 (+0.4%) | 34,251 (-0.3%) |
| no context | 0.01 / 0.01 / 0.01 | 32,234 (0.79%) | 30,874 (-2.1%) | 33,379 (-2.9%) |
| no per-fragment-rank | 0.01 / 0.01 / 0.1 | 33,226 (0.75%) | 31,590 (+0.2%) | 34,195 (-0.5%) |
| no spectrum across peak | 0.01 / 1 / 0.01 | 32,685 (0.72%) | 31,271 (-0.9%) | 34,204 (-0.5%) |
| 21 (all new out) | 0.1 / 0.01 / 0.01 | 31,693 (0.71%) | 30,012 (-4.9%) | 32,663 (-4.9%) |

| ZT Scan, 6 XICs | fold C | at q 1% (FDP) | at FDP 0.5% | at FDP 1% |
|---|---|---|---|---|
| all 41 | 1 / 0.1 / 1 | 31,944 (0.88%) | 28,004 | 32,708 |
| no runner-up | 0.1 / 1 / 1 | 30,910 (0.95%) | 22,774 (-18.7%) | 31,461 (-3.8%) |
| no context | 0.1 / 0.1 / 1 | 31,324 (0.85%) | 26,825 (-4.2%) | 32,232 (-1.5%) |
| no per-fragment-rank | 0.1 / 0.1 / 10 | 31,063 (0.95%) | 24,616 (-12.1%) | 31,392 (-4.0%) |
| no spectrum across peak | 10 / 0.1 / 1 | 31,258 (0.82%) | 25,887 (-7.6%) | 32,360 (-1.1%) |
| 21 (all new out) | 1 / 0.1 / 1 | 29,236 (0.98%) | 20,450 (-27%) | 29,370 (-10.2%) |

The ZT `fam-all41` and `fam-default21` reproduced the old-build "41 features, SVM" and "21 features, SVM (default)"
rows of the ZT ablation table above exactly, fold C picks included.

- The 20 new features together help on every data type under the SVM: Astral +6.7% at FDP 0.5% (+5.6% at 1%),
  Stellar +5.1% (+5.2%), ZT +37% (+11.4%). Every arm calibrated or conservative.
- No single family is needed everywhere, and which one matters depends on the data: spectrum across the peak on
  Astral (about half the gain), context on Stellar, runner-up and per-fragment-rank on ZT.
- Per-fragment-rank (12 of the 20) is worth nothing on Astral or Stellar (dropping it +0.9% / +0.2% at FDP 0.5%) but
  -4.0% at FDP 1% on ZT, so the data do not support dropping it. Every ZT leave-one-out moved the fold C picks, and on
  ZT the C rule alone moves -14% at FDP 0.5% and -3% at 1%: the ZT per-family numbers sit at about that noise level,
  while the all-20 gain (+11% at 1%) is well above it.
- Conclusion: keep all 41. The families are individually small and data-dependent, but none costs IDs anywhere
  beyond the C-pick noise, and together they are the largest single-run gain on every instrument.

**Runner-up features on rescored peaks (2026-10-31, 57e016e86c).** Peaks rescored at override bounds reported a lone
candidate (count 1, margins 0), the most target-like count. Mike's fix: rerun first-pass detection over the normal
window and compare the imposed peak with the candidates it does not cover; `;runnerup=` keys PerFileRescoring /
SecondPassFDR only when a runner-up feature is unmasked. 647/647, inspection clean, Stellar gate PASSED. Every
transfer arm with the runner-up features on was rerun (`fam2-*`, snapshot `_bin\fdr-gap-runnerup-57e016e86c`,
`OSPREY_VERSION_OVERRIDE=26.1.1.303` to adopt fam-all41's scores; launcher `runnerup-rerun.ps1`, log
`D:\test\osprey-runs\fdr-gap\runnerup-rerun.log`). Counts moved by at most 16 precursors (Astral 41 SVM 106,064 ->
106,052 at q 1%, 96,270 -> 96,257 at FDP 0.5%; GBDT 102,232 -> 102,227; Stellar <= 2; ZT <= 1). No conclusion changed;
doc tables updated (01853d89f1). New row: Stellar 41-feature SVM at 12 XICs 27,451 (0.69%) / 26,585 at FDP 0.5% (-16%
vs 6 XICs). Cost of the second detection: per-file rescoring Astral +25-28% (209 -> 267 s; about 2% of the search),
Stellar +11%, ZT none. Mike suggested reusing the first pass's stored CWT candidates instead; not done - pick scores
are not stored (adding them to `cwt_candidates` breaks Rust byte parity), the count is capped at top 5, and forced
gap-fills have no candidates; at ~2% the re-detection was kept. Open option: run it only when a runner-up feature is
unmasked, so default runs pay nothing.

**Review of #4823 (Nick's protein FDR, draft, last updated 2026-10-18; Mike asked for an opinion 2026-10-28).**
- What it does: picked-protein FDR (Savitski 2015) over EVERY library protein / parsimony group, each on its
  single best peptide, target vs decoy paired by base id, scored from the first pass's pre-compaction
  experiment records; plus a second-pass peptide-level competition and peptide / protein-group PEPs (moved from
  #4848). Fixes three real defects: decoys found by `DECOY_` name (none with library decoys -> every q = 0), only
  detected proteins competing, decoys scored from the compacted pool.
- No 2-peptide gate: a one-peptide protein competes on its best peptide like any other (Nick confirmed in the
  thread after Mike's 2026-10-11 comment).
- Reproduced on current master + the tuned library (`astral\pr4823`): 6,848 groups at q 1%, FDP 0.73% (PR:
  6,815 / 0.82%); precursors unchanged. Every group at q 1% has a precursor at q 1%.
- **Single-peptide groups carry nearly all the error**, in both tools - inherent to a global protein FDR:

| groups at reported q <= 1% | #4823 n | #4823 FDP | DIA-NN n | DIA-NN FDP |
|---|---|---|---|---|
| 1 detected peptide | 201 | ~22% (22 entrapment) | 439 | 11.4% |
| >= 2 detected peptides | 6,672 | ~0.1% (3) | 8,247 | 0.5% |
| no passing precursor | 0 | - | 73 | 30.1% |
| all | 6,873 | 0.73% | 8,759 | 1.30% |

- Concerns: (1) the new second-pass peptide competition runs over the protein-compact stratum survivors, so it
  inherits the >= 2-peptide stratum (single-peptide requirement) and the asymmetric decoy reconciliation;
  (2) validated on 3 runs only - Mike's thread point that protein-level false discoveries accumulate with many
  files needs a large-cohort check (82-file SEA-AD); (3) conflicts with master in `FdrScoresSidecar.cs` (resolved
  locally by keeping both assignments) and its protein_fdr.tsv goldens predate two weeks of master; (4) the
  first-pass protein FDR (compaction rescue, stratum) is unchanged.
- Opinion: merge the picked-protein competition (rebased via merge onto master); hold or split out the
  second-pass peptide competition until the second pass itself is fixed; decide how to report one-peptide groups
  honestly (a separate q for them would not block detection, only make their q mean what it says).

**Finding 6 - Osprey's first-step pick finds DIA-NN's peak 91% of the time for the precursors it misses**
(Mike's question: are we choosing the wrong peak before the 21 features ever see it?). `peak_agreement.py`
against DIA-NN without MBR (its own single-run peak), run q <= 1%, real targets, the 3 runs pooled
(`astral\analysis-peaks\peak_agreement.txt`, per-precursor `peak_agreement.parquet`):

| DIA-NN run IDs | n | same peak | wrong pick (in Osprey's top-N CWT candidates) | not a candidate | not scored |
|---|---|---|---|---|---|
| Osprey also reports (pass-1 exp q <= 0.0047, FDP 0.5%) | 243,464 | 99.3% | 0.4% | 0.2% | 0.2% |
| DIA-NN only | 143,379 | 90.8% | 3.9% | 3.3% | 2.0% |

- Same peak = DIA-NN's apex inside Osprey's chosen bounds, or Osprey's apex inside DIA-NN's. On those the
  apexes agree to a median 1.2 s (90% within 3.5 s). Wrong picks sit a median 0.34 min from DIA-NN's apex.
- Peak choice is ~7% of the DIA-NN-only set (plus 2% not scored). The other 91% Osprey scores at the right
  peak and rates weakly: their pass-1 q has median 0.043 (10% under 0.007), against 0.00015 for shared.
- They are low-abundance: median DIA-NN quantity 1.4e5 against 4.2e6 for shared (30x).
- Lead: Osprey's integration bounds are narrower than DIA-NN's on them - median 6.7 s vs 8.3 s, ratio
  osprey/DIA-NN 10th percentile 0.50 - while on shared precursors the widths nearly match (median ratio
  0.89). Narrow bounds on a weak peak would weaken the coelution features that look decoy-like there.

### 2026-10-28 - Planned

Branch and worktree created from origin/master 406fd374c0. Read the compaction gate
(`FirstPassFdrTask.cs:2597`), the second-pass modes (`docs/12-second-pass-fdr.md`) and #4823's
description; test-merged #4823 against master (one conflict).
