# TODO-20260826_hangdetection_dump_leak.md

## Branch Information
- **Branch**: `Skyline/work/20260826_hangdetection_dump_leak`
- **Base**: `master`
- **Created**: 2026-08-26
- **Status**: Completed
- **Module**: `skyline`
- **PR**: [#4618](https://github.com/ProteoWizard/pwiz/pull/4618) (merged 2026-08-26)

## Why

`TestThreadDumpNamesRunningFrames` (added 2026-08-24 with `HangDetection.TryGetThreadDump`)
failed TestRunner's pass-1 leak check. dotMemory showed the retention path: a **RefCounted
(COM) handle** rooting `DacDataTarget` -> `_dataTarget` -> `DataTargetImpl` -> `_versions`
(`ClrInfo[]`) and `_modules` (`ModuleInfo[22]`).

Chasing the second question - "does the attach leave the process in a state later tests
cannot trust?" - turned up an unrelated and worse defect: the walk can hang forever.

## What was wrong

### 1. Every ClrMD attach is permanent

In the checked-in ClrMD (0.8.31.0, `pwiz_tools/Shared/Lib/Microsoft.Diagnostics.Runtime`),
`ClrInfo.CreateRuntime` hands the DAC a COM reference back to `DacDataTarget` that nothing
ever releases. Confirmed against the assembly metadata: `ClrRuntime` has **no** `Dispose`,
and `DacLibrary` has only a finalizer that `FreeLibrary`s the module - which does not drop
that COM ref. So once the DAC is loaded, `using var dataTarget = ...` cannot release it.

(It does NOT follow that `Dispose` is a no-op - see the review section below, which corrects
exactly that overreach. An attach that never reaches `CreateRuntime` is fully releasable.)

Measured with a standalone harness against the checked-in DLL, per fresh attach:

| approach | managed | private bytes |
|---|---|---|
| fresh attach per call (what the code did) | **+9,376 B** | **+3.2 MB** |
| release the DAC's COM objects by hand first | +9,184 B | +3.2 MB (no help) |
| attach once, `ClrRuntime.Flush()` per call | **0** | flat |

`Marshal.FinalReleaseComObject` on `DacLibrary._dac`/`._sos` returns 0 refs and changes
neither number. That path is a dead end.

### 2. The walk hangs on its own thread

Reproduced 100%: a **background** thread asking the DAC for its own stack never returns.
The same walk from the process's main thread comes back empty in 27 ms. `TryGetThreadDump`
always walks on a background thread and **abandons** it at the 5-second deadline - so the
hang would strand a thread holding the DAC (and, after the fix in 1, the shared lock) for
the life of the process, silently degrading every later dump.

Not walking the walking thread: 5/5 clean in the harness that wedged 100% before. It costs
nothing - that stack is the blind spot already documented on `TryGetThreadDump`, and the
thread whose stack a caller actually wants is a different one, still listed. The thread is
still named in the dump, with a line saying its stack could not be read.

The hang is not exotic: ClrMD's own doc for `EnumerateStackTrace` says it "may loop
infinitely in the case of stack corruption or other stack unwind issues which can happen in
practice" and tells callers to cap the loop. This code did not, hence `MAX_FRAMES_PER_THREAD`.

The real test does not hit this today (30/30 full dumps, 0 degraded), but the exposure is
in the helper, which `JsonToolServerTest` and the `TestFunctional` wait timeouts also call.

## What the attach does NOT do

Worth recording, because the question "is a debugger attached?" was the reason to look:

- `Debugger.IsAttached`, `IsDebuggerPresent()`, `CheckRemoteDebuggerPresent()` - all **False**
  before and after. `AttachFlag.Passive` never touches DbgEng; it is `OpenProcess` +
  `ReadProcessMemory` over a read-only DAC.
- Nothing is suspended. A spinner thread's max gap was **0.057 ms during the attach+walk**
  vs **0.136 ms while nothing was happening**, and it ticked 14.5M times in the next 300 ms.
- What does change, once: +3 modules (`mscordacwks.dll`, `clbcatq.dll`, `bcrypt.dll`),
  +3 threads, +42 handles, ~3.2 MB.

## The fix

`pwiz_tools/Skyline/TestUtil/HangDetection.cs`:

* `GetSelfRuntime()` holds one `DataTarget` and one `ClrRuntime` for the process, with
  `ClrRuntime.Flush()` before each walk. Flush is what makes reuse *correct*, not merely
  cheap - without it a live-process runtime answers from its snapshot. The attach stays
  local until a runtime is built through it, and both are dropped as a pair if `Flush` throws.
* `GetAllThreadsCallstacks()` lists the walking thread with a placeholder instead of walking
  it, caps frames at `MAX_FRAMES_PER_THREAD`, takes the lock only with a timeout, and lost
  its `processId` parameter (no caller passed anything but the current process, and a cached
  self-attach makes any other value a trap). It is materialized rather than a `yield return`
  iterator, so it cannot hold the lock across a caller's enumeration.
* `DescribeAttachEnvironment()` keeps its own attach, disposed - it must read the machine at
  the moment of failure, and without `CreateRuntime` there is nothing unreleasable to keep.

## Verification

Verified that cached+`Flush` returns *exactly* what re-attaching returns: identical thread
and frame counts against a fresh attach per call, while threads were being added between
reads.

TestRunner pass-1 leak deltas for `TestThreadDumpNamesRunningFrames`:

| | managed | heap | memory | handles |
|---|---|---|---|---|
| thresholds | 8 KB | 20 KB | 150 KB | 2 |
| before | **15.5 KB** | **193.1 KB** | **7632.6 KB** | 0 |
| after | 1.6 KB | 1.6 KB | 22.9 KB | 0.4 |

Negative test: with the fix reverted and rebuilt, the check fails as
`LEAKED 15848 Managed bytes / 197732 Heap bytes / 7815753 bytes`, total memory climbing
120 -> 224 MB over 15 runs.

- [x] `TestThreadDumpNamesRunningFrames` pass 1 - passes, converges in 9 iterations
- [x] `TestThreadDumpNamesRunningFrames` looped 30 times - 30/30 full dumps, 0 degraded
- [x] `CodeInspection` - passes
- [x] Solution builds

## What `/code-review max` changed

The first cut fixed the leak but turned per-call isolated state into process-lifetime
**shared** state without the invalidation, bounding or self-synchronization shared state
needs. Every claim below was verified independently before acting on it.

* **`Dispose` is NOT a no-op** - the first cut's comment said it "would buy nothing".
  Measured: 10 undisposed attaches cost **10 handles**, disposing all 10 returns every one
  (`DataTargetImpl.Dispose` -> `_dataReader.Close()` -> `CloseHandle`). So an attach that
  never reaches `CreateRuntime` is fully releasable. The attach is now kept **local** until
  a runtime is built through it, and disposed otherwise - which also fixes the case that
  mattered most: on the no-local-DAC agents this file was written for, the guard throws
  before `CreateRuntime`, so the first cut would have left them holding a permanent attach
  that could never produce a dump. A leak introduced by the leak fix.
* **One wedged walk would have killed the diagnostic permanently.** `_attachLock` was held
  across an unbounded `EnumerateStackTrace`, whose ClrMD doc says verbatim it "may loop
  infinitely in the case of stack corruption or other stack unwind issues which can happen
  in practice" and tells callers to "set a maximum loop count". Added `MAX_FRAMES_PER_THREAD`
  and `Monitor.TryEnter(_attachLock, ATTACH_LOCK_TIMEOUT_MILLIS)` that names the cause.
* **A throwing `Flush` poisoned the cache forever** - `_runtime` was assigned on success and
  cleared nowhere. Now dropped as a pair in a catch so the next dump rebuilds.
* **`DescribeAttachEnvironment` went back to its own disposed attach.** Sharing it froze the
  DAC answer at first attach (the one question it exists to answer), needed the lock on the
  *caller's* thread - the one path with no `Join` to bound it - and added an interruptible
  wait inside `catch (Exception)` that could swallow the watchdog's `ThreadInterruptedException`.
* **The walking thread is now listed with a placeholder**, not dropped, so "every managed
  thread" stays true and an empty stack keeps meaning "could not read", as the class doc says.
* **ClrMD is 0.8.31.0**, not 0.9 as the first cut's comment claimed (verified against the
  assembly). The two leak numbers now both appear with their context: 9 KB / 3.2 MB in a bare
  console harness, 15.5 KB / 7.6 MB in a Debug TestRunner.
