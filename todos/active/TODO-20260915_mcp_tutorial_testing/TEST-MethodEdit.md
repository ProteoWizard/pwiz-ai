# TEST — Targeted Method Editing (MethodEdit)

**Status: ISSUES — completed end-to-end, brendanx@BRENDANX-UW8 2026-09-15T23:00Z**
(21/28 screenshots match; s-05 partial, s-10 divergence, s-16/17/21/22 blocked)

Round 2 - re-run of TEST-MethodEdit-round1.md against master bc2c55ef05.

## Run context

- **Branch / PR:** master `bc2c55ef05` (2026-08-26) — includes #4449/#4452 verbs
  (graph click/zoom, tree pick-lists, send_key_stroke/send_text,
  get_locations/set_selection, undo/redo, settings-list tools) and #4575
  (`File > Import > Window Layout...`).
- **Skyline:** `Skyline (64-bit : developer build) 26.1.1.238 (bc2c55ef05)`
- **Connected PID:** 13952
- **Date:** 2026-09-15
- **Data folder:** `C:\Users\brendanx\Documents\MethodEdit` (FASTA, Library, Yeast_atlas verified)
- **UI mode:** proteomic
- **Driver:** per-tutorial sub-agent spawned by the night-session orchestrator.
- **Round 1 result:** `TEST-MethodEdit-round1.md` (2026-07-22, PR #4313 build 26.1.1.202).

## Progress log

- **Getting Started** — PASS. Blank doc confirmed via capture (0/0/0/0, protein icon
  top-right, proteomic). `Settings > Default` → "save current settings?" → **No**.
  Note: the three callout images (`skyline-blank-document.png`,
  `proteomics-interface.png`, `protein-icon.png`) **404** from
  `skyline_get_tutorial_image` — they live in `Documentation/Tutorials/shared/{en,}/`
  and the tool only looks in `MethodEdit/en/` (Finding, tooling). Verified against
  the on-disk copies instead.
- **Spectral Library (s-01)** — PASS, exact. Faithful path drove end-to-end:
  Peptide Settings → Library tab → Build → Name → **Browse** (native `Dialog:Save As`,
  `FileDialog` = `...\Library\Yeast (Atlas).blib`) → Next → Add Files (native
  `Dialog:Add Input Files`) → grid shows `PeptideProphet confidence 0.95` already →
  Finish → `check_item Libraries "Yeast (Atlas)"`. Library built in seconds (8.9 MB).
- **Background Proteome (s-02, s-03)** — PASS both. `set_form_value "Background
  proteome" "<Add...>"` opened Edit Background Proteome; Create → native Save
  (`Yeast.protdb`); Add File → native Open (`sgd_yeast.fasta`) → "61 repeated
  sequences" MessageDlg → OK → "5801 proteins". s-02 differs only in the path
  (install location); s-03 exact. No cyan captures this time.
- **Pasting FASTA (s-04)** — PASS, pixel-level match after layout import. `Set-Clipboard`
  (Fasta.txt) + `Edit > Paste` → `EmptyProteinsDlg` ("added 30 new proteins with no
  peptides… remove?") → **Keep** → 35/25/25/75. (The tutorial text never mentions this
  prompt; captured as `s-04a-emptyproteins.png`.) "Press the down arrow until the first
  peptide is selected": `send_key_stroke SequenceTree Home`/`Down` were accepted but did
  **not** move the selection (as the verb's own doc warns: default TreeView key handling
  is not a KeyDown handler). Used `get_locations molecule` + `set_selection
  Molecule:/YAL005C/VDIIANDQGNR` instead. Then `File > Import > Window Layout` →
  `p07.view` (see "Window layout files"). Window size 1035x511 had to be set **outside
  the MCP** (Win32 `SetWindowPos` from PowerShell; there is no verb for it). With both,
  the capture matches s-04 essentially pixel for pixel (tree, expansion, spectrum,
  status bar `4/35 prot 1/25 pep 1/25 prec 1/75 tran`, Files tab present in both).
- **b-ions + rank-1 transition (s-05)** — PARTIAL (same as round 1). `View > Libraries >
  Ion Types > B` still "Menu item not found" via `click_main_menu_item` and
  `click_control_menu_item(control="")`; `get_children` on `Ion Types` returns `[]`
  even after clicking the item; the graph reports "msGraphExtension has no context
  menu". **Root cause (source, `Menus/ViewMenu.cs` `UpdateIonTypeMenu`):** the submenu's
  only child is a `MenuControl<IonTypeSelectionPanel>` — a ToolStripControlHost hosting
  a checkbox panel — so there is no `ToolStripMenuItem` "B" to match. Selected y7 via
  `get_locations transition` + `set_selection`; tree, red y7 highlight, `2/75 tran` all
  match; purple b3/b5/b6/b7/b8 labels absent.
- **Transition Settings (s-06, s-07, s-08)** — PASS all three, exact. Filter tab:
  `set_form_value "Precursor charges" "2, 3"`, `get_form_value "Ion charges"` = 1,
  `"Ion types" "y, b"`. Library tab: `"product ions" 5`. OK → 35/28/31/155; tree shows
  the new charge-3 AVGIDLGTTYSCVAHFANDR first peptide and b5 (rank 4)/y5 (rank 5).
- **GPM library (s-09)** — PASS, exact. Edit list → Add → Name → **Browse** (native
  `Dialog:Open`, `yeast_cmp_20.hlf`) → OK → OK → `check_item "Yeast (GPM)"`. OK →
  35/182/219/1058.
- **Limit peptides per protein** — PASS. `uncheck_item "Yeast (Atlas)"`, `Rank peptides
  by = Expect`, `Limit peptides per protein = true`. The caption-less count box still
  rejects `set_form_value` by label ("Peptides") **and** by name (`textPeptideCount`):
  "No control matching … supports the action 'set_value'". `perform_action set_value
  type=TextBox value=3` worked (round-1 #6 persists). OK → 35/47/47/223; `Refine >
  Remove Empty Proteins` → 19/47/47/223.
- **Insert Protein List (s-10)** — DIVERGENCE (cosmetic). `set_selection /Insert`;
  `Edit > Insert > Proteins`; **`send_key_stroke gridViewProteins Ctrl+V`** (new verb)
  ran the grid's real paste handler: 17 rows with Description + Sequence resolved from
  the background proteome. Accession/Preferred Name/Gene/Species populated from UniProt
  (round-1 #3, stale tutorial text). The reference has the Sequence column widened via
  header double-click/drag — no MCP verb for column sizing, so the live grid shows all
  seven narrow columns. Insert → 36/58/58/278; Remove Empty Proteins → 24/58/58/278.
- **Insert Peptide List (s-11, s-12)** — PASS both. s-11: `set_selection
  MoleculeGroup:/YAL003W` (first protein) + `Edit > Paste` → `peptides1` with 70
  peptides (25/70/70/338); `perform_action rename_node "Primary Peptides"`; selected
  TLTAQSMQNSTQSAPNK by locator → capture matches s-11 (spectrum, `1/25 prot 6/70 pep
  6/70 prec 26/338 tran`). s-12 — **round-1 blocker #1 FIXED**: `Edit > Undo` ×2
  (`get_undo_redo` confirms), `Edit > Insert > Peptides`, then **`send_key_stroke
  gridViewPeptides Ctrl+V`** ran the form's real paste handler and resolved all 12
  peptides to their proteins (YIL075C … YML057W) with descriptions — grid content
  identical to s-12 (the reference form is shorter; the test resizes it). Insert →
  35/70/70/338, peptides under their own proteins (inserted above YAL003W, where the
  selection was).
- **Simple Refinement (s-13, s-14)** — PASS both, exact. `Edit > Find` → "IPEE" → Find
  Next → `Molecule:/YAL034W-A/IPEEYLDANVFR`; `get_graph_image` of Library Match is
  pixel-identical to s-13 (y6 rank 1 / b4 rank 2). `Refine > Advanced` → `Min
  transitions per precursor = 5` → 64 peptides; status bar `29/35 prot 50/64 pep 50/64
  prec 246/320 tran` = s-14 exactly.
- **Peptide Uniqueness (s-15)** — PASS (content). Last protein YDL245C → `Edit > Unique
  Peptides`: SASWVPPSR × 5 other proteins, same as the reference. Divergence: column
  headers show UniProt-resolved `P39004 / HXT7_YEAST / HXT7 YDR342C…` and Details shows
  resolved metadata, where the reference has bare `YDR342C…` and "Searched:
  Uniprot:S000002404" (internet-dependent metadata again). Cancel; **`send_key_stroke
  SequenceTree Delete` did nothing** (Delete is a menu shortcut, not a control handler)
  → `Edit > Delete` removed YDL245C → 34/63/63/315. New last protein YDL244W → Unique
  Peptides shows GSGITEDFQSLK in 4 THI5/11/12/13 proteins (tutorial: "in this case 4").
  Cancel.
- **Direct Document Editing — auto-completion (s-16, s-17, s-18)** — s-16/s-17
  **BLOCKED** (popup not reproducible), s-18 PASS on content.
  - Probe 1: Skyline brought to the foreground (Win32 `SetForegroundWindow`), then
    `send_text SequenceTree "ybl087"` → the edit box showed **"bl087y"** (out of
    order, exactly as the verb's doc warns), no completion popup; `send_key_stroke
    SequenceTree Esc` did nothing; `perform_action send_key_stroke type=TextBox Esc`
    cancelled the edit.
  - Probe 2: `send_text SequenceTree "y"` (begins the edit) then `perform_action
    send_text type=TextBox "bl087"`. Two `StatementCompletionForm`s opened and
    `get_form_image` of one showed a single **YBL087C** row (with UniProt names
    `P0CX41 RL23A_YEAST RPL23A…` prepended, wider than the reference's plain
    `YBL087C  RPL23A SGDID…`). But `get_controls` on the Targets form listed **six
    nameless TextBoxes**: each forwarded character reached the tree (not the edit
    box) and `SequenceTree.BeginEditNode` created a **new** TextBox per keystroke,
    orphaning the previous ones. `type=TextBox` addressed the first orphan, so
    `Enter` committed the visible box's "y" → "Added peptide group y". Undone.
    Five orphan TextBoxes and one orphan completion popup remained;
    `dismiss_with_cancel_button` closed the popup, but an empty white edit box is
    still painted at the blank node (cosmetic corruption for the rest of the run).
  - Document-equivalent path that works: `set_selection /Insert` + `perform_action
    rename_node` with the completed text — `"YBL087C"` → "Added peptide group
    YBL087C from background proteome" (3 peptides); `"YDR385W"`; and
    `"IQGPNYVPGK::YDR385W"` (the `::` PEPTIDE_SEQUENCE_SEPARATOR the completion
    itself emits) → "Added peptides to peptide group YDR385W". 36/70/70/350.
  - `File > Import > Window Layout` → `p21.view`: the Targets pane visibly widened
    (0.28 → 0.38 of the window) — definitive proof the import applies. s-18 (tree
    crop): YBL087C (ISLGLP… rank 2, ECADLWPR rank 1, VASNSGVVV rank 3) and YDR385W
    (4 peptides ending AYLPVNESFGFTGELR) identical to the reference.
- **Pop-up Pick-Lists (s-19, s-20)** — PASS both (round-1 #7 pick-list half FIXED).
  The tree's node menu is enumerable (`get_children` on `{SequenceTree, ContextMenu}`
  lists Cut/Copy/Paste/Delete/Expand Selection/**Pick Children**/…).
  `click_control_menu_item SequenceTree "Pick Children"` opened `PopupPickList`; its
  toolbar enumerates as OK/Cancel/Filter/Auto-select/Find; `click_control_menu_item
  ToolStrip "Filter"` = the funnel; `get_options`/`check_item`/`uncheck_item` on the
  CheckedListBox work; `Find (Ctrl + F)` shows the search TextBox and `send_text
  TextBox "b ++"` filters. s-19: checked `K.VMPAIVVR.Q [73, 80] (rank 6)` → capture
  identical to the reference except the row highlight. OK → **36/71/71/355** (the
  tutorial's 355). s-20: precursor `light+++` → unchecked y9/y6, Find "b ++", checked
  b5++/b7++ → capture identical except the row highlight; OK → transitions
  b5+/b9+/b10+/b5++/b7++, still 355.
- **Bigger Picture (s-21, s-22) / Drag and Drop** — BLOCKED, not driven. Data tips are
  hover-only (`ITipProvider` on the tree node); `get_actions` on the SequenceTree lists
  no hover/tip verb, and there is no drag verb for the tree (the tutorial test itself
  bypasses both with `ShowNodeTip` and `ModifyDocument(MoveNode)`). Round-1 #7 hover/drag
  half persists.
- **Preparing to Measure (s-23 + explorer + spreadsheet)** — PASS. Transition Settings →
  Prediction: `Collision energy = SCIEX`, `Declustering potential = SCIEX`; Instrument:
  `Max m/z = 1800`. `File > Save` → native `Dialog:Save As` → `MethodEditTutorial.sky`
  (36/71/71/**355**, the tutorial's number). `File > Export > Transition List` →
  Multiple methods, Ignore proteins, Max 75 → form **exact** ("Methods: 5") → native
  Save `Yeast_list` → **5 CSV files, 75+75+75+75+55 = 355 rows**, columns precursor
  m/z, product m/z, dwell, extended peptide, DP, CE. Rows match the spreadsheet
  reference on m/z and `YIL075C.LDQDSTSENVK.+2y8.light`; DP/CE values differ (80 /
  29.3 vs the 2017 reference's 76.2 / 31) because Skyline's shipped SCIEX equations
  have changed — stale screenshot, not a driver issue. The explorer reference lacks the
  `.skyl` audit log newer Skyline writes.

## Screenshot checklist

| Screenshot | Section | Status | Note |
|-----------|---------|--------|------|
| skyline-blank-document / proteomics-interface / protein-icon | Getting Started | PASS* | state verified; images 404 from `get_tutorial_image` (shared folder), checked on disk |
| s-01 | Spectral Library | PASS | exact |
| s-02 | Background Proteome | PASS | 5801 proteins; path differs only |
| s-03 | Digestion tab | PASS | exact |
| s-04 | Pasting FASTA | PASS | pixel-level after `p07.view` import + 1035x511 (size set outside MCP) |
| s-05 | b-ions + rank 1 | PARTIAL | purple b-ion labels absent (Ion Types is a hosted checkbox panel, Finding #1) |
| s-06 | Filter tab | PASS | exact |
| s-07 | Library tab | PASS | exact |
| s-08 | Tree after settings | PASS | exact; 35/28/31/155 |
| s-09 | Both libraries | PASS | exact |
| s-10 | Insert Protein List | DIVERGENCE | column widths not settable; UniProt metadata populated (stale text) |
| s-11 | Peptide list pasted | PASS | exact incl. status bar |
| s-12 | Insert Peptides | PASS | **fixed** — real Ctrl+V resolves proteins; grid identical |
| s-13 | IPEE spectrum | PASS | exact (`get_graph_image`) |
| s-14 | 70 → 64 | PASS | status bar exact |
| s-15 | Unique Peptides | PASS | right protein/peptide; headers carry UniProt names (env) |
| s-16 | Auto-complete "ybl087" | BLOCKED | popup only reachable by corrupting the tree (Finding #2); doc result via `rename_node` |
| s-17 | Auto-complete "eft2" | BLOCKED | same |
| s-18 | Added targets | PASS | tree identical after `p21.view` |
| s-19 | Peptide pick-list | PASS | identical bar row highlight |
| s-20 | Transition pick-list "b ++" | PASS | identical bar row highlight |
| s-21 | Data tip (protein) | BLOCKED | no hover verb |
| s-22 | Data tip (precursor) | BLOCKED | no hover verb |
| s-23 | Export Transition List | PASS | exact, Methods: 5 |
| s-method-edit-file-explorer | Files written | PASS | 5 CSV + .sky (+ .skyl, newer) |
| s-transition-list-spreadsheet | CSV content | PASS* | m/z + labels match; DP/CE differ (stale equations) |

**Tally (28):** 21 PASS (3 of them with environment-only differences), 1 PARTIAL
(s-05), 1 DIVERGENCE (s-10), 4 BLOCKED (s-16, s-17, s-21, s-22), plus the 3 Getting
Started callouts verified by state (image fetch failed) counted in the 21.

## Window layout files

- **Import works through the UI path.** `skyline_click_main_menu_item "File > Import >
  Window Layout"` → native `Dialog:Import Window Layout` → `set_form_value FileDialog
  <path>` → `dismiss_with_accept_button`. No error either time.
- **p07.view before s-04:** applied. The file's `DockLeftPortion=0.28 /
  DockRightPortion=0.41` match the captured pane widths, and its expanded-node list
  (`3,14,20,21,34` = YAL005C, YAL016W, YAL022C, YAL023C, YAL035W) matches the tree.
  With the window also sized to 1035x511 the capture is a pixel-level match to s-04:
  same tree rows, same scrollbar, same spectrum labels, same status bar, and the
  Files tab strip is present in both. **Caveat:** the window size had to be set with
  Win32 `SetWindowPos` from PowerShell; there is **no MCP verb for main-window size /
  state**, and a maximized 1920x1040 Skyline looks nothing like the 1035x511 tutorial
  frames (the first s-04 capture, before resizing, was correct in content but visually
  unrecognisable as the reference).
- **p21.view before s-16/s-18:** applied, and visibly so — the Targets pane widened from
  0.28 to 0.38 of the window, which is exactly the file's `DockLeftPortion`. s-18's tree
  crop then matched. (The tutorial test also hides the Files tab
  (`ShowFilesTreeForm(false)`) before that screenshot; the reference crop does not show
  the tab strip, the live pane does. `View > Files`-style toggling was not probed.)
- **What still differs after import:** (1) window size/state (above); (2) the Files
  tab strip in the Targets pane (present in every live capture; absent from s-11 and
  s-18 references, present in s-04); (3) the inactive-title-bar grey in captures taken
  while a dialog or the MCP client had focus; (4) nothing else — pane proportions,
  dock sides and tree expansion all come from the file.
- **Export round-trips.** `File > Export > Window Layout` → native `Dialog:Export Window
  Layout` → path → accept wrote the current layout; contents carry the p21 proportions,
  the tree's expansion/selection state and the FilesTreeForm. Re-importing that file
  worked and, as a side effect, rebuilt the Targets pane (which cleared the orphan edit
  boxes left by the auto-complete probe). **Quirk:** the dialog appends `.sky.view`, so
  `exported-layout.view` landed as `exported-layout.view.sky.view` — a user naming a
  file `MyLayout` gets `MyLayout.sky.view`, which is fine but surprising.
- **Verdict:** a user can save their own layouts and have Claude restore them at any
  checkpoint through the MCP; combined with a window-size verb this would make the
  main-window screenshots (s-04, s-08, s-11, s-14, s-18) presentable rather than merely
  correct.

## Findings & fix suggestions

### 1. [MCP capability gap] `View > Libraries > Ion Types > B` still unreachable (s-05)
- **What:** `click_main_menu_item` and `click_control_menu_item(control="")` both return
  "Menu item not found"; `get_children` on `Ion Types` is `[]` even after clicking it.
- **Root cause (`Menus/ViewMenu.cs` `UpdateIonTypeMenu`):** the submenu's single child
  is a `MenuControl<IonTypeSelectionPanel>` — a ToolStripControlHost hosting a checkbox
  panel (A/B/C/X/Y/Z). There is no `ToolStripMenuItem` named "B"; the same applies to
  `Charges` (`ChargeSelectionPanel`). MethodRefine's round-1 "succeeded" report cannot
  have gone through this path.
- **Impact:** cosmetic here (purple b-ion labels), but any tutorial that says "Ion
  Types > B/C/Y" or "Charges > 2" cannot be driven faithfully.
- **Fix:** in the menu walker, when a dropdown item is a `ToolStripControlHost`, descend
  into its hosted control and match its checkboxes by label (so the existing path
  syntax `Ion Types > B` just works); or expose the hosted panel via
  `get_controls`/`set_form_value` on the main window.

### 2. [MCP capability gap + Skyline robustness] Auto-completion in the Targets tree (s-16, s-17)
- **What:** typing into the blank node to get the completion popup is the only UI path.
  `send_text` on `SequenceTree` delivers characters through the focused window and each
  one hits the tree rather than the edit box: `SequenceTree.BeginEditNode` runs once
  **per character**, creating a new `TextBox` each time (six after "ybl087"), the text
  arrives out of order ("bl087y"), and the orphans stay in `Parent.Controls` (one was
  still painted at the blank node until the pane was rebuilt). The connector's own doc
  already warns about this; this run confirms the mechanism.
- **Impact:** s-16/s-17 not reproducible; the document result *is* reachable with
  `rename_node "YBL087C"` / `"IQGPNYVPGK::YDR385W"` (same `AfterNodeEdit` resolution),
  so the workflow continues but the teaching moment is lost.
- **Fix:** (a) a `begin_edit` action on the SequenceTree (calls
  `SequenceTree.BeginEdit(false)` and returns the edit box as a normal `TextBox`
  element), after which `send_text`/`set_value` on that TextBox raises `TextChanged` and
  the `StatementCompletionForm` appears — the tutorial test drives it exactly this way
  (`BeginEdit` + `StatementCompletionEditBox.TextBox.Text = "ybl087"`); then
  `send_key_stroke Down/Enter` on the TextBox commits. (b) Make `send_text` on the
  SequenceTree either route through that path or refuse outright instead of corrupting
  the pane. (c) Skyline-side: `BeginEditNode` should commit/remove an existing
  `_editTextBox` before creating another.

### 3. [MCP capability gap] No main-window size/state verb
- **What:** every main-window reference is 1035x511; the live Skyline was maximized at
  1920x1040. Nothing in the MCP sets the window's bounds or restores it from
  maximized. I used Win32 `SetWindowPos` from PowerShell to get the pixel-level s-04.
- **Fix:** `skyline_set_window_bounds(width, height[, x, y])` (or fold it into the
  layout import: an optional `size` argument). Cheap and it is the single biggest
  difference between "correct" and "looks like the tutorial".

### 4. [MCP capability gap] No hover (data tip) or drag-and-drop verb (s-21, s-22, Drag and Drop)
- **What:** data tips are mouse-hover only; protein reorder is drag-only. `get_actions`
  on the tree lists nothing for either.
- **Fix:** `show_node_tip` (the test's `ShowNodeTip(nodeText)`) returning a capture or
  the tip's text/HTML, and `move_node(locator, beforeLocator)` for reorder. Lower
  priority than #1–#3: both are "look at this" steps, not workflow steps.

### 5. [MCP tooling fidelity] `send_key_stroke` cannot navigate or delete in the Targets tree
- **What:** `Home`, `Down`, `Delete` on `SequenceTree` are accepted but do nothing:
  arrow keys are default TreeView behaviour and Delete is the `Edit > Delete` menu
  shortcut, neither a control-level KeyDown handler. The doc says as much, but the
  tutorial's "press the down-arrow key" / "press the Delete key" steps then need a
  translation (`get_locations`+`set_selection`, `Edit > Delete`) the reader does not see.
- **Fix:** have `send_key_stroke` fall back to `ProcessCmdKey`/`ProcessDialogKey` on
  the form when the control did not handle the key, so menu shortcuts and default
  navigation keys work; or document the two substitutions in the verb text.

### 6. [MCP tooling fidelity] Caption-less controls: `set_form_value` rejects both label and name
- **What:** the Peptide Settings count box (`textPeptideCount`, beside the label
  "Peptides") fails `set_form_value` by "Peptides" **and** by `textPeptideCount` ("No
  control matching … supports the action 'set_value'"); only `perform_action set_value
  type=TextBox` works (round-1 #6, unchanged). Column widths in the Insert grid (s-10)
  have no verb at all.
- **Fix:** let `set_form_value` accept the internal Name that `get_controls` prints
  (it prints it, so it should resolve it), and pick up a trailing label ("3 Peptides")
  as the caption. Column sizing is cosmetic; skip.

### 7. [MCP tooling fidelity] `get_tutorial_image` cannot fetch shared images
- **What:** `skyline-blank-document.png`, `proteomics-interface.png`, `protein-icon.png`
  404 — the tutorial HTML references `../../shared/en/…` and `../../shared/…`, the tool
  only tries `<Tutorial>/en/`.
- **Fix:** resolve the `src` path from the HTML (or fall back to `shared/<lang>/` and
  `shared/`) before fetching.

### 8. [Tutorial-text — stale] Metadata, equations and the empty-proteins prompt
- s-10/s-15/s-16: UniProt-resolved accession/preferred-name/gene/species now populate
  (needs internet); the text says the columns "will be empty". s-transition-list: DP/CE
  values reflect older SCIEX equations. s-04: the paste raises an "added 30 new proteins
  with no peptides… remove?" prompt the text never mentions (Keep is required to match
  s-04). Explorer screenshot predates the `.skyl` audit log.
- **Fix:** refresh the text/screenshots; mention the Keep/Remove prompt.

### Works-as-designed (positive, new since round 1)
- `send_key_stroke Ctrl+V` on the Insert grids runs the real paste handler (fixes s-12).
- Tree node context menu is enumerable and `Pick Children` opens the `PopupPickList`,
  whose toolbar (OK/Cancel/Filter/Auto-select/Find), CheckedListBox
  (`get_options`/`check_item`/`uncheck_item`) and search TextBox (`send_text`) all drive
  — s-19 and s-20 both matched.
- `get_undo_redo` + `Edit > Undo` give an auditable undo trail; every step's description
  matched the action taken.
- `File > Import/Export > Window Layout` through the native dialog works and round-trips.
- `get_graph_image` gives pixel-identical spectrum captures (s-13).
- `get_locations`/`set_selection` at every level, incl. `/Insert` for the blank node.

## Round 1 -> Round 2 delta

| # | Round-1 finding | Round 2 | Why |
|---|-----------------|---------|-----|
| 1 | Insert Peptide List doesn't resolve proteins (s-12) | **FIXED** | `send_key_stroke gridViewPeptides Ctrl+V` runs the grid's paste handler; all 12 peptides resolved, grid identical to s-12, inserted per-protein |
| 2 | Ion Types > B unreachable (s-05) | **PERSISTS** | root cause now known: the submenu hosts an `IonTypeSelectionPanel` control, not menu items; MethodRefine's "reconciliation" does not hold |
| 3 | Protein-metadata columns populated vs "empty" (s-10) | **PERSISTS** | tutorial text still stale; now also visible in s-15 headers and the s-16 completion row |
| 4 | Screen-capture consent blocks autonomy | **CHANGED** | pre-granted for this process by the orchestrator; no prompt seen in this run, but the per-process grant is unchanged |
| 5 | `import_fasta` strips empty proteins | **CHANGED** | not exercised — `Set-Clipboard` + `Edit > Paste` is now the runner's documented path and the `EmptyProteinsDlg` (Keep) reproduces s-04 exactly |
| 6 | Cyan overlap / caption-less controls / `textPeptideCount` | **PERSISTS** (partly) | no cyan captures this run; `textPeptideCount` still needs `perform_action set_value type=TextBox` |
| 7 | Direct Document Editing undriveable (s-16–22) | **CHANGED** | pick-lists (s-19, s-20) now drive and match; auto-complete (s-16, s-17) still blocked (and `send_text` corrupts the tree); hover (s-21, s-22) and drag still have no verb |

## Final status

**Status: ISSUES — completed end-to-end 2026-09-15T23:00Z** (blank document → saved
`MethodEditTutorial.sky` with 355 transitions → 5 exported SCIEX CSV files).

- **Completed end-to-end?** Yes. Every workflow step drove through MCP verbs; the two
  places the faithful UI path failed (auto-complete typing, hover/drag) have
  document-equivalent substitutes or are look-only steps.
- **Blocking vs cosmetic:** nothing blocks the *workflow*. Presentation blockers:
  s-16/s-17 (completion popup), s-21/s-22 (data tips). Cosmetic: s-05 (b-ion labels),
  s-10 (column widths), window size everywhere without an external resize.
- **Could a person following along with Claude driving get a presentable,
  tutorial-matching experience today?** Mostly yes — a clear step up from round 1.
  With the two `.view` files imported at their checkpoints and the window sized to
  1035x511, 21 of 28 screenshots match the tutorial closely enough that a viewer would
  recognise each one (s-04, s-08, s-11, s-12, s-13, s-14, s-18, s-19, s-20, s-23 are
  effectively identical). What they would **not** see: the b-ion overlay at s-05, the
  widened Sequence column at s-10, the auto-complete drop-downs at s-16/s-17 (Claude
  would say "I added YBL087C" without the reader seeing the suggestion list), and the
  data tips at s-21/s-22. And without the out-of-band resize every main-window frame
  would be a maximized 1920-wide window with the same content — correct, but not the
  tutorial's picture.
- **Priority fixes:** (1) a window-size/state verb (or a `size` argument on layout
  import) — biggest visual win for the least work; (2) `begin_edit` on the Targets tree
  so auto-completion can be shown (and make `send_text` on the tree safe); (3) descend
  into hosted-control menu items for `Ion Types`/`Charges`; (4) `send_key_stroke`
  fallback to form shortcuts (Delete, arrows); (5) hover/drag verbs; (6) refresh the
  stale tutorial text.
