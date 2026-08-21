# DPI-Scaling Hazard Inventory - pwiz_tools/Skyline (product code)

Generated 2026-08-20 by a fresh-context sweep agent on branch
`Skyline/work/20260820_dpiAwareness`. Root for all paths:
`pwiz_tools/Skyline/`. Baseline: `app.config` `DpiAwareness=SystemAware`
is the only DPI-related declaration in the tree; there is NO existing
DPI-compensation code in product code (no DeviceDpi, LogicalToDeviceUnits,
AutoScaleFactor, DpiChanged, ScaleControl anywhere).

## 1. Runtime `new Font(` outside Designer files

| Site | Description | Risk |
|---|---|---|
| Controls\Startup\StartPage.cs:267 | `new Font(@"Arial", 12F, Point)` tutorial section headers + width math at :282 | high |
| Controls\ImmediateWindow.cs:45 | `new Font(@"Consolas", 9F, Point)` fixed 9pt ignores form font | medium |
| Controls\NodeTip.cs:298-299 (:112-113) | RenderTools 8pt Arial for ALL node tooltips; drives TableDesc measurement | medium |
| Controls\TreeViewMS.cs:326 | `new Font(Font.FontFamily, DEFAULT_FONT_SIZE * TextZoom)`, DEFAULT_FONT_SIZE=8.25 (:53) - overwrites DPI/AutoScale font; paired with ItemHeight :325. Most critical font/metric coupling in the app | high |
| Controls\SequenceTree.cs:1678-1679 | ModFontHolder derives from _control.Font - correct idiom | low |
| Controls\GroupComparison\VolcanoPlotFormattingDlg.cs:48 | 16f symbol-glyph font; feeds ItemHeight=+4 (:249) | medium |
| Controls\StatementCompletionForm.cs:108,177 | derived from ListView.Font | low |
| Controls\IonTypeSelectorControl.cs:184,189 | derived | low |
| Controls\FindResultsForm.cs:85,102,182 | derived | low |
| Util\TextRendererHelper.cs:32 | SystemFonts default, overwritten by callers | low |
| Util\AxisLabelScaler.cs:103 | ZedGraph point sizing, measurement-driven | low |
| FileUI\InsertTransitionListDlg.cs:46,69 | relative *2 / /2 | low |
| FileUI\ImportTransitionListColumnSelectDlg.cs:1614,1698 | derived from grid font | low |
| FileUI\WatersConnectSaveMethodFileDialog.cs:90-111 | derived from actionButton.Font | low |
| Alerts\MsFraggerDownloadDlg.cs:75,93 | derived from rtb.SelectionFont | low |
| SettingsUI\EditPeakScoringModelDlg.cs:970 | derived | low |
| EditUI\EditPepModsDlg.cs:547 | preserves SizeInPoints | low |

## 2. Hardcoded row/item metrics

| Site | Description | Risk |
|---|---|---|
| Controls\TreeViewMS.cs:52 | `DEFAULT_ITEM_HEIGHT = 16` raw px | high |
| Controls\TreeViewMS.cs:68 | ItemHeight = 16 in ctor, every TreeViewMS | high |
| Controls\TreeViewMS.cs:325 | ItemHeight = 16 * TextZoom - TextZoom is the only scale; at 150% rows stay 16px, text clips | high |
| Controls\TreeViewMS.cs:43,45,47 | HORZ_DASH_LENGTH=11, PADDING=3, IMG_WIDTH=16 consumed by owner-draw | high |
| Controls\SequenceTreeForm.Designer.cs:49 | sequenceTree.ItemHeight=16 (ItemHeight NOT font-autoscaled) | high |
| Controls\FilesTree\FilesTreeForm.Designer.cs:63 | filesTree.ItemHeight=16 | high |
| Controls\GroupComparison\VolcanoPlotFormattingDlg.cs:242,249 | font-derived (+4px pad) - mostly correct idiom | low |
| Controls\UndoRedoList.cs:36 | TOTAL_BORDER_WIDTH=2, mostly font-derived | low |
| SettingsUI\ViewLibraryDlg.cs:71 | PADDING=3 in owner-drawn peptide list (:1298) | medium |
| SettingsUI\PeptideSettingsUI.cs:50 | BORDER_BOTTOM_HEIGHT=16 for combo growth (:1930,:1944) | medium |
| FileUI\ExportMethodDlg.cs:62 | RADIO_BUTTON_SHIFT_WC_HIDDEN=11 applied :1980-2001 | medium |
| Controls\Graphs\ChromGraphItem.cs:55-56 | peak-boundary px minimums | low |
| Controls\Graphs\CursorTrackingTip.cs:35-38 | CURSOR_OFFSET 15, PADDING 3 | low |
| Controls\NodeTip.cs:124,332-333 | tooltip table metrics 5/2/6 | low |
| Controls\PopupPickList.cs:510-512 | MARGIN_*=1 | low |
| Controls\SeqNode\SrmTreeNode.cs:58 | ANNOTATION_WIDTH=5, zoomFactor only (:248-257), no DPI | medium |
| Controls\SequenceTree.cs:1304 / FilesTree.cs:593 | edit box MinimumWidth=80 | medium |

