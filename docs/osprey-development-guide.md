# Osprey (Rust) Development Guide

Development conventions for work on the `maccoss/osprey` Rust
project. Referenced by `TODO-OR-*.md` files, which may have workflow
rules that differ from the Skyline-mainline conventions documented
in `ai/WORKFLOW.md`.

## Workspace structure

`maccoss/osprey` is a Cargo workspace with 7 crates:

| Crate | Role | Notable source |
|---|---|---|
| `osprey-core` | Data types, configs, enums | `src/types.rs`, `src/config.rs` |
| `osprey-io` | mzML reader, library loaders, blib writer | `src/mzml/parser.rs`, `src/library/` |
| `osprey-scoring` | XCorr, cosine, batch scoring | `src/lib.rs` (SpectralScorer), `src/batch.rs` |
| `osprey-chromatography` | RT calibration, peak detection | `src/calibration/`, `src/cwt.rs` |
| `osprey-ml` | Machine learning (SVM, matrix, q-value) | `src/svm.rs`, `src/matrix.rs` |
| `osprey-fdr` | Percolator, protein FDR | `src/percolator.rs` |
| `osprey` (binary) | Main entry + pipeline orchestration | `src/pipeline.rs`, `src/main.rs` |

Workspace manifest: `Cargo.toml` at the repo root lists all seven
as workspace members.

## Repositories

| Path | Remote | Purpose |
|---|---|---|
| `C:\proj\osprey` | `maccoss/osprey` (SSH) | **Primary working tree.** Branches for new PRs live here. Also serves as upstream baseline for `Bench-Scoring.ps1` when checked out to `main`. Brendan has push access. |
| `C:\proj\osprey-fork` | `brendanx67/osprey` | **Retired fork.** Preserved as archive; do not extend. Several session's scripts still reference it for legacy but new work ignores it. |

(Rename from `osprey-mm`/`osprey` to `osprey`/`osprey-fork` completed
2026-04-21. Any remaining scripts or docs that mention `osprey-mm`
should be updated to `osprey` when touched.)

New work goes to branches on `maccoss/osprey` directly, never to
the fork. Push directly; create PR with
`gh pr create --repo maccoss/osprey`.

**Bench-Scoring discipline**: `C:\proj\osprey` is shared between
active branch work and `Bench-Scoring.ps1`'s upstream-baseline role.
Before running a benchmark, check out `main` (`git checkout main`)
so the baseline measurement isn't polluted by in-progress changes.

## Build and test commands

**Use the wrapper scripts under `ai/scripts/OspreySharp/`**, not raw
`cargo` commands. Wrappers enforce a consistent build environment
across developer machines (independent of which Visual Studio version
happens to be installed), and also serve as the single place to thread
new knobs like `-OspreyRoot` through every caller.

The wrappers set:

- `CMAKE_GENERATOR = "Ninja"` -- avoids the `cmake` crate's
  auto-detected "Visual Studio NN YYYY" generator string, which will
  not match the `cmake.exe` on PATH once a developer installs a newer
  VS than the bundled `cmake.exe` knows about.
- `VCPKG_ROOT = "$env:USERPROFILE\vcpkg"` -- required by
  `openblas-src` and friends to locate prebuilt BLAS.

**One-time setup: Ninja must be on PATH.** Visual Studio installs
bundle a Ninja binary. Add the VS 2022 Community copy to the User
PATH once, then restart your shell:

```powershell
[Environment]::SetEnvironmentVariable(
    "Path",
    "$([Environment]::GetEnvironmentVariable('Path','User'));C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja",
    "User"
)
```

Prefer the VS 2022 path over VS 2026 preview -- the 2026 folder may
be renamed as the preview evolves. If VS is installed under a
non-Community edition (Professional, Enterprise), substitute the
edition name.

Raw `cargo build`/`test`/`clippy` works only if the developer happens
to have both of these set (e.g. in a shell profile) *and* the machine's
installed `cmake.exe` understands the `cmake` crate's picked generator.
That's fragile across machines; the wrapper is authoritative.

**Primary wrapper**:

