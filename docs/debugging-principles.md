# Debugging Principles

This guide documents the systematic methodology for debugging software issues, developed from 35+ years of experience across Microsoft Visual C++, BEA WebLogic Workshop, and the Skyline project. It transforms debugging from an ad-hoc activity into a structured, methodical process.

## The Debugging Mindset

**Debugging is fundamentally different from development.**

| Development Mode | Debugging Mode |
|-----------------|----------------|
| Build this feature | Something is wrong |
| Understand requirements → Design → Implement | Reproduce → Measure → Bisect → Isolate |
| Forward progress | Hypothesis testing |
| Create new code | Observe existing behavior |

When facing a bug, Claude Code should recognize this as a different mode of operation and shift approach accordingly.

## The First Questions (In Order)

Every debugging session begins with these questions:

| # | Question | Why It Matters |
|---|----------|----------------|
| 1 | **Can the problem be reproduced?** | Without reproduction, strategy changes fundamentally |
| 2 | **What is the current cycle time?** | Determines which techniques are viable |
| 3 | **Can the cycle time be reduced?** | Always worth investing effort here first |
| 4 | **What is the confidence level?** | 100% = bisection works; <100% = need statistical approach |

**The heuristic:** *A bug that can be reproduced consistently in less than a few minutes will not last a day.*

## Cycle Time: The Critical Variable

Cycle time is the time required to determine whether a bug is present or absent after making a change. This single variable determines your entire debugging strategy.

### Reducing Cycle Time

Before diving into investigation, **aggressively pursue cycle time reduction**:

| Technique | Example |
|-----------|---------|
| **Isolate to a single test** | Full test suite → Single test that exhibits the bug |
| **Reduce iterations** | 100 runs → 10 runs (if still shows the pattern) |
| **Strip unnecessary setup** | Skip test sections that don't trigger the issue |
| **Move reproduction local** | Nightly server → Local machine with fast SSD |
| **Amplify the problem** | Add loop around suspected operation to inflate signal |

**Amplification example:** If you suspect a leak in "open/close document", wrap it in a 10-iteration loop. If the leak inflates 10x, you've confirmed your hypothesis AND created a faster feedback cycle.

### Cycle Time → Strategy Matrix

| Cycle Time | Confidence | Strategy |
|------------|------------|----------|
| **< 1 min** | High | Printf debugging, rapid bisection, self-sufficient investigation |
| **1-10 min** | High | Thoughtful printf debugging, fewer iterations, maximize info per run |
| **10-60 min** | High | Careful hypothesis, batch multiple diagnostics per run |
| **Hours/Days** | Variable | Strategic instrumentation, wait for next occurrence |
| **Days/Weeks (intermittent)** | Low | Statistical bisection, DocChangeLogger pattern |

## Fast-Cycle Mode (< 1 minute)

When cycle time is under one minute, you have enormous power. Use it.

### The Core Principle: Self-Sufficiency

> **Never ask the user about runtime behavior you can observe yourself.**

If you're tempted to ask:
- "Is it the same path?" → Add `Console.WriteLine($"Path: {directoryPath}")`
- "Is it the same object?" → Add `Console.WriteLine($"Instance: {RuntimeHelpers.GetHashCode(this)}")`
- "What thread is this on?" → Add `Console.WriteLine($"Thread: {Thread.CurrentThread.ManagedThreadId}")`

Then run the test and see the answer yourself. You can answer your own questions faster and more comprehensively than any human operating a debugger.

### Printf Debugging

With a fast cycle, **printf debugging is your primary tool**. Every question about runtime behavior becomes a `Console.WriteLine()`.

```csharp
// Instead of reasoning about the code, instrument it
Console.WriteLine($"[DEBUG] Entering WatchDirectory: {directoryPath}");
Console.WriteLine($"[DEBUG] IsMonitoring: {IsMonitoringDirectory(directoryPath)}");
Console.WriteLine($"[DEBUG] Thread: {Thread.CurrentThread.ManagedThreadId}");
Console.WriteLine($"[DEBUG] Instance: {RuntimeHelpers.GetHashCode(this)}");
```

Run the test, read the output, understand the behavior. Repeat.

### CRITICAL: Capturing and Analyzing Debug Output

Once you add printf instrumentation, **the logged output becomes your primary source of truth**. Everything you do must be driven by what the output tells you.

**Use the log file, not just console grep.** `Run-Tests.ps1` writes all test output to a log file at `bin\x64\Debug\TestName.log`. This is printed at the end of every run. Use the Read tool to examine the full log:

```bash
# Run the test
pwsh -Command "& './ai/scripts/Skyline/Run-Tests.ps1' -TestName TestSomething"

# Then READ the log file - don't just grep for fragments
Read("C:\proj\pwiz\pwiz_tools\Skyline\bin\x64\Debug\TestSomething.log")
```

**Why Read instead of grep:** When you grep stdout for `[DEBUG]`, you only see your tagged lines in isolation. The log file shows them **interleaved with test framework output**, giving you the full sequence of events. You need this context to understand what happened when.

