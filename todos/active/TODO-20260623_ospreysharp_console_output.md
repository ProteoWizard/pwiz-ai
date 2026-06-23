# TODO: OspreySharp console/log output + IProgressMonitor adoption

**Status**: Backlog (not started)
**Priority**: Medium-High -- foundational CLI usability/observability work that
unblocks `--timestamp`/`--memstamp` perf analysis and percent-progress for long runs.
**Type**: OspreySharp feature / infrastructure / shared-code refactor
**Scope**: One large PR (multi-commit), touches Skyline + a cross-project type
relocation into PortableUtil. Planned 2026-06-23.

## Context (why)
OspreySharp's user-visible output is ad hoc: `Program.LogInfo/LogWarning/LogError`
write straight to `Console.Error` with `[INFO]/[WARN]/[ERROR]` prefixes, ~13 sites
in lower layers (`PercolatorFdr`, `MzmlReader`, version printer, diagnostics-log
default) write to `Console.*` directly, there is no per-line timestamp/memory
stamp, no user log file, and no notion of percent-progress (only discrete
`[TIMING]/[STAGE-WALL]/[COUNT]` lines and per-task start/done). To assess CLI
performance we care about two things Yuval Boss's `perfviz.html` chart already
visualizes from a stamped log: (1) time gaps between output lines (a long gap
makes a user wonder if it hung), and (2) running memory per line.

Skyline solved this years ago: `CommandLine.cs` routes ALL output through a single
`CommandStatusWriter` (a `TextWriter`) and never touches `Console` directly;
`--timestamp`/`--memstamp` toggle per-line stamps; `CommandProgressMonitor` renders
throttled percent-progress on a timer. This sprint brings OspreySharp onto that
pattern and shares the infrastructure via PortableUtil.

## Decisions (locked 2026-06-23)
- **One large PR**, sequenced commits below (not split).
- **Share `CommandStatusWriter` via PortableUtil**: MOVE Skyline's class down to
  `pwiz.Common.SystemUtil` in PortableUtil and have BOTH Skyline and OspreySharp
  use it. Parameterize its one localized dependency (the `Error:` hint).
- **Commit `perfviz.html` into the repo** (`ai/scripts/OspreySharp/perfviz.html`,
  Yuval Boss attribution preserved) as the documented way to visualize a
  `--timestamp --memstamp` log. Source copy: `G:\My Drive\Claude\perfviz.html`.
- **Move `IProgressMonitor`/`ProgressStatus` down to PortableUtil** -- which drags
  `Immutable` + the immutable-collection cluster with them (see Commit 5). Keep all
  namespaces (`pwiz.Common.SystemUtil`, `pwiz.Common.Collections`) so every existing
  Skyline `using` keeps compiling.
- **Extract a fresh portable `ConsoleProgressMonitor`** (the reusable render core of
  `CommandProgressMonitor`); leave Skyline's `CommandProgressMonitor` as its
  Skyline-coupled self (`ILongWaitBroker`/`MultiProgressStatus`/`SrmDocument`).

