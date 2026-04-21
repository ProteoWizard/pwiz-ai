# TODO-20260216_skyd_ioexception_friendly_error.md

## Branch Information
- **Branch**: `Skyline/work/20260216_skyd_ioexception_friendly_error`
- **Base**: `master`
- **Created**: 2026-02-17
- **Status**: Completed
- **GitHub Issue**: [#3946](https://github.com/ProteoWizard/pwiz/issues/3946)
- **PR**: [#3994](https://github.com/ProteoWizard/pwiz/pull/3994)

## Objective
Show friendly error instead of crash dialog when IOException occurs during peptide
search library import (e.g. network drive becomes unavailable while reading .skyd cache).
6 reports from 5 users. Fingerprint: `9c239bb11557ea60`.

## Root Cause
`ChromatogramCache.CallWithStream` throws IOException when reading peak data from a
.skyd file on a network drive that becomes unavailable. The exception propagates through
`ChangeSettings` → `ModifyDocument` → `BuildPeptideSearchLibrary` → `NextPage()` and
reaches the unhandled exception handler.

## Fix Approach
* Added try-catch in `BuildPeptideSearchLibrary()` using `ExceptionUtil.DisplayOrReportException`
  with the existing translated resource string "Failed to build the library {0}."
* Sets `e.Cancel = true` so callers know an error was shown and don't proceed
* All 3 call sites (`NextPage` non-DDA path, DDA search path, wizard finish path) are
  automatically protected
* Extracted `BuildPeptideSearchLibraryOrCloseWizard()` helper from `NextPage()` to keep
  the already-long method clean

## Regression Test — Why None Was Added
Manual reproduction requires a transient network failure: the .skyd cache must be accessible
when initially loaded but become inaccessible during a later `ChangeSettings` read triggered
by `ModifyDocument`. Testing showed:
* The .skyd file is locked by Skyline while open, so it cannot be renamed
* Disconnecting a network drive entirely produces a `DirectoryNotFoundException` during
  `BlibBuild.BuildLibrary` (library *build* fails), which is a different code path caught
  by `BuildOrUsePeptideSearchLibrary`'s internal catch
* Skyline either blocks the wizard until the document is fully loaded (re-locking the .skyd)
  or auto-loads the data
* Simulating partial IO failure (file readable, then not) would require a failure simulation
  layer that does not exist for disk IO (we have one for HTTP but not filesystem)

## Completed Tasks
- [x] Investigate exception call chain and all 3 call sites
- [x] Add try-catch in `BuildPeptideSearchLibrary` using established patterns
- [x] Extract `BuildPeptideSearchLibraryOrCloseWizard` helper from `NextPage`
- [x] Use existing translated resource string for error context
- [x] Build successfully
- [x] Attempt manual reproduction and document findings

## Resolution

**Status**: Merged to master
**PR**: [#3994](https://github.com/ProteoWizard/pwiz/pull/3994) — merged 2026-02-18
**Merge commit**: `d4b487c2`

Friendly error dialog shown instead of crash when IOException occurs during peptide search library import. Try-catch added in `BuildPeptideSearchLibrary()` using `ExceptionUtil.DisplayOrReportException`.

### 2026-02-18 - Merged

PR #3994 merged to master (d4b487c2).

## Files Modified
- `pwiz_tools/Skyline/FileUI/PeptideSearch/ImportPeptideSearchDlg.cs`