## 3. Runtime `new ImageList` (no ImageSize set anywhere in tree)

| Site | Description | Risk |
|---|---|---|
| Controls\SequenceTree.cs:145 | node ImageList, 30 icons, 16x16 forever | high |
| Controls\SequenceTree.cs:181 | StateImageList, 4 peak-state icons | high |
| Controls\FilesTree\FilesTree.cs:78 | 17 icons; comment ":77 // Icons size is 16x16" | high |
| Controls\StatementCompletionTextBox.cs:47 | autocomplete icons; cell scales (dxIcon=bounds.Height) but bitmap doesn't | medium |
| FileUI\PublishDocumentDlgBase.cs:51 | Panorama/Ardia folder tree | medium |

## 4. Owner-drawn measure/paint mixing measured text with px literals

| Site | Description | Risk |
|---|---|---|
| Controls\TreeViewMS.cs:354-379 | whole tree hand-painted (UserPaint, OnPaint override) | high |
| Controls\TreeViewMS.cs:589-667 | DrawNodeCustom: dash rect 11x1, 1px rules, DrawImageUnscaled(img,x,y,16,16) :653/:657/:663 | high |
| Controls\TreeViewMS.cs:564-577,583 | XIndent = 11+3(+16[+16]); HorizScrollDiff +11 | high |
| Controls\TreeViewMS.cs:539-548 | EnsureWidthCustom caches width keyed on TextZoom only - no DPI in key | high |
| Controls\SeqNode\PeptideTreeNode.cs:395-444 | measurement-driven but rides 16px ItemHeight | medium |
| Controls\SeqNode\SrmTreeNode.cs:182-229 | color swatch: imgWidth=16, Rectangle(rightEdge-2,top,23,16), (rightEdge,top,14,13) all literals | high |
| Controls\SeqNode\SrmTreeNode.cs:243-260 | annotation triangle 5+zoomFactor | medium |
| Controls\FilesTree\FilesTreeNode.cs:174-204 | DrawFocus yOffset=1, pen 2px | low |
| Controls\StatementCompletionForm.cs:57-104 | ResizeToIdealSize: dxIcon=32, +=16, dyPadding=2 | high |
| Controls\StatementCompletionForm.cs:120-153 | DrawItem: dxIcon=bounds.Height good; TitleWidth from literals above | medium |
| Controls\ImageListBox.cs:268-292 | OwnerDrawFixed; 16px imageList.Draw, no centering | medium |
| Controls\PopupPickList.cs:515-560 | DPI-aware GetGlyphSize mixed with 1px margins + DrawImageUnscaled stretched | medium |
| SettingsUI\ViewLibraryDlg.cs:1268-1315 | image stretched to bounds.Height; PADDING 3 | medium |
| Controls\FindResultsForm.cs:141-195 | measured highlighting, no raw offsets | low |
| Controls\GroupComparison\VolcanoPlotFormattingDlg.cs:257-270 | DrawText into e.Bounds | low |
| Controls\Graphs\FileProgressControl.cs:301-320 | 1px border relative | low |
| Controls\NodeTip.cs / CustomTip.cs | tip painting; CustomTip default Size(200,100) | low |
| Controls\SeqNode\PeptideGroupTreeNode.cs:307-475 | MeasureString-driven wrap; -4/+2 literals | low |

## 5. Persisted geometry + restore sites

Settings (Properties\Settings.settings / .Designer.cs): MainWindowLocation/Size,
ViewLibraryLocation/Size, AllChromatogramsLocation/Size, StartPageSize
(default 872,648 - only non-zero px default), StartPageLocation,
ViewLibrarySplitMainDist (raw px int), ViewLibrarySplitPropsDist
(FRACTION 0.33 - the DPI-safe model idiom).

| Site | Description | Risk |
|---|---|---|
| Controls\Startup\StartPage.cs:70-81 | restores px Size verbatim (before InitializeComponent) | high |
| Controls\Startup\StartPage.cs:450,458 | saves raw device px | high |
| Skyline.cs:230-244 | main window Size/Location restore + ForceOnScreen | high |
| Skyline.cs:4188,4196 | Move/Resize persist raw px | high |
| SettingsUI\ViewLibraryDlg.cs:182-196,356-358 | Size/Location + SplitterDistance raw px both ways | high |
| Controls\Graphs\AllChromatogramsGraph.cs:84-92 | Location restore | medium |
| Controls\Graphs\MsGraphExtension.cs:154-164 | splitter as fraction of Width - CORRECT PATTERN TO COPY | low |
| Util\FormEx.cs:232-244 | ForceOnScreen clamps, cannot un-shrink | medium |
| SkylineFiles.cs:1469 / SkylineGraphs.cs:533 | dockPanel Save/LoadFromXml - DigitalRune layout persists pane sizes in device px (user layout + every .sky.view); nothing rescales on load. Highest blast radius | high |
| Util\FormGroup.cs:81-103 | 600x440 px floor for new floating windows | medium |
| SkylineGraphs.cs:3853 | Audit Log float min 800 | medium |
| Controls\Databinding\DataboundGridControl.cs:1341-1364 | splitter from grid metrics - self-scaling | low |
| Controls\Graphs\GraphSummary.cs:325-342 | splitter = Toolbar.Height - derived | low |

