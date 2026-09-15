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

### RESULT (2026-09-14 04:58): the 446-run panel went flat

Both phases of `run-446-apexrt.ps1` completed unattended and the gate between them passed
(446 sidecars, 0 not v7/pass-1).

| | pre-fix `paylater-446-v7` | `chs446-apexrt-paylater` |
|---|---|---|
| private peak | **25.3 GB** | **11.7 GB** |
| private floor | 13.1 -> 24.0 GB, +25 MB/file | 6.5 -> 9.2 GB, **+6 MB/file** |
| sustained 300 s | 23.1 GB (91% of peak) | 9.2 GB (79% of peak) |
| managed peak | 15.1 GB | 10.2 GB |
| duration | 1:04:15 | 1:02:55 |
| gaps >= 30 s | 0 | 0 |
| pass-1 panel product | — | **identical but for `generatedUtc`**, 233,498 bytes both |

Plots in `ai/.tmp/sessions/20260914-apexrt/apexrt-{before,after}.png`, and they are the thing
to read: before is flat at ~7 GB for fifty minutes then a steep ramp to 25.5 GB with the
managed heap sawtoothing 6 -> 15 GB under it; after is flat at ~7 GB for fifty-five then a
gentle rise to 10.4 GB with managed level at 4.7 GB and no sawtooth.

Panel internals: 13,954,867 detected rows over 446 files in 492.7 s; boundary experiment 2.8571
from 37,139 accepted precursors; decoys admitted 369, tallied 369.

**The approach is proven for FirstPassFDR**, which was Brendan's precondition for carrying the
idea further. The pass-2 panel still needs nothing done to it - it builds from the resident
reported pool, where `FdrEntry.ApexRt` is already populated.

#### What the prediction got wrong, and it matters

`ai/.tmp/sessions/20260914-apexrt/prediction.md` was written BEFORE the run. Peak, flatness,
unchanged numbers and wall time all came in at or better than predicted. The miss: it predicted
the floor drift would collapse "toward zero" and it collapsed to **+6 MB/file**, still RISING -
2.78 GB across the cohort that is NOT the parquet read.

Its nature is undetermined and should not be guessed at. The pre-fix drift was +25 MB/file
private against +2 MB/file managed, i.e. almost entirely committed-but-free LOH; tonight it is
+6 against +4, so proportionally much more managed - but `--memstamp` counts uncollected
garbage, and removing LOH pressure gives the GC less reason to run, which inflates an apparent
floor by itself. **Next measurement: one pay-later run with `OSPREY_LOG_MEMORY=1` against
`chs446-apexrt-base`** (~63 min, no regen) to separate live from uncollected. Unmeasured
candidate: the panel's own `_byPrecursor` / `_offendersByPair`, which grow with DISTINCT
precursors rather than with files.

#### The cost this change adds to Stage 5: +7.1%, measured

Phase 1 was `--task FirstPassFDR` on the same cohort as the 2026-09-08 baseline run, so it is
a real A/B for the extra column:

| phase | baseline | tonight | delta |
|---|---|---|---|
| stub load (counts-only projection; NOT this change) | 10m25s | 9s | -616 s |
| ingest (subsample) | 33m24s | 36m01s | +157 s |
| scoring (pass 1, writes the sidecar) | 1h06m31s | 1h10m48s | +257 s |
| rest (pass 2 + protein FDR + writes) | 3h00m46s | 3h14m09s | +803 s |
| total | 17,516.9 s | 18,101.9 s | +585 s raw |
| peak working set | 40.8 GB | **39.2 GB** | -1.6 GB |

The raw +3.3% understates it: an unrelated saving on this branch returns 616 s at the front.
Against a comparable base it is **+1,201 s, +7.1%** - ~20 min on a 5-hour Stage 5 - and the
three phase deltas sum to 1,217 s against the 1,201 s the correction predicts. Memory did not
regress.

Two costs are mixed and this run cannot separate them: the extra READ (one column on four
passes, three of which never use it - avoidable with an opt-in on `ReadFdrStubScalars`) and
the FORMAT (29% wider sidecar, ~48 GB of bed instead of ~37 GB, written once and read back by
protein FDR, compaction and every later consumer - not avoidable). The ingest pass isolates the
read alone at +157 s; if that holds across all four the avoidable share is ~470 s, about 8
minutes. **Left as Brendan's decision, not landed overnight** - it is one bool threaded through
the `streamFileRows` delegate, and whether ~2.6% earns a parameter on a five-call-site method
is a judgement, not a measurement.

### Open design question (Brendan, 2026-09-14): is the sidecar being fitted to today's consumer?

Raised after the result: the blib `RetentionTimes` row is `retentionTime, startTime, endTime,
score`, so the natural per-run observation record includes the peak BOUNDS. v7 carries apex
only. If a future statistic wants bounds - and a peak-INTERVAL-overlap co-assignment measure is
more natural than the |dRT|-between-apexes one the panel computes today - we are back to a
panel reading a parquet column per file, and back to this memory profile.

