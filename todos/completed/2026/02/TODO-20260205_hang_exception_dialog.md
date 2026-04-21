# Hang detection should capture ThreadExceptionDialog text before writing thread dump

## Branch Information
- **Branch**: `Skyline/work/20260205_hang_exception_dialog`
- **Base**: `Skyline/work/20260205_DeleteAiFolder` (will rebase to master after parent merges)
- **Created**: 2026-02-05
- **Status**: Completed
- **GitHub Issue**: [#3955](https://github.com/ProteoWizard/pwiz/issues/3955)
- **PR**: [#3957](https://github.com/ProteoWizard/pwiz/pull/3957)

## Objective

Capture ThreadExceptionDialog text content before writing thread dumps in hang detection, so that exception details (type, message, stack trace) are included in the diagnostic output.

## Tasks

- [ ] Identify hang detection code that writes thread dumps
- [ ] Identify existing exception dialog capture logic used during normal test shutdown
- [ ] Reuse/adapt that logic to check for visible exception dialogs before writing thread dumps
- [ ] Log exception dialog text content alongside thread dumps
- [ ] Test the changes

## Key Files

(to be identified)

## Progress Log

### 2026-02-05 - Session Start

Starting work on this issue. Need to explore the hang detection and exception dialog capture code paths.

### 2026-02-06 - Merged

PR [#3957](https://github.com/ProteoWizard/pwiz/pull/3957) merged 2026-02-06.
