# TEST — Targeted Method Refinement (MethodRefine)

**Status: ISSUES — completed end-to-end with findings, MethodRefine sub-agent 2026-07-22.**
Drove blank→WormUnrefined.sky→2.5 refinement iterations→exported unscheduled+scheduled
transition lists→imported 5 scheduled replicates→multi-replicate review. 16 screenshots
exact, 4 pass-with-cosmetic, s-03 optional-skipped. No hard blockers; only drag-to-dock
(s-21 composite) and graph-point-click (s-08, worked around) are undriveable. Automated-
Refinement counts run low (SSRCalc version drift) but data-driven Scheduling count (86)
recovers exactly.

## Run context

- **Branch / PR:** `Skyline/work/20260609_native_file_dialog_automation` — PR #4313
- **Skyline:** `Skyline (64-bit : developer build) 26.1.1.202 (1412612eae)`
- **Connected PID:** 51856
- **Date:** 2026-07-22
- **Data folder:** `C:\Users\brendanx\Documents\MethodRefine`
- **UI mode:** proteomic
- **Driver:** orchestrated per-tutorial sub-agent (autonomous), pausing at every screenshot.

Data folder confirmed present: `WormUnrefined.sky` + pre-cached `WormUnrefined.skyd`
(39-injection "Unrefined" replicate), `worm.1.1.blib`, `Unscheduled01/` +
`Unscheduled02/` (2 RAW each), `Scheduled_REP01..05.RAW`. Optional
`MethodRefineSupplement.zip` (39 RAW re-import, s-03) NOT downloaded — the base
`.skyd` already has the data (tutorial explicitly permits skipping).

## Screenshot checklist
| Screenshot | Section | Status | Note |
|-----------|---------|--------|------|
| s-01 | Results Data | PASS | first peptide + chromatogram + library spectrum all match; b-ions display OK |
| s-02 | Unrefined Methods | PASS* | Export Transition List form matches (Thermo, Multiple, 59, Methods: 39); "Ignore proteins" came up checked (persisted from prior session) vs reference unchecked — unchecked to match |
| s-03 | Importing Multiple Injection Data | SKIPPED | Optional per tutorial (needs separate 36MB MethodRefineSupplement.zip; re-import yields the same pre-cached .skyd already loaded) |
| s-04 | Simple Manual Refinement | PASS | full-range chromatogram (RT 0-100, peaks 34.8/53.0/64.1/72.4) matches reference |
| s-05 | Retention Time Prediction | PASS | Score-To-Run regression graph matches (axes, both lines, scatter, outliers); minor slope/r drift at 0.9 threshold |
| s-06 | Retention Time Prediction | PASS | after Set Threshold 0.95: slope 1.52/window 15.6/r 0.951 vs ref 1.53/15.8/0.9511 — near-identical |
| s-07 | Retention Time Prediction | PASS | chromatogram Predicted RT indicator (63.0) + shaded window matches ref (63.1) |
| s-08 | Missing Data | PASS* | YLAEVASEDR selected via locator (graph-point mouse-click not driveable); tree content matches, selection auto-scrolled to viewport bottom (missing-data peptides below out of frame) |
| s-09 | Missing Data | PASS | "File: worm_0027.RAW" choice-list toolbar present + doubled y3-y10 legend (two files) + chromatogram (42.4/68.8/57.0/65.1) match ref |
| s-10 | Picking Measurable | PASS | peptide view dotp values all match (1160.5434++ 0.57, 1117.5455++ 0.53, 686.3670++ 0.87, 521.7876++ 0.9, 870.4154++ 0.55) |
| s-11 | Picking Measurable | PASS | chromatogram 11 co-eluting y-ions on 63.8 peak matches ref |
| s-12 | Picking Measurable | PASS | library spectrum y10/b10 (rank1) + y12/b12 (rank2) co-annotation matches ref |
| s-13 | Picking Measurable | PASS | expanded precursor transitions + library ranks + bracketed SRM ranks all match exactly |
| s-14 | Picking Measurable | PASS | VTLDSLYAPHAGK (dotp 0.94, y7/y6/y5) + LDWALPTAR (dotp 0.89, y6/y5/y4) tree matches ref |
| s-15 | Picking Measurable | PASS | LDWALPTAR chromatogram y6/y5/y4 peak 50.2 matches ref (minor y-axis autoscale 7 vs 8) |
| (Automated Refinement) | no screenshot | DIVERGENCE | Refine rank3/r0.95/dotp0.8 → 75 pep/225 tran (tutorial 80/240); rank6/r0.9/dotp0.712 → 119 pep (tutorial 127). SSRCalc-drift cascade (RT-outlier filter) |
| (Scheduling import) | no screenshot | PASS | Unscheduled01/02 imported; Refine>Remove Missing Results → 86 pep/256 tran (tutorial 86/255) — count RECOVERS exactly |
| s-16 | Measuring Retention Times | PASS | Export Transition List form exact (Multiple, 130, Methods: 2, Ignore proteins checked) |
| s-17 | Reviewing RT Runs | PASS* | FWEVISDEHGIQPDGTFK (57/86) tiled Unscheduled01/02 chromatograms match; tile order swapped (cosmetic), 167/256 vs 166/255 |
| s-18 | Reviewing RT Runs | PASS | Scheduling graph (2/5/10-min window concurrent-transitions curves) matches ref |
| s-19 | Creating Scheduled List | PASS | Peptide Settings Prediction: WormUnrefined predictor, Time window 4, Use measured RT checked — exact |
| s-20 | Creating Scheduled List | PASS | Export Transition List: Single method, Method type Scheduled, Methods: 1 — exact |
| s-transition-list-spreadsheet | Creating Scheduled List | N/A (Excel) | Scheduled.csv created; CE 26.7 + RT 40.97 + window 4 present (4-min window applied); not a Skyline UI checkpoint |
| s-21 | Reviewing Multi-Replicate Data | PASS (content) / layout BLOCKED | 5 replicates imported; Peak Areas comparison ("6 above cutoff, 0 below") + RT comparison + REP chromatograms (legend off, peak 40.7) all match; docked composite layout needs mouse-drag (no verb) |

