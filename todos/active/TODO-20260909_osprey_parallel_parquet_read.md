# TODO: Parallel parquet row-group decoding (read-side counterpart to #4652)

## Branch Information
- **Branch**: `Skyline/work/20260909_osprey_parallel_parquet_read`
- **Base**: `a9ee510ada` (the parallel-WRITE branch, pre-merge) - **needs `git merge origin/master`** before anything else; master has since taken #4652 and #4680, both of which touch `ParquetScoreCache.cs` and the bundled `ParquetNet.dll`
- **Created**: 2026-09-10 (night session), TODO written 2026-09-17
- **Status**: Implemented, gate green at the time, benchmarked, NOT merged from master, NOT reviewed, no PR
- **Module**: `osprey`
- **PR**: none
- **Worktree**: `D:\Users\brendanx\proj\pwiz-parqread` (pushed to origin 2026-09-17; the worktree is disposable once merged)

## What it does

#4652 made Osprey COMPRESS a row group's columns in parallel. This makes it DECODE
row groups in parallel - the same file, the other direction.

Commit `0401012ede`, "Made parquet row-group decoding run in a bounded read pipeline":

* One shared helper, `ReadRowGroupsPipelined<TGroup>(path, leadReader,
  leadFieldsByName, decode)`, yields `(GroupIndex, Columns)` in strict file order.
  **All 8 row-group loops** in `ParquetScoreCache` now go through it - `grep
  RowGroupCount` matches only the helper. `ReadFdrEntryGroup` was split into
  `DecodeFdrEntryColumns` (parallel) + `MaterializeFdrEntryGroup` (serial).
* Degree 1 reuses the caller's ALREADY-OPEN reader - literally today's code path,
  not a lookalike - so `OSPREY_PARQUET_READ_THREADS=1` is a true A/B.
* Degree N spawns N workers, each owning its own `FileStream` + `ParquetReader`
  (`FileShare.Read`), claiming row-group indices with `Interlocked` under a
  `SemaphoreSlim(N)` whose slot is taken BEFORE the index - that ordering is both
  the memory bound (at most N groups resident, counting the one being consumed)
  and the deadlock-freedom argument. Workers are `TaskCreationOptions.LongRunning`
  because Stage 6 calls these loaders from inside a `Parallel.For`.
* Process-wide `ParquetDecodeGate = SemaphoreSlim(ProcessorCount)`, held only
  while decoding, so `--parallel-files` x read threads cannot oversubscribe.
* **The parallel/serial cut is BELOW the row loop.** Materialization, the running
  `ParquetIndex` counter, the skip rule, and `Canonicalize`/interning all stay on
  the consuming thread. `LibraryStringInterner` writes an unsynchronized
  `Dictionary` when unfrozen, so this is what keeps every caller's contract
  unchanged. No fork change needed or made.
* Worker exceptions rethrow on the consumer via `ExceptionDispatchInfo`; the
  iterator's `finally` cancels and joins, so an abandoned enumeration leaves no
  reader holding the file.

### Tests
`IOTest.TestParquetPipelinedRowGroupRead` - one `[TestMethod]`, degrees 1/2/4/8
over a 6-row-group file: every reader compared against its own degree-1 result
including `ParquetIndex`; the `score_index`-absent counter checked against an
explicit expected numbering under a `keepEntry` filter; the reconciled
`score_index`-present path; worker-exception propagation; abandonment + delete.

Gate at commit time: build + 603 tests + ReSharper 0/0. **Must be re-run after
the master merge.**

### Benchmark (written, opt-in, run once on a quiet-ish box)
`ParquetReadPipelineBenchTest.ParquetRead_ColdWarmAndDegrees`, enabled by
`OSPREY_BENCH_SCORES=<a real .scores.parquet>`. 1.68 GB file, 72 cores:

```
scalars degree 1 pass1/pass2 : 2.30 s / 1.16 s   (ratio 1.98 -> cold pass was disk-bound)
scalars  deg 1/2/4/8/16      : 0.75 / 0.46 / 0.25 / 0.17 / 0.15 s
stubs    deg 1/2/4/8/16      : 2.73 / 0.86 / 0.58 / 0.57 / 0.47 s
working set (stubs)          : 1.87 GB @1 -> 2.17 GB @4 -> 2.29 GB @16
```

3.0x (scalars) / 4.7x (stubs) at degree 4 for +0.3 GB. Only pays on cached data;
cold reads are disk-bound. Run it with `-SourceRoot` pointed at the worktree or
`Build-Osprey.ps1` builds `proj\pwiz` instead.

## Honest sizing - do not oversell this

Reading is roughly **3-4% of an 82-file run**, not the ~9% first estimated: the
1,037 s "Scoring 353M entries" phase is mostly SVM scoring, and reading 82 files'
stub columns is only ~220 s. A 3-4.7x decode speedup saves perhaps 400-600 s of
a 4h29m run. Worth landing because it is cheap and needs no fork change, and
because the two FDR stages (where reading happens) are now 29% of the par4 run and
did not scale at all under `--parallel-files`. It is NOT a second 1.74x.

## Open before a PR

1. **`git merge origin/master`** and resolve - #4652 and #4680 both changed
   `ParquetScoreCache.cs`. Then re-run the pre-commit gate.
2. **Default degree 4 is a GUESS, not a measurement.** It multiplies the resident
   row-group working set 4x per open file, and Stage 6 reads FULL row groups
   (blobs included) inside a `Parallel.For`. Measure with `--timestamp --memstamp`
   + `ai/scripts/perfviz.py` against `ai/docs/memory-band-guide.md` before
   adopting. Consider 2 as the default if memory is tight.
3. Sweep the bench on a SMALL parquet too (a few row groups): each worker
   re-parses the footer, so degree>1 stops paying somewhere. Find the crossover.
   The `Math.Min(degree, rowGroupCount)` guard only catches the 1-group case.
4. `regression.ps1 -Dataset Stellar` and `-Dataset Astral` (output must be
   byte-identical - this changes nothing written, so goldens should not move).
5. `/code-review max` from the worktree, then PR with `osprey` label.

## Latent, pre-existing, out of scope (noted while here)
The CLR treats `int[]` and `uint[]` as cast-compatible, so an Int32 `entry_id`
column decodes straight through `ReadColumnByName`'s `as uint[]`. `StreamEntryIds`'
doc comment claiming a column "written at another width" lands on the null branch
is only true from Int64 up. Not changed.

## Provenance
Implemented by a sub-agent during the 2026-09-09 night session from a design
brief; the brief was wrong in two places the agent corrected (a footer precompute
of `rowIndex` that could not reproduce the skip rule; a "row group missing
entry_id" test case that is not constructible because a `DataField`'s CLR type is
schema-wide). The parent session independently traced the helper's slot protocol,
deadlock-freedom, signal accounting and teardown and found no defect. Full
narrative was in `ai/.tmp/sessions/20260909-night/job3-parallel-parquet-read.md`
(gitignored; may be gone).
