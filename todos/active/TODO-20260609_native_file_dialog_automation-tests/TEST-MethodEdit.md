# TEST — Targeted Method Editing (MethodEdit)

**Status: COMPLETE — driven end-to-end to the export (s-23).** Claimed by Brendan
+ Claude (interactive session), 2026-07-22. Both the results log for MethodEdit
and the worked example of the `TEST-<Name>.md` format (README §6). One functional
blocker (s-12, send-key) and one blocked section (s-16–22, keystroke/mouse); all
other steps drove, most with exact screenshot matches.

## Run context

- **Branch / PR:** `Skyline/work/20260609_native_file_dialog_automation` — PR #4313
- **Skyline:** `Skyline (64-bit : developer build) 26.1.1.202 (1412612eae)`
- **Connected PID:** 51856
- **Date:** 2026-07-22
- **Data folder:** `C:\Users\brendanx\Documents\MethodEdit`
- **UI mode:** proteomic
- **Driver:** standalone interactive session (Brendan + Claude), pausing at every
  screenshot.

## Screenshot checklist

| Screenshot | Section | Status | Note |
|-----------|---------|--------|------|
| (blank/proteomics/protein-icon) | Getting Started | PASS | UI-element callouts; confirmed blank doc + protein icon |
| s-01 | MS/MS Spectral Library | PASS | exact |
| s-02 | Background Proteome | PASS | "…5801 proteins"; only proteome path differs (install location) |
| s-03 | Digestion tab | PASS | exact (first capture cyan from overlap; retry OK) |
| s-04 | Pasting FASTA | PASS | after correcting import→paste; tree/spectrum/status all match |
| s-05 | b-ions + rank-1 transition | PARTIAL | tree/selection/`2/75 tran` match; purple b-ion overlay absent (Finding #2) |
| s-06 | Transition Settings — Filter | PASS | exact (2,3 / 1 / y,b) |
| s-07 | Transition Settings — Library | PASS | exact (Pick 5) |
| s-08 | Document tree updated | PASS | exact — new charge-3 peptide + b5 rank 5 |
| s-09 | Peptide Settings — both libraries | PASS | exact (Atlas + GPM checked) |
| s-10 | Insert Protein List | DIVERGENCE | metadata columns populated vs. tutorial "empty" (Finding #3, stale tutorial) |
| s-11 | Peptide list pasted | PASS | Primary Peptides list; `6/70 pep` selection match |
| s-12 | Insert Peptides (per-protein) | BLOCKED | protein resolution not triggered → bare list (Finding #1, send-key gap) |
| s-13 | Find "IPEE" spectrum | PASS | exact — y6 r1 / b4 r2 (GPM peptide, unaffected by s-12) |
| s-14 | Simple Refinement | PASS | count exact: 70 → 64 peptides |
| s-15 | Peptide Uniqueness | VERB OK | form drives (YAL035W); content cascade-diverged from s-12 |
| s-16 … s-22 | Direct Document Editing | BLOCKED | auto-complete/pick-lists/hover/drag need send-key & mouse verbs (Finding #7) |
| s-23 | Preparing to Measure / Export | PASS | form exact ("Methods: 5"); exported 5 CSV files, correct column format |

## Progress log (condensed)

- **Getting Started** — PASS. `Settings > Default` (→ No to save). Proteomic
  already. **Screen-capture consent** granted by Brendan (Finding #4).
- **Spectral Library (s-01)** — PASS. Peptide Settings → Library → Build; Name
  "Yeast (Atlas)", output path set directly; Add Files → native dialog →
  `interact-prob.pep.xml`; Score Threshold already 0.95; Finish; checked.
- **Background Proteome (s-02, s-03)** — PASS. `<Add...>` → Create (native Save
  `Yeast.protdb`) → Add File (native `sgd_yeast.fasta`) → "61 repeated…aliases" OK
  → "5801 proteins". Digestion tab exact (s-03 retry after cyan).
- **Pasting FASTA (s-04)** — PASS after correction. `import_fasta` gave 5 vs 35
  proteins (Finding #5); Undo; `Set-Clipboard` + `Edit > Paste`; EmptyProteinsDlg
  → **Keep** → 35/25/25/75. Selected VDIIANDQGNR via `get_locations`.
- **b-ions + transition (s-05)** — PARTIAL. Selected y7 (rank 1); tree +
  `2/75 tran` match. `View > Libraries > Ion Types > B` unreachable (Finding #2);
  purple b-ions absent (cosmetic).
- **Transition Settings (s-06/07/08)** — PASS. Filter: charges `2, 3`, ion types
  `y, b` (Ion charges confirmed `1`). Library: Pick `5`. Doc → 28/31/155; tree
  shows new charge-3 first peptide + b5 rank 5.
- **GPM library (s-09)** — PASS. Edit List → Add → Name "Yeast (GPM)", Path set
  directly → checked. OK → doc grows to 182/219/1058.
- **Limit peptides/protein** — uncheck Atlas, Rank by **Expect**, Limit = **3**;
  count field is caption-less (`textPeptideCount`) — `set_form_value` by name/label
  failed; `perform_action set_value type=TextBox` worked (Finding #6). OK →
  47/47/223. `Refine > Remove Empty Proteins` → 19 proteins.
- **Insert Protein List (s-10)** — DIVERGENCE. Set-Clipboard `Protein List.txt`;
  `Edit > Insert > Proteins`; `perform_action paste` into grid. 17 proteins with
  Description/Sequence — **but Accession/Preferred Name/Gene/Species are
  populated** (UniProt values) where the tutorial says they'll be empty
  (Finding #3). Insert → 36; Remove Empty → 24.
- **Insert Peptide List (s-11, s-12)** — s-11 PASS (paste as bare list → "Primary
  Peptides", 70 peptides, `6/70 pep` selection match). Undo ×2. s-12 **BLOCKED**:
  `Edit > Insert > Peptides` + `perform_action paste` → Protein Name/Description
  **empty**; "Check for Errors" = "No errors" but still empty; Insert → peptides
  land as a **bare `peptides1` list**, not per-protein (Finding #1).
- **Simple Refinement (s-13, s-14)** — PASS. `Edit > Find` "IPEE" → IPEEYLDANVFR
  (YAL034W-A); spectrum exact (y6 r1 / b4 r2). `Refine > Advanced` min 5
  transitions/precursor → **70 → 64** (exact).
- **Peptide Uniqueness (s-15)** — VERB OK. Selected last protein (YAL035W in this
  doc; a peptide-list protein in the tutorial — s-12 cascade); `Edit > Unique
  Peptides` opened and rendered correctly (3 unique peptides + UniProt metadata).
  Content can't match s-15's protein. Cancelled without deleting.
- **Direct Document Editing (s-16–22)** — BLOCKED (not driven). Auto-completion
  (type→popup), pop-up pick-lists (hover drop-arrow + funnel/binoculars), data
  tips (hover), drag-and-drop are keystroke/mouse interactions with no MCP verb
  (Finding #7). Documented, not probed (avoids corrupting the doc).
- **Preparing to Measure / Export (s-23)** — PASS. Transition Settings →
  Prediction: CE=SCIEX, DP=SCIEX; Instrument: Max m/z 1800. `File > Save` →
  native Save As → `MethodEditTutorial.sky`. `File > Export > Transition List` →
  Multiple methods, Ignore proteins, Max 75 → form **exact match** ("Methods:
  5", instrument defaulted to SCIEX) → native Save → `Yeast_list`. **5 CSV files
  written** (`Yeast_list_0001..0005.csv`) with the tutorial's column order
  (precursor m/z, product m/z, dwell, extended peptide, DP, CE); only the
  extended-peptide prefix shows the s-12 cascade (`peptides1.` vs protein name).

## Findings & fix suggestions

### 1. [MCP capability gap — send-key] Insert Peptide List doesn't resolve proteins
- **What:** `Edit > Insert > Peptides` + `perform_action paste` fills the Peptide
  Sequence column but leaves **Protein Name/Description empty**; "Check for Errors"
  reports no errors without resolving; Insert then adds the peptides as a **bare
  `peptides1` list** instead of associating each with its background-proteome
  protein (the whole point of the form, s-12).
- **Root cause:** the peptide→protein resolution is driven by the grid's
  **clipboard paste event (real Ctrl+V)**. `perform_action paste` sets cells
  directly and bypasses it; there is **no MCP verb to send a raw keystroke** —
  and "send-key" is explicitly a *remaining gap* in this TODO ("`SelectTreeNode`
  + tree pop-up pick-lists; **send-key**; …").
- **Impact:** Halts faithful reproduction of s-12 and **cascades** — the document
  structure diverges (bare list vs. per-protein) for all later structure-dependent
  screenshots (s-15+). Transition-driven counts (s-14) still match.
- **Fix suggestions:** (a) add a **send-key / paste-via-clipboard verb** so the
  grid's real paste handler runs; or (b) have `perform_action paste` on a
  `PasteDlg` grid route through the form's paste handler (trigger resolution); or
  (c) expose a dedicated "insert peptides/proteins from text" service verb that
  performs the resolution server-side.

### 2. [MCP capability gap] On-demand submenu leaves unreachable (Ion Types)
- **What:** `View > Libraries > Ion Types > {A/B/C…}` leaves (built in
  `DropDownOpening`) don't resolve via `click_main_menu_item` or
  `click_control_menu_item`; `get_children` on "Ion Types" returns `[]`; the
  Library Match graph reports *"msGraphExtension has no context menu."*
- **Impact:** Cosmetic here (spectrum annotation; s-05). Any step depending on an
  on-demand submenu leaf would be blocked.
- **Fix suggestions:** open each submenu (fire `DropDownOpening`) before matching;
  and investigate why the spectrum graph's `ContextMenuBuilder` menu isn't exposed
  (the TODO says graph context menus are invokable).
- **⚠ UPDATE — reconciled by the MethodRefine run (see `TEST-MethodRefine.md`
  Finding #2):** that run **succeeded** at `View > Libraries > Ion Types > B`
  (b-ions rendered) and drove graph right-click menus (Set Threshold, Create
  Regression, Legend) via `click_control_menu_item` with **`control=""` (empty
  control string)**. So this finding is **not a hard gap** — graph context menus
  and the Ion Types leaf ARE reachable. My MethodEdit attempts likely used the
  wrong control argument (named control / `msGraphExtension` path) or hit a
  transient unpopulated-submenu state. **Action:** re-verify the exact approach;
  treat "graph menu → `control=""`" as the canonical method and downgrade this
  from "capability gap" pending that re-test.

### 3. [Tutorial-text — stale] Protein-metadata columns now populated (s-10)
- **What:** The tutorial says the Accession/Preferred Name/Gene/Species columns of
  the Insert Protein List grid "will be empty"; current Skyline **populates them
  from UniProt** (P-accessions, `*_YEAST` names, genes, "Saccharomyces c…") via
  the background-proteome protein-metadata loader.
- **Impact:** Not a bug — *extra correct* metadata; environment-dependent (needs
  internet + async resolution). The text and `s-10.png` are outdated.
- **Fix suggestion:** update the tutorial text/screenshot to reflect populated
  metadata (or note the resolution feature and its internet dependency).

### 4. [Environmental / harness] Screen-capture permission handshake blocks autonomy
- First `skyline_get_form_image` needs an in-Skyline human grant; blocks unattended
  runs. Persists per Skyline process. Fix: a pre-grant/persist path. (README §3.)

### 5. [MCP tooling fidelity] `skyline_import_fasta` strips empty proteins
- `import_fasta` silently removed 30 empty proteins (5 vs 35 at s-04); interactive
  paste prompts (Remove/Keep/Cancel). Runner uses `Set-Clipboard` + `Edit > Paste`
  (README §4). Fix: keep-empty option and/or document the difference.

### 6. [Environmental] Capture redaction on window overlap; and usage learnings
- Cyan capture on Chrome overlap → retry (s-03). Caption-less controls addressed by
  **Type** not label; the Targets tree isn't `get_children`-enumerable (use
  `get_locations`); the caption-less `textPeptideCount` needed
  `perform_action set_value type=TextBox` (not `set_form_value`).

### 7. [MCP capability gap — send-key + mouse] Direct Document Editing undriveable
- **What:** The entire "Direct Document Editing" section (s-16–22) is
  keystroke/mouse-driven: **auto-completion** (type characters → suggestion popup,
  s-16/17/18), **pop-up pick-lists** (hover a node's drop-arrow, click
  funnel/binoculars, s-19/20), **data tips** (hover, s-21/22), and **drag-and-drop**
  to reorder proteins. None map to a current MCP verb.
- **Root cause:** no **send-key** verb, no **mouse hover/drag**, no **tree pop-up
  pick-list** support — all three are on the TODO's own "remaining gaps" list.
- **Impact:** the whole section can't be driven; blocks any tutorial that teaches
  in-tree editing. (Not probed here to avoid corrupting the document.)
- **Fix suggestions:** add send-key + a tree pick-list verb (and, longer-term, a
  hover/data-tip and drag-reorder verb). These also unblock the s-12 peptide
  resolution (Finding #1).

### Works-as-designed (positive)
- Native file dialogs (open + save), tab selection, `check_item`/`uncheck_item`,
  combo/textbox sets, `Find`, `Refine > Advanced`, `Remove Empty Proteins`, grid
  paste of a protein list, `rename_node`, direct locator selection, the
  Transition-List **export** (multi-file), and document **Save** all worked.
  s-01…s-09, s-11, s-13, s-14, s-23 matched (s-05 partial, s-10 stale-tutorial).

## Final status

- **Reached the end** of the tutorial: built the method and **exported the SCIEX
  transition list** (5 CSV files). Every menu/dialog-driven step drove.
- **Screenshot outcomes:** full matches — s-01, 02, 03, 04, 06, 07, 08, 09, 11,
  13, 14, 23. Partial — s-05 (Finding #2, b-ion overlay). Stale tutorial — s-10
  (Finding #3, UniProt metadata). Verb-OK-but-cascaded — s-15. Blocked — s-12
  (Finding #1), s-16–22 (Finding #7).
- **Two things stop a *faithful, fully-autonomous* run:**
  1. **s-12 / s-16–22 need keystroke & mouse verbs** (send-key, tree pick-lists,
     hover, drag) — Findings #1 and #7. s-12 also causes a structural cascade
     (bare peptide list) that diverges later structure-dependent screenshots,
     though transition-driven counts and the export still line up.
  2. **Screen-capture consent** needs a one-time human grant (Finding #4).
- **Everything else works well.** With the faithful `Set-Clipboard`+`Edit>Paste`
  substitution (Finding #5) and screen capture granted, a user + Claude can drive
  MethodEdit from a blank document to an exported transition list via the MCP,
  with high-fidelity screenshot verification at nearly every checkpoint.
- **Priority fixes for Nick + Brendan:** (1) a **send-key / real-paste verb**
  (unblocks s-12 and the auto-completion in s-16–18, the biggest wins); (2) tree
  **pick-list** + **hover/drag** verbs (s-19–22); (3) **pre-grantable screen
  capture** for autonomy; (4) an `import_fasta` keep-empty option; (5) update the
  **s-10 tutorial text** for populated metadata; (6) the **Ion Types** on-demand
  submenu / graph context menu.
