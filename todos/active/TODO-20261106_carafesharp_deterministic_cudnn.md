# TODO-20261106_carafesharp_deterministic_cudnn.md

## Branch Information
- **Branch**: `Skyline/work/20261106_carafesharp_deterministic_cudnn`
- **Base**: `master` (dd1ea43e89)
- **Created**: 2026-11-06
- **Status**: In Review - GPU experiment succeeded (outcome A); PR #5004 open, not merged, no TeamCity triggered. Decision taken
  conservatively: the deterministic setting is scoped to `FineTuneRun.Run` only (prediction is untouched), and
  a libtorch without the exports falls back to today's non-repeatable float32 training with a logged warning,
  rather than re-allowing TF32.
- **GitHub Issue**: (none - follow-up of #4978 / PR #4982)
- **Module**: `osprey`
- **PR**: [#5004](https://github.com/ProteoWizard/pwiz/pull/5004)
- **Worktree**: `C:\proj\wt-tf32`

## Objective

Make CarafeSharp's GPU fine-tuning repeatable byte for byte with TF32 OFF, so training is in float32 like
prediction (PR #4982 turned TF32 off for prediction; `FineTuneRun.Run` re-allowed cuDNN TF32 through
`TorchDevice.AllowTf32ForTraining` because float32 training did not repeat).

Investigation: `ai/.tmp/sessions/20261106-tf32/findings.md` (TorchSharp has no setter; `torch_cpu.dll`
exports `at::globalContext()` and `Context::setDeterministicCuDNN(bool)`).

## Tasks

- [x] Step 1: baseline 4x `TestRegressionSubsetRepeatsOnGpu` on master
- [x] Step 2: `LibTorchContext` (P/Invoke through `NativeLibrary.TryGetExport` + `delegate* unmanaged`) and
      `TorchDevice.DeterministicCuDnn` scope in `FineTuneRun.Run`; TF32 off for training; 4x repeat test
- [x] Steps 3-4 (setFloat32Precision bisection, CUBLAS_WORKSPACE_CONFIG): not needed
- [x] Delete `AllowTf32ForTraining`; unit test that the exports resolve (`TestLibTorchContextResolves`)
- [x] Docs: `docs/04-testing.md` GPU parity / Reproducibility; `osprey-library-generation-guide.md`
- [x] Gates: CPU default pass + inspection, CUDA category, `Compare-CarafeParity.ps1 -Torch cuda` (Stellar), Osprey build
- [x] `/code-review medium`
- [x] Commit 9259c43e64, PR #5004

## Progress Log

### 2026-11-06 - GPU experiment (RTX 4000 Ada, driver 596.71, libtorch 2.10.0)

Logs: `C:\proj\ai\.tmp\sessions\20261106-tf32\logs\<step>\`; CLI run folders `D:\test\carafe-tf32\`.

| Step | Config | Repeat test | CLI repeats | Time |
|---|---|---|---|---|
| 1 | master, TF32 on for training | 4/4 | Chronologer 2/2, LSTM 2/2 | test 80-91 s; fine-tune 36-38 s Chronologer, 43-44 s LSTM |
| 2 | TF32 off + deterministic cuDNN | 4/4 | Chronologer 2/2, LSTM 2/2 | test 63-65 s; fine-tune 32 s Chronologer, 40-42 s LSTM |
| control | TF32 off, no deterministic cuDNN | 0/2 (models differ) | - | 64-83 s |

- The repeat test's subset fine-tunes Chronologer (the default `-rt_model`, convolutions only); the findings
  note assumed the LSTM-CNN RT model. The CLI repeats (`Run-LstmRepeats.ps1 -RtModel alphapeptdeep`) cover
  the AlphaPeptDeep LSTM RT model too: it also repeats with TF32 off, so the cuDNN LSTM is not a source here.
- MS2 weights are the same bytes in every configuration (no cuDNN op in the BERT model); the RT weights
  change with TF32 off, as expected.
- Deterministic float32 training is not slower than TF32 training on this GPU (slightly faster).

### 2026-11-06 - Gates and review

Logs in `C:\proj\ai\.tmp\sessions\20261106-tf32\logs\`:
- `gate-cpu-default-2.log`: CPU default pass Passed 110 (incl. new `TestLibTorchContextResolves`), inspection 0 warnings.
- `gate-cuda-category.log`: Cuda category Passed 2 (`TestGpuPredictionsMatchCpu`, `TestRegressionSubsetRepeatsOnGpu`).
- `gate-parity-cuda-stellar.log`: `Compare-CarafeParity.ps1 -Torch cuda -Dataset Stellar` OVERALL PASS, 8/8, wall 2:06;
  the one GPU pin as before (.blib RT 7.4e-3 min, pin 9.3e-3); `TestFineTuneMatchesCarafe` passed on float32 training.
- `gate-osprey-build.log`: Osprey Debug build (hosts CarafeSharp.Models) clean.
- After the review fixes: `step2-final` repeat test 4/4 (64-66 s), `step2-final-cli-lstm` LSTM 4/4 identical
  (40-44 s fine-tune; 6/6 with step 2).

`/code-review medium`, 8 findings:
- Fixed: `DeterministicCuDnn` now calls `DisableTf32()` itself, so a CUDA device not from `Resolve` still trains in float32.
- Fixed: `LibTorchContext` resolves the exports once per process (`Lazy`), not one `NativeLibrary.TryLoad` per fine-tune.
- Fixed: 04-testing.md wrap; Compare-CarafeParity.ps1 comment names `DeterministicCuDnn`.
- Fixed (evidence): LSTM repeats raised from 2/2 to 6/6, docs updated.
- Dropped: saved GPU parity outputs keyed by GPU go stale - they hold predictions from the pretrained/Carafe
  models only; `CarafeFineTuneParityTest` saves nothing (`GpuParity` is used by CarafeParityTest and LibraryParityTest only).
- Dropped: fall back to TF32 when the exports are missing - the brief specifies a no-op with a logged warning;
  `TestLibTorchContextResolves` fails the default pass on a libtorch that renames them, before anyone ships it.
  Brendan may prefer the TF32 fallback; it is a two-line change.
- Dropped: test flips the global flag concurrently with a GPU fine-tune - CarafeSharp.Test does not parallelize.
- Dropped: macOS `.dylib` - CarafeSharp supports x64 Windows and Linux only (build.ps1).
