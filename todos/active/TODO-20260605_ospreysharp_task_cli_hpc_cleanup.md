# TODO: Replace OspreySharp's HPC mode flags with a single `--task <Name>` CLI

**Status**: Designed, NOT started. Start AFTER PR-E (the straight-through-resume reconciled-RT fix,
branch `Skyline/work/20260605_ospreysharp_resume_reconciled_rt`) merges, and BEFORE the next
`/pw-oop-review` (this cleanup removes a chunk of the CLI/mode-routing complexity an OOP review
would otherwise flag).
**Priority**: Medium-high — the NextFlow HPC pipeline is being implemented NOW; defining the clean
interface before the old flags entrench in pipeline scripts is near-zero cost today and rises weekly.
**Origin**: Brendan, 2026-06-05 — the current worker-mode flags conflate two concerns (HPC
distribution + diagnostic bisection) and are hard to explain to the NextFlow implementer.

## Problem

The per-stage worker CLI evolved to serve BOTH the diagnostic strict-rehydration gate AND the HPC
environment, so it expresses "run this stage, hydrate from these inputs" through a confusing
combination of `--no-join`, `--join-only`, `--join-at-pass=1|2`, `--input-scores`,
`StopAfterStage5`, `ExpectReconciledInput`. A NextFlow author has to decode that
`--join-at-pass=1 --no-join --input-scores` means "the Stage-6 rescore worker."

The PR-A→PR-E declarative-dataflow refactor already made hydration **mechanism-driven, not
flag-driven**: each task rehydrates its upstream state from whatever sidecars are valid on disk
("the disk state determines the hydration shape"). So the flags that used to *steer* hydration are
now largely vestigial — the task already knows how to hydrate. This TODO is the capstone of that
direction.

## Design — `--task <Name>` as the single task-selection interface

Add `--task <Name>` that runs exactly one pipeline task (HPC: one node = one task). It sets the
existing internal `StartAt = StopAfter = <task>` and the implied hydration expectation. The
internal StartAt/StopAfter/ExpectReconciledInput state STAYS as-is; `--task` is a thin, self-
documenting front-end over it. Default (no `--task`) = run the full pipeline (single machine /
straight-through, incl. resume).

Each current worker mode is exactly ONE task — a clean 1:1 collapse (VERIFY against `Program.cs`
arg parsing + the `IsIncluded` matrix + `ProgramTests` before coding; the mapping below is
reconstructed from the PR-D/PR-E work):

| Today's flags                                         | `--task` equivalent      | implies                       |
|-------------------------------------------------------|--------------------------|-------------------------------|
| `--no-join`                                           | `--task PerFileScoring`  | stop after Stage 1-4          |
| `--join-at-pass=1 --join-only` (StopAfterStage5)      | `--task FirstJoin`       | StopAfterStage5               |
| `--join-at-pass=1 --no-join --input-scores`           | `--task PerFileRescore`  | rescore worker                |
| `--join-at-pass=2` (ExpectReconciledInput)            | `--task MergeNode`       | ExpectReconciledInput         |
| *(none)* straight-through                             | default (no `--task`)    | run all                       |