## 6. Resize/layout handlers with manual pixel arithmetic (42 sites)

High: StartPage.cs:428-453,421-426,151-167 (+RecentFileControl 225x20 labels);
FullScanSettingsControl.cs:1052-1218 (165-line runtime re-layout);
ImportTransitionListColumnSelectDlg.cs:787-823 (combo overlay pixel-aligned
to grid columns); TransitionSettingsUI.cs:179-192,245-266 (literal
Size(363,491) + pixelShift moves); ImportFastaControl.cs:57,92-110;
DiannSearchDlg.cs:116-131; DataboundGridControl.cs:855-975,1426 (dendrogram
bounds, magic 3.5); CreateMatchExpressionDlg.cs:72-73 (fully hardcoded grid
Location/Size); EditListDlg.cs:322-323 (form.Width=350/Height=130);
KeyValueGridDlg.cs:142-149; SequenceTree.cs:1299-1307 and
FilesTree.cs:588-602 (edit box off 16px BoundsMS; FilesTree MeasureText
Size(_editTextBox.Height, maxWidth) args LOOK TRANSPOSED - latent bug).

Medium: ExportMethodDlg.cs:239-256,779,802; wizard pageControl placements
(ImportPeptideSearchDlg.cs:252, DiannSearchDlg.cs:721, EncyclopeDiaSearchDlg.cs:234);
SequenceTreeForm.cs:134-143; RunToRunRegressionToolbar.cs:108-111;
FindResultsForm.cs:221-245; PeptideSettingsUI.cs:297,1930,1944;
EditCustomMoleculeDlg.cs:184-283; EditMeasuredIonDlg.cs:50;
EditFragmentLossDlg.cs:50; SearchSettingsControl.cs:72-76;
BuildPeptideSearchLibraryControl.cs:595-596; Irt graph 800x600 x3;
SimpleFileDownloaderDlg.cs; DetailedReportErrorDlg.cs:69-85.

Low: resize handlers that only delegate to ZedGraph AxisChange/Invalidate;
IonTypeSelectorControl AlignColumns (measure-then-size, correct);
LongOperationRunner centering; sibling-copy layouts.

## 7. Existing DPI compensation (idioms to follow)

- Util\ScreenCapture.cs:151-160 GetScalingFactor - only real DPI query
  (desktop-level, used for screenshots, not layout).
- MsGraphExtension splitter-as-fraction - best persistence pattern.
- TextZoom (TreeViewMS.cs:55-57,323-327) - the app's only UI scaling
  mechanism; natural insertion point for a DPI factor on ItemHeight,
  IMG_WIDTH, HORZ_DASH_LENGTH, PADDING, ANNOTATION_WIDTH.
- Measure-then-size sites; SystemInformation scrollbar metrics.
- Absent everywhere: DeviceDpi, Graphics.DpiX/DpiY, LogicalToDeviceUnits,
  AutoScaleFactor, ScaleControl, OnDpiChangedAfterParent.

## Counts

| Category | Hits | high/med/low |
|---|---|---|
| Runtime new Font | 30 | 2/4/24 |
| Row/item metrics | 20 | 7/8/5 |
| ImageList | 5 | 3/2/0 |
| Owner-draw | 18 | 6/6/6 |
| Persisted geometry | 10 settings + 17 sites | 8/5/4 |
| Resize handlers | 42 | 14/17/11 |
| Total | ~132 | ~40 high |

## Top 10 highest-risk

1. TreeViewMS ItemHeight=16 + 8.25pt*TextZoom font override (fixes FilesTree too)
2. TreeViewMS owner-draw pipeline (11/3/16 constants, DrawImageUnscaled 16x16)
3. Three tree ImageLists without ImageSize
4. Start Page package (persisted px size, resize literals, 225px labels)
5. DigitalRune dockPanel Save/LoadFromXml px persistence (user layout + .sky.view) - highest blast radius
6. FullScanSettingsControl 165-line runtime re-layout
7. ImportTransitionListColumnSelectDlg combo overlay pixel-aligned to grid
8. TransitionSettingsUI literal Size(363,491) + pixelShift arithmetic
9. Main window + ViewLibraryDlg raw Size/Location/SplitterDistance persistence
10. SrmTreeNode color swatch literals + tree label-edit box off 16px bounds
    (FilesTree MeasureText transposed-args latent bug)
