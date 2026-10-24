# TODO-20261023_skyline_osprey_search.md

## Branch Information
- **Branch**: `Skyline/work/20261023_skyline_osprey_search` (to be cut from `master` at the start of the
  night session of 2026-10-23; master holds #4909 and #4911)
- **Base**: `master`
- **Created**: 2026-10-23
- **Status**: PR 1 built and gated on the branch by the night session of 2026-10-23 (four commits, last
  638c25cd65; test, CodeInspection, CheckForMissingResources, tcinspect, `/code-review medium` all
  done; real-data run clean). Not pushed: the morning opens the PR (`ai/.tmp/handoff-20261023.md` has
  the commands and the PR body) and decides the mirror zip for TeamCity
- **GitHub Issue**: (none)
- **Module**: `skyline`
- **PR**: #4913 (opened 2026-10-24; bt209, bt210, TestConnected and Code Inspection queued on it, Perf and
  Tutorials deferred)
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
   files; the protein FASTA to predict the library from - the default and what the page asks for, as a
   DDA search asks for its FASTA, with Carafe closing the gap between the FASTA and the library Osprey
   searches (scenario 1 of the Osprey-Carafe integration); an existing `.blib` (`-l`) is an allowed
   alternative on the same page, secondary in the layout, in PR 1 if it costs little and PR 2 otherwise;
   the steel thread the night session proves is the FASTA path; modifications
   (the document's, mapped to CarafeSharp's `--fixMod`/`--varMod`); search settings (resolution unit|hram,
   fragment tolerance and unit, run and experiment FDR, protein FDR, threads, Use GPU as `BuildLibraryDlg`
   offers it, with the CUDA install reused from there); run. The library is predicted with the default
   Carafe source and the pretrained AlphaPeptDeep model, as the Build Library form does when Carafe is the
   source; a fine-tuned model and tuning on the runs are PR 2.
