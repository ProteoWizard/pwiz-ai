# TODO-20260527_svm_stage5_perf.md — Stage 5 SVM training: close the C# vs Rust perf gap

## Status

Active — sprint just opened, no commits yet.

## Branch Information

- **pwiz branch**: `Skyline/work/20260527_svm_stage5_perf` (to be created from `pwiz:master` HEAD)
- **osprey branch**: not opened yet — only if a Rust-side change is needed for cross-impl perf parity
- **ai branch**: `master`

## Background

The 2026-05-26 night-session perf table confirms a large C# vs Rust gap
in Stage 5 across all three storage locations:

| Location | Stellar Rust | Stellar C# | C#/Rust | Astral Rust | Astral C# | C#/Rust |
|---|---:|---:|---:|---:|---:|---:|
| Windows native | 1:06 | 1:52 | 1.69x | 1:23 | 5:01 | 3.63x |
| WSL /mnt/c    | 1:06 | 2:12 | 2.00x | 1:16 | 5:18 | 4.19x |
| WSL /home     | 1:05 | 2:09 | 1.98x | 1:12 | 5:16 | 4.36x |

Stage 5 is **first-pass FDR + reconciliation planning**, dominated on
both sides by the LinearSvm grid-search train loop.  Past sprints
parallelized the grid search and shaved cycles in the SVM hot path but
the gap is still 2x on Stellar / 4x on Astral, and it widens
super-linearly with dataset size — strongly suggesting the inner
training loop has different code-gen properties on the two runtimes
(vectorization, FMA, loop-carried deps) rather than just a constant-
factor overhead.

This sprint is a focused root-cause investigation on the SVM train
loop, with a goal of getting Stage 5 within ~30% of Rust on both
datasets without sacrificing parity (Test-Snapshot still bit-equal
post-change).

## Objective

1. **Measure**: produce a 3-column profile table
   `function | C# time | Rust time` for the top 30 functions in the
   Stage 5 C# profile, with each function's Rust counterpart wall in
   the third column.  Sort by C# time descending.  Bring the actual
   hotspots into focus before forming a fix hypothesis.
2. **Analyze**: for each top function, identify the specific
   code-gen / algorithmic / data-layout difference that costs C# its
   time.  Likely suspects (to be confirmed, not assumed):
   - **Vectorization gap**: the JIT may not auto-vectorize the inner
     SVM gradient/dot-product loops; Rust's LLVM does.  Check whether
     `System.Numerics.Vector<T>` / explicit SIMD helps, and whether
     the matrix layout (row-major span, AoS vs SoA) blocks
     vectorization.
   - **Loop-carried dependencies**: f64 reduction loops where
     IEEE 754 strict mode prevents JIT re-association.  Compare to
     the Matrix `WrapPrefixNoClone` carry-over from postscript 21 of
     the prior sprint — was deferred precisely for this sprint.
   - **Allocation in the hot loop**: per-iteration array/object
     allocations that the GC then has to chase.  Look for `new T[]`
     or `ToArray()` inside the train loop.
   - **Bounds checks / safety**: indexed access patterns the JIT
     can't elide, vs Rust's slice iterators that already check once.
   - **Parallelism granularity**: the existing grid-search
     parallelization may have the wrong unit of work, or contention
     on a shared accumulator.
3. **Fix**: implement the highest-leverage change(s) in
   `pwiz_tools/OspreySharp/OspreySharp.ML/LinearSvmClassifier.cs`
   and `Matrix.cs`, then re-measure.
4. **Verify**: cross-impl bit-parity at 1e-9 must still pass
   (`Compare-EndToEnd-Crossimpl.ps1 -Dataset Stellar -Files All` and
   `-Dataset Astral`), and the 3-column profile table re-runs with
   the new C# numbers in place.

## Files of interest

### C# (pwiz)

- `pwiz_tools/OspreySharp/OspreySharp.ML/LinearSvmClassifier.cs` — SVM
  train loop, grid-search parallelization, prior sprint's hot spot
- `pwiz_tools/OspreySharp/OspreySharp.ML/Matrix.cs` — dense matrix
  storage backing the SVM features; `WrapPrefixNoClone` carry-over
  lives here
- `pwiz_tools/OspreySharp/OspreySharp.FDR/PercolatorFdr.cs` — calls
  into the SVM and owns the Stage 5 wall-time around it
- `pwiz_tools/OspreySharp/OspreySharp.Scoring/SpectralScorer.cs` —
  upstream of Stage 5 (xcorr / cosine etc.); not in scope but the
  feature matrix shape comes from here

### Rust (osprey, reference)

- `crates/osprey-fdr/src/percolator.rs` — equivalent of PercolatorFdr.cs
- `crates/osprey-fdr/src/svm.rs` or wherever the LinearSVM lives —
  the reference implementation; check for `#[inline]`, `iter().fold`,
  vector intrinsics, `rayon::par_iter`
- `Cargo.toml` rustc flags — confirm release profile is `-O3` /
  `target-cpu=native` (or matches whatever produces the bench numbers)

### Harness (ai)

- `ai/scripts/OspreySharp/Compare-EndToEnd-Crossimpl.ps1` — parity gate
- `ai/scripts/OspreySharp/Measure-Pipeline.ps1` — perf medians
- `ai/scripts/OspreySharp/Test-Snapshot.ps1` — per-stage isolation;
  needed for "just run Stage 5" mode
- New (this sprint): `ai/scripts/OspreySharp/Profile-Stage5.ps1`
  (wraps dotTrace for C# + `samply` or `cargo flamegraph` for Rust;
  exports per-function summary CSVs that we'll merge into the
  3-column table)

## Open questions to settle in the first session

- Profiling tools: dotTrace (paid, full call-tree) vs dotnet-trace
  (free, EventPipe sampling) vs PerfView for C#?  `samply` vs
  `cargo flamegraph` vs `perf record` for Rust?
- Single-file or 3-file Stage 5 for profiling?  Stellar single-file
  is the fastest cycle but Astral exhibits the worst gap; both may
  be needed if the hotspot shifts with scale.
- Run Stage 5 in isolation via Test-Snapshot, or as the embedded
  middle of an end-to-end run?  Isolation gives cleaner profiles but
  loses warm-cache state that may matter.

## Progress Log

### 2026-05-27 — Sprint opened

TODO drafted from postscript 21 carry-over #4 (Matrix
`WrapPrefixNoClone` Active-length property) plus the persistent
Stage 5 gap visible in the night-session perf tables.  Working
branch creation via `/pw-startup` follows.
