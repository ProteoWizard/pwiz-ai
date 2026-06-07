# TODO: OspreySharp — replace static diagnostics with an injectable sink (no-op default, enabled by `-d`)

## Branch Information
- **Branch**: `Skyline/work/20260606_ospreysharp_diagnostics_di`
- **Base**: `master`
- **Created**: 2026-06-06
- **Status**: In Progress
- **PR**: (pending)

**Priority**: Medium — clean, mostly parity-neutral, unblocks cleaner scoring/calibration extraction
**Type**: Architecture / decoupling
**Source**: OOP review of `pwiz_tools/OspreySharp` (2026-06-06), Coupling lens + Top Recommendation #3

## Progress log
- 2026-06-06: Branch created. First commit strips the UTF-8 BOM that ReSharper
  re-added to `pwiz_tools/Skyline/Skyline.sln.DotSettings` in #4065 (unrelated
  housekeeping, bundled here per developer request). Diagnostics work follows.
- 2026-06-06: Commented out the predict-rt diagnostic family (per-candidate
  hotspot the OOP review flagged) -- see "Call-site disposition" below. Verified
  green: build (net472 + net8.0), 372 unit tests pass, ReSharper 0 warnings.
  Output-neutral (env-gated dumps, off in all normal runs).
- 2026-06-06: Landed the injectable diagnostics sink (commit 5c36139759).
  **As built (deviation from "Desired design" above):** the DI vehicle is a
  static **facade** `OspreyDiagnostics` (call sites unchanged) delegating to a
  swappable `OspreyFileDiagnostics` sink; the no-op default is a `null` sink
  (null-object via `?.`), not a separate base class and not
  `PipelineContext.Diagnostics`. Chosen for the smaller/safer diff over the
  ~40-flag virtual/override surface (developer picked "encapsulated sink, facade
  kept"). The static `OspreyDiagnostics` class became the instance
  `OspreyFileDiagnostics` (members converted static->instance, dump BODIES
  untouched = byte-stable); the new facade forwards every flag/method. `-d` /
  `--diagnostics` added to `OspreyConfig` + parsed in `Program`, calling
  `OspreyDiagnostics.Initialize(forceDumps)` at pipeline entry; it turns on a
  documented OSPREY_DUMP_* bundle (excludes the per-call MP_INPUTS firehose, the
  disabled predict-rt dump, the *_ONLY exits, and the per-entry DIAG selectors).
  Env-only workflows still self-enable via lazy `Initialize(false)` on first use.
  Verified green: build, 372 tests, ReSharper 0 warnings. Production runs (no env,
  no -d) get a null sink = full no-op.
- 2026-06-06: **Bit-parity verified (measured, not by-construction).** Built Release
  from this branch and ran Test-Snapshot on Stellar `-Files All` vs `_snapshots/main`
  (baseline #4273, an ancestor of HEAD). All comparisons byte-identical: stage1to4,
  stage5 standardizer/subsample/svm_weights, stage5 percolator (SHA 0cc0c7f9, both
  sides), stage6 (parquet+fdr_scores), stage7, and blib (Compare-Blib: 0/59768
  divergence, all columns). The three stage5 dumps + percolator going through the new
  facade/sink prove the dump output is unchanged. Confounds hit along the way (logged
  in TODO-ospreysharp_selfcontained_e2e_regression_gate.md): the first `-Quick` run was
  a false fail (stale Release binary + single-file vs 3-file baseline); and
  Test-Snapshot reports false FAILs on percolator/blib because it invokes
  `Compare-Percolator.ps1` / `Compare-Blib-Crossimpl.ps1` at stale top-level paths
  (now in Compare/archive/ and Compare/). Astral `-Files All` not yet run.

## Problem

`OspreySharp/OspreyDiagnostics.cs` is a ~2,013-line **static** class holding
process-global mutable state (open writers, collection buffers:
`StartCalWindowCollection`, `AddCalWindowRow`, `CloseMpInputsDump`,
`ClosePredictRtDump`, …) and toggled by **environment variables**
(`IsOne`, `ParseIdSet`, `ParseNullableUint` parse `$env:` at call time).

Production (non-test) code calls into it from **104 sites**, concentrated in the
hot scoring path:

| File | Calls |
|------|------:|
| `OspreySharp/Tasks/PerFileScoringTask.cs` | 39 |
| `OspreySharp/Tasks/FirstJoinTask.cs` | 32 |
| `OspreySharp/Tasks/AbstractScoringTask.cs` | 16 |
| `OspreySharp/Tasks/PerFileRescoreTask.cs` | 8 |
| `OspreySharp/Tasks/MergeNodeTask.cs` | 7 |
| other | 2 |

One sits inside the per-candidate loop —
`OspreyDiagnostics.WritePredictRtCall(candidate.Id, …)` at
`AbstractScoringTask.cs:903`, invoked for every candidate. The production scorer
thus has a hard, unconditional dependency on a global static singleton plus its
env-var configuration. The dependency is *justified today* by the steel-thread
parity doctrine (the dumps are the Stage 1–5 bisection seams), but it is real
coupling: the domain logic can't be reasoned about or reused without dragging the
dump infrastructure along, and "is diagnostics on?" is invisible at the call site.

`OspreySharp.FDR/PercolatorFdr.cs` carries the same smell at the FDR layer: five
`WriteStage5*Dump` writers (`:2127–2324`) live inside the SVM/FDR engine.

## Desired design (user direction)

Replace the static class with an **interface + no-op default implementation,
selected by dependency injection** and turned on by a `-d` (diagnostics) CLI
argument:

- `IOspreyDiagnostics` interface declaring the dump surface (the existing
  `Write*Dump` / `Should*` / `Open*` / `Close*` methods).
- `NullOspreyDiagnostics` — the default no-op implementation. When diagnostics are
  off, every call is a cheap no-op (null-object, no env lookups). **Preserve the
  near-zero hot-path cost** the env-var short-circuit gives today — measure
  `WritePredictRtCall` per-candidate overhead before/after.
- `FileOspreyDiagnostics` — the real implementation that owns the writers and the
  per-dump selection (which entry IDs, which pass), moved off statics into
  instance state so a run's diagnostics are self-contained and testable.
- **Injection vehicle: `PipelineContext`.** Add
  `IOspreyDiagnostics Diagnostics { get; }` to the context (it already flows to
  every task's `Run`/`Rehydrate`). Tasks call `ctx.Diagnostics.WriteX(...)`. The
  `AbstractScoringTask._ctx` field already in scope means the engine's static
  `OspreyDiagnostics.X` calls become `_ctx.Diagnostics.X` with no new plumbing.
- **`PercolatorFdr`** (static): thread the sink in as a parameter on the methods
  that dump (they already take `config`/`ctx`-shaped args), and move the
  `WriteStage5*Dump` bodies into `FileOspreyDiagnostics` so the FDR engine no
  longer owns parity scaffolding.
- **CLI**: `-d` / `--diagnostics` on `OspreyConfig` (parsed in `Program`) selects
  `FileOspreyDiagnostics`; default is `NullOspreyDiagnostics`. Sub-selection
  (entry-id sets, stage filters) can stay env-var-driven *inside*
  `FileOspreyDiagnostics`, or migrate to `-d` sub-options — design decision below.

## Constraints (osprey)

- **Parity is byte-for-byte.** This is a pure relocation: the dumps themselves and
  the values dumped must not change, and — critically — enabling/disabling
  diagnostics must not perturb scoring output (no order-of-operations or RNG
  coupling hiding in the dump calls).
- Pre-commit gate (build + tests + zero-warning inspection):
  `Build-OspreySharp.ps1 -Configuration Debug -RunTests -RunInspection`.
- Because hot-path scoring calls are touched, run the C#-side refactor gate
  before/after with `-d` **off** -- the multi-file straight-through run reusing the
  cached Rust reference (Rust not re-run):
  `Compare-EndToEnd-Crossimpl.ps1 -Files All -SkipRust` on Stellar + Astral;
  Stage 7 + blib must match at 1e-9. (Cached Rust reference must match the
  `-Files` set; no `-Force` with `-SkipRust` -- it wipes the cached `rust/`.) Diff
  a representative dump set with `-d` **on** against a current env-var capture to
  prove the dump content is identical.
- net8.0 is the canonical parity runtime.
- Do **not** loosen any parity gate to make this pass — if output moves, the
  extraction changed something; bisect it.

## Call-site disposition (decided 2026-06-06)

These dumps are "previously useful" bisection diagnostics; each call site is a
risk-vs-future-reward call. Two dispositions, not one:

1. **Keep & inject** (the default for the ~100 non-hot-path sites): route through
   `ctx.Diagnostics` with the no-op default. A no-op virtual call per task/per-file
   is negligible.
2. **Remove / comment out** (hot-path sites in per-candidate / per-spectrum inner
   loops): do NOT inject — even a gated-off call + branch per candidate is unwanted
   perf risk that outweighs the future reward of keeping it wired. Comment the call
   out (don't delete the producing method), leave a restore note pointing here.
   Accepts some code-drift risk before the diagnostic is next used; restoring even
   with drift is usually little work.

First applied to the predict-rt family (the hotspot the OOP review flagged):
`WritePredictRtCall` (per-candidate, `AbstractScoringTask.ScoreCandidate`) plus its
paired `WritePredictRtArrays` / `ClosePredictRtDump` in `PerFileRescoreTask` are
commented out as a unit. Byte-identical for production/regression (the dumps are
env-gated and off in every normal run); the `OspreyDiagnostics` methods stay for
easy restore. Verified: build + 372 unit tests + ReSharper 0-warning gate all pass.

## Open design questions

- Keep env-var sub-selection inside `FileOspreyDiagnostics`, or fold all toggles
  into `-d` sub-options? (Leaning: keep env vars for fine entry-id selection,
  `-d` as the master on/off — least churn, preserves existing bisection muscle
  memory.)

## Relationship to sibling TODOs

- Do this **first** or alongside `TODO-ospreysharp_extract_calibrator.md` and
  `TODO-ospreysharp_modular_scoring_context.md`: removing the static-call surface
  means the extracted `Calibrator` / score-calculator classes receive an injected
  sink instead of reaching for a global, which keeps them self-contained.
- Precedent for the injected-context pattern:
  `TODO-20260604_ospreysharp_byproduct_context_prc.md` (PR-C) and
  `PipelineContext` itself.
