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

### 2026-05-28 — First profile pass: Stellar single-file, both impls in WSL

Setup: both impls profiled in WSL on the same Linux .NET 8 build
of OspreySharp + Linux Rust release build of osprey, against
`/home/brendanx/test/osprey-runs/stellar/Ste-...20.mzML` (3-fold
percolator, 16 threads, SVM training capped at 300000).

* C# under dottrace 2026.1.1 (sampling, CpuInstruction)
* Rust under samply 0.13.1 (1 kHz, threadCPUDelta)
* Symbol resolution: dottrace Reporter.exe (Windows) for the .dtp;
  samply JSON addresses resolved via `addr2line -f -C` against the
  unstripped osprey ELF binary.

#### Headline numbers (Stellar single-file, Stage 5 only)

| Metric | C# | Rust | Ratio |
|---|---:|---:|---:|
| Wall time | 85s | 40s | **2.13x** |
| SVM Train/fit CPU time | 734,705 ms | 588,911 ms | **1.25x** |
| Effective cores used | 8.6 | 14.7 | — |

The 2.13x wall gap decomposes into two roughly independent factors:

1. **CPU efficiency**: the C# SVM inner loop costs 1.25x the CPU
   cycles of the Rust SVM inner loop.  Both impls land 96% of
   their pwiz.OspreySharp CPU on a single function
   (`LinearSvmClassifier.Train` / `svm::LinearSvm::fit`), with the
   dot-product / weight-update kernels inlined.  Likely cause:
   LLVM auto-vectorizes the inner loops into SIMD; RyuJIT does
   less.  Bounds-check elimination is a secondary factor.
2. **Parallelism scaling**: the C# fold-parallel path achieves
   ~8.6 effective cores on a 16-core host where Rust achieves
   ~14.7.  This ~1.7x gap is *on top of* the 1.25x CPU gap and is
   where most of the wall difference comes from.  Suspects: RNG /
   shuffle contention, allocator pressure during inner training,
   or false sharing on per-thread weight vectors.

#### Top 30 C# hot spots vs Rust counterparts

| # | C# function | C# own (ms) | Rust own (ms) | Ratio | Rust function |
|---:|---|---:|---:|---:|---|
| 1 | `LinearSvmClassifier.Train`     | 734,705 | 588,911 | 1.25x | `svm::LinearSvm::fit` |
| 2 | `LinearSvmClassifier.FisherYatesShuffle` | 28,212 | (inlined) | n/a | -- |
| 3 | `Matrix.DotVector`              | 2,192   | (inlined) | n/a | -- |
| 4 | `SvmTrainScratch..ctor`         | 2,150   | (n/a) | n/a | -- |
| 5 | `DecoyGenerator.RecalculateFragments` | 1,718 | (n/a) | n/a | -- |
| 6 | `PercolatorFdr.CompeteFromIndicesInto` | 1,216 | 764 | 1.6x | `compete_from_indices` |
| 7 | `PepEstimator+Kde.Pdf`          | 1,176   | 345 | **3.4x** | `pep::PepEstimator::fit` |
| 8 | `DecoyGenerator.CalculateFragmentMz` | 751 | 228 | **3.3x** | `calculate_fragment_mz` |
| 9 | `LibraryCache.LoadCache`        | 129     | -- | n/a | -- |
| 10 | `ParquetScoreCache.LoadPinFeaturesFromParquet` | 48 | 4 | 12x | -- |
| 11 | `FeatureStandardizer.Transform` | 41 | 5 | 8x | `svm::FeatureStandardizer::transform` |

(Full table at `ai/.tmp/stage5-profile/extracted/stage5-csharp-vs-rust.md`.)

#### Open investigation lines

* **SVM inner loop SIMD probe**: dump the JIT assembly for
  `LinearSvmClassifier.Train` via `DOTNET_JitDisasm=Train`, look
  for AVX vector ops on the dot-product and weight-update steps.
  Compare against Rust release asm for `svm::LinearSvm::fit`.
* **Parallelism profile**: a Timeline profile (vs Sampling) on
  the C# side to find where worker threads spend non-CPU time --
  if they sit in `Wait`/`Monitor.Wait` instead of doing SVM work,
  there's a synchronization bottleneck to remove.
* **PepEstimator KDE**: 3.4x gap on a smaller hotspot but a clean
  numerical kernel; a SIMD probe here would either confirm the
  RyuJIT-vs-LLVM vectorization hypothesis at a smaller scale, or
  surface a different algorithmic cost.
