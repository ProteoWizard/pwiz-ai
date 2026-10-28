# TODO-20261005_osprey_perfilescoring_round2.md

## Branch Information
- **Branch**: `Skyline/work/20261005_osprey_perfilescoring_round2` (`C:\proj\pwiz-scanmajor`)
- **Base**: `Skyline/work/20260612_net8_port` (PR #4619), branched at dfcb8d17ef (#4777)
- **Created**: 2026-10-05
- **Status**: Completed
- **PR**: [#4781](https://github.com/ProteoWizard/pwiz/pull/4781) (merged 2026-10-06)
- **Module**: `osprey`
- **Follows**: `ai/todos/completed/TODO-20261004_osprey_mz_lookup.md` (#4770),
  `ai/todos/completed/TODO-20261005_osprey_scan_major.md` (#4779),
  `ai/todos/completed/TODO-20261004_osprey_lazy_xcorr_preprocess.md` (#4768)

## Objective

PerFileScoring is still the longest task in an Osprey run. A new round of profiling on the current port branch
(with #4768, #4770, #4779 merged) to find what remains, then pick the next byte-identical reduction.

## Where PerFileScoring stands (2026-10-05)

| PerFileScoring, warm, i9-14900K | port before #4770 | after #4770 | after #4779 |
|---|---|---|---|
| Astral 3 files, wall (median) | 245.8 s | ~166 s | ~135 s (-45% total) |
| Astral coelution scoring (3-file sum) | 168.9 s | ~106 s | ~81 s |
| Astral calibration scoring (3-file sum) | ~48 s | ~33 s | ~27 s |
| SEA-AD 10 files, wall (paired) | ~1,170 s | ~865 s | ~720 s (-38% total) |

All changes were data-identical (`ai/scripts/Osprey/Compare-ScoreParquets.py`). Memory: private peak unchanged.

## Last profile (Astral file 49, before the calibration scan-major commit; thread-summed own time)

dotTrace summary `ai/.tmp/sessions/20261004-night/scanxic-profile.log` (in those summary tables the FIRST
number is own ms, the SECOND total ms). ScoreWindow total 716 s thread (was 1,561 s before #4770, 1,046 s after).
Top own: `MzBucketIndex.LowerBound` 138 s (now the bulk of XIC/prefilter lookup cost, compute-bound),
`HasTopNFragmentMatch` 78 s (mostly calibration; calibration went scan-major after this profile),
`SgWeightedSweep.ComputeCosineAtScan` 52 s, `ExtractXicsScanMajor` 46 s, `PreprocessSpectrumForXcorrSparse` 44 s,
`CwtPeakDetector.Convolve` 42 s, `SpectraWindowIndex.LoadWindowSerialRead` 40 s. Earlier profiles:
`ai/.tmp/osprey-profile-20261004-114448.dtp` (baseline), `mzlut-profile.log`, `scanmajor-profile.log`.
Also notable: library load + decoy generation ~7-9 s wall per process start.

## Ideas already on the table
- Merge-walk instead of lookups: sort a block's fragment targets by m/z and walk each spectrum once in step with
  them - removes `LowerBound` calls (the scan-major XIC agent's suggestion).
- SG cosine sweep / apex calculators still binary-search (`XcorrCalculators.cs:200`, `ApexMatchCalculators.cs`,
  `SpectralScorer.HasMatch`) on spectra that already have a bucket index.
- Hoist the index fetch out of the per-fragment loop in `HasTopNFragmentMatch` (~3%).
- `MzBucketIndex` memory: +4 B/peak in flight; ushort / fewer buckets if memory ever matters.
- Larger-scale: one RT-ordered sweep per file (Skyline's shape) and possibly no `.spectra.bin` - see the
  "Future direction" section of the scan_major TODO. Not for this round unless profiling points there.

## Constraints / direction (Brendan)
- Byte/data-identical output is the gate (Stellar + Astral regression tests, `Compare-ScoreParquets.py`).
- Scan-major is the direction for all data types (mirrors Skyline). Future timsTOF support uses 3D spectra
  (m/z, IM, intensity) and window groups - do not deepen the Thermo-only window assumptions.

## Progress Log

### 2026-10-05
- Created at handoff after #4779 merged.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20261005_osprey_perfilescoring_round2.md` before starting work.

### 2026-10-05 (evening) - tip profile
Skyline nightlies were running on the box: read proportions, not absolute seconds.
- Profiled Astral file 49 at the tip (snapshot `pr4779-b85e9b010f`), warm cache. Data recreated as hard links in
  `D:\test\osprey-runs\astral`. Files in `ai/.tmp/sessions/20261005-pfs2/`: `tip-profile.log`,
  `tip-profile-report.xml`, `children.py` (direct-callee breakdown from the report's call stacks), `warm2.log`.
- Warm wall, 55.6 s: library + decoys 6.8 s (12%), RT calibration 11.4 s (20%), coelution 29.7 s (53%),
  dedup + parquet write ~7 s (13%).
- Coelution thread time (ScoreWindow 755 s = 100%): ExtractXicsScanMajor 189 s (25%; LowerBound is now inlined into
  it, so its 175 s own time is the lookups), SgWeightedSweep 208 s (27%: ComputeCosineAtScan 73 s, xcorr
  preprocess first touch 57 s), TukeyMedianPolish 78 s (10%; NanMedian 43 s), CWT 76 s (10%; Convolve 45 s),
  prefilter 50 s (7%).
- Cheap identical candidates found in code: `ComputeCosineAtScan` binary searches (not the bucket index) and
  allocates two Lists per call; `NanMedian` allocates a List per call and Compute allocates `oldResiduals` every
  iteration (scratch buffers + the same sort keep values identical).
- Calibration: `LoadWindowSerialRead` is 155 of 298 s calibration thread time, mostly lock wait. A/B
  `OSPREY_SERIAL_WINDOW_READS=0`, 3 interleaved reps (`serialread-ab.log`): calibration 11.5-12.3 s -> 10.0-10.4 s
  (-1.3 s, non-overlapping), total ~-1 s. Serial reads exist for cold spinning disks, so not a default flip.

### 2026-10-05 (late) - median selection + cosine sweep
- Brendan pointed at Skyline's linear-time median (`QNthItem`, Hoare's FIND, `Skyline/Util/Util.cs`). Ported as
  `Osprey.Core/MedianMath.cs` (`MedianInPlace`, `SelectInPlace`, double spans; even counts take the max of the
  lower partition instead of a second select). `TukeyMedianPolish.NanMedian` copies finite values into one
  per-Compute scratch and selects there; `oldResiduals` allocated once per Compute, not per iteration.
- `SgWeightedSweep.ComputeCosineAtScan`: bucket-index lower bound (`Spectrum.MzLowerBound`) instead of binary
  search; sums accumulated in the loop in the same order, no per-call Lists.
- New `TestMedianSelectionMatchesSort` (bitwise vs sort, n = 1..64, ties, sorted/reversed). Debug gate: 655/655,
  inspection 0/0.
- Data identity: 3 of 3 Astral `.scores.parquet` identical to the baseline (`Compare-ScoreParquets.py`;
  baseline = `port-dfcb8d17ef` output in `D:\test\osprey-runs\astral-ab-warmup`).
- Profile shares of ScoreWindow (nightlies running, so timing A/B abandoned; `compare-profiles.py`):
  ComputeCosineAtScan 9.6% -> 4.7%, Tukey Compute 10.4% -> 7.1%, NanMedian 5.7% -> 2.1%. XIC extraction
  unchanged at ~25% (LowerBound is attributed separately or inlined depending on the JIT; read them together).
- Snapshots: `D:\test\osprey-runs\_bin\port-dfcb8d17ef` (baseline), `median-wip1` (this change).
- Not changed: `CwtPeakDetector.SmallMedianInPlace` (about 6 values per call; selection may not beat Array.Sort).

### 2026-10-06 (night session) - PR #4781
- Committed 50068fef61. `/code-review max`: no correctness findings (its harnesses re-verified bit-identity);
  fixed doc overclaims (FIND is linear on average, quadratic worst case), reused
  `TopFragmentExtractor.FindClosestPeakInWindow` in the cosine kernel, removed dead `oldRow`, shifted 16 doc line
  refs (38a4ef6862). Triage notes: `ai/.tmp/sessions/20261005-pfs2/review-triage.md`.
- After the review fixes: gate 655/655 + inspection 0/0; regression Stellar PASS, Astral PASS (all modes).
- PR #4781 opened against the port branch; TeamCity Perf/Regression 4203270 on `pull/4781` (38a4ef68), Agent 1:
  queued 01:17, ran 05:52-06:33, SUCCESS ("Osprey regression PASSED", all four datasets).
- Next round candidates, by size: RT-ordered XIC blocks (XIC extraction ~25% of ScoreWindow; each spectrum is
  re-read once per 512-candidate library-order block, ~36x per window - an estimate, measure first); redundant
  second median polish per scored candidate (~1.6%); HasMatch / ApexFragmentMatchSet still binary-search
  (~1-2%); per-fragment terms recomputed across the 5 SG offsets (~1%); CWT SmallMedianInPlace (~1.8%, A/B).
- Noted, not changed: ComputeCosineAtScan's 1e-12 norm guard vs Rust's 1e-10 (pre-existing; only synthetic
  intensities < 1e-20 reach it).

### 2026-10-06 - Merged

PR #4781 merged into the port branch as commit 213b66b9de. Shipped: MedianMath (Hoare's FIND, ported from
Skyline's QNthItem) for the Tukey median polish medians, and the SG-weighted cosine kernel moved to the m/z
bucket index with in-loop accumulation - data-identical output, cosine kernel 9.6% -> 4.7% and NanMedian
5.7% -> 2.1% of ScoreWindow thread time. Deferred to a next round (no issues filed): RT-ordered XIC blocks
(XIC extraction still ~25% of ScoreWindow), the redundant second median polish per candidate, the remaining
binary searches in HasMatch / ApexFragmentMatchSet, per-fragment terms across the SG offsets, and the CWT
small median. Also pending from Brendan: an end-to-end SEA-AD timing on the port tip.