### Refinements (decided in the 2026-06-05 discussion)
1. **Use the stable task `Name`** ("FirstJoin", "PerFileRescore", …), NOT the C# class name —
   decouples the CLI contract from refactors (renaming `FirstJoinTask` won't break pipelines) and
   reads cleaner. The `Name` property already exists on each `OspreyTask`.
2. **Keep `--input-scores` — it is an INPUT specifier, not a mode flag.** `--task FirstJoin` still
   has to be told which score parquets to consume (vs `-i` mzML). `--task` replaces the *mode*
   flags only; the input flags stay.
3. **"Start from scores on one machine" is NOT a mode** — it is just the default full pipeline with
   `--input-scores` instead of `-i mzML` (PerFileScoring rehydrates from the supplied scores rather
   than computing). So that multi-task convenience falls out for free, no flag. VERIFY this is the
   one mode that currently runs a *range* of tasks and that it is input-type-driven, not flag-driven.

### Flag keep / drop
- **DROP (replaced by `--task`)**: `--no-join`, `--join-only`, `--join-at-pass=1|2`. (And the
  user-facing notion of StopAfterStage5/ExpectReconciledInput as CLI surface — they become internal
  state set by `--task`.)
- **KEEP**: `--task` (new), `-i` (mzML inputs), `--input-scores` (score-parquet inputs), `-l`,
  `-o`, `--resolution`, `--protein-fdr`, `--threads`, and the `OSPREY_*` diagnostic env vars.

## HPC vs diagnostic separation
`--task` serves BOTH uses, so do NOT build a parallel env-var dialect for task selection. The
diagnostic strict-rehydration gate's four phases map 1:1 onto
`--task PerFileScoring / FirstJoin / PerFileRescore / MergeNode`, so migrating it to `--task` makes
it CLEARER, not just different. Reserve env vars for the genuinely sub-task diagnostic knobs that
already use them (the `OSPREY_*` dump / early-exit vars) — orthogonal to task selection. Net: one
task-selection interface for everyone; env vars only for finer diagnostic control. (This refines
Brendan's "replace the flags with diagnostic env vars" — env vars only where `--task` granularity
isn't enough, which is just the existing dump vars.)

## Scope / work items
- CLI parsing: add `--task <Name>`, resolve to the task by `Name`, set StartAt/StopAfter + implied
  ExpectReconciledInput/StopAfterStage5. One `task -> {StopAfterStage5, ExpectReconciledInput,
  expects InputScores}` mapping table, in ONE place.
- Validation + clear errors (e.g. `--task MergeNode` without reconciled inputs). Migrate the
  `ProgramTests` validation cases (`TestValidateJoinOnlyRequiresInputScores` and friends) to `--task`.
- Remove the dropped mode flags (clean break — NextFlow isn't done, so no compat shim needed).
- Migrate the diagnostic gate scripts to `--task`:
  `ai/scripts/OspreySharp/Compare/Compare-Stage7-Rehydration-Strict-CSharp.ps1` (the 4-phase chain),
  and check `Compare-StraightThroughResume-CSharp.ps1` (default pipeline — likely unchanged).

## Gates
- `Build-OspreySharp.ps1 -RunTests -RunInspection`.
- Worker-mode strict bit-parity Stellar AND Astral
  (`Compare-Stage7-Rehydration-Strict-CSharp.ps1`, after migrating it to `--task`).
- Straight-through resume smoke Stellar + Astral (`Compare-StraightThroughResume-CSharp.ps1`).
- `Compare-EndToEnd-Crossimpl` 1e-9.

## Open questions to settle during implementation
- Confirm the exact current mode->task mapping against `Program.cs` + `IsIncluded` (the matrix in
  `ai/todos/completed/TODO-20260601_ospreysharp_declarative_pipeline_dataflow.md`).
- Does any HPC scenario need a *range* of tasks on one node (not just single)? Brendan: "the only
  need is running a single task." If a range is ever needed, the StartAt/StopAfter internals remain,
  so a later `--task-range`/`--start`/`--stop` is a small add — do NOT build it speculatively now.
- Should `--input-scores` auto-discover sibling sidecars (so `--task FirstJoin -i <dir>` suffices)
  or stay explicit? Lean explicit for clarity.

## Related
- `ai/todos/completed/TODO-20260601_ospreysharp_declarative_pipeline_dataflow.md` (umbrella;
  IsIncluded matrix, the mechanism-driven hydration direction this completes).
- `ai/todos/completed/TODO-20260604_ospreysharp_rehydrate_purity_prd.md` (PR-D).
- PR-E (resume reconciled-RT fix) — must merge first.
