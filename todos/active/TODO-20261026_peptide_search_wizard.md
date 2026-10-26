# TODO-20261026_peptide_search_wizard.md

## Branch Information
- **Branch**: `Skyline/work/20261026_peptide_search_wizard`
- **Base**: `master`
- **Created**: 2026-10-26
- **Status**: In Progress
- **GitHub Issue**: (none)
- **Module**: `skyline`
- **PR**: (pending)
- **Checkout**: `C:\dev\pwiz-inspect` (worktree switched from the clean, pushed PR #4769 branch)

## Objective

Refactor and redo the UX of the Run Peptide Search wizard, sharing code with Import Peptide
Search where it makes sense. Run Peptide Search must collect every input up front (search settings
before chromatogram-extraction settings), then run convert -> search -> library -> iRT -> FASTA +
protein association -> apply document -> start extraction without stopping for input.

## Agreed plan (developer-approved 2026-10-26)

Three PRs (the original PR 1 and PR 2 were combined):

1. **PR A - pipeline + wizard framework, behavior-preserving**
   - UI-free `PeptideSearchPipeline` steps in the model layer: convert/search setup (from
     `InitiateSearch`), library build + load (from `BuildPeptideSearchLibraryControl`), iRT
     (split `PeptideSettingsUI.AddIrts` into calculation + dialog wrapper), FASTA import +
     protein association + decoys/auto-train (from `ImportFastaControl.ImportFasta`), detected
     features (from `AddDetectedFeaturesToDocument`). CLI `ImportSearchInternal` moved onto the
     same steps.
   - Declarative wizard page list in a `PeptideSearchWizardBase` replacing the `NextPage` switch,
     `_pagesToSkip`, ordinal page arithmetic and `ShowingFormView` index math.
   - Split into `ImportPeptideSearchDlg` (Import + DIA-NN/EncyclopeDIA hand-offs) and
     `RunPeptideSearchDlg` (Run + feature detection, owns presets).
   - Pages edit an immutable settings object instead of pushing/popping the document stack;
     one document change + one audit log entry at the end (no mid-wizard library commit).
   - Existing tests should pass with at most mechanical changes; keep the nested IFormView
     page type names used by `TestRunnerFormLookup.csv` and ~60 screenshot call sites.
2. **PR B - Run Peptide Search UX**
   - Order: Files & workflow -> Modifications -> FASTA & proteins -> [DIA] conversion/DIA-Umpire
     -> Search settings -> [PRM/DIA] Transition settings -> Full-scan -> Run (progress checklist
     + summary). Feature detection stays Files -> Full-scan -> Hardklor settings -> Run.
   - Up-front replacements for mid-run prompts: CiRT count + recalibrate on files page;
     protein association options on FASTA page (shared control extracted from
     AssociateProteinsDlg); lockmass inline when Waters files present; prefix/suffix trimming
     inline; decoy/auto-train/FASTA/isolation-window validation on page leave.
   - Results summary (iRT, ambiguous matches, protein association counts) on the final page.
   - Resume after failure: steps fingerprint their inputs; re-Run skips unchanged steps.
   - Rewrite the ~25 Run/feature-detection tests with a new shared navigation helper.
3. **PR C - tutorials**: DDASearch, DIA-Umpire-TTOF (published), DiaSearch drafts; new
   screenshots and text incl. ja/zh-Hans; coordinate with tutorial owners.

## Decisions

- Import Peptide Search keeps the AssociateProteinsDlg popup at Finish (no long search precedes it).
- End of run: apply the document, start chromatogram extraction, leave the wizard on a summary
  page with Finish.
- Two dialog classes (Import vs Run).
- iRT Auto with multiple matching standards: CLI errors (unchanged); Import wizard keeps the
  SelectIrtStandardDlg picker; Run wizard picks the best match and reports it.

## Facts gathered (2026-10-26)

- Test inventory: 59 tests in 32 files drive the wizard (29 Import, 23 Run, 2 feature detection,
  3 DIA-NN, 2 EncyclopeDIA). No shared navigation helper exists. AssociateProteinsDlg is reached
  inside the wizard by 26 tests; 9 tutorials screenshot it.
- Search engines take mods via `SetModifications` (from the wizard's working document), enzyme
  via `SetEnzyme` (FASTA page digest settings). Hardklor settings read precursor charges and
  full-scan settings. DIA-Umpire reads the isolation scheme from the FullScanSettingsControl.
  MSFragger DIA engine is created on engine-combo change and reads `IsGpfData` (stale-engine bug).
- `ImportPeptideSearch.CutoffScore` is read from SearchSettingsControl before that page is shown.
- `AssociateProteinsResults.PRODUCER` already computes protein association without UI.

## Progress

- [ ] PR A: pipeline extraction
- [ ] PR A: wizard framework + Import/Run split
- [ ] PR A: settings object replaces document stack
- [ ] PR A: CLI on shared steps
- [ ] PR A: build, full wizard test set green
