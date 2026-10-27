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

- [ ] Model: synchronous AssociateProteinsResults, RunPeptideSearchPipeline
- [ ] Wizard: page order, run start/finish, summary, resume
- [ ] Up-front UI: CiRT/recalibrate, protein association options control, GPF on conversion page
- [ ] Tests: shared navigation helper; rewrite Run / feature detection tests
- [ ] Audit log baselines; tutorial tests (screenshots are PR C)
