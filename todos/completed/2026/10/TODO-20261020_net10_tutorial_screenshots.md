# TODO-20261020_net10_tutorial_screenshots.md

## Branch Information
- **Branch**: `Skyline/work/20261020_net10_tutorial_screenshots` (in `C:\proj\pwiz-work1`), branched from
  `Skyline/work/20261020_skylinetester_hidden_window` (PR #4882) so SkylineTester screenshot runs show
  the main window
- **Base**: `master` (merge master in after #4882 squash-merges; `CommandShell.cs` resolves trivially)
- **Module**: `skyline`
- **Status**: Completed
- **Created**: 2026-10-20
- **PRs**: [#4896](https://github.com/ProteoWizard/pwiz/pull/4896) fixes + 389 screenshots on
  `Skyline/skyline_26_1_1` (merged 2026-10-25 as `dc97cd311c`);
  [#4915](https://github.com/ProteoWizard/pwiz/pull/4915) its cherry-pick to master plus the .NET 10
  fixes (merged 2026-10-29 as `4f92fe97ba`; branch `Skyline/work/20261025_cherry_pick_4896_to_master`,
  worktree `C:\proj\pwiz-work3`);
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
| Docked layout 1 px off on .NET 10 (tree 1 px right with its left border showing, panes 1 px shorter, graphs resized) | Not DigitalRune. The .NET 10 port (254112b277) changed `dockPanel` from anchored at -1,0 and 736x444 in a 734x443 `panel1` (1 px past the left, right and bottom edges, hiding the panes' outer borders) to `Dock = Fill`. Proven by dumping control bounds on both runtimes | Fixed: `panel1_Layout` sets the dock panel to `-1, 0, width + 2, height + 1` (no anchor deltas, so the Windows-container fix stays). AbsoluteQuant s-06, s-10..s-13 identical in en/ja/zh-CHS |
| Status bar size grip (every main-window screenshot, 18x18 px corner) | .NET 10 draws a different, anti-aliased grip | Fixed: `ClassicSizingGripRenderer` (ToolStripSystemRenderer) draws the .NET Framework six-dot grip; pixel-identical |
| DataGridView grays (AbsoluteQuant s-05, s-15; every grid screenshot) | dotnet/winforms #5832 (2021, accessibility 3:1 contrast): GridColor default and header-cell dark border `ControlDark` -> `WindowFrame` (646464), plus a WindowFrame divider over the themed header divider (E5E5E5); separately the BackgroundColor default became `ControlDark` (A0A0A0, was AppWorkspace ABABAB). The header lines are hard-coded in internal methods | Accepted (Brendan, 2026-10-26): intended accessibility change. Restoring background + GridColor alone leaves the headers dark (tried, reverted) |
| AbsoluteQuant s-09 "Open" button text 1 px higher | `BaseFileDialogNE.actionButton` is 20 px high (odd leftover around the text); .NET 10 rounds vertical centering the other way. 23 px buttons unaffected | Real .NET 10 change: accept |

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
- [x] Rerun the 20 tutorials with remaining changes in `pwiz-work2` (list in its
      `SkylineTester test list.txt`; 9 are TestPerf - enable perf tests in SkylineTester)
- [x] Explain the remaining .NET 10 differences (docked-area 1 px, grid, calibration graph)
- [x] Move the fixes to this branch, rerun on master, accept, commit
- [x] Cherry-pick #4896's code commit to master (zh-CHS -> zh-Hans for the two Full-Scan layout
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

### 2026-10-26 (evening) - AbsoluteQuant .NET 10 differences explained

Method: temporary `DiagDumpBounds` in the AbsoluteQuant test dumped every control's bounds at s-06/s-10/s-11
on 26.1.1 (`pwiz-work2`, .NET Framework 4.8) and master (`pwiz-work3`, .NET 10); the first differing line
was `dockPanel` itself. Work files and logs: `ai/.tmp/sessions/20261026-dock/` (`bounds/`, `diffmap.ps1`,
`wf/` WinForms sources, `run-*.log`).
- Uncommitted in `pwiz-work3`: `Skyline.Designer.cs` + `SkylineGraphs.cs` (`panel1_Layout`), `Skyline.cs` +
  new `Controls/ClassicSizingGripRenderer.cs` (status bar grip). Built, AbsoluteQuant passes en/ja/zh-CHS
  with screenshots; TestAreaCVHistograms, TestFilesTreeForm, TestLabelLayoutDeterminism, TestArrangeGraphs pass.
- AbsoluteQuant now differs from the committed set only in s-05/s-15 (grid colors, decision pending) and
  s-09 (Open button text, accept).
- Grid colors accepted; s-09 accepted (standard-size buttons in Import Results Files judged not worth
  it: the buttons match the 20/21 px controls in their rows, and resizing changes every screenshot of
  the dialog in 3 resx layouts - revisit in the high-DPI pass if at all).
- Pushed to #4915: `7f098a7fb0` (dock overhang + grip renderer), `c9e49db333` (9 AbsoluteQuant PNGs).
- Next: re-run the full .NET 10 retake and classify what is left.

### 2026-10-27 - GroupedStudies1 frozen import progress hang

- Cause (proven with the DIAG log): `RefreshSelectedControl` shows the file name until the selected file
  passes 0%, and `UpdateStatus` returned early for the status that triggered the freeze. In the zh run of
  the second retake, file 0 went 0% -> 100% between two UI updates, so the graph never replaced the file
  name and `IsReadyForScreenshot` waited out 360 s. Not caused by earlier tests.
- Fix (uncommitted, `AllChromatogramsGraph.UpdateStatus`): apply the status that reaches the threshold,
  then freeze. Verified Release, en + zh in one process: zh hit the 0 -> 100% case and was ready in 120 ms.
  `TestFunctional.cs` try/finally also still uncommitted. DIAG logging removed.
- Note, not pursued: GroupedStudies s-03 (SRM, `ChromatogramDataProvider`) can freeze at 99% or 100% of
  file 0, i.e. with or without the last chromatogram(s), so a peak can appear or not; the x-axis end
  also varied (49 vs 50, only Y is locked). The freeze was designed around `SpectraChromDataProvider`.
  Likely present on .NET 4.7.2 too. Accept s-03 variation for now.
- Committed `74ba919d91` (freeze fix + try/finally).

### 2026-10-27 (afternoon) - TestTutorial retake reviewed and committed

All 18 TestTutorial screenshots in en/zh/ja accepted or reverted by Brendan. Pushed to #4915:
- `f535098389` stable peptide colors (`ColorGenerator` uses the .NET Framework 64-bit string hash;
  `TestPeptideColorsStable`). Proof: DIA s-16 regenerated pixel-identical to the committed .NET Framework one.
- `5f945a77fc` Import Transition List column-type combo strip takes the grid's BackgroundColor (ExistingQuant s-06).
- `c7b97167f9` `AvailableFieldsTree` ImageList explicit Depth32Bit (only ImageList relying on the default;
  designer lists load fixed-depth ImageStreams). Still 8-bit by design choice: ChooseViewsControl,
  ManageLayoutsForm, ExportLiveReportDlg.
- `71df45db2b` 344 accepted PNGs.
Accepted .NET 10 changes, explained: WinForms #5832 grid/header contrast; ImageList default depth;
menu selection fill (B3D7F3 = 30% Highlight/Window blend); MethodEdit s-17 autocomplete order (ICU vs NLS:
`"` sorts after `;`); MethodEdit s-22 tip values (float.ToString shortest round-trip vs 7 digits; "G7"
would restore).
- Gotcha: screenshot runs pause while the RDP window is minimized (looked like a hang; ExistingExperiments
  took 1,306 s instead of 133 s).
- Next: Brendan running the TestPerf tutorials (~2 h; AcquisitionComparison, DDASearch, DIA-PASEF,
  DIA-QE, DIA-TTOF, DIA-Umpire-TTOF, IMSFiltering).

### Candidate night session: trim screenshot settle waits

Every auto screenshot sleeps 2.5 s fixed, besides WaitForGraphs(): 1,500 ms in
`TestFunctional.CaptureScreenShot` (#3779), 500 ms activation and 500 ms repaint in
`ScreenshotManager.ActivateScreenshotForm` (#3283, #4896). About 2,000 screenshots per full pass, so
~83 min of a ~3.5 h full run (TestTutorial alone ~1.5 h). With client-area animation now off during
screenshot runs (`DisableControlAnimations`), the UI likely settles faster.
Plan: make the three waits overridable for a run (env var), start from the accepted screenshot set,
run TestTutorial (then TestPerf) at reduced waits (e.g. 0 / 100 / 250 ms), count and classify changed
PNGs per setting, and report which screenshots need which wait. Possibly replace fixed sleeps with
"UI thread idle and painted" plus a short delay. Needs an unattended desktop with RDP restored.

- Earlier note, superseded by `f535098389`: `ColorGenerator.GetColorIndex` uses `string.GetHashCode()`,
  which .NET 10 randomizes per process (verified: 3 pwsh runs, 3 values; .NET Framework stable). Peptide
  colors are generated at load, not stored. A drop-in of the .NET Framework 64-bit hash reproduced 26.1.1
  colors exactly. Revisit if peptide colors are seen changing between runs.

### 2026-10-29 - Merged

PR #4915 merged as commit 4f92fe97ba (squash). It carried the #4896 cherry-pick and the .NET 10 fixes:
dock panel 1 px overhang, classic status bar grip, stable peptide colors (ColorGenerator, .NET Framework
64-bit string hash), zero axis tic noise (Scale.AddSteps), Library Match axis title font, AvailableFieldsTree
ImageList depth, Import Transition List combo strip color, Show timestamps checkbox alignment when Open Log
is hidden, msconvert progress reduced to one line per 1,000 spectra (MsconvertExe), and test reliability
fixes (frozen import progress hang, MS Amanda download, Koina prediction wait, PathEx display seam for
alert text, user-documents paths for the iRT and IMS library screenshots, DDA s-12 progress lock). Every
tutorial screenshot in en/zh-Hans/ja was accepted or reverted, except DDASearch s-15, left unaccepted as
the visible case for #4935.

Follow-ups, not in this PR:
- #4935: show all MS/MS ID evidence a precursor uses, and drop outlier IDs from the extraction window
- Candidate night session: trim the 2.5 s of fixed screenshot waits (section above)
- Possible tech-debt issue (not filed): a real msconvert wrapper class like BlibBuild's
- Possible: switch the DDA search tutorial from MS Amanda to MSFragger; pin the MS Amanda download version
- Retire `pwiz-work1` branch `Skyline/work/20261020_net10_tutorial_screenshots` (superseded; has
  uncommitted AbsoluteQuant PNGs - ask first)
- Next: PR #4602 (high-DPI) at 100%, then 150%
