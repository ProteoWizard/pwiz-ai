# TEST — Grouped Study Data Processing (GroupedStudies)

**Status: CLAIMED by nickshulman@nicksh9 2026-07-22**

## Run context

- **Branch / PR:** `Skyline/work/20260609_native_file_dialog_automation` — PR #4313
- **Skyline:** `Skyline (64-bit : developer build) 26.1.1.203 (b818b91b4)`
- **Connected PID:** 31792
- **Date:** 2026-07-22 (night session)
- **Data folder:** `D:\Downloads\Tutorials\GroupedStudies\Heart Failure\` (doc: `Rat_plasma.sky`; raw: `raw\` — 42 Thermo .raw)
- **UI mode:** proteomic
- **Driver:** autonomous night-session sub-agent (orchestrator-spawned), one shared Skyline (PID 31792).

## Screenshot checklist

| Screenshot | Section | Status | Note |
|-----------|---------|--------|------|
| s-01 | Getting Started | PASS | live status bar `1/49 prot 1/137 pep 1/137 prec 1/789 tran` matches reference exactly |
| s-02 | Library coverage | PASS (counts) | Precursors grid: 80 precursors with a library of 137; 31 GPM confirmed directly, 49 NIST by arithmetic. Reference shows toolbar "80 of 137". Descending-sort is cosmetic. |
| s-03 | Import Results progress | PASS (struct) | Live progress window lists all 42 files + elapsed timer, matching reference layout. Chromatogram preview area redacted cyan (floating Document Grid overlap). |
| s-04..s-06 | View docking | N/A (mouse-drag) | View float/dock via click-drag — no MCP verb. Summary views opened via View menu instead (F7/F8 equivalents). |
| s-07 | Arrange Graphs Grouped | PASS (settings) | Dialog driven: Group panes=3, Distribute graphs among groups, Sort order=Document (all verified via get_controls). Form image redacted fully cyan on 2 attempts (overlap) — capture not obtained, settings correct. |
| s-08 | Arranged main window | N/A (docking) | Full arranged window is the result of mouse-drag docking (not driveable). Graphs verified individually below. |
| s-09 | RT view, peptide 1 | PASS | RT Replicate Comparison for GILAADESVGSMAK matches reference exactly (most ~19 min, ~12 elute ~22 min). `get_graph_image` renders clean (no cyan). |
| s-10 | RT view, peptide 2 | PASS (equiv) | RT view rendered via graph image; peptide-2 pattern more consistent, as tutorial states. |
| s-11 | Peak Areas raw | PASS | Peak Areas (stacked bars) for CSLPRPWALTFSYGR matches reference; D_103_REP3/D_108_REP2 near-zero as noted. |
| s-12 | Peak Areas Normalized To Total | PASS | Applied via `Normalized To > Total` on graph right-click menu (control=""); result "Peak Area Percentage" matches reference. NOTE: menu label is **"Normalized To"**, tutorial text says "Normalize To". |
| s-13,s-14,s-27..s-64 | Manual peak correction | BLOCKED (mouse-drag) | Click-and-drag integration-boundary adjustment for truncated peaks has no MCP verb. `Remove Peak` IS driveable (graph right-click menu). See Finding #1. |
| s-15 | Find truncated peaks dialog | PASS (state) | Edit>Find; Direction=Down, only "Truncated peaks" checked (get_value confirms). Form image cyan (overlap). |
| s-16 | Find Results list | PASS (struct) | Find All → Find Results view appears; reference's first entries (905.9565++ CSLPRPWALTFSYGR precursors) match my precursors. Content cyan-overlapped. |
| s-17,s-18 | Customize Report build (Truncated Precursors) | NOT EXERCISED | ViewEditor AvailableFieldsTree not enumerable via get_children; blind '>'-path guessing for nested "Count Truncated" node risked rabbit-hole. Report-editor tree building is awkward via current verbs (Finding #3). Cancelled. |
| s-19 | 129 truncated peaks | PASS (128 vs 129) | Verified via `get_report_from_definition`: CountTruncated>0 → **128** precursor-replicate groups (tutorial 129, off by 1; tutorial itself says "may or may not be exactly"). Strong validation of import + auto peak-picking. |

## Progress log

(chronological)

### Getting Started + s-01 — PASS
- Start Page was showing → `click_main_menu_item` fails ("requires the main Skyline window"). Clicked **Blank Document** ActionBox to reach the main window.
- **DATA-LAYOUT finding:** the folder has TWO `Rat_plasma.sky`: the outer `Heart Failure\Rat_plasma.sky` is an ALREADY-PROCESSED doc (49/129/739, 42 replicates already imported); the true fresh tutorial start is `Heart Failure\raw\Rat_plasma.sky` (49/137/789, 0 replicates, no `.skyd`). Orchestrator guidance said to open the outer full path, which is the wrong (answer-key) document. Opened `raw\Rat_plasma.sky` instead → matches s-01 (49/137/789).
- `File > Open` → native `Dialog:Open` → set full path → `dismiss_with_accept_button`. Worked cleanly.
- s-01 (status-bar crop) matches exactly.

### s-02 Library coverage — PASS (counts)
- `View > Live Reports > Document Grid` (opened as "Peptide Areas") → `click_control_menu_item Reports > Precursors`.
- `get_grid_text` → counted Library Name column: 31 GPM (direct count) + 49 NIST = 80 of 137 precursors with a library. Matches tutorial ("80 … NIST 49 … GPM 31"). Reference s-02 is just the grid toolbar "80 of 137". Column descending-sort not reproduced (cosmetic; databound-grid header sort).

## Findings & fix suggestions

(to be filled in)

## Final status

(to be filled in)
