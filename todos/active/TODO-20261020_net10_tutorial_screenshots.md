# TODO-20261020_net10_tutorial_screenshots.md

## Branch Information
- **Branch**: `Skyline/work/20261020_net10_tutorial_screenshots` (in `C:\proj\pwiz-work1`), branched from
  `Skyline/work/20261020_skylinetester_hidden_window` (PR #4882) so SkylineTester screenshot runs show
  the main window
- **Base**: `master` (merge master in after #4882 squash-merges; `CommandShell.cs` resolves trivially)
- **Module**: `skyline`
- **Created**: 2026-10-20
- **PRs**: [#4896](https://github.com/ProteoWizard/pwiz/pull/4896) fixes + 389 screenshots on
  `Skyline/skyline_26_1_1` (merged 2026-10-25 as `dc97cd311c`);
  [#4915](https://github.com/ProteoWizard/pwiz/pull/4915) its cherry-pick to master (branch
  `Skyline/work/20261025_cherry_pick_4896_to_master`, worktree `C:\proj\pwiz-work3`);
  [#4897](https://github.com/ProteoWizard/pwiz/pull/4897) ImageComparer Accept (master);
  [#4882](https://github.com/ProteoWizard/pwiz/pull/4882) SkylineTester hidden main window (master)
- **Objective**: Validate auto-screenshots on master (.NET 10) at 100%, explain every changed screenshot,
  fix the regressions and accept the real UI changes - before any high-DPI screenshot work
  (`todos/backlog/TODO-high_dpi_tutorial_screenshots.md`).

## Method

- Baseline: the committed screenshots are from the Windows 11 retake, #4002 (2026-02-19). Earlier
  consistency work: #3727 (AllChromatogramsGraph frozen progress, 2026-01-02), #3779 (2026-02-12).
- To separate .NET 10 changes from earlier drift, `C:\proj\pwiz-work2` has `Skyline/skyline_26_1_1`
  (.NET 4.7.2). A full run there changed 351 screenshots.
- Review with ImageComparer. Accept/Revert (git index based) added in
  `Skyline/work/20261021_imagecomparer_accept` (`C:\proj\pwiz`): Accept stages, so the list whittles
  down to the unexplained changes.

## Explained so far (2026-10-20 / 21)

| change | cause | resolution |
|---|---|---|
| Graph legends (many tutorials) | #4025 (Brian, 2026-03-30) legend grouping changed every legend's layout: item width 3.0 -> 4.5 x size for line-only entries, fixed 3/5 px margins -> font-based | Fixed: ungrouped legends use the pre-#4025 layout (`Legend.cs`, `_hasLegendGroups`) |
| Full-scan graph title ~8 px higher (e.g. DIA-QE s-23) | #4166 (Brian, 2026-04-28) moved the scan title to the master pane for the IM multi-pane layouts, including the single-pane spectrum | Fixed: `GraphFullScan.SetScanTitle` - pane title when single-pane, master title when multi-pane |
| iRT regression title shows a full library path (DIA-QE s-04) | `AddIrtPeptidesDlg` used `RetentionTimeProvider.Name` (a path) as the graph title; not a regression, but ties screenshots to the checkout path | Fixed: title is the file name, as the dialog's grid already showed |
| Import Peptide Search wizard 10 px taller (DIA-QE s-06 and later pages) | #4385 (Nick, 2026-07-25) added the "and M-1" checkbox to the Full-Scan MS1 group; the wizard shrinks to fit that page | Real UI change: accept |
| Import Results Files dialog toolbar (AbsoluteQuant s-09) | New Refresh button | Real UI change: accept |
| Full-Scan page title in English in ja/zh (DDASearch s-09) | #3819 (Matt, 2026-06-29) sets `ImportPeptideSearchDlg_ConfigureFullScanChromatogramExtraction` at run time for Run Peptide Search; English only | Leave for the translation pass |
| DDA Search Settings controls 34 px lower (DDASearch s-11) | #3819: first commit put a preset combo at the top of `SearchSettingsControl` and moved 19 controls down 34 px; a later commit removed the combo without moving them back | Fixed: the 19 controls restored to their pre-#3819 positions (`SearchSettingsControl.resx`) |
| Full-scan title missing on the first scan (DIA-QE s-22) | #4166's master title was set after the master layout ran, so the pane painted over it | Fixed: single-pane pane title; IM layouts lay out again when the master title needs room |
| MethodEdit tip screenshots lose right/bottom border (s-21, s-22) | #4114 moved the tip shadow outside the window (OS CS_DROPSHADOW); the test still cropped 4 px for it | Fixed in the test |
| AuditLog s-08 OK button highlighted | #4726 made OK the Accept/Cancel button of Audit Log Extra Information | Real UI change: accept |
| ExistingQuant s-30/31 rdotp values and size 582x376 -> 784x512 | #4279 fixed rdotp indexing by display position (correct now); #4116 stopped moving an existing graph into the current pane, so it keeps its own pane (same size as s-23..26) | Accept |
| PeakBoundaryImputation-DIA s-16 floating RT regression graph | #4116 again: the existing Score to Run graph reappears floating | Fixed in the test: hide it before s-16 |
| ja/zh Full-Scan "and M-1" overlap (DDASearch s-09 etc.) | see the RESX sync note below | Fixed locally for 26.1.1 in #4896 (layout + Needs Review translation) |
| Checkbox corners in CheckedListBox (AbsoluteQuant, DDASearch, GroupedStudies, LibraryExplorer, MS1Filtering) | Corner antialiasing blends over prior partial repaints of the item; color depends on repaint count | Fixed: `ScreenshotManager` repaints each CheckedListBox with erase before capture (single control-adjuster walk, `CONTROL_ADJUSTERS`) |
| Replicates / Spectrum Match combo border or blank (CustomReports, iRT, DDASearch, ExistingQuant, LibraryExplorer, DIA) | Themed combo fades between visual states after the pre-capture WM_CHANGEUISTATE; capture 10 ms later caught a varying frame. Diagnostics: state identical, appearance settled within 500 ms | Fixed: screenshot runs turn off client-area animation and wait 500 ms after adjustments. CustomReports repeatable in en/ja/zh except the shadow below |
| Floating-window shadow seams (CustomReports s-22) | Windows drop shadow over the main window differs by 1 gray level on 1-2 rows between runs; not position (pinned and still varied), not timing (stable within a run) | Flake: revert. Real fix later: capture windows separately and compose. Noted in `screenshot-update-workflow.md` |
| DIA-TTOF and TTOF DIA-Umpire data changes (mProphet model s-14, mass error histogram s-24, RT residuals s-26, and following) | #4589 (Nick, 2026-09-23) keeps spectra with no peaks during chromatogram import instead of dropping them. The TTOF tutorial data is mzML (no WIFF, so no SCIEX reader), and 16% of its spectra are empty (13,065 of 81,704 in `collinsb_I180316_001_SW-A.mzML`), so it changed far more than other datasets. #4589 re-recorded `TestTtofData*.json`, `TestDiaTtofDiaUmpireTutorial*.json`, `TestQeDataDiaNN.json` and PRM-PASEF | Real software change: accept |
| DIA s-17 dotp labels missing from Peak Areas replicate panes (top pane none, bottom only over the short bar; axis 0-2 instead of 0-2.5) | Latent since the headroom code (#3247, 2024): UpdateGraph reserves label space from the label height measured in a previous draw, so a new pane (here from `RestoreViewOnScreen` / `LoadLayout`) gets none. February's run got a second UpdateGraph from retention time alignment finishing after the first draw (`WaitForDocumentLoaded`); now it returns in 13 ms. Also the top pane's labels were never added: `IsRedrawRequired` returned early on the base class's redraw. Proven with a diagnostic log of UpdateGraph/Draw/AddDotProductLabels | Fixed in `AreaReplicateGraphPane`: IsRedrawRequired no longer short-circuits; the Y-axis is re-scaled (`ReformatYAxisForLabels`) when the measured label height changes. Verified: both panes match February at s-17 |
| AbsoluteQuant graphs (.NET 10 only): docked area ~1 px shorter, column splits 1 px off | Not yet explained - a control height or DigitalRune rounding change in .NET 10? | Open |
| AbsoluteQuant s-05 grid empty area, s-15/16 calibration graph | Likely small .NET 4.7.2 -> 10 formatting changes | Open - confirm against the 26.1.1 run |

The four fixes are uncommitted in `pwiz-work2` (26.1.1) for testing; move them to this branch for master
once confirmed: `Shared/zedgraph/ZedGraph/Legend.cs`, `Controls/Graphs/GraphFullScan.cs`,
`SettingsUI/Irt/AddIrtPeptidesDlg.cs`, `FileUI/PeptideSearch/SearchSettingsControl.resx`.
Worth telling Brian about the two ZedGraph regressions so they are not undone.

## Deferred to master (.NET 10) and the translation pass

- **Sync ja/zh-Hans RESX layout with en.** The `ja` and `zh-CHS` `SearchSettingsControl` layouts still
  hold the pre-#3819 positions (consistent again once the en fix lands). Run the update that brings
  ja/zh RESX in line with en in everything but text, marking untranslated text "Needs Translation".
  On 26.1.1 this is the Jam target `IncrementalUpdateResxFiles`
  (`Executables/DevTools/ResourcesOrganizer/Jamfile.jam`). On master Jam is gone, but
  `ResourcesOrganizer/scripts/UpdateResxFiles.bat` (and the CSV import/export scripts) remain and
  already use zh-Hans; it needs a way to build `ResourcesOrganizer.exe` and call it.
  `ResourcesOrganizer/README.md` still recommends "Jamfile Targets" - update it.
  - Second case, worse: #4385 moved the MS1 isotope filter row up 10 px in en
    `FullScanSettingsControl.resx` for the new "and M-1" checkbox (y=115). The ja and zh-CHS
    layouts override that row's positions and still have the old y=102 (text box bottom at 122),
    while the checkbox has no override, so it overlaps the text box by 7 px. Seen in DDASearch
    zh-CHS s-09 (left unaccepted until fixed); ja very likely the same. Check after the sync.
- **Preset row in the Import Peptide Search button bar** (#3819: `lblSettingsPreset`,
  `cbSettingsPreset`, `btnSavePreset` in `ImportPeptideSearchDlg.resx`):
  - "Save..." is clipped to "Save." by the fixed 45 px button.
  - Controls are not aligned on the text baseline.
  - No mnemonics - probably acceptable given rare use and a crowded bar once "Finish" shows.
  - Better: a `FlowLayoutPanel` with an `AutoSize` Save button, so translations do not need a
    per-language layout. Brendan tried a quick baseline/width fix on 26.1.1 and reverted it
    (2026-10-21) to revisit on master after UpdateResxFiles can run.
- **Tutorial test conventions** (not documented in `ai/docs`): draft tutorials are named
  `...TutorialDraft` (`...TutorialLegacy` once retired) so they stay out of the released set; drafts
  run English-only until translated; keep run time within the nightly Perf/Tutorial budget; match the
  comment density of existing tutorial tests. Prompted by a ~1.5 h draft test that ran in every language.

## Tasks

- [x] PR #4882: SkylineTester main window hidden in screenshot modes
- [x] ImageComparer Accept/Revert on the git index (branch `20261021_imagecomparer_accept`)
- [x] Commit the 26.1.1 fixes and accepted screenshots (#4896)
- [ ] Rerun the 20 tutorials with remaining changes in `pwiz-work2` (list in its
      `SkylineTester test list.txt`; 9 are TestPerf - enable perf tests in SkylineTester)
- [ ] Explain the remaining .NET 10 differences (docked-area 1 px, grid, calibration graph)
- [ ] Move the fixes to this branch, rerun on master, accept, commit
- [ ] Cherry-pick #4896's code commit to master (zh-CHS -> zh-Hans for the two Full-Scan layout
      files; master's Legend.cs/GraphFullScan.cs are LF-normalized, so re-apply rather than pick)

## Progress log

### 2026-10-21 (end of day)

- #4896 (26.1.1 fixes + 218 accepted screenshots) and #4897 (ImageComparer Accept) opened; TeamCity
  runs overnight. #4882 still open.
- Brendan reverted ~35 screenshots rather than fix them, and started an overnight retake of ALL
  tutorial screenshots in `C:\proj\pwiz-work2` (branch `Skyline/work/20261021_screenshot_fixes_26_1_1`,
  .NET 4.7.2) to see what is left and whether it is fixable.
- 26.1.1 line endings are mixed in some files (Legend.cs: 145 of 1150 lines CRLF); master was
  normalized in #4789. On 26.1.1 commit with `git -c core.autocrlf=false` and apply diffs to the
  original blob so unchanged lines keep their endings.

### 2026-10-22 / 23

- Second full 26.1.1 retake (drafts renamed `...TutorialDraft`, so out of the Tutorial tests set). Every
  remaining change explained in "Explained so far": checkbox corners, combo fades, window shadows (flake),
  #4589 TTOF data, dotp labels, x-axis label skipping, DIA s-16 selection, IM full-scan three-pane text.
- Pushed to #4896: `8c26943ee8` (code, tests, RESX, tutorial text) and `7ce48dce05` (113 screenshots).
  Third overnight retake running 2026-10-23.
- Next: if clean, squash-merge #4896 to `Skyline/skyline_26_1_1`, cherry-pick to master (zh-Hans RESX,
  LF files, re-apply rather than pick; the local `Skyline/work/20261021_screenshot_fixes_master` in
  `C:\proj\pwiz-work3` predates this round and should be rebuilt from the squash commit), then a
  .NET 10 overnight retake on master.

### 2026-10-25 - #4896 merged

Squash-merged to `Skyline/skyline_26_1_1` as `dc97cd311c` (admin merge; no reviewer). 389 screenshots in
29 tutorials plus 24 code/test/doc files, including the PopupPickList redraw fix (`0e9ca3f92f`) and the
User32Test P/Invoke count. Work branch deleted locally and on GitHub. Next: cherry-pick `dc97cd311c` to
master, then the .NET 10 review on master, then PR #4602 (high-DPI) at 100% and 150%.

Cherry-picked to master as #4915 (one conflict: `DiannSearchPerfTest` keeps master's attributes, since
`NoLeakTesting` does not exist there; zh-CHS RESX edits followed the rename to zh-Hans; LF kept). Built
on .NET 10, CodeInspection passes. Next: full tutorial screenshot retake on master (.NET 10) in
`C:\proj\pwiz-work3` (Release build for SkylineTester), and explain every change against the 26.1.1 set.

### 2026-10-26 - First .NET 10 retake on master (#4915 branch, `C:\proj\pwiz-work3`)

Overnight SkylineTester run (Release, staged to `bin\staging\Release`, en/zh-Hans/ja) in `pwiz-work3`.
Log: `pwiz-work3/pwiz_tools/Skyline/SkylineTester.log`. ~360 changed PNGs left uncommitted in the
worktree for review.

**Run failures (not UI): the frozen import-progress screenshot.** First failure TestGroupedStudies1
(first test in the run order using `PauseForAllChromatogramsGraphScreenShot`): 360 s timeout in
`WaitForConditionUI(IsReadyForScreenshot)`; thread dump shows the chromatogram loader blocked at
`WaitIfProgressFrozen` (`Chromatogram.cs` FinishLoadSynch); file rows at 0% are the frozen display.
`ReleaseFrozenProgress` was never called on failure, so every later test's import hung ("Expecting
loaded document") until DriftTimePredictor hung outright. Uncommitted in `pwiz-work3`:
`try/finally` around the wait+screenshot in `TestFunctional.PauseForAllChromatogramsGraphScreenShot`
(keep), plus DIAG logging to `%LOCALAPPDATA%\SkylineAcgDiag.log` in `AllChromatogramsGraph.cs` and
`Model/Results/Chromatogram.cs` (remove before commit; lines marked `// DIAG`). GroupedStudies1 alone
(Debug, Run-Tests -TakeScreenshots) PASSED: freeze set at 0%, file0 reached 100%, froze, released.
So the failure depends on earlier tests in the run (stale ACG window, a setting, timing). Next: rerun
AbsoluteQuant..ExistingExperiments + GroupedStudies1 (3 languages) in Release with the logging.

**UI differences (AbsoluteQuant en analyzed):**
- Docking layout 1 px off on .NET 10: Targets tree content exactly 1 px right (s-06, s-10 tree region
  matches with 0 px after dx=+1); chromatogram panes 1 px left and slightly different size, so ZedGraph
  redraws curves sub-pixel differently (most of the 46k-95k px per image, looks like line colors).
  Cause unknown: DigitalRune proportional-size rounding, WinForms .NET 10 client-size/frame metrics, or
  `.view` layout restore. Goal (Brendan): tweak DigitalRune (source
  `C:\proj\maccoss-developers\skylinedev\DigitalRune-Docking-Windows`) so .NET 10 places windows as
  .NET 4.7.2 did, avoiding a mass screenshot replacement. Approach: log DockPanel/pane bounds at the
  same AbsoluteQuant step on 26.1.1 (`pwiz-work2`, .NET 4.7.2) and master (`pwiz-work3`, .NET 10);
  first differing bound shows where.
- DataGridView grays (s-05, s-15): empty area `ABABAB`->`A0A0A0`, border `A0A0A0`->`646464`; likely a
  WinForms default changed between .NET Framework and .NET 10 (unverified).
- Tools in `ai/.tmp/sessions/20261021-night/`: `classify-diffs.ps1`, `pairs.ps1`, `crop-zoom.ps1`,
  `best-shift.ps1` (finds the dx/dy shift that best matches a region; C# inner loop).

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20261025_cherry_pick_4896_to_master.md` before starting work.
