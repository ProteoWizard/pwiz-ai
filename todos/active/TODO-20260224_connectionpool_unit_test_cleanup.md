# TODO-20260224_connectionpool_unit_test_cleanup.md

## Branch Information
- **Branch**: `Skyline/work/20260224_connectionpool_unit_test_cleanup`
- **Base**: `master`
- **Created**: 2026-02-24
- **Status**: In Progress - snapshot-on-leak mode added, GraphSpectrum race fixed
- **GitHub Issue**: (none - bug fix for PR #4033)
- **PR**: #4038 (full cleanup), #4037 (minimal fix, merged)

## Context

PR #4033 added ConnectionPool tracking but only wired cleanup into the functional test
path. Since `TrackHistory` was a static bool that stayed `true` once any functional test
set it, all subsequent unit tests accumulated `StackTrace` strings in `_history`, causing
93 tests to show as memory leaks in nightly runs.

## Tasks

- [x] Change `PoolEvent` to store lazy `System.Diagnostics.StackTrace` instead of string
- [x] Add ConnectionPool tracking init/cleanup to `AbstractUnitTest`
- [x] Scope functional test tracking to `WaitForSkyline()` via `ScopedAction`
- [x] Fix Quality tab Pass 1 skip bug (added `qualityonly` flag)
- [x] Fix GC leak tracker being disabled by default `dotmemorywarmup=5` (changed to `HasArg` check)
- [x] Fix 6 GC leak tracker failures exposed by the above fix:
  - [x] UpgradeErrorsFunctionalTest, UpgradeBasicFunctionalTest, UpgradeCancelFunctionalTest - TestDeployment IDisposable
  - [x] TestPeakAreaRelativeAbundanceGraph - ReplicateCachingReceiver Start/EndTrackCaching
  - [x] TestKoinaSkylineIntegration, TestEncyclopeDiaSearch - GraphSpectrum OnHandleDestroyed
- [x] Fix Run-Tests.ps1 warmup default for PinSurvivors mode (WaitRuns=0 -> warmup=1)
- [x] Add snapshot-on-leak mode: auto-snapshot when GC leak detected under dotMemory
  - [x] Added MemoryProfiler.IsReady property
  - [x] Consolidated all GC checking into GarbageCollectionTracker.CheckAfterTest()
  - [x] Added CheckAndPinLeaks() for atomic check+pin+snapshot
  - [x] Updated Run-Tests.ps1: -MemoryProfile without -MemoryProfileWarmup/-MemoryProfileWaitRuns defaults to snapshot-on-leak
- [x] Fixed GraphSpectrum Timer race condition (intermittent GC leak in TestStandardType)
  - [x] Added _disposed guard to UpdateManager.QueueUpdate() to prevent restart after Dispose()
  - [x] Unhook Timer.Tick in Dispose() to break reference chain
  - [x] Verified: 20-loop run under dotMemory with zero GC leaks
- [ ] Run all 6 tests together on TeamCity to confirm (pushed, awaiting results)
- [x] Document GC leak tracker debugging workflow in leak-debugging-guide.md

## Root Cause Analysis

PR #4034 added `GarbageCollectionTracker` to check that `SkylineWindow` and `SrmDocument`
are garbage collected after each functional test. However, the default args string in
`Program.cs` had `dotmemorywarmup=5`, and the condition `if (dotMemoryWarmup > 0)` was
always true. This caused `PinSurvivors()` (silent) to be called instead of `CheckForLeaks()`
(reports failures) for **every test**. The GC tracker was effectively disabled from the
moment it was added.

Our branch changed the condition to `commandLineArgs.HasArg(...)` which only fires when
the arg is explicitly passed on the command line, not just present in defaults. This
enabled `CheckForLeaks()` for the first time, exposing 6 pre-existing leaks.

## GC Leaks Fixed

| Test | Root Cause | Fix |
|------|-----------|-----|
| Upgrade* (3 tests) | Static `UpgradeManager.AppDeployment` → `TestDeployment._completed` delegate → `UpgradeManager._parentWindow` → SkylineWindow | Made TestDeployment IDisposable, `using` pattern |
| TestPeakAreaRelativeAbundanceGraph | Static `ReplicateCachingReceiver._cachedSinceTracked` list holding GraphData with SrmDocument | Replaced TrackCaching property with Start/EndTrackCaching methods |
| TestKoinaSkylineIntegration, TestEncyclopeDiaSearch | `GraphSpectrum.UpdateManager` Timer -> EventHandler -> SkylineWindow | Added `OnHandleDestroyed` to dispose UpdateManager |
| TestStandardType (intermittent) | Same Timer race: QueueUpdate() restarts timer after Dispose() | Added `_disposed` guard + unhook Tick event in Dispose() |