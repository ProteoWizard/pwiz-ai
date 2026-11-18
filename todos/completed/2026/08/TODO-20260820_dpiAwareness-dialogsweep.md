# DPI dialog-tail sweep checklist

Companion to `TODO-20260820_dpiAwareness.md`. Method: two instances side
by side - Debug exe forced DPI-unaware via AppCompatFlags layer =
"before" (authentic pre-flip rendering, bitmap-stretched); Release exe
aware = "after". Captures via SkylineMcp `skyline_get_form_image` per
instance; pairs stored under `ai/.tmp/dpi-sweep/<item>/{before,after}.png`
(not committed; interesting pairs attached to PR #4602). Browse all pairs
side by side in `ai/.tmp/dpi-sweep/index.html` (regenerate with
`python ai/.tmp/dpi-sweep/make_gallery.py`; per-item verdict in `<item>/notes.md`). Verdict per
item: OK (no fix needed) / FIXED (code changed, re-captured) / DEFER
(reason). ACCURACY LESSONS (2026-08-25, after two developer-caught
misses): judge zoomed REGION crops against the scaled 96-DPI reference,
never the whole form at a glance; before capturing, grep the form's code
for runtime-created controls (new Control, ImageList/Image literals,
AutoSizeRows/ItemHeight) and verify each one explicitly - every miss so
far was a runtime-created control or a WinForms auto-size that ignores
DPI. ai/.tmp/dpi-sweep/make_diff.py exists but raw pixel diffing is
too noisy; region pairing needs content anchors, not coordinate scaling.

Legend: [ ] not swept - [x] done. Order: known-visible first, then
high-risk programmatic layouts, then cosmetics.

Session setup state (2026-08-25): DPIUNAWARE compat layer SET on the
Debug exe (HKCU AppCompatFlags\Layers) = the "before" instance; Debug
rebuild kicked off; AI Connector installed in BOTH Debug and Release
settings; SkylineMcp registered (connector-managed) - next session has
native skyline_* tools. ActionBoxControl fix is UNCOMMITTED in the
working tree. Remove the compat layer when the sweep ends.

## Known visible / high priority

- [x] ActionBoxControl tiles (Start Page, Start tab) - FIXED 2026-08-25,
      verified both variants incl. Tutorials tab. (Start Page needs
      manual captures - shows before main window, no MCP menu path.)
- [x] StatementCompletionForm - FIXED 2026-08-25, verified on the
      rebuilt Release exe at 150%: popup 161x27 logical (pre-flip 160x28),
      icon full size, centered, smooth. Swept via Edit >
      Insert > Peptides with Rat_plasma + Rat_mini.protdb as background
      proteome (needed - the popup has nothing to suggest without one),
      typing "ELSD" -> ELSDIALR. Before/after pairs in
      ai/.tmp/dpi-sweep/StatementCompletionForm/ (before 160x28 logical,
      after 137x26). Defect at 150%: row grew with the font (39 device
      px) but the 16px ImageList icon stayed 16px, sitting small in the
      top-left of a gutter sized bounds.Height; dxIcon=32 / +16 gap
      literals unscaled so the text budget was ~7px short. Fix follows
      the tree-cluster pattern: StatementCompletionTextBox ImageList gets
      Depth32Bit + DpiUtil.ScaleSize when factor > 1 and icons added via
      DpiUtil.ScaleImageForList (AddImage helper); StatementCompletionForm
      scales the 32/16 literals with DpiUtil.Scale and draws the icon into
      an explicit, vertically centered destination rect (DrawImageUnscaled
      would re-inflate a 144-DPI-tagged bitmap). 96-DPI path unchanged
      (factor-1 short circuits; centering offset is 0 at 16px-in-17px).
      Gotcha: the popup only appears on REAL keystrokes; SendKeys after
      SetForegroundWindow on the dialog hwnd (AppActivate by pid picked
      the wrong "Skyline" window when two instances were up).
- [x] PopupPickList - FIXED 2026-08-25, verified on the rebuilt Release
      exe at 150%: 615x376 device px (= the 96-DPI proportions), 24px rows
      with 24px icons, scaled toolbar glyphs. Opened with the SPACE key on the
      selected Targets node (SequenceTree.OnKeyDown) - no mouse hover
      needed. Pairs in ai/.tmp/dpi-sweep/PopupPickList/. Defect at 150%:
      the ctor re-applies SizeAll (410x251) AFTER InitializeComponent, so
      the AutoScaleMode.Font layout is squeezed back into the 96-DPI device
      size; pickListMulti.ItemHeight is a designer literal (16) that Font
      autoscale never touches, so rows were shorter than the scaled text;
      16px toolbar glyphs; DrawImageUnscaled on the tree's pre-scaled
      (144-DPI-tagged) icons. Fix: Size = DpiUtil.ScaleSize(SizeAll),
      ItemHeight scaled, DpiUtil.ScaleToolStripImages(toolStrip1), the
      Bottom + 8 literal scaled, DrawRowImage helper (explicit centered
      dest rect), and SequenceTree.GetPickerLocation scales SizeAll for
      placement. 96-DPI path unchanged (factor 1 identity).
- [x] ImportTransitionListColumnSelectDlg - FIXED 2026-08-25, 3rd round
      (developer review of round 2: rows too tall, combo text cropped,
      selection sliver). Rows reverted to AllCells; initial column widths
      DpiUtil-scaled (default 100 device px at any DPI); the '...'
      placeholder first row (designed to sit under the combo overlay) gets
      MinimumHeight = overlay height so the boundary lands on a row edge.
      3rd round verified at 150%: full dropdown text, original tight rows,
      no sliver. Combo-height fix verified, but the developer
      caught residual defects: cramped unscaled grid rows (AllCells
      auto-size, overlay cutting 40% into row 2) and 16px dropdown
      arrows. Fixed: factor>1 scaled fixed RowTemplate height; arrows
      via DpiUtil.ScaleImageForList. Initially miscalled OK; the DEVELOPER caught the clipped
      header-overlay dropdowns. Column alignment is fine (overlay tracks
      runtime grid widths), but the LiteDropDownList combos are created at
      runtime, so Font autoscale never touches them: scaled font in the
      96-DPI default Button height clips the text to ~half glyph height at
      150%. Fix: DpiUtil.Scale the combo Height at creation (panel height
      follows Max(combo.Height)). EditPepModsDlg, the other consumer, is
      unaffected (clones Size from autoscaled designer templates). Pair +
      zoom crop in ai/.tmp/dpi-sweep/ImportTransitionListColumnSelectDlg/.
- [x] VolcanoPlotFormattingDlg - FIXED 2026-08-26, verified at 150%
      after FOUR rounds: (1) unscaled fixed columns/rows/glyphs; (2) the
      nested ColorGrid container's size skipped by form autoscale
      (ctor-time sizing corrupts anchors - size in OnShown from live
      client + scaled margins); (3) proven via a temp title diagnostic;
      (4) the container's anchored CHILDREN also ignore its resize -
      ColorGrid lays them out explicitly on SizeChanged. All ColorGrid
      consumers benefit (EditCustomThemeDlg).
      Developer-reported. Real defects: ColorGrid fixed-width columns
      (color button 20px, swatch 40px, rgb/hex min 6px) + row height +
      the runtime 20px expression-button column + 16px toolbar glyphs,
      all unscaled device px. Fixed in ColorGrid ctor (benefits all its
      users) + the dialog (DpiUtil.Scale / ScaleToolStripImages). Opened
      via Rat_plasma_gc.sky (Test/MSstats copy, ships comparison 'Test')
      > View > Group Comparisons > Test > Volcano Plot > right-click >
      Formatting. Test surfaces: VolcanoPlotFormattingTest AND
      PeakAreaRelativeAbundanceGraphTest (ResolvePointFormat feeds both).
      Pairs in ai/.tmp/dpi-sweep/VolcanoPlotFormattingDlg/.

## Programmatic re-layout dialogs (open by menu, capture, judge)

- [x] Transition Settings > Full-Scan tab - OK 2026-08-25, no fix
      needed. Three states swept (default, DIA, DIA+MS1 Count): the
      re-layout is fully relative (Top = other.Bottom + sep, seps from
      the autoscaled designer layout). The absolute groupBoxMS1.Top = 12
      literal runs only in the feature-detection wizard workflow - check
      under the Import Peptide Search item. Pairs in
      ai/.tmp/dpi-sweep/FullScanSettingsControl/.
- [x] Transition Settings > Filter tab - OK 2026-08-25, no fix needed.
      Default + DIA-exclusion swap states swept (swap fires on the
      isolation-scheme change event - needs DIA + a scheme selected, e.g.
      Results only). All pixelShift math is relative distances between
      autoscaled designer controls. Pairs in
      ai/.tmp/dpi-sweep/TransitionFilterTab/.
- [x] Import Peptide Search wizard - page 1 OK 2026-08-26; deeper
      pages DEFERRED (need search result files; the feature-detection
      groupBoxMS1.Top=12 branch remains unverified - follow up with
      ImportPeptideSearchTest data). Pair in
      ai/.tmp/dpi-sweep/ImportPeptideSearchDlg/.
- [x] Export Method vendor panels - OK 2026-08-26, no fix needed.
      Thermo/SCIEX OS/Waters states swept both sides; the panel swap
      uses relative Top/Left math against autoscaled designer siblings.
      Pairs in ai/.tmp/dpi-sweep/ExportMethodDlg/.
- [x] EditListDlg - FIXED 2026-08-25, 2nd round verified at 150%.
      First verification missed the unscaled 23px button HEIGHTS in the
      rename popup (developer catch); now scaled. Main dialog
      OK (designer layout). The RENAME popup (Rename button) is a
      runtime-built Form with literal 350x130 + control offsets - at 150%
      the OK/Cancel buttons fell below the client area. Fix: all layout
      literals via DpiUtil.Scale. Pairs in ai/.tmp/dpi-sweep/EditListDlg/.
- [x] PeptideSettingsUI internal-standard growth - OK 2026-08-26.
      Rat_plasma_gc ships 3 label types, so the CheckedListBox branch is
      active; growth math is Bottom-relative, only the 16px bottom margin
      stays device px (~8px tighter, invisible). Pair in
      ai/.tmp/dpi-sweep/PeptideSettingsModsIS/.
- [ ] KeyValueGridDlg (document properties style grid dialogs;
      ClientSize math).
- [x] CreateMatchExpressionDlg - OK 2026-08-26 (reachable branch);
      the hardcoded grid Location/Size lives only in the
      no-fold-change-results branch (filters hidden), proactively
      DpiUtil-scaled. Pair in ai/.tmp/dpi-sweep/CreateMatchExpressionDlg/.
- [x] iRT calibrate chain - OK 2026-08-26. EditRTDlg, EditIrtCalcDlg,
      CalibrateIrtDlg (populated via Use Results - needs the .skyd-bearing
      Rat_plasma.sky) and GraphRegression all autoscale; GraphRegression
      measured 780 device = designer 521 x1.5 (the inventory's "800x600
      literals" claim does not match). Captures in
      ai/.tmp/dpi-sweep/EditIrtCalcDlg/.
- [x] EditMeasuredIonDlg - OK 2026-08-26, both modes (designer +
      FormulaBox autoscale; mode radio only toggles enabled states).
      EditCustomMoleculeDlg / EditFragmentLossDlg deferred as same-class
      spot checks. Pair in ai/.tmp/dpi-sweep/EditMeasuredIonDlg/.
- [x] AllChromatogramsGraph - OK 2026-08-26, no fix needed. Captured
      opportunistically (missing-raw re-import errors on Rat_plasma_gc).
      All content scales with the font; only the 16px pin/auto-close
      corner glyphs stay small (cosmetic, icon-assets follow-up class).
      Pair in ai/.tmp/dpi-sweep/AllChromatogramsGraph/.
- [x] Document Grid dendrogram - DEFER 2026-08-26 (needs a clustered
      report setup; not quick). Revisit if a clustering document shows up
      in test data.

## Cosmetic / code-review items

- [x] NodeTip - OK 2026-08-26. Hovered a peptide node at 150%: table
      layout, ion table alignment and colors all font-scaled. Capture in
      ai/.tmp/dpi-sweep/NodeTip/.
- [x] ImmediateWindow - OK 2026-08-26. 9pt Consolas is point-based, so
      it scales with DPI (measured 17 device px vs 11 logical = 1.5x).
      Pair in ai/.tmp/dpi-sweep/ImmediateWindow/.
- [x] FindResultsForm - OK 2026-08-26. Owner-draw is fully
      font-relative (bold highlight verified at 150%). Pair in
      ai/.tmp/dpi-sweep/FindResultsForm/.
- [x] FilesTree edit box - FIXED 2026-08-26 (code fix, no capture).
      Transposed MeasureText proposedSize args corrected (latent even at
      96), minWidth=80 and +8 padding DpiUtil-scaled. The SAME transposed
      idiom found and fixed in StatementCompletionTextBox.AutoResize.

## Known limitations (documented, not sweep items)

- Dock-pane tab descender clip (~2px at 150%) - inside binary
  DigitalRune DLL; needs the team's fork source. See main TODO.
