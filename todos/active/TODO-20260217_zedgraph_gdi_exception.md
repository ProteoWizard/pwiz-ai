# GDI+ ExternalException in ZedGraph FindNearestPaneObject during hit-testing

## Branch Information
- **Branch**: `Skyline/work/20260217_zedgraph_gdi_exception`
- **Worktree**: `pwiz-work2`
- **Base**: `master`
- **Created**: 2026-02-17
- **Status**: In Progress
- **GitHub Issue**: [#3950](https://github.com/ProteoWizard/pwiz/issues/3950)
- **PR**: (pending)
- **Exception Fingerprint**: `0c5af2c98e545893`
- **Exception ID**: 73896

## Objective

Catch `ExternalException` in `MasterPane.FindNearestPaneObject()` so GDI+ failures during hit-testing return the "nothing found" result instead of crashing. This protects all callers (context menu, mouse hover, etc.).

## Tasks

- [ ] Add try-catch for `ExternalException` in `MasterPane.FindNearestPaneObject()`
- [ ] Return "nothing found" result on catch (same as existing no-match path)
- [ ] Build and verify no errors
- [ ] Create PR

## Progress Log

### 2026-02-17 - Session Start

Starting work on this issue. The fix wraps the hit-testing loop in FindNearestPaneObject with a catch for ExternalException.
