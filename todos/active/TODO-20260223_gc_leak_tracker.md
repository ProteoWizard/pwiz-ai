# GarbageCollectionTracker - WeakReference-based GC Regression Test

## Branch Information
- **Branch**: `Skyline/work/20260223_gc_leak_tracker`
- **Base**: `master`
- **Created**: 2026-02-23
- **Status**: In Progress
- **Related**: [PR #4032](https://github.com/ProteoWizard/pwiz/pull/4032) (Nick Shulman - MemoryLeaks fix), [PR #4033](https://github.com/ProteoWizard/pwiz/pull/4033) (ConnectionPool diagnostics)
- **PR**: (pending)

## Problem

PR #4032 fixes memory leaks where static references kept `SkylineWindow` and
`SrmDocument` alive after tests ended (PollingCancellationToken holding
SrmDocument via delegate, RemoteSession/RemoteUrl holding SkylineWindow).
We need a regression test to prevent silent re-introduction of such leaks.

## Approach

A static tracker using weak references, inspired by a Java pattern of using
weak-reference maps to assert that primary objects are properly released after
each test. The tracker:

1. **Registers** objects expected to be GC'd (SkylineWindow, SrmDocument)
2. **Verifies** they were collected after `FlushMemory()` does a full GC
3. **Fails the test** if any survive, catching regressions immediately

## Files to Modify

| File | Change |
|------|--------|
| `TestRunnerLib/GarbageCollectionTracker.cs` | **New** - static tracker class |
| `TestRunnerLib/TestRunnerLib.csproj` | Add Compile entry |
| `TestUtil/TestFunctional.cs` | Register objects in `EndTest()` |
| `TestRunnerLib/RunTests.cs` | Check for leaks after `FlushMemory()` |

All paths relative to `pwiz_tools/Skyline/`.

## Design

### GarbageCollectionTracker (new file in TestRunnerLib)

Static class with three methods:

- **`Register(string name, object target)`** - Stores a `WeakReference` with a
  descriptive name. No-op if target is null. Only a WeakReference is held, so
  registration itself does not prevent collection.
- **`CheckForLeaks()`** - Returns null if all tracked objects were collected, or
  an error message listing survivors. Always clears the tracker.
- **`Clear()`** - Clears tracked objects without checking. Used when a test has
  already failed and leak checking would produce misleading noise.

Lives in TestRunnerLib (not CommonUtil) because the check point is in
`RunTests.Run()`. Uses non-generic `WeakReference` since TestRunnerLib cannot
reference Skyline types. Thread-safe via lock.

### Registration in TestFunctional.EndTest()

Insert after line 2733 (the early-return for null/disposed window), before
the `try` block at line 2735:

```csharp
// Track primary objects for GC verification after test cleanup
GarbageCollectionTracker.Register("SkylineWindow", skylineWindow);
GarbageCollectionTracker.Register("SrmDocument", skylineWindow.Document);
```

- After the null/disposed check, so we only track when a real window exists
- Before `SwitchDocument` replaces the document
- Uses `Document` (thread-safe) not `DocumentUI` (UI-thread only)
- `using TestRunnerLib;` already present at line 67

### Leak Check in RunTests.Run()

Insert after `FlushMemory()` at line 499, before `_process.Refresh()`:

```csharp
// Check for GC leaks - objects registered by test code that should
// have been collected after FlushMemory's full GC cycle
if (exception != null)
{
    GarbageCollectionTracker.Clear();
}
else
{
    var leakMessage = GarbageCollectionTracker.CheckForLeaks();
    if (leakMessage != null)
    {
        Log("!!! {0} GC-LEAK {1}\r\n", test.TestMethod.Name, leakMessage);
        exception = new Exception(leakMessage);
    }
}
```

- FlushMemory has done `GC.Collect()` x2 + `WaitForPendingFinalizers()`
- All test stack frames are gone (test method returned)
- `Program.MainWindow` is null
- Follows existing `!!! CRT-LEAKED` pattern (line 589)
- Skips check when test already failed to avoid noise

## Edge Cases

- **Unit tests**: Never register anything, `CheckForLeaks()` returns null
- **Test already failed**: `Clear()` resets without checking
- **StartPage-only tests**: `EndTest()` early-returns before registration
- **Stress testing loops**: `CheckForLeaks()` always clears after checking
