# Support SIM (Selected Ion Monitoring) scans in Hardklor and BullseyeSharp feature detection

## Branch Information
- **Branch**: `Skyline/work/20260305_hardklor_sim_scans`
- **Base**: `master`
- **Created**: 2026-03-05
- **Status**: Completed
- **GitHub Issue**: [#4053](https://github.com/ProteoWizard/pwiz/issues/4053)
- **PR**: [#4054](https://github.com/ProteoWizard/pwiz/pull/4054) — merged

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
- [x] Push all three repos
- [x] Create PR
- [x] Add `PerfFeatureDetectionSIMscansTest` perf test
- [x] Merge PR and delete branch

## Progress Log

### 2026-03-05 - Session Start

Code changes already implemented in both Hardklor (C++) and BullseyeSharp (C#) submodules.
Branches created and changes committed locally in all three repos. Issue #4053 created.

### 2026-03-16 - Completed

PR #4054 merged to master. All three repos (pwiz, Hardklor, BullseyeSharp) updated.
Perf test `PerfFeatureDetectionSIMscansTest` added with expected counts (1451 features,
1959 transition groups, 5877 transitions) and chromatogram extraction verification.
