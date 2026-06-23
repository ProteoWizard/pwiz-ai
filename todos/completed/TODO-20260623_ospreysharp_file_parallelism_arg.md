# TODO: OspreySharp file-parallelism -- memory-aware default + a first-class CLI argument

## Branch Information
- **Branch**: `Skyline/work/20260623_ospreysharp_file_parallelism_arg`
- **Base**: `master`
- **Created**: 2026-06-23
- **Status**: Completed
- **PR**: [#4324](https://github.com/ProteoWizard/pwiz/pull/4324) (merged 2026-06-23)

## Decisions (2026-06-23, session start)
- AUTO mode (`--parallel-files` no value): implement RAM-aware now. Probe free
  physical memory (net8.0 `GC.GetGCMemoryInfo`; net472 `GlobalMemoryStatusEx`
  PInvoke), estimate per-file footprint = max input mzML size x 3 (grounded:
  Astral hram mzML ~6 GB on disk -> ~14.6 GB working set/file observed
  2026-06-11, i.e. ~2.4x; rounded up to 3x to bias AUTO toward FEWER files).
  Use 80% of available RAM as the budget. Cap by ProcessorCount and nFiles.
  Footprint multiplier is a coarse, deliberately-conservative heuristic;
  explicit `--parallel-files <N>` bypasses it.
- Help grouping: new **Performance** group holding `--parallel-files` (OUTER:
  files at once) + `--threads` (INNER: per-file scoring threads), moved out of
  Distributed / HPC.

**Status**: Completed (merged 2026-06-23 as 0e59d2d) -- original framing below.
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

## Progress (2026-06-23)
Implemented end to end; build + 432 unit tests + 0-warning inspection all green.
- **Core model** (`OspreySharp.Core/FileParallelism.cs`): `FileParallelismMode`
  (Sequential/Auto/Explicit) + readonly `FileParallelism` struct (default =
  Sequential) + `FileParallelismResolver` -- the single owner of the precedence
  (explicit N > auto > `OSPREY_MAX_PARALLEL_FILES` cap > sequential). Auto =
  80% of free RAM / (max mzML x 3) footprint estimate, capped by cores + nFiles.
- **Memory probe** (`OspreySharp.Core/SystemMemory.cs`): net8.0 `GC.GetGCMemoryInfo`
  (cross-platform, cgroup-aware); net472 `GlobalMemoryStatusEx` PInvoke.
- **Config**: `OspreyConfig.FileParallelism` field; `OspreyEnvironment.MaxParallelFiles`
  doc updated (now a back-compat cap; unset = sequential, not all-at-once).
- **CLI** (`OspreyCommandArgs.cs`): `--parallel-files [<N>]` with optional-value
  tokenizer lookahead (mirrors `--help [fmt]`); new **Performance** group holding
  it + `--threads` (moved out of Distributed / HPC); OUTER vs INNER clarified in
  both descriptions.
- **Threading** (`PerFileScoringTask.cs`): all 3 EffectiveFileParallelism sites
  now call one `ResolveFileParallelism` helper; Run's sequential/parallel dispatch
  is driven by the resolved N (was the raw env var). The `[BENCH]
  OSPREY_MAX_PARALLEL_FILES=...` log lines are replaced by one resolver decision line.
- **Tests**: `FileParallelismResolverTests` (precedence/clamping/auto, injected
  RAM/footprint); `OspreyCommandArgsTests` extended (absent/auto/explicit + the
  optional value not swallowing the next flag + Performance group in help).

### Gates
- [x] `Build-OspreySharp.ps1 -RunTests -RunInspection`: build OK, 432 pass / 3 skip, 0 warnings.
- [x] `regression.ps1 -Dataset Stellar`: PASS all 3 modes (mode1 vs golden, mode3 HPC
      chain, mode2 resume). Confirms the new sequential default == the golden (recorded
      under `OSPREY_MAX_PARALLEL_FILES=1`). Run log showed the resolver decision line
      `File parallelism: 1 (sequential default; ...)` for the 3-file set.
- [x] Proved `--parallel-files 3` (explicit) and `--parallel-files` (auto, chose 3 from
      39.5 GB free) BOTH == sequential at 1e-9 incl. peaks, via the regression's own
      `Compare-BlibFull` oracle. NOTE: raw blib SHA differs across runs (SQLite page
      layout is not byte-reproducible) -- same byte size (52,514,816); content matches.
      This is why the regression compares table content at 1e-9, not raw bytes.
- [x] `Test-PerfGate.ps1 -Dataset Stellar -MaxParallelFiles 1 -TestBaseDir D:\test\osprey-testfiles-all`
      (both A/B legs pinned sequential -- the comparable config now the default shifted):
      PASSED, total wall median -3.5%, all stage gates ok/info, no regression.
- [x] `regression.ps1 -Dataset All`: PASS all 6 modes -- Stellar (golden/chain/resume) AND
      Astral 3-file hram (golden/chain/resume). Astral blib 136,622,080 bytes identical
      across straight (15:10) / HPC chain (19:50) / resume (2:09) at 1e-9.
- [x] Perf scripts updated to reproduce recorded conditions after the sequential default:
      Measure-Pipeline C# leg uses `--parallel-files` (Stellar 3 / Astral 1); Test-PerfGate
      keeps OSPREY_MAX_PARALLEL_FILES (pinned old baseline predates the arg), default fixed
      to Stellar 3 / Astral 1; Measure-CumulativeCoverage comment corrected. (pwiz-ai 2762eaa)

### Self-review (PR #4324, fresh-context agent) -- addressed
No CRITICAL/HIGH. Findings:
- MEDIUM: `--parallel-files 0` silently became AUTO + a stray "Unknown argument: 0"
  warning. FIXED (commit 8005878): the lookahead consumes a non-negative integer and
  0 maps to sequential (the natural "off"); test added.
- LOW: net8 `GC.GetGCMemoryInfo` can read stale/zero early -- already fail-safe (CPU-cap
  fallback) and documented in `SystemMemory`; no change.
- LOW: `Osprey-workflow.html` parallelism note described the old parallel-by-default;
  updated for the new sequential default (commit 8005878).

### PR / review flow
- #4324 opened early (updated policy: open PR -> TeamCity/CodeQL first round -> self-review).
  Copilot review now optional/billed; pwiz-ai workflow docs updated separately.

### Deferred / open
- AUTO footprint multiplier (3x) and 80% RAM budget are coarse, conservative
  constants (bias toward fewer files). Refine with measurement in a follow-up;
  explicit `--parallel-files <N>` is the precise escape hatch meanwhile.

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

## Progress Log

### 2026-06-23 - Merged

PR #4324 merged as commit 0e59d2d. Shipped the full design: strictly-sequential
default; first-class `--parallel-files [<N>]` (absent=sequential, `0`/`1`=sequential,
`N`=explicit count, no-value=RAM/CPU-aware AUTO via a cross-platform free-memory probe
-- net8.0 `GC.GetGCMemoryInfo`, net472 `GlobalMemoryStatusEx`); a single
`FileParallelismResolver` owning the precedence (explicit arg > auto > `OSPREY_MAX_PARALLEL_FILES`
back-compat cap > sequential) routed through all three `PerFileScoringTask` sites; new
**Performance** help group. Gates all green: build + 432 tests + 0-warning inspection;
`regression.ps1 -Dataset All` PASS (Stellar + Astral 3-file, all golden/chain/resume modes,
byte-identical at 1e-9); `--parallel-files` explicit + auto proven == sequential at 1e-9 incl.
peaks; `Test-PerfGate` PASS (no regression). Fresh-context self-review was clean (1 MEDIUM
`--parallel-files 0`->sequential + 2 LOW, all addressed in commit 8005878). Separately
(pwiz-ai): updated the PR-review-policy docs (Copilot now optional/billed, self-review the
primary gate, open-PR-early-for-TeamCity), and pinned the perf scripts to the recorded
conditions (Stellar 3-parallel / Astral sequential) now that the default flipped. No GitHub
issue (none was filed). Nothing deferred from the agreed scope; AUTO footprint multiplier (3x)
and 80% RAM budget remain coarse, conservative constants noted for future measurement-based
refinement.
