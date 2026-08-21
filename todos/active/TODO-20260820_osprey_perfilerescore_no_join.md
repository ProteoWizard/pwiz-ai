# PerFileRescoring ends with a whole-run join that rebuilds the buffer its own streaming just discarded

## Branch Information
- **Branch**: `Skyline/work/20260820_osprey_perfilerescore_no_join`
- **Base**: `master`
- **Created**: 2026-08-20
- **Status**: In Progress
- **GitHub Issue**: [#4597](https://github.com/ProteoWizard/pwiz/issues/4597)
- **Module**: `osprey`
- **Worktree**: `C:\proj\pwiz-work1`
- **PR**: (pending)
- **Requester/Reporter**: none — raised by Brendan (project developer), no credit line

## Objective

`PerFileRescoreTask` is a per-file HPC task (`NoJoin` in `Program.cs`), yet on the
straight-through path it ends with whole-run join work: `MaterializeAllSurvivors` +
`OverlayReconciledIntoAllFiles` re-read every file's artifacts to rebuild the complete
in-memory buffer `SecondPassFDR` consumes — the same buffer the streamed rescore
deliberately dropped file-by-file to keep memory bounded.

Move the pool construction to its consumer (`SecondPassFDR`), which already builds it on
the `--task SecondPassFDR` path, and let the lazy `PipelineContext.Get<TInfo>()` pull
materialize it instead of the `SecondPassFdrWillRun` predicate guarding eager work.

Measured cost of the join block on the 82-file SEA-AD run
(`seaad-82files-libdecoy-r1.0-protein-compact-p2-pickrun3-ours-n82`): **16 min 20 s**
(10.2% of PerFileRescoring), managed heap **5.9 GB → 27.0 GB** resident with a 49.9 GB
transient touch; total process 18.8 GB → 41.6 GB entering Stage 7.

## Tasks

- [ ] `PerFileRescoring` ends with no join work, so its shape matches the HPC exit point
      it already is
- [ ] `SecondPassFDR` builds its own global survivor pool — which it already does on the
      `--task SecondPassFDR` path (`Rehydrate`, `ExpectReconciledInput`)
- [ ] `SecondPassFdrWillRun` predicate removed rather than maintained: a worker skips the
      work because nothing pulls it, not because a predicate said so
- [ ] Check (not necessarily fix) the two recorded latent HPC risks while in here:
      `--input-scores` order sensitivity in multi-file FirstJoin, and straight-path global
      compaction vs HPC worker per-file compaction

## What must NOT be lost

- **`ResetRescoredTargets` may only touch files rescored in THIS process.** Scores are
  in-memory only (`ReconciledParquetWriter` persists boundaries/area/features, not
  scores); under frozen-model modes an off-stratum survivor keeps its 1st-pass q, so the
  difference reaches the report. Recorded miss: Stellar straight-through reported 31,583
  precursors against golden 29,364. Resetting resume-skipped files is the mirror error.
- **`canonicalize: false` on the streamed rebuild is deliberate.** Cold rescore appends
  gap-fill at the end and never re-sorts; sorting changes the buffer order Stage 7 writes
  2nd-pass sidecars in, which changes the protein-compact competition and the reported
  set. The resume path passes `true` deliberately (`PerFileRescoreTask.cs:1840-1862`).

## Regression Test

- **Test name**: `TestDeferredMilestoneBuildsOnFirstValueRead`,
  `TestUndeferredMilestoneReadsStraightThrough` (`Osprey.Test/ByproductContextTest.cs`)
- **Test project**: Osprey.Test, plus the behavioral gate `regression.ps1`
- **Fails on master**: n/a — these pin a mechanism master does not have (the deferring
  `RescoredEntries` constructor), so they cannot be red before the change. What they DO
  catch is the two ways the deferral silently un-defers later: a `Publish`-time read of
  `Value` (the DEBUG milestone-ordering guard did exactly that before this change) and a
  second read re-running a non-idempotent overlay.
- **Passes on fix**: yes — 588 Osprey.Test tests green, zero-warning ReSharper inspection

The real failure mode of the move is a wrong COUNT, not a crash, so the deciding gate is
behavioral: `regression.ps1` modes 1/2/3 cover all three `RescoredEntries` build paths
(straight-through cold, straight-through resume, `--task SecondPassFDR` node), and
`-Dataset All` plus the TeamCity Perf/Regression gate before merge.

## Files

- `pwiz_tools/Osprey/Osprey.Tasks/PerFileRescoreTask.cs`
- `pwiz_tools/Osprey/Osprey.Tasks/Pass2FdrSidecar.cs`
- `pwiz_tools/Osprey/Osprey.Tasks/SecondPassFdrTask.cs`
- `pwiz_tools/Osprey/Osprey/Program.cs`

## Progress Log

### 2026-08-20 - Session Start

Starting work on this issue. Branch created in `C:\proj\pwiz-work1`.

### 2026-08-20 - Implemented: the milestone carries the join, the pull runs it

**Design.** The seam is the milestone itself. `RescoredEntries` gained a second
constructor taking an `Action` that runs on the first `Value` read
(`PipelineByproducts.cs`), and `PerFileRescoreTask.Run` publishes it that way, handing it
`BuildRescoredPool` — the former tail block, unchanged in content and order:
`MaterializeAllSurvivors` → `ResetRescoredTargets` → `OverlayReconciledIntoAllFiles(canonicalize: false)`.
`SecondPassFdrTask.Run`'s existing `ctx.Get<RescoredEntries>().Value` is what runs it, so
Stage 7 — the stage that needs a global pool — is where the work lands.

Why not move the body into `SecondPassFdrTask`: the build needs Stage-6 knowledge
(`PerFileRescoreTask.ValidityKey`, the planner byproducts, and which of `canonicalize`
true/false this path requires), and it shares its body with the resume `Rehydrate`. This
matches the precedent the issue itself cites — on the `--task SecondPassFDR` path the code
already lives in `PerFileRescoreTask.Rehydrate` and SecondPassFDR's pull is what triggers it.

**Also in the change**

* `SecondPassFdrWillRun` deleted. A worker skips the join because nothing pulls it.
* The self-gated no-op path's eager refill is deferred too, through the same
  `BuildRescoredPool` with `_rescoredFiles` still null — refill, no overlay, which is what
  keeps `OSPREY_STAGE6_STREAM_SURVIVORS=0` a byte-identity oracle on that path.
* `MaterializeAllSurvivors` throws `InvalidDataException` instead of returning false: a
  deferred build has no bool channel back to the driver loop (the `RehydrateFailedException`
  precedent), and a refill that quietly gave up would hand Stage 7 an empty pool.
* New non-forcing `PerFileEntries.BackingBuffer`, used by the DEBUG milestone-ordering
  guard. Without it `Publish` itself would materialize the deferred milestone in Debug
  builds — before the rescore that fills it has run.
* The `OSPREY_DUMP_RESCORED` cross-impl dump now reads the milestone (a pull), so it still
  dumps the whole-run buffer.
* `regression.ps1`'s known-resident-gaps table said "resident from the end of Stage 6";
  updated to say the pull builds it and that this moves who pays, not how big it is.

**Not changed, deliberately**: the pool still exists and is still O(survivors) resident
through Stage 7. This is a shape change, not a saving — on the straight-through path the
same ~16 min / ~27 GB at 82 files simply lands at the start of Stage 7 instead of the end of
Stage 6, which will show as stage6 wall time moving to stage7. What it buys: no per-file
worker can pay it, and a resume whose Stage 7 outputs are already valid no longer builds a
pool nothing reads.

**Latent HPC risks the issue asked to check while in here** (not fixed, unchanged by this):
`--input-scores` order sensitivity in multi-file FirstJoin, and straight-path global
compaction vs the HPC worker's per-file compaction. Neither is touched — `BuildRescoredPool`
iterates the same per-file collections in the same order the tail block did; only its
position in the run moved.

**Gates**

* `Build-Osprey.ps1 -Configuration Debug -RunTests -RunInspection`: 588 tests pass, 0
  inspection warnings.
* `regression.ps1 -Dataset Stellar`: **PASSED** — mode1 (vs golden), mode1c, mode3 (per-file
  sidecars == straight, 2,443,597 records; HPC chain == straight), mode4, mode2 (resume
  cache hits + resume == straight), mode5, mode6. Log:
  `C:\proj\ai\.tmp\regr-4597-stellar-2.log`.
* First Stellar attempt aborted in mode 3 **phase 1** (`--task PerFileScoring`, exit -1) —
  a phase that runs none of the changed code, and the identical rerun passed it. Treated as
  environmental; `-Dataset All` is the re-confirmation.
* Pending: `Test-PerfGate.ps1 -Dataset Stellar`, `regression.ps1 -Dataset All`,
  `/code-review max`, TeamCity Perf/Regression (ask first).
