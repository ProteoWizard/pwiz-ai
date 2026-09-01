# TODO-20260901_osprey_stage5_reload_materialization.md - Stage 5 collects all survivors into one O(files) buffer

**Found**: 2026-09-01, by the 446-file CHS join that this was supposed to be the baseline for.
The join ran 5h14m and was killed thrashing. See
`ai/.tmp/handoff-20260901_chs_446file_night_session.md` for the full session.

> **CORRECTION (same day).** This file first said the step "materialises 1.34 B entries before
> compacting to 289 M". That was wrong and the distinction matters. The 1.34 B entries are
> **streamed** - ingest, Percolator and q-value assignment all run between 5 and 21 GB, which is
> #4438/#4486 working exactly as designed. What blows up is the step AFTER: collecting the
> **289 M survivors** into one all-files buffer at ~274 B/entry.

## The defect

`FirstPassFdrTask.ReloadFirstPassSurvivors` loads each file's survivors through
`FirstPassSurvivorLoader` - which already filters during the parquet read, so the per-file load
is lean - and then collects every file's list into one buffer. Its own comment names the
problem:

> *"The per-file load is the reusable half and lives on the loader; the collection into one list
> is the O(files) half this method still performs. Keeping them separate is what lets a consumer
> take the loader alone and never build the buffer - the direction issue #4526 is headed."*

So this is **#4526**, measured at the size where it stops being survivable.

```
03:37:51  Streaming first-pass ingest from 446 file(s)      man  5.7 GB
03:41:24  streaming ingest: 1,342,686,095 rows              man  7.3 GB   <- streamed, 3.5 min
04:03:10  Running First-pass Percolator on 1,342,686,095    man 13.4 GB
04:58:30  Assigning q-values to 1,342,686,095 entries       man 11.4 GB
06:56:13  first-pass protein FDR done                       man 19.2 GB
07:13:56  Reloading first-pass survivors from 446 file(s)   man 21.4 GB
08:17:15  compaction 1.34 B -> 289 M reported               man 100.0 GB  <- the only blowup
```

289 M x 274 B = 79 GB of live data; measured peak 102.2 GB, so ~1.35x that with GC overhead.
The same ratio holds at 257 files (133 M x 274 B = 36.4 GB live, 49.1 GB measured), which is
what makes the model trustworthy.

## Why it looks superlinear in FILES

Survivors per file **rise with cohort size** - 0.517 M/file at 257, 0.648 M/file at 446 -
because cross-run reconciliation transfers detections into files where they were not
independently found. That is the effect `ai/scripts/Osprey/CHS/README.md` already documents for
observations (0.410 M/file at 86 -> 0.533 M/file at 257). Entries in scale linearly; the buffer
scales with survivors, and survivors scale faster than files.

## Measurements

| files | entries in | entries out | total heap at compaction | reload+compact wall |
|---|---|---|---|---|
| 257 (`chs-257files-...-s57base257`) | 764,427,887 | 132,912,754 | 49.1 GB | 14m49s |
| 446 (`chs-446files-...-baseline-phase3`) | 1,342,686,095 | 288,920,200 | 102.2 GB | 63m19s |

* Entries INGESTED scale linearly: 2.974 M/file at 257, 3.011 M/file at 446 - and they stream.
* SURVIVORS scale superlinearly: 0.517 M/file at 257 -> 0.648 M/file at 446.
* Heap tracks survivors, giving **N^1.33** overall - x2.08 heap for x1.74 files.
* The rest of FirstPassFDR is lean: **p10 7.9 GB, p50 10.5 GB**. This is one spike, not a pool.

The 446 peak was reached while paging and Server GC behaves differently under pressure, so
treat 1.33 as an upper bound on the exponent rather than a fitted law. The optimistic
linear-in-files bracket still puts 446 at 85 GB.

## Why hardware is not the answer

Peak proportional to N^1.33 means max cohort proportional to RAM^0.75:

| RAM | max files (compaction peak inside RAM) |
|---|---|
| 63.7 GB (current box) | ~280 |
| 128 GB | ~470 |
| 256 GB | ~800 |

Quadrupling RAM buys 2.8x the files. 446 barely fits in 128 GB with nothing to spare.

## The fix

**Not** "filter during the reload" - `FirstPassSurvivorLoader` already does that (#4486), and
that is why the per-file load is cheap. The fix is #4526: **stop building the all-files buffer
at all.** Stage 6 and Stage 7 both consume it one file at a time, and the loader is already
published as a byproduct precisely so they can call it per file instead. Removing the
collection removes the O(files) term outright rather than shrinking its coefficient.

The Phase 3 lean row is complementary, not superseded: it shrinks the 274 B/entry that this
buffer is 289 M copies of, and it also shrinks whatever a per-file consumer holds. Do #4526
first - it removes the term; the lean row then makes what remains cheaper.

Validate at 446 directly on the 63.7 GB box: a fix that clears 446 there is self-proving, and
one that does not is caught by the same `--timestamp --memstamp` instrumentation that caught
this. Do not measure success by wall time on a run that paged.

## Relationship to the Phase 3 lean row

They act on the **same** buffer from two directions, so they are complementary rather than
alternatives. This one removes the O(files) collection; the lean row shrinks the 274 B/entry it
is built from. Sequence this first - a 446-file run never reaches Stage 7 today, so the lean row
cannot even be measured at 446 until the Stage 5 buffer is gone.

## State on disk

* `chs-446files-libdecoy-r1.0-protein-compact-baseline-phase3` — the killed run. `run.log`
  carries a `KILLED BY OPERATOR` line recording that everything after 07:13:56 is page-fault
  bound and must not be read as a baseline.
* It holds 446 `.1st-pass.fdr_scores.bin` (35.0 GB) — the per-file half, complete — but **no
  `.FirstPassFDR.osprey.task` markers**, because the stage never finished. Do not hand-write
  those markers to reuse the work: that manufactures a completion record for a stage that did
  not complete. A re-measurement pays the ~2.7 h per-file pass again.
* All 446 Stage 1-4 parquets are staged and joinable at 26.1.1.243 via
  `runs\_linksrc\{p0059,p0060,p0061,p0062,p0063_0064}` — a fix can be tested immediately
  without redoing any scoring.
