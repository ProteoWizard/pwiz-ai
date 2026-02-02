# Fix protein tooltip in Import Transition List dialog

**Issue**: [#3914](https://github.com/ProteoWizard/pwiz/issues/3914) - ImportTransitionListColumnSelectDlg: protein tooltip crashes and shows wrong protein after sort
**PR**: [#3915](https://github.com/ProteoWizard/pwiz/pull/3915) - Fixed ArgumentOutOfRangeException in transition list protein tooltip
**Cherry-pick**: Manually cherry-picked to `Skyline/skyline_26_1` by bspratt (commit `03a6f5e2d`). Auto-cherry-pick failed ([#3919](https://github.com/ProteoWizard/pwiz/issues/3919)).
**Exception**: [#73851](https://skyline.ms/home/issues/exceptions/announcements-thread.view?rowId=73851) - fingerprint `25731a8d5a02b8b1`

## Status: Complete (merged 2026-01-31)

Two commits on PR #3915:

1. **f39991b** (bspratt via Claude Code): Bounds check on `_proteinList` indexing + `TestMouseMoveToGridCell` test
2. **21df832** (brendanx + Claude): Disabled column sorting on the preview grid

## Resolution

The Cell.Tag approach from issue #3914 was prototyped but discarded. While it correctly survived grid sorting, the Tag values did not actually travel with cells during DataGridView sort operations on a data-bound grid. More importantly, the refactoring required to thread protein data through `AssociateProteins` and `AddAssociatedProtein` was disproportionate to the benefit.

Instead, sorting was disabled entirely by setting `DataGridViewColumnSortMode.NotSortable` on all columns in `DisplayData()`. This is the correct fix because:

* The grid displays pasted transition data in paste order — sorting is not meaningful
* Sorting broke the parallel `_proteinList` index assumption used for tooltip lookup
* Sorting also caused other problems unrelated to tooltips
* One line of code vs. a multi-method refactor

With sorting disabled, the bounds check from the first commit correctly guards the `_proteinList` indexing for all reachable cases.

## What PR #3915 did

1. Extracted `proteinIndex = e.RowIndex - 1` for clarity
2. Added bounds check: `proteinIndex >= 0 && proteinIndex < _proteinList.Count`
3. Added `TestMouseMoveToGridCell` test helper and test in `InsertTest.TestMalformedTransitionListWithAssociateProteins`
4. Drive-by: `"TransitionList"` -> `@"TransitionList"` (CodeInspectionTest fix)
5. Disabled column sorting on all grid columns in `DisplayData()`

## Files changed

* `pwiz_tools/Skyline/FileUI/ImportTransitionListColumnSelectDlg.cs`
  - `dataGrid_MouseMove` — bounds check on `_proteinList` indexing
  - `DisplayData()` — `SortMode = NotSortable` on all columns
  - `TestMouseMoveToGridCell` — test helper for mouse move events
* `pwiz_tools/Skyline/TestFunctional/InsertTest.cs`
  - `TestMalformedTransitionListWithAssociateProteins` — test coverage for row 0 and last row
