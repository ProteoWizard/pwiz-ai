# TODO-20261024_osprey_search_tuning.md

## Branch Information
- **Branch**: `Skyline/work/20261024_osprey_search_tuning`, cut from the head of
  `Skyline/work/20261023_skyline_osprey_search` (PR #4913, PR 1). Stacked: the PR opens against the PR 1
  branch and is retargeted to master when #4913 merges; the update after that squash-merge is
  `git merge origin/master`, never a rebase (version-control guide, the squash-merged-parent case)
- **Base**: PR #4913's branch, then `master`
- **Created**: 2026-10-24
- **Status**: Designed with Brendan 2026-10-24; the night session of 2026-10-24 builds it
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

- [ ] Branch; the Library Model page (designer, resx, resources) with the two radios and the combo
- [ ] `OspreyConfig.ModelPath` / `TrainingInputs`; `BuildCommandLine` emits `--model` and `--training-input`
- [ ] Register the tuned model in `CarafeModelList` after a successful tuning search
- [ ] Validation (stems, name, files)
- [ ] `OspreySearchTuningTest` scenarios 1-3; `OspreySearchPerfTest`
- [ ] Gates; `/code-review medium`; stacked PR

## Progress Log

### 2026-10-24 - Designed

Survey (read-only agent): the workflow doc's three modes; `--training-input` semantics (subset or
disjoint, no count limit, stem clash refused, held-out run absent from the output, `<stem>.model.zip`
in the output dir, `--model` tunes further); regression.ps1 and Skyline perf tests share
`<Downloads>\Perftests\osprey-testfiles-mzML-v2\` from the Panorama perftests URL; Build Library's model
combo and dialogs from #4849 (`TODO-20260928_AlphaPeptDeepSharp.md`); this machine's saved models are all
tuned on `_21`. Brendan settled the UI shape in conversation (Decisions).
