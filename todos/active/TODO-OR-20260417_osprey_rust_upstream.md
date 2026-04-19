# TODO-OR-20260417_osprey_rust_upstream.md

> **Product**: Osprey Rust (OR) — workflow rules differ from Skyline
> mainline. See `ai/docs/osprey-development-guide.md` for cargo
> commands, commit conventions, and upstream-PR workflow.

## Branch Information

- **Working repo**: `C:\proj\osprey-mm` (existing clone of
  `maccoss/osprey`, on `main`). No third working tree is created;
  earlier drafts of this TODO called for `C:\proj\osprey-upstream`
  -- that was simplified on 2026-04-17 since `osprey-mm` already
  tracks upstream `main` cleanly and will eventually be renamed to
  `osprey` once the fork is retired.
- **Remote**: `git@github.com:maccoss/osprey.git` (SSH; switched
  from HTTPS on 2026-04-17 to match Brendan's other repos).
- **Branches (one per batch)**: `diagnostics-port`,
  `hram-xcorr-pool`, `parallel-file-processing`
- **Branches pushed to**: `maccoss/osprey` (Brendan is a
  collaborator as of 2026-04-17)
- **Created**: 2026-04-17
- **Status (end of 2026-04-18 extended session)**: **Three PRs open
  on `maccoss/osprey`**, all MERGEABLE, all Copilot threads resolved,
  awaiting Mike's review.
  - PR #9 `diagnostics-port`: Batch 1 (cross-impl bisection
    infrastructure). +1,129/0, purely additive.
    https://github.com/maccoss/osprey/pull/9
  - PR #10 `loess-classical-robust`: Cleveland 1979 robust LOESS
    toggle behind `OSPREY_LOESS_CLASSICAL_ROBUST=1` (strict `==1`).
    +~60/5, two new regression tests.
    https://github.com/maccoss/osprey/pull/10
  - PR #11 `cross-impl-regression-tests`: Five cross-impl tests.
    +331/0, test-only.
    https://github.com/maccoss/osprey/pull/11
  Batches 2a and 2b remain open — next session's work.
- **Fork retirement unblocked**: With PRs #9/#10/#11 merged,
  `brendanx67/osprey` has no unique content. OspreySharp migrated to
  pure f32 (pwiz commit `03b19c221` on
  `Skyline/work/20260409_osprey_sharp`), so the fork's `c95b36c` f64
  alignment flip is obsolete. Fork can be abandoned once Mike merges.

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
   **As of 2026-04-17 all four are merged, plus `#8`** (xcorr-bin-dedup
   landed earlier than expected; still out of scope for these batches).
2. `C:\proj\osprey-mm` on `main`, synced with `origin/main`, clean.
3. Brendan's collaborator status confirmed -- push access to
   `maccoss/osprey` for branches.
