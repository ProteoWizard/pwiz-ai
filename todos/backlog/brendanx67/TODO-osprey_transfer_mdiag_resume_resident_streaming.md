# TODO: Osprey transfer / mdiag-on-resume resident first-pass pool (OOMs at 82 files)

**Status**: Backlog.
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

## References
- Same O(files)-resident memory theme: `[[TODO-osprey_stage6_rescored_buffer_streaming]]`
  (Stage-6 survivor buffer + Stage-7 SecondPassFDR peak).
- transfer mode: PR #4410. mdiag streaming (fresh path): PR #4420. FirstPassFDR streaming
  precedent + the mdiag-resume asymmetry note: PR #4435 / `[[TODO-20260718_osprey_firstpassfdr_resident]]`.
- `[[reference_osprey_perfile_mem_measurement]]` (reading the [MEM]/perfviz probes).
