# TODO-20260623_ospreysharp_console_output.md

## Branch Information
- **Branch**: `Skyline/work/20260623_ospreysharp_console_output`
- **Base**: `master`
- **Created**: 2026-06-23
- **Status**: In Progress
- **GitHub Issue**: (none)
- **PR**: [#4326](https://github.com/ProteoWizard/pwiz/pull/4326)

# OspreySharp console/log output

**Priority**: Medium-High -- foundational CLI usability/observability work that
unblocks `--timestamp`/`--memstamp` perf analysis and percent-progress for long runs.
**Type**: OspreySharp feature / infrastructure
**Scope**: One PR (multi-commit) on the OspreySharp CLI output path; shares
`CommandStatusWriter` via PortableUtil (Commit 1). Planned 2026-06-23.

> **Follow-on split out:** the `IProgressMonitor`/`ProgressStatus` (+ `Immutable` cluster)
> relocation into PortableUtil and the timer-progress adoption are a **separate future PR** ->
> `ai/todos/backlog/TODO-ospreysharp_progressmonitor_portableutil.md`. This TODO covers
> everything up to but NOT including that refactor.

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
- **IProgressMonitor/ProgressStatus -> PortableUtil + ConsoleProgressMonitor**: split to the
  backlog refactor TODO (see pointer above).

## Target output format (must stay byte-identical to perfviz's parser)
- `--timestamp`: `[yyyy/MM/dd HH:mm:ss]\t<message>`
- `--timestamp --memstamp`: `[yyyy/MM/dd HH:mm:ss]\t<managedMB>\t<privateMB>\t<message>`
  where managedMB = `Round(GC.GetTotalMemory(false)/1MB)`, privateMB =
  `Round(Process.PrivateMemorySize64/1MB)`. Confirmed against
  `G:\My Drive\Claude\Import_20191009_170333-skyline.log` and `perfviz.html`
  (splits each line's text on TAB; >2 fields => memstamps present).

## Commit sequence (pwiz repo; each builds + passes gates)

### Commit 1 - Share CommandStatusWriter via PortableUtil
- [x] Moved `CommandStatusWriter` out of `CommandLine.cs` into
      `pwiz_tools/Shared/PortableUtil/SystemUtil/CommandStatusWriter.cs`
      (namespace `pwiz.Common.SystemUtil`, BCL-only). PortableUtil is SDK-style and
      globs `.cs`, so no csproj `<Compile>` entry needed.
- [x] Parameterized the error hint: the `Resources.CommandStatusWriter_WriteLine_Error_`
      branch in `IsErrorMessage` is replaced by a hint collection seeded with the
      invariant `ERROR_MESSAGE_HINT` ("Error:") plus `AddErrorMessageHint(string)`.
      DECISION/DEVIATION: made the collection `static` (set once at startup) rather
      than per-construction as the original wording implied. Rationale: preserves the
      original dual-detection at ALL writers including the mid-run log-file swap
      (`CommandLine.cs:173`) with one DRY wire-up, and localization is process-wide.
      Note: invariant hint comparison changed InvariantCulture -> CurrentCulture;
      behaviorally identical for the ASCII "Error:" prefix.
- [x] Wired project reference: added `CommonUtil -> PortableUtil` ProjectReference
      (prereq for the backlog refactor). Skyline already references PortableUtil (from OspreyCommandArgs
      work), so no new Skyline ref needed. PortableUtil stays a leaf.
- [x] **REVERTED in Commit 5 (CI breakage):** this `CommonUtil -> PortableUtil` edge broke
      the legacy bjam C++ tool builds (Core/Bumbershoot/Docker on PR #4326). The pwiz GUI
      tools (MSConvertGUI/SeeMS) + Bumbershoot consume CommonUtil via bjam `msbuild <proj>
      /restore`, which can't restore/TF-resolve an SDK-style multi-targeting project ->
      `error MSB4006 circular dependency` (Core) / `error NETSDK1004 project.assets.json not
      found` (Bumbershoot), both naming `PortableUtil.csproj::TargetFramework=net472`. Master
      is green; the failure is type-agnostic (fires just from the SDK project entering the
      bjam ProjectReference graph). CommonUtil uses NO PortableUtil type yet, so the edge was
      load-bearing for nothing -> removed it (kept a guard comment in CommonUtil.csproj).
      The forward-looking half (re-adding the edge once Immutable/ProgressStatus move forces it,
      and the bjam build-infra fix that must precede it) is captured in the backlog refactor TODO
      `ai/todos/backlog/TODO-ospreysharp_progressmonitor_portableutil.md` (Phase 1).
- [x] Updated Skyline: removed class from `CommandLine.cs`; installed the localized
      hint once in `Program.cs:Main` via `CommandStatusWriter.AddErrorMessageHint(
      Resources.CommandStatusWriter_WriteLine_Error_)`. All 10 construction sites and
      the `ERROR_MESSAGE_HINT`/resource references already import `pwiz.Common.SystemUtil`.
- [x] **Gate: full `Skyline.sln` build** PASSED. Committed as `56b10ae613`.
- [x] **REGRESSION + FIX (post-PR #4326):** Commit 1's error-hint parameterization
      broke localized command-line error detection. I captured the localized "Error:"
      prefix into a static collection installed once in `Program.Main`; tests don't run
      Main and switch UI language IN-PROCESS, so in zh/ja/fr/tr the localized prefix
      (`错误：` in zh) went undetected -> `IsErrorReported` false -> "exit status 2 but no
      error reported" across ALL `Console*` tests in non-en passes. Root cause: a
      localizable string assigned to a static freezes the first locale. FIX:
      `CommandStatusWriter.IsErrorMessage` is now a `static Func<string,bool>` (default =
      invariant "Error:"); `CommandLine`'s static ctor assigns a lambda re-resolving
      `Resources.CommandStatusWriter_WriteLine_Error_` per line (installed there because
      every CLI path -- prod and tests via `CommandLineRunner.RunCommand` -- builds a
      `CommandLine` before writing errors). Removed the `Program.Main` install.
      See [[feedback_no_localizable_string_in_static]].
- [x] **GATE STRENGTHENED:** the missed gate was running only the Skyline *build*, not
      localized CLI tests. Standing gate for any output-path change now includes the
      command-line tests in ALL languages: `Run-Tests.ps1 -UseTestList -Language all`
      (the failing set is in `SkylineTester test list.txt`).
- [x] **FIX VERIFIED:** `Run-Tests.ps1 -UseTestList -Language all` -> all 38 tests PASS in
      en/ja/zh/fr/tr (216.6s), including the previously-failing zh pass.
- [x] **CROSS-SOLUTION CONSUMERS (AutoQC / SkylineBatch / SharedBatch):** these separate
      .NET 4.7.2 solutions reference CommonUtil, so the Commit-1 `CommonUtil -> PortableUtil`
      ref makes PortableUtil a new transitive dep there (Skyline.sln can't catch it).
      SkylineBatch.sln builds + tests PASS (PortableUtil resolves transitively). AutoQC.sln
      needed `PortableUtil.csproj` added to the .sln (committed `9a8dd369e7`); its
      AssemblyInfo.cs is Boost-Build-generated (gitignored) and was just absent in the
      checkout (pre-existing, not this PR). AutoQC builds + all AutoQC tests PASS after that.
      Also removed an inspection-flagged unused `using pwiz.Skyline` in CommandLinePeakBoundaryTest.
- [x] **Pinned PortableUtil identity** (`6f68eb372b`): root cause of the GUID divergence was
      that PortableUtil.csproj (SDK-style) had no `<ProjectGuid>`, so each solution mints its
      own. A prior Claude session happened to use {97ECF0B4...} everywhere it wired the project
      (Skyline.sln, OspreySharp.sln, 7 csproj refs); VS-2026 minted a different one (5D588BE8)
      when AutoQC.sln was added by hand. Added `<ProjectGuid>{97ECF0B4...}</ProjectGuid>` to
      PortableUtil.csproj and aligned AutoQC.sln to it, so solutions READ the identity instead
      of minting. PENDING dev verification that VS-2026 honors the pin (doesn't re-mint).
- [ ] **CodeQL** (PR #4326): 2 pre-existing "PanoramaUserEmail -> external write" alerts on
      the moved CommandStatusWriter.cs (flow lives in Skyline; re-flagged only because the
      sink file moved). NOT introduced by this PR -> left for the security review (not resolved).

### Commit 2 - Route OspreySharp exe-layer output through one writer
- [x] `OspreySharp/Program.cs`: added `private static CommandStatusWriter _out =
      new CommandStatusWriter(Console.Error)` as a field (inline init -> never null even
      if Log* is called before Main; Commit 3 reassigns it for --log-file). Rewrote
      `LogInfo/LogWarning/LogError` to `_out.WriteLine("[INFO] {0}", message)` etc.
      (the inherited TextWriter format overload routes through the overridden
      WriteLine(string), so stamps/error-detection apply). Startup banner (the
      `LogInfo("OspreySharp v...")` block) is covered transitively.
- [x] Routed the no-args usage error through `_out` (PrintUsage(null, _out)); `_out`
      wraps Console.Error so it stays on stderr.
- [x] Kept `--version`/`--help` on **stdout** (untouched in OspreyCommandArgs.cs).
      Verified no other direct `Console.*` writes remain in the exe-layer Program.cs.
- Note: PipelineContext/AnalysisPipeline already funnel through `Program.Log*`, so
  the task layer is covered transitively.
- [x] **Gate: OspreySharp pre-commit (build + 432 tests + inspection)** PASSED.
      Committed as `bb9ac04a99`.

### Commit 3 - Add --timestamp / --memstamp / --log-file
- [x] Declared `ARG_TIMESTAMP`, `ARG_MEMSTAMP` (value-less), `ARG_LOG_FILE` (string)
      in a new `GROUP_LOGGING` ("Logging") in `OspreyCommandArgs.cs` (mirrors the
      `--parallel-files` pattern), added to UsageBlocks + help dictionary. Surfaced
      `IsTimeStamped`, `IsMemStamped`, `LogFilePath` on `OspreyConfig` (runtime-only,
      not in any identity hash).
- [x] In `Main` after ValidateArgs: set `_out.IsTimeStamped/IsMemStamped`; if
      `LogFilePath` set, swap `_out` to `CommandStatusWriter(new StreamWriter(path))`
      preserving flags (mirrors Skyline `CommandLine.cs:168-188`). Added a pre-try
      `loggingToFile` flag + `finally` that flushes/disposes ONLY the log-file writer
      (never the shared Console.Error). Placed after validation so a bad command line
      creates no file.
- [x] Extended tests: parse assertions for the three args (defaults off/null) in the
      parse test; added "Logging" group title + `--timestamp` to `TestHelpRendering`.
      The existing `TestEveryArgIsGroupedAndDescribed` drift-killer auto-covers them.
- [x] **Gate: OspreySharp pre-commit** PASSED. Committed as `6076205eb8`.
      regression.ps1 deferred to after Commit 4 (batch output-path commits 2-4).

### Commit 4 - Reroute the below-exe Console bypass sites
**REDESIGN (2026-06-23, per developer):** the TODO's original plan (route the
lower-layer sites through `OspreyDiagnosticsLog.LogAction`) is WRONG on two counts:
(1) it is infeasible -- `OspreySharp.Diagnostics` already references `OspreySharp.FDR`,
so FDR routing through it is a circular project reference; and (2) it conflates
mainline output with the Diagnostics module, which must stay `-d`-only debug code.
Principle (developer): ALL OspreySharp output flows through the one `CommandStatusWriter`
so timestamp/memstamp prefixing is uniform; we are architecting toward long operations
posting `ProgressStatus` to an `IProgressMonitor` (timer-driven percent + exception
rendering), though full progress plumbing is NOT a goal of this sprint.
- [x] Added `OspreySharp.Core/OspreyOutput.cs`: a process-wide `static TextWriter Out`
      (BCL type, so Core needs no PortableUtil ref), default `Console.Error`. `Program`
      points it at `_out` after the stamp/log-file setup, so below-exe layers (FDR, IO)
      emit through the same `CommandStatusWriter`. FDR/IO already reference Core -> no cycle.
- [x] Rerouted `PercolatorFdr.cs` (all 10 `[TIMING]/[COUNT]` + Stage-5 dump lines) and
      `MzmlReader.cs` (2 unsorted-spectrum lines): `Console.Error` -> `OspreyOutput.Out`.
      Both files already `using pwiz.OspreySharp.Core`.
- [x] Reverted the interim `OspreyDiagnosticsLog` default-LogAction change (orthogonal;
      Diagnostics stays `-d`-only, its `LogAction` is still wired to `LogInfo` by Program).
- [x] **Gate: OspreySharp pre-commit** PASSED (build + 432 tests + 0-warning, after a
      doc-comment cref fix). Committed as `5c9a932f17`.
- [x] **Gate: `regression.ps1 -Dataset Stellar` PASSED** (covers output-path commits 2-4):
      mode1 vs golden PASS, mode3 HPC-chain==straight PASS, mode2 resume==straight PASS,
      all at 1e-9 (identical 52,514,816-byte blibs). Output routing did not change results.
- ORIGINAL plan (superseded): Route them through the existing static
      sink `OspreyDiagnosticsLog.LogAction` (already set to `Program.LogInfo` in
      `Program.cs:54`, so they land in `_out`).
- [ ] `OspreyDiagnosticsLog.cs:40`: change the default `LogAction` from
      `Console.WriteLine` (stdout) to `Console.Error.WriteLine` so the unset-sink
      fallback matches the historical stderr channel.
- Result: ALL output flows through `_out` and honors the stamps/log-file.

### Commit 5 - Output-review cleanup (--perf-stats, rescore labels, Percolator cycles)
**Emerged from reviewing the first real `--timestamp --memstamp` Stellar log in
perfviz.html (2026-06-23/24).** Three problems the chart/log surfaced, all output-only
(no data-path change; regression.ps1 still byte-identical at 1e-9):
- [x] **Leftover dev diagnostics removed.** Dropped the `[DIAG]` peptide-trigger block
      (`AAAAAAAAAAAAAAAGAGAGAK`) + `_logInfo` plumbing from `PeakDataExtractor`
      (ctor now `(IScoringDiagnostics)`), the valueless `[POOL]` lines from
      `ScoringPipeline`, the forwarded `logInfo` param from `CoelutionScorer`/
      `ScoringPipeline`; dropped the `[INFO]` prefix on `Program.LogInfo`; `[task]`
      -> `[TASK] ` in `AnalysisPipeline` (3 sites).
- [x] **`--perf-stats` flag gates the machine-parseable lines.** New `OspreyOutput.PerfStats`
      + `IsStatLine` + `StatFilteringTextWriter` (a sink wrapper). Default OFF -> the
      `[COUNT]/[TIMING]/[STAGE-WALL]` lines are suppressed (each has a plain human twin
      that stays); `--perf-stats` ON restores all tagged lines for the perf tools.
      `ARG_PERF_STATS` in `GROUP_LOGGING`; `OspreyConfig.PerfStats`. Verified: default
      Stellar = 0 tagged lines, `--perf-stats` = 125.
- [x] **Rescore scoring passes self-label.** `RunCoelutionScoring` gained an optional
      `passLabel` (default `"Scored"`); the two PerFileRescore phases were emitting the
      identical `Scored N/125` and read as "scored each file twice". Now: `Re-scored`
      (Phase 1 existing entries), `Gap-fill scored` (Phase 2 CWT), `Gap-fill
      forced-integration scored` (Phase 2 forced). First-pass scoring keeps `Scored`.
- [x] **Percolator per-cycle progress** (`PercolatorFdr.TrainFold`): the SVM fold
      training was 57s (first-pass) / 31s (second-pass) of total silence -> two big
      Time-Diff spikes in perfviz. Added a per-cycle line mirroring Skyline's mProphet
      LDA cycle logging: `Percolator fold f/3: iteration i of 10 (N targets at 1% FDR)`.
      Folds train in parallel (OspreyParallel.For) so writes are serialized under
      `_trainProgressLock` and each line names its fold. Plain human line (always on,
      NOT --perf-stats-gated). NO ProgressStatus: the loop converges early
      (consecutiveNoImprove) before MaxIterations. Result: whole-run max inter-line gap
      57s -> 8s.
- [x] **ai perf tools pass `--perf-stats`** so they still receive the tagged lines:
      `Test-PerfGate.ps1` ($cliArgs) and `Measure-Pipeline.ps1` (C#-only branch).
- [ ] **Gate: OspreySharp pre-commit** PASSED (build + 432 tests + 0-warning).
- [ ] **Gate: `regression.ps1 -Dataset Stellar`** (output-only; expect byte-identical).
- [ ] Commit pwiz (SHA: pending); commit ai scripts separately.

**Future direction surfaced here (developer, 2026-06-24):** a `--verbose` mode will
become the gate for implementer-grade metrics (means, SDs, per-step internals), while
the DEFAULT log keeps user-relevant signals -- e.g. "N targets at 1% FDR" (the
Percolator cycle metric) STAYS visible by default; verbose-only metrics are for
algorithm implementers assessing per-step success. This is a DIFFERENT axis from
`--perf-stats` (machine-parseable tags); the two coexist. (`--verbose` shipped in Commit 5b;
the timer-progress adoption is in the backlog refactor TODO.)
Follow-up: the new 8s max gap is the **RT-calibration LDA pass** ("Calibration pass 1
LDA passing count") -- the genuine mProphet-LDA analog; give it the same per-cycle
treatment (candidate for the backlog refactor or a fast-follow).

### Commit 5b - --verbose disposition + Percolator training progress as percent
**Emerged from reviewing the percent/cycle output in perfviz + Notepad++ (2026-06-24).**
- [x] **`--verbose` introduced** as the third output disposition (keep / remove /
      hide-unless-verbose). `ARG_VERBOSE` in `GROUP_LOGGING`; `OspreyConfig.Verbose`;
      `OspreyOutput.Verbose` + `WriteVerbose(...)` helper; wired in `Program` next to
      `PerfStats`. Orthogonal to `--perf-stats` (human detail level vs machine tags).
- [x] **Percolator per-iteration progress reports a percent**, not a raw/summed count.
      The 3 CV folds train in parallel; `TrainProgressReporter` buffers each iteration's
      per-fold reports under a lock and flushes only once all folds report, so output is
      always ordered. Default: one line `iteration N of M (P.P% of training targets at
      1% FDR)` -- passing/total summed over folds, a ratio that cancels the 300k subsample
      scale AND the CV fold-overlap (~2x) double-count, giving a scale-free convergence
      signal. `--verbose`: each fold in fold order with its own `X of Y targets, Z%`
      (the ~2/3 split is explicit, not assumed).
- [x] **CV training-set size in a section sub-header** (emitted from `RunPercolator`,
      where the actual subsample is known): `3-fold cross-validation on <subN> training
      entries (<subTargets> targets)`. First-pass ~300k (MaxTrainSize cap); second-pass
      ~131k (best-per-precursor dedup left fewer) -- honest per-pass denominator.
- [x] **Gate: OspreySharp pre-commit** PASSED (build + 432 tests + 0-warning).
- [ ] **Gate: `regression.ps1 -Dataset Stellar`** (output-only; expect byte-identical).
- [ ] Commit pwiz (SHA: pending).
- **Observation the metric enabled (kept as a future note, NOT changed here):** first-pass
      is still climbing at iteration 10 (hits the MaxIterations=10 cap, not converged);
      second-pass self-stops at iteration 8 (converged). Whether raising MaxIterations
      helps first-pass is an ALGORITHM change (alters scores -> regression golden + Rust
      cross-impl parity), so it is out of scope for this output PR; evaluate via a throwaway
      experiment, decide separately. The visibility itself is the win.

### IProgressMonitor / ProgressStatus -> PortableUtil + timer-progress adoption -- SPLIT OUT
Moved to its own future PR: `ai/todos/backlog/TODO-ospreysharp_progressmonitor_portableutil.md`
(build-infra prerequisite, the Immutable/ProgressStatus cluster move, and the
ConsoleProgressMonitor + percent-progress adoption, with the ProgressStatus-vs-simple-output
classification). This TODO ends at the console-output work above.

### pwiz-ai task (separate from the pwiz PR)
- [ ] Add `ai/scripts/OspreySharp/perfviz.html` (from `G:\My Drive\Claude\perfviz.html`,
      attribution preserved) + a short README note: run with `--timestamp --memstamp`,
      capture stderr or `--log-file run.log`, paste into perfviz to chart inter-line
      gaps + memory.

## Reused existing assets (do not re-implement)
- `CommandStatusWriter` (Skyline `CommandLine.cs:4843-4980`) -- the class shared in Commit 1.
- `OspreyDiagnosticsLog.LogAction` -- existing static sink for lower-layer logging.
- `OspreyCommandArgs` declarative arg framework + drift-killer test (the recent
  `--parallel-files` work, completed PR #4324, is the template).
- `perfviz.html` -- the analysis tool (parses `[date]\t{managed}\t{total}\t{msg}`).

## Verification
- Per commit: `pwsh -File ./ai/scripts/OspreySharp/Build-OspreySharp.ps1 -Configuration Debug -RunTests -RunInspection` (build + tests + 0-warning).
- Correctness (output stamping must NOT change results):
  `pwsh -File ./pwiz_tools/OspreySharp/regression.ps1 -Dataset Stellar`. It compares
  the protein-FDR text golden + blib content at 1e-9 and does NOT diff console/stderr,
  so log changes are invisible to it. Run after the output-path commits (2,3,4) and the
  output-tuning commits (5, 5b).
- Skyline unaffected: full `Skyline.sln` build after Commit 1 (the one commit here that
  touches Skyline / relocates `CommandStatusWriter`).
- perfviz end-to-end: run a small Stellar command with `--timestamp --memstamp` (or
  `--log-file run.log`), load into `ai/scripts/OspreySharp/perfviz.html`, confirm it
  parses and charts time-gaps + managed/total memory.

## Risks / watch-outs
- **stdout vs stderr contract**: keep `--version`/`--help` on stdout; route everything
  else through `_out` (stderr by default). Don't let stamps leak onto stdout.
- **Localization**: OspreySharp log strings remain English literals (current
  convention); only the shared `CommandStatusWriter` error-hint is parameterized so
  Skyline can keep its localized hint.

## Refs
- Skyline pattern: `pwiz_tools/Skyline/CommandLine.cs` (CommandStatusWriter 4843-4980),
  `CommandArgs.cs:268-269` (--timestamp/--memstamp).
- Shared: `pwiz_tools/Shared/PortableUtil/` (target net472;net8.0, zero pwiz refs) -- now holds
  `SystemUtil/CommandStatusWriter.cs`.
- OspreySharp: `OspreySharp/Program.cs` (Log* 409-422, Main entry), `OspreySharp/OspreyCommandArgs.cs`,
  `OspreySharp.FDR/PercolatorFdr.cs`, `OspreySharp.IO/MzmlReader.cs`,
  `OspreySharp.Diagnostics/OspreyDiagnosticsLog.cs`, `OspreySharp.Tasks/{AnalysisPipeline,PipelineContext,PerFileScoringTask}.cs`.
- Tool + sample: `G:\My Drive\Claude\perfviz.html`, `G:\My Drive\Claude\Import_20191009_170333-skyline.log`.
