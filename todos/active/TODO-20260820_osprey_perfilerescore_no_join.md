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

- **Test name**: (filled in once written)
- **Test project**: Test | TestData | Osprey regression.ps1 modes 1/2/3
- **Fails on master**: (pending)
- **Passes on fix**: (pending)

The failure mode is a wrong count, not a crash, so the gate is behavioral:
`regression.ps1 -Dataset All` (modes 1/2/3 cover all three `RescoredEntries` build paths:
straight-through cold, straight-through resume, `--task SecondPassFDR` node) plus the
TeamCity Perf/Regression gate.

## Files

- `pwiz_tools/Osprey/Osprey.Tasks/PerFileRescoreTask.cs`
- `pwiz_tools/Osprey/Osprey.Tasks/Pass2FdrSidecar.cs`
- `pwiz_tools/Osprey/Osprey.Tasks/SecondPassFdrTask.cs`
- `pwiz_tools/Osprey/Osprey/Program.cs`

## Progress Log

### 2026-08-20 - Session Start

Starting work on this issue. Branch created in `C:\proj\pwiz-work1`.