4. Stellar and Astral test datasets at `D:\test\osprey-runs\
   {stellar,astral}\`.
5. Use the existing `C:\proj\osprey-mm` working tree (do NOT create
   a separate `osprey-upstream` folder):
   ```
   cd C:\proj\osprey-mm
   git fetch origin
   git checkout main && git pull --ff-only
   git log --oneline -10 | grep -E 'Merge pull request #(4|5|6|7)'
   ```
   Each batch branch is off `main` here, pushed to `maccoss/osprey`.
   `C:\proj\osprey` (the brendanx67 fork) stays intact as archive.

   **Bench-Scoring contention**: `osprey-mm` is also used as the
   upstream baseline in `Bench-Scoring.ps1`. Check out `main` before
   any benchmark run so the baseline isn't polluted by in-progress
   branch work.

## Batch 1 -- Port cross-implementation bisection diagnostics

**Reframing note (2026-04-17 session)**: Earlier drafts of this TODO
and the companion handoff doc described Batch 1 as a *refactor* that
would "extract" diagnostics already living in upstream. That was
wrong. Upstream `maccoss/osprey:main` has **zero** diagnostic dump
code -- the entire infrastructure (9 dump functions, 12 env vars)
lives only in the fork (`C:\proj\osprey`). Batch 1 is a **port**
from fork -> upstream, organized into new `diagnostics.rs` modules
from the start. No upstream call sites are being "replaced" because
none exist yet.

**Goal**: Single focused PR -- "Add cross-implementation bisection
diagnostics" -- that introduces to upstream:

- `crates/osprey-core/src/diagnostics.rs` -- shared primitives:
  env-var helpers, `format_f10` formatter, `exit_after_dump`
- `crates/osprey-scoring/src/diagnostics.rs` -- scoring-level dumps:
  `dump_cal_sample`, `dump_cal_windows`, `dump_cal_prefilter`
  (Rust-only; not on C# side), `dump_cal_match`, `dump_lda_scores`,
  `dump_cal_xic_entry`, `dump_mp_diag`
- `crates/osprey/src/diagnostics.rs` -- pipeline-level dumps:
  `dump_loess_input`, `dump_search_xic`, `dump_xcorr_scan`

Call sites are *added* to `batch.rs`, `calibration_ml.rs`,
`pipeline.rs` as thin `diagnostics::...` calls. The dump output
must be byte-identical to what the fork (`C:\proj\osprey`)
currently produces; the fork has been receiving all cross-impl
testing for the past week and Session 18 confirmed its dumps are
bit-identical to OspreySharp's 21/21 features on Stellar + Astral.

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

**Sizing**: Fork has ~23 diagnostic occurrences across 4 files
(`pipeline.rs`, `calibration_ml.rs`, `batch.rs`, `fdr/lib.rs`).
Upstream receives roughly that much logic plus three new
`diagnostics.rs` modules -- estimated 700-1000 LOC net addition.

**Validation**:
- `cargo test --workspace` passes on upstream post-port
- Per-dump byte-identical verification: capture **fork** dump output
  to `ai/.tmp/diag-before/` (the known-good reference), port to
  upstream, capture upstream output to `ai/.tmp/diag-after/`, `diff`
  each pair
- `Test-Features.ps1 -Dataset Stellar` and `-Dataset Astral` pass
  at ULP on upstream (no feature regression from the port)
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
| Diagnostics | `diagnostics-port` | `main` |
| HRAM XCorr cache | `hram-xcorr-pool` | `main` |
| Parallel files | `parallel-file-processing` | `main` |

All three are independent in code; order is tactical:

1. **Diagnostics first** -- lowest-risk, enables broader testing
2. **HRAM cache next** -- big measurable win; reviewer-friendly numbers
3. **Parallel files last** -- biggest architectural change; benefits
   from Mike's confidence built up through the first two

## Critical guardrails

- **Byte-identical dump output** (upstream post-port vs fork
  pre-port) is non-negotiable for the diagnostics batch -- cross-
  impl bisection depends on it. Run `diff` against the fork
  baseline (`ai/.tmp/diag-before/`) before committing each dump's
  port.
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
- `C:\proj\osprey-mm` becomes the only active working tree.
- Intended rename (Brendan, 2026-04-17): `osprey-mm` → `osprey`,
  and current `osprey` → `osprey-fork`. All future Rust work
  happens at `C:\proj\osprey` against `maccoss/osprey:main`.

## Session-opening protocol

For the new session that picks this up:

1. `mcp__status__get_project_status` to confirm branch state
2. Read `ai/.tmp/handoff-20260417-osprey-rust-upstream.md`
3. Read this TODO
4. Read `ai/docs/osprey-development-guide.md`
5. Verify maccoss/osprey PRs `#4-#7` merged; `git pull` in
   `C:\proj\osprey-mm` on `main`
6. Start Batch 1 (diagnostics port). **Capture fork dump output to
   `ai/.tmp/diag-before/` BEFORE touching upstream** -- that's the
   known-good reference (fork is bit-identical to OspreySharp per
   Session 18). See the Batch 1 section for why this is a port,
   not a refactor.
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

### 2026-04-17 to 2026-04-18 (long session)

