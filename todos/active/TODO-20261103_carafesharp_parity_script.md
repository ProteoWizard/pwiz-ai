# TODO-20261103_carafesharp_parity_script.md

## Branch Information
- **Branch**: `Skyline/work/20261103_carafesharp_parity_script`
- **Base**: `master` (049d045e98)
- **Created**: 2026-11-03
- **Status**: In Progress (PR open, master merged, awaiting the Perf/Regression gate and maccoss's review).
  **TF32 off shipped in this PR** (Brendan's decision 2026-11-04; agent D4): `TorchDevice.Resolve` turns
  off CUDA matmul and cuDNN TF32, so GPU prediction meets the CPU limits; the GPU gate is pinned only where
  a residual remains (Astral RT 2.34e-6, pin 3e-6; `carafe_main_varmod` .blib RT 7.4e-3 min, pin 9.3e-3).
  Cost 0.98-1.06x in a same-session A/B. **Decision for Brendan (conservative option taken):** fine-tuning
  keeps cuDNN TF32 (`TorchDevice.AllowTf32ForTraining`), because with it off the GPU fine-tune is not
  byte-repeatable (`TestRegressionSubsetRepeatsOnGpu` 0/4, HEAD 3/3) and TorchSharp 0.106 cannot set
  `cudnn.deterministic` (`use_deterministic_algorithms` is `[Obsolete("not implemented")]`). Turning TF32
  off for training too needs a deterministic-cuDNN setter (a TorchSharp upgrade or a native call).
- **GitHub Issue**: [#4978](https://github.com/ProteoWizard/pwiz/issues/4978)
- **Module**: `osprey`
- **PR**: [#4982](https://github.com/ProteoWizard/pwiz/pull/4982)
- **Worktree**: `C:\proj\wt-carafe` (night-session agent worktree, round 2 wave D)

## Objective

Per Brendan's decision on #4978 (2026-11-03): the eight full-size CarafeSharp parity tests leave the
per-commit unit pass and become a developer-run parity script, like Osprey's cross-implementation
comparison; the committed subset twins stay as the unit tests; `tcregression.ps1` stops running them; the
per-commit pass reads `Passed 108` with nothing skipped.

## Design (as built)

- The comparisons stay C# test methods (they are the only implementation of the checks), tagged
  `TestCategory("FullParity")` (`TestData.FULL_PARITY_CATEGORY`), the same mechanism as the existing
  `Astral` full-size tests. `build.ps1`'s default CPU filter adds `TestCategory!=FullParity`, so no test
  pass runs them.
- `pwiz_tools/CarafeSharp/scripts/Compare-CarafeParity.ps1 [-Dataset Stellar|Astral|All] [-TestName] [-NoBuild]`
  calls `build.ps1 -TestCategory FullParity|Astral -RequireData -TestData Fetch -TestDataPackage <ids>`,
  then reads the trx and prints one line per comparison (outcome, time, first lines of a failure
  message) and `OVERALL: PASS/FAIL`, exit 0/1. Packages: Stellar `testfiles,export`; Astral `astral`
  (TestData.cs: the Astral items read only that package).
- **Location: `pwiz_tools/CarafeSharp/scripts`, not `ai/scripts/CarafeSharp`.** The in-tree `scripts/`
  folder holds what CarafeSharp's own entry points use (`TestData.ps1`, which `build.ps1`,
  `regression.ps1` and `tcregression.ps1` dot-source), and the script is a peer of `regression.ps1`: it
  needs no machine paths, only `build.ps1` and `testdata.json`, versions with the tests it runs, and is
  documented in the in-tree `docs/04-testing.md`. `ai/scripts/CarafeSharp` holds tooling that wraps the
  tree for our workflow (CRLF + inspection, package building, the workflow on machine data). A developer
  without pwiz-ai (Mike's Linux box) can run it.
- `tcregression.ps1` step 1 is now `build.ps1 -NoTests -TestData Fetch -TestDataPackage testfiles,regression-export`
  (the packages `regression.ps1 -Dataset Stellar` reads: FASTA + pairing manifest, and the v2 export);
  steps 2-3 (Stellar golden, StellarSubset repeat) unchanged. Its `Perftests\carafesharp` data folder is
  kept so the agent does not re-fetch.
- `testdata.json` package categories left as they were: `-TestData Fetch` with no category still fetches
  the Stellar packages, which `regression.ps1` needs; the doc now says the default pass reads none.
- Side fix: `CarafeSharp.Models/PeptdeepConstants.cs` had a redundant `using System.Collections.Generic`
  (from #4927) that failed CarafeSharp's ReSharper inspection on master.

## Tasks

- [x] Tag the eight; exclude the category in build.ps1
- [x] Script; docs/04-testing.md ("Full-size parity" section, test-pass and CI tables); tcregression.ps1;
      tcbuild.bat / tctest.bat comments
- [x] Gates (below)
- [x] /code-review medium (triage below)
- [x] PR #4982 (reviewer maccoss); commits ed0eb8892a, 5e23704f08

## Gate evidence

- `Build-CarafeSharp.ps1 -SourceRoot C:\proj\wt-carafe -RunTests -RunInspection -RequireData`:
  `Test outcomes: Passed 108`, inspection zero issues. Log `C:\proj\ai\.tmp\agentD-carafe-build.log`.
- `Compare-CarafeParity.ps1 -NoBuild` (fetched both packages, first time on this machine): 8/8 Passed,
  wall 5:36 incl. fetch, `OVERALL: PASS`. Log `C:\proj\ai\.tmp\agentD-parity-stellar.log`.
  Failure path: `-TestName NoSuchTest` -> `OVERALL: FAIL - Stellar: build.ps1 exited 1`.
- New tcregression step 1 run locally: fetched `carafesharp-testfiles-v1, carafesharp-export-v2`, built.
  Log `C:\proj\ai\.tmp\agentD-tcreg-step1.log`. Steps 2-3 unchanged, not re-run locally.
- Osprey pre-commit (`Build-Osprey.ps1 -SourceRoot C:\proj\wt-carafe -Configuration Debug -RunTests -RunInspection`):
  649 tests, inspection clean. Log `C:\proj\ai\.tmp\agentD-osprey-precommit.log`.
- No regression golden can move: no product code changed.

## Code review (/code-review medium, 8 findings)

Fixed (`5e23704f08`): (1) the script built inside the first dataset's call and set "built" even when that
failed, so `-Dataset All` could run Astral on stale binaries - now builds once up front with
`build.ps1 -NoTests` and stops on failure; (2) `-TestName` with `-Dataset All` failed the leg the name does
not exist in - now refused; (3) `[TimeSpan]::Parse` on a missing trx `duration` - guarded; (4) build.ps1's
fetch example said "regression.ps1 reads them" of a set that also holds export-v1 - reworded;
(5) `ai/scripts/CarafeSharp/Build-CarafeSharp.ps1`'s `-TestData Fetch ... -RequireData` example implied the
default pass reads the packages - split into a default example and a `-TestCategory FullParity` one.
Re-ran: `-Dataset All -TestName Masking` -> FAIL exit 1 with the message; full run (with build) 8/8 PASS,
3:51, log `C:\proj\ai\.tmp\agentD-parity-stellar2.log`.

Dropped: `Measure-CumulativeCoverage.ps1`'s "with data" leg no longer includes FullParity - a measurement
tool, its numbers are documented as pre-change, listed under decisions below; trx parsing duplicated from
build.ps1 / hardcoded trx name - a renamed trx surfaces as "no test results" and FAIL, not silently; the
separate `Perftests\carafesharp` folder on the agent - kept deliberately so the agent does not re-fetch 1.5 GB.

## Decisions Brendan might revisit

- The comparisons are still `[TestMethod]`s in `CarafeSharp.Test`, now in a category no pass runs, rather
  than code moved out of the test assembly; moving them would mean shipping test-only comparison code
  in a product assembly or a second test project for no gain.
- `-Dataset Astral` folds the four existing `Astral`-category tests into the same script (they were
  already developer-run via `build.ps1 -TestCategory Astral`).
- `ai/scripts/CarafeSharp/Measure-CumulativeCoverage.ps1`'s "with data" leg (`build.ps1 -Coverage -RequireData`)
  no longer includes the full-size tests; the doc's coverage table notes it was measured before. Not changed.

## Follow-ups (Brendan's review, 2026-11-03)

1. **GPU backend** (`5e337927b0`): `Compare-CarafeParity.ps1 -Torch cpu|cuda` (build.ps1's parameter name).
   The comparisons hard-coded the CPU (`CarafeReferenceRun.Settings.Device = "cpu"`, `CPU` in
   `CarafeParityTest` / `CarafeFineTuneParityTest`), so a CUDA build alone would have run them on the CPU.
   New `TestData.ComparisonDeviceName` / `ComparisonDevice`: GPU when `CARAFESHARP_REQUIRE_CUDA=1` (which
   `build.ps1 -Torch cuda` already sets), failing on fallback; else CPU. Results kept as
   `TestResults/CarafeParity-<Dataset>-<cpu|cuda>.trx`; header and each row name the backend.
   No-GPU path: build.ps1's nvidia-smi preflight, then per test `Assert.Fail("No CUDA device ...
   (CARAFESHARP_REQUIRE_CUDA=1: the comparison must run on the GPU)")`, checked with
   `CUDA_VISIBLE_DEVICES=-1` (log `C:\proj\ai\.tmp\agentD2-parity-nogpu.log`).
   **Bit-for-bit vs tolerance:** neither. Carafe's references were written on CUDA (torch 2.5.1) but no
   backend reproduces them bit for bit; the CPU passes the existing tolerances; CUDA does not for RT.
2. **Astral run here** (first time; fetch 4.8 GB at ~60 MB/s, log `C:\proj\ai\.tmp\agentD2-astral-fetch.log`).
   The documented "about 12 minutes" was never measured; measured ~4 min of tests, doc corrected.
3. **Surfaced**: `osprey-development` SKILL.md (bullet after the Rust parity gate), and
   `ai/docs/osprey-library-generation-guide.md` (GPU section). `ai/scripts/CarafeSharp` has no README, so
   nothing there. `docs/04-testing.md` stays authoritative and now holds the CPU/CUDA table.

### Results (RTX 4000 Ada, driver 596.71; i9-14900)

| Run | Outcome | Wall | Log |
|---|---|---|---|
| Stellar + Astral, CPU (with build) | 12/12 PASS | 5:39 | `C:\proj\ai\.tmp\agentD2-parity-all-cpu.log` |
| Stellar, CUDA (with CUDA build, overlapped the Astral extract) | 6/8 | 4:37 | `C:\proj\ai\.tmp\agentD2-parity-stellar-cuda.log` |
| Stellar, CUDA, -NoBuild, quiet machine | 6/8 | 1:10 | `C:\proj\ai\.tmp\agentD2-parity-stellar-cuda2.log` |
| Astral, CUDA (with build) | 2/4 | 2:36 | `C:\proj\ai\.tmp\agentD2-parity-astral-cuda.log` |
| Stellar, CUDA, `NVIDIA_TF32_OVERRIDE=0`, `-TestName Predict` | 1/2 | - | `C:\proj\ai\.tmp\agentD2-parity-stellar-cuda-notf32.log` |
| Astral, CUDA, `NVIDIA_TF32_OVERRIDE=0` | 3/4 | 4:03 | `C:\proj\ai\.tmp\agentD2-parity-astral-cuda-notf32.log` |

Per-comparison CPU times: Stellar PeptideForms 7.5s, FragmentMz 5.2s, LibraryAssembly 12.1s, PredictedLibrary
42.3s, Predictions 8.5s, FineTune 2.9s, FullFastaBuilds 32.3s, Masking 1.1s; Astral FastaBuilds 18.3s,
FineTune 1.8s, Library 198.3s, Predictions 1.8s. CUDA (quiet run): the same six pass in similar times
(FullFastaBuilds 31.4s, Assembly 16.0s); Predictions and PredictedLibrary fail in 1-4 s on the first folder.
trx copies: `C:\proj\ai\.tmp\agentD2-CarafeParity-*.trx`.

CUDA failures (limits unchanged): Stellar RT 1.0e-4 rt_norm (limit 2e-6), library TSV RT 0.04 min (0.011);
Astral RT 1.3e-4, library TSV RT 0.10. MS2 is fine on CUDA (1.7e-6 - 6.1e-6, limit 1.5e-5). With TF32 off:
Stellar RT 1.6e-6 (passes), Stellar .blib RT 7.4e-3 (limit 1e-3, fails; CPU 3.2e-4), Astral RT 2.3e-6 (fails
by a hair), Astral library passes. So TF32 (libtorch's default for cuDNN conv/LSTM on Ampere+) explains
most of the RT gap; plain GPU rounding the rest.

### Code review of the follow-up (/code-review medium, 8 findings)

Fixed: (1) `CarafeReferenceRun` resolved the GPU in its constructor, so with no usable GPU the
comparisons that never predict (peptidoforms, m/z, assembly, masking) failed with the GPU message -
it is CPU again and `CheckPredictedLibrary` sets `TestData.ComparisonDeviceName` itself; (2) the kept
`CarafeParity-<Dataset>-<torch>.trx` survived a run that wrote none - now removed before each leg;
(3) the backend label named nvidia-smi's first GPU whatever `CUDA_VISIBLE_DEVICES` says - the label now
carries the variable (build.ps1's own preflight has the same first-GPU limitation).

Dropped: `CARAFESHARP_REQUIRE_CUDA=1` left in a developer's shell sends a CPU pass's prediction twins to
the GPU - the variable is build.ps1's, documented as "the GPU is required", and the failure message names
it; CUDA mode always fails so its exit code is not a gate - that is the recorded decision for Brendan, not
something to fix by loosening; `ComparisonDevice` probes CUDA on each access - microseconds against
seconds-long comparisons; the GPU-required check duplicates `CudaDeviceTest`'s - that one is inconclusive
without the variable, a different policy; the fine-tune reload's 1e-6 cosine on the GPU may be
nondeterministic - runs only with `CARAFESHARP_FINETUNE_FULL=1`, never from the script, and the GPU
fine-tune is already shown byte-repeatable by `TestRegressionSubsetRepeatsOnGpu`.

## Progress Log

### 2026-11-03 (night session, agent D)
- Built, gated and committed `ed0eb8892a`; code review and PR follow.
- Follow-ups (agent D2): `5e337927b0` (-Torch backend), `819b195ddc` (review fixes). After the fixes:
  no usable GPU (`CUDA_VISIBLE_DEVICES=-1`) fails only the three GPU comparisons, 5/8 pass
  (`C:\proj\ai\.tmp\agentD2-parity-nogpu2.log`); CUDA 6/8 as before (`agentD2-parity-stellar-cuda3.log`);
  CPU 8/8 (`agentD2-parity-stellar-cpu3.log`). CarafeSharp default pass `Passed 108`, inspection clean
  (`C:\proj\ai\.tmp\agentD2-carafe-build2.log`; one earlier attempt crashed inside InspectCode with an
  internal CLR error, rerun clean); Osprey pre-commit 649 tests, inspection clean
  (`C:\proj\ai\.tmp\agentD2-osprey-precommit.log`).

### 2026-11-04 (agent D3: master merge)
- `397e48f050` merged origin/master. One conflict, `pwiz_tools/Osprey/tcbuild.bat`, in the CarafeSharp
  step: this branch had only reworded its comment, #4995 (merged) had added
  `-BuildWarningsPath "%BUILD_WARNINGS%"` and the `RESULT` bookkeeping. Kept this branch's comment and
  #4995's two lines unchanged. `CarafeSharp/build.ps1` auto-merged (the FullParity exclusion and #4995's
  `-BuildWarningsPath` parameter touch different hunks).
- Gates on the merge: `Build-CarafeSharp.ps1 -RunTests -RunInspection` every test in the default pass
  passed (108, none skipped or inconclusive), 0 compiler warnings, inspection clean
  (`C:\proj\ai\.tmp\agentD3-carafe-build.log`); Osprey pre-commit 652 passed, inspection clean
  (`agentD3-osprey-precommit.log`); `Compare-CarafeParity.ps1` (with build, CPU) Stellar 8/8 PASS, 1:56
  (`agentD3-parity-stellar-cpu.log`); local `tcbuild.bat` (no vendor, coverage on because
  tc-is-default-branch saw no TeamCity branch) exit 0: clean, Osprey 652 and CarafeSharp 108 tests,
  installers, "No build warnings and no inspections at WARNING or above" (`agentD3-tcbuild.log`).
- PR #4918 adds a test to the default pass (109): counts are stated as "every test passes" from here on.

### 2026-11-04 (agent D3: pinned GPU gate, Brendan's decision)
- `7b870207a4`: new `CarafeSharp.Test/GpuParity.cs`. On CUDA each prediction comparison (Stellar/Astral
  predictions and predicted library) predicts twice in-process and requires bit-identical RT/MS2 values
  (library: TSV SHA-256), and compares with the previous run's outputs in
  `TestResults/CarafeParity-Outputs-cuda-<GPU>-<driver>[-tf32off]` (saved only after the comparison passes).
  RT/iRT (predictions, per dataset) and TSV/.blib RT (library, per reference folder) get pinned GPU limits,
  ~1.25x the measured value; MS2 keeps the CPU limits. Each pinned value prints as `GPU pinned: ...` and the
  OVERALL line says `PASS (GPU pinned: RT differs from Carafe beyond the CPU limits by up to ...)`.
  `docs/04-testing.md` has the CPU / CUDA / TF32-off table and the "GPU parity" paragraph.
- Measured (RTX 4000 Ada, 596.71; log `C:\proj\ai\.tmp\agentD3-gpu-measure.log`): Stellar RT 1.02e-4, iRT
  1.46e-2; Astral RT 1.33e-4, iRT 2.09e-2; library TSV RT 0.04 (Stellar initial), 0.77 (`carafe_main_varmod`,
  .blib 0.764), 0.03-0.04 (m3 refs), 0.10 (Astral). The varmod 0.77 min was not seen before (earlier runs
  stopped at the first failing folder). Nondeterminism: none, 19/19 repeats bit-identical in-process and
  across 7 runs, so no cudnn deterministic setting was needed.
- TF32 timing, same build, on/off/on/off, -Dataset All (logs `agentD3-gpu-tf32{on,off}-{1,2}.log`, trx
  `agentD3-CarafeParity-*-cuda-{on,off}{1,2}.trx`, script `.tmp/sessions/20261104-agentD3/timing.py`):
  Stellar predictions 4.7/4.1 s on vs 4.8/4.5 off (1.05); Stellar predicted library 39.5/32.7 vs 36.5/32.9
  (0.96; GPU library prediction 54.3 vs 52.1 s); Astral predictions 1.2/1.2 vs 1.1/1.3 (1.03); Astral library
  206.9/171.2 vs 161.6/180.8 (0.91; prediction 66.6 vs 61.2 s). TF32 off is free within noise. TF32 off:
  RT 1.6e-6 / 2.3e-6 (Astral just over 2e-6), iRT <= 3.9e-4, TSV 0.01, .blib up to 7.4e-3 (varmod).
- /code-review medium, 10 findings. Fixed: baseline folder keyed by GPU+driver (a driver update would fail
  every repeat check); baseline saved only after the comparison passes (a failing first run became the
  baseline); subset runs get their own keys; OVERALL wording (deltas are from Carafe, not from the CPU);
  dropped the redundant MS2 pin fields. Dropped: per-machine pins / fix TF32 instead (Brendan's decision is to
  pin; TF32-off recorded above for him); varmod pin 0.95 too wide (it is 1.25x the measured 0.77, still fails
  on growth); .blib not repeat-checked (TSV carries the same predictions); doubled GPU runtime (the spec asks
  for two predictions; CUDA wall 4:26 for both datasets); `IsGpu` re-probing and a third SHA-256 helper
  (microseconds; the existing ones are private/internal).
- Brendan merged master (#4918, CUDA allocator) into the branch meanwhile; merged it (`68dba733a4`). Gates
  after it: CarafeSharp default pass 109 passed, 0 warnings, inspection clean
  (`agentD3-carafe-build-post4918.log`); CUDA All 12/12, 19/19 repeats bit-identical against the saved outputs
  (`agentD3-parity-cuda-post4918.log`); CPU All 12/12 (`agentD3-parity-cpu-post4918.log`); Osprey pre-commit
  652, inspection clean (`agentD3-osprey-precommit-post4918.log`).
- Also updated `osprey-development` SKILL.md and `osprey-library-generation-guide.md` (CUDA no longer "fails").

### 2026-11-04 (agent D4: TF32 off, Brendan's decision)
- `386715744d` (pushed): everything below.
- `TorchDevice.DisableTf32` (called in `Resolve` once CUDA is known to be there, beside #4918's allocator setup):
  `torch.backends.cuda.matmul.allow_tf32 = false` and `torch.backends.cudnn.allow_tf32 = false`; both setters
  exist in TorchSharp 0.106 (libtorch's matmul default is already off, so cuDNN is the one that matters).
  `NVIDIA_TF32_OVERRIDE` handling removed from the script and `GpuParity`; the outputs folder lost its `-tf32off`
  suffix (a folder saved before the change holds TF32 outputs: delete it, as the doc says).
- Measured (logs `C:\proj\ai\.tmp\agentD4-gpu-tf32code-{1,2,3}.log`, CPU `agentD4-cpu-1.log`): CUDA 12/12, 19/19
  repeats bit-identical in every run AND identical to D3's `NVIDIA_TF32_OVERRIDE=0` outputs (seeded as the baseline),
  so code-off == env-off. TF32 off: Stellar RT 1.55e-6, iRT 2.7e-4; Astral RT 2.34e-6, iRT 3.9e-4; MS2 <= 6.1e-6;
  TSV 0.01 everywhere; .blib 7.40e-3 (varmod), 9.4e-4 / 7.0e-4 (m3). CPU 12/12.
- Pins: Stellar RT/iRT, Astral iRT, all TSV and the m3 .blib now use the CPU limits; kept Astral RT pin 3e-6 and
  varmod .blib pin 9.3e-3 (~1.25x), comments give value, date, GPU.
- Cost: the first runs looked 8-12% slower than D3's TF32-on runs, but the non-GPU comparisons in them were ~40%
  slower too (the machine, not TF32). Same-session A/B (HEAD build vs this change, 2 runs each, logs
  `agentD4-ab-tf32{on,off}-{1,2}.log`, script `.tmp/sessions/20261104-agentD4/ab.sh`): 0.98-1.06 per comparison,
  library prediction 0.99 / 1.00. The TF32-on leg also reproduced D3's TF32 baseline bit for bit. The off leg
  verified the new pins (PASS, pinned lines as above).
- **Found by the CUDA category gate**: with cuDNN TF32 off, `TestRegressionSubsetRepeatsOnGpu` failed 4/4 (the two
  GPU fine-tunes' rt.safetensors differ; golden tolerances still pass); HEAD passed 3/3 (`agentD4-gpurepeat.log`).
  TorchSharp 0.106 exposes no `cudnn.deterministic`, and `use_deterministic_algorithms` is
  `[Obsolete("not implemented")]` (CS0619). Conservative fix: `TorchDevice.AllowTf32ForTraining` re-allows cuDNN
  TF32 for the duration of `FineTuneRun.Run` and turns it off after, so training is exactly as before (byte-repeatable)
  and prediction is float32. After it: CUDA category 3/3 passed (`agentD4-cuda-category-fix-{1,2,3}.log`), CUDA
  parity All 12/12 (`agentD4-gpu-final.log`).
- Gates: CarafeSharp default pass 109 passed, 0 warnings, inspection clean (`agentD4-carafe-build2.log`); Osprey
  pre-commit 652 passed, inspection clean (`agentD4-osprey-precommit2.log`).
- /code-review medium (8 findings, before the training fix). Fixed: the GPU fine-tune regression concern (found
  independently by the gate, fixed above); ChronologerModel's comment restated as the current reason. Dropped:
  stale TF32 baselines in an unsuffixed outputs folder (only this machine ever saved one, re-seeded; the doc says to
  delete it); Stellar RT headroom 1.29x on other GPUs (pins are per-machine measurements by design; the CPU limit is
  the goal); TF32 flags process-wide / paths not through Resolve (every product path resolves through `Resolve`, and
  training sets and restores its own); the flag-readback test (the parity script is the behavioral check; the
  readback catches a setter becoming a no-op in name); pins equal to the CPU limits (`GpuPins` needs both values,
  spelled as the CPU constants); OVERALL wording and the dropped TF32 label (both pinned values are RT; no TF32 mode
  remains to label).
- Second /code-review medium (after the training fix; triage only, bar raised to shipped defects). Fixed (comments
  only, CarafeSharp gate re-run: 109 passed, 0 warnings, inspection clean, `agentD4-carafe-build3.log`): training's
  TF32 scope also covers its calibration/metric predictions (stated; that is the pre-change behavior, kept on
  purpose); `NVIDIA_TF32_OVERRIDE=0` would now also turn off training's TF32 (stated in TorchDevice and the script).
  Dropped: stale baseline folder and per-machine headroom (as above); process-wide flag / nesting (no concurrent or
  nested training in any host; Dispose restores the product policy, off); `GpuPins` equal to the CPU limits print a
  "GPU pinned" line before failing (failure path only, still fails); `using (null)` on the CPU (idiomatic).
- Also updated `osprey-development` SKILL.md and `osprey-library-generation-guide.md` (TF32 off, two pinned residuals).
