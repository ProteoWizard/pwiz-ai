# Files View FileSystemWatcher crashes on NTFS Alternate Data Stream paths

## Branch Information
- **Branch**: `Skyline/work/20260215_fsw-ads-crash`
- **Base**: `master`
- **Created**: 2026-02-15
- **Status**: In Progress
- **GitHub Issue**: [#3979](https://github.com/ProteoWizard/pwiz/issues/3979)
- **PR**: [#3985](https://github.com/ProteoWizard/pwiz/pull/3985)
- **Exception Fingerprint**: `cf66248972edb8a7`
- **Exception ID**: 73974

## Objective

Fix crash when FileSystemWatcher receives rename events for NTFS Alternate Data Stream paths (e.g., `file.zip:Zone.Identifier`). Also filter out `~SK` temp file prefix.

## Tasks

- [x] Add ADS path detection to `ShouldIgnoreFile` in FileSystemService.cs
- [x] Add `~SK` temp file prefix to ignore logic in FileSystemService.cs
- [x] Add defensive try/catch in FileSystemUtil.cs path methods (`IsFileInDirectory`, `IsInOrSubdirectoryOf`, `Normalize`)
- [x] Add regression tests to FilesTreeFormTest.cs

## Progress Log

### 2026-02-15 - Session Start

Starting work on this issue (after completing #3983)...
