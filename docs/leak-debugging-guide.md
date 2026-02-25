# Handle Leak Debugging Guide

This guide documents the methodology for identifying and fixing handle leaks in Skyline, developed during the Files view feature work (December 2025).

> **See also:** [debugging-principles.md](debugging-principles.md) for the general debugging methodology that applies to all types of bugs, including the cycle time analysis, printf debugging techniques, and strategic instrumentation patterns that informed this guide.

## End-to-End Workflow

The complete leak debugging workflow spans two phases:

### Phase 1: Leak Detection and Test Selection (Human)

The nightly test system runs tests on both the Integration branch and Master branch, reporting handle leak counts per test. A human reviews these results to:

1. **Compare Integration vs Master**: Significant difference indicates a leak introduced by the Integration branch
2. **Identify candidate tests**: Tests showing consistent handle leaks
3. **Calculate "handles leaked per second"**: Key metric for selecting the optimal test for isolation
   - Formula: `average_handles_leaked / test_duration_seconds`
   - Higher values = faster feedback during bisection
4. **Select the best test**: Balance between leak magnitude and test runtime
   - Example: `TestAuditLogSaving` leaked ~10 handles in ~64 seconds (~0.16 handles/sec)
   - A 10-iteration loop takes ~10 minutes and clearly shows the leak trend

### Phase 2: Leak Isolation and Fix (Claude Code)

Once a test is selected, Claude Code can autonomously:

1. **Establish baseline**: Run 10-iteration loop with `-ReportHandles -SortHandlesByCount`
2. **Identify leaking handle type**: User/GDI (forms/controls) vs kernel handles (threads/events)
3. **Bisect the test**: Systematically add `return;` statements to narrow down the leak location
4. **Analyze and fix**: Examine the isolated code, identify the leak, implement fix
5. **Validate**: Re-run the loop test to confirm handles are stable

This separation of concerns allows efficient collaboration: the human leverages server-side data to identify *what* to investigate, then hands off to Claude Code for the detailed *how* of isolation and fixing.

## Overview

Handle leaks occur when Windows handles (HWNDs, GDI objects, kernel objects) are allocated but not properly released. Over time, leaked handles accumulate and can cause:
- Memory growth
- Resource exhaustion
- Application instability
- Test failures in long-running test sessions

## Handle Types

Windows has several categories of handles:

| Category | Examples | Common Causes |
|----------|----------|---------------|
| **User handles** | HWNDs (windows, controls) | Forms/controls not disposed, parentless dialogs |
| **GDI handles** | Icons, pens, brushes, fonts, bitmaps | Graphics resources not disposed, Icon.FromHandle() |
| **Kernel handles** | Threads, events, mutexes, files, semaphores | Threads not joined, synchronization primitives not disposed |

## Detection Tools

### Nightly Test Reports

Skyline's nightly test system tracks handle counts:
- **Integration branch** vs **Master branch** comparison
- Per-test handle leak counts
- Memory growth trends

The nightly report format shows `<User+GDI>/<Total>` handles, e.g., `220/550`.

### TestRunner Handle Reporting

Use the `-ReportHandles` flag to see handle counts during test runs:

```powershell
# Basic handle reporting
.\ai\Run-Tests.ps1 -TestName TestAuditLogSaving -Loop 10 -ReportHandles

# Sort by count (leaking types rise to top over multiple runs)
.\ai\Run-Tests.ps1 -TestName TestAuditLogSaving -Loop 10 -ReportHandles -SortHandlesByCount
```

Output format:
```
[11:01]   2.0   TestAuditLogSaving   (en)   0 failures, 4.67/5.52/97.0 MB, 93/550 handles, 4 sec.
# Handles User: 26	GDI: 67	EtwRegistration: 145	Event: 110	...
```

The `# Handles` line shows breakdown by type. When sorted by count, leaking types accumulate and rise to the top of the list.

## Investigation Methodology

### Step 1: Establish a Reproducible Test Case

Find a test that triggers the leak consistently:

```powershell
# Run 10 iterations to see if handles grow
.\ai\Run-Tests.ps1 -TestName TestSuspectedLeak -Loop 10 -ReportHandles -SortHandlesByCount
```

