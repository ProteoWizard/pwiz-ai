# TODO-20260121_fix_testolderproteomedb_leak.md

## Branch Information
- **Branch**: `Skyline/work/20260121_fix_testolderproteomedb_leak`
- **Base**: `master`
- **Created**: 2026-01-21
- **Status**: COMPLETED
- **GitHub Issue**: [#3855](https://github.com/ProteoWizard/pwiz/issues/3855)
- **PR (fix)**: [#3859](https://github.com/ProteoWizard/pwiz/pull/3859) - Cherry-pick to release
- **PR (diagnostics)**: [#3860](https://github.com/ProteoWizard/pwiz/pull/3860) - Master only

## Problem Description

TestOlderProteomeDb has a ~10KB memory leak occurring since 2025-11-19. The leak only affects i9 processors:
- BDCONNOL-UW1
- EKONEIL01/BRENDANX-UW25
- BRENDANX-UW7

This appears to be a timing-related issue where faster processors expose the leak more quickly.

## Initial Hypothesis (WRONG)

The original hypothesis was that a **static `TestBehavior` field** in `HttpClientWithProgress.cs` was causing race conditions when tests run in parallel on fast processors.

**This hypothesis was incorrect.** The `[ThreadStatic]` fix was committed and pushed, but nightly tests continued to show the leak.

### Lesson Learned: "Commit and See" is Poor Strategy

The approach of making an educated guess and committing it to see if nightly tests improve is problematic:
1. Wastes at least 24 hours waiting for nightly results
2. Pollutes git history with ineffective changes
3. Creates false confidence in understanding the problem
4. Delays actual root cause investigation

**Better approach**: Use the debugging methodology in [debugging-principles.md](../docs/debugging-principles.md) and [leak-debugging-guide.md](../docs/leak-debugging-guide.md) to isolate and verify the root cause BEFORE committing.

## Actual Root Cause (Discovered 2026-01-23)

The actual root cause was **uncancelled Task.Delay timers** in `HttpClientWithProgress.ReadChunk()`:

```csharp
// BEFORE (leaking)
private int ReadChunk(Stream stream, byte[] buffer, Uri uri)
{
    var readTask = stream.ReadAsync(buffer, 0, buffer.Length, CancellationToken);
    var delayTask = Task.Delay(ReadTimeoutMilliseconds, CancellationToken);
    var completed = Task.WaitAny(readTask, delayTask);
    // ...
}
```

**The Problem:**
- `Task.Delay` creates an internal `Timer` object that runs for `ReadTimeoutMilliseconds` (15 seconds)
- When `readTask` completes first (the normal case), `delayTask` is abandoned but its timer continues running
- Each timer holds Timer, TimerHolder, TimerQueueTimer, and Task+DelayPromise objects
- On fast i9 machines, tests complete quickly, so many timers accumulate before the 15-second window passes
- dotMemory profiling showed 12 timer-related objects accumulating per test run

**Why it appeared processor-specific:**
- Faster processors complete tests more quickly
- More tests run within the 15-second timer window
- More timers accumulate before cleanup
- Slower machines complete fewer tests before timers expire naturally

## Actual Fix

Cancel the delay timer immediately when the read completes:

```csharp
// AFTER (fixed)
private int ReadChunk(Stream stream, byte[] buffer, Uri uri)
{
    var readTask = stream.ReadAsync(buffer, 0, buffer.Length, CancellationToken);

    // Use a dedicated CTS for the delay so we can cancel it when done.
    // This prevents timer accumulation - each Task.Delay creates an internal Timer
    // that would otherwise run for the full ReadTimeoutMilliseconds duration.
    using var timeoutCts = CancellationTokenSource.CreateLinkedTokenSource(CancellationToken);
    try
    {
        var delayTask = Task.Delay(ReadTimeoutMilliseconds, timeoutCts.Token);
        var completed = Task.WaitAny(readTask, delayTask);

        // Check if cancellation was requested before throwing timeout exception
        CancellationToken.ThrowIfCancellationRequested();

        if (completed != 0)
            throw new TimeoutException(...);
        return readTask.Result;
    }
    finally
    {
        // Cancel the delay timer to prevent timer/handle accumulation
        timeoutCts.Cancel();
    }
}
```

## Verification (2026-01-23)

### Memory Profiling with dotMemory

Used the new dotMemory snapshot support (PR #3860) to profile TestOlderProteomeDb:

1. **5 runs**: Showed baseline memory pattern with timer objects
2. **25 runs**: Showed 5x scaling of timer objects (confirming linear leak)
3. **50 runs after fix**: Memory stable, no timer accumulation

### Key Evidence from Profiler

The dotMemory comparison showed these objects scaling linearly with run count:
- `System.Threading.Timer`
- `System.Threading.TimerHolder`
- `System.Threading.TimerQueueTimer`
- `System.Threading.Tasks.Task+DelayPromise`

Each test run leaked 12 instances of this pattern, matching the number of HTTP requests in TestOlderProteomeDb.

## Files Modified

### PR #3859 (Fix - Cherry-pick to release)
- `pwiz_tools/Shared/CommonUtil/SystemUtil/HttpClientWithProgress.cs`
  - Modified `ReadChunk()` to cancel Task.Delay timer on completion

### PR #3860 (Diagnostics - Master only)
- `pwiz_tools/Skyline/TestRunnerLib/RunTests.cs`
  - Added dotMemory profiling support with configurable warmup and wait runs
- `pwiz_tools/Skyline/TestRunnerLib/TestRunnerLib.csproj`
  - Added JetBrains.Profiler.Api NuGet reference
- `pwiz_tools/Skyline/TestUtil/AbstractUnitTest.cs`
  - Added `DatabaseResources.ReleaseAll()` to unit test cleanup

## Tasks

- [x] Read and understand the codebase
- [x] Create TODO file
- [x] Initial hypothesis and fix ([ThreadStatic]) - INEFFECTIVE
- [x] dotMemory profiling to identify actual root cause
- [x] Implement correct fix (cancel Task.Delay timer)
- [x] Verify fix with 50-run memory test
- [x] Create PR #3859 for the fix (cherry-pick to release)
- [x] Create PR #3860 for diagnostics (master only)
- [x] Update TODO with lessons learned

## Lessons Learned

1. **Understand before fixing**: The principles in debugging-principles.md and leak-debugging-guide.md are essential. Hypothesis-driven "commit and see" approaches waste time and create noise.

2. **Use the right tools**: dotMemory profiling immediately revealed the actual leak pattern (timer objects), while handle counts were misleading (focused on wrong object types).

3. **Time-based issues need time-aware investigation**: The 15-second timeout meant the leak was temporal. Profiling across multiple runs was essential to see the accumulation pattern.

4. **Task.Delay has hidden costs**: Every `Task.Delay` creates timer infrastructure that persists until timeout. When using Task.Delay with Task.WaitAny, always cancel the delay when it loses the race.
