# Audit background thread exception handling - ThreadExceptionDialog appearing

## Branch Information
- **Branch**: `Skyline/work/20260331_thread_exception_audit`
- **Base**: `master`
- **Worktree**: `pwiz-work1`
- **Created**: 2026-03-31
- **Status**: In Progress
- **GitHub Issue**: [#3840](https://github.com/ProteoWizard/pwiz/issues/3840)
- **PR**: (pending)

## Objective

Audit and fix background thread creation points where exceptions escape to .NET's ThreadExceptionDialog instead of being handled by Skyline's exception handling. 878 test failures over the past year contain `ThreadExceptionDialog (Microsoft .NET Framework:` indicating exceptions reaching the .NET system level.

## Tasks

- [ ] Audit background thread creation points for exception handling gaps
- [ ] Convert bare BeginInvoke calls to SafeBeginInvoke where appropriate
- [ ] Build and test
- [ ] Create PR

## Progress Log

### 2026-03-31 - Session Start

Starting work on this issue. Depends on #3842 for the CommonActionUtil normalization foundation.
