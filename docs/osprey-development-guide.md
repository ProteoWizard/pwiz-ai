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
| `C:\proj\osprey-upstream` *(create when needed)* | `maccoss/osprey` | Primary working tree for new PRs. Brendan has push access (collaborator). |
| `C:\proj\osprey-mm` | `maccoss/osprey` | Read-only clone of upstream `main`. Used as Rust baseline in `Bench-Scoring.ps1`. |
| `C:\proj\osprey` | `brendanx67/osprey` | **Historical fork.** Branches (`fix/parquet-index-lookup`, `coelution-search`, etc.) preserved as archive. Do not extend. |

New work goes to branches on `maccoss/osprey` directly, never to
the fork. Push directly; create PR with
`gh pr create --repo maccoss/osprey`.

## Build and test commands

```bash
# Full workspace build
cargo build --workspace --release

# Run all tests (including inline #[cfg(test)] modules)
cargo test --workspace

# Lint (Rust equivalent of ReSharper inspection)
cargo clippy --workspace -- -D warnings

# Format check
cargo fmt --all -- --check

# Build + test a single crate
cargo test -p osprey-scoring
```

The project targets **Rust 1.75+** (see `Cargo.toml` workspace
`rust-version`). Check `rustup show` if you get compile errors
that look toolchain-related.

## Test data locations

Not committed to the repo; lives on the developer workstation:

