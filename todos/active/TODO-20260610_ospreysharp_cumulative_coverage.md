# TODO-20260610_ospreysharp_cumulative_coverage.md -- Cumulative OspreySharp coverage across all TeamCity test processes

> Report cumulative OspreySharp code coverage over **everything TeamCity runs** --
> the `OspreySharp.Test` unit tests **and** the real end-to-end regression
> pipeline runs -- by capturing a dotCover snapshot from each and **merging** them
> into one report. Today only the unit tests are covered (~45%); the pipeline code
> is near-zero under unit tests, so the merged number is the honest one.

## Location / workflow

- **`ai/`-side developer tooling only** -- no pwiz code changes. The pwiz scripts
  (`regression.ps1`, `build.ps1`) exist purely to run on TeamCity; coverage
  *analysis* is a developer activity that lives in `ai/scripts/OspreySharp/`. Per
  `ai/WORKFLOW.md`, `ai/` work commits **directly to pwiz-ai master, no feature
  branch**. (An earlier pwiz branch was created under a wrong assumption and
  deleted.)
- **Created**: 2026-06-10
- **Status**: In Progress
- **Runtime dependencies** (not code deps):
  - The existing coverage tooling -- `Build-OspreySharp.ps1 -Coverage`
    (unit-test snapshot + JSON) and `Summarize-Coverage.ps1` (whole-project
    summary). **These were uncommitted WIP from an earlier session; reconcile +
    commit them before/with this work** (they were authored on a base predating
    origin's recent `Build-OspreySharp.ps1` commits, so they re-apply, not
    fast-forward).
  - The regression harness `pwiz_tools/OspreySharp/regression.ps1`
    (PR [#4280](https://github.com/ProteoWizard/pwiz/pull/4280)) -- must be present
    in the pwiz checkout to cover the pipeline leg.

## Background (the progression)

1. Coverage support added (earlier session) to gauge OspreySharp **unit-test**
   coverage -- ~45%.
2. That session noted the real number is much higher when the regression test is
   included, because the pipeline code has almost zero unit coverage.
3. The regression test was made TeamCity-ready (PR #4280).
4. Now: a **full cumulative** coverage report over everything TeamCity runs.

## Findings (verified 2026-06-10)

- dotCover (installed: console runner **2025.1.7**) accumulates across processes:
  `cover` -> per-process `.dcvr`; `merge /Output=all.dcvr /Source=a.dcvr;b.dcvr`
  (Ant patterns OK); `report /Source=all.dcvr /Output=cov.json /ReportType=JSON`.
- **In-repo precedent:** Skyline `TestRunner.GenerateCoverageReport`
  (`pwiz_tools/Skyline/TestRunner/Program.cs:1286`) collects a snapshot per
  parallel worker, `dotcover merge`es them, then `report`s -- exactly this shape.
- Existing `Build-OspreySharp.ps1 -Coverage`: `dotcover cover` with
  `/Filters=+:module=OspreySharp* /Filters=-:module=OspreySharp.Test`,
  `/Output=<ai/.tmp/osprey-coverage-<ts>.dcvr>`, then `report ... /ReportType=JSON`.
  Reuse that filter + the JSON->`Summarize-Coverage.ps1` path for the merged set.
- Version fragility: that script refuses on dotCover >= 2025.3.0 (slash CLI
  removed); 2025.1.7 is fine. Keep the same `/Param=value` form Skyline uses.
- TeamCity merges snapshots within one build (importData) but not across configs.

## Approach

`ai/scripts/OspreySharp/Measure-CumulativeCoverage.ps1` (new) orchestrates a
"full run mimicking TeamCity" and prints the cumulative figure:
1. **Unit leg** -- `Build-OspreySharp.ps1 -Coverage` -> `unit.dcvr` (+ JSON).
2. **Regression leg** -- run `regression.ps1` under
   **`dotcover cover-everything`** (filter `+:module=OspreySharp* -:OspreySharp.Test`)
   so every `OspreySharp.exe` pipeline process is captured in one
   `regression.dcvr` -- **no change to `regression.ps1`** (this is why the pwiz
   side stays untouched). Per-run `dotcover cover` wrapping is the fallback if
   cover-everything proves noisy.
3. **Merge** -- `dotcover merge /Output=cumulative.dcvr /Source=unit.dcvr;regression.dcvr`.
4. **Report + summarize** -- `dotcover report ... /ReportType=JSON` ->
   `Summarize-Coverage.ps1` on the merged JSON.

## Open decisions

1. **Scope of the regression leg.** Full `-Dataset All` x straight+resume is most
   representative but dotCover instrumentation slows the (already ~15 min) Astral
   hram run materially. Likely default to `-Dataset Stellar` (single or 3-file,
   straight-through) for a repeatable number; `-Dataset All` as an opt-in. Measure
   the instrumentation overhead to decide.
2. **cover-everything vs per-run cover.** Lead with cover-everything (simplest, no
   pwiz change); fall back to wrapping each `Invoke-OspreyRun` if it over-captures
   or misses child processes.
3. **Local tool now; TeamCity later.** Deliver the developer script first. A
   TeamCity "OspreySharp cumulative coverage" config (run everything, import the
   merged snapshot, publish the trend) is a follow-up for Matt.

## Acceptance criteria

- One command produces a cumulative coverage report (the existing
  `Summarize-Coverage.ps1` view) spanning unit tests + the regression pipeline
  runs, merged via dotCover, excluding 3rd-party/test assemblies.
- The cumulative figure is meaningfully above unit-tests-alone (~45%),
  demonstrating the pipeline coverage the regression adds.
- Repeatable; snapshots stay under `ai/.tmp` (or `TestResults`), nothing published.

## Out of scope / future

- A scheduled TeamCity cumulative-coverage config + trend.
- Per-test attribution, coverage thresholds/gates.
- The `Build-OspreySharp.ps1` 2025.3.0+ CLI update (separate fragility).

## Progress Log

### 2026-06-10 -- Created (ai/-only reframe)
Confirmed with Brendan this is `ai/`-side tooling (pwiz scripts are only for
TeamCity). Deleted the mistaken pwiz branch. Verified dotCover merge/report on
2025.1.7 + the Skyline TestRunner precedent + the existing `-Coverage` mechanics.

### 2026-06-10 -- Orchestrator working; first cumulative number
Wrote `ai/scripts/OspreySharp/Measure-CumulativeCoverage.ps1`: unit leg
(`Build-OspreySharp.ps1 -Coverage`) + per-dataset straight-through + resume legs
run via `OspreySharp.exe` directly under `dotcover cover` (chose this over
`cover-everything`'s instance model and over any pwiz change), then
`dotcover merge` -> report (JSON) -> `Summarize-Coverage.ps1`. Extended to
`-Dataset All` (loops Stellar + Astral).

**First run (unit + Stellar single straight+resume) = 70.8% cumulative**
(11465/16191 statements) vs ~45% unit-only -- the pipeline legs add ~26 points.
Per-assembly 60-90%. Remaining 0% types are mostly paths a single Stellar
straight-through can't hit (hram-only `HramStrategy`/`Ms1ScoringByproduct`,
`ElibLoader`, `LibCosineScorer`) -- expected to rise under Astral/hram.
**Instrumentation is heavy:** single-file Stellar straight-through ~7.5 min under
dotCover (Percolator folds ~400s each); the Stellar-single run was ~20 min total.

Decision (Brendan): commit the prior coverage tooling + this orchestrator
(option a), then run the **full** set -- `-Dataset All -Files All` (Stellar +
Astral, 3-file, straight + resume = everything TeamCity runs). Expect hours under
instrumentation; that merged number is the real target.

### Reconciliation note
The prior coverage WIP (`Build-OspreySharp -Coverage`, `Summarize-Coverage.ps1`,
README) was uncommitted on a base 9 behind origin, but origin's 9 commits do NOT
touch those files -> clean fast-forward + reapply, committed together here.

### 2026-06-11 -- Full `-Dataset All` run abandoned under instrumentation; Stellar 3-file first
The full `-Dataset All -Files All` run was killed after ~11 hours: it was still in
the **Astral straight-through PerFileScoring**, with the 3-file **parallel-by-default**
path driving a ~38 GB managed heap that GC-thrashed under dotCover instrumentation
(working set ~44 GB). dotCover instrumentation multiplies the per-file footprint, so
the parallel HRAM path that is merely slow uninstrumented becomes impractical here.
Two consequences:
- **Interim serialization fix** applied to the orchestrator
  (`Measure-CumulativeCoverage.ps1`): for `hram` datasets it now sets
  `OSPREY_MAX_PARALLEL_FILES=1` so the Astral leg serializes (commit `8a71b72`).
  Unit-resolution datasets (Stellar) keep the parallel default. This mirrors
  `Measure-Pipeline.ps1`'s "Astral = 1" policy and the perf scripts. (The regression.ps1
  half + the code-level smarter default are tracked separately:
  `TODO-20260611_ospreysharp_serialize_astral_runners.md` and
  `TODO-ospreysharp_file_parallelism_arg.md`.)
- **Get Stellar 3-file first.** Running
  `Measure-CumulativeCoverage.ps1 -Dataset Stellar -Files All` (unit + 3-file
  straight + resume, merged). This expands the prior 70.8% Stellar-**single** number
  to 3 files; it leaves out only HRAM-specific code (`HramStrategy`,
  `Ms1ScoringByproduct`, MS1/isotope paths). The serialized-Astral leg can follow
  separately once this lands.

### 2026-06-11 -- Stellar 3-file run #1 failed at blib write; root cause = memory, fix = serialize
The first Stellar 3-file coverage run **failed at exit 1** -- but not in the science.
It completed second-pass FDR + protein FDR (6416 protein groups) and died only at
`BlibWriter..ctor` with `Could not load file or assembly 'System.Transactions.Local'
... the system cannot find the file specified` (and earlier non-fatal
`System.Runtime.Intrinsics` warnings reloading `.scores.parquet`). Both are
**shared-framework** assemblies the uninstrumented exe loads fine (last night's
41-min TeamCity nightly wrote blibs without issue), so it is **dotCover-specific**.

**Root cause = memory exhaustion, NOT assembly resolution.** Discriminating test:
re-ran the *same* dotCover apphost launch against the completed work dir
(MergeNode-resume; all heavy stages cached -> **low** memory), hitting the identical
`BlibWriter`/`System.Transactions.Local` path -> **succeeded, exit 0, blib written**.
The only variable was peak memory: the failed run scored 3 files in **parallel**, each
~20 GB working set (peak ~25 GB). Under dotCover instrumentation that exhausts memory
and the framework assembly loader fails with a misleading "file not found". (A single-
file Stellar run -- the prior 70.8% -- also uses BlibWriter and worked, which already
ruled pure resolution out: it would have failed single-file too.)

**Fix:** `Measure-CumulativeCoverage.ps1` now sets `OSPREY_MAX_PARALLEL_FILES=1` for
**every** leg (not just hram), so each multi-file leg scores sequentially with the
full thread budget per file (commit `ddfe7c2`). No-op for single-file legs. Known
small cost: the multi-file `Parallel.For` *scheduling* branch goes uncovered (the
per-file scoring it wraps is covered regardless) -- acceptable vs. a crashed run that
yields zero coverage. Re-launched Stellar 3-file (serialized).

**Staged plan (Brendan, 2026-06-11) -- advance slowly:**
1. **Stellar 3-file** (in progress) -- the most complete number reachable on
   unit-resolution data; report it.
2. **One Astral file, straight-through** next
   (`-Dataset Astral -Files Single` with a single-file run). A single file is
   sequential by definition (`PerFileScoringTask` takes the `InputFiles.Count == 1`
   path -- no parallelism, no 44 GB blow-up, no env-var needed), so it is the cheap
   way to pick up **most** of the HRAM-specific coverage (`HramStrategy`,
   `Ms1ScoringByproduct`, MS1/isotope) that Stellar can't reach.
3. **Decide** from those two numbers whether more ambitious multi-file Astral runs
   (which need the serialized `OSPREY_MAX_PARALLEL_FILES=1` path under instrumentation)
   are worth the wall-time. The 41-min uninstrumented TeamCity nightly says the
   pipeline itself is fast; the cost here is purely dotCover instrumentation.
