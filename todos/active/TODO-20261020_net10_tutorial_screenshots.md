# TODO-20261020_net10_tutorial_screenshots.md

## Branch Information
- **Branch**: `Skyline/work/20261020_net10_tutorial_screenshots` (in `C:\proj\pwiz-work1`), branched from
  `Skyline/work/20261020_skylinetester_hidden_window` (PR #4882) so SkylineTester screenshot runs show
  the main window
- **Base**: `master` (merge master in after #4882 squash-merges; `CommandShell.cs` resolves trivially)
- **Module**: `skyline`
- **Created**: 2026-10-20
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
- [ ] Confirm the four 26.1.1 fixes with a rerun in `pwiz-work2`
- [ ] Explain the remaining .NET 10 differences (docked-area 1 px, grid, calibration graph)
- [ ] Move the fixes to this branch, rerun on master, accept, commit
