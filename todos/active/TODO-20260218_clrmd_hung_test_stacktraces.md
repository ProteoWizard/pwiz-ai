# SkylineNightly: Capture thread stack traces for hung tests using ClrMD

## Branch Information
- **Branch**: `Skyline/work/20260218_clrmd_hung_test_stacktraces`
- **Base**: `master`
- **Created**: 2026-02-18
- **Status**: In Progress
- **GitHub Issue**: [#3850](https://github.com/ProteoWizard/pwiz/issues/3850)
- **PR**: (pending)

## Objective

When SkylineNightly detects a hung test (TestRunner not responding for 1 hour), capture managed thread stack traces from the hung TestRunner.exe process using ClrMD before killing it, and include them in the hang alert email. Also flush partial log lines when tests start so the currently-running test is visible during hangs.

## Tasks

- [ ] Add `Microsoft.Diagnostics.Runtime` NuGet reference to SkylineNightly
- [ ] Implement ClrMD stack trace capture when hang is detected (1-hour timeout)
  - Attach to TestRunner.exe using ClrMD
  - Enumerate all managed threads
  - Capture stack traces as text
- [ ] Include captured stack traces in hang alert email
- [ ] Flush partial line on test start so checking during a hang shows which test is running
- [ ] Test the implementation

## Progress Log

### 2026-02-18 - Session Start

Starting work on this issue. Will implement ClrMD-based stack trace capture for SkylineNightly hung test detection, and add partial line flushing for test start visibility.
