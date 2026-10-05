# TODO-20261004_osprey_lazy_xcorr_preprocess.md

## Branch Information
- **Branch**: `Skyline/work/20261004_osprey_lazy_xcorr_preprocess` (worktree `C:\proj\pwiz-4708`)
- **Base**: `Skyline/work/20260612_net8_port` (PR [#4619](https://github.com/ProteoWizard/pwiz/pull/4619))
- **Created**: 2026-10-04
- **Status**: In progress - committed locally (0acf90c078), not pushed; night session takes it to a PR
- **Module**: `osprey`
- **PR**: (pending)
- **Follows**: `ai/todos/completed/TODO-20261002_osprey_cold_window_reads.md` (#4767)

## Objective

HRAM xcorr preprocessing in `CoelutionScorer.ScoreWindow` built a sparse xcorr form of EVERY spectrum in a
window before scoring it. Xcorr reads only each scored candidate's apex and apex -2..+2
(`XcorrCalculators.cs:67`, `:144-152` SG sweep), so a window with few candidates needs few spectra. Make the
HRAM `WindowXcorrCache` fill on demand. Output must stay byte-identical.

## Evidence (2026-10-04, this machine: i9-14900K, 128 GB)

dotTrace sampling profiles, Astral regression data hard-linked into `D:\test\osprey-runs\astral` (do NOT run
the profiler against the regression folder - it writes caches there):
- **PerFileScoring** (file 49, `C:\proj\ai\.tmp\osprey-profile-20261004-114448.dtp`): scoring CPU 1,561 s
  (thread-summed); `FragmentMath.HasTopNFragmentMatch` 561 s own and `ScoringMath.BinarySearchLowerBound`
  (from `TopFragmentExtractor.FindClosestPeakInWindow`) 554 s own = ~71%. Xcorr preprocessing only ~6%.
  -> separate future work: per-spectrum m/z lookup table (bucket -> first peak index, ushort, ~1-4 Th
  buckets, ~110 MB per file in flight at 1 Th) - same lower-bound index, byte-identical.
- **Stage 6** (`--task PerFileRescoring` on a 3-file Astral bed `D:\test\osprey-runs\astral-stage6bed`,
  `...-120642.dtp`): window-loop CPU 1,098 s; `HramStrategy.PreprocessWindowSpectra` 809 s (74%:
  `PreprocessSpectrumForXcorrSparse` 374 own + `ApplyWindowingNormalizationD` 282 own); candidate scoring
  (`ScoreCandidate`) 46 s; window decode (`GetCalibratedWindow`) 239 s.

Xcorr coverage (temporary diagnostic, 3 Astral files; raw counts):

| Pass | Window caches | Spectra preprocessed | Spectra used by xcorr |
|---|---|---|---|
| Stage 6 re-score | 501 | 607,500 | 386,800 (63.7%) |
| Stage 6 gap-fill, finding missing peaks | 499 | 605,067 | 30,370 (5.0%) |
| Stage 6 gap-fill, imputed boundaries | 371 | 449,638 | 11,099 (2.5%) |
| Stage 6 total | 1,371 | 1,662,205 | 428,269 (25.8%) |
| PerFileScoring | 501 | 607,500 | 555,547 (91.4%) |

Stage 6 makes three passes; each pass rebuilds (decodes + preprocesses) every window it visits. On-demand per
pass: 428,269 preprocessings (25.8% of today). A cache kept across all 3 passes: between 386,800 and 428,269
(23.3-25.8%) - so on-demand alone captures nearly all of it; the remaining cross-pass cost is the window decode
(~3x per window). Percentages must be pooled from raw counts (passes have different denominators).

## Change (commit 0acf90c078)
- `WindowXcorrCache` (ResolutionStrategy.cs): HRAM ctor takes the window's spectra, scorer and a scratch rented
  for the window's lifetime; `Sparse[]` starts empty.
- `HramStrategy.PreprocessWindowSpectra`: no up-front loop; `ReleaseWindowCache` returns the scratch (called
  from a finally in CoelutionScorer).
- `HramStrategy.ScoreXcorr`: `Sparse[i] ??= Scorer.PreprocessSpectrumForXcorrSparse(Spectra[i], Scratch)`.
  One window = one thread (candidates scored in sequence), so no lock. Preprocessing only reads the spectrum
  and clears its scratch, so order cannot change values. Unit resolution keeps its eager path.

## Gates so far
- [x] 647/647 unit tests, inspection 0
- [x] `regression.ps1 -Dataset Stellar` PASSED - but Stellar is UNIT resolution and does not exercise this path
- [x] Astral 3-file A/B (warm), old = #4767 exe `D:\test\osprey-runs\_bin\coldreads-pr4767`, new =
  `D:\test\osprey-runs\_bin\lazyxcorr-wip1`: all 3 `.scores.parquet` and all 9 Stage 6 outputs byte-identical.
  Stage 6 84.3 -> 64.6 s (-23%). PerFileScoring 244.8 / 241.0 / 241.1 s old vs 252.2 / 251.1 / 241.0 s new:
  inconclusive (expected gain <1%).
- [ ] Paired SEA-AD PerFileScoring A/B (positions 1-10, warm, new/old/new/old; per-file
  `[TIMING] Coelution scoring`): running 2026-10-04 18:43 -> ~20:06. Runs 1-2: new 1,180.1 s vs old 1,187.4 s.
  Report: `python C:\proj\ai\.tmp\sessions\20260930-night\lazypaired_report.py`.
- [ ] Astral regression golden (TeamCity Perf/Regression runs it; locally `regression.ps1 -Dataset Astral`)
- [ ] /code-review, PR, TeamCity Windows + Linux + Perf/Regression

## Decision recorded
Brendan (2026-10-04): keep on-demand for all xcorr use unless the paired A/B shows it slows PerFileScoring;
he does not expect a benefit for PerFileScoring with this library, but it could matter with a smaller one.

## Next PR (start after this one): window-major Stage 6
Stage 6's three passes each sweep all windows, so each window is decoded 3x (`GetCalibratedWindow`, 239 s of
the profile) and its cache rebuilt. `RunGapFillTwoPass` (PerFileRescoreTask.cs:3549): gap-fill targets come
from the file's targets before the re-score; the forced pass scores the CWT pass's misses at pre-imputed
boundaries - no cross-window dependency found, so the three passes could run per window with ONE decode and one
on-demand cache, provided outputs are reassembled in today's order (pass-major, then window; the gap-fill block
is already sorted by EntryId). Verify there is no cross-window step between passes before restructuring.

## Progress Log

### 2026-10-04
- Profiles, coverage measurement, change, Astral A/B as above. Paired SEA-AD A/B running at handoff.

**Next session handoff**: For detailed startup protocol, read `ai/.tmp/handoff-20261004_osprey_lazy_xcorr_preprocess.md` before starting work.
