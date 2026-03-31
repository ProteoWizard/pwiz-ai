# Add Excedion Pro Orbitrap support for method export

## Branch Information
- **Branch**: `Skyline/work/20260330_excedion_pro_export`
- **Base**: `master`
- **Worktree**: `pwiz-work2`
- **Created**: 2026-03-30
- **Status**: In Progress
- **GitHub Issue**: [#4118](https://github.com/ProteoWizard/pwiz/issues/4118)
- **Support Request**: [skyline.ms thread 74243](https://skyline.ms/announcements/home/support/thread.view?rowId=74243)
- **PR**: (pending)

## Objective

Method export fails for the Excedion Pro Orbitrap because the installed instrument type `OrbitrapExcedionPro` does not match the expected `OrbitrapExploris480` in `EnsureLibraries`. Add support for the Excedion Pro instrument type.

## Tasks

- [x] Add OrbitrapExcedionPro as a recognized instrument type
- [x] Build and test (ThermoDllFinderTest passes)
- [ ] Create PR

## Progress Log

### 2026-03-30 - Implementation

- Added `THERMO_EXCEDION_PRO` / `THERMO_EXCEDION_PRO_REG` constants
- Added to METHOD_TYPE_EXTENSIONS, THERMO_TYPE_TO_INSTALLATION_TYPE, IsFullScanInstrumentType, and SureQuant export switch case
- Not added to METHOD_TYPES — users select "Thermo" and instrument is auto-detected from registry
- Added DllFinder test case for OrbitrapExcedionPro registry key
