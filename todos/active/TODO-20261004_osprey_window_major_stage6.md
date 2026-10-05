# TODO-20261004_osprey_window_major_stage6.md

## Branch Information
- **Branch**: `Skyline/work/20261004_osprey_window_major_stage6` (worktree `C:\proj\pwiz-stage6`)
- **Base**: `Skyline/work/20260612_net8_port` (PR [#4619](https://github.com/ProteoWizard/pwiz/pull/4619))
- **Stacked on**: `Skyline/work/20261004_osprey_lazy_xcorr_preprocess` (on-demand HRAM xcorr cache) - rebase onto
  the port branch once that PR merges; its PR must merge first
- **Created**: 2026-10-04 (night session)
- **Status**: SHELVED (Brendan, 2026-10-05) - do not PR. ~3.3 s/file (61.0 -> 51.0 s on the 3-file bed) does not
  justify the restructuring, and the one-sweep/shared-per-window design (incl. the per-window speculative forced
  pass, whose waste grows with how many windows cover a precursor) ties Stage 6 harder to Thermo-style disjoint
  isolation windows just as timsTOF (diaPASEF, diagonalPASEF) and SCIEX ZT Scan DIA become the priority. #4768
  already took most of Stage 6's gain (84.3 -> 64.6 s). Branch kept as a measured reference; local only.
- **Module**: `osprey`
- **PR**: (pending)

## Objective

Stage 6 (`--task PerFileRescoring`) scores each file in three passes - the re-score of the reconciled subset,
the gap-fill CWT pass, and forced integration at imputed boundaries for the targets CWT missed - and each pass
swept every isolation window, decoding it again (`StreamingWindowSpectraProvider.GetCalibratedWindow`, 239 s
CPU of the 3-file Astral profile) and rebuilding its xcorr cache. Run all three passes in ONE window sweep:
decode each window once, score every pass against it, share one on-demand xcorr cache. Output byte-identical.

## Design (first cut)
- `ScoringPipeline.RunCoelutionScoringPasses(IReadOnlyList<CoelutionPass>, ...)`: one Parallel.For over windows;
  per window: one `GetCalibratedWindow`, then each pass's `ScoreWindow` in order with a shared
  `SharedWindowXcorr`; results flattened per pass in window order. `RunCoelutionScoring` is now the one-pass case.
  Per-pass setup (`PreparePass`: scorer, scratch pool, RT tolerance/sigma, calibrated fragment tolerance) is the
  old preamble, extracted unchanged.
- `CoelutionPass`: a context + `LibraryForWindow(window, earlierPassesInThisWindow)`.
- `SharedWindowXcorr`: created by the first pass with candidates (exactly where a lone pass creates its own),
  released by the sweep after the last pass.
- `PerFileRescoreTask.GapFillPasses` replaces `RunGapFillTwoPass`.
- **The cross-window dependency** (the night-session handoff said there was none - there is one): the forced
  pass scores the targets CWT missed in EVERY window. A target whose precursor lies in two overlapping windows
  is scored in both, so window A's forced set depends on window B's CWT result. Resolution: each window
  force-integrates every target its OWN CWT pass missed (speculative), and `AppendResults` drops forced rows of
  targets CWT hit anywhere. Exact because a candidate's score depends only on its entry, the window's spectra and
  its override; cost is only the overlap targets forced in vain.
- Tolerance note: the old code cloned the CWT config AFTER the re-score pass had written the calibrated fragment
  tolerance onto `fileConfig`; now all contexts exist before any pass is prepared. Equivalent because
  `MzCalibration.CalibratedTolerance` ignores its base tolerance when calibrated (3*SD, floored) and nothing is
  written when not calibrated.
- Logging: one progress heading for the sweep; "Re-scored N of M peaks (Xs)" now reports the whole sweep;
  the gap-fill count lines lost their per-pass seconds (new resource keys `..._0_`; the forced-pass heading
  string removed; ja/zh-Hans entries dropped for re-translation).

## Gates
- [x] Release build; Debug build + 647/647 tests + inspection
- [x] Astral 3-file Stage 6 bed: 9 outputs byte-identical to the lazy-xcorr reference
  (`D:\test\osprey-runs\astral-lazyab-stage6-new`) on every run - driver
  `ai/.tmp/sessions/20261004-night/Run-Stage6AB.ps1`
- [x] Timing A/B, interleaved old/new x3, warm (log `ai/.tmp/sessions/20261004-night/s6ab1.log`):
  old `_bin\lazyxcorr-wip1` Stage 6 62.7 / 61.0 / 61.0 s; new `_bin\stage6-wip2` (9dc8c5fcda) 51.2 / 50.3 /
  51.0 s -> median 61.0 -> 51.0 s (-16%). The fused sweep (all 3 passes) takes 4.5-5.2 s/file, the same as the
  old re-score pass alone: the two gap-fill sweeps are gone. Scoring is now ~15 s of the 51 s.
- [x] `regression.ps1 -Dataset Stellar` PASSED (201.5 s, `s6-stellar-regression.log`) and `-Dataset Astral`
  PASSED vs the golden masters (1,511 s incl. HPC chain, `s6-astral-regression.log`), both in
  `ai/.tmp/sessions/20261004-night/`, on 9dc8c5fcda
- [x] Parallel vs serial window reads (warm): 51.4 vs 51.0 s - no effect; serial default kept
- [x] /code-review max: no output-changing defect; 15 low-severity findings. Fixed in 3970b9c88c (sub-agent):
  release sweep locals before the per-file GC, accurate docs on shared-config tolerance / staggered-window
  forced cost / discarded forced scorings in -d dumps, stale comments+docs, validate passes before setup and
  allow zero passes, skip gap-fill setup with no targets, window-filtered forced library, one cache path in
  ScoreWindow, ASCII dashes. 647/647, inspection 0, Astral bed byte-identical (`s6wip3.log`).
  Left for the PR: a two-overlapping-window fixture test (subsets have one window, so no test exercises the
  per-window forced filter or cross-pass cache sharing), and moving the sweep time off the "Re-scored" line.
- Brendan (2026-10-04 21:08): no further PerFileRescoring optimization beyond this branch; the remaining Stage 6
  time (parquet write 18 s, decoys, per-file overhead - profile `ai/.tmp/sessions/20261004-night/s6profile.log`)
  is parked. PR this branch after #4768 merges.

## Progress Log

### 2026-10-04 (night)
- First cut written and building (see Design).
