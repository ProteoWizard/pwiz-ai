# TODO-20260928_AlphaPeptDeepSharp.md

## Branch Information
- **Checkout**: `I:\git_i\sky_net10_alphapeptdeep`
- **Branch**: `Skyline/work/20260928_AlphaPeptDeepSharp` (pushed through e62d5693d2)
- **Base**: `master` (#4717 CarafeSharp squash-merged 2026-10-13 as 28c7b7ff03 and merged into this branch)
- **Created**: 2026-09-28
- **Status**: In Progress
- **Module**: `skyline` (also carries CarafeSharp changes Skyline needs; the developer chose to keep them here)
- **PR**: (none yet)

## Objective

Replace the Python AlphaPeptDeep (peptdeep 1.5.0 in an embedded Python that Skyline downloads and
installs) with CarafeSharp's C# TorchSharp port, shipped inside Skyline. Must work with and without an
NVIDIA GPU (CPU libtorch ships; the CUDA runtime downloads on demand). CCS is predicted with CarafeSharp's
port of the CCS model.

## Done

- [x] Parity check (temporary CarafeSharp test, not committed): CarafeSharp with peptdeep 1.5.0's
      library defaults (NCE 30, Lumos, b/y z1-z2 in m/z 200-2000, renormalize to the max kept ion,
      drop < 0.001, top 12) reproduces peptdeep's predict.speclib.tsv: 768/768 precursors with identical
      fragment sets (perf-test with_iRT + Test/predict.speclib.tsv, acetyl peptides excluded since Skyline
      never sends them), intensities within 6e-6, fragment m/z identical, iRT within 0.015. So peptdeep
      1.5.0 uses the same v1 weights CarafeSharp pins.
- [x] `Skyline.csproj`: ProjectReference to `CarafeSharp.Models`, libtorch native via `SkylineTorch`
      property (cpu default, cuda), pretrained_models.zip + LICENSE copied to `models\alphapeptdeep-v1`.
- [x] `AlphapeptdeepLibraryBuilder`: in-process prediction replaces settings export + `peptdeep cmd-flow`;
      writes the same predict.speclib.tsv format (no decoys, no IonMobility/CCS), existing transform +
      BlibBuild/BlibFilter import unchanged. GPU via `TorchDevice.Resolve("gpu")` with CPU fallback.
      Python members removed (CreatePythonInstaller, ScriptsDir, PythonVersion, alpharaw workaround).
- [x] `BuildLibraryDlg`: no Python setup for AlphaPeptDeep.
- [x] Resources: 3 new strings, 3 obsolete peptdeep-command strings removed (en/ja/zh-Hans).
- [x] `TestAlphaPeptDeepBuildLibrary`: Python/NVIDIA install paths removed; baselines re-recorded
      (checked against peptdeep's: same 209/78 target rows, RT within 1.6e-5, intensity within 1.5e-6).
      Fixed a teardown race exposed by the faster prediction: the new document loads the default
      settings' libraries while `CheckForFileLocks` moves the test folder (8/8 pass after, ~4/5 failed before).
- [x] `AlphapeptdeepLibraryBuilderUnitTest`, `PredictionSupportTest`, `SupportedModsTest` pass.

- [x] Deleted the Python infrastructure (`PythonInstaller.cs`, `PythonInstallerUI.cs`, NVIDIA .bat
      templates, `PythonEmbeddable*` settings, resources, `InstallNvidiaTest`, `PythonBootstrapTimeoutTest`)
      and the Java `CarafeLibraryBuilder`. Removing the Java Carafe builder is intended: Skyline will never
      run Java Carafe.
- [x] Fine-tuned `.carafemodel` support in Build Library (`TestCarafeModelBuildLibrary`, TestPerf).
- [x] Builder predicts with a `.carafemodel` exactly as CarafeSharp's `-model` does (0d81b7d843):
      CarafeSharp's RT loading (AlphaPeptDeep or Chronologer, Chronologer's AlphaPeptDeep fallback,
      `rt_maps.json` alignment, minutes vs iRT) moved into `CarafeSharp.Models.RtPredictorLoader`, shared by
      `LibraryGenerator` and `AlphapeptdeepLibraryBuilder`; Skyline takes the file's NCE, instrument,
      activation, analyzer, rt_max and RT model via `CarafeModelFile.ApplyPredictionDefaults`, and ships
      `models\chronologer-20220601193755`. Before, Skyline loaded any `rt.safetensors` as AlphaPeptDeep's RT
      model, so a current (Chronologer) model file would fail or mispredict. Older formats (carafemodel-1)
      need no support or test (developer's decision).
- [x] Regenerated `TestPerf/CarafeModelBuildLibraryTest.zip` (15.6 MB, was 17.7): carafemodel-2, MS2 and
      Chronologer RT fine-tuned (RT R2 0.976 -> 0.997), step 3 of
      `I:\bugs_i\maccoss\20260324_ImportMemory\carafesharp\run-pipeline.ps1` on the Oct 1 Osprey export, CPU,
      output in `carafesharp\train_chronologer\`. The test asserts the model's RT model is Chronologer.
      Gates: CarafeSharp 98 passed / 8 skipped (no test data here), inspection clean; Skyline
      TestCarafeModelBuildLibrary, TestAlphaPeptDeepBuildLibrary (baselines unchanged), TestAlphaPeptDeepUseGpu,
      AlphapeptdeepLibraryBuilderUnitTest, CodeInspection pass.
- [x] BlibBuild/BlibFilter deployment to Skyline's bin: already fixed on master by #4751 (GetTargetPath);
      verified by deleting them from bin and rebuilding.

## Remaining

- [ ] Verify on a machine without an NVIDIA GPU: "Use GPU" disabled, CPU prediction works.
- [ ] Move `CarafeModelBuildLibraryTest.zip` to a server before the PR (developer's task).
- [ ] `/code-review high`, full build + TestPerf, then open the PR (`skyline:`).
- [x] Ion mobility (e62d5693d2): the builder predicts CCS with CarafeSharp's pretrained `CcsModel` (a
      .carafemodel holds none) and writes a `CCS` column, which the transform keeps as
      `CollisionalCrossSection` (0 for Phospho/GlyGly peptides), as the Python path did; Skyline converts CCS
      with each data file's calibration. peptdeep's `IonMobility` (1/K0) column, which the transform always
      dropped, is no longer written. CCS matches peptdeep 1.5.0's baselines within 6.1e-5 A^2 (one float32
      step) on all 209/78 rows; TestAlphaPeptDeepBuildLibrary baselines re-recorded (13 columns again), the
      unit test's `Test/predict.speclib.tsv` resource lost its IonMobility column. Built blib: 6/7 spectra
      with CCS (the 7th is the phosphopeptide).
- [ ] Later: check an AlphaPeptDeep library's CCS against a real timsTOF run in Skyline (never done for the
      Python path either).
- [x] On-demand CUDA download (committed 548d8bebc5, pushed 2026-10-13):
      * CarafeSharp.Models: `LibTorchRuntime` (preloads a libtorch folder by full path before TorchSharp
        loads by name; refuses a second libtorch, and stale libtorch beside TorchSharp.dll),
        `LibTorchPackageSet` + `LibTorchPackageSet.targets` (build writes the libtorch-cuda part package
        list with SHA-512 + size from the NuGet cache), `LibTorchRuntimeInstaller` (verify, unpack,
        restitch fragments + SHA-256, staging folder renamed on completion), `CudaDriver` (nvcuda:
        driver >= 12.8, compute >= 7.0). Unit test `LibTorchRuntimeInstallerTest`.
      * Skyline: CPU libtorch in `torch\cpu` (not beside the exe), CUDA package restored with
        ExcludeAssets=all only for the list; `TorchRuntimes` picks/loads the runtime, downloads into
        %LOCALAPPDATA%\Skyline\libtorch\<set>. BuildLibraryDlg AlphaPeptDeep page has a "Use GPU" checkbox
        (Nick's design): enabled when the GPU qualifies and no libtorch is loaded yet; checking it with
        the runtime missing confirms the size and downloads; choice saved in `AlphaPeptDeepUseGpu`.
        Tests predict on the CPU unless they set `TorchRuntimes.CudaDriver`.
      * Verified 2026-10-13 on RTX 4090 / driver 610.60: real nuget.org download (16 packages, ~6 min,
        4.1 GB installed) and GPU prediction, via a temporary uncommitted TestPerf test.
      * Dev gotcha: `Stage-Tests.ps1` robocopies without /MIR, so old CUDA builds leave libtorch in
        `bin\staging\<Config>\runtimes\win-x64\native`; `LibTorchRuntime.Load` now says so.
- [ ] Later: fine-tuning from inside Skyline (today a .carafemodel comes from the CarafeSharp command line
      and Osprey's training export).
