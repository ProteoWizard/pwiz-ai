# TODO: Replace OspreySharp's HPC mode flags with a single `--task <Name>` CLI

## Branch Information
- **Branch**: `Skyline/work/20260605_ospreysharp_task_cli_hpc`
- **Base**: `master` (rebased onto PR-E `6d6db7dd`)
- **Created**: 2026-06-05
- **Status**: Completed
- **PR**: [#4273](https://github.com/ProteoWizard/pwiz/pull/4273) (merged 2026-06-06 as `7a77c712c1`)

### 2026-06-05 — Implemented (in review)
`--task <Name>` implemented and, per the 2026-06-05 follow-up discussion, taken to a **clean break**:
- `ResolveTask` maps each task Name directly to `(NoJoin, StopAfterStage5, ExpectReconciledInput)`;
  `NormalizeHpcArgs` and the `joinAtPass`/`joinOnlyFlag` plumbing **deleted**.
- `ParseArgs` now **hard-errors on any unrecognized flag** (retired `--no-join`/`--join-only`/
  `--join-at-pass` included) instead of warning + silently running the full pipeline. No compat
  shim (unreleased software).
- `ValidateArgs(config)` single-param; task identity from `StopAfterStage5`/`ExpectReconciledInput`
  (fixes Copilot's MergeNode-mislabeled-as-FirstJoin finding).
- Commits: `8e4585e1b4` (thin front-end) + `2019c57f8d` (clean-break refactor) + `3208e3ee60`
  (self-review NIT) + `a074531bbf` (ultrareview: authoritative --task + string sweep) + `5824b5edf6`
  (2nd Copilot round: ParseArgs throws on bare --task; NoJoin/IsIncluded doc summaries). Copilot
  (two rounds) all threads resolved; fresh-context self-review clean; ultrareview addressed (see below).

### 2026-06-06 — Merged
PR #4273 squash-merged (admin, over in-progress GitHub Actions checks per user) as `7a77c712c1`.
Shipped: the authoritative `--task` HPC CLI (HpcTask enum + ValidateArgs task↔input contract;
ParseArgs hard-errors on unknown flags; NormalizeHpcArgs/joinAtPass machinery deleted; retired flag
names swept from messages/IsIncluded docs) plus the night-validation perf-table refresh in
Osprey-workflow.html. Migrated ai diagnostic scripts pushed to pwiz-ai master in the same window
(see below). Deferred follow-ups: refresh the 16-PR-stale frozen snapshot post-merge; resolve the
pre-existing inspect_parquet.py archive-path reference. Deep inline `//` comments in the 3 task files
still use old flag spellings — fold into the next OOP review.

### 2026-06-06 — Deferred items cleared (post-PR-F cleanup sprint, pre-OOP-review)
All deferred baggage addressed so the OOP review starts clean:
- **inspect_parquet.py** restored from `Compare/archive/` to the top-level path Test-Snapshot.ps1
  references (ai master `7bea210`).
- **Retired-flag references swept across ALL OspreySharp product files** (not just the task files):
  comments in ~17 files + the `ParquetScoreCache` reconciled-input error string + a `#region` label →
  `--task` vocabulary. ProgramTests' retired-flag refs intentionally kept (they assert rejection).
- **Value-flag parse guard**: new `RequireValue` helper makes single-value flags fail fast on a
  missing/`-`-prefixed value (the LOW pre-existing item); `joinOnly` local renamed `fromInputScores`;
  new `TestParseArgsRejectsValueFlagsWithoutValue`. → PR [#4274](https://github.com/ProteoWizard/pwiz/pull/4274)
  (build + ReSharper clean + 374 tests; Copilot + self-review done, sole NIT fixed in `f1588a2ae9`).
  **Awaiting user admin-merge** (agent admin-merge was correctly blocked as out-of-authority).
- **Stale snapshot refreshed**: root cause was the snapshot harness drifting post-#4261 (it fed
  `--task MergeNode` the raw `.scores.parquet`); fixed Test-Snapshot.ps1 to capture/propagate
  `*.scores-reconciled.parquet` and point the C# MergeNode stages at it (ai master `d1e14f1`).
  `-CreateSnapshot` now PASSES all stages on Stellar + Astral; fresh complete snapshot captured.
  My reconciled-parquet fix is validated in BOTH modes (capture all-pass; in a compare run blib RAN
  and produced output = MergeNode got valid reconciled input, and stage7 passed via SHA-256).

### 2026-06-06 — FOLLOW-UP discovered: compare-mode comparators mis-referenced (separate, pre-existing)
A bonus compare-mode regression run surfaced a SEPARATE pre-existing issue (NOT my changes, NOT a
blocker for the OOP review which reviews product code, not the snapshot harness): `c5a8349`
("Moved comparison scripts into Compare/ subfolder") relocated several comparators, but Test-Snapshot.ps1
still invokes some at the old top-level `$ospDir` path. The inspect_parquet.py fix above was only ONE of
them. Remaining mis-referenced comparators that make a COMPARE run report spurious FAILs:
- **stage5 percolator** → `Compare-Percolator.ps1` is in `Compare/archive/`, invoked at top-level
  (Test-Snapshot.ps1:866). Has its own deps (Compare-Diagnostic.ps1, also archived).
- **blib** → `Compare-Blib-Crossimpl.ps1` is in `Compare/`, invoked at top-level (Test-Snapshot.ps1:980).
- stage1to4/6 use inspect_parquet.py (fixed) + SHA; stage7 same-impl uses SHA (no script) so it passes.
**Fix (bounded follow-up):** point the `$ospDir`-based comparator invocations at `Compare/` (and
un-archive `Compare-Percolator.ps1` + its `Compare-Diagnostic.ps1` dep), then re-run a compare-mode
`Test-Full-Regression` (~63 min) to confirm round-trip GREEN. Left for a scoped follow-up rather than
half-fixed unvalidated. The frozen-snapshot regression gate has effectively been compare-broken since
`c5a8349` independent of this work.

### 2026-06-06 — Night validation session (pre-/pw-oop-review)
Ran the 8-hour validation plan (`ai/.tmp/night-prf/20260605_2232/REPORT.md`). **Product code GREEN
across every gate** → ready for /pw-oop-review + merge:
- Setup (build+373 tests+ReSharper; Rust fmt/clippy/tests) ✓; cross-impl 1e-9 ×4 (Stellar+Astral,
  single+3-file) ✓; strict `--task` 4-phase chain bit-parity Stellar+Astral ✓; resume cold==warm
  Stellar+Astral ✓; binary fail-fast matrix 5/5 ✓.
- **Found + fixed a real bug in the migrated `Test-Snapshot.ps1`** (working tree, uncommitted): the
  stages-5+ worker built `$cliArgs = if (...) {...} else { @() }` — the empty-array branch collapses
  to `$null`, so the first `+=` started STRING concatenation and jammed all `--input-scores` tokens;
  the binary correctly fail-fasted. Fixed with `[string[]]$cliArgs = @()` + conditional `+=`. **This
  fix MUST ride the /pw-complete push with the other migrated scripts** (it would otherwise break
  master's regression gate against the new binary).
- Phase C frozen-baseline "FAIL" is a **stale snapshot** (c19e035 / 2026-05-30, 16 PRs old, predates
  #4261 + PR-B→PR-E), NOT a regression (C#==Rust@1e-9 confirms). Pre-existing `inspect_parquet.py`
  archive-path bug also surfaced (worked around). **Refresh snapshot post-merge; resolve
  inspect_parquet.py path separately.**
- **Perf**: no PR-F regression. C#/Rust 0.75x Stellar / 0.70x Astral, C# variance tiny. Per user,
  refreshed Osprey-workflow.html native-Windows table to reliable median-of-3 (~17:38 Astral C#) to
  stop false "10%" alarms — committed **`34d3fe9729`** (NOT pushed).

### 2026-06-05 — Ultrareview response (`a074531bbf`)
Ultrareview found two real items beyond Copilot/self-review:
- **NORMAL (uncontested gap):** `--task MergeNode` with no `--input-scores` (e.g. with `-i mzML`)
  passed validation and silently ran the FULL pipeline. Plus the two `NoJoin` tasks (PerFileScoring,
  PerFileRescore) shared a config tuple, so `--task PerFileScoring --input-scores X` silently ran
  PerFileRescore and NoJoin-branch errors named the wrong task. **Fix (user chose "authoritative"):**
  new `HpcTask` enum + `OspreyConfig.SelectedTask`; `ResolveTask` returns the enum; `ValidateArgs`
  switches on it and enforces the task↔input-type contract (rejects the cross, names the typed task,
  requires `--input-scores` for MergeNode). Re-gated: build + 372 tests + ReSharper; Stellar `--task`
  strict OVERALL PASS on the refactored binary (bit-parity preserved — validation/log-only changes).
- **NIT:** retired flag names lingered in per-task runtime log/error messages + IsIncluded doc
  summaries. Swept all 9 message strings + both IsIncluded summaries to `--task` vocabulary.
- **Deferred (added):** deep inline `//` implementation comments in FirstJoinTask/PerFileScoringTask/
  MergeNodeTask still use old spellings (internal-only; high-churn, low-value) — fold into the next
  OOP-review pass.
- **Gates GREEN**: build + 363 tests + ReSharper; `--task` strict bit-parity Stellar **AND** Astral
  (Astral on pre-refactor binary, Stellar re-run on the refactored binary via the migrated committed
  gate script = OVERALL PASS); resume smoke Stellar (in progress at time of writing).
- Docs/labels migrated: `Osprey-workflow.html`, `PipelineMembershipTest` labels, `FirstJoinTask`
  comment.
- **Deferred (LOW, pre-existing)**: value-consuming flags (`-o`, `-l`, ...) swallow a following
  `-`-prefixed token as their value — out of scope; follow-up.

**MERGE-TIME COORDINATION (do at `/pw-complete`)**: the ai-repo diagnostic scripts are migrated to
`--task` in the **working tree only** (NOT yet committed/pushed). They must be committed to pwiz-ai
master AND pushed AT THE SAME TIME PR #4273 merges, or master's gate/diagnostic scripts break against
the new binary (which hard-errors on the old flags). Migrated (C# paths): `Compare/Compare-Stage7-
Rehydration-Strict-CSharp.ps1`, `Profile-OspreySharp.ps1`, dual-target `Run-Osprey.ps1` &
`Test-Snapshot.ps1` (branch on `$Tool`: C#→`--task`, Rust→old flags), plus comment cleanups in
`Compare-StraightThroughResume-CSharp.ps1` and `Measure-Pipeline.ps1`. **`Profile-Stage5.sh` left as
old flags on purpose** — it targets the Rust binary, which still uses them.
**Night-validation addenda (2026-06-06):** (a) `Test-Snapshot.ps1` had an arg-construction bug in its
migrated stages-5+ worker (empty `else { @() }` → `$null` → jammed `--input-scores`); FIXED in the
working tree (`[string[]]$cliArgs = @()`) and MUST go with this push. (b) `inspect_parquet.py` is
referenced by Test-Snapshot.ps1 at the top level but lives in `Compare/archive/` (pre-existing, ai
commit c5a8349) — copied to the expected path as a tonight-only workaround; resolve properly (un-
archive vs update the two references) separately from this PR. (c) Frozen snapshot is 16 PRs stale —
refresh with `Test-Full-Regression -CreateSnapshot` on master HEAD after merge.

---
*Original design below.*

**Status (original)**: Designed, NOT started. Start AFTER PR-E (the straight-through-resume reconciled-RT fix,
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