**Branch**: `diagnostics-port` on `C:\proj\osprey-mm` (remote
`maccoss/osprey`, SSH). HEAD = `72ee65f "Add cross-implementation
bisection diagnostics"` — the squashed commit. Working tree has
additional uncommitted edits that still need to be amended into that
commit before push (see "End-of-session state" below).

**PRs #3–#8 status at session start**: all merged upstream on
2026-04-17. `fix/parquet-index-lookup` on the fork has 16 exclusive
commits from the merge-base (`4ec7dda`); four of those (`4db625c`,
`a07aae6`, `2d4a8ad`, `22fa4a9`) are now redundant with #3–#8 and
were skipped during the port, the rest are the diagnostic
infrastructure we want upstream.

#### What was delivered (in the squashed commit + working-tree edits)

1. **Port of diagnostic infrastructure from fork to upstream** —
   Batch 1 as described above. Originally framed as "refactor" but
   upstream had zero diagnostic code, so the work is a **port** and
   the TODO was corrected (see Batch 1 section).

2. **Three new `diagnostics` modules**, mirroring
   `pwiz.OspreySharp.OspreyDiagnostics` on the C# side:
   - `osprey-core::diagnostics` (86 lines): shared primitives —
     `format_f10`, `is_dump_enabled`, `exit_if_only`,
     `should_exit_after_calibration`, `should_exit_after_scoring`.
   - `osprey-scoring::diagnostics` (555 lines): `dump_cal_sample_*`,
     `dump_cal_windows_*`, `dump_cal_prefilter_*`, `dump_cal_match`,
     `dump_lda_scores`, plus a `CalXicEntryDump` struct (reads env
     vars once, checks per-entry) for the per-entry XIC dump.
   - `osprey::diagnostics` (345 lines): `dump_loess_input`,
     `dump_xcorr_scan`, `dump_mp_diag`, plus a `SearchXicDump`
     struct for the per-entry main-search XIC dump.
   - Call sites in `batch.rs`, `calibration_ml.rs`, `pipeline.rs`
     are thin `crate::diagnostics::...` calls.

3. **f32 → f64 flip in four `SpectralScorer` helpers**:
   `preprocess_spectrum_for_xcorr`, `preprocess_library_for_xcorr`,
   `apply_windowing_normalization`, `apply_sliding_window`,
   `xcorr_from_preprocessed`. The base versions all move to f64 so
   calibration scoring bit-identically matches C# OspreySharp. New
   `_f32` variant functions (`preprocess_*_f32`,
   `xcorr_from_preprocessed_f32`) run the same f64 arithmetic but
   narrow the *stored* cache to f32 — used by the main-search HRAM
   path in `pipeline.rs` to preserve the 400 KB-per-spectrum cache
   size (vs 800 KB at f64). This is exactly the fork's validated
   design (f64 base + f32-cache variant), not the misleading "f64
   throughout" that the intermediate commits showed.

4. **`batch.rs`**: diagnostic call sites + new
   `rt_calibration_for_diag: Option<&RTCalibration>` parameter on
   `run_coelution_calibration_scoring` (only way to thread the
   LOESS model into the xic_entry dump), plus
   `spec_xcorr_preprocessed: Vec<Vec<f64>>` in the calibration
   buffer. The f64 calibration buffer at unit-resolution binning is
   ~16 KB/spec × ~1K specs/window ≈ 16 MB transient per active
   window, released as each window finishes.

5. **`pipeline.rs`**: stage early-exit env vars
   (`OSPREY_EXIT_AFTER_CALIBRATION`, `OSPREY_EXIT_AFTER_SCORING`),
   diagnostic call sites throughout main search, `rt_calibration`
   threading on pass 2.