Look for patterns:
- **Stable**: Handles fluctuate but don't trend upward (no leak)
- **Growing**: Handles increase steadily each run (leak detected)

Example of leak detection:
```
Run 2:  GDI: 53   User: 20   (baseline)
Run 3:  GDI: 56   User: 22   (+3, +2)
Run 4:  GDI: 59   User: 24   (+3, +2)
Run 5:  GDI: 62   User: 25   (+3, +1)
...
Run 11: GDI: 80   User: 31   (clearly growing)
```

### Step 2: Identify the Leaking Handle Type

Focus on the **largest leaking type first**:

- **User handles leaking**: Usually forms or controls not disposed
- **GDI handles leaking**: Usually graphics resources (icons, brushes, etc.)
- **Thread handles leaking**: Usually threads not properly joined
- **Event/Semaphore handles leaking**: Usually synchronization primitives

User handles often "bring" GDI handles with them (each window has associated GDI resources).

### Step 3: Bisect the Test

This is the key technique. Systematically narrow down where in the test the leak occurs:

1. **Find midpoint**: Add `return;` statement at approximately the middle of the test
2. **Run and compare**: If leak persists, it's in the first half; if not, it's in the second half
3. **Repeat**: Continue bisecting until you isolate the specific operation

Example bisection:
```csharp
protected override void DoTest()
{
    OpenDocument("test.sky");

    // ... first quarter of test ...

    return; // BISECT: Testing first quarter

    // ... rest of test ...
}
```

**Tip**: Choose meaningful boundaries (document operations, dialog shows, etc.) rather than arbitrary line counts.

### Step 4: Analyze the Leaking Code

Once isolated to a specific operation, use **printf debugging** to understand the runtime behavior. With a fast cycle time, add `Console.WriteLine()` statements liberally - you can answer questions about object identity, thread context, and call frequency faster than reasoning about the code statically.

Examine:

1. **What handles are being created?**
   - `new Thread()`
   - `Icon.FromHandle()`, `Bitmap.GetHicon()`
   - `new Form()`, `new Control()`
   - `new AutoResetEvent()`, `new ManualResetEvent()`

2. **Are they being disposed?**
   - Check `Dispose()` implementations
   - Check `using` statements
   - Check static caching (vs. repeated creation)

3. **Is disposal actually called?**
   - Forms with `HideOnClose = true` aren't disposed on close
   - Event handlers may prevent GC
   - Circular references may prevent disposal

### Step 5: Fix and Validate

Common fixes:

| Problem | Solution |
|---------|----------|
| Icon created each time | Cache in static readonly field |
| Form not disposed | Ensure `HideOnClose = false` before final close |
| Thread not joined | Wait for thread completion in Dispose |
| Event handlers holding references | Unsubscribe in Dispose |

After fixing, validate with the same loop test:
```powershell
.\ai\Run-Tests.ps1 -TestName TestAuditLogSaving -Loop 10 -ReportHandles -SortHandlesByCount
```

Handles should now be stable (fluctuating but not trending upward).

## Case Study: AuditLogForm Icon Leak (December 2025)

### Detection (Human - Phase 1)

Nightly tests showed 30-41 handle leaks on the Integration branch vs 0-1 on master. The human reviewed per-test leak data from the LabKey server:

| Test | Avg Handles Leaked | Duration (sec) | Handles/sec |
|------|-------------------|----------------|-------------|
| TestAuditLog | 2.9 | 60.49 | 0.048 |
| TestAuditLogSaving | 10.3 | 63.87 | 0.161 |
| TestAuditLogTutorial | 15.4 | 64.87 | 0.237 |

**Test selection rationale**: `TestAuditLogSaving` was chosen because:
- High leak rate (10.3 handles/run) - clearly detectable in 10 iterations
- Moderate duration (~64 sec) - 10-iteration loop completes in ~10 minutes
- Good handles/sec ratio - efficient for bisection cycles

### Investigation (Claude Code - Phase 2)

1. **Established reproducible case**: 10-run loop showed ~3 GDI + ~1 User handles leaked per run
2. **Identified type**: GDI handles were the primary leak (User handles often follow)
3. **Bisected test**:
   - Full test: leaks present
   - First half: leaks present (smaller)
   - First quarter: leaks present
   - Just `OpenDocument()`: NO leak
   - `OpenDocument()` + `ShowAuditLog()`: leaks present
