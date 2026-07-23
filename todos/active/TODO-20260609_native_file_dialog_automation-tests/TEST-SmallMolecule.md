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
| s-04 | Import Results Files (file dialog) | TBD | |
| s-05 | After import results | TBD | |
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

## Findings & fix suggestions
(in progress — see final section)

## Final status
(in progress)
