# TODO-20260920_osprey_one_task_list.md - One authoritative task list: `--task` looks up an `OspreyTask`, the `HpcTask` enum and its switches go

## Branch Information
- **Branch**: `Skyline/work/20260920_osprey_one_task_list` (checkout `C:\proj\pwiz-work2`)
- **Base**: `Skyline/work/20260612_net8_port` (the .NET 10 port, PR #4619) - all Osprey development is on the port branch
- **Created**: 2026-09-20
- **Status**: PR #4693 open (base = port branch), three commits; reworked to two explicit lists + one membership rule per Brendan's review (`f852b35316`, see the rework section at the end); local gates green on the final commit (Debug tests + inspection, Stellar, StellarLibDecoy); /code-review max triaged in `41e44df8da`; TeamCity Perf/Regression not yet triggered (ask first, `branch="pull/4693"`)
- **Module**: `osprey`
- **PR**: [#4693](https://github.com/ProteoWizard/pwiz/pull/4693)

Raised by Brendan 2026-09-19 reviewing [#4686](https://github.com/ProteoWizard/pwiz/pull/4686).
Started after #4686 merged (2026-09-19; that PR makes each task's `TASK_NAME` the one spelling
of its name; this one makes the task instances the one list). Branched from the port branch at
`f438033ddf`.

## The goal, in Brendan's words

Restore a central list of all available Tasks that directly maps to the `--task` CLI argument,
so that `ALL_TASKS.Select(t => t.Name)` is the preferred way to get the full list of task names
for the CLI usage, the enum goes away, and every switch on it is replaced by a lookup in the list
- "one authoritative list and one place to add a new task". All tasks derive from `OspreyTask`,
including `ModelDiagnostics`, which today has no task class.

## What the history actually says (checked 2026-09-19)

The assumption that `--task` was once a lookup in the pipeline list is not what happened, and
knowing that keeps this from being framed as a restoration of something SpectraCache broke:

- `7a77c712c1` (#4273, 2026-06-06) introduced `--task` AND `enum HpcTask` (four members) AND a
  `ResolveTask` made of four `string.Equals` against literals, replacing the `--no-join` /
  `--join-only` / `--join-at-pass` mode flags. `ResolveTask` has never enumerated the task list
  by `Name` in any commit that touched it. What was, and is, list-driven is the PIPELINE: the
  driver walks `CanonicalPipeline()` and uses `task.Name` for `[TASK]` log lines and the
  `.osprey.task` stamps.
- The dependency chain has been `Osprey.Core <- Osprey.Tasks <- Osprey (exe)` since Phase A
  (`12825485a9`, #4197, 2026-05-11). `OspreyConfig` has always lived in Core, so the config has
  never been able to hold an `OspreyTask`. That is why #4273 put an enum in Core.
- At #4273 the four concrete task classes still lived IN THE EXE beside `Program.cs`; #4304
  (2026-06-16) lifted them into `Osprey.Tasks`. Then #4633 (2026-09-06) made the task library
  itself read `config.SelectedTask` (`RunsStage7Join`, `ReadsReconciledScores`,
  `StartsAfterPerFileScoring`, the resident-pool gate, two `IsIncluded` overrides). Today the
  selection has two consumers on two sides of the Core boundary, which is the one thing
  "enumerate the list in Program" does not solve on its own.
- SpectraCache (#4502) and ModelDiagnostics (#4585 / #4646) each appended an enum member and a
  switch case to a structure that was already enum-and-switch.

## Every place the enum reaches today (`HEAD` of #4686)

| Where | What keys on `HpcTask` |
|---|---|
| `Osprey/Program.cs:111-160` | `ResolveTask` (name -> enum, now a loop over `Enum.GetValues` + `TaskCliName`), then four flag derivations: `ModelDiagnostics`, `NoJoin`, `StopAfterStage5`, `ExpectReconciledInput` |
| `Osprey/Program.cs:561-573` | `TaskCliName`: the enum -> `TASK_NAME` switch |
| `Osprey/Program.cs:655-717` | `ValidateArgs`: per-task switch on what each task requires (inputs / library / output / FirstPassFDR's 2+ inputs and `Reconciliation.Enabled`) |
| `Osprey/Program.cs:317-319, 738-740` | settings-echo "Output:" line; `ExperimentAggFileCount` (per-file workers return 0) |
| `Osprey/AnalysisPipeline.cs:76` | `SpectraCachePipeline()` vs `CanonicalPipeline()` |
| `Osprey.Tasks/ScoringTaskShared.cs:431-433, 500-508, 538, 562-568` | four per-task facts: may hydrate per run, starts after PerFileScoring, reads reconciled scores, runs the Stage 7 join |
| `Osprey.Tasks/SpectraCacheTask.cs:66`, `PerFileRescoreTask.cs:178` | `IsIncluded` gates |
| `Osprey.Core/OspreyConfig.cs:372, 382, 423` | `SelectedTask` (`HpcTask?`), `DiagnosticsOnly`, the enum itself |
| tests | `ForTask(HpcTask)` / `TaskConfig(HpcTask)` helpers; ~60 `HpcTask.X` sites, mostly `ProgramTests.cs` |
| docs | `docs/15-hpc-scoring-split.md` truth table; mentions in 00, 07, 11, DIVERGENCES |

Every row is a property of the selected task. The four FLAGS (`NoJoin`, `StopAfterStage5`,
`ExpectReconciledInput`, `ModelDiagnostics`) are consumed at ~50 sites inside the tasks and stay
flags; what changes is who derives them.

## Design

**Layering.** The consumer defines the contract it needs from a selected task; the definition
has to sit where BOTH consumers can see it, which is Core (the exe and the task library both
reference Core, and the task library never references the exe). So: a small interface in
`Osprey.Core`, implemented by `OspreyTask`, carried by the config. Core still names no task.

1. **`ISelectableTask` in Core** (name open): `Name`, plus the per-task facts the config-keyed
   code asks today, as read-only bools - `HydratesPerRun`, `StartsAfterPerFileScoring`,
   `ReadsReconciledScores`, `RunsStage7Join`, `IsPerFileWorker`, `RunsStandalone`,
   `InCanonicalPipeline`. `OspreyConfig.SelectedTask` becomes `ISelectableTask` (null = the full
   pipeline). `DiagnosticsOnly` becomes a plain settable flag like its three siblings.

2. **`OspreyTask : ISelectableTask`** with every fact a virtual defaulting to FAIL CLOSED (a task
   added later is admitted to nothing until its author decides - the direction
   `RunsStage7Join`'s doc already argues for). The five existing tasks override what is true
   of them; the predicates in `ScoringTaskShared` become one-liners
   (`config.SelectedTask?.RunsStage7Join ?? true`); `SpectraCacheTask.IsIncluded` becomes
   `ReferenceEquals(ctx.Config.SelectedTask, this)`, which works because the pipeline list and
   the selection share instances.

3. **Two more virtuals replace `Program`'s switches.** `ApplySelection(OspreyConfig)`: the task
   sets the flags it implies (PerFileScoring / PerFileRescore -> `NoJoin`; FirstPassFdr ->
   `StopAfterStage5`; SecondPassFdr -> `ExpectReconciledInput`; ModelDiagnostics ->
   `ModelDiagnostics` + `DiagnosticsOnly`). `ValidateSelection(OspreyConfig) -> string`: the
   default demands input + library + output with messages built from `Name`; SpectraCache
   overrides to input only; FirstPassFdr adds its 2+ inputs and `Reconciliation.Enabled` checks.
   `ValidateArgs` collapses to `config.SelectedTask?.ValidateSelection(config)`;
   `ExperimentAggFileCount` and the "Output:" echo read `IsPerFileWorker` / `RunsStandalone`.

4. **The registry, beside `OspreyTask` in `Osprey.Tasks`:** `OspreyTasks.CreateAll()` returns the
   six instances in `--help` order. The canonical four are `all.Where(t => t.InCanonicalPipeline)`;
   the pipeline to run is `selected?.RunsStandalone == true ? new[] { selected } : canonical`
   (SpectraCache is the only standalone task). `CanonicalPipeline()` / `SpectraCachePipeline()`
   go away. A factory, not a static singleton: tasks hold per-run state (the `Rehydrate` one-shot
   guards) and the tests run several pipelines per process. `Main` calls it once and shares the
   instances between the lookup and the run:
   `var all = OspreyTasks.CreateAll(); var selected = all.FirstOrDefault(t => name matches, OrdinalIgnoreCase)`;
   an unknown name lists `all.Select(t => t.Name)`.

5. **`OspreyCommandArgs.ARG_TASK`'s value list** is `OspreyTasks.CreateAll().Select(t => t.Name).ToArray()`,
   evaluated once in the static initializer (six trivial constructions; check the constructors
   stay allocation-free). `--help` and `--task` resolution then cannot disagree.

6. **`ModelDiagnosticsTask : OspreyTask`**, selector-only: in `CreateAll()`, in no pipeline
   (`IsIncluded` false, `Run` / `Rehydrate` unreachable), owning `TASK_NAME` (moved off
   `ModelDiagnosticsReport`), answering the facts (`RunsStage7Join` true, `HydratesPerRun`
   true) and applying its two flags. Same role SpectraCache plays with a one-task pipeline.
   The non-degenerate version - a fifth canonical task after SecondPassFDR that OWNS the report
   render, replacing the `DiagnosticsOnly` write-suppression threaded through the other tasks -
   is the natural follow-up but a behavior move; keep it out of this PR and say so in the class
   doc.

**Adding a task afterwards** = one class deriving from `OspreyTask` (its `TASK_NAME`, its
overrides) + one line in `CreateAll()`. Nothing in `Program`, `OspreyCommandArgs` or
`ScoringTaskShared` changes.

## Scope

About 15 files: Core (delete the enum; the interface; `SelectedTask`'s type; `DiagnosticsOnly` a
flag), Tasks (`OspreyTask` virtuals; five overrides; `ModelDiagnosticsTask`; `OspreyTasks`; the
four predicates; two `IsIncluded`), exe (`Main`, `ValidateArgs`, `ExperimentAggFileCount`, the
echo, `AnalysisPipeline`, `ARG_TASK`), tests (`ForTask` / `TaskConfig` take a task instance;
`ProgramTests` ~40 sites, `PipelineMembershipTest`, `LibraryFragmentReleaseTest`, `IOTest` x3;
the `TestResolveTask` round-trip becomes "every task in `CreateAll()` resolves to itself and
appears in `ARG_TASK.Values` exactly once"), and the truth table in
`docs/15-hpc-scoring-split.md`.

## Gates

- `Build-Osprey.ps1 -SourceRoot C:\proj\pwiz-work2 -Configuration Debug -RunTests -RunInspection`.
- `regression.ps1 -Dataset Stellar` is the correctness proof, not optional: this touches
  pipeline selection and the membership predicates, mode 3 drives every `--task` on its own
  node, and modes 4/5 exercise the resident-pool predicate. Output must match the golden at 1e-9.
- `/code-review max` before the PR; verify each finding (the #4686 review was right about a
  production regression and wrong about a Skyline contract - check both ways).

## Open decisions (recorded, not blocking)

- Interface-in-Core (above) vs the cheaper string-name `SelectedTask` with `TASK_NAME`
  comparisons in the predicates. Recommendation: the interface - the predicates are per-task
  facts, and that is where a switch-free design puts them. Brendan 2026-09-19: the Program owns
  the contract it needs and every task derives from `OspreyTask`.
- Selector-only `ModelDiagnosticsTask` now; report-owning task later.

## Progress

### 2026-09-20 - implemented, gates running

Implemented the design above as written, with these decisions made where the sketch left
room:

- **`ISelectableTask` (Core)** carries `Name`, the five per-task facts the config-keyed code
  asks (`HydratesPerRun`, `StartsAfterPerFileScoring`, `ReadsReconciledScores`,
  `RunsStage7Join`, `IsPerFileWorker`) and three calls the exe makes of the selection:
  `ApplySelection(config)`, `ValidateSelection(config)`, `DescribeOutput(config)`. The last
  replaces the "Output:" echo's three-way `if` on the task: each task describes what it
  writes (SpectraCache the caches, PerFileScoring the parquets, ModelDiagnostics the report),
  null = the blib. `InCanonicalPipeline` / `RunsStandalone` are on `OspreyTask` only - they
  compose the pipeline, which is done where `OspreyTask` instances are in hand.
- **`OspreyConfig.SelectTask(task)`** is the one writer of `SelectedTask` (private set) and
  calls `task.ApplySelection(this)`, so the selection and its flags cannot be written apart.
  `DiagnosticsOnly` is a plain flag set by `ModelDiagnosticsTask.ApplySelection`.
  `HasInputFiles` added to the config (three copies of the null-or-empty test folded).
- **`OspreyTasks`** (`Osprey.Tasks/OspreyTasks.cs`): `CreateAll()` (six instances, `--help`
  order), `FindByName` (OrdinalIgnoreCase), `PipelineFor(all, selected)` (standalone alone,
  else canonical; throws if the selection is not from `all`, so a namesake from a second
  list cannot build a pipeline whose reference checks all fail), `CanonicalPipeline(all)`.
  `AnalysisPipeline.Run(config, allTasks)` takes the list; `CanonicalPipeline()` /
  `SpectraCachePipeline()` are gone.
- **`ModelDiagnosticsTask`** at the Tasks root beside its five siblings (not under
  `ModelDiagnostics/`), selector-only: `IsIncluded` false, `Run`/`Rehydrate` throw
  `InvalidOperationException`. `TASK_NAME` moved off `ModelDiagnosticsReport`.
- **Validation messages** are the same strings as before, now built from `Name` by
  `OspreyTask.RequiresError`; the one text change is ModelDiagnostics, which used the
  full-pipeline "No input files specified" wording and now names the task like the other
  five (test updated). Two `→` arrows in the FirstPassFDR messages became ASCII `->`.
- **`RescoreWorker.cs` deleted.** Zero callers; a one-line alias for the method whose
  signature changed, with a summary describing the retired `--input-scores` shape. The
  docs that cited its summary as evidence for DIVERGENCES U6 (six blob columns null/zero)
  now say the citation was that comment and point at `ParquetScoreCache.cs`; the claim is
  left `[UNVERIFIED]` as it was.
- **`Program.ValidateArgs`**: the doubled `<summary>` and the helper-before-caller ordering
  (`DuplicateInputStemError` sat between the doc comment and its method) fixed in passing.
- **Tests**: `TaskConfigs.ForTask(name)` / `ForTask(allTasks, name)` (new shared helper)
  replaces the three hand-copied `ForTask(HpcTask)` / `TaskConfig(HpcTask)` helpers and goes
  through `SelectTask`. New: `TestSelectedTaskFacts` (the seven-column truth table plus an
  `UnlistedTask` pinning the fail-closed defaults), `TestPipelineForSelection`, and
  `TestResolveTask` now asserts every task resolves to the SAME instance and appears in
  `ARG_TASK.Values` exactly once. 594/594 pass; inspection zero warnings.
- **Docs**: 15's name table and orchestration section rewritten (task list, `ApplySelection`
  table, the facts truth table); one-line fixes in 00, 07, 11, DIVERGENCES.

Gates: `Build-Osprey.ps1 -Configuration Debug -RunTests -RunInspection` green.
`regression.ps1 -Dataset Stellar` running; `-Dataset StellarLibDecoy` next (Stellar carries no
`--model-diagnostics`, so modes 7/11 - the `--task ModelDiagnostics` legs - only run there).
`--task SpectraCache` has no regression leg; smoke-tested by hand (see below).

Follow-ups noted, not done here:
- The report-owning `ModelDiagnosticsTask` (fifth canonical stage) - the class doc says so.
- `CanHydratePerRun` still checks `StopAfterStage5 || ExpectReconciledInput` after the
  `HydratesPerRun` lookup; with the flags derived from the same task it is redundant, kept
  because it is not enum-keyed and removing it is a separate judgment.

### 2026-09-20 - /code-review max triage (15 findings at the cap; each verified)

Fixed in `41e44df8da`:
- **`PipelineFor` failed OPEN** for a listed task that is neither standalone nor canonical:
  it returned the canonical four with no flag set, so the whole analysis ran and the task
  was never called - the opposite of the fail-closed contract the commit asserts. Added
  `OspreyTask.RunsCanonicalPipeline` (default `InCanonicalPipeline`; `ModelDiagnosticsTask`
  overrides true) and `PipelineFor` now throws `InvalidOperationException` for a task that
  answers neither. Pinned in `TestPipelineForSelection` and the facts table.
- **`SelectTask` was additive**: the four derived flags (`NoJoin`, `StopAfterStage5`,
  `ExpectReconciledInput`, `DiagnosticsOnly`) are now cleared before `ApplySelection`, so a
  re-selection cannot keep a stale one; `ModelDiagnostics` is left alone because
  `--model-diagnostics` sets it on its own. Doc claim scoped to what it enforces.
- **`PerFileRescoring`'s echo named the blib it never writes** (`--output` only locates the
  analysis-wide sidecars) - pre-existing, but the rewritten comment repeated the false
  claim. `DescribeOutput` override added; comment fixed.
- **DIVERGENCES U6 was stale, not unverified**: PR #4188 (`40340dada3`) populated the six
  blob columns (`ParquetScoreCache.BuildFdrEntryColumns`); my first commit had re-pointed
  the citation at the deleted `RescoreWorker.cs` summary and kept the claim. Marked RESOLVED
  in DIVERGENCES (entry, table row, counts) and doc 11.
- Stale pointers: docs/15 `-i/--input` row said "forbidden by the joins" (every task takes
  it), `Program.cs:NNN` citations for checks that moved into `ValidateSelection` /
  `ApplySelection` (docs 10, 15, DIVERGENCES), `AnalysisPipeline.CanonicalPipeline` in
  `regression.ps1`'s task-name comment, "the rescore worker" in `AnalysisPipeline.cs`,
  "task-name-to-enum-to-class map" in doc 00, `ResidentPoolGuardTest` doc. "Nothing ...
  names tasks" softened to "switches on a task name" (the `--task` help prose names the
  two selectors; noted where a new selector needs a sentence). The new doc-15 table used
  U+2013 dashes; now ASCII.
- Test guards: every canonical-pipeline task must have an `IsIncluded` row; the flags table
  is counted against `CreateAll()`; cross-fact implications (a stage runs the canonical
  pipeline; one pipeline shape; a per-file worker runs no join; reconciled rows exist only
  after Stage 4); and a reflection assert that every concrete `OspreyTask` in
  `Osprey.Tasks` is in `CreateAll()` exactly once - a class committed without its line no
  longer passes as "unknown task".

Dropped, with the reason:
- `FinalizeAndCheck` keys on bare `NoJoin` and hard-codes "--task PerFileScoring" in a
  message that the rescore worker's rehydrate arm can log: pre-existing, log-only, and the
  branch doubles as the Stage 1-4 stop boundary whose return the rehydrate arm consumes -
  changing its condition is a behavior change outside this PR.
- `ARG_TASK` constructs six tasks in `OspreyCommandArgs`'s type initializer (a future
  throwing constructor would crash the no-args usage path): the TODO's stated design;
  constructors verified trivial; `CreateAll()` staying cheap is documented on the registry.
- `DiagnosticsOnly` is a settable flag rather than derived: the TODO's stated design ("a
  plain settable flag like its three siblings"); its only writer is `ApplySelection`, and
  the `SelectTask` reset keeps it consistent with the selection.
- `ReferenceEquals` identity vs comparing `Name`: the TODO's stated design ("works because
  the pipeline list and the selection share instances"); `PipelineFor` enforces it at the
  one production seam and `TaskConfigs.ForTask(allTasks, name)` exists for tests that build
  a pipeline. Comparing names would drop the shared-list invariant and the `allTasks`
  parameter; noted as an alternative, not taken.
- Two parsers for `--task` (Main's pre-scan and the tokenizer): pre-existing structure;
  folding resolution into `ParseArgs` is a separate refactor.
- `IsIncluded` defaults true (fails open) and the five overrides use different identity
  models: pre-existing; unifying membership under one base predicate is a separate design
  change, and the three row-length asserts force a decision for any task added.
- Base `ValidateSelection` duplicates the no-task branch's three checks with different
  wording: two three-line checks whose distinct wordings are each pinned by a test; a shared
  which-is-missing helper is more machinery than the duplication.

### 2026-09-20 - design rework after Brendan's review (`f852b35316`)

Brendan's review of the first two commits: `--no-join` was dropped with `--task` (a Skyline
one-fan-out/one-join concept that does not fit a two-fan-out/two-join pipeline that could
grow a third), yet `NoJoin` survived as an internal flag; `StartsAfterPerFileScoring`,
`RunsStage7Join` and `InCanonicalPipeline` were overkill or misplaced - the last implied the
All list is kept in pipeline order and the pipeline is filtered out of it, which needs a
comment to explain; two explicit lists (all, the pipeline - eventually several, selectable
by `--pipeline`) are cleaner, and a task's membership in a pipeline is the pipeline's
configuration, not the task's self-description. He asked for the PR to reach a fully reduced
design before squash-merge.

What changed:
- **`OspreyTasks` is an instance with two explicit lists**: `All` (help order) and `Pipeline`
  (execution order), built together in `Create()` so instances are shared, plus the pipeline
  each selector-only task runs (`SpectraCache` -> `[SpectraCache]`; `ModelDiagnostics` ->
  the canonical stages) declared in the set, not on the tasks. The constructor validates the
  lists (every task once, every stage listed, every selector given a pipeline).
  `PipelineFor(selected)` reads them; `FindByName` is an instance method. `InCanonicalPipeline`,
  `RunsCanonicalPipeline`, `RunsStandalone` are gone.
- **One membership rule**, `OspreyConfig.Includes(stage)`: every stage with no selection; the
  selected stage alone when the selection is a stage of the pipeline it runs; every stage when
  it is not (the diagnostics render). The four `IsIncluded` overrides, the base virtual and
  `FirstPassFdrTask.IsIncludedFor` are gone; `AnalysisPipeline.Run(config, pipeline)` asks the
  config. The config carries `Pipeline` (set by `SelectTask(task, pipeline)`) so the
  config-keyed predicates can answer position questions.
- **`NoJoin` deleted.** Its two non-membership readers (`FinalizeAndCheck`'s Stage 1-4 stop,
  the diagnostics-product guard) ask `SelectedTask?.IsPerFileWorker`. The stop boundary's log
  line now names the selected task and says "loaded" for the rescore worker's rehydrate arm
  instead of claiming PerFileScoring scored something (the reviewer's finding 3, dropped
  earlier as behavior-adjacent; the return path is unchanged and documented benign on Demand).
- **Position facts derive from the pipeline**: `ScoringTaskShared.SelectedStageIsAfter<T>`
  and `Includes<T>` answer `StartsAfterPerFileScoring` (after `PerFileScoringTask`),
  `ReadsReconciledScores` (after `PerFileRescoreTask`) and `RunsStage7Join`
  (`Includes<SecondPassFdrTask>`). `ISelectableTask` is `Name`, `IsPerFileWorker`,
  `HydratesPerRun`, `ApplySelection`, `ValidateSelection`, `DescribeOutput`.
- `StopAfterStage5` / `ExpectReconciledInput` stay as behavior flags (~10 readers each in the
  first-pass task's arms and the reconciled-footer gate in Osprey.IO, below the task types);
  `CanHydratePerRun`'s redundant test on them is gone.
- Tests: `TaskConfigs.ForTask` selects with the pipeline; `StraightThrough()` and
  `ContextFor(config)` added; `ResidentPoolGuardTest`'s flag-only configs
  (`{ ExpectReconciledInput = true }` standing for `--task SecondPassFDR`) became real
  selections - with membership on the selection, a flag without one no longer stands for a
  task. `PipelineMembershipTest` pins `Includes`, the two lists, `PipelineFor`, the facts
  table, and the reflection guard.

Gates on `f852b35316`: Debug build + 594/594 + zero inspection warnings; Stellar and
StellarLibDecoy regressions (below).

Gate results on `f852b35316`: Stellar PASS 17/17 legs
(`ai/.tmp/sessions/20260920-one-task-list/regression-stellar3.log`); StellarLibDecoy PASS 27/27
legs including modes 7/11 (`regression-libdecoy2.log`). PR body refreshed to describe the final
design.

### 2026-09-20 - user-facing vocabulary (`git log -1` on the branch)

Brendan: "Stage 1-4" reached a log line; stage numbers are never user-facing, the `--task`
names are (they are in the CLI and the help). Fixed the four strings this PR touched (the two
`FirstPassFdrTask.ValidateSelection` errors, moved from `Program.cs`, and the two
`FinalizeAndCheck` stop lines). 38 pre-existing sites in 10 files remain and belong to the
backlog sweep `ai/todos/backlog/brendanx67/TODO-osprey_log_readability.md`, whose vocabulary
table already rules "never a stage number; the `--task` names are fine" - not a new follow-up.
Debug gate green; no script or test keys on the changed text (checked), so the regression was
not re-run for this message-only commit.

### 2026-09-20 - second /code-review max, high triage bar (`65574be266`)

Brendan asked for one more review of the two-list rework with a high bar: serious issues
that went unnoticed in the refactor, no minor cleanups. 15 findings at the cap; verified.

Fixed:
- `AnalysisPipeline.Run(config, pipeline)` took the pipeline separately from `config.Pipeline`
  with nothing checking they were the same instances; a mismatch is a silent no-op "Analysis
  complete" (every stage excluded) or fail-open (a namesake selection). Now refused with an
  `ArgumentException`; pinned in `TestTaskSetAndPipelineForSelection`.
- `OspreyTasks`' constructor did not check that a selector's declared pipeline uses the set's
  own instances, nor that a stage has no selector entry - the by-reference contract was
  unenforced where the lists are declared. Both checked now.
- `--task FirstPassFDR` still echoed `Output: out.blib` (the misreading the PR fixed for
  PerFileRescoring) and my `Program.cs` comment claimed only SecondPassFDR writes the blib;
  `FirstPassFdrTask.DescribeOutput` added, comment corrected.
- Strings I added broke the recorded vocabulary (`feedback_osprey_user_facing_terminology`):
  "sidecar" -> "intermediate files", `{1:N0}`, "entries" -> "precursor candidates",
  "boundary files" -> "intermediate files".
- Docs I rewrote were wrong: doc 00 named `OspreyTasks.CanonicalPipeline` (no such member);
  doc 15's truth table still annotated rows with the flags its own prose says are not
  membership flags and spelled the column `PerFileRescore`; doc 15 claimed doc 20 names the
  selector-only tasks (it listed four `--task` values; now six, with a sentence each); two
  `regression.ps1` comments still cited the deleted `NoJoin`; two `--` em-dashes in a comment.

Dropped:
- `ARG_TASK`'s type-init now runs a validating constructor, so a malformed list crashes the
  no-args usage path with a `TypeInitializationException`: developer-time only, the inner
  message still prints, every other path reports it with a stack; design per the TODO.
- Deriving `StopAfterStage5` / `ExpectReconciledInput` / `DiagnosticsOnly` from interface
  facts; moving `RunModelDiagnosticsTask` behind an `ISelectableTask` hook; splitting a
  lighter selectable base so `ModelDiagnosticsTask` need not throw from `Run`: design
  alternatives, and the report-owning task is the named follow-up.
- `ResolveTask` spelling its own invalid-value sentence rather than `ValueInvalidMessage`, the
  pre-scan duplicating the tokenizer's missing-value message, `FinalizeAndCheck` re-deriving
  the stop from the selection and its early `return false` suppressing `[TIMING]`: all
  pre-existing shapes.
