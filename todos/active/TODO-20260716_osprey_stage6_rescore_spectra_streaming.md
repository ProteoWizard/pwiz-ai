# TODO: Osprey Stage-6 rescore — stream MS2 from spectra.bin (never materialize)

**Status**: In Progress (follow-up to the Stages 1-4 streaming PR #4427).
**Branch**: `Skyline/work/20260716_osprey_stage6_rescore_spectra_streaming`
**Base**: `master` (post-#4427 merge `32106f96`)
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

## Progress Log

### 2026-07-16 (session start: branch cut, code audit, measurement-first plan)
Branch `Skyline/work/20260716_osprey_stage6_rescore_spectra_streaming` off master `32106f96`
(#4427 merge). TODO backlog -> active.

**Brendan's guidance this session:**
1. Measurement-first: get a repeatable single-file Stage-6 harness (`--task PerFileRescoring`
   on pre-processed data) with before/after peak-memory + a dotMemory dump, to PROVE the lever
   before/after the change.
2. **Stream from `.spectra.bin` only — no mzML fallback.** Stage-6 will essentially always have
   the cache; if absent, that is an error, not a reason to re-read mzML. So the change is
   simpler than reusing Stage-4's mzML-parsing `EnsureSpectraCache`: rescore just `BuildFromCache`
   and hard-fails if absent.

**Code audit (map of the resident `spectra` use in `PerFileRescoreTask`):**
- `RescoreOneFile` (`:644`): `LoadSpectraForRescore` (`:1485`) -> resident `LoadSpectraCache`
  (cache hit) / `MzmlReader.LoadAllSpectra` (miss). The resident list is used ONLY at:
  `ExtractIsolationWindows` (`:738`) + the 3 `RunCoelutionScoring` sites (`:748` subset rescore,
  `:1381` gap-fill CWT, `:1449` gap-fill forced, the latter two inside `RunGapFillTwoPass :1337`)
  + the `spectra = null` release (`:805`). No hidden multi-charge/consensus use.
- Rescore does NOT call `DeduplicateDoubleCounting`, so the provider's `Ms2RetentionTimes` is not
  even needed here (unlike Stage-4).
- The `RunCoelutionScoring(List<Spectrum>)` wrapper's ONLY callers are these 3 rescore sites;
  `ResidentWindowSpectraProvider` is constructed ONLY inside that wrapper. Converting all 3
  opens the door to retiring both (TODO stretch goal) — pending the fallback decision.

**Harness facts established:**
- Post-#4427 the "before" is `SpectraCache.LoadSpectraCache` (full resident grouped load, acq
  order). One `StreamingWindowSpectraProvider(index, ms2Cal)` can be SHARED across all 3 sites
  (stateless; each `GetCalibratedWindow` is a fresh decode), so re-scoring one file 3x just
  re-reads windows — no shared-mutation hazard (which is why the resident path needed
  `consumeInputMzs:false`).
- `RescoreOneFile` has NO memory-boundary probe yet (only the reconciliation-level method has
  `reconciliation-*` probes). Adding a `perfile-rescore-peak` `[MEM]` + `CaptureRetentionSnapshot`
  (mirrors `perfile-scoring-peak`) is the measurement scaffold — zero-cost when `OSPREY_LOG_MEMORY`
  unset, byte-identical; land it FIRST so before/after share the same probe.
- Cache fingerprint (`SpectraCache.TryReadHeader`) is size+mtime, but SKIPPED when the source
  mzML is 0 bytes (`:308 actualSize != 0`). So a 0-byte stub mzML + present `.spectra.bin` =
  guaranteed cache hit in a scratch dir (no 6.3 GB mtime dependency). Same stub trick the
  regression HPC-chain FirstJoin/MergeNode phases use.
- `--task PerFileRescoring` needs `.scores.parquet` + `.calibration.json` + `.spectra.bin`
  (file 49 has all three at `D:\test\osprey-runs\astral\`) + `.reconciliation.json` +
  `.1st-pass.fdr_scores.bin` (generate via `--task FirstPassFDR`; recipe = regression.ps1
  `Invoke-HpcChain` phase 2).

**GATE INTERSECTION (resolve at implementation):** regression.ps1 mode3 phase-3 (rescore) does
NOT ship the `.spectra.bin` to the worker — it copies the mzML and relies on the current
cache-miss `LoadAllSpectra` fallback. Removing that fallback (per guidance) means mode3 phase-3
must instead ship phase-1's `.spectra.bin` so it streams (models the intended deployment +
exercises the new path). Byte-identical (cache round-trip == mzML parse of the same file, already
validated for Stage-4). Confirm retire-vs-keep-fallback with Brendan before coding.
