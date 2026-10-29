# TODO-20261028_osprey_diann_fdr_gap.md

## Branch Information
- **Branch**: `Skyline/work/20261028_osprey_diann_fdr_gap` (local, not pushed: d9ef469191 OSPREY_XIC_FRAGMENTS,
  31f24282b6 / 6ffe5333c4 / 087b2825d9 the new features + OSPREY_FEATURE_MASK), cut from
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
- [ ] Ablate with OSPREY_FEATURE_MASK: which of the 20 new features carry the gain (SVM weights say
      peak_spectrum_cosine_mean/sd, peak_candidate_count, context_precursor_mz, the intensity shares)
- [ ] Stellar check that 12 XICs + features + GBDT do not cost IDs where Osprey already leads
- [ ] Remaining gap (~25% at FDP 0.5%): further Radiant families (alt-charge features, amino-acid counts for
      GBDT), and the classifier (bagged NN like DIA-NN/Radiant)
- [ ] Fix `peak_spectrum_cosine_sd.IsReversedScore` (the data says higher is target-like)
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