4. **Isolated to**: `SkylineWindow.ShowAuditLog()` call

### Root Cause

In `AuditLogForm.cs`:
```csharp
// BEFORE (leaking)
public AuditLogForm(...)
{
    InitializeComponent();
    Icon = Resources.AuditLog.ToIcon();  // Creates new HICON every time!
    ...
}
```

`ToIcon()` uses `Icon.FromHandle(bitmap.GetHicon())` which creates a native handle. Each form instance created a new handle that was never properly released.

### Fix

Cache the icon statically:
```csharp
// AFTER (fixed)
public partial class AuditLogForm : DocumentGridForm
{
    private static readonly Icon AUDIT_LOG_ICON = Resources.AuditLog.ToIcon();

    public AuditLogForm(...)
    {
        InitializeComponent();
        Icon = AUDIT_LOG_ICON;  // Reuses single cached icon
        ...
    }
}
```

### Validation

After fix, 10-run loop showed stable handles: GDI fluctuated 60-67, User 26-28, with no upward trend.

## Case Study: FileSystemWatcher Race Condition (December 2025)

### Detection

After fixing the AuditLogForm icon leak, nightly tests still showed handle leaks. TestExplicitVariable was identified as a heavy leaker (~16 GDI handles per run).

### Investigation - Two-Level Bisection

This case demonstrated a refined bisection approach: **test-level bisection** followed by **code-level bisection**.

#### Level 1: Test Bisection (narrowing to the trigger)

1. **Full test**: Massive leak (~16 GDI, ~5 User, ~20 Event per run)
2. **First half (return at line 141)**: NO leak
3. **Second half**: Leak present - isolated to Save/Open document cycle
4. **Further isolation**: Deleting `.sky.view` file reduced leak significantly

This pointed to layout restore (which recreates `FilesTreeForm`) as the trigger.

#### Level 2: Code Bisection (finding the root cause)

Once we knew the *trigger* (document open with layout restore), we shifted to bisecting the *suspected code* rather than the test:

1. **Commented out `HandleDocumentEvent()` calls** in FilesTree.cs → leak stopped
2. **Uncommented `HandleDocumentEvent()`, commented out `FileSystemService.StartWatching()`** → leak stopped
3. **Enabled watching, commented out `WatchDirectory()` call** → leak stopped
4. **Enabled `WatchDirectory()`, commented out `managedFsw.Start()`** → leak stopped
5. **Enabled `Start()`, commented out event subscriptions** → STILL LEAKED

This narrowed it down to `FileSystemWatcher.EnableRaisingEvents = true`.

### Root Cause Discovery via Debugger

> **Note:** This case study used a debugger, but printf debugging would have been equally effective and faster. Adding `Console.WriteLine($"Start called for {directoryPath}, Thread: {Thread.CurrentThread.ManagedThreadId}")` would have revealed the 2:1 ratio in the test output directly. See [debugging-principles.md](debugging-principles.md) for the self-sufficiency principle: never ask the user about runtime behavior you can observe yourself.

Breakpoints revealed the smoking gun:
- **2 calls to `ManagedFileSystemWatcher.Start()`** for every **1 call to `StopWatching()`**
- All 3 calls were for the **same directory path**
- All 3 calls were on the **same `LocalFileSystemService` instance**

This indicated a **race condition**: two `BackgroundActionService` worker threads were both calling `WatchDirectory()` for the same path simultaneously.

### The Race Condition

```
Thread 9                              Thread 10
────────                              ─────────
WatchDirectory("C:\path")
  IsMonitoringDirectory? → false
                                      WatchDirectory("C:\path")
                                        IsMonitoringDirectory? → false
  Create ManagedFileSystemWatcher
  Start()
  FileSystemWatchers["C:\path"] = fsw1
                                        Create ManagedFileSystemWatcher
                                        Start()
                                        FileSystemWatchers["C:\path"] = fsw2  ← OVERWRITES!
```

Result: `fsw1` is orphaned - never disposed, its handles leak.

### Fix

Move the `IsMonitoringDirectory` check inside the lock:

