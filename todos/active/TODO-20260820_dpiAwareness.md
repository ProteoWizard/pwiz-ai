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
- [x] Grep-hunt inventory (sweep agent): ~132 hazard sites, ~40 high;
      full annotated list in
      `TODO-20260820_dpiAwareness-inventory.md` (auxiliary file)
- [ ] Pilot fix: Start Page (anchored labels, font-derived row height,
      DPI-rescaled persisted size)
- [ ] Broader dialog sweep at 150% (needs a 150% display or a session
      with scaling changed); export/import wizards, Document Grid
- [ ] Effort estimate for the system-aware pass; report on issue #4599
- [ ] Icon assets follow-up issue: one 32px variant per icon (16px kept
      for 100%); 20/24px produced by HighQualityBicubic downscale of the
      32px source at load - per-icon hand-authoring only if a glyph
      looks bad in practice (developer decision 2026-08-20)

## Inventory summary (2026-08-20)

~132 hazard sites, ~40 high-risk. No existing DPI-compensation code
anywhere in product code - the fix introduces the first DeviceDpi
usage. Highlights: the TreeViewMS cluster (ItemHeight=16, 8.25pt
TextZoom font override, owner-draw constants 11/3/16,
DrawImageUnscaled, 3 ImageLists without ImageSize) is the biggest
coherent package and fixes both Targets and Files trees; the
DigitalRune dockPanel XML persistence (user layout + every .sky.view
stores pane sizes in device px) has the highest blast radius; ~10
persisted Size/Point settings restore raw pixels
(MsGraphExtension's splitter-as-fraction is the model idiom); 42
resize/layout handlers do manual pixel arithmetic, 14 high. Also
found a latent bug: FilesTree.cs:602 MeasureText proposed-size args
appear transposed. Full annotated inventory in the auxiliary file.

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

### 2026-08-20 - First real breakage: Start Page (developer report)

Developer-marked screenshot shows three Start Page issues at 125%:
1. Whole form physically smaller: `StartPage.cs:71/81` restores
   `Settings.Default.StartPageSize` - raw pixels persisted from
   DPI-unaware sessions. GENERAL MIGRATION CLASS: all persisted window
   sizes/locations are in pre-flip pixel units; need a one-time DPI
   rescale on restore (or store DPI alongside).
2. Recents truncate with dead space: `RecentFileControl` labels fixed
   at 225px wide (`Designer.cs:42/55`), not anchored; StartPage widens
   the control (`StartPage.cs:155`) but not the labels.
3. Cramped rows/small text: labels hard-pinned y=5/y=25, control
   height fixed 45px, hardcoded Arial 9pt; `StartPage.cs:424-444`
   manual pixel arithmetic in resize handler fights auto-scaling.

Also developer-reported: **Targets/sequence tree crowded** at 125% -
`TreeViewMS.cs:52` hardcodes `DEFAULT_ITEM_HEIGHT = 16` px (set at
ctor and in the TextZoom handler line 325), so scaled tree text fills
the whole row; `SequenceTree.cs` ImageLists use default 16x16
ImageSize, so node icons, Peak/Keep state icons, and +/- expanders
stay small vs the grown text. Fix path: multiply ItemHeight by
DeviceDpi/96 alongside TextZoom; DPI-scale ImageList.ImageSize as a
stopgap; re-author PNG assets at higher sizes for crispness
(developer notes the PNGs are updatable).

Pattern insight: designer-laid-out dialogs (AutoScaleMode.Font)
survive untouched; PROGRAMMATIC pixel layout (StartPage, and anything
like it) is where the system-aware pass will spend its effort. The
inventory should grep-hunt this pattern (runtime `new Font(`, manual
`Width/Height =` arithmetic, persisted pixel Sizes) rather than only
eyeballing dialogs.
