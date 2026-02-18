# Win11 Tutorial Screenshot Migration

## Branch Information
- **Branch**: `Skyline/work/20260217_win11_tutorial_screenshots`
- **Base**: `master`
- **Created**: 2026-02-17
- **Status**: In Progress
- **GitHub Issue**: (pending)
- **PR**: [#4002](https://github.com/ProteoWizard/pwiz/pull/4002)

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

### Phase 2: Win11 Capture — COMPLETE

- [x] Set up Win11 machine (BRENDANX-UW25, Win11 Enterprise build 26200)
- [x] Build Skyline (Debug, up-to-date with master including PR #3989 ImageComparer.Mcp)
- [x] Run all 29 tutorial tests (18 TestTutorial + 11 TestPerf) in auto-screenshot mode
- [x] Re-run TestDiaQeTutorial (all 3 locales) after first-run PersistentFilesDir failure
- [x] Enhance ImageComparer.Core with color-tolerant diffing (see Phase 2a below)
- [x] Run diff report with filtering to surface unexpected differences
- [x] Review filtered diffs — confirm only expected Win11 UI + allowed Win10 changes
- [x] Investigate any unexpected Win11-specific differences — none found
- [x] Fix DIA-Umpire-TTOF s-13 progress bar (added FillProgressBar to DiaUmpireTutorialTest.cs:582)

### Phase 2a: Enhanced Diffing for Win10→Win11 Review

Port color-tolerant comparison from PR #3861 (`ScreenshotInfo.ScreenshotDiff`) to
`ImageComparer.Core` so the MCP server can filter expected Win10→Win11 noise from
1,896 changed screenshots.

**Files to modify**:
- `ImageComparer.Core/ScreenshotDiff.cs` — Add `DiffOptions` class, color tolerance
  (per-channel, default 3), bidirectional system color mappings (e.g., 255,255,255 ↔
  243,243,243), corner exclusion zones (8px radius), dominant color pair tracking
- `ImageComparer.Mcp/Tools/ScreenshotDiffTools.cs` — Expose `colorTolerance`,
  `useColorMappings`, `excludeCorners` params in `generate_diff_image` and
  `generate_diff_report`; include filtering stats in output

**Key design**:
- All new options default to off → backward compatible
- `PixelCount` becomes filtered count; `RawPixelCount` tracks pre-filter total
- `DominantColorPairs` reports color pairs >50% of raw diffs
- Avoids ValueTuple NuGet dependency (uses `int[][]` for net472/netstandard2.0)

### Phase 3: Commit & Verify

- [x] Re-run DIA-Umpire-TTOF test (en only) to capture s-13 with FillProgressBar fix — verified
- [x] Accept DIA/zh-CHS/s-16 (Targets highlighting — consistent across Win10/Win11, note for future)
- [x] Commit all Win11 screenshots + code changes to branch (2 commits: code + 1,896 PNGs)
- [ ] Re-run all tests on Win11 to verify reproducibility (near-zero diffs expected)
- [ ] Document any remaining known differences
- [x] Create PR — [#4002](https://github.com/ProteoWizard/pwiz/pull/4002)

**Code changes to commit**:
- `ImageComparer.Core/ScreenshotDiff.cs` — DiffOptions, color tolerance, color mappings, corner exclusion, dominant color pairs
- `ImageComparer.Mcp/Tools/ScreenshotDiffTools.cs` — New filtering params, pad-and-diff for size changes, diffs subfolder
- `TestPerf/DiaUmpireTutorialTest.cs` — Added FillProgressBar for search progress screenshot (line 582)

**Review conclusion**: All 1,896 screenshot differences are expected Win10→Win11 rendering changes:
window shadows, rounded corners, control borders, scrollbar styling, disabled control colors.
No unexpected layout shifts, missing content, or bugs found.

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

### Run Information

Run date: 2026-02-17 23:28–02:57 on BRENDANX-UW25 (Win11 Enterprise, build 26200), total time **3:28:31**.

All 29 tests ran as a single batch. 28 passed, 1 failed (TestDiaQeTutorial — PersistentFilesDir
cleanup error on first download; en screenshots captured successfully before failure).

TestDiaQeTutorial zh-CHS and ja being re-run separately.

### TestTutorial Results (Win11)

| Test Method | en | zh | ja | Win10 en |
|---|---|---|---|---|
| TestAbsoluteQuantificationTutorial | 63s | 60s | 62s | 76s |
| TestAuditLogTutorial | 79s | — | — | 89s |
| TestCEOptimizationTutorial | 27s | — | — | 36s |
| TestCustomReportsTutorial | 72s | 72s | 71s | 75s |
| TestDiaTutorial | 188s* | 115s | 116s | 178s |
| TestExistingExperimentsTutorial | 155s | 154s | 154s | 142s |
| TestGroupedStudies1Tutorial | 280s | 282s | 281s | 366s |
| TestIrtTutorial | 144s | 145s | 145s | 159s |
| TestLibraryExplorerTutorial | 61s | — | — | 68s |
| TestLiveReportsTutorial | 179s | — | — | 172s |
| TestMethodEditTutorial | 80s | 79s | 80s | 96s |
| TestMethodRefinementTutorial | 127s | 126s | 127s | 162s |
| TestMs1Tutorial | 119s | 120s | 119s | 132s |
| TestPeakPickingTutorial | 83s | — | — | 81s |
| TestSmallMoleculesQuantificationTutorial | 89s | 92s | 92s | 136s |
| TestSmallMoleculesTutorial | 19s | 19s | 19s | 26s |
| TestSmallMolMethodDevCEOptTutorial | 89s | 88s | 88s | 101s |
| TestTargetedMSMSTutorial | 139s | 135s | 134s | 130s |

*DIA en includes 38s first-time data download.

**TestTutorial total**: ~83 min (vs ~96 min on Win10) — **14% faster**.

### TestPerf Results (Win11)

| Test Method | en | zh | ja | Win10 en |
|---|---|---|---|---|
| TestAcquisitionComparisonTutorial | 489s | — | — | 509s |
| TestDdaTutorial | 875s | 874s | 874s | 1611s |
| TestDiaPasefTutorial | 148s | — | — | 200s |
| TestDiaQeTutorial | 273s** | — | — | 201s |
| TestDiaTtofDiaUmpireTutorial | 623s | — | — | 989s |
| TestDiaTtofTutorial | 752s | 725s | 700s | 251s |
| TestDriftTimePredictorTutorial | 471s | — | — | 707s |
| TestHiResMetabolomicsTutorial | 74s* | — | — | 71s |
| TestOrbiPrmTutorial | 398s | — | — | 258s |
| TestPeakBoundaryImputationDiaTutorial | 103s | — | — | 183s |
| TestSmallMoleculeLibrariesTutorial | 121s | — | — | 153s |

*HiResMetabolomics en includes 8s first-time download.
**TestDiaQeTutorial FAILED during en cleanup (PersistentFilesDir modified); zh/ja did not run.

**TestPerf total**: ~125 min (vs ~156 min on Win10) — **20% faster**.

### Overall Timing Comparison

| Metric | Win10 | Win11 | Speedup |
|---|---|---|---|
| TestTutorial (all locales) | 1:36 | 1:23 | 14% |
| TestPerf (all locales) | 2:36 | 2:05 | 20% |
| **Combined** | **~4:12** | **3:29** | **17%** |

Note: Win11 ran all tests as a single batch. Win10 ran TestTutorial and TestPerf separately.
Some Win11 times include first-time data downloads (DIA 38s, HiResMetabolomics 8s).

### TestDiaQeTutorial Failure Details

**Cause**: First-time download creates DIA-QE persistent files folder. During the test, DIA-NN
generates intermediate files in the DIANN subfolder. At cleanup, the test detects the folder size
has changed (files deleted by DIA-NN after processing) and fails the assertion.

**Impact**: en screenshots were captured before cleanup. zh-CHS and ja passes did not run.

**Resolution**: Re-running TestDiaQeTutorial for zh-CHS and ja only. The persistent files folder
now has the correct post-run state, so cleanup will pass on subsequent runs.

### TestDiaQeTutorial Re-run

Re-run of TestDiaQeTutorial for all 3 locales completed successfully:
- en: 308s, zh: 284s, ja: 282s — total 14:35, 0 failures.

### Phase 2a: Enhanced Diff Report

Enhanced `ImageComparer.Core` with color-tolerant diffing (ported from PR #3861) and ran
full diff report across all 1,896 changed screenshots. Filtering options: `colorTolerance=3`,
`useColorMappings=true`, `excludeCorners=true`. Diff images saved to `ai/.tmp/diffs/`.

**Pixel count distribution (after filtering)**:

| Range | Count | % |
|---|---|---|
| 0 (pure color/corner diffs) | 528 | 28% |
| 1–1,000 | 102 | 5% |
| 1,000–5,000 | 701 | 37% |
| 5,000–10,000 | 402 | 21% |
| 10,000–20,000 | 134 | 7% |
| 20,000–35,294 | 29 | 2% |

**Statistics**: Min 0, Max 35,294, Mean 3,860, Median 2,605.

**Interpretation of 0px screenshots**: These are graph-only or region-extracted screenshots that
don't include window corners. The corner exclusion zone uses a geometric quarter-circle test
(8px radius) which does not fully account for Win11's anti-aliased corner curves. Any screenshot
containing a window frame will always have residual filtered pixels from:
1. Corner anti-aliasing — blurred pixels beyond the geometric exclusion zone
2. Title bar/close button — Win11 renders these with fundamentally different styling
3. Control borders — combo boxes, buttons, tabs have different Win11 chrome
4. These are all structural rendering differences (>20 per-channel delta), not shade variations

**Filtering effectiveness**: ~95% noise reduction (204K raw → 10K filtered on typical dialog).
Increasing tolerance from 3 to 20 only reduces from ~10K to ~3.4K — the residual is concentrated
on window chrome and control edges, all expected Win10→Win11 changes.

**Review approach**: Visual triage using Windows File Explorer thumbnail view of `ai/.tmp/diffs/`
with Ctrl+scrollwheel zoom. Red highlights in the **content area** (not borders/corners) indicate
potential unexpected differences. The 29 screenshots above 20K pixels are the priority.

**Top tutorials by mean filtered pixels** (most UI surface area affected):

| Tutorial | Count | Mean | Max |
|---|---|---|---|
| DIA-Umpire-TTOF | 28 | 8,030 | 35,294 |
| CustomReports | 84 | 7,694 | 32,066 |
| PRMOrbitrap | 42 | 6,482 | 21,902 |
| AcquisitionComparison | 36 | 6,199 | 19,792 |
| HiResMetabolomics | 16 | 6,158 | 20,038 |
| DIA-PASEF | 36 | 5,960 | 31,194 |

These tutorials have larger dialogs and chromatogram views with more Win11-styled controls.

**Key finding — window shadow diffs**: The highest pixel-count images (20K+) are screenshots
that capture a region containing a floating window (tooltip, popup, dropdown) embedded within it.
Win11 renders window shadows with a more diffuse, larger spread than Win10. When a screenshot
captures only a single window, `CleanupBorder()` strips the edges. But floating windows embedded
in a region screenshot retain their shadow, creating a large diff halo. This is entirely expected
OS-level rendering and not a content difference.

**Additional expected Win10→Win11 rendering changes observed in 10K-20K bin**:
- Disabled control colors — entire color palette changed for grayed/disabled controls
- Scrollbar thumb color — Win11 uses thinner, differently colored scrollbar thumbs
- Control borders — highlighted borders on combo boxes, text fields, buttons
- More floating window shadow diffs in screenshots with embedded popups/tooltips

All confirmed expected — no unexpected content or layout differences found so far.

### Win10 Known Issues Re-checked on Win11

| Screenshot | Win10 Decision | Win11 Status |
|---|---|---|
| ExistingQuant/en/s-22 | Defer (label thinning) | Still present — en shows every-3 vs every-4 label change. ja and zh-CHS do NOT change this time (opposite of Win10 where all 3 changed). Very sensitive to rendering. |
| ExistingQuant/ja/s-22 | Defer (label thinning) | No change on Win11 |
| ExistingQuant/zh-CHS/s-22 | Defer (label thinning) | No change on Win11 |
| CustomReports/zh-CHS/s-22 | Defer (BUG-001 blank combo) | **Not reproduced on Win11** — BUG-001 does not appear |
| iRT/ja/s-03 | Defer (BUG-001 blank combo) | **Not reproduced on Win11** — BUG-001 does not appear |
| DIA/zh-CHS/s-16 | Reverted (Targets highlighting) | **Still present** — Targets view selection/legend color rectangles appear only in zh-CHS, not en or ja. Highly consistent across both Win10 and Win11. Accept the change here but note as future debugging issue — unexplainable why Chinese alone differs. |
| DIA-Umpire-TTOF/en/s-13 | Defer (search progress text) | **Greater change** — Search progress textbox shows more text variation. Also shows progress bar completed rectangle color change, indicating Win11 changed the system progress bar color AND this screenshot uses the raw system progress bar (not `ScreenshotProcessingExtensions.FillProgressBar()`). The progress bar animation issue is exacerbated by running without Remote Desktop. The text difficulty likely explains why FillProgressBar was not applied here. |

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
