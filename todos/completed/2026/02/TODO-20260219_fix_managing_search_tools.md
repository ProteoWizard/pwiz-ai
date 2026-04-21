# TestManagingSearchTools: Fix fragile CWD-relative path and silent exception swallowing

## Branch Information
- **Branch**: `Skyline/work/20260219_fix_managing_search_tools`
- **Worktree**: `pwiz-work2`
- **Base**: `master`
- **Created**: 2026-02-19
- **Status**: Complete
- **GitHub Issue**: [#4013](https://github.com/ProteoWizard/pwiz/issues/4013)
- **PR**: [#4018](https://github.com/ProteoWizard/pwiz/pull/4018)
- **Failure Fingerprint**: `e2632bfdbfabed24`
- **Test Name**: TestManagingSearchTools
- **Fix Type**: failure

## Objective

Fix intermittent TestManagingSearchTools failures caused by a CWD-relative expression-bodied property that silently changes resolved paths when CWD shifts, combined with silent exception swallowing in tool migration code.

## Tasks

- [ ] Change `oldEncyclopediaDir` from CWD-relative `=>` property to stable `=` field based on `GetToolsDirectory()`
- [ ] Add logging to empty catch at `Program.cs:292` so migration failures are visible
- [ ] Review path update logic in `CopyOldSearchTools` to not update paths on copy failure

## Files

- `pwiz_tools/Skyline/TestFunctional/ManagingSearchToolsTest.cs`
- `pwiz_tools/Skyline/Program.cs`

## Progress Log

### 2026-02-19 - Session Start

Starting work on this issue. Branch created, TODO filed.

### 2026-02-20 - Merged

PR #4018 merged to master (commit 5ac69ce6).

## Resolution

Changed `oldEncyclopediaDir` from a CWD-relative expression-bodied property to a `_oldEncyclopediaDir` private field initialized in the test method body using `GetToolsDirectory()`, ensuring the path is stable, unique per test+culture, and evaluated after `Program.UnitTest` is set. Program.cs changes (logging empty catch, guarding path updates) deferred to enhancement issue #4015.
