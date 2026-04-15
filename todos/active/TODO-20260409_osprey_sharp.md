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

### Priority 1: Main-search Astral walk (correctness)

Walk the same way we did calibration:

- [ ] **Main-search XICs (post-recalibration)**: pick a few entry IDs
      from passing targets, set `OSPREY_DIAG_SEARCH_ENTRY_IDS=...`,
      compare per-fragment XIC values across tools.
- [ ] Note: this diagnostic does NOT early-exit; it collects across the
      full main search. Astral Stage 1-4 in Rust took 879s when last
      run end-to-end. Consider adding an "exit after these IDs are
      dumped" gate before running, OR pick IDs and accept the wait.
- [ ] **CWT peak boundaries**: extend the search XIC dump to also
      write start/apex/end indices and pairwise correlation scores per
      CWT candidate. Compare across tools.
- [ ] **21 PIN features with own calibration**:
      `pwsh -File ./ai/scripts/OspreySharp/Test-Features.ps1 -Dataset Astral`
      Both tools run Stage 1-4 in full. Expect long wait + the LOH GC
      issue from Session 11 to resurface in C# main search.

### Priority 2: HRAM main-search perf (likely required to finish Priority 1)

If C# main search is impractically slow (the prior end-to-end Astral
attempt was killed mid-run after 20+ minutes at ~14% CPU), apply the
analogous fix used for cal:

- [ ] Profile C# Astral with `Profile-OspreySharp.ps1 -Dataset Astral
      -Stage Scoring`. Expect XcorrFromPreprocessed/XcorrAtScan at the
      top with HRAM 100K-bin allocations again.
- [ ] Decide approach:
      - **Per-window HRAM pre-preprocessing** with capped parallelism
        (the Session 11 attempt at this thrashed memory at 32 threads ×
        1 GB; would need MaxDegreeOfParallelism limit, e.g. 8, to fit
        in 64 GB RAM)
      - **RT-sliding window cache** (Skyline pattern) - sort targets by
        expected RT, hold preprocessed spectra only for the active RT
        window, drop as targets pass
      - **Thread-local scratch buffer** with HRAM 100K-bin arrays
        reused across calls (no LOH churn but still does the per-call
        bin/window/slide compute)
- [ ] Implement chosen approach in BOTH tools to keep cross-impl
      parity. Verify Stellar still bit-identical.

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

For detailed Session-12 startup protocol (skills to load, build/
verification commands to confirm parity baselines before changing
anything, the main-search walk plan in step-by-step form, and
gotchas), read `ai/.tmp/handoff-20260409_osprey_sharp.md` before
starting work.
