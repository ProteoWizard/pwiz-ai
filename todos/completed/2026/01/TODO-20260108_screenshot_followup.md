# Screenshot Testing Follow-up Improvements

## Branch Information
- **Branch**: `Skyline/work/20260108_screenshot_followup`
- **Base**: `master`
- **Created**: 2026-01-08
- **GitHub Issue**: [#3778](https://github.com/ProteoWizard/pwiz/issues/3778)
- **PR**: [#3779](https://github.com/ProteoWizard/pwiz/pull/3779)

## Objective

Follow-up items from the screenshot consistency sprint that were not critical for achieving consistent ACG screenshots but would improve the overall screenshot testing infrastructure.

## Completed

- [x] **Fix MethodRefinement s-09** - Added JiggleSelection after RestoreViewOnScreen to force AutoZoomNone
- [x] **Fix LiveReports audit log screenshots (s-02, s-68, s-69)** - Added TestTimeProvider wrapper
- [x] **Fix tests ending up in accessibility mode** - Send WM_CHANGEUISTATE recursively to all controls
- [x] **ImageComparer Diff Amplification Features** - Add diff-only view and amplification for 1-2px diffs
- [x] **Paint over ACG per-file progress bars** - Extended FillProgressBar to handle all visible file progress bars
- [x] **Fix SetScrollPos not scrolling content** - Post WM_HSCROLL/WM_VSCROLL after SetScrollPos
- [x] **Fix MinimizeResultsDlg race condition** - IsComplete used stale stats; replaced properties with SetNoiseLimit()
- [x] **Fix SmallMoleculeIMSLibraries s-10 zoom** - Used test helper ZoomXAxis() which forces Refresh()
- [x] **Fix DIA-QE s-05 DIANN folder** - Deleted DIANN folder causing screenshot diff
- [x] **Fix GroupedStudies s-18 Precursor Results** - Fixed list ordering
- [x] **Committed 95 accepted tutorial screenshots** - Focus rects, ACG progress bars, chromatogram baselines, etc.

## Not Addressed (low priority, no GitHub issue needed)

- **DDA Search output s-13** - Progress count is unpredictable; would need to fake the value
- **X-Axis Label Orientation (MS1Filtering s-21, ja/zh-CHS only)** - ZedGraph auto-layout; very niche
- **CleanupBorder Algorithm** - Speculative off-by-one for Windows 11 curved corners; will surface when build machines upgrade
- **Remove unused timeout parameter** - Minor cleanup of PauseFor*ScreenShot functions
- **PeakBoundaryImputation-DIA s-01** - Minor splitter positioning issue

## Technical Notes

### Accessibility Mode Fix
Windows UI state tracks keyboard vs mouse mode. Send `WM_CHANGEUISTATE` before capture:
```csharp
const int WM_CHANGEUISTATE = 0x0127;
const int UIS_SET = 1;
const int UISF_HIDEFOCUS = 0x1;
const int UISF_HIDEACCEL = 0x2;

SendMessage(form.Handle, WM_CHANGEUISTATE,
    (IntPtr)((UIS_SET << 16) | UISF_HIDEFOCUS | UISF_HIDEACCEL), IntPtr.Zero);
```

### ImageComparer Enhancements
1. "Diff-only" view - paint only diff pixels on white background
2. "Amplification" slider - expand visual area around changed pixels (radius 1-10)

## Progress Log

### 2026-01-08 - Session Start

Starting work on this issue. Created branch and TODO file.

### 2026-01-08 - LiveReports audit log fix

Added `TestTimeProvider` wrapper to `LiveReportsTutorialTest.TestLiveReportsTutorial()` to ensure
consistent audit log timestamps in screenshots s-02, s-68, s-69. This follows the pattern established
in `AuditLogTutorialTest`.

**File**: `pwiz_tools/Skyline/TestTutorial/LiveReportsTutorialTest.cs`

### 2026-01-08 - ACG per-file progress bar painting

Added ability to paint over per-file progress bars in AllChromatogramsGraph screenshots to prevent
Windows progress bar animation inconsistencies (only consistent over RemoteDesktop otherwise).

**Changes**:
1. `FileProgressControl.cs` - Added `ProgressBar` property to expose the progress bar control
2. `AllChromatogramsGraph.cs` - Added `GetVisibleFileProgressBars()` method to enumerate visible bars
3. `ScreenshotProcessingExtensions.cs` - Added `FillProgressBars(IEnumerable<ProgressBar>)` overload
4. `TestFunctional.cs` - Updated `PauseForAllChromatogramsGraph` to fill all progress bars

### 2026-01-08 - Accessibility mode fix (focus rectangles and mnemonics)

Fixed long-standing issue where focus rectangles and mnemonic underscores would appear in screenshots
even when tests were started with a mouse click. Windows tracks keyboard vs mouse mode, and any
keypress (including F5 to start the test) flips into keyboard mode showing these UI cues.

**Solution**: Send `WM_CHANGEUISTATE` message to the top-level form immediately before each screenshot
capture to hide focus rectangles (`UISF_HIDEFOCUS`) and mnemonic underscores (`UISF_HIDEACCEL`).

**Changes**:
1. `User32.cs` - Added `WM_CHANGEUISTATE` to `WinMessageType` enum and `UISF_HIDEALL` constant
2. `ScreenshotManager.cs` - Added `HideKeyboardCues()` method called from `HideSensitiveFocusDisplay()`

**Tested**: Started test with F5, saw focus rectangles in UI during test, but none in screenshots.

### 2026-02-08 - ImageComparer/ScreenshotPreviewForm diff amplification

Added diff-only view and amplification features to both ImageComparer and ScreenshotPreviewForm:

**New Features**:
1. **Diff-only button** (blank.png icon, keyboard shortcut 'D') - Shows diff pixels on white background
2. **Amp button** (text toggle, keyboard shortcut 'A') - Expands diff pixels to 5px radius squares
3. **Image source popup menu** - Context menu with icons for Git HEAD, Web (and Disk in ScreenshotPreviewForm)

**Technical Details**:
- `ScreenshotDiff` class extended with `DiffOnlyImage` property and `CreateAmplifiedImage()`/`CreateAmplifiedDiffOnlyImage()` methods
- Amplification uses `HashSet<Point>` to collect unique pixels, avoiding overlapping alpha darkening
- When no diff exists: Amp does nothing, Diff-only shows white rectangle

**Files Changed**:
- `TestUtil/ScreenshotInfo.cs` - Added diff tracking and amplification methods
- `TestUtil/ScreenshotPreviewForm.cs` - Added UI controls and GetDisplayImage() logic
- `TestUtil/ScreenshotPreviewForm.Designer.cs` - Added toolbar buttons and context menu
- `ImageComparer/ScreenshotInfo.cs` - Same changes as TestUtil version
- `ImageComparer/ImageComparerWindow.cs` - Added UI controls and GetDisplayImage() logic
- `ImageComparer/ImageComparerWindow.Designer.cs` - Added toolbar buttons and context menu

### 2026-02-08 - Accessibility mode fix improvement

Fixed issue where some forms (like ImportPeptideSearchDlg wizard pages) still showed focus rectangles
and mnemonic underscores despite the WM_CHANGEUISTATE fix. The message wasn't propagating through
TabControl/WizardPages containers.

**Solution**: Changed `HideKeyboardCues()` to recursively send WM_CHANGEUISTATE to all descendant controls,
not just the top-level form.

**File**: `TestUtil/ScreenshotManager.cs` - Added `HideKeyboardCuesRecursive()` method

### 2026-02-09 - SetScrollPos fix

Win32 `SetScrollPos` only moves the scrollbar thumb — it doesn't scroll the control's content.
Fixed `User32Extensions.SetScrollPos()` to also post `WM_HSCROLL`/`WM_VSCROLL` with
`SB_THUMBPOSITION`, matching the pattern in `AutoScrollTextBox`. This fixed horizontal scroll
positioning in CustomReports, GroupedStudies, DIA, and PRM tutorial tree views.

**Files**: `User32.cs` (added `WM_HSCROLL`), `User32Extensions.cs` (post scroll message)

### 2026-02-09 - MinimizeResultsDlg race condition fix

`Ms1FullScanFilteringTutorial` s-44 showed inconsistent compression percentages (49% or 70% instead
of correct 55%). Root cause: two bugs in the test interaction with MinimizeResultsDlg.

1. **Stale IsComplete**: `_minStatistics` was not reset when Settings changed and a new background
   worker started. `WaitForConditionUI(IsComplete)` could return true from the old worker's results.
2. **Wrong NoiseTimeRange**: `LimitNoiseTime = true` fired `CheckedChanged` which parsed the textbox
   (default "1" from resx) before `NoiseTimeRange = 2` set it. Worker computed with wrong value.

**Fix**: Replaced `LimitNoiseTime`/`NoiseTimeRange` properties with `SetNoiseLimit(bool, double?)`
that sets textbox before checkbox. Added `_minStatistics = null` reset in Settings setter.
Added `PercentOfTotalCompression` property and assertion of expected 55% value.

**Files**: `MinimizeResultsDlg.cs`, `Ms1FullScanFilteringTutorial.cs`, `PerfMinimizeResultsTest.cs`

### 2026-02-09 - SmallMoleculeIMSLibraries s-10 zoom fix

`GraphSpectrum.ZoomXAxis()` only sets axis scale properties without triggering a repaint.
The test helper `AbstractFunctionalTestEx.ZoomXAxis()` additionally calls `ApplyState`,
`SetScale`, and `Refresh()`. Switched the test to use the helper.

### 2026-02-09 - Committed 95 screenshots, 12 deferred

Ran full auto-screenshot suite. Reviewed all 106 changed PNGs, annotated in
`ai/.tmp/screenshot-review-20260209.csv`. Committed 95 accepted + 6 C# files.

**12 deferred PNGs** (remaining as unstaged modifications):
- DIA-QE s-05 (en/ja/zh-CHS) - Fixed (DIANN folder deleted)
- DIA-Umpire-TTOF s-13 (en) - DDA search output numbers unpredictable
- GroupedStudies s-18 (en/ja/zh-CHS) - Fixed (Precursor Results ordering)
- MethodRefine s-09 (en/ja/zh-CHS) - Fixed (JiggleSelection after RestoreViewOnScreen)
- PeakBoundaryImputation-DIA s-01 (en) - Splitter change to lose border
- SmallMoleculeIMSLibraries s-10 (en) - Fixed (used test helper ZoomXAxis)

### 2026-02-09 - MethodRefine s-09 zoom fix

Wrong zooming only reproduced in full auto-screenshot suite, not in isolation. `AutoZoomNone()` was
called before `RestoreViewOnScreen()` which destroys and recreates all DockableForms. Added
`JiggleSelection(up: true)` after `RestoreViewOnScreen` and `WaitForGraphs` to force the chromatogram
graphs to redraw with the correct zoom setting. Also enhanced `JiggleSelection` to accept an `up`
parameter (some contexts need to move up first to avoid going past the end of the tree).

Revealed that the old committed screenshot had duplicate transitions in the legend.

**Files**: `MethodRefinementTutorialTest.cs`, `TestFunctional.cs`

### 2026-02-09 - Additional fixes for deferred screenshots

* Fixed DIA-QE s-05: Delete DIANN folder before screenshot in `DiaSwathTutorialTest.cs`
* Fixed GroupedStudies s-18: Set `TopNode` to ensure Precursor Results at top of filter tree
* Fixed SmallMoleculeIMSLibraries s-10: Replaced `GraphSpectrum.ZoomXAxis()` (no repaint) with
  `AbstractFunctionalTestEx.ZoomXAxis()` (includes Refresh). Exposed `ZedGraphControl` property.
* Removed now-unused `GraphSpectrum.ZoomXAxis(double, double)` public method

### 2026-02-13 - PR #3779 merged, TODO completed

PR merged to master. Remaining low-priority items (DDA search output count, x-axis label orientation,
CleanupBorder algorithm, unused timeout parameter, PeakBoundaryImputation splitter) deferred without
GitHub issues — they're speculative, cosmetic, or will resurface naturally.

## Bug Fixes

### 2026-02-13 - MinimizeResultsDlg race condition in Ms1 tutorial

- **Branch**: `Skyline/work/20260108_screenshot_followup-fix`
- **PR**: [#3977](https://github.com/ProteoWizard/pwiz/pull/3977)

Nightly tests failed with `Assert.AreEqual failed. Expected:<55>. Actual:<36>` in
`Ms1FullScanFilteringTutorial` at the `PercentOfTotalCompression` assertion added in PR #3779.

**Root causes identified (three issues):**

1. **OnProgress race condition**: `MinimizeResultsDlg.OnProgress` unconditionally wrote `_minStatistics`
   from any background worker, including stale ones. When the dialog opens, `StartStatisticsCollection()`
   starts a worker with initial settings (no noise limit). Then `SetNoiseLimit(true, 2)` starts a new
   worker. The stale worker could write its results (70%) to `_minStatistics`, and `WaitForConditionUI`
   would see `PercentComplete=100` from the wrong worker.

2. **Missing WaitForDocumentLoaded**: `SaveDocument(minimizedFile)` is a Save As to a new path, which
   triggers reload of libraries and the .skyd from the new location. Without waiting, `DocumentChanged`
   events fired while the minimize dialog was open, causing `GetChromCacheMinimizer(document)` to return
   new instances and restart computation repeatedly.

3. **Vendor-dependent compression ratio**: The mzML test files are truncated at 50 minutes while native
   .wiff files extend to 118.8 minutes (confirmed with ProteoWizard SeeMS). The 2-minute noise trimming
   produces 55% compression with .wiff data but only 36% with mzML. Nightly machines without AB SCIEX
   vendor readers fall back to mzML, producing a fundamentally different cache.

**Fixes:**
- `OnProgress`: Guard `_minStatistics` update with `ReferenceEquals` check for current
  `StatisticsCollector`, while still allowing `IsMinimizingFile` progress/cancel to run
- Extracted `UpdateLimitNoiseTime()` from `CheckedChanged` handler so `SetNoiseLimit` can
  call it directly instead of using a toggle trick that briefly applies wrong settings
- Added `WaitForDocumentLoaded()` after `SaveDocument(minimizedFile)`
- Made assertion vendor-aware with tolerance: `PreferWiff ? 55 : 36` (±1)
- Fixed mouse-over tooltip exception in MinimizeResultsDlg

**Files**: `MinimizeResultsDlg.cs`, `Ms1FullScanFilteringTutorial.cs`

**Validated**: 180+ iterations including French with mzML (CanImportAbWiff=false).

PR #3977 merged 2026-02-13.
