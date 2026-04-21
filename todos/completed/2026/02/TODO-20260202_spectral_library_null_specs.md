# TODO-20260202_spectral_library_null_specs.md

## Branch Information
- **Branch**: `Skyline/work/20260202_spectral_library_null_specs`
- **Base**: `master`
- **Created**: 2026-02-02
- **Status**: Completed
- **GitHub Issue**: [#3932](https://github.com/ProteoWizard/pwiz/issues/3932)
- **PR**: [#3941](https://github.com/ProteoWizard/pwiz/pull/3941)

## Objective

Fix NullReferenceException in `SpectralLibrary.Create` when `LibrarySpecs` contains null entries during FilesTree update.

## Root Cause

`SkylineFile.BuildFromDocument()` iterates `peptideSettings.Libraries.LibrarySpecs` without filtering null entries. During XML deserialization, `PeptideLibraries.ReadXml()` creates complementary arrays where `librarySpecs[i]` is null when `libraries[i]` is a `Library` object and vice versa. Normally `ConnectLibrarySpecs` resolves all nulls before the document becomes active, but the exception report shows a null reaching `SpectralLibrary.Create` through an unknown path. The exact mechanism is unclear, but defensive null filtering matches existing patterns in `PeptideSettings.cs` (lines 2030, 2250, 2572).

## Tasks

- [x] Create branch and TODO
- [x] Filter null entries in `BuildFromDocument()` with `.Where(s => s != null)`
- [x] Guard `else` branch with `librarySpecs.Count > 1` to skip empty results
- [x] Build and verify

## Notes

- `SpectralLibrary.Create` depends on `LibrarySpec.Id` for `IdentityPath`, so we cannot fall back to the `Library` object's name for display
- When null specs are filtered out, the FilesTree simply omits spectral libraries until a subsequent `DocumentChangedEvent` fires with fully-resolved specs

## Files Modified

- `pwiz_tools/Skyline/Model/Files/SkylineFile.cs` - Filter nulls from LibrarySpecs, guard else branch with count > 1

## Resolution

- **Status**: Fixed
- **PR**: [#3941](https://github.com/ProteoWizard/pwiz/pull/3941) — merged to master 2026-02-03 (commit `61a3ea5`)
- **Release cherry-pick**: [#3943](https://github.com/ProteoWizard/pwiz/pull/3943) — merged to `Skyline/skyline_26_1` 2026-02-03 (commit `046082e`)
- **Summary**: Added `.Where(s => s != null)` filter on `LibrarySpecs` in `BuildFromDocument()` and guarded the else branch with `librarySpecs.Count > 1` to prevent NRE when null entries are present during FilesTree update.

## Progress Log

### 2026-02-03 - Merged
- PR #3941 merged to master (commit `61a3ea5`)
- Cherry-pick PR #3943 merged to `Skyline/skyline_26_1` (commit `046082e`)
