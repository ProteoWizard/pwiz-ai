# TEST — Targeted Method Editing (MethodEdit)

**Status: CLAIMED by brendanx@BRENDANX-UW8 2026-09-15T22:10Z**

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
