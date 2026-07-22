# TEST — Targeted Method Editing (MethodEdit)

**Status: WIP — partial (through s-04 of s-23).** Claimed by Brendan + Claude
(interactive session), 2026-07-22. This file is both the results log for
MethodEdit and the worked example of the `TEST-<Name>.md` format (README §6).

## Run context

- **Branch / PR:** `Skyline/work/20260609_native_file_dialog_automation` — PR #4313
- **Skyline:** `Skyline (64-bit : developer build) 26.1.1.202 (1412612eae)`
- **Connected PID:** 51856
- **Date:** 2026-07-22
- **Data folder:** `C:\Users\brendanx\Documents\MethodEdit`
  (`FASTA\`, `Library\yeast_cmp_20.hlf`, `Yeast_atlas\interact-prob.pep.xml` + mzXMLs — all present)
- **UI mode:** proteomic
- **Driver:** standalone interactive session (Brendan + Claude), pausing at every
  screenshot. Run was interrupted after s-04 to author the testing process doc,
  so s-05…s-23 remain.

## Screenshot checklist

| Screenshot | Section | Status | Note |
|-----------|---------|--------|------|
| (blank-document / proteomics-interface / protein-icon) | Getting Started | PASS | UI-element callouts, not doc-state checkpoints; confirmed blank doc (0/0/0/0) + protein icon top-right |
| s-01 | MS/MS Spectral Library | PASS | exact — Library tab, ☑ Yeast (Atlas) |
| s-02 | Background Proteome | PASS | "…contains 5801 proteins"; only the proteome-file **path** differs (install location) |
| s-03 | Digestion tab | PASS | exact — Trypsin [KR\|P], 0 missed, Background=Yeast, Enforce=None (first capture was all-cyan from Chrome overlap; retry OK) |
| s-04 | Pasting FASTA | PASS | after correcting import→paste; tree/spectrum/status-bar all match; cosmetic diffs only |
| s-05 | Pasting FASTA (b-ions + rank-1 transition) | BLOCKED | b-ion toggle unreachable (Finding #2); tree/transition state reproducible but not captured/compared |
| s-06 … s-23 | (Transition Settings → Export) | NOT RUN | session pivoted before these |

## Progress log

### Getting Started — PASS
- `Settings > Default` → "save current settings before switching?" → **No**. Settings reset.
- UI mode already `proteomic` (no change).
- **Screen-capture permission:** first `skyline_get_form_image` opened an
  in-Skyline consent dialog and returned "permission required"; Brendan granted
  it; re-capture then worked. (See Finding #3.)
- The three Getting-Started images are UI-element callouts, not document-state
  checkpoints; confirmed the equivalent state (blank document, protein icon in
  the upper-right).

### Creating a MS/MS Spectral Library (→ s-01) — PASS
- `Settings > Peptide Settings` → Library tab (`select_tab` by **Type**
  `TabControl`) → **Build**.
- Build Library: **Name** = "Yeast (Atlas)"; **Output path** set directly to
  `…\Library\Yeast (Atlas).blib` (equivalent to Browse→navigate→Save) → Next.
- **Add Files** → native `Add Input Files` dialog → path
  `…\Yeast_atlas\interact-prob.pep.xml` → `dismiss_with_accept_button`.
- **Score Threshold** column already `0.95` (PeptideProphet confidence) — matches
  the tutorial, no change → **Finish**.
- Library built (background), appeared in the Libraries list; `check_item
  "Yeast (Atlas)"` (idempotent) to enable it.
- **s-01 = exact match.**

### Creating a Background Proteome (→ s-02, s-03) — PASS
- Digestion tab → **Background proteome** = `<Add...>` → Edit Background Proteome.
- **Create** → native `Create Background Proteome` Save dialog →
  `…\FASTA\Yeast.protdb` → accept.
- **Add File** → native `Add FASTA File` dialog → `…\FASTA\sgd_yeast.fasta` → accept.
- Info dialog: *"The added file included 61 repeated protein sequences. Their
  names were added as aliases…"* → OK (normal dedup).
- Status line: *"The proteome file contains 5801 proteins."* — **s-02 match**
  (only the proteome-file path differs, by install location).
- OK → Digestion tab: Trypsin [KR\|P], 0 missed cleavages, Background=Yeast,
  Enforce uniqueness=None — **s-03 exact match** (first capture came back
  all-cyan from a Chrome overlap; a retry succeeded — Finding #4).
- OK to commit Peptide Settings.

### Pasting FASTA Sequences (→ s-04) — PASS (after correction)
- **First attempt used `skyline_import_fasta(Fasta.txt)`** → 5 prot / 25 pep /
  25 prec / 75 tran. **DIVERGENCE** — the tutorial's s-04 status bar shows **35
  proteins**. Root cause: `import_fasta` silently removed the 30 empty proteins
  (Finding #1).
- **Correction:** `Edit > Undo` (→ 0 proteins) → PowerShell `Set-Clipboard` with
  `Fasta.txt` (30,625 chars) → `Edit > Paste`. Skyline raised the
  **EmptyProteinsDlg**: *"This operation has added 30 new proteins with no
  peptides meeting your current filter criteria. Do you want to remove all empty
  proteins…?"* [Remove / Keep / Cancel] → **Keep** → **35 / 25 / 25 / 75**,
  matching s-04.
- Selected the first pasted peptide: `skyline_get_locations` (group → molecule)
  → `skyline_set_selection Molecule:/YAL005C/VDIIANDQGNR`.
- **s-04 = match:** empty proteins retained (YAL001C/002W/003W, then YAL005C
  expanded with its 16 peptides), Library Match "Yeast (Atlas) – VDIIANDQGNR,
  Charge 2" with identical y-ion ranking, status bar `4/35 · 1/25 · 1/25 · 1/75`.
  Cosmetic-only diffs: the Library Match title is clipped (my graph panel is
  narrower) and an Immediate Window was docked (leftover from the CLI import;
  since closed).

### Pasting FASTA — b-ions + rank-1 transition (→ s-05) — BLOCKED
- Goal: `View > Libraries > Ion Types > B` (show b-ions in purple), then expand
  the precursor and select the y7 (rank 1) transition.
- **Blocked** on the b-ion toggle — see Finding #2. Enumerated the transitions
  (`get_locations` → `y8+ / y7+ / y6+` under `Precursor:/YAL005C/VDIIANDQGNR/light++`),
  confirming the tree state s-05 expects, but did not toggle b-ions or capture
  the comparison. The block is **cosmetic** (spectrum annotation; no document
  impact), so the run could have continued past it.

## Findings & fix suggestions

### 1. [MCP tooling fidelity] `skyline_import_fasta` silently strips empty proteins
- **What:** `import_fasta` (→ `SkylineCmd --import-fasta`) removed 30 empty
  proteins → 5 vs. 35 proteins at s-04. The interactive `Edit > Paste` instead
  prompts (EmptyProteinsDlg: Remove/Keep/Cancel); the tutorial keeps them and
  later demonstrates "Remove Empty Proteins" explicitly.
- **Impact:** Not halting (recovered via paste), but **silently unfaithful** —
  would corrupt any tutorial that relies on empty-protein retention or a
  subsequent Remove-Empty step, and the divergence is only caught by checking
  counts.
- **Fix suggestions:** (a) runner reproduces paste via `Set-Clipboard` +
  `Edit > Paste` — **adopted** in README §4; (b) add a keep-empty-proteins
  option to the `import_fasta` tool (or surface the Remove/Keep choice);
  (c) at minimum, document the difference in the tool description.

### 2. [MCP capability gap] On-demand submenu leaves are unreachable (Ion Types)
- **What:** The ion-type leaves under `View > Libraries > Ion Types` (A/B/C/X/Y/Z),
  built in `DropDownOpening`, do not resolve via `skyline_click_main_menu_item`
  **or** `skyline_click_control_menu_item`; `perform_action get_children` on
  "Ion Types" returns `[]`. The Library Match graph's context menu is also
  unreachable: `get_children` on the `msGraphExtension` ContextMenu →
  *"msGraphExtension has no context menu."*
- **Impact:** For this step, cosmetic (b-ion display, no document change). But
  **any** tutorial step depending on an on-demand submenu leaf would be blocked.
- **Fix suggestions:** (a) make the menu-traversal path **open each submenu**
  (fire `DropDownOpening`) before matching so on-demand items populate — the doc
  for `click_control_menu_item` claims "each level's dropdown is opened first,"
  but it did not populate these; (b) the TODO records that graph context menus
  are invokable (`InvokeContextMenuItem` / `skyline_invoke_context_menu_item`
  via the graph's `ContextMenuBuilder`) — investigate why the **Library Match
  spectrum** graph exposes no context menu through `msGraphExtension`, and
  whether the ion-types path there differs from `Ion Types > B`.

### 3. [Environmental / harness] Screen-capture permission handshake blocks autonomy
- **What:** The first `skyline_get_form_image` of a session opens an in-Skyline
  consent dialog and returns "permission required" until a human grants it.
- **Impact:** **Halting for unattended runs** — a night-session sub-agent can't
  click the in-Skyline consent.
- **Fix suggestions:** a way to pre-grant/persist screen-capture permission
  (setting or CLI flag) for headless/autonomous runs. Until then, the human must
  grant it at session start (README §3 prerequisite).

### 4. [Environmental / harness] Capture redaction on window overlap (cyan)
- **What:** `get_form_image` returned a fully-cyan image when Chrome (the
  tutorial) overlapped the Skyline dialog (s-03); a retry after the overlap
  cleared succeeded. Partial-cyan on the main window's left edge is also just
  the browser being redacted.
- **Impact:** Not halting — a single retry works.
- **Fix suggestions:** keep non-Skyline windows off Skyline (README §3) and retry
  a cyan capture once. Optional MCP nicety: bring the target form to the
  foreground before capturing.

### 5. [Usage learning — not a bug] Caption-less controls & tree navigation
- Caption-less controls (`TabControl`, `SequenceTree`, `MsGraphExtension`) have an
  empty Label and must be addressed by **`type`**, not `label` (for `select_tab`,
  `get_children`).
- The Targets tree is **not** enumerable via `perform_action get_children`
  (returns `[]`); use `skyline_get_locations`
  (group→molecule→precursor→transition, optionally scoped by a parent locator) to
  get ElementLocators for `skyline_set_selection`. Worked cleanly.

### 6. [Tutorial-text — minor] Menu-path wording
- *"On the View menu, choose Libraries, then Ion Types, and click B"* is a
  3-level path (`View > Libraries > Ion Types > B`) that took menu enumeration to
  confirm. Fine for a human; noted for the runner. No change strictly required.

### Works-as-designed (positive signal)
- Native file dialogs drive cleanly: set the full path on the file-name field +
  `dismiss_with_accept_button` (Add Input Files, Create-Proteome Save, Add FASTA
  File all worked, including dialogs owned by nested modal wizards).
- Build Library score-threshold default is already `0.95` (no change needed).
- `check_item` is idempotent (safe vs. a toggling click).
- `select_tab` by Type works; menu enumeration via `get_children` works for
  statically-built menu levels.
- s-01 / s-02 / s-03 / s-04 all matched the reference images.

## Final status

- **Completed end-to-end?** No — **partial, through s-04 of s-23.** The session
  pivoted to authoring the testing process doc after s-04; s-05…s-23 (Transition
  Settings, GPM library, limit-peptides, insert protein/peptide lists, simple
  refinement, uniqueness, direct editing, export) are **not yet exercised**.
- **Blocking:** #3 (permission handshake) for *autonomous* runs. Cosmetic block:
  #2 (Ion Types) for the s-05 annotation. Fidelity trap: #1 (`import_fasta`).
  Environmental: #4.
- **Overall:** A user + Claude **can** drive MethodEdit through the core
  method-building steps (s-01…s-04) via the MCP with high-fidelity screenshot
  matches, **provided** the runner (a) uses the faithful `Set-Clipboard` +
  `Edit > Paste` path instead of `import_fasta`, and (b) has screen capture
  pre-granted. Finishing s-05…s-23 is the next step for this tutorial.
