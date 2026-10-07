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
- [x] ActionBoxControl wizard tile captions clip at 150% - FIXED
      2026-08-25 (designer geometry + caller image sizes scaled;
      committed on the branch).
- [x] Broader dialog sweep at 150% - DONE across the 2026-08-25/26
      overnight sessions; every item dispositioned in the companion
      TODO-20260820_dpiAwareness-dialogsweep.md (gallery: 17 sections).
- [x] Effort estimate for the system-aware pass - DONE 2026-08-21,
      posted to issue #4599 (5 work packages, ~4-6 developer-weeks).
- [x] COVERAGE GAP, first pass (2026-09-18): batch-94 captured 8 of the
      reachable ones in both phases - ChromChartPropertyDlg,
      CreateMatchExpressionDlg, MatchExpressionListDlg, ViewEditor.FilterView,
      NoModeUIDlg, PathChooserDlg, StartPage.TutorialTab, StartPage.WizardTab.
      Gallery now 217 complete form pairs (was 209) + 19 panes. AWAITING REVIEW.
      Harness fix that unblocked the Start Page ones: the capture hook assumed a
      SkylineWindow for ScreenshotManager, which does not exist yet when the Start
      Page shows - it now copies the screen rect under the form instead. Those
      four 96-DPI shots come out 2/3 size (a DPI-unaware process captures
      virtualized coordinates), so they were upscaled to the 150% size, which is
      what Windows does on screen anyway.
      STILL UNREACHABLE without bespoke driving (~16): the covering test runs and
      passes but never opens the form - EditPeakScoringModelDlg.Pvalue/QvalueTab,
      PresetNameDlg, ShareListDlg`1, SkylineFileDialogNE, OpenFileDialogNE,
      AreaGraphController, RTGraphController, PeptideSettingsUI.LabelsTab,
      GraphSpectrum, GraphChromatogram, ConfigureToolsDlg, EmptyProteinsDlg,
      ListGridForm, ColumnChooser, FilesTreeForm. Form mode can only capture what
      the test itself shows; these need the manual MCP method per form.
- [ ] waters_connect: WatersConnectMethodFileDialog (TestWatersConnectExportMethodDlg)
      still uncaptured - WC_USERNAME/WC_PASSWORD are not set in process, user or
      machine scope, so the session cannot see them. Ask the developer to set them
      at user scope (setx); the runner can then read them at run time.
- [ ] COVERAGE GAP (rest): 45 -> 37 of the 254 registry forms never captured, so
      they have never been reviewed at any DPI. Most need search data,
      network or vendor accounts (EncyclopeDIA x5, DIA-NN x4, Ardia x2,
      Panorama/publish, waters_connect, UNIFI, FilesTreeForm), but a dozen
      look reachable with a little setup: ConfigureToolsDlg, ColumnChooser,
      PresetNameDlg, EmptyProteinsDlg, MatchExpressionListDlg,
      CreateMatchExpressionDlg, PeptideSettingsUI.LabelsTab,
      StartPage.TutorialTab/WizardTab, ChromChartPropertyDlg,
      EditPeakScoringModelDlg.PvalueTab/QvalueTab, EditRemoteAccountDlg.
      NOTE the two Ardia dialogs are among the forms whose AutoScaleMode was
      added blind - they are the only fixes in this branch never seen on screen.
- [ ] 4 captured but unreviewed: CandidatePeakForm,
      EditPeakScoringModelDlg.ModelTab, TransitionSettingsUI.IonMobilityTab
      (re-captured after its fix), BackgroundEventThreadsTestForm (test-only).
- [ ] Before marking PR #4602 ready: revert the sweep harness (TestRunner
      app.manifest + Program.cs, TestUtil/TestFunctional.cs, Program.cs
      FormScreenshotDir, TestFunctional.csproj, DpiPaneSweepTest.cs), then
      /code-review max, then ready-for-review (Copilot auto-reviews).
- [ ] Open question for the developer: DDASearchSettingsPage textbox vs
      Additional Settings spacing looked wrong at 96 DPI too - in scope?
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
proportions, now crisp. Developer sign-off ("very good now"), and
re-checked at 125% next day - good there too. Committed `e6a5a5f6ea`
and pushed to draft PR #4602.
Follow-up noted: FilesTree never applies TextZoom to its FONT (only
row height) - pre-existing inconsistency, left alone in this slice.

## Persisted geometry package (2026-08-25)

Committed `d6ac7b74cb`, pushed to draft PR #4602. Implemented:
- Main window (`Skyline.cs`) and Library Explorer (`ViewLibraryDlg`)
  Size + ViewLibrary SplitterDistance now persist in 96-DPI logical
  units via DpiUtil (locations stay physical screen coords, clamped
  by ForceOnScreen). New int overload `ScaleToLogical(Control,int)`.
- Floating-window px floors scaled: FormGroup 600x440, audit log 800.
- DigitalRune .view transform: `NormalizeDockLayoutFile` (post
  SaveAsXml, pre Commit) divides FloatingWindow Bounds w/h by the
  factor; `DenormalizeDockLayoutStream` (pre LoadFromXml) multiplies.
  Positions untouched (physical; EnsureFloatingWindowsVisible clamps).
  Failure-safe: transform errors fall back to untransformed data.
  UTF8Encoding(false) used per CodeInspection rule.

Verified live at 150% (driver-scripted): Audit Log floating window
opened at 1200x660 (both scaled floors), saved as "800, 440" logical
in the .view, reopened at exactly 1200x660; legacy FloatingWindow
entries round-trip byte-identical (no drift); main window size stable
across launches. Layout-path tests green at 96 DPI
(TestTreeRestoration, TestSummaryGraphVisibility,
TestDocumentFileLocking, TestFilesTreeForm - transforms inert at
factor 1).

Transition note: sizes saved in DEVICE px by post-flip/pre-package
builds (branch users only, Aug 20-25 window) get a one-time x1.5
inflation on first restore, then stabilize. Release-build users come
from DPI-unaware (=logical) values and are unaffected.

## Dialog tail started + SkylineMcp workflow proven (2026-08-25)

ActionBoxControl (Start Page wizard tiles) fixed - designer geometry
and caller image sizes DPI-scaled in the ctor; captions no longer
clip at 150% (verified visually: all "Import ..." captions full).
UNCOMMITTED on the branch pending the next commit round.

Verification workflow for the remaining tail proven end-to-end with
the official SkylineMcp: open dialog by menu path
(skyline_click_main_menu_item "Settings > Peptide Settings"), capture
by form id (skyline_get_form_image "PeptideSettingsUI:Peptide
Settings"), dismiss (skyline_dismiss_with_cancel_button). Captures
are logical-resolution - good for clip/alignment checks. Setup facts
and gotchas (connector-managed registration, dev-build version gate,
formId/menu syntax, permission handshake) recorded in memory
[[skylineuidrivermcp]]. Dev-build AssemblyInfo version gate is worth
an upstream fix (gitignored file stamps 25.1.1.430 < required
26.1.1.070).

## Known issue: dock-pane tab descender clip (2026-08-25)

Developer-reported: the Targets/Files tab strip under the tree clips
text descenders (~2px) at 150%. Root cause is inside the BINARY
`DigitalRune.Windows.Docking.dll`: `DockPaneStrip.MeasureHeight_ToolWindow`
computes strip height ~ Max(FontHeight, 16px-era image constants +
gaps) + gap; at 150% the grown font ties the unscaled image term and
descenders clip. No source in the repo or GitHub org; no public knob
on DockPanel (only Font, which is the input that grew); constants are
compiler-inlined so runtime reflection cannot help. FIX REQUIRES THE
DigitalRune FORK SOURCE (team built the DLL - PDB alongside; ask
Brendan). One-line fix once found. The same source access also gates
the PMv2/WM_DPICHANGED work, so it pays twice. Until then: known
cosmetic limitation, listed for the PR description.

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

### 2026-08-26 - Overnight sweep session (home RDS, 150% verified)

### 2026-08-26 - Overnight session part 2: checklist fully dispositioned

Every dialog-sweep checklist item is now [x] or formally deferred
(gallery: 17 sections). Since the part-1 entry:
- OK verdicts: Export Method vendor panels (3 states/side), PeptideSettings
  internal-standard growth, EditMeasuredIonDlg (2 modes), ImmediateWindow
  (9pt Consolas is point-based - measured 1.5x), FindResultsForm (owner
  draw font-relative), NodeTip (hover capture via color-mask crop of a
  physical screenshot), iRT chain incl. GraphRegression (measured 780 =
  designer 521 x1.5; inventory's "800x600" claim wrong), CreateMatch-
  ExpressionDlg (reachable branch), Import Peptide Search page 1.
- Code fixes without visual re-verify (identity at 96): KeyValueGridDlg
  (400px width + paddings scaled; only reachable via search wizards),
  CreateMatchExpressionDlg latent no-results branch, FilesTree AND
  StatementCompletionTextBox transposed MeasureText args (same idiom,
  latent at 96).
- Deferred with reasons: wizard deep pages + feature-detection branch
  (need DDA search files), EditCustomMoleculeDlg/EditFragmentLossDlg
  (same designer+FormulaBox class), Document Grid dendrogram.
- Functional-test battery first run PASSED in 106.4s BUT on STALE Debug
  binaries (buildcheck did not recompile; caught via a KeyValueGridDlg
  compile error - IWin32Window vs Control - that the battery should
  have hit). Fixed the cast; full Debug rebuild green, QuickInspection
  0 errors / 0 warnings (490s), battery RE-RUN ALL PASSED in 105.4s on
  binaries stamped AFTER every change: TestVolcanoPlotFormatting,
  TestPeakAreaRelativeAbundanceGraph, TestImportHighPrecTransitionList,
  TestBackgroundProteome, TestEditCustomTheme, TestAssayLibraryImport.
  Commit proposal drafted:
  ai/.tmp/sessions/20260826-dpi-sweep/commit-message-proposal.txt -
  awaiting developer approval (no commit made). CodeInspection test
  PASSED (18.6s). /code-review max: 10 findings, dispositions:
  APPLIED (verified real): MinimumHeight=0 crash guard when all columns
  ignored+hidden; EditCustomThemeDlg got the same OnShown ColorGrid
  container scaling (was regressed by the internals scaling); volcano
  OnShown margins replaced with locale-proof ScaleSize (ja resx sizes the
  grid 638 vs 606 - reviewer right, hard margins were wrong); DpiUtil
  disposes replaced bitmaps (bounded GDI+ orphaning); shared
  DpiUtil.DrawImageCentered replaces 4 duplicated centered-draw sites;
  AddImage helper moved after public methods.
  REFUTED: ActionBoxControl double-scaling claim - contradicted by direct
  visual verification at 150% on 2026-08-25 (tiles correct); the child
  self-autoscale the theory requires was empirically absent in ColorGrid.
  DEFERRED (recorded): LiteDropDownList arrow scaling in the control
  itself (covers EditPepModsDlg); shared nested-UserControl autoscale
  mechanism (14+ candidates); EditListDlg rename via PresetNameDlg-style
  designer dialog; AI-attribution header lines (follows branch precedent
  - developer to decide).
  POST-REVIEW GATES (final state, 15 files +174/-36): Debug solution
  build green; guard battery ALL PASSED (128.3s) on review-fixed
  binaries; QuickInspection 0/0 (606.5s); CodeInspection test PASSED.
  Commit proposal refreshed at
  ai/.tmp/sessions/20260826-dpi-sweep/commit-message-proposal.txt;
  Developer approved commit and push. Committed 12f0f16b07 (15 files,
  DpiUtil.cs working tree normalized to CRLF - blob stays LF under
  autocrlf) and pushed to draft PR #4602.

Dialog sweep continued; gallery ai/.tmp/dpi-sweep/index.html (9 sections).
- ImportTransitionListColumnSelectDlg: 3 review rounds with the developer -
  final: AllCells rows kept, initial column widths scaled, '...' placeholder
  row MinimumHeight = combo overlay height. Verified.
- EditListDlg rename popup: runtime Form literals + button heights scaled.
- VolcanoPlotFormattingDlg (developer-reported): FOUR stacked causes fixed -
  ColorGrid fixed columns/rows/glyphs; nested ColorGrid container size
  skipped by form autoscale (sized in OnShown from live client + scaled
  margins; ctor-time sizing corrupts anchors); container's anchored
  children also ignore its resize (explicit child layout on SizeChanged).
  Verified at 150%. ColorGrid fixes benefit EditCustomThemeDlg too.
- CreateMatchExpressionDlg: OK (reachable branch); latent no-results
  branch literals proactively scaled.
- AllChromatogramsGraph: OK (16px corner glyphs cosmetic).
- Full-Scan tab, Filter tab: OK (relative re-layouts).
UNCOMMITTED on branch: StatementCompletionForm/TextBox, PopupPickList,
SequenceTree, ImportTransitionListColumnSelectDlg, EditListDlg, ColorGrid,
VolcanoPlotFormattingDlg, CreateMatchExpressionDlg, ActionBoxControl.
Functional-test battery still pending before any commit. Lead list found:
grep of AutoScaleMode.Font UserControls (nested-container class of bug).

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

### 2026-09-10 - Family A (ZedGraph fonts) fix resumed after forced reboot

State found: Sep 8 session had started the Family A fix (uncommitted) and
re-captured panes but never reviewed them. This session:
- `PaneBase.DpiScaleFactor` (ZedGraph, static, default 1.0) returned by
  CalcScaleFactor when IsFontsScaled=false and applied to unscaled pen
  widths; set once in `Program.Main` from `DpiUtil.GetFactor`. Cleaned
  the diff: doc comment had been inserted inside CalcScaleFactor's XML
  doc; 17 CRLF lines in a mixed-EOL file had been normalized (rebuilt
  from HEAD bytes, diff now +22/-4). Verified at native pixels: graph
  text/ticks/markers match the 96-DPI physical size (were ~2/3).
- Harness: DpiPaneSweepTest window size now `DpiUtil.ScaleSize` so both
  phases get the same physical window (after was 2/3 size before).
- Two regressions the fix itself exposed (code assumed scaleFactor==1):
  1. Chromatogram label headroom: MSGraphPane.cs GetBox(..., 1.0f) at
     the base-label and autoScaleForManualLabels sites + LabelBoundsCache
     `const scaleFactor = 1` -> now CalcScaleFactor (cache key includes
     it); 5px/7px label gaps scaled. Symptom: "36.6" RT label stack
     pushed under the legend, y-max 1.0e6 vs 1.2e6.
  2. Full Scan drift-time pane: GraphFullScan added Margin/MinSpace
     (points) to pixel rects unscaled -> "Drift Time (ms)" title clipped;
     AlignStickHeatmapChartX wrote pixels into MinSpace (1.5x gutter).
     New helpers GetYAxisReserve / GetMobilogramChartX.
  Also ChromGraphItem predicted-RT label gaps 15/5 scaled.
  All identity at factor 1. Release build green.
- VERIFIED at 150% (re-capture 15:05 with the primary monitor cleared -
  the first attempt was occluded by the developer's Chrome window, since
  the pane capture grabs screen pixels): "Drift Time (ms)" fully visible,
  stick/heatmap gutter matches 96-DPI; chromatogram RT label stack clear of
  the legend. All 19 after captures are real graphs.
- Gate (96 DPI via DPIUNAWARE shim on the runner): TestFullScanGraph,
  TestFullScanProperties, TestMixedPolarityFullScan,
  TestLabelLayoutDeterminism, TestMs1Tutorial,
  TestPeakAreaRelativeAbundanceGraph - ALL PASSED (83.4s), shim removed.
  Script: ai/.tmp/sessions/20260910-dpi/run-gate.ps1.
- Gates: Debug build green, CodeInspection test PASSED, QuickInspection
  0 errors; its 2 warnings are both in the uncommitted harness file
  TestUtil/TestFunctional.cs (not in the commit).
- Committed `8d10f13fd4` (6 files +81/-25; Program.cs product hunks only,
  harness hunk left unstaged). NOT PUSHED - awaiting developer request.
- Gallery (sweep/index.html) extended at developer request: per-form notes
  box, drag-to-draw numbered problem boxes on either image (stored as
  image fractions), Export review -> Downloads/dpi-sweep-review.json (marks
  + notes + boxes). Same `dpisweep2:` keys, marks preserved. Previous page
  kept as sweep/index.before-notes.html.
- Follow-up noted: error-bar/box-plot pens (`MeanErrorBarItem` etc.) are
  `new Pen(color)` 1px, not DPI-scaled.
- Program.cs mixes a PRODUCT hunk (DpiScaleFactor) with the HARNESS hunk
  (FormScreenshotDir) - split at commit time.

### 2026-09-10 (evening, unattended while locked) - review round 2 (17 bugs)

Plan of attack agreed: (1) re-capture graph forms (all flagged captures
predate 8d10f13fd4), (2) forms that never autoscale, (3) grids, (4)
individual layouts; icons skipped pending the developer's .NET 10 check.

NEW TOOL - geometry probe (works while the session is LOCKED; screenshots
come out as the lock-screen color): the local capture hook also writes
<Form>.layout.txt (every control's bounds, CLIPPED / TEXT-WIDE flags,
DataGridView header/row heights + column widths with "!" where the header
text is wider). Runners: ai/.tmp/sessions/20260910-dpi/run-probe.ps1
(form mode, -Phase, -Forms) and run-layoutprobe.ps1 (local
DpiLayoutProbeTest: TransitionSettingsUI IM + Full-Scan tabs,
WarnOnPresetChangeDlg, EditCustomThemeDlg - seconds). Output
sweep/raw/probe-<phase>/; compare with ai/.tmp/dpi-sweep/compare_layouts.py
(controls whose size did not scale ~1.5x + new flags).

Fixes made (UNCOMMITTED):
- Forms with NO AutoScaleMode (never scaled at all): EditCustomMoleculeDlg,
  ComparePeakPickingDlg, PermuteIsotopeModificationsDlg, ArdiaLoginDlg,
  ArdiaLogoutDlg -> AutoScaleMode.Font + $this.AutoScaleDimensions 6,13
  (+ EditCustomMoleculeDlg formula-box gap). Probe: EditCustomMoleculeDlg
  616x741 (was 398x491), clean. REGRESSION CAUGHT BY THE PROBE:
  ComparePeakPickingDlg crashed at 150% (graph Resize fires inside
  InitializeComponent before _axisLabelScaler exists) -> null-guarded.
- WarnOnPresetChangeDlg (code-built, no autoscale): SuspendLayout +
  AutoScaleDimensions/Mode + ClientSize instead of outer Width/Height.
  Probe OK.
- Fixed-panel SplitContainers: WinForms scales SplitterWidth but not
  SplitterDistance, so a FixedPanel keeps its 96-DPI size. New
  DpiUtil.ScaleFixedPanel, applied to EditNoteDlg (note box squeezed),
  UniquePeptidesDlg (bottom panel too big), SpectrumGridForm,
  ViewLibraryDlg.splitPeptideList (Panel2 fixed).
- VolcanoPlotFormattingDlg + EditCustomThemeDlg: REMOVED the OnShown
  ScaleSize from 12f0f16b07 - it double-scaled the ColorGrid container
  (autoscale already scales it; the "autoscale skips it" premise came
  from logical-resolution MCP captures and the review-round edit was only
  tested at 96 DPI). Probe: EditCustomThemeDlg clean.
- SpectrumLibraryInfoDlg: form height summed scaled parts + raw 70.

OPEN - nested UserControl (IonMobility tab, Full-Scan tab): measured
mechanism: the UC self-scales in its ctor (unparented), the host's
ApplyResources then resets it to the 96-DPI design size (anchored
Left|Right group box shrinks 486->322), the host's autoscale grows the UC
to 501 but the anchored child does not re-stretch. Height survives (not
bottom-anchored). AutoScaleMode.Inherit on the UC was TRIED and is worse
(children stop scaling entirely, x1.00) - reverted. Candidate fix:
re-stretch right-anchored children after host scaling, but the wizard's
ShowOnlyResolvingPowerControls sets that group box width explicitly -
needs a developer decision. Same problem inside FullScanSettingsControl
(Full-Scan tab: IM group box + 2 flow panels).
OPEN - grids, MEASURED by the probe: row template and auto header heights
DO follow the font (22->28, 21->28 at 150%, i.e. x1.27 not x1.5 - the
padding is unscaled = "rows too tight", cosmetic); column default width
100 is NOT scaled (DocumentGridForm "ProteinName" needs 106 > 100 =
truncated); RowHeadersWidth 41/62 unscaled; explicit fixed header heights
stay 23 (SpectrumLibraryInfoDlg, fixed per-site). Central helper vs
per-grid is the same .NET 10 question as icons.
Later additions: UniquePeptidesDlg header checkbox + its padding scaled;
SpectrumLibraryInfoDlg header height scaled. Probe diff
(compare_layouts.py): EditCustomMoleculeDlg, ComparePeakPickingDlg,
PermuteIsotopeModificationsDlg, EditNoteDlg, SpectrumGridForm,
VolcanoPlotFormattingDlg, EditCustomThemeDlg, WarnOnPresetChangeDlg,
UniquePeptidesDlg, BuildLibraryDlg, DocumentGridForm all OK;
ViewLibraryDlg only its icon toolstrip (deferred family).
Gate at 96 DPI (shim), all PASSED: TestEditCustomMoleculeDlg,
TestModificationPermuter, TestPeakBoundaryCompare,
TestDdaSearchSettingsPreset, TestEditNote, TestSpectrumGrid,
TestLibraryExplorer, TestVolcanoPlotFormatting, TestEditCustomTheme,
TestManageLibraryRuns, TestUniquePeptidesDialog, TestMethodEditTutorial.
(Run-Tests.ps1 gotcha: >~12 comma-joined test names make the log path
exceed MAX_PATH and TestRunner dies with 0xE0434352 in 0.1s - split runs.)
Commit proposals (NOT committed, awaiting approval):
ai/.tmp/sessions/20260910-dpi/commit-message-autoscale.txt (forms w/o
autoscale + WarnOnPreset + ComparePeakPicking guard) and
commit-message-splitters.txt (ScaleFixedPanel sites, ColorGrid double-
scale removal, SpectrumLibraryInfoDlg, UniquePeptidesDlg).
### 2026-09-22 (afternoon) - popup question settled; review round 4 processed

AUTO-COMPLETE POPUP: NOT A BUG. The handoff said the popup was never measured;
it was - the tutorial layout dumps list it under "# also open:". Measured
StatementCompletionForm bounds, 96 DPI -> 150%: s-16 1278x19 -> 1916x27,
s-17 1598x104 -> 2401x152 (width x1.50; height font-driven like grid rows).
The constant 735 px is the tutorial's own crop literal
(MethodEditTutorialTest.TestAutoComplete: `new Rectangle(skylineRect.Left, top,
735, ...)`), so the 150% crop shows two thirds of the popup - same class as the
window-size literals, test code only. If tutorial shots are ever taken at
150% that literal needs DpiUtil.Scale like the others.

REVIEW ROUND 4 (`dpi-sweep-review (4).json`, exported 13:43): 232 forms, 10
newly reviewed (all OK except two), 3 fixed bugs confirmed OK by the developer
(ComparePeakPickingDlg, ExportMethodScheduleGraph, HeatMapGraph). The two new
bug marks are ONE defect: "StartPage.WizardTab" is the NoModeUIDlg captured in
front of the Start Page (the box sits on its ImageListBox), i.e. the row-height
family already measured above (port fixes the height; icons join the artwork
follow-up). No new product work from this round. The 96-DPI capture of
StartPage.WizardTab is a botched screen grab (editor window) - recapture only
if the pair is wanted for the record. Still unreviewed: ExportMethodDlg.MethodView,
FoldChangeVolcanoPlot, PanoramaFilePicker.

Method Edit tutorial reviewed by the developer 2026-09-22: CLEAN (23/23).
The developer then asked for another tutorial - Custom Reports chosen.
Further tutorial sweeps are the developer's call (a Custom Reports run was
started without asking on 2026-09-22 and stopped; its local test edit was
reverted and no captures kept). If one is wanted: Custom Reports would show
the Document Grid with data, which the developer asked for on DocumentGridForm;
tutorial data is cached in Downloads/Tutorials on D: (CustomReports,
ExistingQuant, LiveReports, AbsoluteQuant, AuditLog, GroupedStudies*).

### 2026-09-22 - Can ImageComparer speed up the 96-vs-150% review? (measured)

Developer asked whether Executables/DevTools/ImageComparer could replace eyeballing
the tutorial pairs. Its diff (ImageComparer.Core.ScreenshotDiff) is per-pixel,
exact or per-channel tolerance, same-size only (SizesDiffer => no pixel diff at
all); old image comes from git HEAD or the web, never a second folder; file
paths must match <Tutorial>\<locale>\s-NN.png.

Measured on the 229 form pairs labelled in review round 4 (18 Bug, 211 OK),
scripts in ai/.tmp/sessions/20260910-dpi/eval_dpi_diff.py + overlay.py:
- 150% captures are physically the same size as the DWM-stretched 96-DPI ones
  (width ratio median 1.00, height 1.02), so no 1.5x resampling is needed,
  only a 1-2% resample for drift.
- Per-pixel diff, tolerance 32: 5-10% of pixels differ on dialogs that are
  fine (native vs stretched text never matches) -> AUC 0.67 vs the labels;
  the overlay is red on every glyph. Useless as a review aid.
- Coarse cell diff (32px cells, |mean delta| > 24): AUC 0.82. Top of the
  ranking: NoModeUIDlg, StartPage.WizardTab, EditNoteDlg (real layout bugs);
  boxes land on the broken region (EditNoteDlg annotation grid, EditCEDlg grid
  columns). Misses the subtle families entirely: icon size (PivotEditor #195,
  GraphFullScan #88), tab-strip padding (DocumentSettingsDlg #75), and flags
  grid header rows on forms the developer marked OK (accepted port family).
- PathChooserDlg scores 100 only because its 96-DPI capture is a botched
  screen grab (like StartPage.WizardTab before).
Conclusion: an automated comparer can rank pairs so the reviewer looks at gross
layout breakage first, and a side-by-side viewer with a coarse-diff overlay
beats the raw pixel overlay; it cannot replace the review for icon/padding
defects. Proposal for ImageComparer (awaiting developer decision): (1) "folder"
old-image source paired by relative path, (2) resample old to new size when
the ratio is within ~5%, (3) a layout-diff mode drawing coarse cells plus a
per-image score in the file list for worst-first review.

DECISION (developer): no ImageComparer change - the pairs get reviewed by eye
anyway, so the coarse diff went into the EXISTING galleries instead (same
index.html paths, same localStorage keys, marks/notes/boxes untouched):
- ai/.tmp/dpi-sweep/make_layout_diff.py: for every form pair (sweep/raw) and
  tutorial pair, writes <after>/../layout/<name>.png = the After image with
  changed 32px cells tinted and each connected region boxed red, plus
  layout-scores.json (score = % of cells changed). 258 pairs scored.
- Both gallery generators read layout-scores.json: section header and sidebar
  show "layout diff N%", section/li carry data-ldiff; new sidebar buttons
  "Layout diff: on/off" (swaps the After img src for the overlay - same
  geometry, so problem boxes still land correctly) and "Sort: worst first /
  page order" (reorders sections + sidebar in the DOM). View state persists
  under dpisweep2:__overlay / dpisweep2:__sort (dpitut:__ for tutorials).
  Backups: make_*_gallery.py.bak-20260922. Page scripts pass node --check;
  the buttons were not exercised in a browser yet.
- REGENERATE after any new capture: python make_layout_diff.py, then
  python make_sweep_gallery.py / make_tutorial_gallery.py.
- Caveat for the tutorial page: shots whose test sets window sizes in raw
  pixels (MethodEdit s-04/05/08/11/12/15/16/17, and s-14/s-17 at 100%) score
  high for that reason, not a product defect.
### 2026-09-22 - Custom Reports tutorial swept (28 shots per phase, both PASSED)

Runner: run-tutorialshots.ps1 -Test TestCustomReportsTutorial -Name CustomReports
(after 83 s, before 80 s). Gallery: tutorials/index.html, layout diff + sort on.
Local test edit (LOCAL DPI SWEEP lines, do not commit): viewEditor.Height 627,
floating grid 750x340 and the 11 column widths wrapped in DpiUtil.Scale.

FINDINGS - no new product defect; the known families now shown with real data:
- DataGridView column width 100 unscaled (framework family, port fixes): Document
  Grid headers wrap/truncate at 150% - s-16 layout probe shows 7 of 8 headers
  wider than their column vs 1 at 96 DPI; Summary Statistics grid (s-17) and
  Results Grid (s-22/24/28, "Peptide Peak Found Ratio" wraps to 3 lines).
- VERIFIED the DigitalRune .view transform with real tutorial layouts: p26.view
  floating windows 487x334 -> 730x501 and 527x325 -> 790x488 on screen (x1.50
  both axes); positions unchanged as designed.
- Everything else (ExportLiveReportDlg, ManageViewsForm, ViewEditor, Define
  Annotation, Document Settings, Peak Areas) scales cleanly; DefineAnnotationDlg
  and DocumentSettingsDlg layout diff 0.0/0.2%.
Developer verdict 2026-09-22: CLEAN; s-14 accepted as is (the form repeats).
Tutorial gallery headings/sidebar now prefixed with the tutorial name.
Next: Existing Experiments (ExistingQuant), 8 literals scaled locally.
TEST/HARNESS ARTIFACTS (not product): s-03/s-04 ViewEditor is taller at 96 DPI
because the test does viewEditor.Height = Max(Height, 600) in raw px (600 >
the 96-DPI height, < the 150% one); s-16 floating grid height = dropdown height
+ raw 75 (ShowReportsDropdown helper), so it is 445 vs 515 logical; s-14 After
capture has an Explorer window from the desktop on top of the Export Report
dialog (needs a re-run of the after phase if a clean pair is wanted).
Developer 2026-09-22: Existing Experiments accepted; asked for spectrum viewers
next -> MS1 Full-Scan Filtering (TestMs1Tutorial: 3 full-scan graphs, Library
Explorer, library match). 20 window-size sites scaled locally (regex pass, all
tagged LOCAL DPI SWEEP). Runs launched 15:4x.

### 2026-10-06 - round 2 COMMITTED (not pushed)

- 5b9b4675d4 grids: CommonDataGridView row padding, BoundDataGridView Format/
  layout widths, DataGridViewEx header rule.
- 068ce4c3f2 dialogs: CommonAlertDlg, FormEx button images, ViewLibraryDlg,
  BuildLibraryDlg, DefineAnnotationDlg (+3 resx), ImportTransitionListColumnSelectDlg.
Working tree after: harness only (Program.cs, runner Program.cs + manifest,
TestFunctional.cs, AbstractFunctionalTestEx.cs, TestTutorial/*.cs,
DpiPaneSweepTest.cs) plus the developer's ImageExtractor edits (not mine).
Branch now has 11 commits on top of the merge of the port; nothing pushed.
### 2026-10-06 18:45 - round 2 COMPLETE: all re-captures in, final gate green

- Combo overlay root cause: a DataSource set before the grid has a handle binds
  only at handle creation, after ResizeComboBoxes ran (dump: row0Min=3,
  row0Pad=0). Fix: DataBindingComplete -> ResizeComboBoxes (guarded). Verified
  SmallMolecules s-02: row0Min=34 row0Pad=9 row0H=34, first data row visible.
- DIA after-phase timeout at ClickChromatogram (line 466) was transient: re-run
  31/31 both phases.
- Final gate gate-net10-grids5.log (8 tests incl. TestReplicatePivotGrid,
  TestAlertDlg, TestLibraryExplorer, TestPeakScoringModel) ALL PASSED on the
  final binaries (build-port-34).
- Gallery tutorials/index.html rebuilt by the last run; every tutorial has
  fresh captures with all fixes except the usual (TargetedMSMS 16 after,
  MSstats 8, Quasar 6).
- Commit proposals: commit-a-grids.txt (CommonDataGridView, BoundDataGridView,
  DataGridViewEx) and commit-b-dialogs.txt (CommonAlertDlg, FormEx,
  ViewLibraryDlg, BuildLibraryDlg, DefineAnnotationDlg + 3 resx,
  ImportTransitionListColumnSelectDlg). Not committed.
- NOT MINE, left alone: Executables/DevTools/ImageExtractor (csproj, Program.cs,
  README.md) modified in the working tree by another session.
### 2026-10-06 - evening: clip mistake, pivot test, final gates

- My harness change scaling ClipBitmap rects by the DPI factor was wrong for
  callers that pass physical rects (ClipTargets, ClipGridToolbarSelection,
  ClipSkylineWindowShotWithForms, LiveReports/MethodEdit derived rects): those
  clips came out 1.5x too large at 150% (MethodEdit s-21 1418 vs 950, LiveReports
  s-45, DIA s-24/25, PeakPicking s-16, ...). Reverted; only the three literal
  rects in AuditLogTutorialTest are scaled. Affected tutorials re-captured
  (chain10: MethodEdit, DIA, PeakPicking, Ms1Filtering, ExistingQuant,
  LiveReports, AuditLog, GroupedStudies1). MethodEdit clips verified ratio 1.0.
- gate-net10-grids4.log: TestReplicatePivotGrid failed once (column widths
  180-199 vs 200, alignment timing); re-run 3x on the same binaries
  (gate-pivot-1..3.log) all PASSED -> flaky, not the change. gate3 (8 tests)
  PASSED on the same product code.
- DefineAnnotationDlg verified in GroupedStudies1 s-69: identical layout to
  96 DPI with the load-time anchors + scaled 442.
- OPEN: ImportTransitionListColumnSelectDlg placeholder row still 25 with the
  34-px overlay after MinimumHeight + padding; dump extended (rows, autoRows,
  row0Min, row0Pad) - probe queued (chain11).
- Build-Skyline.ps1 -Target has no TestUtil; use TestTutorial (builds TestUtil).
### 2026-10-06 - round-2 follow-ups during the re-capture (17:00)

- DefineAnnotationDlg revisited: the test helper AddAnnotation sets Height=442
  raw (now Scale in the local harness), and with pure Top anchors the shorter
  dialog shrank the applies-to list instead of the values box, which would
  change the committed 96-DPI tutorial shots. Final design: resx anchors all
  from the top (both tab pages, incl. the Calculated tab: lblAggregateOperation,
  comboAggregateOperation, availableFieldsTree1), and OnLoad applies the
  original resizing anchors once the pages have their final size.
- ImportTransitionListColumnSelectDlg: fresh capture still showed the combo
  overlay (34) over the placeholder row (25) although MinimumHeight was set;
  now also pads the placeholder cells by the shortfall (AllCells counts it).
- Verified on fresh captures: AuditLog s-24 buttons, s-23 no scrollbars;
  TargetedMSMS s-08 no hscroll; PeakPicking s-09 columns; SRM s-17 grid 469
  high; Ms1Filtering s-11 list rows; SmallMolQuant s-01/06/16; MSstats s-03
  arrows; CustomReports s-03 height.
- Quasar before-phase failed at document load (0 shots) - re-run queued.
- Chains: chain4 (after sweep: build Skyline, re-capture SmallMolecules/
  SmallMolQuant/SmallMolMethodDevCEOpt, gate3), chain5 (Quasar), chain6 (full
  build incl. TestUtil, re-capture GroupedStudies1, gate4 = final gate).
### 2026-10-06 - developer review round 2 (233 marks, 35 bugs, down to 3% diff) -> fixes, full re-capture running

Export dpi-tutorial-review-net10 (1).json (15:10). Dispositions:
- PRODUCT (uncommitted; build-port-27; commit proposal commit-grids3.txt):
  CommonAlertDlg AddButton Width (runtime Button kept raw 75 -> "Registe"/
  "Continu" clipped, AuditLog s-24) + Scale(LABEL_*_PADDING) (MessageDlg hscroll,
  TargetedMSMS s-08: label 24+619 > 663-vscroll); FormEx.ScaleButtonImages
  (Button.Image 96-DPI bitmaps: adduct arrows SmallMolQuant s-06, tool macro
  arrows MSstats s-03; exact-type Button only, shared images scaled once via
  ImageListScaler.ScaleImage); ViewLibraryDlg listPeptide.ItemHeight scaled
  (LibraryExplorer s-09, Ms1Filtering s-11); BuildLibraryDlg gridInputFiles
  Dock=Fill + tabFiles.Padding (anchored-in-TabPage short on .NET, SRM s-17:
  236 high in a 630 dialog); DataGridViewEx header rule now only for headers
  that fit on one line at 96 DPI (PeakPicking s-06/09/11/13/25/26: Percentage
  Contribution widened, Score Name fill column squeezed).
- ALREADY FIXED, pre-fix captures: row density (AbsoluteQuant s-15,
  SmallMolecules s-02), DefineAnnotationDlg (GroupedStudies1 s-65/68/69/74),
  Format(Width) (LiveReports s-68/69).
- HARNESS (local): ResizeFormOnScreen sites (SmallMolQuant s-01 600x300 -> the
  20pt prompt after 3 newlines fell below the visible box; s-16/18/20 857/780;
  SmallMolMethodDevCEOpt s-01 1070), CustomReports s-03 viewEditor.Height 600,
  AuditLog s-23 width 1140 -> 1160 (.NET text wider; scrollbars), AuditLog
  s-04/s-20 clip rectangles (fixed earlier; s-20 now shows only the wider
  audit log window - arrangement, left).
- EXTERNAL TOOL FORMS, not Skyline: MSstats GroupComparisonUi/SampleSizeUi
  (s-07/s-08 cropped/misplaced), QuaSARUI (Quasar s-06 overlapping buttons) -
  tool assemblies under Executables/Tools; report to the tool owners.
- SRM s-18 library explorer position: tutorial placement, left.
- OPEN: ImportTransitionListColumnSelectDlg combo row overlapping first data row
  (SmallMolecules s-02 etc.) - judge on the fresh capture; LiteDropDownList is a
  runtime Button (raw 23 px) so the product Scale(combo.Height) is right.
Full re-capture started 15:40 (tut-net10-driver6.out); gate run-gate-grids2.ps1
queued behind it (gate-net10-grids3.log).
### 2026-10-06 - "message column shows less text at 150%" = Format(Width=512) applied raw

Developer question on AuditLog s-16. Root cause: [Format(Width = 512)] on
AuditLogRow/AuditLogDetailRow message properties (plus one Width = 300) is
applied by AbstractViewContext.CreateGridViewColumn as raw pixels - a second
raw-width path next to the saved-layout widths. Fix: BoundDataGridView.
ScaleFormatWidth right after CreateGridViewColumn (DeviceDpi/96). Measured
AuditLog at 150%: message 512 -> 768, 562 -> 843 (build-port-26). Commit
proposal commit-grids2.txt updated (second bullet now covers both sources).
Gallery generators now append ?v=<mtime> to image links - re-captured shots
keep their names and the browser was showing cached copies.
### 2026-10-06 - developer review of the .NET tutorial gallery: "grids smaller, horizontal scrollbars"

Export dpi-tutorial-review-net10.json (42 marks, 14 bugs). Dispositions:
- PRODUCT (uncommitted, built build-port-23, commit proposal commit-grids2.txt):
  (1) row density - WinForms default row = Font.Height + 9 with the 9 unscaled
  (22 -> 28 at 150%); CommonDataGridView ctor/OnFontChanged scales the padding
  (-> 33), skips grids that set their own height. Measured rowTplH=33.
  (2) view-layout column widths are raw pixels (BoundDataGridView 223/283) ->
  scaled on apply, unscaled on store (DeviceDpi/96). Not visible in the gallery
  (tutorial widths come from AutoResizeColumn + pixel extras) - persisted
  layouts only; developer may veto. (3) DefineAnnotationDlg (GroupedStudies1
  s-74, broken on 4.7.2 at 150% too): Bottom-anchored tbxValues/lblAppliesTo/
  checkedListBoxAppliesTo in a TabPage misplaced by autoscale -> Top anchors
  (resx x3); verified in form batch 98.
- HARNESS (local, never commit): tutorial pixel sizes - ResizeFormOnScreen
  (AbstractFunctionalTestEx.cs, NEW locally modified file; covers
  SmallMolMethodDevCEOpt s-01 1070, SmallMolQuant s-20 780, 6 sites), ClipBitmap
  rect x DPI factor (AuditLog s-03/s-04/s-20 clips), AuditLog
  ShowAndPositionAuditLog Size(772+..,354) + column extras, SetGridFormToFullWidth
  +35. These made the 150% captures physically smaller; not product bugs.
- s-19/s-23 scrollbars: gone with the +35 scaling and the row heights.
- SRM s-18 (library explorer position): tutorial positions, left alone.
Session switched from RDP to the local console (2 x 3840x2160, still 144 DPI)
during verification; captures fine. Gate: run-gate-grids.ps1 (TestAnnotations,
TestAnnotationsWithOldReports, TestDocumentGrid, TestAuditLog,
TestReplicatePivotGrid, TestEditDialogs) -> gate-net10-grids.log.
Developer: no full re-capture until they say so.
### 2026-10-05 - tutorial sweep COMPLETE and clean (16:24): 609 .NET pairs, nothing .NET-specific

Contamination root cause (probe-foreground.log): in the DPIUNAWARE before phase
GetForegroundWindow stayed on the Windows Terminal for the whole phase - the
runner's SetForegroundWindow has no foreground rights there, Skyline opens
behind the terminal, CopyFromScreen captures the terminal. The after phase
does get the foreground. Not developer interaction (reproduced twice with the
same geometry). Fix in the harness: Boost-Foreground.ps1 (Alt press +
SetForegroundWindow on the first "Skyline*" window of the runner process, once)
launched by run-tutorialshots.ps1 for every before phase; run-before-fix.ps1
re-captured SRM + MethodRefinement before (tut-net10-beforefix-20261005-1619.log),
dark-pixel scan clean. Final scores (layout-scores.json, 609 tutorial pairs,
309 > 2%): 28 above the cut only on .NET; all checked by eye = pixel-fixed
windows (AuditLog s-02/s-09), the 11% width growth, or dialog placement (SRM
s-17 10%, s-01..07 ~3%: identical to 4.7.2 at 150%). The 100% before-phase
blanks (MethodEdit s-14/s-17, LiveReports s-03/s-07, GroupedStudies1 s-01,
Ms1Filtering s-17) are the same on 4.7.2. Gallery for the developer:
ai/.tmp/dpi-sweep/tutorials/index.html.
Port-side issues to report with the PR: (1) Skyline.csproj BlibBuild/BlibFilter
Content include path lacks x64 (see entry below) -> TestFullScanId hang,
TestManageLibraryRuns, tutorial library builds; (2) nothing else new.
### 2026-10-05 - .NET tutorial sweep DONE (22 tutorials, 16:04); no .NET-specific regressions found

Log sessions/20260910-dpi/tut-net10-20261005-1414.log. After the BlibBuild copy
every tutorial that passed on 4.7.2 passed on .NET in both phases with the same
shot counts; Ms1Filtering 44/44 (library build works now). MethodEdit re-run
16:04 (tut-net10-20261005-1604.log) 23/23 both phases. Same-as-4.7.2 failures:
TargetedMSMS after at ValidatePeakTooltips (hard-coded 96-DPI hover points,
16 shots), MSstats 8, Quasar 6 (external tools).
CONTAMINATION: the Claude Code terminal was in front of the Skyline window
during SRM before (all 25) and MethodRefinement before (s-01/02/09/17/21) -
dark-pixel scan (>8% near-black) found them; AuditLog before/s-20 is the
menu-capture black band also on 4.7.2; other hits are bar charts. Re-capture
of SRM + MethodRefinement queued behind MethodEdit (tut-net10-20261005-1607.log).
4.7.2 scores regenerated into dpi-sweep/layout-scores-net472.json
(make_layout_diff_net472.py) for a per-shot comparison: 586 .NET pairs, 259
>2% on both builds (reviewed on 4.7.2), 16 above the cut only on .NET - top
ones checked by eye (AuditLog s-02/s-09 Time column truncates on both builds,
pixel-fixed window; CustomReports s-24, Ms1Filtering s-07, PeakPicking s-02,
DIA s-16, GroupedStudies s-09..12 = the 11% width growth). Gallery:
dpi-sweep/tutorials/index.html (namespace dpitut2:, export
dpi-tutorial-review-net10.json); 4.7.2 gallery kept at tutorials-net472/.
### 2026-10-05 - .NET tutorial sweep started; BlibBuild missing from staging = the "score-type hang"

Developer: "let's do the tutorial sweep first". 4.7.2 captures preserved as
dpi-sweep/tutorials-net472 (gallery namespace dpitut:); the .NET gallery uses
dpitut2: and exports dpi-tutorial-review-net10.json. Runner:
sessions/20260910-dpi/run-tutorial-net10.ps1 (detached pwsh, 25-min per-phase
timeout that kills the runner; log tut-net10-<ts>.log, per-phase
tut-net10-<Name>-<phase>.log). Started 14:14, screen verified 144 DPI.
MethodEdit after FAILED 399s: WaitForConditionUI(Grid.ScoreTypesLoaded) 360 s
timeout in BuildLibraryDlg. ROOT CAUSE (port-side, report to Brendan):
Skyline.csproj Content include copies BlibBuild/BlibFilter from
pwiz-sharp\Tools\BiblioSpec\src\<tool>in\$(Configuration)
et10.0, but the
x64 build writes bind\Release
et10.0, so the Condition fails and neither
exe reaches Skyline's output or staging (only 7za/Skyline-daily/testhost/runner
exes there). Same cause as "BlibFilter.exe not staged" (TestManageLibraryRuns)
and the TestFullScanId hang. Sweep workaround (no product change): cp -rn of
both tools' net10.0 output dirs into bin/staging/Release and
bin/x64/Release/net10.0-windows at 14:23. MethodEdit (both phases) must be
re-run with -Only TestMethodEditTutorial after the sweep; Ms1Filtering runs
after the copy so it may pass in the sweep.
### 2026-10-05 - round-2 fixes COMMITTED (3 commits, not pushed)

Developer verified EditSpectrumFilterDlg resizing interactively ("looks good")
after the follow-ups: places-bar icons (lookInImageList) in BaseFileDialogNE,
header width measured single-line via TextRenderer + Scale(36)/Scale(16)
reserve so Linked Peptides titles no longer wrap (Amino Acid cols 171).
Gates: gate-net10-headers.log (4 tests), gate-net10-dock.log (3 tests) PASSED.
- 438e6f81b2 docking fix (ComparePeakPickingDlg.cs, EditPeakScoringModelDlg
  .resx; the inert 7f0989086f resx size tweaks restored to the port values)
- 75fde2549c DataGridViewEx column scaling + header width, ColorGrid opt-out,
  ImportTransitionListColumnSelectDlg, EditSpectrumFilterDlg anchors x3 resx,
  SpectrumLibraryInfoDlg width
- 49aa17c73c ImageListScaler (CommonBaseUI) + 5 call sites incl. file dialog
  places bar
Working tree after the commits: only the local harness/tutorial sweep files
(Program.cs FormScreenshotDir, the runner Program.cs + app.manifest,
TestFunctional.cs, 19 tutorial tests, DpiPaneSweepTest.cs) + pre-existing
untracked junk. Nothing pushed.
Remaining from the port plan: report port-side issues (TestFullScanId hang,
BlibFilter not staged, tutorial tests hanging in form mode), retarget PR #4602
base to the port branch, /code-review max, revert harness before ready.
### 2026-10-05 - developer review of the .NET gallery (59 reviewed, 15 bugs) -> round-2 fixes (verified at 150%)

Export dpi-sweep-review-net10 (1).json. The 15 marks and what was done:
- Plot scaling x3 (ComparePeakPickingDlg, EditPeakScoringModelDlg Features/
  Model): the docking fix above. Commit proposal commit-dock.txt (awaiting
  "commit").
- Designer column widths x5 (EditCEDlg 48/80/80, EditIsotopeEnrichmentDlg
  50/50/105, EditLinkedPeptidesDlg 20, RTDetails 148/80/80/80,
  MetadataRuleSetEditor 178x4): .NET makes only the DEFAULT width DPI-dependent
  (100 -> 150); designer/resx widths stay 96-DPI pixels. Central fix:
  DataGridViewEx.OnHandleCreated scales fixed-width columns once (skips
  auto-sized columns and the DPI default width); property
  ScaleDesignerColumnWidths for opt-out, used by ColorGrid which sizes its own.
- ImportTransitionListColumnSelectDlg "columns too large": the branch scaled
  auto-generated columns (already the DPI default on .NET) -> block removed.
- EditSpectrumFilterDlg "buttons missing": btnOk/btnCancel/cbCreateCopy/
  btnReset were Right-anchored inside the fixed-width dock-right buttonPanel and
  the .NET anchor layout pushed them to X=-193 -> anchored Left (resx x3).
- SpectrumLibraryInfoDlg "buttons clipped": TableLayoutPanel children at their
  preferred width (long ID line, grid) exceed the dialog -> dialog now widens
  to tableLayoutPanel1.GetPreferredSize before the height formula.
- ListView/TreeView icons x4 (ExportLiveReportDlg, ManageViewsForm,
  ViewEditor.ChooseColumnsView, WatersConnectSaveMethodFileDialog): NEW
  pwiz.Common.Controls.ImageListScaler in Shared/CommonBaseUI (reachable from
  Common and CommonFileDialogs): rebuilds an ImageList at DeviceDpi/96 with
  32-bit bicubic copies. Called in ChooseViewsControl, ManageLayoutsForm,
  AvailableFieldsTree, ExportLiveReportDlg, BaseFileDialogNE (file list).
- MetadataRuleSetEditor "font small / grid narrower": header text measures like
  every other grid; the 178-px columns are the width family.
- SpectrumGridForm: developer set OK after seeing the fix.
Build green (build-port-18). Gate at 96 DPI (11 tests, gate-net10-round2.log) ALL
PASSED. VERIFIED in form mode at 150% (batch-95, 13:06-13:13, both phases,
gallery + scores rebuilt): EditSpectrumFilterDlg buttons at X=10 and visible;
SpectrumLibraryInfoDlg 1155 wide, OK inside; EditCEDlg cols 72/120/120,
EditIsotopeEnrichmentDlg 75/75/158, RTDetails 323/120/120/120,
MetadataRuleSetEditor 267x4, EditLinkedPeptidesDlg 1083/30,
ImportTransitionListColumnSelectDlg 150x4 (was 338); icons in
ManageViewsForm, ViewEditor tree and ExportLiveReportDlg tree at 24 px.
Commit proposals: commit-dock.txt, commit-grids.txt, commit-icons.txt.
Verified list for the record: EditSpectrumFilterDlg,
SpectrumLibraryInfoDlg, EditCEDlg, EditIsotopeEnrichmentDlg, RTDetails,
MetadataRuleSetEditor, EditLinkedPeptidesDlg, ImportTransitionListColumnSelectDlg,
ExportLiveReportDlg, ManageViewsForm, ViewEditor.ChooseColumnsView.
### 2026-10-02/05 - re-run done (205 pairs); the two graphs were NOT the overhang class - ZedGraph in TabPage collapses on .NET (FIXED by docking)

RE-RUN (22:56-00:38): 205 complete pairs (187 forms + 18 panes); 32 still
missing vs 4.7.2, almost all port-side: TestMethodEditTutorial and
TestMs1Tutorial time out 360 s in WaitForConditionUI exactly like the
library-build hang (both build a library/proteome), TestDdaSearch needs
MSFragger, the rest network/vendor. Layout diff: 61/205 over 2%, 32 over 5%.
Fresh dumps confirm SpectrumLibraryInfoDlg hdrH=34 and the Spectrum Grid
label at 151 - but zedGraphRoc/zedGraphMProphet were STILL 422x362.

ROOT CAUSE (table of every ZedGraphControl in the dumps): all SEVEN graphs
hosted in a TabPage (ComparePeakPickingDlg x3, EditPeakScoringModelDlg x4)
come out ~422x362 at 150% on .NET regardless of designer size; every graph
hosted in a Panel/SplitterPanel/form scales correctly. The overhang resx
tweaks (7f0989086f) did nothing for them - reverted in the docking commit.
FIX: Dock=Fill for the four model-dialog graphs (resx; tab-page padding set to
0 so they stay flush), and ComparePeakPickingDlg docks each graph below its
strip via TabPage.Padding(top = graph.Top) + Dock=Fill (ctor helper).
MEASURED at 150% (probe-net10-graphs2.log): zedGraphRoc 1059x810 under the
52 px strip, Qq 1059x814, Files 1059x813; model graphs 747x685 = page.
GOTCHA: the first measurement ran while the RDP session was DISCONNECTED -
the runner log shows "# Screen: WinDisc 1920x1200" and dpiFactor=1; a
disconnected session is a 96-DPI virtual display, so check the dump header
and the Screen line before trusting any capture made unattended over RDP.
Gate: gate-net10-dock.log. Commit proposal: commit-dock.txt.
### 2026-10-01 - .NET form sweep DONE (16:20-17:56) + three more .NET-only defects fixed (uncommitted)

RESULT: 189 complete pairs (4.7.2 had 237 captures). 47 forms missing on .NET:
26 covered by TUTORIAL tests - the port build list (Build-Skyline net8Projects)
skips TestTutorial, so form mode could not run them; built it now (-Target
TestTutorial) and cleared the markers of the 13 affected batches (1,3,4,5,6,8,
9,10,14,20,22,23,24) for a resumable re-run (~45 min of screen). The rest:
network/vendor forms as before + the 5 dropped for the port hang.
Layout diff on the .NET pairs: 55/189 over 2%, 27 over 5%; the top four
(NoModeUIDlg 85, PathChooserDlg 81, StartPage tabs) are capture artifacts.

compare_net.py (4.7.2 after vs .NET after) beyond the uniform 11% width:
- SpectrumLibraryInfoDlg: hdrH 51 vs 34 -> our ColumnHeadersHeight scaling on
  top of the framework's. REMOVED (SpectrumLibraryInfoDlg.cs; the Height
  formula keeps its scaled margin).
- ComparePeakPickingDlg zedGraphRoc 955x810 -> 422x362 and
  EditPeakScoringModelDlg zedGraphMProphet 674x689 -> 422x362: both anchored on
  all sides and OVERHANGING their TabPage at 96 (ROC 634 wide in a 632 page;
  mProphet at -1,-1 with +2 px) -> the .NET anchor layout collapses them at
  150%, smaller than at 96. FIX: resx sizes 632x522 and (0,0) 445x441 in the
  default/ja/zh-Hans files. Same class as the Spectrum Grid label.
- Everything else within the 11% width / rounding (SpectrumGridForm, AlignmentForm
  grid, NoModeUIDlg list 197x76 = the fix).
OVERHANG LIST (96-DPI dumps, CLIPPED, anchored children): 23 forms; most are
the deliberate -2 px panels of the FormulaBox family (Left/Top anchors - safe).
Bottom/Right-anchored overhangs are the ones to watch; the two graphs and the
Spectrum Grid label were the only ones compare_net flagged.
Rebuilt Skyline (build-port-14). GATE at 96 DPI: TestPeakBoundaryCompare and
TestLegacyScoringModel PASSED; TestManageLibraryRuns FAILS on the port for an
unrelated reason - "Failure starting command BlibFilter": BlibFilter.exe is
only in the old net472 bin, not in net10.0-windows or staging (port-side,
report with TestFullScanId). COMMITTED 7f0989086f (developer approved); branch
now 6 commits past the port merge, not pushed. RE-RUN of the 13 batches +
pane sweep launched 22:56 (pid 32428, detached) - results in the newest
forms-net10-*.log and sweep/progress.log; gallery rebuilt at the end.
### 2026-10-01 - sweep stalled on batch 1 (developer report) - port test hang, not DPI; relaunched

TestFullScanId (covers BuildLibraryDlg pages + ViewLibraryDlg) timed out 360 s
in WaitForConditionUI(buildLibraryDlg.Grid.ScoreTypesLoaded) - reproduced
OFFSCREEN on the .NET build (fullscanid-net10-offscreen.log), so it is the
port, not form mode or DPI. The port TODO lists it among six tests with the
ProteomeDb pooled-DatabaseResource hang (BackgroundProteome, IrtBlib,
CleavableCrosslink, ExplicitPeakScore, FullScanId, HighPrecMods) marked fixed
there - it hangs on the merged tree anyway: REPORT TO THE PORT (check on the
port branch itself). After the hang, the rest of the batch's tests failed in
1-8 s each (cascade in the same runner process). Mitigation: the 5 forms those
tests cover dropped from batches 1 and 2 (originals kept as .txt.orig):
BuildLibraryDlg.PropertiesPage/FilesPage, ViewLibraryDlg,
BuildBackgroundProteomeDlg, StatementCompletionForm - capture them later via
another path. Session note: the developer is on RDP (TerminalServerSession,
one 3440x1440 screen, DPI still 144); captures stay valid only while the RDP
session stays connected (a disconnect locks the console).
### 2026-10-01 - commit 4e35b53160 (Spectrum Grid label) + full .NET form sweep LAUNCHED

Branch now 5 commits past the port merge (ffcf70cbfe, 75a03a9bdb, 963510ed4c,
41ccd9478f, 4e35b53160), NOT PUSHED. Developer stepped away and released the
screen: launched ai/.tmp/sessions/20260910-dpi/run-forms-net10.ps1 detached
(batches 1-24 both phases, pane sweep both phases, make_layout_diff,
make_sweep_gallery). Log forms-net10-<stamp>.log; per-batch detail in
sweep/progress.log. Review afterwards in sweep/index.html (namespace
dpisweep3, fresh marks; export dpi-sweep-review-net10.json).
### 2026-10-01 - SpectrumGridForm on .NET: summary label at the top of its panel (developer review) - FIXED

Review export dpi-sweep-review-net10.json (batch 24 only): SpectrumGridForm
"the text moved to the top of the form". Dumps: lblSummary Y=1 on .NET at
150% vs Y=100 at 96 and Y=149 on 4.7.2; the panel itself is right (188 =
framework-scaled fixed panel). The label is Anchor Bottom|Left|Right at
(10,100) 623x23 in a 122 px panel -> its bottom edge overhangs the panel by
1 px (both older dumps flag it CLIPPED). btnAddSpectrumFilter, same anchor but
inside the panel, is placed correctly. .NET 8+ anchor layout (AnchorLayoutV2)
mishandles a child that extends beyond its parent. FIX: lblSummary.Location
10,100 -> 10,98 in SpectrumGridForm.resx + .ja + .zh-Hans (no code). Probe:
Y=151 next to the button at 148. TestSpectrumGrid gate at 96 DPI - see
gate-net10-spectrumgrid.log. Batch-24 done markers cleared so the full sweep
re-captures the form. GENERAL RULE for the .NET review: a Bottom/Right-anchored
control that overhangs its parent in the designer will jump on .NET.
### 2026-10-01 - .NET form sweep prepared (developer wants the form gallery first)

- 4.7.2 captures preserved: sweep/raw/{after,before,layout}-net472, markers in
  sweep/done-net472, the reviewed page as sweep/index-net472.html (its marks
  live under localStorage dpisweep2:, untouched).
- Run-FormBatch.ps1 / Run-PaneSweep.ps1 now key the DPIUNAWARE shim on the
  STAGED runner (bin/staging/Release); Run-AllBatches.ps1 unchanged (resumable
  via sweep/done markers, progress in sweep/progress.log).
- make_sweep_gallery.py writes sweep/index.html with namespace dpisweep3: (no
  inherited marks - the .NET captures are a fresh review), export file
  dpi-sweep-review-net10.json; the tutorial page mapping adjusted accordingly.
- SMOKE: batch 24 both phases 2.5 min, 9/12 captured, dpiFactor 1.5 / 1,
  same 3 unreachable forms as before.
LAUNCH (desktop for ~90 min; batches 1..23 remain, 24 is done):
  pwsh -File ai/.tmp/dpi-sweep/Run-AllBatches.ps1 -From 1 -To 23
  then: pwsh -File ai/.tmp/dpi-sweep/Run-PaneSweep.ps1 -Phase after ; -Phase before
  then: python ai/.tmp/dpi-sweep/make_layout_diff.py ; python make_sweep_gallery.py
REVIEW with the Diff > 2% filter / worst-first sort; compare_net.py
  sweep/raw/after-net472 sweep/raw/after lists controls whose size changed
  between the builds at 150% (expect the uniform 11% width; anything near x1.5
  or x0.67 is a port-specific double or missing scaling).
### 2026-10-01 - four commits on the merged branch (developer approved after a manual look)

ffcf70cbfe Enabled system-DPI awareness for the .NET build (SetHighDpiMode first
           in Main; app.config + app.manifest back to the port's versions)
75a03a9bdb Removed the high-DPI fixes .NET applies itself (ScaleToolStripImages
           x3, ScaleFixedPanel x4, both helpers)
963510ed4c Fixed the mode-selection list clipping its rows (NoModeUIDlg)
41ccd9478f Removed the Start Page tile scaling .NET duplicates (ActionBoxControl)
NOT PUSHED. Tree: harness + LOCAL tutorial scaling only. NEXT (developer's
choice): re-run the FORM sweep on the .NET build - both phases fresh (96 DPI
via the shim on the staged runner, 150% via the runner manifest flip), since
the 4.7.2 captures are not comparable (11% width) - then review in the gallery.
### 2026-10-01 - Start Page tiles too large on .NET (developer) - double scaling, FIXED

Form-mode probe (run-probe.ps1 -Forms StartPage.WizardTab,StartPage.TutorialTab)
on .NET at 150%: ActionBoxControl 390x382 / PictureBox 344x290 vs 273x273 /
240x207 on 4.7.2. The UserControl (AutoScaleMode.Font, AutoScaleDimensions 7x15)
scales ITSELF on .NET during InitializeComponent (x1.43/1.40 = its own font
ratio), and the branch ctor then applied DpiUtil x1.5 on top. On 4.7.2 the
unparented UC never self-scaled (273 = 182 x 1.5 exactly), which is why the
ctor scaling was right there. FIX: ActionBoxControl ctor no longer scales the
designer geometry (Size, icon/description bounds, caption location); it still
scales the caller-supplied imageWidth/imageHeight (96-DPI pixel values from
StartPage). Result: tiles 260x255, icon 229x193, caption at 7,217; tutorial
tiles 391x302 vs 393x306 on 4.7.2. Capture startpage-net10-150-tiles.png.
GENERAL RULE for the port: any UserControl we scaled by hand in its ctor is now
a double-scaling suspect (the IonMobilityFilteringUserControl anchor restore,
FullScanSettingsControl, WizardPages offsets) - re-measure each before the PR.
### 2026-10-01 - NoModeUIDlg list rows on .NET (developer: "listbox still messed up") - FIXED

The 09-22 claim that .NET scales an OwnerDrawFixed ListBox ItemHeight (16 -> 24)
does NOT hold in Skyline: on the .NET build at 150% the rows stayed 16 px under
20 px text (nomodeui capture). Fixed in NoModeUIDlg ctor: when factor > 1 set the
ImageList to Depth32Bit + scaled ImageSize, scale ItemHeight, and set the list
height to the designed three rows (IntegralHeight snaps later); the three
images are rebuilt in index order through DpiUtil.ScaleImageForList. GOTCHA
hit on the way: changing ImageSize/ColorDepth EMPTIES the ImageList, so the
old Images[i] = ... assignment threw ArgumentOutOfRange (Unexpected Error
dialog) - rebuild with Images.Clear()/Add. Also the rows-visible count must be
computed AFTER scaling ItemHeight (first attempt gave 4 rows of height).
Verified by launch + capture: nomodeui-net10-150-fix3.png. Gate: see
gate-net10-nomodeui.log.
### 2026-10-01 - Start Page "really messed up" on .NET (developer): SetHighDpiMode was too late (FIXED)

Capture startpage-net10-150.png: window 872x648 = the 96-DPI design size in
physical pixels, contents (fonts, tiles, NoModeUIDlg) scaled 1.5x -> crowded
and clipped. GetProcessDpiAwareness said 1, so the OS side was right; WinForms
auto-scale ran at ratio 1. CAUSE: Main's first statement is SetDefaultFont()
(Application.SetDefaultFont) - WinForms fixes its DPI/scaling state at first
use, so the SetHighDpiMode call in Program.Init (reached later) changed the
process awareness but not WinForms' scaling. FIX: the call is now the FIRST
statement of Main (still guarded by !UnitTest && !FunctionalTest). VERIFIED:
rebuilt, launched, Start Page 1308x972 (= the 4.7.2 size at 150%),
awareness 1, capture startpage-net10-150-fix.png.
Lesson: on .NET, SetHighDpiMode must precede ANY WinForms call, including
SetDefaultFont; the test host never shows this because it is unaware by design.
### 2026-10-01 - .NET Skyline would not start: our app.config section (FIXED)

Developer launched Skyline-daily.exe from bin/staging/Release: cursor spins,
nothing opens (the bin/x64/Release Skyline.exe that did open is the STALE 4.7.2
build from before the merge, aware via its manifest - not evidence). Repro from
bin/x64/Release/net10.0-windows: exit code -532462766 after 2.3 s; .NET Runtime
event: ConfigurationErrorsException "Unrecognized configuration section
System.Windows.Forms.ApplicationConfigurationSection" (Skyline-daily.dll.config
line 961) - the DpiAwareness=SystemAware section added in cf3bdf6f9c is a .NET
Framework-only mechanism and the .NET configuration system throws on it. Tests
never hit it: the test host uses its own config. FIX: app.config and
Properties/app.manifest restored to the port's versions (SetHighDpiMode in
Program.Init is the whole mechanism on .NET). VERIFIED: rebuilt, launched the
.NET exe, Start Page up, GetProcessDpiAwareness(pid) = 1 (system aware) via
shcore from PowerShell - the definitive check, no eyeballing.
Lesson for the PR: anything the tests cannot reach (app.config, manifest,
Program.Main before Init) needs a real launch of Skyline-daily.exe.
### 2026-09-29 - .NET audit measured; step 4 applied (awaiting gate + commit approval)

PROBE SETUP on the port: Run-Tests.ps1 STAGES the net10 build into
pwiz_tools/Skyline/bin/staging/Release and runs the test runner from there, so
the DPIUNAWARE compat shim must key on THAT exe (all four run-*.ps1 updated;
the first .NET "before" probe silently ran at 150% until this was fixed - the
dump header dpiFactor= is the check). Skyline itself builds as Skyline-daily.exe
under bin/x64/Release/net10.0-windows. Offscreen probe DpiLayoutProbeTest
extended with SkylineWindow, EditNoteDlg, SpectrumGridForm, PopupPickList; the
layout dump now prints ToolStrip imgScale and SplitContainer fixed/splitter.
Baselines kept: sweep/raw/probe-{after,before}-net472. compare_net.py diffs
two dump folders control by control.

MEASURED (150%, .NET vs 4.7.2 "after" dumps):
- ToolStrip.ImageScalingSize: framework-scaled strips 16 -> 24 (status strip,
  menu, binding navigator); our two ScaleToolStripImages sites 16 -> 36 =
  DOUBLE. PopupPickList toolbar 43 px wide vs 30. -> deleted (3 sites + helper).
- Fixed-panel SplitterDistance (96 -> 150%): EditNoteDlg 157 -> 363 (x2.31),
  SpectrumGridForm 122 -> 282 (x2.31) with ScaleFixedPanel; the untouched
  splitContainerVertical 100 -> 167 = the framework alone. -> deleted
  (4 sites + helper). SpectrumGridForm.cs is now identical to the port.
- ColorGrid column widths 107 (4.7.2) vs 109 (.NET): the framework does NOT
  re-scale explicitly set DataGridView column widths -> our column scaling
  (ColorGrid, ImportTransitionListColumnSelectDlg, ...) stays. RowHeadersWidth
  41 -> 62 is the framework (as measured on 09-17).
- 96 DPI: .NET and 4.7.2 dumps identical control for control (EditNoteDlg /
  SpectrumGridForm deltas are probe state, not DPI).
- NOT OURS: at 150% .NET makes every AutoScaleMode.Font form 11% WIDER than
  4.7.2 (heights identical; FlowLayoutPanels in the Full-Scan tab 452 -> 333).
  That is the port's font-metric autoscale (average char width measured
  differently on .NET), present on the port with or without this branch.
  Consequence: the 4.7.2 galleries are not pixel-comparable to a .NET sweep;
  a fresh .NET sweep is the reference from here.
PRODUCT CHANGES ON THE MERGED BRANCH (uncommitted): Program.Init
SetHighDpiMode(SystemAware) guarded by !UnitTest && !FunctionalTest; the seven
deletions above; DpiUtil keeps GetFactor/Scale/ScaleSize/ScaleImageForList/
DrawImageCentered/ScaleFromLogical/ScaleToLogical/dock-layout transforms.
GATE (offscreen, .NET, 96 DPI): TestEditNote, TestSpectrumGrid,
TestLibraryExplorer, TestUniquePeptidesDialog, TestVolcanoPlotFormatting,
TestPrecursorIon, TestNeutralLoss - log gate-net10-deletions.log.
### 2026-09-29 - merged the port into the branch (steps 1-3 done)

- ae561caef0 PopupPickList fix committed (approved). Harness + tutorial-scaling
  edits saved as ai/.tmp/sessions/20260910-dpi/patches-20260929/{harness,
  tutorial-scaling}.patch + DpiPaneSweepTest.cs; tree cleaned.
- 8eb6af85b0 = git merge origin/Skyline/work/20260612_net8_port (head
  553a145871). Conflicts exactly as predicted: Skyline.csproj -> took the port
  file; ComparePeakPickingDlg.cs -> same null-guard, took the port comment;
  Program.cs -> kept PaneBase.DpiScaleFactor line next to the port's new
  InitUiThreadExceptionHandling(). Build via Build-Skyline.ps1 -VendorLicenses
  (auto-detects the SDK TFM, builds with dotnet) - log build-port-1.log.
CORRECTIONS to the plan, measured on the merged tree:
- Skyline.csproj is net10.0-windows ONLY (the "net472;net8" reading earlier
  was a stale ref before fetch). So the framework-duplicated fixes are
  DELETED, not made conditional.
- Skyline.csproj has NO <ApplicationManifest>, so Properties/app.manifest
  (our dpiAware flip) is not embedded on .NET -> awareness must be set in
  code: Application.SetHighDpiMode(SystemAware) in Program.Init, guarded by
  !UnitTest && !FunctionalTest so the test host stays 96-DPI deterministic.
  The net10 runner DOES embed its app.manifest (dpiAware commented out), so
  the sweep's "after" phase can keep flipping that manifest locally.
- harness.patch: TestFunctional.csproj hunk obsolete (SDK globbing);
  runner Program.cs hunks hand-applied (scratchpad apply_harness.py).
  tutorial-scaling.patch applies cleanly.
AUDIT LIST for double scaling on .NET (probe at 150% before deleting):
ScaleToolStripImages x3 (Skyline.cs, VolcanoPlotFormattingDlg, PopupPickList),
ScaleFixedPanel x4 (EditNoteDlg, UniquePeptidesDlg, SpectrumGridForm,
ViewLibraryDlg); and check the grid column-width scaling sites (ColorGrid,
ImportTransitionListColumnSelectDlg, UniquePeptidesDlg header, KeyValueGridDlg,
SpectrumLibraryInfoDlg header) since .NET scales default column widths.
### 2026-09-29 - DECISION: land this work through the .NET port branch

Developer: Brendan plans to make the port the main Skyline version by end of
October (3-4 weeks); the DPI work merges INTO the port branch and reaches
master with it. Port state checked 2026-09-29: PR #4619 open (not draft, base
master, 676 commits ahead, head 553a145871 today, currently CONFLICTING until
master is merged in); Skyline multi-targets net472 + .NET, the test runner is
net10.0-windows only; manifest dpiAware still commented out and no
HighDpiMode anywhere -> the .NET build is DPI-unaware, so the merge alone
switches all of this off. 8 overlapping files (unchanged list from 09-17).
PLAN: (1) commit PopupPickList fix; (2) save harness + tutorial-scaling
patches to the session folder, clean the tree; (3) git MERGE (never rebase -
PR exists) origin/Skyline/work/20260612_net8_port, resolve csproj (take
port), ComparePeakPickingDlg (same fix), using blocks; build on the port
toolchain; (4) enable SystemAware for the .NET target; make
ScaleToolStripImages (3) and ScaleFixedPanel (4) conditional on NETFRAMEWORK
(the .NET framework scales those itself; ImageList scaling stays); geometry
probe at 150% on the .NET build; (5) port the capture harness to the net10
test runner, re-run form sweep + tutorial night run, review via galleries;
(6) retarget PR #4602 base to the port branch, /code-review max, ready.
### 2026-09-24 - NIGHT RUN DONE (17:08-18:39, 92 min, 17 tutorials)

Summary log: ai/.tmp/sessions/20260910-dpi/night-20260924-1707.log; per-phase
logs night-<Name>-<phase>.log. Gallery rebuilt: 610 tutorial shots in
ai/.tmp/dpi-sweep/tutorials/index.html (844 pairs scored incl. the form sweep).
14 tutorials PASSED both phases. Failures:
- TargetedMSMS: 150% phase FAILED (16 of 34 shots) - WaitForConditionUI timeout
  360 s with the main window + 2 chromatogram graphs open; the 96-DPI phase
  passed (34 shots). CAUSE: ValidatePeakTooltips (TargetedMSMSTutorialTest.cs
  ~1397) synthesizes mouse positions in 96-DPI pixels on the spectrum graph
  ((191,95), (169,175)); at 150% no peak is under those points, so the
  tooltip never appears and WaitForConditionUI times out. Test literal, not
  product. To finish the 150% set: scale the three points via DpiUtil locally
  (LOCAL DPI SWEEP) and re-run the after phase (~140 s).
  100%-scored pairs are harness artifacts: 5 status-bar clips (34 px tall,
  blank in the DPI-unaware phase) and the MethodEdit crop-literal shots.
  AuditLog/s-20: floating audit log sized from unscaled grid columns
  (1071x183 -> 1207x214, x1.13) - grid family + test sizing.
- MSstats and Quasar (legacy tutorials): FAILED in BOTH phases with "left these
  temp files behind" (test hygiene, not DPI); their 8 and 6 shots were still
  captured and are in the gallery.
Pass-through with the updated score, all 609 tutorial pairs: 329 (54%) over 2%,
197 (32%) over 5%. Grid-heavy tutorials dominate (LiveReports 57/69,
CustomReports 27/28, SmallMolMethodDevCEOpt 25/35); graph/dialog tutorials
run 30-40%.
### 2026-09-22 (evening) - differ upgrade + night run over all tutorials (prepared)

PopupPickList fix VERIFIED: MethodEdit re-capture, s-19/s-20 list 292 = 12*24+4
(was 268), popup 338; 96-DPI phase byte-identical geometry (226/196); gate
TestPrecursorIon, TestNeutralLoss, TestPickChildrenMcpConnector PASSED (25 s).
UNCOMMITTED (Controls/PopupPickList.cs).

DIFFER: developer asked that this class score higher. Measured: a blank band
where the other phase has a row of text barely moves a 32px cell mean (0.5%).
Added a "band" component to make_layout_diff.py: per pixel row/column ink
fraction (gray < 160); a run of >= 6 rows that is blank in one phase (< 0.6%,
i.e. only the form border) and inked in the other (> 5%) counts; score =
max(mean, band). Thresholds read off the s-23 profiles (band rows 0.003 vs
0.05-0.13). Result: pre-fix s-23 4.1 (was 0.5), fixed 0.5; forms AUC 0.855
(was 0.824); a 2% cut keeps ~3 more pairs per clean tutorial. Rejected on the
way: a global ink-density channel (flags every text re-render, 23/23 MethodEdit
pairs) and a 32px blank-vs-content cell test (too coarse for a 15px band).
Overlays draw band findings as orange stripes. Galleries got a "Diff > 2%"
filter button (both pages; keys unchanged).

NIGHT RUN (developer: capture all tutorials, review only > 2%):
- ALL tutorial tests now carry LOCAL DpiUtil scaling of their integer window
  sizes (74 sites in 18 files, tagged "LOCAL DPI SWEEP - do not commit";
  scratchpad scale_tutorials.py/2.py were regex passes, int-only right-hand
  sides so "restore old height" lines stay), plus SetSkylineWindowSize in the
  harness TestFunctional.cs (18 callers incl. cover shots). Release build green.
  Caveat: sizes over the screen at 150% (GroupedStudies1 1920x1032 -> 2880 wide)
  will be clipped and score high - that is test sizing, not product.
- run-tutorialshots.ps1 got -Internet (passes -EnableInternet) for the three
  tutorials whose zips are not cached (iRT, MethodRefine*, GroupedStudies1).
- NEW ai/.tmp/sessions/20260910-dpi/run-tutorial-night.ps1: 18 remaining
  tutorials (cached first, internet ones last), after then before each, one
  log per phase + night-<stamp>.log summary, then make_layout_diff +
  make_tutorial_gallery. -All re-captures the four done today; -Only <tests>.
  SMOKE TEST PASSED (17:11-17:14): LibraryExplorer 23 shots per phase, ~75 s each,
  scoring + gallery ran (log night-20260922-1711.log). First attempt ran the
  wrong test - the runner had names with 'Tutorial' stripped (TestLibraryExplorer
  is a plain functional test; the harness saves shots only when the test name
  contains 'Tutorial') - fixed, all 22 names verified against the files.
  LibraryExplorer added to the done list. Pass-through at the 2% cut on the
  132 pairs from today: 63 (48%); at 5%: 37 (28%); CustomReports is 27/28
  because nearly every shot holds a grid with the unscaled column family.
  LAUNCHED at the developer's request when they left (detached hidden pwsh,
  pid 1976, console unlocked, 2560x1440 at 150%). Results: night-<stamp>.log +
  tutorials/index.html next morning; review with the 'Diff > 2%' filter.
  LAUNCH when the desktop is free (developer's call; takes the primary monitor
  for the whole run): pwsh -NoProfile -File
  ai/.tmp/sessions/20260910-dpi/run-tutorial-night.ps1  (17 tutorials left;
  summary in night-<stamp>.log, per-phase logs night-<Name>-<phase>.log).
- REQUIREMENT: session unlocked, primary monitor free all night (real screen
  captures; a locked session yields lock-screen images).
### 2026-09-22 - PopupPickList blank band under the list (developer report, Ms1 s-23) - FIXED, uncommitted

Developer: "s-23 did not scale the list correctly, too much blank space under
it" (also visible in MethodEdit s-19/s-20; the layout diff missed it - one
mostly-white row moves a 32px cell mean too little).
ROOT CAUSE (measured from the s-23 dumps): the popup scales 226 -> 336 but the
ListBox only 196 -> 268. The 96-DPI design is exactly 12 rows of 16 px (client
192). At 150% the anchored list gets 290 px with 24 px rows = 11.9 rows;
ListBox.IntegralHeight (default true) snaps it to 11 rows (264 + 4 border =
268) when the handle is created - AFTER the ctor fixed the popup height to
list.Bottom + 8 - leaving a 22 px band. Identity at 96 because 192/16 is whole.
FIX (Controls/PopupPickList.cs ctor, after the ItemHeight scaling): rowsVisible
= Round(list.ClientSize.Height / scaled ItemHeight) (12 at every DPI), then
Height += rows*ItemHeight + border - list.Height, so the list is a whole number
of rows before the snap. Delta is 0 at 96 DPI. Only ListBox on the branch that
scales ItemHeight (grep), so no sibling sites.
VERIFY: MethodEdit re-capture both phases (s-19/s-20 dumps: list height should
be 292 = 12*24+4, popup ~360); gate at 96: PrecursorTest, NeutralLossTest,
PickChildrenMcpConnectorTest. Ms1 s-22/s-23 captures predate the fix.
### 2026-09-22 - MS1 Full-Scan Filtering tutorial swept (44 shots per phase, both PASSED)

Runner: -Test TestMs1Tutorial -Name Ms1Filtering (137 s per phase; MS1Filtering-
22_2.zip raw data cached). 20 window-size sites scaled locally (regex pass).

FINDINGS - no new product defect; SPECTRUM VIEWERS COVERED:
- Full-scan MS1 spectrum graphs (3), library match pane, library-explorer
  spectrum, chromatogram and peak-area metafiles: every pane capture scores
  0.0 layout diff at exactly 1.5x pixel size (25 pane pairs).
- ViewLibraryDlg 4.3%: boxes on list rows and peak labels only; layout
  intact (first clean capture of this dialog - the form sweep always had
  Add Modifications in front).
- AlignmentForm 6.1%: boxes on its grid header/row = the column-width family.
- Import Peptide Search wizard pages (6), Associate Proteins, Import Results
  progress, Add Modifications, Minimize Results, main window layouts: 0-7%.
HARNESS ARTIFACTS: the two screen-region captures are broken in the 96-DPI
phase only - s-13 (Peak Areas + context menu, ScreenForm) grabbed the editor
window, s-17 (status bar clip) came out blank; a DPI-unaware process computes
screen rects in virtualized coordinates. The 150% versions are fine (context
menu and check marks scale correctly).

Spectrum-viewer tutorials still available: Targeted MS/MS (many library match
+ MS/MS full-scan captures; TargetedMSMS_2.zip IS cached) and
DIA (13 full-scan refs; DIA-QE/DIA-TTOF zips cached but multi-GB runs).
### 2026-09-22 - Existing Experiments tutorial swept (37 shots per phase, both PASSED)

Runner: run-tutorialshots.ps1 -Test TestExistingExperimentsTutorial -Name
ExistingQuant (after 168 s, before 160 s; ExistingQuant.zip raw data, cached).
Local test edit (8 LOCAL DPI SWEEP lines): importDialog/messageDlg/SkylineWindow
sizes, documentGrid container size, GraphPeakArea width via DpiUtil.

FINDINGS - no new product defect:
- 15 graph-pane captures (chromatogram, peak areas, RT, library match) score
  0.0 layout diff even though the 150% images are exactly 1.5x the 96-DPI ones
  (pane captures are true renders, not DWM-stretched: 784x512 -> 1179x771):
  the DpiScaleFactor graph work reproduces the 96-DPI layout cell for cell.
- s-29 Document Grid (Replicates): the known unscaled column-width family
  ("Analyte Concentration" header wraps/truncates; probe cols=[100,100!106,
  100!173] at 150% vs [100,100,100!111]).
- s-06 Import Transition List column select: layout diff 25% only because the
  scaled initial column widths shift the column boundaries; same 4 columns
  visible in both phases (this dialog had 3 review rounds in the form sweep).
- s-22 main window with three graphs: diff boxes fall on tree icons and bar
  charts (rendering noise), layout intact.
- All dialogs (Peptide Settings tabs, Edit Static Mod, Insert Transition List,
  Import Results Samples/Name, Edit Modifications) 0-4%.
### 2026-09-22 - HANDOFF (context exhausted mid-tutorial-sweep)

BRANCH STATE: 6 commits pushed to draft PR #4602 (tip `0389b02887`), working
tree clean of product changes. Uncommitted and NEVER to be committed - the
sweep harness: TestRunner/app.manifest + TestRunner/Program.cs, Program.cs
(FormScreenshotDir hunk only), TestUtil/TestFunctional.cs (capture hook, layout
dump, CaptureScreenRect, TutorialPath redirect, open-forms dump),
TestFunctional.csproj + TestFunctional/DpiPaneSweepTest.cs, and NOW ALSO
TestTutorial/MethodEditTutorialTest.cs (4 window sizes wrapped in DpiUtil.Scale,
each marked "LOCAL DPI SWEEP - do not commit").

WHERE THE TUTORIAL SWEEP STOPPED: Method Edit captured in both phases with
scaled window sizes; 21 of 23 shots now match physically. Two do not - s-16
and s-17, both of the protein/description AUTO-COMPLETE DROPDOWN
(StatementCompletionForm), 735 px wide in BOTH phases while the text is the
same physical size, i.e. it looks like the popup does not scale.
NOT PROVEN: the dump of open forms came back with only the docked forms
(SequenceTreeForm, GraphSpectrum) - the popup is not in Application.OpenForms
at capture time, so its real bounds were never measured. Next session: measure
StatementCompletionForm directly (a DpiLayoutProbeTest-style test that types
into the Targets box and dumps the popup) before calling it a bug. Its sizing
code (Controls/StatementCompletionForm.cs ResizeToIdealSize) already scales
dxIcon/dxGap and measures with the ListView font, so the mechanism is unclear;
MaxWidth = 1000 is a raw literal but appears unused.

ALSO NOTE: the 96-DPI tutorial run reported a GC-LEAK failure (SkylineWindow,
SrmDocument not collected) while still producing all 23 shots - unrelated to
DPI as far as anything here shows, but worth a look if it recurs.

NEXT STEPS, in the order they make sense:
1. Developer reviews tutorials/index.html (Method Edit) and the 8 new forms in
   the form gallery; export as dpi-tutorial-review.json / dpi-sweep-review.json.
2. Settle the auto-complete popup question above.
3. More tutorials if wanted: run-tutorialshots.ps1 -Phase after|before
   -Test <TestName> -Name <Folder>, then make_tutorial_gallery.py. Each
   tutorial that sets window sizes in pixels needs the same local
   DpiUtil.Scale treatment as MethodEditTutorialTest.
4. waters_connect dialog still blocked on WC_USERNAME/WC_PASSWORD.
5. When the port merges: the PORT-MERGE PLAN section below.
6. Before marking PR #4602 ready: revert the harness files, /code-review max.

### 2026-09-22 - Tutorial screenshots as a second sweep (Method Edit first)

Developer's idea: drive SkylineTester's tutorial auto-screenshot mode in both
DPI phases - the shots show populated windows (real data, graphs, grids), which
the form sweep could not.

Mechanism: `pause=-3` is auto-screenshot mode; the wrapper already exposes it as
`Run-Tests.ps1 -TakeScreenshots` (implies -ShowUI). CAUTION: that mode writes
`s-NN.png` straight into `Documentation\Tutorials\<name>\en\`, i.e. it would
overwrite the committed tutorial images with 150% versions. The local harness
now redirects it: `TutorialPath` honours SKYLINE_TUTORIAL_SHOT_DIR (sweep-only,
in the uncommitted TestFunctional.cs). Verified `git status` on Documentation
stays clean after both runs.

Runner: ai/.tmp/sessions/20260910-dpi/run-tutorialshots.ps1 -Phase after|before
[-Test <TestName> -Name <FolderName>]. Output:
ai/.tmp/dpi-sweep/tutorials/<Name>/<phase>/s-NN.png.
Review page: `python ai/.tmp/dpi-sweep/make_tutorial_gallery.py` ->
tutorials/index.html (same controls as the form gallery; localStorage namespace
`dpitut:`, export file dpi-tutorial-review.json, so the two reviews never mix).

Method Edit: 23 shots in each phase, test PASSED both times (103 s per run).
CAVEAT for review: 8 of the 23 (s-04, s-05, s-08, s-11, s-12, s-15, s-16, s-17)
come out physically smaller at 150% because the tutorial sets window sizes in
raw pixels (MethodEditTutorialTest.cs:170 `SkylineWindow.Size = new Size(1035,
511)`, pastePeptidesDlg.Height = 437, uniquePeptidesDlg.Height/SplitHeight).
Judge those by internal proportion; the crowding is test sizing, not product
layout. The same class of test-code sizing was fixed in DpiPaneSweepTest by
scaling through DpiUtil - tutorial tests would need the same if tutorial
screenshots are ever taken on a scaled display.

### 2026-09-22 - NoModeUIDlg list rows (developer report) - measured, port fixes it

"Select a Default User Interface": the ImageListBox rows grow with the font
but not with DPI (list 120x52 -> 178x68, i.e. width x1.48, height x1.31).
Same shape as grid rows: item height = font height + unscaled padding.
Probe on .NET 10: an OwnerDrawFixed ListBox's ItemHeight goes 16 -> 24
(exactly x1.5), so THE PORT FIXES THE ROW HEIGHT. What the port does NOT fix
is the row icons: ImageList.ImageSize stays 16x16 DPI-aware on .NET 10, so
ImageListBox icons need the same ScaleImageForList treatment the trees got,
or 32px assets. Left unfixed on this branch by the same rule as the other
framework families; the icon half joins the artwork follow-up.

### 2026-09-17 - PORT-MERGE PLAN (agreed: wait for the port to merge)

Do NOT rebase this branch onto the port - it has PR #4602, so the repo rule
is `git merge origin/master` after the port lands (a rebase would force a
force-push). Expect the squash-merged-parent shape: the merge base falls
back and the diff looks enormous though master moved by one commit; merge
and resolve anyway (both sides already hold the port's content).

Measured overlap (port branch `20260612_net8_port` head c0d8525373 vs this
branch 0389b02887): 8 files of the port's 1847 and our 56.
- `Skyline.csproj` - certain conflict, trivial: the port rewrites it whole
  (7574 -> 561 lines, SDK-style). Our single added <Compile> line for
  DpiUtil.cs is redundant under SDK globbing -> TAKE THE PORT'S FILE.
- `ComparePeakPickingDlg.cs:854` - both branches made the SAME fix
  (`_axisLabelScaler?.` + brace); keep either comment. The port hit that
  crash independently.
- Possible `using`-block conflicts: Program.cs, Skyline.cs,
  SpectrumGridForm.cs, ExportMethodScheduleGraph.cs (both add usings).
- The other 48 of our files (designers, resx, ZedGraph, MSGraph, DpiUtil)
  the port does not touch.

THE MERGE SILENTLY DISABLES THIS WORK unless awareness is re-enabled: the
port sets no ApplicationHighDpiMode, calls no SetHighDpiMode, and its
app.manifest still has dpiAware commented out (line 52) - and on .NET the
manifest is not the mechanism anyway. A probe on the port confirmed the
default is UNAWARE. Sequence after the port merges:
1. merge master, resolve the above;
2. enable awareness for net10 (ApplicationHighDpiMode / SetHighDpiMode);
3. run the geometry probe over the fixed dialogs and DELETE what now
   double-scales: ScaleToolStripImages x3 and ScaleFixedPanel x4 - the
   ColorGrid row bug was this exact failure mode.
   CORRECTION (2026-09-22, measured): the tree/list ImageList scaling must
   be KEPT. .NET 10 leaves ImageList.ImageSize at 16x16 even when DPI-aware
   (it scales ToolStrip.ImageScalingSize but not image lists), so
   ScaleImageForList and the SequenceTree/FilesTree ImageList work stay;
   dropping them would shrink the tree icons again after the port;
4. keep the rest (AutoScaleMode additions, wizard offsets, code-built
   dialogs, ZedGraph/MSGraph, dendrogram, scheduling pane, persisted
   geometry, nested-UC anchor restore).

### 2026-09-17 - review round 3 (222 forms reviewed, 19 bugs)

Export `dpi-sweep-review (3).json`. 7 earlier bugs now marked OK
(WarnOnPresetChangeDlg, VolcanoPlotFormattingDlg, EditCustomMoleculeDlg,
DiaIsolationWindowsGraphForm, GraphRegression, AlignmentForm,
CalibrationForm). Of the 12 new/changed entries:

REAL BUG, MINE, FIXED: ColorGrid rows were DOUBLE-SCALED. ColorGrid.cs
scaled RowTemplate.Height, but WinForms already derives row height from the
font (22 -> 28 at 150%), so rows came out 42 - the last row clipped and the
grid appeared to run into the controls below (EditCustomThemeDlg, and the
same control in VolcanoPlotFormattingDlg). Line removed; probe confirms
22 -> 28. Column-width scaling on the neighbouring lines IS needed and stays.
(Same class as the OnShown double-scale removed earlier: our fix plus a
framework behaviour that was already there.)

ComparePeakPickingDlg: withdrawn by the developer; measurement agreed - the
checkbox/graph overlap exists identically at 96 DPI (by design, the boxes sit
over the graph's empty top margin) and scales proportionally.

FRAMEWORK FAMILIES (leave for the port, all measured):
- grids: EditCEDlg, EditIsotopeEnrichmentDlg, FoldChangeGrid and
  SpectrumLibraryInfoDlg row spacing. Designer-fixed column widths in the
  .resx (Charge.Width etc.) are not scaled; MinimizeResultsDlg looks right
  because it sets AutoSizeColumnsMode = Fill in code (MinimizeResultsDlg.cs:88),
  so its widths follow the control. .NET scales default widths 100 -> 150.
- tab strips: DocumentSettingsDlg and ListDesigner "extra space at the
  bottom". .NET Framework grows the strip 22 -> 29 at 150% (font-derived,
  padding unscaled); .NET 9 gives item height 20 -> 30 and page top 24 -> 34.
- icons: EditPeakScoringModelDlg.FeaturesTab, GraphFullScan (size only now -
  their fonts are fixed).

HeatMapGraph and ExportMethodScheduleGraph re-captured on the current build -
both were REAL and are now FIXED:
- DendrogramScale reserved a fixed 100px for the tree depth
  (GetScaleMaxSpace + Draw), so trees shrank against the heat map as the
  factor grew. Now DENDROGRAM_DEPTH * scaleFactor, the same way ZedGraph
  scales fonts and symbols. Re-capture matches the 96-DPI proportions.
- ExportMethodScheduleGraph adds its pane to the MasterPane AFTER the control
  is laid out, so nothing ever resized it and it kept ZedGraph's default
  500x375 rect - which happens to fill the dialog at 96 DPI and covers two
  thirds of it at 150%. Now ReSize'd to the control after the pane is added.
Gate at 96 DPI: TestEditCustomTheme, TestVolcanoPlotFormatting,
TestClusteredHeatMap, TestExportMethodDlg all PASSED.
Committed `0389b02887` and pushed (gates: CodeInspection PASSED,
QuickInspection 0 errors, its 3 warnings all in the uncommitted harness).
Branch now 6 commits ahead of 12f0f16b07 on draft PR #4602.

Icon asymmetry the developer spotted: the volcano formatting toolbar looks
right because it is one of only THREE toolbars with an explicit
DpiUtil.ScaleToolStripImages call (main window, volcano formatting, pick-list
popup). PivotEditor's up/down/delete come from the shared
pwiz.Common ColumnListEditor, which has none - as does every other toolbar.
They are ToolStrip images, so the port scales them (16 -> 24 measured);
adding calls now would only have to be deleted at port time.

THE VOLCANO TEST ASSERT IS NOT A DPI BUG - measured matrix:
150% offscreen PASS, 150% onscreen PASS, form mode at 96 DPI FAIL, form mode
at 150% FAIL. It needs FORM MODE, i.e. our local capture hook, which replaces
the interactive pause with activate + 1.5s + screenshot while the test is
mid-interaction with the color grid; a phantom new row gets committed and the
next iteration sees 1 row where it expects 0. Harness-only, never committed.
The clipped error dialog in the developer's screenshot is WinForms' own
ThreadExceptionDialog (Skyline shows its own reporter in production).

### 2026-09-17 - MEASURED: modern .NET scales the two deferred families

CONFIRMED ON .NET 10 (2026-09-17, after the developer installed VS 2026:
SDK 10.0.401, WindowsDesktop 10.0.12): the same probe retargeted to
net10.0-windows produces numbers IDENTICAL to net9 in all three modes -
ImageScalingSize 16 -> 24, column width 100 -> 150, row 25 -> 33, header
23 -> 34, row-header 41 -> 62, fixed SplitterDistance 117 -> 167, tab item
height 20 -> 30, page top 24 -> 34; drawn image stays 16px. Everything
below therefore holds for the port, not just for .NET 9.

The original measurement was made with no .NET 10 SDK on the machine
(highest was SDK 9.0.203, WindowsDesktop 9.0.4), using a throwaway
WinForms app (scratchpad .../dpiprobe, net9.0-windows, awareness chosen at
run time). At 150%, DPI-aware (SystemAware and PerMonitorV2 identical):

| value (96-DPI default) | unaware | DPI-aware |
|---|---|---|
| ToolStrip.ImageScalingSize 16 | 16 | 24 |
| DataGridView column width 100 | 100 | 150 |
| DataGridView row height | 25 | 33 |
| ColumnHeadersHeight | 23 | 34 |
| RowHeadersWidth 41 | 41 | 62 |
| SplitContainer fixed SplitterDistance (design 100) | 117 | 167 |

So on .NET the framework scales icon sizes, grid metrics AND fixed splitter
positions - all three are .NET Framework gaps we have been filling by hand.
The source artwork is still 16px (drawnImageSize stays 16), so icons remain
soft until 32px assets exist; that part is not a framework question.

CONSEQUENCES
1. Do NOT write the central icon or grid-column fixes on this branch: after
   the port they would double-scale, exactly like the ColorGrid OnShown bug
   removed today.
2. At port time AUDIT (likely delete) the fixes that duplicate framework
   behavior: DpiUtil.ScaleToolStripImages (main toolbar, volcano toolbar),
   the tree/FilesTree ImageList scaling + ScaleImageForList, and
   DpiUtil.ScaleFixedPanel (4 call sites).
   KEEP (genuine app bugs, framework-independent): the AutoScaleMode
   additions, wizard AddPageControl offsets, code-built dialog layout,
   ZedGraph DpiScaleFactor + MSGraph measurement, GraphFullScan point/pixel
   units, persisted 96-DPI geometry, the nested-UC anchor restore.
3. Re-run the probe on .NET 10 once its SDK is installed (one command) to
   confirm nothing changed between 9 and 10.

### 2026-09-17 - five commits pushed to draft PR #4602

Pre-push gates: Debug build green, CodeInspection test PASSED,
QuickInspection 0 errors / 4 warnings - 3 in the uncommitted harness file
and 1 real leftover of the wizard commit (unused `using System.Drawing`
in EncyclopeDiaSearchDlg after its private AddPageControl was removed),
fixed and folded into that commit before pushing.
ATTRIBUTION DEFECT CORRECTED: the first two commits carried the harness-
injected trailer (model name + Claude-Session URL). This repo's rule is
exactly `Co-Authored-By: Claude <noreply@anthropic.com>` and nothing else;
both messages were rewritten before the push (never pushed in the bad
form, so no force-push).
Pushed `12f0f16b07..48ef8f4731`:
  aac5777159 Scaled graph fonts, symbols and pens to the display DPI
  d2bd634292 Fixed wizard page bodies riding up under their title headers
  8f23cb42a9 Enabled auto-scaling on dialogs that never scaled
  2c037c5ff8 Fixed fixed-panel splitters and color grid double scaling
  48ef8f4731 Fixed the ion mobility group box staying at 96-DPI width
Still local (sweep harness, never commit): Program.cs harness hunk,
TestFunctional.csproj, TestRunner/Program.cs, TestRunner/app.manifest,
TestUtil/TestFunctional.cs, TestFunctional/DpiPaneSweepTest.cs.

### 2026-09-17 - visual verification of the review-round-2 fixes

Developer corrections: the Full-Scan tab is FINE (its IM group box sits
below the visible area of that tab - it is there for the wizard - and the
2 flow-panel CLIPPED flags are 1-2px rounding); and the Ion Mobility TAB
is not part of the import wizard (the shared thing is the user control,
via FullScanSettingsControl, which calls ShowOnlyResolvingPowerControls).
So the tab could be fixed directly: IonMobilityFilteringUserControl now
records its group box's right gap in the ctor and restores it in OnLoad,
skipped when the wizard has set the width (_groupBoxWidthSetByHost).
Probe: group box 326 -> 489 (x1.5), tab OK; wizard ImsFullScanPage
unchanged (only the same 1-2px flow-panel flags).

Re-captured at 150% (batch-91 = 19 forms, batch-92 = IonMobilityTab).
VERIFIED VISUALLY: EditCustomMoleculeDlg, PermuteIsotopeModificationsDlg,
ComparePeakPickingDlg (no crash), WarnOnPresetChangeDlg, EditNoteDlg,
UniquePeptidesDlg, SpectrumGridForm, VolcanoPlotFormattingDlg (columns +
RGB combo + OK/Cancel all back), EditCustomThemeDlg, SpectrumLibraryInfoDlg,
IonMobilityTab; and the graph-font commit cleared GraphRegression,
DiaIsolationWindowsGraphForm, EditPeakScoringModelDlg charts, AlignmentForm,
CalibrationForm, GraphFullScan axes, FoldChangeVolcanoPlot.
Still visible in those captures (open families): grid column widths
(EditPeakScoringModelDlg "Enab"/"Percent", UniquePeptidesDlg peptide column)
and 16px icons.
ViewLibraryDlg again captured with Add Modifications in front - its covering
test opens that dialog immediately; needs a different capture path.
Test noise at 150% in form mode: TestVolcanoPlotFormatting asserts
(pre-existing - also failed in batch-07 on 2026-09-08) and left a modal
error dialog that blocked the run until dismissed; TestEditNote asserted
once (colour index, not layout) but passes at 96 DPI and passed twice at
150% earlier today - treated as flaky.
Third commit proposal: commit-message-ionmobility.txt.

Visual re-capture queued for the unlocked desktop:
sweep/batches/batch-91.txt (19 forms: graph-font forms + every fixed
dialog): pwsh -File ai/.tmp/dpi-sweep/Run-FormBatch.ps1 -Batch 91 -Phase after

### 2026-09-10 (cont.) - Wizard header overlap (bug family D) root-caused

Developer review export (Downloads on D:, `D:\Users\RitaCh\Downloads\
dpi-sweep-review.json`) flagged the wizard pages. Root cause: three
identical private `AddPageControl` copies (ImportPeptideSearchDlg,
DiannSearchDlg, EncyclopeDiaSearchDlg) place the runtime-created page
body at raw 96-DPI offsets (header 60/50/43, border 2/18/3/0) AFTER the
form auto-scaled, so at 150% the body rides ~30px up under the (scaled,
designer-built) title banner. SpectraPage is correct because its body is
docked into a designer panel. Fix (uncommitted): one shared
`WizardPages.AddPageControl` that DPI-scales border/header; the one
caller passing an already-scaled value (feature-detection
buildSpectralLibraryTitlePanel.Bottom) converts via ScaleToLogical.
Also DIA-NN settings-preset row: combo placed from the label's Right
before the label was parented (default-font width) + unscaled literals
-> combo overlapped "Settings preset:"; now parented first, measured
with PreferredWidth, literals scaled, Save matches Back/Next height/top.
Re-capture batch: sweep/batches/batch-90.txt (14 wizard pages);
pre-fix afters backed up to raw/after-prewizard/.
VERIFIED at 150%: 13/14 re-captured (DiannSearchDlg.FastaPage never
captures); FASTA/DDA Search/Chromatograms/Search Settings/Conversion/
IMS pages match the 96-DPI layout, DIA-NN header + preset row fixed.
Gate at 96 DPI (shim): TestImportPeptideSearch, TestDiannSearch,
TestDdaSearch, TestDiaSearchVariableWindows, TestEncyclopeDiaSearch,
TestDiaTutorial, TestTargetedMSMSTutorial pass. TestMs1Tutorial failed
once ("Full-scan dot not present") then passed alone and after
TestEncyclopeDiaSearch - 3/4 passes at 96 today; treated as a click-helper
timing flake, not proven. NOTE: TestRunner's "N failures" column is the
RUN's cumulative count, not per test.
Test-harness follow-up: at 150% DPI-aware the tests' pixel window sizes
leave tiny chromatograms, so ClickChromatogram hits labels (TestMs1Tutorial
fails consistently in form mode at 150%) - scale test window sizes if
DPI-aware test runs are ever wanted. TestTargetedMSMSTutorial times out
(360s WaitForConditionUI) in 150% form mode, pre-existing.
Committed `b7174274cc` (4 files +54/-51) on developer approval. NOT
PUSHED (with 8d10f13fd4); QuickInspection + CodeInspection before push.

Other review findings still open (from the export): ViewLibraryDlg
capture actually shows Add Modification dlg (capture artifact);
EditPeakScoringModelDlg.FeaturesTab icon + chart fonts (check whether
the graph-font commit fixed the fonts); WarnOnPresetChangeDlg buttons
clip/form too small; WatersConnectSaveMethodFileDialog + PivotEditor +
GraphFullScan toolbar icons (family E); VolcanoPlotFormattingDlg grid
still too large; EditNoteDlg field height; DDASearchSettingsPage textbox
vs Additional Settings spacing (pre-existing too); UniquePeptidesDlg
bottom panel larger (marked OK).

### 2026-09-07 - Registry-driven form sweep started (Chunk 1)

Manual brute-force sweep, driven by TestRunnerFormLookup.csv (265 forms),
risk-ranked (ai/.tmp/dpi-sweep/form-risk-ranking.tsv). Gallery now has a
checkable alphabetical sidebar. Chunk 1: 5 before/after pairs captured
(InsertTransitionListDlg, EditNoteDlg, EditPepModsDlg, AreaCVToolbarProperties,
EditIsolationSchemeDlg) - awaiting developer review. Image-diff automation
ruled a dead end (logical-res captures). **Next session handoff**: read
ai/.tmp/handoff-dpi-form-sweep.md for the full continue protocol.