6. **Twelve new diagnostic env vars** (all `OSPREY_*`):
   `DUMP_CAL_SAMPLE`/`_ONLY`, `DUMP_CAL_WINDOWS`/`_ONLY`,
   `DUMP_CAL_PREFILTER`/`_ONLY`, `DUMP_CAL_MATCH`/`_ONLY`,
   `DUMP_LDA_SCORES`/`_ONLY`, `DUMP_LOESS_INPUT`/`_ONLY`,
   `DIAG_XIC_ENTRY_ID`+`DIAG_XIC_PASS`, `DIAG_SEARCH_ENTRY_IDS`,
   `DIAG_MP_SCAN`, `DIAG_XCORR_SCAN`, `EXIT_AFTER_CALIBRATION`,
   `EXIT_AFTER_SCORING`.

#### Stripped from the PR (follow-up PRs)

1. **`OSPREY_LOESS_CLASSICAL_ROBUST` + `classical_robust_iterations`
   config field in `osprey-chromatography/rt.rs`** — reverted. The
   Cleveland-1979 robust LOESS toggle is a small algorithmic change
   that deserves its own PR with its own justification. Brendan's
   guidance: _"we can do those in a separate PR that also argues the
   other approach is better than what is implemented in
   main/HEAD"_. OspreySharp already has two LOESS implementations
   and the default passes parity with maccoss/osprey main/HEAD.
   Will be **follow-up PR #2**.

2. **Five cross-implementation regression tests** (from fork commit
   `0cbbccd`): `test_xcorr_fragment_bin_dedup`,
   `test_libcosine_closest_by_mz`,
   `test_median_polish_convergence_after_both_sweeps`,
   `test_xcorr_windowing_normalization`,
   `test_xcorr_f64_vs_f32_precision_drift`. Removed from this PR —
   Brendan's guidance: a testing-only PR is an easy review-and-merge
   and shouldn't distract from the core diagnostics change. Will be
   **follow-up PR #3**.

#### Validation

- `cargo build --workspace --release`: clean.
- `cargo test --workspace`: all pass.
- `cargo clippy --workspace --all-targets -- -D warnings`: clean.
- **Stellar 21/21 PIN features at 1e-6** vs OspreySharp. Every
  surviving non-zero delta is a known floating-point ordering
  known-small effect, same as baseline.
- **Astral 21/21 PIN features at 1e-6** — confirmed with the f64
  base; later "cleanup" attempts that reverted to pure f32 broke
  Astral parity, proving the f64-base-with-f32-cache design is
  **load-bearing** for cross-impl agreement, not cosmetic.
- **Byte-identical dump output fork vs this PR**: 917,366 lines
  across 9 dumps (`rust_cal_grid.txt`, `rust_cal_match.txt`,
  `rust_cal_prefilter.txt`, `rust_cal_sample.txt`,
  `rust_cal_scalars.txt`, `rust_cal_windows.txt`,
  `rust_lda_scores.txt`, `rust_loess_input.txt`,
  `rust_xic_entry_0.txt`) match exactly on Stellar.

#### Memory / perf validation (against `origin/main`)

`Bench-Scoring.ps1` was extended (permanently) to:

- Always sample peak `WorkingSet64` via `Start-Process` + 500 ms
  polling and report peak RSS alongside wall-clock and per-stage
  timing. Rationale: _"every time we run it we are confronted with
  the memory use required to achieve the timing result."_
- Accept `-BaselineBin` + `-BaselineLabel` (+ `-BaselineType`) for
  A/B comparison, typically between `origin/main` and a proposed
  branch.
- Added `-SkipFork` (was only `-SkipUpstream` and `-SkipRust`; no
  way to run upstream + csharp without fork).
- Added `-SkipCSharp` (useful when doing Rust-only A/B for a PR).
- **Fixed Parse-RustStages regex bug**: the Stage-4 parse pattern
  was `'Scored (\d+) entries.*for Ste'` which only matched Stellar
  files. Now matches any dataset via `'Scored (\d+) entries\s+\(.*\)\s+for\s+'`.
- Switched the upstream benchmark's `EarlyExit` param from `$false`
  to `$true` since upstream (`osprey-mm`) now supports
  `OSPREY_EXIT_AFTER_SCORING` post-Batch-1 port.
- Relaxed the successful-runs gate from `<2` to `<1` so a single-
  iteration smoke test produces a results table.

