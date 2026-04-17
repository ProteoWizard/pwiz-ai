# TODO-OR-20260417_osprey_rust_upstream.md

> **Product**: Osprey Rust (OR) — workflow rules differ from Skyline
> mainline. See `ai/docs/osprey-development-guide.md` for cargo
> commands, commit conventions, and upstream-PR workflow.

## Branch Information

- **Working repo**: `C:\proj\osprey-upstream` (to be created from
  `maccoss/osprey:main`)
- **Branches (one per batch)**: `diagnostics-extraction`,
  `hram-xcorr-pool`, `parallel-file-processing`
- **Branches pushed to**: `maccoss/osprey` (Brendan is a
  collaborator as of 2026-04-17)
- **Created**: 2026-04-17
- **Status**: Not started -- staged for a fresh session

## Objective

Upstream three coherent improvements to `maccoss/osprey` that our
fork has validated through the OspreySharp port:

1. **Diagnostics extraction** -- cross-implementation bisection
   dumps + env-var control, pulled into dedicated `diagnostics.rs`
   modules so the cross-impl testing infrastructure lives upstream
2. **Performance 2a: HRAM XCorr array cache** -- `XcorrScratchPool`
   + per-window preprocessed cache pattern (the C# side demonstrated
   a 4.5x speedup from pooling alone)
3. **Performance 2b: Parallel file processing** -- Rayon file-level
   parallelism with per-file config cloning and inner-thread scaling