4. **The command**: `-i <runs> --fasta <fasta> (or -l <blib>) -o <doc>.osprey.blib --torch-runtimes <Tools>
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

## Decisions (Brendan, 2026-10-23)

1. **Where the wizard lives**: its own **Search > Osprey Search...** wizard, parallel to DIA-NN's and
   EncyclopeDIA's - the seam that exists. Brendan's reservation, to return to later: from the user's side
   the model feels off, with File > Search > Peptide Search serving several DDA engines (Comet, MS Amanda,
   Tide, MS-GF+) while each DIA tool has a menu item of its own. EncyclopeDIA may go away eventually; its
   workflow is the most particular (a library built with Koina first).
2. **Inputs in PR 1**: a protein FASTA is the default expectation, as in a DDA search, and Carafe closes
   the gap between it and the library Osprey needs - that is what users now expect of a DIA search tool.
   The library is predicted with the default Carafe source and the pretrained AlphaPeptDeep model, as the
   Build Library form does when Carafe is selected. The PR must not require an input library; it may also
   accept an existing `.blib` as an alternative, secondary in the page. Tuning on the runs
   (`--training-input`) and a fine-tuned model (`--model`) are PR 2.
3. **The `.blib`'s role**: the document library, written to the document's library name with DIA-NN's
   overwrite-or-append prompt; the existing-library route learns the document case.
4. **Presets and the `.cfg` import**: not in PR 1.
5. **The download source** (revised 2026-10-24): tests find Osprey the way SkylineNightly finds
   SkylineTester - the latest successful `ProteoWizard_OspreyWindowsNet` build on a designated branch
   (master for Skyline master), through TeamCity's REST API, which the Osprey project opens to guest
   access (no token; checked 2026-10-24: build #1110 at e0da8ae319 lists
   `Osprey-26.1.1.296-win-x64.zip`, 156 MB). The zip's version is read from the artifact name and the
   download is addressed by build id. The shipping pin is the artifact of the pinned build until a
   release process exists; the tool testing mirror is not used. The release process itself (a TeamCity
   deployment config with the Deploy button that pins and tags an Osprey build, as Matt's monthly
   ProteoWizard job and the Docker publish configs do) is for Brendan to return to.
7. **The menu item is hidden outside developer builds** (Brendan, 2026-10-24): the wizard and its test
   are fully present, but Search > Osprey Search... shows only when `Install.IsDeveloperInstall`, so this
   PR merging to master does not decide Osprey's release.
6. **The package size**: PR 3 (`--torch-cpu` beside `--torch-runtimes` and a Skyline-bound package without
   libtorch and the models). Not PR 1.

## PR plan

| PR | Holds |
|---|---|
| **1 (tonight)** | The steel thread: `OspreyHelpers`, `SearchToolType.Osprey`, the menu item and install gate, `OspreySearchDlg` with the pages above (FASTA the only library source), the hand-off making Osprey's `.blib` the document library, `OspreySearchTest` on the Stellar subset against a local Osprey.exe, resources, form lookup entries |
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

- [x] Verify Osprey's progress lines parse through `ProcessRunner` (a `NN%` line per update); if not, the
      smallest Osprey change that makes them - by reading: `ProcessStreamReader` interleaves stderr (where
      Osprey writes) with stdout, and `ProgressReporter` writes `"<indent>  NN%"` lines, which
      `ProcessRunner.Run` parses from the last space-separated token. Confirmed empirically by the test's
      progress-bar assertion
- [x] `OspreyHelpers`: version, folders, download info, command line, `RunSearch`
- [x] `SearchToolType.Osprey`; menu item; `ShowOspreySearchDlg` with the download gate
- [x] `OspreySearchDlg` and `OspreySearchControl`: the five pages, validation, the overwrite prompt
- [x] The hand-off to `ImportPeptideSearchDlg` with Osprey's `.blib` as the document library (Decision 3)
- [x] `OspreySearchTest` end to end on the Stellar subset; form lookup entries; resources
- [x] Gates; `/code-review medium` (9 findings, 8 fixed); tcinspect clean
- [x] Osprey resolved from TeamCity for tests; the menu item hidden outside developer builds
- [ ] Push, open the PR (body drafted); the release leg (Deploy button) when Brendan returns to it

## Corrections to the design found while building (night of 2026-10-23)

- **No `--log-file`.** Osprey's `--log-file` replaces its console writer entirely (`Program.OpenOutput`),
  so the wizard would see nothing. `OspreyHelpers.RunSearch` tees Osprey's output itself to
  `<doc>.osprey\osprey-skyline-stdout.log`, as the DIA-NN path does beside its `--out`.
- **`--work-dir <doc>.osprey`.** Without it Osprey writes its `.spectra.bin` caches and scores parquets
  beside the raw data files. The predicted library lands in that folder too (`<doc>.predicted.blib`).
- **The Stellar subset has no FASTA.** `Osprey.Test\TestData\StellarSubset.zip` holds the three mzMLs and
  the library TSVs, not `hela-filtered.fasta`. `TestFunctional\OspreySearchTest.zip` holds the mzMLs and a
  synthetic `stellar-subset-proteins.fasta` built the way `SubsetPipelineTest.LibraryBuild` builds its
  FASTA (each subset protein's tryptic peptides joined end to end), by
  `ai/.tmp/sessions/20261023-osprey-search/New-OspreySearchTestZip.ps1`.
- **Enzyme and modifications map by behavior, not name.** Skyline references `CarafeSharp.Proteome`
  already, so `OspreyHelpers.GetCarafeEnzymeIndex` finds the Carafe enzyme whose cleavage decision
  matches Skyline's over every residue pair (Skyline "Trypsin/P" is Carafe "Trypsin (no P rule)"), and
  `GetCarafeModificationIds` matches `StaticMod.UnimodId` and site against `CarafeModification.
  TopModifications`. Unsupported ones are refused on the page with their names.
- **Document settings feed the digest.** Peptide length, precursor charges and the variable-mod limit
  come from the document's filter and modification settings; the pages show resolution, fragment
  tolerance and unit (defaults follow Osprey's: 10 ppm hram, 0.5 m/z unit), run, experiment and protein
  FDR, and threads. `--device auto`, so a CUDA runtime Skyline already installed in Tools is used (the
  Use GPU control is PR 2 as planned).
- **The modifications page starts from the document's structural modifications**, and the ones the search
  used are added to the document before the hand-off, because the existing-library route of
  `ImportPeptideSearchDlg` skips the match-modifications page.
- **The document case in `AddExistingLibrary`**: when the existing library's path is the document
  library's (`<doc>.blib`), the spec is created with `ChangeDocumentLibrary(true)` and inserted at the head
  of the spectral library list, as a BlibBuild result is.
- **Overwrite, not append.** Osprey writes a whole `.blib`, so the prompt is Overwrite/Cancel, asked when
  Run is pressed (before Osprey starts), and the deletion follows DIA-NN's recipe (close streams, release
  the cached library, delete the `.blib` and `.redundant.blib`).
- **The pinned version is a placeholder**: `OSPREY_VERSION = 26.1.1.296`, the local Debug build's; the
  mirror zip `Osprey-26.1.1.296-win-x64.zip` does not exist yet (PR 3). The test finds Osprey through
  `SKYLINE_TEST_OSPREY_EXE`, then a build at `pwiz_tools\Osprey\Osprey\bin\x64\{Debug,Release}\net10.0`,
  then the mirror; on TeamCity the test will fail at the mirror step until the zip is uploaded.

## Progress Log

### 2026-10-23 - Designed

Survey by a read-only agent over `pwiz_tools\Skyline` (DIA-NN's wizard, download, process, hand-off,
tests), the design above, and six decisions for Brendan. The CarafeSharp-in-Skyline numbers that frame
Decision 6: `torch\cpu` 256 MB on disk (76 MB zipped), the models 25 MB, TorchSharp 3 MB; Osprey's own
installer is 105 MB compressed, 393 MB installed, with the same libtorch and models plus a self-contained
.NET runtime.

### 2026-10-23/24 (night session) - PR 1 built, the steel thread passes end to end

Branch cut at e0da8ae319. Every piece of PR 1 is in (see the table in `ai/.tmp/handoff-20261023.md`
and the Corrections section above). `OspreySearchTest` passes in 8 s wall (Osprey's whole run on the
subset is 2.6 s): the predicted library holds 341 target peptides / 1342 precursors (charges 2-3,
decoys included); 127 / 116 / 125 precursors at 1% run FDR; 144 at 1% experiment FDR; 76 protein
groups; the output `.blib` carries 144 spectra with 432 retention times over 3 runs; the finished
document has 81 proteins, 141 peptides, 3 replicates, with the `.blib` as the document library. The
progress bar moved, which is Osprey's `NN%` lines parsing through `ProcessRunner` unchanged.

One product finding from the first (failing) run: a default document's transition filter has
precursor charge 2 alone, so the library was predicted for 2+ only and the second pass had nothing at
1% experiment FDR (0 of 124). `OspreySearchDlg.GetPrecursorCharges` now applies the rule the Import
Peptide Search wizard's DIA transition settings page applies to a default document (charges 2 and
3), so the predicted library covers what the document will look for after the hand-off; a document
with its own charges keeps them. Osprey's `.blib` has no `IrtLibrary` table (checked in
`BlibOutputWriter`/`BlibSchema`), so the existing-library route shows no predictor prompt.

CodeInspection and CheckForMissingResources pass. `ai/scripts/fix-crlf.ps1` now also converts
untracked files (its filter skipped `??` rows, so new files stayed LF).

Commits on the branch: 6eb2199654 (the wizard), beb52034c6 (review fixes: the install check and the
download use the pinned path so a stale registration cannot pass for an install; an existing library
may not be the document library or a non-.blib/.tsv file; FDR thresholds exclude 0; the
document-library case comes before the library-list lookup; an N-terminal modification maps to
Carafe's peptide N-term entry only; `ImportPeptideSearch.DeleteDocumentLibrary` shared with DIA-NN),
74cd1be6d5 (below). `/code-review medium` returned 9 findings: 8 fixed, the container boilerplate
copy left as the pattern the three DIA wizards share. `tcinspect.ps1` clean.

**The existing-library and re-run leg** (74cd1be6d5). `OspreySearchTest` now runs the wizard a second
time on the same document, with the first run's predicted library (`<doc>.osprey\<doc>.predicted.blib`)
as the existing library and the Overwrite prompt accepted. Two defects it found, both fixed:
- Osprey refuses a `.blib` whose precursors carry decoy accessions unless `--decoys-in-library` is given
  (and refuses the flag for a library without a `DecoyPairs` table). The wizard passes the flag exactly
  when the chosen `.blib` has that table (`OspreyHelpers.LibraryHasDecoyPairs`), which Osprey's own
  predicted library does; a target-only library still gets Osprey's generated decoys.
- On a re-run the window's document kept the `Library` object loaded from the deleted `.blib`:
  `DeleteDocumentLibrary` evicts the manager's cache, but nothing reloads the document's object, and
  `AddExistingLibrary` returns early because the spec is already in the document.
  `OspreySearchDlg.ReloadDocumentLibrary` loads the rewritten file through the library manager and swaps
  it into the document with no settings change, when the search finishes and again at Finish.
Second-run numbers: Osprey reused the first run's valid stage outputs in the shared work dir and re-ran
only the second pass (416 ms): 144 of 200 target peptides at 1% experiment FDR, 76 protein groups, 144
spectra; the document ends with 83 proteins, 144 peptides, 3 replicates and one document library.
Noted, not changed: `ImportResults` skips replicates already in the document, so a re-run that finds new
peptides leaves them without chromatograms until results are re-imported (the DIA-NN path behaves the
same); and a default document's `MaxMissedCleavages` is 0, so the wizard's default digest is fully
tryptic where Osprey's own default is one missed cleavage - the FASTA page shows and controls it.

### 2026-10-24 (morning) - Osprey from TeamCity; the menu item hidden until release

Brendan's direction: tests should find Osprey as SkylineNightly finds SkylineTester (the latest
successful build on a designated branch, guaranteed to stay available), and releases should work like
the Docker publish configs (a Deploy button promoting a successful build), on the model of Matt's new
monthly ProteoWizard releases (`TODO-20261022_monthly_releases.md`: a TeamCity job pins and tags
`release-[daily-]YYYY-MM-DD-sha`, artifacts stay on TeamCity, an index goes to the website). Survey
notes: SkylineNightly needs a Bearer token (`TEAMCITY_NIGHTLY_TEST_AUTH_TOKEN`) because guest access
was withdrawn for its project; the Osprey project still allows guest access to the REST API and
artifacts (checked 2026-10-24); the Osprey Windows build is `ProteoWizard_OspreyWindowsNet`, with no
package or release config and no release branch; the Docker Deploy buttons are TeamCity deployment
configs with a `latest.lastSuccessful` artifact dependency, not GitHub workflows; the tool testing
mirror is an S3 bucket uploaded by hand.

Done in this PR: `OspreyHelpers.GetLatestBuildDownloadInfo` resolves the latest successful master
build through the guest REST API (the build by locator, then its artifact list, then the zip by build
id so a build finishing in between cannot change the download). The test uses it when neither
`SKYLINE_TEST_OSPREY_EXE` nor a sibling dev build exists, and checks the resolution (name, path, a
HEAD on the artifact) on every run. The pinned package's URL is the artifact of the TeamCity build
that made 26.1.1.296 (build id 4234706), valid while that build is kept. The forced TeamCity path
was run once locally: the 156 MB download, unzip into Tools and the two wizard runs passed in 17 s.
Search > Osprey Search... shows only when `Install.IsDeveloperInstall` (Decision 7).

Left for Brendan (he will return to it): the release leg - a "Publish Osprey Release" TeamCity
deployment config with the Deploy button that pins and tags an Osprey build, most cheaply by giving
Matt's `publish_monthly_release.py` a build-type parameter; a download page or GitHub Release can
point at the same pinned builds later.

### 2026-10-24 (night session) - the wizard's command line on real data

A sub-agent ran the exact command line the wizard builds for a default document (charges 2-3,
length 8-25, no missed cleavages, Carbamidomethyl fixed, unit resolution, 0.5 m/z) on the three real
Stellar HeLa sDIA files with `hela-filtered.fasta`, detached, from a snapshot of the Debug build
(v26.1.1.296): `D:\test\osprey-runs\skyline-wizard-stellar\run.log`, status
`ai/.tmp/agent-osprey-realdata-status.md`. Exit 0, no warnings, **3 min 42 s end to end including the
library prediction**. `--device auto` chose the GPU (RTX 4000 Ada) through the CUDA runtime in the
user's `%LOCALAPPDATA%\Osprey\torch` cache: 97,829 target peptides digested, 385,206 precursors
predicted in 24 s. Results: 23,559 / 24,010 / 24,372 precursors at 1% run FDR; 27,281 peptides at 1%
experiment FDR; 4,608 protein groups; 29,884 spectra with 89,652 retention times in the `.blib`
(verified with sqlite). Against the earlier one-command reference (`one-command-stellar\reference-6.log`,
Osprey's own defaults and a tuned CarafeSharp library): -10% precursors and spectra, -0.5% protein
groups, and faster overall (the reference's CPU prediction alone took 174 s). A cold Release rerun
(`skyline-wizard-stellar-release\run.log`, v26.1.1.296 at 89648e66b5) gave bit-identical counts in
**2 min 37 s** end to end: PredictLibrary 32.9 s, PerFileScoring 71.8 s, FirstPassFDR 64.1 s,
PerFileRescoring 15.7 s, SecondPassFDR 5.4 s. The Debug run's 93 s first pass was mostly the build;
the remaining 15 s over the reference's 49 s is not a regression claim (different library size,
threads and version).

Two things to carry into PR 2 and the PR description:
- The wizard passes `--torch-runtimes <Skyline Tools>`, so in Skyline the GPU is used only once
  Skyline's own CUDA install exists there (Build Library > Use GPU); the user's Osprey cache is not
  consulted. That is the design (one CUDA download serving both), and the Use GPU control is PR 2.
- The work folder beside the document is large: 4.34 GB here, of which 3.13 GB is the three
  `.spectra.bin` caches and 467 MB the predicted library. Worth a note in the wizard or a cleanup option.

### 2026-10-23 - Decisions taken; ready for the night session

Brendan: the FASTA is the default expectation, as in a DDA search, with Carafe closing the gap to the
library Osprey searches; an existing library is an allowed alternative, never a requirement; the default
Carafe source with the pretrained AlphaPeptDeep model as Build Library offers it; tuning in PR 2; the
separate wizard for now with the menu model to revisit. The night session starts here: cut `Skyline/work/20261023_skyline_osprey_search` from
master, verify Osprey's progress lines through `ProcessRunner` first, then the tasks in order. Osprey.exe
for the test loop: `pwiz_tools\Osprey\Osprey\bin\x64\Debug\net10.0\Osprey.exe` (master has #4909 and the
icon PR #4911 may land first; either is fine).
