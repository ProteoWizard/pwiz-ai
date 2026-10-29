# TODO-20261029_run_peptide_search_diann.md

## Branch Information
- **Branch**: `Skyline/work/20261029_run_peptide_search_diann` 
- **Base**: `Skyline/work/20261027_run_peptide_search_ux` (PR [#4928](https://github.com/ProteoWizard/pwiz/pull/4928), PR B), itself stacked on #4923 (PR A)
- **Created**: 2026-10-29
- **Status**: In Progress
- **GitHub Issue**: (none)
- **Module**: `skyline`
- **PR**: (pending)
- **Checkout**: `C:\dev\pwiz-inspect`

## Objective

PR C: fold the DIA-NN search wizard (`DiannSearchDlg`) into Run Peptide Search, so a DIA-NN run collects
every input up front and runs search -> library -> iRT -> FASTA + protein association -> document ->
extraction like the other engines (PR B), instead of handing off to the Import Peptide Search wizard.
The Run tutorial screenshots/text (previously "PR C") move after this PR.

## Current state (survey 2026-10-29)

- `DiannSearchDlg` (FileUI/PeptideSearch) is its own FormEx wizard: DIA files -> FASTA -> DIA-NN mods ->
  settings (ppm tolerances, q-value, threads, missed cleavages, Met excision, length/charge grid) -> run
  (`DiannSearchControl : SearchControl`). Separate presets (`DiannSearchSettingsPresets`).
- `DiannHelpers.RunSearch` runs DIA-NN twice: predict a library from the FASTA, then search the runs
  -> `diann-output-lib.parquet` (+ report parquet, .quant files) in the document folder. BiblioSpec's
  `DiaNNSpecLibReader` builds the .blib (Global.Q.Value filter, RT.Start/Stop as explicit peak bounds).
- Hand-off: plain `ImportPeptideSearchDlg` with the parquet as search file; user walks every page plus
  AssociateProteinsDlg. Existing doc .blib -> Overwrite/Append/Cancel prompt.
- Install: `SkylineWindow.EnsureDiannInstalled` (registry check, `DiannDownloadDlg` academic 2.5.0 MSI or
  open-license 1.9.1 zip), `SearchToolType.DIANN`.
- Latent bugs: enzyme is never passed to DIA-NN (no `--cut`); two missed-cleavage values; a DIA-NN `.cfg`
  parsed by the Run wizard's params import sets `SearchEngine.DIANN` (index 6) on a 5-item combo.

## Decisions (user, 2026-10-29)

- Engine choice for DIA lives on the conversion page, renamed in effect to "DIA search method":
  DIA-Umpire (then any DDA engine) / MSFragger-DIA / DIA-NN. Page order stays as in PR B.
- Search > DIA-NN Search... stays as a shortcut that opens Run Peptide Search with DIA + DIA-NN preselected.
- Existing document library: ask up front (Overwrite / Append / Cancel) for every Run engine, not just
  DIA-NN - asked when Run is clicked, before anything runs, like the lockmass prompt (not mid-run).
  Today the Run wizard silently overwrites for all engines; DiannSearchDlg asked after its search.
  Append goes to BlibBuild's append mode; Overwrite deletes the library first
  (`ImportPeptideSearch.DeleteDocumentLibrary`). No prompt when the document has no document library.
- Decoys and mProphet auto-train default off for DIA-NN (DIA-NN supplies peak boundaries); user can turn on.

## Design

1. `DiannSearchEngine : AbstractDdaSearchEngine` wrapping `DiannHelpers`' two steps;
   `GetSearchResultFilepath` = the shared lib parquet for every run; progress from DIA-NN stdout into the
   run page; mods from the Modifications page split fixed/variable with UniMod ids (mass fallback);
   enzyme + missed cleavages from document settings (fixes `--cut`); DIA-NN-only settings (MS1 accuracy,
   threads, Met excision, peptide length, charge range) as AdditionalSettings; ppm-only tolerances, 0 = auto.
   Conversion: DIA-NN reads only some vendor formats, so `GetSearchFileNeedsConversion` decides by
   vendor type (`DataSourceUtil.GetSourceType`), not by extension as the other engines do (".raw" is
   Thermo or Waters; ".d" is Bruker timsTOF, Bruker BAF/TSF or Agilent). Native (confirm against the
   DIA-NN docs for 1.9.1 and 2.5): Thermo RAW, Sciex WIFF/WIFF2, mzML, Bruker .d with analysis.tdf
   (timsTOF). Everything else (Waters RAW, Bruker BAF/TSF, Agilent, Shimadzu, mzXML, mz5, mzMLb, UIMF,
   Mobilion ...) converts to mzML with the same `DiaConverter` MSFragger-DIA uses. The current
   DiannSearchDlg never converts, so this also fixes those formats.
2. Conversion page gains the DIA search method choice; `SearchSettingsControl` shows the chosen engine's
   settings (lift the "DIA = MSFragger only" rule; map combo items to `SearchEngine` explicitly, not by index).
3. Pipeline unchanged after the search; keep the zero-precursor parquet check with a clear message.
4. Install check for DIA-NN runs on leaving search settings (move `EnsureDiannInstalled` logic to a place
   the wizard can call).
5. Presets: DIA-NN in `SearchSettingsPresets` (built-ins from `DiannHelpers.GetDefaultPresets`); migrate the
   separate DIA-NN preset list; `.cfg` import works for DIA-NN.
6. Audit log: DIA-NN engine settings in the single run entry.
7. Remove `DiannSearchDlg` (+ designer/resx), `DiannSearchControl`, the DIA-NN preset list type, and
   dialog-only resource strings; menu item becomes the shortcut.
8. Check during implementation: replicate names vs DIA-NN run-file keys (.raw kept with extension, mzML
   without) so per-run peak bounds/RTs match the imported replicates - including converted files, where
   the library's run is the converted mzML but the replicate is imported from the original vendor file.

## Tests

- Rewrite `TestFunctional\DiannSearchTest` (TestDiannSearch, TestDiannSearch1_9_1,
  TestDiannSearchEmptyResults1_9_1) for the Run wizard; keep install-flow, preset and `.cfg` checks.
- Rewrite `TestPerf\DiannSearchPerfTest` (`TestDiannSearchTutorial`); re-record
  `TutorialAuditLogs\{en,fr,ja,tr,zh}\TestDiannSearchTutorial.log`.
- Update `TestPerf\DiannSearchLFQbenchTest` (manual, `[TestMethod]` commented out).
- Overwrite/Append prompt: a functional test runs a search into a document that already has a document
  library, checks the prompt appears before anything runs, and checks Append keeps the earlier entries
  while Overwrite replaces them; Cancel leaves the wizard on its last input page.
- Unit test (one table of input -> expected) for DIA-NN's needs-conversion decision across vendor types,
  incl. Waters vs Thermo .raw and Bruker .d with/without analysis.tdf.
- A DIA-NN run on a converted vendor format (e.g. Waters) in a perf test, checking peak bounds land on the
  imported replicate.
- Unaffected (import an existing DIA-NN library, no wizard): DiaSwathTutorialTest DIA-NN variants,
  DiaNnPeakImputationTest, GlobalQValueFilterTest.

## Out of scope

- Osprey and EncyclopeDIA wizards (same copied pattern; could follow).
- Run tutorial screenshots/text (next PR, so screenshots are redone once).

## Progress

- [x] Plan approved (2026-10-29)