**The discipline after each run:**
1. Read the complete debug output from the log file
2. Before making any code change, write down what the output tells you
3. If the output doesn't answer your question, add more instrumentation — don't guess
4. If the output contradicts your theory, **believe the output, not your theory**

**Common failure mode:** You add good instrumentation, run the test, see the output, but then ignore it and make a guess-based code change anyway. This defeats the purpose. The output is telling you what happened — read it carefully and let it guide your next step.

### Use Stack Traces to Understand Call Flow

A debugger's greatest advantage over printf debugging is showing *how code was called*, not just *that it was called*. Stack traces close this gap — but they're verbose, so use them strategically.

**Two-phase approach:**

1. **Start with lightweight instrumentation** to understand *how often* and *in what contexts* code runs:
   ```csharp
   Console.WriteLine($"[DEBUG] CloseInapplicableForms: formCount={forms.Count}, listCount={listCount}");
   ```

2. **Add stack traces selectively** once you know which calls are interesting. If a method is called 50 times but only one call matters, gate the stack trace:
   ```csharp
   if (docIdChanged && listCount == 0)  // Only the case we care about
       Console.WriteLine($"[DEBUG] Stack:\n{Environment.StackTrace}");
   ```

Stack traces tell you:
- **Who called this method** — was it triggered by NewDocument, OpenFile, or something else?
- **What thread you're on** — UI thread, background thread, or a BeginInvoke callback?
- **Whether the call is synchronous or deferred** — is this inside the operation or queued for later?

Without a stack trace, you'll waste cycles guessing whether a method is being called directly, via BeginInvoke, from a timer, or from an event handler. With a stack trace, one run answers all of these.

**For scoped stack trace logging**, use `StackTraceLogger` (`TestUtil/StackTraceLogger.cs`). It logs stack traces only when the call does NOT come from an expected path — perfect for finding unexpected callers:

```csharp
// Log document changes NOT originating from ImportFasta
using (new DocChangeLogger("SkylineWindow.ImportFasta"))
{
    SuspectedOperation();  // Only unexpected doc changes get logged with stack traces
}
```

### Diagnostic Output Toolkit

Common C# patterns for printf debugging:

| Need | Pattern |
|------|---------|
| Object identity | `RuntimeHelpers.GetHashCode(obj)` |
| Thread identity | `Thread.CurrentThread.ManagedThreadId` |
| Call stack | `Environment.StackTrace` or `new StackTrace(true)` |
| Timestamps | `DateTime.Now.ToString("HH:mm:ss.fff")` |
| Method entry/exit | `Console.WriteLine($"[DEBUG] Entering {nameof(MethodName)}")` |
| Value inspection | `Console.WriteLine($"[DEBUG] {nameof(variable)} = {variable}")` |
| Accurate line numbers | `[MethodImpl(MethodImplOptions.NoOptimization)]` on method |

**NoOptimization for exception diagnostics:** JIT optimization can inline methods and reorder code, causing exception stack traces to report inaccurate line numbers. When an exception report points to a line that doesn't make sense (e.g., a null dereference where no null is possible), adding `[MethodImpl(MethodImplOptions.NoOptimization)]` to the method ensures the next occurrence reports the true source line. This is a low-cost, permanent instrumentation — it disables optimization for a single method while preserving it everywhere else. Requires `using System.Runtime.CompilerServices`.

### Anti-Pattern: Reverting to Guess-and-Test

The most dangerous failure mode in debugging is: you add good instrumentation, run the test, see the output — and then **ignore the output and start making speculative code changes**.

Signs you've fallen into guess-and-test:
- You're changing production code hoping to fix the test without understanding why the current code fails
- You haven't read the full debug output from the last run
- Your "fix" is based on a theory about timing, threading, or async behavior that you haven't proven with instrumentation
- You're making multiple changes per cycle instead of one change to answer one question

**When you catch yourself guessing, stop and ask:** "What does my debug output actually say?" If the output doesn't answer your question, add more instrumentation. If it does answer it, read it more carefully — the answer is often already there.

**Concrete example:** If debug output shows `listCount=1` when you expected `listCount=0` after `NewDocument()`, don't hypothesize about `BeginInvoke` timing. The output is telling you the list genuinely exists. Investigate *why* the list exists, not why some cleanup mechanism "didn't fire fast enough."

### Bisection

Bisection is systematic hypothesis testing through binary search.

1. **Find midpoint**: Add `return;` at approximately the middle of the suspected code
2. **Run and compare**: If bug persists, it's before the return; if not, it's after
3. **Repeat**: Continue narrowing until you isolate the specific operation

```csharp
protected override void DoTest()
{
    OpenDocument("test.sky");

    // ... first half of test ...

    return; // BISECT: Testing first half for bug

    // ... second half of test ...
}
```

**Tip:** Choose meaningful boundaries (document operations, dialog shows, API calls) rather than arbitrary line counts.

### Two-Level Bisection

Sometimes test bisection identifies a *trigger* but not the *root cause*. Shift to code bisection:

1. **Test bisection**: Find which test operation triggers the bug
2. **Code bisection**: Comment out features/functionality in the triggered code path

