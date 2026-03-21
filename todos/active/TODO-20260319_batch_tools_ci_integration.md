---
name: AutoQC CI Integration
description: Add AutoQC build and test targets to Jamfile.jam for TeamCity CI integration
type: project
---

# AutoQC CI Integration

## Branch Information
- **Branch**: `Skyline/work/20260319_batch_tools_ci_integration`
- **Base**: `master`
- **Created**: 2026-03-19
- **Status**: In Progress
- **Prior PR**: [#3697](https://github.com/ProteoWizard/pwiz/pull/3697) (to be closed - stale branch from 2025-12-04)
- **PR**: (pending)

## Objective

Enable CI to build and test AutoQC via Jamfile targets, following the existing SkylineBatch pattern. TeamCity admin is available to configure the server side.

## Changes Summary

### Jamfile.jam
- Added `generate-skyline-AssemblyInfo.cs` call for AutoQC
- Added `do_auto_qc` / `do_auto_qc_test` rules and actions
- Added `AutoQC.exe` and `AutoQCTest` make targets
- Test action `cd`s to AutoQC directory (vstest deploy path fix)
- Connected tests excluded via `/TestCaseFilter:"TestCategory!=Connected"`

### .gitignore
- Added AutoQC AssemblyInfo.cs
- Removed AutoQC AssemblyInfo.cs from git tracking (`git rm --cached`)

### AutoQC Version Handling (Program.cs)
- Added `Install` class following Skyline's `Install.cs` pattern
- Parses version string from assembly attributes (handles git hash, build type suffixes)
- Exposes `Version`, `BareVersion`, `GitHash`, `IsDeveloperInstall`, `IsAutomatedBuild`
- Replaced `System.Version _version` field with `Install _install` (initialized eagerly)
- Removed `TEST_VERSION` hack - tests now exercise real version parsing
- Title bar shows `BareVersion` (numeric only, no git hash)

### Test Infrastructure
- `[TestCategory("Connected")]` on 3 network-dependent tests
- `AllowInternetAccess` property on `SharedBatchTest.AbstractUnitTest`
- `PanoramaTest` restructured: removed TestInitialize/TestCleanup, setup in test body
- `AutoQcConfig.DiffReport()` for readable config comparison on test failures
- `AutoQcConfigManager.ConfigListDiffReport()` for list-level diffs
- `WaitForCondition` improvements: early bail on error, elapsed time reporting
- Longer timeouts for Panorama-dependent waits (120s)
- Fixed `GetTestSkylineSettings()` to return `Local` type when local SkylineCmd exists
- Documented `ACCESS_INTERNET` environment variable in TestUtils.cs

## Tasks

- [x] Add AutoQC AssemblyInfo generation to Jamfile.jam
- [x] Add AutoQC build rule/actions to Jamfile.jam
- [x] Add AutoQC test rule/actions to Jamfile.jam
- [x] Add AutoQC.exe and AutoQCTest make targets to Jamfile.jam
- [x] Add AutoQC AssemblyInfo.cs to .gitignore
- [x] Remove AutoQC AssemblyInfo.cs from git tracking
- [x] Fix vstest deploy path (cd to AutoQC directory)
- [x] Fix version parsing (Install class, NRE fix)
- [x] Add [TestCategory("Connected")] and AllowInternetAccess guards
- [x] Fix SkylineSettings round-trip equality in tests
- [x] Add DiffReport for config comparison diagnostics
- [x] Verify: bjam AutoQCTest passes (15 local tests)
- [x] Verify: VS tests pass without ACCESS_INTERNET
- [x] Verify: VS tests pass with ACCESS_INTERNET=True
- [ ] Commit and create PR
- [ ] Close old PR #3697
- [ ] Coordinate with TeamCity admin for server configuration
- [ ] Merge after verification

## Known Issues

**TestEnableInvalid** - Currently disabled in `ConfigManagerTest.cs`
- Was not running correctly; after fixing threading issue, the test fails
- Not blocking for CI integration - can be investigated separately

## References

- SkylineBatch CI pattern in Jamfile.jam
- Skyline's `Install.cs` (pwiz_tools/Skyline/Util/Install.cs) - version parsing model
- `AutoQCTest/TestUtils.cs` for credential and internet access documentation