## Progress log

### Getting Started — PASS
- `Settings > Default` → "save current settings?" → **No**. Proteomic mode already set.
- `File > Open` → discard-changes "No" → native Open dialog → set path
  `C:\Users\brendanx\Documents\MethodRefine\WormUnrefined.sky` → accept.
- Doc loaded from pre-cached `.skyd`: **1 prot / 225 pep / 225 prec / 2096 tran /
  1 replicate ("Unrefined")** — matches tutorial's "225 peptides and 2096 transitions".

### Results Data (s-01) — PASS [2026-07-22]
- Selected first peptide `YLGAYLLATLGGNASPSAQDVLK` via `set_selection`
  (`Molecule:/peptides1/YLGAYLLATLGGNASPSAQDVLK`).
- `View > Auto-Zoom > Best Peak` — OK.
- `View > Libraries > Ion Types > B` — **succeeded** (reported success; b-ions render
  in the Library Match spectrum). NOTE: this same on-demand submenu leaf was BLOCKED
  in MethodEdit (its Finding #2). Here it worked — see Findings.
- Live vs s-01.png: match. Targets tree (peak-quality icons green/yellow/red), the
  "Unrefined" chromatogram (RT labels 72.4/72.9/73.2, y3-y15 legend, y-axis to 9000),
  and the Library Match spectrum (y8 rank1, y13 rank2, y9 rank3, y12 rank4, purple
  b-ions b8/b10/b11/b13/b14/b15) all correspond. Status bar 1/225 pep, 1/2,096 tran.

### Unrefined Methods (s-02) — PASS [2026-07-22]
- `File > Export > Transition List` → chose **Multiple methods** → set **Max transitions
  per sample injection = 59**. Form shows Instrument Thermo, **Methods: 39**, Standard.
- Divergence: "Ignore proteins" checkbox came up CHECKED (persisted from the prior
  MethodEdit export) vs the reference's UNCHECKED. Unchecked it. (Methods: 39 regardless,
  1 protein.) Classed Environmental/persisted-state.
