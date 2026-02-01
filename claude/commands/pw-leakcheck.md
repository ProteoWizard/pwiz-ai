---
description: Run memory profiling on a test to investigate leaks
---

# Memory Leak Investigation

Profile a test with dotMemory to investigate memory or handle leaks reported in nightly tests.

**Argument**: Test name (required)

## Step 1: Read the Methodology Guide

**MANDATORY**: Before doing anything else, read the leak debugging guide:

```
Read ai/docs/leak-debugging-guide.md
```

This guide contains critical information including:
- Handle leak investigation with `-ReportHandles`
- Bisection techniques for isolating leaks
- Case studies (AuditLogForm icon leak, FileSystemWatcher race condition, HttpClientWithProgress timer leak)
- Interpreting dotMemory results

## Step 2: Ask User for Profiling Parameters

Use `AskUserQuestion` to ask the user:

1. **Warmup runs** (default 10): Iterations before first snapshot to allow JIT/caching/thread pool to stabilize
2. **Wait runs** (default 20): Iterations between snapshots (analysis period)
3. **Collect allocations**: Whether to capture allocation stack traces (slower but shows where objects originate)

Suggested options:
- Warmup: 10 (standard), 20 (extended for thread pool investigation)
- Wait: 20 (standard), 50 (extended)
- Allocations: No (faster), Yes (shows allocation sites)

## Step 3: Run Memory Profiling

After user confirms parameters, run:

```powershell
# Without allocation tracking
Run-Tests.ps1 -TestName <test> -MemoryProfile -MemoryProfileWarmup <warmup> -MemoryProfileWaitRuns <wait>

# With allocation tracking
Run-Tests.ps1 -TestName <test> -MemoryProfile -MemoryProfileWarmup <warmup> -MemoryProfileWaitRuns <wait> -MemoryProfileCollectAllocations
```

Output: `ai/.tmp/memory-YYYYMMDD-HHMMSS.dmw` (open in dotMemory GUI to compare snapshots)

## Interpreting Results

| Snapshot Comparison | Indicates |
|---------------------|-----------|
| Managed heap stable, few new objects | No managed leak (check unmanaged) |
| Objects growing linearly with runs | Managed memory leak |
| Thread pool objects (WorkStealingQueue) | Runtime warm-up, not a leak |