- `D:\test\osprey-runs\stellar\` -- small Stellar DIA dataset
  (3 mzML files, ~1 GB each)
- `D:\test\osprey-runs\astral\` -- larger Astral HRAM dataset
  (3 mzML files, ~5-10 GB each)

Both have `.blib` or `.tsv` spectral libraries alongside the mzML.
Dataset-specific configuration lives in
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
OspreySharp. Use `-SkipUpstream` to skip the upstream Rust run when
not needed.

## Environment variable reference

### Control / throttling

| Name | Purpose |
|---|---|
| `OSPREY_EXIT_AFTER_CALIBRATION` | Exit after Stage 3 (calibration done); skip main search |
| `OSPREY_EXIT_AFTER_SCORING` | Exit after Stage 4 (main search done); skip FDR + blib |
| `OSPREY_LOAD_CALIBRATION` | Path to `.calibration.json` to load instead of running Stage 3 (bisection) |
| `OSPREY_LOESS_CLASSICAL_ROBUST` | `1` = use Cleveland (1979) robust LOESS; default matches Rust calibration_ml.rs |
| `OSPREY_MAX_SCORING_WINDOWS` | Cap main-search windows for fast iteration under profilers |

### Diagnostic dumps (cross-impl bisection)

Each dump has a `_DUMP` flag (write the file) and often an `_ONLY`
flag (exit after writing). Filenames begin with `cs_` on the C#
side and `rust_` on the Rust side (when the reference tool writes
them).

| Name | Output | Use |
|---|---|---|
| `OSPREY_DUMP_CAL_SAMPLE` + `_SAMPLE_ONLY` | `*.cs_cal_sample.txt`, `cs_cal_scalars.txt`, `cs_cal_grid.txt` | Stage 2 calibration sample |
| `OSPREY_DUMP_CAL_WINDOWS` + `_WINDOWS_ONLY` | `cs_cal_windows.txt` | Per-entry cal window selection |
| `OSPREY_DUMP_CAL_PREFILTER` + `_PREFILTER_ONLY` | `cs_cal_prefilter.txt` *(Rust-only for now)* | Pre-filter candidates |
| `OSPREY_DUMP_CAL_MATCH` + `_MATCH_ONLY` | `cs_cal_match.txt` | Per-entry calibration match |
| `OSPREY_DUMP_LDA_SCORES` + `_SCORES_ONLY` | `cs_lda_scores.txt` | LDA discriminant + q-value |
| `OSPREY_DUMP_LOESS_INPUT` + `_INPUT_ONLY` | `cs_loess_input.txt` | LOESS input pairs |
| `OSPREY_DIAG_XIC_ENTRY_ID` + `OSPREY_DIAG_XIC_PASS` | `cs_xic_entry_<ID>.txt` | Per-entry calibration XIC (exits after dump) |
| `OSPREY_DIAG_SEARCH_ENTRY_IDS` | `cs_search_xic_entry_<ID>.txt` | Main-search XIC for specific entries (does NOT exit) |
| `OSPREY_DIAG_MP_SCAN` | `cs_mp_diag.txt` | Median polish for a specific scan |
| `OSPREY_DIAG_XCORR_SCAN` | `cs_xcorr_scan.txt` *(Rust-only)* | XCorr detail at a specific scan |

The C# side consolidates these in `pwiz.OspreySharp.OspreyDiagnostics`
(Session 18, 2026-04-17). The Rust equivalent is deferred to
`TODO-OR-20260417_osprey_rust_upstream.md` Batch 1.

## Commit and PR conventions

**Follow the upstream convention** -- do NOT apply Skyline's 10-line
past-tense-title format to `maccoss/osprey` work. Look at recent
`maccoss/osprey` merge commits for style:

```bash
git log --oneline -20 --author="MacCoss"
git show <hash>  # see full message style
```

Key differences from Skyline WORKFLOW.md:

- **No CRLF requirement.** Rust convention is LF on all files.
  Do NOT run `fix-crlf.ps1` on the Rust working tree.
- **No `Co-Authored-By: Claude` trailer** unless Mike explicitly
  opts in. When in doubt, omit.
- **Reasonable prose is fine.** Upstream reviewers read longer
  messages; the Skyline 10-line cap is a Skyline-team convention.
- **Cross-references** to related PRs or issues are welcome
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

## Critical rules (Rust-specific)

- **Byte-identical dump preservation** is non-negotiable when
  touching diagnostic code. Cross-impl bisection against OspreySharp
  depends on it. Run `diff` before/after every dump extraction.
- **`cargo clippy -- -D warnings`** must pass before pushing. The
  project has no tolerance for clippy warnings on `main`.
- **Parity gate after any scoring/calibration change**: Stellar +
  Astral `Test-Features.ps1` at ULP.

## Cross-impl bisection methodology

When the two tools diverge on a dataset, the debugging approach is
fundamentally different from single-codebase debugging. **Do not
start by comparing top-level counts or summary statistics** — they
hide the structure of the drift. Bisect from the first selection or
randomized step downstream, prove match via `diff`, and never compare
downstream values before upstream is proven identical.

### The nested env-var gate protocol

The pipeline has discrete checkpoints; each has a dump + early-exit
pair so you can prove bit-identical agreement at that point before
moving on. Walk them in order:

1. **Calibration sample** (`OSPREY_DUMP_CAL_SAMPLE=1 +
   OSPREY_CAL_SAMPLE_ONLY=1`) — the initial ~100K library entries
   sampled for calibration. Must be identical before anything else
   matters.
2. **Calibration match** (`OSPREY_DUMP_CAL_MATCH=1 +
   OSPREY_CAL_MATCH_ONLY=1`) — 7 columns (scan, apex_rt,
   correlation, libcosine, top6, xcorr, snr) per sampled entry.
   First place where XCorr / LibCosine drift shows up.
3. **LDA scores + q_values** (`OSPREY_DUMP_LDA_SCORES=1 +
   OSPREY_LDA_SCORES_ONLY=1`) — per-entry discriminant and q_value
   after 3-fold CV. Tiny drifts from cal_match amplify here.
4. **LOESS input** (`OSPREY_DUMP_LOESS_INPUT=1 +
   OSPREY_LOESS_INPUT_ONLY=1`) — the (lib_rt, measured_rt) pairs
   fed to LOESS at machine-epsilon precision.
5. **Pass-2 LOESS model stats** — 10 numbers describing the fitted
   model (already logged; no separate env var).
6. **Main-search XICs** (`OSPREY_DIAG_SEARCH_ENTRY_IDS=id1,id2,...`)
   — per-fragment XIC values for the specified library entries.
   Does NOT early-exit; collects across the whole main search.
7. **CWT peak boundaries** — start/apex/end plus pairwise correlation
   per candidate peak. Dump alongside the XIC data.
8. **21 PIN features** — final stage, only worth comparing after
   every upstream stage above matches.

### F10 formatting and "it's just formatting" traps

Numeric formatting across .NET `F10` and Rust `{:.10}` DOES differ
at half-boundaries because .NET's default is banker's rounding
(round-half-to-even) while Rust rounds half-away-from-zero. A value
like `0.15` can format to `0.14` or `0.15` depending on language.

**Always** use the `F10()` helper in C# (`AnalysisPipeline.cs`, rounds
half-to-even BEFORE formatting) and `{:.10}` in Rust for dump output.
**Cast `float` to `double` before F10 formatting** in C# to defeat
the shortest-round-trip float formatter. When you see "max diff 3.6e-15
on the LOESS input, just formatting noise" — prove it with a raw
binary dump before you dismiss it. Mike's review rule (and ours):
treat formatting drift as a real drift until you've reproduced
bit-identical output.

### Bisection case study: the per-fragment Da tolerance bug

During Session 11 we saw `cal_match` counts diverge on Astral:
Rust 110,055 vs C# 120,532 (13K+ difference). The bisection walk
proceeded as follows:

1. **Cal sample**: identical. ✅
2. **Cal match**: counts differ, 6 of 7 columns match at ULP for the
   matched subset. Signal: 10K entries were matched in C# but not in
   Rust. `diff` the sorted `entry_id` columns to list exactly which
   entries differ.
3. Inspected the diff: every diverging entry was a peptide where C#
   had a wide Da tolerance (precursor-derived) but Rust had a narrow
   per-fragment Da tolerance. Found in `HasTopNFragmentMatch` — C#
   used one tolerance for ALL fragments derived from the precursor
   m/z, Rust computed per-fragment.
4. Fixed, re-ran: counts matched 110,055 = 110,055. Next column
   diff: `xcorr` drift at 1/110055 entries (a coarser unit-bin
   border case, 1e-3 magnitude). Follow that thread next.

The pattern: diff the SORTED output at each stage, look for structural
patterns (all decoys? all short peptides? all charge-3?), not just
aggregate stats.

## Testing patterns

### Translation-proof unit tests

`OspreySharp.Test` mirrors `osprey-scoring/src/lib.rs` and related
Rust modules. To keep tests useful across a port:

- **Explicit element types**: `var xs = new double[] { 1.0, 2.0 }` is
  ambiguous across `List<double>` / `Array<double>` /
  `IEnumerable<double>` when porting. Write `new List<double> { ... }`
  or `new double[] { ... }` explicitly to match the Rust type.
- **Translation-proof assertions** (CRITICAL-RULES): never use English
  text literals in asserts — breaks on translated builds. Use
  `AssertEx.Contains(msg, Resources.X)` not `Assert.IsTrue(msg.Contains("..."))`.
- **`AssertEx.Contains` / `AssertEx.AreClose`** over `Assert.IsTrue`:
  AssertEx supports debugger-break-on-fail, which is the difference
  between 20 minutes of investigation and 5.
- **Keep `Assert.IsNotNull` not `AssertEx.IsNotNull`**: ReSharper
  only recognizes `Assert.IsNotNull` as a null-guard.

### Bug-class regression tests

Every time you close a cross-impl divergence, add a regression test
named after the bug class. Phase 2 built ~18 of these (e.g.
`TestXcorrFragmentBinDedup`, `TestPerFragmentDaTolerance`,
`TestPercentileValueRounding`). The pattern:

1. A synthetic library + spectrum that triggers the bug.
2. An expected output precomputed from the Rust reference on a known
   bit-identical version.
3. The test passes iff the C# output matches the expected output.

These catch regressions when refactoring the hot path months later,
which happens.

### Cross-impl parity gate script

`Test-Features.ps1 -Dataset {Stellar|Astral}` is the gate. Run it:

- After every change to scoring, calibration, or XCorr internals.
- Before every commit that touches either implementation.
- As the final verification for an upstream PR.

The script per-feature threshold table (line ~240) is authoritative.
Tightening a threshold is fine; loosening requires a comment
explaining the source of the intrinsic drift (e.g. f32 HRAM cache
summation order vs BLAS sdot).

## Performance and profiling patterns

### Allocation hotspots dominate at scale

On .NET Framework 4.7.2 with server GC, the two worst allocation
patterns on the main-search hot path (HRAM Astral, ~11M candidates)
are:

1. **Per-call `double[NBins]` for XCorr preprocessing** — NBins ~100K
   for HRAM, 800 KB per array, hits the LOH, every call triggers
   gen-2 pressure. Fix: `XcorrScratchPool` at
   `OspreySharp.Scoring/XcorrScratchPool.cs`. Grows organically to
   ~NThreads sets, never shrinks, gen-2 holds the arrays for the
   full run.
2. **Per-candidate `bool[NBins]`** for fragment dedup — 100 KB each,
   ~66M allocations on Astral = 6.6 TB of gen-0 churn. Fix:
   `WindowXcorrCache.VisitedBins` — single array per window,
   O(n_fragments) selective-clear instead of O(NBins) Array.Clear.

When `gen2_count` stays constant across a run, you've eliminated LOH
churn. When it ticks up every window, you haven't. The
`[MEM pre/post-main-search]` log line reports it.

### dotTrace API integration

`ProfilerHooks.cs` wraps `JetBrains.Profiler.Api.MeasureProfiler` via
non-inlineable methods with try/catch (matches
`Skyline/TestRunnerLib/MemoryProfiler.cs`). Enable via:

```bash
pwsh -File ai/scripts/OspreySharp/Profile-OspreySharp.ps1 \
    -Dataset Astral -ScopeToMainSearch -MaxWindows 2 -TopN 30
