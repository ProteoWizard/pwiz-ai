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

### TestTutorial Tests (1,296 PNGs)

Per-pass runtimes from nightly run #80807. Auto-screenshot runtimes from Phase 1 below.

| Tutorial Folder | Test Method | PNGs | Per-Pass |
|---|---|---|---|
| AbsoluteQuant | TestAbsoluteQuantificationTutorial | 51 | 7s |
| AuditLog | TestAuditLogTutorial | 30 | 6s |
| CustomReports | TestCustomReportsTutorial | 84 | 6s |
| DIA | TestDiaTutorial | 102 | 10s |
| ExistingQuant | TestExistingExperimentsTutorial | 117 | 20s |
| GroupedStudies | TestGroupedStudies1Tutorial | 297 | 44s |
| iRT | TestIrtTutorial | 90 | 19s |
| LibraryExplorer | TestLibraryExplorerTutorial | 23 | 10s |
| LiveReports | TestLiveReportsTutorial | 70 | 10s |
| MethodEdit | TestMethodEditTutorial | 75 | 27s |
| MethodRefine | TestMethodRefinementTutorial | 69 | 15s |
| MS1Filtering | TestMs1Tutorial | 141 | 19s |
| OptimizeCE | TestCEOptimizationTutorial | 8 | 4s |
| PeakPicking | TestPeakPickingTutorial | 26 | 14s |
| PRM | TestTargetedMSMSTutorial | 117 | 28s |
| SmallMolecule | TestSmallMoleculesTutorial | 18 | 5s |
| SmallMoleculeMethodDevCEOpt | TestSmallMolMethodDevCEOptTutorial | 106 | 10s |
| SmallMoleculeQuantification | TestSmallMoleculesQuantificationTutorial | 69 | 11s |

### TestPerf Tutorial Tests (684 PNGs)

| Tutorial Folder | Test Method | PNGs | Per-Pass |
|---|---|---|---|
| AcquisitionComparison | TestAcquisitionComparisonTutorial | 36 | 368s |
| DDASearch | TestDdaTutorial | 51 | 130s |
| DIA-PASEF | TestDiaPasefTutorial | 37 | 62s |
| DIA-QE | TestDiaQeTutorial | 105 | 82s |
| DIA-TTOF | TestDiaTtofTutorial | 105 | 188s |
| DIA-Umpire-TTOF | TestDiaTtofDiaUmpireTutorial | 29 | 492s |
| HiResMetabolomics | TestHiResMetabolomicsTutorial | 17 | 30s |
| IMSFiltering | TestDriftTimePredictorTutorial | 26 | 391s |
| PeakBoundaryImputation-DIA | TestPeakBoundaryImputationDiaTutorial | 19 | 66s |
| PRMOrbitrap | TestOrbiPrmTutorial | 42 | 111s |
| SmallMoleculeIMSLibraries | TestSmallMoleculeLibrariesTutorial | 20 | 71s |

**Longest tests**: TestDiaTtofDiaUmpireTutorial (8 min), TestDriftTimePredictorTutorial (6.5 min),
TestAcquisitionComparisonTutorial (6 min), TestDiaTtofTutorial (3 min), TestDdaTutorial (2 min).

### Tutorials Without Automated Tests (48 PNGs)

| Tutorial Folder | PNGs | Notes |
|---|---|---|
| ImportingAssayLibraries | 7 | Has screenshots but no CoverShotName test |
| ImportingIntegrationBoundaries | 2 | Has screenshots but no CoverShotName test |
| PRMOrbitrap-PRBB | 39 | May be subset of PRMOrbitrap test |

### Total: 2,028 PNGs across 31 tutorials

## Tasks

### Phase 1: Win10 Baseline Verification — COMPLETE

- [x] Run all 18 TestTutorial tests in auto-screenshot mode on Win10
- [x] Review diffs using ImageComparer (and MCP server)
- [x] Document allowed changes (accept/revert/defer for each diff)
- [x] Run all 11 TestPerf tutorial tests in auto-screenshot mode on Win10
- [x] Review TestPerf diffs
- [ ] Commit any accepted Win10 changes or code fixes (none needed — all deferred)

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

```
TestRunner.exe ... offscreen=False loop=1 pause=-3 runsmallmoleculeversions=on
    recordauditlogs=on language=en-US,zh-CHS,ja perftests=on
    test="@SkylineTester test list.txt"
```

## Phase 1 Review: Win10 Baseline

### TestTutorial Results (Win10)

Run date: 2026-02-17 17:34–19:08 on BRENDANX-UW (Win10), total time **1:35:42**.

All 18 tests passed, 0 failures. Languages: en, zh-CHS, ja.
7 tests short-circuited zh/ja passes (not yet translated).

