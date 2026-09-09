# TODO-20260909_osprey_projection_scan_progress.md - the deferred first-pass row scan reports nothing

**Module**: `osprey`
**Status**: In Progress
**Branch**: `Skyline/work/20260909_osprey_projection_scan_progress` in `C:\proj\pwiz-work1`,
cut from `origin/master` (`ade29fa42d`). NOT stacked on #4646 - the defect is master's.

## What

`PerFileScoringTask` publishes `FdrProjections` as a deferred factory. Its one consumer,
`FirstPassFdrTask.Run`, pulls `.Value` about seventy lines after entry, and the factory then
reads every scored row of every file with **nothing reporting**. At 446 runs that is a
**618-second silent window** - the longest unexplained pause in a 6.5 h job and the only
reporting gap over 30 s in it.

Fix: a `ProgressReporter` inside the factory. The deferral is correct and stays.

## Why it is NOT a regression, and why it appeared now

Introduced by `c4921f3d6c` (#4633, 2026-09-06) - already on master. Before it, the scan ran
eagerly inside `PerFileScoringTask`'s own per-file loop, which HAD a progress bar
(`Loading scored entries`). Deferring the work moved it out of that loop; the reporting did
not follow it.

**The deferral made nothing slower - it made the work CONDITIONAL.** Its own comment says why:
the only consumer is `FirstPassFdrTask.Run`, and a resume whose 1st-pass outputs are valid
SKIPS that Run, so the scan was "built and discarded, every time". `TODO-20260901_osprey_stage5_reload_materialization.md`
measures the win as `Loading scored entries` **9m46s -> 10s**, part of resume startup
26m23s -> 2m53s. A `--task PerFileRescoring` worker is exactly such a run: it is excluded from
FirstPassFDR's membership, so it was paying a ten-minute all-files join-shaped scan as dead
lead-in before touching its one file - which is what #4597's contract forbids.

My run is the case where the condition is TRUE. FirstPassFDR did run, the factory fired, and
the same 9m46s came back - now unreported. **9m46s and 618s are the same scan.**

## Evidence (three runs, same 446-run CHS cohort, same -LinkFrom shape)

| run | build | gaps >=30s | max gap |
|---|---|---|---|
| `stage5stream`, 2026-09-02 | pre-#4633 | 1 | 47 s |
| `stages567/run-orig`, 2026-09-03 | pre-#4633 | **0 OK** | **24 s** |
| `stages567-n4646`, 2026-09-09 | post-#4633 | 1 | **618 s** |

Memory is unchanged across them (managed peak 32.5 -> 33.5 GB; `PerFileRescoring`
10.0/12.0/24.5 -> 10.0/12.1/24.5 GB), so this is observability only, not behaviour.

On the Sep-3 log `stage5-start-live` and `projection counts-only` are in the SAME SECOND; on
2026-09-09 they are 618 s apart with working set growing 14.6 -> 20.3 GB between them. That
two-line signature is the regression test if one is ever wanted - it needs a cohort large
enough to make the scan measurable, not 446 files.

## The label

The bar reads `Reading scored rows from N file(s) for first-pass FDR`, NOT "building the
first-pass projection". Developer, 2026-09-09: *"What is the 'first-pass projection'? This is
not inherently a meaningful phrase to me."* It was the type's name (`FdrProjectionSet`), which
describes the implementation rather than the work. Name a progress bar for what a person
watching the run is waiting for.

## The wider point (developer, 2026-09-09)

> Using a 446 file dataset as a regression test can allow issues to survive and last for days
> before they are detected... Each testing mode has its cycle-time, and we really can't make a
> full 446 file test on a 64 GB computer much faster. So, we need to be sure we make the most of
> any issues we find regardless of the stage of development we may be in at the time we find an
> issue in a multi-day test cycle.

This defect lived three days because it is invisible below cohort scale: at Stellar size the
same pull is milliseconds, so no gate would show it. Two things still owed on the 446-run
cohort and NOT covered by this branch: a run that executes **Stages 1-4** rather than linking
them, and a **straight-through run with `--model-diagnostics`** (the per-task vs straight-through
concern). The 2026-09-09 run deliberately had neither.

## Gates

* `Build-Osprey.ps1 -SourceRoot C:/proj/pwiz-work1 -RunTests -RunInspection`: 604 tests,
  603 passed, 1 pre-existing skip, 0 warnings.
* Still owed: `regression.ps1 -Dataset Stellar`, then `/code-review` before opening the PR.
