# TODO-ospreysharp_progressmonitor_portableutil.md

## Status
- **Type**: OspreySharp infrastructure / shared-code refactor (separate PR)
- **Origin**: split out of `ai/todos/active/TODO-20260623_ospreysharp_console_output.md`
  (the console-output PR #4326). Planned 2026-06-24; start as its own PR AFTER #4326 lands.
- **Branch**: TBD (`Skyline/work/YYYYMMDD_ospreysharp_progressmonitor`)

# Move IProgressMonitor/ProgressStatus into PortableUtil + adopt timer progress in OspreySharp

## Context (why)
OspreySharp CLI output now flows through one `CommandStatusWriter` with `--timestamp/--memstamp/
--log-file`, `--perf-stats`, `--verbose`, and Percolator percent progress (shipped in PR #4326). The
next step -- Skyline-CLI-style **timer-driven `%` progress** for long determinate operations -- needs
`IProgressMonitor`/`ProgressStatus` available to OspreySharp's lower DLLs. Those types live in
`CommonUtil` (net472, non-SDK). The agreed direction is to relocate them into SDK-style `PortableUtil`
(net472;net8.0) so Skyline and OspreySharp share them, then adopt timer-progress in OspreySharp.

## Decisions (carried from the console-output TODO)
- **Move `IProgressMonitor`/`ProgressStatus` down to PortableUtil** -- drags `Immutable` + the
  immutable-collection cluster. Namespaces UNCHANGED (`pwiz.Common.SystemUtil`,
  `pwiz.Common.Collections`) so every existing Skyline/OspreySharp `using` keeps compiling.
- **Extract a fresh portable `ConsoleProgressMonitor`** (reusable render core of Skyline's
  `CommandProgressMonitor`); leave Skyline's `CommandProgressMonitor` as its Skyline-coupled self
  (`ILongWaitBroker`/`MultiProgressStatus`/`SrmDocument`).
- `CommandStatusWriter` already shipped to PortableUtil in PR #4326 (do not re-do).

## Output disposition model
- **Keep (always):** results (`N targets at 1% FDR`, precursors, protein groups), task start/done,
  input/library summary, CV training-size header.
- **Remove:** dead dev diagnostics (done in #4326).
- **`--verbose` only:** implementer detail (per-fold Percolator breakdown, means/SDs/sub-step internals).
- **`--perf-stats` only:** machine-tagged lines (orthogonal axis; done in #4326).

## ProgressStatus (timer-%) vs simple progressive text -- classification
Rule: **timer-%** when a block iterates a **known total** of interchangeable units (per-step number is
noise -> show ~% on a 2s timer, drop the counter line). **Simple progressive text** when each step
carries **insight** (convergence) or has **no clean denominator** -> one discrete line per step.

| Block | File | Disposition |
|---|---|---|
| Per-file scoring fan-out | `OspreySharp.Tasks/PerFileScoringTask.cs` | **ProgressStatus** (total = input files) |
| Isolation-window scoring (`Scored N/125`) | `OspreySharp.Scoring/ScoringPipeline.cs` (`Parallel.For`) | **ProgressStatus** (total = windows; `ThreadsafeIncrementPercent`) |
| Rescore window loops (`Re-scored`/`Gap-fill scored`) | `OspreySharp.Tasks/PerFileRescoreTask.cs` | **ProgressStatus** |
| Spectrum/library load | IO layer | **ProgressStatus** if a clean total exists; else keep |
| Percolator fold training (per-iteration %) | `OspreySharp.FDR/PercolatorFdr.cs` | **Simple progressive** -- keep as-is (shipped in #4326) |
| RT/MS2 calibration LDA passes | `OspreySharp.Tasks/Calibrator.cs` | **Simple progressive** (iterate-to-converge); consider a per-iteration line to fill its ~8s gap |
| Protein FDR / blib / merge | various | **Keep** (fast, headline) |

Confirmed (developer, 2026-06-24): keep insight lines, `%`-ify the pure counters; the window counters
move under `--verbose`.

## Phase 1 - Build-infra prerequisite (validate in isolation; Matt's domain)
The `CommonUtil -> PortableUtil` edge pulls the SDK multi-target PortableUtil into the legacy bjam tool
builds (`MSConvertGUI`, `SeeMS`, `greazy`), which `msbuild <tool>.sln /restore` with a shared `obj/` ->
`NETSDK1004` (no `project.assets.json`) and `MSB4006` (multi-target P2P loop). This broke
Core/Bumbershoot/Docker on PR #4326 and was reverted there. `Skyline.sln` works only because it carries
explicit config-mapping rows for PortableUtil. Fix, landed + **TeamCity-validated BEFORE any type move**
(the edge is inert until Phase 2):
- Re-add the `CommonUtil -> PortableUtil` `ProjectReference` with
  `<SetTargetFramework>TargetFramework=net472</SetTargetFramework>` --
  `pwiz_tools/Shared/CommonUtil/CommonUtil.csproj` (there's a guard comment there now).
- Add PortableUtil (`{97ECF0B4-0AAA-4593-ADE0-9E8740973AC2}`) to the tool solutions with x86->AnyCPU /
  x64->x64 rows copied from `Skyline.sln:182-189`: `pwiz_tools/MSConvertGUI/MSConvertGUI.sln`,
  `pwiz_tools/SeeMS/seems.sln` (+ `greazy.sln` if it transitively pulls CommonUtil).
- Fallback if still red: add a `msbuild PortableUtil.csproj /t:restore` pre-step in the tool Jamfiles
  (`pwiz_tools/MSConvertGUI/Jamfile.jam` ~line 73, SeeMS Jamfile).
- Own commit; coordinate with Matt (build-infra owner; was out when this surfaced). TeamCity
  (Core/Bumbershoot/Docker) is the authority -- NOT locally reproducible.

## Phase 2 - Move the Immutable/ProgressStatus cluster to PortableUtil
Move the **transitive closure** (namespaces unchanged -> no consumer edits), from
`pwiz_tools/Shared/CommonUtil/{SystemUtil,Collections}` to `pwiz_tools/Shared/PortableUtil/{SystemUtil,Collections}`:
- Target 7: `SystemUtil/IProgressMonitor.cs`, `SystemUtil/ProgressStatus.cs`, `SystemUtil/Immutable.cs`,
  `Collections/ImmutableList.cs`, `Collections/ImmutableListFactory.cs`, `Collections/ImmutableDictionary.cs`,
  `Collections/ImmutableCollection.cs`.
- Required to avoid a CommonUtil<->PortableUtil cycle (deps of the above): `Collections/CollectionUtil.cs`,
  `Collections/IntegerList.cs`, `Collections/Factor.cs`.
- **VERIFY FIRST:** trace the full dependency closure of `CollectionUtil`/`IntegerList`/`Factor` before
  moving -- they may drag further CommonUtil types. Move "whatever closes the graph," not a fixed 10.
- Strip `using JetBrains.Annotations;` + `[InstantHandle]` from `Immutable.cs` (PortableUtil stays
  JetBrains-free; attribute is inspection-only).
- Remove the matching `<Compile Include=...>` lines from `CommonUtil.csproj` (old-style); grep ALL csprojs
  for stray link-includes of these filenames. `Skyline/Model/MultiProgressStatus.cs` stays (subclass).
- All target files verified net8.0-safe (no net472-only APIs). No namespace collision
  (`CommandStatusWriter` already lives in `pwiz.Common.SystemUtil` under PortableUtil).
- Gate: full `Skyline.sln` build + `OspreySharp.sln` gate + TeamCity (incl. the Phase-1 tool builds).

## Phase 3 - Portable ConsoleProgressMonitor + OspreySharp adoption
- **New** `pwiz_tools/Shared/PortableUtil/SystemUtil/ConsoleProgressMonitor.cs`: BCL-only render core of
  Skyline's `CommandProgressMonitor` (`pwiz_tools/Skyline/CommandLine.cs:5025-5250`). Ctor
  `(TextWriter, IProgressStatus, double secondsBetweenStatusUpdates = 2.0)`; throttle on the interval;
  render `"{0}%"` / `"{0}% - {1}"`; `IsCanceled => false`, `HasUI => false`. Drop `ILongWaitBroker`,
  `MultiProgressStatus`, `SrmDocument`, localized resources, BiblioSpec logic.
- Thread an `IProgressMonitor` `Program -> AnalysisPipeline.Run -> PipelineContext` (new ctor param,
  default `SilentProgressMonitor`), alongside the existing log delegates; construct
  `new ConsoleProgressMonitor(OspreyOutput.Out, new ProgressStatus())`. Files:
  `OspreySharp/Program.cs`, `OspreySharp.Tasks/AnalysisPipeline.cs`, `OspreySharp.Tasks/PipelineContext.cs`.
- Add `PortableUtil` `ProjectReference` to `OspreySharp.Tasks`, `OspreySharp.Scoring`, `OspreySharp.FDR`
  (Core stays pure-BCL; the exe already references PortableUtil).
- Adopt timer-% in the **ProgressStatus** blocks (table) via `ProgressStatus.UpdatePercentCompleteProgress`
  / `ThreadsafeIncrementPercent` (parallel-safe for `Parallel.For`/`OspreyParallel.For`); move the pure
  counter lines (`Scored N/125`, rescore window loops, per-file fan-out) under `--verbose`. Leave the
  simple-progressive blocks (Percolator percent, calibration LDA) unchanged.

## Reused existing assets (do not re-implement)
- `CommandProgressMonitor` (Skyline `CommandLine.cs:5025-5250`) -- render-core reference.
- `IProgressMonitor`/`SilentProgressMonitor` (`CommonUtil/SystemUtil/IProgressMonitor.cs`).
- `ProgressStatus.ThreadsafeIncrementPercent` / `UpdatePercentCompleteProgress`
  (`CommonUtil/SystemUtil/ProgressStatus.cs`) -- parallel-safe percent helpers.
- `Skyline.sln:182-189` PortableUtil config-mapping rows -- the proven x86->AnyCPU / x64->x64 pattern.

## Verification
- Per phase: `pwsh -File ./ai/scripts/OspreySharp/Build-OspreySharp.ps1 -Configuration Debug -RunTests -RunInspection`.
- Output-unchanged-where-required: `pwsh -File ./pwiz_tools/OspreySharp/regression.ps1 -Dataset Stellar`
  (1e-9 golden + resume + HPC chain; progress changes are output-only -> expect byte-identical).
- Skyline unaffected: full `Skyline.sln` build after Phase 1 and Phase 2.
- TeamCity authoritative for Phase 1 (Core/Bumbershoot/Docker) -- not locally reproducible.
- End-to-end: `pwsh -File ./ai/.tmp/Run-OspreyStellar.ps1` (default) and `-Verbose`; review the two
  stable logs `C:\proj\ai\.tmp\osprey-default\run.log` and `...\osprey-verbose\run.log`; load into
  `ai/scripts/OspreySharp/perfviz.html` and confirm timer-% on determinate blocks while
  Percolator/calibration keep their per-iteration lines.

## Risks / watch-outs
- **Phase 1 not locally verifiable** -- relies on TeamCity; have the Jamfile pre-restore fallback ready;
  Matt owns this area.
- **Phase 2 closure** -- `CollectionUtil`/`IntegerList`/`Factor` may pull more; trace before moving.
- **Wide blast radius** -- `ImmutableList`/`ProgressStatus` used in 150+ Skyline/Shared files; the move
  is namespace-preserving (home-assembly relocation), gated by a full `Skyline.sln` build.