```bash
# Build release (default is C:\proj\osprey = maccoss/osprey primary)
pwsh -File ./ai/scripts/OspreySharp/Build-OspreyRust.ps1

# Build a different tree (rare; e.g. the retired fork at C:\proj\osprey-fork)
pwsh -File ./ai/scripts/OspreySharp/Build-OspreyRust.ps1 -OspreyRoot C:/proj/osprey-fork

# With format + lint + tests (mirrors what CI runs -- use before every push)
pwsh -File ./ai/scripts/OspreySharp/Build-OspreyRust.ps1 -Fmt -Clippy -RunTests
```

**CI parity check**: the `maccoss/osprey` GitHub Actions workflow
runs `cargo fmt --check`, `cargo clippy --all-targets --all-features
-- -D warnings`, and `cargo test` on Linux/macOS/Windows. Running
the wrapper with `-Fmt -Clippy -RunTests` exercises the same gates
locally. A few lints are CI-only flavored (e.g.
`clippy::items-after-test-module` — test modules must be the last
item in the file, not sandwiched between pub items); check CI on the
first push of every new branch to catch these early.

**Raw cargo reference** (for understanding what the wrappers run):

```bash
cargo build --workspace --release
cargo test --workspace                         # includes inline #[cfg(test)]
cargo clippy --workspace -- -D warnings        # Rust equivalent of ReSharper
cargo fmt --all -- --check
cargo test -p osprey-scoring                   # single crate
```

Targets **Rust 1.75+** (see workspace `rust-version`). Check
`rustup show` if you get toolchain-related compile errors.

**If the wrappers don't cover your task** (e.g. full-workspace
test + clippy for a baseline sanity check, or running the binary from
a non-default tree): extend the existing script. See "Running against
a non-fork tree" below for script-by-script parameterization status.

### Running against a non-default tree

Under the post-2026-04-21 layout, `C:\proj\osprey` is the single
primary tree (what was previously `osprey-mm`). Scripts have
residual parameterization from the dual-tree era:

| Script | Accepts alternate tree? | Notes |
|---|---|---|
| `Build-OspreyRust.ps1` | `-OspreyRoot` param, default `C:\proj\osprey` | Works on any tree |
| `Bench-Scoring.ps1` | Hardcoded two-tree comparison (historical) | May need updating once the legacy fork references are swept out |
| `Run-Osprey.ps1` | Check before invoking on a non-default tree | Older script; may still hardcode a path |
| `Test-Features.ps1` | `-CsharpRoot` param with auto-detect across `pwiz-work1` / `pwiz` / `pwiz-work2` | The Rust side always uses `C:\proj\osprey` |

When extending these scripts, the canonical Rust root is
`C:\proj\osprey`. Do not reintroduce the `osprey-mm` name.

## Test data locations

Not committed; lives on the developer workstation:

- `D:\test\osprey-runs\stellar\` -- 3 Stellar mzML files, ~1 GB each
- `D:\test\osprey-runs\astral\` -- 3 Astral HRAM mzML files, ~5-10 GB each

Dataset-specific configuration:
`ai/scripts/OspreySharp/Dataset-Config.ps1`.

## Cross-implementation parity testing

The cross-impl bisection infrastructure lives on the C# side (under
`ai/scripts/OspreySharp/`) but drives both tools:

```
# Stellar parity (fast, ~2 min)
pwsh -File ./ai/scripts/OspreySharp/Test-Features.ps1 -Dataset Stellar

# Astral parity (slow, ~18 min)
pwsh -File ./ai/scripts/OspreySharp/Test-Features.ps1 -Dataset Astral

