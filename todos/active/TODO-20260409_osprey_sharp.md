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
- [x] Run Osprey on Stellar dataset (29,916 precursors, 26,523 peptides, 4,995 proteins at 1% FDR)
- [ ] Run Osprey on Astral dataset (in progress, ~1.5M peptide library)
- [ ] Scaffold `pwiz_tools/OspreySharp/` solution structure

## Remaining Tasks

### Phase 1: Project Setup
- [ ] Create `pwiz_tools/OspreySharp/` .NET solution mirroring Osprey's 7-crate layout:
  - `OspreySharp.Core` ← `osprey-core` (types, config, errors)
  - `OspreySharp.IO` ← `osprey-io` (mzML, blib, library loaders)
  - `OspreySharp.Chromatography` ← `osprey-chromatography` (peak detection, calibration)
  - `OspreySharp.Scoring` ← `osprey-scoring` (feature extraction, decoys, batch scoring)
  - `OspreySharp.FDR` ← `osprey-fdr` (Percolator SVM, TDC, protein parsimony)
  - `OspreySharp.ML` ← `osprey-ml` (linear SVM, matrix ops, PEP, q-values)
  - `OspreySharp` ← `osprey` (CLI + pipeline orchestration)
- [ ] Set up project references to Shared, BiblioSpec, pwiz_data_cli
- [ ] Developer setup doc (`docs/dev-setup.md`) — Rust reference oracle + C# build

### Phase 2: Core Types & Infrastructure
- [ ] Port `osprey-core/src/types.rs` → core types (LibraryEntry, Spectrum, FdrEntry, etc.)
- [ ] Port `osprey-core/src/config.rs` → OspreyConfig + YAML deserialization
- [ ] Port `osprey-ml/src/svm.rs` → LinearSvmClassifier
- [ ] Port `osprey-ml/src/matrix.rs` → matrix operations
- [ ] Set up Math.NET Numerics + MKL provider for BLAS

### Phase 3: I/O (leverage existing pwiz infrastructure)
- [ ] DIA-NN TSV library reader (port `osprey-io/src/library/diann.rs`)
- [ ] elib library reader (port `osprey-io/src/library/elib.rs`)
- [ ] blib library reader (reuse BiblioSpec / port `osprey-io/src/library/blib.rs`)
- [ ] mzML reader (wrap pwiz_data_cli.dll via ProteoWizardWrapper)
- [ ] blib writer with Osprey extension tables (reuse BiblioSpec + `osprey-io/src/output/blib.rs`)
- [ ] Parquet caching (Parquet.NET + ZSTD, SHA-256 metadata per `osprey/docs/12-intermediate-files.md`)

### Phase 4: Algorithms
- [ ] LOESS regression (port `osprey-chromatography/src/calibration/rt.rs`)
- [ ] CWT peak detection (port `osprey-chromatography/src/cwt.rs`)
- [ ] RT/mass calibration (port `osprey-chromatography/src/calibration/`)
- [ ] Decoy generation (port `osprey-scoring/src/lib.rs` DecoyGenerator)
- [ ] Feature extraction — 21-feature CoelutionFeatureSet (port `osprey-scoring/src/batch.rs`)
- [ ] Batch XCorr/cosine scoring (port `osprey-scoring/src/batch.rs` + `lib.rs`)
- [ ] Percolator-style SVM FDR (port `osprey-fdr/src/percolator.rs`)
- [ ] Target-decoy competition + q-values (port `osprey-fdr/src/lib.rs`)
- [ ] Protein parsimony + picked-protein FDR (port `osprey-fdr/src/protein.rs`)

### Phase 5: Pipeline & CLI
- [ ] Pipeline orchestration (port `osprey/src/pipeline.rs`)
- [ ] CLI entry point (port `osprey/src/main.rs`)
- [ ] End-to-end validation vs Osprey on Mike's test data

### Phase 6: Performance & Validation
- [ ] Benchmark C# vs Rust on Astral + Stellar datasets
- [ ] Profile hot paths (batch scoring, BLAS, mzML parsing)
- [ ] Validate on larger experiments (100+ file) on desktop/server hardware
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

**Astral run**: In progress at session end (larger library ~1.5M peptides, hram resolution).

**Test infrastructure created** (`C:\test\osprey-runs\`):
- `clean-run.ps1` - wipe Osprey runtime caches from a test data folder
- `clean-build.ps1` - cargo clean + full rebuild + test

**Next steps**:
- Complete Astral run and record results
- Run both datasets on desktop (i9, 64 GB) and NUMA server (72 cores, 512 GB)
- PR the parquet_index fix to Mike
- Begin scaffolding `pwiz_tools/OspreySharp/`
