# TODO: --parallel-files uses static contiguous buckets, not a shared work queue

## Branch Information
- **Branch**: not started
- **Base**: `Skyline/work/20260612_net8_port` (PR #4619)
- **Created**: 2026-09-30
- **Status**: Observed and measured on a live 82-file run; no code written
- **Module**: `osprey`
- **PR**: none

## Observation

Brendan, reading the live progress line of an 82-file `--parallel-files 4` run:

```
[2026/09/30 19:17:06]  [14] 68%  [33] 37%  [53] 29%  [72] 83%
```

> "It is unlike Skyline which would show 4 files in sequence with new files being pulled
> from a queue. This looks like the files get divided into 4 buckets at the start and then
> each thread has its own queue. That is different and unexpected to a Skyline user."

Correct, and confirmed in code.

## Cause

`PerFileScoringTask.cs:364`:

```csharp
Parallel.For(0, config.InputFiles.Count, parallelOpts, fileIdx => ...)
```

`Parallel.For` over an index RANGE uses .NET's range partitioner, which hands each worker a
contiguous chunk rather than dispatching one item at a time from a shared queue. At 82
files and `MaxDegreeOfParallelism = 4` the lanes are observed to be
**1-20 / 21-41 / 42-61 / 62-82**, each marching through its own block.

**Nobody chose this** - it is the default behaviour of the construct.

### CORRECTION (observed later in the same run): it is COARSE-CHUNKED, not strictly static

At 75 of 82 files the lanes read `[40] 52%  [59] 80%  [79] 97%  [81] 76%`. The worker that
started on bucket 1-20 is now on file 40, and TWO workers are inside the 62-82 range. So
.NET's range partitioner DOES redistribute once a worker drains its chunk; the chunks are
merely coarse enough that for most of the run it presents as fixed buckets.

That weakens one argument below: a single pathological file does NOT strand a lane for the
whole run, only for the remainder of its current chunk. The user-visible surprise and the
coarse-granularity tail are still real. Corrected here rather than left standing, because
the first reading overstated the defect.

## It is NOT the 2026-09-30 throughput regression

Measured per-lane completion mid-run (50 of 82 done):

| lane | files | done |
|---|---|---|
| 1 | 1-20 | 14 |
| 2 | 21-41 | 13 |
| 3 | 42-61 | 12 |
| 4 | 62-82 | 11 |

A 14-vs-11 spread means a tail of roughly 3 files x ~2.3 min = **7-9 min on a 4.5 h stage,
about 3%**. Real, but it does not explain the separate ~2.7x PerFileScoring slowdown seen
on the current tip. **Do not conflate the two.**

## Why it is still worth fixing

* **This cohort is heterogeneous by construction.** The SEA-AD README records that file NAME
  order tracks ACQUISITION order with monotonic instrument degradation (files 1-40 pass a
  median ~27,000 targets vs ~19,000 for 41-82), and that the **7 pooled QC injections sort
  LAST** (positions 76-82). Contiguous buckets therefore hold systematically different
  populations - the lanes are not interchangeable samples, so imbalance is structural
  rather than random.
* **One pathological file strands an entire lane** while the other workers idle. Dynamic
  dispatch bounds that at one file.
* **It gets worse with scale and with HPC fan-out** - at 446 (CHS) and 1000+ files, static
  partitioning is the wrong default.
* **The progress display implies a queue the code does not have**, which is the surprise
  that prompted this.

## Fix

Replace the range partition with one-at-a-time dynamic dispatch:

```csharp
Parallel.ForEach(Partitioner.Create(0, config.InputFiles.Count, 1), parallelOpts, range => ...)
```

or an explicit work queue. Keep `MaxDegreeOfParallelism`.

## Gate

**Should be output-neutral**, so the standing byte-identical regression gate is the right
check and must pass unchanged:

* Per-file scoring is independent.
* The first-pass training reservoir keys on the file INDEX (`f`), not on completion order,
  so the sampled training set does not depend on scheduling.

Note this output-neutrality only became true once **#4706** fixed the `FrozenModelScorer`
shared-scratch-buffer race (`fcd59201a3`, 2026-09-28). Before that, concurrency DID leak
across files, and a scheduling change would have altered results. Verify, do not assume:
`regression.ps1 -Dataset Stellar`, then `regression-parallel.ps1 -Dataset All`.

## Both per-file stages have it - confirmed

The same construct appears in BOTH stages that scale with `--parallel-files`:

* `Osprey.Tasks/PerFileScoringTask.cs:364` - `Parallel.For(0, config.InputFiles.Count, parallelOpts, fileIdx => ...)`
* `Osprey.Tasks/PerFileRescoreTask.cs:982` - `Parallel.For(0, nTotalFiles, parallelOpts, fileNum => ...)`

So this is one pattern repeated twice, and the fix is a two-site change that benefits both
stages. Those two stages are 68% of an 82-file run's wall time (12,281 s of 17,960 s on the
2026-09-25 par3 measurement), so the tail they each leave is paid twice per run.

Worth noting when re-measuring concurrency: PerFileRescoring was 3.0% SLOWER at par4 than
par3 on 2026-09-26 (4,253.2 s vs 4,127.9 s). Different bucket boundaries give different
imbalance at different N, so static partitioning is one candidate explanation - but that
measurement is also contaminated by the `FrozenModelScorer` race, so it has to be
re-measured on fixed code before drawing any conclusion.