```csharp
// BEFORE (race condition)
private void WatchDirectory(string directoryPath)
{
    if (directoryPath == null || IsMonitoringDirectory(directoryPath))
        return;

    var managedFsw = new ManagedFileSystemWatcher(...);
    managedFsw.Start();

    lock (_fswLock)
    {
        FileSystemWatchers[directoryPath] = managedFsw;
    }
}

// AFTER (thread-safe)
private void WatchDirectory(string directoryPath)
{
    if (directoryPath == null)
        return;

    lock (_fswLock)
    {
        if (IsMonitoringDirectory(directoryPath))
            return;

        var managedFsw = new ManagedFileSystemWatcher(...);
        managedFsw.Start();
        FileSystemWatchers[directoryPath] = managedFsw;
    }
}
```

### Key Lessons

1. **Two-level bisection**: When test bisection identifies a trigger but not the root cause, shift to bisecting the suspected code itself by commenting out features/functionality.

2. **Use the debugger strategically**: Once bisection narrows to a small area, breakpoints can reveal timing issues (like the 2:1 Start/Stop ratio) that aren't visible from handle counts alone.

3. **Watch for concurrent access**: When multiple threads access shared state, check-then-act patterns are inherently racy. The check and the act must be atomic.

4. **Handle counts tell the story**: The ratio of operations (2 Starts per 1 Stop) directly explained the leak rate (~16 handles per iteration = 1 orphaned watcher with ~16 handles).

## Best Practices

### Prevention

1. **Cache static resources**: Icons, brushes, and other GDI objects that don't change should be cached statically
2. **Use `using` statements**: For any IDisposable that's created and used locally
3. **Implement IDisposable properly**: Classes that hold handles should implement IDisposable
4. **Unsubscribe event handlers**: In Dispose methods
5. **Be careful with `Icon.FromHandle()`**: The comment in `UtilUI.ToIcon()` warns "caller is responsible for disposing"

### Testing

1. **Run leak detection in CI**: Nightly tests should compare Integration vs Master handle counts
2. **Add loop tests for new features**: When adding code that creates handles, verify with loop tests
3. **Document handle-creating code**: Add comments noting disposal requirements

## Tooling Enhancements (December 2025)

The following improvements were made to support leak debugging:

### Run-Tests.ps1

New parameters:
- `-ReportHandles`: Enable handle count diagnostics
- `-SortHandlesByCount`: Sort handle types by count (descending) so leaking types rise to top

### TestRunnerLib/RunTests.cs

- Added `SortHandlesByCount` property and command-line option
- Enhanced `# Handles` output to include User and GDI handles (not returned by HandleEnumeratorWrapper)
- Combined all handle types (User, GDI, kernel) in single sortable list

### TestRunner/Program.cs

- Added `sorthandlesbycount` command-line argument (default: off)

## Memory Profiling with dotMemory (January 2026)

For **managed memory leaks** (as opposed to handle leaks), dotMemory profiling provides detailed object-level analysis that handle counts cannot reveal.

### When to Use dotMemory

Use dotMemory when:
- Handle counts are stable but memory grows
- You suspect managed object accumulation (cached objects, event handlers, etc.)
- The leak involves .NET framework internals (timers, tasks, etc.)
- You need to see object allocation patterns across test runs

### TestRunner dotMemory Integration

TestRunnerLib includes automatic snapshot support when running under dotMemory. This eliminates manual snapshot timing and enables comparison across test iterations.

**How it works:**
1. Run tests under dotMemory profiler
2. TestRunner detects dotMemory and takes snapshots at configured intervals
3. Snapshots are taken immediately after `RunTest.MemoryManagement.FlushMemory()` clears collectible garbage
4. Compare snapshots in dotMemory to identify objects that accumulate

**Configuration:**

The snapshot behavior is controlled by properties on `RunTests`:
- `DotMemoryWarmupRuns` - iterations before first snapshot (baseline)
- `DotMemoryWaitRuns` - iterations between first and second snapshot (analysis period)
- `DotMemoryCollectAllocations` - when true, enables allocation stack trace collection

Currently these are set in code. For manual profiling sessions, modify the values in `RunTests.cs` or set them programmatically.

