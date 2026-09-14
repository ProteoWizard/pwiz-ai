# Osprey: the model-diagnostics co-assignment panel allocates ~30 GB/min and inflates committed memory to 42 GB at 446 runs

## Branch Information
- **Branch**: `Skyline/work/20260912_osprey_coassignment_allocation` (`C:\proj\pwiz-work2`, off
  master `7af9eb0ea5`)
- **Base**: `master`
- **Created**: 2026-09-12
- **Status**: In Progress
- **GitHub Issue**: [#4657](https://github.com/ProteoWizard/pwiz/issues/4657)
- **Module**: `osprey`
- **PR**: [#4662](https://github.com/ProteoWizard/pwiz/pull/4662) - STACKED on #4661
- **Labels to carry**: `performance`

## Objective

`PeakCoAssignmentSource.Build` is the largest single memory consumer in `--task ModelDiagnostics`
at cohort scale and the only part of that command whose memory is not flat: on the 446-run CHS
cohort it takes private bytes from ~10 GB to 41.7 GB in 12.5 minutes (12.5 of `FirstPassFDR`'s
69). The live set is small and bounded - the O(files x entries) retention was already removed -
so what remains is ALLOCATION RATE: per-file dictionaries of ~4.2 M entries built from empty and
discarded 446 times, plus per-file parquet column reads, at ~30 GB/min of large-object garbage.
Server GC answers that rate by expanding committed memory. Committed-but-free, not a leak, and
cheap to fix without changing a byte of output.

Measured (446-run CHS, `--task ModelDiagnostics`, exe snapshot of `1b9dc83cf7`):

| when | phase | private | managed |
|---|---|---|---|
| 56 min | `FirstPassFDR` fold, one run resident at a time | flat ~10.5 GB | flat ~7.5 GB |
| 3.5 min | co-assignment phase 1: scanning 1st-pass sidecars over 446 files | 10 -> 35 GB | sawtooth 9-19 GB |
| 9 min | co-assignment phase 2: joining apex RT over 446 files | 35 -> 41.7 GB | sawtooth 9-19 GB |

## Where the allocation comes from (from the issue)

**Phase 1 - decoy score cutoffs.** Per file, `FdrScoresSidecar.ReadRecords` streams every record
(~4.18 M x 28 B = 117 MB; 52 GB of IO cohort-wide) and `ObserveCutoff` folds each into
`_fileBest` (`Dictionary<uint, double>` keyed by entry id) and `_fileAccepted` (`HashSet<uint>`).
`SealRunCutoff` reduces the dictionary to ONE number plus a few thousand admitted decoy ids, then
`_fileBest = new Dictionary<uint, double>()`: ~22 prime-doubling resizes to ~4.18 M entries, each
a new bucket + entry array on the LOH, ~230 MB of garbage per file, 446 times in 3.5 min. The
dictionary is ~100x larger than the information it yields.

**Phase 2 - apex-RT join** (`AddFile`). Per file: `ParquetScoreCache.TryReadEntryIdsAndApexRts`
reads two full columns (4.18 M x 12 B = 50 MB of arrays plus Parquet's transient buffers), then
the SAME sidecar is streamed a second time (another 52 GB of IO) to re-derive `runQ` /
`experimentQ` for rows already classified in phase 1. Rows clearing the cutoff build a string key
(`modSeq + "|" + charge`) and a `CoAssignmentRow`, retained in `_fileRows` / `_byPrecursor` -
O(accepted precursors x runs), ~16.5 M rows, ~2-3 GB: the genuine live growth. The rest of
35 -> 41.7 GB is committed expansion from the per-file column reads.

## Tasks

- [ ] Phase 1: stop re-allocating the per-file containers. Minimal: `Clear()` keeps the grown
      capacity. Better: replace `_fileBest` with two flat `double[]` indexed by base id (targets
      and decoys; base ids are dense under the 6.2 M-entry library), ~100 MB allocated once for
      the whole panel, O(1) per record, zero per-file allocation; `_fileAccepted` as a bit array
- [ ] Phase 2: read each sidecar once. The join needs apex RT only for rows that clear the
      cutoff, and which rows those are is known after phase 1 - carry the per-file accepted set
      (or re-derive from the sealed cutoff) instead of re-streaming 117 MB per file
- [ ] Phase 2: pool the two parquet column arrays (`ArrayPool<T>`) so the 50 MB per file is not
      re-allocated; Parquet's own buffers are out of reach
- [ ] Verify with `perfviz.py` on the 446-run bed (`D:\test\osprey-runs\chs-seer\runs\chs446-mdiagtest-copy`,
      `--task ModelDiagnostics`, products deleted first, `OSPREY_VERSION_OVERRIDE=26.1.1.243`,
      exe snapshotted): the 22:01-22:14 excursion should collapse toward the fold's ~10 GB
      floor, and the report must stay byte-identical (`Compare-DiagReports.ps1`, strict,
      against the products the current build produces - banked at
      `ai/.tmp/sessions/20260910-01Qwgkv/oracle-products/`)
- [ ] Gates: `regression.ps1 -Dataset StellarLibDecoy` (modes 7 and 11 cover the panel), then
      `regression-parallel.ps1 -Dataset All`; output byte-identical is the whole acceptance
      criterion

## Regression Test

- **Test name**: (the acceptance criterion is byte-identical output; the diagnostics-report
  goldens in modes 1b / 5 / 7 / 11 are the regression test, and the 446-run perfviz plot is the
  performance verification - no new unit test is planned unless the phase-1 restructuring
  earns one for the flat-array reduction)
- **Test project**: Regression (goldens)
- **Fails on master**: n/a - performance change, output must not move
- **Passes on fix**: (perfviz numbers and the strict report compare, when run)

## Watch for

- `SealRunCutoff` builds `admitted` as a `HashSet<uint>` from a dictionary walk; if any consumer
  enumerates that set into the report, the enumeration order (insertion-dependent) is part of
  the byte-identity contract and a flat-array walk changes it. Check every reader of
  `_admittedRunDecoys` before touching the container.
- The same per-file `Dictionary<uint, FdrScoreRecord>` shape lives in
  `FirstPassFdrTask.StreamFirstPassFileScores` (protein FDR reduce, and since #4661 the pass-1
  FDRBench emitter). Same churn at 446 files; a fix here should be the shape that one adopts.

## Progress Log

### 2026-09-12 - Session Start

Branch created off master `7af9eb0ea5` in `pwiz-work2` (the other two checkouts hold open PRs
#4660 and #4661). Origin: PR #4656's 446-run oracle and
`TODO-20260910_osprey_mdiag_resident_removal.md` ("Recorded from the 446 runs").

### 2026-09-12 - Implemented; unit gate green; StellarLibDecoy gate running

Three files, +130/-48, on `pwiz-work2`:

* **Phase 1** (`CoAssignmentPassBuilder`): `_fileBest` (`Dictionary<uint, double>` by entry id,
  rebuilt per file) and `_fileAccepted` (`HashSet<uint>`) are two `double[]` by BASE id (target
  and decoy sides) plus a `bool[]`, allocated once via `ReserveRunScope(maxBaseId)` - the
  caller takes the bound from the experiment-scope map, since every record phase 1 folds is
  gated on having one - and reset by a fill between files. NaN = not seen this file, which is
  what the dictionary's missing key meant, so `ObserveCutoff`'s store rule and
  `SealRunCutoff`'s two reductions are the same expressions over a different container.
  `_admittedRunDecoys[f]` is still the per-file `HashSet` (only ever probed with `Contains`,
  never enumerated, so no ordering reaches the report). Grows on demand if unreserved, so the
  unit tests that build a builder bare still work.
* **Phase 2** (`ParquetScoreCache.TryReadEntryIdsAndApexRts`): fills caller-owned `ref` arrays
  and reports `count`, growing them only when a file is larger than any before it;
  `PeakCoAssignmentSource.BuildCore` holds them across the loop. Parquet.Net's own per-row-group
  column arrays are out of reach.
* **Not done, and why**: "read each sidecar once" (the issue's second phase-2 item). Phase 2
  keeps the best-scoring row per (precursor, file) among rows that clear a gate the DECOY side
  of which is only known after every file is sealed (`SealCutoffs`), and pass 1 is
  pre-compaction, so a precursor has many candidate rows per file. Carrying "the rows phase 2
  will keep" from phase 1 therefore means buffering candidate rows for every file across the
  cohort - the O(files x rows) shape this panel was rebuilt to avoid. The second sidecar stream
  is IO (117 MB/file) with no per-record allocation (`in FdrScoreRecord`), so it is not what
  drives the committed-memory excursion; the column arrays and the per-file dictionary were.

`Build-Osprey.ps1 -Configuration Debug -RunTests -RunInspection`: 593/593, 0 warnings.
`regression.ps1 -Dataset StellarLibDecoy` (modes 7 and 11 compare the diagnostics report to
its golden) running; then the 446-run bed via `oracle-446-4657.ps1` (this session dir), strict
against the banked current-build products, with perfviz; then `regression-parallel.ps1
-Dataset All`.

### 2026-09-12 - The flat arrays were O(n^2) without a reserve; fixed and pinned

The StellarLibDecoy gate passed but was 30-60% slower everywhere a pass-2 diagnostics report is
built. Per-leg, against the same dataset's legs on the fdrbench branch's `-Dataset All` run
earlier the same day:

| leg | fdrbench branch | #4657 branch |
|---|---|---|
| pay-later diagnostics fold (mode 11) | 15.7 s | 492.2 s |
| HPC 4-task chain (mode 3) | 557.6 s | 846.5 s |
| resume (mode 2) | 172.7 s | 470.2 s |
| Stage-5 rehydrate (mode 5) | 93.0 s | 422.8 s |

Root cause: `EnsureRunScopeCapacity` grew to exactly `baseId + 1`. Rows reach `ObserveCutoff`
in parquet row order, which is ASCENDING entry id, so an unreserved builder saw a new maximum on
almost every row and copied all three arrays each time - O(n^2) per file. `ReserveRunScope` hides
it on the phase-1 path (`PeakCoAssignmentSource`), which is why the 446-run bed's first phase
looked fine; the PASS-2 builder in `SecondPassFdrTask` is constructed bare and never reserved, so
every pass-2 fold paid it. The 446-run oracle launched at 18:36 was still inside that fold at
21:22 (it had reached the pass-1 boundary at 19:46), which is what exposed it.

Fix: geometric growth (`max(baseId + 1, 2 * old)`), so a reserve from empty still lands exactly
on `maxBaseId + 1` and an unreserved ascending stream grows O(log n) times.
`TestCoAssignmentRunScopeGrowsGeometrically` pins both halves and is red on the exact-growth
version (verified: "grew the run scope 100000 times; geometric growth allows at most 18").

Commits `997ed8d94b` + `e23ffdd616`, now REBASED onto the #4661 branch
(`Skyline/work/20260912_osprey_fdrbench_pass_bitmask` @ `7c595218e6`) so one TeamCity run
validates both, per Brendan's night-session instruction. #4661 merges first.

### 2026-09-12 - Code review applied; PR #4662 opened; the 446-run oracle CRASHED

`/code-review max` on the two commits alone (a review branch off master, so the #4661 commits
underneath were not re-reviewed) returned 15 findings. The verifier refuted three mechanisms
outright. Applied (`d8b273410d`):

* **The accepted set goes back to a HashSet of FULL entry ids.** It is the ~1% FDR population -
  thousands per file - so a dense `bool[6.2M]` was the wrong shape, and indexing it by BASE id
  quietly changed the keying: the score is filed by the entry id's DECOY BIT while the accepted
  flag was set on the CLASS, so a row whose class and bit disagree would have had its score read
  off the other side as NaN and dropped out of the minimum. The full id restores the dictionary's
  exact behaviour and makes the seal's minimum O(accepted) instead of O(capacity).
* **The arrays are released at `SealCutoffs`**, beside the existing `_experimentAccepted.Clear()`.
  Both writers throw after the seal, so 105-210 MB was provably dead and still rooted through the
  phase-2 join, the build and serialization - in a PR about committed memory.
* **The per-file reset is fused into the sweep the decoy side already makes**, so a file costs one
  pass over the dense arrays rather than five.
* **The other two builders reserve** (`SecondPassFdrTask`, `BuildCoAssignmentCore`); only the
  1st-pass panel did, and the pass-2 builder is the one whose 15.7s -> 492s regression this branch
  had to fix. **Parquet buffers grow geometrically** for the same reason the run scope does - an
  ascending-size cohort reallocated on every file otherwise.
* **Two tests, both verified red**: the seal must forget the file it sealed, and "not seen" must be
  NaN rather than 0.0 (zero-fill admitted the entire reserved capacity - 65 of 65 - as decoys).
* Dropped: the `int.MaxValue` clamp complaint (a 31-bit id space would need a 17 GB array long
  before the clamp matters) and the ref-buffer ownership refactor (real future hazard, but a
  signature change across two assemblies is not this PR).

Unit gate after: 593/593, zero inspection warnings.

**The 446-run oracle crashed** at 23:19 after 1h50, 94% through "Folding experiment-q floors over
446 run(s)":

```
Fatal error. System.AccessViolationException: Attempted to read or write protected memory.
   at Parquet.Encodings.ParquetPlainEncoder.Decode(Span<Byte>, Span<String>, SchemaElement)
```

Pass-1 products were written and compare STRICT-identical to the banked current-build products
(`pass-1 compare exit 0`); the pass-2 product was never written. What this is NOT: the crash is in
Parquet.Net's string decoder on the experiment-q fold, a reader path this branch does not touch
(the branch's parquet change reads the `entry_id` and `apex_rt` columns). None of the five earlier
446-run logs on this bed carries an AccessViolation. What it probably IS: the box was
over-subscribed - the stacked regression gate's two lanes were running against the same 64 GB
while the cohort held ~20 GB, and the harness had already killed background tasks for low memory.
Being re-run ALONE on the final build to settle it; a crash inside a memory PR cannot be left as
"probably the neighbours".

### 2026-09-13 - Oracle re-run alone: PASS, and the crash does not reproduce

`ORACLE VERDICT: PASS - exit 0, route clean, products strictly identical to the current build`,
wall 1:50:37 on the final build (`coassign-4657-v3`), running with nothing else on the box. Both
products written this time: pass-1 233,498 bytes and pass-2 218,074 bytes, each byte-compared
strict against the banked current-build products.

The crash therefore does not reproduce on the same bed, the same command and a SUPERSET of the
code (the review fixes landed in between). Same wall to the second - 1:50:36 crashed, 1:50:37
clean - so contention was not slowing the run down; what differed was how much memory was left
when Parquet.Net's string decoder asked for its next buffer. Filed as issue #4663 rather than fixed here: an
`AccessViolationException` out of a managed library under memory pressure is worth knowing about
(it is a hard process kill, not an `OutOfMemoryException` a caller could catch), but it is not
this branch's to fix and nothing in the branch reaches that decoder.

**Private bytes** - CORRECTED on 2026-09-13 after Brendan asked whether perfviz had been run
against the bed's prior logs and PNGs rather than against the numbers quoted in the issue. It had
not: the first write-up compared my windows to the issue's recorded figures and reported
"41.7 -> 29.7 GB overall", which is not a process peak. The like-for-like comparison, with the two
pre-fix runs being the SAME build:

| run | build | `FirstPassFDR` peak (the panel) | `SecondPassFDR` peak | process peak |
|---|---|---|---|---|
| 09-10 22:56 | `mdiagfix-1b9dc8` | 41.7 GB | 39.2 GB | 41.7 GB |
| 09-11 02:09 | `mdiagfix-1b9dc8` | 37.0 GB | 32.9 GB | 37.0 GB |
| 09-13 01:17 | this branch | **30.2 GB** | 38.2 GB | 38.2 GB |

Same build, two runs, 4.7 GB and 6.3 GB apart - so single numbers here are a band, not a point.
The panel's phase is below both unfixed runs (30.2 against 37.0-41.7), and inside it phase 1 is
flat at 11.3 -> 12.2 GB where it climbed 10 -> 35 GB. That part of the goal is met.

The PROCESS peak is not: it moved to `ReclampExperimentQToBestRun` ("Folding experiment-q floors
over 446 run(s)"), 28.3 -> 38.2 GB here against 27.8 -> 32.9 GB on the baseline - inside the same
band, on code this branch does not touch. The two pass-2 co-assignment windows are 20.4-21.0 GB in
both runs. Filed as #4664: that fold materializes every file's full `FdrEntry` list, modified-
sequence strings included, to compute two minima - the shape #4657 just removed, one phase over -
and it is also where #4663's AccessViolation hit.

Gates: `regression-parallel.ps1 -Dataset All` on the stack 70 PASS / 0 FAIL / 0 SKIP in 55:27;
unit gate 593/593 with zero inspection warnings. TeamCity on `pull/4662` queued (build 4174297).

### 2026-09-13 - One unexplained unit-test failure, under the same memory pressure

`TestStreamReconciledTransferMatchesLoadAllOverlay` failed once - `Assert.AreEqual failed.
Expected:<2>. Actual:<0>` on `result.NReplaced` - in the full-suite run made while the 446-run
cohort and the two-lane gate were both on the box. It passed in isolation immediately afterwards
and in a full 593/593 re-run, and it passes on the stashed (pre-change) tree as well, so it is
not this branch. No theory that survives inspection: the suite runs sequentially
(`vstest.console.exe`, one assembly, no `/Parallel`, no `[assembly: Parallelize]`), so the shared
`ParquetScoreCache.RowGroupRowCapForTest` static that six IOTest methods set is not being raced.
Recorded rather than explained; if it recurs outside a memory-starved box it deserves a real look.

### 2026-09-13 - TeamCity green

TeamCity #250 on `pull/4662` (`1276737f35`): **SUCCESS, 70 PASS / 0 FAIL / 0 SKIP in 1:01:47**.
It ran the whole stack, so it covers #4661's sparse matrix as well. Ready for `/pw-complete`
after #4661 merges and this retargets to master.

### 2026-09-13 - Scope re-cut: the floor fold moves to #4664

The experiment-q floor fold was implemented here, proven CORRECT (446-run products strictly
identical, Stellar golden-identical at 1e-9, the route asserted in the log by a new mode 13) and
3.5x faster (13 min -> 3m46s) - and then **reverted out of this PR** (`9a85f68a8b`), because it
made the thing it was meant to fix worse: the 446-run committed peak went 38.2 -> 44.4 GB.

Why, and it is the useful part: the fold still decodes ~366 M modified-sequence strings from the
parquet identity columns. The pool path allocated MORE in total but spread it over 13 minutes of
heavy GC pressure that kept the heap trimmed; the artifact path allocates less, in a short window,
with nothing forcing a collection - managed climbs 5.2 -> 18.7 GB inside the window and falls back
to 9.3 GB in the next phase, and Server GC commits to match. Less allocation, higher peak.

The work is preserved on `Skyline/work/20260913_osprey_expq_floor_fold` (commits `35c7b1e917`
floor fold, `54df126669` mode 13) and #4664 now owns it, together with the blocking question:
the sequences must come from a cohort-wide source rather than a per-file parquet read, and
`libraryById` is not guaranteed to carry decoy entry ids, whose sequences are not their targets'.

Brendan's correction that prompted this: `FirstPassFDR` was not finished. Its co-assignment
apex-RT join still climbs 13.0 -> 30.8 GB over ~9 minutes, about half live and half garbage, and
the live half includes 13.95 M retained rows each carrying a `Key` string that duplicates two
fields already in the same struct (~1.4 GB). That, not the pass-2 fold, is the next thing inside
the panel this PR is about - written up as item 1 of #4664.

**This PR now is**: the co-assignment working set (flat arrays + reusable parquet buffers), the
geometric growth fix, the code-review findings, and the reusable pass-2 join index. Peak
`FirstPassFDR` 41.7/37.0 -> 30.2 GB with products unchanged.

### 2026-09-13 - Regeneration validity: two defects found by bisection (NOT filed as issues)

Brendan's bisection, five cells on the 446-file CHS bed, each a fresh hard-linked mirror of a
completed run (scripts in `ai/.tmp/sessions/20260912-e12121ed/novalidwork-446*.ps1`):

| # | invocation | `--model-diagnostics` | diagnostics products | result |
|---|---|---|---|---|
| 1 | full pipeline | no | absent | all four tasks skip - **4 s** |
| 2 | full pipeline | yes | present | first three skip; **SecondPassFDR re-runs** ("Loading scored entries...", ~19 GB climbing) |
| 3 | `--task FirstPassFDR` | no | absent | skip - 0 s |
| 4 | `--task FirstPassFDR` | yes | present | skip - 0 s |
| 0 | `--task FirstPassFDR` | yes | **absent** | **full re-run incl. Percolator retrain** -> resident pre-compaction pool, 109 GB at file 165/446 |

Validity detection itself is sound and nearly free: 8,037 artifacts, four tasks, four seconds.
`--task` is not the variable either (3 and 4 are instant). The variable is **the diagnostics
product being absent while `--model-diagnostics` is requested**.

**Defect A - `FirstPassFDR` re-runs the whole first pass instead of folding the report.**
`FirstPassFdrTask.cs:470` gates the pay-later fold on
`config.ModelDiagnostics && OnlyDiagnosticsProductOutstanding(ctx)`, which is NOT
`--task ModelDiagnostics`-only, so row 0 should have folded. It did not, and the predicate's
own "not folding diagnostics from completed work - {0} is {1}" line never appears - leaving the
one branch that returns false SILENTLY (`FirstPassFdrTask.cs:359`):
`if (string.IsNullOrEmpty(diagnosticsPath) || File.Exists(diagnosticsPath)) return false;`
So either `ModelDiagnosticsReport.Pass1SidecarPath(config)` resolved empty for this invocation,
or the file was judged present. Start there. This is the blocker for the intended workflow -
add `--model-diagnostics`, re-run, do only the diagnostics work - and the only path that
produces the complete report (with the Model tab) is the one that cannot finish at 446 files.

**Defect B - `SecondPassFDR` re-runs with nothing missing.** Row 2: every product present,
including `out.2nd-pass.model-diagnostics.json` and the HTML with their
`...SecondPassFDR.osprey.task` stamps, and it still loads the scored pool. Likely the same
shape as A: the validity key an ordinary `--model-diagnostics` run computes differs from the key
those stamps were written under ("present but not current"), rather than anything being absent.

Related, from the same runs: `--task ModelDiagnostics` logs *"first-pass model not retrained on
this run (resumed/rehydrated); the Model tab's feature table and per-feature distributions are
unavailable"*. So the bounded path and the complete-report path are not the same report today.

### 2026-09-13 - Session end: where #4662 stands

**#4662 is ready to merge except for one TeamCity run.** Locally green on all four datasets
(`regression-parallel.ps1 -Dataset All`: 70 PASS / 0 FAIL / 0 SKIP in 51:49), unit gate 593/593
with zero inspection warnings, 446-run oracle products byte-identical, `FirstPassFDR` private
peak 41.7/37.0 -> 30.2 GB. Branch `Skyline/work/20260912_osprey_coassignment_allocation` at
`9a85f68a8b`, pushed, base `master` (retargeted when #4661 merged). TeamCity #250 is STALE - it
was green on `1276737f35`, before the floor fold was added and reverted - so `pull/4662` needs one
more run before merge. ASK before triggering.

What the PR contains, after the re-cut: the co-assignment working set (flat arrays by base id +
caller-owned parquet buffers), the geometric-growth fix, the `/code-review max` findings, and the
reusable pass-2 overlay join index. Nothing else.

**Not in it, deliberately**: the experiment-q floor fold lives on
`Skyline/work/20260913_osprey_expq_floor_fold` (pushed, no PR). Correct and 3.5x faster but it
raises the committed peak 38.2 -> 44.4 GB until its ~366 M per-file string decodes are removed.

**Still open on the pwiz side**: #4660 is OPEN and BEHIND master (needs an update-branch merge;
TeamCity #249 was green on `ca29bc84b3`). Its branch is in `C:\proj\pwiz`, which also has an
untracked `pwiz-sharp/` directory that is not this work's.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260912_osprey_coassignment_allocation.md` before starting work.

### 2026-09-13 - Scope widened: the regeneration path had to work before #4662 can be finished

**This branch is NOT ready to merge, and the previous entry saying so is superseded.** The
pay-later regeneration path is how the memory work on this branch gets measured at cohort
scale, and two of its four entry points were broken. Fixing them here rather than in a
follow-up, per Brendan: "these issues came up as blocking the necessary testing to reach
closure on #4662 ... the PR cycle itself has a cost and small PRs can soak up a lot of time
getting to a goal. We are not there yet."

#### The gate now covers every entry point, not one

Mode 11 asserted exactly one way of asking for a pay-later report - `--task ModelDiagnostics`.
Four more reach the same state and none was covered. They share mode 11's setup (completed
cohort, both products deleted), so the whole section costs **48.2 s**:

| cell | entry point | products | expected |
|---|---|---|---|
| C | whole pipeline `--model-diagnostics` | present | all four tasks skip |
| D | whole pipeline `--model-diagnostics` | absent | both folds, PerFile interrogated and skipped |
| A | `--task FirstPassFDR --model-diagnostics` | absent | pass-1 fold, no analysis |
| B | `--task SecondPassFDR --model-diagnostics` | absent | **refuse** - see below |
| B2 | `--task SecondPassFDR --model-diagnostics` | pass-2 only | pass-2 fold |

Asserted from the LOG, like the rest of mode 11: a re-analysis produces the RIGHT artifact, so
no byte comparison can separate it from a fold. `ALL-RUNS reconciliation bundle` is in the
forbidden set alongside the pool and rescore markers - it is what caught the second link below
after the first fix looked complete.

#### Defect A - `--task FirstPassFDR --model-diagnostics`, two links

Measured at 3 files, cell A, both links visible in its own log ordering:

1. `PerFileScoringTask.PreCompactionPoolReason` forced the RESIDENT pre-compaction pool on
   `FirstPassFdrTask.IsIncludedFor(config)` - task MEMBERSHIP standing in for "will it train".
   False in exactly this case: the task is present and trains nothing, because its only
   outstanding output is a report it folds one run at a time. `Run` materializes `ScoredEntries`
   before it can reach the arm that would say so, which is why the 446-run cohort hit 109 GB at
   file 165 and never got there at all.
2. Removing that left the leg on the disk-load path, still building the **ALL-RUNS
   reconciliation bundle**, O(files x entries), to render a page that reads none of it - the
   structure that put an earlier fold past a 63.7 GB box at file ~310.

Fix: `FirstPassFdrTask.WillOnlyFoldDiagnostics(ctx)`, the predicate `Run`'s arm already used,
now also gates the pool decision AND the `Rehydrate` fork, so a fold-only leg takes
`RehydrateFromOwnOutputs` - the lean streaming load the in-pipeline route takes. One predicate,
three call sites, so the hydrate decision and the fold decision cannot drift.

Cell A: RESIDENT pool + bundle -> **neither**, 11.7 s -> 9.1 s, product still produced, route
now identical to cell D's.

#### Defect B - `--task SecondPassFDR --model-diagnostics` reported success for nothing

With both products absent it logged "folding the pass-2 report from the completed second pass",
ran 5.2 s, logged `SecondPassFDR:done` and **exited 0 having written no product**. Its own log
said why: `[MODEL-DIAGNOSTICS] pass-1 data sidecar not found; pass-2 enrichment skipped`. The
pass-2 page is an ENRICHMENT of the pass-1 page.

`ReadPass1ForEnrichment`'s degrade is deliberately left alone - pass 1's page is a complete
statement on its own, and a run merely carrying `--model-diagnostics` should not die for a view
it did not ask for. The arm is the only place it is wrong, because there producing that product
is the whole request. It now throws, naming the absent file and the command that produces it,
and refuses in **0.2 s** instead of doing 5.2 s of work to write nothing.

#### Gates

* Unit 593/593, ReSharper **0 warnings** (101 s).
* `regression.ps1 -Dataset StellarLibDecoy`, **no -Skip switches** - deliberately, because the
  fix changes the fork at the top of `PerFileScoringTask.Rehydrate` and modes 2/3/5 are the legs
  that drive it hardest. All 27 legs PASS, exit 0.

#### Still open

* **Row 2 is unexplained.** The 446-run observation (SecondPassFDR re-running with every product
  present, in a hard-linked mirror) does NOT reproduce at 3 files: cell C is 0.1 s and green, and
  mode 4 is green in place. Cell C runs IN the straight dir, so relocation is still untested, and
  the hand-restored stamps on `chs446-mdiagtest-copy` remain the leading candidate.
* The 446-run re-measurement of cells A and B with these fixes.
* `-Dataset All` before this branch is considered done.


### 2026-09-13 (evening) - The panel's memory is the PARQUET READ, not anything we guessed

`--task FirstPassFDR --model-diagnostics` now works (committed `4a715d004c`), so for the first
time the 446-run co-assignment panel could be MEASURED rather than reasoned about. Two fixes
aimed at it produced no change, and the third measurement found the actual cost.

#### The acceptance measurement, and what it says

446-run CHS, `--task FirstPassFDR --model-diagnostics`, products withheld, exe snapshots in
`D:\test\osprey-runs\_bin\coassign-4657-v5` and `-v7`:

| metric | v5 (string key) | v7 (PrecursorKey struct) |
|---|---|---|
| process peak | 25.5 GB | 25.3 GB |
| private floor drift | +10.85 GB, **+25 MB/file**, RISING | +10.99 GB, **+25 MB/file**, RISING |
| managed floor | 8.0 -> 7.1 GB, falling | 7.6 -> 8.3 GB, level |
| phase-2 wall | 713.0 s | 692.7 s |
| pass-1 product | 233,498 B | 233,498 B |

The fold is FLAT for 48 of the 58 minutes at ~8 GB private. The entire excursion is the
co-assignment panel in the last ~10 minutes: phase 1 (sidecar scan) is flat at 9.4 -> 9.9 GB -
that half of #4662 is a clean win against the 10 -> 35 GB it used to cost - and phase 2 (the
apex-RT join) goes 10 -> 26 GB and stays there.

**Brendan's bar is not met**: lower than the 41.7 GB it was, but not flat.

#### Two fixes that did nothing, kept for their own sake

Both are byte-identical (mode 1b/7/11 green) and both removed real allocation, and NEITHER moved
the 446-run numbers by more than noise:

* Caching the co-assignment key string per entry id (13.9 M rebuilds -> ~37 K).
* Replacing it with `PrecursorKey`, a `readonly struct : IEquatable<>, IComparable<>`. Brendan's
  point, and correct: a concatenated `sequence + "|" + charge` key is a scripting idiom, not C#.
  The struct removes the per-row allocation entirely, folds `ModifiedSequence`/`Charge` into one
  value instead of duplicating them beside the key, and replaces the `\u0001` pair-key
  concatenation (which existed because two composite strings can collide) with a tuple.

`CompareTo` REPRODUCES the old composite-string order rather than the obvious
`(sequence, charge, decoy)` one, so no golden moves. The two disagree wherever one sequence is a
prefix of another - the shorter key's string continued with `'|'` (0x7C) and the longer with a
residue, so `ABCD|2` sorts BEFORE `ABC|2`. `TestPrecursorKeyOrderMatchesCompositeString` pins
the equivalence and is verified RED on the natural order. That matters: the natural order passed
the entire 3-file matrix, because no prefix-pair m/z tie occurs at that scale. The gate is blind
to this class of change and the unit test is the only thing that is not.

#### Where the memory actually goes (measured, not inferred)

New env-gated probe `OSPREY_LOG_COASSIGN_ALLOC` tallies allocated bytes per call site in the
join. On 3 Stellar files:

```
peak co-assignment join allocated 0.1 GB over 3 file(s):
    parquet columns 29 MB/file, sidecar stream 4 MB/file
```

**7:1.** `TryReadEntryIdsAndApexRts` reads two FULL columns per file - `entry_id` 4 B/row and
`apex_rt` 8 B/row - at ~16 B/row measured, which extrapolates to ~68 MB/file and ~30 GB across
446 files. Parquet.Net hands back a fresh array per column per row group (100,000 rows), so at
800 KB per array these are ~42 LARGE-OBJECT allocations per file, ~19,000 across the cohort, on
a heap that is not compacted by default. That fits a floor rising a steady +25 MB/file far
better than an allocation-rate story does, and it is why 13.9 M short-lived key strings moved
nothing.

Reading `entry_id` only for the first row group (it is not data - it exists to assert that the
sidecar and the parquet are in the same row order, and that drift is systematic) takes 29 ->
22 MB/file. Byte-identical, goldens green. It is a 24% cut and it is NOT enough.

#### The fix, and the constraint that shapes it

The join already streams the 1st-pass sidecar for every row to get score and q-values. If the
sidecar carried `apex_rt` too, the parquet read leaves this phase entirely - all 22 MB/file of
it, the alignment assertion it exists to support, and the `entry_id` change above. Brendan:
that also matches the output blib's `RetentionTimes` table, which carries apex RT, composite
score and per-run q together.

**The constraint**: `FdrScoresSidecar.FormatVersion` (currently 6, record 28 B) is part of
FirstPassFDR's validity key, so bumping it invalidates every bed on disk. Regeneration costs,
measured from this machine's own logs:

| | 446 files |
|---|---|
| `--task FirstPassFDR` (genuine, from parquets) | **5h11m** (18,674 s and 18,796 s on two runs), peak ~39 GB |
| `--task PerFileRescoring` | 8h01m (28,869 s) |
| `--task SecondPassFDR` | 18m |
| full Stages 5-7 | ~13h30m |
| a FRESH 86-file cohort | 8h20m, of which PerFileScoring alone is 5h04m |

So a fresh bed is out, and only Stage 5 needs re-running - 5h11m, not 13.5h. That fits one
night, with the ~58-minute pay-later measurement after it.

#### Uncommitted in `pwiz-work2`

| file | change |
|---|---|
| `ModelDiagnosticsData.CoAssignment.cs` | `PrecursorKey` value type; row carries it; tuple pair key; `\u0001` separator deleted |
| `PeakCoAssignmentSource.cs` | builds `PrecursorKey`; allocation tally; dotMemory checkpoints |
| `ParquetScoreCache.cs` | `entry_id` read for the first row group only; `verifiedRows` out-param |
| `OspreyEnvironment.cs` | `OSPREY_LOG_COASSIGN_ALLOC` |
| `ModelDiagnosticsDataTest.cs` | `TestPrecursorKeyOrderMatchesCompositeString` (594 total) |

Gates on the working tree: 594/594 unit, ReSharper 0 warnings, `regression.ps1 -Dataset
StellarLibDecoy` green (three separate runs across the three changes).

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260913_osprey_coassign_parquet.md` before starting work.


---

## 2026-09-14 (overnight): apex_rt moved into the sidecar at format v7

Committed as `247e351940` on `Skyline/work/20260912_osprey_coassignment_allocation`.

### What landed

`FdrScoreRecord` gains `double ApexRt`; `FdrScoresSidecar.FormatVersion` 6 -> 7 and
`RecordLength` 28 -> 36. The panel's parquet read, its positional join and the `entry_id`
alignment assertion are all deleted, and `ParquetScoreCache.TryReadEntryIdsAndApexRts` with
them - including the first-row-group `entry_id` narrowing from 2026-09-13, which was the
partial fix this replaces rather than preserves.

Where the column comes from, per path:

| path | source | cost |
|---|---|---|
| streaming 1st pass (`IsCountsOnly`, the 446-run path) | a sixth scalar on `ReadFdrStubScalars`, which already walks five | one more column on an existing read |
| resident 1st pass (the flag-off `FdrEntry` oracle) and the 2nd pass | `ParquetScoreCache.ReadApexRtsByParquetIndex`, indexed by `FdrProjection.ParquetIndex` | one per-file read on a path that already holds the fat pool |
| `Pass2PerFileWorker` | `FdrEntry.ApexRt`, already populated on the resident reported pool | nothing |

`ReadApexRtsByParquetIndex` reads THROUGH `ReadFdrStubScalars` rather than opening the column
itself, so the ordinal the array is keyed by and the ordinal the projection rows carry come
from one walk and one row-group skip rule. `ScoreProjectionAndComputeFdrInPlace` now THROWS on
a null apex loader, the way it already did for a null feature loader: a defaulted RT would be
a fabricated number in a persisted artifact that no reader could tell from a measured one.

Also folded in (it removed real allocation and its ordering needed the same unit test):
`PrecursorKey` replaces the composite string key, with `CompareTo` reproducing that string's
order so no golden moves.

### Evidence, 3-file StellarLibDecoy, before the 446 run

* `OSPREY_LOG_COASSIGN_ALLOC=1` on the replayed cell A:
  `peak co-assignment fold allocated 0.0 GB over 3 file(s): sidecar stream 0.0 GB (4 MB/file),
  no parquet column read` - against `parquet columns 29 MB/file, sidecar stream 4 MB/file`
  on 2026-09-13. The 7:1 is gone, not reduced.
* The written sidecar, read back byte-wise: v7, pass 1, 958,241 records, **0 NaN and 0
  exactly-0.0** apex RTs, range 1.2905 - 20.6235 min over a ~21-minute gradient, 63,685
  distinct values. That check exists because a run that wrote a default everywhere would look
  identical from the outside - the panel would still build and the memory curve would still
  flatten - while reporting perfect co-elution between every pair of precursors.
* `out.1st-pass.model-diagnostics.json` vs the banked pre-change product: the `coAssignment`
  subtree is IDENTICAL (NaN-aware compare). The only differences in the whole document are
  `generatedUtc` and the model section, which is present because the v7 bump forced a retrain
  that the banked run had adopted from disk.
* 594/594 unit tests, ReSharper 0 warnings.

The two parity tests now compare apex RT as well. That is the point of adding it there: the
resident path resolves it by `ParquetIndex` against a column and the streaming path takes it
off the row stream, so it is the one output a shared defect could not produce identically by
accident. The fixture gives every row a distinct RT, scrambled against the row ordinal, so an
off-by-one cannot land on a matching value.

### Verified before mirroring the bed

`chs446-mdiagtest-copy`'s 1st-pass sidecars are hard-linked into EIGHT other run dirs. A
delete-then-move (what `FileSaver.Commit` does) replaces the directory entry and leaves the
other links on the old inode - confirmed on this machine with a two-link probe before any
mirror was made. So the regen rewrites only its own copy.

### In flight overnight

`ai/.tmp/sessions/20260914-apexrt/run-446-apexrt.ps1`, one detached driver chaining both
phases so phase 2 starts when phase 1 VERIFIES rather than when someone notices it finished:

1. regen `chs446-apexrt-base` - `--task FirstPassFDR -NoModelDiagnostics`, ~5h11m
2. gate: 446 sidecars AND every header v7/pass-1 (count alone would accept 446 untouched v6
   files; presence alone would accept a partly-rewritten bed)
3. measure `chs446-apexrt-paylater` - the pay-later fold, ~58m, comparable to
   paylater-446-v5/v6/v7 of 2026-09-13
4. perfviz

Success is the last ten minutes FLAT and the private floor drift collapsing from +25 MB/file
toward zero. If it does not go flat the LOH model is wrong, and that is the finding - the idea
does not get extended to a second pass on the strength of a hope.

### Still owed

* `regression.ps1 -Dataset StellarLibDecoy` on the committed tree. Deferred behind the 446 run
  deliberately: 64 GB of RAM against a 39 GB peak leaves no room for a second Osprey, and the
  paths it would newly cover (pass 2, resume, HPC modes) are not the ones tonight's runs
  exercise. Cell A already ran `--task FirstPassFDR --model-diagnostics` end to end on a real
  cohort at v7.
* `-Dataset All` before the PR is a merge candidate.
