# TODO-20260409_osprey_sharp.md

## Branch Information
- **Branch**: `Skyline/work/20260409_osprey_sharp`
- **Base**: `master`
- **Created**: 2026-04-09
- **Status**: In Progress
- **GitHub Issue**: (pending)
- **PR**: (pending)

## Objective

Port Mike MacCoss's **Osprey** (Rust DIA peptide-centric search tool) to C# as
**OspreySharp** within `pwiz_tools/OspreySharp/`. The goal is a C# implementation
that performs comparably to the Rust original but is accessible to the Skyline team
for integration and reuse.

### Why pwiz_tools?

- `pwiz_data_cli.dll` / `ProteoWizardWrapper.dll` for mzML + vendor format reading
- `pwiz_tools/BiblioSpec` for blib read/write (reference implementation)
- `pwiz_tools/Shared` for common dependencies (SQLite, etc.)
- Boost Build system already in place
- Precedent: Bumbershoot (myrimatch, idpicker), Topograph, BiblioSpec
- Natural staging area for Skyline integration (like BlibBuild.exe / BlibFilter.exe)

### Reference implementation

- **Osprey source**: `C:\proj\osprey` (github.com/maccoss/osprey, branch `main`)
- **Crate-to-namespace mapping**: Each Rust crate maps to an OspreySharp namespace/project.
  References to the Rust source (e.g., `osprey-fdr/src/percolator.rs`) help Mike trace
  between the two implementations during active development.
- **Test oracle**: Osprey builds and passes 335 unit tests on this machine.
  End-to-end validation pending Mike's test data (downloading from Panorama).

### Key constraints

- Back-references to the Osprey Rust source are helpful for traceability during the
  active port. These can be cleaned up once OspreySharp is established on its own.
- Tests are the load-bearing spec — Osprey's 335 unit tests + end-to-end outputs
  on real data are the validation target.
- Numerical reproducibility vs Osprey: statistically equivalent (same peptide detections,
  same q-values within ~1e-4), not necessarily bit-identical.

## Completed Tasks

- [x] Clone and evaluate Osprey project (7 Rust crates, 335 tests, rich docs)
- [x] Install Rust toolchain (1.94.1 MSVC), CMake 4.3.1, vcpkg, OpenBLAS 0.3.29
- [x] Build Osprey from source (`cargo build --release`, 3m 55s)
- [x] Pass all 335 unit tests (0 failed, 2 ignored)
- [x] Run end-to-end smoke test on real DIA mzML (pipeline works, 0 detections due
      to library mismatch — Tutorial_DIA.blib was proteome library, not PROCAL)
- [x] Pull Mike's latest bug fixes (2026-04-09, 13 files changed)
- [x] Create pwiz branch `Skyline/work/20260409_osprey_sharp`

## In Progress

- [x] Download Mike's test data from Panorama (Astral + Stellar datasets, HeLa library)
- [x] Rebuild Osprey with latest changes and rerun tests (335 pass)
- [x] Fix parquet_index bug in Osprey's second-pass FDR (see below)
- [x] Fix parquet_index initialization bug in fresh scoring path (see Session 3 below)
- [x] Run Osprey on Stellar dataset (36,783 precursors, 33,966 peptides, 5,604 proteins at 1% FDR)
- [x] Run Osprey on Astral dataset (143,622 precursors, 125,609 peptides, 13,482 proteins at 1% FDR)
- [x] Scaffold `pwiz_tools/OspreySharp/` solution structure

## Remaining Tasks

### Phase 1: Project Setup
- [x] Create `pwiz_tools/OspreySharp/` .NET solution mirroring Osprey's 7-crate layout
- [ ] Set up project references to Shared, BiblioSpec, pwiz_data_cli
- [ ] Developer setup doc (`docs/dev-setup.md`) — Rust reference oracle + C# build

### Phase 2: Core Types & Infrastructure
- [x] Port `osprey-core/src/types.rs` → core types (20 files, 14 tests)
- [x] Port `osprey-core/src/config.rs` → OspreyConfig + config types (5 files, 7 tests)
- [x] Port `osprey-ml` → SVM, Matrix, PEP, Q-values, LDA (7 files, 39 tests)
- [ ] Set up Math.NET Numerics + MKL provider for BLAS (deferred to perf phase)

### Phase 3: I/O (leverage existing pwiz infrastructure)
**REVIEW GATE**: Before writing I/O code, survey and wire up existing pwiz infrastructure.
Do NOT straight-port the Rust I/O — wrap existing pwiz_tools/Shared libraries instead.

- [ ] **Pre-I/O review**: Add project references to CommonUtil, BiblioSpec, ProteowizardWrapper
- [ ] **Chemistry integration**: Replace IsotopeEnvelope with Shared/CommonUtil/Chemistry
  (Molecule, AminoAcidFormulas, MassDistribution). OspreySharp MUST calculate masses
  and isotope distributions identically to Skyline — use the same code, not a port.
