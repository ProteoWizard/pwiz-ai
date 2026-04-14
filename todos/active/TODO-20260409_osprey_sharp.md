# TODO-20260409_osprey_sharp.md  -  Phase 2

## Branch Information
- **Branch**: `Skyline/work/20260409_osprey_sharp`
- **Base**: `master`
- **Created**: 2026-04-09
- **Phase 2 started**: 2026-04-11 (Session 8)
- **Status**: In Progress
- **GitHub Issue**: (pending)
- **PR**: (pending)

## Phase History

See [TODO-20260409_osprey_sharp-phase1.md](TODO-20260409_osprey_sharp-phase1.md)
for Sessions 1-7 (2026-04-09 through 2026-04-11): initial Osprey build and
bugfixes, full OspreySharp scaffolding (Phase 1-5), end-to-end pipeline, and
cross-implementation bisection walk that proved bit-identical pass-1
calibration features (Stellar file 20: 192,289/192,289 matches, max |d| <=
5e-10, 90.72% exact-bit-equal across all 6 feature columns).

The phase-1 file also contains the full set of diagnostic env vars, fast
iteration commands, build commands, test data locations, and debugging
gotchas that remain valid in Phase 2  -  do not duplicate them here.

## Objective

Port Mike MacCoss's **Osprey** (Rust DIA peptide-centric search tool) to C# as
**OspreySharp** within `pwiz_tools/OspreySharp/`. The goal is a C#
implementation that performs comparably to the Rust original but is
accessible to the Skyline team for integration and reuse.

## Osprey Fork Status (IMPORTANT)

The Rust Osprey project at `C:\proj\osprey` is tracked via the user's
**private fork**, `git@github.com:brendanx67/osprey.git`, branch
`fix/parquet-index-lookup`. Some changes on the Rust side are tactical  - 
cross-impl diagnostics, parity-fix decisions, scratch instrumentation  -  and
may never be upstreamed to `maccoss/osprey`. **The user decides per-change
whether to PR upstream.**

When touching the Rust side:
- Commit locally with clear messages so we can always tell what is "ours"
  vs what upstream has.
- Do not skip `cargo fmt` + `cargo clippy -- -D warnings` on Rust commits  - 
  the fork still tracks upstream CI expectations (Session 7's scratch
  diagnostics commit skipped both and left three files of debt for Session 8
  to clean up).

## Current State (updated Session 9)

**Proven bit-identical** (walking downstream from library sampling):
1. Library sampling (Session 6)
2. Per-entry (m/z, RT) window selection (Session 6)
3. Pass-1 chromatograms / XICs (Session 7, <= 1e-10 rounding noise)
4. CWT peak detection + best-peak selection + fallback path
5. Reference XIC selection, apex selection, SNR on reference XIC
6. LibCosine / Top-6 / XCorr at apex
7. All 6 pass-1 cal_match feature columns: 192,289/192,289 matches,
   max |d| <= 5e-10, 90.72% exact-bit-equal on all columns (Session 7)
8. Apex scan number in cal_match dump (Session 8)
9. Pass-2 XIC extraction on entry 0 (46 candidates, 276 XIC rows <= 1e-10)
10. Pass-1 LDA discriminant + q-value (Session 8, after iterative port):
    192,289 rows, 192,288/192,289 discriminants bit-equal (max |d| = 1e-10),
    all 192,289 q-values bit-equal, target 1% FDR pass 11,937 = 11,937
    (delta 0), full set overlap.
11. Pass-1 S/N quality filter: 6,423 = 6,423 input points to LOESS
    (was 6,409 in Session 7 due to LDA drift; now matches after iterative
    LDA port). Verified via OSPREY_DUMP_LOESS_INPUT diagnostic: 6,423/6,423
    lib_rt bit-equal, 6,422/6,423 measured_rt bit-equal (1 row at 2 ULP).
12. Pass-1 LOESS fit (Session 8 continuation): all 10 LOESS MODEL stats
    bit-identical at F10 precision (r_squared, residual_sd, mean_residual,
    max_residual, p20/p80_abs_residual, mad, expected_rt, tolerance).
    Root cause of prior divergence: Rust computes robust-iteration residuals
    ONCE from initial fit; C# was refreshing per iteration (classical mode).
    Fixed C# to match Rust. Both tools now also support the classical mode
    via OSPREY_LOESS_CLASSICAL_ROBUST=1 env var for potential upstream fix.
13. Pass-2 LOESS MODEL on entry 0 bit-identical (all stats match, verified
    via OSPREY_DIAG_XIC_ENTRY_ID=0 OSPREY_DIAG_XIC_PASS=2).
14. MS2 m/z calibration stats bit-identical (Session 9): mean=-0.0654 Th,
    SD=0.1325 Th, n=44,277 errors (top-6 fragments from passing targets).
15. Main-search XICs (post-recalibration, Session 9): 9 spot-checked entries
    across different RT/m/z ranges, 0/2,269 XIC values differ by >0.01.
    Fixes applied: global RT tolerance (was per-entry), scan boundary order,
    MS2 calibrated fragment tolerance (3*SD), MS2 m/z offset correction.

16. CWT peak boundaries (Session 9): spot-checked 3 entries  -  same
    number of peaks, same boundaries, same correlation scores.
17. Main-search all 21 PIN features (Session 9, COMPLETE):
    311,176 matched entries with shared calibration. All 21 features at
    0.00% divergence (>1e-6 threshold), with only 4 entries from different
    CWT peak selection and 191 consecutive_ions.
    Bugs fixed this session:
    - peak_apex/area/sharpness: composite XIC -> ref XIC + trapezoidal
    - xcorr: fragment bin double-counting (shared bins counted once)
    - n_coeluting_fragments: any-positive -> mean-positive
    - MS1 features: added HRAM-only gate (unit resolution skips MS1)
    - fragment matching in mass_accuracy: most-intense -> closest-by-mz
    - median polish convergence: incremental -> full-iteration comparison
    - SG-weighted features: enabled (were zeroed)
    - MS2 calibrated tolerance + m/z offset: ported from Rust
    - Global RT tolerance: ported from Rust (was per-entry local)
    - Scan boundary: fixed off-by-one at RT window edge
    Note: comparison used OSPREY_LOAD_CALIBRATION to share Rust's
    calibration JSON (eliminates independent-calibration noise).

