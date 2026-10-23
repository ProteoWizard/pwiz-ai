# TODO-20261023_skyline_osprey_search.md

## Branch Information
- **Branch**: `Skyline/work/20261023_skyline_osprey_search` (to be cut from `master` at the start of the
  night session of 2026-10-23; master holds #4909 and #4911)
- **Base**: `master`
- **Created**: 2026-10-23
- **Status**: Designed - Brendan's decisions below are open; the branch is cut when the night session starts
- **GitHub Issue**: (none)
- **Module**: `skyline`
- **PR**: (none yet)
- **Checkout**: `C:\proj\pwiz`
- **Continues**: `TODO-20261019_osprey_one_command.md` (PR 4d, #4909, defined the `--torch-runtimes`
  hand-off this integration uses; its phase-1 file holds the Osprey-CarafeSharp design)

## Goal

Skyline runs Osprey as a DIA search engine: a **Search > Osprey Search...** wizard takes the DIA runs and a
protein FASTA (or an existing spectral library), runs Osprey, and hands Osprey's `.blib` to the Import
Peptide Search wizard, which adds it to the document and imports the runs. Osprey is a download into
Skyline's Tools folder, as DIA-NN is, from a release site (to be decided; the TeamCity artifact can
stand in), with one CUDA runtime download serving Skyline's AlphaPeptDeep and Osprey.

Better supported than DIA-NN in three ways Brendan set out (2026-10-23): no licence or version variants
to handle (Osprey is ours, one zip, one pinned version); no BlibBuild on the output (Osprey writes
exactly the `.blib` Skyline needs, through the shared BiblioSpec.IO writer); and the library prediction
is inside the one Osprey command, so the wizard has no separate "predict the library" step.

## Why (Brendan, 2026-10-23)