**Using dotMemory:**
```
1. Open dotMemory → Profile Application → TestRunner.exe
2. Add arguments: test=TestOlderProteomeDb loop=50
3. Set DotMemoryWarmupRuns and DotMemoryWaitRuns in code before profiling
4. Run and compare the two automatic snapshots
```

**Allocation Stack Traces:**

Set `DotMemoryCollectAllocations = true` to capture where leaked objects were allocated. This is enabled on the first snapshot, so the second snapshot shows allocation sites for objects created during the analysis period. This is invaluable for understanding *where* leaking objects originate.

### Case Study: Timer Leak in HttpClientWithProgress (January 2026)

dotMemory profiling was critical in solving Issue #3855, where handle-based debugging failed:

**Initial Investigation (handle counts):**
- Handle counts showed no obvious leak pattern
- GDI/User handles were stable
- Yet memory grew consistently on i9 machines

**dotMemory Analysis:**
1. Ran TestOlderProteomeDb with `-Loop 5` under dotMemory, snapshot taken
2. Ran with `-Loop 25`, compared snapshots
3. Found 5x scaling in timer-related objects:
   - `System.Threading.Timer` (12 per run)
   - `System.Threading.TimerHolder`
   - `System.Threading.TimerQueueTimer`
   - `System.Threading.Tasks.Task+DelayPromise`

**Root Cause:** `Task.Delay` in `ReadChunk()` created timers that weren't cancelled when reads completed. Each 15-second timer accumulated until timeout.

**Fix:** Cancel the delay timer immediately when the read completes using `CancellationTokenSource.CreateLinkedTokenSource()`.

**Verification:** 50 runs showed stable memory with no timer accumulation.

### Best Practices for dotMemory Profiling

1. **Use warmup runs**: Skip the first 2-3 runs to exclude startup allocation noise
2. **Compare at intervals**: Snapshots at runs 5, 10, 15, etc. show accumulation patterns
3. **Look for linear growth**: Objects that scale with run count are likely leaks
4. **Focus on "new" objects**: dotMemory comparison highlights objects present in second snapshot but not first
5. **Check .NET internals**: Leaks often hide in framework types (timers, tasks, delegates) rather than application types

### Discounting WeakReference Accumulation

WinForms maintains static `WeakRefCollection` instances to track all ToolStrips for input message routing. These collections accumulate `System.WeakReference` and `System.Windows.Forms.ClientUtils+WeakRefCollection+WeakRefObject` entries over time.

**Key insight**: These weak references allow the actual ToolStrip objects to be GC'd, but the `WeakReference` wrapper objects themselves only get pruned when the collection is actively enumerated/accessed - not during GC cycles.

When evaluating "Objects delta" in dotMemory snapshot comparisons, **subtract these types** - they don't represent actual memory leaks:

| Objects Delta | Interpretation |
|---------------|----------------|
| 250 total (150 WeakReference + 100 WeakRefObject) | Effectively **0** real leak |
| 250 total (actual domain objects) | Real leak to investigate |

Common allocation stack traces for these (can be ignored):
- `ToolStripMenuItem.CreateDefaultDropDown()` → accessing `DropDownItems` on menu items
- `ToolStripOverflowButton.CreateDefaultDropDown()` → ToolStrip layout creating overflow buttons
- Any `ToolStrip..ctor()` or `ToolStripDropDown..ctor()` path

## Future Vision: Automated Leak Detection Workflow

The current workflow requires a human to review nightly test results and select the optimal test for investigation. A planned enhancement would automate Phase 1 through an MCP (Model Context Protocol) server integration.

### Planned Architecture

```
┌─────────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  LabKey Server      │────▶│  MCP Server      │────▶│  Claude Code    │
│  (Nightly Results)  │     │  (JSON API)      │     │  (Analysis)     │
└─────────────────────┘     └──────────────────┘     └─────────────────┘
```

### Envisioned Capabilities

1. **Automatic leak detection**: MCP server queries nightly results, compares Integration vs Master
2. **Optimal test selection**: Calculates "handles leaked per second" for all leaking tests
3. **Investigation recommendations**: Returns ranked list of tests worth investigating
4. **New slash command**: `/pw-review-leaks` would:
   - Fetch last night's test results via MCP
   - Identify tests with significant handle leaks
   - Recommend which test to investigate first
   - Optionally begin autonomous investigation

