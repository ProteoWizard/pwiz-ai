# TODO-20261104_unified_search_presets.md

## Branch Information
- **Branch**: `Skyline/work/20261104_unified_search_presets`
- **Base**: `Skyline/work/20261102_run_peptide_search_osprey` (PR [#4972](https://github.com/ProteoWizard/pwiz/pull/4972), PR D),
  stacked on #4944 (PR C), #4928 (PR B) and #4923 (PR A)
- **Created**: 2026-11-04
- **Status**: Planned
- **GitHub Issue**: (none)
- **Module**: `skyline`
- **PR**: (pending)
- **Checkout**: `C:\dev\pwiz-inspect`

## Objective

PR E: one list of search settings presets (`SearchSettingsPresets`) for every engine, each preset holding the
settings of its engine's own pages (a polymorphic engine part), with the preset combo listing only the presets
of the selected workflow. Osprey's separate preset list (`OspreySettingsPresets`, shared with Build Library) goes
away. The Run tutorial screenshots/text move to PR F.

## Current state (after PR D)

- `SearchSettingsPreset` (`search_workflow` element): engine, generic engine settings as attributes (precursor and
  fragment tolerance, max variable mods, fragment ions, MS2 analyzer, cutoff, additional settings XML), FASTA,
  enzyme, missed cleavages, decoys, auto-train, modifications, workflow, iRT standard. PR D added an embedded
  `OspreySettings` (`OspreySettingsPreset`), so an Osprey preset also carries unused generic tolerance/cutoff values.
- DIA-NN presets are ordinary generic presets (PR C), since DIA-NN's settings live on the generic page.
- `OspreySettingsPresets` (`OspreySettingsPreset`, `.skyosp`): Osprey's settings page only (resolution, fragment
  tolerance ppm/m-z, run/experiment/protein FDR, additional settings XML). Listed by the preset row of
  `OspreySearchSettingsControl`, which Build Library's Osprey route shows; PR D hides that row in Run Peptide Search.
- The wizard's preset combo (`SettingsListComboDriver<SearchSettingsPreset>`) lists every preset; applying one sets
  the workflow, so a DIA preset chosen on the first page switches the wizard to DIA (`TestDdaSearchSettingsPreset`
  checks this). The driver indexes the combo straight into the list, with no filter.

## Decisions (user, 2026-11-04)

- One preset list with a polymorphic engine part: a DIA-NN preset fills DIA-NN's pages, an Osprey preset Osprey's.
- Strict filtering by workflow: the combo lists only the presets of the selected workflow (DDA hides DIA presets,
  including on the first page). Choosing a preset no longer switches the workflow; the workflow is chosen first.
- Separate PR (E) stacked on PR D.

## Design

1. **Engine part.** `SearchSettingsPreset` keeps its shared part and gains `EngineSettings`, one of:
   - `GenericEngineSettings`: tolerances, max variable mods, fragment ions, MS2 analyzer, cutoff, additional
     settings (MS Amanda, MS-GF+, MSFragger, Comet, Tide, DIA-NN).
   - `OspreyEngineSettings`: today's `OspreySettingsPreset` values (reuse the type as the payload, unnamed).
   The engine decides the type. The existing generic constructors and accessors stay (built-in presets, the
   params/.cfg parser and the tests use them), delegating to the generic part; an Osprey constructor takes the
   Osprey part. PR D's `ChangeOspreySettings` goes.
2. **XML.** Keep `search_workflow`. Generic settings stay as attributes, so existing presets load unchanged; an
   Osprey preset writes its settings as an `osprey_settings` child and no generic attributes. Reading picks the
   part by the engine attribute.
3. **Filtering.** `SettingsListComboDriver` gains an optional item filter: `LoadList` adds only matching items, and
   `SelectedItem` maps the combo index through the filtered items. Edit list / Add still work on the whole list;
   the combo reloads filtered afterwards. Default: no filter, so the other 26 drivers are unchanged.
   - Run Peptide Search filters by `BuildPepSearchLibControl.WorkflowType`; a workflow change reloads the combo
     and clears a selection that no longer matches. A preset with no workflow (the built-in Default, older presets)
     counts as DDA. Applying a preset no longer sets the workflow.
   - Feature detection keeps its preset controls hidden.
   - Save on a page keeps the current workflow, so a saved preset appears under it.
4. **Applying.** The generic part fills the generic search settings page; the Osprey part fills
   `OspreySearchSettingsControl`; the shared part fills the FASTA, modifications and DIA search method pages as now.
5. **Build Library.** `OspreySearchSettingsControl`'s preset row lists `SearchSettingsPresets` filtered to Osprey
   presets, applies only their Osprey part, and saves Osprey presets (workflow DIA, no FASTA, document mods) into the
   same list. Run Peptide Search keeps the row hidden (its combo is the wizard's).
6. **Migration.** On first use (the wizard's `EnsureDefaultPresets` and the Osprey control), each saved
   `OspreySettingsPreset` becomes an Osprey `SearchSettingsPreset` (unique name, as PR C's DIA-NN migration), and the
   old list is emptied; `OspreySettingsPresetList` stays so settings that hold it still load. Edit list's Import
   accepts a shared `.skyosp` file by converting it.
7. **Defaults.** Built-in presets keep their workflows (DIA-NN and MSFragger DIA presets are DIA). Consider a
   built-in Osprey preset per resolution (HRAM 10 ppm, unit 0.5 m/z) so the DIA list has Osprey entries.

## Prerequisite

- Merge master into the stack (A -> B -> C -> D) first, so Build Library's Osprey route can be tested: the latest
  Osprey master build needs master's #4938, and `TestBuildLibraryCarafeWizard` fails on the stack without it.

## Tests

- `TestDdaSearchSettingsPreset`: rewrite the spectra-page preset checks: DDA lists no DIA presets; switching the
  workflow to DIA lists the DIA presets and clears a DDA selection; a preset no longer changes the workflow.
- `OspreySearchTest`: the preset round trip uses an Osprey preset from the filtered list; migration of a saved
  `OspreySettingsPreset`.
- `TestDiannSearch`: its custom preset is a DIA preset, listed in DIA only.
- Build Library: an Osprey preset saved there is listed in Run Peptide Search's DIA list and applies its settings.
- Unit: `SearchSettingsPreset` XML round trip for generic and Osprey presets, and loading a legacy preset
  (attributes only) and a PR D preset (embedded `osprey_settings_preset`); `SettingsListComboDriver` filtering
  (index mapping, reload after Edit list); `OspreySettingsPresetTest` updated or folded in.

## Out of scope

- Library Model page choices (saved model, tuning runs) in presets: per-run file paths.
- EncyclopeDIA.
- Run tutorial screenshots/text (PR F).

## Progress

- [x] Plan and decisions (2026-11-04)
- [ ] Merge master into the stack
- [ ] Engine part + XML
- [ ] Driver filter + workflow filtering in Run Peptide Search
- [ ] Build Library on the unified list; migration; .skyosp import
- [ ] Tests; tcinspect; code review
