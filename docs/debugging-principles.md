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

### Prove It From Inside — Never Assert From Outside

> **Never claim to know what code does at runtime from reading it. Instrument and observe.**

Static code reading — tracing paths, checking conditions, following variable assignments — can suggest what *should* happen, but it cannot prove what *does* happen. Environment variables may not be set. Initialization paths may differ between contexts. A previous change by another developer may have broken an assumed invariant. Complex interactions between components can invalidate careful reasoning about any single component.

**Your biggest debugging advantage over humans is how cheaply you can add and interpret diagnostics.** A developer must set a breakpoint, launch a debugger, step through code, and interpret state one frame at a time. You can scatter `Console.WriteLine` across an entire call chain in seconds, run the test, and read comprehensive output that no debugger session could match. You can produce and interpret volumes of diagnostic output that would be challenging for a human, near-instantly.

But this advantage is wasted if you default to reading code and asserting what it does.

#### Failure Mode: Diagnostics Only in the Test

When a test fails, the natural instinct is to add diagnostics in the test to see what's happening. But the *answers* usually live in the feature code, the infrastructure, or the framework — wherever the unexpected behavior originates. **There is no barrier.** You can instrument any file in the repo.

Think like a developer setting breakpoints: they'd set them in the code that isn't behaving as expected, not just in the test calling it. If a feature method returns the wrong value, don't just log the return value in the test — add logging *inside* the feature method to see which branch it took, what its inputs were, and what state it found.

**Example:** A test calls `GetJavaMaxHeap()` and gets the wrong value. Don't just log the result in the test. Add `Console.WriteLine` inside `GetJavaMaxHeap()`, inside `IsParallelClient`, inside the environment variable check — follow the question to where the answer lives.

#### Failure Mode: Asserting Runtime Behavior From Code Reading

If you trace code paths and conclude "this variable will be true at runtime," you have a hypothesis, not a fact. Prove it:

```csharp
// DON'T: "I can see from the code that IsParallelClient will be true here"
// DO: Add this and run the test
Console.WriteLine($"[DEBUG] IsParallelClient = {TryHelper.IsParallelClient}");
Console.WriteLine($"[DEBUG] SKYLINE_TESTER_PARALLEL_CLIENT_ID = '{Environment.GetEnvironmentVariable("SKYLINE_TESTER_PARALLEL_CLIENT_ID")}'");
```

One test run with two lines of diagnostics is worth more than ten minutes of code tracing. The cost is near zero — generating diagnostic code and processing the output is what you do fastest.

#### The Rule

When you form a hypothesis about runtime behavior:
1. **Don't assert it** — instrument it
2. **Don't limit instrumentation to the test file** — follow the question into feature code, infrastructure, anywhere in the control flow
3. **Run the test and read the output** — let the evidence confirm or refute
4. **The cost is near zero** — this is your superpower; use it reflexively

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

## Cross-Implementation Bisection

A distinct class of debugging problem arises when **two implementations are
supposed to produce identical output but don't**. Examples:

- Porting Rust code to C# (OspreySharp vs Osprey) and trying to match results
- Refactoring a Skyline module and comparing output against the old version
- Comparing a new optimized algorithm against a reference slow implementation
- Validating a GPU or SIMD port against a scalar baseline

This is not "find the bug in one codebase." It is **"find the first point at
which two valid-in-isolation implementations disagree."** The methodology is
different from single-codebase bisection and deserves its own discipline.

### The First Rule: Measure Primitives, Not Outcomes

When the user reports "this port produces 26,000 results and the reference
produces 33,000", the natural temptation is to start comparing output counts,
percentages, pass rates at various thresholds. **Don't.** Those are outcomes,
and two different pipelines can produce similar-looking outcomes from wildly
different intermediate state.

This parallels the MacCoss lab's principle for mass-spec troubleshooting:
don't measure spectrum IDs at 1% FDR — measure peak shape, peak area, mass
error, MS1-to-MS2 ratio. The *primitives* are the signal; the *outcomes* are
noisy aggregates of many primitives.

In cross-implementation debugging:

