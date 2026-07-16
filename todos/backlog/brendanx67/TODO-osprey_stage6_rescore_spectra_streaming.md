# TODO: Osprey Stage-6 rescore — stream MS2 from spectra.bin (never materialize)

**Status**: Backlog (follow-up to the Stages 1–4 streaming PR).
**Priority**: Medium — the last resident full-`List<Spectrum>` load in the per-file path.
**Created**: 2026-07-16
**Scope**: `pwiz_tools/Osprey/Osprey.Tasks/PerFileRescoreTask.cs`
(`LoadSpectraForRescore`), `Osprey.Scoring/ScoringPipeline.cs`
(`RunCoelutionScoring(List<Spectrum>)` wrapper), `WindowSpectraProvider.cs`
(`ResidentWindowSpectraProvider`).

## Motivation
The Stages 1–4 PR made per-file scoring + calibration stream every isolation window
from the `.spectra.bin` cache and stop materializing the full ~6 GB `List<Spectrum>`
(via `EnsureSpectraCache`). **Stage 6 (reconciliation rescore + gap-fill) still does the
old full-resident load**: `PerFileRescoreTask.LoadSpectraForRescore` calls
`SpectraCache.LoadSpectraCache` (cache hit → whole file into memory) or
`MzmlReader.LoadAllSpectra` (miss), and passes the resident `List<Spectrum>` to the
`RunCoelutionScoring(List<Spectrum>)` wrapper → `ResidentWindowSpectraProvider`. That is
the last place the entire MS2 list is materialized in the per-file pipeline, deliberately
left out of the Stages 1–4 PR to keep it scoped.

## What to do
- Give Stage-6 rescore the same treatment: build a `SpectraWindowIndex` over the cache and
  stream each window via `StreamingWindowSpectraProvider` instead of a resident load.
- Rescore already flows through the `IWindowSpectraProvider` seam (`ScoringPipeline`
  `RunCoelutionScoring(IWindowSpectraProvider, ...)`), so the plumbing exists — the work is
  in `LoadSpectraForRescore` / the 3 `PerFileRescoreTask` call sites (748, 1381, 1449),
  supplying a streaming provider + the index's `Ms2RetentionTimes`/isolation windows.
- Check what rescore reads from the resident list beyond per-window scoring (it re-scores a
  reconciled candidate set — likely still one-window-per-candidate) and confirm the
  streaming provider covers it. Watch the multi-charge consensus rescore + forced-peak
  gap-fill paths.
- Once rescore no longer needs it, `ResidentWindowSpectraProvider` + the
  `RunCoelutionScoring(List<Spectrum>)` wrapper can likely be retired too — verify no other
  caller remains.

## Gates
- Byte-identical: `regression.ps1 -Dataset All` (mode3 HPC chain exercises Stage-6 rescore;
  mode2 resume too) + the FirstJoin/reconciliation golden.
- Watch the multi-file memory: the rescore resident load is per-file transient, but on the
  HPC merge node it stacks — measure `[MEM]` before/after.

## Not in scope
- The cache-*miss* streaming mzML parse (a streaming `MzmlReader` → `SpectraCache` writer so
  even first-parse never materializes) — its own separate TODO/lever.
