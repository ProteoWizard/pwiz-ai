# Make Skyline DPI-aware (scouting)

## Branch Information
- **Branch**: `Skyline/work/20260820_dpiAwareness` (pwiz1)
- **Base**: `master`
- **Created**: 2026-08-20
- **Status**: In Progress
- **GitHub Issue**: [#4599](https://github.com/ProteoWizard/pwiz/issues/4599)
- **Module**: `skyline`
- **PR**: [#4602](https://github.com/ProteoWizard/pwiz/pull/4602) (draft)

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
  at 150%+ would newly see scaled geometry - affects LabelLayoutTest English
  pins and tutorial screenshot capture (96 DPI assumption).

## Tasks

- [x] Flip `Properties/app.manifest` to system-DPI-aware +
      `DpiAwareness=SystemAware` config section in app.config
- [x] Build; launch at developer's scale factor; first-pass inventory
      (main window, key dialogs) - no breakage found at 150%
- [x] Verify functional tests unaffected (TestRunner has its own
      manifest; LabelLayoutTest en pins pass onscreen at 150%)
- [x] Grep-hunt inventory (sweep agent): ~132 hazard sites, ~40 high;
      full annotated list in
      `TODO-20260820_dpiAwareness-inventory.md` (auxiliary file)
- [x] Pilot fix: Start Page. New `Util/DpiUtil.cs` (first DPI
      compensation code in the codebase): GetFactor/Scale via
      Control.DeviceDpi + ScaleFromLogical/ScaleToLogical establishing
      the "persist 96-DPI logical units, scale on restore" convention
      (backward compatible: DPI-unaware builds saved logical-96 values
      by definition). StartPage restores/saves size through it and
      scales its layout literals (18/40/20/3); RecentFileControl rows
      laid out from font metrics with width-tracking anchored labels.
      Verified at 150%: window size restored correctly, rows use full
      panel width, name/path lines have proper separation. All 12
      StartPage functional tests pass (offscreen).
- [ ] ActionBoxControl wizard tile captions clip at 150%
      ("Import DIA Peptide Se...") - fixed-size tiles, add to the
      dialog-layout package
- [ ] Broader dialog sweep at 150% (needs a 150% display or a session
      with scaling changed); export/import wizards, Document Grid
- [ ] Effort estimate for the system-aware pass; report on issue #4599
- [ ] Icon assets follow-up issue: one 32px variant per icon (16px kept
      for 100%); 20/24px produced by HighQualityBicubic downscale of the
      32px source at load - per-icon hand-authoring only if a glyph
      looks bad in practice (developer decision 2026-08-20)

## Tree cluster (started 2026-08-20, in progress)

Implemented the first slice on the same branch (uncommitted until
verified):
- `TreeViewMS`: instance properties `DashLength`/`TextPadding`/
  `ImgWidth` (DPI-scaled versions of the 96-DPI consts); ItemHeight
  DPI-scaled in ctor, `OnTextZoomChanged`, and a new `OnHandleCreated`
  override (designer files re-set 16px after the ctor); expander
  glyphs drawn DPI-scaled; `DrawNodeCustom`/`XIndent`/`HorizScrollDiff`
  use the scaled values. Font left in points (scales naturally).
- `DpiUtil`: added `Scale(Graphics,int)` for static draw code,
  `ScaleSize`, and `ScaleImageForList` (32bpp ARGB, color key applied
  BEFORE bicubic resampling so magenta cannot bleed into glyph edges;
  returns original image untouched at 100% so 96-DPI behavior is
  byte-identical).
- `SequenceTree`: both ImageLists get DPI-scaled ImageSize +
  Depth32Bit only when factor > 1 (96-DPI config unchanged); all 34
  Add calls routed through `AddNodeImage`/`AddStateImage`; edit box
  MinimumWidth scaled.
- `FilesTree`: same ImageList treatment (17 icons).
- `SrmTreeNode`: color swatch + annotation triangle scaled.
- `PeptideTreeNode`: padding via instance property / Graphics overload
  in static `DrawPeptideText` (also used by ViewLibraryDlg's list).

Build + tree tests + CodeInspection/QuickInspection all green; 96-DPI
behavior verified unchanged (factor-1 short circuits). Developer
visually confirmed the tree at **125%** (2026-08-21, via RDP - the
session DPI comes from the CLIENT's scaling, 3440x1440 at 125%;
Windows Settings does not show scaling inside RDP, use the DPI probe
from [[dpi-query-live-not-registry]]). Re-checked at **150%**
2026-08-21 via RDP reconnect with client scaling raised to 150%
(probe confirmed session DPI 144): developer confirms icons and
expander glyphs look much better; row spacing good; font size correct
(same physical size as the pre-flip stretched rendering, now crisp;
TextZoom remains available as a preference). Tree slice fully
verified at 125% and 150%. Note: system-DPI-aware apps
pick up session DPI at launch; after an RDP reconnect with different
client scaling, previously launched instances are bitmap-stretched
until restarted (the PMv2 gap).
Not in this slice (still in package): PopupPickList, ImageListBox,
StatementCompletion sizes, FilesTree edit-box (incl. the transposed
MeasureText args), NodeTip metrics, EnsureWidthCustom DPI cache key
(safe while system DPI cannot change mid-session).

## Toolbar glyphs + two framework gotchas (2026-08-21)

Added `DpiUtil.ScaleToolStripImages` (ImageScalingSize + bicubic
pre-scale, per-item ImageTransparentColor applied before resampling)
and called it for `mainToolStrip` in the SkylineWindow ctor. Developer
confirmed the toolbar at 150%.

Debugging it surfaced two framework gotchas that reshaped DpiUtil:

1. **`Control.DeviceDpi` is ALWAYS 96 on .NET Framework 4.7.2 in
   system-DPI-aware mode** - before AND after handle creation (it is
   only maintained under per-monitor-V2). Proven with a file-log diag:
   ctor DeviceDpi=96, OnHandleCreated DeviceDpi=96 at session DPI 144.
   Consequence: `GetFactor` now reads the screen DC once
   (`Graphics.FromHwnd(IntPtr.Zero).DpiX`) and caches it statically
   (system DPI is fixed per process; the property is on per-node paint
   paths). HONEST CORRECTION: the committed Start Page pilot
   (`cf3bdf6`) was inert - its factor always computed 1; the cached
   screen-DC rewrite is what actually activated DpiUtil scaling.
2. **`DrawImageUnscaled` honors DPI metadata**: bitmaps created inside
   a 144-DPI process carry 144-DPI tags and got re-inflated 1.5x at
   draw (24px icons drawn at 36px - developer-reported icon overlap on
   multi-icon rows). Fixed with explicit destination-rect `DrawImage`
   in `DrawNodeCustom` + `SetResolution(96,96)` on all pre-scaled
   bitmaps.

Verified at 150% with developer's real settings (TextZoom=1.5!):
rows 36px, font 29px, icons 24px = exactly the old bitmap-stretched
proportions, now crisp. Developer sign-off ("very good now").
Follow-up noted: FilesTree never applies TextZoom to its FONT (only
row height) - pre-existing inconsistency, left alone in this slice.

## DigitalRune refinement (2026-08-21)

Dissected a real .sky.view: the docked layout is stored as FRACTIONS
(DockLeftPortion/AutoHidePortion etc.) - inherently DPI-proof. The
pixel exposure is only `FloatingWindow Bounds="x, y, w, h"` (absolute
device px; the 600x440 sample matches FormGroup's px floor). DLL is
binary-only (Shared/Lib) so the fix is an XML transform around
SaveAsXml/LoadFromXml: normalize floating SIZES to 96-logical on save,
scale + clamp on-screen on load; legacy files are 96-logical by
definition; no DPI stamp needed (old readers unaffected). Revised
estimate: 1-2 days (down from +2-3), mostly compatibility matrix.

## Branch state

Pushed 2026-08-21: `cf3bdf6f9c` (flip + Start Page pilot) and
`259a9f3d70` (tree cluster). Draft PR #4602 opened as the team
progress venue - mark ready for review (triggers Copilot) when the
package set feels complete.

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
Build green. Dev machine runs 150% scaling (live GetDpiForSystem=144; the registry
AppliedDPI=120 is a stale pre-sign-in value - do not trust it), two
2560x1440 monitors - native scouting environment. First launch:
**Start Page renders crisp at 150%, layout intact.** Inventory of the
main window and key dialogs in progress.

### 2026-08-20 - First-pass inventory at 150% (UI driver sweep)

Process verified system-DPI-aware via GetProcessDpiAwareness (=1).
Everything inspected renders CRISP with intact layout at 150%:

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
onscreen (en) at 150% with the flipped manifest - the English
geometry pins hold because TestRunner stays DPI-unaware.

### 2026-08-20 - First real breakage: Start Page (developer report)

Developer-marked screenshot shows three Start Page issues at 150%:
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

Also developer-reported: **Targets/sequence tree crowded** at 150% -
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
