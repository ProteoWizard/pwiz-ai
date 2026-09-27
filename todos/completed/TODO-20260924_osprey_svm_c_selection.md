# TODO-20260924_osprey_svm_c_selection.md

## Branch Information
- **Branch**: `Skyline/work/20260924_osprey_svm_c_selection_port`
- **Base**: `Skyline/work/20260612_net8_port` (899f348f3d)
- **Created**: 2026-09-24
- **Status**: Completed
- **GitHub Issue**: [#4704](https://github.com/ProteoWizard/pwiz/issues/4704)
- **Module**: `osprey`
- **PR**: [#4703](https://github.com/ProteoWizard/pwiz/pull/4703) (merged 2026-09-27 as 3b8dd2f398), base `Skyline/work/20260612_net8_port`
  (branch `Skyline/work/20260924_osprey_svm_c_selection_port`). Replaces #4701, opened against master and
  closed: Osprey needs the .NET 10 port to read RAW files.
- **Rust PR**: [maccoss/osprey#69](https://github.com/maccoss/osprey/pull/69) (`feature/svm-c-selection-tolerance` @ `c1d039a`)
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
- [x] `regression.ps1 -Dataset All` against the new goldens, on the port branch (net10.0): PASSED, 43 phases,
      3.4 h (log `ai/.tmp/sessions/20260923-carafesharp/cselport-regression-all.log`)
- [x] `/code-review max`: 15 findings; 12 fixed, 3 skipped (below)
- [ ] Perf gate (`Test-PerfGate.ps1 -Dataset Stellar -BaselineRoot D:\Dev\pwiz-perfbase -BranchRoot D:\Dev\pwiz-osprey-csel`,
      baseline worktree at `899f348f3d`). Attempt 2026-09-24 stopped: other sessions' builds loaded the machine
      (a baseline run went 658 s -> 1,100 s). Needs a quiet machine.
- [x] Copilot review (2 threads) addressed in `f9aa0dd9f0`, replied and resolved.
- [x] Rust counterpart: maccoss/osprey#69 (`svm::select_c`, `PercolatorConfig::c_selection_tolerance`, no env
      opt-out, as #66). Cross-impl Stellar vs the port-branch C# at its default: #69 alone matches the whole
      first pass at 1e-9 (1,448,698 records) and the precursor count (31,720); #69 + maccoss/osprey#68 (open)
      is OVERALL PASS at 1e-9 end to end, on Stellar and on Astral (117,236 precursors both sides).
- [ ] When #69 merges: flip `Compare-EndToEnd-Crossimpl.ps1 -CsSvmCTolerance` default to '' and drop the
      `OSPREY_SVM_C_TOLERANCE=0` pins in `Compare-CrossImpl-Reference.ps1` / `Compare-EndToEnd-Bisect-Crossimpl.ps1`.
      Running the Rust exe outside cargo needs `%USERPROFILE%\vcpkg\installed\x64-windows\bin` (OpenBLAS) on PATH.
- [x] TeamCity Perf/Regression PASSED 2026-09-27 (triggered by Brendan). Review requested from Brendan (2026-09-25); he triggers the TeamCity Osprey Perf/Regression run - the developer (Mike) has no trigger access, so do not ask him to.

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

### 2026-09-26 - Review A/B at scale (Brendan's session)

Same build (f9aa0dd9f0) in every arm; "strict" = `OSPREY_SVM_C_TOLERANCE=0`. Library: the SEA-AD
08-17 rebuild (`sea-ad\lib\target+decoy+entrapment-20260817`). Runners: `Run-SeaAd.ps1`
(`-SvmCTolerance`, `-SvmCValues`, `-LinkFrom`) and `ai/scripts/Osprey/AstralEntrap/Run-AstralEntrap.ps1`.
Reader: `ai/scripts/Osprey/SEA-AD/tools/pass1_fdp.py`. Weights: `ai/.tmp/sessions/20260925-pr4703/compare_weights.py`.

**3-file Astral (regression HeLa files) x SEA-AD entrapment library** - neutral:

| Arm | Final C 1% / strict | Exp. @q=1% (true FDP) 1% vs strict | Matched 0.75% true FDP |
|---|---|---|---|
| LibDecoy pass 1 | 1,1,1 / 1,1,1 | 83,674 (0.760%) vs 83,836 (0.798%) | +0.1% |
| LibDecoy pass 2 | | 102,615 (0.461%) vs 102,133 (0.453%) | -0.4% |
| GenDecoy pass 1 | 0.1,1,1 / 1,1,1 | 92,951 (1.87%) vs 93,009 (1.90%) | +0.3% |
| GenDecoy pass 2 | | 108,539 (1.41%) vs 108,433 (1.44%) | +0.1% |

Scores differ even where the final C matches: `GridSearchC` runs on every training iteration.
Dirs: `D:\test\osprey-runs\astral-entrap-3file\runs\astral3-3files-{libdecoy,gendecoy}-r1.0-protein-compact[-csel0]-lib0817-pr4703`.

**82-file SEA-AD, library decoys** - three arms, experiment-level precursors at matched true FDP:

| Pass | True FDP | 1% rule (C 1,1,0.1) | Strict (C 100,1,0.1) | Fixed C = 0.1 (all folds) |
|---|---|---|---|---|
| 2 | 0.65% | 51,385 | 51,405 | 52,457 |
| 2 | 0.75% | 52,523 | 52,911 | 53,594 |
| 2 | 1.00% | 55,177 | 55,548 | 55,677 |
| 1 | 0.75% | 46,665 | 45,943 | 46,156 |
| 2 @q=1% | reported | 58,780 (1.44%) | 57,995 (1.37%) | 59,275 (1.52%) |

- The strict arm's pass 1 (45,943 at 0.7460%) reproduces the recorded pickrun3 baseline exactly.
- The 1% rule is neutral at scale (pass 2 0.0 to -0.7% vs strict): no harm, no gain.
- **Fixed C = 0.1 is best in pass 2 at matched FDP, +1.3-2.1% in the 0.65-0.75% range** - evidence for
  Mike's hypothesis that stronger regularization transfers better to reconciled pass-2 peaks. It needed
  an experimental `OSPREY_SVM_C_VALUES` override: local branch
  `Skyline/work/20260926_osprey_svm_c_values_override` in `C:\proj\pwiz-work1` (b749ba8f39, NOT pushed).
- Weights show the two solutions Mike described: C >= 1 folds put median-polish cosine at 2-3x the
  SG-weighted cosine; at C = 0.1 the two are about equal (fold 1: 0.39 vs 0.38).
- Inner-CV passing counts at SEA-AD are only ~1,200 of 150,050 training targets (0.5-0.8%), so the
  fixed 1% band is well inside noise at this scale.
- Dirs: `D:\test\osprey-runs\sea-ad\runs\seaad-82files-libdecoy-r1.0-protein-compact[-csel0|-cvals0.1]-lib0817-pr4703`.

Side finding: on 3-file Astral, generated decoys run at 1.4-1.9% true FDP at q=1% vs library decoys
at 0.46-0.76%.

**Open follow-ups from the review:**
- Fixed C = 0.1 (or a grid capped at C <= 1) deserves the same A/B on Astral 3-file and the Stellar legs
  before it is proposed as a default; the override branch above is the lever.
- A large Stellar cohort A/B once one can be searched (`OSPREY_SVM_C_TOLERANCE=0` vs default).
- The mitigation caveat: the underlying problem is the frozen first-pass model transferring poorly to
  reconciled pass-2 peaks.
- The gbdt lean-path branch conflicts with this change; resolve with `CloneForTrainOnly()` and move the
  two `BuildStreamingTrainConfig` assertions in `FdrTest.cs` to it.

### 2026-09-27 - Merged

PR #4703 merged as commit 3b8dd2f398 into `Skyline/work/20260612_net8_port` (Brendan approved and completed;
TeamCity Perf/Regression passed). Shipped the 1%-tolerance C selection, `OSPREY_SVM_C_TOLERANCE`, and the
regenerated goldens. Deferred: the perf gate on a quiet machine, the post-#69 cross-impl script flips, and
the follow-ups above.