### Benefits

- **Faster response**: Leaks detected and investigated within hours of nightly run
- **Consistent methodology**: Same bisection approach applied systematically
- **Reduced manual overhead**: Human only needed to review and approve fixes
- **Complete audit trail**: All investigation steps documented in TODO files

### Implementation Status

- [x] Tooling for leak isolation (this guide)
- [x] Handle reporting improvements (`-ReportHandles`, `-SortHandlesByCount`)
- [x] MCP server for LabKey integration (see `ai/mcp/LabKeyMcp/`)
- [x] dotMemory snapshot integration in TestRunnerLib (January 2026)
- [x] Command-line arguments for dotMemory properties (January 2026)
- [ ] `/pw-review-leaks` slash command
- [ ] Autonomous investigation mode

This represents a path toward having Claude Code proactively identify and fix handle leaks with minimal human intervention, transforming leak debugging from a reactive manual process to an automated continuous improvement system.

### Command-Line Arguments for dotMemory (January 2026)

TestRunner now supports command-line arguments to configure dotMemory snapshot behavior:

```
dotmemorywaitruns=N        # Iterations between snapshots (enables profiling)
dotmemorywarmup=N          # Warmup iterations before first snapshot (default: 5)
dotmemorycollectallocations=on  # Capture allocation stack traces (default: off)
```

**Usage:** Run TestRunner under dotMemory GUI profiler with these arguments:
```
TestRunner.exe test=TestOlderProteomeDb loop=20 dotmemorywaitruns=10 dotmemorywarmup=5 dotmemorycollectallocations=on
```

**What happens:**
- Test runs for 5 iterations (warmup, allows JIT/caching to stabilize)
- Snapshot #1 taken: `TestOlderProteomeDb_Warmup_After5`
- Test runs 10 more iterations
- Snapshot #2 taken: `TestOlderProteomeDb_Analysis_After15`
- Compare snapshots in dotMemory GUI to identify leaking objects

When `dotmemorywaitruns` is set and `dotmemorywarmup` is not specified, warmup defaults to 5 runs.

### Automated Memory Profiling with Run-Tests.ps1 (January 2026)

The `-MemoryProfile` flag on `Run-Tests.ps1` provides fully automated memory profiling via dotMemory CLI:

```powershell
# Basic profiling (10 warmup, 20 wait runs)
Run-Tests.ps1 -TestName TestOlderProteomeDb -MemoryProfile -MemoryProfileWarmup 10 -MemoryProfileWaitRuns 20

# With allocation stack traces (slower but shows where objects originate)
Run-Tests.ps1 -TestName TestOlderProteomeDb -MemoryProfile -MemoryProfileWarmup 10 -MemoryProfileWaitRuns 20 -MemoryProfileCollectAllocations

# Extended run for thread pool warm-up investigation
Run-Tests.ps1 -TestName TestOlderProteomeDb -MemoryProfile -MemoryProfileWarmup 20 -MemoryProfileWaitRuns 50
```

**What happens:**
1. Script launches TestRunner under dotMemory CLI profiler
2. Test runs for warmup iterations (allows JIT/caching/thread pool to stabilize)
3. Snapshot #1 taken automatically after warmup
4. Test runs for wait iterations (analysis period)
5. Snapshot #2 taken automatically
6. Workspace saved to `ai/.tmp/memory-YYYYMMDD-HHMMSS.dmw`

**Interpreting results:**

| Observation | Indicates |
|-------------|-----------|
| Managed heap stable, few new objects | No managed leak (investigate unmanaged) |
| Objects growing linearly with runs | Managed memory leak - investigate in GUI |
| Thread pool objects (WorkStealingQueue) | Runtime warm-up artifact, not a true leak |
| Large object delta with short warmup | Increase warmup runs (e.g., 20 instead of 10) |

**Limitation:** dotMemory CLI cannot export comparison reports to JSON/XML (only produces binary `.dmw` workspace files). Visual analysis in dotMemory GUI is required to drill down into specific object types and allocation stack traces.