**One premise needs correcting.** The blib does not read the sidecar. `BlibOutputWriter` builds
each RetentionTimes row from the resident reported pool at pass 2, where `FdrEntry.ApexRt` /
`StartRt` / `EndRt` (Osprey.Core\FdrEntry.cs:132-134) are all in hand. So there is no broken
supply chain. What is real is that we now keep TWO records of the same entity - one per-run peak
observation - carrying different subsets of it, and nothing justifies the difference.

**What it would cost to carry the whole peak.** Measured tonight: one column is +7.1% of
Stage 5 (~20 min on the 446 cohort). Adding start_rt and end_rt is roughly 3x that, about an
hour per Stage 5 run, paid by every run forever. So "carry the peak as insurance" is not cheap.

That 3x is a LINEAR EXTRAPOLATION from a single column, not a measurement, and it should be
labelled as one whenever it is quoted. What supports linearity is the mechanism (per-row-group
column decode, and all three columns are f64) plus one corroborating point from 2026-09-13:
narrowing the panel's own two-column read to roughly two-thirds of its bytes took its
allocation 29 -> 22 MB/file, close to proportional. What is NOT established is that DECODE TIME
scales the same way as allocated bytes - per-column fixed overhead would make 3 columns cost
less than 3x. If the decision turns on this number, measure it rather than trusting it.

**Why it is expensive is the useful part.** Not the file's width - that is sequential IO, the
cheap half. It is that each column is decoded out of the parquet on FOUR passes of the score
pass (subsample, pass 1, pass 2, protein-q resolve) and THREE never use it. The ingest pass,
which neither writes nor reads back a sidecar, still slowed 7.8% on one column. So the
diagnosis is not over-tuned file, it is wrong courier.

**Hard constraint either way.** The sidecar reader walks 2,048 records per buffer to stay under
the 85,000-byte LOH threshold, capping RecordLength at **41 bytes**. v7 at 36 fits; apex +
start + end at 52 does not and forces `RECORDS_PER_CHUNK` down. Not a blocker; it does say the
format is near a natural size.

**Recommendation**: keep v7 (proven 2x, and reverting costs another regen per bed); do not
widen speculatively; land the opt-in on `ReadFdrStubScalars` - it recovers most of the +7.1%
AND makes every future column cost a quarter as much, which is what turns this from a one-off
tune into the general answer. Widen now ONLY if there is a concrete near-term statistic wanting
bounds, since each format bump costs ~5 h of regen per bed and two bumps are much worse than
one. That question is Brendan's to answer.

### Gate (2026-09-14): green after teaching the comparison harness v7

Run 1 (05:00, 30m52s): 24 of 26 checks, exit 1. The only failure was
`mode3 (per-file FDR sidecars==straight)`, and it was GATE-SIDE:
`pwiz_tools/Osprey/Regression/FdrSidecars.ps1` hard-coded the v6 28-byte layout and REFUSED to
decode v7 rather than mis-decoding it, naming its own fix in the message. Mode 1 vs the
committed C# golden was green, so the change is output-neutral.

Run 2 (05:31, 28m32s): **25 of 25, exit 0**, including
`mode3 (per-file FDR sidecars==straight): PASS`. Fix committed as `48f4307297`: `RecordLen`
28 -> 36, `ExpectedVersion` 6 -> 7, and `apex_rt` added to the compared-fields table. That last
part earns its place - the straight route and the HPC per-file route obtain apex RT from
different sources (streaming row source vs `FdrEntry.ApexRt` on the resident reported pool), so
it is one of the few columns a shared defect could not produce identically by accident. They
agree.

Still owed before this is a merge candidate: `regression-parallel.ps1 -Dataset All`, and
`/code-review max` from `C:\proj\pwiz-work2`.

## 2026-09-14 (morning): SecondPassFDR diagnostics - first profile, and where its memory goes

Brendan asked for an isolated look at the pass-2 half of `--task ModelDiagnostics`. Run:
`--task SecondPassFDR --model-diagnostics` pay-later fold, 446 runs, on the ORIGINAL v6 bed
with a pre-v7 binary, so the apex_rt work cannot confound it (the pass-2 co-assignment panel
never joined a parquet - it builds from the resident reported pool - so nothing is lost by
measuring before the change).

### Staging traps, both hit and both caught early

* `out.model-diagnostics.html` is ALSO a declared output of SecondPassFDR
  (`ModelDiagnosticsReport.ReportPath`). Withholding it makes a declared output missing and the
  task runs a GENUINE second pass (~2 h) instead of folding the report. Withhold ONLY
  `out.2nd-pass.model-diagnostics*`. Caught at 3 minutes by reading the route marker, not at
  2 hours by reading the clock.
* `;fdrsidecar=` is in SecondPassFDR's validity key too, so a v7 binary against a v6 bed
  abandons the pay-later arm. The probe binary was therefore built by cherry-picking the probe
  commit onto `4a715d004c` (pre-v7) - `SecondPassFdrTask.cs` is untouched by the v7 work, so it
  applies clean. Snapshot: `D:\test\osprey-runs\_bin\pass2probe-v6`.

### The profile

21m42s unprobed / 17m37s probed, exit 0, products identical. Peak 22.6 GB, sustained
20.5 GB at 91% of peak. Phases, and only ONE of them grows:

