# SkylineNightly: Capture thread stack traces for hung tests using ClrMD

## Branch Information
- **Branch**: `Skyline/work/20260218_clrmd_hung_test_stacktraces`
- **Base**: `master`
- **Created**: 2026-02-18
- **Status**: In Progress
- **GitHub Issue**: [#3850](https://github.com/ProteoWizard/pwiz/issues/3850)
- **PR**: [#4011](https://github.com/ProteoWizard/pwiz/pull/4011)

## Objective

When SkylineNightly detects a hung test (TestRunner not responding for 1 hour), capture managed thread stack traces from the hung TestRunner.exe process using ClrMD before killing it, and include them in the hang alert email. Also flush partial log lines when tests start so the currently-running test is visible during hangs.

## Tasks

- [x] Add ClrMD DLL reference to SkylineNightly.csproj (already in repo at `Shared/Lib/Microsoft.Diagnostics.Runtime/lib/net40/`)
- [x] Add stack trace capture method to LogFileMonitor.cs (reuse pattern from `TestUtil/HangDetection.cs:157-175`)
- [x] Include captured stacks in hang alert email (in CheckLog ~line 191, before SendEmailNotification)
- [x] Add ClrMD DLL and XML to SkylineNightly.zip artifact packaging (CreateZipInstallerWindow.cs)
- [x] Build and verify
- [ ] Verify TeamCity build produces SkylineNightly.zip with ClrMD DLL
- [ ] Investigate partial line flushing (SkylineTester's `BeginOutputReadLine()` buffers until `\n`)

## Key Reference

- `TestUtil/HangDetection.cs:157-175` - existing ClrMD usage pattern (GetAllThreadsCallstacks)
- `SkylineNightly/LogFileMonitor.cs` - hang detection and email sending
- `SkylineTester/CommandShell.cs` - BeginOutputReadLine() buffering is why partial lines don't appear

## Progress Log

### 2026-02-18 - Session Start

Starting work on this issue.

### 2026-02-18 - Exploration Complete

Found that ClrMD is already in repo, used by TestUtil/HangDetection.cs. Real hang example from last night (TestDiaQeDiaUmpireTutorialExtra on release_perf run 80833) confirms Nick's internal thread dump didn't fire, justifying external capture. SkylineTester's `BeginOutputReadLine()` is why the hung test start line appears after `# Stopped` in the log.

Starting implementation.

### 2026-02-18 - Implementation Complete, PR Created

Implemented ClrMD stack trace capture in 3 files:
- `SkylineNightly.csproj` - Added Microsoft.Diagnostics.Runtime reference
- `LogFileMonitor.cs` - Added `AppendTestRunnerStacks()` using ClrMD passive attach
- `CreateZipInstallerWindow.cs` - Added DLL/XML to SkylineNightly.zip packaging

PR #4011 created, Nick Shulman added as reviewer. Remaining: verify TeamCity artifact and investigate partial line flushing.
