# TODO-20261026_build_library_carafe_wizard.md

## Branch Information
- **Branch**: `Skyline/work/20261026_build_library_carafe_wizard`
- **Base**: `master` (fb75aff35b, after PR #4917 merged)
- **Created**: 2026-10-26
- **Status**: In Progress
- **Module**: `skyline` (with Osprey / CarafeSharp changes where a feature needs them)
- **PR**: https://github.com/ProteoWizard/pwiz/pull/4925 (opened 2026-10-27)
- **Objective**: After choosing the AlphaPeptDeep (Carafe) source in Build Library, Next leads to wizard
  pages that decide what the library is predicted FOR and what the model is tuned ON, the design of the
  June 2024 Skyline-Carafe integration spec (`ai/.tmp/Skyline-Carafe Integration - Google Slides.pdf`,
  two slides) carried onto the Osprey engine PR #4917 put behind the dialog.
- **Requested by**: Brendan, 2026-10-26, as the feature PR that follows #4917
- **Follows**: `TODO-20261026_osprey_library_engine.md` (PR 3). Its testing cost is handled first by
  `TODO-osprey_test_subsetting.md`: this PR's functional tests need a subset on which one run tunes.

## The June 2024 design (the two slides)

- **Slide 1, "Skyline UI - for library building - Phase 2 (Carafe)"**: Build Library's first page with
  Data source: Files, AlphaPeptDeep, Carafe, Koina; choosing Carafe turns Finish into **Next**, as
  choosing Files does today.
- **Slide 2, "Skyline UI - for transfer learning"**: the second page, **Learn from:** a combo with two
  sources shown: **Skyline Results** (a "Learning document" path with Browse, a .sky file whose results
  the model learns from) and **Libraries** (a checklist of "Learning libraries", the document's spectral
  libraries whose measured spectra the model learns from). Finish on that page.

What has changed since: AlphaPeptDeep and Carafe are one source (the Model combo of #4849 holds the
pretrained models and saved fine-tuned models), the Osprey Search wizard's Library Model page (PR #4914)
already has the "Use this model / Fine-tune a new model on these runs" UI with a checked run list and
Use GPU, and Osprey predicts for Build Library through `--precursors` (#4917).

## What the infrastructure gives

- `BuildLibraryDlg` is already a wizard: `WizardPages` hides the `tabControlDataSource` tabs,
  `DataSourcePages { files, alpha, koina }`, Next/Previous/Finish buttons, and the Files source goes to
  a second page for its file list. A Carafe path can add pages the same way.
- The wizard's Library Model page (`OspreySearchDlg`, PR #4914): the model combo over
  `Settings.Default.CarafeModelList`, the Fine-tune radio with Browse... and "Choose from the searched
  files", Use GPU through `UseGpuDriver`, the validation (stems, files exist), the replace prompt. A
  shared user control for both dialogs is the first refactor this PR would make.
- Osprey's one command: `--fasta` + `--training-input` tunes on runs searched against a library
  predicted from the FASTA, writes `<out>.model.zip`, then predicts and searches; `--precursors` (#4917)
  predicts exactly a table's precursors, no search; `--model` predicts with a saved model.
- **CarafeSharp trains only from Osprey's training exports** (`TrainingSettings.cs:27-52`, the
  `--ms` usage text: "CarafeSharp reads no spectra: the fragment matches, XICs and peak boundaries come
  from Osprey's training export"). Anything that learns from something other than an Osprey search needs
  a writer of that export (`TrainingExportParquet`, the contract in `CarafeSharp.Contracts`).

## The candidate features, with what each needs

1. **Tune on data files searched by Osprey** (the slide's spirit, with today's engine). Page: the FASTA
   the tuning runs are searched against, the runs (the wizard's checked list), Use GPU. Osprey runs its
   tuning phases (predict the training library from the FASTA, search the runs, TrainModel) and then
   PredictLibrary over the document's precursor table with the tuned model; no final search, the runs'
   results are not imported - "cutting the Osprey search off from the normal pipeline". The model joins
   the saved-model list or sits beside the library.
   - Osprey: allow `--precursors` with `--training-input` and `--fasta` (the FASTA for the training
     library only; today `--fasta` and `--precursors` refuse each other), ending at PredictLibrary.
   - Skyline: the pages, the command line, the import of the tuned model into the list.
   - Exists end to end in Osprey today except the one combination; the cheapest feature.
   - **Brendan (2026-10-26)**: this is the one imagined. It needs almost the whole Osprey Search wizard's
     inputs - the FASTA to search with and any further search parameters - and ends not with a search
     result but with a fine-tuned Carafe predictor that predicts spectra for all the document's precursors.
     So the pages are the wizard's pages (data files, FASTA and digest, Library Model) reused inside
     Build Library, minus the import of the search.
2. **Predict from a full FASTA** instead of the document's precursors (what the Osprey Search wizard
   does). Page: a FASTA and the digest settings. Osprey: `--fasta` + `--task PredictLibrary` exists; the
   output is Carafe's `<out>.predicted.blib` with decoys and DecoyPairs, so Build Library would take that
   blib as it is (the wizard's document library already is one) rather than the peptdeep TSV path.
   - Skyline only, plus a decision on decoys in a Build Library library.
   - **Brendan (2026-10-26)**: as placed, an additional choice on top of feature 1: predict the (or an)
     entire FASTA rather than the document's precursors. Given feature 1, that may be the full searched
     FASTA, as Osprey does, or a second FASTA with any relationship to the first (subset, superset,
     intersection, disjoint), plus decoys and possibly entrapment. So "Predict for" has three answers:
     this document's precursors, the searched FASTA, another FASTA.
3. **Learn from Skyline results** (slide 2's first source). The document's own results, or a learning
   document's, become the training data: fragment chromatograms, peak boundaries and library ions are
   what the training export holds, and Skyline has them. Needs a Skyline writer of
   `TrainingExportParquet` records from a document's results, then CarafeSharp's TrainModel over those
   exports (no raw files read). The most valuable source for Skyline users, who curate their results;
   the largest piece of new work; a study of the export contract comes first.
   - **Brendan (2026-10-26)**: still interesting, and it seems to take only writing from Skyline the
     format Osprey writes for Carafe. A fully processed dataset imported into Skyline should be usable
     as a fine-tuning dataset for Carafe. The study is of `TrainingExportParquet` (the record per
     precursor per run: fragment matches, XICs, peak boundaries, q-value) against what a Skyline
     document's results hold, and of which training rules (`-cor`, masking, `-fdr`) then apply.
4. **Learn from libraries** (slide 2's second source). Measured spectral libraries (DDA) as MS2 training
   data, with library RTs for RT. Needs a library-to-export adapter in CarafeSharp and a look at how the
   training rules (XIC correlation, masking) apply without chromatograms. Research item.
   - **Brendan (2026-10-26)**: the least interesting, especially now that a library's source may well be
     Osprey, which could already have exported a fine-tuning file for Carafe. Lowest priority.

## The design (settled with Brendan, 2026-10-26)

**The principle the design is measured against**: the user specifies everything, then leaves. No wait in
the middle of saying what you want; a fine-tune that takes an hour runs after Finish, with the prediction
and the import, as one background job. The Osprey Search wizard already has one such break (its search
runs, then Import Peptide Search asks its questions), which Brendan intends to remove eventually; this
PR must not add a second. A separate tuning dialog that a user must wait on before finishing the library
(name the model, build, wait, come back) was considered and rejected for the primary path on this ground.

- **Build Library's primary path stays in Build Library.** After the AlphaPeptDeep source, the pages
  collect the tuning inputs up front, as the wizard's "Fine-tune a new model on these runs" radio does
  (PR 2's Library Model page: Use this model / Fine-tune on these runs, Browse..., Use GPU; here also the
  FASTA and digest the tuning runs are searched against, and any further search parameters, since the
  runs must be searched by Osprey first). Finish runs tune, predict and import as one job. The wizard's
  radio stays as it is: for the lab's common case, tuning on a subset of the search files, it is a few
  clicks, and that is the point of it.
- **The tuned model is a named support file beside the library**, `<library>.model.zip`, NOT added to the
  saved-model list - the same as the Osprey Search wizard's `<doc>.model.zip` (PR 2's decision). A user
  who wants it named and saved adds it later by Add... and pointing at the file, which shows what it was
  trained on; or takes the editor route below.
- **A secondary route, later or never**: a Build... button in `EditCarafeModelDlg` (the model list's
  Add... / Edit current... editor, which already has Name, a path with Browse..., and the details box)
  that opens the tuning wizard and puts the built `.model.zip` in the path box. It is a wait by nature,
  but a user taking it is mid-specification of nothing else; it serves "a model and no library yet" and
  reuse across documents. If built: no file is created first (a model is an output, unlike the iRT and
  ion mobility editors' databases), the output path sits on the wizard's first page prefilled from the
  Name, and the wizard ends on a run page with the progress bar, the log and Open Log, as the search does.
  The tuning wizard itself would be the Osprey Search wizard in a tune-only mode (stop at the model, no
  hand-off), not a new form.
- **The predict-for page**, for AlphaPeptDeep and Koina alike: **Document precursors** (the default,
  today's behaviour) or **Provided FASTA**, with the FASTA, and in either case the decisions about decoys
  and entrapment peptides. Skyline can digest the FASTA and add decoys and entrapment in process with
  CarafeSharp.Proteome (`Digester`, `EntrapmentFastaBuilder`, TorchSharp-free and already referenced),
  producing one precursor table that AlphaPeptDeep sends to Osprey's `--precursors` and Koina sends to
  its service - one implementation for both sources. Decoys in the table need a marker the peptdeep
  TSV's Decoy column and the blib carry (Osprey's own FASTA path writes DecoyPairs; detail to design).
- **Scope for the first PR**: the tuning pages (feature 1) and the predict-for page for both sources
  (feature 2); feature 3, Skyline results as the training source, as the PR after, once the export
  contract has been studied; the editor's Build... when wanted.
- The reuse of the wizard's pages as controls both `OspreySearchDlg` and `BuildLibraryDlg` host is the
  refactor to do first, gated by the existing `OspreySearchTest`, `OspreySearchTuningTest` and
  `AlphaPeptDeepUseGpuTest`.
- Osprey: allow `--precursors` with `--training-input` and a `--fasta` for the training library, ending
  at PredictLibrary over the table with the tuned model (today the two refuse each other).

## Tests

- Functional: a Build Library run per feature on the Stellar subset (feature 1 needs one-run tuning on
  the subset: `TODO-osprey_test_subsetting.md`), the page navigation and validation, fr/ja/en.
- Perf: one tuned Build Library run on the perf subset, inside the 5-minute budget that TODO sets.
- Osprey: `TestSubsetPrecursorTable` extended with the `--training-input` combination.

## Decisions

1. Decoys and entrapment for a Provided FASTA: decided and implemented in the session (see the
   progress entry of 2026-10-26): Skyline generates the decoys and CarafeSharp's
   `EntrapmentFastaBuilder` the entrapment peptides (or a FASTA the user supplies), for Koina too,
   and the library marks them in Carafe's DecoyPairs table.
2. The editor's Build... route: not in this PR, as the spec's "later or never" says.
3. Feature 3 is the PR after this one (the study of the export contract first).

Decided (2026-10-26): the tuning inputs live on Build Library's pages and run after Finish; the wizard's
radio stays; the tuned model is `<library>.model.zip` beside the library, not listed; a named, saved model
comes from Add... pointing at the file, or from the editor route.

## Progress Log

### 2026-10-26 - Written

From the two slides and the state after PR #4917; discussed with Brendan.

**Handoff from the session of 2026-10-26**: read `ai/.tmp/handoff-20261026_osprey_followups.md` first (build and test gotchas, the Osprey changes feature 1 needs, the code to reuse).

### 2026-10-26 (evening, autonomous session) - Implemented, local commits only, no push

Brendan's goal for the session: the full spec, plus a functional test that can pause on every page
for a live demo; nothing pushed, no PR. Three local commits: f770da6bb5 (Osprey, CarafeSharp, the wizard
pages as controls), cdf21b2c55 (Build Library's pages, the builder, the test) and 86546e2461
(CodeInspection fixes; CodeInspection green); see the session's
handoff `ai/.tmp/handoff-20261026_carafe_wizard.md`. `BuildLibraryCarafeWizardTest` passes end to end
(tuned build, saved-model build, FASTA build) in en-US, fr-FR and ja-JP, as do `AlphaPeptDeepUseGpuTest`,
`OspreySearchTuningTest`, `OspreySearchTest` and `KoinaSkylineIntegrationTest`. One `OspreySearchTest`
run timed out in its chromatogram import (720 s) while run paired with the Koina test and with git work
in the same checkout; alone it passed, so it is noted here rather than chased.

**Done**
- Osprey: `--precursors` with `--training-input` and `--fasta`: the FASTA names the training library,
  the tuning runs are searched against it, the models tuned, and the tuned models predict the table;
  no `--task` needed and no `-i` inputs (the run searches nothing but the tuning runs). `Program.LibraryBuildError`,
  `ValidateArgs`, `OspreyCommandArgs.InterpretLibraryBuild`, `LibraryBuildWorkflow.PhaseTask`; the usage
  text of `--precursors`. `TestSubsetPrecursorTable` has the tuned leg (cold, warm, refusals) and passes.
- CarafeSharp fix found by that test: `PrecursorTablePredictor` forced the AlphaPeptDeep RT model kind
  for any model folder, so a tuned Chronologer RT model was swapped for the pretrained one and the
  table came back with the pretrained RTs. The FASTA path's model-folder handling moved to
  `LibraryModels.ApplyModelDirectoryMeta` and both paths use it.
- Skyline refactor: the wizard's Library Model, Modifications and Search Settings pages are
  `OspreyLibraryModelControl`, `OspreyModificationsControl`, `OspreySearchSettingsControl`
  (FileUI/PeptideSearch), hosted by `OspreySearchDlg` with its public API delegating, so the existing
  tests drive it unchanged. `OspreySearchTuningTest` passes on the refactor. `UseGpuDriver` takes a
  `Control` owner. `WizardPages.AddPageControl` is the shared placement helper.
- A compact `OspreyFastaControl` (FASTA path, enzyme, missed cleavages) for Build Library's FASTA
  page: `ImportFastaControl` is laid out for a 425 px page and does not fit Build Library's 303 px
  pages (its text box collapses and the DDA panel falls off the page); the wizard keeps
  `ImportFastaControl` because Finish hands its `ImportSettings` on.
- Build Library (`BuildLibraryDlg`): pages `properties, files, predict_for, library_model, fasta,
  modifications, search_settings` with a history stack for Previous. Routes: Files -> files;
  Koina -> predict_for -> Finish; AlphaPeptDeep -> predict_for -> library_model -> (Use this model:
  Finish | Fine-tune: fasta -> modifications -> search_settings -> Finish). The Model combo and Use
  GPU moved from page 1's Carafe tab to the Library Model page (page 1's tab is now a description);
  the modification warning sits under the model page. Predict For: the document's precursors, or a
  protein FASTA digested with the document settings into a document of its own
  (`ImportPeptideSearch.ImportFasta`, under a LongWaitDlg at Finish) - one implementation for
  AlphaPeptDeep and Koina. No decoys or entrapment yet (open decision 1).
- `AlphapeptdeepLibraryBuilder.TuningConfig`: the fine-tune's one command through
  `OspreyHelpers.BuildCommandLine` (now handles `PrecursorTablePath`, `Task`, `Timestamp`, and
  omits the search settings when nothing is searched), run under `OspreyProgressMonitor` (7 tasks),
  in `<lib dir>/<lib stem>/osprey/` (kept between builds, so the same runs tune once); the model is
  copied to `<library>.model.zip` (`OspreyHelpers.GetLibraryModelPath`), not listed.
- Tests: `BuildLibraryCarafeWizardTest` (TestFunctional, on `OspreySearchTest.zip`): the tuned
  build with every page's refusals and Previous/Next, a build with the saved model added to the
  list, a build for a FASTA. Set env `SKYLINE_BUILD_LIBRARY_DEMO=1` and run with `-ShowUI` to pause on
  every page (`PauseTest`). Updated navigation in `KoinaSkylineIntegrationTest`,
  `KoinaBuildLibraryTest` (TestConnected), `AcquisitionComparisonTutorialTest`,
  `AlphapeptdeepBuildLibraryTest`, `CarafeModelBuildLibraryTest` (TestPerf, not run here).

**Decoys and entrapment (open decision 1), answered in code in a commit of its own**: the Predict
For page offers "Add shuffled-sequence decoys, one per peptide" and "Add entrapment peptides from a
FASTA file", for the document route and the FASTA route, AlphaPeptDeep and Koina alike. Skyline
generates the decoys (`RefinementSettings.GenerateDecoys`, shuffle) and digests the entrapment FASTA
with the document settings, in the document the builder predicts for (the open document is never
changed). The built library then gets Carafe's DecoyPairs table (`LibraryDecoyPairs`, Model/Lib):
a row per target, a decoy's row pointing at its target's, IsEntrapment on the entrapment FASTA's
peptides, Method "shuffle" - the one marking the blib format already has, which Osprey reads with
`--decoys-in-library`. Spectra are matched by unmodified sequence and charge; one that is not unique
gets no row. The entrapment source is either: CarafeSharp's `EntrapmentFastaBuilder` in process
(the FASTA route with the entrapment box empty: the predicted FASTA's peptides shuffled, one per
target, ratio 1, added as a peptide list), or a FASTA file the user supplies (required on the
document route, which has no FASTA to shuffle from). Each is its own commit, so the review can take
or replace it on its own. After it, `BuildLibraryCarafeWizardTest`, `KoinaSkylineIntegrationTest`,
`AlphaPeptDeepUseGpuTest` and `CodeInspection` pass.

**Design decisions taken in the session**
- Koina goes through the Predict For page too (the spec says both sources), which adds a Next
  click before Finish and changes the Acquisition Comparison tutorial's Build Library step and
  screenshot; routing Koina straight to Finish is a one-line change in `GetNextPage`.
- The Provided FASTA is digested by Skyline's own FASTA importer with the document's settings,
  not by CarafeSharp's digester: the builders consume PeptideDocNodes, and the document's enzyme,
  modifications and charges then apply exactly as "this document's precursors" do.
- The Model combo left page 1: with the Library Model page carrying it, a second copy would be two
  states for one choice. The quick path (pretrained model, document precursors) is three Nexts.

**Not done / next**
- Run (all green at the end of the session): `AlphaPeptDeepUseGpuTest`, `OspreySearchTest`,
  `KoinaSkylineIntegrationTest`, `BuildLibraryCarafeWizardTest` (en, fr, ja), `CodeInspection`,
  and the TestPerf `AlphapeptdeepBuildLibraryTest` and `CarafeModelBuildLibraryTest` (with
  `-EnableInternet`), and `KoinaBuildLibraryTest` (TestConnected, `-EnableInternet`).
  `AcquisitionComparisonTutorialTest` passes too (381 s, `-EnableInternet`); its Build Library step
  gained a Next click, so its screenshot and the tutorial text need Brendan's decision on Koina's
  routing either way.
- Decoys and entrapment for a Provided FASTA (open decision 1); the editor's Build... route
  (decision 2); feature 3 (decision 3).
- The Osprey `--training-search` HPC stage decomposition is still refused with `--precursors`.
- `/code-review medium` ran on the branch (10 findings): 9 fixed in the fourth local commit, after
  which `BuildLibraryCarafeWizardTest`, `OspreySearchTuningTest`, `AlphaPeptDeepUseGpuTest`,
  `CodeInspection` and Osprey's `TestSubsetPrecursorTable` passed again;
  dropped: the progress bar of a fine-tuned build jumps between the builder's four weighted
  segments and `OspreyProgressMonitor`'s seven task segments (5% -> 0% -> ~95% -> 85% -> 100%).
  Cosmetic; the fix is for the monitor to map task progress into the segment it is given rather
  than redefining the segments.

## Revisions for the next session (collected in the review of 2026-10-27)

1. **Drive demos over the Skyline MCP.** A test-runner argument (plumbed as a switch of the
   `ai/scripts/Skyline` test script, e.g. `-AiConnector`) that, when the test creates its
   SkylineWindow, registers the instance in `~/.skyline-mcp` as a normal Skyline does when "register
   at startup" is set, and pre-approves the screen-capture permission for that process. Off by
   default, so the tests of the MCP itself keep today's behavior. With it, a Claude Code session sees
   the test's Skyline, captures its forms and clicks the pause dialog's Continue itself. Brendan,
   2026-10-27: a flag, not "always when ~/.skyline-mcp exists".
2. **The first page's Carafe tab.** It is now a description, since the Model combo and Use GPU moved
   to the Library Model page. Brendan is not yet convinced; decide after seeing the Library Model
   page whether the combo comes back to page 1 for the quick path (page 2 then holding only the
   fine-tune choice), or the blurb stays.
3. **Predict For: the FASTA box starts blank.** No prefilled path (the test's "missing.fasta" stays
   in the box after its refusal check, which is what Brendan saw). Choosing the FASTA option and
   clicking Browse starts in the last FASTA folder, else the document's; the box shows nothing
   until a file is chosen.
4. **Decoys: "[ ] Add decoy peptides"** with a tooltip saying what is added, and reverse-sequence
   decoys (Skyline's reverse), not shuffled; the DecoyPairs Method recorded becomes "reverse".
5. **Entrapment: "[ ] Add entrapment peptides"** with a tooltip; nothing more until it is checked.
   Checked, it reveals "Generation method:" [Shuffled | From FASTA]; only "From FASTA" reveals the
   path box and its own Browse.... Progressive disclosure: the naive user sees two checkboxes; the
   separate-FASTA source is a power-user option whose value is not settled (conserved peptides can
   pass the filters and be detected for real biological reasons).
6. **Drop the long captions** on both checkboxes; the explanation lives in the tooltips.
7. **Put the Carafe group box back on the first page** (settles 2) and populate it with a simple
   set of choices that make the extra pages unnecessary for the default case: the pretrained (or a
   listed) model and the document's precursors, Finish from page 1 as before the branch. The fuller
   range (fine-tune on runs, a FASTA's precursors, decoys, entrapment) is reached off that path, so
   users who are not ready for it do not see it. Brendan's design principle for Skyline, stated
   2026-10-27: "Streamline the default case as much as possible, enable greater flexibility off that
   path so that users who are not ready for it don't even see it." The next session designs what the
   group box holds (candidates: the Model combo and Use GPU as before; one control that opens the
   advanced route, such as a "Fine-tune a new model on DIA runs..." choice or an Advanced... button
   leading to the pages) and which pages remain behind it.
   Direction from the demo (2026-10-27): put the decisions on page 1 as expressions of intent in
   the group box, each leading to its pages only when checked, e.g. "[ ] Digest external FASTA
   sequences" and "[ ] Fine-tune the model" (wordings open). The FASTA choice may want a radio pair
   or a combo (this document's precursors vs an external FASTA) rather than a checkbox, because the
   form must say plainly what the default predicts for: with a full-FASTA DIA library now a
   prominent use, a naive user looking at the form cannot tell that it builds a library of
   predictions for the precursors in the document. "Use this model as it is" turning Next into
   Finish is the pattern to keep. The Library Model page is fine as it is: Browse... is the only
   way runs get into the list, which the top blurb already says.

8. **A wait verb for the MCP** (Brendan, 2026-10-27, after the first MCP-driven demo): the
   session learned a pause had arrived by polling the open-forms list after a fixed sleep. The MCP
   has no events (Nick's area; its verbs are request and response), and the shape that serves both
   the test harness and a session driving a user's UI is a blocking verb, not a push event:
   `skyline_wait_for_form(type, timeout)` returning when the form is up, the contract of the
   harness's `WaitForOpenForm`. Belongs in the MCP, in production, not on this branch; proposal
   for Nick.

**Plan for the next session (Brendan, 2026-10-27)**: in this order.
1. Revision 1 first: the test-runner flag that registers the test's Skyline with the MCP and
   pre-approves screen capture, so the session can drive a demo test itself (capture each page,
   click the pause dialog's Continue, read the form's values).
2. Then mockups, not implementations: page 1's Carafe group box in its candidate shapes (the intent
   checkboxes; a radio pair or combo naming the default, "the precursors in this document", against
   an external FASTA; the fine-tune choice), walked through over the MCP with Brendan at the
   demo pauses, revised until agreed.
3. Real code behind the agreed shape only after that, with the Predict For revisions (3 to 6) and
   the rest of the list.
The existing branch stays as the working implementation behind whatever page 1 becomes: the
pages, the builder's one-job tune and predict, the DecoyPairs marking and the tests all remain.

### 2026-10-27 - The MCP-driven demo, then page 1 redesigned (local commits, no push)

All three steps of the plan above, in order, with Brendan at the keyboard.

1. **`-AiConnector`** (pwiz d4e1433526; pwiz-ai 1bd96957): TestRunner `aiconnector=on` sets
   `Program.AiConnector`; `Program.Main` then starts the JSON tool service and writes the
   connection file as a Skyline set to connect at startup does, and the harness pre-approves
   screen capture for the process. Verified by driving `BuildLibraryCarafeWizardTest`'s demo from
   the session: instance listed, every page captured with no permission dialog, Continue clicked
   on the pause dialog. Documented in the script README and `build-and-test-guide.md`.
2. **The mockup**: page 1's Carafe tab with Model + Use GPU, a "Predict for" combo (the
   precursors in this document / the peptides of a protein FASTA file...) and a "Fine-tune the
   model on DIA runs..." box, shown live at the first pause. Brendan: "achieves the goal", with
   the Model combo to be the settings-list combo (Add..., Edit current..., Edit list...).
3. **The real code** (pwiz d4b08ea590): `CarafeModelCombo` (SettingsUI) is the model combo both
   Build Library's page 1 and the wizard's Library Model control use; `UseGpuDriver` on page 1;
   `OspreyLibraryModelControl.HideModelChoice()` leaves the runs list for Build Library's runs
   page. Routing: the defaults finish from page 1; Predict for a FASTA leads to the Predict For
   page; the fine-tune box to the runs, FASTA, modifications and search settings pages. Koina
   has the Predict for combo on its tab (kept in step with Carafe's) and finishes from page 1
   again. Predict For page per revisions 3 to 6: blank FASTA box, "Add decoy peptides" (reverse
   decoys, DecoyPairs Method "reverse"), "Add entrapment peptides" revealing "Generation
   method" (Shuffled sequences of the FASTA's peptides | A FASTA file of entrapment proteins)
   and the FASTA box for the latter; captions in tooltips. The modification warning is back on
   page 1 (the tab control grew 24 px for it). The five tests that had gained a Next click are
   restored to their master versions. Brendan's wording, folded in: "Peptide sequence source:"
   with "Shuffled target sequences" | "A FASTA file of entrapment proteins", and the page's
   description "The FASTA file digested with the document settings to produce the peptide
   precursors the library is predicted for." Green: `BuildLibraryCarafeWizardTest` (en, fr,
   ja), `CodeInspection`, `AlphaPeptDeepUseGpuTest`, `KoinaSkylineIntegrationTest`,
   `OspreySearchTuningTest`.
   **Scope decision taken**: decoys and entrapment are offered on the FASTA route only; a
   document that wants them holds them already (Refine > Add Decoys, an import). Said to
   Brendan, no objection yet.

Also green, with `-EnableInternet`: `AlphapeptdeepBuildLibraryTest`, `CarafeModelBuildLibraryTest`,
`AcquisitionComparisonTutorialTest` (TestPerf, back on its master step count, so no screenshot
change) and `KoinaBuildLibraryTest` (TestConnected), all on their master navigation; and
`OspreySearchTest`. Every gate named in this TODO is green on the nine local commits; the branch
is ready for `/code-review medium` and a PR when Brendan says so.

**Text review and code review (2026-10-27, later)**: Brendan reviewed every new string through
`Export-ResxChanges.ps1` (a CSV of the branch's added and changed resx strings, in
`ai/scripts/Skyline`): no component named in user text (no Osprey, no DecoyPairs table), page
descriptions that say what the page's settings do, the progress text naming the chosen model
("Predicting the library with the {0} model"). UI review over the MCP-driven demo: done, no
further change. `/code-review medium`: 8 findings; fixed 5 (a non-tuning rebuild deleted the
saved model it predicted with; stale decoy and entrapment boxes drove a document build after the
Predict For page was left; the hidden runs-page combo read every model file on a toggle; page 1
validated twice on Finish; DecoyPairs written one parsed statement per row); dropped 2 (the
progress bar cosmetic below; remote sources in the wizard control's Browse, from PR #4914); one
left for Brendan: Osprey's hosted route never sets `ApplyTrainingRunMeta`, so after a fine-tune
the training run's NCE, instrument, rt_max and precursor m/z range do not apply to the prediction
(FASTA route and table route alike; `TestSubsetPrecursorTable` passes either way). One line in
`LibraryBuildWorkflow` would set it, but it also lets the run's NCE override a user-given one.

**Follow-up PRs named by Brendan (2026-10-27)**: expose the full engine settings in a name-value
grid, as the other search engines do, for both the Osprey Search wizard and Build Library's
fine-tune (it would also let a user choose peptdeep's RT model again).

**Later on 2026-10-27**: b8503cf122 renames `AlphapeptdeepLibraryBuilder` to
`CarafeLibraryBuilder` and keeps the AlphaPeptDeep name for the default models only (three user
strings reworded and re-keyed, the ja/zh source captions read Carafe, the dialog's property is
`Carafe`). 5307ed1ef7 drops the table route's override of Carafe's RT model: the pretrained
Chronologer predicts RT (Mike: peptdeep's RT model is poor; Bo Wen's new base RT model comes
later). **`AlphapeptdeepBuildLibraryTest` (TestPerf) now fails on its answer files' RT column and
needs re-recording** (`IsRecordMode`, then the zip on the test data server): Brendan's step. The
other gates are green on the twelve local commits. Still open: the fine-tune progress
bar cosmetic (above), and the pause dialog truncates a long description to its first words
(existing behavior, tooltip has the full text).
