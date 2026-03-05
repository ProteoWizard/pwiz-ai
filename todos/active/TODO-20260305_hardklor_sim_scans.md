# Support SIM (Selected Ion Monitoring) scans in Hardklor and BullseyeSharp feature detection

## Branch Information
- **Branch**: `Skyline/work/20260305_hardklor_sim_scans`
- **Base**: `master`
- **Created**: 2026-03-05
- **Status**: In Progress
- **GitHub Issue**: [#4053](https://github.com/ProteoWizard/pwiz/issues/4053)
- **PR**: (pending)

## Objective

When Hardklor processes SIM scan data (where each MS1 scan covers only a narrow
m/z window), the Kronik2 feature-building step incorrectly treats missing peptide
detections in non-overlapping scans as chromatographic gaps. This causes features
to be fragmented or dropped entirely.

## Tasks

- [x] Add `MAX_SIM_WINDOW_MZ` constant and `scanWinLower`/`scanWinUpper` fields to `sScan` in `CKronik2.h`
- [x] Write scan window bounds to Hardklor output in `CHardklor.cpp` and `CHardklor2.cpp`
- [x] Parse scan window bounds and skip non-overlapping windows in `CKronik2.cpp`
- [x] Mirror all changes in `BullseyeSharp/CKronik2.cs`
- [x] Commit submodule changes on `Skyline/work/20260305_hardklor_sim_scans` in Hardklor and BullseyeSharp
- [x] Commit submodule pointer updates in main pwiz repo
- [ ] Push all three repos
- [ ] Create PR

## Progress Log

### 2026-03-05 - Session Start

Code changes already implemented in both Hardklor (C++) and BullseyeSharp (C#) submodules.
Branches created and changes committed locally in all three repos. Issue #4053 created.
Ready to push and open PR.
