# GarbageCollectionTracker - WeakReference-based GC Regression Test

## Branch Information
- **Branch**: `Skyline/work/20260223_gc_leak_tracker`
- **Base**: `master`
- **Created**: 2026-02-23
- **Status**: Ready for PR
- **Related**: [PR #4032](https://github.com/ProteoWizard/pwiz/pull/4032) (Nick Shulman - MemoryLeaks fix, MERGED)
- **PR**: (pending)

## Summary

Added a WeakReference-based GC leak tracker that verifies SkylineWindow and SrmDocument
are garbage collected after each functional test. During development, discovered and fixed
two real leaks: `DuplicatedPeptideFinder._lastSearchedDocument` (static cache holding strong
reference to SrmDocument) and test-side audit log entry caches holding undo closures that
captured SkylineWindow.

## Changes

### Production code fix
- `Model/Find/DuplicatedPeptideFinder.cs` - Changed `_lastSearchedDocument` from `SrmDocument`
  to `WeakReference<SrmDocument>` to prevent static `Finders.LST_FINDERS` from holding documents
  indefinitely. This was the root cause of 11 of 12 initially failing tests.

### Test infrastructure (already committed in initial tracker commit)
- `TestRunnerLib/GarbageCollectionTracker.cs` - Static tracker class with Register, CheckForLeaks,
  Clear, and PinSurvivors methods
- `Program.cs` - IGarbageCollectionTracker interface and Program.GcTracker static property
- `Skyline.cs` - SkylineWindow and SrmDocument registration
- `TestUtil/TestFunctional.cs` - GcTrackerAdapter bridge + audit log cleanup
- `TestRunnerLib/RunTests.cs` - GC leak check after FlushMemory, dotMemory integration

### Additional fixes in this commit
- `TestRunnerLib/RunTests.cs` - `_testObject` as instance field for proper nulling before GC;
  dotMemory single-snapshot support (WaitRuns=0); PinSurvivors for dotMemory inspection
- `TestRunnerLib/GarbageCollectionTracker.cs` - Enhanced diagnostics (total/collected counts,
  Target type names); PinSurvivors for dotMemory retention path analysis
- `TestUtil/TestFunctional.cs` - CleanupAuditLogs() clears `_setSeenEntries` and
  `_lastLoggedEntries` to break reference chain from test -> AuditLogEntry -> undo closure -> SkylineWindow
- `TestFunctional/RetentionTimeManagerTest.cs` - `_documents.Clear()` at end of DoTest
- `TestRunner/Program.cs` - Fixed dotMemory config to activate on warmup > 0 (not waitruns > 0)

### Script changes (not committed to pwiz repo)
- `ai/scripts/Skyline/Run-Tests.ps1` - Single-snapshot support with `-MemoryProfileWaitRuns 0`

## Root cause analysis

### Primary leak: DuplicatedPeptideFinder (static cache)
`Finders.LST_FINDERS` (static) -> `DuplicatedPeptideFinder` -> `_lastSearchedDocument` (strong ref)
-> SrmDocument -> AuditLog -> AuditLogEntry._undoAction closure -> SkylineWindow

Every SrmDocument created through ModifyDocument carries an AuditLogEntry with an undo closure
(Skyline.cs:876) that captures `this` (SkylineWindow). So any strong reference to an SrmDocument
transitively holds SkylineWindow alive.

### Secondary leaks: test-side caches
- `_setSeenEntries` / `_lastLoggedEntries` in TestFunctional held AuditLogEntry objects
- `RetentionTimeManagerTest._documents` accumulated SrmDocuments during test

## Test results
- 395 TestFunctional tests: **ALL PASS** (full English run, serial + parallel validation)
