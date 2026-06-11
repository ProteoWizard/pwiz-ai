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
  be created off `master` **after PR #4280 merges**)
- **Base**: `master`
- **Created**: 2026-06-11
- **Status**: Queued (not started) -- gated on the in-flight cumulative-coverage
  run freeing the machine (the verification needs a sequential Astral run).
- **GitHub Issue**: (none)
- **PR**: (pending)

## The change
Two runners, two repos:
1. **`pwiz_tools/OspreySharp/regression.ps1`** (pwiz, needs the branch/PR above) --
   set `$env:OSPREY_MAX_PARALLEL_FILES = '1'` for the Astral (hram) leg
   (resolution-gated, or per-dataset), unset for Stellar. Mirrors
   `Measure-Pipeline.ps1`'s "1 for Astral" policy.
2. **`ai/scripts/OspreySharp/Measure-CumulativeCoverage.ps1`** (ai/ -> pwiz-ai
   master, no branch) -- same, for its Astral leg. **No golden dependency**
   (coverage is scheduling-independent), so this half can land independently and
   immediately once picked up.

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
