# TODO-20260928_AlphaPeptDeepSharp.md

## Branch Information
- **Checkout**: `I:\git_i\sky_net10_alphapeptdeep` (Nick); `C:\proj\pwiz` (Brendan's sessions, adopted
  2026-10-22 with `/pw-adopt` while Nick is away two weeks)
- **Branch**: `Skyline/work/20260928_AlphaPeptDeepSharp` (master merged 2026-10-15; 2026-10-22 at
  46af8ac754, which carries #4895's `.carafemodel` -> `.model.zip` rename and 4a-4c's CarafeSharp changes;
  again 2026-10-22 evening at f4f24aefad as 1be6a071bf)
- **Base**: `master` (#4717 CarafeSharp squash-merged 2026-10-13 as 28c7b7ff03 and merged into this branch)
- **Created**: 2026-09-28
- **Status**: In Progress - Carafe model list, modification matching and fine-tuned modification support built and pushed 2026-10-22; next `/code-review medium`, TeamCity, Brendan's UI pass on a Release build, human review, merge
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
- [x] The "limited support ... consider fine-tuning with Carafe" warning judges against the chosen model
      (ad68ed0e88): a fine-tuned file's training modifications count as supported for fragmentation and
      retention time.
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

## Design: "Carafe" as the source, the model as an editable list (Brendan, 2026-10-22; for Nick to react to)

Brendan's interactive pass found the current UI wonky: the source is called AlphaPeptDeep when it is Carafe
running the AlphaPeptDeep model, the "fine-tuned Carafe model" sits as an option under it, and the editable
combo does not say what one is supposed to type into it. The chooser is folder-shaped where the user's act
is "this file": one model means browsing for its parent folder, and a folder holding several models cannot
be picked from one at a time without separating the files into folders. The change, decided in discussion
(not built yet):

1. **The source radio says `Carafe`** (`radioAlphaSource`, group box "Carafe Options"). Internals keep their
   names (`AlphapeptdeepLibraryBuilder`, the `AlphaPeptDeep` test property): the builder IS the AlphaPeptDeep-
   format predictor, and a rename is churn with no user-visible value. The status line "Predicting with
   AlphaPeptDeep on the GPU/CPU" stays true and stays.
2. **One `Model:` combo in the standard editable-list paradigm** (`SettingsListComboDriver`): the uneditable
   default `Default (AlphaPeptDeep)` (`ExcludeDefaults = 1`) first, the user's fine-tuned models after it, then
   `<Add...>`, `<Edit current...>`, `<Edit list...>`. A `DropDownList`: no typed path, so the "file does not
   exist" validation goes; the editable path box, the "..." button and the recent-10-by-side-effect list go
   with it (`CarafeModelList` as a list of paths, `MAX_RECENT_CARAFE_MODELS`, `AddRecentCarafeModel`,
   `RecentCarafeModels`, the owner-drawn rows in the main combo).
3. **The item** is `CarafeModelSpec : XmlNamedElement` - name + file path, serialized in `user.config` in a
   `CarafeModelList : SettingsList<CarafeModelSpec>`, `IItemEditor<CarafeModelSpec>`. The file's metadata
   (instrument, gradient, precursor m/z, NCE, fragmentation, training runs, held-out cosine and R2, date;
   `CarafeModelChoice` reads it today through `CarafeModelFile.ReadDescription`) is read from the file when
   shown, never stored, so a moved or deleted file shows as missing rather than describing a file that is
   gone. A named spec rather than a bare path, so that later Osprey's one command and the Skyline MCP can
   refer to a model by name.
4. **`<Add...>` and `<Edit current...>`** open a small item editor: Name, File with Browse... (OpenFileDialog,
   `CarafeModelFile.FilePatterns`: `*.model.zip;*.carafemodel`), and below them the file's details read-only
   (what `CarafeSharp --model_info` prints, in the grid's columns), refreshed when the file changes. One
   model per Add, as every other list in Skyline adds one item (a folder-at-once add was considered and
   dropped: a model is a deliberate choice, like a library).
5. **`<Edit list...>` opens Nick's grid as a custom list editor** (`CarafeModelList` overrides
   `SettingsListBase.EditList`, as `ReportSpecList` does with its own form): the list's models as rows with
   the same sortable columns, and Add..., Edit..., Remove, Up, Down. This is where a user compares models
   to pick the one matching the instrument and method (Mike, 2026-10-21); the item editor alone cannot show
   that. `CarafeModelChooserDlg` becomes this editor: the Folder box and its browse go; `FolderPath`,
   `GetInitialFolder` and `Settings.Default.CarafeModelDirectory` survive only as the start folder of the
   file dialog.
6. **The combo's rows** are `GetDisplayName` strings, so the dropdown is plain text; start with a one-line
   display name (`<name> - <instrument>, <gradient> min, NCE <n>`) and judge whether that is enough to
   recognise a chosen model, since the comparison lives in the grid.
7. Untouched: the builder, `TorchRuntimes`, Use GPU (orthogonal to the model, stays in the group),
   `CarafeModelFile`, the tests' mechanics. `TestCarafeModelBuildLibrary` drives `<Edit list...>` -> Add...
   (or `<Add...>`) with the test model instead of the chooser's folder; `TestAlphaPeptDeepUseGpu` unchanged.
   `PeptideSettingsUI.BuildLibrary`'s recent-model update (from the review fixes) goes with the recent list.

Open for Nick: whether `Default (AlphaPeptDeep)` should be the wording (Brendan prefers it to a bare
"AlphaPeptDeep": it says what happens when you choose nothing); and whether the one-line display name
suffices or the owner-drawn two-line rows should come back for the list items.

## Progress Log

### 2026-10-22 - Adopted; master merged (Brendan's session, Nick away)

Brendan: first bring the branch to current CarafeSharp, build and pass tests, then `/pw-review`. Adopted in
`C:\proj\pwiz` with `/pw-adopt`; `git merge origin/master` (46af8ac754: #4879, #4890, #4885, #4895, #4844,
#4850, #4897, #4898). One textual conflict, `TestPerf/AlphapeptdeepBuildLibraryTest.cs`: both sides fixed the
same teardown race (the new document loading libraries while `CheckForFileLocks` moves the folder); master's
#4890 form (`WaitForDocumentLoaded` + `WaitForBackgroundLoaders`) taken. One semantic conflict: #4895 renamed
`.carafemodel` to `.model.zip` (`CarafeModelFile.EXTENSION`, `LEGACY_EXTENSION`, `FilePatterns`,
`IsModelFileName`); `CarafeModelChooserDlg.UpdateModels` listed a folder with `"*" + EXTENSION` and would have
hidden every existing `.carafemodel`, so it enumerates `CarafeModelFile.FilePatterns` now. The model's
`Open`/`Read` already accepted either name by content. Comments naming `.carafemodel` say `.model.zip`.
Gates on the merge: Skyline solution build; CarafeSharp 106 passed + 8 NotExecuted (no Carafe reference
data on this box) + inspection 0; Skyline `AlphapeptdeepLibraryBuilderUnitTest`, `TestAlphaPeptDeepUseGpu`,
`CodeInspection`, and after `-Target TestPerf` (not in the solution build; the first run silently ran only the
three built ones) `TestAlphaPeptDeepBuildLibrary` (6 s) and `TestCarafeModelBuildLibrary` (3 s), all pass
on the CPU. Next: `/pw-review 4849` with Brendan; Mike's open question on the model chooser (grid with
metadata - the "..." grid is the current answer) and Brendan's: the Use GPU checkbox stays enabled and explains
itself (already the design).

### 2026-10-22 - `/pw-review 4849` (Brendan's session)

Verdict: ready for a human pass. Two concerns, two suggestions, two nits, three questions. Brendan: apply all
but the translation nit (CarafeSharp's `Describe()` text reaches a Skyline status line in English; CarafeSharp
gets translated later, not in this PR); the questions (uninstall removing all of `Tools\` and `user.config`;
Java `CarafeLibraryBuilder` deleted; the model chooser shape against Mike's ask) raise no concern for him
beyond wanting a working build to try. Applied and pushed: `LibTorchRuntimeInstaller.AddPackage` refuses an
entry whose last part is not a plain file name (a backslash the `/` split leaves, or `..`) - the CodeQL Zip
Slip alert; pinned in `LibTorchRuntimeInstallerTest` with two synthetic packages. `LibTorchRuntime` marks
itself `Loaded` from the first library that loads rather than before loading, so a missing or empty
`torch\cpu` reports its own error on every attempt instead of "already loaded ... restart Skyline".
`BuildLibraryDlg.AddRecentCarafeModel` (now public) runs from `PeptideSettingsUI.BuildLibrary` after
`CompleteLibraryBuild`, not from `ValidateBuilder`, so a model whose build failed or was cancelled does not
head the recent list. `BuildLibraryDlg.UpdateUseGpu` finds the NVIDIA driver (`nvcuda` load + `cuInit`) on
a background thread the first time, with the box disabled until it returns (`TorchRuntimes.IsCudaDriverFound`;
tests set the driver, so they stay synchronous). `TorchRuntimes.CudaInstaller` is read once and invalidated
by the folder setters. Dropped as not worth it: nothing else. Gates: CarafeSharp 106 + 8 skipped + inspection
0; Skyline solution and TestPerf builds; the five branch tests pass. Next: Brendan's interactive UI testing
on a Release build; then TeamCity, human review, merge.
Brendan: the GPU probe belongs behind `LongWaitDlg` with an indeterminate (marquee) bar - the Skyline wrapper for a potentially long operation on a background thread - not a bare thread that re-enables the box. Done (the `Action` overload, no cancel, shown past 500 ms; resource "Looking for an NVIDIA GPU"); the five tests pass; Release rebuilt for his UI pass.

### 2026-10-22 - "No NVIDIA GPU" in a harness-launched Skyline (Brendan)

Brendan checked Use GPU in a Skyline paused inside a SkylineTester tutorial run (TestRunner `pause=-1`) and got "No NVIDIA GPU was found" on an RTX 4000 Ada (driver 596.71, CUDA 13.2, compute 8.9). Root cause: not the probe - `CudaDriver.Find()` from the built `CarafeSharp.Models.dll` returns the driver in the same RDP session (`ai/.tmp/sessions/20261022-libcache/Probe-Cuda.ps1` and a reflection call both confirm) - but `TorchRuntimes`'s constructor nulled the driver whenever `Program.UnitTest` was set, which a harness-launched Skyline shares with a real test. Fix: the override is gone; `TestAlphaPeptDeepBuildLibrary` and `TestCarafeModelBuildLibrary` set `CudaDriver = null` on the dialog's `TorchRuntimes` themselves (before selecting AlphaPeptDeep, so the probe never runs in them). Five tests pass; Release rebuilt. Lesson for the design above: nothing in product code should tell a test from a developer driving Skyline through the harness.

### 2026-10-22 - The Carafe source and the editable model list, built (Brendan's session)

Brendan's pass with the ... chooser: folder box disabled, no way to tell what the grid's OK would do, and OK only filled the combo's edit box, which dropping the list cleared - "not willing to merge with the UI in this state". Built the design section above, less the folder add: `CarafeModelSpec` (`Model/Lib/AlphaPeptDeep`, `XmlNamedElement` with `file_path`; `DEFAULT` has none), `CarafeModelList : SettingsList<CarafeModelSpec>` in `Settings.cs` (`ExcludeDefaults = 1`, display name "Default (AlphaPeptDeep)" or name + `CarafeModelChoice.Summary` in parentheses as the enzyme list shows cleavage; `EditItem` -> `EditCarafeModelDlg`; `EditList` override -> `CarafeModelListDlg`; `SettingsListBase.EditList` made virtual for it). The `CarafeModelList` setting replaced the `List<string>` of recent paths under the same name (a stale user.config value deserializes to the default list). `EditCarafeModelDlg`: Name, File + Browse... (`*.model.zip;*.carafemodel`, start folder `CarafeModelDirectory`), details read-only from `CarafeModelFile.ReadDescription(path).FormatInfo()`; OK checks the name is unique and `CarafeModelFile.Open` passes (`ValidateModelPath`, which `BuildLibraryDlg.ValidateBuilder` also runs on the chosen model). `CarafeModelChooserDlg` -> `CarafeModelListDlg` (git mv): the folder controls gone, Name column first, Add/Edit/Remove/Up/Down, a missing file shown in gray. `BuildLibraryDlg`: radio "Carafe", group "Carafe Options", `Model:` `DropDownList` driven by `SettingsListComboDriver` (filled when the Carafe source is first shown, since display names read the files); `CarafeModel` property, `CarafeModelPath` getter, `AddCarafeModel()` / `EditCarafeModelList()` for tests; the owner-drawn rows, `RecentCarafeModels`, `AddRecentCarafeModel`, the ... button and the path validation strings gone, and `PeptideSettingsUI`'s recent-model update with them. `SettingsListComboDriver.AddItem`/`EditCurrent` reselect by `GetDisplayName`, not `GetKey` (`LoadList` compares the combo text), a latent defect for any list with a richer display name. `TestCarafeModelBuildLibrary` drives Edit list... -> Add... (name, file, details), refuses a duplicate name, picks the model by `CarafeModel`, builds, then the combo's own Add... and a Remove in Edit list.... Gates: Skyline solution + TestPerf; `TestCarafeModelBuildLibrary`, `TestAlphaPeptDeepUseGpu`, `TestAlphaPeptDeepBuildLibrary`, `AlphapeptdeepLibraryBuilderUnitTest`, `CodeInspection` pass. Open: whether the display-name summary suits the combo (design item 6); ja/zh-Hans strings in the translation pass.

### 2026-10-22 - Modification matching and the warning's timing (Brendan's session)

Brendan's test document defines carbamidomethylation the old way ("Carbamidomethyl Cysteine", the formula on C, no UniMod id). Carafe skipped every cysteine peptide ("missing a Unimod ID ... will be skipped"), listed the modification under both the unknown and the limited-support warnings, and asked only after Build Library had closed, so Cancel landed in Peptide Settings. Fixes: `AbstractDeepLibraryBuilder.MatchUniMod` resolves a modification without an id through `UniMod.FindMatchingStaticMod` (same definition: formula or mass, amino acids, terminus - the Panorama approach, with Skyline's own matcher), used by the input rows and the warning; the limited-support list excludes `none`; `GetWarningMods`/`GetWarning` have static forms over a document and a `LibraryBuilderModificationSupport` (`AlphapeptdeepLibraryBuilder.MODEL_MODIFICATION_SUPPORT`). `BuildLibraryDlg` shows `Limited or no support for: <mods>` (dark red, full warning as tooltip) in the Carafe group as soon as the source is chosen, and asks the OK/Cancel question in `ValidateBuilder` before the form closes; `PeptideSettingsUI.BuildLibrary` no longer asks. Tests: `AlphapeptdeepLibraryBuilderUnitTest` adds the old-definition document (no warning; `Carbamidomethyl@C` rows); `TestAlphaPeptDeepBuildLibrary` checks the in-form flag and takes the question from `OkWizardPage`. Open: "Add All..." (a folder walked recursively, file names to element names) held until Mike says labs will have many models per machine; the limited-support warning still judges against the pretrained models' list when a fine-tuned model is chosen - next is to treat the chosen file's `Training.Modifications` as supported.

### 2026-10-22 - Handoff

**Next session handoff**: read `ai/.tmp/handoff-20261022_4849_carafe_model_list.md` first. Uncommitted in `C:\proj\pwiz`: fine-tuned model modifications (compiles; `TestFineTunedModificationSupport` fails because a custom Oxidation with losses does not match UniMod Oxidation (M) - suspect `RelativeRT`/`IsVariable` in `StaticMod.Equivalent`). Test model for Brendan: `D:	est\carafe-models\Stellar-gpu-tuned+TMT-MetOx.model.zip`. Pending: email draft to Mike and Nick about "Add All..."; master merge; code review; TeamCity.

### 2026-10-22 - Fine-tuned model modifications committed (Brendan's session, evening)

Committed ad68ed0e88: `AlphapeptdeepLibraryBuilder.GetModificationSupport(carafeModelPath)` extends the pretrained
support with the file's `Training.Modifications` (CarafeSharp names -> UniMod ids, fragmentation + retention
time; CCS stays pretrained), the builder's support follows `CarafeModelPath`, `BuildLibraryDlg`'s in-form
warning follows the chosen model, and the limited-support list ignores a missing CCS. Root cause of the
failing `TestFineTunedModificationSupport`: `UniMod` builds its modifications with `RelativeRT.Matching` and
`StaticMod.Equivalent` compares `RelativeRT`, so the test's `RelativeRT.Unknown` MetOx never matched; the
losses-only retry also could not match a definition with extra losses, since UniMod's Oxidation (M) carries
its own. Fix, scoped on Brendan's challenge about touching central code: `StaticMod.Equivalent` untouched;
`UniMod.FindMatchingStaticMod` gained an optional `ignoreLosses` (existing callers unchanged; loss-only
entries such as Water Loss, which have no UniMod id, are skipped since `ChangeLosses(null)` fails their
validation), and `MatchUniMod` normalizes `RelativeRT` before calling it with the flag. Gates: solution +
TestPerf builds, the five branch tests pass (log
`bin\staging\Debug\AlphapeptdeepLibraryBuilderUnitTest,...,CodeInspection.log`). Email to Mike and Nick about
"Add All..." sits as a Gmail draft for Brendan to send. Then master merged (f4f24aefad: #4904, #4902; one
comment in Skyline.csproj auto-merged).

### 2026-10-22 - Review fixes, resource key fix, TeamCity (Brendan's session, evening)

Brendan: the two sessions' UI work looks right; apply the review fixes, push, watch TeamCity, then trigger
Perf and Tutorial. `/code-review medium 8c08464fe2..HEAD`: 9 findings, 5 fixed in ce7b115b78 (one
`LIBRARY_PREDICTION_SUPPORT` threshold for the in-form warning and the per-peptide "limited" message; a
fine-tuned modification widens a narrower pretrained entry (GlyGly) instead of being skipped; exact UniMod
match before the loss-stripped one; `MatchUniMod` memoized per definition in a static `ConcurrentDictionary`;
dead `ILibraryBuildWarning` removed), 4 dropped (model validated on the UI thread at Finish - dropped
2026-10-14 already; manifest re-read per combo change and the double warning on first show - milliseconds;
combo selection by display text falling to the default if a model file vanishes between two list reloads -
needs the file to disappear mid-dialog). TeamCity build 22440 (cc9dc013) failed `CheckForMissingResources`:
the `SettingsUIResources` designer property renamed with `EditCarafeModelDlg` still looked up the old
`BuildLibraryDlg_ValidateCarafeModel_...` key; fixed in 31079d741b (reproduced and verified locally, 1 s).
Only bt209 runs automatically on this PR; Perf and Tutorial
(`ProteoWizard_SkylinePrPerfAndTutorialTestsWindowsX8664`, ~3.5 h) to trigger once bt209 is green. Brendan's
plan after: approve, give Mike and Nick time to respond, merge, then a night session on PR 4d of the
Osprey-Carafe integration.

bt209 #22445 (31079d741b) passed: 1821 tests. Triggered Perf and Tutorial (build 4231741). Two statuses
still red on the commit: "Skyline code inspection" (7 ReSharper warnings, 3 from today's commits: UniMod
candidates enumerated twice, the memo lambda's `mod` hiding the method's, the two ambiguous `GetWarningMods`
crefs, `LongWaitDlg` initialized outside its `using`, an unused using in `EditCarafeModelDlg`) and CodeQL
(cs/zipslip at `LibTorchRuntimeInstaller.cs:103`, still open after 8c08464fe2's file-name check because the
split part flowed into `Path.Combine` untouched). Fixed both: the extraction destination is
`Path.GetFullPath` under the staging folder and checked to start with it - the form CodeQL's query knows as a
sanitizer - alongside the plain-file-name refusal; `TestLibTorchRuntimeInstall` passes. Local gates: six
tests (the five plus `CheckForMissingResources`) pass; `pwiz_tools/Skyline/tcinspect.ps1` run locally before
the push: clean ("No build warnings and no inspections at WARNING or above"). Committed as 75355ed91b and
pushed; the first Perf and Tutorial run (4231741, on 31079d741b) cancelled five minutes in, to re-trigger
on 75355ed91b once TeamCity has queued bt209 for it: bt209 #22446 (4231753) and Perf and Tutorial
4231761 running on 75355ed91b. On 75355ed91b CodeQL and the Skyline inspection both pass. Osprey Linux .NET
had failed on every commit since 8c08464fe2 added the slip test: Linux's `Path.GetFileName` keeps a
backslash, so the backslash entry was accepted; `AddPackage` now refuses a backslash explicitly
(ece246eade; Windows test passes). Perf and Tutorial cancelled again and re-triggered on ece246eade as
4231773; bt209 #22447 (4231765) and Osprey Linux .NET (4231764) run on it too. Both passed (Osprey Linux
green for the first time on this PR); CodeQL, both code inspections, Core Windows/Linux, Osprey Windows,
Ubuntu all green on ece246eade. Docker/Wine passed too: 19 of 20 statuses green on the head.

**Open at 21:30: `ConsoleTestDiaPasef` failed in Perf and Tutorial 4231773** ("Error: There are no decoy
peptides in the document. Failed to create scoring model" after "Added 30 decoy peptides"; the DIA import
itself ran). Facts: no nightly failure history; it passed in Perf 4230300 on this branch at 2bcd8e5b this
morning and in the master runs on 7819a9b6 and 22626556; every other recent Perf failure is master's old
Python `TestAlphaPeptDeepBuildLibrary` (unable to open the .blib), which this PR replaces. Known-bad range is
today's commits plus the two master merges; the only master commits no Perf run has covered are #4844,
#4850 (tc-perftests.bat now builds x64 through SkylineBuild.proj; new test-data extraction), #4897, #4898,
#4902, #4904. `CommandLine.CreateScoringModel` reports it when `GetPeakFeatures` yields no decoy groups, so
the decoys had no chromatograms, suspect the library ion mobility lookup for decoys (only the PASEF test
uses `--ims-library-res`; `ConsoleTestDiaQe` ran before it and passed). Steps taken: master Perf and
Tutorial triggered as a control (4231992); local repro needs a vendor build (the no-vendor build rejects the
.d as an isolation scheme; data is at `D:\Users\brendanx\Downloads\Tutorials\DIA-PASEF-small`), building
with `-VendorLicenses`. If local reproduces on the branch, run it on master in `pwiz-scanmajor` to split
branch vs master.

**Root cause (22:40).** Alone the test passes 9/9 locally (Debug and Release); after
`TestCarafeModelBuildLibrary` in the same process it fails every time (30 s cycle). Instrumentation, since
reverted, walked it back: no group had peak features because the .skyd held only the 15 iRT standards;
the others got no chromatograms because MS1 filtering was on (Count, TOF 30000) where the passing run
has none; it was on because `CommandArgs` parsed `--full-scan-precursor-isotopes=Count ... =None` as
Count. The shared `CommandLineParser` (master's #4885/#4898, merged this morning after the last green Perf
run) reads its grammar from the process-wide `ArgUsage.Grammar`; `CarafeCommandLine`'s static constructor
installed Carafe's grammar (`FirstValueWins`) and text there, and `CarafeModelFile` references that class
for its messages, so reading a model in Build Library flipped Skyline's own parser. Master's control Perf
run (4231992, cancelled after) passed the test: master runs no in-process Carafe before it. Fix, per Brendan
(a scoped install, centralized): `ArgUsageSettings` declares what one argument model installs,
`ArgUsage.Install(settings)` is the only setter (returns an `IDisposable` that restores the previous
settings; the static setters are private), Skyline and Osprey install once in their static constructors,
`CarafeCommandLine` installs around `Parse`, `BuildUsage` and `GenerateUsageHtml` and restores the host's
after; Osprey's workaround that forced Carafe's initializer first is gone. `CommandArgsGrammarTest` (Test)
runs a Carafe parse then a Skyline parse.

**Final design (Brendan, 23:30), committed 29b73ab380 and pushed.** The running process owns the argument
grammar and it does not change: `ArgUsageSettings` declares everything one argument model installs,
`ArgUsage.Install(settings)` is the one way to set it (void, no IDisposable; the static setters are private;
`ArgUsage.Current` snapshots for the tests that switch grammars), Skyline, Osprey and CarafeSharp.exe's
`Main` install once at startup, and `CarafeCommandLine` installs nothing - hosted in Skyline and Osprey its
declarations run under the host's grammar (Osprey parses the options it hosts under its own). Osprey's
static-constructor workaround that forced Carafe's initializer first is gone. Tests: `CommandArgsGrammarTest`
(Skyline Test: a Carafe parse, then a Skyline parse keeps its last value), CarafeSharp's `TestAssemblySetup`
installs Carafe's settings once for its test process, `CommandLineParserTest` uses `ScopedAction` and
`OspreyCommandArgsTests` reinstalls its snapshot. Gates on 29b73ab380: CarafeSharp build, inspection 0,
106 passed / 8 skipped; Osprey build + 10 OspreyCommandArgs tests; Skyline Debug build + 8 tests
(both grammar tests, five branch tests, CheckForMissingResources); Release `TestCarafeModelBuildLibrary,
ConsoleTestDiaPasef` passes (the reproduction). Follow-ups Brendan raised, not for this PR: isolate
`CarafeCommandLine` so Skyline never loads it (cut the message-text references in `CarafeModelFile`,
`LibrarySettings`, `LibraryOutputs`, `EntrapmentPairingValidator`, `CarafeModelOrigin`, `LibraryGenerator`,
`ModelTrainer`, then its own assembly for CarafeSharp.exe, its tests and Osprey); maybe move `ScopedAction`
to CommonUtil. Next: TeamCity on 29b73ab380 - bt209, Perf and Tutorial, and Osprey Perf/Regression
(`ProteoWizard_OspreyWindowsNetPerfRegressionTests`, `pull/4849`) since Osprey and CommonUtil changed; then
Brendan approves, Mike and Nick get time to respond, merge, PR 4d.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260928_AlphaPeptDeepSharp_teamcity.md` before starting work. It is a night session:
tend TeamCity to green; if something as involved as tonight's failure appears, root-cause it, design the
fix, and stop before implementing anything major.

### 2026-10-23 - Night session: TeamCity on 29b73ab380 (started 22:22)

Perf and Tutorial 4231773 (ece246eade) had a second failure the handoff missed:
`CommandlineCreateImsDbPerfTest` ("Error: Unexpected argument --in ...", test 2.27, right after
`ConsoleTestDiaPasef` at 2.16). Same root cause: Carafe's grammar installed process-wide has no `--in`,
so Skyline's own parser rejected it. Not broken on master (Perf 4230286 and 4229688 are SUCCESS). Verified
the fix covers it: Release `TestCarafeModelBuildLibrary,CommandlineCreateImsDbPerfTest,ConsoleTestDiaPasef`
in one process on 29b73ab380 passes 3/3 in 48 s (log in `pwiz_tools/Skyline/bin/staging/Release/`).
bt209 #22449 (4232016) passed: 1823 tests (1821 + the two grammar tests). GitHub on 29b73ab380 at 23:40:
16 of 18 statuses green including the Skyline inspection and CodeQL; Perf and Tutorial (4232023, started
22:26, ~3.4 h) and Osprey Perf/Regression (4232024, queued behind Perf on MacCoss Agent 1) outstanding.
The working tree holds one uncommitted whitespace-only line wrap in `CommonTest/CommandLineParserTest.cs`
(line 105, 115 chars as committed); the committed form passes the inspection, so it was left alone and
nothing was pushed - a push would re-queue the 3.4 h Perf run.
