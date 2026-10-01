# TODO: Parallelize FirstPassFDR - 86% of the stage is serial per-file work

## Branch Information
- **Branch**: `Skyline/work/20260930_osprey_pass2_runq_reuse` (worktree `pwiz-net10b`)
- **Base**: `Skyline/work/20260612_net8_port` (PR #4619), branched at `ed25627d81`
- **Created**: 2026-09-26
- **Status**: Item 1 DONE: 3 commits (`65283f6dc1`, `154219f399`, `b8524ef1dc`), gated at
  48 PASS / 0 FAIL (-Dataset All), measured two ways at **~370-394 s off an 82-file
  FirstPassFDR**. Not pushed, no PR. **Mis-sized originally - read the 2026-10-01 sections at the END.**
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

## 2026-10-01 night session: item 1 MEASURED. The sort costs 38.3 s / 33.5M rows.

This supersedes the "Still outstanding" line in the 2026-09-30 section above.

### Commits (branch `Skyline/work/20260930_osprey_pass2_runq_reuse`, worktree `pwiz-net10b`)

* `65283f6dc1` - pass 2 reads the run q-values off the sidecar instead of re-sorting.
* `154219f399` - `[PATH]` cost attribution for BOTH streaming passes. Log-only.

### How to measure this stage - do NOT use log-heading deltas

The first attempt measured "pass 2" as `t("Assigning q-values")` to
`[TASK] FirstPassFDR:done` and got a misleading answer. **That window is about 3x pass 2**:
it also contains `sink.Finish`, mdiag peak co-assignment, first-pass protein FDR,
resolve-protein-q + persist stratum, the FDRBench pass-1 write and the compaction - the
159 + 100 + 182 + 889 s items this TODO already lists separately. A 38 s effect inside a
370 s window whose run-to-run noise is +-4% (+-15 s) is not resolvable; the A/B showed 14 s
and read as "no win", which was wrong.

**Use the `[PATH]` lines from `154219f399`.** They bucket each pass directly and are
log-only, so they cost nothing and perturb nothing (the stopwatches run once per FILE, except
one per-row timer around `sink.Accept` worth ~1.5 s over 33M rows).

### Measured, 8 files / 33,459,602 rows, isolated `-Task FirstPassFDR`

```
pass 1: walk 7.5s | sidecar 0.1s | score+competition 20.0s | RUN-Q SORT 38.3s |
        clamp floors 9.2s | sidecar write 5.9s                        total 81.0s
pass 2: walk 7.2s | sidecar 3.1s | fill 0.5s | run-q recompute 0.0s |
        q-assign 76.6s (sink 40.0s, lookups ~36.6s)                   total 87.4s
```

`run-q recompute 0.0s` in pass 2 is the proof the read-back fires - zero sorts - which the
wall-clock A/B could not establish. Pass 1 still pays its own 38.3 s sort, correctly: it is
the writer and the sort is what produces what it writes.

**The sort is 38.3 s**, measured in pass 1 on the same call and the same data pass 2 no
longer sorts.

| | pass 2 |
|---|---|
| before | 87.4 + 38.3 = 125.7 s |
| after | 87.4 s |
| saving | **38.3 s, -30.5% of pass 2** |

Scaling by rows (353,085,961 / 33,459,602 = 10.55x; per-file row counts are equal, so the
per-file sort scales linearly in files): **~404 s off an 82-file FirstPassFDR**, roughly
7-10% of the stage against the 4,015.7 s par3 reference.

So item 1 is worth **~400 s, not the ~1,163 s** this TODO originally claimed - the 1,163 s
was pass 2's whole cost, and the sort is under a third of it. It is still a real win and the
change is byte-identical.

### Where the rest of pass 2 goes - the next target, now quantified

`q-assign` is **76.6 s of pass 2's 87.4 s (88%)**, and it splits:

| | 8 files | ~82 files |
|---|---|---|
| `sink.Accept` (the record write) | 40.0 s | ~422 s |
| the five q-value lookups | ~36.6 s | ~386 s |

That is **~800 s at 82 files inside pass 2 alone**, and it is a much better founded target
than the original item 1. Two of the four per-row dictionary lookups are keyed on the peptide
STRING and on a `(string, bool)` tuple, so every row pays string hashing; `expPrecByWinnerId`
and `expAggByEntryId` are `uint`-keyed and cheap by comparison. Ruled out already:
`ProgressReporter.Report` is an uncontended lock plus a `Stopwatch.Elapsed` read, ~1.5 s over
the pass, so the per-row progress call is not the cost.

### Verification state

* 628/628 unit tests pass, on both commits, including every `SubsetPipelineTest` leg
  (resume, HPC task chain, sidecar contracts, rescore resume).
* `TestStreamingFirstPassMatchesProjection` gained a third arm holding the sidecar read-back
  to the resident projection oracle at 0.0 delta, with a guard that pass 1 actually flushed
  every file so it cannot pass vacuously. Negative control: perturbing the served
  `RunPrecQ` by `1e-12` makes it FAIL.
* `regression.ps1 -Dataset Stellar` PASSED (5 legs; mode 1 is the 1e-9 golden byte gate).
* `regression-parallel.ps1 -Dataset All` launched 00:36 - this is the one that matters here,
  because Stellar sets `SkipModes = @(2, 3)`. (Mode 3, the cross-PROCESS `--task`
  rehydrate chain, turned out to run on StellarLibDecoy, NOT Astral - see the final section
  at the end of this file for the result: 48 PASS / 0 FAIL.)

### Caveats on tonight's numbers

MACS2 was shared all night: a foreign `diann.exe` ran at up to ~24 cores and was still
resident at 00:30, and the 82-file par4 run held the box until 00:17:42. Every absolute
wall-clock number from tonight is contended and must not be compared with 2026-09-26.
The `[PATH]` buckets above are internally consistent within one run, which is why they are
the numbers quoted rather than any stage total. A quiet-box re-run would tighten them.

## 2026-10-01 final results (same night session). Supersedes the "not in at the time of writing" notes above.

### Branch is three commits, all gated

```
b8524ef1dc  osprey: Removed the per-row sink timer from the pass-2 cost attribution
154219f399  osprey: Added pass-1 and pass-2 cost attribution to the streaming first pass
65283f6dc1  osprey: Changed pass 2 to read the run q-values pass 1 already stored
```

`b8524ef1dc` exists because `154219f399` shipped a **per-row** `Stopwatch` around `sink.Accept`
- about 2% of pass 2, permanently, to watch a split that is now written down here. The per-FILE
buckets are free at any cohort size and are kept. To get the finer split again, build a
throwaway with per-row timers; the snapshot `_bin\26.1.1.273-instr-lookups` already has them.

### `regression-parallel.ps1 -Dataset All`: **48 PASS / 0 FAIL / 0 SKIP in 00:56:36**

**Correction to the note above: mode 3 runs on StellarLibDecoy, NOT on Astral.** Astral ran
only mode4, mode1 (streamed join) and mode6. The coverage is better than feared, and it
includes the leg that matters most for this change:

```
StellarLibDecoy mode3 (per-file FDR sidecars==straight): PASS (5,094,029 records)
StellarLibDecoy mode3 (HPC chain==straight): PASS
StellarLibDecoy mode3 (per-run hydrate): PASS (3 worker(s))
StellarLibDecoy mode2 (resume cache hits): PASS;  mode2 (resume==straight): PASS
StellarGenDecoyEntrap mode2 / mode12 (resume fdrbench==straight): PASS
```

"per-file FDR sidecars == straight" over 5,094,029 records is precisely the assertion a
sidecar read-back change needs.

### The win, measured two independent ways on a QUIET box

The machine went genuinely quiet at 01:36 (`diann.exe` gone, total CPU 1-2%).

| measurement | result |
|---|---|
| direct bucket: pass 1 `run-q sort` | **37.3 s** / 33.46M rows |
| clean stage A/B, `-Task FirstPassFDR`, 8 files | **485.2 s -> 450.1 s = -35.1 s (-7.2%)** |
| the A/B's control (pass 1) | **102 s in BOTH arms - exactly flat** |

The two agree within 6%. **At 82 files: ~370-394 s off FirstPassFDR.**

Quote the **bucket as primary** in the PR. Stage-level run-to-run noise on a quiet box is
~6.7% (two instrumented runs that both contained the change came in at 474.6 s and 506.3 s),
the same order as the effect; the bucket does not depend on that noise.

### Quiet-box attribution of the whole stage (8 files / 33,459,602 rows)

```
pass 1: walk 6.7 | sidecar 0.0 | score+competition 18.9 | run-q SORT 37.3 | clamp 9.8 | write 5.4  = 78.1 s
pass 2: walk 7.4 | sidecar 2.8 | fill 0.9 | run-q 0.0 | q-assign 79.2 (sink 35.7, peptide lookups 20.5) = 90.3 s
```

Pass 2 at 82 files is therefore ~953 s, and ~1,347 s before this change - which **reconciles
with the 1,163 s this TODO originally quoted for pass 2.** That figure was a fair number for
pass 2 as a whole; the error was attributing it to re-decoding parquet rather than to the sort
plus the emit loop.

### A one-row memo for the peptide lookups is REFUTED - do not build it

Measured adjacency over 33,459,602 rows:

```
same entry_id as previous row:        0        (ZERO)
same peptide by reference:      224,578        (0.67%)
same peptide by value only:   5,679,528        (17.0%)
```

Adjacent rows **never** share an entry_id, so the assumption that a precursor's rows sit
together (parquet written `(entry_id, charge, scan)`-sorted) does not hold on this path. A
one-row memo would hit 17.7% at best and 96% of those hits would still pay a full string
compare. **Side finding:** 224,578 reference matches against 5.68M value matches means the
parquet reader allocates a **fresh peptide string per row** - ~33.5M allocations per pass, no
interning. That is GC pressure and a candidate in its own right.

### What to do next, with sizes (82 files, scaled x10.55 from the quiet-box buckets)

1. `sink.Accept`, the pass-2 record write - **~376 s**. Largest single item in pass 2.
2. The two peptide-keyed lookups - **~216 s**. The memo is out; the option left is making the
   maps ID-keyed, i.e. assign a peptide ordinal once in
   `StreamingFdr.BuildExperimentPeptideQMap` and key on that instead of the string. The four
   `uint`-keyed lookups plus the arithmetic are ~243 s and already cheap per probe.
3. Interning the peptide column at decode, which would cut both the allocations and the
   hashing. Ruled out as the cost already: `ProgressReporter.Report` is an uncontended lock
   plus a `Stopwatch.Elapsed` read, ~1.5 s over the pass.

### Separately settled: there is NO PerFileScoring regression on the tip

Handoff item 6, taken in the quiet window with the sanctioned runner (not the `ai/.tmp`
bisect script), 4 files, `-Task PerFileScoring`, identical config, back-to-back:

| | PerFileScoring |
|---|---|
| old pin `5bd83dae8b` (v26.1.1.268) | 750.7 s |
| tip `ed25627d81` (v26.1.1.273) | **738.1 s** |

**The tip is 1.7% faster.** So the 2026-09-30 PerFileScoring 2.16x and FirstPassFDR 1.55x gaps
against 2026-09-26 were contention plus config differences, not a code regression - the
previous handoff was right to withdraw that finding, and the "maybe a real regression hides
alongside it" worry is now closed. Both SHAs also scored **16,656,225** peaks on the same 4
files, identical across the eleven commits. Caveat: threads 30 sequential here against
threads 72 `--parallel-files 4` in the 82-file runs, so these absolutes are comparable only to
each other.
