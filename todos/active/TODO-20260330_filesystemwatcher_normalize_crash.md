# FileSystemWatcher crash on invalid paths - Normalize returns invalid path instead of null

## Branch Information
- **Branch**: `Skyline/work/20260330_filesystemwatcher_normalize_crash`
- **Base**: `master`
- **Created**: 2026-03-30
- **Status**: In Progress
- **GitHub Issue**: [#4098](https://github.com/ProteoWizard/pwiz/issues/4098)
- **PR**: (pending)
- **Exception Fingerprint**: `bef5650fea50a402`, `54623034b73cd258`

## Objective

Fix `FileSystemUtil.Normalize()` to return `null` instead of the original invalid path when `Path.GetFullPath()` throws `ArgumentException` or `NotSupportedException`. The current behavior causes downstream crashes in `IsFileInDirectory` when `Path.GetDirectoryName()` is called on the invalid path.

## Tasks

- [ ] Change `catch (NotSupportedException)` to return `null` instead of `path`
- [ ] Change `catch (ArgumentException)` to return `null` instead of `path`
- [ ] Verify existing null checks in `IsFileInDirectory` and `IsInOrSubdirectoryOf` handle null correctly
- [ ] Add unit test for `Normalize` with invalid paths
- [ ] Cherry-pick fix to `Skyline/skyline_26_1` release branch

## Progress Log

### 2026-03-30 - Session Start

Starting work on this issue. Bug affects release version 26.1.0.057 with 15 reports from 6 users.
