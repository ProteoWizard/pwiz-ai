# GarbageCollectionTracker - WeakReference-based GC Regression Test

## Branch Information
- **Branch**: `Skyline/work/20260223_gc_leak_tracker`
- **Base**: `master`
- **Created**: 2026-02-23
- **Status**: In Progress
- **Related**: [PR #4032](https://github.com/ProteoWizard/pwiz/pull/4032) (Nick Shulman - MemoryLeaks fix, MERGED), [PR #4033](https://github.com/ProteoWizard/pwiz/pull/4033) (ConnectionPool diagnostics)
- **PR**: (pending)

## Current State (save point for context compaction)

### What's done - committed on branch
One commit `2e7f2e18a` rebased on top of master (which includes Nick's PR #4032):

**Files changed (all paths relative to `pwiz_tools/Skyline/`):**
- `TestRunnerLib/GarbageCollectionTracker.cs` - **New file**. Static class with `Register(Type, object)`, `CheckForLeaks()`, `Clear()`. Groups survivors by `Type.Name` with counts (e.g. `SrmDocument x5`).
- `TestRunnerLib/TestRunnerLib.csproj` - Added Compile entry for new file
- `TestRunnerLib/RunTests.cs` - After `FlushMemory()` (~line 500): if test passed, calls `CheckForLeaks()` and fails test on leak; if test already failed, calls `Clear()`. Uses `!!! GC-LEAK` prefix matching existing `!!! CRT-LEAKED` pattern.
- `Program.cs` - Added `IGarbageCollectionTracker` interface (takes `Type type, object target`) and `static IGarbageCollectionTracker GcTracker` property (null in production)
- `Skyline.cs` - SkylineWindow constructor calls `Program.GcTracker?.Register(typeof(SkylineWindow), this)`. `SetDocument()` calls `Program.GcTracker?.Register(typeof(SrmDocument), docNew)` after successful CAS swap - this tracks EVERY document that becomes active.
- `TestUtil/TestFunctional.cs` - `RunFunctionalTestOrThrow()` sets `Program.GcTracker = new GcTrackerAdapter()`. Added `GcTrackerAdapter` internal class at end of file that bridges `IGarbageCollectionTracker` to TestRunnerLib's static `GarbageCollectionTracker.Register()`.

### Test results
1. **Against unfixed master (before Nick's PR):** Both `AlertDlgIconsTest` and `TestDiaSearchFixedWindows` correctly fail with `!!! GC-LEAK Objects not garbage collected after test: SkylineWindow, SrmDocument`
2. **566 unit tests pass** - no false positives or NREs from the tracker
3. **After rebasing on master with Nick's PR #4032 merged:** Tests STILL FAIL with same leak message. This means **Nick's fixes alone are not sufficient** to resolve all GC roots keeping SkylineWindow and SrmDocument alive.

### What needs investigation
Nick's PR fixed:
- `PollingCancellationToken` thread now joins on Dispose (releases SrmDocument delegate)
- `SkylineRemoteAccountServices` singleton replaces `RemoteUrl.RemoteAccountStorage = this` (breaks SkylineWindow static reference)

But `RemoteSession.RemoteAccountUserInteraction = this` is still set in SkylineWindow constructor (line 198). Nick's `OnClosed` handler nulls it, but the question is whether OnClosed runs reliably in test cleanup. There may be additional static reference chains.

**Next step:** Investigate which static references are still holding SkylineWindow alive after test cleanup. Check `RemoteSession.RemoteAccountUserInteraction`, and look for other statics that reference SkylineWindow. May need to use ConnectionPool tracking (PR #4033) or add diagnostic output to identify the GC root chain.

## Design

### Architecture (interface-based, as implemented)

```
Skyline project:
  IGarbageCollectionTracker interface on Program
  Program.GcTracker static property (null in production)
  SkylineWindow constructor -> registers this
  SetDocument -> registers every SrmDocument

TestRunnerLib project:
  GarbageCollectionTracker static class (Register, CheckForLeaks, Clear)
  RunTests.Run() -> checks after FlushMemory

TestUtil project:
  GcTrackerAdapter bridges IGarbageCollectionTracker to static GarbageCollectionTracker
  RunFunctionalTestOrThrow -> sets Program.GcTracker = new GcTrackerAdapter()
```

Key design decisions:
- Interface in Skyline lets objects register themselves at the source
- TestRunnerLib holds tracking logic (where FlushMemory and RunTests.Run live)
- TestUtil bridges the two (references both assemblies)
- `Type` parameter lets tracker decide naming (currently uses `Type.Name`)
- Survivors grouped by type with counts for concise reporting
- Non-generic `WeakReference` since TestRunnerLib can't reference Skyline types