* **Parquet loaders 8-12x slow**: the parquet load functions
  (`LoadPinFeaturesFromParquet`, `LoadFdrStubsFromParquet`,
  `FeatureStandardizer.Transform`) consume small absolute time
  but show very large ratios.  Likely a row-by-row C# read vs
  a vectorized Arrow read on the Rust side -- worth a quick fix.

#### Tooling assets created (not yet committed)

* `ai/scripts/OspreySharp/samply-to-csv.py` -- samply JSON to flat
  per-function CSV with addr2line + libiberty demangling.
* `ai/.tmp/stage5-profile-stellar.sh` -- one-shot freeze-then-profile
  shell driver (will be promoted to `Profile-Stage5.ps1` once the
  iteration loop stabilizes).
* `ai/.tmp/stage5-extract-and-merge.ps1` -- post-processor producing
  the 3-col markdown table (will be promoted to
  `Combine-Stage5-Profile.ps1` after Astral pass confirms hotspots).

WSL prereq: `/proc/sys/kernel/perf_event_paranoid` must be <= 1
for samply; the user lowered it in a separate sudo shell.
Profile-prep freeze workdir at
`/home/brendanx/test/osprey-runs/stellar/_test_snapshot_profile-prep/`
preserved for follow-up runs.

### 2026-05-28 — Sprint commit 1: SIMD inner loops (PASS)

pwiz `Skyline/work/20260527_svm_stage5_perf @ 35afd3a521` --
`LinearSvmClassifier.Train` dot-product and weight-update loops
hand-vectorized with `System.Numerics.Vector<double>`.  Reduction
uses `Vector.Dot(sumVec, Vector<double>.One)` for cross-framework
horizontal sum (`Vector.Sum` is .NET 7+; net472 needs the Dot path).

Measured impact (Stellar single-file Stage 5, dottrace sampling
+ samply, both in WSL on `/home`):

| Metric | Baseline | Fix #1 | Delta |
|---|---:|---:|---:|
| `LinearSvmClassifier.Train` OwnTime | 734,705 ms | 481,133 ms | **-34.5%** |
| C# Percolator train all folds (max) | 77.0s | 53.2s | **-31%** |
| C# Stage 5 total wall | 85s | 62s | **-27%** |
| C# / Rust wall ratio | 2.13x | 1.55x | -27% |

End-to-end Astral 3-file parity:

