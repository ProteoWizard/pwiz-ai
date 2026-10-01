# TODO: Parallelize FirstPassFDR - 86% of the stage is serial per-file work

## Branch Information
- **Branch**: `Skyline/work/20260930_osprey_pass2_runq_reuse` (worktree `pwiz-net10b`)
- **Base**: `Skyline/work/20260612_net8_port` (PR #4619), branched at `ed25627d81`
- **Created**: 2026-09-26
- **Status**: Item 1 IMPLEMENTED and committed (`65283f6dc1`), unit-green (628/628), awaiting
  the Stellar regression gate and a before/after stage measurement. **Item 1's size was
  mis-stated in the original analysis - see the 2026-09-30 section at the END.**
- **Module**: `osprey`
- **PR**: none

## Goal

`FirstPassFDR` is the only large stage that is completely flat in `--parallel-files`
(1.02x sequential->par4 on the 2026-09-10 sweep; measured again 2026-09-26 as
4,015.7 s at par3 vs 3,973.2 s at par4, -1.1%). At 82 files it is **22% of the run**
and, with PerFileScoring now scaling well, it and SecondPassFDR set the Amdahl floor.

Brendan's framing: the streaming rewrite took this stage from O(files) to O(1) resident.
Where memory is available, **O(1) -> O(C) for small constant C is still O(C)** and should
recover the parallel gains already proven for parquet read/write.

## Evidence it is CPU-bound, not I/O-bound

Measured from `seaad-82files-libdecoy-r1.0-protein-compactnet10port-par3/run.log`:

* **Pass 0 is a complete decode walk of all 82 parquet files and costs 92 s.**
* **Pass 1 does the same walk plus feature load plus scoring and costs 1,027 s.**

So ~900 s is compute layered on a 92 s I/O walk, and observed CPU during the stage was
**~2 cores of 72**. This is the opposite of the N=8 read-contention trap recorded in
`TODO-20260909_osprey_parallel_parquet_write.md`; there is real CPU headroom here.

## Where the 4,015.7 s goes (par3, 82 files)

| sub-step | time | % | per-file? |
|---|---|---|---|
| mdiag classify + pass 0 (full decode walk) | 112 s | 3% | yes, order-dependent |
| training-subset feature load, 82 files | 200 s | 5% | **yes** |
| train (3-fold CV, 10 iters, C sweep) | 43 s | 1% | no, global |
| **pass 1: score 353,085,961 entries** | **1,027 s** | **26%** | **yes** |
| **pass 2: assign q-values to 353,085,961 entries** | **1,163 s** | **29%** | **yes** |
| mdiag peak co-assignment | 103 s | 3% | partly |
| first-pass protein FDR | 159 s | 4% | global join |
| resolve protein q + persist stratum | 100 s | 2% | global join |
| FDRBench pass-1 input, 82 files | 182 s | 5% | **yes** |
| **compacting first-pass results, 82 files** | **889 s** | **22%** | **yes** |

**~3,461 s (86%) is per-file work running strictly serially.**

## Memory: O(4) does not raise the run's peak

FirstPassFDR private peak is **25.2 GB**; the run's peak is **46.8 GB** (PerFileScoring).
Per concurrent file: one `RowBuffer` (~30 B/row) plus its feature vectors
(nFeatures x 8 B/row), order of a few hundred MB to ~1 GB at ~4.3M rows/file. **O(4) adds
~3 GB and stays ~18 GB under the existing run peak.** The concurrency is free in memory
terms on any box that already runs the stage.

## Determinism - the merges are provably exact

Byte-identical output is the standing gate, and `Osprey.Test/FdrTest.cs:1242` already
asserts `RunStreamingFirstPass` is byte-identical. Pass 1
(`Osprey.FDR/PercolatorScorer.cs`, the `for f` loop under `Scoring {0} entries`) has
exactly FOUR pieces of cross-file state:

1. **`g1`, the global row ordinal.** Looks like a hard sequential dependency. It is not:
   **pass 0 has already counted every file's rows**, so `g1` is a **prefix sum computable
   up front**. This is the unlock.
2. **`streamingQ.Add`** (`StreamingFdr.StreamingFirstPassQ`, ~line 977). A max-reduction
   with strict `>` and first-seen-wins-ties. Given precomputed `g` that is associative and
   commutative: merge per-file partials by score desc, ties to lowest `g`. **Bit-exact.**
3. **`minRunBothByEntryId` / `minRunBothByPeptide`.** Min-reductions - exactly
   order-independent, no float-ordering concern.
4. **`contribAcc`.** The one to watch: floating-point sums. Merge per-file partials **in
   file order** to preserve addition order.

`ComputeStreamedScore`, `PercolatorQValues.ComputePerFileRunQvalues` and
`flushFileRunScope` are per-file and independent.

Pass 2 is easier: by then `pepByEntryId`, `expPrecByWinnerId`, `expPeptByPeptide` and
`expAggByEntryId` are **read-only**. Pure lookup + sink write.

## Work items, in the order worth doing

1. **Pass 2: read the v7 sidecar instead of re-decoding parquet a THIRD time** (1,163 s).
   Pass 1 already wrote each file's sidecar via `flushFileRunScope`, and
   `TryLoadCompletedScores` already exists. **No concurrency and no determinism risk** -
   the largest single win for the smallest change. (The in-code comment about "~7% the
   price of not relying on a distant invariant" concerns the apex-RT column specifically;
   the bigger cost is the whole re-decode.)
2. **Compacting first-pass results -> O(C)** (889 s). Biggest single block, per-file.
3. **Pass 1 -> O(C)** (1,027 s) with prefix-sum ordinals and the three exact merges above.
   The interesting one; do it after 1 and 2 prove the harness.
4. **Training-subset feature load and FDRBench pass-1 write -> O(C)** (382 s). Trivial.

Rough ceiling: item 1 plus ~3x on 4 lanes for 2-4 takes the stage from ~4,015 s to
**~1,600-1,900 s**, i.e. **~35-40 min off every 82-file run**, and makes FirstPassFDR
scale with `--parallel-files` for the first time.

## Gates

* `regression.ps1 -Dataset Stellar` then `regression-parallel.ps1 -Dataset All` - the only
  refactor gate is **byte-identical output**.
* `Test-PerfGate.ps1 -Dataset Stellar` for the perf half.
* An 82-file SEA-AD run to confirm the stage time actually moves; compare **full-run to
  full-run** (see the noise note below).

## Measurement note carried over

From `TODO-20260925_osprey_seaad_par3_net10port.md`: **full-run vs full-run stage times
reproduce to ~1%** (FirstPassFDR 4,015.7 s par3 vs 3,973.2 s par4), but a
**`-LinkFrom` isolated stage carries a systematic +10.1%** (4,422.2 s for the same stage).
Never compare a LinkFrom measurement against a full-run number.

## Incidental finding

The FDRBench pass-1 write (182 s) is **new since the 2026-09-10 reference** - #4661
(09-13) made `--fdrbench-pass both` actually emit pass 1. So today's FirstPassFDR does
182 s of work the reference never did and still came in faster (4,015.7 s vs 4,173.7 s).
Net of that the stage is ~8% quicker than the reference, not ~4%.

## 2026-09-30 night session: item 1 implemented, and its size CORRECTED

### Item 1 as originally written conflated two different costs

The work-item list above says:

> 1. **Pass 2: read the v7 sidecar instead of re-decoding parquet a THIRD time** (1,163 s).

That attributes the whole 1,163 s of pass 2 to the re-decode. It is not the re-decode, and
the re-decode is not 1,163 s. Three pieces of evidence, all from the code and the logs
rather than from a new experiment:

* **Pass 2 already reads the sidecar.** `TryLoadCompletedScores` was already being called
  at BOTH score-pass call sites (`PercolatorScorer.cs`, pass 1 and pass 2). On a cold run
  pass 1 writes each file's sidecar through `flushFileRunScope`, so by the time pass 2
  reaches that file the shortcut already fires: pass 2 was NOT reloading features or
  re-running the dot product.
* **A full decode walk of all 82 files is 43-92 s, not 1,163 s.** Pass 0 is a complete
  decode walk and the in-code comment at the pass-0 loop states "43s at 82 files"; the
  analysis above quotes 92 s for the same step. Either way it is a few percent of pass 2.
  The pass-2 comment in the source makes the same estimate in its own words - it calls the
  remaining walk "the ~7% ... price of not relying on a distant invariant".
* **Pass 2 is SLOWER than pass 1 while doing strictly less scoring work.** From
  `seaad-82files-libdecoy-r1.0-protein-compactnet10tip-par4/run.log`:
  pass 1 ("Scoring 353,085,961 precursor candidate peaks") 20:41:45 -> 21:05:55 = **1,450 s**;
  pass 2 ("Assigning q-values to 353,085,961 precursor candidate peaks") 21:05:55 -> ~21:36
  = **~1,830 s**. Pass 1 pays the feature load AND the SVM dot product; pass 2 pays neither.
  So pass 2's cost is overwhelmingly in work that is NOT decoding and NOT scoring.

### What the real redundancy is

Pass 2 recomputed `PercolatorQValues.ComputePerFileRunQvalues` - **a sort per file, 353M
rows across the cohort** - to re-derive the two run q-values that **pass 1 had already
computed and written into the v7 sidecar**. The sidecar record carries them
(`FdrScoreRecord.RunPrecursorQvalue` / `.RunPeptideQvalue`) and the reader materialized
them and then threw them away: `rec => onScore(rec.EntryId, rec.Score)`.

Why it looked free, which is the part worth keeping: the doc comment on
`TryLoadCompletedScores` justified recomputing as "a sort and costs nothing next to loading
a file's feature vectors and re-running the dot product". That comparison is sound on the
RESUME path it was written for. It silently carries over to fresh-run pass 2, where there
is no feature load and no dot product to weigh it against - so the sort is measured against
nothing and becomes the pass's dominant remaining cost. **A cost justification that names
what it is cheaper THAN stops being true when the thing it was cheaper than is removed.**

The determinism objection in that same comment ("rather than by trusting two writers to
agree") does not apply either: there is one writer. `FirstPassFdrTask.cs` states it
directly - "the score and both run q-values are final the moment that file's rows have been
walked, and no later phase revises them". Pass 2 is a reader, not a second writer.

### What was implemented (commit `65283f6dc1`)

* Added `CompletedScoreStreamer` (`Osprey.FDR/FdrProjectionOutput.cs`), replacing the
  `Func<string, Action<uint, double>, bool>` so a file's stored score arrives with BOTH run
  q-values instead of alone.
* `TryLoadCompletedScores` returns the two q-value arrays through `out` parameters, published
  only after the existing count check AND row-identity check both pass, so a rejected
  sidecar yields three nulls together.
* **Pass 2** uses them and sorts only a file that had no sidecar. **Pass 1 deliberately
  discards them** (`out _, out _`): it is the writer, the sort is what produces what it
  writes, and on a resumed file those values feed the global clamp-floor reduction, so the
  saving there would be confined to a resume while the blast radius would be global state.
  Pass 1's resume path is a possible follow-up, not part of this change.

### Verification

* **628/628 Osprey unit tests pass**, including every `SubsetPipelineTest` leg (resume, HPC
  task chain, sidecar contracts, rescore resume) - the suite that exercises the sidecar
  paths this change touches.
* `TestStreamingFirstPassMatchesProjection` gained a **third arm**: it captures pass 1's
  run-scope output and serves it back to pass 2, then compares against the SAME resident
  projection oracle the other two arms use, exact (0.0 delta). It asserts pass 1 actually
  flushed every file first, so it cannot pass vacuously by falling back to the recompute.
* **Negative control run deliberately**: perturbing the served `RunPrecQ` by `1e-12` makes
  that arm FAIL. The arm genuinely exercises the read-back and the comparison is exact.
* Still outstanding: `regression.ps1 -Dataset Stellar` (modes 1-3) and a before/after stage
  measurement. The expected win is the per-file sort across 353M rows, NOT the ~7% walk.

### Separate finding: the Osprey pre-commit INSPECTION gate is broken in these worktrees

`Build-Osprey.ps1 -RunInspection` reports **427 errors + 20 warnings** and so always fails.
It is not caused by any change: the **clean tip `ed25627d81`, detached, with the script
printing "No modified/added files found", produces the IDENTICAL 427/20 and the same
per-file counts**. All 427 are `CSharpErrors` of the form "Cannot resolve symbol 'X'" for
types living in the pwiz-sharp / CommonUtil projects, and `jb inspectcode` prints
"Referenced project 'X' not found in the solution, it's output assembly wasn't found either"
for every one of them. So `Osprey.sln` does not carry those project references in a form the
inspector can resolve, and the "errors" are resolution failures, not code defects - the
compiler builds the same tree clean.

Consequence: the documented gate `Build-Osprey.ps1 -Configuration Debug -RunTests
-RunInspection` cannot go green here, and a session that treats its red as a real signal
will chase 427 phantoms. Worth its own TODO and a fix to the inspection invocation (or to
`Osprey.sln`'s reference set).

Incidental: the unit-test run ends with an unhandled `NullReferenceException` in
`OspreyDiagnostics.<Initialize>b__2_0` (`OspreyDiagnostics.cs:107`), an exit-time event
handler. The run still reports success. Pre-existing and unrelated to this change, but it is
noise in every test run.
