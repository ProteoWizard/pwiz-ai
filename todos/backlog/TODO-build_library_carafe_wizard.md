# TODO-build_library_carafe_wizard.md

## Branch Information
- **Branch**: Not yet created - will be `Skyline/work/YYYYMMDD_build_library_carafe_wizard` (from `master`,
  after PR #4917 merges)
- **Module**: `skyline` (with Osprey / CarafeSharp changes where a feature needs them)
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

## Proposed shape of the PR (Brendan's reframing, 2026-10-26)

Two separate things, joined by the model list:

- **Fine-tuning is a wizard of its own, popped up over Build Library**, and its product is a new
  `.model.zip` that appears in the Model combo and is selected when the wizard closes. The model list
  (`Settings.Default.CarafeModelList`, the seam Build Library and the Osprey Search wizard already
  share) is the integration point, so Build Library's pages never carry the tuning inputs. The tuning
  wizard is the Osprey Search wizard's pages minus the import - data files, FASTA and digest, Library
  Model with the tuning runs - ending at the model (feature 1); the Skyline-results source (feature 3)
  is a second way into the same wizard later. How it is launched is open: an entry in the Model combo
  (PR 2 declined a "Train new model..." pseudo-item in the standard `SettingsListComboDriver` combo), a
  Fine-tune... button beside the combo, or Fine-tune... in the model list dialog.
- **Build Library's page 2 is only "what to predict for"**, and Koina gets it too: **Document
  precursors** (the default, today's behaviour) or **Provided FASTA**, with the FASTA, and in either case
  the decisions about decoys and entrapment peptides. Skyline can digest the FASTA and add decoys and
  entrapment in process with CarafeSharp.Proteome (`Digester`, `EntrapmentFastaBuilder`, TorchSharp-free
  and already referenced), producing one precursor table that AlphaPeptDeep sends to Osprey's
  `--precursors` and Koina sends to its service - the same table for both sources, so "Provided FASTA"
  is one implementation. Decoys in the table need a marker the peptdeep TSV's Decoy column and the blib
  carry (Osprey's own FASTA path writes DecoyPairs; detail to design).
- **Scope for the first PR**: the predict-for page for both sources (feature 2 in its new form) and the
  tuning wizard for Osprey-searched runs (feature 1); feature 3 as the PR after, once the export contract
  has been studied.
- The reuse of the wizard's pages as controls both `OspreySearchDlg` and the tuning wizard host is the
  refactor to do first, gated by the existing `OspreySearchTest`, `OspreySearchTuningTest` and
  `AlphaPeptDeepUseGpuTest`.

## Tests

- Functional: a Build Library run per feature on the Stellar subset (feature 1 needs one-run tuning on
  the subset: `TODO-osprey_test_subsetting.md`), the page navigation and validation, fr/ja/en.
- Perf: one tuned Build Library run on the perf subset, inside the 5-minute budget that TODO sets.
- Osprey: `TestSubsetPrecursorTable` extended with the `--training-input` combination.

## Open decisions (Brendan)

1. Which features the first PR carries (the predict-for page for both sources plus the tuning wizard
   proposed; the page alone is a smaller first PR).
2. How the tuning wizard is launched from Build Library (combo entry, a button beside the combo, or the
   model list dialog); the tuned model joins the list and is selected when the wizard closes (decided).
3. Decoys and entrapment for a Provided FASTA: who generates them (CarafeSharp.Proteome in Skyline, so
   Koina gets them too) and how the library marks them.
4. Feature 3 as the PR after this one (Brendan: still interesting; the study of the export contract first).

## Progress Log

### 2026-10-26 - Written

From the two slides and the state after PR #4917; discussed with Brendan.
