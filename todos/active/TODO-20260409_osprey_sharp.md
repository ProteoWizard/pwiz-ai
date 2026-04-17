# TODO-20260409_osprey_sharp.md  -  Phase 3

## Branch Information
- **Branch**: `Skyline/work/20260409_osprey_sharp`
- **Base**: `master`
- **Created**: 2026-04-09
- **Phase 3 started**: 2026-04-14 (end of Session 11)
- **Status**: In Progress
- **GitHub Issue**: (pending)
- **PR**: (pending)

## Phase History

See [TODO-20260409_osprey_sharp-phase1.md](TODO-20260409_osprey_sharp-phase1.md)
for Sessions 1-7 (2026-04-09 through 2026-04-11): initial Osprey build and
bugfixes, full OspreySharp scaffolding (Phase 1-5), end-to-end pipeline, and
cross-implementation bisection walk that proved bit-identical pass-1
calibration features on Stellar.

See [TODO-20260409_osprey_sharp-phase2.md](TODO-20260409_osprey_sharp-phase2.md)
for Sessions 8-11 (2026-04-11 through 2026-04-14): iterative LDA refinement,
LOESS robust-mode alignment, MS2 m/z calibration, main-search 21 PIN features
on Stellar (all bit-identical), Session 10 perf optimizations, and Session 11
HRAM/Astral debugging that produced four cross-impl bug fixes (Rust XCorr
fragment-bin dedup, Rust DIA window-bounds truncation, C# per-fragment Da
tolerance, C# `PercentileValue` rounding) and brought C# Stage 1-3 on Astral
to 1.06x Rust wall-clock parity.

The phase-2 file also contains the full set of diagnostic env vars, fast
iteration commands, build commands, test data locations, and the per-stage
parity tables  -  do not duplicate them here.

## Objective

**Phase 3 goal**: bring C# OspreySharp to bit-identical 21 PIN feature
parity with Rust Osprey on Astral data, without breaking the Stellar 21
PIN feature parity that's already passing. The pre-main-search Astral
walk (cal sample → cal_match → LDA → LOESS input → pass-2 LOESS) is
already bit-identical at ULP. The remaining work is the main-search
walk and any perf fixes needed to make the main search complete in a
reasonable time on Astral.

## Session 13 (2026-04-15): Astral main-search faster than Rust

End-to-end Astral wall-clock now **0.64x Rust** (568.6s vs 884.6s). All
21 PIN features still bit-identical at ULP on both Stellar and Astral.

### Profiling infrastructure

- Added `pwiz.OspreySharp.ProfilerHooks` wrapping JetBrains.Profiler.
  Api MeasureProfiler with try/catch in non-inlineable helpers (matches
  Skyline `TestRunnerLib.MemoryProfiler`). `RunCoelutionScoring` now
  brackets the parallel loop with `StartMeasure` / `SaveAndStopMeasure`
  + per-stage memory logging. No-op when no profiler is attached.
- Added `OSPREY_MAX_SCORING_WINDOWS` env var capping the windows
  scored in Stage 4 — Astral profile cycle ~15 min -> ~2 min.
- `Profile-OspreySharp.ps1` gained `-ScopeToMainSearch` (passes
  `--use-api --collect-data-from-start=off` to dotTrace) and
  `-MaxWindows N` to drive the new gate.

### HRAM pre-preprocess per-window cache

- The first 4-window Astral profile (post Session 12 pool fix) showed
  `ApplySlidingWindow` + `ApplyWindowingNormalization` taking 79% of
  Stage 4: every candidate × every scan was re-running the full
  preprocessing. Rust `pipeline.rs:5954-5957` pre-preprocesses all
  window spectra ONCE and then scores each candidate via the
  O(n_fragments) `xcorr_from_preprocessed` fast path.
- Implemented the matching `HramStrategy.PreprocessWindowSpectra`
  using a new `XcorrScratchPool.RentBins` / `ReturnBins` /
  `ReturnBinsArray` API for bare `double[NBins]` arrays. Per window
  we rent one scratch (intermediates) + N output buffers; on window
  exit `ScoreWindow.finally` returns all rented bins. Each candidate
  now scores via `XcorrFromPreprocessed` (O(n_fragments) bin lookup
  with dedup), matching the Rust HRAM fast path.
- `HramStrategy.ScoreXcorr` checks `preprocessed[spectrumIndex]` and
  routes to the fast path if available; falls back to inline scratch
  scoring when no per-window cache (e.g. calibration).

### f32 HRAM cache + visitedBins pooling

- Narrowed the per-window preprocessed cache from `double[NBins]` to
  `float[NBins]` for HRAM only. Calibration and unit-res stay f64 to
  preserve bit-identical parity through calibration (the earlier
  full-f32 attempt cascaded through calibration LDA → different RT
  calibration → different apex picks → 18 divergent entries). HRAM
  main-search cache uses f32 with `WindowXcorrCache` wrapper holding
  typed arrays per strategy.
- Pooled `bool[NBins]` visitedBins in `XcorrFromPreprocessed` via the
  `WindowXcorrCache`. Was 66M × 100 KB = 6.6 TB gen-0 churn per
  Astral run; now reused per window with O(n_frags) selective clear
  instead of O(NBins) Array.Clear. This was the remaining allocation
  hotspot (zero gen-2 collections during main search after the fix).
- Added pool diagnostic logging: `[POOL] scratch_allocs=N, bins_allocs=N`
  at end of main search.

### Astral single-file Stage 1-4 progression

| Stage | C# wall | Ratio vs Rust (~900s) |
|--------|---------|------------------------|
| Session 11 baseline (xcorr bugs fixed) | 4341.9s | 4.93x |
| Session 12 + XcorrScratchPool | 964.0s | 1.09x |
| Session 13 + HRAM pre-preprocess per window | 568.6s | 0.64x |
| + f32 HRAM cache only | 361.9s | 0.42x |
| **+ visitedBins pooling** | **120.9s** | **0.13x** |

Stellar single-file Stage 1-4 still at parity (~1x; noisy at small
wall-clock).

### Next: 3-file parallel and memory budget

- Per-window preprocessed cache (HRAM): 1 `double[NBins]` per spectrum
  (~800 KB). Astral has ~1222 spectra/window; with 32 active windows
  in parallel that's ~31 GB of pool arrays. Single-file Astral peak
  working set saw ~25 GB after HRAM change — within 64 GB budget.
- For 3-file parallel runs (matching the Stellar 0.55x evidence in
  the workflow HTML), we likely need:
  1. **`float[]` preprocessed cache** instead of `double[]` (halves
     pool memory; matches upstream maccoss/osprey which is f32 in
     `osprey-scoring/src/lib.rs:2258-2378`. Our fork flipped to f64
     in commit `c95b36c` purely for cross-impl bit-identical
     comparison. With both sides on f32 we get the memory win and
     the change is upstream-friendly).
  2. **`OSPREY_SCORING_MAX_PARALLEL`** env var to cap
     MaxDegreeOfParallelism for the main-search Parallel.ForEach,
     so 3-file parallel can run 8 threads/file instead of 32.
  3. **Library/decoy load-once** across files (the current pipeline
     loads the library + generates decoys per file; would save
     ~3 GB for 3 parallel files).
- Bench `Bench-Scoring.ps1 -Dataset Astral -Files All` after each of
  the above lands.

## Session 12 (2026-04-15): Astral main-search bit-identical + LOH pool

End-to-end Astral parity achieved at 1.09x Rust wall-clock. All 21 PIN
features pass at ULP on both Stellar (0.98x Rust) and Astral
(1.09x Rust).

### Cross-impl fixes (this session)

- **C# `AnalysisPipeline.RunCalibration`**: added MS1 mass calibration
  alongside MS2. Extracts M+0 observed m/z from apex MS1 of each cal-
  sample peptide; feeds `MzCalibration.CalculateSingleLevel`. Without
  this, each-tool-own-cal mode on Astral diverged on ms1_precursor_
  coelution (21.87%, max diff 2.0) and ms1_isotope_cosine (13.68%,
  max diff 1.0) because C#'s main-search MS1 features used raw
  precursor m/z at 10 ppm tolerance instead of the reverse-calibrated
  m/z at `max(3*SD, 1.0)` ppm tolerance.
- **C# `ComputeApexMatchFeatures`**: returns calibrated fragment
  tolerance as abs_mass_error when no fragments match, matching Rust
  `compute_mass_accuracy` `(0.0, tolerance, tolerance)` sentinel.
  Closed 8 outliers (max diff 5.97).
- **Rust `longest_consecutive_ions`**: previously reverse-looked-up the
  library by m/z and broke on first hit, silently dropping one
  fragment's ordinal on m/z collisions. `FragmentMatch` now carries
  the ordinal directly; function uses it. Closed 290 Astral divergences.
- **Rust `lib_cosine` norm gate**: previously returned
  `SpectralScore::default()` when `lib_norm` or `obs_norm` < 1e-10,
  zeroing the counting features (consecutive_ions, explained_intensity)
  alongside the undefined cosine. Counting features are independent
  of the cosine norms — decoupled so cosine/Pearson/Spearman zero out
  on the gate while presence counters still populate. Closed 59
  short-/low-signal Astral rows.

### Perf fix (the big one)

- **C# `XcorrScratchPool`**: new `OspreySharp.Scoring.XcorrScratchPool`
  with a `ConcurrentBag<XcorrScratch>` that holds per-spectrum 4-buffer
  scratch sets (binned, windowed, prefix, preprocessed — all `double[
  NBins]`, plus `bool[NBins]` visitedBins). `SpectralScorer.XcorrAtScan`
  has a pool-aware overload that writes into rented buffers. On HRAM
  (`NBins ~100K`, 800 KB per array), per-call allocation was hitting
  LOH on every scan × every candidate × every window, driving gen-2 GC
  that accounted for the vast majority of main-search time. Pool grows
  organically to NThreads sets, then reuses for the full run — gen-2
  holds the arrays; no more LOH churn.

**Astral end-to-end Stage 1-4** (single Astral file 49, HRAM, all 21
PIN features ULP-identical):

| Config | C# wall-clock | Ratio vs Rust (886.9s) |
|--------|---------------|------------------------|
| Pre-pool (session 11, xcorr bugs fixed) | 4341.9s | 4.93x |
| Post-pool (session 12) | **964.0s** | **1.09x** |

Stellar end-to-end dropped 1.28x → 0.98x over the same change.

### Remaining perf headroom (~9% / 77s gap)

1. **mzML parsing**: C# ~38.7s vs Rust 22-24s from Phase 2 (HDD-bound
   for C#; Rust uses mzdata's OS-cache-friendly access). Accounts for
   roughly 16s of the 77s deficit. `MemoryMappedFile + MemoryMapped-
   ViewStream` in `MzmlReader.cs` deferred as its own task.
2. **Other hot paths not yet pooled**: XIC extraction, MS1 isotope
   envelope, Tukey median polish. Unit-res pool win (1.28x → 0.98x)
   hints there's still small-allocation churn outside XCorr.
3. **Inner-loop vectorization**: Rust's windowing/sliding-window may
   auto-vectorize better than the C# explicit for-loops.

## Next sprint: profile + measure peak memory

Now that Astral single-file is 0.13x Rust (120.9s vs 911.6s), next
sprint targets 3-file parallel within the 64 GB memory budget:

- **Short-circuit env var** `OSPREY_MAX_SCORING_WINDOWS=N` in
  `AnalysisPipeline.RunCoelutionScoring` (around line ~2443, before
  `Parallel.ForEach(isolationWindows, ...)`) — caps Astral's ~130
  windows to 1-2 for rapid iteration.
- **dotTrace API hooks** mirroring `Skyline/Util/DotTraceProfile.cs`:
  dynamic load of `JetBrains\dotTrace\v5.3\Bin\JetBrains.Profiler.Core
  .Api.dll` (so the project doesn't hard-link), `Start()/Stop()/
  EndSave()` around the main-search loop. `Profile-OspreySharp.ps1`
  already supports `-Stage Scoring` but uses command-line dotTrace;
  switching to API mode isolates Stage 4 profile.
- **Peak memory**: add `Process.PeakWorkingSet64` and `GC.GetGC-
  MemoryInfo().HeapSizeBytes` logging at end of run. The 4341.9s run
  peaked at ~17 GB working set / ~26 GB private; post-pool expected
  to be similar since pool holds the same NThreads * NBins * 8 bytes
  in gen-2 rather than churning LOH.

## Current State (entering Phase 3)

**Astral pre-main-search parity** (single Astral file 49, HRAM):

| Stage | Divergence (own calibration) |
|-------|------------------------------|
| Cal sample (library targets) | 0 |
| Cal match: matched counts | 110055 = 110055 |
| Cal match: 6 of 7 columns | max 5e-10 (ULP) |
| Cal match: xcorr | 1/110055 entry diff 1e-3 (coarser unit-bin border case) |
| LDA scores + q_values | 1/110055 discriminant 1e-4, 4/110055 q_value 1e-5 |
| LOESS input (2966 pairs) | max 3.6e-15 (machine epsilon) |
| Pass-2 LOESS model (10 stats) | 0 |
| **Main-search XICs (post-recal)** | **NOT YET WALKED** |
| **Main-search CWT peak boundaries** | **NOT YET WALKED** |
| **21 PIN features** | **NOT YET WALKED** |

**Stellar 21 PIN features**: all PASS at 1e-6 threshold (Test-Features.ps1
-Dataset Stellar with own calibration). Don't break this.

**Astral Stage 1-3 perf**: C# 64.6s vs Rust 60.7s = 1.06x. Cal pass 1
scoring: C# 6.9s vs Rust 12s (C# faster). mzML parsing: C# 38.7s vs Rust
22-24s = 1.7x slower (HDD bound for C#, OS-cache served for Rust).

**Stage 4 (main search) perf**: NOT YET MEASURED at parity. Earlier
Astral attempts on full pipeline showed C# at ~14% CPU sustained while
Rust spikes to 100% then 50% before completing. Suspected HRAM 100K-bin
LOH GC pressure on the per-candidate apex XCorr. The cal-phase fix
(unit-bin scorer) does NOT apply to main search because main-search
XCorr needs HRAM precision for fragment matching. A different fix
(per-window pre-preprocessing scoped to HRAM, controlled parallelism,
or RT-sliding cache) will be needed if main search is too slow.

## Remaining Tasks

### Priority 1: Main-search Astral walk (correctness)  -  DONE

- [x] Main-search parity: all 21 PIN features bit-identical between
      Rust and C# on Astral with each tool's own calibration (session
      12). Session 11-12 fixes: MS1 mass calibration in C#;
      per-fragment mass-error sentinel; Rust `longest_consecutive_
      ions` ordinal attribution; Rust `lib_cosine` norm-gate
      decoupling; C# `XcorrScratchPool`.

### Priority 2: HRAM main-search perf  -  DONE (1.09x Rust)

- [x] Short-term fix: `XcorrScratchPool` with `ConcurrentBag` holds
      per-spectrum 4-buffer scratch sets across the whole scoring run.
      Organic high-water (NThreads sets). Brought Astral 4.93x Rust →
      1.09x Rust (964s vs 887s).
- [ ] Next sprint (see "Remaining perf headroom" above): profile with
      dotTrace + short-circuit env var, measure peak memory, attack
      the residual 9%. Possible follow-ups: pre-preprocess window
      spectra once per window on HRAM too (Unit-res already does this;
      HRAM was blocked by allocation cost — now viable with pool).

### Priority 3: Upstream the three Rust bug fixes

PR each as its own focused fix to `maccoss/osprey`:

- [ ] **XCorr fragment bin dedup** (`scorer.xcorr()` and
      `xcorr_at_scan()` in osprey-scoring/src/lib.rs): commit
      `4db625c`. Current Rust counts shared bins twice; matches Comet
      theoretical-spectrum convention to dedup. Jimmy Eng (XCorr
      author at UW) should weigh in on the algorithmic intent.
- [ ] **DIA window bounds truncation** in
      `group_spectra_by_isolation_window` (osprey-scoring/src/batch.rs):
      commit `a07aae6`. Current Rust uses truncated 0.1 m/z keys as
      the actual filter bounds; affects ~0.002% of entries near
      boundaries on Astral. Hit any DIA dataset whose isolation
      windows aren't aligned to the 0.1 m/z grid.
- [ ] **Unit-bin calibration XCorr scorer** in pipeline.rs (commit
      `2d4a8ad`): matches the intent of Mike's existing
      `run_xcorr_calibration_scoring` comment; 50x cheaper allocations
      with no correctness loss.

### Priority 4: mzML perf (optional, after main-search parity)

- [ ] Try `MemoryMappedFile` + `MemoryMappedViewStream` in
      `MzmlReader.cs` to get OS-cache-friendly access like Rust's
      `mzdata`. Could close the 1.7x mzML parsing gap. Bigger lift
      than buffer tuning since the existing `XmlReader.Create(stream)`
      code path needs to wrap a view stream. Defer until main search
      is bit-identical.

### Priority 5: Stellar regression coverage (carry-over from Phase 2)

Continue the bug-class regression test suite from Session 10. Phase 2
finished 18 tests; new Session 11 bug classes deserve coverage:

- [ ] XCorr fragment bin dedup (already exists from Session 10:
      `TestXcorrFragmentBinDedup` - extend to assert via the public
      `SpectralScorer.xcorr` path matches `xcorr_from_preprocessed`)
- [ ] Per-fragment Da tolerance in `HasTopNFragmentMatch` (regression
      test that asserts a varied-m/z fragment list gets per-fragment
      Da windows, not a single precursor-derived one)
- [ ] PercentileValue rounds half-away-from-zero (matches Rust)
- [ ] Isolation window bounds preservation (Rust-side test)

## Quick Reference  -  must-know commands and locations

**Run the parity tests**:
```bash
# Stellar (always passes; do not break)
pwsh -File './ai/scripts/OspreySharp/Test-Features.ps1' -Dataset Stellar

# Astral (incomplete - main search not yet validated)
pwsh -File './ai/scripts/OspreySharp/Test-Features.ps1' -Dataset Astral
```

**Stage-gated benchmarks**:
```bash
pwsh -File './ai/scripts/OspreySharp/Bench-Scoring.ps1'   -Dataset Astral -Stage Calibration -SkipUpstream -Iterations 2
pwsh -File './ai/scripts/OspreySharp/Profile-OspreySharp.ps1' -Dataset Astral -Stage Calibration -TopN 25
```

**Diagnostic env vars** (early-exit gates for fast iteration):
- `OSPREY_DUMP_CAL_SAMPLE=1` + `OSPREY_CAL_SAMPLE_ONLY=1`
- `OSPREY_DUMP_CAL_MATCH=1` + `OSPREY_CAL_MATCH_ONLY=1`
- `OSPREY_DUMP_LDA_SCORES=1` + `OSPREY_LDA_SCORES_ONLY=1`
- `OSPREY_DUMP_LOESS_INPUT=1` + `OSPREY_LOESS_INPUT_ONLY=1`
- `OSPREY_DIAG_XIC_ENTRY_ID=<id>` + `OSPREY_DIAG_XIC_PASS={1,2}`
- `OSPREY_DIAG_SEARCH_ENTRY_IDS=<id,id,id>` (NO early exit; runs full
  main search collecting these IDs)
- `OSPREY_EXIT_AFTER_CALIBRATION=1` (Stage 1-3 only)
- `OSPREY_EXIT_AFTER_SCORING=1` (Stage 1-4 only)

**Test data**: `D:\test\osprey-runs\stellar\` and
`D:\test\osprey-runs\astral\`. Both tools share the same input mzML
and library files; each writes its own `.calibration.json`,
`.spectra.bin`, `.scores.parquet` caches. `Clean-TestData.ps1` in
`ai/scripts/OspreySharp/` clears caches.

**Repos involved**:
- `C:\proj\pwiz` - OspreySharp C# (branch `Skyline/work/20260409_osprey_sharp`)
- `C:\proj\osprey` - our Rust fork (branch `fix/parquet-index-lookup`)
- `C:\proj\osprey-mm` - upstream maccoss/osprey baseline (rebased onto
  v26.1.3 in Session 10)
- `C:\proj\ai` - this TODO + scripts + handoffs

## Critical reminders for the next session

1. **Don't drift back to "shared calibration is fine" thinking**. It's
   a bisection tool only (`Test-Features.ps1 -SharedCalibration`).
   Default test mode is each tool's own calibration with exit after
   Stage 4. Session 11 found two cross-impl bugs (per-fragment Da
   tolerance, window bounds truncation) that shared-calibration
   testing had hidden.

2. **Faithful diagnostic dumps**. Use the `F10()` helper in C# for
   doubles and cast `float`->`double` before F10 formatting. Don't
   write off divergences as "just formatting" - that's how regressions
   sneak in.

3. **Memory pattern matters on .NET Framework**. Any per-call
   `double[NBins]` where NBins is HRAM-scale (~100K) goes to the
   large object heap (>85 KB) and triggers gen-2 GCs. Avoid those
   allocations in hot paths. The cal-phase fix used unit bins to
   avoid this; main search will need a different approach (per-
   window batching with controlled concurrency, or scratch reuse).

4. **Stellar must keep passing**. Run
   `Test-Features.ps1 -Dataset Stellar` after every change before
   declaring it done.

5. **Cross-impl changes go to BOTH tools simultaneously**. Any change
   that affects scoring values (bin config, dedup, rounding,
   filtering) needs the matching change applied in C# AND Rust the
   same session, otherwise the parity walk diverges.

## Session 14 (2026-04-15 -> 2026-04-16): Multi-file determinism + 3-file bench

End-of-session state: Astral single-file 0.13x Rust still holds.
Sequential 3-file Astral C# = 360.5s. Per-file determinism across
parallelism modes is now correct (Stellar 3-file seq/par2/parN all
produce bit-identical cs_features.tsv).

### Critical bugfix: per-file OspreyConfig leak

When `--write-pin --protein-fdr 0.01` was run on Stellar 3-file with
`MaxParallelFiles>1`, per-file scored entry counts diverged across
modes (e.g. file 20 in seq=466188, par2=466188, parN=464800). Two
sequential runs with `MaxParallelFiles=1` were bit-identical — the
non-determinism was specifically tied to file-level parallelism.

Root cause: `AnalysisPipeline.cs:2433` mutates `config.FragmentTolerance`
after MS2 calibration. `OspreyConfig` was the same instance shared by
all parallel `ProcessFile` calls; whichever calibration finished
second clobbered the first file's calibrated tolerance, so downstream
scoring on the first file used the second file's tolerance.

Fix: `OspreyConfig.ShallowClone()` + `config = config.ShallowClone()`
at the top of `ProcessFile`. Stellar 3-file validation now matches
across seq/par2/parN.

Note: this fix also resolves a subtle non-determinism in seq mode
that nobody noticed — file 1's calibration tolerance was leaking into
file 2 and 3 even when sequential, just deterministically. Per-file
counts in seq jumped to 466188/466131/466211 (all higher than
pre-fix), suggesting calibration was previously slightly overrun by
the wrong tolerance carried forward.

### OSPREY_MAX_PARALLEL_FILES env var

New env var (`AnalysisPipeline.cs:147`):
- `1` = strictly sequential, one file at a time (memory-safe)
- `N > 1` = `Parallel.For` capped at N concurrent files
- unset/<=0 = `Parallel.For` default (all files at once)

`Bench-Scoring.ps1` exposes via `-MaxParallelFiles N` (C# only;
Rust is always sequential).

### 3-file timings observed (single run, no median)

| Dataset | Mode | C# wall | Notes |
|---------|------|---------|-------|
| Stellar | seq  (`MaxParallelFiles=1`) | 71.3s | reference |
| Stellar | par2 (`MaxParallelFiles=2`) | 59.9s | best |
| Stellar | parN (default) | 75.6s | thread oversubscription |
| Astral  | seq  (`MaxParallelFiles=1`) | 360.5s | Rust = ~3000s |
| Astral  | par2 (`MaxParallelFiles=2`) | 364.5s | no win, ~30 GB/file working set |

Astral parN (full parallel) was killed earlier — risk of OOM with
3 × ~30 GB working sets on a 64 GB machine.

## Session 15 (2026-04-16): Stellar perf locked in + variance solved

End-of-session state: Stellar 3-file par-3 = 49.5s median with ~5%
variance. HTML diagram fully updated with Session 14 numbers across
header subtitle, Stage 4 parity blurb, four per-stage badges, and
footer. Natural commit point for the Stellar half of the sprint.

### Perf fixes (this session)

- **`OspreyConfig.EffectiveFileParallelism`** (new property) +
  per-file thread scaling in `ProcessFile`: when N files run in
  parallel, each file's main-search `Parallel.ForEach` gets
  `NThreads / N` threads instead of the full `ProcessorCount`.
  Eliminates the 3 x 32 = 96 thread oversubscription on the
  32-core box. Par-3 median dropped from 89.9s -> 56.6s.
- **`s_mzmlReadGate` `SemaphoreSlim(1,1)`** in `AnalysisPipeline`:
  serializes the `MzmlReader.LoadAllSpectra` call across concurrent
  `ProcessFile` invocations. The producer inside `LoadAllSpectra`
  is a sequential `XmlReader` over a `FileStream`, so 3 parallel
  reads fight for the same disk scan - 45-95s wall-time jitter.
  Gating collapses the disk-bound portion to one stream at a time
  while main-search scoring overlaps freely. Par-3 median dropped
  from 56.6s -> 49.5s; variance collapsed from 60% to ~5%. Gate is
  only engaged when `EffectiveFileParallelism > 1` so single-file
  and sequential runs are uncontested.
- **Rust fork build fix**: `crates/osprey/src/pipeline.rs:5292` was
  summing an `&Vec<f32>` into an `f64` (compile error after the
  Session 13 f32 HRAM narrow). Added explicit `|&v| v as f64` cast.
- **`Bench-Scoring.ps1` median off-by-one fixed**: PowerShell's
  `[int]` uses banker's rounding, so `[int](3/2) = 2` picked the max
  instead of the middle for 3-iteration runs. Replaced with
  `[Math]::Floor`.

### Experiment that did not pan out

Capping `MzmlReader`'s internal decompression `Parallel.ForEach` at
`config.NThreads` (instead of `Environment.ProcessorCount`) was
tried as an alternative to the read gate. Did not help - median
went 56.6s -> 60.7s and variance rose to 85%. The decompression
pool is brief and TPL's default scheduler was handling it fine;
throttling it just starved work. Reverted.

### Stellar perf (final)

| Mode | Median | Spread | vs Rust |
|------|-------:|-------:|--------:|
| Fork Rust (seq)          | 83.4s | ±3% | 1.00x |
| C# sequential            | 63.9s | ±3% | 0.77x |
| C# parallel-3            | 49.5s | ±5% | 0.59x |

Single-file Stellar (per-stage, median of 3): C# 22.7s vs Rust
23.2s = 1.0x (tied). S1 lib-load warm 0.7s (0.1x), S2 mzML 5.8s
(1.2x), S3 calibration 11.7s (1.5x), S4 main-search 4.5s (0.9x).

### `Osprey-workflow.html` updated

- Header subtitle: Session 14, 21 features ULP on Stellar + pass on
  Astral, 0.59x 3-file parallel.
- Stage 4 parity blurb reflects both datasets and the f32 cache
  note.
- Per-stage badges: S1 0.7s / S2 5.8s / S3 11.7s / S4 4.5s.
- Footer: Session 14 medians, Astral single-file 0.13x, full
  optimization stack including per-file thread scaling and mzML
  read gate.

## Session 16 (2026-04-16): Astral perf + first upstream PR

End-of-session state: Astral C# beats Rust ~8x on 3-file parallel
(342s vs 2751s). First upstream PR (maccoss/osprey#3) posted with
measured calibration evidence. Stage 1 upstream path is live.

### Astral 3-file perf (1 iteration, Session 15 fixes in place)

| Mode | Wall | vs Rust |
|------|-----:|--------:|
| Fork Rust (seq, sequential always)  | 2751.2s | 1.00x |
| C# sequential (`MaxParallelFiles=1`) | 380.1s | 0.138x (7.2x faster) |
| C# par-2 (`MaxParallelFiles=2`)      | 372.8s | 0.136x (7.4x faster) |
| C# par-3 (`MaxParallelFiles=3`)      | 342.3s | 0.124x (8.0x faster) |

Rust 3-file wall (~2751s) is ~3x Rust single-file from Session 14
(~917s), confirming Rust has zero file-level parallelism - linear
scaling with file count. C# par-3 (342s) vs C# single-file (111s) is
~3.1x, meaning ~97% parallel efficiency across 3 files. Session 15
per-file thread scaling (3 x 10 threads = 30 on 32-core box) and
mzML read gate are both earning their keep on Astral too. Par-3 did
NOT OOM on 64 GB - the per-file thread scaling effectively reduces
per-file in-flight window count, which shrinks the scratch pool
high-water mark.

### Astral single-file baseline (1 iteration, for per-stage badges)

C# 110.7s (cold 160.9s), S1 4.3s lib-load, S2 34.9s mzML parse,
S3 20.0s calibration, S4 49.4s main-search. mzML parse is still
HDD-bound and roughly 1.6x Rust's mzdata crate - see "mzML perf
considerations" below.

### Upstream PR path launched - Stage 1 plan

Strategy for upstreaming parity + perf work to maccoss/osprey
documented this session. Stage 1 ships 5 small focused PRs, each
anchored on Mike's own in-code comments or a specific correctness
bug class, landed in order of least-controversial first. Stage 2
offers perf optimizations (file parallelism, XCorr scratch pooling)
after Stage 1 demonstrates working collaboration.

Stage 1 PR order (landing sequence, least-controversial first):

1. **Unit-bin calibration XCorr** (posted as maccoss/osprey#3)
2. `longest_consecutive_ions` ordinal attribution (fork commit
   `22fa4a9` split)
3. `lib_cosine` norm-gate decoupling (fork commit `22fa4a9` split)
4. DIA window bounds truncation (fork commit `a07aae6`)
5. XCorr fragment bin dedup (fork commit `4db625c`) - most
   algorithmic, save for last after Mike engages with the smaller
   PRs

Stage 2 perf offers (after Stage 1):
- Rayon file parallelism (+ per-file config clone, same pattern as
  C# `OspreyConfig.ShallowClone()`)
- Per-window XCorr preprocessed cache (analog of C# `XcorrScratchPool`
  + `WindowXcorrCache` - rust already has the ingredients)

### maccoss/osprey#3 - unit-bin calibration XCorr

Posted today. Single-line change + expanded comment in
`run_calibration_discovery_windowed` (pipeline.rs:407), switching
the HRAM branch from `SpectralScorer::hram()` to
`SpectralScorer::new()`. Matches the choice already made in
`run_xcorr_calibration_scoring` (batch.rs:2021), anchored on
Mike's own comment there.

PR body includes measured evidence from before/after runs on Mike's
Astral file 49 (fork vs fork with the one-line revert, both using
the fork's diagnostic dumps):

- RT calibration curve: max predicted-measured-RT delta 0.45s over
  21.7-min gradient (median 0.07s)
- MS1 mass cal: mean shift delta 0.02 ppm, tolerance delta 0.03 ppm
- MS2 mass cal: mean shift delta 0.003 ppm, tolerance delta 0.07 ppm
- LOESS pool: unit 2927 pairs vs hram 2966 pairs (1.3% more)
- R^2: delta 1.6e-5 (0.99865 vs 0.99867)

Diagnostic outputs saved at `ai/.tmp/cal_delta/{unit_bins,hram_bins}/`
for future reference. Writeup contingency: if Mike wants even
deeper evidence, same infrastructure can extend to 21-feature
main-search diffs using the existing `OSPREY_DIAG_SEARCH_ENTRY_IDS`
dumps.

### If Mike rejects unit-bin calibration

The alternative path is to adopt per-window HRAM calibration in
C# to preserve cross-impl parity. Session 15 infrastructure
(`XcorrScratchPool`, `WindowXcorrCache`, `EffectiveFileParallelism`
thread scaling) makes this a ~1 day port. Estimated Astral
calibration cost: ~20s (similar to today's all-at-once unit-bin
20.0s), bounded above by Stage 4 x entry-ratio. Stellar is
unit-resolution so no change there. Total run-wide impact ~1-2%
of wall clock. Not devastating if it happens.

### mzML perf considerations (deferred)

Rust's mzdata crate uses SIMD base64 (`base64-simd` crate) and
quick-xml streaming, giving it ~1.7x our C# mzML parse on HDD.
Rust doesn't use memory-mapped files - it's pure SIMD-heavy
per-byte decode. For OspreySharp, the obvious alternative is
`pwiz_data_cli.dll` (the existing ProteoWizard C# wrapper around
C++ pwiz). Worth benchmarking but not this sprint - three
outcomes:
1. `pwiz_data_cli` wins -> adopt, delete our MzmlReader
2. Ties our custom reader -> pwiz C++ itself has a gap vs mzdata,
   optimizing pwiz benefits Skyline and all consumers
3. Loses -> interesting data, keep custom reader

Tracked as a separate follow-up task outside this sprint.

## Session 17 (2026-04-16): Stage 1 upstream PRs posted end-to-end

End-of-session state: all five Stage 1 PRs are up in front of Mike
(maccoss/osprey#3 merged, #4-#8 open). Each carries a regression
test that was explicitly verified to fail under the pre-fix
behavior. C# side has matching regression guards wherever the
invariant was at risk of drift.

### Upstream PRs posted (all against maccoss/osprey main)

| # | Title | File | Scope | Evidence |
|---|-------|------|-------|----------|
| 3 | Use unit-resolution bins for calibration XCorr scorer | pipeline.rs | perf-at-parity | **MERGED** (RT delta 0.45s max, MS1/MS2 mass cal deltas <=0.02 ppm) |
| 4 | Add regression tests for calibration XCorr bin choice | pipeline.rs | guard for #3 | open |
| 5 | Attribute consecutive-ions ordinals from FragmentMatch directly | lib.rs | parity bug (290 Astral rows) | open |
| 6 | Decouple lib_cosine counting features from the norm gate | lib.rs | parity bug (59 Astral rows) | open |
| 7 | Preserve full-precision isolation-window bounds in DIA grouping | batch.rs | parity bug (~2 Astral rows, cascades) | open |
| 8 | Dedup fragment bins in scorer.xcorr and xcorr_at_scan | lib.rs | algorithmic, changes all XCorr values | open |

Each PR:
- Touches a single file, single function family
- Includes a regression test verified to fail under the pre-fix
  code (left/right values captured in each PR body)
- States how it relates to the others (all independent; any merge
  order works)
- Declares cross-implementation validation evidence where observed

PR #8 is the most algorithmic -- it changes all XCorr numerical
output. PR body explicitly flags Jimmy Eng as a candidate reviewer
since he authored Comet's XCorr algorithm. If Mike wants to
defer #8 pending Jimmy's input, #3-#7 can still land and #8 is
the only one whose rejection would require rolling back C#
(because our C# made the matching dedup change in Session 9).

### Rejection-contingency cost per PR (parity perspective)

- **#4** (test-only): no C# cost if rejected; we keep our own test.
- **#5** (ordinal attribution): C# already iterates library
  fragments per ion type; C# never had the bug. Rejection means
  accepting ~290-row divergence at b_n/y_m m/z collisions.
- **#6** (norm-gate decouple): C# computes counting features in
  separate functions; C# never had the bug. Rejection means
  accepting ~59-row divergence on short-/low-signal peptides.
- **#7** (DIA bounds): C# already stores the full IsolationWindow
  object (keyed by truncated center only for dedup). Rejection
  means accepting ~2-row divergence at window boundaries.
- **#8** (XCorr dedup): C# already dedups (Session 9). Rejection
  here would require **reverting the Session 9 C# dedup** to
  restore numerical parity -- real cost.

### Regression guards on the C# side

One C# regression test added this session:
`TestCalibrationXcorrScorerUsesUnitBins` in
`OspreySharp.Test/CalibrationTest.cs`. Mirrors PR #4's Rust
guard -- verifies `s_calXcorrScorer.BinConfig.NBins` equals
`BinConfig.UnitResolution()`'s NBins and is not
`BinConfig.HRAM()`'s. Required `[InternalsVisibleTo("pwiz.
OspreySharp.Test")]` in OspreySharp's AssemblyInfo.cs and
flipped `s_calXcorrScorer` from private to internal.

The other three non-algorithmic bug classes (ordinal attribution,
norm gate, DIA bounds) were evaluated for a C# port and skipped
because C# was structurally immune by design in each case (see
per-PR analysis above). Adding a guard where no bug can exist
would duplicate effort better spent on code paths where drift is
possible.

### Approach that worked, for future reference

When splitting a multi-concern fork commit into multiple upstream
PRs (e.g. 22fa4a9 -> PR-5 ordinal + PR-6 norm-gate):

1. Branch from upstream/main
2. Cherry-pick the whole fork commit with --no-commit
3. Use Edit to revert the hunks NOT in this PR's scope, so the
   stage matches the intended PR diff
4. git reset HEAD to unstage, then manually git add the final file
5. Commit with an upstream-tone message (no internal TODO refs,
   no OspreySharp mentions, anchor on upstream's own comments/
   docs where possible)
6. Add regression test for the invariant being enforced, verify
   test fails with pre-fix + passes with fix
7. Push, gh pr create

Each PR took about 20-30 minutes from branch-creation to PR-up,
including the regression-test authoring + failure verification.

## Next session: wait on Mike + start thinking about Stage 2

1. **Respond to Mike's questions on #4-#8** as they come in. Each
   PR stands on its own, so he can merge/reject/discuss
   independently. #8 is the most likely to generate discussion
   (Jimmy Eng's input may be requested).
2. **If Mike rejects #8**: revert the Session 9 C# dedup fix in
   OspreySharp.Scoring to restore parity. See SpectralScorer.cs
   XCorr path. All other rejections are parity-degradation but
   don't require code changes on our side.
3. **Stage 2 prep** (Rust perf offers, after Stage 1 settles):
   - Rayon file-level parallelism with per-file
     `OspreyConfig.clone()` -- the same pattern as the C#
     `OspreyConfig.ShallowClone()` we added in Session 12.
     Measured 7-8x Rust speedup on 3-file Astral (Rust currently
     linear-in-file-count at ~917s/file). Biggest single Rust
     perf opportunity in our pocket.
   - Per-window XCorr preprocessed cache
     (`XcorrScratchPool`/`WindowXcorrCache` equivalent) -- Rust
     already has the ingredients (`preprocess_library_for_xcorr`,
     `xcorr_from_preprocessed`), just needs the pool pattern
     around them. Would bring main-search memory and allocation
     under control similar to our C# wins.
4. **Stage 5 + 6 work on our side**: Percolator SVM FDR and
   the blib output path are the next stages to port/verify on
   the C# side. Out of scope of this sprint but the natural
   continuation.
5. **pwiz_data_cli mzML eval**: still a standing follow-up task.

### Stage 1 PR links for reference

- https://github.com/maccoss/osprey/pull/3 (merged)
- https://github.com/maccoss/osprey/pull/4
- https://github.com/maccoss/osprey/pull/5
- https://github.com/maccoss/osprey/pull/6
- https://github.com/maccoss/osprey/pull/7
- https://github.com/maccoss/osprey/pull/8

### Known small items (unchanged since Session 16)

- `Bench-Scoring.ps1` does not produce the MEDIAN table for
  `-Iterations 1` runs (requires `$runs.Count -ge 2`). The raw
  per-iteration numbers still print, so we read them directly.
- `Osprey-workflow.html` could add a note about the 1-file Astral
  mzML parse rate (~35s vs Rust ~22s) with the "SIMD base64 /
  quick-xml" explanation (see Session 16's mzML perf
  considerations).

## Session 18 (2026-04-16): Project review + cleanup sprint

Pivoted from Stage 2 prep to a structured project-health review and
cleanup pass. With Stage 1 PRs in front of Mike and core parity +
perf locked in, this is the natural checkpoint before continued
LLM-assisted development drifts the project's internal shape.

### Review findings (health-score snapshot)

Eight-project layout (Core / ML / IO / Chromatography / Scoring /
FDR / main / Test) is cleanly decomposed by subject area; namespace
and folder organization align perfectly; no public mutable fields;
disciplined `[InternalsVisibleTo]` use; MSTest discipline
throughout. The 8-project split already delivers most of what a
review would otherwise recommend.

| Dimension | Grade | Notes |
|---|---|---|
| Modularity (cross-project) | A | Clean decomposition by subject area |
| Modularity (within-project) | C | `AnalysisPipeline.cs` = 4,721 LOC god class; `PercolatorFdr.cs` = 1,521 LOC |
| DRY | B- | 17+ scattered env-var reads; repeated dump/exit scaffolding; `BlibLoader`/`ElibLoader` SQLite-open duplication |
| Encapsulation | A- | All private; 3 mutable statics in `AnalysisPipeline` deserve scrutiny (`_top6MzCache` grows unbounded across files) |
| Separation of concerns | C+ | Pipeline stages cleanly split across projects, but inside `AnalysisPipeline` orchestration + feature extraction + diagnostics + IO routing are interleaved |

### Cleanup in scope this session

- Copy `Skyline.sln.DotSettings` to `OspreySharp.sln.DotSettings`
  (pruning Skyline-only excluded paths).
- Add `-RunInspection` switch to
  `ai/scripts/OspreySharp/Build-OspreySharp.ps1`, modeled on the
  Skyline `-RunInspection` design but self-contained.
- Zero compiler + ReSharper warnings on `OspreySharp.sln`.
- Apply Apache-2.0 license headers to all ~71 non-generated .cs
  files under `pwiz_tools/OspreySharp/`, per `ai/STYLEGUIDE.md`
  §"File Headers and AI Attribution" — original author Brendan
  MacLean, AI assistance Claude Code, "Based on" credit to
  maccoss/osprey.
- Extract `OspreyEnvironment` static helper to centralize the 17+
  env-var reads and dump/exit scaffolding. Behavior-preserving;
  add unit tests.
- Add local `pwiz_tools/OspreySharp/Jamfile.jam` (modeled on
  `pwiz_tools/SeeMS/Jamfile.jam`) with explicit `OspreySharp` and
  `OspreySharpTest` targets for `quickbuild.bat` / TeamCity
  integration. Both `explicit` so OspreySharp opts in rather than
  breaking default Skyline builds.

### Deferred — Phase 4 cleanup follow-ups

Recommended refactoring items intentionally NOT in this session.
Each deserves its own focused sprint with parity + perf regression
guards:

1. **Extract `FeatureExtractor`** from `AnalysisPipeline.cs` —
   ~1,500 lines of feature math (`ComputeCoelutionStats`,
   `ComputePeakShapeFeatures`, `ComputeApexMatchFeatures`,
   `ComputeMs1Features`, XIC extraction) moved into a dedicated
   class in `OspreySharp.Scoring`. Biggest modularity win.
2. **Stage-class split** — `LibraryLoadingStage`, `CalibrationStage`,
   `MainSearchStage`, `FdrStage`, `OutputStage`. Reduces
   `AnalysisPipeline.cs` from 4,721 LOC to a ~400-line thin
   orchestrator.
3. **Split `PercolatorFdr.cs` (1,521 LOC)** — separate PIN format
   writer from LDA.
4. **`SQLiteLibraryLoaderBase`** — extract shared
   `SQLiteConnection` open + `TableExists` helpers from
   `BlibLoader` / `ElibLoader` (`pwiz.OspreySharp.IO`).
5. **`AnalysisCache`** — wrap `_top6MzCache` (currently a raw
   run-lifetime `ConcurrentDictionary`) with a cache object
   cleared per-file to bound memory on long runs.
6. **Extend regression test coverage** — the 18-test bug-class
   regression suite (Phase 2 Priority 5) is ready to extend with
   main-search era bug classes now that parity is locked in.

### Session 18 results (end-of-session, 2026-04-17)

Full sprint landed in 7 focused commits on the branch:

1. `c55b32a1e` OspreySharp cleanup: inspection support, warnings,
   license headers (DotSettings copy + 74 Apache-2.0 headers + 157
   ReSharper warnings taken to zero; MLTest type-inference regression
   caught and fixed)
2. `6cb02278f` Fixed STYLEGUIDE.md violations in OspreySharp (117
   single-line ifs split, 25 non-ASCII -> ASCII)
3. `3f8334d6c` Cleaned up OspreySharp assembly naming and enum file
   layout (drop `pwiz.` prefix from 8 assembly names, copyright
   2026, 7 enum files merged into related class files)
4. `9f0c0c76a` Extracted OspreyEnvironment for control/throttling env
   vars (6 env vars cached as readonly statics)
5. `672b8612e` Extracted OspreyDiagnostics for cross-impl bisection
   dumps (~350 lines out of AnalysisPipeline; 9 checkpoint methods
   + F10 formatter; byte-identical output preserved)
6. `27f915572` Added OspreySharp Jamfile for quickbuild integration
   (explicit OspreySharp / OspreySharpTest targets; parent Jamfile
   picks up via build-project-if-exists)

Plus the ai/ scripts companion commit `ad1fe6b` for the renamed
binary/DLL names.

### Validation gates passed

- **Unit tests**: 186/186 pass
- **ReSharper + compiler warnings**: 0
- **Non-ASCII characters in .cs files**: 0
- **Stellar parity**: 21/21 features bit-identical at 1E-06
  (317,536 entries; C# 26.0s vs Rust 26.5s = 0.98x)
- **Astral parity**: 21/21 features bit-identical at 1E-06
  (945,354 entries; C# 143.1s vs Rust 976.8s = 0.147x, 6.8x faster)
- **Stellar perf bench**: C# 24.4s vs Rust 25.2s = 1.0x
  (Stage 1-4 breakdown clean; no regression introduced by the
  OspreyDiagnostics indirection)

### Deferred to follow-up sprints

- **Mirror OspreyDiagnostics on the Rust side** (new follow-up): same
  checkpoint API in `osprey` (our fork) so the bisection infrastructure
  stays symmetric and can be upstreamed cleanly to maccoss/osprey for
  long-term cross-impl consistency testing.
- Findings #1-#6 from the Phase 4 review (FeatureExtractor,
  stage-class split, PercolatorFdr split, SQLiteLibraryLoaderBase,
  AnalysisCache, regression-test suite extension) remain deferred.
- Astral perf bench (3-iteration median run) skipped per user
  direction; Astral single-file timing captured indirectly via the
  parity test is sufficient for regression check.

## Next session handoff

For the session-19 startup protocol, respond to any pending Mike
comments on maccoss/osprey#4-#8, then either start Stage 2 prep
(Rayon file-level parallelism, per-window XCorr cache) or the
mirrored Rust diagnostics extraction. No handoff file is needed --
state is captured in this TODO and the open PRs.