# Re-use existing Rust output (skip the ~16 min Rust run)
pwsh -File ./ai/scripts/OspreySharp/Test-Features.ps1 -Dataset Astral -SkipRust
```

All 21 PIN features must remain bit-identical at the `1E-06`
threshold. Run this gate after every Rust change that could affect
scoring or calibration.

**Perf benchmark**:

```
pwsh -File ./ai/scripts/OspreySharp/Bench-Scoring.ps1 -Dataset Stellar -Files Single -Iterations 3
```

Compares upstream Rust (`osprey-mm`), our fork Rust (`osprey`), and
OspreySharp. `-SkipUpstream` skips the upstream Rust run.

## HPC split CLI flags

Since the 2026-04-19 HPC split sprint, both tools expose CLI flags
that break the pipeline at Stage 4 / Stage 5 so workers can score in
parallel and a merge node runs FDR + .blib output:

| Flag | Behavior |
|---|---|
| `--no-join` | Run Stages 1-4 on the given `--input` mzML(s). Write per-file `.scores.parquet`. **Do NOT run Stage 5 FDR or write a blib.** Replaces the retired `OSPREY_EXIT_AFTER_SCORING` env var. |
| `--join-only` | Skip Stages 1-4. Read Parquet inputs via `--input-scores`, run Stage 5+ (Percolator FDR, reconciliation, protein FDR), write blib at `--output`. Mutually exclusive with `--no-join`/`--input`. |
| `--input-scores <PATH...>` | One or more `.scores.parquet` files (or a directory; non-recursive glob). Required when `--join-only` is set. |
| `--parquet-compression {zstd,snappy}` | Write the scores Parquet with the requested codec. Rust default is `zstd`; use `snappy` when the output must be read back by OspreySharp (Parquet.Net 3.x on .NET Framework supports Snappy only). Production default stays Zstd; Snappy is a cross-impl interop affordance. |

Parquet interop gotchas:

- **Version lock**: the Parquet footer validator aborts on a `major.minor`
  mismatch between the writer's `osprey.version` and the reader's.
  Rust and OspreySharp must share the same `major.minor` for a
  cross-impl Parquet to round-trip. When Rust bumps to a new minor
  (e.g., `26.4.0`), bump OspreySharp's `Program.VERSION` in lockstep.
- **Path-dependent library hash**: `library_identity_hash` hashes
  `lib_path.display()` verbatim, so passing `/d/test/...` (Bash-style)
  hashes differently from `D:\test\...` (Windows-style) even when
  the file is the same. Invoke cross-impl parity runs via `pwsh`
  with Windows-native paths so the hash matches across tools.
- **Snappy disables dictionary encoding** in Rust (RLE_DICTIONARY
  isn't supported by Parquet.Net 3.x). Expect ~3x larger files on
  the Snappy path compared to the default Zstd.

## Environment variable reference

### Control / throttling

| Name | Purpose |
|---|---|
| `OSPREY_EXIT_AFTER_CALIBRATION` | Exit after Stage 3; skip main search |
| `OSPREY_LOAD_CALIBRATION` | Path to `.calibration.json` to load instead of running Stage 3 |
| `OSPREY_LOESS_CLASSICAL_ROBUST` | `1` = Cleveland (1979) robust LOESS; default matches Rust |
| `OSPREY_MAX_SCORING_WINDOWS` | Cap main-search windows for fast iteration under profilers |
| `OSPREY_TRACE_PEPTIDE` | Modified-sequence filter for the per-peptide diagnostic trace (`[trace]` log lines across Stages 3-7). Comma-separated for multiple. Paired decoys auto-matched. |

`OSPREY_EXIT_AFTER_SCORING` (retired 2026-04-19) was replaced by the
`--no-join` CLI flag; bench/profile scripts have migrated.

### Diagnostic dumps (cross-impl bisection)

Each dump has a `_DUMP` flag (write the file) and often an `_ONLY`
flag (exit after writing). Filenames begin with `cs_` on the C#
side and `rust_` on the Rust side.

| Name | Output | Use |
|---|---|---|
| `OSPREY_DUMP_CAL_SAMPLE` + `_SAMPLE_ONLY` | `*.cs_cal_sample.txt`, `cs_cal_scalars.txt`, `cs_cal_grid.txt` | Stage 2 calibration sample |
| `OSPREY_DUMP_CAL_WINDOWS` + `_WINDOWS_ONLY` | `cs_cal_windows.txt` | Per-entry cal window selection |
| `OSPREY_DUMP_CAL_PREFILTER` + `_PREFILTER_ONLY` | `cs_cal_prefilter.txt` *(Rust-only for now)* | Pre-filter candidates |
| `OSPREY_DUMP_CAL_MATCH` + `_MATCH_ONLY` | `cs_cal_match.txt` | Per-entry calibration match |
| `OSPREY_DUMP_LDA_SCORES` + `_SCORES_ONLY` | `cs_lda_scores.txt` | LDA discriminant + q-value |
| `OSPREY_DUMP_LOESS_INPUT` + `_INPUT_ONLY` | `cs_loess_input.txt` | LOESS input pairs |
| `OSPREY_DUMP_STANDARDIZER` + `_STANDARDIZER_ONLY` | `*_stage5_standardizer.tsv` | Per-feature mean/std from `FeatureStandardizer` (Stage 5 boundary) |
| `OSPREY_DUMP_SUBSAMPLE` + `_SUBSAMPLE_ONLY` | `*_stage5_subsample.tsv` | Stage 5 best-per-precursor subsample membership + fold assignment per entry |
| `OSPREY_DUMP_SVM_WEIGHTS` + `_SVM_WEIGHTS_ONLY` | `*_stage5_svm_weights.tsv` | Per-fold final SVM weights + bias + iteration count |
| `OSPREY_DUMP_PERCOLATOR` + `_PERCOLATOR_ONLY` | `*_stage5_percolator.tsv` | End-of-Stage-5 per-FdrEntry dump: score, pep, 4 q-values |
| `OSPREY_DIAG_XIC_ENTRY_ID` + `OSPREY_DIAG_XIC_PASS` | `cs_xic_entry_<ID>.txt` | Per-entry cal XIC (exits after dump) |
| `OSPREY_DIAG_SEARCH_ENTRY_IDS` | `cs_search_xic_entry_<ID>.txt` | Main-search XIC for specific entries (no exit) |
| `OSPREY_DIAG_MP_SCAN` | `cs_mp_diag.txt` | Median polish for a specific scan |
| `OSPREY_DIAG_XCORR_SCAN` | `cs_xcorr_scan.txt` *(Rust-only)* | XCorr detail at a specific scan |

Stage 5 dumps all land via `osprey-fdr/src/percolator.rs` (Rust) and
`pwiz.OspreySharp.FDR.PercolatorFdr` (C#); the end-of-stage
Percolator dump also uses the main-crate `osprey/src/diagnostics.rs`.
Floats route through `osprey_core::diagnostics::format_f64_roundtrip`
(normalizes `-0.0` to `0`, stable for `NaN`/`inf`).

The C# side consolidates cal-phase dumps in
`pwiz.OspreySharp.OspreyDiagnostics`; Stage 5 dumps are inlined in
`PercolatorFdr.cs` (the `OspreySharp.FDR` assembly cannot reference
main-crate helpers due to a circular-dep risk).

## Cross-impl bisection methodology

When the two tools diverge on a dataset, debug from the first
divergent stage downstream. **Do not start by comparing top-level
counts or summary statistics** -- they hide the structure of the
drift. Bisect stage-by-stage, prove each matches via `diff`, never
compare downstream values before upstream is proven identical.

### Bisection walk order

Walk the checkpoints in sequence; advance only after the previous
one matches:

**Stages 1-4 (calibration + scoring):**

1. **Calibration sample** (`OSPREY_DUMP_CAL_SAMPLE=1 + OSPREY_CAL_SAMPLE_ONLY=1`)
2. **Calibration match** (`OSPREY_DUMP_CAL_MATCH=1 + OSPREY_CAL_MATCH_ONLY=1`)
3. **LDA scores + q_values** (`OSPREY_DUMP_LDA_SCORES=1 + OSPREY_LDA_SCORES_ONLY=1`)
4. **LOESS input** (`OSPREY_DUMP_LOESS_INPUT=1 + OSPREY_LOESS_INPUT_ONLY=1`)
5. **Main-search XICs** (`OSPREY_DIAG_SEARCH_ENTRY_IDS=id1,id2,...`)
6. **21 PIN features** (via `Test-Features.ps1` — Stellar + Astral must pass at ULP)

**Stage 5 (Percolator FDR) via `--join-only` on a canonical Rust
Parquet input** — the Stage 5 bisection uses the `OSPREY_DUMP_*`
dumps added by PR #18 (osprey) / the OspreySharp mirror PR:

7. **Feature standardizer** (`OSPREY_DUMP_STANDARDIZER=1 + OSPREY_STANDARDIZER_ONLY=1`)
   → per-feature mean + std. Divergence means feature extraction or
   standardizer math differs.
8. **Subsample + fold assignment** (`OSPREY_DUMP_SUBSAMPLE=1 + OSPREY_SUBSAMPLE_ONLY=1`)
   → per-entry `in_subsample` + `fold_id` + `native_position`.
   Divergence means input-array ordering or the stratified CV
   selection differs.
9. **Per-fold SVM weights** (`OSPREY_DUMP_SVM_WEIGHTS=1 + OSPREY_SVM_WEIGHTS_ONLY=1`)
   → 21 feature weights + bias per fold, plus iteration count. Isolates
   SVM training drift from Granholm calibration.
10. **End-of-Stage-5 Percolator** (`OSPREY_DUMP_PERCOLATOR=1 + OSPREY_PERCOLATOR_ONLY=1`)
    → per-FdrEntry `score, pep, run_precursor_q, run_peptide_q,
    experiment_precursor_q, experiment_peptide_q`. The acceptance
    gate. Compared via `ai/scripts/OspreySharp/Compare-Percolator.ps1`
    (hash-joins on `(file_name, entry_id)`, sort-order-agnostic —
    not the row-wise `diff` that `Compare-Diagnostic.ps1` uses).

Diff the SORTED output at each stage. Look for structural patterns
(all decoys? all short peptides? all charge-3?), not aggregate stats.

**Tool support**:

- `ai/scripts/OspreySharp/Compare-Diagnostic.ps1` — row-wise `diff`
  with context, drives Stages 1-4 dumps. Fails if the two tools
  render rows in different orders even when values match; invest in
  stable sort on both sides before diffing.
- `ai/scripts/OspreySharp/Compare-Percolator.ps1` — hash-joined
  per-column numeric compare with per-column thresholds; drives the
  Stage 5 Percolator dump. Extendable to other Stage 5+ dumps with
  `(file_name, entry_id)` keys.

### Numeric formatting is NOT just noise

.NET `F10` default rounds half-away-from-zero; Rust `{:.10}` rounds
half-to-even (banker's). A value like `0.15` can format differently.
OspreySharp's `OspreyDiagnostics.F10()` (C#) rounds half-to-even
before formatting to match Rust's `{:.10}`. The Rust diagnostics
side uses `{:.10}` directly.

**Cast `float` to `double` before F10 formatting** to defeat the
shortest-round-trip float formatter. When a "just formatting" drift
of 3e-15 appears on a LOESS input line, reproduce bit-identical
output by re-running through F10 before dismissing it. This
distinguishes true noise from a real algorithmic drift that happens
to round identically in 999 of 1000 cases.

## Parallel Rust + C# gotchas

Hard-won patterns from the OspreySharp port:

### Shared mutable state across parallel files

`OspreyConfig` is passed by reference to `ProcessFile`. Any mutation
during file processing leaks to sibling parallel files. Session 14
caught `config.FragmentTolerance = calibratedTolerance` overwriting
concurrently. Fix: `OspreyConfig.ShallowClone()` at the top of
`ProcessFile`. When Batch 2b brings parallel files to Rust, add
`OspreyConfig::clone()` with the same semantics.

Treat config as immutable post-entry. If you must adjust per-file,
clone first.

### f32 vs f64 in XCorr

`maccoss/osprey` stores f32 in the per-window `preprocessed_xcorr`
cache. Preprocessing runs in f64 internally; only the per-window
cache store narrows to f32. This halves the 100K-bin HRAM cache
memory without losing precision. C# mirrors via
`SpectralScorer.PreprocessSpectrumForXcorrInto(spec, scratch, float[]
output)`. Drift vs a pure-f64 cache is ~1e-7 absolute on xcorr score
(confirmed on Astral 945K entries).

Cross-language sqrt parity: `(intensity as f64).sqrt() as f32` in
Rust, `(float)Math.Sqrt((double)intensity)` in C#. Both go through
f64 sqrt then round to f32, avoiding double-rounding drift.

### Randomness

Never use unseeded randoms in the scoring pipeline. .NET's
`new Random()` defaults to `Environment.TickCount`; Rust defaults to
thread time. The calibration sampler uses seed 43 deliberately
(matches Rust's `42 + attempt=1` on first attempt). Always pass an
explicit seed.

**Custom `Xorshift64` PRNG**: both sides implement `Xorshift64`
(not stdlib `Random` / `thread_rng`) for fold-assignment shuffles
and SVM coordinate descent. `OspreySharp.ML.LinearSvmClassifier.cs`
has a unit test verifying byte-parity of the Rust and C# outputs at
`seed=42` (`MLTest.TestXorShiftMatchesRust`). Don't swap one side to
a different PRNG without the matching swap on the other.

### Determinism: sorted iteration + serial reduction

HashMap iteration in Rust is randomized per process; `.NET
Dictionary<,>` is insertion-ordered but not stable across logically
equivalent inserts. Any pipeline step that iterates a HashMap and
then feeds the output into a float accumulation has a per-process
drift risk that shows up as 1-ULP differences across runs.

Patterns the pipeline now relies on:

- **Sort the union of base_ids** before building competition
  winners in `compute_fdr_from_stubs` (`osprey-fdr/src/percolator.rs`).
  Don't iterate `targets.iter().chain(decoys.iter())` directly —
  that leaks HashMap order into `PepEstimator::fit_default`.
- **Serial `iter().fold()`** for the KDE `pdf` sum in
  `osprey-ml/src/pep.rs`. Rayon's `par_iter().sum()` is non-deterministic
  across calls; serial accumulation is left-to-right and
  deterministic for a fixed input (it is still order-dependent
  across different input permutations — same-input reproducibility is
  the invariant the downstream pipeline requires).
- **Deterministic tie-break** in `grid_search_c` (first-C wins on
  ties; matches the comment "first C as tiebreaker" that the Rust
  code didn't originally implement). `Iterator::max_by_key` returns
  the *last* tied element per stdlib docs — don't use it for
  tie-sensitive selection. Manual scan with strict `>` is what both
  tools now use.
- **Non-conservative FDR formula `n_decoy / n_target`** for
  internal grid-search counting in
  `count_passing_targets_svm` — matches `compute_qvalues` on the
  same path and `OspreySharp.FDR.PercolatorFdr.ComputeQvalues`. The
  conservative `(n_decoy + 1) / n_target` formula is reserved for
  final reported q-values (`ComputeConservativeQvalues`), not for
  hyperparameter-tuning heuristics.
- **`-0.0` normalized to `"0"`** in
  `osprey_core::diagnostics::format_f64_roundtrip`. Rust's default
  `{}` emits `-0` for `-0.0`; .NET's G17 emits `0`. Without
  normalization the two texts disagree even when the values are
  numerically equal. Route every float in a cross-impl dump
  through the shared formatter.

### Steel-thread parity doctrine

Cross-impl parity projects stall when a small bit-level gap blocks
the rest of the pipeline (a compression codec, a numerical
ordering, etc.). The working discipline, proven in Brendan's
K-score / Comet effort (Keller et al. 2006):

1. Establish bit-parity gates at every stage boundary (dumps + a
   compare script).
2. When a single stage won't close, add the **smallest possible
   switch** (env var, Cargo feature, or runtime flag) that lets the
   "non-default" side match the other for end-to-end testing. Keep
   the production default fast/correct.
3. Ship the switch as a **debt item** — always retire it by fixing
   the underlying gap, not by making it the default.

Active steel-thread switches:

- `--parquet-compression snappy` (Rust default Zstd; Snappy bridges
  to OspreySharp's Parquet.Net 3.x reader). Retires when OspreySharp
  grows Zstd support.

Historical (retired the same session they were introduced):

- `OSPREY_CSHARP_SCALAR_SVM` — was planned as a scalar-SVM shim;
  the root cause turned out to be a formula mismatch in
  `count_passing_targets_svm`, not the SVM math. Switch was removed
  before it landed upstream; see the TODO for the audit.

When proposing a new switch, ask: **is the underlying difference
worth fixing on one side instead?** If so, fix it and skip the
switch. The session where Stage 5 parity landed ended up replacing a
fully-drafted `OSPREY_CSHARP_SCALAR_SVM` switch with a 20-LOC fix in
`count_passing_targets_svm` once the switch had localized the gap.

### Stable vs unstable sort

Rust `sort()` is unstable; `sort_by()` with a key is stable. .NET
`List<T>.Sort()` is QuickSort (unstable). When sorted output matters
for parity, use LINQ `OrderBy` in C# (stable, matches Rust
`sort_by`). When it doesn't matter, document the choice.

### Explicit element types in tests

C# `var xs = new[] { 1, 2, 3 }` infers `int[]`, not `double[]`.
ReSharper's auto-fix to drop the explicit type broke
`MLTest.TestMatrixSlice` in Session 18 (integer inference mismatched
`double[]` on the comparison target). Keep `new double[] {...}` in
test assertions that compare against typed arrays. See STYLEGUIDE.md
"Array Literal Type Inference".

### Bug-class regression tests

Each time you close a cross-impl divergence, add a regression test
named after the bug class (e.g. `TestXcorrFragmentBinDedup`,
`TestPerFragmentDaTolerance`, `TestPercentileValueRounding`). Pattern:

1. Synthetic library + spectrum that triggers the bug
2. Expected output precomputed from a known bit-identical reference
3. Test passes iff output matches expected

Catches regressions during refactors months later.

## Performance patterns

### Allocation hotspots

On .NET Framework 4.7.2, the two worst hot-path patterns are:

1. **Per-call `double[NBins]`** for XCorr preprocessing (800 KB at
   HRAM NBins=100K hits LOH -> gen-2 pressure). Fixed by
   `XcorrScratchPool` at
   `pwiz_tools/OspreySharp/OspreySharp.Scoring/XcorrScratchPool.cs` --
   grows to NThreads sets, never shrinks, gen-2 holds the arrays.
2. **Per-candidate `bool[NBins]`** for fragment dedup (100 KB each).
   Fixed by `WindowXcorrCache.VisitedBins` with O(n_fragments)
   selective clear.

When `gen2_count` stays constant across a run, LOH churn is
eliminated. The `[MEM pre/post-main-search]` log line reports it.

Rust has Vec allocation instead of LOH but the pattern is the same.
Batch 2a of `TODO-OR-20260417_osprey_rust_upstream.md` brings the
pool + per-window cache pattern to Rust.

### Release vs debug

Both sides must run release mode for benchmarks. `cargo build
--release` and `Build-OspreySharp.ps1 -Configuration Release`. A
Debug C# build vs release Rust is 10x misleading.

### Server vs workstation GC

`OspreySharp.exe.config` sets `gcServer enabled="true"`. Without it
you lose 30-50% on parallel workloads. Confirm with `GC.IsServerGC`
or check the .config file.

### Profiling C# via dotTrace

`ProfilerHooks.cs` wraps `JetBrains.Profiler.Api.MeasureProfiler`.
Drive via:

```
pwsh -File ai/scripts/OspreySharp/Profile-OspreySharp.ps1 \
    -Dataset Astral -ScopeToMainSearch -MaxWindows 2 -TopN 30