**Not yet proven** (next downstream targets):
- First-pass Percolator SVM FDR
- Second-pass reconciliation + boundary overrides
- Final blib output

## Phase 2 Remaining Tasks

### Immediate: Port iterative LDA refinement  -  DONE (Session 8)
- [x] Port `create_stratified_folds_by_peptide` (3-fold CV grouped by peptide)
- [x] Port `count_passing_targets` (paired target-decoy competition -> q-values)
- [x] Port `select_positive_training_set` (Percolator-style positive selection
      with `MIN_POSITIVE_EXAMPLES = 50`)
- [x] Port `average_weights` (mean of N weight vectors)
- [x] Port the main iteration loop in `train_lda_with_nonnegative_cv` with
      best-iteration tracking and 2-consecutive-no-improve early stopping
- [x] (Not needed) signature change: sequences are pulled from `matches[i].Sequence`
      inside `TrainAndScoreCalibration`, matching Rust's extraction pattern
- [x] LDA dump verification: 192,288/192,289 discriminants bit-equal
      (max |d| = 1e-10), 192,289/192,289 q-values bit-equal, target 1% FDR
      pass 11,937 = 11,937, full set overlap
- [x] Re-verified cal_match features unchanged (no regression)
- [x] Commit: pwiz `2704aa1ef` "Ported iterative non-negative CV LDA
      refinement to CalibrationScorer"

### Fidelity walk continuation
After LDA passes, continue the Session 6/7 methodology:
- [ ] Pass-1 LOESS fit output  -  extend the XIC dump to include N predictions
      across the RT range; diff against Rust
- [x] Main-search XICs (post-recalibration) on 9 entries via
      `OSPREY_DIAG_SEARCH_ENTRY_IDS`  -  0/2,269 XIC values differ >0.01
      (Session 9). Required: global RT tolerance, scan boundary fix,
      MS2 calibrated fragment tolerance, MS2 m/z offset correction.
- [x] Main first-pass search features  -  all 21 PIN features at 0.00%
      divergence across 311K entries with shared calibration (Session 9)
- [ ] First-pass Percolator SVM  -  discriminant scores + q-values per
      precursor (expect ULP drift here too  -  SVM training is similar to LDA)
- [ ] Second-pass reconciliation  -  boundary overrides, re-scored features at
      locked RT boundaries
- [ ] Final blib output  -  precursor counts, RT boundaries, fragment tables

### Core port carry-over (still open from Phase 1 plan)
Items that were scoped in Phase 1 but deferred, dropped, or never reached:

- [ ] **Chemistry integration**: replace `IsotopeEnvelope.cs` placeholder with
      `Shared/CommonUtil/Chemistry` (Molecule, AminoAcidFormulas,
      MassDistribution). OspreySharp MUST calculate masses and isotope
      distributions identically to Skyline  -  17 years of validation behind
      the Shared code. Do NOT port Rust's binomial isotope approximation.
- [ ] **Parquet caching**: evaluate whether to port Rust's per-file
      `.scores.parquet` cache (21 PIN features + fragments + CWT candidates,
      ZSTD-compressed, SHA-256 metadata for invalidation) or stick with
      direct file I/O. Rust uses this to scale to 1000+ file experiments
      without OOM; C# currently has no equivalent.
- [ ] **Project references**: wire up CommonUtil, BiblioSpec,
      ProteoWizardWrapper as project references so OspreySharp can reuse
      Skyline's Shared libraries (not redundant ports).
- [ ] **Pre-I/O review** (scoped in Phase 3, never formally done): survey
      existing pwiz infrastructure before any more I/O work; prefer wrappers
      over ports where Shared code already handles the format.
- [ ] **Pre-pipeline review** (scoped in Phase 5, never formally done):
      verify threading (ActionUtil.RunAsync), progress reporting, and
      cancellation follow Skyline conventions.
- [ ] **Math.NET Numerics + MKL provider** for BLAS (deferred to perf
      phase): replace the managed matrix loops in SVM/LDA training with
      MKL-backed ndarray-equivalent when we start optimizing performance.
- [ ] **Developer setup doc** (`pwiz_tools/OspreySharp/docs/dev-setup.md`):
      Rust reference oracle install + C# build walkthrough. Pairs with the
      new README.md below.

### End-to-end validation (full pipeline, both datasets)
Session 6-8 proved bit-identical pass-1 calibration features. The pipeline
from pass-1 LDA onward (LOESS -> pass-2 scoring -> Percolator -> FDR ->
reconciliation -> blib) has never been validated side-by-side in full. Goal:
C# produces the same precursor / peptide / protein counts as Rust on real
data, not just the intermediate diagnostic dumps.

- [ ] **Stellar full-pipeline side-by-side**: C# and Rust both process the
      three Stellar mzML files, both output a final blib, both reported
      target 1% FDR counts match within noise. Rust reference (Session 3):
      36,783 precursors / 33,966 peptides / 5,604 proteins on desktop.
      Current C# state: unknown past LDA; needs re-measurement after the
      iterative LDA port lands.
- [ ] **Astral full-pipeline side-by-side**: has NEVER been run end-to-end
      in C#. Rust reference (Session 3): 143,622 precursors / 125,609
      peptides / 13,482 proteins. Astral has ~1.5M library entries and
      uses HRAM fragment tolerance; expect multi-hour runtime.