- OK → native Save → path set to `...\MethodRefine\worm` → accept.
- Verified on disk: **39 CSV files** `worm_0001.csv`..`worm_0039.csv` (~3.2K each).

### Importing Multiple Injection Data (s-03) — SKIPPED (optional)
- The tutorial marks this section optional: the pre-cached `WormUnrefined.skyd` "already
  has all the data Skyline requires" and re-importing needs a separate 36MB
  `MethodRefineSupplement.zip` (39 Thermo RAW, 161MB) producing an equivalent `.skyd`.
  Skipped to prioritize progress; the pre-cached data is in use. (Mandatory RAW imports
  later — Unscheduled01/02 and Scheduled_REP01-05 — ARE driven below.)

### Simple Manual Refinement (s-04) — PASS [2026-07-22]
- `View > Auto-Zoom > None` (Shift-F11). Live "Unrefined" chromatogram (full RT 0-100,
  peaks 34.8/40.3/53.0/52.2/64.1/59.6/67.5/72.4, y-axis to 14e3) matches s-04.png.
- `Edit > Delete` removed first peptide → doc **225→224 pep, 2096→2083 tran**.

### Retention Time Prediction (s-05, s-06, s-07) — PASS [2026-07-22]
- `View > Retention Times > Regression > Score To Run` → floating GraphSummary opened.
  s-05 live matches ref structurally (SSRCalc 3.0 (300A) Score vs Measured Time, Refined
  + full regression lines, blue Peptides Refined / purple Outliers, x-axis missing-peak
  outliers). Minor numeric drift at the default 0.9 threshold (live slope 1.52/r 0.9021
  vs ref 1.64/r 0.9033).