Value proposition to Mike: real-dataset (Stellar + Astral) accuracy
and performance testing infrastructure that goes well beyond unit
tests, plus two large measured perf wins. Mike added Brendan as a
collaborator on 2026-04-17 after the Stage 1 bugfix PRs (#3 merged,
#4-#8 in review); now is the natural time to contribute the
diagnostic and performance infrastructure that makes the ongoing
cross-impl collaboration sustainable.

## Prerequisites

1. `maccoss/osprey` PRs `#4`, `#5`, `#6`, `#7` merged to `main`.
   (`#8` optional -- algorithmic implications; safe to defer.)
2. `C:\proj\osprey-mm` synced to latest `maccoss/osprey:main`.
3. Brendan's collaborator status confirmed -- push access to
   `maccoss/osprey` for branches.
4. Stellar and Astral test datasets at `D:\test\osprey-runs\
   {stellar,astral}\`.
5. Fresh Rust working tree at `C:\proj\osprey-upstream`:
   ```
   git clone git@github.com:maccoss/osprey.git C:\proj\osprey-upstream
   cd C:\proj\osprey-upstream
   git log --oneline -5
   ```
   Each batch branch is off `main` here, pushed to `maccoss/osprey`.
   `C:\proj\osprey` (the brendanx67 fork) stays intact as archive.

## Batch 1 -- Diagnostics extraction (mirror OspreyDiagnostics)

**Goal**: Single focused PR -- "Add cross-implementation bisection
diagnostics" -- that introduces:

- `crates/osprey-core/src/diagnostics.rs` -- shared primitives:
  env-var helpers, `format_f10` formatter, `exit_after_dump`
- `crates/osprey-scoring/src/diagnostics.rs` -- scoring-level dumps:
  `dump_cal_sample`, `dump_cal_windows`, `dump_cal_prefilter`
  (Rust-only; not on C# side), `dump_cal_match`, `dump_lda_scores`,
  `dump_cal_xic_entry`, `dump_mp_diag`
- `crates/osprey/src/diagnostics.rs` -- pipeline-level dumps:
  `dump_loess_input`, `dump_search_xic`, `dump_xcorr_scan`

Call sites in `batch.rs`, `calibration_ml.rs`, `pipeline.rs`
replaced with thin `diagnostics::...` calls. Every dump emits
byte-identical output to what upstream currently produces.

**Env vars consolidated (12 diagnostic names)**:
- `OSPREY_DUMP_CAL_SAMPLE` + `OSPREY_CAL_SAMPLE_ONLY`
- `OSPREY_DUMP_CAL_WINDOWS` + `OSPREY_CAL_WINDOWS_ONLY`
- `OSPREY_DUMP_CAL_PREFILTER` + `OSPREY_CAL_PREFILTER_ONLY`
- `OSPREY_DUMP_CAL_MATCH` + `OSPREY_CAL_MATCH_ONLY`
- `OSPREY_DUMP_LDA_SCORES` + `OSPREY_LDA_SCORES_ONLY`
- `OSPREY_DUMP_LOESS_INPUT` + `OSPREY_LOESS_INPUT_ONLY`
- `OSPREY_DIAG_XIC_ENTRY_ID` + `OSPREY_DIAG_XIC_PASS`
- `OSPREY_DIAG_SEARCH_ENTRY_IDS`
- `OSPREY_DIAG_MP_SCAN`
- `OSPREY_DIAG_XCORR_SCAN`

**Why this comes first**: Zero algorithmic impact -- easiest review.
Once landed, `maccoss/osprey` gains the ability to be bisected
against future C# changes without extra machinery, and Mike gets a
testing surface that complements unit tests with real-dataset
accuracy gates.

**Sizing**: 700-1000 LOC net delta across 3 crates.

**Validation**:
- `cargo test --workspace` passes
- Per-dump byte-identical verification: capture pre-refactor output
  to `ai/.tmp/diag-before/`, refactor, capture post output, `diff`
- `Test-Features.ps1 -Dataset Stellar` and `-Dataset Astral` pass
  at ULP (cross-impl parity gate)
- Rust wall-clock (Stellar single-file, 3-iteration median) does
  not regress beyond +/-3%

## Batch 2a -- HRAM XCorr array cache

**Goal**: Bring the C# `XcorrScratchPool` + `WindowXcorrCache`
pattern to Rust. Primitives already exist
(`preprocess_library_for_xcorr`, `xcorr_from_preprocessed`) --
missing piece is the pool + per-window cache wrapper.

**Evidence from C# (Session 12-13)**:

| Variant | Astral Stage 1-4 | Ratio vs Rust |
|---|---:|---:|
| Baseline (no pool) | 4341.9s | 4.93x |
| + XcorrScratchPool | 964.0s | 1.09x |
| + HRAM pre-preprocess per window | 568.6s | 0.64x |
| + f32 HRAM cache | 361.9s | 0.42x |
| + visitedBins pooling | 120.9s | 0.13x |

**Scope**:

- Add `XcorrScratchPool` in
  `crates/osprey-scoring/src/xcorr_pool.rs` (or inline in
  `scorer.rs`)
- Replace per-call `Vec<f64>` / `Vec<f32>` allocations on the hot
  path with pool rent/return. Expected single-PR win: matches the
  C# "4341.9s -> 964.0s" jump from pool alone
- If per-window pre-preprocessing isn't already the default on the
  Rust HRAM path, add it (C# `HramStrategy.PreprocessWindowSpectra`
  equivalent)
- Optional follow-up: `visitedBins` pooling -- only if profiling
  shows `Vec::clear` in the hot path after the first PR

**Validation**:
- `cargo test --workspace` passes
- Astral single-file before/after: Rust drops meaningfully
  (targeting ~200-400s from current ~900s)
- Stellar single-file: neutral or slight improvement
- No algorithmic change -> bit-identical features

## Batch 2b -- Parallel file processing

**Goal**: Bring Rayon file-level parallelism to the Rust pipeline,
with per-file config cloning (mirrors C#
`OspreyConfig.ShallowClone()` from Session 12).

**Evidence from C# (Session 14-16)**: Rust is currently linear in
file count (`~3 * single_file_time`). C# reaches ~97% parallel
efficiency (Astral par-3 = 342s vs Astral seq = 380s = 1.11x
wall-time).

**Scope**:

- `crates/osprey/src/pipeline.rs`: wrap file loop in `par_iter()`
  (Rayon)
- Add `OspreyConfig::clone()` or `shallow_clone` method -- a few
  fields like `fragment_tolerance` get mutated per-file after MS2
  calibration; those must not leak between parallel files
- Add `OSPREY_MAX_PARALLEL_FILES` env var (mirrors C# side); wire
  via scoped Rayon `ThreadPoolBuilder`
- Per-file inner thread scaling: N files in parallel ->
  `num_cpus / N` threads per file to avoid oversubscription
  (C# captured this in `EffectiveFileParallelism`)
- mzML read serialization: a single `Mutex`/`Semaphore` gates the
  mzML read phase while main-search runs free (C# Session 15 found
  60% wall-time variance without this gate)

**Validation**:
- `cargo test --workspace` passes
- Astral 3-file: target ~3x speedup (from ~3000s sequential to
  ~1000s par-3)
- Memory high-water: per-file thread scaling keeps 3 x working set
  under 64 GB (confirm via `VmHWM` on Linux,
  `GetProcessMemoryInfo` on Windows)
- Features bit-identical to sequential

## Branch and PR strategy

Each batch is a branch off `maccoss/osprey:main`, pushed to
`maccoss/osprey`, PR'd for review:

| Batch | Branch name | Depends on |
|---|---|---|
| Diagnostics | `diagnostics-extraction` | `main` |
| HRAM XCorr cache | `hram-xcorr-pool` | `main` |
| Parallel files | `parallel-file-processing` | `main` |

All three are independent in code; order is tactical:

1. **Diagnostics first** -- lowest-risk, enables broader testing
2. **HRAM cache next** -- big measurable win; reviewer-friendly numbers
3. **Parallel files last** -- biggest architectural change; benefits
   from Mike's confidence built up through the first two

## Critical guardrails

- **Byte-identical dump preservation** is non-negotiable for the
  diagnostics batch -- cross-impl bisection depends on it. Run
  `diff` before committing each dump's extraction.
- **No algorithmic changes** in Batches 1 and 2a. Batch 2b adds
  config semantics (per-file clone) but preserves scoring
  determinism.
- **Parity gate after every batch**: Stellar + Astral
  `Test-Features.ps1` must pass at ULP before PR creation.
- **One batch per PR.** Do not bundle; each batch reviews in
  isolation and Mike can accept/decline each on its merits.
- **`Test-Features.ps1` on the C# side** stays unchanged; the
  upstream Rust must keep producing the same dump file formats so
  the existing comparison tooling keeps working.

## Our fork's fate

After all three batches merge upstream:

- `brendanx67/osprey` branches
  (`fix/parquet-index-lookup`, `coelution-search`,
  `peak-detection-improvement`, `performance-optimization`) become
  historical archive. Keep them on the remote; do not continue
  development there.
- `C:\proj\osprey` working tree can be left as-is or repointed at
  `maccoss/osprey`.
- `C:\proj\osprey-upstream` becomes the primary workspace for all
  future Rust work.

## Session-opening protocol

For the new session that picks this up:

1. `mcp__status__get_project_status` to confirm branch state
2. Read `ai/.tmp/handoff-20260417-osprey-rust-upstream.md`
3. Read this TODO
4. Read `ai/docs/osprey-development-guide.md`
5. Verify maccoss/osprey PRs `#4-#7` merged; spin up
   `C:\proj\osprey-upstream`
6. Start Batch 1 (diagnostics). **Capture pre-refactor sample dumps
   to `ai/.tmp/diag-before/` BEFORE touching anything** so byte-
   identical verification is possible after.
7. Per batch: implement, `cargo test --workspace`, validate parity
   via `Test-Features.ps1`, PR to maccoss/osprey

## Out of scope

- `fix/parquet-index-lookup` changes themselves -- the name reflects
  stale earlier work; not obvious what it is now; do NOT port to
  upstream without revisiting its purpose first.
- Six OspreySharp follow-up findings (FeatureExtractor,
  stage-class split, PercolatorFdr split, SQLiteLibraryLoaderBase,
  AnalysisCache, regression-test extension) -- C# work, tracked
  separately.
- Upstream of PR `#8` (XCorr fragment bin dedup) -- still open
  pending Jimmy Eng review; not blocking any of the three batches.

## Progress log

*(Each session working on this TODO should append an entry here
summarizing what was done.)*