* **Style**: `$@"..."` over `$"..."` (style-guide.md:138), no single-line `if`
  (CRITICAL-RULES.md:72), AI assistance header line (style-guide.md:712).
* Dropped the `Kernel32.GetCurrentThreadId` P/Invoke for `ClrThread.ManagedThreadId`, which
  ClrMD documents as equivalent to `Thread.ManagedThreadId` in the target process - verified,
  exactly one match and the OS ids agree.

**Refuted, not applied**: the claim that the hard-coded 5000 ms attach timeout could consume
the whole budget. `LiveDataReader` takes only a pid, so ClrMD ignores `msecTimeout` on the
passive path - it is the DbgEng handshake timeout, used only for Invasive/NonInvasive.

**Noted, not done**: `SkylineNightly/LogFileMonitor.cs:275` already walks threads
cross-process by pid and has no `LocalMatchingDac` guard, so it is still exposed to the
745-1035 s symbol-server path. Out of scope here; it wants the out-of-process work below.
**Carried forward** - this did not ship with #4618 and is worth its own item.

### Test coverage the review was right about

`TestThreadDumpNamesRunningFrames` called `TryGetThreadDump` **once**, so the reuse branch -
the thing this whole change rests on - never executed under an assertion. Delete `Flush()`
and every later dump would serve the first dump's stacks as current, and the test still
passed. Added `AssertSecondDumpIsNotTheFirstOne`: start a thread, wait for it to signal it is
up, take a second dump, assert it names that thread's managed id.

