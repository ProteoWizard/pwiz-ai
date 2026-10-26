# TODO-20261026_osprey_library_engine.md

## Branch Information
- **Branch**: `Skyline/work/20261026_osprey_library_engine`, cut from the head of
  `Skyline/work/20261024_osprey_search_tuning` (PR #4914, PR 2) at f7731c2c1a. Stacked: once #4914
  squash-merges, the update is `git merge origin/master`, never a rebase (version-control guide, the
  squash-merged-parent case)
- **Base**: PR #4914's branch, then `master`
- **Created**: 2026-10-26
- **Status**: Built, gated and reviewed in one day (2026-10-26); PR #4917 open against master, all 18
  checks green (the two Linux builds after re-queuing past three unresponsive cloud agents). Settled with
  Brendan: tests follow the latest successful master Osprey build, nothing is pinned to this PR's build; the
  two Build Library perf tests are red on TeamCity until the merge gives master an Osprey with `--precursors`
- **GitHub Issue**: (none)
- **Module**: `skyline` (with an Osprey / CarafeSharp change for the precursor-table input)
- **PR**: [#4917](https://github.com/ProteoWizard/pwiz/pull/4917) (opened 2026-10-26, commit e085895639)
- **Checkout**: `C:\proj\pwiz`
- **Continues**: `TODO-20261024_osprey_search_tuning.md` (PR 2), whose "PR 3" section is the agreed direction

## Goal

PR 3 of the Skyline-Osprey integration: Osprey's package becomes the engine package. Build Library's
AlphaPeptDeep/Carafe path downloads the Osprey package at first use (the Osprey Search location) and
predicts the library by running `Osprey.exe` out of process through the wizard's ProcessRunner, log tee,
rollover and `OspreyProgressMonitor`; Skyline stops shipping `torch\cpu` (256 MB), the pretrained models
(25 MB) and TorchSharp, which #4849 put into the installer (daily zip 94 MB -> about 195 MB).

## Survey (2026-10-26, read-only agent, verified by hand where it matters)

- **Build Library predicts the document's exact precursors.** `AlphapeptdeepLibraryBuilder`
  (`Model\Lib\AlphaPeptDeep`) writes `input.tsv` (sequence, mods, mod_sites, charge) from the document
  plus the iRT standard peptides (`AbstractDeepLibraryBuilder.GetPrecursorTable`), then predicts in
  process with `Ms2Model` / `RtPredictorLoader` / `CcsModel` directly (NCE 30, Lumos hard-coded), writes
  its own speclib TSV, fits iRT, and runs BlibBuild + BlibFilter. It bypasses CarafeSharp's
  `LibraryGenerator` entirely.
- **Osprey's library phase predicts from a FASTA only.** `--task PredictLibrary` needs `--fasta` and `-o`,
  no raw data (`Program.cs:981-986`); `LibraryBuildWorkflow.PhaseTask` builds a `PredictLibraryTask`
  over an in-memory digest (`LibraryPeptides.Build`), and `LibraryGenerator.Run` lists peptidoforms from
  bare sequences through `PeptideIsoformGenerator` (global fixed/variable modifications) and charges
  from a charge range. There is no precursor-table input anywhere in CarafeSharp or Osprey, so the plan
  as written cannot reproduce Build Library's "exactly these precursors, these modification sites, these
  charges". The output lands at `<out>.predicted.blib` with decoys and DecoyPairs always on.
- **TorchSharp reaches Skyline through CarafeSharp.Models** (`Skyline.csproj:315-319`: the
  `LibTorchRuntimeLayout.targets` import, the CarafeSharp.Models and .Proteome project references, the
  model Content items at 322-337). `CarafeSharp.Proteome` has no TorchSharp and must stay: `CarafeModelFile`
  (manifest reading in `EditCarafeModelDlg`, `CarafeModelChoice`, the tuning test), `CarafeCommandLine.ARG_*`
  (`OspreyHelpers.AppendLibraryBuildArgs`), `Enzyme`, `ModificationTable`.
- **Use GPU depends on in-process CUDA detection.** `UseGpuDriver` (`SettingsUI`) probes
  `TorchRuntimes` (a `CarafeSharp.Models.LibTorchRuntimes`): `CudaInstaller` reads `torch\*.packages.txt`
  from Skyline's bin, `GetCudaUnavailability`, `IsCudaInstalled`, `InstallCuda`. Without `torch\` in the
  bin the reason becomes `no_package_list`. Osprey has `--install-cuda-runtime --torch-runtimes <dir>`
  (`OspreyCommandArgs.cs:222-227`).
- **Osprey's package already carries everything**: `Osprey.csproj` imports the same targets and sets
  `UseCarafeModels=true`; `package.ps1` zips a self-contained net10.0 publish (156 MB).
- **Install seam**: `SkylineFiles.EnsureOspreyInstalled` (3884-3910) is private to `ShowOspreySearchDlg`;
  `OspreyHelpers.CreateDownloadInfo` checks the versioned path, not the registration (the stale
  registration finding of PR 1).
- **Tests on the in-process path**: `TestAlphaPeptDeepBuildLibrary` (TestPerf, Rat_plasma.sky, with and
  without iRT against reference blibs), `TestCarafeModelBuildLibrary` (TestPerf, pasted peptides, a legacy
  `.carafemodel`), `AlphaPeptDeepUseGpuTest` (TestFunctional, fake CudaDriver), the unit tests
  `AlphapeptdeepLibraryBuilderTest` and `AbstractLibraryBuilderModificationSupportTest`; the Osprey seam
  is `OspreySearchTest.EnsureOsprey` (`SKYLINE_TEST_OSPREY_EXE`, the sibling build, or the pinned download).

## Design points (to settle with Brendan before coding)

1. **The precursor-table input** - DECIDED (Brendan, 2026-10-26): Osprey/CarafeSharp's library phase
   accepts the precursor table Skyline writes, and Skyline runs it as a process the way the Python-era
   builder ran `peptdeep cmd-flow` (`Skyline/skyline_26_1_1`'s `AlphapeptdeepLibraryBuilder`: prepare
   input.tsv, run the process, `TransformPeptdeepOutput`, `ImportSpectralLibrary` with BlibBuild +
   BlibFilter). Nick's in-process CarafeSharp calls are walked back: the prediction code that replaced
   `ExecutePeptdeep` (`PredictSpectralLibrary`, `WriteSpectrum`, `GetModifiedPeptide`, the iRT fit) moves
   OUT of Skyline into CarafeSharp, where Osprey's `--task PredictLibrary --precursors <input.tsv>` writes
   the same peptdeep-shaped `predict.speclib.tsv`, so the transform, the blib import and the reference
   blibs of `TestAlphaPeptDeepBuildLibrary` are unchanged.
2. **Use GPU and CUDA install without TorchSharp in Skyline** - DECIDED (Brendan, 2026-10-26): the
   detection and install classes (`CudaDriver`, `LibTorchRuntimes` minus its loader, `LibTorchRuntimeInstaller`,
   `LibTorchPackageSet`; none uses TorchSharp, verified by their usings) move out of CarafeSharp.Models into
   an assembly Skyline references without TorchSharp; `UseGpuDriver` keeps its behaviour (probe at open,
   reason, download in a LongWaitDlg); the package list `torch\<id>.packages.txt` is read from the
   downloaded Osprey install folder, so Skyline's CUDA version matches the Osprey it runs; the runtime
   stays in Skyline's Tools folder, passed as `--torch-runtimes`; the "already loaded, restart" rule goes.
   The aim: one set of dependencies for the two paths that build Carafe models and predict Carafe
   libraries from Skyline.
3. **Framework-dependent vs self-contained package** - DECIDED (Brendan, 2026-10-26): the one
   self-contained package, as today (149 MB zipped, 35 MB of it the .NET runtime); a Skyline-only
   variant is not worth a second packaging surface for a smallish, once-per-version download.
4. **Which tests move to the download seam** - DECIDED (Brendan, 2026-10-26): `TestAlphaPeptDeepBuildLibrary`
   and `TestCarafeModelBuildLibrary` obtain Osprey through the `EnsureOsprey` seam (env var, sibling build,
   pinned download), moved from `OspreySearchTest` to a shared test helper; their reference blibs stay the
   oracle. `AlphaPeptDeepUseGpuTest` keeps its fake driver against the moved detection classes and needs no
   Osprey. The unit tests of the table, transform, import and modification support are unchanged. No
   in-process path is kept: in-process CarafeSharp was a short detour, seen to be the wrong direction once
   File > Search > Osprey Search existed.

## Plan (2026-10-26, after the four decisions)

Order, each step built and tested before its commit:
1. **CarafeSharp.Core takes the runtime classes**: `CudaDriver`, `LibTorchPackageSet`, `LibTorchRuntimeInstaller`,
   `LibTorchRuntimes` (minus `CpuRuntime`, `CanChooseRuntime`, `Load`) move from Models to Core (namespace
   `pwiz.CarafeSharp.Core`); Models keeps `LibTorchRuntime` and gains the static
   `LibTorchRuntime.Load(LibTorchRuntimes, bool useCuda)`. Osprey's `OspreyTorchRuntimes` and the tests follow.
2. **The precursor-table prediction in CarafeSharp.Tasks**: `PrecursorTablePredictor` (the code of Skyline's
   `PredictSpectralLibrary`, `OpenCarafeModel`, `ReadPrecursorInputFile`, `WriteSpectrum`, `GetModifiedPeptide`,
   `GetPrecursorMz` and their constants, moved) writes the peptdeep-shaped `predict.speclib.tsv`; a
   `PredictPrecursorTableTask : CarafeTask` under the name PredictLibrary wraps it with the stamp/resume contract.
3. **Osprey `--precursors <input.tsv>`**: valid only with `--task PredictLibrary` and `-o` (plus `--model`,
   `--device`, `--torch-runtimes`, `--output-dir`, `--timestamp`); refused with `-i`, `--fasta`,
   `--training-input`, the entrapment and digest options. Writes `<out>.predicted.speclib.tsv` beside the
   output (the FASTA phase's `<out>.predicted.blib` naming). Osprey.Test covers the grammar and a tiny table.
4. **Skyline**: `AlphapeptdeepLibraryBuilder` runs Osprey through a `RunOsprey` factored out of
   `OspreyHelpers.RunSearch` (ProcessRunner, tee, rollover, timestamp stripping, `OspreyProgressMonitor` with one
   task); `TorchRuntimes` reads the package list from the installed Osprey folder; `UseGpuDriver` loses
   `inProcess` and the restart rule; `EnsureOspreyInstalled` becomes shared with Build Library (called when the
   AlphaPeptDeep source is chosen) and re-registers the pinned package when a registration is stale;
   `Skyline.csproj` drops the torch layout import, the model Content items and the Models reference;
   `OspreyTestUtil.EnsureOsprey` in TestUtil replaces the copies; the two TestPerf tests use it.
5. Gates: `Build-CarafeSharp.ps1`, `Build-Osprey.ps1 -RunTests -RunInspection`, `Build-Skyline.ps1`,
   `TestAlphaPeptDeepBuildLibrary`, `TestCarafeModelBuildLibrary`, `AlphaPeptDeepUseGpuTest`, `OspreySearchTest`,
   `OspreySearchTuningTest`, `OspreyProgressMonitorTest`, `CodeInspection`, `CheckForMissingResources`, fr/ja/en;
   tcinspect; `/code-review medium`.
6. Optional, last: `CarafeSharp.exe` in the Osprey package (Brendan's item 3) - two self-contained publishes
   in one folder need a look at the shared runtime files first.

## Tasks

- [x] Design settled (above)
- [x] Step 1: runtime classes to CarafeSharp.Core (Build-CarafeSharp tests + inspection green)
- [x] Step 2: PrecursorTablePredictor + task in CarafeSharp.Tasks; `PrecursorTable` (columns + reader) in Core;
      `LibraryModels` factored out of `LibraryGenerator` (pure code motion); `PrecursorTablePredictorTest`
- [x] Step 3: Osprey --precursors (grammar, workflow, refusals, help pages regenerated in en/ja/zh-Hans, docs);
      `TestSubsetPrecursorTable`, `TestPrecursorsArg`; Build-Osprey Debug tests (645) + inspection green
- [x] Step 4: Skyline builder, GPU, install seam, csproj, tests. Gate in en: AlphaPeptDeepUseGpuTest,
      OspreyProgressMonitorTest, OspreySearchTest, OspreySearchTuningTest, TestAlphaPeptDeepBuildLibrary (answer
      files matched through Osprey), TestCarafeModelBuildLibrary, CodeInspection, CheckForMissingResources all pass
- [x] Step 5: fr/ja pass, CarafeSharp tests, tcinspect, commit, `/code-review medium` (7 findings: 6 fixed - the
      stale-registration rule narrowed to a missing file, ProcessRunner's own segment advance and the cancel path,
      `--culture`, digest options refused with `--precursors`, the dead working-folder assignment and banner line;
      1 dropped - the install prompt at source selection, which mirrors the Koina check in the same handler and
      feeds the Use GPU box), PR #4917 opened
- [x] TeamCity on #4917: 18/18 green
- [ ] Brendan's review and merge; then the first nightly perf run with master's new Osprey
- [ ] **Pinned package for TeamCity** (open question for Brendan): `OspreyHelpers.OSPREY_BUILD_ID` 4234706 (26.1.1.296)
      has no `--precursors`, and `OspreyTestUtil.EnsureOsprey` downloads the latest master Osprey build, which lacks
      it until this PR merges. Locally the sibling build serves. On the PR, TestAlphaPeptDeepBuildLibrary and
      TestCarafeModelBuildLibrary (PR perf config) would fail against master's Osprey; after the merge the nightly
      Osprey build has it. Options: pin this PR's own Osprey TeamCity build id once it exists and let the tests
      take the pinned package on a PR; or accept the one red PR perf run and merge Osprey first.

## Notes from the build (2026-10-26)

- **Build Library's run is one ProcessRunner call with percent parsing ON** (`OspreyHelpers.RunOsprey(..., true)`),
  not the wizard's `OspreyProgressMonitor`: the builder keeps its four segments (5/85/90/100) and Osprey's
  `NN%` lines move the prediction segment; the monitor would rewrite the segments to its own task count.
  No `--timestamp` for the builder: its log in `<lib>\APD\<stamp>\osprey-skyline-stdout.log` is unstamped,
  and the status messages carry Osprey's lines as they are.
- **Osprey's output naming**: the builder passes `-o <work>\output_libs\predict.blib` and reads
  `predict.predicted.speclib.tsv` beside it (`OspreyHelpers.GetPredictedTablePath`), the FASTA phase's
  `<out>.predicted.blib` naming carried over; `TransformedOutputSpectraLibFilepath` is unchanged, so the
  TestPerf tests' answer files still apply.
- **CCS with a saved model**: the predictor loads the model folder's `ccs_model.pt` when the file has one
  (`LibraryModels.LoadCcsModel`, as Osprey's own prediction does); the in-process code always took the
  pretrained CCS model. A CarafeSharp `.model.zip` holds none, so only a legacy Carafe `.carafemodel` with a
  CCS model would differ, and `TestCarafeModelBuildLibrary` asserts RT only.
- **`OspreyInstaller.EnsureInstalled(parent)`** (SettingsUI) replaced `SkylineWindow.EnsureOspreyInstalled`:
  called by the wizard's menu item, when Build Library's AlphaPeptDeep source is chosen (before the Use GPU
  probe, which reads the CUDA package list from the installed Osprey folder), and again in
  `CreateAlphaBuilder`. Its `DropStaleRegistration` forgets a registered Osprey under the Tools folder that
  is not the pinned package (another version, or deleted), so the pinned one takes over; a registration
  outside the Tools folder is a developer's build and is kept (the PR 1 review finding).
- **`UseGpuDriver(owner, checkBox)`**: no in-process flag, no "restart Skyline" rule; the SettingsUI string
  for it is gone, as are the builder's "Predicting on the CPU/GPU" and "fine-tuned model" strings
  (ModelResources, English only, no translations existed). `TorchRuntimes_GetCudaUnavailableReason_This_build_of_Skyline...`
  was renamed to say Osprey is not installed.
- **`OspreyTestUtil`** (TestUtil) holds `EnsureOsprey` / `RegisterOsprey` / `ENV_OSPREY_EXE`; OspreySearchTest
  keeps `VerifyLatestBuildOnTeamCity` and a const alias of the variable name.

## Progress Log

### 2026-10-26 - Built, gated, reviewed, PR opened

The four design points settled with Brendan in the morning (the precursor-table input, the TorchSharp-free
detection classes, one self-contained package, the tests on the download seam), then steps 1-5 in one
session: commit e085895639 (one commit, amended with the review fixes before the push), PR #4917. Gates:
Osprey 645 tests + inspection + regenerated help pages, CarafeSharp 116 tests + inspection, Skyline's
AlphaPeptDeepUseGpuTest, OspreyProgressMonitorTest, OspreySearchTest, OspreySearchTuningTest,
TestAlphaPeptDeepBuildLibrary (answer files matched through Osprey), TestCarafeModelBuildLibrary,
CodeInspection, CheckForMissingResources in en, the first four plus CheckForMissingResources in fr and ja,
tcinspect clean. An hour went to a stale `TestPerf.dll`: `Build-Skyline.ps1`'s default target does not
build TestPerf, so `-Target TestPerf` must precede `Run-Tests.ps1` after a perf-test edit (memory saved).
Open: the pinned package question above (Brendan to decide); CarafeSharp.exe in the package (optional item 6)
not done.

### 2026-10-26 - Branch cut, survey

Branch cut from PR 2's head after Brendan approved #4914's squash-merge (waiting on its re-run checks;
auto-merge is disabled on the repository). Survey as above; the precursor-table gap found and verified in
`LibraryGenerator.Run` and `PredictLibraryTask`.
