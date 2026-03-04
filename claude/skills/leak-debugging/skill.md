---
name: leak-debugging
description: Load when investigating handle leaks, memory leaks, or GC-LEAK failures. Covers handle counting, dotMemory profiling, and GC leak tracker workflows.
---

# Leak Debugging

Specialized workflows for investigating handle leaks, managed memory leaks, and
GC leak tracker failures in Skyline tests.

## Core Documentation

Read before investigating any leak:

**ai/docs/leak-debugging-guide.md** - Complete reference covering:
- Handle leak detection and bisection (User/GDI/kernel handles)
- dotMemory profiling for managed memory leaks
- GC leak tracker (`GC-LEAK Objects not garbage collected after test:`)
- Case studies with step-by-step investigation examples

## Quick Reference: Which Leak Type?

| Error Message | Type | Section |
|---------------|------|---------|
| `GC-LEAK Objects not garbage collected after test: SkylineWindow, SrmDocument` | GC leak | "GC Leak Tracker" section |
| Handle counts growing in nightly tests | Handle leak | "Investigation Methodology" section |
| Memory growing but handles stable | Managed memory leak | "Memory Profiling with dotMemory" section |

## GC Leak Workflow (Most Common)

When you see `GC-LEAK Objects not garbage collected after test:`:

1. **Reproduce locally**: `Run-Tests.ps1 -TestName <test>` — confirm it fails
2. **Profile**: `Run-Tests.ps1 -TestName <test> -MemoryProfile -MemoryProfileWaitRuns 0`
3. **Ask the user** to open the `.dmw` file in dotMemory GUI and share a screenshot
   of Key Retention Paths for the leaked type (e.g., SkylineWindow)
4. **Read the screenshot** to identify the retention chain
5. **Fix** the retention chain (dispose timers, null delegates, clear caches)
6. **Verify**: run without profiling to confirm test passes
7. **Negative test**: comment out fix, confirm test fails again

**IMPORTANT**: Step 3 requires a human. Do NOT attempt to guess retention paths —
dotMemory shows you exactly what's holding the object alive. Guessing wastes time
when the answer is one screenshot away.

## Handle Leak Workflow

When nightly tests show growing handle counts:

1. **Select test**: Choose test with highest handles-leaked-per-second ratio
2. **Reproduce**: `Run-Tests.ps1 -TestName <test> -Loop 10 -ReportHandles -SortHandlesByCount`
3. **Identify type**: Which handle category is growing? (User, GDI, kernel)
4. **Bisect**: Add `return;` to narrow down which test operation causes the leak
5. **Fix and validate**: Re-run loop test, confirm handles are stable

## Common GC Leak Patterns

| Pattern | Example | Fix |
|---------|---------|-----|
| Undisposed Timer | `UpdateManager` Timer in `GraphSpectrum` | Dispose in `OnHandleDestroyed` |
| Static delegate chain | `UpgradeManager.AppDeployment` → delegates → SkylineWindow | Make holder IDisposable, `using` pattern |
| Static tracking list | `ReplicateCachingReceiver._cachedSinceTracked` | Start/End pattern that nulls the list |
| Event handler subscription | Component subscribes to long-lived source | Unsubscribe in Dispose |

## Related Skills

- **debugging** - General debugging methodology (cycle time, bisection, printf)
- **skyline-nightlytests** - Query nightly test data for leak trends
- **skyline-development** - For implementing fixes after isolation
