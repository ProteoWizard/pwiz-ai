# TODO-ospreysharp_output_progress.md

## Status
- **Type**: OspreySharp CLI output (final tuning round; follow-on to PR #4326 / #4327)
- **Branch**: `Skyline/work/20260625_ospreysharp_output_progress` (started 2026-06-25)
- **Status**: In progress. Hoped to be the **final** OspreySharp output-tuning round.
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

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260625_ospreysharp_output_progress.md` before starting work.
