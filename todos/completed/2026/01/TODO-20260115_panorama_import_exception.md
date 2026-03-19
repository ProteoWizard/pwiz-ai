# PanoramaImportErrorException treated as programming defect

## Branch Information
- **Branch**: `Skyline/work/20260115_panorama_import_exception`
- **Base**: `master`
- **Created**: 2026-01-15
- **GitHub Issue**: https://github.com/ProteoWizard/pwiz/issues/3808
- **PR**: https://github.com/ProteoWizard/pwiz/pull/3809

## Objective

Fix `PanoramaImportErrorException` being treated as a programming defect instead of showing the user-friendly error message that was already implemented.

## Root Cause

`PanoramaImportErrorException` inherits from `Exception`, not `IOException`. This causes it to be treated as a "programming defect" by `ExceptionUtil.IsProgrammingDefect()`.

## Tasks

- [x] Add `PanoramaException` base class inheriting from `IOException`
- [x] Change `PanoramaServerException` to inherit from `PanoramaException`
- [x] Change `PanoramaImportErrorException` to inherit from `PanoramaException`
- [x] Run Panorama-related tests to verify fix
- [x] Add unit test `TestPanoramaExceptionsUserActionable`

## Progress Log

### 2026-01-15 - Session Start

Starting work on this issue. The fix is straightforward - introduce a `PanoramaException` base class that inherits from `IOException`, then have both `PanoramaServerException` and `PanoramaImportErrorException` inherit from it.

### 2026-01-15 - Implementation Complete

**Changes made:**

1. **PanoramaUtil.cs** - Added `PanoramaException` base class:
   - New class inheriting from `IOException`
   - Provides constructors for message-only and message+innerException
   - Updated `PanoramaServerException` to inherit from `PanoramaException`
   - Updated `PanoramaImportErrorException` to inherit from `PanoramaException`

2. **UtilTest.cs** - Added test `TestPanoramaExceptionsAreNotProgrammingDefects`:
   - Verifies `ExceptionUtil.IsProgrammingDefect()` returns `false` for all Panorama exceptions
   - This test would have failed before the fix (when `PanoramaImportErrorException` inherited from `Exception`)

**Tests run:**
- `TestPublishToPanorama` - PASSED
- `TestPanoramaDownloadFile` - PASSED
- `TestPanoramaDownloadFileWeb` - PASSED
- `TestPanoramaExceptionsAreNotProgrammingDefects` - PASSED

**Ready for commit and PR.**
