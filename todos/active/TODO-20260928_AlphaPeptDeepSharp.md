# TODO-20260928_AlphaPeptDeepSharp.md

## Branch Information
- **Checkout**: `I:\git_i\sky_net10_alphapeptdeep`
- **Branch**: `Skyline/work/20260928_AlphaPeptDeepSharp` (master merged 2026-10-15)
- **Base**: `master` (#4717 CarafeSharp squash-merged 2026-10-13 as 28c7b7ff03 and merged into this branch)
- **Created**: 2026-09-28
- **Status**: In Progress
- **Module**: `skyline` (also carries CarafeSharp changes Skyline needs; the developer chose to keep them here)
- **PR**: [#4849](https://github.com/ProteoWizard/pwiz/pull/4849) (draft; screenshots in nickshulman/pr-assets `pwiz/4849-alphapeptdeep`)

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
      writes the same predict.speclib.tsv format (no decoys; CCS came back in e62d5693d2, below), existing transform +
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

- [x] Verified on a machine without an NVIDIA GPU (developer, 2026-10-14): "Use GPU" explains why, CPU
      prediction works.
- [x] Old Python installs need no cleanup code: the settings import copies only tools the settings name
      (never `Tools\Python`), an old ClickOnce install's Python goes with that install's uninstall, and the
      net10 uninstall removes all of `Tools\` (151b60ae45). Say so in the PR.
- [x] Removed `PythonInstaller_BuildPrecursorTable_Python_0_installation_is_required`, the one resource
      the branch left unreferenced (its `_please_wait` sibling and `PythonInstaller_Download_failed_...`
      were already unused on master; out of scope).
- [ ] Move `CarafeModelBuildLibraryTest.zip` to a server (developer's task; deferred, not blocking the
      draft PR).
- [x] `/code-review high` (2026-10-14), 10 findings. Fixed in a93f925e12: partly loaded libtorch left
      `Loaded` null; per-package progress segments could repeat an end (packages < 1%); older CUDA runtime
      versions now removed once a new one installs (renamed first, so one another Skyline has loaded stays);
      `ProgressStatus.ChangePercentComplete` compared the zoomed percent with the overall one (resets in
      ChangeSegments kept for external `IsPercentComplete` callers); builder used the GPU whenever the CUDA
      runtime was loaded, now only with `UseGpu`; dead `ArgumentAndValue`, output-line members and the
      `_please_wait` resource removed. Dropped: uninstall removing all of `Tools\` (deliberate, see
      Setup.iss), .carafemodel validated on the UI thread and `CudaInstaller`/`CudaDriver.Find` cost (small
      files, one-time driver init), `WizardPages.SelectedIndex` hiding the base (all callers go through it).
- [x] Full ReSharper inspection crashes in jb ("Roslyn Worker process exited unexpectedly", no log detail,
      3 runs, fresh cache too); the developer fixed the two warnings it found on another run (29c5d0889b).
      CarafeSharp inspection clean, CodeInspection test passes.
- [x] `Test-Installer.ps1` (2026-10-14): install, SkylineCmd, uninstall removing Tools\ and user.config all
      passed; its final check failed only on a `.vs` folder (Visual Studio state from 2026-10-10) left in
      the install folder, which no installer step creates.
- [x] Screenshots for the draft PR (2026-10-15, Release build driven through the Skyline MCP): real CUDA
      download (16 packages, ~2.9 GB, into `Tools\libtorch-cuda-12.8-win-x64.2.10.0`, 4.1 GB), GPU builds
      with the pretrained and the fine-tuned model, restart message. Found and fixed (ff3b767df4) the
      download prompt still saying the runtime is shared by all installations.
- [ ] Decide: the "limited support in the default predictive model ... consider fine-tuning with Carafe"
      warning still shows when a .carafemodel is chosen.
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
        Skyline's Tools folder (151b60ae45; was %LOCALAPPDATA%\Skyline\libtorch), which the installer's
        uninstall removes along with user.config (`Test-Installer.ps1` checks it). BuildLibraryDlg
        AlphaPeptDeep page has a "Use GPU" checkbox (Nick's design): always enabled; checking it when the GPU
        cannot be used (no driver, old driver, old GPU, another runtime already loaded this session) says
        why and unchecks it; with the runtime missing it confirms the size and downloads; choice saved in
        `AlphaPeptDeepUseGpu`.
        Tests predict on the CPU unless they set `TorchRuntimes.CudaDriver`.
      * Verified 2026-10-13 on RTX 4090 / driver 610.60: real nuget.org download (16 packages, ~6 min,
        4.1 GB installed) and GPU prediction, via a temporary uncommitted TestPerf test.
      * Dev gotcha: `Stage-Tests.ps1` robocopies without /MIR, so old CUDA builds leave libtorch in
        `bin\staging\<Config>\runtimes\win-x64\native`; `LibTorchRuntime.Load` now says so.
- [ ] Later: fine-tuning from inside Skyline (today a .carafemodel comes from the CarafeSharp command line
      and Osprey's training export).
