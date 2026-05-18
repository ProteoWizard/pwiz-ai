---
name: debugging
description: ALWAYS load when investigating bugs, failures, or unexpected behavior - ensures root cause analysis before attempting fixes.
---

# Debugging Mode

> **Trust comes from verifiers, not from the LLM.** Every technique below is a way to build a verifier the model cannot talk around: a failing test, a printf line, a diff that is either zero or nonzero. The trustworthiness of any conclusion in this mode is bounded above by the strength of the verifier that produced it. See [ai/docs/validation-cycle-principles.md](../../../docs/validation-cycle-principles.md) for the full framing.

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
   - For leak-specific workflows, load the **leak-debugging** skill instead

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

## Critical Principle: Prove It From Inside — Never Assert From Outside

> **Never claim to know what code does at runtime from reading it. Instrument and observe.**

See **ai/docs/debugging-principles.md** → "Prove It From Inside" for the full methodology, failure modes, and examples. Key points:

- **Don't assert** runtime behavior from code reading — instrument and run
- **Don't limit diagnostics to the test file** — instrument feature code, infrastructure, anywhere in the control flow
- **The cost is near zero** — generating diagnostic code and processing the output is what you do fastest

## Critical Principle: Write the Failing Test First

> **Before declaring a fix, write a test that fails on the current code and passes after the fix.**

The test does three jobs at once:

1. **Proves you understood the bug.** A test that does not actually fail on master is a test for a phenomenon you only theorize about. If you cannot reproduce the failure as a test, you do not yet know enough to fix it.
2. **Proves the fix addresses the root cause.** A passing test after a code change is the only deterministic evidence that the change has the effect you claim. Anything else is "this looks right to me."
3. **Leaves behind a permanent verifier.** Every defect becomes a check that runs forever at near-zero cost. The bar rises deterministically; that failure mode cannot silently recur.

**For nightly test failures, exception reports, and reproducible bug reports**: the test usually already exists or can be constructed from the stack trace and the report's reproduction steps. Write it first, watch it fail, then make it pass. The fix is the diff between "test red" and "test green."

**For bugs that resist reproduction**: make reproduction the *first* deliverable. Until a test fails reliably, no fix can be trusted. See "Long-Cycle Mode" in `ai/docs/debugging-principles.md` for amplification, statistical bisection, and DocChangeLogger strategies.

This is the "permanent verifier" rule from [ai/docs/validation-cycle-principles.md](../../../docs/validation-cycle-principles.md) made operational. The bug is not allowed to be considered fixed without also being gated against forever after.

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

- **leak-debugging** - Handle leaks, memory leaks, GC leak tracker failures
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
