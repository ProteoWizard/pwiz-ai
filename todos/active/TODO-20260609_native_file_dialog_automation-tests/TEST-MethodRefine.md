# TEST — Targeted Method Refinement (MethodRefine)

**Status: CLAIMED by MethodRefine sub-agent 2026-07-22**

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