Example from handle leak investigation:
1. Test bisection isolated: "Open document with layout restore" triggers leak
2. Code bisection:
   - Comment out `HandleDocumentEvent()` → leak stops
   - Enable `HandleDocumentEvent()`, comment out `StartWatching()` → leak stops
   - Enable `StartWatching()`, comment out `managedFsw.Start()` → leak stops
   - Isolated to `FileSystemWatcher.EnableRaisingEvents = true`

## Long-Cycle Mode (Hours to Days)

When you cannot reproduce locally or cycle time is very long, the strategy changes.

### Statistical Bisection

You can still bisect intermittent bugs - your cycle time is just "time to achieve statistical confidence."

**If a bug occurs weekly across 20 machines (~1/140 per run):**
- 2 weeks without occurrence → ~13% chance it's still there
- 4 weeks without occurrence → ~2% chance it's still there

So **4 weeks becomes your "3 runs" equivalent** for presence/absence determination.

| Reproduction Rate | Statistical Confidence Window | Effective Bisection Cycle |
|-------------------|------------------------------|---------------------------|
| Every run | 3 runs | Seconds-minutes |
| 1 in 10 runs | ~30 runs | Hours |
| Weekly (1/140) | 2-4 weeks | Weeks |
| Monthly | 2-3 months | Months |

**The math:** If bug occurs with probability p per test, after n tests without occurrence, probability it's still present ≈ (1-p)^n. Choose n so this is negligibly small.

### Strategic Instrumentation: Moving Up the Causal Chain

When you can't iterate quickly, you must **move up the causal chain** with instrumentation.

The failure you observe (crash, assertion, wrong state) is a symptom. Instrument at higher-leverage points upstream:

- **Document changes** - Fundamental operation affecting everything downstream
- **State transitions** - Mode changes, connection state, authentication
- **Resource acquisition** - File handles, network connections, locks

### The DocChangeLogger Pattern

`Skyline\TestUtil\StackTraceLogger.cs` exemplifies this approach:

```csharp
// RAII scoping - only instrument during suspected operation
using (new DocChangeLogger("SkylineWindow.ImportFasta"))
{
    // Only document changes NOT from ImportFasta get logged
    // Any UNEXPECTED changes appear in the output
    SuspectedOperation();
}
```

**Key design principles:**

1. **Instrument at high-leverage point**: Document changes affect everything downstream
2. **RAII scoping**: Limits instrumentation to suspected code regions
3. **Filter expected behavior**: Only log the unexpected (proof by exclusion)
4. **Minimal overhead**: Tests must still run normally across 10-20 machines
5. **Stack trace capture**: Know exactly how you got to each state change

**When the bug finally occurs with instrumentation enabled**, the unexpected entries in the log reveal the causal chain.

### Worth-the-Investment Analysis

Not every bug is worth solving. Consider:

| Frequency | User-Facing Impact | Test-Only Impact |
|-----------|-------------------|------------------|
| Weekly+ | Definitely solve | Probably solve |
| Monthly | Probably solve | Maybe (if blocking) |
| Yearly | Maybe (if severe) | Probably ignore |

## Recognizing Debugging Mode

Claude Code should recognize it's in debugging mode when:

1. User describes unexpected behavior ("X should do Y but does Z")
2. User mentions failures, crashes, leaks, or errors
3. User references nightly test results or exception reports
4. User asks "why is this happening?" rather than "how do I build this?"
5. User provides stack traces, error messages, or diagnostic output

**The mode shift:** Stop thinking "how do I implement this?" and start thinking "how do I observe and isolate this?"

## Integration with Other Resources

- **Handle/Memory Leaks**: See [leak-debugging-guide.md](leak-debugging-guide.md) for specialized techniques
- **Exception Reports**: Use the `skyline-exceptions` skill and MCP server to query skyline.ms
- **Nightly Test Failures**: Use the `skyline-nightlytests` skill to identify patterns and affected computers
- **Run Tests**: Use `ai/Run-Tests.ps1` with `-Loop`, `-ReportHandles`, `-SortHandlesByCount` flags

## Summary: The Debugging Flowchart

```
Bug Reported
    │
    ▼
Can it be reproduced?
    │
    ├─► YES: What's the cycle time?
    │         │
    │         ├─► < 1 min: Printf debugging + bisection
    │         │            Be self-sufficient. Never ask what you can observe.
    │         │
    │         ├─► 1-60 min: Careful bisection, batch diagnostics
    │         │
    │         └─► Hours+: Can we reduce it?
    │                      │
    │                      ├─► YES: Reduce first, then appropriate strategy
    │                      │
    │                      └─► NO: Statistical bisection or strategic instrumentation
    │
    └─► NO (intermittent):
              │
              ├─► What's the reproduction rate?
              │
              ├─► Can we amplify it? (loops, stress)
              │
              └─► Strategic instrumentation (DocChangeLogger pattern)
                  Deploy, wait, analyze when it occurs
```

**The core principle:** No bug is unsolvable - it's a matter of applying the right strategy for the reproduction characteristics.