```

`-MaxWindows N` sets `OSPREY_MAX_SCORING_WINDOWS=N` so profile cycle
time stays small (Astral ~15 min -> ~2 min with `-MaxWindows 2`).

Rust equivalent: `cargo flamegraph` or `perf record / perf report`
with `OSPREY_MAX_SCORING_WINDOWS` equally applicable.

## Commit and PR conventions

**Follow the upstream convention** -- do NOT apply Skyline's 10-line
past-tense-title format to `maccoss/osprey` work. Look at recent
`maccoss/osprey` merge commits:

```bash
git log --oneline -20 --author="MacCoss"
git show <hash>
```

Differences from Skyline WORKFLOW.md:

- **No CRLF requirement.** Rust convention is LF. Do NOT run
  `fix-crlf.ps1` on the Rust working tree.
- **No `Co-Authored-By: Claude` trailer** unless Mike opts in.
- **Reasonable prose is fine.** The Skyline 10-line cap is a
  Skyline-team convention.
- **Cross-references** to related PRs are welcome
  (`Follow-up to #3`, `Relates to osprey#12`).

**PR creation**:

```bash
gh pr create --repo maccoss/osprey \
    --base main \
    --head diagnostics-extraction \
    --title "Add cross-implementation bisection diagnostics" \
    --body "$(cat <<'EOF'
## Summary
- ...
## Test plan
- [x] ...
EOF
)"
```

