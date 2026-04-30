# TODO: Osprey Rust parallel file processing (Rayon, per-file config clone)

**Status**: Backlog
**Priority**: Medium (nice-to-have wall-clock win on multi-file experiments; not blocking anything)
**Complexity**: Medium (structural -- needs per-file config clone + mzML read serialization)
**Created**: 2026-04-19
**Scope**: `C:\proj\osprey-mm` (maccoss/osprey, Rust)
**Predecessor**: `ai/todos/active/TODO-OR-20260417_osprey_rust_upstream.md` -- Batch 2a (PR #12) shipped the single-file HRAM win; this is the deferred Batch 2b.

## Motivation

Rust Osprey processes input mzML files sequentially today: on an N-file
experiment wall-clock is roughly `N * single_file_time`. OspreySharp
already does file-level parallelism in `Parallel.ForEach` with
`MaxParallelFiles` control, per-file `OspreyConfig.ShallowClone`, and
reaches ~97% parallel efficiency on 3-file Astral (par-3 = 342s vs
seq = 380s = 1.11x wall-time per file).

After Batch 2a, Rust single-file Astral Stage 1-4 is ~100s (warm cache)
versus OspreySharp's ~220s, so the gap has inverted -- Rust is now
~2.2x faster per file. Parallelism is therefore a "nice to have" rather
than a competitive requirement, but still unlocks another ~3x on
multi-file workloads with enough RAM.

### C# evidence (from the OspreySharp port, Sessions 14-16)

- Seq vs par-3 on Astral: 380s -> 342s wall-clock (1.11x per-file --
  ~97% parallel efficiency).
- Stellar 3-file was where the gain showed most clearly since single-
  file Stellar is quick; par-3 stabilized at 49.5s median.

## Scope

**Single goal: bring Rayon file-level parallelism to the Rust pipeline,
with per-file config cloning.**

1. **Parallel file loop** in `crates/osprey/src/pipeline.rs`: wrap the
   existing per-file iteration in `par_iter()` (Rayon) with a scoped
   thread pool.

2. **Per-file config clone.** A few `OspreyConfig` fields get mutated
   during processing (notably `fragment_tolerance` after MS2 calibration),
   which would race across parallel files. Mirror C#
   `OspreyConfig.ShallowClone()` -- add `OspreyConfig::clone()` or
   `shallow_clone` semantics and call at the top of each per-file task.

3. **Inner thread scaling** via `OSPREY_MAX_PARALLEL_FILES` env var
   (mirrors C#). Default = min(3, num_files). When N files run in
   parallel, inner Rayon uses `num_cpus / N` threads per file to avoid
   oversubscription. C# captured this in `EffectiveFileParallelism`.

4. **mzML read serialization.** A single `Mutex` / `Semaphore` gates the
   mzML read phase while main-search runs free. C# Session 15 found
   ~60% wall-time variance without this gate (disk thrash + I/O contention).

5. **Per-file Parquet writes** already work independently; no changes
   needed there.

## Validation

- [ ] `cargo test --workspace` passes.
- [ ] `cargo clippy --workspace --all-targets -- -D warnings` passes.
- [ ] `cargo fmt --all --check` passes.
- [ ] Test-Features passes 21/21 on Stellar + Astral at 1e-6 vs
      OspreySharp (this PR must not affect scoring deterministically).
- [ ] Bench-Scoring.ps1 on Astral 3-file: target ~2-3x wall-clock
      speedup vs sequential (from ~300s to ~100-150s).
- [ ] Memory high-water stays under 64 GB (confirm via peak RSS
      column in Bench-Scoring output). Per-file thread scaling must
      keep 3 x working set from OOMing.
- [ ] Features bit-identical to sequential (config clone must not drift).

## Known risks

- **Memory pressure**: 3 parallel Astral files at ~34 GB peak each
  would need 100+ GB RAM. Inner thread scaling helps but N-parallel
  x per-file RSS is the ceiling. Users with <96 GB should cap
  `OSPREY_MAX_PARALLEL_FILES` at 1 or 2.

- **Rayon thread pool conflicts with per-window parallelism**:
  main-search already uses `par_iter` on the window loop. Nesting
  rayon pools without care causes work-stealing thrash. Use a
  scoped nested pool (`rayon::ThreadPoolBuilder::new().num_threads(n).build()`)
  per file, or per-file adjust of the global pool's effective concurrency.

- **Calibration determinism**: the current sampler uses a fixed seed
  (42 + attempt) which must stay per-file, not leak between files.
  Covered by the per-file config clone but worth verifying explicitly.

## Not in scope

- Switching from Rayon to async / Tokio / futures (too invasive for
  the gain; Rayon fits the data-parallel shape already used).
- Multi-host / cluster parallelism (that lives in the separate
  `TODO-osprey_hpc_scoring_split.md` backlog item -- Parquet-based
  Stage 4 split is orthogonal to Rayon file-level).
- Reconciliation / FDR parallelism: these phases are already fast
  enough that file-level parallelism dominates wall-clock.

## References

- C# parallel file implementation:
  `C:\proj\pwiz\pwiz_tools\OspreySharp\OspreySharp\AnalysisPipeline.cs`
  (search for `Parallel.ForEach`, `ShallowClone`, `MaxParallelFiles`).
- C# evidence log: `TODO-OR-20260417_osprey_rust_upstream.md`
  "Session 14-16" entries (captured before being retired).
- Orthogonal HPC-friendly split: `TODO-osprey_hpc_scoring_split.md`.

## Picking this up

1. Read the C# `AnalysisPipeline.ProcessAllFiles` parallel loop and
   `OspreyConfig.ShallowClone` for the template.
2. Confirm single-file HRAM perf is still where PR #12 left it
   (`Bench-Scoring.ps1 -Dataset Astral -Files Single` -- expect
   ~100s Stg 1-4 warm median).
3. Branch off latest `maccoss/osprey:main`. Batch 2a's branch
   `hram-xcorr-pool` (PR #12) is merged by then so no dependency.
4. Wire `par_iter`, per-file clone, scoped inner pool, mzML read
   mutex. Keep it small -- target ~100-200 line diff.