**Negative test**: with `Flush()` commented out and rebuilt, the run fails at
`HangDetectionThreadDumpTest.cs:141` in `AssertSecondDumpIsNotTheFirstOne`. Restored and green.

## Progress Log

### 2026-08-26 - Merged

PR #4618 merged as commit `bf8a9dd2d` with the admin override - all checks were green
(TeamCity Skyline 1740 tests, Core Windows 308, Docker/Wine 44, code inspection, six CodeQL
analyses) but the branch was `BEHIND` master, which the up-to-date-branch protection blocks.

What shipped: the attach is made once and reused with `Flush`, the dump no longer walks its
own thread, the walk is bounded by `MAX_FRAMES_PER_THREAD` and a lock timeout, and the reuse
now has a test. Copilot's review added two more: the frame name is built rather than formatted
(an unresolved type used to render as a bare leading dot, `.[Unknown]`), and per-thread notes
carry `THREAD_NOTE_PREFIX` which the test's frame count excludes - without that, the notes this
work introduced counted as frames, so a dump that walked nothing could have satisfied "named no
frames on any thread". Every one of those was negative-tested.

Nothing was deferred from the stated scope. The out-of-process dumper below was never in it.

## Open question

The remaining blind spot is unchanged and still wants the documented real fix: a **passive
self-attach cannot walk a running stack**, so the UI thread - usually the one worth seeing -
comes back with no frames. Taking the dump from a **separate process** would fix that and
would also move the DAC, the handle and the 3.2 MB out of the process under test entirely.
That is a much larger change and is deliberately not attempted here.