**Benefits over manual GUI workflow:**
- No human needed to launch dotMemory GUI and manually take snapshots
- Precise snapshot timing (immediately after GC, at stable memory points)
- Reproducible methodology for comparing leak investigations
- Similar developer experience to `-Coverage` flag

## GC Leak Tracker: Object Lifecycle Verification (February 2026)

The **GarbageCollectionTracker** (PR #4034) verifies that key objects (`SkylineWindow`,
`SrmDocument`) are garbage collected after each functional test. This catches a different
class of leaks than handle counting: managed object retention via static references,
undisposed timers, cached collections, and delegate chains.

### How It Works

1. **Registration**: Skyline registers objects via `Program.GcTracker.Register<T>(target)`,
   which stores a `WeakReference` in the static tracker
2. **After test**: `RunTests.Run` calls `FlushMemory()` (full GC), then `CheckForLeaks()`
3. **Verification**: If any WeakReference is still alive, the tracked object was retained
   by a strong reference chain — a GC leak
4. **Reporting**: Test fails with `"Objects not garbage collected after test: SkylineWindow, SrmDocument"`

### PinSurvivors Mode for dotMemory Analysis

When a GC leak is detected, you need to find the **retention path** — the chain of
references preventing garbage collection. dotMemory can show this, but only if the
objects exist as strong references (WeakReferences are invisible to retention analysis).

**PinSurvivors mode** bridges this gap:
- Instead of failing the test, promotes surviving WeakReferences to strong references
  in a static `_pinnedSurvivors` list
- Takes a dotMemory snapshot while these objects are pinned
- The snapshot shows the original retention paths that prevented GC

### Workflow: Investigating a GC Leak

#### Step 1: Confirm the leak exists

```powershell
# Run the failing test normally
Run-Tests.ps1 -TestName TestEncyclopeDiaSearch
# Expected: "Objects not garbage collected after test: SkylineWindow, SrmDocument"
```

#### Step 2: Profile with PinSurvivors mode

```powershell
# -MemoryProfileWaitRuns 0 enables PinSurvivors mode (single snapshot, no failure)
Run-Tests.ps1 -TestName TestEncyclopeDiaSearch -MemoryProfile -MemoryProfileWaitRuns 0
```

This produces a `.dmw` workspace file in `ai/.tmp/`.

#### Step 3: Analyze retention paths in dotMemory GUI

1. Open the `.dmw` file in dotMemory GUI
2. Open the snapshot → find `SkylineWindow` (or `SrmDocument`) in type list
3. Click through to **Key Retention Paths** tab
4. The retention paths show exactly what's holding the object alive

**What to look for in the retention paths:**
- The `GarbageCollectionTracker._pinnedSurvivors` path is the pinning reference itself — ignore it
- Other paths are the actual leaks to fix
- Common patterns: static fields, undisposed Timers, delegate chains, cached collections

#### Step 4: Fix and verify

Fix the retention chain, then verify both ways:

```powershell
# Verify no more pinned objects in dotMemory
Run-Tests.ps1 -TestName TestEncyclopeDiaSearch -MemoryProfile -MemoryProfileWaitRuns 0

# Verify GC tracker passes (no failure message)
Run-Tests.ps1 -TestName TestEncyclopeDiaSearch
```

#### Step 5: Negative test (recommended)

Comment out the fix and confirm the test fails again. This is important because the
GC tracker was accidentally disabled for months (see case study below) — an absence
of failure alone is not sufficient proof.

### Case Study: GraphSpectrum Timer Leak (February 2026)

**Detection**: After fixing the GC tracker's `DotMemoryWarmupRuns` default bug,
`TestKoinaSkylineIntegration` and `TestEncyclopeDiaSearch` failed with
`"Objects not garbage collected after test: SkylineWindow, SrmDocument"`.

**PinSurvivors profiling** revealed 4 retention paths to SkylineWindow:
1. `GarbageCollectionTracker._pinnedSurvivors` → SkylineWindow (the pin — ignore)
2. `FilesTreeForm` → `ControlAccessibleObject` → weak handle (benign)
3. `SequenceTree` → `ControlAccessibleObject` → weak handle (benign)
4. `GraphSpectrum._stateProvider` → `UpdateManager._target` → `EventHandler` →
   `Timer.onTimer` → **Regular handle** ← THE LEAK

