# TODO-20261120_osprey_nn_fdr_model.md

## Branch Information
- **Branch**: `Skyline/work/20261120_osprey_nn_fdr_model`
- **Base**: `master` (b3dcb52e07; #4950 has merged)
- **Worktree**: `D:\Users\brendanx\proj\pwiz-nnfdr` (MACS2)
- **Created**: 2026-11-20
- **Status**: In progress
- **PR**: (pending)
- **Module**: `osprey`
- **Objective**: Add a bagged feed-forward neural network as a third FDR model beside the linear SVM and GBDT, and measure it against GBDT on SEA-AD

## Goal

Osprey's FDR models are a linear SVM and gradient-boosted trees (`FdrClassifier` in
`Osprey.Core/OspreyConfig.cs`, GBDT in `Osprey.ML/GradientBoostedTrees.cs`). GBDT measured better than the SVM.
Nobody has measured a neural network. DIA-NN's classifier is a bagged neural network, and its open-source 1.7.12 release
shows what that network is. The network itself has probably not changed since the source closed (Brendan, 2026-11-20),
even though the FDR estimation around it has. The gap to DIA-NN at 82 SEA-AD files is about 4%, so even a 2% gain would
close half of it.

## The model to try (DIA-NN 1.7.12, public source, `src/diann.cpp`)

- 12 networks averaged (bagging). Each has 5 tanh hidden layers of widths 25, 20, 15, 10, 5 and a 2-class softmax,
  with cross-entropy loss.
- Adam (beta1 0.9, beta2 0.999), learning rate 0.003, batches of up to 50, 1 epoch, L2 regularization.
- Labels: every target is class 1 and every decoy class 0. This is a single pass, not Percolator's iterative selection
  of confident targets.
- By default it trains and scores on the same data (cross-validation is an option and off). **Osprey keeps
  cross-validation**: reuse the existing folds, which keep each target and its decoy together.

## Design

- Hand-written C# in `Osprey.ML` (a `NeuralNetClassifier` beside `GradientBoostedTrees`), NOT TorchSharp:
  - Output must be bit-identical across Windows, Linux and thread counts. CPU libtorch is not, because its matrix code
    splits work across threads and differs by platform. Use double precision, a fixed seed per network, serial
    arithmetic within a network, and parallelism only across the networks.
  - About 3,500 weights per network: TorchSharp's per-call overhead would dominate, and the search path would gain a
    native dependency.
  - TorchSharp (already used by CarafeSharp) may check the gradients in a unit test.
- Selected by `OSPREY_FDR_MODEL=nn`, as `gbdt` is; a command-line value only once it has proven itself.
- Two training setups to compare:
  - (a) the network in place of the SVM or GBDT inside the Percolator loop;
  - (b) DIA-NN style: one pass, all targets against all decoys, cross-validated.
- Features: Osprey's existing feature set, standardized. DIA-NN's ~110 features are a separate question.

## Validation

- Unit tests in `Osprey.Test` (MLTest): learns a separable toy problem, gives bit-identical output across thread
  counts, matches a TorchSharp reference.
- Regression tests should pass without change (the default model is unchanged).
- SEA-AD, 3 files then 82, against GBDT:
  - identifications at 1% precursor FDR;
  - FDRBench entrapment FDP;
  - wall time for both FDR passes.
- A default change needs an 82-file run of the combination that would ship.
- Log per-user CPU (`ai/scripts/Get-CpuByUser.ps1`) every 10 minutes for the whole length of every timing run.

## Progress Log

### 2026-11-20 - Planned

Planned with Brendan after reading DIA-NN 1.7.12's classifier (`NNClassifier`, `nnBagging`, `nnHidden` in `diann.cpp`).

### 2026-11-20 - First implementation (uncommitted, `pwiz-nnfdr`)

- `Osprey.ML/NeuralNetClassifier.cs` (+ `NnParams`, `NnModelData`) and `INonlinearFoldModel`, which `GradientBoostedTrees` now
  implements; the score paths, `PercolatorResults.FoldGbtModels` and the frozen scorer take the interface, so the network
  is trained and scored through the trees' per-fold path (`PercolatorConfig.UseGradientBoostedTrees` plus `UseNeuralNet`).
- Deterministic: double precision, `XorShift64` init (sum of 12 uniforms) and shuffle, tanh and sigmoid on
  `DeterministicMath.Exp`, Adam bias correction from running products (no `Math.Pow`), one thread per network.
- `OSPREY_FDR_MODEL=nn`; `OSPREY_NN_ALL_TARGETS`, `OSPREY_NN_BAGGING`, `OSPREY_NN_EPOCHS`, `OSPREY_NN_LEARNING_RATE`; the
  validity key carries every setting (`PercolatorEngine.NnValidityKeySuffix`); `FirstPassModelIO` persists `FoldNnModels`.
- Tests: `MLTest.TestNeuralNetClassifier` (learns, thread-count identical, persisted form identical, refuses bad input);
  `SubsetPipelineTest.TestSubsetOptionVariants` gains an nn leg, same blib on 1 and 4 threads. Both pass; FirstPassModelIoTest 8/8.
- Queued on MACS2 (`ai/.tmp/sessions/20261120-nnfdr/Chain-Nn82.ps1`): full Osprey tests + inspection, then three 82-file
  SEA-AD arms resumed from FirstPassFDR on the direct-read write-cache arm's scoring (`runs-nn82\...-defaultnn`,
  `-defaultnnalltargets`, `-defaultgbdtresume`), per-user CPU logged every 5 minutes.

### 2026-11-20 night - Committed; 82-file arms running

- First full gate failed on inspection: one `PossibleNullReferenceException` at `PercolatorEngine.cs:298`
  (`config.Scoring` where `config` may be null); fixed to `config?.Scoring.GbtOutOfFold ?? false`. Then Osprey tests
  672/672 and zero-warning inspection. Committed locally as `3309785f9d` on `Skyline/work/20261120_osprey_nn_fdr_model`
  (not pushed). Release snapshot with vendor readers: `D:\Users\brendanx\test\osprey-runs\_bin\nnfdr`.
- Arms started 23:00 (`runs-nn82\...-defaultnn`, then `-defaultnnalltargets`, `-defaultgbdtresume`), each resumed
  from FirstPassFDR on the write-cache arm's scoring (`runs-directread82\...-defaultdirectwritecache`, 97,191
  precursors, GBDT). The log confirms `classifier nn`.
- Reference for the comparison, the October `plot_entrapment` view against DIA-NN 2.7 (own library, first pass,
  `D:\Users\brendanx\test\diann-vs-osprey\seaad\cmp82-fp-pass1-now`): GBDT pass 1 94,007 vs 99,548 at FDP 0.5%
  (-5.6%), 100,174 vs 107,129 at FDP 1% (-6.5%). October's master was 43,675 (-56%).
- Timeline: `ai/.tmp/night-session-budget-20261120.md`.