## Differences from Skyline's WORKFLOW.md

| Topic | Skyline default | Osprey Rust |
|---|---|---|
| Shell | `pwsh` required | Any shell; `cargo` is the tool |
| Build | MSBuild / quickbuild.bat | `cargo build --workspace` |
| Tests | `TestRunner.exe` + vstest.console.exe | `cargo test --workspace` |
| Static analysis | ReSharper / `jb inspectcode` | `cargo clippy -- -D warnings` |
| Code format | CRLF, space indent | LF, rustfmt defaults |
| Naming | `_camelCase` private, `PascalCase` types | snake_case everywhere |
| Commit title | Past tense, <=10 lines total | Upstream-style prose |
| Co-author trailer | `Co-Authored-By: Claude <noreply@anthropic.com>` | Only if maintainer opts in |
| PR target | `ProteoWizard/pwiz:master` | `maccoss/osprey:main` |
| Review gate | Brendan / Nick | Mike (maccoss) |
| Resource strings | Required for user text | N/A -- `log::info!` and CLI output are plain |

## Critical rules

- **Byte-identical dump preservation** when touching diagnostic
  code. Cross-impl bisection depends on it. `diff` before/after
  every dump extraction.
- **`cargo clippy -- -D warnings`** must pass before pushing.
- **Parity gate after any scoring/calibration change**: Stellar +
  Astral `Test-Features.ps1` at ULP.

