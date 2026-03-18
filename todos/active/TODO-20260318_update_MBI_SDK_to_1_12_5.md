---
name: Update MOBILion MBI SDK to 1.12.5
description: Update vendor_api_Mobilion.7z to MBI SDK 1.12.5 which upgrades HDF5 to 1.12.3 to resolve open CVE
type: project
---

# Update MOBILion MBI SDK to 1.12.5 (HDF5 CVE Fix)

## Branch Information
- **Branch**: `Skyline/work/20260318_update_MBI_SDK_to_1_12_5`
- **Repo**: `C:\Dev\Mobilion_update`
- **Base**: `master`
- **Created**: 2026-03-18
- **Status**: In Progress
- **GitHub Issue**: [#4081](https://github.com/ProteoWizard/pwiz/issues/4081)
- **PR**: (pending)

## Objective

MOBILion Systems released MBI SDK 1.12.5, a patch that upgrades HDF5 to 1.12.3
to resolve an open CVE against the previously bundled HDF5 version. Update
`vendor_api_Mobilion.7z` to include the new SDK binaries.

## Tasks

- [x] Download MBI SDK 1.12.5 from MOBILion (user did this manually)
- [x] Update `vendor_api_Mobilion.7z` with new SDK files (MBI_SDK.dll v1.12.5.10441)
- [ ] Build with new SDK
- [ ] Verify MOBILion reader tests pass
- [ ] Commit and create PR

## Progress Log

### 2026-03-18 - Session Start

User downloaded MBI SDK 1.12.5 and updated `vendor_api_Mobilion.7z` before starting
the session. The DLL in the extracted directory is already v1.12.5.10441. Created
branch `Skyline/work/20260318_update_MBI_SDK_to_1_12_5` and GitHub issue #4081.
