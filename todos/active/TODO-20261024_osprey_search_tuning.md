# TODO-20261024_osprey_search_tuning.md

## Branch Information
- **Branch**: `Skyline/work/20261024_osprey_search_tuning`, cut from the head of
  `Skyline/work/20261023_skyline_osprey_search` (PR #4913, PR 1). Stacked: the PR opens against the PR 1
  branch and is retargeted to master when #4913 merges; the update after that squash-merge is
  `git merge origin/master`, never a rebase (version-control guide, the squash-merged-parent case)
- **Base**: PR #4913's branch, then `master`
- **Created**: 2026-10-24
- **Status**: Built and gated by the night session of 2026-10-24 (commits 1576709ba2, a169605c1e; not
  pushed). `OspreySearchTuningTest` passes in fr/ja/en; `OspreySearchPerfTest` passed its three scenarios
  on the Stellar runs (44.7 min); `/code-review medium` findings triaged. The morning pushes and opens the
  PR stacked on #4913 (`ai/.tmp/handoff-20261024.md` has the PR body)
- **GitHub Issue**: (none)
- **Module**: `skyline`
- **PR**: #4914 (opened 2026-10-25 against PR #4913's branch; retargeted to master the same morning after
  #4913 merged as d476f8a120, with `git merge origin/master` resolved to the branch's side on the eight
  shared files - merge commit 57584b8348, tree identical to a169605c1e)
- **Checkout**: `C:\proj\pwiz`
- **Continues**: `TODO-20261023_skyline_osprey_search.md` (PR 1: the FASTA path with the pretrained models,
  the existing-library alternative, Osprey from TeamCity, the menu item hidden outside developer builds)

## Goal

PR 2 of the Skyline-Osprey integration: the Osprey Search wizard supports modes 2 and 3 of Osprey's
one command (`pwiz_tools\Osprey\Osprey-workflow.html`, "Building the library"): **predict with a saved
model** (`--model`), and **tune a model, then predict** (`--training-input`, optionally from a saved
model), with the tuning runs chosen either as a subset of the searched runs or as a separate set of
runs collected for the tuning. The model a tuning search produces joins Skyline's saved-model list so
the next search, here or in Build Library, can use it.

## Why (Brendan, 2026-10-24)

PR 1 only predicts with the pretrained AlphaPeptDeep models (mode 1). Mike's libraries for the Stellar
data were built from a model tuned on the middle run (`..._21`), which is what regression.ps1's modes 13
and 14 reproduce; users need that path from the wizard. The saved-model piece reuses the UI #4849 added
to Build Library for Carafe, so the new work is only the training section.

## Design

**Where.** A page of its own, **Library Model**, between FASTA and Modifications (assumption: the FASTA
page's lower band holds the existing-library alternative and has no room for a file list; Brendan may
prefer it on the FASTA page). The page is skipped when an existing library is searched.

**Controls.**
1. **Model:** combo - Build Library's exactly: `SettingsListComboDriver<CarafeModelSpec>` over
   `Settings.Default.CarafeModelList` (Default (AlphaPeptDeep), the saved models, Add..., Edit
   current..., Edit list...), with `EditCarafeModelDlg` and `CarafeModelListDlg` as they are. Visible under
   both radios: it is the model predicted with, or the model the tuning starts from, which is what
   Osprey's `--model` means in each case.
2. Radio **Use existing model**: mode 3 (or mode 1 with Default). Command: `--model <path>` for a saved
   model; nothing for Default.
