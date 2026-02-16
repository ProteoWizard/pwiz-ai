# Files View FileSystemWatcher crashes on NTFS Alternate Data Stream paths

## Branch Information
- **Branch**: `Skyline/work/20260215_fsw-ads-crash`
- **Base**: `master`
- **Created**: 2026-02-15
- **Status**: Review
- **GitHub Issue**: [#3979](https://github.com/ProteoWizard/pwiz/issues/3979)
- **PR**: [#3985](https://github.com/ProteoWizard/pwiz/pull/3985)
- **Exception Fingerprint**: `cf66248972edb8a7`
- **Exception ID**: 73974

## Objective

Fix crash when FileSystemWatcher receives rename events for NTFS Alternate Data Stream paths (e.g., `file.zip:Zone.Identifier`). Also filter out `~SK` temp file prefix.

## Tasks

- [x] Add ADS path detection to `ShouldIgnoreFile` in FileSystemService.cs
- [x] Add `~SK` temp file prefix to ignore logic in FileSystemService.cs
- [x] Add defensive handling in FileSystemUtil.cs: `Normalize` returns original path on exception; null guards in `IsFileInDirectory` and `IsInOrSubdirectoryOf`
- [x] Add regression tests to FilesTreeFormTest.cs

## Progress Log

### 2026-02-15 - Implementation and Review

Completed initial implementation:
- `IsAlternateDataStream` using `IndexOf(':', 2)` — simple but had a bug
- `ShouldIgnoreFile` with ADS detection and `~SK` prefix filtering
- `Normalize` with try-catch returning null, null guards in path methods
- Regression tests in FilesTreeFormTest

Copilot review identified four issues, all addressed in follow-up commit:
1. `IsAlternateDataStream` false positive on `\\?\C:\` extended-length paths — rewrote to use `LastIndexOf(':')` + check no separator follows
2. `Normalize` returning null breaks existing callers — changed to return original path as fallback
3. `FILE_EXTENSION_IGNORE_LIST` was case-sensitive (pre-existing) — added `StringComparer.OrdinalIgnoreCase`
4. Missing extended-length path test — added

All review threads replied to and resolved. Awaiting merge.
