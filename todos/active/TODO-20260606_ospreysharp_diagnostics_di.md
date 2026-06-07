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
- Gate with the **C#-only end-to-end regression** before/after:
  `Compare-EndToEnd-Crossimpl -Files All -SkipRust` (reuse cached Rust).
- Because hot-path scoring calls are touched, also run `Test-Features.ps1` on
  Stellar + Astral at **1e-6 per PIN feature** with `-d` **off** and confirm the
  feature vectors are unchanged. Diff a representative dump set with `-d` **on**
  against a current env-var capture to prove the dump content is identical.
- net8.0 is the canonical parity runtime.
- Do **not** loosen any parity gate to make this pass — if output moves, the
  extraction changed something; bisect it.

## Open design questions

- Keep env-var sub-selection inside `FileOspreyDiagnostics`, or fold all toggles
  into `-d` sub-options? (Leaning: keep env vars for fine entry-id selection,
  `-d` as the master on/off — least churn, preserves existing bisection muscle
  memory.)
- Null-object vs. an `IsEnabled` guard at the hottest sites — measure which keeps
  `WritePredictRtCall` overhead at zero when off.

## Relationship to sibling TODOs

- Do this **first** or alongside `TODO-ospreysharp_extract_calibrator.md` and
  `TODO-ospreysharp_modular_scoring_context.md`: removing the static-call surface
  means the extracted `Calibrator` / score-calculator classes receive an injected
  sink instead of reaching for a global, which keeps them self-contained.
- Precedent for the injected-context pattern:
  `TODO-20260604_ospreysharp_byproduct_context_prc.md` (PR-C) and
  `PipelineContext` itself.
