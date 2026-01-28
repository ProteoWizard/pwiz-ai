---
description: Run memory profiling on a test to investigate leaks
---

# Memory Leak Investigation

Profile a test with dotMemory to investigate memory or handle leaks reported in nightly tests.

**Argument**: Test name (required)

## Quick Start

```powershell
# Basic profiling (10 warmup, 20 wait, no stack traces)
Run-Tests.ps1 -TestName <test> -MemoryProfile -MemoryProfileWarmup 10 -MemoryProfileWaitRuns 20

# With allocation stack traces (slower but shows where objects are created)
Run-Tests.ps1 -TestName <test> -MemoryProfile -MemoryProfileWarmup 10 -MemoryProfileWaitRuns 20 -MemoryProfileCollectAllocations

# Extended run for thread pool warm-up investigation
Run-Tests.ps1 -TestName <test> -MemoryProfile -MemoryProfileWarmup 20 -MemoryProfileWaitRuns 50
```

Output: `ai/.tmp/memory-YYYYMMDD-HHMMSS.dmw` (open in dotMemory GUI to compare snapshots)

## Interpreting Results

| Snapshot Comparison | Indicates |
|---------------------|-----------|
| Managed heap stable, few new objects | No managed leak (check unmanaged) |
| Objects growing linearly with runs | Managed memory leak |
| Thread pool objects (WorkStealingQueue) | Runtime warm-up, not a leak |

## Reference

See **ai/docs/leak-debugging-guide.md** for complete methodology including:
- Handle leak investigation with `-ReportHandles`
- Bisection techniques for isolating leaks
- Case studies (AuditLogForm icon leak, FileSystemWatcher race condition, HttpClientWithProgress timer leak)
