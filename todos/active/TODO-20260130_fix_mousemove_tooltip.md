# Fix protein tooltip in Import Transition List dialog

**Issue**: [#3914](https://github.com/ProteoWizard/pwiz/issues/3914) - ImportTransitionListColumnSelectDlg: protein tooltip crashes and shows wrong protein after sort
**PR**: [#3915](https://github.com/ProteoWizard/pwiz/pull/3915) - Fixed ArgumentOutOfRangeException in transition list protein tooltip
**Exception**: [#73851](https://skyline.ms/home/issues/exceptions/announcements-thread.view?rowId=73851) - fingerprint `25731a8d5a02b8b1`

## Status

PR #3915 (by bspratt via Claude Code) fixes the crash with a bounds check on `_proteinList` indexing. This is correct but incomplete — it doesn't fix the sorting bug described in #3914.

**This branch needs**: Replace the `_proteinList` parallel-list approach with `DataGridViewCell.Tag` storage, as described in #3914. The new test from PR #3915 (`TestMouseMoveToGridCell`) must still pass.

## What PR #3915 did

1. Extracted `proteinIndex = e.RowIndex - 1` for clarity
2. Added bounds check: `proteinIndex >= 0 && proteinIndex < _proteinList.Count`
3. Added `TestMouseMoveToGridCell` test helper and test in `InsertTest.TestMalformedTransitionListWithAssociateProteins`
4. Drive-by: `"TransitionList"` -> `@"TransitionList"` (CodeInspectionTest fix)

## What still needs to be done

Replace the parallel `_proteinList` with `Cell.Tag` storage:

1. **In `dataGrid_MouseMove`**: Read protein from cell Tag instead of `_proteinList`:
   ```csharp
   if (e.RowIndex >= 0 && e.ColumnIndex == 0 && isAssociated)
   {
       var protein = dataGrid.Rows[e.RowIndex].Cells[0].Tag as Protein;
       if (protein != null)
       {
           var tipProvider = new ProteinTipProvider(protein);
           // ...
   ```

2. **After `UpdateForm()` (~line 1625)**: Tag the protein name cells. The protein name cell text already comes from the Protein objects, so the Tag can be set at the same time. Alternatively, after `UpdateForm()` returns and the grid is populated, iterate and set tags from `_proteinList`, then clear/remove `_proteinList`.

3. **Remove `_proteinList` field** if possible (it's only used for tooltip lookup — 4 references total: declaration at line 74, init at 293, add at 419, read at 1477).

### Why Cell.Tag is better

- Eliminates the off-by-one indexing entirely
- Survives grid sorting (Tag travels with the cell)
- No parallel data structure to keep in sync
- The existing test (`TestMouseMoveToGridCell` on row 0 and last row) will pass because a null Tag simply skips the tooltip

### Grid structure reminder

- Row 0 in the DataGridView is a "..." placeholder row covered by combo box controls in `comboPanelInner`
- Data rows start at row 1
- `_proteinList[0]` corresponds to grid row 1 (hence the `- 1` offset)
- When headers exist, `_proteinList[0]` is actually a null protein for the header line
- Grid is data-bound to a DataTable (`dataGrid.DataSource = table`), so Tags must be set after binding

## Files to change

- `pwiz_tools/Skyline/FileUI/ImportTransitionListColumnSelectDlg.cs`
  - `dataGrid_MouseMove` — read from Cell.Tag
  - After `UpdateForm()` in associate proteins flow — set Cell.Tag
  - `AddAssociatedProtein` — may still add to temp list, or refactor
  - Remove `_proteinList` field if no longer needed

## PR #3915 also needs

- Reference to issue #3914 in the PR description
- Labels: "skyline", "bug"
- Assignee: brendanx67
