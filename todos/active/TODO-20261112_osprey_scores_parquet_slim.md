# Stop writing non-scoring data no reader needs to Osprey .scores.parquet

## Branch Information
- **Branch**: `Skyline/work/20261112_osprey_scores_parquet_slim`
- **Base**: `master`
- **Created**: 2026-11-12
- **Status**: In Progress
- **GitHub Issue**: [#5023](https://github.com/ProteoWizard/pwiz/issues/5023)
- **Module**: `osprey`
- **PR**: (pending)

## Objective

Each Osprey `<run>.scores.parquet` written by PerFileScoring is ~37% non-feature data, much of it with no
production reader. On SEA-AD Astral (82 runs, split-sized library, #4950 settings) about 30% of every scoring
parquet can be removed or moved without losing information. Each byte is written once, read ~1.7x by
FirstPassFDR and again by PerFileRescoring (whose reconciled writer streams every column), so each byte saved
is ~3-4x its size in I/O per run. PR targets `master`; #4950 takes it by merge.

Measured file (UW25): `..._A01_005.scores.parquet`, 4,403,242 rows, 3.89 GB compressed / 7.00 GB uncompressed.
`cwt_candidates` 12.6%, `fragment_mzs`+`fragment_intensities` 10.5%, `reference_xic_*` 6.9%.

## Tasks

- [x] Stop writing `fragment_mzs` / `fragment_intensities` (verbatim library spectrum; joinable by `entry_id`)
- [x] Write `reference_xic_*` only when a consumer asks (`--training-export`) - developer decision 2026-11-12
- [~] Move `cwt_candidates` to its own per-run file - NOT done: no visible gain (see audit)
- [x] Reconciled writer stops copying the dropped/moved columns into `.scores-reconciled.parquet`
- [ ] Record PIN features at column granularity (belongs on #4950: `PinFeatureMask` is not on master)
- [ ] *(Option, after measuring)* Normalize identity columns against the library by `entry_id`

## Verification

- [ ] Regression goldens byte-identical (`regression.ps1`, `regression-parallel.ps1 -Dataset All`)
- [ ] Confirm every reader of each column before removing it (round-trip tests, diagnostics, generic copies)
- [ ] `SubsetPipelineTest` and the training export pass
- [ ] SEA-AD measurement: per-file parquet size, PerFileScoring write time, FirstPassFDR / PerFileRescoring bytes read

## Regression Test

- **Test name**: (filled in once written)
- **Test project**: OspreySharp.Test
- **Fails on master**: n/a (size/IO change; goldens prove outputs unchanged)
- **Passes on fix**: (pending)

## Progress Log

### 2026-11-12 - Session Start

Started on MACS2 in `D:\Users\brendanx\proj\pwiz`, branch from origin/master 829aee74b6.

**Reader audit on master (829aee74b6), by symbol and by column name:**
- `fragment_mzs` / `fragment_intensities`: no production reader. `FdrEntry.FragmentMzs` was set
  by `CoelutionScorer.BuildFdrEntry`, written, then nulled (`PerFileScoringTask`,
  `PerFileRescoreTask.ReleaseRescoredPayload`); only `LoadFullFdrEntries` decoded it, and that
  has test callers only. Removed end to end (fields, scorer copy, writer, reader).
- `cwt_candidates`: read only from `.scores.parquet` (`CwtCandidateLoader` ->
  `LoadCwtCandidatesFromParquet`, `ProbeCwtRowMetadata`). Nothing reads it from
  `.scores-reconciled.parquet` (Stage 7 reads stubs/features/scalars; the rescore resume arm
  reads stubs). So the reconciled write stops copying it, and the Stage 6 streamed read of
  Stage 4 stops decoding it (`FdrRowColumns.NoCandidates`).
- **Moving `cwt_candidates` to its own file buys ~nothing**: `BlockReadStream` skips untouched
  column-chunk gaps over 1 MB (a 100k-row group's CWT chunk is ~11 MB), so FirstPassFDR never
  reads it today; the only re-reads were Stage 6's copy, now gone. Not done (no visible gain).
- `reference_xic_*`: **held, design conflict.** Read by the training export from the
  reconciled parquet, re-scored rows included. The export is pay-later by design (P16:
  `--training-export` added to a finished analysis re-scores nothing), so writing the XIC only
  when the export is requested would force Stage 4 + 6 re-scoring for that path. Developer
  decision needed.
- Column-level PIN feature recording: `PinFeatureMask` exists only on #4950
  (`Skyline/work/20261028_osprey_diann_fdr_gap`), not master - belongs on #4950.

**Gates so far:** `Build-Osprey.ps1 -Configuration Debug -RunTests -RunInspection` 656/656 pass,
inspection clean. `regression.ps1 -Dataset Stellar` PASSED
(`ai/.tmp/sessions/20261112-5023/regression-stellar.log`).

### 2026-11-12 - SEA-AD A/B (3 files, paired ABAB, MACS2 otherwise idle)

Matched files A01_005, A06_010, A10_014; split-sized r=1.0 library; Run-SeaAd defaults; fresh per
arm; 36 threads. master = 829aee74b6 (`_bin\master-829aee74b6`), slim = branch WIP
(`_bin\slim5023-wip`). Script `ai/.tmp/sessions/20261112-5023/ab-slim.ps1`; runs in
`D:\Users\brendanx\test\osprey-runs\sea-ad\runs-slim5023\`; per-task times from
`ab_summary.py` (task end = its `[PATH] ... block reads` marker).

| arm | total | PerFileScoring | FirstPassFDR | PerFileRescoring | SecondPassFDR |
|---|---|---|---|---|---|
| master01 | 660 s | 330 s | 148 s | 129 s | 54 s |
| slim01 | 553 s | 263 s | 140 s | 97 s | 53 s |
| master11 | 603 s | 273 s | 149 s | 127 s | 54 s |
| slim21 | 564 s | 272 s | 138 s | 102 s | 52 s |

- **PerFileRescoring -22%** (128 -> 100 s), consistent in both pairs. FirstPassFDR -6% (149 -> 139 s),
  also consistent though its bytes read are identical. SecondPassFDR unchanged.
- PerFileScoring: master01 is a cold-start outlier (its calibration pass 1 took 17.6 s vs 5-9 s);
  the second pair is 273 vs 272 s. Per-file parquet write 17.6 -> 16.2 s mean (-8%).
- Total: -11.6% on means, but -6.5% on the second pair alone; Stages 5-7 alone -12% (330 -> 291 s).
- **Bytes read** (`[PATH] block reads`, parquet): PerFileRescoring 13.5 -> 7.9 GB (-41%; Stage 6 reads
  the Stage 4 file more than once); FirstPassFDR 3.8 GB both; SecondPassFDR 1.0 GB both. Whole run
  25.0 -> 19.4 GB read (-22%).
- **Disk** (3-run TOTALS, not per run): `.scores.parquet` 5,571 -> 4,382 MB (-21.3%),
  `.scores-reconciled.parquet` 1,152 -> 580 MB (-49.7%), whole run dir 8,249 -> 6,488 MB (-21.3%):
  ~0.59 GB/run, ~48 GB at 82 runs, ~262 GB at 446.
- **Results identical**: every blib result table (RefSpectra, peaks, proteins, retention times,
  source files) hashes equal across all four arms; only LibInfo (creation time) and LibMetadata
  `osprey.command` (output dir) differ.
- On #4950's 109-feature files the same bytes are a smaller share (UW25's 3.89 GB file: fragments
  10.5%, CWT 12.6%).

### 2026-11-12 - Reference XIC written only for the training export

Developer decision: `reference_xic_*` has one reader, `TrainingEvidence.AlignReference` (the
training export, i.e. Carafe fine-tuning data), so it is worth breaking the export's pay-later
property (doc 00 P17 rule 2) to stop carrying it on every run. Implemented:
- `ParquetScoreCache.WritesReferenceXic(config)` (= `TrainingExport.Enabled`) gates the columns in
  both writers; `ReferenceXicValidityKeySuffix` (`;refxic`, empty without the export) is appended
  to the PerFileScoring and PerFileRescoring keys. FDR task keys unchanged.
- Adding `--training-export` to an analysis that ran without it now re-runs PerFileScoring and
  PerFileRescoring; FirstPassFDR/SecondPassFDR skip. Exports byte-identical to up-front ones
  (`TestSubsetTrainingExport`). The export-only arm stays, for an export-enabled analysis
  missing only exports (now asserted in `AssertFailedExportIsRetriedAlone`).
- `LoadTrainingExportRows` refuses a file without the XIC columns (would silently export rows
  with no reference otherwise).
- P17 in doc 00 records the exception and says the next optional product must not take it by
  precedent; docs 22 and 14 updated.
- Metadata projection (3-file master run): XIC is 0.519 of 5.571 GB Stage 4 (9.3%) and 0.111 of
  1.152 GB reconciled; with the earlier cuts, per run ~0.80 GB saved (Stage 4 -30.7%, reconciled
  -59%), ~65 GB at 82 runs, ~355 GB at 446.

Gates: Debug tests 656/656, inspection 0 warnings. Running `regression-parallel.ps1 -Dataset All`
then a second SEA-AD pair (`ai/.tmp/sessions/20261112-5023/gate-and-ab2.ps1`, log
`gate-and-ab2.log`).

### 2026-11-12 - Full regression + SEA-AD pair 2 (fragments, reconciled CWT and reference XIC removed)

`regression-parallel.ps1 -Dataset All`: **49 PASS / 0 FAIL** in 42:03
(`ai/.tmp/sessions/20261112-5023/regression-all.log`). Then master 829aee74b6 vs
`_bin\slim5023-xic`, same 3 files and settings as pair 1, ABAB (`gate-and-ab2.ps1`, runs
`masterr3/slimxicr3/masterr4/slimxicr4` in `runs-slim5023\`).

| arm | total | PerFileScoring | FirstPassFDR | PerFileRescoring | SecondPassFDR |
|---|---|---|---|---|---|
| masterr3 | 605 s | 272 s | 146 s | 131 s | 54 s |
| slimxicr3 | 551 s | 257 s | 146 s | 91 s | 55 s |
| masterr4 | 625 s | 293 s | 148 s | 128 s | 54 s |
| slimxicr4 | 577 s | 273 s | 147 s | 100 s | 54 s |

- Total wall 615 -> 564 s (**-8.3%**); **PerFileRescoring 130 -> 96 s (-26%)**; FirstPassFDR and
  SecondPassFDR unchanged (pair 1's FirstPassFDR -6% did not reproduce); PerFileScoring -6%, noisy.
- Per-file scores parquet write 18.4 -> 15.4 s mean (-16%).
- Parquet bytes read: PerFileRescoring 13.5 -> 6.9 GB (-49%); whole run 25.0 -> 18.4 GB (-26%).
- Disk (3-run totals): `.scores.parquet` 5,571 -> 3,862 MB (-30.7%), reconciled 1,152 -> 469 MB
  (-59.3%), run dir 8,249 -> 5,858 MB (-29.0%). **Per run 2.75 -> 1.95 GB, -0.80 GB**: ~65 GB at 82
  runs, ~355 GB at 446. (Measured; matches the metadata projection.)
- Results: every blib table except LibInfo/LibMetadata hashes `fef0c2039041138e` in all 8 arms of
  both pairs.