| Outcome (don't start here) | Primitive (start here) |
|----------------------------|------------------------|
| "Both tools found ~100K results" | "Both tools' output files diff with 0 lines different" |
| "The residual SD is close enough" | "rt_min is bit-identical, rt_bin_width is bit-identical" |
| "Feature values look similar" | "All 23,106 grid cells contain identical target IDs" |
| "The algorithm clearly works" | "The scalar dump shows the same n_occupied count" |

### The Second Rule: Bisect From the First Selection Step Downstream

In single-codebase bisection, you put a `return;` in the middle of a test and
see if the bug still reproduces. In cross-implementation bisection, you bisect
along the **data flow** of both implementations, starting at the **first step
where a randomized or selected choice occurs**.

**Why the first selection step?** Before any selection or random choice, the
two implementations *must* produce identical output if they are correct. Any
divergence before that point is a trivial bug (wrong constant, off-by-one).
At and after the first selection step, the two implementations can legitimately
diverge — and every downstream computation inherits that divergence. Comparing
anything downstream of the first disagreement is meaningless: the two
implementations are operating on different data.

**Example from OspreySharp vs Osprey:**

The pipeline has these stages:

1. Library load + dedup — should be bit-identical (no randomness)
2. Decoy generation — should be bit-identical (deterministic reversal)
3. **Calibration peptide sampling** — *first selection step* (picks 100K from 242K)
4. Calibration scoring — depends on stage 3
5. RT calibration LOESS fit — depends on stage 4
6. Per-entry coelution scoring — depends on stage 5
7. Peak picking — depends on stage 6
8. Feature computation at peak — depends on stage 7
9. FDR / Percolator — depends on stage 8
10. Output counts — depends on stage 9

Early in the investigation, ~2 hours were wasted comparing PIN feature values
(stage 8 output) between the two tools, trying to find feature-specific bugs.
The features were divergent — but they were computed for *different peaks* in
the two tools (stage 7 had picked different peaks because stage 5 had fit
different LOESS curves because stage 4 had different inputs because stage 3
had sampled different peptides).

**The fix was at stage 2.** C# was keeping 4 targets whose reversed decoys
collided with other target sequences; Rust excluded them. That changed stage
3's input (242,841 → 242,837 targets), which changed grid bin assignments,
which changed the 100K sample (20 different entries), which cascaded all the
way to the output counts. Comparing stage 8 output told us nothing until
stage 2 was fixed.

**The rule:** When facing a cross-implementation divergence, always begin
at the earliest stage where a choice is made, prove that stage matches, and
only then move downstream. Do not try to match downstream values before
upstream matches are proven.

### The Third Rule: Proof Requires `diff`, Not Counts

"Both tools sampled 100,000 targets" is a statistic. "The two sample files
have zero differing lines after sorting and normalizing line endings" is
proof. Use `diff`, not `wc -l`.

**What counts as proof:**
```
grid diff count (should be 0 for 100% match): 0
sample diff count: 0
```

**What does not count as proof:**
- "Count matches" — two implementations can produce matching counts over
  completely disjoint sets of entries.
- "Values are close" — 13-decimal-place numerical agreement on one feature
  does not prove anything about the other 20 features, or about the peak
  that feature was computed on.
- "Results statistically similar" — see outcome-vs-primitive above.

### Diagnostic Infrastructure: Env-Var-Gated Early-Exit Dumps

Both implementations need coordinated diagnostic output at the same stage,
exiting after the dump so you're not running the full pipeline for every
iteration. The pattern:

**Add to both implementations:**
```csharp
if (Environment.GetEnvironmentVariable("MY_TOOL_DUMP_STAGE_N") == "1")
{
    // Dump scalars to a file with a known name
    using (var w = new StreamWriter("stage_n_scalars.txt"))
    {
        w.WriteLine("param1\t" + param1.ToString("R"));  // "R" preserves bits
        w.WriteLine("param2\t" + param2.ToString("R"));
    }

    // Dump intermediate state (cell contents, lookup tables, etc.)
    using (var w = new StreamWriter("stage_n_state.txt"))
    {
        // Sorted for stable comparison
        foreach (var item in stateItems.OrderBy(...))
            w.WriteLine(...);
    }

    // Dump final output of this stage
    using (var w = new StreamWriter("stage_n_output.txt"))
    {
        foreach (var entry in output.OrderBy(e => e.Id))
            w.WriteLine(entry.Id + "\t" + entry.Field1 + "\t" + entry.Field2);
    }

    if (Environment.GetEnvironmentVariable("MY_TOOL_STAGE_N_ONLY") == "1")
        Environment.Exit(0);
}
```

```rust
if std::env::var("MY_TOOL_DUMP_STAGE_N").is_ok() {
    use std::io::Write;
    if let Ok(mut f) = std::fs::File::create("rust_stage_n_scalars.txt") {
        writeln!(f, "param1\t{:.17}", param1).ok();  // 17 digits = full bits
        writeln!(f, "param2\t{:.17}", param2).ok();
    }
    // ... intermediate and output dumps ...

    if std::env::var("MY_TOOL_STAGE_N_ONLY").is_ok() {
        std::process::exit(0);
    }
}
```

**Why early exit matters:** Without it, a full pipeline run is 3-10 minutes.
With it, a targeted iteration cycle is 20-60 seconds. At the early stages,
the only work done is loading library + generating decoys + sampling — which
should take under a minute even on big data.

### Bit-Preserving Number Formats

Cross-implementation comparison fails if the numbers are bit-identical but
format differently. Text-diff will report false differences on the formatting,
hiding the fact that the underlying values are equal.

| Language | Format that preserves all bits |
|----------|-------------------------------|
| C#       | `"R"` (round-trip format)      |
| C++      | `std::setprecision(17)` with `std::fixed` |
| Rust     | `{:.17}`                       |
| Python   | `repr(x)` or `f"{x:.17g}"`     |

**Always dump scalars with one of these formats** when comparing across
implementations. Then, when `diff` reports a difference in a scalar, you
know it's a real numerical difference, not formatting noise.

**Verifying a format diff is only cosmetic:** If `1.6` and
`1.60000000000000009` both parse to the same `double`, the values agree.
Confirm either by (a) parsing both back to doubles and comparing bits, or
(b) checking that all downstream values computed from them match. If the
bin widths, cell assignments, and final output all match, the formatting
difference is definitionally cosmetic.

### Cross-Implementation Bisection Protocol

1. **Identify the pipeline stages.** List the stages in order, with each
   stage's input and output. Mark which stages involve randomization or
   selection (sampling, shuffling, seeding, choice from multiple candidates).
2. **Find the first selection stage.** This is your initial bisection anchor.
3. **Add diagnostic dumps to both tools at the end of that stage.** Scalars,
   intermediate state, final output. Gate behind an env var. Add a second
   env var for early exit after dump.
4. **Build both tools, run both with early-exit env vars set.** Aim for
   under-60-second iteration cycles.
5. **`diff` the outputs.** Normalize line endings first (`tr -d '\r'`).
   Start with scalars — they usually catch the issue quickly. Then
   intermediate state. Then final output.
6. **If diffs are non-zero:** investigate the specific differences. Scalars
   usually point directly at a missing filter, off-by-one, or different
   constant. Intermediate state differences often indicate different input
   to the current stage — which means the divergence is actually at an
   earlier stage you missed.
7. **When `diff` is zero everywhere:** commit your fix, update the TODO with
   the proof, and move the anchor to the next stage downstream.
8. **Repeat for each downstream stage in turn.** Never skip ahead — every
   stage depends on its predecessors matching.

**Don't proliferate commented-out code while bisecting.** The goal is to
match at one stage, commit, and move forward. The commits, the TODO log,
and the diagnostic dumps are the record of what was tried — not a trail of
`// BISECT:` comments in the source.

### Anti-Patterns Specific to Cross-Implementation Debugging

**Comparing downstream values before upstream is proven.** If the two
implementations have diverged at stage 3, comparing stage 8 output is
meaningless because the inputs to stage 8 are different. This is the most
common wasted effort.

**Trusting that "the algorithm is a direct port."** Even a direct port can
have subtle differences: off-by-one in loop bounds, different floating-point
order of operations, different handling of edge cases (zeros, NaNs,
collisions), different defaults for missing fields. The code *looks* right
until the diagnostics prove it isn't.

**Iterating on the high-level output instead of the primitives.** "The final
count is closer now" is not progress — a closer count can come from
compensating errors. Progress is "one more stage's diagnostic dump now has
zero differences."

**Not exiting early.** Running the full pipeline when you only need the
first stage's output wastes the cycle-time reduction that early-exit gives
you. A 20-second targeted cycle is 10x more valuable than a 3-minute full run
when you're iterating on a single diagnostic.

**Relying on "numbers look close" tables in the TODO.** A table like "C# 26K,
Rust 33K (1.3x off)" tells you nothing about root cause. It should be
replaced with "Stage 3 sample: 0 diff lines; Stage 4 scoring: 192,469 vs
192,289 (180 diff lines, investigating)". Prove match at each stage; record
the proof.

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
