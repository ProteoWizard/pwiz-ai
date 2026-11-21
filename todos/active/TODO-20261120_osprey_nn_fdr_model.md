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

## Result: the network loses to the trees; branch discarded

All arms on identical inputs: 82-file SEA-AD, FirstPassFDR onward resumed from one scoring
(`D:\Users\brendanx\test\osprey-runs\sea-ad\runs-directread82\...-defaultdirectwritecache`), protein-best on,
exe `_bin\nnfdr`. Pass 1 counts are the October `plot_entrapment` view against DIA-NN 2.7 on its own first pass
(`D:\Users\brendanx\test\diann-vs-osprey\seaad\cmp82-fp-pass1-<tag>\plot.log`).

| Model | Precursors at 1% | vs GBDT | Pass 1 at FDP 0.5% (DIA-NN 99,548) | at FDP 1% (DIA-NN 107,129) | FirstPassFDR |
|---|---|---|---|---|---|
| GBDT (shipped HRAM default) | 97,191 | - | 94,007 (-5.6%) | 100,174 (-6.5%) | 1,727-1,780 s |
| NN, q-value labels | 90,703 | -6.7% | 87,830 (-11.8%) | 93,979 (-12.3%) | 5,742 s |
| NN, all-targets labels (DIA-NN's) | 88,219 | -9.2% | 84,547 (-15.1%) | 91,987 (-14.1%) | 5,808 s |
| Linear SVM | 83,753 | -13.8% | 80,575 (-19.1%) | 86,202 (-19.5%) | 2,300 s |

GBDT is +16.0% over the SVM at 82 files; the network (+8.3% over the SVM) recovers about half of that
(6,950 of 13,438 precursors). SVM arm: `runs-nn82\...-defaultsvm`, other users peaked at 2.3 logical processors;
its stage times shared the machine with the TDP-43 runs.

All of these use the default 70 of 109 features (`FDR features: default (70 of 109, ...)` in each run.log; 71 in the
second round with the protein-best column). The verdict is for that feature set; all 109 is untested for any model.

**Where GBDT stood against the SVM before tonight** (no 82-file SVM record exists: the 11-08 `svm82` run never got
past reading the candidate peaks, `runs-pb\svm82-off.out`):
- 62 files, first pass, protein-best off, 11-08 features (`TODO-20261030_osprey_scoring_library.md`, "Osprey SVM,
  62 files"): SVM 70,900 vs GBDT 84,576 targets at q 1%; at on-target FDP 1%, 76,722 vs 87,738 (SVM -12.6%).
- 3 matched files, protein-best on (same TODO, "Matched 3 files"): at FDP 1%, SVM 65,753 vs GBDT 74,378 (GBDT +13%).
- So GBDT was worth roughly 13-14% over the SVM, more than the 5% recalled; tonight's 82-file arm puts it at 16%.

**Earlier network results agreed.** Offline classifier bench (`TODO-20261030_osprey_scoring_library-phase1.md`,
2026-10-31 and 11-01, session agents): a bagged sklearn MLP near the SVM (41,673 vs GBDT 45,850); later, on all rows,
a torch MLP at 51,959 vs xgboost 52.2k, and all-vs-all labels hurt there too (46,800). Tonight's in-pipeline result
repeats both: no gain from the network, and DIA-NN's labelling costs more.

**History of the trees.** Mike contributed the GBDT, after a Noble-lab graduate student's success with boosted trees
for DDA spectrum matching (Brendan, 2026-11-21).

**Disposition.** The branch (`3309785f9d`, never pushed) is discarded. Levers nobody tested, if anyone returns:
per-file feature standardisation, a wider first layer, more epochs, scoring only rows above an SVM floor. The FDR
gap to DIA-NN is not a classifier-strength problem on these features (the same conclusion as 10-31).

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

### 2026-11-21 night - nn arm: 6.7% fewer than GBDT, first pass 3.2x slower

82-file SEA-AD, resumed from FirstPassFDR on the same scoring (`runs-nn82\...-defaultnn` vs
`runs-directread82\...-defaultdirectwritecache`). Machine quiet: other users peaked at 1.7 logical processors
(services, 25 samples, `ai/.tmp/sessions/20261120-nnfdr/load-nn.log`).

| | GBDT | nn | nn vs GBDT |
|---|---|---|---|
| Precursors at 1% (Osprey) | 97,191 | 90,703 | -6.7% |
| Pass 1 at FDP 0.5% (vs DIA-NN 99,548) | 94,007 (-5.6%) | 87,830 (-11.8%) | -6.6% |
| Pass 1 at FDP 1% (vs DIA-NN 107,129) | 100,174 (-6.5%) | 93,979 (-12.3%) | -6.2% |
| FirstPassFDR | 1,780 s | 5,742 s | 3.2x |
| PerFileRescoring / SecondPassFDR | 1,722 / 136 s | 1,843 / 128 s | |

- The SVM folds behave alike (iteration 1 at 49.9% vs 45.3% of training targets). The network costs 59 s of
  training against 10 s for the trees; the rest of the 3,960 s is scoring 359M candidate peaks through 12 networks.
- As implemented (DIA-NN 1.7's 25-20-15-10-5 tanh MLP bag, decoy-vs-target-at-q labels), the network is worse
  than the trees on both counts. nnalltargets (DIA-NN's labelling) and a GBDT resume control follow.
- Comparison: `D:\Users\brendanx\test\diann-vs-osprey\seaad\cmp82-fp-pass1-nn\plot.log`.

### 2026-11-21 night - nnalltargets arm: DIA-NN's labelling is worse again

Same resume (`runs-nn82\...-defaultnnalltargets`, `OSPREY_NN_ALL_TARGETS=1`); other users peaked at 2.0 logical
processors (services, 25 samples, `load-nnalltargets.log`).

| | GBDT | nn | nnalltargets |
|---|---|---|---|
| Precursors at 1% | 97,191 | 90,703 | 88,219 (-9.2% vs GBDT) |
| Pass 1 at FDP 0.5% (DIA-NN 99,548) | 94,007 | 87,830 | 84,547 (-15.1%) |
| Pass 1 at FDP 1% (DIA-NN 107,129) | 100,174 | 93,979 | 91,987 (-14.1%) |
| FirstPassFDR | 1,780 s | 5,742 s | 5,808 s |

- Training on every target as a positive (DIA-NN 1.7's labelling) costs a further 2.7% against our q-value labels.
  Neither network variant approaches the trees; the GBDT resume control is running.
- Comparison: `D:\Users\brendanx\test\diann-vs-osprey\seaad\cmp82-fp-pass1-nnalltargets\plot.log`.

### 2026-11-21 night - GBDT control reproduces the bed; verdict on the network

`runs-nn82\...-defaultgbdtresume` (same resume, trees) gives 97,191 precursors and the same pass 1 curve as the
write-cache bed (94,007 at FDP 0.5%, 100,174 at FDP 1%); FirstPassFDR 1,727 s vs the bed's 1,780 s. So the resume
path is exact and the nn losses are the model's, not the harness's.

**Verdict:** the DIA-NN 1.7 network does not help Osprey's first pass on SEA-AD at 82 files. With our labels it
loses 6.7% of precursors, with DIA-NN's all-targets labels 9.2%, and either costs about 66 extra minutes of first-pass
FDR. The code stays on the local branch (`3309785f9d`, unpushed) as an experiment; nothing to carry forward without a
variant that beats the trees. Untested levers, if anyone returns to it: features standardised per file rather than
experiment-wide, a wider first layer, more epochs, scoring only rows above an SVM floor.
- FDRBench outputs byte-identical to the bed: pass 1 sha256 `431e7bc040c7ed78...`, pass 2 `5811d02b0defd3f5...` in both.

### 2026-11-21 - TDP-43 (21 files) repeats the SEA-AD result

nn arm resumed from FirstPassFDR on the TDP-43 every-8th GBDT run (`tdp43\runs\...-defaultevery8-nn` vs
`...-defaultevery8-now`; 70 of 109 features), against the same DIA-NN 2.7 report:

| | GBDT | nn | nn vs GBDT |
|---|---|---|---|
| Precursors at 1% | 43,702 | 40,490 | -7.3% |
| Pass 1 at FDP 0.2% (DIA-NN 39,638) | 43,256 | 40,424 | -6.5% |
| Pass 1 at FDP 0.3% (DIA-NN 41,922) | 44,841 | 42,104 | -6.1% |
| FirstPassFDR | 563 s | 1,668 s | 3.0x |

The second dataset gives the same loss (6-7%) and the same 3x first-pass cost as SEA-AD. Stage times contended by the
82-file SVM arm. Outputs `ai/.tmp/sessions/20261120-nnfdr/cmp-tdp43-every8-nn-pass{1,2}.txt`.
