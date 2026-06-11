# TODO-20260611_ospreysharp_serialize_astral_runners.md -- Interim: serialize Astral (hram) in the multi-file runners

> Interim mitigation (pending the smarter-default code fix,
> `TODO-ospreysharp_file_parallelism_arg.md`): the runners that drive 3-file
> **Astral (hram)** through OspreySharp's **parallel-by-default** file processing
> hit a **~44 GB working set** and risk OOM on a smaller agent. Set
> `OSPREY_MAX_PARALLEL_FILES=1` for the Astral leg so it serializes -- matching
> what `ai/scripts/OspreySharp/Measure-Pipeline.ps1` already does (and what keeps
> the perf comparisons competitive with single-file Rust).

## Branch Information
- **Branch**: `Skyline/work/20260611_ospreysharp_serialize_astral` (pwiz part; to
  be created off `master` -- **PR #4280 now merged, so the base is ready**)
- **Base**: `master`
- **Created**: 2026-06-11
- **Status**: **Active, not started.** The PR-#4280 gate is cleared (merged
  2026-06-11 as `55b34e8`). The orchestrator half (`Measure-CumulativeCoverage.ps1`)
  is **done** (commit `8a71b72`). The `regression.ps1` half remains -- still gated
  only on the machine freeing up, because its verification needs a sequential
  Astral run and the box is busy with the Stellar cumulative-coverage run.
- **GitHub Issue**: (none)
- **PR**: (pending)

## The change
Two runners, two repos:
1. **`pwiz_tools/OspreySharp/regression.ps1`** (pwiz, needs the branch/PR above) --
   set `$env:OSPREY_MAX_PARALLEL_FILES = '1'` for the Astral (hram) leg
   (resolution-gated, or per-dataset), unset for Stellar. Mirrors
   `Measure-Pipeline.ps1`'s "1 for Astral" policy.
2. **`ai/scripts/OspreySharp/Measure-CumulativeCoverage.ps1`** (ai/ -> pwiz-ai
   master, no branch) -- **DONE (commit `ddfe7c2`).** Note the scope is broader here
   than in the regression: under dotCover instrumentation even **unit-resolution
   Stellar** 3-file parallel exhausts memory (the framework assembly loader fails at
   the blib write), so the orchestrator serializes **all** legs, not just Astral.
   The regression test runs uninstrumented (no dotCover), so it only needs the
   Astral leg serialized (item 1). **No golden dependency** (coverage is
   scheduling-independent), which is why this half landed independently.

## Verification gate (do BEFORE changing the regression)
The committed Astral golden (`osprey-regression.data/astral/`) was captured with
**parallel** file processing. Serial vs parallel **should** produce an identical
blib (each file's PerFileScoring is independent; the cross-impl gate already runs
C# **sequential** vs single-file Rust at 1e-9), but verify, don't assume:
- Run Astral 3-file **sequential** (`OSPREY_MAX_PARALLEL_FILES=1`) and
  `Compare-BlibFull` it against the parallel-captured golden/blib at 1e-9.
- **Identical** -> safe; commit the runner change, no golden re-capture needed.
- **Different** -> a real determinism finding (parallel vs sequential diverge) ->
  STOP and investigate; that would be a bug, not a config tweak.

## Sequencing / why queued
- Run the verification after the cumulative-coverage run completes (it is using
  the box at ~85% memory; a second Astral run now would contend).
- The pwiz part waits for PR #4280 to merge (then branch off master).
- The ai/ coverage-orchestrator half can go first (no golden gate).

## Relationship
- Stopgap until `TODO-ospreysharp_file_parallelism_arg.md` lands the memory-aware
  default + the explicit `--file-threads`-style argument.

## Progress Log
### 2026-06-11 -- Queued
Verified the parallel-default behavior (`PerFileScoringTask.cs:202-280`) +
`Measure-Pipeline.ps1`'s Astral=1 policy from the cumulative-coverage run's 44 GB
Astral observation. Brendan: queue this; let the in-flight run finish rather than
kill it to verify now.

### 2026-06-11 -- Gate cleared (#4280 merged); precautionary, not urgent
PR #4280 merged, so the `regression.ps1` branch can now fork off `master`. Orchestrator
half already shipped (`8a71b72`). **Important nuance:** last night's first TeamCity
nightly of the merged regression ran the full Stellar + Astral (3-file, parallel)
in **41 minutes** with no OOM -- so the current TeamCity agent handles parallel
Astral fine. This interim fix is therefore **defensive** (smaller agents) and
**policy-consistency** (match `Measure-Pipeline.ps1`'s single-file Astral, which is
what keeps the perf comparisons competitive with single-file Rust), **not** a fix
for a current TeamCity failure. Still worth doing, but it is not blocking the
nightly. Remaining work unchanged: branch off master, gate the Astral leg on
`OSPREY_MAX_PARALLEL_FILES=1`, run the sequential-vs-parallel golden verification
at 1e-9, commit + PR. Deferred until the Stellar (then single-Astral) coverage runs
free the box.
