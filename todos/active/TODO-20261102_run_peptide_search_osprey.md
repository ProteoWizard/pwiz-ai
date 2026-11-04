# TODO-20261102_run_peptide_search_osprey.md

## Branch Information
- **Branch**: `Skyline/work/20261102_run_peptide_search_osprey`
- **Base**: `Skyline/work/20261029_run_peptide_search_diann` (PR [#4944](https://github.com/ProteoWizard/pwiz/pull/4944), PR C),
  stacked on #4928 (PR B) and #4923 (PR A)
- **Created**: 2026-11-02
- **Status**: In Review
- **GitHub Issue**: (none)
- **Module**: `skyline`
- **PR**: [#4972](https://github.com/ProteoWizard/pwiz/pull/4972)
- **Checkout**: `C:\dev\pwiz-inspect`

## Objective

PR D: fold the Osprey Search wizard (`OspreySearchDlg`) into Run Peptide Search, as PR C did for DIA-NN, so
an Osprey run collects every input up front and runs search -> library -> iRT -> FASTA + proteins ->
document -> extraction without handing off to the Import Peptide Search wizard. The Run tutorial
screenshots/text move to PR E.

## Current state (survey 2026-11-02)

- `OspreySearchDlg` (FormEx wizard): data files -> FASTA (+ "use existing library" checkbox/path) ->
  Library Model (saved/pretrained model or fine-tune on chosen runs, GPU) -> Modifications (own fixed/variable
  lists, Carafe-supported only) -> Search Settings (`OspreySearchSettingsControl`: resolution, fragment
  tolerance ppm/m-z, run/experiment/protein FDR, threads, scoped Additional Settings grid, own
  `OspreySettingsPresets`) -> run (`OspreySearchControl`). Osprey writes the document library itself (`-o`
  doc .blib); Finish adds the search mods to the document, reloads the library object, and opens
  ImportPeptideSearchDlg on its existing-library route. `OspreySearchSettings` is tracked in that import's
  audit log entry.
- Build Library's Osprey route (`BuildLibraryDlg`) hosts the same four controls (FASTA, Library Model,
  Modifications, Search Settings) and the same `OspreySettingsPresets`, so the controls and preset list stay.
- Osprey reads mzML and vendor formats itself (pwiz-sharp), so no conversion step.
- Install gate: `OspreyInstaller.EnsureInstalled` (pinned package or latest TeamCity master build).
- Precursor charges: the wizard predicts for the document's charges, special-casing a default document to
  2-3 because the import's DIA transition page sets them later.

## Decisions (user, 2026-11-02)

- The search settings page hosts Osprey's own `OspreySearchSettingsControl` when Osprey is chosen (not a
  mapping into the generic engine controls). The wizard preset carries the Osprey settings with the FASTA,
  enzyme and mods.
- Predict-from-FASTA vs search-an-existing-library goes on the DIA search method page, under the Osprey
  choice. The Library Model page shows only when predicting.
- Existing document library prompt for Osprey: Overwrite / Cancel (no Append); other engines keep
  Overwrite / Append / Cancel.

## Design

1. `SearchEngine.Osprey`; `OspreySearchEngine : AbstractDdaSearchEngine, IProgressMonitor` wrapping
   `OspreyHelpers.RunSearch`; a UI-built `OspreyConfig` (page settings, model, library source) set on it
   before the run; data files, FASTA, enzyme, missed cleavages and mods (Carafe ids) from the wizard.
   No conversion. `-o` goes to the working folder (`<doc>.osprey\<doc>.blib`); `GetSearchResultFilepath`
   returns it for every run; `LogFilePath` = the teed stdout log. A tuning search copies the tuned model
   beside the document after success.
2. DIA search method page: Osprey added to the direct-DIA engines; under it, Predict / Existing library
   [path][Browse] (existing library validated: .blib or .tsv, not the document library).
3. New Library Model page (hosts `OspreyLibraryModelControl`), applicable for DIA + Osprey + predicting;
   keeps its checks (model opens, tuning runs, stem clash, overwrite of the document's tuned model).
4. Search settings page: when Osprey is chosen, hosts `OspreySearchSettingsControl` (its own preset row
   hidden; the wizard preset applies) in place of the generic engine controls; scopes from the config.
5. Modifications: the wizard's Modifications page (document mods); leaving the search settings page with
   Osprey predicting rejects mods Carafe cannot predict (`GetCarafeModificationIds` unsupported list) and an
   enzyme without a Carafe index.
6. Pipeline: an engine that writes a finished library (`WritesLibrary`) skips BlibBuild; the library step
   sets the old document library aside (PR C's SetAsideLibrary), moves Osprey's .blib into place, loads it,
   and restores the old library on failure. Then iRT, FASTA, proteins as for any engine.
7. Prompt: Overwrite / Cancel for Osprey.
8. Charges: the transition settings page now comes before the run, so the config uses the document's
   charges as set there; drop the default-document special case.
9. Presets: `SearchSettingsPreset` gains an Osprey settings element (an unnamed `OspreySettingsPreset`);
   built-in Osprey presets if useful. `OspreySettingsPresets` stays for Build Library.
10. Audit log: `OspreySearchSettings` stays tracked in the single Run entry.
11. Search > Osprey Search... opens Run with DIA + Osprey preselected, after `OspreyInstaller.EnsureInstalled`
    (or the install check moves to leaving the search settings page, as DIA-NN's did).
12. Remove `OspreySearchDlg` (+designer/resx), `OspreySearchControl`, form-lookup rows, dialog-only strings.
13. Decoys and auto-train off by default for Osprey (it supplies peak boundaries and q-values).

## Tests

- Rewrite `TestFunctional\OspreySearchTest` (predict, then re-run on the predicted library with Overwrite;
  install gate, additional settings, preset, command line, audit log) and `OspreySearchTuningTest` for
  the Run wizard.
- Rewrite `TestPerf\OspreySearchPerfTest`.
- Pipeline: a failed Osprey run leaves the old document library in place.
- Unit tests that stay: OspreySettingsPresetTest, OspreyAdditionalSettingsTest, OspreyProgressMonitorTest.
- Unaffected: BuildLibraryCarafeWizardTest, AlphaPeptDeepUseGpuTest (Build Library route) - run to confirm.

## Out of scope

- EncyclopeDIA wizard.
- Run tutorial screenshots/text (PR E).

## Progress

- [x] Plan and decisions (2026-11-02)
- [x] OspreySearchEngine (Model/DdaSearch) + SearchEngine.Osprey (EnumNames audit name); Osprey writes `-o` into
      its working folder; engine strings moved to ModelResources; tuned model copied beside the document after success
- [x] DIA search method page: Osprey in the direct-DIA engines; Predict / Search an existing library [path][Browse];
      leaving it validates the existing library, the stem clash, and runs OspreyInstaller.EnsureInstalled (the
      settings page asks Osprey for its settings, so the install check moved here from the menu item)
- [x] Library Model page added in code (PeptideSearchWizardDlg.AddWizardTabPage, Pages.library_model_page) with
      a WizardPage.IsShown check, since predicting is chosen after the first page fixes the workflow's pages
- [x] Search settings page hosts OspreySearchSettingsControl (HidePresets) in place of the generic engine controls;
      grid scopes from RunPeptideSearchDlg.GetOspreyConfig (which carries the runs and FASTA, so ScopesFor and the
      audit log's in-scope settings are right)
- [x] Pipeline: SearchResultIsLibrary engines skip BlibBuild; InstallSearchLibrary copies the library into place
      (PR C's SetAsideLibrary restores the old one on failure); Overwrite / Cancel prompt for Osprey
- [x] Presets: SearchSettingsPreset.OspreySettings (an embedded OspreySettingsPreset); a DIA preset for Osprey
      turns DIA-Umpire off and chooses Osprey; menu item opens Run with DIA + Osprey; charges from the document
      after the transition settings page (no default-document special case)
- [x] Removed OspreySearchDlg (+designer/resx), OspreySearchControl, its form-lookup rows and unused strings;
      OspreySearchSettings moved to its own file
- [x] Tests: OspreySearchTest, OspreySearchTuningTest, OspreySearchPerfTest rewritten for the Run wizard and passing;
      DDA/DIA/DIA-NN search tests, preset tests, Osprey unit tests, CodeInspection pass
- [x] (fixed 2026-11-04 by merging master into the stack) TestBuildLibraryCarafeWizard failed on this stack with the latest Osprey master build (26.1.1.304): master's
      #4938 changed Osprey's precursor-table prediction to write a .blib, with the Skyline side on master; the stack
      predates it (not PR D code). Resolves when master is merged into the stack.
- [x] tcinspect clean
- [x] /code-review high: 7 of 9 findings fixed - the page showing stays in the page order (a preset on the
      Library Model page had made Next finish the wizard), and a preset there refreshes the engine list; Osprey's
      checks and engine settings repeat at Run (a preset can choose Osprey after the method page); Osprey's own
      work-folder output is refused as the library to search; max variable mods from the document; Use GPU saved
      only when the Library Model page was used; a tuned model not kept is shown after the run; the resume
      fingerprint includes the existing library and saved model timestamps; the model list is read only when
      needed. Dropped: the duplicated two-line Carafe checks (Build Library and Run hosts)
- [x] PR created
