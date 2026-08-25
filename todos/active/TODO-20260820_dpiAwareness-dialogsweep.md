# DPI dialog-tail sweep checklist

Companion to `TODO-20260820_dpiAwareness.md`. Method: two instances side
by side - Debug exe forced DPI-unaware via AppCompatFlags layer =
"before" (authentic pre-flip rendering, bitmap-stretched); Release exe
aware = "after". Captures via SkylineMcp `skyline_get_form_image` per
instance; pairs stored under `ai/.tmp/dpi-sweep/<item>/{before,after}.png`
(not committed; interesting pairs attached to PR #4602). Verdict per
item: OK (no fix needed) / FIXED (code changed, re-captured) / DEFER
(reason).

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
- [ ] StatementCompletionForm - autocomplete popup during peptide edit
      in Targets tree (Edit > Insert > Peptides, type partial). Fixed
      dxIcon=32/dxItem+=16 literals + 16px ImageList.
- [ ] PopupPickList - tree node picker (click picker button on a
      precursor node; needs a document, e.g. Rat_plasma). 16px margins,
      DrawImageUnscaled stretch.
- [ ] ImportTransitionListColumnSelectDlg - combo overlay alignment over
      grid columns (Edit > Insert > Transition List, paste sample rows).
      Pixel-exact overlay math.

## Programmatic re-layout dialogs (open by menu, capture, judge)

- [ ] Transition Settings > Full-Scan tab (FullScanSettingsControl
      165-line re-layout): "Settings > Transition Settings", select
      Full-Scan; also flip acquisition method to exercise re-layout.
- [ ] Transition Settings > Filter tab (pixelShift moves on isolation
      scheme changes).
- [ ] Import Peptide Search wizard pages (File > Import > Peptide
      Search; FullScanSettingsControl embedded + wizard page placement).
- [ ] Export Method vendor panels (File > Export > Method; switch
      instrument types - panelThermoRt/panelWaters/panelAbiSciexOS
      relative Top/Left math).
- [ ] EditListDlg (Settings > Peptide Settings > Modifications >
      Edit list): hardcoded form.Width=350/Height=130 growth.
- [ ] PeptideSettingsUI Modifications internal-standard combo growth
      (BORDER_BOTTOM_HEIGHT=16 math; add several isotope label types).
- [ ] KeyValueGridDlg (document properties style grid dialogs;
      ClientSize math).
- [ ] CreateMatchExpressionDlg (View > Volcano Plot > formatting >
      match expression; fully hardcoded grid Location/Size).
- [ ] Irt calibrate/add-peptides graphs (Settings > Peptide Settings >
      Prediction > iRT calculator edit; 800x600 literals - now scaled
      floors? no - raw literals, judge at 150%).
- [ ] EditCustomMoleculeDlg / EditMeasuredIonDlg / EditFragmentLossDlg
      (small-molecule + settings editors with runtime controls at
      literal offsets).
- [ ] AllChromatogramsGraph (import progress window - open any raw
      import; location restore + layout).
- [ ] Document Grid dendrogram (View > Document Grid + clustering;
      needs clustered report - DEFER unless quick).

## Cosmetic / code-review items

- [ ] NodeTip/CustomTip hover tooltips (hover a peptide node; capture
      via physical screenshot - tooltips are not forms).
- [ ] ImmediateWindow fixed 9pt Consolas (View > Immediate Window).
- [ ] FindResultsForm (Edit > Find All; measured-text drawing).
- [ ] FilesTree edit box MinimumWidth + transposed MeasureText args
      (code fix, no capture; latent bug even at 96 DPI).

## Known limitations (documented, not sweep items)

- Dock-pane tab descender clip (~2px at 150%) - inside binary
  DigitalRune DLL; needs the team's fork source. See main TODO.
