# Make Skyline DPI-aware (scouting)

## Branch Information
- **Branch**: `Skyline/work/20260820_dpiAwareness` (pwiz1)
- **Base**: `master`
- **Created**: 2026-08-20
- **Status**: In Progress
- **GitHub Issue**: [#4599](https://github.com/ProteoWizard/pwiz/issues/4599)
- **Module**: `skyline`
- **PR**: (pending)

## Objective

Skyline declares no DPI awareness (`Properties/app.manifest` still has the
commented-out VS template `dpiAware` element - never enabled, confirmed via
`git log -S dpiAware`), so Windows renders it at 96 DPI and bitmap-stretches
the window on scaled displays. Developer screenshot comparison vs Excel shows
pronounced blur. This scouting phase flips the manifest to system-DPI-aware
on a branch and inventories the breakage to size the real fix.

## Strategy (agreed with developer 2026-08-20)

1. **Scouting (this branch)**: system-DPI-aware manifest + app.config; run at
   125%/150%; catalog layout/owner-draw/icon breakage.
2. **System-DPI-aware release**: fix the inventory, full dialog audit at 150%.
   Fixes single-monitor high-DPI blur (the reported case).
3. **Per-monitor V2** (Excel parity): tied to the .NET 8 port
   (`TODO-20260612_net8_port`) - WinForms PMv2 on 4.7.2 is incomplete and
   DigitalRune docking / ZedGraph do not handle `WM_DPICHANGED`.
   `<gdiScaling>` was considered and rejected as a destination (GDI text only;
   ZedGraph charts are GDI+ and would stay blurry).

## Known impact areas to check

- Forms with `AutoScaleMode.None` or hardcoded pixel layouts.
- Owner-drawn controls: Targets tree (SrmTreeView), sequence/associate grids,
  custom renderers.
- ZedGraph panes + LabelLayout pixel math (should be DPI-agnostic - it
  measures real pixels - but verify at 150%).
- DigitalRune docking panels.
- 16x16 icons: sharp but small after the flip; higher-res assets are a
  follow-up.
- Tests/tooling: nightly agents run at 100% (unaffected); developers onscreen
  at 125%+ would newly see scaled geometry - affects LabelLayoutTest English
  pins and tutorial screenshot capture (96 DPI assumption).

## Tasks

- [x] Flip `Properties/app.manifest` to system-DPI-aware +
      `DpiAwareness=SystemAware` config section in app.config
- [x] Build; launch at developer's scale factor; first-pass inventory
      (main window, key dialogs) - no breakage found at 125%
- [x] Verify functional tests unaffected (TestRunner has its own
      manifest; LabelLayoutTest en pins pass onscreen at 125%)
- [ ] Broader dialog sweep at 150% (needs a 150% display or a session
      with scaling changed); export/import wizards, Document Grid,
      Immunity/tools dialogs
- [ ] Effort estimate for the system-aware pass; report on issue #4599

## Progress Log

### 2026-08-20 - Session start

Issue #4599 created; branch pushed; developer approved the staged strategy
after reviewing the Skyline-vs-Excel blur comparison screenshot.

### 2026-08-20 - Scouting flip + first launch

Flipped `Properties/app.manifest` (`dpiAware=true`) and added
`System.Windows.Forms.ApplicationConfigurationSection` with
`DpiAwareness=SystemAware` to app.config (4.7.2 mechanism; the old
`EnableWindowsFormsHighDpiAutoResizing` appSetting is the 4.6 one).
Build green. Dev machine runs 125% scaling (AppliedDPI=120), two
2560x1440 monitors - native scouting environment. First launch:
**Start Page renders crisp at 125%, layout intact.** Inventory of the
main window and key dialogs in progress.

### 2026-08-20 - First-pass inventory at 125% (UI driver sweep)

Process verified system-DPI-aware via GetProcessDpiAwareness (=1).
Everything inspected renders CRISP with intact layout at 125%:

- Start Page (recents list, tiles).
- Main window with loaded document (ABSciex4000 cal curves): menus,
  toolbar, Targets tree + icons, DigitalRune docking panes, ZedGraph
  chromatogram pane (axis labels, peak annotations, legend), Peak
  Areas pane, Results Grid (DataGridView), status bar.
- Dropdown menus (View, Settings) incl. checkmarks.
- Peptide Settings: Digestion + Modifications tabs (lists, combos,
  tooltips, Edit list buttons).
- Transition Settings: Library + Full-Scan tabs (group boxes, nested
  enable/disable controls, inline labels).

No clipping, truncation, or misalignment found in this pass. Likely
because Skyline forms use AutoScaleMode.Font and layouts have been
exercised for years by localized (wider) strings. 16x16 toolbar/tree
icons are sharp-but-small as predicted; higher-res assets remain a
follow-up for the real release.

Key test-impact finding: functional tests are hosted by TestRunner.exe,
which has ITS OWN manifest - Skyline's flip does not change test
geometry. Keeping TestRunner DPI-unaware preserves 96-DPI test
determinism (LabelLayoutTest pins, tutorial screenshots) even on
scaled dev machines. VERIFIED: TestLabelLayoutDeterminism passes
onscreen (en) at 125% with the flipped manifest - the English
geometry pins hold because TestRunner stays DPI-unaware.
