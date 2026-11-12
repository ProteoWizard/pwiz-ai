# Recompute CWT candidates in PerFileRescoring instead of storing them in Osprey .scores.parquet

## Branch Information
- **Branch**: `Skyline/work/20261112_osprey_cwt_recompute`
- **Base**: `Skyline/work/20261028_osprey_diann_fdr_gap` (#4950, stacked)
- **Created**: 2026-11-12
- **Status**: In Progress
- **GitHub Issue**: [#5024](https://github.com/ProteoWizard/pwiz/issues/5024)
- **Module**: `osprey`
- **PR**: (pending)

## Objective

`cwt_candidates` is ~0.54 GB per SEA-AD run (the largest column group left after #5023), but the
Stage 6 planner reads ~0.7% of its rows (~30k of ~4.3M per run: consensus, passing, apex outside
tolerance) and only 3 of the 6 values per candidate. Planning already runs per run in
PerFileRescoring just before the rescore. Recompute the candidates there for the consulted rows
and stop writing the column - with candidates identical to Stage 4's, so goldens do not move.

## Tasks

- [ ] Diagnostic: recompute candidates for consulted rows in PerFileRescoring, compare field by
      field with the stored lists (opt-in). SEA-AD 3 files + regression datasets. Gate: 0 mismatches.
- [ ] Planner uses recomputed candidates; Stage 4 stops writing `cwt_candidates`
- [ ] Remove `CwtCandidateLoader`, `LoadCwtCandidatesFromParquet`, `ProbeCwtRowMetadata`,
      range validation, the column
- [ ] Goldens byte-identical (`regression-parallel.ps1 -Dataset All`), `SubsetPipelineTest`
- [ ] SEA-AD A/B: disk, PerFileScoring write, PerFileRescoring time

## Regression Test

- **Test name**: (pending - the diagnostic's comparison, then the goldens)
- **Test project**: OspreySharp.Test / regression
- **Fails on master**: n/a (storage change; goldens prove outputs unchanged)
- **Passes on fix**: (pending)

## Progress Log

### 2026-11-12 - Session Start

Working in `D:\Users\brendanx\proj\pwiz-nightbase` (MACS2), branched from #4950 head e2ea35f0cc.
Developer chose to stack on #4950 because its CoelutionScorer changes are not expected to move
again. Overlap with #5023 (targets master, same ParquetScoreCache writer code): #5023 should be
merged into #4950 before this lands, or this branch merges it in.

**Code map (read-only audit of this branch, 2026-11-12; nothing run yet):** bit-identical
recompute looks feasible - every Stage 4 input is on disk.
- Stage 4 chain: `CoelutionScorer.ScoreCandidate` -> `PeakDataExtractor.TryExtract` (non-override
  path) -> `CaptureCwtCandidates` -> stable descending rank-score sort, truncated to
  `Reconciliation.TopNPeaks` (5) -> `BuildFdrEntry`. Window: Stage 3 RT calibration,
  MAD = `rtCalibration.Stats().MAD`, `SearchWindowHalfWidth(...)`, sigma max(5*1.4826*MAD, 0.1),
  `OSPREY_LOCAL_RT_TOLERANCE`; fragment tolerance from ms2Cal SD; spectra (RT, scan) sorted.
- No cross-precursor dependency (per-candidate context cleared); dedup only drops rows.
- Catch: a precursor in two overlapping isolation windows is scored per window and dedup keeps
  one row; the window is not stored -> identify it from the apex `ScanNumber`.
- Stage 6 has no call that reproduces it: re-pick/forced rows are rescored as boundary overrides
  (no CWT) with the REFINED calibration. Recompute must use the Stage 3 calibration, and spectra
  load after planning today (`LoadSpectraForRescore` follows `PlanRun`).
- The planner reads only Apex/Start/End RT and list order (candidate index into
  `.reconciliation.json`); Area/SNR/CoelutionScore are read by nothing.
- Risks: wrong window choice, `refined` vs Stage 3 calibration, OSPREY_* drift between stages,
  `OSPREY_LOAD_CALIBRATION`, demux-cache vs `.spectra.bin`, `OSPREY_REF_XIC=corr` (candidate
  apex/area depend on which peak won).

Diagnostic (`OSPREY_CWT_RECOMPUTE_CHECK=1`, compare recomputed vs stored for every non-Keep row)
being implemented by a sub-agent in pwiz-nightbase; status in `ai/.tmp/agent-cwtcheck-status.md`.

### 2026-11-12 - Diagnostic built; bit-identical on the subsets and on SEA-AD

Sub-agent implemented `OSPREY_CWT_RECOMPUTE_CHECK=1` in pwiz-nightbase (uncommitted):
`ScoringPipeline.ApplySearchSettings` (pure code motion out of `RunCoelutionScoring`),
`CoelutionScorer.SortWindowSpectra` / `WindowRetentionTimes` (code motion) and the new
`RecomputeCwtCandidates` entry point (Stage 4's own TryExtract + CaptureCwtCandidates, Stage 3
calibration), `Osprey.Tasks\CwtRecomputeCheck.cs`, called in `RescoreOneFile` after the mass
calibrations load; `[BISECT] cwt-recompute-check` summary + `cwt-recompute-mismatch` examples.
Enabled in four existing SubsetPipelineTest legs (Stellar/Astral parallel, both HPC chains) with
`AssertCwtRecomputeAgrees`. Gate 691/691, inspection clean
(`ai/.tmp/sessions/20261112-cwtcheck/full-gate3.log`). Subsets: 368/368 rows exact, all six
fields; HPC workers (JSON-loaded calibration) identical. Negative control (refined calibration
instead of Stage 3): 81/82 and 92/94 rows mismatched - the check discriminates.

**SEA-AD** (#4950 head + diagnostic, `_bin\cwtcheck-4950`; A01_005/A06_010/A10_014, split-sized
r=1.0 library, defaults, fresh; `D:\Users\brendanx\test\osprey-runs\sea-ad\runs-cwtcheck\`):

| run | rows | stored candidates | exact | mismatches |
|---|---|---|---|---|
| A01_005 | 30,296 | 109,597 | 30,296 | 0 |
| A06_010 | 30,225 | 104,915 | 30,225 | 0 |
| A10_014 | 30,332 | 112,386 | 30,332 | 0 |

90,853 rows / 326,898 candidates, all six fields exact; no ambiguous or missing windows, no
apex-scan differences, no uncalibrated runs. The gate for the production change is met.

Caveats for the production change: the recompute reads the process's OSPREY_* settings (must
match Stage 4's; pin or key them); runs whose Stage 3 calibration failed used a FallbackRtMap
that is not persisted; the check reloads each consulted precursor's windows (~one extra pass
over the spectra cache) - the production version should share the rescore's window loads.
Also: `Build-Osprey.ps1 -TestName 'A|B'` matches nothing and still prints "All tests passed"
(comma-separated is the supported form) - worth a script fix.

### 2026-11-12 - Production change (uncommitted in pwiz-nightbase, on 8396e56c76)

8396e56c76 = merge of #5025 into this branch (conflicts in `WriteFields` / `BuildFdrEntryColumns`
resolved as #4950's recorded-feature columns + #5025's conditional blobs; `;refxic` added to #4950's
PerFileScoring key override; 3 #4950-only test calls given `writeReferenceXic: false`). Gate 691/691.

Sub-agent production change, gate 684/684 (codec + loader tests removed), inspection clean
(`ai/.tmp/sessions/20261112-cwtcheck/gate-p2c.log`); 41 files, +655/-1623:
- `FilePlanner.PlanFile` takes a `CwtCandidateSource` delegate; a first pass applies the existing
  predicates (consensus, passing, then the Keep test `IsAtExpectedRt`), the source is called once
  with the moved entries, `DetermineAction` runs in the same order. Production source:
  `CwtCandidateRecompute.ForRows` (first-pass calibration, `ApplySearchSettings` on a config clone,
  `CoelutionScorer.RecomputeCwtCandidates`), window = holds the precursor m/z and the apex scan,
  lowest index on a tie.
- `RescoreRunSpectra`: spectra index / MS1 / mass calibrations loaded lazily once per run, shared by
  PlanRun and RescoreOneFile. Candidate windows are an EXTRA read (planning precedes the rescore's
  target list); not yet timed.
- **Premise corrected:** a run whose Stage 3 calibration failed IS planned (the refit does not need
  it), so the recompute rebuilds Stage 4's `FallbackRtMap` (Calibrator's range/mapping code moved
  to `RtRangeMapping`, pure motion). Not exercised end to end (could not make Stage 3 fail on the
  subset); a no-RT-model run in a task chain planned identically.
- Removed: `cwt_candidates` (write + read), `LoadCwtCandidatesFromParquet`, `ProbeCwtRowMetadata`,
  `CwtCandidateLoader` + Stage6Planner range validation, `CwtCandidateCodec`, `FdrEntry` /
  `CoelutionScoredEntry.CwtCandidates`, 7 resource strings (en/ja/zh-Hans), the diagnostic.
- Keys: every setting that shapes the candidates is already in the base key (search hash,
  `PickValidityKeySuffix`, `xic=`); `OSPREY_LOAD_CALIBRATION` was keyed nowhere - added
  `LoadCalibrationValidityKeySuffix()` to PerFileRescoring's key (Stage 4's gap predates this).
- Subset A/B pre-change exe vs new (`D:\Users\brendanx\test\cwt-recompute\`): `.reconciliation.json`
  identical for all 5 runs, reconciled parquets + FDR sidecars byte-identical, blib tables identical;
  `.scores.parquet` 219 -> 127 KB (Stellar), 178 -> 116 KB (Astral).
- Docs 00 (relay checklist: planning reads `.spectra.bin`), 03, 05, 06, 10, 11, 14, 15, 19, DIVERGENCES.

Regression `-Dataset All`: 49 PASS / 0 FAIL in 59:16 (`ai/.tmp/sessions/20261112-5023/regression-all-5024.log`).

### 2026-11-12 - SEA-AD 3-file A/B: #4950 head vs this stack

ABAB in `D:\Users\brendanx\test\osprey-runs\sea-ad\runs-stack5024` (libdecoy, protein-compact;
caches read from E:; exe snapshot `_bin\stack-5024`; log `ai/.tmp/sessions/20261112-5023/gate-and-ab3.log`).
The base arm is #4950 with #5025 merged, so this measures #5024 alone.

| Per run | #4950 + #5025 | + #5024 | Change |
|---|---|---|---|
| `.scores.parquet` | 1.857 GB | 0.751 GB | -60% |
| `.scores-reconciled.parquet` | 0.384 GB | 0.156 GB | -59% |
| Both scores files | 2.241 GB | 0.907 GB | -1.33 GB (-60%) |
| Whole run directory (3 runs) | 8.25 GB | 4.25 GB | -48% |

| Wall (s) | base p1 | base p2 | stack p1 | stack p2 |
|---|---|---|---|---|
| PerFileScoring | 389 | 271 | 241 | 240 |
| FirstPassFDR | 154 | 151 | 148 | 148 |
| PerFileRescoring | 132 | 131 | 90 | 89 |
| SecondPassFDR | 58 | 55 | 53 | 53 |
| Total | 737 | 611 | 535 | 534 |

- base p1 ran first after the regression on a cold page cache; its PerFileScoring (389 s) is the
  outlier. Against base p2: total -12.6% (611 -> 534 s), PerFileScoring -11% (smaller write),
  PerFileRescoring -32% (131 -> 89 s): the recompute's extra spectra reads cost less than the
  `cwt_candidates` read they replace.
- Blib: every data table identical across all four runs (only LibInfo / LibMetadata, which carry
  the creation time, differ).
- At 82 runs: ~109 GB less; at 446 (CHS): ~595 GB less.
