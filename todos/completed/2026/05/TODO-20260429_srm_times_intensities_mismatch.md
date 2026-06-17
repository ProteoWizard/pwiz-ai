# Fixed times/intensities length mismatch on SRM mzML import

## Branch Information
- **Branch**: `Skyline/work/20260429_srm_times_intensities_mismatch`
- **Base**: `master`
- **Created**: 2026-04-29
- **Status**: Merged (PR #4174 squashed as 3315ee92b on 2026-05-11)
- **GitHub Issue**: (none - reported via support thread by Wesley)
- **Support thread**: https://skyline.ms/home/support/announcements-thread.view?rowId=66356 (Wesley Vermaelen)
- **PR**: [#4174](https://github.com/ProteoWizard/pwiz/pull/4174)

## Objective

Fix `InvalidDataException: Times (390) and intensities (779) disagree in point count`
when Skyline imports a Shimadzu LabSolutions native-export mzML that contains two
acquisition events sharing the same Q1 m/z but with disjoint Q3 m/z sets.

## Reproducer

- Files: `D:\data\Wesley\Labsolutions_PackA_MA_alt.{lcd,mzML}` plus `Wesley.sky`
  (a steroid-hormone panel; Q1=331.25 covers DOC and 17α-hydroxyprogesterone,
  scheduled as two separate MRM events with overlapping but non-identical Q3 sets).
- Symptom: `SkylineCmd --import-file=...mzML` aborts with the times/intensities
  disagreement error during chromatogram release.

## Root cause

`SpectraChromDataProvider.ProcessExtractedSpectrum` has two zero-fill paths that
add intensities without adding matching times:

1. The new-collector back-fill at line 1759 (`FillZeroes(lenTimes - 1)`).
2. The trailing missing-ion zero-fill at line 1796 (`AddPoint(chromIndex, 0, 0)`).

Both make sense in `IsGroupedTime` / `IsSharedTime` modes where every collector
shares one time array, so an "implied" scan needs a zero intensity on the
collectors that were not measured this cycle. In `IsSingleTime` mode (set when
`HasSrmSpectra == true`, i.e. SRM data via mzML spectra), each `ChromCollector`
owns its *own* time array. Adding an intensity without a corresponding time on
those collectors directly desyncs the arrays.

Empirically traced via diagnostic logging on Wesley's data: at Q1=331.25, scans
alternate between Q3={97,109,121} (17α-OH-P) and Q3={81,97,109} (DOC). Each
17α-OH-P scan triggers the trailing block to `AddPoint(0,0)` on the Q3=81
collector (not present this cycle) without adding to its Times. After 390 cycles
each, the Q3=81 collector lands at 390 times / 779 intensities (390 real adds
+ 389 zero-fills from trailing) — exactly the reported error.

Also confirmed `lenTimes` is computed as `collector.TimeCount`, which itself
returns `Intensities.Count` of the first product collector — already
inconsistent in single-time mode but harmless once the zero-fill paths are
guarded.

## Fix

Guarded both zero-fill blocks with `&& !IsSingleTime`. In single-time mode,
each collector now adds an intensity *and* a time only on cycles where its Q3
was actually measured, which preserves array alignment. Grouped/shared time
modes keep the original zero-fill behavior.

## Tasks

- [x] Reproduced on `Labsolutions_PackA_MA_alt.mzML` via SkylineCmd.
- [x] Identified offending collector (Q1=331.25, Q3=81 / Q3=121) with debug logging.
- [x] Traced root cause to `ProcessExtractedSpectrum` zero-fill paths in
      `IsSingleTime` mode.
- [x] Applied guarded fix (skip both zero-fill paths when `IsSingleTime`).
- [x] Verified `Labsolutions_PackA_MA_alt.mzML` now imports cleanly.
- [ ] Run `ShimadzuFormatsTest` regression in Release. *(deferred — will be
      exercised by master nightlies)*
- [x] Added regression test `ShimadzuSrmDuplicateQ1ImportTest` bundling
      Wesley's `.lcd` + LabSolutions native `.mzML` (ShimadzuSrmDuplicateQ1.zip,
      ~2.4 MB). Verified fails on master, passes on fix branch.
- [x] Opened PR #4174 and merged to master 2026-05-11 (no separate GitHub
      issue — tracked via support thread 66356).

## Notes

- The thread also reports a second issue: in the "Skyline grouped" format, when
  multiple compounds share an identical (Q1, Q3) pair, Skyline only shows one
  of them. That is a separate bug in chromatogram-to-target mapping and is
  *not* addressed by this branch.
- The `lenTimes`/`TimeCount` naming is misleading (it returns intensity count,
  not time count). Worth renaming in a follow-up cleanup.

Co-Authored-By: Claude <noreply@anthropic.com>
