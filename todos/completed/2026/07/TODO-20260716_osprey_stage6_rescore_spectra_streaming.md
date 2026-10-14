# TODO: Osprey Stage-6 rescore — stream MS2 from spectra.bin (never materialize)

**Status**: Completed
**Branch**: `Skyline/work/20260716_osprey_stage6_rescore_spectra_streaming`
**Base**: `master` (post-#4427 merge `32106f96`)
**PR**: [#4429](https://github.com/ProteoWizard/pwiz/pull/4429) (merged 2026-07-16 as `d4b7ad54b`)
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

### 2026-07-16 (measurement scaffold + BASELINE proven; lever = 5.88 GB)
**Probe (commit pending):** added `perfile-rescore-loaded` (forced-GC, resident MS2 rooted) +
`perfile-rescore-peak (pre-GC)` (during-scoring high-water) + `perfile-rescore-live` (forced-GC
floor) probes to `RescoreOneFile`, plus retention snapshots at the loaded/floor boundaries for
dotMemory. Byte-identical (zero-cost/no-op when `OSPREY_LOG_MEMORY` unset). KEY placement lesson:
the resident MS2 must be measured RIGHT AFTER `LoadSpectraForRescore` -- Release JIT drops the
`spectra` root after its last scoring use, so a forced GC at the post-write-back "peak" already
reclaims it (live-at-peak collapsed to the floor, 8.84==8.84 in the first attempt).

**Harness:** `ai/.tmp/stage6-mem.ps1` -- single-file `--task PerFileRescoring` on Astral file 49.
`-Setup` scores file 55 (FirstPassFDR needs 2+ files; 49 alone is rejected), runs FirstPassFDR
(49+55 -> 21 MB reconciliation.json + 101 MB 1st-pass.bin for 49), and stages a rescore dir that
HARDLINKS the 6.3 GB spectra.bin + a 0-byte stub mzML (fingerprint skipped for a 0-byte source ->
guaranteed cache HIT, no mzML read). Measure loop deletes only the rescore outputs per rep.
`-DotMemory` drives dotMemory `--use-api`. Rescore does REAL work: 65,611 entries re-scored,
62,749 reconciliation actions.

**BASELINE (before, median of 3, Astral file 49):**
| metric | GB |
|---|---|
| loaded-live (forced-GC, resident MS2 rooted) | 8.19 |
| working_set peak (during-scoring high-water) | 29.81 |
| pre-GC managed at peak | 14.80 |
| post-release floor (in RescoreOneFile) | 9.00 |
| truly-persistent floor (reconciliation-resident) | 2.39 |

**LEVER SIZED DIRECTLY (`ai/.tmp/measure-ms2-size.ps1`, Server GC, managed-heap delta of
`LoadSpectraCache`):** 204,149 MS2 = **5.88 GB** (the streamed-away resident set); 1,223 MS1 =
0.03 GB (stays resident by design). So streaming should drop loaded-live 8.19 -> ~2.3 GB and cut
the during-scoring peak further by also eliminating the per-pass calibrated COPIES the resident
provider builds. dotMemory `.dmw` saved at `D:\test\osprey-runs\_stage6mem\stage6-rescore-before-*.dmw`
(11.5 GB; open -> `perfile-rescore-loaded` snapshot -> dominators to confirm List<Spectrum> holds
the 5.88 GB).

### 2026-07-16 (IMPLEMENTED + all local gates green; committed 89943fb38, pushed)
**Change (commit `89943fb38`):**
- `PerFileRescoreTask.LoadSpectraForRescore` -> `SpectraWindowIndex.BuildFromCache` (streams each
  window); MS1 + isolation windows from the index; ONE shared `StreamingWindowSpectraProvider`
  across the subset rescore + both gap-fill passes (stateless, re-reads windows per pass). **No mzML
  fallback** -- absent/stale cache hard-fails (`InvalidDataException`), per Brendan.
- **Retired** `ResidentWindowSpectraProvider` + `ScoringPipeline.RunCoelutionScoring(List<Spectrum>)`
  wrapper (callerless once all 3 rescore sites use the provider). Net -56 lines.
- **regression.ps1 mode3** phase-3 now ships phase-1's `<stem>.spectra.bin` + a 0-byte stub mzML to
  the rescore worker (was: copy the real mzML + rely on the removed reparse fallback). Disk-neutral.
- Added `perfile-rescore-loaded/-peak/-live` [MEM] probes + a `perfile-rescore-apex` retention
  snapshot so the NEXT lever (scored/reconciled entries rooted by fdrEntries) is directly visible.

**A/B RESULT (Astral file 49, median of 3, before=resident vs after=streaming):**
| metric | before | after | delta |
|---|---|---|---|
| loaded-live (resident MS2 rooted) | 8.19 GB | 2.30 GB | **-5.89 GB (-72%)** |
| working_set peak (during-scoring) | 29.81 GB | 14.1 GB | **-15.7 GB (-53%)** |
| pre-GC managed at peak | 14.8 GB | 8.63 GB | -6.17 GB |
| rescore wall (warm) | 64.3 s | 57.5 s | **-11% (faster; GC-pressure relief)** |

-5.89 GB loaded-live matches the measured 5.88 GB MS2 lever exactly; the extra WS drop is the 3
per-pass whole-list calibrated copies, also gone. FASTER warm (no perf regression), mirroring #4427.

**Gates (all green):** `regression.ps1 -Dataset Stellar` mode1 (vs golden) + mode3 (HPC chain, now
streams) + mode2 (resume) all PASS byte-identical (blib 45,064,192). `Build-Osprey.ps1 -RunTests
-RunInspection`: 508/508 tests, inspection 0/0. after `.dmw`:
`D:\test\osprey-runs\_stage6mem\stage6-rescore-after-20260716-191611.dmw` (5.8 GB, half the before).

**Remaining before merge:** `regression.ps1 -Dataset All` (Astral) + TeamCity Astral Perf/Regression
(Brendan-gated); `/pw-self-review`; open PR.

### NEXT LEVER (Brendan, from the dotMemory summary): scored-entry accumulation
After the resident MS2 is gone the dominant per-file holder is the **scored + reconciled entries**
(~6.5 GB for file-49 rescore): parquet-loaded fdrEntries + reconciled/gap-fill results, each carrying
heavy per-entry arrays (Features / CwtCandidates / Fragment* / ReferenceXic*). We do NOT write scored
precursors as we go -- the whole set is held to the end (rescore even reloads the full parquet in the
write-back). Same root cause in **BOTH** PerFileScoring (~8 GB scoredEntries) and PerFileRescoring.
Dedup + FDR need the full set but only the light scalars; the heavy arrays are only needed to write
the parquet, so they could be flushed + nulled as scoring proceeds. Backlog:
`TODO-osprey_perfile_scored_entry_streaming.md` -- the next PR, shared across both stages. The new
`perfile-rescore-apex` snapshot in the after `.dmw` shows these dominators. Written up as a
standalone backlog TODO: `TODO-osprey_parquet_bounded_rowgroup_write.md` (bounded row-group write,
shared by PerFileScoring + the reconciled write-back; start after this squash-merges).

### 2026-07-16 (self-review clean + PR #4429 opened)
Fresh-context `/pw-self-review` (general-purpose agent, diff vs origin/master): **no CRITICAL/HIGH**.
Independently verified byte-identity (fresh per-pass decode == resident calibrated copy; ScoreWindow's
(RT,ScanNumber) re-sort makes the offset-vs-file pre-sort order irrelevant; index IsolationWindows/MS1
== ExtractIsolationWindows/resident MS1), `Parallel.For` concurrency (LoadWindow owns its FileStream,
immutable index maps, pure ApplyCalibration), the mode3 0-byte-stub fingerprint skip
(`TryReadHeader:305-310`), retirement completeness (zero residual refs), and the ProfilerHooks no-op.
- **[MEDIUM] accepted (intended, per Brendan's directive):** hard-fail on absent cache is a genuine
  behavior change -- a resume with a SEPARATE `--cache-dir` that was independently cleaned would abort
  where the old mzML fallback succeeded. Error message is clear + actionable ("Re-run PerFileScoring
  for <file>"). Flagged in the PR body; straight-through / same-dir resume / HPC chain are unaffected.
- **[LOW] fixed (commit `63a2e6e40`):** stale RescoreOneFile doc ("reload ... or the mzML") -> streams.

PR #4429 opened (body per version-control convention). **Remaining before merge (Brendan-gated):**
`regression.ps1 -Dataset All` (Astral byte-identity) + TeamCity Astral Perf/Regression; optional
Copilot / `/ultrareview`.

### 2026-07-16 (Copilot review + COLD perf A/B)
**Copilot (PR #4429):** 2 inline comments, one duplicated nit -- phase-3 stub named `"$s.mzML"` vs
`Split-Path -Leaf $mzmlByStem[$s]` for case-sensitive-FS robustness. **Pushed back** (Brendan
concurred, triggered TeamCity on `63a2e6e40` with no changes): consistent with the phase-2/4 stubs,
the rescore worker derives cache/sidecar paths from the `.scores.parquet` stem (`ResolveInputScores`
-> `Config.InputFiles`) not the stub filename, mode3 byte-identical, Windows-only harness. Replied to
both threads, left unresolved for the human reviewer.

**COLD perf A/B (Brendan: "HPC will always be cold").** Built the resident before-binary from
`32106f960` into `D:\test\osprey-runs\_stage6base\net8.0`; `ai/.tmp/stage6-cold-perf.ps1` evicts the
OS standby cache (42 GB balloon, as a CHILD process so it frees on exit) before each rep and runs
`--task PerFileRescoring` cold with NO `OSPREY_LOG_MEMORY` (clean timing). Astral file 49:

| cold (no probe) | rep1 | rep2 |
|---|---|---|
| before (resident) | 83.2 s | 63.0 s |
| after (streaming)  | 51.8 s | 52.2 s |

**min-before (63.0) > max-after (52.2)** -> streaming is FASTER cold by ~11-31 s, never slower.
Streaming overlaps the cold per-window I/O (contiguous v4 reads) with scoring compute, vs the
resident path's blocking upfront full read + 3 calibrated-copy allocations. Resolves the HPC
cold-worker concern. TeamCity Astral Perf/Regression (running) is the authoritative whole-pipeline
cold gate.

### 2026-07-16 - Merged

PR #4429 merged as squash commit `d4b7ad54b` on master. Shipped: Stage-6 rescore
(`PerFileRescoreTask`) streams each isolation window's MS2 from the `.spectra.bin` cache via a shared
`StreamingWindowSpectraProvider` instead of a resident ~6 GB `List<Spectrum>`; the cache is required
(no mzML fallback, hard-fails if absent). Retired `ResidentWindowSpectraProvider` + the
`RunCoelutionScoring(List<Spectrum>)` wrapper (net -56 lines); `regression.ps1` mode3 now ships
phase-1's `.spectra.bin` (+ 0-byte stub mzML) so the HPC chain streams. Astral file 49: resident MS2
load 8.19->2.30 GB, working-set peak 29.8->14.1 GB (-53%), faster warm AND cold. Byte-identical
(Stellar mode1/2/3, 508 tests, 0-warning inspection, TeamCity Astral green 18/18). Copilot's one nit
(phase-3 stub filename) pushed back with rationale, threads left open for the human reviewer.
Follow-up filed: `TODO-osprey_parquet_bounded_rowgroup_write.md` (the reconciled/scores Parquet write
is now the tallest ~14 GB per-file peak; bounded row-group write shared with PerFileScoring).