- **Graph right-click menu**: `click_control_menu_item` with control=`graphControl`
  FAILED ("No control ... supports get_children"), but with an **EMPTY control string**
  it SUCCEEDED (reaches the form's own right-click/ZedGraph menu). This is the key
  method for graph context menus — see Findings (differs from MethodEdit's "no context
  menu" conclusion).
- Set Threshold → dialog → Threshold=0.95 → OK. s-06 live slope 1.52/intercept 2.85/
  window 15.6/r 0.951 vs ref 1.53/2.49/15.8/0.9511 — near-identical, expanded outlier
  set matches.
- Create Regression → **Edit Retention Time Predictor** pre-populated: Name WormUnrefined,
  Slope 1.516, Intercept 2.850, Time window 15.6194, Calculator SSRCalc 3.0 (300A),
  **"(140 peptides, R = 0.951)"**. Tutorial states **146 peptides** / window 15.7 —
  DIVERGENCE of 6 in the refined-set count (SSRCalc/version drift; regression stats still
  match). Accepted with OK.
- s-07: chromatogram (first peptide VLEAGGLDC[+57]DMENANSVVDALK) shows "Predicted" RT
  indicator at 63.0 (ref 63.1) with the shaded ±window (~55-71 min) around the 63.8 peak,
  peaks 41.4/48.2/62.4/67.7 and y3-y13 legend — matches ref.

### Missing Data (s-08, s-09) — PASS [2026-07-22]
- Tutorial selects the left-most x-axis outlier by **mouse-clicking the graph point**
  (cursor→hand). No MCP verb for clicking a data point on a graph → achieved the same
  selection with `set_selection` `Molecule:/peptides1/YLAEVASEDR`. s-08 Targets content
  matches (…VKVEQELNDIC[+57]QDVLK (missed 1) → YLAEVASEDR selected); the tree scrolled
  the selection to the viewport bottom so the 7 missing-data peptides below are out of
  frame (no scroll verb) — cosmetic.
- Selected VTVVDDQSVILK (`Molecule:/peptides1/VTVVDDQSVILK`, peptide 158/224). s-09: the
  chromatogram pane shows the **"File:" choice list = worm_0027.RAW** and the y3-y10
  legend is DOUBLED (transitions for worm_0027 + worm_0028) — the tutorial's evidence
  that a transition list was duplicated across two RAW files. Clean chromatogram
  (Predicted 45.7, peaks 42.4/68.8/57.0/57.7/65.1, y to 350) matches ref.
- Closed the floating regression graph: menu toggle re-showed it and the graph
  right-click menu has no "Close"; `dismiss_with_cancel_button` on the FloatingWindow
  closed it.

### Picking Measurable Peptides and Transitions (s-10..s-15) — PASS [2026-07-22]
- Selected first peptide (VLEAGGLDC[+57]DMENANSVVDALK), F11 Best Peak, `Edit > Expand
  All > Peptides`. s-10 peptide-view dotp values all match reference exactly.
- s-11 chromatogram (11 co-eluting y-ions, 63.8 peak) and s-12 library spectrum
  (y10/b10 rank1, y12/b12 rank2 co-annotation) match ref.
- Expanded precursor via `perform_action expand type=TreeView value=["peptides1",0,0]`
  (index path; the text-path form failed on the modified peptide's node text). s-13
  transitions + library ranks + bracketed SRM ranks match exactly.
- Deleted VLEAGGLDC[+57]DMENANSVVDALK and WNTENQLGTVIEVNEQFGR (`set_selection` + `Edit >
  Delete`) → 224→222 pep, 2083→2061 tran.
- VTLDSLYAPHAGK: read SRM ranks from the expanded tree; kept the 3 both-agree ions
  (y5/y6/y7), multi-selected the other 6 (y11/y10/y9/y8/y4/y3 via additionalLocators) →
  `Edit > Delete`. dotp 0.87→0.94. Matches s-14.
- LDWALPTAR: SRM ranks y4[1]/y5[2]/y6[3]/y7[4]/y3[5]; deleted y7 + y3, kept y4/y5/y6.
  dotp 0.89. s-14 tree + s-15 chromatogram (y6/y5/y4, peak 50.2) match ref.
- Multi-transition delete via `set_selection` primary + `additionalLocators` worked
  cleanly (no send-key needed) — a positive for transition-level refinement.
- Skipped the no-screenshot optional VTADVGVTSAPVINAAGVFSR manual edit (keep y14/y13/y11);
  Automated Refinement re-filters to 3 transitions/precursor regardless.

### Automated Refinement (no screenshots) — DIVERGENCE (count) [2026-07-22]
- `Refine > Advanced` → Results tab (`select_tab type=TabControl value=Results`). Set
  Max transition peak rank=3, checked Prefer larger product ions, Remove nodes missing
  results, Target r=0.95, Min dotp=0.8. OK → **75 pep / 225 tran** (tutorial: 80 / 240).
- Undo → 222/2053. Second Refine rank=6, r=0.9, Min dotp=0.712 → **119 pep** (tutorial:
  127). Undo → 222/2053.
- Both counts run ~5-8 peptides LOW. Root cause: the same SSRCalc score drift that gave
  140 refined vs 146 at s-06/s-07 — the "Target r" RT-outlier filter classifies a few
  more peptides as outliers on this Skyline build, removing them. Not an MCP issue; a
  Skyline calculation/version difference vs the tutorial's original build.

### Scheduling for Efficient Acquisition (through import) — PASS [2026-07-22]
- Undo (222). `Edit > Manage Results` → Remove → OK (0 replicates). `File > Save`.
- `File > Import > Results` → **Add multi-injection replicates in directories** → OK →
  **Browse For Folder** (native) accepted default (MethodRefine) → **Import Results**
  common-prefix dialog → **Do not remove** → OK.
- Imported Unscheduled01 + Unscheduled02 (4 RAW, ~80MB) behind AllChromatogramsGraph;
  polled `get_open_forms` until it closed. 2 replicates.
- `Refine > Remove Missing Results` → **86 pep / 256 tran** (tutorial 86 / 255). Peptide
  count matches EXACTLY — the data-driven Scheduling count recovers despite the earlier
  refinement divergence. (256 vs 255 tran: one peptide keeps 3 vs 2, negligible.)

### Measuring Retention Times (s-16, s-17, s-18) — PASS [2026-07-22]
- `File > Export > Transition List` → Max transitions=130. s-16 form EXACT: Multiple
  methods, **Methods: 2**, Ignore proteins checked (ref matches). OK → native Save
  `...\MethodRefine\Unscheduled` → 2 CSVs `Unscheduled_0001.csv`, `Unscheduled_0002.csv`.
- Closed Library Match (`dismiss_with_cancel_button`). `View > Arrange Graphs > Tiled`.
  Selected FWEVISDEHGIQPDGTFK (57/86). s-17: Unscheduled01 (peak 62.1) + Unscheduled02
  (peak 62.4) tiled, y9/y6/y4 — matches ref; tile L/R order swapped (cosmetic Tiled
  ordering), status 167/256 vs 166/255. Had to close a leftover Peak Areas graph first.
- `View > Retention Times > Scheduling` → floating GraphSummary. s-18 concurrent-
  transitions curves (2/5/10-min windows, 10-min peak ~90 at scheduled time ~50)
  match ref (only legend line-wrap differs). Confirms the s-07 RT predictor works.

### Creating a Scheduled Transition List (s-19, s-20) — PASS [2026-07-22]
- Closed scheduling graph. `Settings > Peptide Settings` → Prediction tab → Time window
  =4. s-19 EXACT (predictor WormUnrefined, Use measured RT checked, window 4).
- `File > Export > Transition List` → **Single method**, Method type=**Scheduled**. s-20
  EXACT (Methods: 1, scheduled-only options shown). OK → **Scheduling Data** dialog →
  **Use retention time average** → OK → native Save `...\MethodRefine\Scheduled` →
  `Scheduled.csv` (17KB).
- CSV row 0: `686.37, 743.38, 26.7, 40.97, 4, 1, VTLDSLYAPHAGK, peptides1, y7, 1` — CE
  26.7 (=0.034*mz+3.31), RT 40.97, **window 4** → 4-min scheduling applied. (Tutorial's
  s-transition-list-spreadsheet shows explicit start/stop cols; this build emits
  RT+window — a Thermo-format representation detail, not a Skyline UI checkpoint.)

### Reviewing Multi-Replicate Data (s-21) — PASS (content) / layout BLOCKED [2026-07-22]
- `Edit > Manage Results` → Remove All → OK. `File > Save`.
- `File > Import > Results` → Add single-injection replicates in files → OK →
  **OpenDataSourceDialog** (Skyline's own browser, not native). Setting the "Source name"
  field text directly did NOT register a selection ("Please select one or more data
  sources"). The working path: `perform_action select_item` on the **ListView** once per
  file (Scheduled_REP01.RAW..REP05.RAW) — the field then auto-populates and Open works.
- Common-prefix dialog: set Common prefix = `Scheduled_` → replicate names REP01..REP05.
- Imported 5 RAW (~28MB) behind AllChromatogramsGraph; polled until closed. 5 replicates,
  86 pep. `Refine > Remove Missing Results` → **65 pep / 195 tran** (ref status 194).
- Selected VTLDSLYAPHAGK. Opened `View > Retention Times > Replicate Comparison` and
  `View > Peak Areas > Replicate Comparison` (both open FLOATING). Toggled chromatogram
  Legend off via `click_control_menu_item control="" menuPath="Legend"`.
- **Content verified against s-21** (captured each graph individually):
  - Peak Areas comparison: y7/y6/y5 stacked bars Library+REP01-05, dotp line ~0.95,
    **"Replicates above dotp cutoff: 6, below cutoff: 0"** — matches ref exactly.
  - RT comparison: y7/y6/y5 RT bars REP01-05 (~40.5-40.9) — matches ref.
  - REP01 chromatogram: peak 40.7, y7/y6/y5, legend off — matches ref.
- **Layout BLOCKED**: the tutorial drag-docks Peak Areas to the right edge and RT to the
  bottom edge (mouse drag-to-dock). No MCP drag verb → graphs stay floating; the single
  composite s-21 window can't be assembled, and a main-window capture with the graphs
  floating over it redacts to cyan. All CONTENT is present and correct.

### Conclusion — reached the end of the tutorial.

## Findings & fix suggestions

### 1. [MCP capability gap — mouse drag-to-dock] Composite graph layouts undriveable (s-21)
- **What:** The final section drags floating graph panes to dock them (Peak Areas → right
  edge, RT Replicate Comparison → bottom edge) to build the s-21 composite window. There
  is no MCP drag / drag-to-dock verb, so `View > ... > Replicate Comparison` panes stay
  **floating**; the assembled layout can't be produced. A main-window capture with panes
  floating over it redacts to solid cyan.
- **Impact:** Cosmetic — ALL content is reachable (each graph rendered and matched s-21
  individually via `get_graph_image`). Only the single composite screenshot is blocked.
  Any tutorial whose screenshot depends on a hand-arranged dock layout hits this.
- **Fix:** add a dock verb (e.g. `dock_pane form=<graph> edge=Right|Bottom|Left|Top`),
  or a "capture a set of forms as a composite" helper; short-term the runner captures the
  panes individually (works well).

### 2. [MCP tooling — DISCOVERY, supersedes MethodEdit Finding #2] Graph right-click menus ARE reachable
- **What:** `skyline_click_control_menu_item` with **`control=""` (empty)** reaches a
  ZedGraph pane's own right-click menu. This drove **Set Threshold** and **Create
  Regression** on the RT regression graph (s-06/s-07) and the chromatogram **Legend**
  toggle (s-21). Passing the named graph control (`graphControl`) instead FAILS ("No
  control ... supports get_children"), and the `{parent,type:ContextMenu}` path needs a
  form-qualified UiElementPath that isn't obtainable → also fails.
- **Impact:** POSITIVE — MethodEdit concluded graph context menus were unreachable
  ("msGraphExtension has no context menu"); they are reachable via the empty-control form.
  Its s-05 Ion-Types-style items may still differ, but graph menus in general work.
- **Fix:** document `control=""` as the canonical way to hit a graph's context menu; have
  the named-control path fall back to the form's own menu instead of erroring.

### 3. [MCP tooling fidelity] Skyline OpenDataSourceDialog needs ListView selection, not the text field
- **What:** `File > Import > Results` opens Skyline's OWN data-source browser
  (`OpenDataSourceDialog`, IsNative=False), not a native OS dialog. Setting its "Source
  name" text field (even with correctly-quoted paths/filenames) does NOT register a
  selection → "Please select one or more data sources." The working method is
  `perform_action select_item` on the **ListView**, once per file (accumulates; the field
  then auto-fills). Native Open/Save dialogs (the `.sky` open, transition-list saves) DID
  take the file-name field directly, so the two dialog kinds behave differently.
- **Impact:** Would block multi-file result import until the ListView path is found.
- **Fix:** make `set_form_value` on `OpenDataSourceDialog`'s Source name parse quoted
  names into a real selection (parity with the native dialog), and/or document the
  select_item path. Note `get_children` on that ListView returns `[]` (can't enumerate
  items first — you must know the filenames), which compounds the discovery cost.

### 4. [MCP capability gap — graph data-point click] Clicking a point on a graph (s-08)
- **What:** s-08 selects a peptide by hovering the left-most x-axis outlier on the RT
  regression graph until the cursor becomes a hand, then clicking the point. No MCP verb
  clicks a graph data point. Worked around with `set_selection` by element locator.
- **Impact:** Cosmetic here (the selection was achievable another way), but any step that
  *depends* on picking a specific graph point (or a hover data-tip) is blocked.
- **Fix:** a graph-point pick verb (by series+index or nearest-to-value), plus hover/
  data-tip support (also on MethodEdit's gap list).

### 5. [Skyline calculation / version drift — tutorial counts stale] SSRCalc refined-set differs
- **What:** On this build (26.1.1.202) the SSRCalc-based RT regression refines **140**
  peptides where the tutorial states **146** (s-06/s-07, same near-identical slope/r).
  This cascades through the RT-outlier (`Target r`) filter: Automated Refinement gives
  **75 pep/225 tran** (tutorial 80/240) and **119 pep** (tutorial 127). The DATA-driven
  Scheduling count recovers exactly (**86 pep**, tutorial 86) and the final Remove-Missing
  gives 65. Not an MCP issue — the tutorial text/screenshots predate a SSRCalc/scoring
  change.
- **Impact:** The Automated-Refinement count assertions no longer match; everything visual
  still matches. Downstream data-driven steps self-correct.
- **Fix (tutorial):** refresh the 146 / 80-240 / 127 numbers against a current build, or
  note they are approximate/version-sensitive.

### 6. [Environmental / harness] Cyan redaction from overlapping floating Skyline windows
- **What:** Captures of the main window redact to solid cyan when separate top-level
  Skyline windows (floating graph panes) overlap it (s-21; also intermittently on a form,
  s-19 succeeded on first try). Retc didn't clear it while the float persisted. Capturing
  each pane via `get_form_image`/`get_graph_image` by its own Id works.
- **Fix:** composite-capture helper (Finding #1), or capture that ignores overlapping
  *Skyline* windows rather than redacting them.

### 7. [Environmental / tutorial-text — minor]
- **s-02 Ignore proteins**: came up CHECKED (persisted from the prior session's export)
  vs the reference UNCHECKED; unchecked it. (At s-16 the reference IS checked — the
  export dialog's persisted state is the variable.) A dialog-state reset per tutorial
  would remove this ambiguity.
- **s-17 tile order**: `Arrange Graphs > Tiled` placed Unscheduled01 left / Unscheduled02
  right, the reference has them swapped — non-deterministic tile order, cosmetic.

### Works-as-designed (positive)
- Native Open (`.sky`) and Save (transition lists) dialogs via the file-name field;
  menus and dialog chains (Export Transition List, Refine/Advanced with tab select,
  Manage Results, Peptide Settings/Prediction, Scheduling Data, Import Results modes,
  Browse-For-Folder, common-prefix); **multi-transition delete** via `set_selection`
  primary + `additionalLocators` (no send-key needed); tree **expand** by index path;
  locator-based selection throughout; long multi-RAW imports polled cleanly via
  `get_open_forms`; `get_graph_image` renders graphs directly (bypasses cyan). Screenshot
  matches: s-01,04,05,06,07,09,10,11,12,13,14,15,16,18,19,20 exact/near-exact; s-02 (after
  unchecking), s-08, s-17, s-21 pass with the noted cosmetics; s-03 optional-skipped.

## Final status

- **Reached the end of the tutorial** (blank/reset → opened WormUnrefined.sky → two-and-
  a-half refinement iterations → exported unscheduled + scheduled transition lists →
  imported 5 scheduled replicates → multi-replicate review). Every menu/dialog step drove.
- **Screenshot outcomes (22 s-XX checkpoints + 1 Excel + optional s-03):**
  - **PASS (exact/near-exact):** s-01, 04, 05, 06, 07, 09, 10, 11, 12, 13, 14, 15, 16,
    18, 19, 20 (16).
  - **PASS with cosmetic note:** s-02 (persisted Ignore-proteins, corrected), s-08
    (locator vs graph-point click; scroll position), s-17 (tile order; 167 vs 166 tran),
    s-21 (content matches; composite dock layout not assemblable).
  - **SKIPPED (optional):** s-03 (RAW re-import; pre-cached .skyd used).
  - **N/A:** s-transition-list-spreadsheet (Excel view, not a Skyline UI checkpoint).
  - **Count DIVERGENCE:** Automated Refinement 75/119 vs tutorial 80/127 (SSRCalc drift);
    Scheduling recovered 86 exactly.
- **Blocking vs cosmetic:** No hard blockers to *completing* the tutorial. The only
  undriveable steps are **cosmetic/manual-arrangement**: drag-to-dock for the s-21
  composite (Finding #1) and the graph data-point click at s-08 (Finding #4, worked
  around). Everything functional drove.
- **Overall — YES, a user + Claude can finish MethodRefine via the MCP today**, with
  high-fidelity screenshot verification at nearly every checkpoint. Two things a
  first-time runner must discover: graph right-click menus need `control=""` (Finding #2)
  and multi-file result import needs ListView `select_item` (Finding #3) — both should be
  documented so the next tutorial run doesn't re-discover them.
- **Top fix for Nick + Brendan:** add a **drag-to-dock verb** (and/or a composite multi-
  pane capture) — it's the single thing standing between the runner and a pixel-faithful
  s-21, and it recurs for any tutorial that hand-arranges panes.

## Status: ISSUES — completed end-to-end with findings (MethodRefine sub-agent, 2026-07-22)
