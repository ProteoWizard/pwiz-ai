# TODO-20260924_osprey_svm_c_selection.md

## Branch Information
- **Branch**: `Skyline/work/20260924_osprey_svm_c_selection`
- **Base**: `master` (83836d2827)
- **Created**: 2026-09-24
- **Status**: In Progress
- **Module**: `osprey`
- **PR**: (pending)
- **Worktree**: `D:\Dev\pwiz-osprey-csel`

## Objective

Stop Osprey's first-pass SVM regularization C from being chosen by noise. The C grid search keeps
the strict maximum of the inner-CV passing counts, but C = 0.1, 1 and 10 differ by 0.1-0.6% of the
targets on Stellar, so the pick flips on tiny input changes. It matters: weakly regularized C = 1
fits split weight between correlated spectral features (apex-scan `xcorr` / `median_polish_cosine`
vs multi-scan `sg_weighted_cosine`) in a way the second pass, which reuses the frozen first-pass
model on reconciled peaks, handles much worse.

## Findings (2026-09-23/24, while comparing CarafeSharp and Carafe libraries)

- Osprey is deterministic (a resumed rerun reproduced 21,176 exactly), but two Stellar libraries
  predicted from the same models on GPU and CPU (1e-4 rounding differences) gave 21,176 vs 28,309
  experiment precursors at the same FDRBench FDP. First-pass per-run counts agreed within 0.5%.
- Every low arm chose C = 1 in all folds; every high arm had a fold at C = 0.1. Forcing C = 0.1
  lifted the low arm to 30,679; forcing C = 1 on the high arm gave 27,605 (C = 1 has two
  solutions). Scoring one arm's reconciled entries with the other arm's model moved the
  reconciled targets at 1% from 20,301 to 24,738 on the same data.
- Regression gate 2026-09-23 (part-B build): Stellar chose C = 1,1,1 and got no second-pass lift.
- Retraining the second-pass model is NOT an option (removed in #4528: it leaks first-pass
  information and breaks FDR control). The developer does not want C fixed for all datasets.
- Diagnostic runs and scripts: `D:\test\osprey-runs\cdiag-*`, `ctol0.01-*`;
  `ai/.tmp/sessions/20260923-carafesharp/run-cdiag*.sh`, `run-ctol-datasets.sh`,
  `py/bimodal_models.py`, `py/stage6_arms.py`. Memory: `osprey-stage6-bimodal-ids`.

## Change

- `PercolatorTrainer.SelectC`: the smallest (most regularized) C whose inner-CV count is within
  `CSelectionTolerance` (default 0.01) of the best; 0 = the old strict maximum (Rust's rule).
- `PercolatorConfig.CSelectionTolerance`, carried by `CloneForTrainOnly` and the scorer's training
  config (`PercolatorScorer.BuildStreamingTrainConfig`); `OspreyEnvironment.SvmCSelectionTolerance` /
  `OSPREY_SVM_C_TOLERANCE` override in [0, 1). Anything else is a startup ERROR (Program.cs, beside
  the OSPREY_PASS2_QVALUE check); a set value is logged at startup, and the Stage 5 C line names the rule.
- First-pass training validity key gains `;csel=<tolerance>`, emitted for every setting (a flipped
  default), so older FirstPassFDR-and-later directories are not resumed.
- `PickLdaModel`: `System.Linq.Enumerable.SequenceEqual` qualified, the same hunk as #4588 on the
  .NET 10 branch; master's `string[].SequenceEqual` only compiled with C# 14 (first-class spans),
  so Osprey did not build with Visual Studio 2022's C# 13.
- Docs: `07-fdr-control.md` (C selection, relay caveat, parity-notes divergence entry),
  `20-command-line.md` (env var), `DIVERGENCES.md`, `Osprey-workflow.html`.
- `regression.ps1` clears (and restores) an inherited `OSPREY_SVM_C_TOLERANCE`. In pwiz-ai:
  `OspreyDatasetRun.psm1` strips it; the three `Compare/` cross-impl scripts set it to 0;
  `osprey-development-guide.md` grid_search_c note.

## Evidence with the rule (diagnostic build, resumed from the 2026-09-23 gate scores)

| Dataset | C, strict -> rule | Experiment precursors, strict -> rule |
|---|---|---|
| Stellar | 1,1,1 -> 0.01,0.1,0.1 | 27,321 -> 31,720 (+16.1%) |
| StellarLibDecoy | 0.1,1,1 -> 0.1,0.1,0.1 | 31,046 -> 31,392 (+1.1%) |
| StellarGenDecoyEntrap | 1,0.1,1 -> 0.1,0.1,0.1 | 29,953 -> 31,750 (+6.0%); FDRBench FDP 0.98% -> 1.04% combined, 0.91% -> 0.94% paired |
| Astral | 1,1,1 -> 0.1,0.1,1 | 117,265 -> 117,236 (-0.02%) |
| CarafeSharp pair (GPU / CPU library) | | 21,176 / 28,309 -> 30,316 / 30,485 |

## Gates

- [x] `Build-Osprey.ps1 -Configuration Debug -RunTests -RunInspection` (597 tests, 0 inspection issues;
      re-run after the review fixes, same)
- [x] `regression.ps1 -Dataset All -CreateGolden` (goldens change on every dataset; RefSpectra rows
      Stellar 27,321 -> 31,720, StellarLibDecoy 31,046 -> 31,392, StellarGenDecoyEntrap 29,953 -> 31,750,
      Astral 117,265 -> 117,236; entrap pass-2 experiment FDP 0.95% -> 1.02% combined, 0.95% -> 1.03%
      paired, ~160 entrapment hits, SE ~0.08 points)
- [ ] `regression.ps1 -Dataset All` against the new goldens (running; log
      `ai/.tmp/sessions/20260923-carafesharp/csel-regression-all.log`)
- [x] `/code-review max`: 15 findings; 12 fixed, 3 skipped (below)
- [ ] Perf gate (`Test-PerfGate.ps1 -Dataset Stellar`, uncontended machine)
- [ ] Rust counterpart in maccoss/osprey (cross-impl parity with OSPREY_SVM_C_TOLERANCE=0 meanwhile)
- [ ] TeamCity Perf/Regression only on the PR candidate, and only after asking

## Follow-ups (not in this PR)

- Pre-existing: `--fdr-method gbdt` on the default lean first-pass path trains the linear SVM
  (`PercolatorScorer.BuildStreamingTrainConfig` carries no tree settings; the streaming score passes
  are linear-only). Since #4446. Separate change.
- Relay nodes (`--task PerFileRescoring` / `SecondPassFDR`, `-LinkFrom`) key with their own
  environment's tolerance and do not check the one the persisted model was trained under (same gap
  as trainpick/maxtrain). Documented; a model-stamp check in `FirstPassModelIO` would close it.
- `;csel=` also keys gbdt/simple runs, where C is not selected: a one-time re-run of their FDR tail.
- Remaining input sensitivity: inner-CV folds are dealt by sorted position and re-dealt each
  iteration (`PercolatorSampling.cs`), and the best iteration is a strict maximum; a stable
  hash-based fold assignment would remove what the 1% band does not.
- Rust counterpart in maccoss/osprey.

## Progress Log

### 2026-09-24
- Root-caused the bimodal Stellar result, prototyped the rule behind env vars in the gate worktree
  (uncommitted there), implemented it on this branch, unit tests + validity-key test added.
- Goldens regenerated; `/code-review max` fixes applied; branch squashed to one commit (`f12bde87eb`).