| Metric | Baseline (2026-05-26 night) | Fix #1 | Delta |
|---|---:|---:|---:|
| C# wall  | 22:02 | 19:48 | **-10%** |
| Rust wall | 24:10 | 24:46 | run noise |
| Precursors (Rust = C#) | 167,285 = 167,285 | 167,285 = 167,285 | match |
| Stage 7 1e-9          | PASS  | PASS  | -- |
| Blib SQL row+col 1e-9 | PASS  | PASS  | -- |

C# end-to-end on Astral 3-file is now ~5 minutes FASTER than Rust
on the same input, with the bit-parity gate at 1e-9 still green.

Pushed to `origin/Skyline/work/20260527_svm_stage5_perf`.
No PR opened yet -- the branch carries one commit and the user
will decide when to open the PR.

### 2026-05-28 — Sprint commit 3: parallel LOESS outer loop (PASS)

`Skyline/work/20260527_svm_stage5_perf @ c39b3889a7` — wrap
`LoessFitInternal`'s outer `for (int i = 0; i < n; i++)` in
`Parallel.For`.  Each output index is independent (read-only x/y, write-
once `fitted[i]`), so the change is mechanical and cheap.

Profile pass against the Astral 3-file dataset that motivated the
sprint:

| Metric | Pre Fix #5b | Post Fix #5b | Delta |
|---|---:|---:|---:|
| `LoessFitInternal` lambda OwnTime | 130,805 ms (serial) | (parallelized, 16 threads) | — |
| C# reconciliation wall | 165.8s | 43.7s | **-74%** |
| C# Stage 5 isolated wall (--join-only) | 4:20 | 2:18 | **-47%** |
| Astral 3-file end-to-end C# wall | 19:48 (Fix #1 only) | 15:17 | **-23%** |
| Astral 3-file end-to-end Rust wall | 24:46 | 25:58 | run noise |
| Cross-impl 1e-9 parity (Stellar 1-file + Astral 3-file) | PASS | PASS | bit-equal |

C# now beats Rust by **10:41** on Astral 3-file end-to-end with
bit-equality preserved.  The headline "Astral stage5 4x C#/Rust" gap
that started this profile pass is resolved.

### 2026-05-28 — Sprint commit 4 attempt: SIMD inner LOESS accumulator (REJECTED)

Tried Fix #5a on top of Fix #5b: `System.Numerics.Vector<double>` SIMD
over the 5 weighted partial sums in the inner accumulator loop, with the
hoisted `1/maxDist` and tricube `min(u,1)^3` clamp form.  Build green.

Re-profile on Astral 3-file:

| Metric | Fix #5b only | Fix #5b + #5a |
|---|---:|---:|
| `LoessFitInternal` lambda OwnTime | 357,635 ms | 221,671 ms (**-38% CPU**) |
| C# Stage 5 isolated wall | 138.0s | 134.3s (-2.7%) |

SIMD worked at the kernel level (-38% CPU on the targeted function),
but the **wall savings were absorbed by Amdahl's law**.  After Fix #5b
parallelized LOESS to 16 cores, the LOESS wall was already ~8-13s out
of a 43s reconciliation phase; SIMD shrinks LOESS further but other
reconciliation work (PepEstimator KDE, decoy generation, consensus
computation, JSON writing) keeps the overall wall ~constant.

Per the "only commit changes with proven value" directive, 2.7% wall
delta is within run-to-run noise.  Reverted.  Branch ends the
sprint at `c39b3889a7` (Fix #1 + Fix #5b).

### 2026-05-28 — Sprint commit 2 attempt: scratch pool + AggressiveInlining (REJECTED)

Tried Fix #2 (pool `int[]` partition buffers + `ExtractRowsInto`
overload accepting an explicit row count) + Fix #3
(`[MethodImpl(AggressiveInlining)]` on
`LinearSvmClassifier.FisherYatesShuffle`).

Build green.  Stellar single-file end-to-end parity at 1e-9 PASS
(walls 2:20 C# vs 2:21 Rust).

Re-profiled Stellar Stage 5 with both fixes applied:

| Metric | Fix #1 only | Fix #1 + #2 + #3 |
|---|---:|---:|
| C# Percolator train all folds (max) | 53.2s | 53.7s |
| C# Stage 5 total wall | 62.1s | 62.9s |

Within run-to-run noise.  Fix #3 did inline `FisherYatesShuffle`
(it disappeared from the top-10 profile, with its 26 s of CPU now
attributed to `Train`'s OwnTime which rose 481 -> 512 ms),
confirming the JIT honored the hint -- but the inlining produced no
net CPU savings because the call overhead was already negligible
relative to the swap loop body.  Fix #2's allocator pool did not
move the wall either: the existing `TrainData`/`TestData` pool
already absorbed the dominant LOH pressure, and the residual
`List<int>` + ToArray pattern at ~190 MB/run was not a measurable
bottleneck.

Per the user directive "only commit changes with proven value,"
both changes were reverted via `git checkout --` and the branch
ends the sprint at `35afd3a521` (Fix #1 only).

### Carry-overs

1. **PR for `Skyline/work/20260527_svm_stage5_perf`** -- ready when
   the user is.
2. **Astral Stage 5 profile pass** (TODO task 166) -- skipped
   in this session.  Worth running to confirm the post-Fix-#1
   hotspot pattern at the bigger scale matches Stellar's, and
   to characterize Astral's residual gap.  Current best estimate
   from the end-to-end Astral wall (-10%) implies most of the
   Stellar Stage 5 SIMD win carries over.
3. **PepEstimator KDE Pdf 3.4x gap** -- still on the
   secondary-target list (1176 vs 345 ms own).  SIMD on the
   bandwidth-selection inner loop would be the same pattern as
   Fix #1.  Defer to a future session unless prioritized.
4. **GC-pressure investigation** -- the apparent parallel-scaling
   gap (post Fix #1: C# 62s wall vs Rust 40s) may not be GC after
   all, given Fix #2's null result.  Could be:
   - dotnet startup + JIT warmup (the dotTrace profile process
     pays init cost the bash `time` measures).
   - Library load + decoy generation cost difference (pre-Stage-5
     setup is part of the 62s C# vs 40s Rust window).
   - Library file mzML parsing in WSL crossing the 9P boundary --
     `/home` is ext4 but the parent process may still load
     `/mnt/c/proj` binaries.
   Worth measuring per-phase walls inside the percolator-only run
   before forming a fix hypothesis.
