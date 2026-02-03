# TODO-20260202_spectral_library_null_specs.md

## Branch Information
- **Branch**: `Skyline/work/20260202_spectral_library_null_specs`
- **Base**: `master`
- **Created**: 2026-02-02
- **Status**: In Progress
- **GitHub Issue**: [#3932](https://github.com/ProteoWizard/pwiz/issues/3932)
- **PR**: (pending)

## Objective

Fix NullReferenceException in `SpectralLibrary.Create` when FilesTree debounce timer fires before `ConnectLibrarySpecs` has resolved all library spec entries.

## Root Cause

`SkylineFile.BuildFromDocument()` iterates `peptideSettings.Libraries.LibrarySpecs` without filtering null entries. During XML deserialization, library specs can be null before `ConnectLibrarySpecs` resolves them. The FilesTree 100ms debounce timer creates a race window where the document has libraries but some specs are still null.

## Tasks

- [x] Create branch and TODO
- [x] Filter null entries in `BuildFromDocument()` LibrarySpecs iteration
- [ ] Build and verify
- [ ] Create PR

## Files Modified

- `pwiz_tools/Skyline/Model/Files/SkylineFile.cs` - Filter nulls from LibrarySpecs with `.Where(s => s != null)`
