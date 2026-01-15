# PanoramaImportErrorException treated as programming defect

## Branch Information
- **Branch**: `Skyline/work/20260115_panorama_import_exception`
- **Base**: `master`
- **Created**: 2026-01-15
- **GitHub Issue**: https://github.com/ProteoWizard/pwiz/issues/3808

## Objective

Fix `PanoramaImportErrorException` being treated as a programming defect instead of showing the user-friendly error message that was already implemented.

## Root Cause

`PanoramaImportErrorException` inherits from `Exception`, not `IOException`. This causes it to be treated as a "programming defect" by `ExceptionUtil.IsProgrammingDefect()`.

## Tasks

- [ ] Add `PanoramaException` base class inheriting from `IOException`
- [ ] Change `PanoramaServerException` to inherit from `PanoramaException`
- [ ] Change `PanoramaImportErrorException` to inherit from `PanoramaException`
- [ ] Run Panorama-related tests to verify fix

## Progress Log

### 2026-01-15 - Session Start

Starting work on this issue. The fix is straightforward - introduce a `PanoramaException` base class that inherits from `IOException`, then have both `PanoramaServerException` and `PanoramaImportErrorException` inherit from it.
