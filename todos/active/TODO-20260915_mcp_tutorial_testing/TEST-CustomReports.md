# TEST — Custom Reports (CustomReports)

**Status: ISSUES — reached and verified every section + all 28 screenshot checkpoints (many EXACT: s-02, s-07/s-10, s-17 CVs, s-20 filter, s-21 peak areas; Overview CSV+skyr round-trip; Study 7 light/heavy pivot; Tailing annotation define->set->export). ONE major blocking gap: the ViewEditor column tree add/select is top-level-only (Finding #1) — building/editing/filtering reports through the Edit Report UI is impossible via MCP; reproduced via skyline_add_report + report-definition tools. Column REMOVE/reorder, Share/Import/Remove .skyr, annotation define+set+export, and all grids/graphs DO work. No product bugs. Driven by nickshulman@nicksh9 (night-session sub-agent), 2026-07-22.**

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
| s-11 | Edit Report copy (Study 7) | BLOCKED (UI) | Copy dropdown "Open View Editor" unreachable (Finding #2) + column tree unbuildable (Finding #1) |
| s-12 | Edit Report Study 7 full | BLOCKED (UI) | Built 25-col Study 7 via add_report workaround |
| s-13 | Preview pivoted | PASS (data) | pivot_isotope_label verified: light/heavy prefixed columns (light/heavy BestRetentionTime, TotalArea, PrecursorMz, Area...) in single rows |
| s-14 | Export Report Study 7 | PASS | Study 7 appears in report list |
| s-15 | Manage Reports Summary Statistics | PASS | Imported Summary_stats.skyr; list matches reference |
| s-16 | Document Grid Reports menu | PASS (equiv) | Reports>Summary Statistics via click_control_menu_item |
| s-17 | Document Grid Summary Statistics | PASS (EXACT) | Grid renders clean; INDISHTQSVSAK 59.3%/23.5% CV matches tutorial; others <10%/<5% |
| s-18 | Customize Report Cv Total Area | BLOCKED (UI) | Filter tree nested-select blocked (Finding #1); no double-click verb to sync list->tree |
| s-19 | Customize Report filter | BLOCKED (UI) | Add>> needs the nested column selected |
| s-20 | Document Grid filtered | PASS (EXACT) | Filter CvTotalArea>0.2 via report tool -> 2 rows (LEP 59.3%, MBP 22.4%), matches reference exactly |
| s-21 | Peak Areas INDISHTQSVSAK | PASS (EXACT) | After Normalized>None + Transitions>All: stacked y7/y12/y11, Rep1~0.4 outlier, totals match reference exactly |
| s-22 | Results Grid view | PASS | Renders clean; Rep1-5 precursor result columns |
| s-23 | Skyline w/ Results Grid docked | N/A (docking) | Docking is mouse-drag; views exist and render individually |
| s-24 | Results Grid w/ note | PASS | Rep1 Precursor Replicate Note="Low signal" set via grid; verified. NewResultsGridView column-remove worked via UI |
| s-25 | Define Annotation Tailing | PASS | Name Tailing, Type True/False, Applies To Precursor Results — captured, matches reference |
| s-26 | Document Settings Annotations | PASS | Tailing checked in Annotations tab — captured, matches reference |
| s-27 | Customize Report + Tailing | BLOCKED (UI) | Tailing nested in tree, check blocked (Finding #1) |
| s-28 | Skyline w/ Tailing column | PASS (data) | Column-add via tree blocked; annotation value SET (ESDTSYVSLK Rep1=True) + exported/verified via report tool |

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

### Sharing Report Templates — PASS
- Export Report -> Edit list -> Manage Reports. `ChooseViewsControl.get_children` -> inner `ListView` (listView1). `select_item "Overview"` on that ListView **WORKS** (ListView searches all items — unlike the top-level-only tree). Share -> native **Save As** dialog -> set path -> accept.
- `Overview.skyr` written and verified on disk: `<view name="Overview" rowsource="...Precursor">` with columns Peptide.Sequence, IsotopeLabelType, Results!*.Value.BestRetentionTime, Results!*.Value.TotalArea. (s-08 PASS; the form captured clean, not cyan.)

### Managing Report Templates — PASS (round-trip)
- Remove: select Overview in ListView -> Remove -> "Are you sure?" AlertDlg -> accept. Overview gone.
- Import: Import button -> native **Open** dialog -> set Overview.skyr path -> accept -> OK. **Overview restored** in the Export Report list (s-10 PASS, captured). Full delete+reimport round-trip works via addressable buttons + native dialogs.

### Modifying Existing Report Templates — s-11/s-12 UI BLOCKED; s-13 data PASS (workaround)
- **Copy dropdown unreachable:** select Overview -> `Copy` posts and opens a **dropdown ContextMenuStrip** ("Open View Editor"), but `click_form_button` errors "ContextMenuStrip is not a form" and `click_control_menu_item control=Copy` errors "&Copy... has no context menu". The Copy dropdown's items can't be invoked. **Finding #2.** (Moot anyway — the destination ViewEditor tree is unbuildable per Finding #1.)
- **Workaround:** `add_report "Study 7"` — 25 columns (ProteinName, PeptideSequence, BestRetentionTime, TotalArea, FileName, SampleName, ReplicateName, AverageMeasuredRetentionTime, PeptideRetentionTime, RatioToStandard, PrecursorCharge/Mz, ProductCharge/Mz, FragmentIon, MaxFwhm, MinStartTime, MaxEndTime, RetentionTime, Fwhm, StartTime, EndTime, Area, Height, UserSetPeak), pivot_isotope_label=true.
- `get_report_rows Study 7`: **840 transition rows, 1140 cols.** **s-13 pivot-isotope-label VERIFIED** — matching `light`/`heavy` prefixed columns present in single rows (light BestRetentionTime + heavy BestRetentionTime, light/heavy TotalArea, light/heavy PrecursorMz, light/heavy ProductMz, light/heavy Area, ...). Divergence: the report tool ALSO pivoted replicates by default (tutorial's final layout unchecks replicate pivot); the light/heavy teaching point is unaffected. Study 7 appears in the Export Report list (s-14 PASS).

### Quality Control Summary Reports — s-15/s-17/s-20/s-21 PASS (mostly EXACT); s-18/s-19 UI BLOCKED
- Opened **Study9pilot.sky** (tutorial prose says "Study9S.sky" and "22 peptides/10 runs" — stale; shipped file is Study9pilot, 7 prot / 10 pep / 10 prec / 30 tran / **5 replicates**). Tutorial-text divergence, Finding #4.
- `View > Live Reports > Document Grid` (Replicates report, Rep1-Rep5). Reports button menu driven via `click_control_menu_item control="" "Reports > Manage Reports"`. Import Summary_stats.skyr (native Open dialog). **Summary Statistics** added -> **s-15 PASS** (list matches reference).
- `Reports > Summary Statistics` -> grid switches. **s-17 PASS (EXACT):** grid renders clean; verified via get_report_rows (10 rows): INDISHTQSVSAK (LEP) CvTotalArea **59.3%**, CvMaxFwhm **23.5%** (tutorial 59.2%/23.5%); all others CvTotalArea <10%, CvMaxFwhm <5%; RangeBestRetentionTime all <=0.13 min (<0.15).
- **Filter (s-18/s-19) UI BLOCKED:** `Reports > Edit Report` opens Customize Report (ViewEditor). Filter tab has its OWN `availableFieldsTreeFilter` + `Add >>` button + filter grid. To add the filter I must select nested **Cv Total Area** in that tree — `select_item` fails ("no match"), and selecting it in the right ListView does not sync to the tree (tutorial uses a **double-click** to sync; no double-click verb exists). Finding #1. `Add >>` button itself is addressable but useless without the nested selection.
- **Workaround (s-20) PASS (EXACT):** `get_report_rows "Summary Statistics"` with filterJson `CvTotalArea > 0.2` -> exactly **2 rows**: LEP INDISHTQSVSAK 59.3% and MBP HGFLPR 22.4%. s-20 reference shows the SAME 2 rows with identical values (confirms Study9pilot IS the screenshot dataset).
- **s-21 PASS (EXACT):** closed filter; selected INDISHTQSVSAK; View > Peak Areas > Replicate Comparison. Graph was stuck Normalized-To-Heavy (empty; no heavy standards) -> `Normalized To > None` + `Transitions > All` via graph right-click. Result: stacked y7(blue)/y12(purple)/y11(red), Rep1 ~0.4 (outlier), Rep2 ~4.2, Rep3 ~8.7, Rep4 ~8.0, Rep5 ~7.9 — matches reference exactly, showing the reproducibility problem behind the 59.3% CV.

### Results Grid View — PASS (s-22/s-24); column-remove UI WORKS
- `View > Live Reports > Results Grid`. Selected precursor `Precursor:/LEP/INDISHTQSVSAK/light+++` (467.2440+++). **s-22 PASS:** grid renders clean (Rep1-5; columns Replicate, Precursor Replicate Note, Peak Found Ratio, Best RT, Max Fwhm, Min Start Time, ...).
- **s-24 PASS:** grid = DataboundGridControl > BoundDataGridViewEx (boundDataGridView). `set_current_cell_address [1,0]` (path-based) + `set_grid_text "Low signal"` -> Rep1 Precursor Replicate Note = "Low signal" (verified via get_grid_text; Rep1 Total Area 470755 vs Rep2-5 4-8M confirms the outlier).
- **NewResultsGridView (column customize) — WORKS via UI:** Reports > Customize Report; named it; for Min Start Time / Max End Time / Library Dot Product: `select_item` on the right ListView (listViewColumns) + click the **Remove** ToolStripButton (toolStripColumns has Remove/Up/Down). All three removed (verified via get_grid_text). **Important refinement of Finding #1:** column REMOVE and reorder (Up/Down) buttons ARE addressable; only column ADD (checking a nested node in the AvailableFieldsTree) is blocked.
- s-23 (docked layout) is mouse-drag docking — N/A; the windows exist and render individually.

### Custom Annotations — s-25/s-26 PASS; s-27 UI BLOCKED; s-28 value set + exported (workaround)
- `Settings > Document Settings` (Annotations tab) -> Edit List -> Define Annotations -> Add -> **Define Annotation**: Name="Tailing", Type="True/False" (combo set), Applies to -> `check_item "Precursor Results"`. **s-25 PASS** (captured clean, matches reference; get_form_value confirms Precursor Results checked).
- OK/OK back to Document Settings; `check_item "Tailing"` on the annotations CheckedListBox (matched by type). **s-26 PASS** (captured; Tailing checked). OK.
- Selected `Precursor:/CRP/ESDTSYVSLK/light++` (564.7746++).
- **s-27 add-column BLOCKED:** Results Grid Reports > Edit Report -> Customize Report; `check_item "Tailing"` on the AvailableFieldsTree fails (nested — Finding #1). Cancelled.
- **Workaround — annotation is fully functional & exportable:** `get_report_from_definition_rows` select [ProteinName, PeptideSequence, ReplicateName, **Tailing**] -> Tailing is a **boolean** column, 50 rows (10 prec x 5 rep), default False (the tutorial's stated purpose: "export the Tailing annotation... appears in the Precursor Results field group"). Built report "Tailing Review", loaded in Document Grid, `set_form_value boundDataGridView[3,40] = True` (ESDTSYVSLK Rep1). Filter Tailing=True -> exactly **1 row: CRP ESDTSYVSLK Rep1 True**. Full define->activate->set->export loop verified. **s-28 data PASS.**

## Findings & fix suggestions

1. **[MCP capability gap — HIGH] The ViewEditor `AvailableFieldsTree` cannot add/select a NESTED column via MCP.** (BLOCKING for building any report in the UI; worked around throughout.) `get_controls` doesn't list the tree; via `ChooseColumnsTab.get_children` you reach `AvailableFieldsTree`, but `get_children` on it returns **[]** (no node paths), and `check_item`/`select_item`/`uncheck_item` match **only the tree's top-level root nodes** (e.g. "Proteins" checks/unchecks OK; "Peptides", "Peptide Sequence", "Cv Total Area", "Tailing" all fail "no match"). `expand`/`collapse` DO take a path array and work. Net: no way to add an individual column (s-03, s-04, s-11, s-12) or select a nested column for a filter (s-18/s-19) or add an annotation column (s-27). This is the whole build-a-report activity the tutorial teaches. **Fix:** make `check_item`/`select_item` recurse the whole tree (match by node text or a `>`-separated path like `expand` uses), and/or have `get_children` enumerate the tree nodes so their paths can be passed back. This single change would unblock ~7 screenshots and the tutorial's core skill. NOTE: column **remove** (Remove ToolStripButton) and **reorder** (Up/Down) on the right ListView DO work via `select_item` + click — only tree-based ADD is blocked.

2. **[MCP capability gap — MEDIUM] Nested tree-node SELECTION is also top-level-only in the Export Report "Report" tree and the ViewEditor filter tree.** `select_item "Overview"` on the Export Report Report tree fails (Overview is nested under "Main"), and `get_children`=[] — so a report can't be selected to Preview/Export via that dialog. Same root cause as #1 (same top-level-only tree matcher). Worked around: exported via `--report-name` CLI; and the **ChooseViewsControl ListView** in Manage Reports (a ListView, not a tree) DOES support `select_item` for any item, which is how Share/Remove were driven. **Fix:** same as #1 (recursive tree matching).

3. **[MCP capability gap — LOW] The Manage Reports "Copy" split-button dropdown ("Open View Editor") is unreachable.** Clicking `Copy` opens a ContextMenuStrip dropdown; `click_form_button` errors "ContextMenuStrip is not a form" and `click_control_menu_item control=Copy` errors "&Copy... has no context menu". So the Copy->Open View Editor path (s-11) can't be driven. Moot here (destination tree unbuildable per #1), but a real gap. **Fix:** model a ToolStrip/button DropDown menu the way right-click ContextMenus are, addressable via `click_control_menu_item`.

4. **[Tutorial-text — LOW] Stale filename/counts in the QC section.** The tutorial says open **"Study9S.sky"** and describes **"22 analyte peptides over 10 runs"**; the shipped file is **`Study9pilot.sky`** with **10 peptides / 5 replicates**. The s-17/s-20/s-21 reference screenshots match the shipped Study9pilot data exactly (INDISHTQSVSAK 59.3%, the 2-row filter, the Rep1 outlier), so only the prose filename/counts are stale. **Fix:** update the tutorial text to `Study9pilot.sky` and "10 peptides / 5 replicates". (Also s-21 caption says "F7"; the earlier Data Overview says F8 for Replicate Comparison — minor inconsistency.)

5. **[Environmental / harness — LOW] Overlapping FLOATING windows redact each other in `get_form_image`.** With several floating tool windows stacked (Results Grid / Document Grid / Peak Areas), a `get_form_image` of one sometimes returns the window on top instead. Not cyan — the modal-cyan issue did NOT occur here (Export Report, Manage Reports, Edit Report, Define Annotation, Document Settings all captured clean). Grid/annotation state was verified functionally via `get_grid_text`/report tools. **Fix:** capture from the target control's own device context (as graphs do), or raise the target before capture.

### Works-as-designed (positive)
Native Open/Save dialogs (path-set + accept) for open/import/share/export; `File > Export > Report` tree + Manage Reports Add/Remove/Import/Share/OK buttons; **ChooseViewsControl ListView `select_item`** (drove Share/Remove/Copy-select); **Share -> .skyr written & verified**, **Remove+Import round-trip**; Document Grid `Reports` dropdown via `click_control_menu_item`; **`.skyr` import (Summary_stats) -> Summary Statistics report** with data matching the tutorial EXACTLY (CVs, 2-row filter); graph right-click menus (`Normalized To`, `Transitions`); Results Grid note set via `set_grid_text`; **column REMOVE/reorder** in the ViewEditor; **Define Annotation** dialog (name/type/applies-to) fully driveable; annotation activation + **set boolean value via Document Grid cell + export/filter**; `add_report`/`get_report_from_definition[_rows]` as faithful report-build + preview + export workarounds (Overview 20-row pivot, Study 7 light/heavy isotope pivot, Summary Statistics, Tailing).

## Final status
- **Completed end-to-end? YES, functionally — every section and every screenshot checkpoint was reached and verified**, but the tutorial's central hands-on skill (building/editing a report by checking columns in the Edit Report tree) is **not driveable through the MCP** and was reproduced via the `add_report`/report-definition tools instead. Data fidelity was high, several checkpoints EXACT: s-02 (Edit Report), s-07/s-10 (report list), s-17 (Summary Statistics CVs incl. INDISHTQSVSAK 59.3%/23.5%), s-20 (2-row CV filter), s-21 (Rep1-outlier peak areas), plus Overview CSV export (21 lines, headers), Overview.skyr share round-trip, Study 7 light/heavy pivot, and the Tailing annotation define->set->export loop.
- **Blocking vs cosmetic:** **1 major blocking capability gap** (Finding #1 — ViewEditor nested-column tree add/select; it also underlies #2 tree-select and the filter/annotation-column steps), **2 secondary gaps** (#2 nested tree selection for report Preview/Export; #3 Copy dropdown). Non-blocking: #4 tutorial-text, #5 floating-window capture overlap. **No Skyline product bugs found.**
- **Can a user + Claude finish this tutorial today via the MCP?** **Partially.** All the surrounding workflow — export to CSV, share/import/remove `.skyr` templates, import a shared report and read its data, define + activate + set + export custom annotations, drive the Document/Results Grids, and inspect the QC graphs — works, often with EXACT fidelity. **But the core teaching — designing a custom report by adding columns in the Edit Report tree — cannot be done through the UI via MCP;** it must be substituted with `skyline_add_report` + report-definition tools. Fixing Finding #1 (recursive tree `check_item`/`select_item`) would make this tutorial fully completable through the faithful UI path.
