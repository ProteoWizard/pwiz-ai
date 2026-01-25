# TODO-20260121_irtdb_friendly_error.md

## Branch Information
- **Branch**: `Skyline/work/20260121_irtdb_friendly_error`
- **Base**: `master`
- **Created**: 2026-01-21
- **Status**: Complete - Merged to master (not cherry-picked to 26.1 release)
- **GitHub Issue**: [#3856](https://github.com/ProteoWizard/pwiz/issues/3856)
- **PR**: [#3867](https://github.com/ProteoWizard/pwiz/pull/3867)

## Problem Description

Users opening a corrupted or incompatible iRT database file see a technical crash dialog with:
```
SQLiteException: SQL logic error or missing database - no such table: IrtLibrary
```

This error occurs at `IrtDb.cs:190` in the `ReadPeptides()` method when NHibernate tries to query the `IrtLibrary` table which does not exist in the corrupted/incompatible database file.

## Initial Fix Attempt (Discarded)

The initial approach added a friendly message in `IrtDb.GetIrtDb()` for "no such table" SQLite errors. This was **discarded** after deeper analysis revealed the root cause is elsewhere.

**Why the initial fix was wrong:**
1. `IrtDb.GetIrtDb()` already has proper exception handling that wraps errors in `DatabaseOpeningException`
2. When a `LoadMonitor` is passed, errors are reported through `IProgressMonitor.UpdateProgress(status.ChangeErrorException(x))`
3. The real problem is that `IrtDbManager.LoadBackground()` doesn't catch exceptions properly, letting them bubble up to `BackgroundLoader.OnLoadBackground()` which sends ALL uncaught exceptions to `Program.ReportException()` (the crash dialog)

## Root Cause Analysis (Revised)

### Architecture Overview

The Skyline background loading architecture has these layers:

1. **BackgroundLoader.OnLoadBackground()** - Base class method that runs on background thread
   - Has a catch-all: `catch (Exception) { Program.ReportException(exception); }`
   - This means ANY unhandled exception becomes a crash dialog

2. **IrtDbManager.LoadBackground()** - Override that loads iRT databases
   - Currently has NO try-catch for most operations
   - Calls `LoadCalculator()` which properly passes a `LoadMonitor` to `RCalcIrt.Initialize()`
   - BUT also calls `IrtDb.GetIrtDb(path, null)` with `null` for the monitor in lines 122 and 129
   - Other operations like `calc.GetDbIrtPeptides()` have no exception handling

3. **IrtDb.GetIrtDb()** - Model layer database opening
   - Has proper exception handling that converts errors to `DatabaseOpeningException`
   - When `loadMonitor != null`: reports errors via `loadMonitor.UpdateProgress(status.ChangeErrorException(x))` and returns `null`
   - When `loadMonitor == null`: throws `DatabaseOpeningException`
   - The existing error messages are already user-friendly

### The Real Bug

The exception reaches the crash dialog because:
1. `IrtDbManager.LoadBackground()` calls `IrtDb.GetIrtDb(path, null)` with null monitor
2. `GetIrtDb()` throws `DatabaseOpeningException` (as designed when no monitor)
3. No code catches this exception
4. It bubbles up to `BackgroundLoader.OnLoadBackground()` catch-all
5. `Program.ReportException()` shows the crash dialog

### The Correct Pattern

`LibraryManager.CallWithSettingsChangeMonitor()` shows the correct pattern:

```csharp
catch (Exception x)
{
    if (ExceptionUtil.IsProgrammingDefect(x))
    {
        throw;  // Let programming defects go to crash dialog for reporting
    }
    settingsChangeMonitor.ChangeProgress(s => s.ChangeErrorException(x));
    return null;  // User-actionable errors reported through progress monitor
}
```

`ExceptionUtil.IsProgrammingDefect()` returns `false` for user-actionable exceptions:
- `InvalidDataException`, `IOException`, `OperationCanceledException`
- `UnauthorizedAccessException`, `UserMessageException` (and subclasses)

## Correct Fix Approach

### 1. Wrap IrtDbManager.LoadBackground() in try-catch

```csharp
protected override bool LoadBackground(IDocumentContainer container, SrmDocument document, SrmDocument docCurrent)
{
    var loadMonitor = new LoadMonitor(this, container, document);
    IProgressStatus status = new ProgressStatus(IrtResources.IrtDbManager_LoadBackground_Loading_iRT_calculator);

    try
    {
        loadMonitor.UpdateProgress(status);

        // ... existing code ...

        loadMonitor.UpdateProgress(status.Complete());
        return true;
    }
    catch (Exception x)
    {
        if (ExceptionUtil.IsProgrammingDefect(x))
        {
            throw;  // Programming defects should reach crash dialog
        }
        loadMonitor.UpdateProgress(status.ChangeErrorException(x));
        EndProcessing(document);
        return false;
    }
}
```

### 2. Pass LoadMonitor to all IrtDb.GetIrtDb() calls

Lines 122 and 129 currently pass `null`:
```csharp
calc = calc.ChangeDatabase(IrtDb.GetIrtDb(calc.DatabasePath, null));
```

Should pass the loadMonitor and handle null return:
```csharp
var db = IrtDb.GetIrtDb(calc.DatabasePath, loadMonitor);
if (db == null)
{
    EndProcessing(document);
    return false;
}
calc = calc.ChangeDatabase(db);
```

### 3. Progress Reporting Design Consideration

The current design has `IrtDb.GetIrtDb()` creating its own `ProgressStatus`:
```csharp
var status = new ProgressStatus(string.Format(IrtResources.IrtDb_GetIrtDb_Loading_iRT_database__0_, path));
```

This breaks the progress tracking chain because:
- Each `ProgressStatus` has an `Id` property for identifying operations
- You track the same operation via `ReferenceEquals` on the `Id`
- Creating a new status loses the connection to the outer caller's progress tracking

**Ideal fix**: `IrtDb.GetIrtDb()` should optionally accept an `IProgressStatus` parameter and advance it 0-100%. The outer caller can use `ChangeSegments()` to make that 0-100% represent only part of the overall operation.

**Pragmatic fix**: For this issue, wrapping `LoadBackground()` in try-catch is sufficient. The progress reporting refinement can be a separate improvement.

## Files Modified

1. `pwiz_tools/Skyline/Model/Irt/IrtDbManager.cs` - Added try-catch with `IsProgrammingDefect()` pattern
   - Extracted `LoadBackgroundInner()` for cleaner exception handling
   - Pass `LoadMonitor` to `IrtDb.GetIrtDb()` calls instead of `null`
   - Consolidated duplicate database loading into single load

Note: No new resource strings needed - `IrtDb.GetIrtDb()` already has user-friendly messages.

## Progress

- [x] Read and understand the codebase
- [x] Create TODO file
- [x] Initial fix attempt (adding message in GetIrtDb) - DISCARDED
- [x] Deeper analysis of BackgroundLoader architecture
- [x] Audit of all BackgroundLoader subclasses (see Future Work section)
- [x] Reset branch to master (discarding initial fix)
- [x] Document correct fix approach
- [x] Implement try-catch wrapper in IrtDbManager.LoadBackground()
- [x] Thread IProgressStatus through call chain via ref parameter
- [x] Add IrtDb.GetIrtDb() overloads with clear null-monitor semantics
- [x] Consolidate duplicate database loading (load once, reuse for duplicate removal)
- [x] Build and test locally (all iRT tests pass)
- [x] Create PR #3867
- [x] Address Copilot review comments
- [x] TeamCity nightly testing
- [x] Merge PR to master

**Release notes**: Not cherry-picked to 26.1 release branch (too close to release). Will ship in next major release and begin testing in Skyline-daily after 26.1 ships.

## Test Plan

1. **Existing iRT tests** - Must still pass:
   - IrtCalibrationTest, MinimizeIrtTest, BlibIrtTest, AddIrtStandardsTest, AssayLibraryImportTest

2. **New test for corrupted database** - Add to IrtTest.cs:
   - Create a valid SQLite database file with no tables
   - Attempt to open it as an iRT calculator
   - Verify user-friendly error is shown (not crash dialog)
   - Verify error message contains the file path

---

## Future Work: BackgroundLoader Exception Handling Audit

A comprehensive audit of all 9 `BackgroundLoader.LoadBackground()` overrides revealed widespread inconsistency in exception handling. This should be addressed in a separate PR.

### Summary Table

| Manager | File | Has Try-Catch | Uses IsProgrammingDefect | Status |
|---------|------|---------------|--------------------------|--------|
| IrtDbManager | Irt\IrtDbManager.cs | YES | YES | **FIXED (this PR)** |
| IonMobilityLibraryManager | IonMobility\IonMobilityLibraryManager.cs | NO | NO | **NO HANDLING** |
| LibraryManager | Lib\Library.cs | YES | YES | **CORRECT** |
| OptimizationDbManager | Optimization\OptimizationDbManager.cs | NO | NO | **NO HANDLING** |
| BackgroundProteomeManager | Proteome\BackgroundProteomeManager.cs | YES | NO | **INCORRECT** |
| ProteinMetadataManager | Proteome\ProteinMetadataManager.cs | YES | NO | **INCORRECT** |
| ChromatogramManager | Results\Chromatogram.cs | NO | NO | **NO HANDLING** |
| RetentionTimeManager | RetentionTimes\RetentionTimeManager.cs | YES | NO | **INCORRECT** |
| AutoTrainManager | Results\Scoring\AutoTrainManager.cs | YES | NO | **INCORRECT** |

### Issue Categories

**NO HANDLING (4 managers)**: Exceptions bubble up to crash dialog
- IrtDbManager, IonMobilityLibraryManager, OptimizationDbManager, ChromatogramManager
- User-actionable errors (corrupt files, locked files, etc.) show crash dialog
- **Priority**: HIGH - these should be fixed

**INCORRECT (4 managers)**: Catch all exceptions without `IsProgrammingDefect()` check
- BackgroundProteomeManager, ProteinMetadataManager, RetentionTimeManager, AutoTrainManager
- Programming defects (NullReferenceException, etc.) are hidden from crash dialog
- Makes debugging harder because defects aren't reported
- **Priority**: MEDIUM - should be fixed for code health

**CORRECT (1 manager)**: LibraryManager
- Uses `ExceptionUtil.IsProgrammingDefect()` to distinguish user errors from programming defects
- User errors reported through progress monitor
- Programming defects thrown to crash dialog for reporting

### Recommended Follow-up

1. Create GitHub issue for BackgroundLoader exception handling audit
2. Fix all managers to use the correct pattern:
   ```csharp
   catch (Exception x)
   {
       if (ExceptionUtil.IsProgrammingDefect(x))
           throw;
       progressMonitor.UpdateProgress(status.ChangeErrorException(x));
       return false;
   }
   ```
3. Consider whether `CalculatorException` / `DatabaseOpeningException` should extend `UserMessageException` to be recognized by `IsProgrammingDefect()`

### Follow-up Issue

See: [#3871 - BackgroundLoader exception handling audit](https://github.com/ProteoWizard/pwiz/issues/3871)