- [ ] **Reconciliation + second-pass FDR** must be ported before Astral
      validation makes sense (Rust uses boundary overrides + second-pass
      Percolator, C# does not yet).
- [ ] **Multi-charge consensus**: Rust picks a consensus leader among FDR
      passing charge states using SVM scores; C# has this as a stub.
- [ ] **Protein parsimony + picked-protein FDR**: Rust has native Rust
      impl (`osprey-fdr/src/protein.rs`), C# has a port but it's untested
      end-to-end.

### Performance parity (hard Phase 2 goal, not optional)

**Session 10 performance optimization** (Stellar file 20, `--resolution unit`,
`Bench-Scoring.ps1`, median of 2-3 iterations):

```
Session start (3.3x):
  Fork Rust      5.0s    5.0s     9.0s     6.0s    24.0s
  OspreySharp    2.1s   16.2s    30.7s    30.7s    79.3s   3.3x

After all optimizations (1.6x):
  Fork Rust      4.5s    5.0s     9.0s     6.0s    24.5s
  OspreySharp    2.2s    8.4s    18.0s    10.5s    39.0s   1.6x
  C#/Rust       0.5x    1.7x     2.0x     1.8x     1.6x
```

Optimizations applied in Session 10 (total: 3.3x -> 1.6x = 2x speedup):
- [x] **Library binary cache** (`6877858cd`): 9.1s cold -> 2.1s cached
- [x] **Parallel decoy generation** (`6877858cd`): 1.7s -> 0.9s
- [x] **Pre-preprocessed XCorr per window** (`ea8cba515`): Stage 4
      30.7s -> 9.6s (3.2x speedup). Spectrum binning+windowing+sliding
      done once per window, O(n_frags) bin lookups per candidate.
- [x] **Calibration XCorr cache** (`38b86c488`, `2d5177be6`): Stage 3
      30.7s -> 19.3s. Fixed window key resolution for neighbour fallback.
- [x] **Calibration prefilter optimization** (`3ecd576fa`): replaced
      LINQ OrderByDescending+Take+ToList with HasTopNFragmentMatch
      (binary search, no alloc). 25.8s -> 19.3s.
- [x] **Cached top-6 fragment m/z** (`38a4578cb`): ConcurrentDictionary
      caches top-6 fragment m/z per entry ID. Eliminated prefilter sort.
      19.8s -> 18.0s.
- [x] **Parallel mzML decompression** (`5c70d657e`): two-phase parse +
      Parallel.For decode. 14.9s -> 9.5s.
- [x] **Producer-consumer mzML pipeline** (`ded71b5a3`): XML parse
      overlaps with decompression via BlockingCollection. 9.5s -> 8.1s.
      Note: Skyline CommonUtil.ProducerConsumerWorker should be used in
      future integration.
- [x] **dotTrace profiling** (3 runs): identified hot spots, drove each
      optimization. Script: `ai/scripts/OspreySharp/Profile-OspreySharp.ps1`.

Remaining optimization targets (to reach 1.5x = ~37s):
- [ ] **Stage 3 calibration XIC extraction** (55s own across threads):
      `ExtractTopNFragmentXics` does 6 fragments x ~100 spectra x binary
      search per entry. Rust uses batch matrix scoring instead of per-entry
      XIC extraction. Options: (a) implement batch matrix scoring,
      (b) precompute fragment-to-bin index per window, (c) SIMD binary search.
- [ ] **Stage 2 mzML further optimization**: use Skyline's
      ProducerConsumerWorker from CommonUtil for production integration.
      Buffer pooling for base64/zlib allocations.
- [ ] **SIMD / vectorize CWT convolution** via `System.Numerics.Vector<T>`
      or `System.Runtime.Intrinsics` (AVX2/AVX-512 where available).
- [ ] **Math.NET Numerics + MKL provider for LDA/SVM training**
      (see Core port carry-over).
- [ ] **mzML reader**: already native C# XmlReader (not COM bridge).
      Rust is faster due to quick-xml + mzdata ConcurrentLoader.

### Regression test coverage (new  -  Phase 2 addition)

**Context**: All OspreySharp unit tests (~161 tests across Core, ML, IO,
Chromatography, Scoring, FDR) were passing before Session 5's end-to-end
validation began  -  and then Sessions 5-8 uncovered many serious port errors
that the unit tests did not catch. The unit-test-green state was a **false
sense of security**. Phase 2 adds targeted regression tests designed to fail
against the pre-fix implementation of each bug class, so future ports do not
repeat the same mistakes.

- [x] Write regression tests (each must be fast, no full Stellar dataset)
      for the following Session 5-9 lessons (18/18 done, Session 10):

  **Session 5-8 bugs (calibration phase)**:
  - [x] **XCorr windowing normalization**  -  `TestXcorrWindowingNormalization` +
        `TestXcorrFullPipeline` (Session 10)
  - [x] **SNR input buffer**  -  `TestSnrUsesRefXicNotComposite` (Session 10)
  - [x] **Apex selection tie-break**  -  `TestApexTieBreakLastWins` (Session 10)
  - [x] **f32 vs f64 intermediate precision drift**  -  `TestXcorrF64VsF32PrecisionDrift` (Session 10)
  - [ ] **Constant mismatches**  -  regression test that detects when shared
        named constants in Osprey and OspreySharp diverge
        (`MIN_COELUTION_SPECTRA` was the Session 7 example).
  - [x] **Stable sort on apex ranking**  -  `TestStableSortOnApexRanking` (Session 10)
  - [x] **Decoy collision exclusion**  -  `TestDecoyCollisionExclusion` (Session 10)
  - [x] **Iterative LDA refinement vs single-pass**  -  `TestIterativeLdaRefinement` (Session 10)

  **Session 9 bugs (main search features, 10 fixes)**:
  - [x] **Peak shape from ref XIC**  -  `TestPeakShapeFromRefXicNotComposite` (Session 10)
  - [x] **Trapezoidal area**  -  `TestPeakAreaTrapezoidal` (Session 10)
  - [x] **Peak sharpness as slope**  -  `TestPeakSharpnessIsSlope` (Session 10)
  - [x] **XCorr fragment bin dedup**  -  `TestXcorrFragmentBinDedup` (Session 10)
  - [x] **n_coeluting_fragments mean-positive**  -  `TestCoelutingFragmentsMeanPositive` (Session 10)
  - [x] **MS1 features HRAM-only**  -  `TestMs1FeaturesHramOnly` (Session 10)
  - [x] **Fragment matching closest-by-mz**  -  `TestLibCosineClosestByMz` (Session 10)
  - [x] **Median polish convergence**  -  `TestMedianPolishConvergenceAfterBothSweeps` (Session 10)
  - [x] **MS2 calibrated tolerance**  -  `TestMs2CalibratedTolerance` (Session 10)
  - [x] **Scan boundary order**  -  `TestScanBoundaryOrder` (Session 10)

### Documentation (new  -  Phase 2 addition)
- [ ] Create `pwiz_tools/OspreySharp/README.md` with:
  - Project overview, goals, relationship to Rust Osprey
  - Crate-to-project mapping (osprey-core -> OspreySharp.Core, etc.)
  - Build instructions (Visual Studio + MSBuild command line)
  - Testing instructions (unit tests + Stellar cross-impl runs)
  - **ASCII rendering** of the Osprey processing workflow (pipeline
    diagram)
  - Link to `Osprey-workflow.html` for the higher-fidelity figure
- [ ] Create `pwiz_tools/OspreySharp/Osprey-workflow.html` with:
  - **Inline SVG** rendering of the full Osprey processing pipeline:
    library load -> decoy generation -> calibration sampling -> pass-1
    scoring -> LDA -> LOESS -> pass-2 scoring -> Percolator -> FDR ->
    reconciliation -> blib output
  - Designed at paper-figure quality  -  could later be adapted into a
    figure for a publication about OspreySharp / the port / DIA peptide
    search in Skyline
  - Self-contained (no external CSS/JS dependencies) so it opens from
    any browser without network access

## Ideas / Future Work

- Skyline integration strategy: standalone EXE (like BlibBuild) vs pulling
  pieces into Skyline proper. Decide after the cross-impl fidelity walk is
  complete and performance is quantified on larger datasets.
- Protein-level FDR improvements (Mike flagged upstream as "needs work").
- Upstream-back-to-Osprey: decide which of our Rust-side changes are
  generally useful and worth PRing to `maccoss/osprey` (the f64 flip,
  diagnostic env vars, parquet_index fix if not already upstreamed).
- Publication figure: `Osprey-workflow.html` (see Documentation section)
  could seed a figure for a paper about the Rust->C# port methodology or
  DIA peptide search in Skyline.

## Progress Log

### 2026-04-11 Session 8 (desktop)  -  LDA drill-down and phase rollover

**Baseline verification**: Re-ran cal_match + pass-1 XIC entry 0 dumps after
rebuilding both binaries. Confirmed all Session 7 proofs still hold
(174,449/192,289 all-6-bit-equal = 90.72%; pass-1 XICs within 1e-10).

**Scan column gap closed**: The `scan` column in `cs_cal_match.txt` was
empty (intentional Session 7 TODO  -  "C# doesn't track scan number in
CalibrationMatch"). Session 8 added `ScanNumber` to `CalibrationMatch`,
populated from `apexSpectrum.ScanNumber` in `ScoreCalibrationEntry`, and
updated the dump writer. Now 192,289/192,289 apex scan numbers match
Rust bit-for-bit.

**LDA drill-down**: Added per-entry LDA score diagnostics
(`OSPREY_DUMP_LDA_SCORES=1` + `OSPREY_LDA_SCORES_ONLY=1`) writing
`{rust,cs}_lda_scores.txt` with 4 columns (entry_id, is_decoy,
discriminant, q_value), sorted by entry_id at F10 precision.

**Root cause found**: Not the hypothesized ULP drift on 14 entries at the
1% FDR cutoff. C#'s `CalibrationScorer.TrainAndScoreCalibration` is a
simplified non-iterative port. Rust's `train_lda_with_nonnegative_cv` does
Percolator-style iterative refinement (3-fold stratified CV, positive
training set selection, best-iteration tracking). **Every single one** of
the 192,289 discriminants differs (max |d| = 0.67, mean 0.36). Target 1%
FDR: Rust 11,937 vs C# 11,776 (-161), overlap 11,494, Rust-only 443,
C#-only 282.

**Osprey Rust CI cleanup**: Session 7's scratch diagnostic commit
(`2577e61`) was never `cargo fmt`'d or `cargo clippy`'d. Session 8
resolved fmt (~14 blocks in `batch.rs` + `pipeline.rs`), a
`needless_range_loop` clippy error in the grid dump, and a broken test
(`f32 -> f64` type annotation in `lib.rs`) left over from the f64 flip.

**Rolled phase**: Copied end-of-session TODO content to
`TODO-20260409_osprey_sharp-phase1.md` and replaced the main file with
this Phase 2 version. Future sessions should update this file's Progress
Log and leave phase1.md frozen.

**Iterative LDA port (continuation, same session)**: Rewrote
`CalibrationScorer.TrainAndScoreCalibration` to match Rust's
`train_lda_with_nonnegative_cv` line-for-line: baseline best-single-feature
selection, 3-fold stratified CV by peptide, positive training set selection
(`SelectPositiveTrainingSet` with Percolator-style FDR-relaxation cascade
at 5%/10%/25%/50%), consensus fold weight averaging with non-negative
clipping, best-iteration tracking across up to 3 iterations with
2-consecutive-no-improve early stopping. Added `Matrix.ExtractRows(int[])`
to `OspreySharp.ML/Matrix.cs`. Replaced local `CalculateQValues` helper
with canonical `QValueCalculator.ComputeQValues`. Fixed
`CompeteCalibrationPairs` sort tiebreak to match Rust (score desc, then
base_id ascending) - previously only primary score sort, which let
HashMap iteration order pollute winner ordering.

**LDA parity results** (after port, Stellar file 20):
```
discriminant   max |d| = 1.000e-10   bit-equal 192288/192289 (99.9995%)
q_value        max |d| = 0.000e+00   bit-equal 192289/192289 (100.0000%)
target 1% FDR  rust=11937  cs=11937  delta=0  full overlap (rust-only=0, cs-only=0)
```
Single ULP discriminant drift on one row is f64 sum non-associativity in
either `LinearDiscriminant.Fit` or `Predict` - not a real algorithmic gap.
cal_match features remain unchanged (regression check passed). All 167
OspreySharp unit tests still pass including the existing
`TestCompeteCalibrationPairs` (the base_id tiebreak change doesn't alter
its behavior - the test data has no score ties).

**LDA timing shift**: C# LDA went from 0.10s (single-pass) to 1.06s
(iterative 3 iterations x 3 folds). This is expected - Rust does the
same iterative work. The 10x step slowdown adds ~1s to the C#
wall-clock, not a showstopper for the Session 7 ~2.39x total gap.

**Commits**:
- pwiz `Skyline/work/20260409_osprey_sharp`:
  - `4328eb6de` - "Added apex scan number to cal_match diagnostic dump"
  - `a8d2b6ab7` - "Added per-entry LDA scores diagnostic dump"
  - `2704aa1ef` - "Ported iterative non-negative CV LDA refinement
    to CalibrationScorer"
- osprey `fix/parquet-index-lookup`:
  - `225f9db` - "Formatted and linted Session 7 scratch diagnostics"
  - `260852c` - "Added per-entry LDA scores diagnostic dump"
- ai `master`:
  - `a9ccf58` - "Rolled osprey_sharp TODO to phase 1 archive and
    started phase 2"

**LOESS walk-forward (continuation, same session)**:

Added OSPREY_DUMP_LOESS_INPUT diagnostic to both tools (writes sorted
(lib_rt, measured_rt) pairs at full-precision). Verified LOESS inputs
are bit-identical: 6,423/6,423 lib_rt 100% equal, 6,422/6,423
measured_rt bit-equal (1 row at 2 ULP -- noise floor).

**LOESS root cause found**: Inputs match, but LOESS fit stats diverged
by 1.7e-4 in r_squared (Rust 0.9577 vs C# 0.9576). Root cause:
Rust's `RTCalibrator::fit` captures residuals ONCE from the initial
fit and reuses them unchanged across all robustness iterations,
producing a single refinement. C#'s `LoessRegression.Fit` was
refreshing residuals per iteration (classical Cleveland 1979 robust
LOESS), producing a genuinely different 2-pass refinement. Fixed C#
to match Rust (residuals computed once) -> bit-identical on all 10
LOESS MODEL stats.

**LOESS classical-robust toggle added**: Both tools now support
`OSPREY_LOESS_CLASSICAL_ROBUST=1` env var to switch to classical mode
(residuals refreshed per iteration). This lets both tools be validated
against each other in EITHER mode, and the classical mode could be
proposed upstream to maccoss/osprey as a fix if the improvement is
deemed significant. Added `RTCalibratorConfig.ClassicalRobustIterations`
field (default false) plumbed through to `LoessRegression.Fit` in C# and
`RTCalibrator::fit` in Rust, set from the env var in both pipelines.

**Stable sort fix**: Switched `LoessRegression.Fit` and
`RTCalibrator.Fit` internal sorts from `Array.Sort` (introsort,
unstable) to LINQ `OrderBy` (stable), matching Rust's
`slice::sort_by`. Didn't change behavior on Stellar data (no
duplicate lib_rt values in the 6,423-point set), but is the correct
defensive pattern for data with multi-charge peptides that share a
library RT.

**Additional commits** (Session 8 continuation):
- pwiz `Skyline/work/20260409_osprey_sharp`:
  - `773791a4b` - "Added OspreySharp README.md and workflow HTML figure"
  - `b3855fb96` - "Matched Rust LOESS robust iteration + added input
    diagnostic"
  - `8cc3f86fb` - "Added classical robust LOESS toggle
    (OSPREY_LOESS_CLASSICAL_ROBUST)"
- osprey `fix/parquet-index-lookup`:
  - `f1da6da` - "Added LOESS input pair diagnostic dump"
  - `3a3efbd` - "Added classical robust LOESS toggle
    (OSPREY_LOESS_CLASSICAL_ROBUST)"

**Next**: Verify broader pass-2 XIC (multiple entries), then move to
Stage 4 (main first-pass search, 21 PIN features per entry). The
calibration phase (Stage 3) is essentially complete -- all upstream
stages through pass-1 LOESS are bit-identical, and pass-2 entry 0 is
confirmed. Remaining calibration work is a confidence-building
exercise across more entries.

**Session 9 handoff**: For detailed startup protocol (skills to load,
commit verification, approach for Stage 4, test data paths, build
commands, diagnostic env vars, gotchas), read
`ai/.tmp/handoff-20260411-osprey-sharp-session8.md` before starting work.

### 2026-04-11 Session 9 (desktop)  -  RT tolerance fix + resolution mode discovery

**CRITICAL: `--resolution unit` is required for Stellar (and possibly Astral)**

Session 9 discovered that the Stellar test runs were producing ~986
precursors instead of the expected ~36K. Both our fork AND upstream
maccoss/osprey (v26.1.2, commit `1302c90`) produced the same low count.
Root cause: the Session 3 reference used `--resolution unit` per Mike's
original instructions, but our bisection runs omitted this flag and used
the default `resolution_mode: Auto`.

Running with `--resolution unit --protein-fdr 0.01` (Mike's exact flags)
restores the expected results:
```
Fork (clean Session 8 code):  36,703 precursors / 33,960 peptides / 5,608 proteins
Session 3 reference:          36,783 precursors / 33,966 peptides / 5,604 proteins
Upstream maccoss/osprey:      986 precursors (also missing --resolution unit)
```
Small delta vs Session 3 is expected (Percolator SVM is non-deterministic).

**Upstream baseline established**: Cloned `maccoss/osprey` HEAD (`1302c90`,
v26.1.2) to `C:\proj\osprey-mm`. Confirmed it produces the same result
as our fork when both use the same flags. The upstream repo can serve as
a regression baseline independent of our changes.

**RT tolerance divergence found (C# vs Rust)**:
- Rust `run_search`: global tolerance `3 * MAD * 1.4826`, clamped [min, max]
- C# `ScoreCandidate`: per-entry `LocalTolerance` (interpolated residuals)
- C# also missing `MaxRtTolerance` cap
- Fix written (stashed): replace per-entry tolerance with global MAD-based
  calculation matching Rust. Also added `OSPREY_DIAG_SEARCH_ENTRY_IDS`
  diagnostic to both tools for main-search XIC validation.
- Changes stashed during resolution-mode investigation: `git stash pop` in
  both `pwiz` and `osprey` repos to restore.

**Test commands** (from Mike's README notes, must always use these flags):
```bash
# Stellar (3 files, unit resolution)
osprey -i *.mzML -l hela-filtered-SkylineAI_spectral_library.tsv \
  -o stellar-ospreyoutput.blib --resolution unit --protein-fdr 0.01
# Expected: ~36K precursors / ~34K peptides / ~5.6K proteins

# Astral (3 files, also unit resolution per Mike - TBD if HRAM is better)
osprey -i *.mzML -l hela-filtered-SkylineAI_spectral_library.tsv \
  -o astral-ospreyoutput.blib --resolution unit --protein-fdr 0.01
# Expected: ~144K precursors / ~126K peptides / ~13.5K proteins
```

**Test data**: `D:\test\osprey-testfiles\stellar\` (source), copied to
`D:\test\osprey-runs\stellar\` (working). Upstream test data at
`D:\test\osprey-mm\stellar\`.

**Session 9 commits**:
- pwiz `Skyline/work/20260409_osprey_sharp`:
  - `263f15123` - Aligned main-search XIC extraction with Rust
  - `0cc5161b2` - Fixed peak shape features and xcorr bin double-counting
  - `91515db2a` - Matched all 21 PIN features with Rust
  - `ef1802c27` - Updated workflow figure: Stages 1-4 all green
- osprey `fix/parquet-index-lookup`:
  - `10c42cc` - Added OSPREY_DIAG_SEARCH_ENTRY_IDS diagnostic
  - `97a369d` - Added median polish diagnostic dump and peak boundary data
- ai `master`:
  - `70448ce` - Updated Session 9 progress
  - `bc0ebc0` - Corrected bisection order
  - `ca96b65` - Added OspreySharp build, test, and run scripts
  - `13892ee` - Session 9: all 21 PIN features matched

**Session 10 handoff**: For detailed startup protocol (upstream merge
plan, regression test approach, build commands, diagnostic env vars),
read `ai/.tmp/handoff-20260412-osprey-sharp-session9.md` before
starting work.

### 2026-04-12 Session 10 (desktop)  -  Upstream merge + test coverage audit

**Upstream merge completed**: Rebased fork's `fix/parquet-index-lookup`
onto `maccoss/osprey` HEAD (`4ec7dda`, v26.1.3). Dropped 2 parquet_index
fix commits (superseded by upstream's comprehensive fix with regression
tests). Cherry-picked 7 diagnostic commits cleanly (2 trivial conflicts
in `pipeline.rs`  -  comment wording only). `main` fast-forwarded to
upstream HEAD. Both branches pushed to `brendanx67/osprey`.

**Upstream now at v26.1.3** (was v26.1.2 in Session 9 handoff). New
since our base: reconciliation tolerance bug fix (v26.1.3), apex
proximity reconciliation (v26.1.2), progress bars, two-tier logging,
parquet_index regression tests. Stellar 3-file count jumped from ~36K
to 49,770 precursors  -  this is upstream improvement (reconciliation fix
recovers more precursors), not a regression.

**Session 9 SG-weighted fixes applied** (from parallel session):
- `sg_weighted_cosine`: C# LibCosine wasn't filtering by spectrum m/z
  range (Rust `compute_cosine_at_scan` does). Added
  `ComputeCosineAtScan` in `AnalysisPipeline.cs`.
- `sg_weighted_xcorr`: C# SG loop used global window indices that could
  escape the RT-filtered candidate range. Fixed to use candidate-local
  indices bounded by rangeLen.
- pwiz `22c24af6b`, osprey `085ce53`.

**Full pipeline re-validation**: `Test-StellarFeatures.ps1` confirms all
21 features at 0.00% divergence across 311,297 matched entries with
shared calibration on the rebased fork. Rust CI: 354 tests pass, fmt
clean, clippy clean. C#: 167 tests pass.

**Test coverage audit completed**: Mapped all 167 existing unit tests to
the 8-stage Osprey workflow (see Osprey-workflow.html). Key findings:

Existing tests cover **data structure mechanics** well (serialize,
compute a matrix product, generate a decoy) but almost entirely miss
**algorithmic fidelity** (does the computation produce the right answer
for the right reason?). Every bug found in Sessions 5-9 was in code that
had "passing" unit tests but computed the wrong thing:
- Stage 1 (library prep): 36 tests  -  well covered
- Stage 2 (mzML): 3 tests  -  light but adequate
- Stage 3 (calibration): 31 tests  -  DECEPTIVE (looks good, misses all
  Session 5-8 bugs: xcorr normalization, SNR buffer, apex tie-break,
  LOESS robust mode, MS2 calibrated tolerance, iterative LDA)
- Stage 4 (main search): 2 tests  -  MAJOR GAP (18 of 20 bug-prone
  features have no tests)
- Stage 5 (FDR): 18 tests  -  good structural coverage
- Stage 6 (refinement): 0 tests  -  not yet ported
- Stage 7 (protein FDR): 7 tests  -  reasonable
- Stage 8 (output): 9 tests  -  OK

**Next**: Write regression tests for the 18 Session 5-9 bugs, starting
from Stage 3 (calibration) and Stage 4 (main search features) where the
gap is widest. Annotate Osprey-workflow.html with unit test coverage
markers as tests are added.

**Session 10 commits**:
- pwiz `Skyline/work/20260409_osprey_sharp`:
  - `64fbbb03a` - Added 9 regression tests (batch 1)
  - `e85eb4e2f` - Added 6 more regression tests (batch 2)
  - `d1f2d5255` - Completed all 18 regression tests (batch 3)
  - `abdd60b9a` - Added CWT fallback peak detection and signal prefilter
  - `6877858cd` - Wired library binary cache and parallel decoy generation
- osprey `fix/parquet-index-lookup`:
  - Rebased 7 diagnostic commits onto upstream/main `4ec7dda` (v26.1.3)
  - `0cbbccd` - Added 5 cross-implementation Rust regression tests
- ai `master`:
  - `e31eb1d` through `8f14da8` - TODO updates, benchmark/profiling scripts

**Stage 4 completion** (Session 10): Added three-tier CWT fallback peak
detection (CWT consensus -> median polish elution -> ref XIC) and signal
prefilter (2/6 top fragments in 3/4 consecutive scans). Entry count gap
closed from 13,840 to 23 out of 466K. All 21 features still pass on
317,630 matched entries.

**Performance baseline established** (Session 10): Ground-truth benchmark
with `Bench-Scoring.ps1` (warmup + 3 iterations, median, consistency
check). C# Stages 2-4: 77.2s vs Rust 20s = 3.9x. Target: under 2x.
dotTrace profiling script ready at `ai/scripts/OspreySharp/Profile-OspreySharp.ps1`.

**Final perf table** (Session 10, with server GC + parallel files):

```
Single file (server GC):
                          Stage 1  Stage 2  Stage 3  Stage 4  Stg 1-4
Fork Rust                   4.5s     5.0s     9.0s     5.0s    24.5s
OspreySharp (C#)            0.7s     5.5s    10.4s     4.0s    21.9s
C# / Rust ratio             0.2x     1.1x     1.2x     0.8x     0.9x

3-file parallel (server GC):
Fork Rust (sequential)                                          93.5s
OspreySharp (Parallel.For)                                      51.5s
C# / Rust ratio                                                 0.55x
```

Session 10 brought C# from **3.3x slower to 0.9x faster** (single file)
and **0.55x on 3-file parallel** (C# is 1.8x faster than Rust).

Key findings:
- Server GC (`gcServer enabled="true"`) nearly halved every stage
  vs workstation GC  -  the single biggest performance factor
- Rust calibration uses the SAME per-entry XIC approach (not batch
  matrix scoring as assumed)  -  the `run_windowed_calibration_scoring`
  batch path exists but is unused by the pipeline
- mzML reader is native C# XmlReader (not ProteoWizard COM bridge)
- Rust file processing is sequential  -  parallel files is a feature to
  PR upstream to maccoss/osprey (needs loop body extraction + rayon)
- Skyline's `MultiFileLoader.GetBalancedThreadCount` algorithm
  optimizes file parallelism: half physical cores, reduce to avoid
  idle threads in final batch, cap at 12 (server GC) or 3 (workstation)

**Session 10 pwiz commits** (performance optimization):
- `abdd60b9a` - CWT fallback peak detection + signal prefilter
- `6877858cd` - Library binary cache + parallel decoy generation
- `ea8cba515` - Pre-preprocessed XCorr per window (Stage 4: 30.7s -> 9.6s)
- `38b86c488` - Calibration XCorr cache
- `3ecd576fa` - Calibration prefilter optimization (LINQ -> binary search)
- `2d5177be6` - Fixed calibration XCorr cache window key resolution
- `010ce1b4d` - Updated workflow figure with badges
- `5c70d657e` - Parallel mzML decompression
- `ded71b5a3` - Producer-consumer mzML pipeline
- `38a4578cb` - Cached top-6 fragment m/z per entry

**Session 10 additional pwiz commits** (performance + parallel):
- `947a1dbe8` - Parallel file processing + server GC (0.9x single, 0.55x 3-file)

**Next session handoff**: For detailed startup protocol (build commands,
perf baselines, Rust parallel files plan, Stages 5-8 approach), read
`ai/.tmp/handoff-20260413-osprey-sharp-session10.md` before starting work.

### 2026-04-14 Session 11 (desktop)  -  HRAM unblock, XCorr dedup bug, honest validation

**HRAM/Astral crash root cause**: C# calibration was hanging for minutes
on Astral's single file (204K MS2 spectra). Root cause: Session 10's
XCorr per-window pre-preprocessing optimization allocates `double[NBins]`
per spectrum. For unit resolution (NBins=2,000) that's ~16 KB/spectrum =
~3 GB total and fine. For HRAM (NBins=100,001) it's ~800 KB/spectrum =
**~160 GB total**, causing catastrophic allocation pressure.

Fix: introduced `IResolutionStrategy` in `OspreySharp.Scoring` with
`UnitStrategy` (keeps pre-preprocessing) and `HramStrategy` (returns null;
XCorr falls back to inline `XcorrAtScan` per scan). Also added
`ScoringContext` bundling `(Config, Resolution, FileName)` per-file so
pipeline methods never need to check `ResolutionMode` directly again.
All 185 OspreySharp unit tests still pass; Stellar Stage 1-4 perf
unchanged at ~0.99x Rust. Astral calibration pass 1 now completes in
88s (was unbounded).

**MS1 feature port** (continuation of pre-session work on HRAM): ported
`osprey-core/src/isotope.rs` as `IsotopeDistribution.cs` (polynomial
expansion over C/H/N/O/S natural abundance), replaced the averagine
approximation. `ComputeMs1Features` rewritten to use the reference XIC
(not summed fragment XIC) for coelution, apply MS1 calibrated tolerance
via `reverse_calibrate_mz`, and gate isotope cosine on `envelope.has_m0()`
-- all matching Rust pipeline.rs:5362-5404.

**Test-Features.ps1 honest-validation rewrite**: previous default used
shared calibration (C# loading Rust's `calibration.json` via
`OSPREY_LOAD_CALIBRATION`), which short-circuited calibration scoring.
Useful as a Session 9 bisection tool but **hid all divergence in the
calibration phase from Sessions 9-10 testing**. Rewrote defaults:
- Each tool computes its own calibration (honest).
- Both tools exit after Stage 4 via `OSPREY_EXIT_AFTER_SCORING=1`
  (apples-to-apples wall-clock timing; skips Mokapot/blib).
- `-SharedCalibration` opt-in flag preserves the old bisection mode.

Added `OSPREY_EXIT_AFTER_SCORING` env var to Rust to match
(pipeline.rs: returns after per-file scoring loop, before FDR).

**XCorr dedup bug in Rust**: pipeline walk with each tool's own
calibration revealed the `xcorr` column in `cal_match` dumps had
23,238/192,289 entries diverging by >1e-6 (max |d|=0.81) while every
other column was bit-identical at 1e-10 ULP. Traced to Rust having
**two inconsistent XCorr code paths**:

- `SpectralScorer::xcorr_from_preprocessed` (used by coelution
  `best_xcorr` via `preprocess_library_for_xcorr` setting
  `binned[bin] = 1.0`): implicit dedup, correct.
- `SpectralScorer::xcorr()` + `xcorr_at_scan()` (used by `cal_match`
  diagnostic dump's `xcorr_score` field and several other callers):
  sums preprocessed values at every fragment bin position. Two
  fragments hitting the same bin double-counts.

Session 9's `0cc5161b2` added `visitedBins` dedup to C#'s
`XcorrFromPreprocessed` (the correct Comet-style behavior). The Rust
side was never updated. Shared-calibration testing never exercised
`scorer.xcorr()`, so this went undetected.

Fixed both Rust methods to dedup. After fix: cal_match ALL 7 columns
bit-identical at 1e-10 ULP (Session 7's claim restored). Downstream
(LDA scores, LOESS input) also bit-identical.

**Upstream candidate**: this dedup fix is worth sending to
`maccoss/osprey`. Jimmy Eng (original XCorr author, same building at UW)
should weigh in -- the non-deduped `scorer.xcorr()` is in a module
comment claiming to "match Comet exactly", but Comet's theoretical
spectrum uses unit intensity per bin, not accumulated per-fragment.

**Remaining drift root cause: Math.Round banker's rounding in
PercentileValue**. After the xcorr dedup fix the pipeline walk showed
pass-2 LOESS stats all bit-identical EXCEPT MAD (9e-5 drift), which
cascaded to tolerance (4e-4 drift), then to expected_rt (~6e-4 drift),
then to every downstream `mass_accuracy` and `rt_deviation`. Root cause
was a one-line rounding-mode mismatch:

- Rust `percentile_value`: `(p * (n-1)).round()` -- round half away
  from zero (IEEE 754 `f64::round()`).
- C# `PercentileValue`: `Math.Round(p * (n-1))` -- banker's rounding
  (round half to even) by default.

For n=6398 and p=0.50: 3198.5 rounds to 3199 in Rust, 3198 in C# --
picking adjacent sorted absolute residuals that differed by 9e-5.
p20 (idx 1279.4) and p80 (idx 5117.6) don't hit the .5 boundary so they
both stayed bit-identical, which is why the drift was so narrow. Fixed
C# to `MidpointRounding.AwayFromZero`.

**Pipeline walk status after Session 11** (Stellar, own calibration,
all stages bit-identical at ULP):

| Stage | Divergence |
|-------|------------|
| Cal sample (library targets) | 0 |
| Cal scalars / grid | 0 (formatting only) |
| Cal match (all 7 columns) | max 5e-10 (ULP) |
| LDA scores | max 1e-10 (ULP) |
| LOESS input | max 9e-16 (machine epsilon) |
| Pass-2 LOESS model (all 10 stats) | 0 (bit-equal) |
| Main search `expected_rt` | 0 (bit-equal) |
| 21 PIN features | all PASS at 1e-6 threshold, max drift <1e-14 |

The `Test-Features.ps1 -Dataset Stellar` honest validation (own
calibration, Stage 1-4 only) now returns ALL 21 FEATURES PASSED with
max divergence 1e-11 on `rt_deviation` and 0 on `mass_accuracy`. This
is the Session 7-level bit-identical parity that was always the
target; shared-calibration testing was masking real drift introduced
by two separate bugs (Rust xcorr dedup + C# banker's rounding).

**Session 11 commits**:
- osprey `fix/parquet-index-lookup`:
  - `4db625c` - Fixed XCorr fragment bin dedup and added scoring-only
    early exit
- pwiz `Skyline/work/20260409_osprey_sharp`:
  - Single amended commit adding IResolutionStrategy, ScoringContext,
    HRAM pre-preprocessing skip, MS1 calibration load, sequence-based
    isotope cosine, and PercentileValue rounding-mode fix
- ai `master`: (this TODO + Test-Features/Run-Osprey/Dataset-Config
  rename + Bench-Scoring generalization + README)

**Next**: (a) repeat the pipeline walk on Astral HRAM data now that the
crash is fixed and Stellar parity is restored, (b) PR the xcorr dedup
fix upstream to `maccoss/osprey`, (c) add a regression test for the
banker's-vs-away-from-zero percentile rounding so future C#/Rust ports
catch this reflexively.

## Next Sprint: Upstream Merge + Regression Tests

### Priority 1: Merge upstream maccoss/osprey into our fork  -  DONE (Session 10)

- [x] **Diff our fork vs upstream**: compared `brendanx67/osprey`
      `fix/parquet-index-lookup` against `maccoss/osprey` HEAD (`4ec7dda`,
      v26.1.3). Common ancestor `bc51ca9`. Upstream: 25 new commits
      (v26.1.0-v26.1.3, parquet fixes, reconciliation fix, logging).
      Ours: 9 commits (2 parquet fixes + 7 diagnostics).
- [x] **Merge upstream into fork**: rebased 7 diagnostic commits on top
      of upstream/main HEAD (`4ec7dda`). Dropped 2 parquet_index fixes
      (`dfe5f9e`, `2812401`) - superseded by upstream's comprehensive
      `464a601` + `1293ddf` + `80c94c7` (with regression tests).
      Only conflict: comment wording in `pipeline.rs` (2 hunks, trivial).
- [x] **Push to fork**: `main` fast-forwarded, `fix/parquet-index-lookup`
      force-pushed with `--force-with-lease`.
- [x] **Re-test Stellar 3-file**: Rust v26.1.3 now produces 49,770
      precursors / 45,596 peptides / 6,603 proteins (up from ~36K -
      upstream v26.1.3 reconciliation fix recovers more precursors).
- [x] **Re-verify PIN features**: Test-StellarFeatures.ps1 confirms all
      21 features at 0.00% divergence across 311,297 matched entries
      with shared calibration on the rebased fork.
- [x] **Rust CI checks**: `cargo fmt --check` clean, `cargo clippy
      -D warnings` clean, 354 unit tests pass.
- [x] **C# unit tests**: all 167 pass.

### Priority 2: Regression unit tests (OspreySharp C#)

Write fast unit tests for every bug found in Sessions 5-9 (see the
regression test checklist above). Each test:
- Uses synthetic data (no Stellar dataset dependency)
- Would have FAILED against the pre-fix implementation
- Runs in < 100ms
- Covers both the correct and incorrect behavior
Target: ~18 new tests covering all items in the checklist.

### Priority 3: Regression tests for Rust Osprey

Give back to Mike: contribute Rust unit tests that guard the same
code paths, particularly:
- [ ] XCorr bin dedup (fragments sharing a bin)
- [ ] Median polish convergence criterion
- [ ] Fragment matching closest-by-mz consistency
- [ ] n_coeluting mean-positive definition
- [ ] Calibrated tolerance computation from MzCalibration stats
These can be submitted as a PR to maccoss/osprey after the merge.