| phase | floor (p10) | end | duration |
|---|---|---|---|
| startup + library | - | 11.7 GB | 30 s |
| the overlays | 12.5 GB | 20.7 GB | ~8 m |
| mdiag fold | 19.6 GB | 20.7 GB | 7m22s |
| co-assignment panel | 19.7 GB | 20.7 GB | 5m11s |

The pass-2 co-assignment panel is NOT the story, unlike pass 1's - it is 5 of 22 minutes and it
runs ON the plateau rather than creating it. There is no apex_rt-shaped fix to carry over here,
because there is nothing of that shape.

### The +19 MB/file "drift" does NOT scale - correcting an earlier claim

perfviz reported `+19 MB/file RISING`, which reads as O(files). Windowing by run index:

| runs | growth | per run |
|---|---|---|
| 0-112 | +7.71 GB | +70.8 MB/run |
| 112-223 | -0.36 GB | -3.3 MB/run |
| 223-334 | +1.08 GB | +9.9 MB/run |

86% arrives in the first quarter and one window is NEGATIVE. It is an accumulator filling
toward a bound, ~86% saturated by run 112 - a linear fit across a saturating curve. Read the
plot before quoting a drift number, which is what `feedback_read_the_perfviz_png_not_the_probes`
already says. Residual risk: the last window is +9.9 MB/run, not zero, so a small genuinely
linear term may hide under the noise; an 86-file comparison would settle it.

### Probes added (commit `2a30b1196d`) and what they show

Three `ProfilerHooks.LogMemoryStats` calls bracketing the join in `FoldPass2DiagnosticsOnly`,
plus dotMemory snapshots at the same points.

| probe | working set | managed | committed | LIVE (gc_heap_last_gc) |
|---|---|---|---|---|
| before the join | 0.04 GB | 0.00 | 0.00 | 0.00 |
| after `RescoredEntries` | 11.37 GB | 5.29 | 10.09 | 4.19 |
| after the overlays | 21.31 GB | 8.63 | 20.98 | 8.33 |

So the ~9.9 GB the overlays add is 4.14 GB LIVE + ~5.8 GB committed-but-free (18 gen2/LOH
collections across the phase, fragmentation 0.02 GB). Neither "all churn" nor "all retention" -
42/58, and the two halves have opposite fixes.

Note `ctx.Get<RescoredEntries>()` completes in 33 s at 11.37 GB: it is the library load and
setup, NOT the 446-run fold. The `Second-pass join: folding over 446 run(s)` line is logged at
the Stage-6 DECISION point and returns a lazy fold; the folding happens under the overlays.

### Library-vs-cohort: the ratio, and what is already built

625,620 retained base_ids against 6,175,389 library entries - the cohort needs ~10%.

Confirmed instance: `SecondPassFdrTask.cs:868` sizes the co-assignment run-scope arrays from
`MaxBaseId(classByBaseId)` - the LIBRARY - where pass 1 sizes them from `experimentRecords.Keys`.
Two `double[]` of maxBaseId+1 = ~99 MB. Real, free to fix, and ~1% of what we are chasing.