Groundwork for Skyline-Osprey integration, now that the one command (#4876, #4885, #4898) and the
run-time libtorch layout (#4909) are on master. Osprey is unreleased; this lets Skyline users reach it
before its first release and keeps the two products on one spectral-library path.

## Survey (2026-10-23, master at 60276b7182; the full report is in the session notes)

**DIA-NN's shape in Skyline.** A menu item (`Skyline.resx:518`, handler `SkylineFiles.cs:3681`) opens
`FileUI\PeptideSearch\DiannSearchDlg` with pages: DIA data files (`ImportResultsDIAControl`), FASTA
(`ImportFastaControl` with `IsDDASearch = true`), modifications, search settings, run
(`DiannSearchControl : SearchControl`). `SkylineFiles.EnsureDiannInstalled` (`:3806`) gates the install
through `DiannDownloadDlg` (licence, two versions, MSI or zip - all DIA-NN's, none Osprey's).
`Model\Lib\DiannHelpers` holds the version pin, the Tools-folder path, `FileDownloadInfo` with
`CheckInstalledPath`, the command lines, and `RunDiannProcess`: `ProcessRunner` with the 8.3 short path,
`BelowNormal` priority, stdout teed to a log, the exit code and a "Critical error" scan as the verdict.
On Finish, `ImportDiannLibrary` (`DiannSearchDlg.cs:558`) opens `ImportPeptideSearchDlg` with the parquet
as a search file, which BlibBuild converts.

**The seams Osprey uses.**
- `SearchToolType` (`Model\SearchTool.cs:29`, serialized by name) and `Settings.Default.SearchToolList.
  GetToolPathOrDefault` (`Settings.cs:1843`): a registered path wins over the Tools-folder default, which
  is how a test or a developer points Skyline at a local Osprey.exe. `ToolsUI\EditSearchToolDlg` lists the
  enum automatically.
- `SimpleFileDownloader.DownloadRequiredFiles` (`Util\UtilInstall.cs:249`): under `Program.UnitTest` it
  rewrites the URL to `https://ci.skyline.ms/skyline_tool_testing_mirror/<file>`, caches the download for
  the test run, unzips, and registers the tool. The Java entry (`:140`) is the minimal zip-tool template.
- `ProcessRunner.Run` turns any stdout line ending in `NN%` into `PercentComplete` and every other line
  into the status message (`CommonUtil\SystemUtil\ProcessRunner.cs:197-229`); `SearchControl` is the
  `IProgressMonitor`, with cancel killing the process. Osprey writes through the same `CommandStatusWriter`
  Skyline's command line uses, so its progress lines should parse with no wrapper (to verify first).
- The existing-library overload `ImportPeptideSearchDlg(SkylineWindow, LibraryManager, Workflow.dia,
  foundResults, fastaSettings, existingLibraryFilepaths)` (`ImportPeptideSearchDlg.cs:742`), EncyclopeDIA's
  route (`EncyclopeDiaSearchDlg.cs:410`): skips the library-build page, pre-fills the results files, and
  `AddExistingLibrary` (`BuildPeptideSearchLibraryControl.cs:448`) adds the `.blib`, offering an RT
  predictor when it carries an `IrtLibrary` table.
- GPU: `Model\Lib\AlphaPeptDeep\TorchRuntimes` and `BuildLibraryDlg`'s Use GPU flow (`:314-437`) decide
  whether the GPU can be used and install the CUDA runtime into `ToolDescriptionHelpers.GetToolsDirectory()`.
  Osprey's `--torch-runtimes <that folder>` finds the same install (same package set, same folder name).

**What Osprey skips.** `DiannDownloadDlg`, the registry scan, MSI extraction, the two-version choice; the
predictor-then-search split and speclib file resolution; the parquet row-count gate; BlibBuild and the
`ScoreTypesLoaded` wait; the enzyme `--cut` map and UniMod formatting (Osprey takes Skyline's enzyme and
modifications in CarafeSharp's terms); `DiannProgressMonitor`.

## Design

1. **`Model\Lib\OspreyHelpers`** (static, modelled on `DiannHelpers` minus the above): `OSPREY_VERSION`
   (pinned; the zip's folder is `Osprey-<version>-win-x64`), `OspreyDirectory` under the Tools folder,
   `OspreyBinary` through `GetToolPathOrDefault(SearchToolType.Osprey, ...)`, one `FileDownloadInfo`
   (`Unzip`, `InstallPath` = Tools, `CheckInstalledPath` = the exe, `DownloadUrl` = the release site;
   under tests the mirror), `BuildCommandLine(runs, fasta | library, outBlib, settings, toolsFolder)`, and
   `RunSearch(...)` through `ProcessRunner` with the DIA-NN precautions (short paths, `BelowNormal`, the
   teed stdout log `osprey-skyline-stdout.log` beside the output). The verdict is the exit code; Osprey's
   `Error:` lines are already what `CommandStatusWriter` marks as errors.
2. **`SearchToolType.Osprey`**; the Search menu item **Osprey Search...** beside DIA-NN's;
   `SkylineWindow.ShowOspreySearchDlg` with an install gate that is `SimpleFileDownloader.
   DownloadRequiredFiles` under a `LongWaitDlg` (download size stated first) - no custom dialog.
3. **`FileUI\PeptideSearch\OspreySearchDlg`** with `OspreySearchControl : SearchControl`, pages: DIA data
   files; library source (a protein FASTA to predict from - the default - or an existing `.blib` for `-l`);
   modifications (the document's, mapped to CarafeSharp's `--fixMod`/`--varMod`); search settings
   (resolution unit|hram, fragment tolerance and unit, run and experiment FDR, protein FDR, threads, Use GPU
   as `BuildLibraryDlg` offers it, with the CUDA install reused from there); run.
4. **The command**: `-i <runs> --fasta <fasta> | -l <blib> -o <doc>.osprey.blib --torch-runtimes <Tools>
   --device auto|cpu --enzyme/--miss-c from the FASTA page, --fixMod/--varMod from the modifications page,
   --resolution, --fragment-tolerance, --fragment-unit, --run-fdr, --experiment-fdr, --protein-fdr,
   --threads, --log-file`. The output name and the overwrite-or-append prompt follow
   `DiannSearchDlg.cs:595-621`.
5. **Hand-off**: Finish opens `ImportPeptideSearchDlg` through the existing-library overload with the
   `.blib`, the FASTA settings and the found results files pre-filled; the DIA pages (chromatograms,
   transition settings, full scan, FASTA/decoys, associate proteins) are the standard ones. Whether the
   `.blib` becomes the document library or a non-document library is Decision 3.
6. **Tests**: `TestFunctional\OspreySearchTest` modelled on `DiannSearchTest`, on Osprey's Stellar subset
   (`Osprey.Test\TestData\StellarSubset.zip`: the runs and `hela-filtered.fasta`), with Osprey found through
   the registered tool path when `SKYLINE_TEST_OSPREY_EXE` names a local build (the developer loop) and
   through the mirror zip otherwise (TeamCity); `TestRunnerFormLookup.csv` entries; the preset round-trip
   only if presets are in (Decision 4).

## Decisions for Brendan

1. **Where the wizard lives**: its own **Search > Osprey Search...** wizard (DIA-NN's and EncyclopeDIA's
   pattern; recommended - it is the seam that exists) versus Osprey as a choice inside the Import Peptide
   Search DIA workflow (no DIA engine abstraction exists there today; a larger change).
2. **Inputs in PR 1**: FASTA (mode 1, the one command) plus an existing `.blib` (`-l`), with tuning on the
   runs (`--training-input`, mode 2) and saved models (`--model`) left for PR 2 - or tuning in PR 1 since
   the options are CarafeSharp's declarations already hosted by Osprey.
3. **The `.blib`'s role**: the document library (DIA-NN's choice, written to the document's library name,
   with the overwrite/append prompt) or a non-document library added beside it (EncyclopeDIA's route,
   what the existing-library overload does today). Recommended: the document library, since the search
   result is the document's evidence, which means teaching the overload to make it so.
4. **Presets and the `.cfg` import**: skip in PR 1 (Osprey has no settings file today); add a preset list
   when the settings page has stabilized.
5. **The download source**: start with the TeamCity artifact of the pinned Osprey build mirrored to
   `ci.skyline.ms/skyline_tool_testing_mirror/Osprey-<version>-win-x64.zip` (the test path) and a release
   URL to be named later; or publish the zip now to a `skyline.ms/home/software/Osprey` files folder as
   the release site, the way ProteoWizard publishes its installer. Either way someone with access uploads
   the zip - the PR cannot.
6. **The package size**: the win-x64 zip carries `torch\cpu` (256 MB) and the models (25 MB), which
   Skyline already installs for AlphaPeptDeep. PR 3 would add `--torch-cpu <folder>` beside
   `--torch-runtimes` and a Skyline-bound package without them (a `package.ps1 -ForSkyline` leg), cutting
   the download to the self-contained .NET runtime plus Osprey. Not for PR 1.

## PR plan

| PR | Holds |
|---|---|
| **1 (tonight)** | `OspreyHelpers`, `SearchToolType.Osprey`, the menu item and install gate, `OspreySearchDlg` with the pages above, the hand-off through the existing-library overload, `OspreySearchTest` on the Stellar subset against a local Osprey.exe, resources, form lookup entries |
| **2** | Tuning (`--training-input`, `--model`) and the saved-model list; presets; the GPU choice wired to `TorchRuntimes` with the CUDA install; the tutorial-style perf test on real data |
| **3** | The Skyline-bound Osprey package without libtorch and the models (`--torch-cpu`), the release site, the mirror zip for TeamCity |

## Gates

- `Build-Skyline.ps1 -SourceRoot C:/proj/pwiz -Summary`; `Run-Tests.ps1 -SourceRoot C:/proj/pwiz -TestName
  "OspreySearchTest,CodeInspection,CheckForMissingResources" -Summary` (with `SKYLINE_TEST_OSPREY_EXE`
  pointing at `pwiz_tools\Osprey\Osprey\bin\x64\Debug\net10.0\Osprey.exe` until the mirror zip exists)
- `Build-Osprey.ps1 -SourceRoot C:/proj/pwiz -Configuration Debug -RunTests -Summary` if Osprey changes
  (it should not in PR 1)
- `pwsh -File C:/proj/pwiz/pwiz_tools/Skyline/tcinspect.ps1` before the push; `/code-review medium`;
  bt209 and the Perf and Tutorial config on the PR

## Tasks (PR 1)

- [ ] Verify Osprey's progress lines parse through `ProcessRunner` (a `NN%` line per update); if not, the
      smallest Osprey change that makes them
- [ ] `OspreyHelpers`: version, folders, download info, command line, `RunSearch`
- [ ] `SearchToolType.Osprey`; menu item; `ShowOspreySearchDlg` with the download gate
- [ ] `OspreySearchDlg` and `OspreySearchControl`: the five pages, validation, the overwrite prompt
- [ ] The hand-off to `ImportPeptideSearchDlg` and, per Decision 3, the document-library behaviour
- [ ] `OspreySearchTest` end to end on the Stellar subset; form lookup entries; resources
- [ ] Gates; `/code-review medium`; PR

## Progress Log

### 2026-10-23 - Designed

Survey by a read-only agent over `pwiz_tools\Skyline` (DIA-NN's wizard, download, process, hand-off,
tests), the design above, and six decisions for Brendan. The CarafeSharp-in-Skyline numbers that frame
Decision 6: `torch\cpu` 256 MB on disk (76 MB zipped), the models 25 MB, TorchSharp 3 MB; Osprey's own
installer is 105 MB compressed, 393 MB installed, with the same libtorch and models plus a self-contained
.NET runtime.