```

`-ScopeToMainSearch` passes `--use-api --collect-data-from-start=off`
to dotTrace so the snapshot contains only the main-search loop
bracketed by `ProfilerHooks.Start/SaveAndStopMeasure`.
`-MaxWindows N` sets `OSPREY_MAX_SCORING_WINDOWS=N` (caps inner
`Parallel.ForEach(windows, ...)`). On Astral, `-MaxWindows 2` cuts
profile cycle time from ~15 min to ~2 min while still exercising
the hot paths representatively.

### Memory diagnosis toolkit

- Live during a run: `pwsh -File ai/.tmp/mem_check.ps1` (working set,
  private, system-free — creates if not there).
- End-of-stage: `ProfilerHooks.LogMemoryStats(LogInfo, "label")` emits
  `[MEM label] working_set=X GB (peak=Y GB), managed_heap=Z GB,
  peak_paged=W GB, gen2_count=N, loh_count=N`.
- Pool high-water: `[POOL] scratch_allocs=N, bins_allocs=N` at end of
  `RunCoelutionScoring` (pool.ScratchAllocCount / BinsAllocCount).

### When Rust looks faster than C# or vice versa

First check: are both processes compiled in release mode? `cargo
build --release` and `Build-OspreySharp.ps1` both do the right thing
but a Debug C# build competing against release Rust will be 10x off.

Second: cache state. Rust has a `.libcache` binary; C# doesn't. The
first run after a cache clear includes TSV parsing. Compare like to
like. `Bench-Scoring.ps1 -Iterations 3` runs a throwaway "cold" run
first, then timed iterations against the warm caches.

Third: server vs workstation GC. `OspreySharp.exe.config` has
`gcServer enabled="true"`. Without it you lose 30-50% on parallel
workloads. Confirm with `GC.IsServerGC` or check the .config file.

## Parallel Rust + C# gotchas

### Shared mutable state across parallel files

`OspreyConfig` is passed by reference to `ProcessFile`. Any mutation
of config during file processing leaks to sibling parallel files.
Session 14 found that `config.FragmentTolerance = calibratedTolerance`
after MS2 cal was overwriting concurrently across files. Fix:
`OspreyConfig.ShallowClone()` at the top of `ProcessFile`.

Lesson: treat the config as immutable post-entry. If you must adjust
it per-file, clone first. Test: `ai/.tmp/validate_file_parallelism
.ps1 -Dataset Stellar` runs seq/par2/parN modes, diffs per-file TSVs.
Exit 0 = bit-identical across parallelism modes.

### f32 vs f64 in XCorr

`maccoss/osprey` upstream is f32 throughout for XCorr. We flipped our
fork to f64 in session 7 for bit-identical alignment with C#, then
flipped back to f32 in session 14 narrowed-only-at-cache-store: the
preprocessing pipeline runs in f64, only the per-window
`preprocessed_xcorr` cache stores f32. This halves the 100K-bin cache
memory without losing precision for the calibration path.

C# mirrors: `SpectralScorer.PreprocessSpectrumForXcorrInto(spec,
scratch, float[] output)` uses f64 scratch internally, narrows at the
final `output[i] = (float)preprocessed[i]` line. The resulting drift
vs a pure-f64 cache is bounded at ~1e-7 absolute on xcorr score
(empirically confirmed on Astral 945K entries).

Cross-language sqrt parity: use `(intensity as f64).sqrt() as f32`
in Rust and `(float)Math.Sqrt((double)intensity)` in C# — both go
through f64 sqrt then round to f32, avoiding double-rounding drift.

### Randomness

Any `new Random()` without an explicit seed defaults to
`Environment.TickCount` in .NET and thread-time in Rust — DO NOT use
unseeded randoms anywhere in the scoring pipeline. The calibration
sampler uses seed 43 deliberately (matches Rust's `42 + attempt=1` on
first attempt). When adding new sampling, always pass an explicit
seed.

### Stable sort differences

Rust `sort()` is unstable; `sort_by()` is stable with a key function.
.NET `List<T>.Sort()` is QuickSort (unstable) with no stable option
without LINQ `OrderBy`. When the sorted output matters for parity,
use `OrderBy` in C# (stable, matches `sort_by` in Rust). When it
doesn't matter, unstable is fine but document the choice.

## Upstreaming to maccoss/osprey

Session 11 identified three Rust-side fixes that belong upstream:

1. **XCorr fragment bin dedup** (`scorer.xcorr()` +
   `xcorr_at_scan()` in `osprey-scoring/src/lib.rs`) — shared bins
   contribute once, matching Comet theoretical spectrum convention.
   Commit `4db625c` on our fork.
2. **DIA window bounds truncation** in
   `group_spectra_by_isolation_window` — preserves full-precision
   bounds so entry filtering uses the real bounds not truncated
   keys. Commit `a07aae6`.
3. **Unit-bin calibration XCorr scorer** — matches the intent of
   the existing "Always use unit resolution bins for calibration
   XCorr" comment. Commit `2d4a8ad`. 50x cheaper allocations.

Each is its own focused PR against `maccoss/osprey`. Avoid bundling.
When preparing the PR, rebase on upstream main first (`osprey-mm` is
the upstream baseline clone in `C:\proj\osprey-mm`); conflicts
usually show up around the batch scorer if Mike has touched it.

## See also

- `ai/WORKFLOW.md` -- Skyline-mainline conventions (different
  product, different rules)
- `ai/docs/debugging-principles.md` -- Cross-implementation
  bisection section (generic; this guide is the dataset-specific
  workflow)
- `ai/todos/active/TODO-OR-20260417_osprey_rust_upstream.md` --
  staged sprint to upstream diagnostics + perf
- `ai/todos/active/TODO-20260409_osprey_sharp.md` -- OspreySharp
  port history; `-phase1.md` / `-phase2.md` archives
- `ai/scripts/OspreySharp/` -- cross-impl test tooling (C# side);
  `Test-Features.ps1` is the parity gate
- `ai/scripts/OspreySharp/Bench-Scoring.ps1` -- official perf
  benchmark; `-MaxParallelFiles N` controls C# file-level
  parallelism
- `pwiz_tools/OspreySharp/OspreySharp/OspreyDiagnostics.cs` --
  C# reference implementation for diagnostic extraction
- `pwiz_tools/OspreySharp/OspreySharp.Scoring/XcorrScratchPool.cs`
  -- per-window buffer reuse pattern
