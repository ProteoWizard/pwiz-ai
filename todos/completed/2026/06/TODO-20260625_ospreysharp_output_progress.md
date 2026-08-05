# TODO-ospreysharp_output_progress.md

## Status
- **Type**: OspreySharp CLI output (final tuning round; follow-on to PR #4326 / #4327)
- **Branch**: `Skyline/work/20260625_ospreysharp_output_progress` (started 2026-06-25)
- **PR**: [#4332](https://github.com/ProteoWizard/pwiz/pull/4332) (merged 2026-06-25 as bcc9480774)
- **Status**: Completed. The final OspreySharp output-tuning round + Stage 6 rescore parallelization.
- **Packaging**: Part 1 (5s I/O interval) rides along in the SAME PR as Part 2 (the parallel-files
  MultiProgressReporter) -- the 5s tweak alone isn't worth a PR cycle (Brendan, 2026-06-25). One PR
  for both.

# Final tuning round for OspreySharp console output

Two parts: a small immediate tweak (done), and the larger open design problem of progress
reporting under parallel-file processing.

## Part 1 - I/O reporting interval 5s (DONE this branch)

The I/O `ProgressReporter` cadence was 2s, which on HRAM/Astral-class data emits a long string
of percent lines for the 30-47s I/O steps. Brendan's call: 5s is still reassuring to a watching
user (they won't think it hung) while cutting the clutter.

- Added `ProgressReporter.IO_INTERVAL_SECONDS = 5.0` (Core) and applied it to the four I/O
  reporters: mzML read (`MzmlReader`) and the three parquet build/write loops
  (`ParquetScoreCache`). The compute loops (e.g. `ScoringPipeline` isolation-window scoring)
  stay at 2s -- they advance smoothly and a tighter cadence reads as healthy progress.
- Output-only; no parity impact. Validate with the standing gates (build + tests + inspection;
  `regression.ps1 -Dataset Stellar` stays byte-identical -- progress lines are not compared).

## Part 2 - Progress + output under `--parallel-files != 1` (THE open problem)

### The goal: mimic Skyline's MultiProgressStatus
When more than one file is processed concurrently, Skyline collapses the per-file progress onto
a **single throttled line** that shows every active file's percent at once, updated in place:

```
[1] 11%  [2] 12%  [3] 11%  [4] 11%  [5] 11%  [6] 11%
[1] 12%  [2] 13%  [3] 12%  [4] 12%  [5] 12%  [6] 12%
...
[15] 96%  [16] 83%
[16] 96%
```

Reference: `G:\My Drive\Claude\Import_20191009_170333-skyline.log`, lines **18-478** (16-file
parallel load/score on a Navarro SWATH benchmark). The section that **follows** (lines 479-548)
is the single-status tail Osprey already mirrors in spirit: file join, "Training scoring model
(iteration N of 10 - ... peaks at X% FDR)", and the score-contribution table

```
Intensity: 0.4074 (13.2%)
Library intensity dot-product: 6.0406 (54.8%)
Shape (weighted): -0.8902 (-10.7%)
...
```

-- which is exactly the feature-weight + percent-contribution table OspreySharp now emits (PR
#4328). So Part 2 is specifically the **multi-file, concurrent** progress line; the
single-status pipeline tail and the weights table are already in place.

As with #4326, use the existing OspreySharp `ProgressReporter`, **NOT** a port of Skyline's
`IProgressMonitor` / `ProgressStatus` / `MultiProgressStatus` (decided too big a refactor for
the features we need). We want a `MultiProgressReporter`-style aggregator that owns N child
percents and renders the one-line `[i] p%` summary on the same 2s/5s throttle.

### Why this is harder in OspreySharp than in Skyline
Skyline's parallelism is **file-parallel end-to-end**: each file loads + scores on its own
thread, so a per-file `IProgressStatus` maps cleanly to one `[i] p%` slot.

OspreySharp's `--parallel-files` parallelism is shaped differently: **single-file spectrum
loading (sequential I/O) followed by parallel scoring** (the `Parallel.For` over isolation
windows in `ScoringPipeline`). So "file i is at p%" is not a single thread's progress -- the
work for a file is split across an I/O phase and a fan-out compute phase, and multiple files'
phases interleave. Tracking *single-file scoring progress in parallel-file mode* therefore needs
an explicit per-file progress accumulator that the parallel scoring loop updates by file, fed
into the one-line aggregator. This is the crux to design.

### Open tasks
1. **Survey the current `--parallel-files` path.** Where is the flag parsed, how are files
   dispatched (the single-load-then-parallel-score shape), and where would per-file percent be
   observable? Confirm the sequential-vs-parallel default and what `!= 1` actually changes.
2. **Design a `MultiProgressReporter`** (Core) that aggregates N per-file percents behind the
   same stopwatch throttle as `ProgressReporter` and renders the `[i] p%` line to
   `OspreyOutput.Out`. Decide how a file enters/leaves the active set (start at load? drop at
   blib write?) and how the I/O phase vs scoring phase each contribute to one file's percent.
3. **Wire per-file progress** from the spectrum-load + parallel-scoring phases into the
   aggregator, keyed by file index. Keep it deterministic enough not to garble under concurrency
   (the single line is rewritten, not appended; mind interleaving with other log lines).
4. **--verbose disposition.** Decide what extra per-file detail (if any) verbose adds; the
   one-line summary is the default-mode view.
5. **Gate**: output-only, so `regression.ps1` stays byte-identical; validate the multi-file run
   visually on Astral `-Files All` and (ideally) with `--parallel-files` > 1.

### Refined design (2026-06-25, after reviewing the sequential output)

Scope confirmed from `ai/.tmp/osprey-output-20260625/stellar-nonverbose.log`: only **PerFileScoring**
(log 27-87) and **PerFileRescoring** (146-190) emit the repeating per-file blocks -- those are the
parallel candidates. **FirstPassFDR** and **SecondPassFDR** (join, Percolator iterations, the
feature-weights table, protein FDR) are global single-status and already mirror Skyline's import
*tail* (sample log 491-512); they stay as-is. The switch is the existing
`File parallelism: N` line / `--parallel-files`.

**Two display mechanisms (Brendan's Boost-Build model):**
1. **Live aggregate line** while files run concurrently -- Skyline MultiProgressStatus look:
   `[1] 42%  [2] 38%  [3] 51%`, one throttled rewritten line; a file drops out when it finishes.
2. **Per-file buffered block flushed atomically on completion** -- each file's narrative
   (`Reading…/Loaded…/Calibration…/Scored…/Wrote…`) accumulates in that file's own buffer and
   prints as one contiguous block when the file completes, so blocks never interleave (exactly how
   Boost Build buffers per-action output).

**`MultiProgressReporter` (thin wrapper, Core).** Owns N `FileSlot`s = `{index, percent,
StringBuilder buffer}` behind the shared stopwatch throttle. `BeginFile(i)` -> a handle exposing a
`TextWriter` (the buffer) for that file's narrative + band-scoped child reporters; `Report(i, pct)`
updates a slot and re-renders the `[i] p%` line on the throttle; `CompleteFile(i)` flushes the
buffer block under the render lock then drops slot `i`.

**Composite per-file percent -- use the ProgressStatus *segments* model (Brendan, 2026-06-25).** A
parallel file task is composed of multiple **segments** (read, calibrate, score [the inner
`Parallel.For`], write), each counting its OWN 0->100%, combined for display into a single 0->100%
for that file -- exactly how Skyline's `ProgressStatus` segments work today (we mimic the behavior,
not the class). The per-file handle advances segments (`handle.Segment(index, count)` /
`NextSegment()`); the active segment's 0->1 maps into its slice of the file's 0-100. Start with
**equal-weight** slices (even split by segment count -- the simple ProgressStatus default); weighted
segment ends are available later if one phase dominates wall-clock enough to warrant it. So there are
TWO combine levels: segments -> one file's 0-100% (segment model), then N files' 0-100% -> the
`[i] p%` aggregate line (MultiProgressReporter). This replaces the earlier band-weight-table idea.

**Extend ProgressReporter, do NOT port IProgressStatus/Monitor.** Total footprint = the wrapper +
two small additions:
1. **`IProgressSink` on ProgressReporter** -- today it writes `<pct>%` straight to
   `OspreyOutput.Out`; give it an optional sink (default = current behavior). In multi-mode the
   band-reporter's sink is "update file slot i" instead of "print a line." Sequential / compute
   paths untouched.
2. **Per-file output scoping** -- the only genuinely new concept; ProgressReporter alone can't buffer
   narrative. A file's task spans threads (inner `Parallel.For`), so a plain thread-local won't
   attribute inner-scoring output to the file. Prefer an `AsyncLocal<TextWriter>` override on
   `OspreyOutput` that flows into child tasks (smallest blast radius, no signature churn through the
   scoring stack) over threading an explicit per-file `TextWriter` everywhere.

We start to want IProgressStatus/Monitor only if we later need cancellation propagation,
nested/composite progress beyond one level, or a UI consumer -- none in scope; the sink seam leaves a
clean swap-in point if they ever are.

**Resolved (Brendan, 2026-06-25):** in parallel mode the inner scoring loop is the *score segment*
of its file -- its 0->100% feeds the file's composite percent, it does NOT print standalone
`26->85->100%` lines. Only the aggregate `[i] p%` shows motion; the full per-file narrative appears
in the completion block.

### References
- `OspreySharp.Core/ProgressReporter.cs` (the throttle to reuse), `ProgressStream.cs`.
- `OspreySharp.Scoring/ScoringPipeline.cs` (the `Parallel.For` scoring loop + its reporter).
- Skyline `MultiProgressStatus` / `CommandProgressMonitor` for the target format; sample log
  `G:\My Drive\Claude\Import_20191009_170333-skyline.log` lines 18-548.
- Predecessors: `ai/todos/completed/TODO-20260624_ospreysharp_io_progress.md` (#4327, the I/O
  progress this round tunes) and the feature-weights table (#4328).

## Progress Log

### 2026-06-25 - Session 1 (Part 1 done, Part 2 designed)

Branched off master at `74cf4785e9` (both #4327 + #4328 already merged + cleaned up this session).

- **Part 1 (5s I/O interval): DONE + committed on branch (`38eeba1104`).** `ProgressReporter`
  gained `IO_INTERVAL_SECONDS = 5.0`, applied to the 4 I/O reporters (MzmlReader + the 3
  ParquetScoreCache build/write loops); scoring compute loop stays 2s. Release build + 438 tests +
  0-warning inspection green. Output-only -- NOT yet run through `regression.ps1` (it compares
  blib/protein-FDR, not progress lines, so it is byte-identical by construction; run it as the
  standing gate before the combined PR merges anyway).
- **Review captures:** ran clean `-Files All` Stellar + Astral, non-verbose + verbose, to
  `ai/.tmp/osprey-output-20260625/` (4 logs). Brendan reviewed non-verbose: "looks good." The 5s
  effect is visible on Astral HRAM mzML read (~9 % lines vs ~20). Verbose adds only ~6 KB (moderate
  detail, not per-spectrum spam). NOTE: `Run-Osprey.ps1` data lives at
  `D:\Users\brendanx\Downloads\Perftests\osprey-testfiles-mzML` (pass `-TestBaseDir` to it; the
  default `D:\test\osprey-runs` has no mzML). Verbose must be passed as `-ExtraArgs:--verbose`
  (colon-bound; `-ExtraArgs "--verbose"` makes pwsh read the leading `--` as a parameter).
- **Part 2 (parallel-files MultiProgressReporter): DESIGNED, not started.** Design above is settled
  with Brendan: segments model for per-file percent, `[i] p%` aggregate line + Boost-Build per-file
  buffered block, thin `MultiProgressReporter` + `IProgressSink` seam + `AsyncLocal<TextWriter>`
  output scoping, no IProgressStatus/Monitor port. Scope = PerFileScoring + PerFileRescoring only.
- **Next concrete step:** survey the `--parallel-files` dispatch (TODO task 1) -- where the flag is
  parsed and exactly where single-file load hands off to parallel scoring -- then sketch the
  `MultiProgressReporter` / `IProgressSink` API against the real call sites before coding.

### 2026-06-25 - Session 2 (Part 2 implemented + demonstrated)

Built Part 2 end-to-end. Debug build + 439 tests (incl. new `TestMultiProgressReporter`) +
0-warning inspection all green; demonstrated on a real Stellar 3-file `--parallel-files 3` run.

**Implemented (the locked design, minimal blast radius via an ambient sink):**
- `OspreySharp.Core/MultiProgressReporter.cs` (NEW): thin aggregator. `BeginFile(i, name, segCount)`
  returns a `FileScope` (IDisposable) that redirects this async flow's narrative into the file's own
  buffer and becomes the ambient `Current`; `FileScope.BeginSegment()` advances equal-weight segments;
  each segment's `IProgressSink` maps an inner reporter's 0-100 into its slice (monotonic, so the
  multi-reporter write phase never regresses); renders the `[i] p%` line to the unscoped writer on the
  shared throttle; flushes each file's buffered block atomically on `CompleteFile`.
- `OspreyOutput.cs`: `AsyncLocal<TextWriter>` scoped-out (per-file buffer) + internal `RealOut`
  (unscoped) for the aggregate line; flows into the inner scoring `Parallel.For` via ExecutionContext.
- `ProgressReporter.cs`: captures the ambient `CurrentSink` at construction; in multi mode routes
  percent to the sink (no `<pct>%` line) while the heading still buffers. **Zero changes to
  MzmlReader / ScoringPipeline / ParquetScoreCache** -- their existing reporters route automatically.
- `PerFileScoringTask.cs`: wraps the `Parallel.For` body in `BeginFile`; `ProcessFile` calls
  `MultiProgressReporter.Current?.BeginSegment()` at the read/calibrate/score/write boundaries
  (`PROCESS_FILE_SEGMENTS = 4`).
- `Program.LogWarning` now routes through `OspreyOutput.Out` so WARN buffers into the file block
  (per Brendan: warnings in the block); `LogError` stays on `_out` -> immediate (errors surface now).

**Demonstrated:** `ai/.tmp/osprey-output-20260625/stellar-parallel3-scoring.log` (THE canonical demo
log -- keep refreshing this one path; Brendan reads it in Notepad++) -- the `[1] p% [2] p% [3] p%`
aggregate line tracks all 3 files (reads stall at 25% under the mzML gate; scoring drives the bulk),
then each file's full narrative flushes as one contiguous block on completion, no interleaving.
Exactly the Skyline MultiProgressStatus + Boost-Build look. Run on a SCRATCH dir
(`D:\test\osprey-runs\mpdemo`, source hardlinked in) so the read-only source is untouched.

**Review fixes this session (Brendan):**
1. **Stat-line leak (regression I introduced) -- FIXED.** The per-file buffer was a plain StringWriter,
   so it bypassed `StatFilteringTextWriter` and leaked the machine `[COUNT]`/`[TIMING]`/`[BENCH]` lines
   the default log suppresses (looked like perf mode). Fix: `BeginFile` wraps the buffer in a
   `StatFilteringTextWriter`, so stat lines drop as they're buffered (unless `--perf-stats`), exactly
   like the unbuffered path.
2. **`[BENCH]` now perf-gated.** Added `[BENCH]` to `OspreyOutput.IsStatLine` so the
   `[BENCH] Per-file thread cap` line (and the env-triggered ones) are hidden by default and restored
   under `--perf-stats`, alongside `[COUNT]`/`[TIMING]`/`[STAGE-WALL]`. (Flag for Brendan: this is a
   slightly broader output change beyond the parallel-files feature.)
3. **Legend added.** Before the aggregate line, `PerFileScoringTask.Run` prints
   `Scoring N files in parallel:` + a numbered `  [i] <path>` list mapping each `[i]` slot to its
   input file (mirrors Skyline's numbered file list above its multi-import progress).
`TestMultiProgressReporter` extended to assert stat lines are filtered from the buffered block. All
gates re-green (439 tests, 0-warning inspection).

**Output-polish round 2 (Brendan, same session):**
4. **Legend uses Skyline's `N. <path>` format** (un-bracketed), not `[N]`. (`PerFileScoringTask.Run`.)
5. **No `[WARN]` for `--task` runs.** Removed the "`--task PerFileScoring: --output is ignored`"
   warning -- `--task` is standard on HPC and wrappers pass a placeholder `--output`, so warning is
   noise. (`Program.Main`.)
6. **Settings block reports the task + real output.** Added `Task: <CLIName> (single-task run)` when
   `--task` is given (new `Program.TaskCliName` maps HpcTask->CLI name), and for PerFileScoring the
   `Output:` line now reads `per-file .scores.parquet (next to each input mzML)` instead of the
   ignored blib path. Full-pipeline (no `--task`) runs are unchanged (no Task line, Output = blib).
Rebuilt, all gates green; canonical demo log re-captured (legend + clean settings, no [WARN]).

**Parallelized the Stage 6 rescore (Brendan asked; was sequential).** `PerFileRescoreTask.ExecuteRescore`
now runs its per-file loop as a `Parallel.For` bounded by the SAME `ctx.RunPlan.EffectiveFileParallelism`
the scoring phase resolved (sequential when ==1 or 1 file), mirroring `PerFileScoringTask`: per-file
results land by index (order-free accumulation), each file wrapped in `MultiProgressReporter.BeginFile`
with a 3-segment model (read/score/write) via `RESCORE_FILE_SEGMENTS`, inner thread budget divided by
parallelism, plus the `Re-scoring N files in parallel:` legend. Safe because each file's rescore is the
designed "second per-file fan-out": own entry list + own `.scores-reconciled.parquet`, reusing the
already-concurrent `RunCoelutionScoring`; no cross-file mutable state.
**PARITY PROVEN:** `OSPREY_MAX_PARALLEL_FILES=3 regression.ps1 -Dataset Stellar -SkipHpcChain` (the env
cap forces the in-process straight-through + resume legs to parallelism 3, exercising parallel scoring
AND rescore) -> **mode1 (vs committed golden) PASS, mode2 (resume==straight) PASS**, i.e. byte-identical
to the sequentially-generated golden.

**FULL GATE GREEN:** `OSPREY_MAX_PARALLEL_FILES=2 regression.ps1 -Dataset All` (both datasets, all 3
modes, in-process legs at parallelism 2 so parallel scoring + rescore run on Stellar AND Astral vs the
committed goldens) -> ALL 6 legs PASS (Stellar+Astral x mode1 vs-golden / mode2 resume / mode3 HPC
4-task chain); blib byte-size identical across modes per dataset. Log:
`ai/.tmp/osprey-output-20260625/regression-all-parallel2.log`. Comprehensive correctness sign-off for
the whole changeset (output buffering + aggregate line + legend + clean settings/no-[WARN] + parallel
rescore). Still TODO before PR: `Test-PerfGate.ps1`, `--verbose` disposition (task 4), then commit Part 2 +
rescore-parallel alongside Part 1 (38eeba1104).

**[BENCH] gating CONFIRMED (Brendan, 2026-06-25):** he reviewed and approved removing `[BENCH]` from
the default log alongside the other 3 perf prefixes. Usage audit (the why): only 3 production emit
sites, all measurement -- `[BENCH] Per-file thread cap` (parallel-mode thread-split report, the only
one in normal use) + two env-gated dev knobs (`OSPREY_EXIT_AFTER_CALIBRATION`, `OSPREY_MAX_SCORING_WINDOWS`).
Same character as [COUNT]/[TIMING]/[STAGE-WALL]; restored under `--perf-stats`. Settled.
Also re-ran the canonical demo at `--parallel-files 3` (full pipeline): all 3 files concurrent in BOTH
the scoring AND the now-parallel rescore phases; rescore 14.4s (vs 19.7s at parallelism 2 -- fan-out scales).

**PERF GATE PASSED -- net speedup (2026-06-25).** `Test-PerfGate.ps1 -Dataset Stellar` (branch vs
pinned pwiz-perfbase @ #4298, parallelism 3, 3 interleaved reps): **total -5.5% median, every rep
faster** (-5.5/-7.3/-4.9). stage1to4 (scoring, where all the output buffering/aggregate/filtering
lives) **flat at -0.7%** -> output changes add zero overhead. **stage6 (rescore) -51.2%** (21.5s->10.6s,
all reps ~-51%) -> the rescore parallelization. blib +7.9% is +0.3s on a 3.5s stage (noise, info-only).
Log: `ai/.tmp/osprey-output-20260625/perfgate-stellar.log`; verdict: `ai/.tmp/perf-gate/20260625-234034Z/verdict.md`.

**Test-PerfGate harness fix (NEEDED to run the gate; include in PR or as a sibling fix).** The gate
unconditionally passed `--perf-stats` to BOTH binaries, but the pinned baseline (#4298) predates that
flag (added in #4326, same PR as `--parallel-files`) and exited 1 -> the perf gate had been un-runnable
since #4326 merged. Fix: made `--perf-stats` version-aware in `ai/scripts/OspreySharp/Test-PerfGate.ps1`
-- detect per-variant `SupportsPerfStats` from each root's `OspreyCommandArgs.cs`, add the flag only
where supported (pre-#4326 baselines emit the `[STAGE-WALL]`/`[TIMING]` lines unconditionally). Same
asymmetry the harness already handled for `--parallel-files` via `OSPREY_MAX_PARALLEL_FILES`. Baseline
NOT advanced (kept #4298 per Brendan).

**Committed + PR'd + self-reviewed (2026-06-25).** Two pwiz commits on the branch (b3f3a186f0 output,
a18af7c452 rescore-parallel) atop Part 1 (38eeba1104) -> **PR #4332** (base master); Test-PerfGate fix +
TODO committed to the ai repo. `/pw-self-review` (fresh-context agent) found NO critical/high; it
independently re-confirmed the parallel-rescore per-file independence + byte-identical invariant +
AsyncLocal flow + no deadlock. Addressed: read the per-file buffer without the misleading lock (only
caller runs after the inner Parallel.For joins) and dropped the unnecessary per-file segment lock
(single-threaded advance); removed the dead `FileSlot.DisplayName`. Dismissed two cosmetic LOWs
(render-lock-held-during-block-flush is intentional for block contiguity; resume/no-work files briefly
at 0% is transient). Fix commit d9c2f2fb70 (build + 439 tests + 0-warning inspection green). The
reviewer's "validated on a real multi-file reconciliation run?" question = yes, regression -Dataset All
at parallelism 3.

**Harmonized the per-file block header (Brendan, 2026-06-25):** scoring's
`\n===== Processing file N/M: <path> =====` banner replaced with the terse `Scoring file N/M: <path>`
to match rescore's `Re-scoring file N/M: <stem>` (rescore left as-is). Scoring keeps the full mzML path
(it reads the mzML); rescore keeps the stem (reads from cache). Output-only -> golden unaffected; build
+ 439 tests + 0-warning inspection green. Canonical demo log refreshed with the new headers.

**Scope finding:** `PerFileRescoreTask.ExecuteRescore` runs its per-file loop SEQUENTIALLY (`for`,
not `Parallel.For`) -- so PerFileScoring is the ONLY concurrent producer today; the rescore phase
emits one file at a time and needs no aggregate line. Wiring rescore would first require
parallelizing it (a parity-sensitive change, out of this output-only round). Left as-is; noted for
Brendan.

**Still to do before the combined PR:** run the standing `regression.ps1 -Dataset Stellar` gate
(output-only change -> expected byte-identical golden) and `Test-PerfGate.ps1`; then commit Part 2
alongside the already-committed Part 1 (`38eeba1104`) as one PR. Decide whether `--verbose` adds any
per-file detail (TODO task 4 -- currently unaddressed; the one-line summary is the default view).

**Run-harness gotcha (learned the hard way):** `Run-Osprey.ps1 -ExitAfterScoring` writes per-file
`.scores.parquet` / `.spectra.bin` / `.calibration.json` NEXT TO each input mzML, so pointing
`-TestBaseDir` at the read-only `D:\Users\brendanx\Downloads\Perftests\osprey-testfiles-mzML` source
dirties it. Copy the mzML+library into a scratch base (e.g. `D:\test\osprey-runs\stellar`) and point
`-TestBaseDir` there, like `regression.ps1` does. (Cleaned up the stellar source dir afterward.)

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260625_ospreysharp_output_progress.md` before starting work (NOTE: that handoff
predates Session 2 -- Part 2 is now implemented; trust this Session 2 entry over the handoff).

### 2026-06-25 - Merged

PR #4332 merged as commit bcc9480774. Shipped Part 1 (5s I/O progress interval) + Part 2 (the
`MultiProgressReporter` for `--parallel-files`: throttled `[i] p%` aggregate line + numbered legend +
per-file buffered blocks, clean default log with `[BENCH]` now perf-gated, no `--task`/`--output`
warning, corrected `Task:`/`Output:` settings, `Scoring file N/M` header) + the Stage 6 per-file
rescore parallelization (byte-identical, ~2x faster on the rescore stage). Gates: full
`regression.ps1 -Dataset All` (6/6 legs PASS at parallelism 3), `Test-PerfGate` total -5.5%, TeamCity
Osprey .NET green (436 tests), self-review addressed (buffer/segment lock cleanup, dead-field removal).
Sibling ai-repo fix: made `Test-PerfGate.ps1` version-aware so it can measure a baseline that predates
`--perf-stats` (#4326) -- the perf gate had been un-runnable since #4326 merged. No scope deferred;
`--verbose` was confirmed a no-op (verbose detail already buffers into each file's block).
