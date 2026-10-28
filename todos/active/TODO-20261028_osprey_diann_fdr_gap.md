# TODO-20261028_osprey_diann_fdr_gap.md

## Branch Information
- **Branch**: `Skyline/work/20261028_osprey_diann_fdr_gap` (local only, no commits yet), cut from
  `origin/master` at 406fd374c0 (2026-10-28), which holds all of Brendan's Osprey work to date,
  including the one-command CarafeSharp library build (#4876, #4885) and the `.model.zip` rename (#4895)
- **Checkout**: `D:\Dev\pwiz-osprey-fdr` (new worktree)
- **Base**: `master`
- **Created**: 2026-10-28
- **Status**: Planned. The plan is below; nothing has been run yet
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

## Progress Log

### 2026-10-28 - Planned

Branch and worktree created from origin/master 406fd374c0. Read the compaction gate
(`FirstPassFdrTask.cs:2597`), the second-pass modes (`docs/12-second-pass-fdr.md`) and #4823's
description; test-merged #4823 against master (one conflict).
