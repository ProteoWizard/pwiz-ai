# Fixed msconvert mzWindow filter leaving ion mobility arrays untrimmed

## Branch Information
- **Branch**: `Skyline/work/20261127_mzwindow_all_arrays` (checkout `C:\Dev\cmdline`)
- **Base**: `master`
- **Created**: 2026-11-27
- **Status**: Completed
- **GitHub Issue**: (none - found while preparing test data for #5083)
- **Module**: `pwiz`
- **PR**: [#5085](https://github.com/ProteoWizard/pwiz/pull/5085) (merged 2026-11-27)

## Objective

The C# port of `SpectrumList_MZWindow` (`pwiz/analysis/SpectrumListMzWindow.cs`) trimmed only the
m/z and intensity arrays. The retired C++ version sort_together'ed every array of m/z length with
m/z and trimmed them all, dropping arrays of other lengths. With `--combineIonMobilitySpectra`,
the port wrote mzML whose ion mobility array kept its full length (2,031,351 values against
13,618 m/z values on John's Agilent mouse liver run), so every peak got the wrong mobility.

## Tasks

- [x] Extend `SpectrumListWrapperTests.MzWindow_DropsPeaksOutsideRange` with unsorted m/z and a
      parallel ion mobility array (red on master)
- [x] Port the C++ behavior (green; all 207 Analysis.Tests pass)
- [x] End-to-end: regenerated D:\bench\im-peak-picking\trim\VLSSIEQK_trim_fixed.mzML - arrays
      equal length, m/z sorted, Skyline import with IM 22.598 ms picks 20.52 min as the .d does
- [x] /code-review medium - 6 findings, triaged:
      * Re-sorting by m/z (fixed): SpectrumListBase.HasNonMzOrderingAxis / EnsureMzAscending
        deliberately leave IM-axis spectra in mobility order; the C++ sort_together predates
        that rule. Now keeps input order (also moots the unstable-sort finding).
      * Integer arrays of m/z length not trimmed (fixed).
      * Non-parallel arrays dropped, incl. a malformed intensity array (fixed: left as is).
      * Mutation of spectra retained by in-memory inner lists - pre-existing, dropped.
      * "Comment misstates cpp" - reviewer misread cpp (it re-adds equal-length arrays); moot.
- [x] PR #5085 opened 2026-11-27
- [x] Second /code-review medium on #5085 (requested by Brian): 3 nits fixed in a6c565c1cb
      (intensity out of step with m/z -> spectrum left untouched; early return when nothing is
      dropped plus span-based compaction; test asserts on the returned spectrum's arrays),
      2 pre-existing dropped (inner-list mutation, FullMetadata peak count). 207 tests pass;
      regenerated mzML spectrumList is byte-identical to the Skyline-verified one.
- [x] Copilot review: none posted on the PR; /code-review was the AI review
- [x] TeamCity green, human review (Brian)

## Regression Test

- **Test name**: `MzWindow_DropsPeaksOutsideRange` (extended)
- **Test project**: pwiz/analysis/test/Analysis.Tests.csproj
- **Fails on master**: yes (element 1 mismatch - unsorted, IM untrimmed)
- **Passes on fix**: yes

## Notes

- Build gotcha: `Build-PwizSharp.ps1 -Project .../MsConvert.csproj` writes to
  `MsConvert/src/bin/Release/net10.0/`, not `bin/x64/Release/` - the x64 folder holds a stale
  build and its msconvert.exe silently runs old code.
- Unverified: every combined IMS spectrum also carries a constant scan-level
  "ion mobility drift time" (29.9298). Did not affect Skyline here; compare with C++ output.

## Progress Log

### 2026-11-27

Found while trimming test data for #5083 (TODO-20261127_im_peak_picking.md). Fixed and verified.

### 2026-11-27 - Merged

PR #5085 merged as commit 63087163d1. mzWindow now trims every binary and integer array of m/z
length with m/z, keeps input peak order (IMS spectra stay in mobility order), and leaves arrays
of other lengths and spectra with out-of-step intensities untouched. Considered and left as is:
the sampled-noise arrays (MS:1002743-1002745) are not per-peak, so the same-length rule would
trim them wrongly if their length happened to equal the peak count; no C# reader emits them,
and the m/z sorter uses the same rule.