3. Radio **Fine-tune a new model on:** mode 2 (Brendan's design, 2026-10-24). Beneath it one checked
   list of runs, which starts EMPTY, and two ways to fill it:
   - **Browse...** (multi-select file dialog) adds runs collected for the tuning: they go to the TOP of
     the list, checked. A browsed file that is also a searched file is listed once, at the top, checked.
   - **[ ] Choose from searched files** (a checkbox below the list): checking it adds the search files
     from page 1 after any browsed ones, unchecked, in search order; unchecking removes them and their
     checks. Browsed files are untouched either way.
   - The tuning set is the checked items. The 446-file case: leave the box off, Browse the four, done.
     The middle-run case: check the box, check the run. A searched run tuned on is parsed once (shared
     cache); a browsed run not in the search is searched for the tuning only and is absent from the
     output. No Reset or Remove: nothing a control does discards a choice, and an unwanted browsed file
     is unchecked.
   - **Save as**: the new model's list name, default `<document> tuned on <first checked run>`.
   - Command: `--training-input <runs>` (plus `--model <path>` when the combo is a saved model, which
     tunes it further). Osprey writes `<work dir>\<doc>.model.zip` (`LibraryBuildWorkflow.ModelPath`:
     the output stem in the `--output-dir`, which is the wizard's `--work-dir`).
   - On success, before the hand-off, the model file is registered in `CarafeModelList` under the name
     (the Add path's code, not the dialog), replacing an entry of the same name after a prompt.
4. Validation on Next: a tuning run's file stem may not clash with another tuning run's or with a search
   file's (Osprey keys the spectra cache by stem; `Program.cs:1184-1203` refuses it); at least one
   tuning run; a non-empty unique name; "other files" exist.

**What Osprey gives for free.** A tuning run also in `-i` is parsed once (shared cache); the trained model
carries its training provenance in `manifest.json` (instrument, NCE, runs, cosine, RT R2, date), which
`CarafeModelListDlg` shows; `--model` with `--training-input` tunes the saved model further.

**Unchanged from PR 1.** `--device auto` (the GPU when Skyline's CUDA runtime is in Tools), the document
library as the output, the hidden menu item (Decision 7 of PR 1 stands until release).

## Tests

1. **`OspreySearchTuningTest`** (TestFunctional, the subset data of PR 1's test, seconds per run), one
   `[TestMethod]`, three wizard runs on one document:
   - Scenario 1: search all three subset runs; "Choose from searched files" on; check the middle one.
   - Scenario 2: search the two outer runs; Browse the middle one (held out; it arrives checked).
   - Scenario 3: search all three with the model scenario 1 saved (Use existing).
   Asserts: the command lines (`--training-input`, `--model`, no `-l`); the model from scenarios 1 and 2
   is the same model by the SHA-256 of its tensor entries in `manifest.json` (the manifest also carries
   the save date, so bytes differ); scenario 2's results differ from 1's (fewer runs); the model is in
   `CarafeModelList` under the given name and the combo offers it; scenario 3's library comes from the
   tuned model (its LibMetadata names the model). Use `--device cpu`? No: `--device auto` as the wizard
   passes it; the subset tunes in seconds on either.
2. **`OspreySearchPerfTest`** (TestPerf): `TestFilesZipPaths = GetPerfTestDataURL("osprey-testfiles-mzML-v2.zip")`,
   which lands in `<Downloads>\Perftests\osprey-testfiles-mzML-v2\`, the folder regression.ps1 uses too, and is
   not downloaded when present (RegressionData.ps1 mirrors `PathEx.GetDownloadsPath`). Scenarios 1 and 2 on
   the three Stellar runs with `hela-filtered.fasta` from that folder, tuning on `..._21` as Mike did.
   Asserts the same model equality and result counts near regression.ps1's modes 13/14 (read them from a
   current regression run, not from memory). Runs on this machine's GPU through `--device auto`.
3. PR 1's `OspreySearchTest` keeps passing (the new page is skipped on its existing-library leg and
   defaults to Use existing + Default on its FASTA leg, so its command lines are unchanged).

## Decisions

Taken (Brendan, 2026-10-24): radio buttons at the outer level, the standard `SettingsListComboDriver`
combo unchanged (no "Train new model..." pseudo-item), the training section the only new UI; the tuning
runs chosen in ONE checked list that starts empty, filled by Browse... (added runs on top, checked) and a
"Choose from searched files" checkbox (search files below, unchecked), so a 446-file search with four
tuning files never scrolls the search list; the Stellar regression data for the perf test, downloaded to
the shared Perftests folder; tune on the middle run.

Assumed by the night session unless Brendan says otherwise: a Library Model page of its own; the combo
doubles as the tuning start point; `--device auto` for the night's runs; the model name default above;
PR 2 opened stacked on #4913.

## Gates

- `Build-Skyline.ps1 -SourceRoot C:/proj/pwiz -Summary`; `Run-Tests.ps1 -SourceRoot C:/proj/pwiz -TestName
  "OspreySearchTest,OspreySearchTuningTest,CodeInspection,CheckForMissingResources" -Language "fr,ja,en" -Summary`
  (the French run is what caught PR 1's decimal default)
- `Run-Tests.ps1 ... -TestName OspreySearchPerfTest -RunPerfTests` (switch name to confirm in the script)
- `pwsh -File C:/proj/pwiz/pwiz_tools/Skyline/tcinspect.ps1`; `/code-review medium` before the PR
- No Osprey change (if the wizard needs one, stop and report)

## Night-session plan (2026-10-24)

Order, each a commit with its test leg, so the morning can take the first N:
1. The Library Model page with Use existing + the combo (mode 3), test scenario 3 against a model already
   on this machine (`D:\test\carafe-models\Stellar-gpu-tuned.model.zip`, tuned on `_21`) for the real-data check
2. Train on selected search files (scenario 1), model saved into the list
3. Train on other files (scenario 2), the model-equality assertion
4. `OspreySearchPerfTest` on the Stellar regression data
5. Gates, review, TODO, handoff; no push

Budget rules from the night of 2026-10-23: the survey is done (above); sub-agents run the test loops and
the review; the parent reads reports, synthesizes and commits; re-measure context at 30 minutes.

## Tasks

- [x] Branch; the Library Model page (designer, resx, resources) with the two radios and the combo
- [x] `OspreyConfig.ModelPath` / `TrainingInputs`; `BuildCommandLine` emits `--model` and `--training-input`
- [x] Register the tuned model in `CarafeModelList` after a successful tuning search
- [x] Validation (stems, name, files)
- [x] `OspreySearchTuningTest` scenarios 1-3; `OspreySearchPerfTest`
- [x] Gates (fr/ja/en tests, CodeInspection, CheckForMissingResources); `/code-review medium` (9 findings, 2 fixed)
- [x] tcinspect clean on a169605c1e
- [x] Pushed; PR #4914 opened stacked on #4913 (2026-10-25 morning, at Brendan's request)
- [x] Retargeted to master after #4913 merged (2026-10-25)
- [ ] Brendan reviews the UI; TeamCity green on #4914 (the legacy "Skyline Code Inspection" config will
  overwrite bt209's inspection status with its error on every new commit until Matt retires it)

## Corrections to the design found while building (night of 2026-10-24)

- **The subset cannot tune on the middle run alone.** Probed before writing the test
  (`D:\test\osprey-runs\tuning-probe\run.log`): `--training-input <_21>` alone exits 1 with "0 precursors
  at 1.0% run-level FDR" in the one-run first pass (the same reason `SubsetPipelineTest.LibraryTuning`
  tunes on all three). So `OspreySearchTuningTest` tunes on all three runs in both tuning scenarios:
  scenario 1 checks all three searched files; scenario 2 searches the outer two and browses all three
  (the middle run held out of the search, the browsed-searched files listed once at the top). Tuning on
  all three takes 17 s on the CPU (`run-all.log`), and two trainings gave identical ms2/rt safetensors
  SHA-256, so the model-equality assertion holds between the two scenarios. The perf test keeps the
  middle-run tuning, which works at full scale.
- **Three documents, not one.** Osprey finds a model current when the tuning runs are unchanged, so a
  second tuning on the same document would skip the training (and the equality would be trivial); and
  the predicted library of a saved-model run on a document that already tuned might be found current
  too. Each scenario gets its own document (same folder); the overwrite prompt stays covered by PR 1's test.
- **The replace prompt is asked at Next, not at the end.** A model name already in the list is confirmed
  (Yes/No) when leaving the Library Model page, before a run that can take an hour, and the answer is
  remembered for that name; the registration after the run replaces the entry without asking again.
- **The registered model is a copy named after the model** (`<work dir>\models\<name>.model.zip`,
  `OspreyHelpers.GetRegisteredModelPath`), found by `/code-review`: Osprey writes every tuning of a
  document to `<work dir>\<doc>.model.zip`, so a second tuning under another name would overwrite the
  file the first listed model pointed to. The copy also lets a document tune further from its own saved
  model, since Osprey refuses only `--model` equal to its own output path (the page still refuses that
  path with its own message).
- **Two searched runs with one file name are refused on the data files page** (also from the review):
  the stem clash matters to every search, not only a tuning one.
- The build gate: Build-Skyline.ps1 refused to run while an idle SkylineTester from this checkout was
  open (started 15:48, no test running); the night session closed it with a normal window close.

## Morning of 2026-10-25 (Brendan reviewing the perf run)

- **Use GPU on the Library Model page** (Brendan): a checkbox beside the Model combo, since it applies to
  both choices. It is Build Library's Use GPU, so the logic moved out of `BuildLibraryDlg` into
  `SettingsUI\UseGpuDriver` and both forms drive it; the one difference is that Osprey predicts in its own
  process, so the "runtime already loaded, restart Skyline" rule applies only in Build Library. The wizard
  now sends `--device gpu` or `--device cpu` (Osprey's `gpu` is a requirement, so the box guards the CUDA
  install first, as Build Library does) and `--torch-runtimes <TorchRuntimes.RuntimesDirectory>`; the
  choice is remembered in `Settings.Default.AlphaPeptDeepUseGpu`, shared with Build Library. PR 1's
  `--device auto` is gone. Note for the real Skyline on this machine: the CUDA runtime Osprey installed is in
  `%LOCALAPPDATA%\Osprey\torch`, which Skyline's Tools folder does not see; Use GPU here offers the download.
- **The perf test does one fine-tune**: the outer runs searched with `_21` browsed in and held out (the
  single-run tuning the subset cannot do), then the three runs with the saved model. Tuning on `_21` from
  the searched files was dropped (the same tuning through the other list, which the functional test
  covers; it doubled the run to 47 min). `SKYLINE_TEST_OSPREY_TORCH_RUNTIMES=<runtimes folder>` (the
  folder with `libtorch-cuda-12.8-win-x64.2.10.0` in it; Osprey's own is `%LOCALAPPDATA%\Osprey\torch`)
  points the wizard at that CUDA runtime and checks Use GPU; `Run-Tests.ps1 -EnvironmentVariables` passes it.
  The first try named `%LOCALAPPDATA%\Osprey` and failed the test's own precondition: the installer keeps
  the runtime directly under the runtimes folder, with no `torch` segment of its own. With the right
  folder the test passed on the GPU (NVIDIA RTX 4000 Ada) in 818 s for its two scenarios, against about
  28 min for the same two on the CPU (47 min for the old three).
- Still open from the review of the run: an Open Log button on the run page, and a segmented progress bar
  driven by Osprey's `[TASK]` lines (the bar now restarts per phase and freezes through the fine-tune).
- **Fine-tuning starts from AlphaPeptDeep only** (Brendan, after the on-screen review): choosing the
  Fine-tune radio sets the Model combo to "Default (AlphaPeptDeep)" and disables it, so the page states
  what the tuning starts from; "Use this model" re-enables the combo and restores the earlier choice. Osprey
  can tune a saved model further, but chained fine-tunes compound drift and are less tested, so that is not
  offered until users ask (or more base models arrive). The "model this search writes" refusal went with it.
- **No "Save as"** (Brendan): the fine-tuned model is a document support file like the document library,
  copied beside the document as `<doc>.model.zip` (`OspreyHelpers.GetDocumentModelPath`), and nothing joins
  the model list. A user who wants it for other documents adds it by name through the list's Add..., which
  shows what the file was trained on. Fine-tuning is thus a straight-through choice: radio, runs, Next. When
  the document already has a model, Next asks (OK/Cancel) before the run overwrites it, since a list entry
  may point at the file; Cancel stays on the page. The default-name logic, the replace prompt and the
  automatic registration went, with their strings. Why: a required name and a growing list for the basic
  case would stop users at exactly the point they were told fine-tuning helps.
- **Page titles** (Brendan): the Osprey and DIA-NN wizards now show the current page's name in a title panel
  above the pages, the Import Peptide Search wizard's title region (which has one panel per page; here one
  panel on the form, since `WizardPages` hides the tabs, so only the tab control moved down). EncyclopeDIA's
  wizard already had per-page title panels.
- **Review pauses moved to the perf test** (Brendan: pauses are not committed in functional tests, and
  CodeInspection may flag them). `OspreySearchPerfTest` is now the lab's workflow, three Stellar runs
  searched and tuned on the middle one chosen from the searched files, with a `PauseTest` on each page of
  that search for Brendan's on-screen trial (`Run-Tests.ps1 -TestName OspreySearchPerfTest -ShowUI
  -EnvironmentVariables "SKYLINE_TEST_OSPREY_TORCH_RUNTIMES=$env:LOCALAPPDATA\Osprey\torch"`); the saved
  model is then added to the list by name and used for a second search. The held-out scenario stays in
  the subset test. **Remove the pauses before the merge.** A pause is for looking: a click on a wizard
  control that opens a dialog fails the run after 10 s (`CommonAlertDlg.ShowWithTimeout`), which is how
  the first on-screen run ended (the Use GPU box, clicked by hand, offered the CUDA download).

## Follow-ups for the next session (Brendan, after the on-screen review of 2026-10-25)

- [x] Progress bar: segments from Osprey's `[TASK]` lines, sub-progress from the `file N/M:` lines in the PerFile
  tasks (evening of 2026-10-25, below). Before: the NN% lines were consumed by `ProcessRunner.Run` (set
  PercentComplete, never shown), so the bar restarted at every phase that printed 100% and froze through the
  fine-tune; no flag is passed to Osprey.
- [x] An "Open Log" button on the run page, right of "Show timestamps", for `<doc>.osprey\osprey-skyline-stdout.log`.
- The afternoon's changes (no Save as, title panels, combo snap, extension-less list, the perf test as the
  lab's workflow) are committed as c4032bf58b and pushed; the gate passed. The review pauses were removed
  before the commit (CodeInspection forbids `PauseTest` in checked-in tests, including TestPerf).
- Still open: PR 1's stale Osprey registration when the pinned package is already installed
  (`SkylineFiles.EnsureOspreyInstalled`), from the review; and Brendan's look at the new bar on a real run
  (the fine-tune segment does not move while the epochs print: its `epoch N/M` lines are indented and come
  in two series, RT then MS2, so they are left alone rather than guessed at).

## Evening of 2026-10-25 - the progress bar and Open Log

- **The bar follows Osprey's tasks** (`OspreyProgressMonitor` in `Model\Lib\OspreyHelpers.cs`). It wraps the
  wizard's monitor as the one `ProcessRunner` reports to, with the runner's percent parsing OFF
  (`updateProgressPercentage: false`, the DIA-NN path's arrangement), so every line arrives as a message and
  the bar is decided from them: `[TASK] name:starting` opens a segment (`ChangeSegments`, rebuilt on every
  line because the runner's own status never sees them), `:done` and `:skipping (outputs valid)` complete it.
  The segment count is known up front from the config (4 for an existing library, 5 with a predicted library,
  11 with tuning runs: training library + 4, TrainModel, PredictLibrary + 4) and widens if Osprey prints more.
  Within PerFileScoring/PerFileRescoring the `file N/M:` lines set the segment to (N-1)/M (regex on
  non-indented lines, no `\b`, so the Japanese `ファイル2/3を...` counts); within the other tasks Osprey's own
  `NN%` lines do. A segment never moves backwards (Osprey's percentages restart at every step), and a later
  N/M series that starts over (the training exports after the last re-scored file) or with another count is
  ignored, the task's count being its first file line's. The bar's text is the task's name (LibResources,
  seven strings) with the file `N/M` or the task's own percentage; the run page switches to `CustomText` for
  the run and back to `Percentage` for the done/failed milestone. The log box keeps every line as Osprey
  printed it, `[TASK]` lines included, so it never mixes translated and machine text. A cancel or error
  status passes through untouched (`ChangePercentComplete` would reset it to running).
- `/code-review medium` on the diff: 7 findings, 6 fixed (cancel pass-through, the file-count rule, the raw
  `[TASK]` lines, the stale RunSearch summary, the DIA-NN path with an unsaved document, the test's static
  recorder) and the stale-log point, first as a truncating tee, then at Brendan's request as the rollover
  above for both engines.
- **Open Log** is on the shared `SearchControl` (so DIA-NN's run page has it too, for `diann-skyline-stdout.log`
  beside the document): `SetLogFilePath` shows the button, `OpenLog` shell-opens the file or says it has not
  been written yet. The "Show timestamps" box moved left (157 from 238, in the ja and zh-Hans resx too, which
  carry layout) to make room at the right edge. The tee is auto-flushed and shared for reading, so the file
  opened in an editor (Notepad++ with Monitoring on) scrolls as the run goes, the command-line experience
  Brendan wanted. **Log rollover** (Brendan, 2026-10-25 evening, for both engines): before a search starts,
  an earlier log at the fixed name moves aside as `<name>_<yyyy-MM-dd_HH-mm-ss>.log` stamped with the OLD
  file's last write (when that search ended), not with now; a same-second collision takes a `-N` suffix
  (`FileTimeEx.RollWithTimeStamp` in `Util\UtilIO.cs`, the scripts' `run.log` convention from
  `OspreyDatasetRun.psm1`). Osprey rolls in its tee (one process per search); DIA-NN rolls once at the top of
  `DiannHelpers.RunSearch`, because its predictor and search are two processes appending to the one file.
- **`--timestamp`** (Brendan, from the on-screen run): Osprey now stamps every line (`[yyyy/MM/dd HH:mm:ss]\t`,
  `CommandStatusWriter`'s format) so the log on disk carries the time of each line, and the wizard strips
  the stamp before display (`CommandStatusWriter.StripTimeStamp`, in the monitor), so the run page and its
  own "Show timestamps" box are unchanged. `ProcessRunner` strips it too before its `Error:`/`Warning:`
  first-word check, since Osprey's error lines go to stdout through the same stamped writer and would
  otherwise drop out of a failed search's message.
- Tests: `OspreyProgressMonitorTest` (Test.csproj) feeds the line shapes of the real logs
  (`D:\test\osprey-runs\skyline-wizard-stellar-release\run.log`, `tuning-probe\run-all.log`) and checks the
  segment, its percentage and the overall percentage at each step, the skip-and-resume case, the growth case
  and the Japanese file line; `OspreySearchTest.RunSearch` asserts the button and its path after the run.

## PR 3: Osprey's package is the engine package (decided with Brendan, 2026-10-26; ready to start)

**Why.** #4849 (2026-10-23) made AlphaPeptDeep library building run in process through CarafeSharp, which put
`torch\cpu` (256 MB, 76 MB zipped), the models (25 MB) and TorchSharp into Skyline's bin; the new Inno
installer stages the whole bin, so the daily zip goes from 94 MB (26.1.1.279, 2026-10-06) to about 195 MB
for a feature most users never touch (bt209's SkylineTester.zip jumped 258 -> 384 MB at that commit).
Osprey's own package already carries `torch\cpu` and the models, chooses its libtorch at run time and
downloads the CUDA one (#4909), and exposes the library phases as `--task PredictLibrary` / `--task TrainModel`.

**The refactor.**
1. Build Library's Carafe/AlphaPeptDeep path downloads the Osprey package at first use, to the same Tools
   location Osprey Search uses (`OspreyHelpers` download info, `SkylineFiles.EnsureOspreyInstalled`), and
   builds the library by running `Osprey.exe --task PredictLibrary` (and `--task TrainModel` for tuning)
   out of process, through the same ProcessRunner + log tee + rollover + `OspreyProgressMonitor` the wizard
   uses. Device and CUDA handling are Osprey's (`--device`, `--torch-runtimes`), so Build Library's
   "runtime already loaded, restart Skyline" rule goes.
2. Skyline stops shipping `torch\cpu`, the models and TorchSharp: remove `LibTorchRuntimeLayout.targets`
   and the model Content items from `Skyline.csproj`; `TorchRuntimes` keeps only what the wizard's Use GPU
   still needs (the CUDA download into the shared folder Osprey is pointed at), or moves to Osprey entirely.
   `CarafeSharp.Proteome` stays in process for reading `.model.zip` manifests (no torch).
3. The Osprey package also carries `CarafeSharp.exe` (the Carafe-shaped CLI, `pwiz_tools\CarafeSharp\CarafeSharp`)
   for scripts and parity testing; Skyline does not depend on it. Consider a framework-dependent publish
   to cut the first-use download below the self-contained 156 MB, since Skyline's machine has .NET 10.
4. The stale registration when the pinned package is installed (PR 1 review finding) is fixed in the shared
   `EnsureOspreyInstalled`.
5. Tests: TestAlphaPeptDeepBuildLibrary and the other in-process library tests move to the download seam
   OspreySearchTest uses (`EnsureOsprey`, `SKYLINE_TEST_OSPREY_TORCH_RUNTIMES` for the GPU).
The earlier PR 3 idea (`--torch-cpu`, Skyline-bound package without libtorch) is superseded: Osprey keeps
its own libtorch and Skyline borrows nothing.

**Still Brendan's, not PR work.** The Osprey release leg (a TeamCity deployment config with a Deploy button
that pins and tags a build), the TeamCity mirror zip, Decision 7 (un-hiding Search > Osprey Search...),
presets / `.cfg` import (Decision 4, optional), and OspreySearchPerfTest's 28 min on a CPU-only agent.
Stacked on #4914's branch until it merges; afterwards `git merge origin/master`, never rebase.

## Progress Log

### 2026-10-25 (late evening) - Issue #4916, TeamCity on PR 2, handoff

Filed #4916 (SCIEX wiff reader in the .NET 10 port: ~4 s per open, every metadata request fetches and
centroids peaks; assigned to Matt) from the perf investigation. PR #4914 TeamCity: 16/18 green on
b1cefa6ec1; TestManagingSearchTools failed once on a tools-folder Directory.Move access-denied in
`SettingsImporter` (not this PR's code), the Wine build red only as its snapshot dependency. Queued bt209
re-run 4235543 and the first Perf and Tutorial run 4235542 (includes OspreySearchPerfTest). Then (2026-10-26,
with Brendan) PR 3 was redefined after measuring the installer cost of in-process AlphaPeptDeep: Osprey's
package becomes the engine for Build Library too, section "PR 3: Osprey's package is the engine package".
Next session: read the two TeamCity results first, then start PR 3 from that section and the handoff.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20261024_osprey_search_tuning.md` before starting work.

### 2026-10-25 (evening) - Progress bar by task, Open Log button

Brendan's two follow-ups from the on-screen review ("Evening of 2026-10-25" above): `OspreyProgressMonitor`
segments the bar by Osprey's `[TASK]` lines with the per-file tasks advanced by their `file N/M:` lines, and
the shared run page has an Open Log button (Osprey's working-folder log, DIA-NN's document-folder log).
`OspreyProgressMonitorTest` added. Brendan reviewed the run page on screen (the perf test with temporary pauses,
GPU) and asked for log rollover for both engines and `--timestamp` on Osprey's log, both added. Gate on the
final code: OspreyProgressMonitorTest, OspreySearchTest, OspreySearchTuningTest, DiannSearchTest (3 tests),
CodeInspection, CheckForMissingResources all pass. Commit b1cefa6ec1, pushed to PR #4914. Open concern
(Brendan): OspreySearchPerfTest costs about 28 min on a CPU-only agent (14 min on this box's GPU), and the
perf runs are already long; the lever is dropping its saved-model search (the functional test covers that
path) or a smaller FASTA.

**Perf budget investigation** (evening, findings in `ai/.tmp/diatosrm-perf-findings-20261025.md`):
TestDiaToSrmTutorial is 141 s here steady-state (124 s of it the 35 GB chromatogram extraction, three files
at a time under TestRunner's workstation GC), 163-472 s on BRENDANX-UW7, 1,185-1,231 s on disk-bound
BSPRATT-UW2, and absent from the PR perf build; the 80-90 min memory was the screenshot-capture runs. The
PR perf build (3 h 31 min) spends 34 min downloading test data to a fresh agent, 8 min of it the same
zips again because the CI cleanup level deletes each zip after its test: keeping zips for the run and a
same-region mirror are the 20-30 min cut, with no test changed. TestDiannSearchTutorial is the largest
test there (36 min; 11.5 min here, CPU-bound in DIA-NN). Nightly: UW2 never finishes its perf-first pass
in 12 h (98 tests, 695 min) while UW7 does it in 267 min and runs 4,784 tests; Brendan is considering
moving overnight perf off the i7.

### 2026-10-24 - Designed

### 2026-10-24/25 (night session) - PR 2 built, gated, reviewed

Branch cut at 813c0a6867 (PR 1's head). Two probes on the subset before any code (`D:\test\osprey-runs\
tuning-probe`): one tuning run alone fails the first pass; all three tune in 17 s on the CPU with
bit-identical safetensors across two runs. Commit 1576709ba2: the Library Model page, the command-line
options, the registration, the validation, `OspreySearchTuningTest` (43 s), `OspreySearchTest` updated for
the page. Gates: `OspreySearchTest,OspreySearchTuningTest,CodeInspection,CheckForMissingResources` in
fr/ja/en all pass (163 s). A sub-agent wrote `OspreySearchPerfTest` on the shared Perftests Stellar data:
tuned on `_21` from the searched files, 32,519 library spectra across 3 runs (untuned 29,884; model MS2
PCC 0.9678 vs pretrained 0.9423, RT R2 0.9990, fine-tune 580 s on the CPU); `_21` held out, 30,780 across 2
runs with tensors identical to the first model's; the saved model, 32,546. `/code-review medium`: 9
findings, 2 fixed (commit a169605c1e: the registered model is a copy named after the model; the stem clash
is refused on the data files page), 7 dropped as PR 1 code or outside the branch (listed in the handoff).
The perf test re-run on a169605c1e (the consolidated helpers and the model copy) passed again, 2805 s;
tcinspect clean on a169605c1e after a first run that raced the builds (handoff).

### 2026-10-24 - Designed

Survey (read-only agent): the workflow doc's three modes; `--training-input` semantics (subset or
disjoint, no count limit, stem clash refused, held-out run absent from the output, `<stem>.model.zip`
in the output dir, `--model` tunes further); regression.ps1 and Skyline perf tests share
`<Downloads>\Perftests\osprey-testfiles-mzML-v2\` from the Panorama perftests URL; Build Library's model
combo and dialogs from #4849 (`TODO-20260928_AlphaPeptDeepSharp.md`); this machine's saved models are all
tuned on `_21`. Brendan settled the UI shape in conversation (Decisions).
