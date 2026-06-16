# TODO: OspreySharp file-parallelism -- memory-aware default + a first-class CLI argument

**Status**: Backlog (not started)
**Priority**: Medium -- a memory footgun on smaller machines and a missing
user-facing perf knob; not blocking, but the current default can OOM/thrash on
multi-file HRAM.
**Type**: OspreySharp feature / performance / usability
**Source**: 2026-06-11 -- the cumulative-coverage run on 3-file **Astral (hram)**
hit **~44 GB working set** (managed heap ~34-38 GB) because the pipeline processes
all input files **in parallel by default**. Brendan: the single-file/sequential
HRAM behavior the perf scripts rely on (to stay competitive with single-file
Rust) is only reachable via an **environment variable**, which implies it is for
testing/diagnostics -- when it is actually a useful user-facing control.

## Verified behavior (2026-06-11)

- **Default = parallel across files.** `PerFileScoringTask.cs:202-280`:
  `maxParallelFiles = OspreyEnvironment.MaxParallelFiles` (from
  `OSPREY_MAX_PARALLEL_FILES`); when unset it falls to
  `Parallel.For(0, InputFiles.Count, ...)` with
  `MaxDegreeOfParallelism = min(nFiles, ProcessorCount)`.
- **`OSPREY_MAX_PARALLEL_FILES=1` = strictly sequential.** Its own code comment:
  *"one file at a time ... Useful for 3-file Astral runs that would OOM in
  parallel."*
- **The perf scripts already serialize Astral.** `ai/scripts/OspreySharp/
  Measure-Pipeline.ps1`: `MaxParallelFiles` *"Default 1 for Astral (memory ...)"*.
  So "single-file HRAM" is a **script** choice via the env var, not a code policy.
- The env var sets a **maximum** (a cap), framed as a bench/diagnostic toggle
  (`[BENCH] OSPREY_MAX_PARALLEL_FILES=...`). It is not surfaced as a CLI argument
  and is not in `--help`.

## What to build

### 1. Smarter default (memory-aware)
Stop blindly parallelizing all files up to `ProcessorCount` -- that assumes a
big-RAM box. The default should be safe on a typical dev/CI machine. Options to
weigh:
- Serialize HRAM by default (resolution-aware: hram -> 1, unit -> parallel), since
  HRAM spectra are dense and the per-file footprint is large; OR
- Gate parallelism by **available RAM** vs an estimated per-file footprint (e.g.
  derive a safe concurrent-file count from free physical memory / spectra size);
  OR a combination (resolution hint + RAM cap).
- Whatever the policy, it must not silently OOM/thrash on 3-file Astral on a
  normal machine, and should log the chosen file-parallelism + the reason.

### 2. First-class CLI argument (explicit count, NOT a max)
Add a documented argument that **explicitly sets the number of files processed
concurrently** -- e.g. `1,2,3,...8` -- so users can tune to their hardware and
**self-diagnose performance degradation** (e.g. moving to a NUMA server with
~500 GB RAM, 48 cores, fast SSD might want more concurrent files; a laptop wants
1). Precedent: Skyline's `--import-threads=<integer>`.
- **Explicit count, not a maximum.** The current env var is a *cap*; the argument
  should set the actual concurrent-file count the user asked for (subject to a
  sanity clamp to `nFiles`).
- **Name (open):** something file-scoped and clear -- e.g. `--file-threads <N>`
  (parallels Skyline's `--import-threads`), `--parallel-files <N>`, or
  `--concurrent-files <N>`. Distinguish from the existing `--threads`, which is
  the *inner* (per-file main-search) thread budget.
- **Interaction with `--threads`.** Two parallelism dimensions: OUTER (files at
  once = this new arg) and INNER (main-search threads per file = `--threads`).
  The code already divides the inner budget by `EffectiveFileParallelism` to avoid
  oversubscription (`PerFileScoringTask.cs` ~208-216); the new arg drives that
  outer number. Document the relationship in `--help`.
- Keep `OSPREY_MAX_PARALLEL_FILES` working as a back-compat override (the arg wins
  when both are given), but make the **argument** the documented, primary control.

## Open questions

1. Default policy: resolution-aware (hram->1), RAM-aware (estimate footprint), or
   both? What is the safe default concurrent-file count on a normal box?
2. Argument name + semantics vs the existing `--threads`; do we also rename/retire
   the "MAX" framing internally?
3. Per-file memory estimate -- can we cheaply estimate (from mzML size / spectra
   count) before committing to a parallel count?
4. Determinism: confirm parallel vs sequential produce identical output (each
   file's PerFileScoring is independent; the cross-impl gate runs C# sequential vs
   single-file Rust at 1e-9). Needed before changing defaults so committed goldens
   / cross-impl baselines stay valid.
5. Rust parity: Rust osprey is single-file per process (HPC splits files across
   nodes), so this in-process outer-parallelism is C#-only -- the arg has no Rust
   equivalent. Note in help/docs.

## Interim mitigation (separate, smaller)
Until the smarter default lands, the multi-file runners that go through the
parallel path on HRAM should serialize Astral to avoid OOM on the agent:
- `pwiz_tools/OspreySharp/regression.ps1` (the nightly regression -- runs Astral
  3-file) and `ai/scripts/OspreySharp/Measure-CumulativeCoverage.ps1` should set
  `OSPREY_MAX_PARALLEL_FILES=1` for the Astral leg (matching `Measure-Pipeline.ps1`).
  Verify the committed Astral golden is unchanged parallel-vs-sequential first
  (should be identical). This is a quick fix, trackable on its own.

## Refs
- `PerFileScoringTask.cs:202-280` (parallel/sequential branches, EffectiveFileParallelism).
- `OspreyEnvironment.MaxParallelFiles` (env-var read).
- `ai/scripts/OspreySharp/Measure-Pipeline.ps1` (Astral default = 1).
- Skyline `--import-threads=<integer>` (CLI-arg precedent).
- Observed: ~44 GB working set, 3-file Astral hram parallel (cumulative-coverage run, 2026-06-11).
