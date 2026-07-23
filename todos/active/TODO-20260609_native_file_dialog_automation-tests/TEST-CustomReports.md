# TEST — Custom Reports (CustomReports)

**Status: CLAIMED by nickshulman@nicksh9 2026-07-22**

## Run context
- **Branch / PR:** `Skyline/work/20260609_native_file_dialog_automation` — PR #4313
- **Skyline:** `26.1.1.203 (b818b91b4)`
- **Connected PID:** 31792
- **Date:** 2026-07-22 (autonomous night session)
- **Data folder:** `D:\Downloads\Tutorials\CustomReports\`
- **UI mode:** proteomic
- **Driver:** autonomous night-session sub-agent (orchestrator-spawned), one shared Skyline (PID 31792).

## Screenshot checklist
| Screenshot | Section | Status | Note |
|-----------|---------|--------|------|
| s-01 | Export Report form | PASS | Captures clean (not cyan). Structure matches; current build has extra default reports (Detailed Log, Peptide Areas, Peptide RT Results) |
| s-02 | Edit Report "Overview" name | PASS (EXACT) | Live capture matches reference exactly; Pivot Replicate Name already checked by default |
| s-03 | Edit Report + Peptide Sequence checked | BLOCKED (UI) | Nested-column check impossible via MCP — see Finding #1 |
| s-04 | Edit Report + precursor cols + pivot | BLOCKED (UI) | Same |
| s-05 | Preview form | PASS (data) | Preview UI blocked (can't select nested "Overview"); data verified via get_report_rows: 20 rows (10 pep x light/heavy) x 28-replicate BestRT/TotalArea pivot; D_01~D_02 areas match |
| s-06 | Manage Reports w/ Overview | PASS (equiv) | Overview present after add_report |
| s-07 | Export Report w/ Overview | PASS | Overview at top of Main; matches reference |
| s-08 | Manage Reports (Share) | | |
| s-09 | Manage Reports Overview selected | | |
| s-10 | Export Report (removed) | | |
| s-11 | Edit Report copy (Study 7) | BLOCKED (UI) | |
| s-12 | Edit Report Study 7 full | BLOCKED (UI) | |
| s-13 | Preview pivoted | | |
| s-14 | Export Report Study 7 | | |
| s-15 | Manage Reports Summary Statistics | | |
| s-16 | Document Grid Reports menu | | |
| s-17 | Document Grid Summary Statistics | | |
| s-18 | Customize Report Cv Total Area | | |
| s-19 | Customize Report filter | | |
| s-20 | Document Grid filtered | | |
| s-21 | Peak Areas INDISHTQSVSAK | | |
| s-22 | Results Grid view | | |
| s-23 | Skyline w/ Results Grid docked | | |
| s-24 | Results Grid w/ note | | |
| s-25 | Define Annotation Tailing | | |
| s-26 | Document Settings Annotations | | |
| s-27 | Customize Report + Tailing | | |
| s-28 | Skyline w/ Tailing column | | |

## Progress log

### Getting Started / Data Overview — PASS
- Opened `Study7_example.sky` via File > Open (native dialog: set File name, dismiss_with_accept_button). Doc = **7 prot / 10 pep / 20 prec / 60 tran / 28 replicates** — matches tutorial (10 peptides, 28 acquisitions).
- Selected HGFLPR (`set_selection Molecule:/MBP/HGFLPR`); View > Peak Areas > Replicate Comparison opened; graph renders (bars rise D->J across the concentration series as described). Note: graph was in "Normalized To Heavy" state from prior session, not a checkpoint. Closed Peak Areas.

### Creating a Simple Custom Report — s-01/s-02 PASS; column-build BLOCKED (Finding #1)
- `File > Export > Report` -> **Export Report** form (ExportLiveReportDlg). Captured CLEAN (not cyan). s-01 structure matches reference; current build lists a few extra default reports. Report tree + Preview/Edit list/Language/Export/Cancel all present.
- `Edit list` -> **Manage Reports** (ManageViewsForm); `Add` -> **Edit Report** (ViewEditor). Set Report Name = "Overview". s-02 live capture = reference EXACTLY (Pivot Replicate Name already checked by default in this build).
- **KEY capability probe — column tree:** `get_controls` does not list the tree; via `ChooseColumnsTab.get_children` found child `AvailableFieldsTree` (availableFieldsTreeColumns) + `ListView` (listViewColumns) + ToolStrip. `AvailableFieldsTree.get_children` returns **[]** (not enumerable). Its `get_actions` advertises expand/collapse/check_item/select_item.
  - `expand ["Proteins","Peptides"]` (path array) **WORKS**.
  - `check_item`/`select_item`/`uncheck_item` by text **FAIL for every nested node** ("Peptide Sequence", "Peptides") with "Tree node not found ... no match".
  - But `check_item "Proteins"` (the TOP-LEVEL root node) **SUCCEEDS**, and `uncheck_item "Proteins"` too.
  - **Precise mechanism:** check_item matches only the tree's top-level root nodes (Proteins, Replicates), NOT recursively into nested field nodes; and get_children=[] gives no node paths. So an individual column (Peptide Sequence, Total Area, etc.) cannot be added through the ViewEditor via MCP. This BLOCKS the faithful UI build of every report in this tutorial (s-03/s-04/s-11/s-12/s-18/s-19/s-27). **Finding #1.**
- **Workaround:** create the reports with `skyline_add_report` (JSON definition) and verify DATA/columns with `get_report`/`get_report_from_definition_rows` (below).
- `add_report` "Overview" (select PeptideSequence/IsotopeLabelType/BestRetentionTime/TotalArea, pivot_replicate=true) -> report created. `get_report_rows Overview`: **20 rows, columns = PeptideSequence, IsotopeLabelType, then per-replicate (D_01..J_04, 28 acquisitions) x {BestRetentionTime, TotalArea}** — exactly the s-05 pivoted layout. Sample data: AGLCQTFVYGGCR light D_01 area 84357 vs D_02 84909 (same concentration -> similar, as tutorial states); heavy areas ~10x higher. **s-05 data PASS.**
- Reopened Export Report -> **Overview** now listed at top of Main (s-06/s-07 PASS, matches reference).
- **Nested-tree selection ALSO blocked here:** `select_item "Overview"` on the Export Report **Report** tree fails ("no match") and `get_children`=[] — same top-level-only limitation (Finding #1). So selecting Overview to Preview/Export via the UI is not possible either.

### Exporting Report Data to a File — PASS (CLI workaround)
- UI path (select Overview -> Export -> native Save dialog) blocked at the nested-node selection above. Exported faithfully via `skyline_run_command --report-name="Overview" --report-file="...\Overview_Study7_example.csv"`.
- Verified on disk: **21 lines** (1 header + 20 data rows). Header = `Peptide Sequence,Isotope Label Type,7_2_ D_ 01 Best Retention Time,7_2_ D_ 01 Total Area,...` across all 28 replicates. Column headers present (the tutorial's key point about export vs copy/paste). **PASS.**