For today's validation we created `C:\proj\osprey-mm-main` as a
detached-HEAD worktree at `origin/main` with **one extra line**
patched into `crates/osprey/src/pipeline.rs` so it honors
`OSPREY_EXIT_AFTER_SCORING=1` and exits at the same pipeline
checkpoint as our proposed build. The worktree is temporary — the
one-line patch is uncommitted and discarded after the PR work
completes.

**Stellar single-file, 3 warm iterations (unit resolution):**

| | Stg 1-4 | Peak RSS |
|---|---:|---:|
| Proposed (f64 + diag) | 24.7s | 4,326 MB |
| Baseline (origin/main + 1-line exit) | 25.7s | 4,356 MB |
| OspreySharp (C#) | 22.6s | 11,606 MB |

Delta proposed vs baseline: **−30 MB (−0.7%), −1.0s (−3.9%)**.
Within run-to-run variance. The f64 calibration buffer has **no
measurable memory cost** at unit-resolution binning.

**Astral single-file, 2 warm iterations (HRAM)**: in progress at
end of session; see `ai/.tmp/bench-astral.log`. Expected outcome
(same story): calibration memory is tiny compared to scoring
memory; scoring memory is unchanged because the HRAM per-window
cache continues to use the f32 variant. Next session should
confirm.

#### Architectural clarifications / critical rules added

- **`ai/CRITICAL-RULES.md`** now has a rule that `C:\proj\ai\.tmp\`
  is the **only** temp/scratch folder for work in `C:\proj`. Do
  not use `/tmp/`, `C:\tmp\`, or `%TEMP%`. Git Bash and PowerShell
  see `ai/.tmp` identically; the others diverge silently between
  shells.
- **Never strip comments as a side effect of unrelated edits.**
  Brendan's rule: _"All that 'mess' you just cleaned up, those were
  the bug fixes."_ Function-level doc comments and inline
  explanations in `preprocess_spectrum_for_xcorr` / `xcorr_at_scan`
  etc. describe the Comet convention and are load-bearing for
  future readers. Any comment that is still accurate in the f64
  form must be preserved during the flip; only the specific
  comments whose content became wrong (e.g. "BLAS sdot for f32
  slices" → "BLAS ddot for f64 slices") can be updated.
- **Minimal diff for upstream PRs.** Brendan's guidance: when Mike
  reviews the cumulative changes he should not see any stray,
  unintentional edits. All changes should be clearly tied to
  diagnostics (or to the f32→f64 decision, which is justified by
  bit-identical dump parity with C# at unit-resolution, with
  memory validated as non-regressive).

#### Critical mid-session scope reduction

The session originally aimed to bundle Batch 1 (diagnostics) with
the f32 → f64 calibration flip because the fork's dump output is
bit-identical to C# only when calibration runs in f64. Astral
benchmarking (`Bench-Scoring.ps1 -BaselineBin osprey-mm-main`)
exposed a real cost: **f64 leaked into the main-search preprocess
path via the `_f32` variant wrapper that computes in f64 and
narrows at the end**, adding **+317s (+60%) to S4 (main search)**
on Astral (1 iter cold; confirmed as the fork's steady-state on
warm runs too). Calibration itself (S3) was unaffected (+1s).

Brendan's call: strip f64 from this PR. _"It's not ready. I am
pretty sure it will not be easy to maintain parity and keep the
32-bit calculations osprey main uses. This is exactly the point
of paying the price to upstream changes we made very quickly in
the heat of a POC sprint: determine whether they can be
integrated in a lasting way that will enable side-by-side
development on a longer time scale."_

The strip took the PR from +1,591/-67 down to **+1,129/0** —
purely additive, no base-type changes, no `_f32`/`_f64` variants.
Call sites use upstream's existing f32 preprocessing unchanged.
Dump output on the xcorr-derived fields (cal_match xcorr column,
lda_scores, xcorr_scan) will reflect upstream's native f32
precision, which differs from C# OspreySharp by ~4-7e-6 in
practice. Cross-impl bisection still works at that noise floor;
true algorithmic divergence is still clearly visible above it.

#### Astral benchmark results (final)

With `Bench-Scoring.ps1` (new in PR #9: always-on memory
sampling, optional `-BaselineBin` for A/B against a second
upstream build):

Astral single file, Stages 1-4 (early exit):

    Metric         origin/main*    this PR      Delta
    -------------  ------------    ----------   --------
    Stg 1-4 total  627.6s          574.0s       -8.5%  (within cold variance)
    Peak RSS       33,044 MB       33,135 MB    +0.3%
    S3 Calibr.     23.0s           20.0s        -13%
    S4 Main srch   530.0s          488.0s       -8%

*origin/main built from a worktree at `C:\proj\osprey-mm-main`
with a 1-line `OSPREY_EXIT_AFTER_SCORING` patch (uncommitted,
thrown away after measurement). The worktree has been removed.

Stellar single file, Stages 1-4 (3-iteration median):

    Metric         origin/main     this PR      Delta
    -------------  ------------    ----------   -------
    Stg 1-4 total  25.7s           24.7s        -3.9%
    Peak RSS       4,356 MB        4,326 MB     -0.7%

Both datasets: no measurable cost when diagnostic env vars are
unset. Conclusion shown in the PR body: diagnostic call sites
are effectively free.

#### Bench-Scoring.ps1 improvements (kept permanently)

- Always-on memory: `WorkingSet64` polled every 500 ms via
  `Start-Process`. Peak RSS reported as a new column in the
  results table. Rationale: _"every time we run it we are
  confronted with the memory use required to achieve the timing
  result."_
- `-BaselineBin` + `-BaselineLabel` + `-BaselineType` for A/B
  comparison (e.g. origin/main vs a proposed branch).
- `-SkipFork` and `-SkipCSharp` added.
- `Parse-RustStages` regex fixed — it used `'for Ste'` and
  never matched Astral files.
- `ai/.tmp/bench-memory/` is the log directory (per the new
  `ai/.tmp`-is-the-only-temp-dir rule in CRITICAL-RULES.md).

#### Shipped PR scope

PR #9: https://github.com/maccoss/osprey/pull/9
HEAD: `72d1838` "Add cross-implementation bisection diagnostics"

Files (11 total, +1,129/-0):

    Cargo.lock                                  +1
    crates/osprey-core/Cargo.toml               +1
    crates/osprey-core/src/diagnostics.rs       +86  (NEW)
    crates/osprey-core/src/lib.rs               +1
    crates/osprey-scoring/src/batch.rs          +88
    crates/osprey-scoring/src/calibration_ml.rs +2
    crates/osprey-scoring/src/diagnostics.rs    +555 (NEW)
    crates/osprey-scoring/src/lib.rs            +1
    crates/osprey/src/diagnostics.rs            +345 (NEW)
    crates/osprey/src/lib.rs                    +3
    crates/osprey/src/pipeline.rs               +46

One public signature change: `run_coelution_calibration_scoring`
gets an 11th arg `rt_calibration_for_diag: Option<&RTCalibration>`
to thread the fitted LOESS model into the per-entry XIC dump. All
call sites updated in the same commit. The parameter is ignored
unless `OSPREY_DIAG_XIC_ENTRY_ID` is set.

Commit message and PR body are in `ai/.tmp/` for reference:
- `diagnostics-port-commit-msg.txt`
- `diagnostics-port-pr-body.md`

#### Follow-up PRs (status as of 2026-04-18 extended session)

1. **`OSPREY_LOESS_CLASSICAL_ROBUST` toggle** — shipped as PR #10.
2. **Cross-implementation regression tests** — shipped as PR #11.
3. **f32 → f64 calibration scoring** — **OBSOLETE**. The extended
   session proved OspreySharp can migrate to pure f32 to match
   upstream Rust's native f32 path (instead of dragging Rust up to
   f64 to match C#'s f64). The fork's `c95b36c` flip was solving the
   wrong direction.

#### Still open (next session)

- **Batch 2a** (XcorrScratchPool) — next priority.
- **Batch 2b** (Rayon file-level parallelism) — after 2a.

#### End-of-session artifacts (safe to delete after PR merges)

- `ai/.tmp/diagnostics-port-commit-msg.txt`
- `ai/.tmp/diagnostics-port-pr-body.md`
- `ai/.tmp/bench-astral-v*.log`
- `ai/.tmp/dump-compare-fork/`, `ai/.tmp/dump-compare-upstream-v*/`
- `ai/.tmp/bench-memory/` (new log dir for future bench runs —
  keep)
- `ai/.tmp/measure-astral-cold.ps1` (one-shot helper, superseded
  by `Bench-Scoring.ps1 -SkipFork -SkipCSharp`)

**Next session handoff (superseded)**: the 2026-04-18 handoff at
`ai/.tmp/handoff-20260418-osprey-diagnostics-pr9-shipped.md` is now
stale; see the newer entry below.

### 2026-04-18 (continued) — PR #9 rebase, f32 spike, PRs #10 + #11

Picked up from the earlier 2026-04-18 session. Output: three PRs open
on `maccoss/osprey` (all MERGEABLE, all Copilot threads resolved),
OspreySharp migrated to pure f32 upstream-equivalent, fork retirement
unblocked.

#### PR #9 rebase + Copilot review

v26.3.0 landed on `maccoss/osprey:main` between PR #9 posting and
review, producing a merge conflict in `pipeline.rs` and a type
mismatch (upstream's `scored_candidates` in main-search is now a
3-tuple with RT-penalized score, added in `dba7f4e`). Rebased onto
`7f7fcbf`; `dump_peaks` signature updated to accept the new tuple
(emits the raw coelution_score; ordering reflects upstream's
RT-penalized sort).

Copilot posted 9 inline comments. All addressed in commit `5e5d5f4`:
removed a hardcoded `DECOY_ALQFAQWWK` filter in `dump_mp_diag`,
dropped workspace-only `ai/scripts/DIAGNOSTICS.md` doc links, fixed
broken intradoc link, switched bare `{}` to `{:.10}` in
`dump_xcorr_scan`, relaxed the `osprey-core` module doc, noted the
`cal_match` scan column is a Rust-only extension, and added a
length-mismatch warn + header line to `dump_loess_input`. PR #9
head: `5e5d5f4`.

#### f32/f64 spike — key finding

The 2026-04-09/10 session chose f64-everywhere-in-Rust to match C#
OspreySharp's natural f64 (Math.Sqrt is double). That decision was
reasoned abstractly, not benchmarked the other direction. It caused
the Astral S4 regression that motivated the "Batch 2a + f64
calibration" follow-up plan. **The other direction was never
tested: make OspreySharp match upstream Rust's pure f32.**

Spike: flip OspreySharp's XCorr preprocess to pure f32 using
`(float)Math.Sqrt((double)x)` as the f32-sqrt proxy
(`MathF.Sqrt(float)` is .NET Core 2.0+ / not available in
OspreySharp's .NET Framework 4.7.2 target). Result on Stellar
`cal_match`:

| | Before (C# f64) | After (C# f32) |
|---|---:|---:|
| xcorr max \|d\| vs Rust f32 | 4.195e-6 | **1.000e-10** |
| rows bit-equal / 192,289 | 35 (0.02%) | 192,283 (99.997%) |

`(float)Math.Sqrt((double)x)` is bit-equivalent to Rust's native
`f32::sqrt` on this workload — zero ULP drift across 192K matches.
The 4e-6 drift was entirely from f64-compute-then-narrow in C#;
sqrt, bisquare weights, and transcendentals were never the issue.

#### OspreySharp f32 migration (productionized)

Three call sites flipped to pure f32 in pwiz commit `03b19c221` on
`Skyline/work/20260409_osprey_sharp`:

1. `SpectralScorer.cs::PreprocessSpectrumForXcorrInto` — HRAM
   main-search cache, now f32 throughout (was f64-compute-then-
   narrow). New public `PreprocessSpectrumForXcorrF32` helper.
2. `ResolutionStrategy.cs::UnitStrategy.PreprocessWindowSpectra` —
   unit-res main-search cache, f32 compute with lossless widen to
   double[] for downstream `XcorrFromPreprocessed(double[], ...)`.
3. `AnalysisPipeline.cs:1176` — calibration preprocess loop, same
   widen-to-double[] pattern.

Private helpers `ApplyWindowingNormalizationF` /
`ApplySlidingWindowF` added to `SpectralScorer`. Pwiz branch is
7 commits ahead of origin. ReSharper clean, 186 unit tests pass.

**Test-Features against upstream Rust (not fork)**:
- Stellar: **21/21 PASS** at 1e-6 (xcorr max 2.3e-7, sg_weighted 1.9e-7)
- Astral: **21/21 PASS** at 1e-6 (xcorr max 3.3e-7, sg_weighted 3.0e-7)

Astral wall-clock: Rust upstream 628.7–727.5s vs C# 125.5–215.2s
(single file, Stage 1-4 only). The 3-5x C# lead is exactly the gap
Batches 2a + 2b would close by porting C#'s pool + parallelism.

#### PR #10 — LOESS classical robust toggle

Ported from fork commit `5588082`. Default unchanged (historical
residual reuse); `OSPREY_LOESS_CLASSICAL_ROBUST=1` enables classical
Cleveland 1979 residual refresh per iteration. Strict
`== Ok("1")` env-var parsing matches OspreySharp's `IsOne` helper —
the earlier `is_ok()` had a latent cross-impl bug where
`OSPREY_LOESS_CLASSICAL_ROBUST=0` would silently enable the feature
in Rust but disable it in C#.

Copilot review (3 comments) addressed in commit `e5c749f`: strict
env-var parsing, clarified config docstring (crate doesn't read env
vars; the `osprey` binary maps), added two regression tests
(`test_loess_default_mode_is_iteration_invariant`,
`test_loess_classical_mode_diverges_from_default`). All threads
resolved. PR #10 head: `e5c749f`.

#### PR #11 — Cross-impl regression tests

Ported from fork commit `0cbbccd`. Five tests guard algorithmic
fidelity across implementations. My first port had a bug in
`test_median_polish_convergence_after_both_sweeps`: dropped the
`+ result.residuals[f_idx][s_idx]` term and the `.exp()` conversion,
which made the assertion fail on log-space output. Fixed in commit
`a21a19f` (mass-preservation identity:
`(overall + row + col + residuals).exp() == value`).

Copilot review (2 comments) addressed in commit `256ad1f`: rewrote
`test_xcorr_fragment_bin_dedup` to call
`preprocess_library_for_xcorr` + `xcorr_from_preprocessed` directly
(previous version deduplicated via `HashSet` inside the test,
making the assertion self-fulfilling). All threads resolved. PR #11
head: `256ad1f`.

#### Bench-Scoring.ps1 / Test-Features.ps1 defaults (suggested)

Once PRs land, flip `-RustTree` default from `Fork` to `Upstream` in
both scripts. Fork stays on disk as archive but is no longer the
baseline. Also consider auditing any remaining `C:\proj\osprey`
references in the AI scripts to ensure `C:\proj\osprey-mm` is the
primary path.

#### Batch 2a scope — audit still needed

Upstream has evolved since the TODO was written. Before porting,
next session should audit whether upstream's `pipeline.rs`
main-search already has a per-window preprocessed XCorr cache
(the `ctx.preprocessed_xcorr` parameter suggests yes), which
determines whether Batch 2a is pure pool-addition (small PR) or
pool + cache-wrapper addition (larger PR).

**Next session handoff**: read
`ai/.tmp/handoff-20260419-batch2a-xcorr-pool.md` before starting
work. The stale 2026-04-18 handoff at
`ai/.tmp/handoff-20260418-osprey-diagnostics-pr9-shipped.md` is
superseded.
