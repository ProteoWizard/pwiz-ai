# TODO: Osprey per-file MS2 spectra streaming by isolation window

**Status**: In Progress
**Branch**: `Skyline/work/20260715_osprey_perfile_spectra_window_streaming`
**Base**: `master` (follow-on to #4424, merged)
**Priority**: High (the single largest remaining per-file memory lever; ~6.3 GB of
resident MS2 spectra held in BOTH the calibration and scoring peaks)
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
- **Phase 3 (code complete, gate running)** -- `StreamingWindowSpectraProvider` (Osprey.Tasks,
  wraps the IO index, calibrates each window in place). In `ProcessFile` after
  `ResolveCalibration`: `BuildFromCache` the index, `spectra = null` (drops ~6 GB resident
  MS2), stream scoring; resident fallback if the cache can't be indexed. All 510 unit tests
  pass. **Gate: `regression.ps1 -Dataset All` (Stellar + Astral) RUNNING.**

Verified byte-identity linchpins: `Calibrator` never mutates the resident spectra objects
or order (it sorts only its own transient dict lists); after `LoadSpectra` the on-disk
cache matches the resident spectra bit-for-bit; `ScoreWindow`'s `(RT, ScanNumber)` re-sort
is a unique total order so file-order streamed load scores identically. Remaining: Phase 3
Astral gate, memory A/B (`Get-MemoryReport.ps1` on `OSPREY_LOG_MEMORY=1` single-Astral
before/after), `Test-PerfGate.ps1` (watch scattered-read I/O), PR.

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
