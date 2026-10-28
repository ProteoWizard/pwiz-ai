# TODO-20261027_run_peptide_search_ux.md

## Branch Information
- **Branch**: `Skyline/work/20261027_run_peptide_search_ux`
- **Base**: `Skyline/work/20261026_peptide_search_wizard` (PR [#4923](https://github.com/ProteoWizard/pwiz/pull/4923)); retarget to `master` once that merges
- **Created**: 2026-10-27
- **Status**: In Progress
- **GitHub Issue**: (none)
- **Module**: `skyline`
- **PR**: (pending)
- **Checkout**: `C:\dev\pwiz-inspect`

## Objective

PR B of the plan in TODO-20261026_peptide_search_wizard.md: Run Peptide Search collects every
input first (search settings before chromatogram-extraction settings), then runs search ->
library -> iRT -> FASTA + protein association -> apply document -> start extraction without
stopping for input, and ends on a summary with Finish.

## Design

- **Page order (Run)**: Files & workflow -> Modifications -> FASTA & proteins -> [DIA] Conversion
  -> Search settings -> [PRM/DIA] Transition settings -> Full-scan -> Run (progress + summary).
  Feature detection: Files -> Full-scan -> Hardklor settings -> Run (Hardklor reads the full-scan
  resolution and precursor charges). The Run DIA chromatograms page goes away: the files to
  extract are the files searched; GPF moves to the conversion page.
- **Leaving the last input page starts the run** (Next reads "Run"). The run page shows one log
  and progress bar for every step and its Cancel button covers every step.
- **Model pipeline** (`RunPeptideSearchPipeline`, Model): after the search (still driven by
  DDASearchControl / HardklorSearchControl), headless library build (builder.BuildLibrary, as the
  CLI does), LibraryIrtCalibration with up-front answers, add library to the document, then
  feature-detection features or FASTA import + protein association (AssociateProteinsResults run
  synchronously) + decoys + iRT standards + auto-train. Settings-list changes (spectral library
  list, RT predictor) are made on the UI thread when the result is applied.
- **One document change at the end**: library, proteins and results import are committed in a
  single SkylineWindow.ModifyDocument with one audit log entry (was two: "Add document spectral
  library" + "Import results"). Run tutorial audit-log baselines change.
- **Up-front answers**: CiRT count + recalibrate on the files page; protein association options
  on the FASTA page (control extracted from AssociateProteinsDlg and shared with it); lockmass
  asked when Run is clicked, before anything runs; prefix/suffix trimming stays a dialog on
  leaving the files page (it already comes before any long step); DIA-Umpire isolation-window
  check moves to the full-scan page; auto iRT with several matching standards picks the one with
  the most library peptides and reports it.
- **Summary** on the run page: library, iRT standard (and whether it was chosen automatically),
  calibrated peptides, ambiguous matches, protein association counts, document counts, decoys,
  extraction started. Back/Cancel disabled after the document is applied; Finish closes.
- **Resume**: after a failure the user can go Back and Run again; the search is skipped when its
  inputs (files, engine settings, mods, enzyme, FASTA, conversion) are unchanged and its result
  files still exist.

## Progress

- [x] Model: synchronous AssociateProteinsResults (Calculate, GetFinalTargetCounts), RunPeptideSearchPipeline
- [x] Wizard: page order, run start/finish, summary, resume (search fingerprint + result files exist)
- [x] Up-front UI: CiRT count/recalibrate, ProteinAssociationOptionsControl (shared with AssociateProteinsDlg), GPF on conversion page
- [x] Tests rewritten for the new order: DdaSearchTest, DiaSearchTest, ManagingSearchToolsTest; TestPerf DdaTutorial,
      DiaSearchTutorial, DiaUmpireTutorial, DiaUmpireVendorFormat, FeatureDetection, PerfFeatureDetectionSIMscans
      (no shared navigation helper: the walks differ enough per test that one didn't pay off)
- [x] Functional tests green: 8 DDA, 5 DIA, ManagingSearchTools, 16 tests that drive AssociateProteinsDlg
- [x] Perf tests (8 rewritten): green apart from the expected audit-log change
- [x] Audit log baselines re-recorded in all 5 languages for the 6 Run tutorial tests (30 logs); all 8 perf tests green
- [ ] Tutorial screenshots/text (PR C)
- [x] CodeInspection + tcinspect clean

## Parity fixes found by the tests

- The FASTA import needs the document's RT predictor already in place: AddStandardsToDocument drops proteins made
  only of iRT standard peptides, read from the predictor. The pipeline now creates the predictor (no settings-list
  change) and puts it in the document before AddProteins; ApplyResult saves it to the settings lists on the UI thread.
- The requested iRT standard reaches the FASTA import even when the library isn't calibrated (old AddIrts did this).
- Search result files are de-duplicated (Tide writes one percolator.pep.xml for all spectrum files).
- AddIrtPeptidesDlg checks in DiaUmpireTutorialTest now read Result.IrtCalibration (ProcessedIrtAverages).

## Audit log

- One "Imported a peptide search" entry per run. It carries the library build (search files, score
  type and threshold, iRT standard, ambiguous matches, workflow, input type) as a Build Spectral Library
  section, reusing the existing ImportPeptideSearchSettings_BuildPeptideSearchLibrarySettings property name.
- The entry now also records the transition and full-scan settings (incl. isolation scheme) the wizard
  changed: the old "Added spectral library" entry committed them without logging them.
- The 4 strings the Model pipeline uses moved from PeptideSearchResources to ModelResources (with their
  ja/zh-Hans translations), since Model code must not reference FileUI.

## Code review (/code-review high, 2026-10-28)

Fixed:
- Q-value filter on the FASTA page was shown and logged but not applied: validated on leaving the page, applied before association.
- StartRun / ApplyResult exceptions left every wizard button disabled: now end the run (RunFailed) with the error shown.
- CiRT count / recalibrate visibility read comboStandards.Visible (false off-screen): tracked by a field.
- Cancel during FASTA import or association showed an error: a failure after Cancel is a cancel.
- Library build failure showed two error dialogs: one per run.
- Resume shortcut never fired after conversion: remembers the accepted search's result files; fingerprint adds the DIA-Umpire settings.
- Existing protein associations discarded silently: the run log says so (existing AssociateProteinsDlg string).
- "Several standards matched ... used Automatic" when calibration then found nothing: chosen flag set only on success.
- Found by the new resume test: a failed run left its library loaded and locked, so the rerun could not rebuild it (pipeline.ReleaseLibrary).

Dropped:
- Duplicated calibration/FASTA sequencing vs CommandLine: the shared parts are LibraryIrtCalibration and the ImportPeptideSearch model steps; the remaining sequencing differs on purpose (CLI errors on several matching standards, has no decoy/parsimony UI choices).
- ApplyResult changes settings lists before ImportResults commits: the old flow added the library and RT predictor to the settings lists at library build, before later steps could fail; a leftover list entry is harmless.
