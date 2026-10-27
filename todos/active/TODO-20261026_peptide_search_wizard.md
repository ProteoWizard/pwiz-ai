# TODO-20261026_peptide_search_wizard.md

## Branch Information
- **Branch**: `Skyline/work/20261026_peptide_search_wizard`
- **Base**: `master`
- **Created**: 2026-10-26
- **Status**: In Progress
- **GitHub Issue**: (none)
- **Module**: `skyline`
- **PR**: [#4923](https://github.com/ProteoWizard/pwiz/pull/4923) (PR A)
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

- [x] PR A: wizard framework - `PeptideSearchWizardDlg` base (designer + resx renamed from
      ImportPeptideSearchDlg, dead never-parented controls removed) with a `WizardPage` list
      (applies / leave / return-to); `NextPage` switch, `_pagesToSkip`, page ordinal arithmetic,
      `LastPage` enum scan and index-based `ShowingFormView` gone
- [x] PR A: `ImportPeptideSearchDlg` (Import + EncyclopeDIA/Osprey/DIA-NN hand-offs) and
      `RunPeptideSearchDlg` (Run + feature detection, presets, search page) split
- [x] PR A: back navigation pops the documents a page pushed (tracked per page) instead of
      per-page `_xxxChanged` flags
- [x] PR A: `LibraryIrtCalibration` (Model/Irt) shared by PeptideSettingsUI.AddIrts (wizard +
      Peptide Settings) and the CLI `--import-search` iRT block
- [x] PR A: model `ImportPeptideSearch.PrepareSearch` (engine/converter setup),
      `AddDetectedFeatures` (feature detection document building; MessageDlg no longer shown
      from the worker thread), `ChangeAutoTrain`; `ViewLibraryPepInfo.MakeCompareKey` moved to model
- [x] PR A: tests retargeted (script, user-approved): nested types -> `PeptideSearchWizardDlg.*`,
      Run/feature-detection tests -> `RunPeptideSearchDlg`; TestRunnerFormLookup.csv rows
- [x] PR A: perf/tutorial wizard tests (DDA tutorial, DIA-Umpire TTOF, feature detection,
      DIA-TTOF) - first run failed only because C: was full (4 GB free); green after space was freed
- [x] PR A: code inspection (tcinspect.ps1) - 8 unused usings removed, then 0 findings
- [x] PR A: user-reported bug - checked modifications lost on Back (Run): restored across
      re-initialization; a preset re-applies its mods only once (`_modificationsPagePreset`);
      saving a preset off the mods page reads the list box (pre-existing bug, fixed here)
- [x] PR A: /code-review high (8 findings): fixed - page set fixed on leaving the first page
      (a preset changing the workflow later stranded Back/Next or skipped the search); Back
      restores the document stack depth instead of popping a count; form views named by the
      declaring class everywhere (TryWaitForOpenForm now matches FormSeen/CodeInspection; CSV
      rows are PeptideSearchWizardDlg.*); feature detection opens RunPeptideSearchDlg directly;
      progress integer division; AI header removed from long-standing files. Dropped - null
      return of ChangeAutoTrain/AddDetectedFeatures (documented, both callers check)

### Deviation from the plan (to discuss)

"Pages edit a settings object; one document change at the end" was NOT done in PR A. The Import
wizard commits the library to the Skyline document on leaving page 1 (its own undo record and
audit entry), and changing that changes undo/audit-log output that tutorial audit-log baselines
record. It fits PR B, where the Run wizard's single end-of-run apply changes those baselines anyway.

### Translation note

The wizard's designer strings moved from ImportPeptideSearchDlg*.resx to
PeptideSearchWizardDlg*.resx (git mv). ResourcesOrganizer keys include the file, so ~15 short
heading strings will show as new in the next translation round.
