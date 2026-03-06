# Reader_Agilent_Test: intermittent "unreleased file locks" failure on IMS data (ImsSynth_Chrom.d)

## Branch Information
- **Branch**: `Skyline/work/20260306_agilent_ims_file_locks`
- **Base**: `master`
- **Created**: 2026-03-06
- **Status**: In Progress
- **GitHub Issue**: [#4057](https://github.com/ProteoWizard/pwiz/issues/4057)
- **PR**: (pending)

## Objective

Fix intermittent `Reader_Agilent_Test` failure on AWS/TeamCity agents where `bfs::rename()` of
`ImsSynth_Chrom.d` fails due to unreleased file locks. Root cause: `MidacDataImpl::~MidacDataImpl()`
calls `imsReader_->Close()` but does not force .NET GC finalization, leaving native file handles
open until the GC finalizer thread runs (non-deterministically).

## Tasks

- [ ] Add `System::GC::Collect()` + `System::GC::WaitForPendingFinalizers()` to `MidacDataImpl::~MidacDataImpl()`
      in `pwiz_aux/msrc/utility/vendor_api/Agilent/MidacData.cpp`

## Progress Log

### 2026-03-06 - Session Start

Starting work on this issue. Fix is a 2-line change to the destructor, mirroring the existing
pattern in `MassHunterDataImpl::~MassHunterDataImpl()` for DAD files.
