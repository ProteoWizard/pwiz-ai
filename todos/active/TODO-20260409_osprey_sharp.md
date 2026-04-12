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

## Current State (end of Phase 1, start of Phase 2)

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

**Not yet proven** (next downstream targets):
- Pass-1 LOESS fit coefficients (should now match after LDA parity)
- Pass-2 XIC extraction on other entries (only entry 0 tested)
- Main first-pass search (21 PIN features per entry)
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
- [ ] Pass-2 XIC on 10-20 entries via `OSPREY_DIAG_XIC_ENTRY_ID`  -  confirm
      pass-2 bit-identicality is broad, not lucky on entry 0
- [ ] Main first-pass search features  -  `.cs_features.tsv` via
      `AnalysisPipeline.WriteFeatureDump` vs matching Rust dump; 21 PIN
      features per entry
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

Session 7 perf snapshot on Stellar file 20 to cal_match exit: **C# 40.6s
vs Rust 17.0s = 2.39x wall clock**. Per-phase: library load 8.4s vs 0s
(C# has no binary cache wired), mzML parse 14.2s vs ~6s (ProteoWizard
wrapper interop), pass-1 scoring 15.7s vs ~4s (3.93x slower). **Shipping
a C# tool that is ~2-3x slower than the Rust reference is not an
acceptable final state.** Target: within ~1.5x wall clock on the same
hardware after correctness is proven.

- [ ] **Wire `LibraryBinaryCache.cs` into the pipeline**: the class exists
      in `OspreySharp.IO` but `AnalysisPipeline` re-parses the DIA-NN TSV
      on every run. Expected saving: ~8s per run on Stellar (library load
      drops from 8.4s to near-zero on warm cache).
- [ ] **Profile pass-1 scoring hot loop** to identify the 3.93x gap:
      likely contributors are managed f64 math with no auto-vectorization
      (vs Rust LLVM autovec), per-entry CWT convolution, and XCorr
      preprocessing. Use BenchmarkDotNet + dotTrace to attribute cost.
- [ ] **SIMD / vectorize CWT convolution** via `System.Numerics.Vector<T>`
      or `System.Runtime.Intrinsics` (AVX2/AVX-512 where available).
- [ ] **Math.NET Numerics + MKL provider for LDA/SVM training**
      (see Core port carry-over) - replaces managed dense-matrix loops in
      LinearDiscriminantAnalysis / LinearSvmClassifier with MKL-backed
      routines equivalent to Rust's ndarray + BLAS.
- [ ] **Parallel preprocessing** match: verify OspreySharp's
      `Parallel.ForEach` window-processing loop has the same parallelism
      grain as Rust's `par_iter`.
- [ ] **Evaluate mzML parse path**: 2.37x slower is interop overhead
      (pwiz_data_cli COM bridge). Not worth optimizing until everything
      else is within target - reusing ProteoWizardWrapper was a
      scaffolding decision we accept unless measurement proves otherwise.
- [ ] **Re-run perf snapshot** after each major performance change and
      record in the progress log. Final perf table must show C# vs Rust
      within the 1.5x target on both Stellar and Astral datasets before
      the project is considered done.

### Regression test coverage (new  -  Phase 2 addition)

**Context**: All OspreySharp unit tests (~161 tests across Core, ML, IO,
Chromatography, Scoring, FDR) were passing before Session 5's end-to-end
validation began  -  and then Sessions 5-8 uncovered many serious port errors
that the unit tests did not catch. The unit-test-green state was a **false
sense of security**. Phase 2 adds targeted regression tests designed to fail
against the pre-fix implementation of each bug class, so future ports do not
repeat the same mistakes.

- [ ] Write regression tests (each must be fast, no full Stellar dataset)
      for the following Session 5-8 lessons:
  - [ ] **XCorr windowing normalization**  -  max-bin vs sum-bin, missing
        Comet MakeCorrData windowing, library-intensity-weighted vs
        sum-at-fragment-positions. Fixture: synthetic spectrum + known
        library with a hand-computed reference xcorr.
  - [ ] **SNR input buffer**  -  must use ref_xic, not composite sum of all
        fragment XICs. Fixture: two-fragment synthetic XIC with known
        reference.
  - [ ] **Apex selection tie-break**  -  ties must resolve LAST-wins to match
        Rust `Iterator::max_by`. Fixture: flat intensity plateau across
        multiple scans.
  - [ ] **f32 vs f64 intermediate precision drift**  -  XCorr sliding window
        produces ~4e-6 drift when f32 buffers are used. Fixture:
        sliding-window accumulator test comparing f32 vs f64 result on
        deterministic input.
  - [ ] **Constant mismatches**  -  regression test that detects when shared
        named constants in Osprey and OspreySharp diverge
        (`MIN_COELUTION_SPECTRA` was the Session 7 example).
  - [ ] **Stable sort on apex ranking**  -  `List<T>.Sort` is unstable;
        LINQ `OrderBy`/`OrderByDescending` is stable. Fixture: inputs with
        many ties; compare against Rust `sort_by` result recorded inline.
  - [ ] **Decoy collision exclusion**  -  targets whose reversed sequence
        matches another target must be excluded. Fixture: tiny library
        with 1 known cross-target collision.
  - [ ] **Iterative LDA refinement vs single-pass**  -  run
        `TrainAndScoreCalibration` on a small synthetic match set with
        known scores and verify it selects the iteration with the best
        training-set 1% FDR count, not the last iteration.

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

**Next**: Walk downstream from LDA to pass-1 LOESS fit. Extend the
pass-2 XIC diagnostic to include LOESS predictions across a sampled
RT range and diff against Rust - expectation is bit-identicality
since pass-1 LDA (upstream) is now matching.
