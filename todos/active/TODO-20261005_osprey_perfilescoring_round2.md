# TODO-20261005_osprey_perfilescoring_round2.md

## Branch Information
- **Branch**: not started (create from `Skyline/work/20260612_net8_port` when there is code)
- **Base**: `Skyline/work/20260612_net8_port` (PR #4619), tip 01a3a9c5f6 (#4779) as of 2026-10-05 22:00
- **Created**: 2026-10-05
- **Status**: Not started - profile first
- **Module**: `osprey`
- **PR**: none
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
