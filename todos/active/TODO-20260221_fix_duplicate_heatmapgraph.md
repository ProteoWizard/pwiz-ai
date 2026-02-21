# TestListClustering: duplicate HeatMapGraph after NewDocument/OpenFile

## Branch Information
- **Branch**: `Skyline/work/20260221_fix_duplicate_heatmapgraph`
- **Base**: `master`
- **Created**: 2026-02-21
- **Status**: In Progress
- **GitHub Issue**: [#4022](https://github.com/ProteoWizard/pwiz/issues/4022)
- **PR**: [#4030](https://github.com/ProteoWizard/pwiz/pull/4030)

## Objective

Fix duplicate HeatMapGraph forms appearing after NewDocument() + OpenFile() sequence by adding DataboundGraph cleanup in LoadLayoutLocked() and CloseInapplicableForms() in UpdateGraphUI().

## Tasks

- [x] Add `DataboundGraph` and `ListGridForm` cleanup in `LoadLayoutLocked()` alongside existing `FoldChangeForm` cleanup
- [x] Add `DataboundGraph.CloseInapplicableForms()` in `UpdateGraphUI()` to close forms when list no longer exists
- [x] Add `ListGridForm.CloseInapplicableForms()` in `UpdateGraphUI()` to close list grid when list no longer exists
- [x] Add screenshot infrastructure: full-screen and arbitrary rectangle capture
- [x] Add `FindAiTmpPath()` utility to `AbstractUnitTest`
- [x] Fix `OpenDocument()` to handle absolute paths in `AbstractFunctionalTestEx`
- [x] Update test to verify fix and CloseInapplicableForms behavior
- [x] Verify TestListClustering passes

## Key Finding

NewDocument() preserves list schema and contents from the prior document. This means
CloseInapplicableForms() won't close list-dependent forms on NewDocument — the list still
exists. This is a separate concern (noted with CONSIDER comment in test) for Nick to review.

## Progress Log

### 2026-02-21 - Session Start

Starting work on this issue.

### 2026-02-21 - Fix Complete

Two-pronged fix:
1. **LoadLayoutLocked**: Close DataboundGraph and ListGridForm before layout deserialization
   (prevents duplicates when .sky.view exists)
2. **UpdateGraphUI**: Added CloseInapplicableForms() for both DataboundGraph and ListGridForm
   (closes forms when switching to document without the list, e.g. no .sky.view path)

Also added screenshot infrastructure (full-screen, arbitrary rectangle) and FindAiTmpPath()
utility for test diagnostics.

Debugging revealed that NewDocument() preserves lists with data, so CloseInapplicableForms
only fires when opening a truly different document. Test exercises both paths.