| Test Method | en | zh | ja |
|---|---|---|---|
| TestAbsoluteQuantificationTutorial | 76s | 78s | 76s |
| TestAuditLogTutorial | 89s | — | — |
| TestCEOptimizationTutorial | 36s | — | — |
| TestCustomReportsTutorial | 75s | 77s | 78s |
| TestDiaTutorial | 178s | 122s | 122s |
| TestExistingExperimentsTutorial | 142s | 143s | 143s |
| TestGroupedStudies1Tutorial | 366s | 372s | 372s |
| TestIrtTutorial | 159s | 158s | 158s |
| TestLibraryExplorerTutorial | 68s | — | — |
| TestLiveReportsTutorial | 172s | — | — |
| TestMethodEditTutorial | 96s | 98s | 98s |
| TestMethodRefinementTutorial | 162s | 163s | 164s |
| TestMs1Tutorial | 132s | 133s | 133s |
| TestPeakPickingTutorial | 81s | — | — |
| TestSmallMoleculesQuantificationTutorial | 136s | 141s | 141s |
| TestSmallMoleculesTutorial | 26s | 26s | 26s |
| TestSmallMolMethodDevCEOptTutorial | 101s | 100s | 100s |
| TestTargetedMSMSTutorial | 130s | 131s | 132s |

### TestTutorial Screenshot Diffs (Win10)

**6 changed screenshots** out of 1,296 tested — excellent baseline consistency.

| Screenshot | Pixels | Decision | Notes |
|---|---|---|---|
| ExistingQuant/en/s-22 | 1677 | **Defer** | X-axis "Replicate" label thinning (1 every 4 vs 3). Consistent but sensitive to future change. |
| ExistingQuant/ja/s-22 | 1777 | **Defer** | Same as en — label thinning |
| ExistingQuant/zh-CHS/s-22 | 1777 | **Defer** | Same as en — label thinning |
| CustomReports/zh-CHS/s-22 | 2623 | **Defer (BUG-001)** | Replicates dropdown blank in Targets view |
| DIA/zh-CHS/s-16 | 2508 | **Reverted** | Selection/legend color rectangles beside peptides. Not present in en or ja — intermittent bug. |
| iRT/ja/s-03 | 2508 | **Defer (BUG-001)** | Same blank Replicates combo box bug |

**Watch list for Phase 2**: ExistingQuant s-22 (all locales), CustomReports/zh-CHS/s-22,
iRT/ja/s-03 — verify these are consistent across locales on Win11 before accepting.

### TestPerf Results (Win10)

Run date: 2026-02-17 20:13–22:50 on BRENDANX-UW (Win10), total time **2:36:14**.

All 11 tests passed, 0 failures. Languages: en, zh-CHS, ja.
7 tests short-circuited zh/ja passes (not yet translated).
TestDdaTutorial dominates at ~27 min/pass x3 = ~80 min (half the total).

| Test Method | en | zh | ja |
|---|---|---|---|
| TestAcquisitionComparisonTutorial | 509s | — | — |
| TestDdaTutorial | 1611s | 1619s | 1602s |
| TestDiaPasefTutorial | 200s | — | — |
| TestDiaQeTutorial | 201s | 187s | 189s |
| TestDiaTtofDiaUmpireTutorial | 989s | — | — |
| TestDiaTtofTutorial | 251s | 315s | 316s |
| TestDriftTimePredictorTutorial | 707s | — | — |
| TestHiResMetabolomicsTutorial | 71s | — | — |
| TestOrbiPrmTutorial | 258s | — | — |
| TestPeakBoundaryImputationDiaTutorial | 183s | — | — |
| TestSmallMoleculeLibrariesTutorial | 153s | — | — |

### TestPerf Screenshot Diffs (Win10)

**1 changed screenshot** out of 684 tested — near-perfect consistency.

| Screenshot | Pixels | Decision | Notes |
|---|---|---|---|
| DIA-Umpire-TTOF/en/s-13 | — | **Defer** | Search progress text-box shows variable line counts from external tool. Scrollbar thumb also shifts slightly. Would require painting over the text control to fix. |

### Recommended Batching for Phase 2

To keep each run between 1:15–1:30 on Win10 (faster on Win11):

1. **TestTutorial tests** (~1:36) — all 18 tests
2. **TestPerf minus TestDda** (~1:12) — 10 tests
3. **TestDdaTutorial alone** (~1:20) — 1 test, 3 languages

## Phase 1 Summary

**Total**: 7 diffs out of 1,980 tested PNGs (0.35%) — 1 reverted, 6 deferred.
Phase 1 complete. Win10 baseline is exceptionally stable and ready for Win11 migration.

## Phase 2 Review: Win11 Capture

_(To be filled in during Phase 2)_

## Bugs Found

### BUG-001: Blank Replicates combo box in Targets view
**Found in**: CustomReports/zh-CHS/s-22, iRT/ja/s-03
**Description**: The Replicates dropdown in the Targets panel is blank in the new screenshot
where it previously showed a value. Appears only in non-English locales.
**Status**: Deferred — minor cosmetic, consider fixing in future sprint

## Related

- `ai/docs/screenshot-update-workflow.md` — Full screenshot review workflow
- `ai/todos/completed/TODO-20260108_screenshot_followup.md` — Prior screenshot consistency work
- `ai/todos/active/TODO-20260216_imagecomparer_mcp.md` — ImageComparer MCP server for automated review
- `ai/todos/backlog/TODO-automated_screenshot_review.md` — Future automation vision
