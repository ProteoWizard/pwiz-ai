# TODO-20261003_osprey_diagnostics_exit_nre.md

## Branch Information
- **Branch**: `Skyline/work/20261003_osprey_diagnostics_exit_nre`
- **Base**: `Skyline/work/20260612_net8_port` (077ebe41e8)
- **Created**: 2026-10-03
- **Status**: In review - PR #4766 opened 2026-10-04
- **GitHub Issue**: none (found by the 2026-10-02 coverage run; Brendan asked for the fix directly)
- **Module**: `osprey`
- **PR**: [#4766](https://github.com/ProteoWizard/pwiz/pull/4766)
- **Worktree**: `C:\proj\pwiz-osprey`

## Objective

Stop the unhandled `NullReferenceException` that every Osprey unit-test host prints at process exit:

```
Unhandled exception. System.NullReferenceException: Object reference not set to an instance of an object.
   at pwiz.Osprey.OspreyDiagnostics.<>c.<Initialize>b__2_0(Object _, EventArgs _) in ...\OspreyDiagnostics.cs:line 107
```

## Root cause

`OspreyDiagnostics.Initialize` registers a `ProcessExit` handler `(_, _) => s_sink.CloseAll()` that reads
the static field at exit time, not the sink it was registered for. A later `Initialize` with diagnostics off
sets `s_sink` to null. The `--diagnostics` subset test does exactly that (a diagnostics run, then plain
runs in the same test host), so the handler dereferences null at exit. A production process calls
`Initialize` once, so this only showed up in test hosts, but it was noise in every test run and was noted
as such in TODO-20260926_osprey_firstpassfdr_parallel.md.

## Fix

Capture the local `sink` in the handler, so each handler closes the sink its own call created.

## Gates

- [x] `Build-Osprey.ps1 -Configuration Debug -RunTests -RunInspection`: 647/647, inspection clean; the test log no longer shows the
  exit-time `Unhandled exception` (present in every run on 2026-10-02)
