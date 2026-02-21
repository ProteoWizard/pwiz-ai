# TestListClustering: duplicate HeatMapGraph after NewDocument/OpenFile

## Branch Information
- **Branch**: `Skyline/work/20260221_fix_duplicate_heatmapgraph`
- **Base**: `master`
- **Created**: 2026-02-21
- **Status**: In Progress
- **GitHub Issue**: [#4022](https://github.com/ProteoWizard/pwiz/issues/4022)
- **PR**: (pending)

## Objective

Fix duplicate HeatMapGraph forms appearing after NewDocument() + OpenFile() sequence by adding DataboundGraph cleanup in LoadLayoutLocked() and optionally handling them in UpdateGraphUI().

## Tasks

- [ ] Add `DataboundGraph` cleanup in `LoadLayoutLocked()` alongside existing `FoldChangeForm` cleanup
- [ ] Consider whether `UpdateGraphUI` should hide DataboundGraph forms when document has no relevant data
- [ ] Move duplicate-form assertion from `TryWaitForOpenForm()` back into `FindOpenForm()` once fix is confirmed
- [ ] Verify TestListClustering passes

## Progress Log

### 2026-02-21 - Session Start

Starting work on this issue. The fix is well-scoped in the issue description.