## See also

- `C:\proj\osprey\CLAUDE.md` -- project overview (architecture, CI,
  critical invariants). Read this first when joining the Rust side.
- `ai/WORKFLOW.md` -- Skyline-mainline conventions (different
  product, different rules)
- `ai/docs/debugging-principles.md` -- "Cross-implementation
  bisection" section (generic protocol; this guide is the
  dataset-specific workflow)
- `ai/todos/active/TODO-OR-20260417_osprey_rust_upstream.md` --
  staged sprint to upstream diagnostics + perf to `maccoss/osprey`
- `ai/todos/active/TODO-20260423_osprey_sharp.md` -- OspreySharp
  Phase 4 sprint (Stages 6-8 cross-impl parity walk). Bisection
  methodology + Stage 5 resolution documented in
  `ai/todos/completed/TODO-20260422_ospreysharp_stage5_diagnostics.md`.
- `ai/scripts/OspreySharp/` -- cross-impl test tooling (C# side):
  `Test-Features.ps1` (Stages 1-4 parity), `Compare-Diagnostic.ps1`
  (row-wise dump diff), `Compare-Percolator.ps1` (hash-joined
  Stage 5 compare), `Bench-Scoring.ps1` (perf),
  `Profile-OspreySharp.ps1` (C# profiling)
- `pwiz_tools/OspreySharp/OspreySharp/OspreyDiagnostics.cs` --
  C# diagnostic constants + cal-phase dump methods
- `pwiz_tools/OspreySharp/OspreySharp.FDR/PercolatorFdr.cs` -- C#
  Stage 5 implementation with the four inlined dumps
- `pwiz_tools/OspreySharp/OspreySharp.Scoring/XcorrScratchPool.cs`
  -- per-window buffer reuse pattern Batch 2a will mirror
