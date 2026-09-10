# TODO-20260909_osprey_projection_scan_progress.md - the counts-only projection scanned 1.34 B rows to learn 446 numbers

**Module**: `osprey`
**Status**: Completed 2026-09-09 (PR #4651, merged as 5471d2ab85)
**Branch**: `Skyline/work/20260909_osprey_projection_scan_progress` in `C:\proj\pwiz-work1`,
cut from `origin/master` (`ade29fa42d`). NOT stacked on #4646 - the defect is master's.

## What it was

`PerFileScoringTask` publishes `FdrProjections` as a deferred factory whose body streamed every
row of every `.scores.parquet` through `FdrProjectionSet.Builder(countsOnly: true)`. In that
mode `AddRow` **discards all five fields and increments a counter**:

```csharp
public void AddRow(uint entryId, byte charge, bool isDecoy, double coelutionSum,
    string modifiedSequence)
{
    if (_countsOnly)
    {
        _curFileCount++;
        return;            // every value thrown away
    }
```

| | |
|---|---|
| read | 1,342,686,095 rows across 446 files - `entry_id`, `charge`, `is_decoy`, `coelution_sum` and a STRING `modified_sequence`, decoded row group by row group |
| produced | **446 file names + 446 row counts** |
| cost | **618 s** and ~5.7 GB of allocation (446-run CHS, 2026-09-09) |

And the phase immediately after it - `Streaming first-pass ingest from 446 file(s)` - re-reads
the same columns from the same files to do the actual work. The counts-only branch's own comment
says so: *"the counts-only producer read the same parquet to count its rows"*.

## The fix: delete the scan, not report it

The count was always free. Parquet's footer declares `NumRows`;
`ParquetScoreCache.ProbeResumeSchemaAndRows` returns it from the open the load loop **already
performs** for the PIN-schema check, and that loop already did `leanRowCount += probe.RowCount`
under a comment reading *"the count comes from the footer, not a scan"*. A counts-only
projection is nothing but those counts paired with their file names, so the factory is now
`FdrProjectionSet.CountsOnly(names, counts)` and no path scans at all.

~10 minutes -> ~0, and the only full read left is the ingest that was always going to happen.

**A progress bar was the wrong fix and was reverted before push.** It would have made ten
minutes of pointless work *look legitimate*, which is worse than the silence that exposed it.
It only became the right question when the developer asked what the ten minutes actually
produced - "Is it truly a join? Could PerFileScoring also write a sidecar optimized for this
task?" The answers are no and no-sidecar-needed: nothing crosses a file boundary in counts-only
mode (every `FdrProjectionSet.Builder` in this task is `countsOnly: true`), and Parquet's footer
already IS the optimised sidecar.

## Why it appeared only now

Introduced by `c4921f3d6c` (#4633, 2026-09-06), already on master. Before it the scan ran
eagerly inside the per-file loop, which had a progress bar (`Loading scored entries`).
Deferring made the cost CONDITIONAL - a `--task PerFileRescoring` worker is excluded from
FirstPassFDR's membership, skips its `Run`, and so never pulls the factory. That is the win
`TODO-20260901_osprey_stage5_reload_materialization.md` measures as `Loading scored entries`
**9m46s -> 10s** (resume startup 26m23s -> 2m53s).

**9m46s and 618 s are the same scan, seen from the two sides of that condition.** The deferral
removed it for runs that skip FirstPassFDR; it stayed, and lost its progress reporting, for
runs that do not. #4633 was right to defer; it just deferred work that should not exist.

## Evidence (three runs, same 446-run CHS cohort, same -LinkFrom shape)

| run | build | gaps >=30s | max gap |
|---|---|---|---|
| `stage5stream`, 2026-09-02 | pre-#4633 | 1 | 47 s |
| `stages567/run-orig`, 2026-09-03 | pre-#4633 | **0 OK** | **24 s** |
| `stages567-n4646`, 2026-09-09 | post-#4633 | 1 | **618 s** |

Memory is unchanged across them (managed peak 32.5 -> 33.5 GB; `PerFileRescoring`
10.0/12.0/24.5 -> 10.0/12.1/24.5 GB). On the Sep-3 log `stage5-start-live` and
`projection counts-only` are in the SAME SECOND; on 2026-09-09 they are 618 s apart with
working set growing 14.6 -> 20.3 GB. **That two-line signature is the acceptance test** - it
needs a cohort big enough to make the scan measurable, not 446 files.

## Guards added

* `TestFooterRowCountMatchesScan` pins the invariant the whole change rests on: the footer's
  declared `NumRows` is the same number a full scan reaches. Multiple row groups on purpose
  (cap 2 over 5 rows) - a single-group file cannot tell a footer count and a per-group append
  loop apart. **CORRECTED after `/code-review high`**: the claim originally written here -
  "`ReadFdrStubScalars` reads every row group with no filter, so they cannot legitimately
  differ" - is FALSE. It skips a row group whose `entry_id` or `is_decoy` comes back null,
  all-or-nothing per file, so a parquet can declare N rows and scan to 0. See the probe
  hardening below.
* `RowCountAsInt` REFUSES rather than casting. The cohort total already outgrew `int`
  (1,342,686,095 at 446 files, which is why the running total is a `long`), so the per-file
  value is the next one to watch; an unchecked cast would wrap a large run's count negative and
  size first-pass FDR from it silently.

## The wider point (developer, 2026-09-09)

> Using a 446 file dataset as a regression test can allow issues to survive and last for days
> before they are detected... we need to be sure we make the most of any issues we find
> regardless of the stage of development we may be in at the time we find an issue in a
> multi-day test cycle.

This lived three days because it is invisible below cohort scale: at Stellar size the same pull
is milliseconds. Still owed on the 446-run cohort and NOT covered here: a run that executes
**Stages 1-4** rather than linking them, and a **straight-through run with
`--model-diagnostics`**. The 2026-09-09 run deliberately had neither.

See also the backlog item this raised: `TODO-osprey_log_lines_are_user_facing_prose.md`.

## Gates

* `Build-Osprey.ps1 -SourceRoot C:/proj/pwiz-work1 -RunTests -RunInspection`: **605 tests, 604
  passed, 1 pre-existing skip, 0 warnings**.
* `regression.ps1 -Dataset Stellar`: RUNNING. This is the real check - the change alters what
  first-pass FDR is sized from, so `mode1 (vs golden)` is what proves the counts are identical.
* Then `/code-review`, then the PR.

### 2026-09-09 - Merged

PR [#4651](https://github.com/ProteoWizard/pwiz/pull/4651) merged as `5471d2ab85`, after
`git merge origin/master` brought in #4646 plus an unrelated `SkylineNightly/Nightly.cs` change
(zero Osprey files, so the Stellar green stood).

**Merged with `--admin`, at the developer's instruction.** What that bypassed, recorded so the
green is not overstated: **6 CodeQL `Analyze` checks were QUEUED** (none failing, PR
MERGEABLE), and **TeamCity Perf/Regression was never triggered on this PR at all**. The local
evidence is what backs it: 593 tests / 593 passed / 0 skipped / 0 warnings, and
`regression.ps1 -Dataset Stellar` PASSED twice - the second run deliberately AFTER the schema
probe changed what it accepts, because the first green predated that.

**Verified at 446 files, which is the acceptance test this branch is about.** Same cohort,
same `-LinkFrom` shape as the run that produced the 618 s:

```
13:31:47  [MEM stage5-start-live] ... (post-GC, entering first-pass FDR, files=446)
13:31:47  [MEM projection counts-only: 1342686095 rows across 446 files (no resident rows)]
```

Same second, identical row total - so the footer counts reproduce the scan's answer on real
data, and the pre-#4633 behaviour is restored rather than newly invented.

**`/code-review high`, 6 findings: 3 fixed, 3 dropped.** The level matters - `max` returns its
cap of ~15 every time, and answering all of them generates the next round's findings. Fixed:
the schema probe tested only `PIN_FEATURE_NAMES[0]` while the columns that make footer != scan
are `entry_id`/`is_decoy`; a sentence garbled by the builder-to-bool rewrite; and a BOM flipped
in OPPOSITE directions on two files by `utf-8-sig` python edits and `sed -i` (restored both).
Dropped, with reasons: `FdrProjectionSet.Builder` is now dead production code with a parity
test still certifying it (a refactor, not a defect); the bench deletion is out of scope for a
footer-counts PR (true, but the developer asked for it); and `Run`'s lean loop has no progress
bar where the resume loop does (deliberate - restoring it is the instinct this whole change
disproved).

**Still open, carried forward:**

* [#4650](https://github.com/ProteoWizard/pwiz/issues/4650) - library retention, rehydration and
  spectrum dropping need an end-to-end review. Stage 7 spends 11 minutes and peaks at 41.5 GB
  rebuilding all 446 runs to recompute a retained set Stage 5 already has, then releases 0 of
  6,175,389 entries.
* **`FdrProjectionSet.Builder` should be deleted with its parity test** - named in the PR body
  as out of scope, not forgotten.
* Still owed on the 446-run cohort: a run executing **Stages 1-4** rather than linking them, and
  a **straight-through run with `--model-diagnostics`**.
