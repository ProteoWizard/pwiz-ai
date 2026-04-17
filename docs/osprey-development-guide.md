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
| `C:\proj\osprey` | `brendanx67/osprey` | **Historical fork.** Branches preserved as archive; do not extend. |

New work goes to branches on `maccoss/osprey` directly, never to
the fork. Push directly; create PR with
`gh pr create --repo maccoss/osprey`.

## Build and test commands

```bash
cargo build --workspace --release
cargo test --workspace                         # includes inline #[cfg(test)]
cargo clippy --workspace -- -D warnings        # Rust equivalent of ReSharper
cargo fmt --all -- --check
cargo test -p osprey-scoring                   # single crate
```

Targets **Rust 1.75+** (see workspace `rust-version`). Check
`rustup show` if you get toolchain-related compile errors.

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

## Environment variable reference

### Control / throttling

| Name | Purpose |
|---|---|
| `OSPREY_EXIT_AFTER_CALIBRATION` | Exit after Stage 3; skip main search |
| `OSPREY_EXIT_AFTER_SCORING` | Exit after Stage 4; skip FDR + blib |
| `OSPREY_LOAD_CALIBRATION` | Path to `.calibration.json` to load instead of running Stage 3 |
| `OSPREY_LOESS_CLASSICAL_ROBUST` | `1` = Cleveland (1979) robust LOESS; default matches Rust |
| `OSPREY_MAX_SCORING_WINDOWS` | Cap main-search windows for fast iteration under profilers |

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
| `OSPREY_DIAG_XIC_ENTRY_ID` + `OSPREY_DIAG_XIC_PASS` | `cs_xic_entry_<ID>.txt` | Per-entry cal XIC (exits after dump) |
| `OSPREY_DIAG_SEARCH_ENTRY_IDS` | `cs_search_xic_entry_<ID>.txt` | Main-search XIC for specific entries (no exit) |
| `OSPREY_DIAG_MP_SCAN` | `cs_mp_diag.txt` | Median polish for a specific scan |
| `OSPREY_DIAG_XCORR_SCAN` | `cs_xcorr_scan.txt` *(Rust-only)* | XCorr detail at a specific scan |

The C# side consolidates these in `pwiz.OspreySharp.OspreyDiagnostics`.
The Rust equivalent is staged in
`TODO-OR-20260417_osprey_rust_upstream.md` Batch 1.

## Cross-impl bisection methodology

When the two tools diverge on a dataset, debug from the first
divergent stage downstream. **Do not start by comparing top-level
counts or summary statistics** -- they hide the structure of the
drift. Bisect stage-by-stage, prove each matches via `diff`, never
compare downstream values before upstream is proven identical.

### Bisection walk order

Walk the checkpoints in sequence; advance only after the previous
one matches:

1. **Calibration sample** (`OSPREY_DUMP_CAL_SAMPLE=1 + OSPREY_CAL_SAMPLE_ONLY=1`)
2. **Calibration match** (`OSPREY_DUMP_CAL_MATCH=1 + OSPREY_CAL_MATCH_ONLY=1`)
3. **LDA scores + q_values** (`OSPREY_DUMP_LDA_SCORES=1 + OSPREY_LDA_SCORES_ONLY=1`)
4. **LOESS input** (`OSPREY_DUMP_LOESS_INPUT=1 + OSPREY_LOESS_INPUT_ONLY=1`)
5. **Main-search XICs** (`OSPREY_DIAG_SEARCH_ENTRY_IDS=id1,id2,...`)
6. **21 PIN features** (via `Test-Features.ps1`)

Diff the SORTED output at each stage. Look for structural patterns
(all decoys? all short peptides? all charge-3?), not aggregate stats.

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

- `ai/WORKFLOW.md` -- Skyline-mainline conventions (different
  product, different rules)
- `ai/docs/debugging-principles.md` -- "Cross-implementation
  bisection" section (generic protocol; this guide is the
  dataset-specific workflow)
- `ai/todos/active/TODO-OR-20260417_osprey_rust_upstream.md` --
  staged sprint to upstream diagnostics + perf to `maccoss/osprey`
- `ai/scripts/OspreySharp/` -- cross-impl test tooling (C# side):
  `Test-Features.ps1` (parity), `Bench-Scoring.ps1` (perf),
  `Profile-OspreySharp.ps1` (C# profiling)
- `pwiz_tools/OspreySharp/OspreySharp/OspreyDiagnostics.cs` --
  C# reference implementation for the diagnostic extraction Batch 1
  will mirror in Rust
- `pwiz_tools/OspreySharp/OspreySharp.Scoring/XcorrScratchPool.cs`
  -- per-window buffer reuse pattern Batch 2a will mirror
