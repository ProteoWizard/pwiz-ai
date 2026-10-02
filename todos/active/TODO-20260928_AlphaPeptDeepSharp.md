# TODO-20260928_AlphaPeptDeepSharp.md

## Branch Information
- **Checkout**: `E:\Users\nicksh\git_e\sky_net10alphapeptdeep`
- **Branch**: `Skyline/work/20260928_AlphaPeptDeepSharp` (pushed; exploratory, commit 2b58a4be47)
- **Base**: `Skyline/work/20260923_carafesharp` (PR #4717, itself on the .NET 10 port #4619)
- **Created**: 2026-09-28
- **Status**: In Progress
- **Module**: `skyline`
- **PR**: (none - exploratory)

## Objective

Replace the Python AlphaPeptDeep (peptdeep 1.5.0 in an embedded Python that Skyline downloads and
installs) with CarafeSharp's C# TorchSharp port, shipped inside Skyline. Must work with and without an
NVIDIA GPU. CCS prediction is dropped for now (not ported; someone else will port the CCS model).
Installer size is not a concern on this branch; on-demand CUDA download is deferred.

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

## Remaining

- [ ] Verify the CUDA build (`SkylineTorch=cuda`) falls back to CPU on a machine without a GPU, then
      decide the default.
- [ ] Verify on a machine with an NVIDIA GPU (compute >= 7.0, driver >= 570).
- [ ] Delete the now-unused Python infrastructure: `PythonInstaller.cs`, `PythonInstallerUI.cs`, NVIDIA
      .bat templates, `PythonEmbeddable*` settings, their resources, `InstallNvidiaTest`,
      `PythonBootstrapTimeoutTest`, SkylineNightly LongPathsEnabled. Keep `PythonInstallerLegacyDlg`
      (Tool Store) and the `PythonInstallerUtil` path helpers the Java Carafe builder uses.
- [ ] On-demand CUDA download (deferred).
- [ ] CCS model port (someone else).
- [ ] Fine-tuning through CarafeSharp (the Python path never had it wired).

## Notes

- Pre-existing, not this branch: `Skyline.csproj` deploys BlibBuild/BlibFilter from
  `bin\$(Configuration)\net10.0`, but `Build-Skyline.ps1` passes `/p:Platform=x64`, so they build to
  `bin\x64\$(Configuration)\net10.0` and never reach Skyline's bin; AlphaPeptDeep's import then fails with
  "Failure starting command BlibBuild". Worked around locally by copying the x64 output. Same on the port branch.
