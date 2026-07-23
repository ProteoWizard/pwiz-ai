# TEST — Existing & Quantitative Experiments (ExistingQuant)

**Status: WIP — driven by nickshulman@nicksh9 (night-session sub-agent), 2026-07-22**

## Run context

- **Branch / PR:** `Skyline/work/20260609_native_file_dialog_automation` — PR #4313
- **Skyline:** `Skyline (64-bit : developer build) 26.1.1.203 (b818b91b4)`
- **Connected PID:** 31792
- **Date:** 2026-07-22 (night session)
- **Data folder:** `D:\Downloads\Tutorials\ExistingQuant\` (MRMer + Study 7 subfolders)
- **UI mode:** proteomic
- **Driver:** autonomous night-session sub-agent (orchestrator-spawned), one shared Skyline (PID 31792).

## Environment notes

- All WinForms modal dialogs capture as **solid cyan** (GroupedStudies Finding #2 reproduced). Retried s-01 twice, still cyan even after closing leftover floating windows. Dialog fidelity is therefore verified **functionally** (get_controls / get_value / get_options / document settings XML) and against the reference image; graph captures (get_graph_image) and main-window captures are used where they render.
- Data-file naming mismatch: tutorial says `Yeast_MRMer_mini.blib`; on disk it is **`Yeast_MRMer_min.blib`** (protdb is `Yeast_MRMer_mini.protdb`, matches). Minor.

## Screenshot checklist

| Screenshot | Section | Status | Note |
|-----------|---------|--------|------|
| skyline-blank-document / proteomics-interface / protein-icon | Getting Started | PASS (functional) | Settings>Default→No; UI already proteomic; blank doc confirmed |
| s-01 | Peptide Settings — Library | PASS (functional) | Yeast_mini library checked; Pick peptides matching=Library. Capture cyan; verified via get_options/settings XML |
| s-02 | Peptide Settings — Digestion | PASS (functional) | Background proteome=Yeast_mini committed (settings XML). Capture cyan |
| s-03 | Edit Isotope Modification (C-term K) | BLOCKED→worked around | Could not open isotope "Edit list" (duplicate-button gap, Finding #1). Defined via settings-list XML: K, C-term, 13C+15N, +8 Da |
| s-04 | Edit Isotope Modification (C-term R) | BLOCKED→worked around | Same; R, C-term, 13C+15N, +10 Da. Both committed + active (settings XML confirms) |
| s-05 | Insert Transition List form | DIVERGENCE (method) | Form opened; but its paste box could not be programmatically triggered (Finding #2). Switched to tutorial's alternate method-2 (Edit>Paste direct) |
| s-06 | Import Transition List: Identify Columns | PASS (functional) | Direct paste on Targets tree triggered this form; columns auto-ID'd Peptide Modified Sequence/Precursor m/z/Product m/z; Associate proteins already checked (True); Peptides radio. Capture cyan |
| s-07 | Peptides grouped in proteins | PASS (counts exact) | After OK: **24 prot / 44 pep / 88 prec / 296 tran** — exact match to tutorial. Main-window capture cyan; counts via get_document_status |
| s-08 | MS/MS spectrum, transition highlighted | PASS (graph) | Library Match spectrum renders cleanly via get_graph_image (LTSLNVVAGSDLR: y7 r1, y5 r2, y9 r4...) matching reference. Edit>Expand All>Precursors done |
| s-09 | Import data, Find ETFP (red dot) | PASS (graph) | mzXML imported (1 replicate). ETFPILVEEK chromatogram matches reference EXACTLY (light 602.8266++ ~100k red, heavy 606.8337++ ~380k blue, peak 30.0, interference ~30.4). Tree/status via reference; graph via get_graph_image |
| s-10 | y3 transition / all transitions | PASS (graph) | Light precursor 602.8266++ chromatogram renders; interference double-peak ~29.8/30.0 visible. Navigated via get_locations/set_selection |
| s-11 | Adjust peak boundaries (drag) | BLOCKED | Mouse-drag peak-boundary edit; chromatogram graph exposes only get_actions/get_children/click/get_value — no set-boundary verb. Finding #3 (= MethodEdit #7 / GroupedStudies #1) |
| (Removing Transition Peak — Quantitative) | Removing interference | PARTIAL | Multi-select of 4 transitions (light+heavy y3/y4) worked (set_selection additionalLocators); but tree right-click "Quantitative" not reachable — Targets-tree ContextMenu not enumerable. Finding #4 |
| s-12 | Edit Isotope Modification (13C(6) C-term R) | BLOCKED→worked around | Same duplicate-button gap (Finding #1); defined Label:13C(6) (C-term R) via settings XML. Checked it, unchecked 15N4-R, kept K. |
| s-13 | Study 7 Identify Columns | PASS (functional) | Direct paste of 57-row/6-col Simple list; Skyline auto-mapped precursor m/z, product m/z, **peptide+protein parsed from col D dotted notation**, other cols Ignore. Capture cyan |
| s-14 | Max m/z error | PASS (exact) | On OK: error "product m/z 1519.78 is out of range... Check the Instrument tab" (get_grid_text) — matches tutorial exactly |
| s-15 | Peptide view after paste | PASS (structure exact) | After Max m/z=1800 + re-paste + Collapse All>Peptides: **7 groups/11 pep/19 prec/57 tran**; group+peptide layout (APR/LEP/MYO/MBP×2/PSA×2/HRP/CRP×3) matches reference s-15 exactly |
| s-16 | Edit Isotope Modification (Label:13C on V) | BLOCKED | Edit>Modify Peptide opens; but per-residue "Isotope heavy" dropdowns are caption-less LiteDropDownLists, not uniquely addressable (set_form_value=label-only; get_children=[]). Finding #5 |
| s-17 | Edit Modifications form | BLOCKED | Same as s-16 |
| s-18 | Add heavy precursor via pick list | BLOCKED | Hover drop-arrow + pick-list popup — no MCP verb (tree pop-up pick-list, = MethodEdit #7). 3 V/L peptides stay light-only (19 prec vs tutorial's 22) |

## Progress log

### Getting Started — PASS
- `Settings > Default` → MultiButtonMsgDlg → clicked **No** (don't save). UI mode already `proteomic` (get_ui_mode). Document blank (get_document_status: 0/0/0/0).

### Preparing a Document to Accept a Transition List — PASS (functional; s-03/s-04 worked around)
- **Library (s-01):** `Settings > Peptide Settings` → Library tab (active) → Edit list → Add → Edit Library: set Name="Yeast_mini", Path=`...\MRMer\Yeast_MRMer_min.blib` (set directly by label, avoiding native browse) → OK → OK. Checked "Yeast_mini" in Libraries list (`check_item`). Verified: settings XML shows `<bibliospec_lite_library name="Yeast_mini" ...>`, pick="library". Matches reference s-01.
- **Background proteome (s-02):** Digestion tab → Background proteome combo set to `<Add...>` → Edit Background Proteome: Name="Yeast_mini", Proteome file=`...\MRMer\Yeast_MRMer_mini.protdb` (set directly) → OK. Combo reads "Yeast_mini". Settings XML shows `<background_proteome name="Yeast_mini" ...>`. Matches reference s-02.
- **Isotope modifications (s-03, s-04):** Modifications tab. The isotope "Edit list" button could **not** be clicked — there are TWO buttons both labeled "Edit list" (Structural + Isotope) and `click_form_button`/`perform_action` match only by visible text/label, so `perform_action click "Edit list"` always hits the **Structural** one; internal name `btnEditHeavyMods` is not matchable (`click_form_button` errors "No control matching"). **Finding #1.** Worked around with `skyline_add_settings_list_item` (listType "Isotope Modifications"):
  - `Label:13C(6)15N(2) (C-term K)` — aminoacid K, terminus C, 13C+15N (+8 Da)
  - `Label:13C(6)15N(4) (C-term R)` — aminoacid R, terminus C, 13C+15N (+10 Da)
  - Reopened Peptide Settings → Modifications → both now appear in Isotope modifications list → `check_item` both → verified checked via get_value; Carbamidomethyl (C) confirmed checked in Structural. OK.
- **Committed state (settings XML):** background_proteome Yeast_mini; bibliospec library Yeast_mini; static_modifications Carbamidomethyl (C) + both Label:13C(6)15N(2)(K) and Label:13C(6)15N(4)(R) with correct label_13C/label_15N. Isotope mods active (get_settings_list_selected_items). Section state matches tutorial exactly.

### Inserting a Transition List with Associated Proteins — PASS (counts exact; method diverged)
- Extracted cols A-C (peptide / precursor m/z / product m/z), 296 rows, from the "Fixed" sheet of `silac_1_to_4.xls` via Excel COM; put on clipboard.
- `Edit > Insert > Transition List` opened **Insert Transition List** dlg (s-05). Its textbox "Press Ctrl-V to paste here" processes on a real WM_PASTE; `perform_action paste` set the text but did **not** launch column identification (Finding #2). Cancelled.
- Used the tutorial's documented **alternate method** (Edit > Paste directly): `perform_action paste` on `SequenceTreeForm:Targets` (type SequenceTree) with the 296-row value → launched **Import Transition List: Identify Columns** (s-06). Columns auto-identified: Peptide Modified Sequence, Precursor m/z, Product m/z. **Associate proteins** already ticked (get_value=True). OK.
- Result: **24 proteins / 44 peptides / 88 precursors / 296 transitions** — matches the tutorial's stated counts EXACTLY (s-07). Library Match spectrum renders cleanly (s-08). `Edit > Expand All > Precursors` applied.
- Note: On-demand submenu leaves `View > Libraries > Ion Types > B` and `Charges > 2` (spectrum annotation) not exercised — cosmetic; same class as MethodEdit Finding #2.

### Importing Data (MRMer) — PASS (graphs); manual-refinement steps BLOCKED
- `File > Save As` → native Save dialog → path set directly → `MRMer.sky`. `File > Import > Results` → OK → OpenDataSourceDialog: set Source name to full mzXML path → Open. Import completed: **1 replicate `silac_1_to_4`**, doc 24/44/88/296.
- s-09/s-10: navigated to ETFPILVEEK (`get_locations`/`set_selection`); chromatograms render via `get_graph_image` and match the reference (interference shoulder ~30.4; double peak on light precursor). Individual precursor/transition selection via locators works.
- **Removing a Transition Peak (Quantitative toggle):** multi-selected the 4 interference transitions successfully, but the Targets-tree **right-click "Quantitative"** could not be invoked — `click_control_menu_item` reports the SequenceTree "does not support get_children" for its context menu, and a hand-built ContextMenu path is rejected (needs a real serialized UiElementPath, which the non-enumerable tree can't provide). **Finding #4.** Not applied.
- **Adjusting Peak Boundaries (s-11):** click-drag under the x-axis — no MCP verb (graph actions = get_actions/get_children/click/get_value only). **BLOCKED, Finding #3** (same root gap as MethodEdit #7 / GroupedStudies #1). Downstream: the MRMer precursor total-area ratios that depend on this manual correction (0.24 / 0.27 in the tutorial) are not reproduced; auto-picked ratios remain.
- Data anomaly the tutorial itself calls out (2 peptides YVDPNVLPETESLALVIDR, FPEPGYLEGVK with blank transitions in the mzXML) present as described — not a runner issue.

### Preparing / Pasting the Study 7 Transition List — PASS (structure exact)
- New Document. Study 7 isotope mod `Label:13C(6) (C-term R)` defined via settings XML (duplicate-button gap again). Peptide Settings: checked K+15N2 and 13C(6)-R, unchecked 15N4-R and the Yeast_mini library, Background proteome → None.
- Extracted the "Simple" sheet (57 rows × 6 cols) from `Study7 transition list.xls`. Direct-paste on the tree → Identify Columns: precursor m/z / product m/z auto-detected; **col D `PROT.PEPTIDE.frag.label` parsed into both Protein Name and Peptide** (7 groups); other cols Ignore. (s-13)
- OK → error **"product m/z 1519.78 is out of range… Check the Instrument tab"** (s-14, exact). Cancel; Transition Settings > Instrument > Max m/z=1800; re-paste; OK. Collapse All > Peptides.
- Result **7/11/19/57**; s-15 layout matches reference EXACTLY.

### Adjusting Modifications Manually (s-16–s-18) — BLOCKED
- `Edit > Modify Peptide` opens the Edit Modifications form (main-menu path works), but the per-residue **Isotope heavy** dropdowns are caption-less `LiteDropDownList`s: only residues that already carry a mod expose a label; the V/L residues needing a new `Label:13C` are unlabeled and share the same type, and `set_form_value` matches by label (internal name `comboHeavy8_1` errors "No control matching"), `get_children`=[]. So the V/L labels can't be applied (Finding #5).
- The subsequent **heavy-precursor pick-list** (hover the peptide's drop-arrow → check "747.3481++ (heavy)") has no MCP verb (tree pop-up pick-list, = MethodEdit #7). Finding #6.
- **Impact:** the 3 V/L peptides (AGLCQTFVYGGCR, IVGGWECEK, YEVQGEVFTKPQLWP) stay light-only → 19 precursors vs the tutorial's 22. Light-form analysis downstream is unaffected; light:heavy ratios for these 3 are unavailable.

## Findings & fix suggestions

(accumulating — see final section)

## Final status

(to be filled in)