The Timer in GraphSpectrum's UpdateManager kept a strong reference chain alive via
its event handler delegate, which captured the GraphSpectrum instance, which held
`_stateProvider` (SkylineWindow).

**Fix**: Added `OnHandleDestroyed` override to GraphSpectrum:
```csharp
protected override void OnHandleDestroyed(EventArgs e)
{
    _updateManager.Dispose();
    _documentContainer.UnlistenUI(OnDocumentUIChanged);
    base.OnHandleDestroyed(e);
}
```

**Why OnHandleDestroyed?** The existing `OnVisibleChanged` cleanup only fires when
visibility changes, but `Dispose()` (via Designer) only disposes `components`. The
`UpdateManager` with its Timer was never cleaned up. `OnHandleDestroyed` fires
reliably during form teardown.

**Verification**: Commented out the fix → test failed. Restored fix → test passed.
dotMemory snapshot confirmed no SkylineWindow in survivors.

### Case Study: GC Tracker Accidentally Disabled (February 2026)

**Symptom**: GC tracker (PR #4034) was added to detect leaks, but no tests ever
failed — even tests with known retention issues. The tracker appeared to work in
dotMemory profiling mode but never reported failures in normal runs.

**Root cause**: The default args string in `Program.cs` included `dotmemorywarmup=5`.
The condition `if (dotMemoryWarmup > 0)` was always true, causing
`GarbageCollectionTracker.PinSurvivors()` (silent) to be called instead of
`CheckForLeaks()` (reports failures) for every test.

**Fix** (PR #4038): Changed the condition to
`if (commandLineArgs.HasArg("dotmemorywarmup") || commandLineArgs.HasArg("dotmemorywaitruns"))`
which only fires when the arg is explicitly passed on the command line.

**Lesson**: Default argument values that enable profiling modes can silently disable
production code paths. Test new detection mechanisms by verifying they catch a known
failure — don't assume "no failures" means "working correctly".

### Common GC Leak Patterns

| Pattern | Example | Fix |
|---------|---------|-----|
| Undisposed Timer | `UpdateManager` in `GraphSpectrum` | Dispose in `OnHandleDestroyed` |
| Static delegate chain | `UpgradeManager.AppDeployment` → delegates → SkylineWindow | Make holder IDisposable, `using` pattern |
| Static tracking list | `ReplicateCachingReceiver._cachedSinceTracked` holding GraphData | Start/End pattern that nulls the list |
| Event handler subscription | Component subscribes to long-lived event source | Unsubscribe in Dispose/OnHandleDestroyed |

### The Start/End Tracking Pattern

When test infrastructure uses static state to track results (for assertions), use
paired Start/End methods that fit into `ScopedAction`:

```csharp
// In production code:
public static void StartTrackCaching()
{
    _cachedSinceTracked = new List<TResult>();
    _trackCaching = true;
}

public static void EndTrackCaching()
{
    _trackCaching = false;
    _cachedSinceTracked = null;  // Release references!
}

// In test code:
List<ResultType> results;
using (new ScopedAction(
           CachingReceiver.StartTrackCaching,
           CachingReceiver.EndTrackCaching))
{
    // ... trigger the operation ...
    results = CachingReceiver.CachedSinceTracked.ToList();  // Capture before End
}
// Assert on results outside the scope
```

**Key principles:**
- Start clears stale data AND enables tracking
- End disables tracking AND releases references (nulls collections)
- Capture results into local variables BEFORE End runs
- Method groups (`StartTrackCaching`, `EndTrackCaching`) fit cleanly into `ScopedAction`

### Limitations: dotMemory GUI Required

Currently, retention path analysis requires the dotMemory GUI:
1. Claude runs PinSurvivors profiling → produces `.dmw` file
2. Human opens `.dmw` in dotMemory GUI
3. Human navigates to Key Retention Paths
4. Human takes screenshot → Claude reads it

This human-in-the-loop step is the main bottleneck. A command-line tool that could
query retention paths from a `.dmw` file and output JSON would enable fully autonomous
GC leak investigation. See the JetBrains feature request in the project notes.
