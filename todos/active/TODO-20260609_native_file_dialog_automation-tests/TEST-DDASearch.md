# TEST — DDA Search for MS1 Filtering (DDASearch)

## Run context
- Branch / PR: native_file_dialog_automation (PR #4313)
- Skyline: Release 26.1.1.203 (b818b91b4), connected PID 31792
- Date: 2026-07-22
- Data folder: `D:\Downloads\Tutorials\DdaSearchMs1Filtering\DdaSearchMS1Filtering\`
- UI mode: proteomic
- Driver: night-session per-tutorial agent (orchestrator PID 31792)

Status: CLAIMED by nickshulman@DESKTOP 2026-07-22

## Screenshot checklist
| Screenshot | Section | Status | Note |
|-----------|---------|--------|------|
| s-01 | Getting Started (Peptide Settings) | PASS* | Internal standard=none, Carbamidomethyl(C) checked; extra pre-defined mods in lists (environmental) |
| s-02 | Wizard: Select Files to Search | PASS | exact |
| s-03 | Wizard: 3 mz5 files added | PASS | exact |
| s-04 | Wizard: Import Results (remove prefix) | PASS | exact |
| s-05 | Wizard: Add Modifications (initial) | DIVERGENCE* | extra pre-defined mods in list (environmental); only Carbamidomethyl(C) checked (correct) |
| s-06 | Edit Isotope Modification (K) | BLOCKED | Edit modifications dropdown unreachable via MCP (Finding #1) |
| s-07 | Edit Isotope Modification (R) | BLOCKED | same as s-06 |
| s-08 | Wizard: Add Modifications (complete) | PASS* | correct 4 mods checked; extra unchecked env entries |
| s-09 | Wizard: Configure Full-Scan Settings | PASS | Mass Accuracy=20; header text renamed (cosmetic) |
| s-10 | Wizard: Import FASTA | PASS | FASTA loaded via Browse (native dialog); path prefix differs (folder) |

## Progress log

### Getting Started
- UI mode set to proteomic. Data folder confirmed: 3 mz5 files + 2014_01_HUMAN_UPS.fasta present.
- Window hygiene: attempted to close a stale floating Document Grid ("Tailing Review") via View > Live Reports > Document Grid toggle x2 — did NOT close (stale floating instance persists from prior session). Immediate Window docked bottom. Noted; only affects screenshot fidelity. Finding #H.
- Settings > Default → answered No to save prompt (MultiButtonMsgDlg). OK.
- Settings > Peptide Settings → Modifications tab → Internal standard type = none. OK.
- **s-01**: PASS with cosmetic divergence. Live Peptide Settings/Modifications matches reference: only Carbamidomethyl (C) checked in structural, Internal standard type = none. DIVERGENCE (environmental): global modification lists contain extra pre-defined entries (Carbamidomethyl Cysteine, Phospho (Y), Phospho (S,T), Label:13C(6)15N(2), Label:13C(6)15N(4), Label:13C(6), Heavy K, 13C, 13C K) not present in the fresh-install reference. `Settings > Default` resets document settings but not the persistent global mod definitions. Checked/selected states are correct.

### Wizard — Building the Spectral Library (Select Files)
- Saved doc to `...\DdaSearchMS1FilteringTutorial.sky` via File > Save (native Save As dialog, set full path, dismiss_with_accept_button). OK.
- File > Search > Run Peptide Search → ImportPeptideSearchDlg opened on "Select Files to Search" page.
- **s-02**: PASS exact. Workflow defaults to "DDA with MS1 filtering".
- Add Files button is NESTED inside BuildPeptideSearchLibraryControl — NOT surfaced by get_controls (only top-level controls listed). Had to `get_children type=BuildPeptideSearchLibraryControl` then click by returned path. Finding #A (nested-control discoverability).
- OpenDataSourceDialog (Skyline's own, IsNative=False): set Source name = folder path + click Open to navigate in; then per-item `select_item` on ListView for each of 3 mz5 files (additive — Source name reflected all 3 quoted). Clicked Open. Files added.
- **s-03**: PASS exact — all 3 mz5 files in "Files to search" grid.
- Next → **s-04** Import Results (remove shared prefix `QE_140221_0` / suffix `spiked`, replicate names `1_UPS1_100fmol` etc). PASS exact. dismiss_with_accept_button (OK).

### Wizard — Add Modifications page (s-05..s-08)
- **s-05**: DIVERGENCE (environmental). Reference list = only "Carbamidomethyl (C) = C[57] (fixed)" checked. Live list contains ~13 entries (13C, 13C K/L/R/V, Carbamidomethyl (C) [checked], Carbamidomethyl Cysteine, Heavy K, Label:13C(6), Label:13C(6)15N(2) (C-term K), Label:13C(6)15N(4) (C-term R), Phospho (S,T), Phospho (Y)) — leftover GLOBAL mod definitions. Carbamidomethyl (C) correctly checked. Note: the two heavy SILAC mods the tutorial asks to CREATE already exist in this environment; Oxidation (M) does NOT.
- **Edit modifications button — BLOCKED (MCP capability gap; Finding #1).** The button (btnAddModification, nested in MatchModificationsControl) shows a ContextMenuStrip programmatically on click with items "Edit structural modifications" / "Edit heavy modifications". Could NOT reach those items via any of:
  1. `click_control_menu_item(control="Edit modifications", menuPath="Edit heavy modifications")` → "&Edit modifications has no context menu".
  2. `get_children path={...button..., type:ContextMenu}` → "has no context menu".
  3. click button then `click label="Edit heavy modifications"` → "No control found matching the path".
  `get_children` on the button returns `[]`; `get_actions` lists only click/get_children/get_value. So s-06 and s-07 (Edit Isotope Modification dialogs) could NOT be captured via the wizard path. This blocks faithful in-wizard modification CREATION.
- Workaround to complete the tutorial: check the two pre-existing heavy mods directly in the list; define Oxidation (M) via settings-list API + refresh page; then check it.
- Checked both heavy mods via `check_item` on the nested CheckedListBox (needs FULL path incl. MatchModificationsControl parent — bare type=CheckedListBox fails).
- Oxidation (M) not present. `skyline_add_settings_list_item` StaticModList `<StaticMod name="Oxidation (M)" aminoacid="M" variable="true" formula="O" unimod_id="35" short_name="Oxi"/>` → added. List did NOT live-refresh; clicked `< Back` then `Next >` (re-triggered ImportResultsNameDlg → OK) to rebuild the page — Oxidation (M) then appeared BUT the Back/Next reset all prior checkboxes to default (only Carbamidomethyl C). Re-checked all 3 (2 heavy + Oxidation M).
- **s-08**: PASS (functional). Checked set = exactly {Carbamidomethyl (C), Label:13C(6)15N(2) (C-term K), Label:13C(6)15N(4) (C-term R), Oxidation (M)} matching the reference. Divergence: extra UNCHECKED environmental entries remain visible. s-06/s-07 (Edit Isotope Modification dialog) NOT captured — blocked by Finding #1.

### Wizard — Full-Scan, FASTA, Search Settings (s-09..s-11)
- Next → **Configure Full-Scan** page. Set Mass Accuracy 10→20 via set_value on nested FullScanSettingsControl>Mass Accuracy TextBox. **s-09 PASS** (defaults: charges 2, isotope peaks Count, Peaks 3, Centroided, Use only scans within 5 min). Cosmetic: live header "Configure Full-Scan Chromatogram Extraction" vs reference "Configure Full-Scan Settings" (version text drift — Finding #C tutorial-text).
- Next → **Import FASTA** page. Browse (nested ImportFastaControl>Browse) → native "Open FASTA" dialog; set full path, dismiss_with_accept_button. **s-10 PASS** (Trypsin [KR | P], 0 missed cleavages).

## Findings & fix suggestions
(to be filled)

## Final status
(to be filled)
