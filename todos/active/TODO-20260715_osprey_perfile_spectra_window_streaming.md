# TODO: Osprey per-file MS2 spectra streaming by isolation window

**Status**: Implemented + byte-identity-gated (Stellar+Astral), **PR HELD** pending a
bigger memory-apex win (the MS2-streaming payoff alone is only ~2 GB -- see Phase 4
findings). Branch pushed, 3 commits. NOT merged. Next: extend the rearchitecture to
the actual per-file apex (calibration + scored entries) before opening a PR.
**Branch**: `Skyline/work/20260715_osprey_perfile_spectra_window_streaming` (pushed, HEAD `07c23c7`)
**Base**: `master` (follow-on to #4424, merged)
**Priority**: High (the single largest remaining per-file memory lever; ~6.3 GB of
resident MS2 spectra held in BOTH the calibration and scoring peaks) -- **REVISED by
Phase 4 measurement: #4424 already freed the m/z (~4 GB) via consumeInputMzs, so
MS2-streaming's SCORING-phase remainder is only ~2 GB; the true apex is the CALIBRATION
phase (holds full resident MS2) + the ~8 GB of scored entries. See Phase 4 below.**
**Complexity**: Large (streaming refactor of a parity-locked scoring path + a new
seekable loader; the design is clear and HIGH-confidence byte-identical, the risk is
byte-parity of the on-disk reads, three method-signature changes, and parallel-reader
concurrency)
**Created**: 2026-07-15
**Scope**: `pwiz_tools/Osprey/Osprey.IO/SpectraCache.cs` (+ a new
`SpectraWindowIndex.cs`), `Osprey.Scoring/ScoringPipeline.cs`,
`Osprey.Scoring/CoelutionScorer.cs`, `Osprey.Tasks/PerFileScoringTask.cs`.

## Progress (branch `Skyline/work/20260715_osprey_perfile_spectra_window_streaming`)

Implemented in three byte-identity-gated phases (design refinement vs the original
plan: `RunCoelutionScoring` has 3 resident callers -- Stage-6 rescore + 2 gap-fill --
so instead of swapping its `List<Spectrum>` param we introduced an
`IWindowSpectraProvider` seam that both the resident and streaming paths flow through):

- **Phase 1 (commit `8ad51e2`)** -- `SpectraWindowIndex` (Osprey.IO): header-only pass
  builds a `windowKey -> [fileOffset]` map + `AllMs2Rts`; `LoadWindow(key)` seeks +
  decodes one window on demand via shared `SpectraCache.ReadMs2Record`. DRY-refactored
  `SpectraCache` decode into `TryReadHeader`/`ReadMs2Record`/`ReadMs1Record`. New
  `TestSpectraWindowIndex` proves streamed grouping == `LoadSpectraCache` grouping
  (byte-identical, incl. two centers rounding to one key, an empty-peak record, MS1 skip,
  absent key, `AllMs2Rts`). Debug build + inspection (0 warn) + test green.
- **Phase 2 (commit `c1b90f5`)** -- `IWindowSpectraProvider` + `ResidentWindowSpectraProvider`
  (Osprey.Scoring, holds the old calibrate-copy+group prologue verbatim incl.
  `consumeInputMzs`); `RunCoelutionScoring` split into a resident `List<Spectrum>` wrapper
  (used unchanged by the 3 rescore callers) + a provider core; `ScoreWindow` takes one
  window's list; `DeduplicateDoubleCounting` takes `IReadOnlyList<double>`. **Gate:
  `regression.ps1 -Dataset Stellar` mode1/2/3 all PASS (blib byte-identical).**
- **Phase 3 (commit `07c23c7`)** -- `StreamingWindowSpectraProvider` (Osprey.Tasks,
  wraps the IO index, calibrates each window in place). In `ProcessFile` after
  `ResolveCalibration`: `BuildFromCache` the index, `spectra = null` (drops the resident
  MS2), stream scoring; resident fallback if the cache can't be indexed. All 510 unit tests
  pass. **Gate: `regression.ps1 -Dataset All` (Stellar + Astral) mode1/2/3 all PASS,
  blib byte-identical (Stellar 45,064,192; Astral 135,249,920).**

Verified byte-identity linchpins: `Calibrator` never mutates the resident spectra objects
or order (it sorts only its own transient dict lists); after `LoadSpectra` the on-disk
cache matches the resident spectra bit-for-bit; `ScoreWindow`'s `(RT, ScanNumber)` re-sort
is a unique total order so file-order streamed load scores identically.

## Phase 4 findings -- MEASUREMENT REVERSED THE PREMISE (read before continuing)

Single Astral file 49, Stage 1-4, `OSPREY_LOG_MEMORY=1`, resident (Phase 2 `c1b90f5`) vs
streaming (Phase 3). To get a readable scoring-peak number I temporarily routed the
`perfile-scoring-peak` retention snapshot through `ProfilerHooks.LogManagedHeapAfterGcIfEnabled`
(forced-GC printf; reverted after measuring -- main is clean at `07c23c7`).

| metric (file 49) | resident | streaming | delta |
|---|---|---|---|
| `perfile-scoring-peak` forced-GC LIVE | 6.02 GB | 4.05 GB | **-1.97 GB** |
| managed pre-GC after scoring | 9.43 GB | 6.81 GB | -2.6 GB |
| peak working set | 25.89 GB | 23.53 GB | -2.4 GB (NOISY: first A/B showed ~0) |
| committed (last GC) | 26.09 GB | 23.48 GB | -2.6 GB |
| **post-calibration managed (the APEX)** | **11.02 GB** | **11.08 GB** | **~0 (unchanged)** |
| wall (Stage 1-4) | 92.7 s | 91.0 s | ~0 (perf-neutral) |

**Conclusions:**
1. The mechanism WORKS and is byte-identical + perf-neutral -- streaming genuinely drops
   the resident MS2 from the scoring-phase live set (6.02 -> 4.05 GB).
2. But the payoff is **~2 GB, not ~6.3 GB**: #4424's `consumeInputMzs` already freed the
   resident *m/z* (~4 GB) during scoring, so only the ~2-3 GB of intensities remained for
   this work to reclaim.
3. The peak-WS/committed benefit is **GC-decommit-timing-dependent** -- the first (no
   forced-GC) A/B showed the freed pages staying committed (peak ~unchanged); only once a
   GC runs after `spectra = null` do they decommit. Noisy ~0..2.4 GB run-to-run.
4. **The per-file APEX is now the CALIBRATION phase** (post-cal managed ~11 GB > scoring
   peak ~4-6 GB), which still materializes the full resident MS2 for Stage-3 XCorr and is
   OUT OF SCOPE for this change. So streaming SCORING does not lower the per-file peak.
   The other co-dominant holder at the scoring peak is the **~8 GB of scored entries**.

**PROVISIONAL -- retention not yet dominator-verified (per Brendan).** All of the above is
from console `[MEM]` AGGREGATES, which show how much is live, not WHO holds it. Before
trusting "the resident MS2 is released, so the win is only ~2 GB", a dotMemory retention
snapshot (`perfile-scoring-peak` dominators) must confirm nothing unexpected still roots
the resident MS2 (index / provider / closure / isolationWindows / scratch pool /
windowResults). If a hidden root exists, streaming is NOT releasing as intended and fixing
that root is the real lever. A current-state streaming `.dmw` was generated at
`ai/.tmp/osprey-memory-*.dmw`; a fresh `.dmw` is a required end-of-night deliverable. See
`ai/.tmp/handoff-osprey-memory-apex-20260715.md` -> "CRITICAL: validate RETENTION".

## Next: prove the apex win before any PR (the /night-session mission)

The rearchitecture (SpectraWindowIndex + provider seam) is a clean, byte-identical,
perf-neutral FOUNDATION but does not justify itself on a ~2 GB scoring-only win. To prove
its value, land the pieces that actually move the per-file apex, THEN PR the whole thing:

- **Lever A -- stream the CALIBRATION phase's spectra** (the true apex). Stage 3
  (`Calibrator.RunCalibration` -> builds its own `spectraByWindowKey` +
  `PreprocessWindowsForXcorr` dense XCorr cache) currently holds the full resident MS2.
  Investigate whether calibration can consume the same `IWindowSpectraProvider` / index
  per window (its access pattern samples entries across windows -- confirm it can be a
  per-window sweep or a windowed load). This is the biggest apex lever.
- **Lever B -- stream/bound the ~8 GB of scored entries** (co-dominant at the scoring
  peak). See the sibling `TODO-osprey_perfile_scored_entry_streaming.md`: write scored
  entries to `.scores.parquet` incrementally instead of accumulating all in RAM.

Together A+B (on top of this MS2 streaming) would drop the ~6.3 GB resident MS2 AND the
8 GB scored entries from the apex -- the real "fit large runs on a modest machine" win
(#4355/#4378 lineage). Only then is the rearchitecture's value provable -> open the PR.

Held gates (do NOT re-litigate; already green on this branch): `Build-Osprey.ps1 -RunTests
-RunInspection` (my files 0 warn; SystemMemory.cs 9 = known #4379 noise), `regression.ps1
-Dataset All` (byte-identical). `Test-PerfGate.ps1` was deferred -- the single-file A/B
already showed perf-neutral, so it is not the blocker; the apex win is.

## Start here (fresh session)

Run `/pw-startup` on this file. Load `/osprey-development` + `/debugging`. This is the
follow-on to the **2026-07-15 per-file memory-reduction sprint** (branch
`Skyline/work/20260715_osprey_memory_reduction`, 4 byte-identical commits): that work
freed the redundant calibrated-spectra m/z copy in scoring (scoring peak 16.08 -> 9.41
GB managed on Astral file 49) and halved the calibration XCorr cache (3.3 -> 1.65 GB).
After it, the **apex is the calibration peak (~13 GB managed)** and the dominant shared
holder in BOTH peaks is the **~6.3 GB of resident MS2 spectra**. This TODO streams them.

## Motivation (measured)

Single Astral file 49, Stage 1-4, `OSPREY_LOG_MEMORY=1` (harness:
`ai/scripts/Osprey/run-astral-mem.ps1`-style single-file run; `Get-MemoryReport.ps1`
for the A/B table; `Profile-Osprey.ps1 -Dataset Astral -MemoryProfile` for a retention
`.dmw`). Both the calibration peak and the scoring peak hold the full MS2 spectra list
(~204k `Spectrum`, ~6.3 GB) resident. Streaming the spectra **per isolation window**
(load a window's spectra, score it, release) drops the resident MS2 from ~6.3 GB to
roughly `NThreads` windows (~tens of MB), reducing BOTH peaks.

## What is ALREADY there vs what this adds (do not confuse them)

Both C# and Rust already **iterate/score by isolation window** -- but they LOAD THE
WHOLE SPECTRA CACHE INTO RAM FIRST, then group in memory:

- C#: `PerFileScoringTask.LoadSpectra` -> `SpectraCache.LoadSpectraCache`
  (`PerFileScoringTask.cs:2271`) or `MzmlReader.LoadAllSpectra` (`:2295`) returns the
  full `List<Spectrum>`. Then `RunCoelutionScoring` builds
  `spectraByWindowKey = Dictionary<int, List<Spectrum>>`
  (`ScoringPipeline.cs:131-143`, key `= (int)Math.Round(IsolationWindow.Center * 10.0)`)
  and scores window-by-window.
- Rust (`crates/osprey/src/pipeline.rs`): `load_spectra_cache` (`:3161`) loads all,
  then `run_search` calls `group_spectra_by_isolation_window(spectra_ref)` (`:7810`)
  and builds the per-window XCorr cache `Vec<Vec<f32>>` (`:7920`).

So "iterating over isolation blocks" **exists** (this is what a reader may mean by
"it's already in there"); "not loading the entire cache into memory" **does not**. This
TODO is the memory-axis change: a `window -> [file offsets]` index over the on-disk
cache + lazy per-window load/release. (The only streaming today is file-granularity:
reconciliation re-scores files sequentially to avoid holding every file's spectra --
still all-of-one-file in RAM.)

## Design (HIGH-confidence, byte-identical)

The key correctness fact: each isolation window's MS2 scoring is **self-contained** --
`CoelutionScorer.ScoreWindow` (`CoelutionScorer.cs:70`) reads only
`spectraByWindowKey[windowKey]`, never other windows' MS2, and re-sorts each window by
the unique total order `(RetentionTime, ScanNumber)`, so the pre-sort/streaming order
is **irrelevant to output**. MS1 access is global (`PeakDataExtractor` ->
`MS1Spectrum.FindNearest`, an RT binary search over the whole MS1 list), so **MS1 stays
fully resident** (small in DIA; do NOT stream MS1).

1. **`SpectraWindowIndex` (new, `Osprey.IO`).** `BuildFromCache(cachePath, sourcePath)`:
   open `.spectra.bin`, validate the header identically to `LoadSpectraCache`, then do a
   **header-only pass** over the `n_ms2` records reading the fixed **48-byte MS2 prefix**
   (`scan, rt, precursor_mz, iso_center, iso_lower, iso_upper, n_peaks`) and
   `Seek(n_peaks * 12, SeekOrigin.Current)` past the peak blob (peaks are
   `f64 mz * n + f32 int * n = 12*n` bytes). Build
   `Dictionary<int, List<long>> windowKeyToOffsets` with the SAME key as today,
   `(int)Math.Round(iso_center * 10.0)`, plus a flat `double[] allMs2Rts` in file order.
   `LoadWindow(windowKey)`: seek to each offset, read the record into a `Spectrum` using
   the SAME decode helpers as `LoadSpectraCache`; return a fresh `List<Spectrum>`. One
   reused `FileStream`; make it `IDisposable`; load each window's list inside its own
   parallel-body (one reader per task, or a lock) so only ~`NThreads` windows are resident.
2. **`RunCoelutionScoring` (`ScoringPipeline.cs:65`)**: replace the `List<Spectrum>
   spectra` param with the window source; delete the up-front `spectraByWindowKey` build
   (`:131-143`). NOTE: the 2026-07-15 work already eliminated the calibrated-copy
   double-hold via `consumeInputMzs`; for streaming, fold the per-m/z calibration
   (`MzCalibration.ApplyCalibration`, currently `:113`) into `LoadWindow` so only one
   window's calibrated copy is ever live.
3. **`ScoreWindow` (`CoelutionScorer.cs:70`)**: take a `List<Spectrum> windowSpectra`
   directly instead of the dictionary + `TryGetValue`; everything from the sort onward
   is verbatim. Empty/absent window -> empty list (same as today's miss).
4. **`DeduplicateDoubleCounting` (`ScoringPipeline.cs:336`)**: it reads only
   `s.RetentionTime` (`:371-395`) -- change the `IList<Spectrum>` param to
   `IReadOnlyList<double> ms2Rts` (the index's `allMs2Rts`). This severs the last
   resident-spectra dependency so `ProcessFile` can drop the resident MS2 before scoring.
5. **`PerFileScoringTask.ProcessFile`**: `LoadSpectra` still loads resident MS2 for
   calibration (Stage 3 reads peaks); after `ResolveCalibration`, **drop the resident MS2
   list** and build the `SpectraWindowIndex` from the on-disk cache (guaranteed present
   after `LoadSpectra`), then stream scoring. (Optionally later: stream calibration too;
   out of scope here.)

## CRITICAL: do NOT bake in a window-boundary model (per Mike MacCoss)

Byte-identity **requires** the index to key EXACTLY like today's in-memory grouping:
`(int)Math.Round(iso_center * 10.0)`, taken from each spectrum's **self-declared**
`iso_center` in the `.spectra.bin` header. Do NOT invent an isolation-scheme model, a
fixed DIA grid, or infer boundaries -- the existing grouping is already data-driven,
which is why it is robust to variable schemes. Consequences to preserve:

- **Standard DIA / GPF / PRM**: handled for free -- each spectrum self-declares its
  window, and the index buckets by the declared center exactly as today. (Reconciliation
  works with GPF; PRM's only failure mode is the RT-calibration step, unrelated to this.)
- **A candidate scored in >1 overlapping window**: whatever `Round(center*10)` produces
  today, reproduce identically. Do not "fix" it.
- **diaPASEF**: today's grouping keys by m/z center ONLY (no ion-mobility term). That is
  a pre-existing modeling question, ORTHOGONAL to streaming -- the index must mirror the
  current m/z-only keying and NOT add a mobility dimension here.

## Byte-identity gates (every change)

- `pwsh -File ./pwiz_tools/Osprey/regression.ps1 -Dataset Stellar` (mode1 golden +
  mode2 resume + mode3 HPC chain). **AND `-Dataset Astral`** -- Astral (HRAM) is the
  load-bearing gate: it always calibrates and exercises the full window-scoring path;
  its mode1 golden compare is what proves the streamed reads reproduce the resident path.
- Pre-commit: `Build-Osprey.ps1 -Configuration Debug -RunTests -RunInspection`
  (SystemMemory.cs 9 warnings are known #4379 local noise).
- Memory A/B: single-Astral-file `[MEM]` before/after (expect the scoring/calibration
  resident MS2 to drop from ~6.3 GB to ~tens of MB); a `.dmw` for the retention view.
- Perf: `Test-PerfGate.ps1` (the seek-per-window reads add I/O; confirm no regression --
  the 2026-07-15 memory work was actually a speedup via GC-pressure reduction, so watch
  the net).

## Feasibility + fallbacks (from the 2026-07-15 design pass)

- **Verdict**: byte-identical, HIGH confidence (~85%). No FP recomputation (calibration
  is the same multiply already run; ordering is doubly-guaranteed by the
  `(RetentionTime, ScanNumber)` re-sort; dedup needs only bitwise-identical RTs). The
  residual risk is operational: the resident MS2 must actually be dropped between
  calibration and scoring (verify with the `perfile-scoring-peak` retention snapshot).
- **Fallback (lower risk, most of the win)**: stream **peaks only** -- keep the ~204k
  `Spectrum` stubs resident (~10 MB: scalars + isolation window; carry `ScanNumber`/
  `RetentionTime` for the sort) and lazily load/release each window's `Mzs`/`Intensities`
  arrays. Preserves the window partition + ordering exactly; only the heavy peak blobs
  (the real 6.3 GB) stream. Consider if the full window-order reconstruction is deemed risky.

## Explicitly NOT in scope

- Changing the `.scores.parquet` contract / scored-entry streaming (separate parity
  decision; see `TODO-osprey_perfile_scored_entry_streaming.md`).
- Streaming MS1 (global `FindNearest`; small; keep resident).
- Any isolation-window / diaPASEF-mobility modeling (see the CRITICAL section).
- Changing the `.spectra.bin` on-disk format (cross-impl-shared with Rust via the source
  fingerprint; a format change is a cross-impl decision, out of scope).

## References

- 2026-07-15 sprint: branch `Skyline/work/20260715_osprey_memory_reduction`; its TODO
  `ai/todos/active/TODO-20260715_osprey_memory_reduction.md`; the design notes
  `ai/.tmp/agent-task2-plan.md` (if still present -- the design above is the self-contained
  distillation).
- `ScoringPipeline.cs:65` (RunCoelutionScoring), `:131-143` (window grouping), `:336`,
  `:371-395` (DeduplicateDoubleCounting RTs-only); `CoelutionScorer.cs:70` (ScoreWindow);
  `PerFileScoringTask.cs:2250-2310` (LoadSpectra), `:2271`/`:2295` (cache/mzML load);
  `SpectraCache.cs` (format + decode helpers); `PeakDataExtractor.cs` (MS1 FindNearest).
- Rust analogs: `pipeline.rs:3161` (load_spectra_cache), `:7810`
  (group_spectra_by_isolation_window), `:7920` (`Vec<Vec<f32>>` per-window cache);
  `osprey-scoring/src/batch.rs` (group_spectra_by_isolation_window, MIN_COELUTION_SPECTRA).
- Memory: `[[feedback_bit_parity_tolerance]]`, `[[reference_osprey_perfile_mem_measurement]]`,
  `[[project_osprey_parity_removal_sprint]]`.
