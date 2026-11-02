# TODO-20261102_run_peptide_search_osprey.md

## Branch Information
- **Branch**: `Skyline/work/20261102_run_peptide_search_osprey`
- **Base**: `Skyline/work/20261029_run_peptide_search_diann` (PR [#4944](https://github.com/ProteoWizard/pwiz/pull/4944), PR C),
  stacked on #4928 (PR B) and #4923 (PR A)
- **Created**: 2026-11-02
- **Status**: In Progress
- **GitHub Issue**: (none)
- **Module**: `skyline`
- **PR**: (pending)
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
- [ ] OspreySearchEngine + SearchEngine.Osprey
- [ ] DIA search method page: Osprey + library source
- [ ] Library Model page
- [ ] Search settings page hosts OspreySearchSettingsControl
- [ ] Pipeline: engine-written library installed with set-aside/restore; Overwrite/Cancel prompt
- [ ] Presets, menu shortcut, install check
- [ ] Remove OspreySearchDlg
- [ ] Tests rewritten and passing; tcinspect; code review