- [x] DIA-NN TSV library reader (column variants, mod parsing, grouping, 2 tests)
- [x] elib library reader (two schema variants, SQLite, bracket notation)
- [x] blib library reader (zlib decompression, mod identification, 2 tests)
- [ ] mzML reader (wrap pwiz_data_cli.dll via ProteoWizardWrapper — deferred to pipeline)
- [x] blib writer (full schema, peak compression, mods, proteins, RTs, 8 tests)
- [x] Library deduplication (best-per-precursor, sequential IDs, 4 tests)
- [x] Library binary cache (round-trip, versioning, 3 tests)
- [x] Spectra binary cache (MS1+MS2, round-trip, 2 tests)
- [ ] Parquet caching (deferred — evaluate need for C# port vs direct file I/O)

### Phase 4: Algorithms
- [x] LOESS regression (port, 8 tests — placeholder for Shared/Common/LoessInterpolator)
- [x] CWT peak detection (Mexican Hat, consensus median, 13 tests)
- [x] RT/mass calibration (LOESS fitting, outlier removal, mz stats, JSON I/O, 17 tests)
- [x] Decoy generation (enzyme-aware reversal, cycle fallback, 8 tests)
- [x] Spectral scoring: XCorr, LibCosine, BatchScorer, CalibrationScorer (10 tests)
- [x] Pearson correlation, coelution sum helpers (5 tests)
- [x] FdrController: target-decoy competition, q-values, filtering (11 tests)
- [x] Percolator SVM FDR: 3-fold CV, grid search, dual-level q-values (7 tests)
- [x] Protein parsimony + picked-protein FDR (8 tests)

### Phase 5: Pipeline & CLI
- [ ] **Pre-pipeline review**: Verify threading patterns (ActionUtil.RunAsync),
  progress reporting, and cancellation follow Skyline conventions
- [ ] Pipeline orchestration (port `osprey/src/pipeline.rs`)
- [ ] CLI entry point (port `osprey/src/main.rs`)
- [ ] End-to-end validation vs Osprey on Mike's test data

### Phase 6: Performance & Validation
- [ ] Benchmark C# vs Rust on Astral + Stellar datasets
- [ ] Profile hot paths (batch scoring, BLAS, mzML parsing)
- [ ] Validate on larger experiments (100+ file) on desktop/server hardware
- [ ] **Skyline integration review**: Check for duplicated utilities from pwiz.Common,
  patterns that conflict with Skyline integration, naming consistency
- [ ] Evaluate Skyline integration: standalone EXE vs pull pieces into Skyline

## Context

### Mike's test data (from email 2026-04-09)
- Location: https://panoramaweb.org/MacCoss/maccoss/Shared_w_lab/project-begin.view?pageId=Raw%20Data
  folder "osprey-testfiles"
- Files: mzML files + `hela-filtered-SkylineAI_spectral_library.tsv` (DIA-NN format,
  ~1.5M peptides for Astral)
- Astral command: `osprey -i *.mzML -l hela-filtered-SkylineAI_spectral_library.tsv -o astral-ospreyoutput.blib --protein-fdr 0.01`
- Stellar command: `osprey -i *.mzML -l hela-filtered-SkylineAI_spectral_library.tsv -o stellar-ospreyoutput.blib --resolution unit --protein-fdr 0.01`
- Stellar data is faster; Astral has ~1.5M peptide library
- Protein-level FDR still needs work per Mike; peptide/precursor level is good
- Also includes a fasta for easier Skyline import

### Osprey build environment (on this laptop)
- Rust 1.94.1 (MSVC), CMake 4.3.1, vcpkg + OpenBLAS 0.3.29
- Build notes: `ai/.tmp/osprey-build-setup-notes.md`
- Windows README says `OPENBLAS_PATH` but CI actually uses vcpkg (README is stale)

### Related
- **Carafe**: grad student project (MacCoss + Noble labs), Java + Python, PR #3549 on pwiz
  — integration point, not port target

## Handoff Notes (from 2026-04-09 session)

### Building and running Osprey (the Rust reference oracle)

The Rust toolchain is installed but **not on the default Git Bash PATH**. Every
`cargo` invocation needs these exports:
```bash
export VCPKG_ROOT="$USERPROFILE/vcpkg"
export PATH="$USERPROFILE/.cargo/bin:/c/Program Files/CMake/bin:$USERPROFILE/vcpkg/installed/x64-windows/bin:$PATH"
```
The last PATH entry (`vcpkg/.../bin`) is for `openblas.dll` at runtime. Without it,
`osprey.exe` fails with "cannot open shared object file: openblas.dll".

Build + test:
```bash
cd C:/proj/osprey
cargo build --release    # ~4 min first time, ~30s incremental
cargo test --release     # 335 pass, 2 ignored, ~10s
```

### Windows build gotchas discovered this session

1. **Osprey README says `OPENBLAS_PATH`; CI uses vcpkg.** The README's "set
   OPENBLAS_PATH" instructions don't work on Windows — `openblas-src` 0.10's
   `system` feature uses vcpkg, not a custom env var. The CI workflow
   (`.github/workflows/ci.yml:46`) is the source of truth. Potential upstream
   README fix to propose to Mike.

2. **`set -o pipefail` isn't enough for exit codes.** It only handles piped
   commands. For sequential commands (`cmd1; cmd2`), capture the exit code
   explicitly: `cmd1; RESULT=$?; echo "EXIT=$RESULT"; exit $RESULT`.

3. **DIA-NN `.tsv.speclib` is binary, not TSV.** Despite the extension, this is
   DIA-NN's proprietary binary library format (magic bytes `fd ff ff ff`).
   Osprey only reads plain-text DIA-NN TSV exports (from `--out-lib`).

### Mike's test data — what to expect

- Downloading from Panorama: `osprey-testfiles` folder
- **Stellar dataset** = faster, unit resolution (`--resolution unit`). Best
  first target on this 32GB laptop.
- **Astral dataset** = bigger, ~1.5M peptide library, high-resolution (default ppm).
  Better for desktop/server.
- Library: `hela-filtered-SkylineAI_spectral_library.tsv` (actual DIA-NN text TSV)
- Mike's exact commands are in the Context section below.
- Mike says **protein-level FDR "still needs work"** but peptide/precursor FDR
  is good. Don't expect perfect protein-level results.
- Mike says output is **"very verbose right now"** with plans to add verbosity
  levels. We don't need to replicate that verbosity in OspreySharp.

### pwiz_tools/ layout (for scaffolding)

Existing siblings at `pwiz_tools/`:
```
BiblioSpec/      ← blib tools (BlibBuild.exe, BlibFilter.exe) — reuse for I/O
Bumbershoot/     ← myrimatch, idpicker — precedent for tool suites
Shared/          ← common deps (SQLite, etc.) — reference from OspreySharp
Skyline/         ← main application
Topograph/       ← another standalone tool
```
OspreySharp goes at same level: `pwiz_tools/OspreySharp/`.

### What the failed smoke test proved

The PROCAL smoke test (Tutorial_DIA.blib + DIA_100fmol.mzML) produced 0 detections
because the library (45,044 proteome peptides) didn't match the sample (PROCAL
synthetic standard, ~40 peptides). This is a **library mismatch, not an Osprey bug**.
The pipeline ran correctly end-to-end in 17 seconds: loaded library, parsed mzML,
scored 89,168 entries, ran Percolator 3-fold CV, wrote Parquet + TSV. The diagnostic
"target_mean=0.839, decoy_mean=0.839" (identical distributions) confirms targets
weren't present in the data.

Don't re-attempt this combination. Wait for Mike's matched test data.

## Decisions

- **Location**: `pwiz_tools/OspreySharp/` (not standalone repo). Provides BiblioSpec,
  pwiz_data_cli, Shared, Boost Build. Can be abandoned if exploration doesn't pan out.
- **Back-references**: Keep one generation of references to Osprey Rust code for
  traceability during active port. Clean up once OspreySharp is established.
- **BLAS strategy**: Math.NET Numerics + MKL provider for SVM; consider SIMD intrinsics
  (`System.Numerics.Vector<float>`) for hot inner loops in batch scoring.
