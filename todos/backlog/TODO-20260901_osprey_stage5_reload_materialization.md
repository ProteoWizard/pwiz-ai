# TODO-20260901_osprey_stage5_reload_materialization.md - Stage 5 reload materialises 1.34 B entries before compacting to 289 M

**Found**: 2026-09-01, by the 446-file CHS join that this was supposed to be the baseline for.
The join ran 5h14m and was killed thrashing. See
`ai/.tmp/handoff-20260901_chs_446file_night_session.md` for the full session.

## The defect

`FirstPassFDR`'s Stage-5 reload loads every per-file first-pass survivor into one structure and
compacts afterwards:

```
07:13:56  Reloading first-pass survivors from 446 file(s)...   managed 21.4 GB
   ...    63 minutes, climbing
08:17:15  First-pass compaction: 1342686095 -> 288920200 entries (625620 passing base_ids)
08:17:15  Reconciliation planning                              managed 100.0 GB
```

**78% of what it materialises is discarded.** Worse, the `625,620 passing base_ids` that decide
what survives are computed at 07:09:15 — **four minutes before the reload starts**. The filter
is already in hand and is applied too late.

This is `feedback_fdr_no_files_times_entries` ("per-file compute -> O(entries) aggregate ->
streamed emit") violated by a JOIN task, which is what
`project_osprey_work_belongs_in_perfile_tasks` predicts JOIN tasks will do.

## Measurements

| files | entries in | entries out | total heap at compaction | reload+compact wall |
|---|---|---|---|---|
| 257 (`chs-257files-...-s57base257`) | 764,427,887 | 132,912,754 | 49.1 GB | 14m49s |
| 446 (`chs-446files-...-baseline-phase3`) | 1,342,686,095 | 288,920,200 | 102.2 GB | 63m19s |

* Entries scale **linearly**: 2.974 M/file at 257, 3.011 M/file at 446.
* Heap scales as **N^1.33** — x2.08 for x1.74 files. The step costs more per entry as entries
  grow, and that gap is the actual defect, not the absolute size.
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

Stream the per-file survivors through the `passing base_ids` filter **as they are read**, so
only the ~289 M survivors are ever resident. Expected ~4.6x reduction at 446 files, and it
removes the superlinear term if the excess is a resize/rehash/sort over the full 1.34 B.

Validate at 446 directly on the 63.7 GB box: a fix that clears 446 there is self-proving, and
one that does not is caught by the same `--timestamp --memstamp` instrumentation that caught
this. Do not measure success by wall time on a run that paged.

## Relationship to the Phase 3 lean row

**They are different problems and this one is the blocker.** The lean row targets
SecondPassFDR's resident floor (p10 18.2 GB at 257 files, per `s57base257`). That floor is real
and worth shrinking, but a 446-file run never reaches Stage 7 — it dies in Stage 5. Sequence
this first, or the lean-row work cannot be measured at 446 at all.

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
