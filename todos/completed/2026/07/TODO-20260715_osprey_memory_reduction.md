# TODO: Osprey per-file memory reduction (single Astral file 49)

**Status**: Completed
**Branch**: `Skyline/work/20260715_osprey_memory_reduction` (off master @ 110c9f7833)
**PR**: [#4424](https://github.com/ProteoWizard/pwiz/pull/4424) (merged 2026-07-15 as fc148e4)
**Created**: 2026-07-15
**Goal**: Lower the per-file memory ceiling for the single Astral file-49 case
with verified, byte-identical, regression-green code. Bank safe wins; take the
next big step on the ceiling. Merge nothing that is not regression-green AND
byte-identical (the standing refactor gate: `regression.ps1 -Dataset Stellar`).

See the analysis in
`ai/todos/backlog/brendanx67/TODO-osprey_perfile_scored_entry_streaming.md`
(peak decomposition, ranked levers) and the handoff
`ai/.tmp/handoff-osprey-memory-nightsession.md`.

## Measured baseline (file 49, uncapped, cal-recompute, spectra+lib cache hit)

Single Astral file, `--task PerFileScoring`, `OSPREY_LOG_MEMORY=1`
(run script `ai/.tmp/run-astral-mem.ps1`, ~111 s/run):

| boundary | working_set (peak) | managed_heap |
|---|---|---|
| library-resident | -- | 2.92 GB (3.13M entries) |
| post-calibration (CAL peak) | 20.24 GB | 13.36 GB |
| single file scored (SCORING peak) | 30.91 GB | 16.08 GB |
| perfile-scored-live (floor) | -- | 3.52 GB |

Scoring is the apex here (16.08 GB managed), calibration second (13.36 GB). Both
hold library (~2.9 GB) + MS2 spectra (~6.3 GB). CAL managed also carries the
~3.3 GB uncollected dense XCorr cache.

## Task 0 -- post-calibration MEM boundary (DONE, byte-identical)

`PerFileScoringTask.ProcessFile` emits `[MEM post-calibration]` +
SnapshotReady-gated `CaptureRetentionSnapshot("post-calibration")` right after
`ResolveCalibration` returns, so the calibration peak is measurable (previously
only the scoring peak was). Log-only + profiler-gated -> no-op on batch/regression.

## Task 1 -- library-load cleanups (DONE, byte-identical, regression-green)

- **1a decoy string interning**: `LibraryStringInterner.InternInPlace(decoys)`
  right after `DecoyGenerator.GenerateAllWithCollisionDetection`
  (`PerFileScoringTask.cs`). Decoys mint fresh `"DECOY_"+accession` ProteinIds
  never re-interned; interning collapses the per-protein duplicates (measured
  55.8% collapsed, ~2.9M dup strings).
- **1b shared empty-list sentinels**: `LibraryEntry.EmptyModifications` /
  `EmptyStringList` (`static readonly`) assigned by `LibraryCache.ReadEntries`
  at its `count==0` branches (mods / proteinIds / geneNames), where the `.Add`
  loops run zero times so the sentinel is never mutated. **The constructor keeps
  fresh lists** -- an earlier cut that shared them in the constructor broke 7
  unit tests that do `entry.Modifications.Add` on a fresh-built entry (aliasing
  the shared sentinel); the loaders are the only place the retained empties come
  from anyway.
- **Result**: library-resident 2.92 -> 2.67 GB (-250 MB, -8.6%); CAL peak
  13.36 -> 13.15 GB. Regression Stellar mode1/2/3 byte-identical
  (blib 45,064,192). 506/509 tests pass.

## Task 2 -- MS2 spectra during scoring

**Bankable slice DONE (byte-identical, regression-green, committed a961152edd).**
On a calibrated file `RunCoelutionScoring` copied every spectrum's m/z into a
calibrated list while the caller still held the originals for
`DeduplicateDoubleCounting` -- two ~4 GB MS2 m/z sets coexisted. Added a
`consumeInputMzs` flag (Stage-4 call site only) that nulls each input spectrum's
m/z as its calibrated copy is built (dedup reads only RetentionTime; Stage-6
rescore shares one spectra list across 3 calls and keeps the default false).
- **Result**: SCORING peak managed 16.08 -> 9.41 GB (**-6.6 GB, -41%**). The apex
  moves from the scoring peak to the calibration peak (13.18 GB): overall managed
  apex 16.08 -> 13.18 GB (**-18%**). 1,683,778 entries scored (unchanged).
  Regression Stellar mode1/2/3 byte-identical (blib 45,064,192).

**Full per-window disk streaming (NEXT, ~6.3 GB more, scoring MS2 -> ~NThreads
windows)** remains the documented follow-up (agent plan `ai/.tmp/agent-task2-plan.md`).
Larger surface (new SpectraWindowIndex/loader, `RunCoelutionScoring`/`ScoreWindow`
signature changes, parallel reader). Not attempted this session.

## Task 2 background (design)

Design in `ai/.tmp/agent-task2-plan.md`. On a calibrated (Astral) file,
`ScoringPipeline.RunCoelutionScoring` builds a full `calibratedSpectra` copy
(~4.2 GB new Mzs) WHILE the caller still holds the original 6.3 GB for
`DeduplicateDoubleCounting` -> ~10.5 GB double-hold during scoring.
- **Bankable slice**: calibrate into the per-window groups + hand
  `DeduplicateDoubleCounting` the pre-extracted MS2 RTs (a `double[]`), then drop
  the original resident list before scoring -> frees ~4.2 GB. Byte-identical
  (same calibration multiply; `ScoreWindow` re-sorts each window by
  `(RetentionTime, ScanNumber)`; identical RT multiset for dedup).
- **Full per-window disk streaming** (another ~6.3 GB, scoring MS2 -> ~NThreads
  windows): `.spectra.bin` is window-seekable (48-byte MS2 prefix + n_peaks*12).
  Larger surface (new index/loader, 3 signature changes, parallel reader). Roadmap
  in the agent plan; attempt only if runway allows, else leave prototyped.

## Task 3 -- calibration XCorr cache float[][] (bankable slice; design agent-task3-plan.md)

The calibration peak (13.18 GB, now the apex) holds a ~3.3 GB dense XCorr cache.
`Calibrator.PreprocessWindowsForXcorr` got the canonical `float[]` Comet cache from
`PreprocessSpectrumForXcorrF32` then **widened every float to `double`** and stored
`double[][]` (8 bytes carrying 4 bytes of info). **Implemented**: store `float[][]`
directly (drop the widening loop) and let the consumer (Calibrator.cs:2155) bind to
the EXISTING `XcorrFromPreprocessed(float[], entry)` overload -> cache 3.3 -> ~1.65 GB.
- **Byte-identical**: both overloads widen the SAME float to double before the same
  same-order `+=` (float->double is exact + unique); the 3-arg double/float bodies are
  identical arithmetic. Same equivalence #4398 / `XcorrFromSparse` already ship on.
- Edits (Calibrator.cs only): `PreprocessWindowsForXcorr` return type + body + doc;
  3 params (`ScoreCalibrationMatches`/`RunRefinementPass`/`ScoreCalibrationEntry`) +
  the `windowPreprocessed` local -> `float[][]`. Pre-commit GREEN (0 warnings, 506/509).
- Result: PENDING regression + Astral A/B (expect CAL peak 13.18 -> ~11.5 GB).

**Full per-window build+release of the calibration cache (DEFERRED, prototype-only):**
both passes iterate ALL sampled entries in a flat `Parallel.ForEach` with the window
resolved inside the loop (+ neighbor/linear-scan fallbacks), so there is no window
partition to hang a build/release on; and pass 2 needs pass 1's completed LOESS fit.
A per-window lifecycle needs entry-partition-by-window + a two-sweep pass split --
large, byte-identity-risky, second-order. See agent-task3-plan.md Section 4.

## Task 5 -- read-only arrays for library-entry collections (DONE, byte-identical)

Retyped `LibraryEntry.Modifications/ProteinIds/GeneNames/Fragments` from `List<T>`
to `IReadOnlyList<T>` backed by arrays (`Array.Empty<T>()` when empty). Interning
moved INTO construction: `LibraryStringInterner` is now an instance pool (relocated
to `Osprey.Core`) that the loaders + `DecoyGenerator` route strings through as they
fill the interned arrays -- replacing the post-load member-mutation pass (same
72.7% / 55.8% collapse). Drops the per-entry List wrapper + growth slack.
- **Result**: library-resident **2.67 -> 2.07 GB (-600 MB)**; cumulative from the
  2.92 GB baseline = -850 MB / -29%. Byte-identical: Stellar AND Astral mode1/2/3
  (blib 45,064,192 / 135,249,920); 506/509 tests; 0 warnings. Commit 870d7d2a8.

## Verification status (2026-07-15)

- **Byte-identical on BOTH datasets**: `regression.ps1 -Dataset Stellar` PASS (run per
  task) AND `-Dataset Astral` PASS (mode1 vs golden / mode3 HPC / mode2 resume, blib
  135,249,920). The Astral golden compare is the load-bearing one -- Task 2's
  `s.Mzs = null` only runs on CALIBRATED MS2, which HRAM always is.
- Pre-commit GREEN each task (0 inspection warnings, 506/509 tests).
- Independent fresh-context self-review of the diff: 0 blocking findings
  (`ai/.tmp/agent-selfreview.md`).
- Perf standing gate (`Test-PerfGate.ps1 -Dataset Stellar`): **PASSED, and the
  changes are FASTER** -- total 4:00 -> 3:15 (median -19%), stage1to4 1:58 -> 1:21
  (-31.3%), no regression (reduced gen-2 GC pressure). Some rep variance; median +
  2/3 reps show it. Verdict: `ai/.tmp/perf-gate/20260715-084056Z/verdict.md`.
- NOT pushed; NO PR opened (per the night handoff -- Brendan reviews first).

## Task 7 -- intern manifest / dedup protein accessions (self-review follow-up, byte-identical)

A fresh-context self-review + a Stellar-libdecoy A/B found the library-decoy
**manifest path un-interned protein accessions**:
`DecoyPairingManifest.ApplyToLibrary` replaced ProteinIds on ~98% of entries
(968,437/988,740) with fresh un-interned `List`s, discarding the loader's
interning for almost the whole resident library on libdecoy runs (the path
Pilot-MTG uses; the gendecoy regression golden never exercises it). Fixed by
interning the manifest's clean accessions into a read-only array via a shared
`LibraryStringInterner` (Stellar libdecoy: 42,590 distinct / 1,022,095 total,
**95.8% collapsed**). `LibraryDeduplicator` merged-group unions got the same
treatment; the loader's `InternToArray` moved onto `LibraryStringInterner`.
- **Byte-identical**: Stellar regression mode1/2/3 PASS (blib 45,064,192);
  post-fix Stellar-libdecoy A/B vs master byte-identical (6/6 fdr_scores.bin raw;
  all calibration/reconciliation/parquet identical modulo run-path / search_hash /
  timestamp only). Interning is identity-only. 509 tests, 0 inspection warnings.

## Gates (every change)

- `pwsh -File ./pwiz_tools/Osprey/regression.ps1 -Dataset Stellar` (byte-identical).
- `pwsh -File ./ai/scripts/Osprey/Build-Osprey.ps1 -Configuration Debug -RunTests -RunInspection`
  (SystemMemory.cs 9 warnings are known local #4379 noise).
- `-MemoryProfile` / `OSPREY_LOG_MEMORY` A/B before+after each change.

## 2026-07-15 - Merged

PR #4424 merged as commit fc148e4. Shipped: freed the Stage-4 MS2 m/z double-hold
(scoring peak 16.08 -> 9.41 GB), calibration XCorr cache float[][] (~3.3 -> ~1.65 GB),
resident library ~850 MB (decoy interning, empty-list sentinels, array-backed
IReadOnlyList collections), and a profiler-gated post-calibration [MEM] boundary --
all byte-identical (Stellar+Astral regression mode1/2/3). A self-review + Stellar-libdecoy
A/B caught the library-decoy manifest path un-interning protein accessions on ~98% of
entries; fixed in follow-up (Task 7, 95.8% collapse, byte-identical). Full per-window MS2
disk streaming was deferred to
`ai/todos/backlog/brendanx67/TODO-osprey_perfile_spectra_window_streaming.md` (next session).
The manual TeamCity Perf/Regression was re-run green on the pre-fix head; the final
identity-only interning commit was merged on local gates (regression Stellar + libdecoy
A/B) by Brendan's explicit judgment call, not a fresh Perf/Regression.
