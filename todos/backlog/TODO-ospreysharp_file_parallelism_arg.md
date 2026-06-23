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
Reinforced 2026-06-22: **Mike** independently hit the parallel-by-default behavior
and raised two concerns on a 64 GB box -- (a) it silently competes with the inner
scoring threads he was already tuning, and (b) multi-file HRAM can stress system
RAM. This drove the **sequential-by-default** decision below. Credit the eventual
commit/PR `Requested by Mike.`

**Note (2026-06-23)**: This TODO was written before the declarative CLI framework
landed (Phase A #4322 + Phase B #4323, both merged). Adding the argument is now the
established `OspreyCommandArgs` pattern, not a from-scratch parser change -- see the
implementation notes under "What to build #2".

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

### 1. Default = strictly sequential (one file at a time)
Change the default from "parallel across files up to `ProcessorCount`" to **N=1,
sequential**. Safe on any machine, and it matches what the perf scripts already
force. Mike's 64 GB-box concerns (thread competition + RAM stress, see Source)
drive this: a sequential default removes both surprises, and users opt INTO
parallelism explicitly.
- The memory/CPU-aware logic previously floated as "the smarter default" now lives
  behind `--parallel-files` with **no value** (auto mode, see #2) -- it is NOT the
  default.
- Each file's PerFileScoring is independent, so sequential is a strict subset of
  today's behavior (identical output to `OSPREY_MAX_PARALLEL_FILES=1`).

### 2. First-class `--parallel-files` argument (optional value)
Name decided: **`--parallel-files`**, deliberately distinct from `--threads` (the
INNER per-file main-search thread budget). Three states:
- **absent** -> sequential (the new default, N=1).
- **`--parallel-files` (no value)** -> AUTO: pick N from available RAM + processor
  count (estimate per-file footprint vs free physical memory; cap by `ProcessorCount`
  and `nFiles`). Log the chosen N and the reason.
- **`--parallel-files <N>`** -> explicit N, **regardless** of system RAM/CPU (sanity-
  clamp to `nFiles` only). Lets a 500 GB / 48-core NUMA box force more, or pin a value
  to self-diagnose perf.

Implementation notes (post-#4323 CLI framework):
- Declare an `OspreyArgument` in `OspreySharp/OspreyCommandArgs.cs`. This needs
  **optional-value support, which the OspreySharp tokenizer does not yet have** (args
  are currently either pure flags or value-required). Add it: `--parallel-files`
  consumes the next token as N **only if** it is a non-flag positive integer; otherwise
  it is auto-mode and the token is left for normal processing (mirror the optional-value
  lookahead the `--help [fmt]` special-case already does in `TokenizeAndDispatch`).
- `ProcessValue` sets a new `OspreyConfig` field, e.g. `FileParallelism` (encode the
  three states: default-sequential / auto / explicit-N -- e.g. `int?` with a sentinel,
  or a small struct). Add its text to the inline `IArgUsageProvider` `DESCRIPTIONS`
  dict; add an arg->config row to `OspreyCommandArgsTests` (the drift-killer test then
  enforces it is grouped + described). Add a case for the no-value (auto) form too.
- **Group + help:** clarify OUTER (files at once = `--parallel-files`) vs INNER
  (per-file scoring threads = `--threads`) in both descriptions. `--threads` currently
  sits in "Distributed / HPC"; in-process file parallelism is not HPC, so decide whether
  to add a small "Performance" group or co-locate with `--threads`.
- Keep `OSPREY_MAX_PARALLEL_FILES` as a back-compat cap (the **arg wins** when both set).

### 3. Thread the count through PerFileScoringTask (now THREE sites)
The `maxParallelFiles` / `EffectiveFileParallelism` logic is no longer one place: it
appears in **three** spots in `OspreySharp.Tasks/PerFileScoringTask.cs` -- the real
execution path in `Run` (~204-267) plus two "Mirror Run's EffectiveFileParallelism
bookkeeping" copies (~356, ~435) added by the HPC task split. **Extract the effective-N
decision into one shared helper** (takes config + `nFiles`, returns N, resolving
precedence: explicit arg N > auto > env-var cap `OSPREY_MAX_PARALLEL_FILES` > sequential
default) and call it from all three. Today the task reads
`OspreyEnvironment.MaxParallelFiles` directly and bypasses config -- route it through the
new config field. (Anchor on the symbols, not the line numbers, which drift.)

## Open questions

1. RESOLVED: default = strictly sequential (N=1). The RAM/CPU-aware policy is opt-in
   via `--parallel-files` with no value (auto mode), not the default.
2. RESOLVED: name = `--parallel-files` (clearly distinct from `--threads`). The "MAX"
   framing is internal back-compat only (`OSPREY_MAX_PARALLEL_FILES` env cap); the arg
   is the documented primary control and is an explicit count / auto, not a cap.
3. AUTO-mode footprint estimate -- can we cheaply estimate N from mzML size / spectra
   count + free physical memory before committing? (Only the no-value auto form needs
   this now; the default and explicit-N forms do not.)
4. Determinism + gates (UPDATED -- the first-line gate is now the committed golden, not
   the cross-impl run):
   - Confirm parallel/auto == sequential **byte-identical** via
     `pwiz_tools/OspreySharp/regression.ps1 -Dataset Stellar` (and `-Dataset All` for
     multi-file Astral) before relying on any parallel path. Cross-impl is the rare
     drift check.
   - The Stellar golden is 3-file **unit** and was recorded sequentially; the new
     sequential default keeps it valid as-is. Prove the parallel/auto paths match it
     separately (run with `--parallel-files`).
   - PERF: `Test-PerfGate.ps1`'s pinned `pwiz-perfbase` baseline runs the OLD parallel
     default, so a sequential default shifts multi-file A/B timings -- pin
     `--parallel-files <N>` on BOTH sides of the A/B (or justify the shift). The perf
     scripts' existing `OSPREY_MAX_PARALLEL_FILES=1` for Astral becomes redundant once
     the default is sequential.
5. Rust parity: unchanged -- Rust osprey is single-file per process (HPC splits files
   across nodes), so this in-process outer-parallelism is C#-only; note in help/docs.

## Interim mitigation -- DONE (superseded)
The script-level serialize-Astral interim was handled separately and that TODO
was closed as superseded (completed
`TODO-20260611_ospreysharp_serialize_astral_runners.md`):
`ai/scripts/OspreySharp/Measure-CumulativeCoverage.ps1` sets
`OSPREY_MAX_PARALLEL_FILES=1` under instrumentation, and the perf scripts already
serialize Astral via `Measure-Pipeline.ps1`. What remains for THIS TODO is the
durable code-level fix: the memory-aware default + the first-class
`--file-threads` CLI argument described above (neither is built yet).

## Refs
- `OspreySharp.Tasks/PerFileScoringTask.cs` -- parallel/sequential branches +
  `EffectiveFileParallelism`, now in 3 spots (`Run` ~204-267, mirrors ~356, ~435).
- `OspreySharp.Core/OspreyEnvironment.cs:50` -- `MaxParallelFiles` (env-var read).
- `OspreySharp/OspreyCommandArgs.cs` -- declarative arg model to add `--parallel-files`
  to (the `OspreyArgument` declarations, the `IArgUsageProvider` DESCRIPTIONS dict, and
  `TokenizeAndDispatch` for the optional-value handling).
- `OspreySharp.Test/OspreyCommandArgsTests.cs` -- arg->config table + drift killer to extend.
- `OspreySharp.Core/OspreyConfig.cs` -- add the new `FileParallelism` field.
- Gates: `pwiz_tools/OspreySharp/regression.ps1 -Dataset Stellar|All` (byte-identical
  correctness); `ai/scripts/OspreySharp/Test-PerfGate.ps1` (perf A/B);
  `ai/scripts/OspreySharp/Build-OspreySharp.ps1 -RunTests -RunInspection` (build+tests+0-warn).
- `ai/scripts/OspreySharp/Measure-Pipeline.ps1` (Astral default = 1).
- Skyline `--import-threads=<integer>` (CLI-arg precedent).
- Observed: ~44 GB working set, 3-file Astral hram parallel (cumulative-coverage run, 2026-06-11).
