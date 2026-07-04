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

## Progress log

- 2026-07-03: Diagnosed via 3 code probes (C# memory, C# disk/temp, Rust techniques) +
  the live Carafe log. Filed issue #4355, created branch + this TODO. Root cause = O(N)
  heavy-array retention; not a leak. Plan phased above.

## Handoff prompt

Fixing O(N) memory in Osprey multi-file runs (issue #4355). Root cause: heavy `FdrEntry`
arrays already spilled to parquet stay resident for all N files. Start at Phase 0
(instrument + measure baseline), then Phase 1 (null-after-spill + rehydrate, audit every
consumer of `Features`/`CwtCandidates`/`Fragment*`/`ReferenceXic*`). Gate on
`regression.ps1` (byte-identical) + a `ProfilerHooks` measurement showing <64 GB for ~80
files. Rust reference (frozen) at `D:\GitHub-Repo\maccoss\osprey`.
