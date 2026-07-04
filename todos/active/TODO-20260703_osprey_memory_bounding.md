# TODO-20260703_osprey_memory_bounding.md -- Bound Osprey peak memory on large multi-file runs

> An ~80-sample DIA search OOMs a 96 GB box (memory 100%, SSD 100% pagefile, CPU
> ~29%). Peak memory scales O(N) with sample count because every file's heavy
> `FdrEntry` arrays -- already spilled to `scores.parquet` -- stay resident until
> Stage-5 compaction. Port the Rust "shrink-after-spill + rehydrate" so an 80-file
> Astral run fits in **64 GB** with **byte-identical** output.

## Branch Information

- **Branch**: `Skyline/work/20260703_osprey_memory_bounding`
- **Base**: `master` (`d032f5978`)
- **Created**: 2026-07-03
- **Status**: In Progress
- **GitHub Issue**: [#4355](https://github.com/ProteoWizard/pwiz/issues/4355)
- **PR**: (pending)

## Problem (evidence)

- Real run `Y:\2026-05-SEA-AD-Pilot-MTG\Carafe-Osprey\carafe_log.txt` (via Carafe): 82
  Astral files, `File parallelism: 1` (sequential), 3.2M-entry library. Stopped mid
  per-file scoring at file 55/82.
- Host: 96 GB RAM. Symptom: RAM 100% + SSD 100% + CPU ~29% == memory exhaustion ->
  Windows pagefile thrashing (threads blocked on page faults). Target: **64 GB**.
- Because parallelism == 1, only one file's spectra are resident. The blowup is NOT
  spectra; it is the accumulating results buffer.

## Root cause (from 3 code probes + Rust comparison)

- All N files' `FdrEntry` objects accumulate in one shared buffer
  (`PerFileScoringTask._perFileEntries`) held until Stage-5 compaction; peak = end of
  Stage 4 (all N resident, pre-compaction).
- **Dominant term:** each retained `FdrEntry` still carries heavy arrays already
  written to parquet and reloadable -- `Features`, `CwtCandidates`, `FragmentMzs`,
  `FragmentIntensities`, `ReferenceXicRts`, `ReferenceXicIntensities`
  (`FdrEntry.cs:59-104`). They are never nulled after `WriteScoresParquet`
  (`ProcessFile` returns them as-is). ~N x the full heavy per-entry set stays resident.
- The C# port kept the Rust per-file spill-to-parquet but NOT the Rust struct
  downsizing (`CoelutionScoredEntry` ~940 B -> `FdrEntry` stub ~128 B after spill).
- Compounding: `--parallel-files` free-RAM guard budgets only per-file *spectra* bytes,
  not the growing results buffer (`PerFileRescoreTask.cs:558-566`).
- Not a leak: no undisposed streams/SQLite, no sample-keyed static caches, spectra are
  per-file locals; the buffer is reclaimed at compaction and run end.

## Disk symptom (secondary)

- Mostly pagefile thrashing (memory). Plus an independent contributor: score parquets
  are staged in local `%TEMP%` (SSD) then cross-volume `File.Move`d to the NAS
  (`ParquetScoreCache.cs:262-290, 455-480`) -- unlike `FileSaver`, which stages a
  sibling temp in the destination dir.

## Fix plan (phased, ordered by impact/risk)

**Phase 0 -- Instrument & measure the baseline.**
- Add `ProfilerHooks.LogMemoryStats` calls in the per-file scoring loop and around
  `CompactFirstPass` / the join boundary. Run a subset that does not OOM (e.g. 15-20
  files) to get the per-file GB slope; confirm the linear climb + drop-at-compaction
  signature and quantify the dominant term. This is the yardstick for every later phase.

**Phase 1 -- Drop heavy arrays after the parquet spill (the O(N) killer).**
- Enumerate the heavy `FdrEntry` fields that are (a) already persisted to parquet and
  (b) reloadable. For each, map EVERY downstream consumer (Stage-5 compaction,
  `FirstJoinTask`/Percolator, `ConsensusRts`, `MergeNodeTask`/blib, `PerFileRescoreTask`)
  and confirm it either does not need the array or rehydrates it from parquet
  (`RescoreHydration`).
- Null those arrays on each retained stub immediately after `WriteScoresParquet`; add
  rehydration where a consumer needs them. Port of the Rust tiered downsizing.
- Delicate: a consumer that reads a nulled array = silently WRONG output, not a crash.
  The regression gate is the safety net; consider a debug guard that a nulled field is
  never read without rehydration.

**Phase 2 -- Parallelism RAM accounting.**
- Make the `--parallel-files` free-RAM guard budget the accumulating results buffer, not
  just spectra, so K reflects true peak RAM. Independent, low risk.

**Phase 3 -- Parquet temp staging (SSD win).**
- Stage the `scores.parquet` temp beside the destination (mirror `FileSaver`), not
  `%TEMP%`. Removes the cross-volume copy + direct SSD traffic. Independent, small.

**Phase 4 (only if Phase 1 falls short of 64 GB) -- Stream the join.**
- Stream Percolator scoring from per-file parquet instead of holding all entries
  (Rust #5/#3); fix the Stage-7 `O(passing x N)` pre-size (`MergeNodeTask.cs:482`).
  Larger; gate on measurement.

## Success criteria / gates

- [ ] ~80-file Astral search peaks **< 64 GB** (measured via `ProfilerHooks`).
- [ ] `Build-Osprey.ps1 -RunTests -RunInspection` green.
- [ ] `regression.ps1 -Dataset Stellar` (and `All` before merge): **byte-identical**
      output vs golden (this is a scoring-pipeline change -- mandatory).
- [ ] `Test-PerfGate.ps1`: no speed regression (rehydration adds I/O -- watch it).
- [ ] SSD no longer saturated by parquet staging.

## Risks

- **Rehydration completeness** -- the one that can bite: a missed consumer reads a nulled
  array and produces wrong FDR silently. Mitigate: explicit per-consumer audit +
  regression gate + optional debug assertion.
- **Reload cost** -- rehydrating from parquet is extra I/O; keep it only where needed;
  verify with the perf gate.
- **Library baseline** -- 3.2M-entry library is a separate fixed cost; only address if
  Phase-0 measurement shows it dominates after Phase 1.

## Cross-reference: Rust techniques (frozen oracle at `D:\GitHub-Repo\maccoss\osprey`)

The 10 techniques inventoried from the archived Rust impl; C# already has per-file
spectra freeing + spill + `XcorrScratchPool` + streaming blib. The gaps that matter
here: #1 (free results per file) and #2 (shrink struct after spill) -- Phase 1; the
parallelism/accounting -- Phase 2. Streaming Percolator (#5) -- Phase 4 if needed.

## Phase 1 design (from the rehydration audit, 2026-07-03)

Heavy `FdrEntry` fields + verdicts (all persisted by `ParquetScoreCache.WriteScoresParquet`
and reloadable by `ParquetIndex`):
- **5 blob fields** (`CwtCandidates`, `FragmentMzs`, `FragmentIntensities`,
  `ReferenceXicRts`, `ReferenceXicIntensities`) -- **no in-memory consumer** after the
  per-file write (Stage 6 CWT loads from parquet via `CwtCandidateLoader`; blib fragments
  come from the library, not these). Safe to null. The bulk of the memory.
- **`Features`** (double[21]) -- one in-memory consumer: Stage-5 first-pass Percolator
  (`FirstJoinTask.RunFdr` -> `PercolatorEntryBuilder`). Stage 7 reloads from parquet.
- **Landmine:** `ReconciledParquetWriter.ApplyRescoredRows` uses `Features == null` as the
  "not rescored, keep parquet row" sentinel -> invariant `Features-null <=> blobs-null`.
  Breaking it silently overlays empty blobs into the reconciled parquet.

3-site implementation (null all six; matches the existing warm-path contract):
1. After `WriteScoresParquet` (`PerFileScoringTask.cs:~1307`, before `return` at ~1314):
   null all six on each entry -> stub shape.
2. Before Stage-5 Percolator (`FirstJoinTask` before `RunFdr`): bulk-reload `Features` per
   file via `ParquetScoreCache.LoadPinFeaturesFromParquet` + bind by `ParquetIndex` (reuse
   `Pass2FdrSidecar.MapFeaturesByParquetIndex` / `LoadJoinOnlyScores`).
3. After first-pass + protein FDR, before Stage 6: re-null `Features` (mirror
   `FirstJoinTask.cs:431-433`) so the sentinel invariant holds.

**Percolator refinement (confirmed in code):** C# ALREADY subsamples training to 300K
(`PercolatorConfig.MaxTrainSize = 300000`, `PercolatorFdr.cs:115`; `BuildTrainingSubset`).
So training memory is bounded, same as Rust. The Stage-5 watermark is the **score** pass:
`RunFdr` holds the full `IList<PercolatorEntry>` and a dense `n x nFeatures` matrix
(`PercolatorFdr.cs:254`) over ALL entries. Rust streams the score pass from per-file
parquet and never materializes that. => **Phase 4, if needed, streams the SCORING (not the
trainer)** + drops the separate dense `stdFeatures` copy. Phase 0 measurement decides.

## Progress log

- 2026-07-03: Diagnosed via 3 code probes (C# memory, C# disk/temp, Rust techniques) +
  the live Carafe log. Filed issue #4355, created branch + this TODO. Root cause = O(N)
  heavy-array retention; not a leak.
- 2026-07-03: Rehydration audit complete (per-field verdicts + 3-site design above);
  confirmed the 300K training subsample is already ported (Stage-5 lever is streaming the
  score pass). Dataset confirmed: 82 SEA-AD Astral files at `Y:\...\project_mzML`.
  Implementing Phase 0 (ProfilerHooks) + Phase 1 next.

## Handoff prompt

Fixing O(N) memory in Osprey multi-file runs (issue #4355). Root cause: heavy `FdrEntry`
arrays already spilled to parquet stay resident for all N files. Start at Phase 0
(instrument + measure baseline), then Phase 1 (null-after-spill + rehydrate, audit every
consumer of `Features`/`CwtCandidates`/`Fragment*`/`ReferenceXic*`). Gate on
`regression.ps1` (byte-identical) + a `ProfilerHooks` measurement showing <64 GB for ~80
files. Rust reference (frozen) at `D:\GitHub-Repo\maccoss\osprey`.
