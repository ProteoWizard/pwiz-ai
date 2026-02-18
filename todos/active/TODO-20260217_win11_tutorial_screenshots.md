# Win11 Tutorial Screenshot Migration

## Branch Information
- **Branch**: `Skyline/work/20260217_win11_tutorial_screenshots`
- **Base**: `master`
- **Created**: 2026-02-17
- **Status**: In Progress
- **GitHub Issue**: (pending)
- **PR**: (pending)

## Objective

Migrate tutorial screenshots from Windows 10 to Windows 11. This is a careful, multi-phase
process to ensure screenshot consistency on Win11 matches what we had on Win10. Prior work on
border painting for Win11 rounded corners provides the foundation.

## Strategy

1. **Phase 1 (Win10 Baseline)**: Run all tutorial tests in auto-screenshot mode on this
   Win10 machine. Confirm that the current code produces minimal changes from committed
   screenshots. Document any changes we choose to allow.

2. **Phase 2 (Win11 Capture)**: Run the same tests on a Win11 machine in auto-screenshot
   mode. Review that all differences are either:
   - Expected Win11 UI changes (rounded corners, theme differences)
   - The same changes already allowed in Phase 1

3. **Phase 3 (Commit & Verify)**: Commit the Win11 screenshots. Re-run on Win11 to prove
   we've achieved the same level of consistency on Win11 as we had on Win10.

## Tutorial-to-Test Mapping

### TestTutorial Tests (~70 min total on Win10)

Per-pass runtimes from Performance Tests run #80807 (BRENDANX-UW25, 2026-02-17).

| Tutorial Folder | CoverShotName | Test Method | Per-Pass |
|---|---|---|---|
| AbsoluteQuant | AbsoluteQuant | TestAbsoluteQuantificationTutorial | 7s |
| AuditLog | AuditLog | TestAuditLogTutorial | 6s |
| CustomReports | CustomReports | TestCustomReportsTutorial | 6s |
| DIA | DIA | TestDiaTutorial | 10s |
| ExistingQuant | ExistingQuant | TestExistingExperimentsTutorial | 20s |
| GroupedStudies | GroupedStudies | TestGroupedStudies1Tutorial | 44s |
| iRT | iRT | TestIrtTutorial | 19s |
| LibraryExplorer | LibraryExplorer | TestLibraryExplorerTutorial | 10s |
| LiveReports | LiveReports | TestLiveReportsTutorial | 10s |
| MethodEdit | MethodEdit | TestMethodEditTutorial | 27s |
| MethodRefine | MethodRefine | TestMethodRefinementTutorial | 15s |
| MS1Filtering | MS1Filtering | TestMs1Tutorial | 19s |
| OptimizeCE | OptimizeCE | TestCEOptimizationTutorial | 4s |
| PeakPicking | PeakPicking | TestPeakPickingTutorial | 14s |
| PRM | PRM | TestTargetedMSMSTutorial | 28s |
| SmallMolecule | SmallMolecule | TestSmallMoleculesTutorial | 5s |
| SmallMoleculeMethodDevCEOpt | SmallMoleculeMethodDevCEOpt | TestSmallMolMethodDevCEOptTutorial | 10s |
| SmallMoleculeQuantification | SmallMoleculeQuantification | TestSmallMoleculesQuantificationTutorial | 11s |

### TestPerf Tutorial Tests (~150 min total on Win10)

| Tutorial Folder | CoverShotName | Test Method | Per-Pass |
|---|---|---|---|
| AcquisitionComparison | AcquisitionComparison | TestAcquisitionComparisonTutorial | 368s |
| DDASearch | DDASearch | TestDdaTutorial | 130s |
| DIA-PASEF | DIA-PASEF | TestDiaPasefTutorial | 62s |
| DIA-QE | DIA-QE | TestDiaQeTutorial | 82s |
| DIA-TTOF | DIA-TTOF | TestDiaTtofTutorial | 188s |
| DIA-Umpire-TTOF | DIA-Umpire-TTOF | TestDiaTtofDiaUmpireTutorial | 492s |
| HiResMetabolomics | HiResMetabolomics | TestHiResMetabolomicsTutorial | 30s |
| IMSFiltering | IMSFiltering | TestDriftTimePredictorTutorial | 391s |
| PeakBoundaryImputation-DIA | PeakBoundaryImputation-DIA | TestPeakBoundaryImputationDiaTutorial | 66s |
| PRMOrbitrap | PRMOrbitrap | TestOrbiPrmTutorial | 111s |
| SmallMoleculeIMSLibraries | SmallMoleculeIMSLibraries | TestSmallMoleculeLibrariesTutorial | 71s |

**Longest tests**: TestDiaTtofDiaUmpireTutorial (8 min), TestDriftTimePredictorTutorial (6.5 min),
TestAcquisitionComparisonTutorial (6 min), TestDiaTtofTutorial (3 min), TestDdaTutorial (2 min).

### Tutorials Without Automated Tests

| Tutorial Folder | Notes |
|---|---|
| ImportingAssayLibraries | Has screenshots but no CoverShotName test |
| ImportingIntegrationBoundaries | Has screenshots but no CoverShotName test |
| PRMOrbitrap-PRBB | May be subset of PRMOrbitrap test |

## Tasks

### Phase 1: Win10 Baseline Verification

- [ ] Run all 18 TestTutorial tests in auto-screenshot mode on Win10
- [ ] Review diffs using ImageComparer (or MCP server)
- [ ] Document allowed changes (accept/revert/defer for each diff)
- [ ] Fix any bugs discovered during review
- [ ] Run TestPerf tutorial tests as time permits
- [ ] Commit any accepted Win10 changes or code fixes

### Phase 2: Win11 Capture

- [ ] Set up Win11 machine with same Skyline build environment
- [ ] Run all TestTutorial tests in auto-screenshot mode on Win11
- [ ] Review diffs — confirm only expected Win11 UI + allowed Win10 changes
- [ ] Investigate any unexpected Win11-specific differences
- [ ] Fix any Win11-specific border painting or layout issues
- [ ] Run TestPerf tutorial tests as time permits

### Phase 3: Commit & Verify

- [ ] Commit Win11 screenshots to branch
- [ ] Re-run all tests on Win11 to verify zero (or near-zero) diffs
- [ ] Document any remaining known differences
- [ ] Create PR

## Running Tests in Auto-Screenshot Mode

```bash
# Single tutorial test
pwsh -Command "& './ai/scripts/Skyline/Run-Tests.ps1' -TestName TestAbsoluteQuantTutorial -TakeScreenshots"

# The -TakeScreenshots flag sets pause=-3 (auto-screenshot) and implies -ShowUI
```

## Phase 1 Review: Win10 Baseline

### TestTutorial Results (Win10)

_(To be filled in as tests are run)_

### TestPerf Results (Win10)

_(To be filled in as tests are run)_

## Phase 2 Review: Win11 Capture

_(To be filled in during Phase 2)_

## Bugs Found

_(To be documented as BUG-001, BUG-002, etc. per screenshot-update-workflow.md)_

## Related

- `ai/docs/screenshot-update-workflow.md` — Full screenshot review workflow
- `ai/todos/completed/TODO-20260108_screenshot_followup.md` — Prior screenshot consistency work
- `ai/todos/active/TODO-20260216_imagecomparer_mcp.md` — ImageComparer MCP server for automated review
- `ai/todos/backlog/TODO-automated_screenshot_review.md` — Future automation vision
