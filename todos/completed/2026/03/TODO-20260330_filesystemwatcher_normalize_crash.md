# FileSystemWatcher crash on invalid paths - Normalize returns invalid path instead of null

## Branch Information
- **Branch**: `Skyline/work/20260330_filesystemwatcher_normalize_crash`
- **Base**: `master`
- **Created**: 2026-03-30
- **Status**: Complete
- **GitHub Issue**: [#4098](https://github.com/ProteoWizard/pwiz/issues/4098)
- **PR**: [#4119](https://github.com/ProteoWizard/pwiz/pull/4119)
- **Cherry-pick PR**: [#4122](https://github.com/ProteoWizard/pwiz/pull/4122)
- **Exception Fingerprint**: `bef5650fea50a402`, `54623034b73cd258`

## Objective

Fix `FileSystemUtil.Normalize()` to return `null` instead of the original invalid path when `Path.GetFullPath()` throws `ArgumentException`. The current behavior causes downstream crashes in `IsFileInDirectory` when `Path.GetDirectoryName()` is called on the invalid path.

Note: `NotSupportedException` (thrown for ADS paths with colons) keeps returning `path` because `Path.GetDirectoryName()` handles those fine.

## Tasks

- [x] Change `catch (ArgumentException)` to return `null` instead of `path`
- [x] Verify existing null checks in `IsFileInDirectory` and `IsInOrSubdirectoryOf` handle null correctly
- [x] Add tests for `Normalize` with invalid paths and downstream graceful degradation
- [x] Build and test pass (FilesTreeFormTest)
- [x] Create PR — merged
- [x] Cherry-pick fix to `Skyline/skyline_26_1` release branch (via "Cherry pick to release" label)

## Progress Log

### 2026-03-30 - Implementation

- Changed `catch (ArgumentException)` in `Normalize` to return `null` instead of `path`
- Kept `catch (NotSupportedException)` returning `path` — ADS paths (e.g. `file.zip:Zone.Identifier`) throw this but are handled fine by downstream `Path.GetDirectoryName()`
- Added tests in `FilesTreeFormTest.TestFileSystemHelpers()` for invalid paths with `<`, `>`, `|` characters
- Verified `IsFileInDirectory` and `IsInOrSubdirectoryOf` return `false` (no crash) for invalid paths
- FilesTreeFormTest passes
