# TEST — Small Molecule Targets (SmallMolecule)

## Run context
- Branch / PR: native_file_dialog_automation (PR #4313)
- Skyline: 26.1.1.203 (b818b91b4), developer build, connected PID 31792
- Date: 2026-07-22
- Data folder: D:\Downloads\Tutorials\SmallMolecule\
- UI mode: small_molecules (Molecule interface)
- Driver: night-session sub-agent (orchestrator-spawned)

Status: CLAIMED by nickshulman@DESKTOP 2026-07-22

## Screenshot checklist
| Screenshot | Section | Status | Note |
|-----------|---------|--------|------|
| s-01 | Insert Transition List form | PASS | exact match |
| s-02 | Import Transition List: Identify Columns | PASS | exact; Molecules radio pre-pressed, all columns auto-identified |
| s-03 | Targets after insert | PASS (cosmetic env divergence) | tree/counts exact (6/12/19/21); leftover floating Document Grid + Immediate Window from prior session not in reference |
| s-04 | Import Results Files (file dialog) | PASS (functional) | 18 folders selected via ListView select_item; live capture initially obscured by leftover floating grid, then clear |
| s-05 | After import results | PASS (content) | all 18 replicates imported (native Waters .raw), all targets green-checked; chromatogram content exact; main-window cosmetic divergence (leftover floating Peak Areas graph + Immediate Window) |
| s-06 | Peak Areas + RT + chromatograms | TBD | |

## Progress log

### Getting Started
- Settings > Default → MultiButtonMsgDlg "save current settings?" → clicked **No**. PASS.
- UI mode already `small_molecules` (Molecule interface); verified via get_ui_mode. PASS.

### Insert Transition List (faithful UI path test)
- Set clipboard to SMTutorial_TransitionList.csv contents (PowerShell Set-Clipboard).
- Edit > Insert > Transition List → opened `InsertTransitionListDlg:Insert Transition List`. **s-01 PASS** (exact match to reference "Press Ctrl-V to paste here.").
- **BLOCKED on this specific dialog:** `perform_action paste` put the CSV text into the textbox but the dialog did NOT advance to the column-identify form. Source (`InsertTransitionListDlg.cs`) shows the dialog only acts on a real **Ctrl-V KeyDown** (`textBox1_KeyDown`: clears box, calls `textBox1.Paste()` from clipboard, sets `DialogResult=OK`). KeyPress handler sets `e.Handled=true` for all other keys, and the form has **no accept/default button** (`dismiss_with_accept_button` → error "has no default (accept) button"). So the MCP `paste` verb cannot trigger this paste-catcher dialog. → Finding #1 (MCP capability gap). Cancelled the dialog.
- **Fallback faithful path (works):** `perform_action paste` targeting the **Targets tree** (`SequenceTreeForm:Targets`, type=SequenceTree) with the CSV text → opened `ImportTransitionListColumnSelectDlg:Import Transition List: Identify Columns`. This is the Edit>Paste-into-document equivalent and reaches the SAME mapping dialog the tutorial's Ctrl-V would.
- **s-02 PASS** (exact match): Molecules radio pre-pressed, "Show unused columns" checked; columns auto-identified (Molecule List Name, Molecule Name, Molecule Formula, Precursor Adduct, Precursor Charge, Explicit Retention Time, Explicit Collision Energy, Product m/z, ...). The mapping GRID is fully readable via get_form_image; no per-column remapping needed here since auto-detection succeeded.
- Clicked **OK** (dismiss_with_accept_button). Document status: **Lists 6, Molecules 12, Precursors 19, Transitions 21** — matches computed CSV expectation and reference status bar "1/6 list 1/12 mol 1/19 prec 1/21 tran".
- **s-03 PASS** (content exact): Targets tree shows all 6 lists / 12 molecules exactly as reference. Cosmetic env divergence only: a leftover floating "Document Grid: Tailing Review" and docked Immediate Window (pre-existing layout from a prior agent session) are present in the live window but not the reference; not caused by tutorial steps.

### Importing Mass Spectrometer Runs
- View > Document Grid clicked twice attempting to close a leftover floating "Document Grid: Tailing Review" (persisted layout from a prior session) — toggle did not dismiss it; it closed on its own later. Environmental, cosmetic.
- File > Save → native `Dialog:Save As` (SaveFileDialog). set_form_value with full path `D:\...\Amino Acid Metabolism.sky`, dismiss_with_accept_button. Saved OK (document path updated, counts unchanged).
- File > Import > Results → `ImportResultsDlg`. Selected radio "Add single-injection replicates in files" (tutorial "Import single-injection replicates in files"). "Files to import simultaneously" already = "Many" (get_value confirmed; set_value to "Many" errored "No item 'Many'" — minor: the combo's set-by-text rejects the value it already reports via get_value). Clicked OK.
- `OpenDataSourceDialog:Import Results Files` (Skyline's custom data-source browser, NOT native). Navigated by setting "Source name" to the folder path + Open.
  - **Multi-select attempt via quoted names failed:** setting "Source name" to all 18 quoted `.raw` names then Open → MessageDlg "Please select one or more data sources." So this dialog does NOT parse quoted names into a selection. → Finding #2.
  - **Multi-select via ListView `select_item` WORKS and accumulates:** 18 sequential `perform_action select_item` calls (by folder text) selected all 18 (verified two-item accumulation by capture). Definitive proof: 18 replicates imported.
  - s-04: live capture initially obscured by the leftover floating Document Grid; after it closed, a clean capture matched the reference selection. Functional PASS.
- Common-prefix dialog `ImportResultsNameDlg`: clicked "Do not remove", OK.
- Import: all 18 Waters `.raw` folders imported via the **native Waters vendor reader** (no mzML fallback needed). get_replicate_names lists all 18. 18 GraphChromatogram graphs docked; all targets show green checkmarks.
- **s-05 PASS (content):** ID15655 chromatogram graph exactly matches reference (Ornithine ~0.8, Arginine ~2.0, Methionine ~2.5, Leucine ~2.9, Phenylalanine ~3.1; intensity to ~250e6). Status counts 6/12/19/21 unchanged. Main-window layout diverges cosmetically (leftover floating Peak Areas graph overlaps chromatogram pane; Immediate Window docked) — environmental, not tutorial-induced.

## Findings & fix suggestions
(in progress — see final section)

## Final status
(in progress)
