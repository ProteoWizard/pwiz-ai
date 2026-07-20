# TODO: Osprey transfer / mdiag-on-resume resident first-pass pool (OOMs at 82 files)

**Status**: Active (started 2026-07-19).
**Branch**: `Skyline/work/20260719_osprey_transfer_streaming` (pwiz).
**Priority**: Medium for the transfer arm alone (transfer is the non-default experimental pass-2
mode, #4410); HIGHER for the mdiag-on-resume half, which OOMs ANY --model-diagnostics RESUME at
scale (percolator too), not just transfer.
**Created**: 2026-07-19
**Next-session handoff (start here)**: `ai/.tmp/handoff-20260719_osprey_transfer_mdiag_resume_streaming.md`
-- session-start protocol, the exact B-run command (+ OSPREY_VERSION_OVERRIDE=26.1.1.199 resume), the
flat-through-Stage-5 success criterion, and gotchas (detached runs, cwd trap).
**Scope**: `Osprey.Tasks/FirstJoinTask.cs:~280` (`needsResidentFirstPassPool` = ... ||
`OspreyEnvironment.Pass2TransferQ`), `Osprey.Tasks/PerFileScoringTask.cs:~625`
(`needsResidentPool = NeedsResidentPool(config) || config.ModelDiagnostics` on the RESUME path),
the transfer score->q table build (`Pass2FdrSidecar` / the #4410 transfer mechanism).

## What we observed (2026-07-19, 82-file SEA-AD Astral, transfer resume from A)
Ran B = `--task`-equivalent transfer + --model-diagnostics, RESUMED from A's Stage-1-4 sidecars
(LinkFrom, OSPREY_VERSION_OVERRIDE=26.1.1.199). Resume worked (skipped Stages 1-4). But loading
the resident first-pass pool OOM'd at the **82 GB commit ceiling at only 46% loaded**
(managed 80.5 GB / private 82.2 GB, WS collapsed to 0.3 GB = fully paged); projecting ~178 GB to
finish. Killed to save the box. Trajectory: 40%->70 GB, 45%->79 GB, 46%->82 GB. 64 GB physical /
82 GB commit. This is why the 82-file transfer arm has NEVER completed in any prior session.

## Root cause -- TWO forcing conditions (both must be fixed)
`needsResidentFirstPassPool`/`needsResidentPool` is forced true by BOTH:
1. **transfer** (`OspreyEnvironment.Pass2TransferQ`, FirstJoinTask.cs:~282): the TRIC score->q
   table is built from the full pre-compaction pool, so the fat `FdrEntry` pool (21 PIN features
   per row, all 82 files) is held resident. The #4435 FirstPassFDR streaming does NOT apply -- it
   is the resident FORK.
2. **--model-diagnostics on RESUME** (PerFileScoringTask.cs:~625): the fresh compute Run path
   streams the mdiag report via the ModelDiagnosticsData.Accumulator (#4420), but a RESUME skips
   the score pass, so FirstJoin emits the report via the RESIDENT batch `ModelDiagnosticsReport.
   Write`, forcing the fat pool. This is the pre-existing #4355/#4377 asymmetry flagged in the
   #4435 self-review -- and it OOMs a **percolator** mdiag resume at 82f too, not just transfer.

## The levers (both tractable)
1. **Stream the transfer score->q table:** it only needs `(score, label)` per entry, NOT the 21
   features (7/13 handoff mdiag-82file §5). Build it in a streaming pass over parquet scalars +
   the frozen 1st-pass model (like RunStreamingFirstPass does for the q maps) -- a smaller lever
   than the full first-pass streaming.
2. **Stream mdiag-on-resume:** wire the RESUME path to feed the same ModelDiagnosticsData.
   Accumulator the fresh Run path uses (#4420), instead of the resident batch report -- removes
   the #4355/#4377 asymmetry. Fixes percolator+mdiag+resume at scale as a side effect.

With both, an 82-file transfer+mdiag resume fits in 64 GB (streaming, like A's fresh percolator run).

## Gates
- Transfer output byte-identical vs the 20-file transfer oracle (7/13 pass2ab-20file results).
- 82-file transfer+mdiag RESUME completes in 64 GB (the run that OOM'd here).
- mdiag report byte-identical fresh-Run vs resume (the asymmetry fix must not change output).
- `regression.ps1 -Dataset Stellar` (default percolator path unaffected).

## Progress (2026-07-19, session)
Implemented on `Skyline/work/20260719_osprey_transfer_streaming` (pwiz commit 604c85568):
- **Lever 1 (transfer table streaming):** new `Pass2FdrSidecar.FirstPassScoreQTableAccumulator`
  fed by `FdrStoringSink` (averaged-model score `fScores`/`finalScores` + effective experiment q --
  the same pair the resident `BuildFullPopulationScoreQTable` collects); `BuildScoreToQTable` sorts,
  so the streamed table is byte-identical. Threaded a `captureModel` callback through
  `RunStreamingFirstPass`/`RunStreamingIntoProjection` to publish `FirstPassPercolatorModel` off the
  projection path. Removed `Pass2TransferQ` from `needsResidentFirstPassPool` (FirstJoinTask) and
  `NeedsResidentPool` (PerFileScoringTask). Resident `BuildFullPopulationScoreQTable` kept for the
  projection-off path.
- **Lever 2 (mdiag on resume):** dropped `|| config.ModelDiagnostics` from the RehydrateFromOwnOutputs
  resident-pool gate; `FirstJoinTask.WriteModelDiagnosticsFromSidecars` streams the 1st-pass sidecar +
  parquet scalars into `ModelDiagnosticsData.Accumulator` + `WriteFromAccumulator` on the Rehydrate
  path (`streamModelDiagnosticsFromSidecars`). `BuildModelDiagnosticsAccumulator` now takes run names.
- **Gates green so far:** Build + 520 unit tests + zero-warning inspection; `regression.ps1 -Dataset
  Stellar` mode1/2/3 byte-identical (default path unaffected; lean resume + HPC reconciliation OK).
- **PR:** #4437 (open; CI unit build running).
- **8-file A/B GREEN** (master pwiz-work2 @ df9bb01218 resident vs branch streaming, both LinkFrom the
  82-file A Stage-1-4 caches, OSPREY_VERSION_OVERRIDE=199):
  - Transfer: all 8 `.1st-pass.fdr_scores.bin` byte-identical (resident==streaming). These carry the
    exact (averaged-model score, experiment q) pairs the table is built from, so the table is identical
    (BuildScoreToQTable sorts). `2nd-pass q comes from` the streamed table + published model confirmed.
  - mdiag: `out.model-diagnostics.data.json` + `.html` byte-identical modulo GeneratedUtc (resident
    `Write` vs streaming `WriteFromAccumulator`).
  - **Memory (the point):** 8-file, 33.3M entries: unfixed Stage-5 managed heap **48 GB** (resident
    FdrEntry pool) -> fixed **13 GB** (streamed); whole-run managed peak 48 GB -> 21.6 GB (peak MOVED
    to the Stage-6 reconciliation survivor buffer -- the expected mild incline, separate Stage-6 TODO).
  - I sized the resident "before" arm down from 20 files (peaked ~60 GB, too close to the 64 GB wall)
    to 8 files (~48 GB Stage-5) at Brendan's prompting; killed it after it wrote the 1st-pass sidecars +
    pass-1 mdiag (enough for the diffs) rather than running the full resident pipeline.
- **Case B (mdiag on FirstJoin.Rehydrate)** not directly A/B'd -- uses the same WriteFromAccumulator +
  sidecar-streaming primitives as Case A (validated), byte-identical by construction. Flag for self-review.
- **82-file B run LAUNCHED + Stage 5 CONFIRMED FLAT** (`runs\pass2ab-82file-transfer-5dayTransferFixed`,
  fixed binary, LinkFrom A, v199, threads 8): resumed Stage 1-4, streamed Stage 5 on 344.6M entries.
  Log confirms BOTH levers at scale: `[MODEL-DIAGNOSTICS] wrote model diagnostics report` (18:18) and
  `OSPREY_PASS2_QVALUE=transfer: built FULL-population score->q table` (18:20). Stage-5 live-managed peaked
  ~36-51 GB (transient pre-GC; the score->q accumulator + #4435 streamingQ over 344M rows) then dropped --
  NOT the 82 GB live resident pool that OOM'd the unfixed run (which sat at 80 GB live managed). Now in
  Stage 6 (survivor reload ~38 GB / reconciliation), the expected mild incline. No OOM.
- **PR self-review (fresh agent):** 1 HIGH, 2 MEDIUM, 2 LOW. MEDIUM/LOW addressed in pwiz 016fb99d3
  (stale-comment fix; nSkipped byte-identity invariant documented; `TestScoreQTableOrderIndependent`).
- **OPEN -- HIGH finding to verify post-B-run:** dropping `config.ModelDiagnostics` from
  `RehydrateFromOwnOutputs` makes a straight-through mdiag resume that lands in `FirstJoin.Rehydrate`
  (Stage-5 sidecars cached) produce lean/empty `ScoredEntries`; the agent worried
  `HydrateReconciliationOverlay`->`CompactedEntries` could go empty and starve Stage 7/8. Investigation:
  the bundle-path `CompactFirstPass` calls `RescoreCompaction.Apply(bundle)` (operates on the disk-hydrated
  bundle, not the stubs), and MergeNode reads `RescoredEntries`/the reconciled parquet -- so it MAY
  reconstruct from disk regardless. The `#4435` comment framed the resident-pool forcing as ONLY for the
  mdiag report, implying reconciliation already works lean (plain percolator is lean too). NOT the B-run
  path (that's `FirstJoin.Run`). **Verify:** small plain-percolator straight-through, then invalidate a
  DOWNSTREAM stage but keep FirstJoin's Stage-5 sidecars, re-run -> forces `FirstJoin.Rehydrate` lean ->
  check the blib is non-empty + byte-identical. If plain works -> mdiag works (dismiss). If broken ->
  pre-existing #4400/#4435 issue; my change would regress mdiag-resume-to-Rehydrate (was fat) -> fix then.
- **Next:** B run -> exit 0; render perfviz + compare A vs B mdiag; run the FirstJoin.Rehydrate verification.

## References
- Same O(files)-resident memory theme: `[[TODO-osprey_stage6_rescored_buffer_streaming]]`
  (Stage-6 survivor buffer + Stage-7 SecondPassFDR peak).
- transfer mode: PR #4410. mdiag streaming (fresh path): PR #4420. FirstPassFDR streaming
  precedent + the mdiag-resume asymmetry note: PR #4435 / `[[TODO-20260718_osprey_firstpassfdr_resident]]`.
- `[[reference_osprey_perfile_mem_measurement]]` (reading the [MEM]/perfviz probes).