- **Mokapot**: dropped from scope (Osprey's built-in Percolator SVM is the default).
- **Numerical tolerance**: match Osprey statistically, not bit-for-bit.
- **Chemistry/mass calculation**: MUST use `Shared/CommonUtil/Chemistry/` (Molecule,
  AminoAcidFormulas, MassDistribution) for all mass calculations and isotope distributions.
  Do NOT port Rust's binomial isotope approximation. OspreySharp must produce identical
  masses and isotope patterns as Skyline. Current IsotopeEnvelope.cs is a placeholder
  that will be replaced when CommonUtil project reference is added in Phase 3.
- **pwiz infrastructure review gates**: Phase 3 (I/O) and Phase 5 (pipeline) each
  require a review step before coding. At I/O: wire up CommonUtil, BiblioSpec,
  ProteowizardWrapper and design around them rather than porting Rust I/O directly.
  At pipeline: verify threading/progress/cancellation follow Skyline conventions.

## Progress Log

### 2026-04-09 Session 2 (laptop)

**Test data**: Downloaded from Panorama to `C:\test\osprey-testfiles\{astral,stellar}`.
Each has 3 mzML files, a DIA-NN TSV library, a fasta, and a readme with Mike's exact command.

**Bug found and fixed**: `run_percolator_fdr_direct()` and the streaming scoring path
in `pipeline.rs` assumed positional correspondence between `fdr_entries` and Parquet rows.
After first-pass FDR compaction, `fdr_entries` is shorter than the Parquet cache, causing:
1. Panic (slice index out of bounds) in the second-pass direct path
2. Targets receiving decoy features (or vice versa) in the first-pass, because the
   Parquet stores targets and decoys interleaved but `fdr_entries` order may differ

**Fix**: Use `fdr_entry.parquet_index` (which preserves the original Parquet row) instead
of positional index. Fixed in three places in `run_percolator_fdr_direct()` and the
streaming Phase 2 (training subset) and Phase 4 (scoring all entries) paths.

**Branch**: `brendanx67/fix-parquet-index-lookup` on `maccoss/osprey`

**Stellar results** (3 files, unit resolution, hela-filtered library):
- 29,916 precursors, 26,523 peptides, 4,995 protein groups at 1% FDR
- 7 minutes 22 seconds on laptop (32 GB RAM)

**Astral results** (3 files, hram resolution, ~1.5M peptide library):
- 0 detections at 1% FDR despite calibration LDA finding ~5K peptides per file
- 3 hours 19 minutes on laptop (32 GB RAM)
- Used streaming Percolator path (4.6M entries > 600K threshold)
- Training subset had skewed target/decoy ratio (203K targets vs 97K decoys) — likely
  a separate streaming-path bug where target-decoy pairing breaks at scale
- Needs further investigation on more powerful hardware with diagnostics

**Test infrastructure created** (`C:\test\osprey-runs\`):
- `clean-run.ps1` - wipe Osprey runtime caches from a test data folder
- `clean-build.ps1` - cargo clean + full rebuild + test

**Osprey fork**: `brendanx67/osprey`, branch `fix/parquet-index-lookup`
- Fix committed and pushed, ready for PR to `maccoss/osprey`
- Other machines: `git clone git@github.com:brendanx67/osprey.git && git checkout fix/parquet-index-lookup`

**Next steps**:
- Investigate Astral 0-detection issue (streaming path target/decoy pairing)
- Run both datasets on desktop (i9, 64 GB) and NUMA server (72 cores, 512 GB)
- PR the parquet_index fix to Mike
- Begin scaffolding `pwiz_tools/OspreySharp/`

### 2026-04-09 Session 3 (desktop, i9 + 64 GB RAM)

**Environment setup**: Installed Rust 1.94.1, vcpkg + OpenBLAS 0.3.29, cloned
`brendanx67/osprey` to `C:\proj\osprey`. VS 18 (Community) is too new for vcpkg's
bundled CMake -- requires `CMAKE_GENERATOR=Ninja` and Ninja on PATH from VS install.
Build time: 1m19s (vs 3m55s on laptop). All 335 tests pass.

**Second parquet_index bug found**: `to_fdr_entry()` sets `parquet_index: 0` with
comment "populated by caller after Parquet write" but the caller at pipeline.rs:2522
never populated it. After the first fix (dfe5f9e) switched feature lookup to use
`parquet_index` instead of positional index, every entry loaded row 0's features,
destroying all SVM discriminative signal. This caused 0 detections on fresh runs
(the bug was masked when reusing cached Parquet files because `load_fdr_stubs_from_parquet`
correctly sets `parquet_index` from the Parquet row).

**Diagnosis**: Compared `main` vs `fix/parquet-index-lookup` on Stellar data:
- `main`: first-pass streaming found 49,704 precursors (using `local_idx`), then panicked
  in second-pass direct path (the original parquet_index bug)
- `fix`: first-pass streaming found 0 targets (using `parquet_index` which was always 0)
- Root cause confirmed: "Best initial feature: xcorr (10,752 at 1% FDR)" on `main` vs
  "median_polish_cosine (1 at 1% FDR)" on fix -- identical features for all entries

**Fix**: One-line change -- set `parquet_index = i` during FdrEntry stub creation at
the call site (pipeline.rs:2522). Committed as 2812401.

**Mike is independently working on a fix** via his own Claude Code session after
reproducing the bug. Merge of his fix and ours may be needed.

**Stellar results** (3 files, unit resolution, hela-filtered library):
- 36,783 precursors, 33,966 peptides, 5,604 protein groups at 1% FDR
- 4 minutes 39 seconds (vs 7m22s on laptop first-pass only)
- Substantially better than laptop (29,916 precursors) because second-pass
  reconciliation now works correctly

**Astral results** (3 files, hram resolution, ~1.5M peptide library):
- 143,622 precursors, 125,609 peptides, 13,482 protein groups at 1% FDR
- 1 hour 9 minutes (vs 3h19m with 0 results on laptop)
- This is the first successful Astral run -- proves the streaming path works

**Validation oracle established**: Both datasets produce strong results on desktop.
These numbers serve as the reference for OspreySharp C# port validation:
- Stellar: ~37K precursors, ~34K peptides, ~5.6K proteins (statistically equivalent)
- Astral: ~144K precursors, ~126K peptides, ~13.5K proteins (statistically equivalent)

**Desktop build environment** (`C:\proj\osprey`):
```bash
export VCPKG_ROOT="$USERPROFILE/vcpkg"
export CMAKE_GENERATOR=Ninja
export PATH="$USERPROFILE/.cargo/bin:/c/Program Files/Microsoft Visual Studio/18/Community/Common7/IDE/CommonExtensions/Microsoft/CMake/Ninja:$USERPROFILE/vcpkg/installed/x64-windows/bin:$PATH"
```
Also: `openblas.dll` copied to `target/release/` to avoid DLL search issues in Git Bash.

**Test data locations** (desktop):
- Stellar: `D:\test\osprey-runs\stellar\` (3 mzML + hela-filtered library)
- Astral: `D:\test\osprey-runs\astral\` (3 mzML + SkylineAI library)

**Next steps**:
- Coordinate with Mike on merging parquet_index fixes
- Begin scaffolding `pwiz_tools/OspreySharp/` solution structure
- Port Phase 2 (core types) as first C# implementation milestone

### 2026-04-10 Session 4 (desktop, i9 + 64 GB RAM)

**OspreySharp C# port — Phases 1-4 + partial Phase 3 completed in single session.**

**Approach**: Straight port of Rust code to establish a validated baseline. Shared/Common
integration (LOESS, Chemistry, MedianPolish, etc.) deferred to a separate branch so we
can diff the numerical impact of each substitution. The Rust-derived tests become
regression tests validating the Skyline implementations produce equivalent results.

**Phase 1**: Scaffolded 8-project .NET Framework 4.7.2 solution (7 libraries + 1 test),
old-style .csproj matching pwiz conventions. All build clean with zero warnings.

**Phase 2** (Core Types + ML):
- 23 type files in OspreySharp.Core: LibraryEntry, FdrEntry, CoelutionFeatureSet (47 fields),
  IsolationWindow, IsotopeEnvelope, MS1Spectrum, Spectrum, BinConfig, OspreyConfig,
  FragmentToleranceConfig, RTCalibrationConfig, all enums
- 7 files in OspreySharp.ML: LinearSvmClassifier (dual CD), Matrix, PepEstimator,
  QValueCalculator, LinearDiscriminant, GaussSolver, XorShift64 PRNG
- 60 tests passing (21 core + 39 ML)
- XorShift64 verified to produce identical output as Rust implementation

**Phase 4** (Algorithms):
- OspreySharp.Chromatography: CWT peak detection (Mexican Hat, consensus median),
  LOESS regression, RT calibration (outlier removal, local tolerance), mass calibration,
  calibration JSON I/O via Newtonsoft.Json — 30 tests
- OspreySharp.Scoring: DecoyGenerator (enzyme-aware reversal), SpectralScorer (XCorr,
  LibCosine), BatchScorer, CalibrationScorer (LDA), PearsonCorrelation — 18 tests
- OspreySharp.FDR: FdrController (target-decoy competition), PercolatorFdr (3-fold CV,
  grid search, dual-level q-values, PEP), ProteinFdr (parsimony, subset elimination,
  picked-protein FDR) — 26 tests

**Phase 3** (I/O — partial):
- DIA-NN TSV reader, BiblioSpec blib reader/writer, EncyclopeDIA elib reader
- Library deduplication, binary library cache, spectra binary cache
- 27 tests; all use System.Data.SQLite from pwiz libraries/
- mzML reader deferred (needs ProteowizardWrapper for pipeline integration)
- Parquet caching deferred (evaluate need vs direct file I/O)

**Existing pwiz_tools/Shared code identified for integration** (on a separate branch):
- `Common/DataAnalysis/LoessInterpolator.cs` — replaces our LoessRegression.cs
- `CommonUtil/Chemistry/` (Molecule, AminoAcidFormulas, MassDistribution) — replaces
  IsotopeEnvelope.cs. CRITICAL: masses and isotope distributions must be identical to
  Skyline. 17 years of validation behind the Shared chemistry code.
- `Common/DataAnalysis/MedianPolish.cs` — reuse directly for scoring features
- `Common/DataAnalysis/Matrices/ImmutableMatrix.cs` — evaluate overlap with Matrix.cs

**Total**: 54 source files, 161 tests passing, 0.58s test runtime.

**Next steps**:
- Phase 5: Pipeline orchestration + mzML reading via ProteowizardWrapper
- End-to-end validation on Stellar/Astral datasets
- Branch for Shared integration: swap LoessInterpolator, Chemistry, MedianPolish
  and validate that all 161 tests still pass

### 2026-04-10 Session 5 (desktop) — Pipeline, feature fixes, start of bisection

**Phase 5 completed end-to-end** (CLI, pipeline orchestration, mzML reader,
ParquetNet score cache, blib writer optimizations). End-to-end run on Stellar
file 20 works: parses mzML, calibrates, scores, runs Percolator, writes blib.

**Key optimizations landed**:
- `BlibWriter` prepared statements + transactions (1209s → 3.5s, 345x speedup)
- Percolator parallel-folds (Parallel.For over 3 folds — matches Rust par_iter)
- Best-per-precursor subsampling before Percolator training (was treating N files
  x same precursor as N independent observations, inflating separation)
- `Matrix.WrapNoClone` + Array.Copy in ExtractRows to avoid double allocation
- LDA-based RT calibration (replaced naive LibCosine + score>0.3 threshold)

**Feature accuracy work** — iterative, converged on real values:
- Full 21-feature PIN vector computed in ScoreCandidate (was: only coelution_sum)
- Tukey median polish ported (TukeyMedianPolish.cs) — features 15, 16, 19, 20
- SG-weighted XCorr/cosine ported (features 17, 18)
- ExtractFragmentXics now top-6 by intensity + closest peak by m/z + all-zero
  fragments included (match Rust extract_fragment_xics exactly)
- Candidate peak ranking by mean pairwise fragment correlation (was: first CWT peak)

**Stellar 3-file timing** (final state of session 5):
  File processing:  150s   (3 files in sequence, ~50s/file)
  Percolator FDR:   100s   (parallel folds)
  Blib output:      3.5s
  Total:            ~290s vs Rust ~279s (1.04x)

But detection counts still don't match Rust. This triggered Session 6's bisection.

### 2026-04-10/11 Session 6 — Rigorous bisection for accuracy parity

**Lesson learned (MAJOR, apply going forward)**:

When two tools produce different outputs but both "look right" at a high level,
**stop measuring statistics and start measuring primitives**. This is the MacCoss
lab mass-spec troubleshooting principle: don't measure spectrum IDs at 1% FDR,
measure peak shape, peak area, mass error, ratio between MS1 and MS2. Same
here: don't measure "N precursors at 1% FDR", measure the intermediate values
at each pipeline stage.

The bisection **must start at the very first randomized/selected step** and
walk downstream, proving match at each point with hard diff data (not
statistical similarity). Going downstream first (comparing features in PIN
files) was wasted effort because the features were computed for different
peaks — the divergence had already happened upstream.

**Bisection protocol** (worked, use this pattern):
1. Identify the first randomized/sampled step (calibration sampling in this case)
2. Add DIAGNOSTIC DUMPS to both tools that exit after the dump (env var
   guarded). Dump EVERYTHING that could differ: scalars (min/max/bin widths/
   counts), full intermediate state (grid cell contents), final output.
3. Build both with dumps, run with early-exit (~30s cycle, not 3 minutes).
4. `diff` the outputs. If zero lines differ → prove match and move to next
   stage. If differences → drill in on the differing data specifically.
5. For scalars: use format that preserves all bits (Rust `{:.17}`, C# `"R"`).
   Compare numerically, not textually, since format may differ.

**First proven match point — calibration sampling**:

Started by dumping the calibration sample (100,000 targets) from both tools
to sorted TSV files. Initial diff showed 10 entries in each direction different
(99.99% match). Added scalar + full-grid dumps to both tools.

Scalar diff revealed the root cause: **Rust n_targets = 242,837 vs C# n_targets
= 242,841** (4 extra targets in C#).

**Root cause**: Rust's `DecoyGenerator.generate_all_with_collision_detection`
excludes targets whose reversed sequence matches ANOTHER target's stripped
sequence. C#'s `DecoyGenerator.Generate()` only checked the palindromic case
(reversed == original), missing the cross-target collision case. For the
242,841-target HeLa library, exactly 4 targets fall into this category.

**Fix** (committed e06ce878e):
- `AnalysisPipeline.GenerateDecoys` now builds HashSet of target sequences,
  tries reversal first, falls back to cycling lengths 1..10, excludes
  target+decoy pairs with no collision-free option, returns `validTargets`
  list alongside decoys.
- `AnalysisPipeline.Run` replaces `library` with `validTargets` before
  appending decoys (matches Rust `library = valid_targets; library.extend(decoys)`).
- `DecoyGenerator.RemapModificationsStatic`, `RecalculateFragmentsStatic`:
  public static wrappers so pipeline can build collision-checked decoys while
  reusing the remap logic.

**Hard proof of match after fix** (single Stellar file 20):
```
n_targets:     242837 = 242837  (was 242837 vs 242841)
n_decoys:      242837 = 242837
bins_per_axis: 159 = 159
rt_min/max, mz_min/max, bin_widths: bit-identical
n_occupied:    23106 = 23106
per_cell:      4 = 4
Grid cells:    0 diff lines (all 23106 cells contain identical target IDs)
Final sample:  0 diff lines (all 100000 targets identical by id, modseq,
               charge, mz, rt)
```

Sample and grid files compared with `diff` after normalizing line endings.
This is what "proven match" looks like.

**Infrastructure for continuing bisection**:

Both tools now support diagnostic dumps via env vars:
- `OSPREY_DUMP_CAL_SAMPLE=1` — dump calibration sample + scalars + grid
- `OSPREY_CAL_SAMPLE_ONLY=1` — exit after calibration sample dump (fast cycle)

C# dump locations (relative to input mzML directory):
- `{file}.cs_cal_sample.txt` — sorted targets (id, modseq, charge, mz, rt)
- `cs_cal_scalars.txt` — rt_min, rt_max, mz_min, mz_max, bin widths, n_occupied, per_cell
- `cs_cal_grid.txt` — rt_bin, mz_bin, count, sorted target_ids per non-empty cell

Rust equivalents:
- `rust_cal_sample.txt`
- `rust_cal_scalars.txt`
- `rust_cal_grid.txt`

Rust diagnostic code lives in `C:\proj\osprey\crates\osprey-scoring\src\batch.rs`
at the end of `sample_library_for_calibration`. **Not committed to Rust repo**
(was an uncommitted scratch edit on branch `fix/parquet-index-lookup`).

**IMPORTANT**: If a future session continues bisection, the Rust diagnostic
code is still in place in `batch.rs` (check `git status` in `/c/proj/osprey`).
If lost, the pattern to re-add is:
1. Check for `OSPREY_DUMP_CAL_SAMPLE` env var
2. Write scalars to `rust_cal_scalars.txt` and grid to `rust_cal_grid.txt`
3. Write final sample to `rust_cal_sample.txt`
4. Check for `OSPREY_CAL_SAMPLE_ONLY` env var and `std::process::exit(0)` if set

**Fast iteration commands** (no full pipeline run):
```bash
cd /d/test/osprey-runs/stellar

# Clean rust caches so calibration actually runs
rm -f *.parquet *.calibration.json *.spectra.bin *.fdr_scores.bin 2>/dev/null

# Rust with early exit (~20s after build)
OSPREY_DUMP_CAL_SAMPLE=1 OSPREY_CAL_SAMPLE_ONLY=1 \
  /c/proj/osprey/target/release/osprey.exe \
  -i Ste-2024-12-02_HeLa_4mz_sDIA_400-900_20.mzML \
  -l hela-filtered-SkylineAI_spectral_library.tsv \
  -o rust-output.blib --resolution unit

# C# with early exit (~20s after build)
OSPREY_DUMP_CAL_SAMPLE=1 OSPREY_CAL_SAMPLE_ONLY=1 \
  /c/proj/pwiz/pwiz_tools/OspreySharp/OspreySharp/bin/x64/Release/pwiz.OspreySharp.exe \
  -i Ste-2024-12-02_HeLa_4mz_sDIA_400-900_20.mzML \
  -l hela-filtered-SkylineAI_spectral_library.tsv \
  -o cs-output.blib --resolution unit

# Diff (should all be empty for proven match)
diff <(tr -d '\r' < rust_cal_sample.txt) <(tr -d '\r' < Ste-...20.cs_cal_sample.txt) | wc -l
diff <(tr -d '\r' < rust_cal_grid.txt) <(tr -d '\r' < cs_cal_grid.txt) | wc -l
```

**Next bisection point — Calibration LDA scoring** (not yet proven):

The 100,000 calibration targets are now identical between the two tools.
The next step in the pipeline is `ScoreCalibrationEntry` (per-entry 4-feature
computation: correlation, libcosine, top6_matched, xcorr) followed by
`CalibrationScorer.TrainAndScoreCalibration` (LDA over those features).

Current state (before fix was applied):
- Rust LDA winners at 1% FDR: 16,509
- C# LDA winners at 1% FDR: 9,158 (55% of Rust)

**Need to verify**: With the calibration sample now matching, does C# produce
the same 192,289 per-entry scores? If not, the per-entry scoring is still
divergent. If yes, the LDA is divergent (less likely — LinearDiscriminant is
a direct port).

**Bisection plan for next session**:
1. Add diagnostic dump to both tools: for each calibration entry
   (after `ScoreCalibrationEntry`), write id, correlation, libcosine, top6, xcorr
   to a sorted TSV. Early-exit after the dump.
2. Diff the two files.
3. If 0 diff lines → LDA is the problem.
4. If N diff lines → per-entry scoring has issues; isolate which feature
   differs first by comparing column-by-column.

**Downstream from calibration**: Once calibration sample + scoring + LDA all
match, C#'s RT calibration LOESS fit should produce bit-identical coefficients
to Rust. Then RT calibration output (expected_rt for each library entry) can
be diffed. Then coelution scoring (per-entry features), etc.

**Current `--write-pin` feature dump in C#** (for later, when upstream matches):
`AnalysisPipeline.WriteFeatureDump` writes `.cs_features.tsv` with the 21
PIN features per entry after ProcessFile. This is the downstream comparison
target — but only meaningful once upstream divergences are fixed.

**Remaining known issues (not yet bisected)**:
1. RT calibration quality: residual SD 0.85 min vs Rust's 0.28 min.
   Probably fixes itself when calibration scoring matches.
2. Detection count mismatch: C# ~26K per file vs Rust ~33K per file after
   all session 5 + 6 work. Should converge as upstream divergences are fixed.
3. Missing peak detection fallbacks (CWT → median polish profile → ref XIC).
   Rust has 3; C# only has CWT. Accounts for some under-detection.
4. Multi-charge consensus + inter-replicate reconciliation + second-pass
   FDR — all TODO in AnalysisPipeline. These are post-first-pass refinements
   Rust does but C# doesn't yet.

**Session 6 takeaways for future bisection work**:

1. **Measure primitives, not outcomes**. "26K vs 33K precursors at 1% FDR"
   is an outcome. "(id, libcosine, xcorr) per calibration entry" is a
   primitive.

2. **Start at the first selection step, walk downstream**. Never try to match
   from the end. The feature values in a PIN file are meaningless if the two
   tools picked different peaks.

3. **Prove match, don't infer it**. "Both tools sampled 100K targets" is not
   proof. "All 100K IDs identical via diff, 0 lines different" is proof.

4. **Dump everything, then drill in**. Scalars + intermediate state + final
   output. Format numerical values with precision that preserves all bits
   (C# `"R"`, Rust `{:.17}`). Compare with `diff` on normalized line endings.

5. **Use env-var-guarded early exits for fast cycles**. Don't run the full
   pipeline (3+ minutes) when you only need the output of one stage (20s).

6. **Don't proliferate commented-out code when bisecting**. Get to match at
   one stage, commit, move to next stage. The session log is the record of
   what we tried.

**File pointers for future sessions**:
- `C:\proj\pwiz\pwiz_tools\OspreySharp\OspreySharp\AnalysisPipeline.cs`
  lines ~265-380: GenerateDecoys + BuildDecoyFromSequence
  lines ~800-960: SampleLibraryForCalibration (2D grid, stride sampling)
  lines ~960+: ScoreCalibrationEntry (next bisection target)
- `C:\proj\osprey\crates\osprey-scoring\src\batch.rs`
  line ~1450: sample_library_for_calibration (has diag dumps, uncommitted)
- `C:\proj\pwiz\pwiz_tools\OspreySharp\OspreySharp.Scoring\TukeyMedianPolish.cs`
  Direct port of Rust median polish algorithm
- Commits to study: 849ea7f69 (bisection baseline), e06ce878e (first match)

### 2026-04-11 Session 7 (desktop) — Pass-1 calibration bit-identical

**Goal**: Walk downstream from the proven calibration-sample match point
(Session 6) and get to bit-identical pass-1 per-entry features against Rust.

**Final result**: All 192,289 calibration matches bit-identical on all 6
feature columns (apex_rt, correlation, libcosine, top6, xcorr, snr) at
f64 rounding noise (max |d| ≤ 5e-10; 90.72% exact bit-equal). Pass-2 XIC
extraction bit-identical on entry 0 (same 46 candidates, 276 XIC rows
within 1e-10). Pass-1 XIC bit-identical too (earlier in session, max
|d|=1e-10 at F10 precision).

**Bisection walk (what was proven in order)**:
1. Pass-1 chromatograms (XICs): identical within 1e-10 rounding noise on
   all 2198 records of entry 0. Format fix: F10 (up from F6) to avoid
   banker's-vs-half-up formatting diffs.
2. Pass-1 per-entry features diff (OSPREY_DUMP_CAL_MATCH): started with
   xcorr at 0% text-equal (max diff 116), snr at 3% (max diff 4.6e7),
   apex_rt at 72.8% (max diff 0.66 min). Root causes:
   - **XCorr algorithm was wrong**: C#'s ComputeXcorrForSpectrum used
     max-bin instead of sum-bin, was missing Comet MakeCorrData windowing
     normalization, and did a library-intensity-weighted dot product
     instead of Comet's "sum at fragment positions" form.
   - **SNR input was wrong**: C# computed SNR on compositeXic (sum of
     all fragment XICs), Rust uses ref_xic (single reference fragment).
   - **Apex selection was wrong**: C# required top-6 match constraint
     and used composite argmax, Rust uses plain argmax of ref_xic within
     peak bounds.
   - **Tie-break direction was wrong**: C# used strict `>` (first-wins),
     Rust's Iterator::max_by returns last-wins on ties. Changed to `>=`.
3. After the above fixes, cal_match diff improved to: libcosine/snr/top6
   100% match, apex_rt 90.73% text-equal (1e-10 max = rounding only),
   xcorr 4.2e-6 f32/f64 drift (Rust was f32, C# f64). **Flipped Rust
   xcorr pipeline from Vec<f32> to Vec<f64>** (preprocess_*, apply_*,
   xcorr_from_preprocessed, plus Vec<Vec<f32>>→Vec<Vec<f64>> call sites
   in batch.rs and pipeline.rs). This brought xcorr to bit-identical.
4. Match count gap: Rust 192,289 vs C# 186,271 (6018 delta). Two causes:
   - **Missing CWT fallback**: Rust falls back to detect_all_xic_peaks
     on ref_xic when CWT returns empty; C# only had CWT. Ported
     detect_all_xic_peaks + SmoothSavitzkyGolay + WalkBoundaryLeft/Right
     + ComputeAsymmetricHalfWidths to C# PeakDetector.cs. Wired as
     fallback in ScoreCalibrationEntry. List.Sort → LINQ
     OrderByDescending (stable, matches Rust sort_by).
   - **MIN_COELUTION_SPECTRA constant mismatch**: Rust = 3, C# = 5.
     Changed C# to 3.
   Final gap: 0 (192,289 = 192,289).

**Two-pass RT calibration refinement also landed** (was pass-2 missing
entirely in C#): extracted RunCalibrationScoringPass helper, added pass-2
branch with MAD-based refined tolerance (clamp(mad*1.4826*3, [min,max]))
and LOESS-predicted expected_rt, accept-iff-R²-doesn't-degrade-1% gate.
ScoreCalibrationEntry takes RTCalibration param; uses Predict() on pass 2.
ABSOLUTE_MIN_CALIBRATION_POINTS = 50 for pass-2 LOESS floor.

**Rich diagnostic dumps** now in place in both tools:
- `OSPREY_DIAG_XIC_ENTRY_ID=<id>` + `OSPREY_DIAG_XIC_PASS={1,2}` —
  per-entry dump with PASS CALCULATIONS block (library_rt, expected_rt,
  tolerance, rt_window_lo/hi, rt_slope, rt_intercept) and on pass 2 a
  LOESS MODEL block (n_points, r_squared, residual_sd, mad, percentiles),
  followed by CANDIDATES + TOP-6 + XICS tables. F10 precision throughout.
  Exits immediately after write.
- `OSPREY_DUMP_CAL_MATCH=1` + `OSPREY_CAL_MATCH_ONLY=1` — 11-column
  cal_match dump (entry_id, is_decoy, charge, has_match, scan, apex_rt,
  correlation, libcosine, top6, xcorr, snr), F10 precision, sorted by
  entry_id for stable diff.

**Proof of final match** (Stellar file 20, cal_match diff):
```
matched: rust=192289  cs=192289  delta=0
matched by Rust only: 0
matched by C#   only: 0
max abs diffs:
  |d apex_rt|    = 1.0e-10   (f64 rounding noise)
  |d correlation|= 1.0e-10
  |d libcosine|  = 1.0e-10
  |d xcorr|      = 1.0e-10
  |d snr|        = 5.2e-10
exact bit-equal on all 6 columns: 174449/192289 (90.72%)
```

**Pass-2 XIC check** (entry 0, AAAAAAAAAAAAAAAGAGAGAK z=2):
```
rust candidates: 46, cs candidates: 46, overlap: 46
rust-only scans: [], cs-only scans: []
max |dRT| on overlap       = 1.0e-10
max |dIntensity| on overlap = 1.0e-10
```

**Remaining Session 7 discrepancies** (all small, don't affect pass-2 XIC):
1. **LOESS input count drift**: Rust 6423 points vs C# 6409 (−14) survive
   LDA+S/N filter into the pass-2 LOESS fit. Hypothesis: ULP-level drift
   in LDA discriminant scores on the 1% FDR cutoff boundary, ping-ponging
   ~14 entries. Does not affect pass-2 expected_rt enough to change
   candidate selection on entry 0. Next bisection candidate if we want
   100% LOESS alignment: dump per-entry LDA discriminant + q-value from
   both tools and diff.
2. **9.28% of cal_match rows differ by 1 ULP** on one or more feature
   columns — f64 sum non-associativity (different accumulation orders
   for terms that are mathematically equal but bit-drift by 1 ULP).
   Not fixable without forcing strict iteration order and no SIMD.

**Commits**:
- pwiz `Skyline/work/20260409_osprey_sharp`: **d832476ef** — "Fixed C#
  pass-1 calibration features to match Rust bit-for-bit" (3 files
  changed, 815 insertions, 153 deletions: SpectralScorer.cs,
  AnalysisPipeline.cs, PeakDetector.cs).
- osprey `fix/parquet-index-lookup`: **2577e61** — "Flipped XCorr
  pipeline to f64 for cross-impl bit-identical alignment" (3 files,
  442 insertions, 34 deletions: lib.rs, pipeline.rs, batch.rs with
  scratch diagnostics).
- **Not pushed** — local commits only.

**Fast iteration commands** (still work from Session 6; now for pass-2
bisection):
```bash
cd /d/test/osprey-runs/stellar

# Per-entry XIC dump, pass 1 (default)
rm -f *.scores.parquet *.calibration.json *.spectra.bin *.fdr_scores.bin
OSPREY_DIAG_XIC_ENTRY_ID=0 /c/proj/osprey/target/release/osprey.exe \
  -i Ste-2024-12-02_HeLa_4mz_sDIA_400-900_20.mzML \
  -l hela-filtered-SkylineAI_spectral_library.tsv \
  -o rust-output.blib --resolution unit
OSPREY_DIAG_XIC_ENTRY_ID=0 \
  /c/proj/pwiz/pwiz_tools/OspreySharp/OspreySharp/bin/x64/Release/pwiz.OspreySharp.exe \
  -i Ste-2024-12-02_HeLa_4mz_sDIA_400-900_20.mzML \
  -l hela-filtered-SkylineAI_spectral_library.tsv \
  -o cs-output.blib --resolution unit

# Per-entry XIC dump, pass 2
OSPREY_DIAG_XIC_ENTRY_ID=0 OSPREY_DIAG_XIC_PASS=2 ...

# Cal_match per-entry feature dump (early exit after scoring)
OSPREY_DUMP_CAL_MATCH=1 OSPREY_CAL_MATCH_ONLY=1 ...

# Diff after normalizing line endings
diff <(tr -d '\r' < rust_cal_match.txt) <(tr -d '\r' < cs_cal_match.txt) | wc -l
```

**Next bisection candidates** (when time to resume):
1. Drill into LDA (14-point LOESS delta): dump per-entry discriminant
   scores + q-values from both tools, find the 14 entries at the cutoff,
   confirm ULP drift hypothesis.
2. Move downstream to main first-pass search — compare the 21 PIN
   features per entry. Now that pass-1 calibration features and pass-2
   XIC extraction are bit-identical, downstream features should now
   differ only by f64 rounding noise.
3. Check if the same Rust-side f32→f64 flip is needed in any other
   scoring paths (hyperscore? mass error accumulation? isotope cosine?).

**Codebase size comparison (ran 2026-04-11 at end of Session 7)**:

Ran `cloc` on both projects to get a size snapshot at the point where pass-1
calibration features are bit-identical. Script: `ai/scripts/audit-loc.ps1`
(used for methodology; this run was per-project via direct cloc invocation
since OspreySharp has its own project structure).

Overall:
```
                    Files   Blank  Comment    Code
OspreySharp (C#)      77    2,759   3,244   16,466
Osprey (Rust)         45    4,416   6,432   29,466
```

Per-project (code lines only):
| OspreySharp project    | C#     | Rust crate            | Rust   | C#/Rust |
|------------------------|-------:|------------------------|-------:|--------:|
| Core                   |    808 | osprey-core           |  1,854 |   44%   |
| IO                     |  2,910 | osprey-io             |  3,618 |   80%   |
| ML                     |    923 | osprey-ml             |  1,719 |   54%   |
| Chromatography         |  1,773 | osprey-chromatography |  3,597 |   49%   |
| Scoring                |  1,478 | osprey-scoring        |  6,946 |   21%*  |
| FDR                    |  1,800 | osprey-fdr            |  4,251 |   42%   |
| OspreySharp (CLI+pipe) |  3,128 | osprey                |  7,481 |   42%   |
| Non-test subtotal      | 12,820 |                       | 29,466 |   43%   |
| .Test (separate proj)  |  3,646 | (inline in .rs)       |    —   |    —    |

*Scoring ratio isn't apples-to-apples: in C# the main pass-1 scoring
orchestration is in `AnalysisPipeline.cs` (under the OspreySharp project),
while in Rust it's in `osprey-scoring/src/batch.rs`. Combining Scoring +
CLI/pipeline gives C# 4,606 vs Rust 14,427 = 32%.

Rust tests live inline under `#[cfg(test)] mod tests`, counted as
production code by cloc. Extracting `#[cfg(test)]`-onwards lines gives
~7,180 test-code lines (after applying the overall blank/comment ratio):

| Metric                | C# (OspreySharp) | Rust (Osprey) | Ratio |
|-----------------------|-----------------:|--------------:|------:|
| Non-test code         |           12,820 |        ~22,286 | 57.5% |
| Test code (approx)    |            3,646 |         ~7,180 |  51%  |

**Takeaways**:
- OspreySharp is ~55-60% the size of Osprey for both production and tests.
- Some reduction is real (Rust has verbose doc comments, more explicit
  error handling, the scoring crate packs multiple search path variants).
- Some reduction is because C# leverages existing pwiz infrastructure
  (mzML via ProteowizardWrapper, Chemistry via Shared/CommonUtil planned).
- Some reduction is still missing functionality: multi-charge consensus,
  reconciliation, second-pass FDR — not yet ported. Expected to add
  ~1,500-2,500 lines when done.
- **Estimated size at feature-complete**: ~15,000 non-test lines + ~4,500
  test lines ≈ 20K total, vs Osprey's ~30K total. ~65-70% size ratio.
- OspreySharp.IO (80% of osprey-io) is surprisingly close — reader/writer
  ports are 1:1 because the formats (DIA-NN TSV, blib, elib) are rigid.

**Performance comparison (ran 2026-04-11 at end of Session 7)**:

Measured wall clock to pass-1 calibration exit (the point where both tools
produce 192289/192289 bit-identical cal_match output). Same command both
tools: `OSPREY_DUMP_CAL_MATCH=1 OSPREY_CAL_MATCH_ONLY=1`. Input: Stellar
file 20 (Ste-2024-12-02_HeLa_4mz_sDIA_400-900_20.mzML, 97500 MS2 + 780 MS1
spectra). Library: hela-filtered-SkylineAI_spectral_library.tsv (242841
entries). Cold caches before each run (rm .scores.parquet .calibration.json
.spectra.bin .fdr_scores.bin .mzML.spectra.bin). One warm-up run then
min-of-3 timed runs. Release builds for both tools.

Wall clock (min of 3 runs):
| Tool | Run 1  | Run 2  | Run 3  | Min     |
|------|-------:|-------:|-------:|--------:|
| Rust | 16.93s | 17.06s | 17.30s | **17.0s** |
| C#   | 40.56s | 41.30s | 40.73s | **40.6s** |
| C#/Rust ratio |        |        |        | **2.39x** |

Per-phase breakdown (from single-run stderr logs):

| Phase                       |  Rust |    C# | C#/Rust |
|-----------------------------|------:|------:|--------:|
| Library load + decoys       |   ~0s |  8.4s |   (∞)   |
| mzML parse                  |   ~6s | 14.2s |  2.37x  |
| Calibration sampling        |   ~0s | 0.06s |    —    |
| Pass 1 scoring              |   ~4s | 15.7s |  3.93x  |
| Match dump + post-processing|   ~6s | ~1.6s |  0.27x  |

Observations:
- **Library load (0s vs 8.4s)**: Rust uses a binary library cache
  (`.libcache` file, persistent across runs). C# re-parses the TSV every
  time. C# has `LibraryBinaryCache.cs` in OspreySharp.IO but it's not
  wired into the pipeline yet.
- **mzML parse (~6s vs 14.2s)**: C# uses ProteowizardWrapper (native COM
  bridge + managed wrapper). Rust uses the `mzdata` crate (pure Rust).
  The 2.4x ratio is typical wrapper/interop overhead and probably not
  worth optimizing — reusing pwiz's reader was a scaffolding decision.
- **Pass 1 scoring (~4s vs 15.7s, 3.93x slower)**: this is the primary
  perf target for C#. Per-entry CWT peak detection + apex selection +
  4-feature computation over 200K entries in parallel. Both tools
  parallelize (Rust rayon, C# Parallel.ForEach). The gap is likely
  from: (a) f64 managed math loops vs Rust's LLVM auto-vectorization
  and (b) ndarray/BLAS dot products in Rust's XCorr (we flipped to
  f64 in Session 7 so it's now ddot, but C# uses plain managed loops).
- **Match dump (6s vs 1.6s)**: Rust is SLOWER here because of a post-
  scoring deduplication step — Rust iterates per (entry, window) pair
  and keeps the best match via HashMap dedup. C# scores each entry
  once (single window lookup) so no dedup needed. This is not a C#
  win to celebrate — it's that C# skips a step Rust does for
  multi-window precursors.

**Net**: C# at 99.9% fidelity point runs at ~2.4x Rust wall clock on this
benchmark. The primary scoring loop is ~4x slower; library load and
mzML parse contribute the rest. Expected improvement targets:
1. Wire up `LibraryBinaryCache` — saves ~8s on every run.
2. Hot-path SIMD / vectorize the CWT convolution and per-entry
   feature computation — primary target for closing the 4x scoring
   gap.
3. Accept mzML parse as fixed (ProteowizardWrapper dependency).

**Session 7 takeaways (add to Session 6 principles)**:
- **Use LINQ OrderBy for stable sorts** when porting from Rust. .NET
  List<T>.Sort is unstable (introsort); Rust Iterator::sort_by is
  stable. Matters for tie-breaking in argmax/argmin loops.
- **Tie-break direction matters** even for f64 values — ties DO occur
  in practice (zero intensities in XIC tails, equal correlation sums
  on short peaks). `>` gives first-wins, `>=` gives last-wins. Rust
  max_by gives last-wins; match with `>=`.
- **f32 vs f64 intermediate buffers cause ~4e-6 drift** in algorithms
  that accumulate hundreds of sqrt'd values through sliding windows.
  When comparing tools bit-for-bit, align the intermediate precision
  (either side works; f64 is often the right call for a C# port since
  C# is naturally f64).
- **Constants matter**: a one-line MIN_COELUTION_SPECTRA=3 vs =5
  difference accounted for ~6000 of 192,289 match-count delta. When
  two tools have the same algorithm but different match counts, check
  the constants first.
- **Text format traps**: %.6f half-way rounding (banker's vs
  round-half-up) produces thousands of text diffs on numerically
  identical values. Use F10 (or hex bits) to avoid.
