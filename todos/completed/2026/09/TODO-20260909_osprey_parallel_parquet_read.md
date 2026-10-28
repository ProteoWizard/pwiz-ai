# TODO: Parallel parquet row-group decoding (read-side counterpart to #4652)

## Branch Information
- **Branch**: `Skyline/work/20260909_osprey_parallel_parquet_read`
- **Base**: **must be stacked on PR #4751** (`Skyline/work/20260929_Net10_Parquet6`, Parquet.Net 6.1.0) - see the 2026-10-01 section at the END. The 2026-09-30 rebase onto `ed25627d81` (`b9c380515e`) is superseded.
- **Created**: 2026-09-10 (night session), TODO written 2026-09-17
- **Status**: **Closed 2026-10-04 - NOT implemented (parked).** The CHS measurement on the i9 (PR #4765) showed cold FirstPassFDR reads are seek-bound, not decode-bound, so the fix that shipped was planned, gated span reads (`BlockReadStream`, now the default) instead. Branch `b9c380515e` stays on origin, unported. See "2026-10-04: DECISION" at the top.
- **Module**: `osprey`
- **PR**: none
- **Worktree**: `D:\Users\brendanx\proj\pwiz-parqread` (pushed to origin 2026-09-17; the worktree is disposable once merged)

## 2026-10-04: DECISION - parked, not ported. Why, with the numbers.

Measured on the i9 (i9-14900, 64 GB, one HDD) during PR #4765, CHS cohort, cold, `[PATH]` buckets
(full tables in `ai/todos/completed/TODO-20260926_osprey_firstpassfdr_parallel.md`):

* **Cold reads are seek-bound, not decode-bound.** 128 files, 1 lane: the pass 2 parquet walk read ~9 GB
  in 246 s (~36 MB/s against ~200 MB/s sequential) - about 200 small column-chunk reads per file across
  36 row groups. The same walk warm costs ~0.8 s/file vs ~2.2 s/file cold, so decode is the minority of
  the cost this branch would parallelize.
* **The FDR lanes already decode several files at once** in FirstPassFDR, which covers what intra-file
  row-group parallelism would buy there.
* **On one spindle it makes the access pattern worse.** N readers per file x L file lanes interleaves more
  seeks; ungated 4 lanes already made the cold training load 69% slower than 1 lane (468 vs 277 s). The
  branch's own benchmark says it "only pays on cached data".
* **What shipped instead (#4765):** `BlockReadStream` reads each row group's touched column chunks as one
  span, planned from the footer, under a process-wide disk gate, decoding concurrently on the lanes.
  CHS 446 files: FirstPassFDR 8,717 s vs 17,145 s same-day baseline, byte-identical. On the SSD the gate
  did not hurt (1,124 s vs 1,155 s at 3 lanes, 128 files).

**When to revisit (not the HDD low-bar machine):** an SSD or warm-cache machine, where reads are cheap
and lanes kept scaling (SSD 6 lanes 15% faster than 3) - intra-file decode parallelism is most plausible
there; and stages the lanes do not cover (PerFileRescoring hydrate, SecondPassFDR), which were NOT measured.
A revisit should re-port onto the async-first Parquet.Net 6 read surface and decode from buffers that the
planned span reads already fetched, not open N readers per file.

## 2026-10-03: what the i9 should decide

**State.** #4751 (Parquet.Net 6.1, built from `maccoss-developers\skylinedev\Parquet.Net6` via
`Shared\Lib\Parquet\ParquetNet.targets`) merged into the port branch as `e60a58be42`. This
branch is pwiz-only - `b9c380515e` touches `ParquetScoreCache.cs`, `IOTest.cs` and the new
`ParquetReadPipelineBenchTest.cs`, and uses only the public read API, so it needs NO change in
any Parquet.Net fork (the old `skylinedev\Parquet.Net` 4.25 checkout is write-side history and
can be ignored). The re-port onto 6.1 will conflict across ~800 lines of `ParquetScoreCache.cs`,
whose read surface is now async-first and wrapped.

**Origin is current.** Brendan force-pushed `b9c380515e` over the pre-rebase `0401012ede`
(stacked on `a9ee510ada`, which landed as #4652), so the i9 can check the branch out directly.

**A new reason the prize may have shrunk.** The FDR lanes work (PR #4765,
TODO-20260926_osprey_firstpassfdr_parallel.md) now decodes several FILES concurrently in
FirstPassFDR, which overlaps most of what decoding row groups in parallel within one file buys
there. The serial-decode case that remains is a single large file, or any stage still reading
files one at a time.

**Measure before porting - the #4765 CHS sweep already produces the data.** Its pass 0/1/2
`[PATH]` lines carry the `parquet walk` bucket (summed over lanes) next to the pass wall clock.
From the CHS 446-file `-Task FirstPassFDR` arms:
* walk share of pass wall at lanes-1 (the serial ceiling this branch could attack), and
* the same at lanes-4: if the walk is no longer on the critical path once files overlap, this
  branch is worth little in FirstPassFDR.
* The walk is the one SUPERLINEAR bucket (3.27x for 2.04x rows at 8->16 files), so only a
  measurement at 446 files settles it; do not extrapolate from 8.
* Also look at the stages the lanes do NOT cover (PerFileRescoring hydrate, SecondPassFDR) for
  serial single-file reads.

Decide: port onto the port branch (expect the conflict above), or park this branch with the
numbers recorded.

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

## 2026-10-01: this branch must be STACKED ON PR #4751 (Parquet.Net 6). Do not PR it onto the tip.

Brendan, 2026-10-01: the read work has to sit on top of **PR #4751**, where Nick upgrades to
current Parquet.Net for the .NET 10 port. We were only on the old version because 4.25.0 was
the most recent release we believed we could use with .NET 4.7.2 - that constraint is gone with
the port, so the pin goes away.

**This supersedes the 2026-09-30 rebase onto `ed25627d81`.** That rebase
(`b9c380515e`, backup ref `backup/pre-rebase-20260930`) is still useful as a record of which
upstream *behaviour* changes the read code has to honour - `RequireCharge` (#4680), the 6-arg
`ReadFdrStubScalars` + mandatory `StubColumns`, `TryReadEntryIdsAndApexRts` deleted for
`ReadApexRtsByParquetIndex`, `StreamReconciledScoresParquet` gaining `taskName`, the RESX
strings - but the mechanical rebase will have to be redone on #4751.

### PR #4751 (`Skyline/work/20260929_Net10_Parquet6`, nickshulman, OPEN)

Base is the port branch. Head `df01fa50e3`, 4 commits off merge base `553a145871`, and
**5 commits behind `ed25627d81`**. `ed25627d81` is NOT an ancestor of it.

What it changes in this area (merge base -> head, so this is #4751's own work):

```
pwiz_tools/Osprey/Osprey.IO/ParquetScoreCache.cs      | 433 +++-
pwiz_tools/Osprey/Directory.Build.targets             |  58 +-
pwiz_tools/Osprey/Osprey.IO/Osprey.IO.csproj          |  14 +-
pwiz_tools/Osprey/Osprey.Test/Osprey.Test.csproj      |  18 +-
pwiz_tools/Osprey/Osprey.Test/IOTest.cs               |  22 +-
ParquetNet.dll (751104) DELETED; Parquet.dll (743936) ADDED
IronCompress / Snappier / ZstdSharp / System.Text.Json / nironcompress / ... DELETED
ParquetNet.xml -> Parquet.xml;  new ParquetNet.targets (53 lines)
```

It does **not** touch `regression.ps1` or the `PeakDigest.tsv` goldens. (An earlier read of
mine suggested it did; that was an artifact of diffing `ed25627d81..df01fa50e3` across a
divergence instead of from the merge base. The goldens are safe.)

### Why the collision is structural, not textual

In Parquet.Net 6, **`ParquetReader` is only `IAsyncDisposable`**. #4751 therefore introduces

```csharp
private sealed class SyncParquetReader : IDisposable   // holds a ParquetReader
    public int RowGroupCount => _reader.RowGroupCount;
    public ParquetRowGroupReader OpenRowGroupReader(int index) => _reader.OpenRowGroupReader(index);
private static SyncParquetReader OpenReader(Stream stream)
    => new SyncParquetReader(RunSync(ParquetReader.CreateAsync(stream)));
```

and replaces every `using (var reader = RunSync(ParquetReader.CreateAsync(stream)))` site with
it, re-typing `BuildFieldLookup` and `ReadFdrEntryGroup` to take `SyncParquetReader`.

`RowGroupCount` and `OpenRowGroupReader` are **exactly** the two members this branch's design
confines to `ReadRowGroupsPipelined` - that confinement is the branch's stated invariant and
the thing `grep RowGroupCount` was used to verify. So the two changes meet in the same file, in
the same methods, on the same two API members.

Worse for the port than a type rename: this branch's degree-N path gives **each worker its own
`FileStream` + `ParquetReader`**. On #4751 that becomes N `SyncParquetReader`s created AND
disposed async-over-sync (`RunSync`) on `TaskCreationOptions.LongRunning` threads. #4751's own
PR body records that Parquet.Net 6 "awaits the footer write without `ConfigureAwait(false)`"
and deadlocked on a WinForms thread, and that the fork's `byte`/`sbyte`/`short`/`ushort`
encoders "returned their pooled buffer before encoding from it and so were unsafe to run
concurrently". Both are write-side, but they establish that this fork has had
`ConfigureAwait` and concurrency-safety gaps - a read-side pipeline running N concurrent
readers deserves the same scrutiny rather than an assumption.

### RE-ESTABLISH THE BENCHMARK BEFORE RE-PORTING ~800 LINES

The branch's premise is that serial row-group decode is the bottleneck, and it was
**benchmarked on Parquet.Net 4.25.0 - a library that this PR replaces wholesale.** A major
version can change decode throughput and internal parallelism. So the first step on top of
#4751 is not the port, it is a measurement: with #4751 alone, is row-group decode still the
bottleneck, and how much is there to win?

If it is, port it. If Parquet 6 narrowed the gap, the ~800 lines and the N-reader concurrency
risk may no longer pay for themselves - and that is a much better thing to learn from a
one-hour measurement than from a completed port.

A cheap way to take that measurement exists already: the night of 2026-09-30/10-01 added
`[PATH]` per-file cost buckets to the FirstPassFDR passes (commits `154219f399` /
`b8524ef1dc` on `Skyline/work/20260930_osprey_pass2_runq_reuse`), and the `parquet walk`
bucket is the decode cost. On a quiet box it read 6.7-7.4 s per pass at 8 files, and it is the
one bucket that scales SUPERlinearly in file count (3.27x for 2.04x rows), so measure it at
the file count you care about.

### Sequencing

Both branches are unpushed and neither has a PR, so nothing is locked in yet.

* **Preferred: let #4751 land first, then re-port onto the updated port branch.** It avoids the
  stacked-PR trap the version-control guide documents: when the parent squash-merges, the
  child's merge base falls back and both sides re-introduce the parent's whole content, so the
  child conflicts with a master that moved by one commit.
* If the read work must proceed before #4751 merges, develop it on a branch off
  `df01fa50e3` and open the PR with `--base Skyline/work/20260929_Net10_Parquet6`, then
  `git merge` the port branch once #4751 is in - **merge, never rebase**, once a PR exists.
* Either way, the gates must be re-run on the new base. The Stellar regression that went green
  on 2026-09-30 was green against `ed25627d81`'s build and goldens, not #4751's.

### The DLL question is now moot

The 2026-09-30 session concluded "keep the tip's `ParquetNet.dll` (751104, re-bumped by #4680);
the branch carries no binary change". True at the time and no longer relevant: #4751 **deletes**
`ParquetNet.dll` and its companion DLLs, adds `Parquet.dll` (743936), renames the XML docs, and
moves consumers onto a `ReferenceParquetNet=true` targets mechanism. There is no longer a
vendored `ParquetNet.dll` for this branch to have an opinion about.

### 2026-10-01: that measurement is DONE. The premise survives Parquet 6.

Built `df01fa50e3` (#4751 head) with the three FirstPassFDR commits cherry-picked on top
(`65283f6dc1` / `154219f399` / `b8524ef1dc`), so **both sides of the comparison carry the same
code and the only variable is the Parquet library**. Saved as branch
`nightlywork/4751-parquet6-instr` @ `6c8ba03c04` in `pwiz-parqread`; that worktree has been
restored to its own branch and `backup/pre-rebase-20260930` is intact.

Two useful by-products before the number:

* **#4751 builds here** - `Build succeeded in 77.3s`. Nick's private `skylinedev/Parquet.Net6`
  fork restores without any feed trouble on this machine, and the shipped assembly is
  `Parquet.dll`, 743936 bytes, **FileVersion 6.1.0.0**.
* **The two lines of work compose.** The three FirstPassFDR commits cherry-picked onto #4751
  with no conflict at all - they touch `PercolatorScorer.cs` / `PercolatorEngine.cs` /
  `FdrProjectionOutput.cs` / `FirstPassFdrTask.cs` / `FdrTest.cs`, and #4751 touches
  `ParquetScoreCache.cs` / `IOTest.cs` / the csproj+targets. The collision is specific to the
  READ-pipeline branch, not to the FirstPassFDR work.

#### The decode cost, 8 files / 33,459,602 rows, quiet box

| bucket | Parquet 4.25 (`ed25627d81`) | Parquet 6.1 (#4751) | |
|---|---|---|---|
| pass 1 `parquet walk` | 6.7 s | **8.4 s** | +25% |
| pass 2 `parquet walk` | 7.4 s | **8.2 s** | +11% |

**Parquet 6 decode is slightly SLOWER, not faster.** So the upgrade does not dissolve the
problem this branch solves - serial row-group decode is still worth parallelising, and the
port remains justified in principle.

#### Do not read the other buckets as a comparison

`q-assign` reads 62.4 s here against 79.2 s on 4.25, but that is **not** controlled: the 79.2 s
run carried the per-row sink and peptide timers that `b8524ef1dc` removes and which are absent
here, and the mdiag state and run-to-run variance differ. Only the walk was set up as a
like-for-like. For the record, the rest came in at run-q sort 36.1 s (against 37.3), 
score+competition 18.2 (18.9), clamp floors 7.9 (9.8), sidecar write 5.3 (5.4), sidecar load
2.8 (2.8) - all within noise of the 4.25 figures, which is the expected result for a change
that touches only the parquet layer.

#### Still size it at the real file count before porting

The walk is the **one superlinear bucket** - 3.27x for 2.04x rows on 4.25 (6.7 s at 8 files,
21.9 s at 16). So 8.4 s at 8 files does not scale to 82 by multiplication, and the prize could
be a lot bigger than a naive x10.55 suggests, or differently shaped. Measure the walk on #4751
at the file count that matters before committing to re-porting ~800 lines of N-reader
concurrency onto a reader surface that is now async-first and wrapped.

(The run's version stamp reads `26.1.1.268` because `-LinkFrom` pins
`OSPREY_VERSION_OVERRIDE` from the source run. That is expected and not a wrong build; the
`Parquet.dll` 6.1.0.0 check above is what confirms which library ran.)

#### Bonus, and worth passing to Nick: Parquet 6 reads the existing parquet bit-identically

Same experiment, extra check. The two runs differ ONLY in the Parquet library (identical Osprey
code: `65283f6dc1` + `154219f399` + `b8524ef1dc` on both sides), same 8 input
`.scores.parquet`, same `-LinkFrom` source:

```
1st-pass FDR sidecars: 8 bins per side, SHA256 mismatches = 0
  -> BYTE-IDENTICAL between Parquet.Net 4.25.0 and 6.1.0
```

Row counts agree exactly too - `33,459,602 peaks (16,807,902 targets, 16,651,700 decoys,
21 features)` on both.

So on the Osprey READ path the 6.1.0 fork decodes the existing files to the same values, and
everything downstream of it in FirstPassFDR lands on the same bytes. That is independent
corroboration for **#4751** at 33M-row scale on real SEA-AD data, which is broader than its own
test plan (regression subsets, `TestParquetRoundTripScalarStress`, the BiblioSpec DIA-NN tests)
- worth handing to Nick as supporting evidence.

`FirstPassFDR:done (672.7s)` on Parquet 6. **Do not compare that against the 450-485 s figures
from 4.25**: it ran 07:57-08:08, by which time other users were active again, and only the
`[PATH]` walk buckets were set up as a controlled comparison.
