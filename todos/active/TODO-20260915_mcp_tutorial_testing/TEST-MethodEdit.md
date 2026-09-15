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
