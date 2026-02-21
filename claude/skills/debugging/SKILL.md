---
name: debugging
description: ALWAYS load when investigating bugs, failures, or unexpected behavior - ensures root cause analysis before attempting fixes.
---

# Debugging Mode

When investigating bugs, failures, or unexpected behavior, shift into debugging mode. This is fundamentally different from development mode.

## Core Documentation

Read these files before investigating:

1. **ai/docs/debugging-principles.md** - Complete methodology
   - Cycle time analysis
   - Printf debugging techniques
   - Bisection methodology
   - Long-cycle/intermittent strategies
   - Diagnostic output toolkit

2. **ai/docs/leak-debugging-guide.md** - Handle/memory leak specifics
   - Handle types and their causes
   - TestRunner flags (`-ReportHandles`, `-SortHandlesByCount`)
   - Case studies with detailed bisection examples

## The First Questions

Always start by answering these:

1. **Can it be reproduced?** → Determines entire strategy
2. **What is the cycle time?** → How long to confirm presence/absence?
3. **Can cycle time be reduced?** → Invest effort here first
4. **What is reproduction confidence?** → 100% vs intermittent

## Quick Reference: Strategy by Cycle Time

| Cycle Time | Strategy |
|------------|----------|
| < 1 min | Printf debugging, rapid bisection, **be self-sufficient** |
| 1-60 min | Batch diagnostics, careful hypothesis |
| Hours+ | Statistical bisection or strategic instrumentation |
| Intermittent only | DocChangeLogger pattern, deploy and wait |

## Critical Principle: Self-Sufficiency

> **Never ask the user about runtime behavior you can observe yourself.**

When cycle time is fast:
- Don't ask "is it the same object?" → Add `Console.WriteLine($"Instance: {RuntimeHelpers.GetHashCode(obj)}")`
- Don't ask "what thread?" → Add `Console.WriteLine($"Thread: {Thread.CurrentThread.ManagedThreadId}")`
- Don't ask the user to run the debugger → Instrument the code with printf statements and run the test yourself

You can answer your own questions faster and more comprehensively than any human operating a debugger.

## Diagnostic Toolkit

```csharp
// Object identity
Console.WriteLine($"Instance: {RuntimeHelpers.GetHashCode(obj)}");

// Thread identity
Console.WriteLine($"Thread: {Thread.CurrentThread.ManagedThreadId}");

// Call stack — add selectively to calls of interest (verbose)
Console.WriteLine($"[DEBUG] Stack:\n{Environment.StackTrace}");

// Method entry with context
Console.WriteLine($"[DEBUG] {nameof(MethodName)}: param={value}");
```

## Output-Driven Discipline

Once you add instrumentation, **the log output is your primary source of truth**:

1. **Use the log file**: `Run-Tests.ps1` writes to `bin\x64\Debug\TestName.log`. Use `Read` to examine it — don't just grep stdout
2. **Read before changing**: After each run, read the full debug output before making any code change
3. **Believe the output**: If output contradicts your theory, your theory is wrong
4. **No guessing**: If the output doesn't answer your question, add more instrumentation — don't speculate
5. **Stack traces selectively**: Start with lightweight logging to see how often code runs, then add `Environment.StackTrace` to the specific cases of interest. Use `StackTraceLogger` (`TestUtil/StackTraceLogger.cs`) for scoped logging that filters out expected callers

## Bisection Pattern

```csharp
protected override void DoTest()
{
    // ... first half ...

    return; // BISECT: Testing if bug is in first half

    // ... second half ...
}
```

If bug present → it's before the return
If bug absent → it's after the return
Repeat to isolate.

## Related Skills

- **skyline-nightlytests** - Query nightly test data, find affected computers
- **skyline-exceptions** - Query exception reports from skyline.ms
- **skyline-development** - For implementing fixes after isolation

## When to Activate This Skill

Recognize debugging mode when user:
- Describes unexpected behavior
- Mentions failures, crashes, leaks, errors
- References test results or exception reports
- Asks "why?" rather than "how do I build?"
- Provides stack traces or error messages

**The mode shift:** Stop thinking "how do I implement?" → Start thinking "how do I observe and isolate?"
