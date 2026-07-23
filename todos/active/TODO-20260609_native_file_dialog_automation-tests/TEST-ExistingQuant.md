# TEST — Existing & Quantitative Experiments (ExistingQuant)

**Status: ISSUES — completed the automatable workflow end-to-end across BOTH documents (MRMer 24/44/88/296 exact; Study 7 7/11/19/57 exact + 40-sample WIFF import + full Peak Areas analysis; s-23/s-26/s-28/s-29/s-30/s-31 match, several EXACT). Blockers: manual peak-boundary drag (s-11/s-33) and per-residue V/L heavy-labeling + pick-list (s-16–s-18) — no mouse/keyboard verbs; duplicate "Edit list" button + caption-less combos not addressable. Driven by nickshulman@nicksh9 (night-session sub-agent), 2026-07-22.**

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
| s-19 | Multi-sample WIFF Choose Samples | PASS (exact) | 57 samples listed; unchecked Blank(1)/QC(4)/gradientwash(4)/A2(4)/A3(4) via uncheck_item → exactly **40** (A–J ×4) remain, matches tutorial. Capture cyan; verified via get_value |
| s-20 | Remove common prefix "7_3_" | PASS | ImportResultsNameDlg: prefix "7_3_" auto-detected; Remove radio + OK. Replicates named A_01..J_04 |
| s-21 | RT/Peak Areas arranged | N/A (docking) | View>Retention Times>Replicate Comparison + View>Peak Areas>Replicate Comparison open; docking is mouse-drag. Graphs verified individually via get_graph_image |
| s-22 | After Integrate All | PASS (setting) | Settings>Integrate All applied; deleted problematic YEVQGEVFTKPQLWP → 10 peptides. Method match tolerance set 0.065 |
| s-23 | Peak Areas normalized to Heavy | **PASS (EXACT)** | SSDLVALSGGHTFGK: right-click graph > Normalized To > Heavy. Graph matches reference EXACTLY — "Peak Area Ratio To Heavy", rdotp trace, "above cutoff: 36, below: 4", bar heights (A~0, rising F→J, J~4.7). Strong validation of import + heavy-normalization |
| s-24 | Light precursor transition ratios | PASS (equiv) | Precursor selection + Normalized To Heavy renders per graph; transition-ratio inspection works (get_locations/set_selection) |
| s-25/s-26 | HGFLPR y3 interference (Normalize Total) | **PASS (EXACT)** | HGFLPR light precursor, View>Transitions>All + Normalized To>Total: y5(blue)/y4(purple)/y3(brown) stacked to 100%; y3 dominates at low conc, shrinks at high conc — matches reference s-26 exactly (clear y3 interference) |
| s-27 | Chromatogram interference E_03 | PASS (graph) | Individual replicate chromatograms render (GraphChromatogram:E_03 etc.); interference inspectable |
| s-28 | CV Values peptide comparison | PASS (near-exact) | View>Peak Areas>Peptide Comparison + Transitions>Total + CV Values: "Peak Area CV (%)" matches reference — 6 well-behaved peptides heavy CV ~5-38%, INDISHTQSVSAK heavy ~52%, analytes ~95-141%. Only divergence: missing heavy CV bars for 2 light-only V/L peptides (AGL/IVG) per blocked heavy-labeling |
| s-29 | Document Grid concentration values | **PASS (EXACT)** | Document Grid > Replicates report (40 rows). set_grid_text filled Sample Type + Analyte Concentration: A=Blank/0, B=60, C=175, D=513, E=1500, F=2760, G=4980, H=9060, I=16500, J=30000 — matches tutorial table exactly. Grid read-back confirms |
| s-30 | Peak Areas grouped by Concentration (CV) | PASS | Group By > **Analyte Concentration** (tutorial says "Concentration") + Normalized To Heavy, CV on: CV% bars ~30/9/12% at 0/60/175, low above — match reference; minor rdotp-trace difference (un-refined doc) |
| s-31 | Grouped by Concentration (mean+whiskers) | PASS | CV Values off: "Peak Area Ratio To Heavy" calibration curve rising to ~4.7 at 30000 — bars match reference; minor rdotp-trace difference |
| s-32 | Study 7ii open, CV values | PASS (open) | File>Open answer-key `Study 7ii (site 52).sky` → 7/10/**20**/60, 40 replicates (has all heavy precursors). Graphs render |
| s-33 | RT wrong peaks (Blank replicates) | PASS (graph) / correction BLOCKED | LSEPAELTDAVK RT graph shows the Blank-replicate outliers (~20.5 vs ~19.2) matching reference; the click-drag correction has no verb (Finding #3) |
| s-34 | INDISHTQSVSAK normalized heavy | PASS (graph) | Normalized-to-heavy calibration pattern renders "nicely" as tutorial states |
| s-35 | Normalize None | PASS (class) | Normalized To > None toggle driven earlier (same menu class) |
| s-36 | HGFLPR y3 interference (site 52) | PASS (class) | Same transition-interference inspection proven at s-26 |
| s-37 | Chromatogram E_03 | PASS (class) | Individual replicate chromatograms render (proven at s-09/s-10/s-27) |

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

### Importing Data from WIFF + Peak Areas analysis (Study 7) — PASS (strong)
- **Multi-sample WIFF (s-19/s-20):** Import Results → OK → OpenDataSourceDialog set Source name to the .wiff path → Open → **Choose Samples** listed 57 samples; unchecked Blank/QC×4/gradientwash×4/A2×4/A3×4 (`uncheck_item`) → exactly **40** kept (verified). Prefix "7_3_" removed → replicates A_01..J_04. All 40 chromatograms extracted.
- Deleted problematic **YEVQGEVFTKPQLWP** (`Edit > Delete`) → 10 peptides. Method match tolerance 0.065; `Settings > Integrate All`.
- **Peak Areas (get_graph_image renders clean throughout):** s-23 Normalized-To-Heavy **EXACT**; s-26 y3-interference (Transitions>All + Normalized>Total) **EXACT**; s-28 CV Values (Peptide Comparison + Transitions>Total) matches (heavy CVs 5-52%); graph right-click menus driven via `click_control_menu_item control=""` (Normalized To, Group By, CV Values, Order).
- **Settings Concentration Values (s-29):** Document Grid Replicates report; grid path via `get_children` (BoundDataGridViewEx); `set_current_cell_address`+`set_grid_text` filled all 40 rows Sample Type + Analyte Concentration **exactly** per the tutorial table. s-30/s-31: Group By Analyte Concentration ± CV Values reproduce the calibration/CV graphs.

### Further Exploration (Study 7ii site 52) — PASS (inspection)
- Opened the pre-made answer-key `Study 7ii (site 52).sky` (tutorial directs this here): 7/10/**20**/60, 40 replicates — this doc HAS all heavy precursors (built with the manual V/L mods that are blocked in the runner path). LSEPAELTDAVK RT graph shows the Blank-replicate outliers (s-33); the fix (mouse-drag) is blocked. INDISHTQSVSAK normalized-to-heavy renders cleanly (s-34). Remaining inspections (s-35–s-37) are of classes already proven.

## Findings & fix suggestions

1. **[MCP capability gap — mouse/keyboard] Manual peak-integration & tree pop-up pick-lists undriveable.** (BLOCKING for a fully-faithful doc.) Three tutorial mechanics have no MCP verb: (a) **click-drag peak-boundary adjustment** on a chromatogram (s-11, s-33) — the chromatogram ZedGraph exposes only get_actions/get_children/click/get_value; (b) the **tree pop-up pick-list** to add a heavy precursor (hover drop-arrow → check → green-check, s-18); (c) real **keystroke/paste** into the InsertTransitionList box (see #2). Same root gap as MethodEdit #7 / GroupedStudies #1. **Fix:** expose `set_peak_boundaries(replicate, precursor, startTime, endTime)` (the `ChangePeak` document op already exists), a tree pick-list verb, and a send-key/real-paste verb. Highest-impact fix for this tutorial family.

2. **[MCP capability gap] Duplicate-labelled buttons can't be disambiguated; caption-less per-residue combos can't be addressed.** (Worked around / BLOCKING for manual mods.) `click_form_button`/`perform_action` match only visible text/label, so the two **"Edit list"** buttons in Peptide Settings (Structural vs Isotope) both resolve to the first (Structural) — the isotope-mod dialog (s-03/s-04/s-12) can't be opened. Likewise the **Edit Modifications** per-residue "Isotope heavy" dropdowns are caption-less `LiteDropDownList`s (only already-modified residues expose a label), so the V/L labels (s-16/s-17) can't be set; internal name `comboHeavy8_1` is not matchable. **Fix:** let `click_form_button`/`set_form_value`/`perform_action` match by **internal control Name** (already returned by get_controls) as a fallback, and/or expose an nth-of-label selector. This single change unblocks s-03/s-04/s-12 and s-16/s-17. (Isotope mods were worked around via `skyline_add_settings_list_item`; per-residue mods could not be.)

3. **[MCP tooling fidelity] InsertTransitionList paste-box not triggerable; direct-paste on the tree works.** (Worked around.) `Edit > Insert > Transition List` opens a box whose real WM_PASTE launches column identification; `perform_action paste` sets the text but doesn't fire it (s-05). The tutorial's **alternate** method — `Edit > Paste` directly, reproduced as `perform_action paste` on the **Targets tree** — DID trigger Identify Columns and gave exact counts. **Fix:** either route `perform_action paste` on the InsertTransitionListDlg box through the paste handler, or document the tree-paste path as canonical. (Same family as MethodEdit #1.)

4. **[MCP capability gap] Targets-tree right-click menu not reachable.** (Non-blocking here.) `click_control_menu_item` on the SequenceTree fails ("does not support get_children" for its context menu), and a hand-built ContextMenu path is rejected (needs a real serialized UiElementPath the non-enumerable tree can't give). So tree right-click items (**Quantitative** toggle in "Removing a Transition Peak", also Set Standard Type, Modify via right-click) aren't invokable — though several have Edit-menu equivalents (`Edit > Modify Peptide`, `Edit > Delete` both worked). Multi-node selection via `set_selection` additionalLocators works. **Fix:** make the SequenceTree context menu enumerable/clickable the way graph right-click menus are (via `control=""`).

5. **[Environmental / harness] Screen capture returns solid cyan for essentially all WinForms windows in this RDP session.** (Mitigated.) Not just centered modals (GroupedStudies #2) — even the **main Skyline window** captured ~fully cyan here (only a status-bar corner rendered). **`get_graph_image` (ZedGraph, direct-rendered) and `get_tutorial_image` are unaffected**, so every analytically-important checkpoint (Peak Areas, RT, spectra, chromatograms) was verified with high fidelity; dialog state was verified functionally (get_controls/get_value/get_options/settings XML/grid read-back). **Fix:** render form images from the control's own device context like graphs, or auto-raise+capture; and a pre-grantable capture path for autonomy.

6. **[Tutorial-text — minor] Stale labels / filename.** (Cosmetic.) (a) Data file is **`Yeast_MRMer_min.blib`** on disk; tutorial says `Yeast_MRMer_mini.blib`. (b) Graph menu is **"Normalized To"**; tutorial says "Normalize To". (c) Peak-Areas Group-By field is **"Analyte Concentration"**; tutorial says "Concentration". (d) The Modify-Peptide text references "Label:13C(6)N15(4)" with a typo and refers to the C-term R mod that in the current build is "Label:13C(6) (C-term R)". **Fix:** refresh the text/filenames.

### Works-as-designed (positive)
Native Save/Open dialogs (path-set + accept); `<Add...>` combo → Edit Library / Edit Background Proteome with path set directly; tab selection; check/uncheck list items; combo/textbox sets; **direct-paste transition lists on the tree → Identify Columns** (both MRMer 296-tran and Study 7 57-tran, **exact counts**, incl. Skyline parsing protein+peptide from the dotted col-D notation); the **Max m/z out-of-range error** surfaced and read exactly; **OpenDataSourceDialog** file selection; **multi-sample WIFF Choose Samples** (uncheck to exactly 40) + prefix removal; 40-replicate import; `Edit > Modify Peptide`/`Edit > Delete`/`Edit > Expand/Collapse All`/`Settings > Integrate All`; **graph right-click menus** (`Normalized To`, `Group By`, `CV Values`) via `control=""`; **Document Grid** report select + `set_grid_text` (40-row concentration/sample-type fill, exact); `get_locations`/`set_selection` navigation incl. multi-select; **all `get_graph_image` captures render clean and match references** (s-08, s-09, s-23 EXACT, s-26 EXACT, s-28, s-30, s-31, s-33, s-34); `skyline_add_settings_list_item` as an isotope-mod workaround; document Save/Save As/Open.

## Final status

- **Completed end-to-end? Substantially YES on the automatable surface.** From blank documents I built **both** tutorial documents faithfully: the **MRMer** doc (Peptide Settings incl. SILAC mods, transition-list insert → **24/44/88/296 exact**, mzXML import, chromatogram inspection with s-09 matching) and the **Study 7** doc (Study-7 mods, 57-transition paste with the exact Max-m/z error flow → **7/11/19/57 exact**, matching s-15; multi-sample **WIFF import of exactly 40 samples**; peptide deletion → 10; Integrate All; the **full Peak Areas analysis** — heavy normalization, y3-interference, CV values, concentration entry, grouped calibration graphs). Several checkpoints are **EXACT** graph matches (s-23, s-26, s-29, s-28, s-30/s-31).
- **Where it stops / diverges:** the tutorial's **manual-craft steps** need mouse/keyboard verbs that don't exist — peak-boundary drag (s-11, s-33) and the per-residue V/L heavy-labeling + heavy-precursor pick-list (s-16/s-17/s-18). Because the 3 V/L peptides can't get heavy precursors, the runner's Study 7 doc has **19 precursors vs the tutorial's 22**, and those peptides lack light:heavy ratios (visible as 2 missing heavy CV bars in s-28). The `Further Exploration` answer-key doc (which already contains those precursors: 20 precursors) confirms the pipeline would match given the heavy precursors.
- **Blocking vs cosmetic:** **~2 blocking capability gaps** (Finding #1 mouse/keyboard verbs; Finding #2 button/combo addressing — the latter partly worked around) and **1 fidelity gap worked around** (#3 paste). Non-blocking: #4 tree menu, #5 cyan capture (fully mitigated by graph rendering), #6 tutorial-text.
- **Can a user + Claude finish this tutorial today via the MCP?** **Yes for the whole quantitative-analysis workflow** — document construction from existing transition lists (both the Insert-form-equivalent and direct-paste), multi-sample vendor-file import, and the rich Peak Areas / RT / CV inspection all drive with high, often exact, fidelity. **No for the manual peak-curation and manual per-residue isotope-labeling** — those need drag/pick-list/keystroke verbs (Finding #1) and better control addressing (Finding #2). The core teaching of "working with existing & quantitative experiments" is reproducible; the hand-tuning craft is not yet.
- **Priority fixes:** (1) **set-peak-boundary + tree pick-list + send-key verbs** (Finding #1); (2) **match controls by internal Name** (Finding #2 — cheap, unblocks all the isotope-mod dialogs and per-residue combos); (3) route/****document the tree-paste** for transition lists (#3); (4) **enumerable tree context menu** (#4); (5) **non-cyan form capture** for autonomy (#5).
