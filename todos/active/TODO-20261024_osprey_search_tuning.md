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
- **PR**: (none yet)
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
- [ ] Push; the stacked PR (body drafted in `ai/.tmp/sessions/20261024-osprey-tuning/pr-body.md`)

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

## Progress Log

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
