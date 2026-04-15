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

Now that the edit-build-test loop is viable (Astral in ~16 min end-to-
end; Stellar in ~2 min), profile the scoring phase with dotTrace to
find the remaining 9%. Proposed approach:

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

## Next session handoff

Session 12 wrapped Astral main-search parity + pool fix. For the
**session-13 startup protocol** (dotTrace API wire-in, short-circuit
env var, peak-memory logging), see the "Next sprint" section above.

The phase-2 handoff at `ai/.tmp/handoff-20260409_osprey_sharp.md` is
superseded by the Session 12 entry above. Don't rely on the older
parity tables in that handoff - they're pre-Astral-main-search.
