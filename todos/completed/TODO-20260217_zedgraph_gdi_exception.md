# GDI+ ExternalException in ZedGraph FindNearestPaneObject during hit-testing

## Branch Information
- **Branch**: `Skyline/work/20260217_zedgraph_gdi_exception`
- **Worktree**: `pwiz-work2`
- **Base**: `master`
- **Created**: 2026-02-17
- **Status**: Completed
- **GitHub Issue**: [#3950](https://github.com/ProteoWizard/pwiz/issues/3950)
- **PR**: [#3998](https://github.com/ProteoWizard/pwiz/pull/3998)
- **Exception Fingerprint**: `0c5af2c98e545893`
- **Exception ID**: 73896

## Objective

Catch `ExternalException` in `MasterPane.FindNearestPaneObject()` so GDI+ failures during hit-testing return the "nothing found" result instead of crashing. This protects all callers (context menu, mouse hover, etc.).

## Tasks

- [x] Add try-catch for `ExternalException` in `MasterPane.FindNearestPaneObject()`
- [x] Return "nothing found" result on catch (same as existing no-match path)
- [x] Build and verify no errors
- [x] Create PR

## Progress Log

### 2026-02-18 - Merged

PR #3998 merged to master (c84f7570).

### 2026-02-17 - Session Start

Starting work on this issue. The fix wraps the hit-testing loop in FindNearestPaneObject with a catch for ExternalException.

## Resolution

**Status**: Merged to master
**PR**: [#3998](https://github.com/ProteoWizard/pwiz/pull/3998) — merged 2026-02-18
**Merge commit**: `c84f7570`

Try-catch for `ExternalException` added in `MasterPane.FindNearestPaneObject()` so GDI+ failures during hit-testing return "nothing found" instead of crashing.
