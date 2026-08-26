# Collapse the .NET 8.0 branch chain and merge it to master

## Branch Information
- **Checkout**: `C:\proj\pwiz-work1` (the net8 work tree - fully provisioned for it)
- **Branch**: `Skyline/work/20260818_commonutil_winforms_split` (PR #4587)
- **Base**: `chambem2/pwiz-sharp` (PR #4178)
- **Created**: 2026-08-26
- **Status**: In progress - #4587 is CLEAN and waiting on TeamCity
- **Module**: `skyline`
- **PR**: [#4587](https://github.com/ProteoWizard/pwiz/pull/4587)

## Goal, in Brendan's words

1. Get everything applicable into `master:head` - **done**, via #4610
2. Collapse all Skyline/Osprey .NET 8.0-specific work into **#4587** - **done**
3. Squash-merge **#4587** into pwiz-sharp **#4178**, which then becomes `master:head`
   and the source of ProteoWizard, Skyline and (soon) Osprey installers

## Where it stands (2026-08-26)

```
master
  <- #4178  chambem2/pwiz-sharp                        MERGEABLE (was CONFLICTING)
       <- #4587  Skyline/work/20260818_commonutil_winforms_split   MERGEABLE/CLEAN
            <- #4588  osprey: ProteoWizard the only spectrum reader on net8.0
```

| Branch | Fate |
|---|---|
| `Skyline/work/20260612_net8_port` | **deleted** - zero unique commits, strict ancestor of pwiz-sharp |
| `Skyline/work/20260821_net8_test_reliability` (#4605) | **auto-merged** into #4587, branch deleted |
| `Skyline/work/20260822_test_stability` | **abandoned**, remote deleted. Local branch kept in pwiz-work1 as insurance; SHA `9354eb2f59b2818386f595478225f9f0a13043f2` |

#4588 already bases on #4587, so it needs no retarget until #4587 merges.

## What remains before the squash-merge

- [ ] **TeamCity on #4587.** It reports *no checks* - work branches do not auto-trigger it.
      This is the only thing between here and the merge. Everything below is verified on
      one machine only.
- [ ] Squash-merge #4587 into `chambem2/pwiz-sharp`
- [ ] Then #4178 into master

## Verified locally on #4587 (`295ad8c92d`)

Full solution builds Debug (~83 s) and Release (~85 s). `TestThreadDumpNamesRunningFrames`,
`TestUnattendedDialogTimeout`, `TestStaleProgressDoesNotRegressFinishedFile`, `UtilTest`
and `CodeInspection` all pass.

## Judgment calls a reviewer should look at

**`HangDetection` was PORTED, not replaced.** The two lines use different ClrMD:

| | master / net472 | net8 line |
|---|---|---|
| ClrMD | vendored 0.8.31 | PackageReference **3.1.512801** |
| API | `AttachToProcess(..., AttachFlag.Passive)` | `CreateSnapshotAndAttach` |
| Running threads | cannot read - the documented blind spot | **can** read |

`AttachFlag`, `DacInfo` and `LocalMatchingDac` do not exist in 3.1. Master's structure
(bounding, degradation, `GetCallingThreadStack`) was ported onto the 3.x API rather than
keeping #4605's older file - because keeping it would have REGRESSED master's version when
this line merges back, and dropped its test.

**`DocNodeChromInfo` resolved to #4605's side**, not master's: its comments carry the
correction that `Equals` is content equality by design and reference equality must never be
suggested there.

**A pre-existing leak surfaced during that port.** ClrMD 3.x's snapshot writes a `symbols`
cache into the process TEMP directory, which `AbstractUnitTest` redirects per test - so every
dump left a directory behind and the test's leftover-file check failed it. It had been
happening on #4605 unnoticed, because that branch has no test that takes a dump.
`HangDetection` now removes the cache it creates (`Path.GetTempPath()`, NOT the working
directory - that was the bug in the first two attempts at the fix).

## OPEN QUESTION - decide before #4587 merges onward

**PR [#4618](https://github.com/ProteoWizard/pwiz/pull/4618)** (nickshulman, against master)
fixes three real defects in master's `HangDetection`:

1. **Every ClrMD attach was permanent** - 0.8.31's `CreateRuntime` hands the DAC a COM
   reference nothing releases, so `using var dataTarget` released nothing. 9 KB managed /
   3.2 MB private leaked per call; 15.5 KB / 7.6 MB inside a Debug TestRunner. Fixed by
   attaching once and reusing with `ClrRuntime.Flush()`.
2. **The walk hangs on its own thread** - reproduced 100%. Because `TryGetThreadDump`
   ABANDONS the dump thread at its deadline (added 2026-08-25 to fix a 17-minute stall),
   that hang would strand a thread holding the DAC for the life of the process.
3. **`EnumerateStackTrace` was unbounded**, against ClrMD's own documentation.

**None of this has been re-asked against ClrMD 3.1 on the net8 line**, where the code is
different and this fix WILL conflict:

- Does 3.x leak the same way? It has real `IDisposable` semantics, so possibly not.
- Does the self-walk still hang? A snapshot can read running threads, so possibly not.
- The frame cap almost certainly still applies either way.

Do not merge #4618 forward by taking either side wholesale. Each of the three needs a
measurement on 3.1, the way #4618 measured them on 0.8.31.

## Also fixed today, in #4587 (`295ad8c92d`)

Staging resolved build output as `bin\<Config>\<TFM>` in **four** places, which is where a
plain `dotnet build` writes - but Visual Studio and `Build-Skyline.ps1` build x64 into
`bin\x64\<Config>\<TFM>`. A stale AnyCPU `TestRunner.exe` sat in the assumed path, so every
existence check passed and staging ran a stager four hours older than the source, failing on
an argument it had never heard of. Fixed in `TestStager.GetProjectOutput` (the root),
`SkylineTesterWindow.FindStagerExe`, `Stage-Net8Tests.ps1`, and `Build-Skyline.ps1`
(pwiz-ai `8f9d748`, now passes `/p:Platform`).

`TestStager.IsOutputStale` - the guard meant to catch exactly this - did not fire, because
it was checking the wrong directory. The guard was sound; the path it guarded was not.

## Checkouts

| Checkout | Role |
|---|---|
| `pwiz-work1` | **net8** work tree, fully provisioned. On #4587. |
| `daily` | **net472/master** work tree. Has the native build; cannot build the net8 path (`SpectrumList_LockmassRefiner` missing). Currently on `pr4618-review`. |
| `pwiz` | other work - `Skyline/work/20260824_webclient_prohibition` |

Do not try to build the net8 line in `daily`, or master's native path in `pwiz-work1`.