`LibraryLoadOptions` ALREADY HAS `RetainFragmentsFor { get; set; }` (a `HashSet<uint>`),
threaded through `LibraryLoader.Load` -> `LibraryCache.LoadCache(..., options.RetainFragmentsFor)`.
It was proposed in TODO-20260717 ("Proposed lever (candidate, not yet built):
`LibraryLoadOptions { OmitFragments }`") and BUILT. It has no production setter - the only
construction in the tree is `PerFileScoringTask.cs:1031`, which sets `OmitFragments` alone. And
`SecondPassFdrTask.cs:983` documents the consequence: this leg "loads the library
fragment-laden (`OmitFragments` is gated on `StopAfterStage5`, false here)".

Meanwhile `out.1st-pass.retained_base_ids.bin` is a persisted 2.5 MB artifact of exactly those
625,620 ids, read from CONFIG ALONE by `ScoringTaskShared.ReadRetainedBaseIds` - and
`PerFileRescoreTask.cs:2218` already reads it on this very leg ("625620 retained base_id(s)
read once"). So this is not "introduce a capability"; it is an ORDERING problem between two
things that already exist and already meet on this code path.

Worth 2.83 GB (the 4.19 GB library here against 1.36 GB for the identical library on the
pass-1 fold - confirmed across BOTH binaries, so not code drift). On this leg
`LibraryFragmentRelease` never runs at all: it lives at `SecondPassFdrTask.cs:981-989` and needs
`rescored.StreamFiles(...)`, which the pay-later fold has no pool for. Load-then-drop does not
just cost time here - the drop never happens.

### What the 4.14 GB LIVE is - UNRESOLVED

Named from code, all experiment-wide and all keyed at library scale:

| structure | shape | est. |
|---|---|---|
| `experimentRecords` | `Dictionary<uint, FdrExperimentRecord>`, 6,044,771 | ~400 MB (code says so) |
| `minRunBothByEntryId` | `Dictionary<uint, double>` | ~240 MB |
| `minRunBothByPeptide` | `Dictionary<(string, bool), double>` | ~270 MB |

~0.9 GB of 4.14. The obvious suspect was RULED OUT: `byEntryId`
(`Dictionary<uint, FdrEntry>`, hoisted outside the per-file closure, ~274 B/entry) is a reused
scratch buffer cleared per file at `Pass2FdrSidecar.cs:637`. Same at :573 and
`Pass2SidecarWriter._byEntryId` :1212. Correctly written; not it.

~3.2 GB unaccounted. Further code reading is guesswork; dotMemory is the tool, and the
snapshots are already wired. Arithmetic that motivates the retained-set question: 4.14 GB over
6,044,771 experiment records is ~685 B each (plausible); over 625,620 retained base_ids it is
~6.6 KB each (not plausible). So the live pass-2 state is shaped like the library, not the
cohort - inferred from a ratio, NOT identified, and that distinction matters.

### Opportunity on a 22.6 GB peak

| | size | status |
|---|---|---|
| library fragments never released on this leg | 2.83 GB | machinery exists, unwired |
| live pass-2 state, if cohort-sized | up to ~3.7 GB | shape inferred, structures unidentified |
| committed-but-free churn | ~5.8 GB | separate, allocation-shape |
| run-scope arrays sized from the library | 99 MB | one-line fix |

Per Brendan: the systematic sweep of library loading and retention belongs to issue #4650 -
pass-2 rehydrate should avoid LOADING spectra it will not need rather than load and drop. The
risk to carry into that work: filtering the library makes lookups for non-retained ids MISS
where they used to hit, and the co-assignment panel does exactly that lookup with a base-id
fallback. The code comment there records what happened last time a lookup silently thinned -
the decoy class 30x under-reported, "19 counted against 598", nothing in the output to say so.
A filtered load needs a proof that every consumer only asks about retained ids, and a hard
failure rather than a miss when one does not.

### dotMemory run in flight

`ai/.tmp/sessions/20260914-apexrt/run-pass2-dotmemory.ps1`. `--use-api`, so snapshots are taken
only at `pass2-join-start` / `pass2-join-end`; the DIFF is the 4.14 GB by type and retained
size. Two gotchas already paid for: the bed must be RESTAGED (the probed run consumed the
withheld product, so a re-run would profile an early return), and the app args need `--` to
escape them or dotMemory parses Osprey's `-i`/`-l` as its own and exits 1024 instantly.
dotMemory has no text interface - Brendan opens the `.dmw`.

## 2026-09-14: the experiment sidecar persists a q-value the pipeline then overrides

Found by the floor counter added in `19708cccdb`. This is a sidecar DEFICIENCY, not a
diagnostics problem, and it is the kind this validation phase exists to catch.

### The measurement

`--task SecondPassFDR --model-diagnostics` on the 446-run cohort, counting what the pass-2
re-apply of the best-of-runs clamp actually RAISES:

| | |
|---|---|
| applications | 892 (= 2 per run x 446 - every run is materialised and re-floored TWICE) |
| values raised | 1,125,526 of 593,865,660 |
| overall rate | 0.1895% |
| per application | min 1,169, median 1,259, max 1,392 (0.158% - 0.248%) |
| corr(raised, rows) | 0.976 |

Uniform, systematic, ~1 row in 530. NOT a few pathological entries.

### Why it happens - documented, and the docs are right

`docs/07-fdr-control.md` section 3j: experiment-level FDR competes each precursor's single
best observation against a thinner de-duplicated decoy null, so the raw experiment q can fall
BELOW every per-run q, "producing reported peptides with no run-level ID line". The clamp
floors experiment q up to the entry's own min-over-runs combined run q. And the re-apply
exists because "reconciliation resets the run q-values of moved and gap-filled peaks (issue
#4390)" - step 5 of the doc's list is the clamp, step 8 is "Re-apply the best-of-runs clamp".

`SecondPassFdrTask.cs:500-506` says the same in its own words: Stage 6 "zeroes the run q of
moved peaks AFTER that clamp", and the re-clamp runs "against the run q's actually written to
the blib", restoring "reported => some run genuinely passed" for the final output.

So the clamp is correct and necessary. The counter proves it is not redundant - an earlier
hypothesis that it was is DISPROVED, and deleting it would change 1.1 M user-visible q-values.

### The deficiency

`ReclampExperimentQToBestRun` mutates the ENTRIES (which feed the blib). The
`FdrExperimentAccumulator` behind `out.2nd-pass.fdr_experiment.bin` keeps the PRE-clamp value.
Ordering is not the problem - `WritePass2ExperimentSidecar` runs inside `RunProteinFdr`, well
after the re-clamp at `:506` - the accumulator simply is not the thing the clamp updates.

**Consequence: the experiment sidecar holds a q-value the pipeline itself considers wrong, and
the corrected value exists only inside the .blib.** Anything rebuilding from the sidecar - the
mdiag pass-2 fold, any future consumer - must re-derive the floor by re-materialising every run,
or silently report the un-floored number. That is the 8-minute traversal and the ~4.3 GB of live
growth measured in the profile above, twice over.

### The fix (Brendan, 2026-09-14): store both at experiment level

`FdrExperimentRecord` gains the two floors - they key differently, so both are needed:

* `MinRunQByEntry` - the min-over-runs combined run q for this entry_id
* `MinRunQByPeptide` - the same for this entry's `(ModifiedSequence, IsDecoy)`

44 B -> 60 B; the 446-run pass-2 sidecar goes 54.5 MB -> ~74 MB. The raw competed q is KEPT,
so both numbers are on disk: a consumer applies `max(raw, floor)` to get what the user saw, and
an analyst can still see the un-floored competition result. It also makes an invariant checkable
that is not today - `floored >= raw`, and the blib agrees with the floored value.

**No bed invalidation.** `FdrExperimentSidecar.FormatVersion` is in NO validity key (unlike
`FdrScoresSidecar.FormatVersion`, which cost a 5h11m regen for apex_rt). But that also means a
naive bump is WORSE than that one: a v2 file would look current to its owning task and then fail
the version check on read. So the reader must accept v2 AND v3 - v2 yielding NaN floors, meaning
"unknown, recompute" - which is the graceful-growth shape discussed against Skyline's
`StructSerializer.ItemSizeOnDisk` earlier today, and degrades exactly to today's behaviour.

Payoff: the mdiag pass-2 fold reads two numbers per entry instead of materialising 446 runs
twice, which removes the traversal AND whatever `StreamFiles` retains during it.

## 2026-09-14 (afternoon): root cause of the 0.19%, and the re-clamp's fold is gone

The floors work from the morning was built the wrong way round and has been re-cut. What
follows is the finding first, because it changes what the fix IS.

### Root cause: the second pass never floors the experiment q it computes

`Pass2FdrSidecar.FinishRecord` - the sweep that builds the analysis-wide experiment records
inside the protein-compact competition, which is the SHIPPED DEFAULT - produces
`new FdrExperimentRecord(rec.EntryId, eq, eq, ...)` with no best-of-runs floor applied.
`ClampExperimentQToBestRunFlat` is called from `StreamingFdr.cs:128` and
`PercolatorTrainer.cs:364` only, both FIRST pass. So:

* pass-1 experiment q is floored in-pass, before it is written
* pass-2 experiment q is **not floored when it is computed**
* the only thing that floored it was `ReclampExperimentQToBestRun`, afterwards, onto the
  ENTRIES - never onto the record the sidecar is written from

That is the whole of the 1,125,526 values / 0.19% measurement, and why the file disagreed with
the .blib.

**Both strata, by two different routes** (Brendan's hypothesis, confirmed):

| stratum | what it gets | why it can fall below its own best run |
|---|---|---|
| on-stratum | a fresh second-pass competition q | never clamped at all |
| off-stratum | its pass-1 q, carried | that q WAS clamped - against pass-1 run q - while pass 2 refreshed run q underneath it, a run that did not compete taking 1.0 |

One rule applied to every record closes both. The earlier "is the re-clamp redundant?"
hypothesis stays DISPROVED, and now for a reason rather than a measurement.

### The fix: fold where the records already stream, apply where the pool already materialises

The sweep at `Pass2FdrSidecar.cs:2383` reads every file's `.2nd-pass.fdr_scores.bin` to build
the experiment records, and each record carries `RunPrecursorQvalue` / `RunPeptideQvalue`. So
the per-entry min-over-runs costs **one comparison per record and no IO of its own**.

The PEPTIDE floor is derived from the entry floors by grouping through the library's own
`(ModifiedSequence, IsDecoy)` - exact, not an approximation, because `min` is associative:
min over a peptide's rows == min over its entries of each entry's min over rows. The library is
a legitimate identity source here because a generated decoy is a full `LibraryEntry` of its own
(`DecoyGenerator.cs:134`: `Id = target.Id | 0x80000000`, `"DECOY_" + target.ModifiedSequence`)
and `PerFileScoringTask.cs:1120` puts them in `fullLibrary`, so a target can never inherit its
paired decoy's bucket.

Both floors are stamped onto the records before anything reads them, so the FILE is final.
The pre-blib step is now an APPLY only (`Pass2FdrSidecar.ApplyExperimentQFloors`), riding the
per-run materialisation the blib gates already do.

**What went away: a full extra traversal of every run.** `ReclampExperimentQToBestRun`'s fold
half (`rescored.StreamFiles(@"Folding experiment-q floors")`) is deleted. That was 8 minutes
and a multi-GB working set at 446 runs, paid by EVERY analysis whether or not anything asked
for diagnostics. So the ordinary no-diagnostics path gets faster, not slower - which was
Brendan's question about the morning's cut, and the morning's cut had the wrong answer to it.

A record reaching the apply without floors is now a **hard throw**, not a silent re-derivation:
it means some pass-2 path computed an experiment q and did not floor it, which is precisely the
defect above, and falling back quietly would let the next such path stay green.

### Discarded from the morning's cut

* the fold moved ahead of `RunProteinFdr` and threaded through it - gone
* the peptide floor denormalized through the reconciled parquet's `modified_sequence` column,
  one tuple-keyed string lookup per ROW (~297 M at 446 runs) - gone, replaced by one lookup per
  distinct entry against the library
* a `Pass2ExperimentQFloors` byproduct - unnecessary once the records themselves carry the
  floors, since they resolve the same way on both arms (in-memory scope, or the sidecar)

### Gate

`regression.ps1 -Dataset StellarLibDecoy` PASSED, exit 0, on the morning's cut (all checks,
including `mode1 (vs golden)`, `mode3 (HPC chain==straight)` - which byte-compares the
experiment sidecars, so both routes agree on the floors - `mode7`, and `mode11` pass-2
byte-exact). Re-running on the re-cut.

**`mode1 (vs golden)` is the equivalence oracle for the re-cut**: if the streamed floors differ
by one ULP from the ones the deleted fold produced, the blib's experiment q moves and mode 1
goes red against the committed golden.

New standing assertions in `regression.ps1` mode 11, because modes 7 and 11 pass whether the
floors were applied from the records or re-derived by a traversal - the report is identical
either way, so only the log can tell:

* marker: `experiment-q floors: applying`
* forbidden: `Folding experiment-q floors` (the deleted traversal's own progress heading)

Also fixed there: the experiment-sidecar compared-record count divided by 36 where the record
is 60 bytes (count only, never pass/fail).

### Trap paid

`-KeepRunDirs` is a STARTUP prune of ORPHANS; a run still deletes its own directory as it goes.
`-KeepOutput` is the flag that retains it. The first gate run was launched with the former, so
its Osprey logs were gone and the "did it read or re-fold?" question could not be answered from
them - which is what prompted putting the question in the harness instead, where it belongs.

### Still owed

* `regression-parallel.ps1 -Dataset All`
* the 446-run cohort with the re-clamp counter still in place: the counter must read ZERO. It
  is instrumentation that already exists (`19708cccdb`), and zero is what retires the apply's
  remaining justification with evidence rather than argument.
* `BuildExperimentScope` (the transfer arm) folds its peptide map from the entries' own
  `ModifiedSequence` but looks it up per entry through the library. Same string by
  construction, but the two arms should key identically - switch it to
  `DerivePeptideFloorsFromLibrary` so fold key and lookup key have one source.
* `/code-review max` from `C:\proj\pwiz-work2`

### 2026-09-14 (late): Stellar caught a route-dependent identity source, and the format grew a pass split

Two changes after the first green StellarLibDecoy gate, both prompted by Brendan.

#### The peptide floor must not come from the library

`-Dataset Stellar` went red on `mode3 (per-file FDR sidecars==straight)` - specifically the
experiment-sidecar byte compare inside it. Decoded record by record:

| | |
|---|---|
| records | 333,404 |
| entry-floor differences | **0** |
| peptide-floor differences | **166,680** - every one a decoy |
| straight route | real floors (e.g. entry_id 2147483651 -> 0.3348) |
| chain `--task SecondPassFDR` | **NaN** |

Root cause: the first cut derived the peptide identity for an entry_id from
`LibraryById`. A `--task SecondPassFDR` node loads a library with **no GENERATED decoys in
it**, so a decoy entry_id resolves on the straight route and resolves to nothing on the
distributed one. Exactly half the records, which is the target/decoy split.

**StellarLibDecoy could not have caught this** - there the decoys come from the library FILE
and are present on both routes. Only a generated-decoy leg exposes it, which is the argument
for the dataset matrix and for not deferring `-Dataset All`.

Fixed by taking the identity from the SURVIVOR WALK that `ComputePass2TransferCompeteFull`
already performs (`ExperimentQFloors.ObserveIdentities`), which is route-independent because
both routes build the pool from the same artifacts. The floors still come from the per-file
second-pass records; the two halves meet in `DerivePeptideFloors`, which is exact rather than
approximate because `min` is associative. No library, no parquet column, no extra walk.

The transfer arm's `BuildExperimentScope` now uses the same `DerivePeptideFloors`, which also
closes the fold-key vs lookup-key inconsistency noted as owed in the previous entry.

#### The experiment record width follows the PASS, not the version

Raised by Brendan: re-running `--task FirstPassFDR` at 446 files is **5 h 01 m** (measured, in
`chs446-apexrt-base/run.log`: `[TASK] FirstPassFDR:done (18101.9s)`), and it was being forced by
`;expsidecar=` in FirstPassFDR's and PerFileRescoring's validity keys - to regenerate a
first-pass file whose two new columns are NaN on every record.

The asymmetry has a principle behind it, which is now in `07-fdr-control.md` and on
`FdrExperimentSidecar.FormatVersion`:

> the floor can be omitted from a file exactly when the value and the run q it floors against
> were produced together and neither moved afterwards

* PASS 1 satisfies it. `PercolatorScorer` computes both floor maps and applies them in the same
  emit pass, over the same arrays; `FirstPassFdrTask.cs:2385` accumulates straight off those
  entries. Re-applying is `max(floored, floor)` - a no-op.
* PASS 2 breaks it in both branches of `FinishRecord`, as the previous entry records.

So: `RecordLengthFor(pass)` - 60 bytes second pass, **44 first**; `VersionReadable` accepts v2
or v3 for a first-pass file (identical layouts) and v3 only for second-pass; `;expsidecar=`
removed from FirstPassFDR and PerFileRescoring, kept on SecondPassFDR alone.

**Consequence: `chs446-apexrt-base` and `chs446-apexrt-paylater` stay valid through Stage 5**,
so a cohort measurement is `--task SecondPassFDR` (~20 min) rather than 5 h + Stage 6 + Stage 7.
Confirmed from the bed's own stamps: `PerFileScoring` keys on
`search=...;library=...;pick=lda;pickmodel=none` with no sidecar terms at all, so Stages 1-4
were never at risk - apex_rt was always a `.scores.parquet` column and v7 only carries it
forward.

The regression harness learned the same split (`ExperimentRecordLenFor(pass)` in
`FdrSidecars.ps1`, used by `CheckPass2ProteinQ` and `LoadExperimentMap`, and by
`regression.ps1`'s compared-record count).

#### Slip worth not repeating

`ExperimentQFloors.cs` was created with the Write tool and landed **LF** in a CRLF repo. It
passed build and inspection (CodeInspectionTest only catches MIXED endings, so an all-LF file
is invisible to it) and surfaced only because `cat -A` showed no `^M` while a patch script kept
missing its `\r\n` patterns. Any NEW file written into pwiz needs its endings checked, not
assumed - `fix-crlf.ps1` did not catch it either, since the file was still untracked.

#### Gate status

* StellarLibDecoy, streaming floors, exit 0 - all checks including `mode1 (vs golden)`,
  `mode3 (HPC chain==straight)`, `mode7`, `mode11`
* Sidecars decoded directly: 313,537 records, both floors on every one, identical across routes;
  the deleted whole-run fold appears in no log on any route
* Stellar, streaming floors: red as above - now fixed
* Unit gate 594/594, inspection zero warnings on the current cut
* `regression-parallel.ps1 -Dataset All` in flight

### 2026-09-14 (evening): the format change is OUT; the floor is applied at the source

Brendan retracted the format-change direction, and the reasoning is worth keeping because it
generalises: the experiment sidecar holds DERIVED values - the model q-values cannot be
reconstructed from it in any case - so storing the raw competed q beside the floor, to make the
correction re-derivable later, preserved only WHICH ~0.1% of entries the floor moved. That is not
worth a wider record and a format version. It was a BUG that the second pass wrote an unfloored
q, and the fix belongs where both the value and its floor are in hand.

**Net effect: NO format change at all.** `FdrExperimentSidecar` is back at v2 / 44-byte records
for both passes, `FdrExperimentRecord` back to its six fields, and `;expsidecar=` is gone from
all three validity keys - so nothing invalidates any bed. Commits `7cf1ef2db6` and `21d3394490`
are fully reverted in the working tree; the squash-merge collapses that cleanly.

#### What the change is now

* the pass-2 sweep that builds the experiment records folds each entry's best-of-runs floor out
  of the per-file `.2nd-pass.fdr_scores.bin` records **it is already reading** - one comparison
  per record, no IO of its own
* the peptide floor is derived from those entry floors, grouped through identities recorded on
  the survivor walk that sweep already performs (`ExperimentQFloors.ObserveIdentities` /
  `DerivePeptideFloors`); exact because `min` is associative
* `FdrExperimentAccumulator.ApplyRunQFloors` raises both q-values before the records are written
* `ReclampExperimentQToBestRun` is **deleted entirely** - both the whole-run fold and the apply

**`mode1 (vs golden)` is the proof and no separate validation run is needed**: the committed
golden .blib was produced WITH the old re-clamp, so flooring at the source has to reproduce it
byte for byte.

#### Scope: #4662 will carry "Fixes #4664"

Today's fold re-derived what `9a85f68a8b` deliberately reverted to issue #4664 - I did not know
that branch existed until Brendan's 2026-09-13 perfviz log showed a floors line no code on this
branch could emit. Per Brendan: #4664 was created early, when stopping after FirstPassFDR looked
possible; the possibility of further sidecar format changes (now avoided) convinced him to treat
this whole area as one PR. So #4662 gains `Fixes #4664` rather than the work moving.

Worth carrying forward from that revert, because only ONE of its two causes is addressed:

| revert cause (`9a85f68a8b`) | status here |
|---|---|
| "still decodes ~366 M sequence strings" | **gone** - identity comes from the survivor walk, not the parquet column |
| "with the pool materialization gone nothing forces a collection inside the window, so the heap drifts" | **untested** - the pre-blib traversal is deleted here too; only the 446-run number can say |

That second row is what the overnight bed exists to answer. The earlier measurement was
38.2 -> 44.4 GB committed peak.

#### What the dotMemory workspace actually showed

Read with Brendan at a machine. The probes did NOT bracket what the handoff assumed:

| snapshot | total | .NET used | live objects |
|---|---|---|---|
| `pass2-join-start` | 81.63 MB | **573.5 KB** | **4.8 K** |
| `pass2-join-end` | 13.57 GB | 4.70 GB | 28.05 M |

573 KB / 4.8 K objects is a process that has loaded nothing - `CaptureRetentionSnapshot` fired
before `ctx.Get<RescoredEntries>()`. The comparison confirms it: 4.70 GB **New**, 477.6 KB
survived. So the delta was the whole stage's working set measured against an empty process, not
"what the overlays retain".

The type breakdown settles the attribution. Of 5,047,750,287 New bytes:

| type | new objects | new bytes |
|---|---|---|
| `LibraryFragment[]` | 6,175,390 | **3.04 GB (60%)** |
| `LibraryEntry` | 6,175,389 | 543 MB |
| `String` / `String[]` | ~5.7 M / 6.18 M | 310 MB / 200 MB |
| `Dictionary+Entry<UInt32, LibraryEntry>[]` | 1 | 173 MB |
| `Modification` / `Modification[]` / `LibraryEntry[]` | - | 184 MB |
| **library subtotal** | | **~4.59 GB, 91%** |
| `FdrEntry` (the survivor pool) | 628,645 | 131 MB |
| `Dictionary+Entry<UInt32, FdrExperimentRecord>[]` | 1 | 89 MB |

**So the entire pass-2 experiment-scope machinery, floors included, is ~300 MB against 4.59 GB of
library.** The "~4 GB unaccounted in a loop whose only product is 90 MB" was a probe-placement
artifact. There is no retention bug in that loop. FIXED: `pass2-join-start` now fires after the
lazy byproducts resolve, so the pair brackets the overlays.

Brendan's reading of the managed-heap plot also holds: total used sawtooths to a ~7 GB post-GC
floor that does NOT drift across 27 minutes, with `Allocated in LOH since GC` cycling 0 -> 4-5 GB.
20-30 GB private bytes is Server GC committed expansion under allocation pressure, not held
memory.

And on the original perfviz plot: the ~45 GB apex is at 09:31-09:35, while
`SecondPassFDR: folding the second pass` logs at 09:39:34 on the DESCENDING side (19,127 MB
managed at 09:39:52 -> 7,148 MB seven seconds later). Pass 2 inherited the apex rather than
causing it.

#### #4650 (spectra at rehydrate): still unwired, and NOT applicable yet

Verified rather than taken from the handoff: `RetainFragmentsFor` has exactly two references -
its declaration (`LibraryLoadOptions.cs:77`) and the pass-through at `LibraryLoader.cs:111`.
**Nothing assigns it.** The one production construction site, `PerFileScoringTask.cs:1031`, sets
only `OmitFragments`. Everything around it is finished: the artifact is written
(`FirstPassFdrTask.cs:2598`), the reader exists and is already called on the right legs
(`ScoringTaskShared.ReadRetainedBaseIds`), and the cache loader honours the set once given it.

A gap to close WITH it: the skip path in `LibraryCache.cs:335` assigns
`Array.Empty<LibraryFragment>()`, which is the READABLE empty spectrum. `ReleaseSpectrum`'s
`RELEASED_SPECTRUM` singleton throws on every access including `.Count`, turning the universal
`Fragments == null || Fragments.Count == 0` guard into a tripwire. A never-allocated entry should
take the loud state, not the quiet one - otherwise a wrong retain-set writes a thin .blib
silently instead of throwing.

Per Brendan this waits until a fully valid Stage 5-7 bed exists.

#### Night run prepared

`ai/.tmp/sessions/20260914-3753ea36/run-chs446-floors.ps1`, `-WhatIf` verified: 446/446 files,
1784 Stage 1-4 artifacts hard-linked from `chs446-apexrt-base` (0 missing), version pinned to
26.1.1.243 by `-LinkFrom`, `--timestamp --memstamp`, `--model-diagnostics` ON.

**The `-WhatIf` caught a full-re-run mistake**: the runner's default library resolution picks
`target+decoy+entrapment` (13.09 GB, June) where the bed used `...-20260817` (12.39 GB, August).
A different library changes the `library=` validity term and invalidates every linked artifact.
`-LibraryDir` now pins it.

`--model-diagnostics` stays ON by agreement: the bed then carries a flag-up-front report as the
byte-comparison oracle for tomorrow's pay-later fold at cohort scale, and a run without
diagnostics is imitated by deleting the JSON + HTML afterwards.

#### Process mistakes, so they are not repeated

* **`git checkout master -- <file>` where `HEAD` was meant, twice.** It cost `IOTest.cs`'s
  apex_rt updates (caught by the build in seconds) and `FdrSidecars.ps1`'s v7 layout knowledge
  (caught an hour later, as Astral mode 3 red on a HARNESS artifact). Audit first:
  `git log --oneline master..HEAD -- <file>` says whether a full revert is right.
  `FdrSidecars.ps1` is touched by TWO branch commits and only one was being undone.
* **A Monitor liveness check that greps for `Osprey.exe`** reports "process gone" between gate
  phases, when no Osprey is running. Key on the launcher's parent PID instead.
* **`-KeepRunDirs` is a STARTUP prune of ORPHANS**; a run still deletes its own directory.
  `-KeepOutput` is the flag that retains it.
