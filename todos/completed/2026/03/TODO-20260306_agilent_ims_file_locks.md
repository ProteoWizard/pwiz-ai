# Reader_Agilent_Test: intermittent "unreleased file locks" failure on IMS data (ImsSynth_Chrom.d)

## Branch Information
- **Branch**: `Skyline/work/20260306_agilent_ims_file_locks`
- **Base**: `master`
- **Created**: 2026-03-06
- **Status**: Completed
- **GitHub Issue**: [#4057](https://github.com/ProteoWizard/pwiz/issues/4057)
- **PR**: [#4058](https://github.com/ProteoWizard/pwiz/pull/4058)
- **Merged**: 2026-03-06 (`bc140a8c9aec75ae0a9df7371d56dd9161f49140`)

## Objective

Fix intermittent `Reader_Agilent_Test` failure on AWS/TeamCity agents where `bfs::rename()` of
`ImsSynth_Chrom.d` fails due to unreleased file locks. Root cause: `MidacDataImpl::~MidacDataImpl()`
calls `imsReader_->Close()` but does not force .NET GC finalization, leaving native file handles
open until the GC finalizer thread runs (non-deterministically).

## Tasks

- [x] Add `System::GC::Collect()` + `System::GC::WaitForPendingFinalizers()` to `MidacDataImpl::~MidacDataImpl()`
      in `pwiz_aux/msrc/utility/vendor_api/Agilent/MidacData.cpp`; also null out `imsReader_`
      and `imsCcsReader_` gcroots first so managed objects are eligible for collection

## Progress Log

### 2026-03-06 - Session Start

Starting work on this issue. Fix is a 2-line change to the destructor, mirroring the existing
pattern in `MassHunterDataImpl::~MassHunterDataImpl()` for DAD files.

### 2026-03-06 - Completed

PR #4058 merged to master. Fix nulls out `imsReader_` and `imsCcsReader_` gcroots before calling
`GC::Collect()` + `WaitForPendingFinalizers()` so managed objects are eligible for collection in
the same GC cycle, ensuring file handles are fully released before the rename check in the test
harness.