## Target output format (must stay byte-identical to perfviz's parser)
- `--timestamp`: `[yyyy/MM/dd HH:mm:ss]\t<message>`
- `--timestamp --memstamp`: `[yyyy/MM/dd HH:mm:ss]\t<managedMB>\t<privateMB>\t<message>`
  where managedMB = `Round(GC.GetTotalMemory(false)/1MB)`, privateMB =
  `Round(Process.PrivateMemorySize64/1MB)`. Confirmed against
  `G:\My Drive\Claude\Import_20191009_170333-skyline.log` and `perfviz.html`
  (splits each line's text on TAB; >2 fields => memstamps present).

## Commit sequence (pwiz repo; each builds + passes gates)

### Commit 1 - Share CommandStatusWriter via PortableUtil
- [ ] Move `CommandStatusWriter` out of `pwiz_tools/Skyline/CommandLine.cs:4843-4980`
      into `pwiz_tools/Shared/PortableUtil/SystemUtil/CommandStatusWriter.cs`
      (namespace `pwiz.Common.SystemUtil`, BCL-only).
- [ ] Parameterize the error hint: replace the `Resources.CommandStatusWriter_WriteLine_Error_`
      branch in `IsErrorMessage` with a settable hint collection (default `{ "Error:" }`);
      Skyline sets the localized variant where it constructs the writer.
- [ ] Wire project references: add `PortableUtil` ProjectReference to `CommonUtil`
      (and `Skyline` directly if its non-SDK csproj does not flow the reference
      transitively -- verify). PortableUtil stays a leaf (never references back).
- [ ] Update Skyline (`CommandLine.cs`, `Program.cs`) to use the moved class.
- [ ] **Gate: full `Skyline.sln` build** (this commit touches Skyline).

### Commit 2 - Route OspreySharp exe-layer output through one writer
- [ ] `OspreySharp/Program.cs`: add `private static CommandStatusWriter _out` =
      `new CommandStatusWriter(Console.Error)` in `Main` before any logging; rewrite
      `LogInfo/LogWarning/LogError` (`Program.cs:409-422`) to `_out.WriteLine(...)`
      keeping the `[INFO]/[WARN]/[ERROR]` prefixes; route the no-args usage error
      (`Program.cs:60`) and startup banner through `_out`.
- [ ] Keep `--version`/`--help` on **stdout** (`OspreyCommandArgs.cs:350,552`) -- do
      NOT let `_out` push these to stderr (HPC scripts capture stdout for version).
- Note: PipelineContext/AnalysisPipeline already funnel through `Program.Log*`, so
  the task layer is covered transitively.

### Commit 3 - Add --timestamp / --memstamp / --log-file
- [ ] Declare `ARG_TIMESTAMP`, `ARG_MEMSTAMP` (value-less), `ARG_LOG_FILE` (string)
      in `OspreyCommandArgs.cs` in a Diagnostics/General group (mirror the recent
      `--parallel-files` pattern); surface on `OspreyConfig` (`IsTimeStamped`,
      `IsMemStamped`, `LogFilePath`).
- [ ] In `Main` after parse: set `_out.IsTimeStamped/IsMemStamped`; if `LogFilePath`
      set, swap `_out` to a `CommandStatusWriter(new StreamWriter(path))` preserving
      the stamp flags (mirror Skyline `CommandLine.cs:168-188`), try/finally flush+dispose.
- [ ] Extend the drift-killer test in `OspreySharp.Test/OspreyCommandArgsTests.cs`.

### Commit 4 - Reroute the below-exe Console bypass sites
- [ ] Sites that cannot see `Program._out` (they live in `OspreySharp.FDR` /
      `OspreySharp.IO`): `PercolatorFdr.cs` (~lines 253,308,319,387,452,455,2209,2258,
      2292,2345) and `MzmlReader.cs:701,705`. Route them through the existing static
      sink `OspreyDiagnosticsLog.LogAction` (already set to `Program.LogInfo` in
      `Program.cs:54`, so they land in `_out`).
- [ ] `OspreyDiagnosticsLog.cs:40`: change the default `LogAction` from
      `Console.WriteLine` (stdout) to `Console.Error.WriteLine` so the unset-sink
      fallback matches the historical stderr channel.
- Result: ALL output flows through `_out` and honors the stamps/log-file.

### Commit 5 - Move IProgressMonitor + ProgressStatus + Immutable cluster to PortableUtil
- [ ] Move (delete from CommonUtil, add under PortableUtil, namespaces UNCHANGED):
      `SystemUtil/IProgressMonitor.cs`, `SystemUtil/ProgressStatus.cs`,
      `SystemUtil/Immutable.cs`, `Collections/ImmutableList.cs`,
      `Collections/ImmutableListFactory.cs`, `Collections/ImmutableDictionary.cs`,
      `Collections/ImmutableCollection.cs`.
- [ ] Strip the single `using JetBrains.Annotations;` + `[InstantHandle]` from the
      moved `Immutable.cs` (keeps PortableUtil JetBrains-free; attribute is inspection-only).
- [ ] `CommonUtil.csproj`: remove those 7 `<Compile>` entries (PortableUtil reference
      was added in Commit 1). Grep ALL `.csproj` for stray `<Compile>` includes of
      those filenames so nothing double-compiles.
- [ ] **Gate: full `Skyline.sln` build** -- this is the riskiest commit (relocates a
      foundational base class's home assembly across all of Skyline).

### Commit 6 - Portable ConsoleProgressMonitor + percent-progress adoption
- [ ] Add `pwiz_tools/Shared/PortableUtil/SystemUtil/ConsoleProgressMonitor.cs`
      (`pwiz.Common.SystemUtil`): fresh port of the render core of
      `CommandProgressMonitor` (CommandLine.cs:5151-5376) -- ctor
      `(TextWriter, IProgressStatus, secondsBetweenStatusUpdates = 2.0)`, throttled
      `UpdateProgress` so fast ops show ~0%..100% and slow ops show intermediate %,
      indeterminate (-1) handling, `IsCanceled => false`. No `ILongWaitBroker` /
      `MultiProgressStatus` / `SrmDocument` / Skyline localization.
- [ ] Thread an `IProgressMonitor` from `Main` into `AnalysisPipeline.Run` and onto
      `PipelineContext` (alongside the existing log delegates); construct
      `new ConsoleProgressMonitor(_out, new ProgressStatus())`.
- [ ] Push the `PortableUtil` ProjectReference down to the OspreySharp DLLs that
      report progress (Core/Tasks/FDR) as needed.
- [ ] Report percent in the three dominant loops using the existing
      `ProgressStatus.ThreadsafeIncrementPercent` / `UpdatePercentCompleteProgress`
      helpers: per-file scoring fan-out (`PerFileScoringTask`), Percolator folds
      (`PercolatorFdr.cs:452` loop), scoring windows (`ScoringPipeline`). Keep the
      existing `[TIMING]/[STAGE-WALL]/[COUNT]` lines (they coexist and feed perfviz).

### pwiz-ai task (separate from the pwiz PR)
- [ ] Add `ai/scripts/OspreySharp/perfviz.html` (from `G:\My Drive\Claude\perfviz.html`,
      attribution preserved) + a short README note: run with `--timestamp --memstamp`,
      capture stderr or `--log-file run.log`, paste into perfviz to chart inter-line
      gaps + memory.

## Reused existing assets (do not re-implement)
- `CommandStatusWriter` (Skyline `CommandLine.cs:4843-4980`) -- the class being shared.
- `CommandProgressMonitor` (Skyline `CommandLine.cs:5151-5376`) -- render-core reference.
- `IProgressMonitor`/`SilentProgressMonitor` (`CommonUtil/SystemUtil/IProgressMonitor.cs`).
- `ProgressStatus.ThreadsafeIncrementPercent` / `UpdatePercentCompleteProgress`
  (`CommonUtil/SystemUtil/ProgressStatus.cs`) -- parallel-safe percent helpers.
- `OspreyDiagnosticsLog.LogAction` -- existing static sink for lower-layer logging.
- `OspreyCommandArgs` declarative arg framework + drift-killer test (the recent
  `--parallel-files` work, completed PR #4324, is the template).
- `perfviz.html` -- the analysis tool (parses `[date]\t{managed}\t{total}\t{msg}`).

## Verification
- Per commit: `pwsh -File ./ai/scripts/OspreySharp/Build-OspreySharp.ps1 -Configuration Debug -RunTests -RunInspection` (build + tests + 0-warning).
- Correctness (output stamping must NOT change results):
  `pwsh -File ./pwiz_tools/OspreySharp/regression.ps1 -Dataset Stellar`. It compares
  the protein-FDR text golden + blib content at 1e-9 and does NOT diff console/stderr,
  so log changes are invisible to it. Run after the output-path commits (2,3,4) and
  the progress commit (6).
- Skyline unaffected: full `Skyline.sln` build after Commit 1 and Commit 5 (the two
  commits that touch Skyline / relocate shared types).
- perfviz end-to-end: run a small Stellar command with `--timestamp --memstamp` (or
  `--log-file run.log`), load into `ai/scripts/OspreySharp/perfviz.html`, confirm it
  parses and charts time-gaps + managed/total memory.

## Risks / watch-outs
- **Riskiest: Commit 5** (moving `Immutable` + immutable-collections down). Wide
  Skyline usage; relocating the home assembly can surface duplicate-type compiles or
  a non-SDK transitive-reference gap. Mitigation: move the whole cluster in one
  commit, grep every `.csproj` for stray `<Compile>` of those files, gate on a full
  `Skyline.sln` build, limit the JetBrains-strip to the one `[InstantHandle]`.
- **Project-reference flow**: Skyline's non-SDK csprojs may not flow PortableUtil
  transitively through CommonUtil -- be ready to add a direct `Skyline -> PortableUtil`
  reference (and for any OspreySharp DLL that newly uses the moved types).
- **stdout vs stderr contract**: keep `--version`/`--help` on stdout; route everything
  else through `_out` (stderr by default). Don't let stamps leak onto stdout.
- **Localization**: OspreySharp log strings remain English literals (current
  convention); only the shared `CommandStatusWriter` error-hint is parameterized so
  Skyline can keep its localized hint.

## Refs
- Skyline pattern: `pwiz_tools/Skyline/CommandLine.cs` (CommandStatusWriter 4843-4980,
  CommandProgressMonitor 5151-5376), `CommandArgs.cs:268-269` (--timestamp/--memstamp).
- Shared types: `pwiz_tools/Shared/CommonUtil/SystemUtil/{IProgressMonitor,ProgressStatus,Immutable}.cs`,
  `pwiz_tools/Shared/CommonUtil/Collections/Immutable*.cs`,
  `pwiz_tools/Shared/PortableUtil/` (target net472;net8.0, zero pwiz refs).
- OspreySharp: `OspreySharp/Program.cs` (Log* 409-422, Main entry), `OspreySharp/OspreyCommandArgs.cs`,
  `OspreySharp.FDR/PercolatorFdr.cs`, `OspreySharp.IO/MzmlReader.cs`,
  `OspreySharp.Diagnostics/OspreyDiagnosticsLog.cs`, `OspreySharp.Tasks/{AnalysisPipeline,PipelineContext,PerFileScoringTask}.cs`.
- Tool + sample: `G:\My Drive\Claude\perfviz.html`, `G:\My Drive\Claude\Import_20191009_170333-skyline.log`.
