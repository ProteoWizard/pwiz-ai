# Sprint: one shared toolkit under Osprey and CarafeSharp, then one pipeline

## Branch Information
- **Branch**: `Skyline/work/20261014_osprey_carafe_shared_toolkit` (PR 1). Later PRs get their
  own `Skyline/work/YYYYMMDD_...` branches off `master`, listed under their PR section as they start.
- **PR 2**: [#4846](https://github.com/ProteoWizard/pwiz/pull/4846) (part D plus the review fixes;
  Perf/Regression green on its first head, master with #4845 merged in and re-gated locally;
  merged 2026-10-15 as 1575f27201).
- **PR 2 branch**: `Skyline/work/20261014_one_command_line_tokenizer` (off master 2026-10-14, in
  `C:\proj\pwiz`; PR 1's branch is pushed and only waits on TeamCity). After #4845 merges, this
  branch needs `git merge origin/master`: PR 1 also edits `CarafeCommandLine.cs` (the
  `-log_file` / `-timestamp` / `-memstamp` options and the hand-written usage) and
  `CarafeSharp.Core.csproj` (the same CommonUtil reference), so the merge re-adds those three
  options as declarations.
- **PR 3 branch**: `Skyline/work/20261015_osprey_carafe_contracts` (off master `1575f27201`
  2026-10-15, in `C:\proj\pwiz`). Part F first (the shared training-record assembly), then part G.
- **Base**: `master`
- **Created**: 2026-10-14 (vision note 2026-10-13; restructured into a staged sprint 2026-10-14)
- **Status**: In Progress - Phase 1 merged 2026-10-15 (PR 1 #4845 as a0107497d1, PR 2 #4846 as 1575f27201; the workflow page #4847 as a5a3fc3dbb). PR 3 started 2026-10-15 on its branch: part F coded (see the PR 3 section), gating. PR 1 (parts A, B, C, E) was coded and gated 2026-10-14 in four commits
  (07894725c3, bb0ccd12c8, 517fb096ef, 141b3bc642); next the pre-PR `/code-review`, the PR, and
  the TeamCity Perf/Regression gate. Mike's agreement to the CommonUtil dependency is assumed
  pending his return from vacation. PR 2 (part D) coded and gated 2026-10-14 on its own branch
  (see the PR 2 branch line and the part D section); next its `/code-review`, PR and, after
  #4845 merges, `git merge origin/master`.
- **GitHub Issue**: (none yet; PR #4717 closed #4707)
- **Module**: `osprey`
- **PR**: [#4845](https://github.com/ProteoWizard/pwiz/pull/4845) (PR 1: parts A, B, C, E plus the review fixes; TeamCity Perf/Regression green; merged 2026-10-15 as a0107497d1)

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20261015_osprey_carafe_pr3_contracts.md` before starting work. Phase 1 is on
master; PR 3 (the contracts) starts on its own branch off master.
- **Checkout**: `C:\proj\pwiz`
- **Depends on**: CarafeSharp in `pwiz_tools/CarafeSharp` (PR #4717, merged 2026-10-14)
- **Related**: `TODO-carafe_osprey_library_contract.md` (the library Carafe writes and Osprey
  loads, with one shared validator) and `TODO-task_file_contract_from_declarations.md` (task
  file contracts printed from declarations and staged by the harnesses). Both land inside this
  sprint's Phase 2 rather than beside it.

## Goal

Osprey and CarafeSharp work as one tool from the user's side: given a FASTA and the runs to
search (and optionally separate runs to train on), Osprey builds, searches, fine-tunes and
re-searches in one command, using CarafeSharp's classes in-process rather than running Carafe.

Before that can be built, both tools must stand on one toolkit. Brendan (2026-10-13): too many
ways of doing one thing give developers the chance to pick the one where a bug was not fixed.
So the sprint has two phases. **Phase 1** replaces every duplicated utility with the one in
`pwiz_tools/Shared/CommonUtil` and gives CarafeSharp's stages the same task shape Osprey's
have, with no behavior change in either tool. **Phase 2** is the integration itself.

## Why (Brendan, 2026-10-13)

Osprey has to win over users of fully integrated tools (DIA-NN, Spectronaut), who supply a FASTA and
their runs and get results. Today the lab's workflow is four steps across two tools (Mike, 2026-10-12:
"1) generate the library as the default model, 2) search the middle file, 3) fine tune the library and
4) search all 3 files. This is basically the lab workflow we use for everything."), driven by
`ai/scripts/CarafeSharp/Run-CarafeSharpWorkflow.ps1`. The lab commonly trains on part of the search
data, not the whole dataset (Brendan's concern: overtraining when the training runs are also searched).

The training records are not an interface between two tools: Osprey writes a report whose content the
training defines. The dependency runs from Osprey to the training side, not the reverse.

## Survey (2026-10-14, master at PR #4717's merge)

CommonUtil already holds most of the shared pieces. Osprey's exe uses two of them; the copies
left in Osprey exist because `Osprey.Core` does not reference CommonUtil (only the exe does
directly; IO and Tasks see it transitively through ProteowizardWrapper). CarafeSharp references
nothing in `Shared/` but the Parquet targets.

| Piece | CommonUtil | Osprey | CarafeSharp |
|---|---|---|---|
| `Argument` / `ArgUsage`, ascii + HTML help | `CommandLine/` | uses it; own tokenizer (`OspreyCommandArgs.TokenizeAndDispatch`) | own 819-line `CarafeCommandLine`, hand-written `Usage` block, option table as two strings |
| `CommandStatusWriter` (timestamps, memstamps, log file, error detection) | `SystemUtil/` | uses it; `OspreyOutput` seam for the layers below the exe | plain `TextWriter`; no stamps, no `--log-file` |
| `CommonExceptionUtil.IsProgrammingDefect` | `SystemUtil/` | uses it (`Program.DescribeFailure`) | `Program.cs` prints `ERROR: <message>` for every exception; a defect loses its stack |
| `IProgressMonitor` / `ProgressStatus` / `ProgressStream` | `SystemUtil/` | own `ProgressReporter` (253 lines), `MultiProgressReporter` (366), `ProgressStream` (99) | none; `TextWriter log` / `Action<string> log` threaded through 20 signatures |
| Atomic file writer | none | `Osprey.Core/FileSaver.cs` (183 lines, 25 call sites) | `PartialFile` (4 sites) plus a hand-rolled `.tmp` + move in `CarafeModelFile.cs:145` |
| User-facing text in resources | n/a | every project has a resx | zero resx; 185 `throw` sites with literal text |
| Median | | `Osprey.Core/MedianMath` | `CarafeSharp.Core/Statistics.Median` |
| Library blib writer | | `Osprey.IO/LibraryBlibWriter` (+ `BlibWriter`, 1114 lines) | `CarafeSharp.IO/BlibLibraryWriter` (610 lines) |
| Library entry types | | `Osprey.Core/LibraryEntry`, `LibraryFragment` | `CarafeSharp.Core/LibrarySpectrum`, `LibraryFragment` |

Facts the plan turns on:
- **Three FileSavers in pwiz_tools, five writers in all.** Osprey's is cross-platform
  (`Path.GetRandomFileName` + `CreateNew`), overwrites, and honors `OSPREY_KEEP_FAILED_WRITES`.
  SharedBatch's (`Skyline/Executables/SharedBatch/SharedBatch/FileSaver.cs`, 83 lines) is a Win32
  `GetTempFileName` P/Invoke, refuses overwrite and swallows commit failures to `Trace`; its
  callers are SkylineBatch's `DownloadDlg`, `SkylineBatchTest/TestUtils` and three DevTools. All
  are `net10.0-windows`, so they can reference CommonUtil. Skyline's own in `Util/UtilIO.cs`
  (stream manager, `CanSave` dialogs, undisposed-instance tracking) stays where it is. Osprey's
  header comment already says: move to CommonUtil once Core has Shared dependencies.
- **`ProgressReporter` is a deliberate simplification, and it has worked.** Its own comment calls it
  a stopgap modeled on Skyline's `CommandProgressMonitor`, kept to learn whether the full
  `IProgressMonitor` machinery is worth sharing. `CommandProgressMonitor` cannot move as-is: it
  lives in `Skyline/CommandLine.cs` with `SrmDocument`, `ILongWaitBroker` and
  `Program.ImportProgressPipe` wired in. `ProgressReporter` writes to the static
  `OspreyOutput.Out`, which `MultiProgressReporter` redirects per file via `AsyncLocal`, and the
  regression gate and `ai/scripts/perfviz.py` read its exact line cadence (heartbeat 15 s, gap
  threshold 30 s).
- **Three tokenizers, one declaration framework.** CommonUtil's grammar is Skyline's strict
  `--name=value`. Osprey adds `--name value`, short aliases (`-i`), variadic `-i a b c`, a
  positional-file fallback and optional-count arguments. Carafe's is single-dash `-name value` /
  `-name=value`, flags that reject `=value`, first value wins on repeats, unknown option is an
  error, stray non-option tokens ignored, every Carafe 2.2.0 option recognized even where unused
  ("so CarafeSharp accepts exactly what Carafe's GUI passes"). Names shared below the exe live
  in `Osprey.Core/OspreyArgNames`; CarafeSharp duplicates `TRAINING_EXPORT_SUFFIX` in
  `CarafeCommandLine` because Proteome cannot see IO.
- **Two task shapes.** `OspreyTask` declares `Name`, `Inputs`, `Outputs`, `ValidityKey`, an
  in-file `ArtifactStamp`, `Run`/`Rehydrate`, `Publishes`; `AnalysisPipeline` skips a task whose
  outputs carry a current stamp. CarafeSharp's stages (`EntrapmentFastaBuilder`,
  `PairingManifestReconciler`, `LibraryGenerator`, `ModelTrainer` over `FineTuneRun`) are a
  settings object plus a `TextWriter` plus `Run()`: no declared files, no stamp, no skip. Stage
  selection is the workflow script's `-Stages 1a,1b,2,3,4-5,6`.
- **Mass tables stay.** `AlphabaseMasses`, `CompomicsMasses`, `ResidueMasses`, `ChemicalFormula`,
  `ModificationTable`, `JavaRandom`, `JavaNumberFormat` reproduce alphabase, compomics and Java
  to the bit for Carafe parity (SHA-256-identical stage 1 on 14 configurations). They are not
  duplicates of `CommonUtil/Chemistry` and must not move onto it.
- **`CarafeSharp.Core` references nothing by design** (its `Directory.Build.props`: no pwiz-sharp
  reference, runs anywhere net10.0 and libtorch do). CommonUtil is plain net10.0 and adds
  Newtonsoft.Json, IdentityModel, ProtectedData and JetBrains.Annotations to the output. Linux
  is unaffected; never call the DPAPI methods there.
- **Tests.** CommonUtil's tests live in `pwiz_tools/Skyline/CommonTest` (PathEx, PerfUtil,
  PrecisionNumber, ...). Osprey has `FileSaverTest`, `ProgressReporterTest`, `ArgTokens`,
  `CommandLineErrorTest`; CarafeSharp has `CommandLineErrorTest`, `LibraryCommandLineTest`,
  `BlibLibraryWriterTest` (exercises `PartialFile`).
- **PR #4717 deferred two follow-ups**: atomic model-folder writes (closed by PR 1, part A) and training
  memory at 40-run scale (out of this sprint).

## Decisions (Brendan, 2026-10-14)

1. **CarafeSharp depends on CommonUtil.** Mike has been asked and is on vacation; proceed on the
   assumption he accepts. If he does not want dependencies on pwiz utilities, the question becomes
   whether CarafeSharp belongs in the pwiz repository at all, which is revisited then, not now.
2. **Progress: Osprey's simplification is the shared one.** Skyline's `IProgressMonitor` /
   `ProgressStatus` / `CommandProgressMonitor` is too complicated for general use; Osprey's
   `ProgressReporter` has worked well where no GUI tracks in-memory processing. Move it as-is
   (with its sink made injectable) rather than rebuild on `IProgressMonitor`.
3. **One tokenizer class with grammar options, in one PR.** The end state is a single
   configurable tokenizer in CommonUtil that Skyline, Osprey and CarafeSharp all declare
   against. Standardize as far as possible, but every existing grammar stays available as a
   configuration: Skyline's strict `--name=value` for every tool that drives SkylineCmd today,
   and Carafe's single-dash grammar because CarafeSharp is a cross-impl parity option for
   Noble-Lab/Carafe (the maccoss/Carafe fork) and must accept Carafe's exact command lines.
   Do it in PR 2 rather than a two-tokenizer interim. (Brendan, 2026-10-14: "one class with
   tokenizing options is the route we want to take.")
4. **The task contract is extracted to Shared.** CarafeSharp.exe keeps no Osprey dependency;
   Osprey.exe links CarafeSharp's DLLs directly and runs its tasks in-process, never the
   CarafeSharp exe as a child process.
5. **Resx extraction for CarafeSharp is deferred.** Osprey got its resx only recently after months
   of development; CarafeSharp's 185 literal sites are a later PR of their own.

## PR plan (compressed 2026-10-14)

Four PRs in all. Brendan (2026-10-14): the PR process itself adds cost; CarafeSharp is early and
Osprey unreleased, so move quickly with multiple commits and TeamCity iterations inside a PR
rather than a PR per topic. The lettered sections below are the checklists; they are grouped by
what the change touches, not by topic:

| PR | Holds | Touches |
|---|---|---|
| **PR 1** | A, B, C, E: FileSaver, output and errors, progress, the task contract | Osprey, CarafeSharp, SharedBatch, CommonUtil |
| **PR 2** | D: one tokenizer | CommonUtil, **Skyline `CommandArgs`**, Osprey, CarafeSharp |
| **PR 3** | F, G: training records, pairing manifest, library contract, one blib writer | Osprey, CarafeSharp |
| **PR 4** | H, I, J: one command, HPC tasks, packaging | Osprey, CarafeSharp, installers |

PR 2 stays separate only because it is the one change that reaches SkylineCmd, the released
product; a reviewer sees it without the Osprey and CarafeSharp moves around it. Phase 1 may
collapse to one PR if that stops mattering. Measurement follows PR 4 with no PR of its own.

## Phase 1 - shared code and normalized architecture (no behavior change)

Every Phase 1 PR passes the same gates (section "Gates"), the first of which is byte-identical
output on both tools. Inside PR 1, commit order: A first (it adds the references the rest build
on), then B and C, then E (the task driver logs and reports progress through the shared pieces).

### PR 1, part A - one atomic file writer in CommonUtil

Done 2026-10-14, commit 07894725c3. Gates run on the final code: Osprey build + 638 tests +
zero-warning inspection; CarafeSharp build + 97 tests (8 inconclusive, no local test data) +
zero-warning inspection; `TestSimpleFileSaver` and `CodeInspection` in the Skyline tree;
SkylineBatch build + tests and the AutoQC build; `regression.ps1 -Dataset Stellar` PASSED against
the golden; `CarafeSharp/regression.ps1 -Leg Chained` PASSED.

- [x] Added `pwiz_tools/Shared/CommonUtil/SystemUtil/SimpleFileSaver.cs` from Osprey's
      (cross-platform temp allocation, overwrite on commit, temp cleaned on dispose). The two
      resource strings and their ja / zh-Hans translations moved to `MessageResources`.
      **Named `SimpleFileSaver`, not `FileSaver`**: 49 of the 58 Skyline files that use
      `pwiz.Skyline.Util.FileSaver` also import `pwiz.Common.SystemUtil`, so a shared `FileSaver`
      there would be ambiguous in every one of them (Osprey's header comment had proposed the
      name). Temp prefix is Skyline's `~SK` (was `~OS` in Osprey, `~SB` in SharedBatch).
- [x] `KeepFailedWrites` is a static property on the shared class; `Program.RunCommand` copies
      `OspreyEnvironment.KeepFailedWrites` into it beside the other process-wide seams
      (`OspreyOutput.PerfStats` / `Verbose`). CommonUtil reads no `OSPREY_*` variable.
- [x] `CommitAs(path)` on the shared class (PartialFile's). The "name (N)" fallback itself stays in
      the two CarafeSharp writers that choose the name.
- [x] `Osprey.Core.csproj` references `CommonUtil.csproj`; `Osprey.Core/FileSaver.cs` deleted;
      29 files renamed `FileSaver` -> `SimpleFileSaver` (type uses, crefs and prose) with the using
      added where the type is used.
- [x] `CarafeSharp.Core.csproj` references `CommonUtil.csproj` (no `.sln` entry needed: `dotnet`
      and the inspection resolve the ProjectReference, as Osprey's do); `PartialFile.cs` deleted;
      the four writers moved onto `SimpleFileSaver`. `EntrapmentFastaBuilder` no longer refuses a
      manifest path equal to the FASTA's temp name (temp names are random now). Tests assert "no
      `~SK*` file left in the folder" instead of "no `<name>.partial`".
- [x] `CarafeModelFile.Save` writes through `SimpleFileSaver` (the "atomic model-folder writes"
      follow-up from PR #4717). `ZipFile.Open(..., Create)` needs a non-existent file and the
      saver pre-claims a 0-byte temp, so it is `new ZipArchive(new FileStream(SafeName, Create))`.
- [x] SharedBatch: `SharedBatch/FileSaver.cs` and its three resource strings deleted; SkylineBatch
      `DownloadDlg` and `SkylineBatchTest/TestUtils` use the shared one. Behavior change for
      `DownloadDlg`: a download onto an existing file now replaces it, where the SharedBatch
      `Commit` threw on the move and swallowed the exception to `Trace` (the file silently stayed
      stale).
- [ ] **Deferred: three more copies in DevTools** (`ImageComparer/FileSaver.cs`,
      `ResourcesOrganizer/ResourcesOrganizer/FileSaver.cs`, `SortRESX/SortRESX/FileSaver.cs`), all
      forks of Skyline's with `File.Replace` + backup semantics, each in a standalone solution
      with its own `FileEx` / `Helpers` copies and (ResourcesOrganizer) a HintPath
      `System.Resources.Extensions` that CommonUtil's package reference would collide with. Not in
      PR 1; a small follow-up of its own.
- [x] `Osprey.Test/FileSaverTest.cs` -> `Skyline/CommonTest/SimpleFileSaverTest.cs` (one
      `[TestMethod]`, `AssertEx`): the atomic contract, the bare-name case, `CommitAs` including
      after a failed `Commit`, and keep-failed-writes.
- [x] Extra gate for PR 1: `SkylineBatchTest` 37 of 39 passed; the two failures
      (`TestRunFromRScripts`, `TestMultipleLogs`) run R scripts and this machine has no R
      installed, so they fail on master too. `DataDownloadTest`, the one through `DownloadDlg`,
      passed. AutoQC builds.
- [x] `Build-Skyline.ps1 -Target CommonTest` added (pwiz-ai), so a CommonUtil change can be
      tested without a solution build; `Run-Tests.ps1 -TestName TestSimpleFileSaver` finds it.

### PR 1, part B - CarafeSharp output and errors through CommonUtil

Done 2026-10-14, commit bb0ccd12c8. Gate: CarafeSharp build + 98 tests + zero-warning inspection.

- [x] `CarafeSharp/Program.cs`: both console streams are `CommandStatusWriter`s (stdout for
      progress, stderr for errors and warnings, as Carafe, so the tests' stream split holds);
      `-log_file` replaces both with one file writer, as Osprey's `--log-file` does;
      `-timestamp` / `-memstamp` stamp every line. The `TextWriter log` plumbing is unchanged.
      Parsed by `CarafeCommandLine` in every mode (part D re-declares them).
- [x] `Program.DescribeFailure` follows Osprey's: a user-actionable exception is its message plus
      a `Caused by:` line for its root cause (today's behavior, kept); a defect is
      `Fatal error: <exception>` with type and stack; `UnwrapUserException` for the parallel-loop
      `AggregateException`. CarafeSharp's settings validation reports bad input as
      `ArgumentException` and an unported Carafe option as `NotSupportedException`, so those two
      count as user errors here (part D moves them to parse time).
- [x] Exit codes as Osprey's: 0, 1 failure to start, 2 ran with errors (`ReconcileExitCode` over
      `IsErrorReported`). Every error line, usage errors included, starts with
      `CommandStatusWriter.ERROR_MESSAGE_HINT` (`Error:`), where it was `ERROR:`; no script read
      the old prefix.
- [x] `TestOutputAndErrors` in `CommandLineErrorTest`: the log file and stamps, an unopenable log
      file, the usage-error line, `DescribeFailure` on each exception class, and the exit-code
      reconciliation.

### PR 1, part C - one progress reporter in CommonUtil

Done 2026-10-14, commit 517fb096ef. Gates: Osprey build + 636 tests + zero-warning inspection;
CarafeSharp build + 98 tests + zero-warning inspection; CommonTest; regression Stellar PASSED;
chained leg PASSED.

- [x] `ProgressReporter`, `MultiProgressReporter` (with `IProgressSink`, `FileScope`) moved to
      `CommonUtil/SystemUtil` unchanged in behavior, constants and line formats. The seam is
      `CommandOutput` (`Out`, the per-flow `PushScopedOut`, internal `RealOut`); `OspreyOutput`
      keeps only `PerfStats`, `Verbose` and `WriteVerbose`, so `OspreyLog.Write` is unchanged.
      28 Osprey files renamed `OspreyOutput.Out` -> `CommandOutput.Out`.
- [x] One `ProgressStream`: CommonUtil's (`IProgressMonitor`-driven, 8 Skyline callers) gained
      a `(Stream, ProgressReporter)` constructor; Osprey's copy deleted.
- [x] `ProgressReporterTest` and the generic parts of `MultiProgressReporterTest` moved to
      `CommonTest` (CommonUtil now has `InternalsVisibleTo CommonTest` for the segment and
      buffer internals the aggregator test reads). Osprey keeps one test: its gated tags stay
      out of a buffered file block.
- [x] CarafeSharp: `Program` points `CommandOutput.Out` at its output writer for the run (and
      restores it), so percent lines land between the stages' log lines with the same stamps;
      `LibraryDatabase.DigestPeptides` reports over proteins and `LibraryGenerator.PredictChunks`
      over peptide forms at the I/O cadence. The fine-tune epoch loop already logs a line per
      epoch and lives in `CarafeSharp.Models` (model code), so it was left alone; the
      `TextWriter log` / `Action<string> log` plumbing is unchanged (it gives way with part E).
      `TestModesAndPartialOutput` asserts the digest heading in the output stream.
- [x] Docs: `docs/21-user-facing-text.md` and the development guide name `CommandOutput`; the
      guide's "lean toward `IProgressMonitor`" sentence now records decision 2.

### PR 2, part D - one command-line grammar in CommonUtil, CarafeSharp declared on Argument

Coded 2026-10-14 on `Skyline/work/20261014_one_command_line_tokenizer`. Gates run: Osprey build +
640 tests + zero-warning inspection; CarafeSharp build + 109 tests + zero-warning inspection;
CommonTest `TestCommandLineParserGrammars`; Skyline `CommandLineTest` and `CommandLineRefineTest`
(the progress log has the rest).

- [x] `CommandLineGrammar` (the configuration object: `Prefix`, `AcceptedPrefixes`,
      `ShortPrefix`, `ValueMayFollow`, `PrefixedTokenEndsValue`, `FirstValueWins`,
      `ValidatesListedValues`, `StrayTokens`; `STRICT` is Skyline's and the default) and
      `CommandLineParser<TContext>` (`Parse`, `FindValue`, `SeenArguments`, `PositionalHandler`)
      in `CommonUtil/CommandLine`. The grammar is process-wide on `ArgUsage.Grammar`, like
      `Provider` and `ArgumentValueSeparator`, because `ArgumentText` is spelled with its prefix.
      `ArgumentBase` gained `Variadic`, `OptionalValueFilter` and `TakesValue`; `NameValuePair.Bind`
      is the parser's binding (`IsMatch` stays for Skyline's `CommandLineRefineTest`); every usage
      error is a `UsageException` with `Argument`, plus the new `UnknownArgumentException`, and
      `IArgUsageProvider.UnknownArgumentMessage`. Inline `=value` is accepted by every grammar.
- [x] Skyline's `CommandArgs.ParseArgsInternal` parses with it under the default grammar;
      `ProcessArgument` is gone. The unexpected-argument text moved from the parse loop to the
      provider: resource `CommandArgs_UnknownArgumentMessage_Unexpected_argument__0_` ("Unexpected
      argument {0}", the token as typed) replaces the old one that carried "Error: " itself, so
      the output line is unchanged in English and the ja/zh lines lose a doubled prefix.
- [x] `OspreyCommandArgs` installs its grammar (`ShortPrefix "-"`, `ValueMayFollow`, listed
      values left to the handlers); the 110-line tokenizer, `FindByToken`, `TakeValue`,
      `RequireInlineValue`, `ValueMissingMessage` and `OPTIONAL_COUNT_ARGS` are gone: `-i` is
      `Variadic`, the four `--parallel-files*` are `OptionalValue` with the digits-only filter,
      `--help` / `--version` do their terminal work in their handlers, the positional-file
      fallback is the parser's `PositionalHandler`, and the `--task` missing-value text is the
      provider's one special case. Behavior changes, all benign: `--verbose=1` is "does not take
      a value" rather than "unknown argument"; `-o=x` is accepted; `--parallel-files=` is auto
      rather than an error. The Osprey tests that pinned `ArgumentException` for parser errors
      now pin the specific `UnknownArgumentException` / `ValueMissingException` (MSTest matches
      the exact type); the handlers' own errors stay `ArgumentException`.
- [x] `CarafeCommandLine`: 100 declarations in seven groups (`Value` / `Choice` / `Flag`
      factories, each recording into the same `_values` / `_flags` that `Interpret` reads, which
      is untouched), under Carafe's grammar (`Prefix "-"`, `--` accepted, `PrefixedTokenEndsValue
      false` so `-seed -5` and `-mode -` are values, `FirstValueWins`). The option table,
      `TryGetOptionName` and the hand-written `Usage` are gone. `-h` is `help` with `ShortName h`
      (`-help` / `--help` are the same declaration); its optional value picks the help form.
- [x] Help: generated like Osprey's (`BuildUsage` unicode / ascii / sections / section filter,
      `GenerateUsageHtml`, `PrintUsage`), descriptions in `CarafeCommandArgUsage.resx` (English;
      a compatibility option without an entry gets one shared line from the provider). Decision (Brendan, 2026-10-14): cross-tool consistency inside pwiz_tools wins over
      Carafe's spelling, so the help renders `--db` and is laid out as Osprey's, and BOTH helps end
      with an "OTHER FORMS ACCEPTED" paragraph (Osprey: `--name=value` and a bare input file;
      CarafeSharp: `--name=value` and Carafe's single dash, so a Carafe 2.2.0 command line runs
      unchanged). The option names stay Carafe's. A usage error prints the message and `Run
      CarafeSharp --help for the options.` instead of the whole usage. The settings' own messages
      still spell `-db` (literal text; the deferred resx extraction moves them). `CommandArgsTest` is the drift killer (every arg grouped, described, exactly
      Carafe's option set, grammar rules, help forms) and self-updates
      `Documentation/Help/en/CommandLine.html` as Osprey's does. `docs/08-command-line.md` is the
      sibling of Osprey's `20-command-line.md`.
- [x] `OspreyTrainingExportFile.SUFFIX` in `CarafeSharp.Core` (below both Proteome and IO) replaces
      the `TRAINING_EXPORT_SUFFIX` duplicate; `OspreyTrainingExport.FILE_SUFFIX` aliases it. No
      `CarafeArgNames` class: nothing below Proteome builds argument text from names (the
      literal `-rt_reference` etc. in messages are the deferred resx extraction's).
- [x] CommonTest `CommandLineParserTest`: the three grammars on a six-argument declaration set,
      with a terse provider, so each message is pinned to the call that built it.
- [x] Extra gate for PR 2: Skyline's `CommandLineTest` and `CommandLineRefineTest` (TestData),
      since the tokenizer now serves `CommandArgs`.

### PR 2 - `/code-review medium` triage (2026-10-14)

Ten findings on the branch before the PR; six fixed in the second commit, four dropped.

Fixed:
- A `Variadic` argument consumed following tokens under a grammar whose values never follow
  (`STRICT`); the loop is now guarded by `ValueMayFollow`, and `CommandLineParserTest` pins it.
- `CommandLineGrammar.LongPrefixes` rebuilt and sorted its list on every token; cached once.
- The provider's `--task` missing-value special case compared typed text to one argument's
  spelling; replaced by `ArgumentBase.MissingValueMessage`, set on `ARG_TASK` where it belongs.
- The parser snapshotted `ArgUsage.Grammar` at construction while `ArgumentText` read it live;
  the parser reads it live too, so tokens and text can never come from two grammars.
- `ValueInvalidException` spelled the argument with `ArgumentText` while the other parser errors
  used the token as typed; `Bind` now passes the typed text through.
- The variadic inline value had its own empty-value rule (`RequireValue`); it goes through
  `ReadValue` like every value.

Dropped:
- `--parallel-files=` (an empty inline value on an optional-value argument) is "no value" rather
  than the old Osprey error: that is Skyline's rule for `--name=` on an optional value
  (`IsMatch` treats it as name-only), and the one grammar follows Skyline's contract.
- `-fast=` (an empty inline value on a flag) is the flag rather than Carafe's "unrecognized
  option": the same Skyline rule (`--flag=` was always name-only there).
- A lone `-` is an unknown option under a grammar whose short prefix is `-` (Carafe's old parser
  skipped it): a dash is not a word a Carafe command line records, and as a value (`-mode -`) it
  still parses.
- CarafeSharp's new user-facing literals (`UsageHint`, the provider's messages) are not in a
  resx: decision 5 defers CarafeSharp's resx extraction to its own PR; the strings are a handful
  among its 185 literal sites and move with them.

### PR 1, part E - the task contract in Shared, CarafeSharp's stages on it

Done 2026-10-14, commit 141b3bc642. Gates: Osprey build + 636 tests + zero-warning inspection;
CarafeSharp build + 99 tests + zero-warning inspection; CommonTest; `CodeInspection`; regression
Stellar PASSED; chained leg PASSED.

- [x] `pwiz.Common.Pipeline` in CommonUtil (a namespace, not a new assembly): `PipelineTask`
      (`Name`, `Inputs` / `Outputs`, `ValidityKey` / `OutputValidityKey`, `OutputStamp`, `Run` /
      `Rehydrate`, `Publishes`), `TaskContext` (the task registry, the byproduct cache with
      `Publish` / `TryGet` / `Get` / `Demand` / `Consume` / `Release`, the one-shot materialization
      guard, `CanRehydrate`, `ExitCode`, the build `Version` and the stamp reader the host supplies)
      and `PipelineDriver` (the walk with `OnStarting` / `OnDone` / `OnSkipped` hooks).
      `ArtifactStamp` moved there with `IsCurrent(task, version, key)`; its serialized form
      (`osprey-validity/1`, the `osprey.validity` / `osprey_validity` slots) is unchanged so every
      existing artifact still reads.
- [x] Osprey: `OspreyTask : PipelineTask, ISelectableTask` seals each contract method against
      `TaskContext` and forwards to the `PipelineContext` overload every task already overrides
      (no task file changed for that); `PipelineContext : TaskContext` keeps `Config`, `RunPlan`,
      `Diagnostics`, the `LogTag` overloads, `DropAllButLibrary` and the DEBUG milestone guard
      (via the base's `OnPublishing` / `WasConsumed` hooks); `AnalysisPipeline` runs an
      `OspreyPipelineDriver` whose hooks print the `[TASK]` / `[STAGE-WALL]` lines unchanged.
      `OspreyVersion.Stamp(task, key)` and the `IsCurrent(this ArtifactStamp, task, key)`
      extension replace `ArtifactStamp.ForCurrentBuild` (23 sites), so the version has one source.
      `RehydrateFailedException` and the two unknown-type exceptions moved with the context.
- [x] CarafeSharp: `CarafeContext : TaskContext`, `CarafeTask : PipelineTask` and four tasks
      (`BuildEntrapmentFasta`, `ReconcileManifest`, `PredictLibrary`, `Train`), each wrapping the
      existing stage class, with `CarafeValidity.Key` (a hash of the settings' JSON plus the
      name, length and write time of every input file) as the validity key, computed before the
      run touches a setting. `Program` runs the mode's task through `CarafeDriver`, whose
      `OnDone` prints Carafe's completion line. `CarafeSharp.exe` references nothing in Osprey.
- [x] Stamp slots: the `.carafemodel` manifest's first property (`osprey_validity`, read by
      `CarafeModelFile.ReadStamp` without unpacking) and the blib's `OspreyMetadata` table (the
      one Osprey's blib writer uses, under the same key), read by `CarafeStamps`. The TSV
      library and the FASTA have no slot a reader of those formats would tolerate, so the
      entrapment-FASTA and reconcile tasks, and a TSV-only prediction, declare no outputs and
      always run. Goldens unaffected: the stamp is metadata the comparators do not read.
- [x] `TestResumeSkipsCurrentOutputs`: the second identical prediction is skipped and leaves
      the `.blib` untouched; a changed `-nce` predicts again with a new key; TSV-only always
      runs. `TestModesAndPartialOutput`'s locked-library case now changes a setting first, since
      the same command would be skipped (correctly) rather than fail.
- [ ] `TODO-task_file_contract_from_declarations.md` items 1 and 2 (`IsPerFile`, which Osprey's
      `IsPerFileWorker` already is, and `--help-files` printed from the declarations) stay in
      that TODO: the printer is now writable against the shared contract but was not written
      here. Item 3 (harness staging) is PR 4, part I.

### PR 1 - `/code-review medium` triage (2026-10-14)

Ten findings; eight fixed in one commit, two dropped:
- Fixed: a `blib,DIA-NN` prediction declared only the blib, so a run that committed the blib and
  failed on the TSV would be skipped (now a format that writes a TSV declares no output); the
  stamp version was the constant assembly version (now the informational version with the
  commit); `TrainTask` ran the export locator per enumeration (cached); SkylineBatch's download
  dialog stayed open when the shared `Commit` threw where SharedBatch's swallowed (Commit's
  failure is caught there, the dialog closes as before); a folder's identity included the run's
  own outputs, so `-o` at `-model_dir` could never skip (own outputs excluded); the blib stamp
  slot was defined three times (now `ArtifactStamp.BLIB_*` constants used by Osprey's and
  CarafeSharp's writers and readers); a dead null guard from the Win32 port in
  `SimpleFileSaver`; `DescribeFailure` treated every `ArgumentException` subtype as a user error
  (exact type now).
- Dropped: "route Osprey's per-file `IsCurrent` checks and `OspreyVersion.Stamp` through
  `ctx.IsCurrent` / `ctx.Stamp`" - a wider refactor of static writer helpers that have no
  context; both sources are `OspreyVersion.Current` today. Revisit when a host pins
  `TaskContext.Version` differently. "Sweep stale `~SK*` temps at writer start as `PartialFile`
  did for its fixed name" - a sweep would delete another process's live temp in a shared output
  folder, the hazard the random names exist to avoid; Osprey has the same property by design.

## Phase 2 - integration

The design below is unchanged from 2026-10-13. Phase 2 starts after PR 1 (PR 2 may run in parallel).

### Design

#### 1. One training-record assembly, owned by the training side

A small assembly (working name `CarafeSharp.Training.Records`, net10.0, no TorchSharp) holding:
- the record type (one per precursor per run) and its ion slots, flags and per-ion evidence;
- the schema: column names, footer keys, format version, slot layout, modification position rules;
- the Parquet writer and reader (both tools already use `Shared/Lib/Parquet/ParquetNet.targets`).

Osprey references it and writes records through it; CarafeSharp reads through it. Osprey's
`TrainingRecord`/`TrainingExportParquet` and CarafeSharp's `OspreyTrainingRecord`/`OspreyTrainingExport`
are deleted. Renaming or renumbering then changes both or fails the build. The pairing manifest's schema
belongs in it or beside it (see the library contract TODO, which wants a shared validator too; one shared
"Osprey-Carafe contracts" assembly may serve both).

What PR #4717 left (2026-10-13): the training export schema is defined twice, by hand, with nothing
shared. Writer: `Osprey.IO/TrainingExportParquet.cs` (columns, `FORMAT_VERSION = 2`),
`Osprey.Tasks/TrainingExportWriter.cs` (footer keys `osprey.rt_max`, `osprey.isolation_mz_min`,
`osprey.ms2_scan_window`, `osprey.collision_energies`, ...), `Osprey.Core/TrainingRecord.cs` (ion flag
bits). Reader: `CarafeSharp.IO/OspreyTrainingExport.cs` (about 40 column names, the footer keys,
`FORMAT_VERSION = "2"` as a string), `OspreyTrainingRecord.cs` (`OspreyIonFlags`, the same eight bits
value for value). Shared by convention only: the slot layout (`4*(L-1)`, `slot = p*4 + t`, Osprey
`docs/22-training-export.md`), the position-0 N-terminal modification rule
(`CarafeSharp.Training/OspreyModificationMapper.cs`), the FDRBench pairing manifest columns
(`EntrapmentFastaBuilder.cs` writes, `Osprey.IO/DecoyPairingManifest.cs` reads), and the decoy rule
(`EntrapmentSequences.cs` follows `Osprey.Scoring/DecoyGenerator.cs`). A renamed column or a format bump
fails loudly; a change of meaning without a bump does not. Until this lands, the nightly chained leg
(`regression.ps1 -Leg Chained`) is the guard; the per-commit `TestRegressionSubset` reads a frozen export.

#### 2. In memory first; the file is the stage's checkpoint

The seam is a sequence of records per run: the training search produces it, the fine-tune consumes it.
`<stem>.training.parquet` stays, as that stage's rehydration file, like Osprey's other stage files, so a
lost machine loses no completed stage. The format version then guards resuming across builds rather than
compatibility between tools.

| Stage | Checkpoint (rehydration) |
|---|---|
| FASTA -> target/decoy/entrapment FASTA, pairing manifest | the FASTA and manifest (`-build_entrapment_fasta`) |
| Predict the starting library | `.blib` |
| Search the training runs | `<stem>.training.parquet` per run |
| Fine-tune | `.carafemodel` |
| Predict the final library | `.blib` |
| Search all runs | Osprey's existing stage files |

Each stage is a task on the shared base (PR 1, part E), selectable with `--task` for the HPC chain,
with its file contract declared.

#### 3. Keep libtorch out of Osprey's core

TorchSharp and libtorch are about 330 MB (CPU) and 4 GB (CUDA 12.8). `CarafeSharp.Models` and
`CarafeSharp.Training` stay separate assemblies, loaded only by the library stages, so a search with a
user-supplied library never loads libtorch, and Osprey's Linux and Windows packages can ship the CPU
runtime without the CUDA one. The GPU choice (`-device`) becomes an Osprey option. The reproducibility
work in #4717 holds: the alignment reference predicts in float64 on the CPU, and the CUDA generator is
seeded, so a training stage repeats exactly on each system and device.

Dependency direction (decision 4): CarafeSharp.exe references nothing in Osprey. Osprey.exe (or a new
`Osprey.Library` project it loads for the library stages) references `CarafeSharp.Proteome`,
`CarafeSharp.Training` and `CarafeSharp.Models` and runs their tasks in-process through the shared driver.

#### 4. Command line

```
Osprey --fasta proteome.fasta --input run1 run2 run3 [--training-input run2] [--library existing.blib]
```
- No `--library`: Osprey builds one (stages above).
- No `--training-input`: decide the default with Mike. The lab trains on one run that is also searched
  ("search the middle file"); a default of "every search run" trains on all of them. Brendan's concern:
  training on the runs then searched risks overtraining, which the entrapment FDR should measure.
- `CarafeSharp.exe` stays as a thin front end for library-only use and Carafe command-line
  compatibility, declared on the shared grammar (PR 2).

### PR 3 - contracts

- **Part F - training-record assembly.** Extract it; move Osprey's writer and CarafeSharp's reader
  onto it; delete the duplicates. Gate: Osprey and CarafeSharp regressions unchanged byte for byte,
  and the chained leg.
  - **Where it lives (decided 2026-10-15, answering the open question):**
    `pwiz_tools/CarafeSharp/CarafeSharp.Contracts` (namespace `pwiz.CarafeSharp.Contracts`),
    plain net10.0 under CarafeSharp's `Directory.Build.props`, depending only on CommonUtil
    (`SimpleFileSaver`) and the patched Parquet.Net. The dependency runs one way (decision 4):
    `Osprey.IO`, `Osprey.Scoring`, `Osprey.Tasks`, `Osprey` and `Osprey.Test` reference it as an
    out-of-solution project, the way they reference CommonUtil (Osprey's
    `Directory.Build.targets` carries the Configuration), so Osprey.sln stays Osprey-only and
    CarafeSharp.sln builds and inspects the project. Part G's pairing manifest and library
    contract validator go in the same assembly.
  - [x] `TrainingRecord` + `TrainingIonFlags` (Osprey's names, which follow the columns; CarafeSharp
        renamed onto them: `NPeakScans`, `MpFitted`, `MpResidualMad`, `NSameApexClaimants`,
        `NCoelutingClaimants`, `NFiniteScans`, `PolishPosResidMax`, `SharedApexN`,
        `SharedCoeluteN`, `NSlots` for `SlotCount`; `Has(slot, flag)` kept from CarafeSharp's).
  - [x] `ParquetBlobCodec` public in the assembly (`ParquetScoreCache` uses it from there); its one
        resource string moved out of `OspreyIOResources` (en, ja, zh-Hans) into `ContractsResources`.
  - [x] `TrainingExportParquet`: `EXT`, `FORMAT_VERSION` (int; `FORMAT_VERSION_TEXT` for footers),
        `IsExport`, `ColumnNames`, `Write(..., rowsPerGroup)` and one validated `Read` (format
        version 1 or 2, every main column present, `4 * (L - 1)` slots per row - the checks
        CarafeSharp's reader made, now on both sides); `ReadFooter`. Osprey's `PathFor` moved to
        `TrainingExportWriter.PathFor` (it needs `ArtifactPaths`).
  - [x] `TrainingExportKeys`: every footer key as a constant; Osprey's `BuildMetadata` and
        CarafeSharp's `ModelTrainer`, `OspreyTrainingSet`, `TrainingExportLocator` use them.
  - [x] `TrainingExport` (was `CarafeSharp.IO/OspreyTrainingExport`): path + records + footer with
        the typed accessors (`RtMax`, `Ms2ScanWindow`, `DominantCollisionEnergy`, ...).
  - [x] Deleted: `Osprey.Core/TrainingRecord.cs`, `Osprey.IO/TrainingExportParquet.cs`,
        `Osprey.IO/ParquetBlobCodec.cs`, `CarafeSharp.IO/OspreyTrainingRecord.cs`,
        `CarafeSharp.IO/OspreyTrainingExport.cs`, `CarafeSharp.Core/OspreyTrainingExportFile.cs`.
  - [x] CarafeSharp's tests write exports through the shared writer; the reader-refusal cases
        (format 1 with its extra columns, format 3, no version, a missing column) rewrite a
        written file column by column (`OspreyTestRecords.Rewrite` over `ParquetColumns`), so
        the test no longer carries its own copy of the schema.
  - [x] Docs: `Osprey/docs/14-intermediate-files.md` and `22-training-export.md` name the new home.
  - [x] Gates (part F commit, 2026-10-15): Osprey Debug build, 637 tests, inspection clean;
        CarafeSharp Debug build, 103 tests (7 parity tests skipped for test data this machine
        lacks), inspection clean after dropping eight `using pwiz.CarafeSharp.IO;` that the move
        made redundant; `regression.ps1 -Dataset Stellar` PASS (byte-identical golden, modes 1,
        1c, 4, 6); CarafeSharp `regression.ps1 -Leg Chained` REGRESSION PASSED
        (`CarafeSharp/TestResults/regression/stellar-chained-cpu-20261015-093120`).
- **Part G - contracts.** Fold the pairing manifest schema into the same assembly and land the
  library contract validator from `TODO-carafe_osprey_library_contract.md` (CarafeSharp refuses to
  write a violating library; Osprey fails at load, every violation listed by class).
- **Part G - one blib writer (decision, Brendan, 2026-10-14).** The core writer lives in
  `pwiz_tools/Shared/BiblioSpec`, which becomes the DLL every tool imports: a plain net10.0
  project depending only on System.Data.SQLite (the version all three already carry), holding
  the schema (`BlibSchema`, moved from `pwiz_tools/BiblioSpec`, the one definition with the
  version history) and a streaming writer over a neutral record (designed from BiblioSpec's
  `RefSpectrum` outward, so small-molecule metadata fits) with prepared inserts, compressed
  peak blobs, LibInfo and indexes, an atomic commit through `SimpleFileSaver`, and one hook for
  a host's own tables in the same transaction. The `BlibBuild` / `BlibFilter` process wrappers
  stay in that project, and Skyline keeps running the EXEs as processes, as it always has.
  `CarafeSharp.IO/BlibLibraryWriter` and `Osprey.IO/LibraryBlibWriter` + `BlibWriter` become
  that writer (Osprey's five `Osprey*` tables and Carafe's `DecoyPairs` through the hook), with
  `LibrarySpectrum` / `LibraryEntry` reconciled into the record. Gate: both regressions
  byte-identical, since both compare the written library. Not CommonUtil: a SQLite dependency
  does not belong in the utility library every tool loads.
  - Next after this sprint: `pwiz_tools/BiblioSpec`'s `BlibMaker` delegates its table creation
    and inserts to the same writer (Matt's port; the cpp parity tests are the gate). Four
    writers to two.
  - Backlog, not this sprint: Skyline's NHibernate `BlibDb` keeps its own writes (least to gain,
    byte-level drift risk in libraries its tests compare); a backlog TODO unifies it later.
- **Docs.** Done: `CarafeSharp/Carafe-workflow.html`, PR [#4847](https://github.com/ProteoWizard/pwiz/pull/4847) (docs only; merged 2026-10-15 as a5a3fc3dbb), in the style of `Osprey/Osprey-workflow.html`
  (hand-maintained), one block per stage with its checkpoint file; after PR 4 it folds into the
  Osprey page as the library-build chapter.

### PR 4 - one command

- **Part H - one command.** Osprey runs the stages in-process with checkpoints and resume;
  `Run-CarafeSharpWorkflow.ps1` reduces to one Osprey invocation per dataset (kept as the harness
  that names the dataset presets).
- **Part I - HPC tasks** for the new stages with declared file contracts; harness staging from the
  declarations (`TODO-task_file_contract_from_declarations.md` item 3).
  - HPC task set (discussed 2026-10-15, to confirm when PR 4 starts): three CarafeSharp
    boundaries, the FASTA build (reused by stages 5 and 6), library prediction (one task, run
    pretrained before the training search and fine-tuned after) and fine-tuning (the saved
    model predicts many libraries), between the two Osprey chains. `ReconcileManifest` stays a
    command-line mode, not a chain stage. A boundary is justified by resource class (CPU digest,
    GPU prediction and training, CPU fan-out searches), restart cost and reuse, not by the data
    flow alone, which needs only the two cuts around Osprey's training search.
  - Library prediction should fan out across several GPU nodes (Brendan, 2026-10-15: desirable
    where the cluster has them; node availability decides how many). The split goes inside the
    prediction task as batches of peptidoforms, the way Osprey's per-file tasks fan out, with the
    chunks merged into one library; not a new boundary between tasks. Astral's 6.2M precursors
    are about an hour on one GTX 1650.
- **Part J - packaging.** libtorch CPU in Osprey's Windows and Linux packages; CUDA as an optional
  download; `OSPREY_VERSION_OVERRIDE` and the daily stamp cover the model file too.

### Measurement (no PR)

- **After PR 4.** One-command Stellar / Astral / ZT Scan runs against today's four-step
  workflow: IDs at matched entrapment FDP and wall time; training on searched vs held-out runs (the
  overtraining question) recorded here with the run folders.

## Gates

Every PR, before `gh pr create` (then `/code-review medium` on the branch):
- `pwsh -File ./ai/scripts/Osprey/Build-Osprey.ps1 -Configuration Debug -RunTests -RunInspection`
- `pwsh -File ./pwiz_tools/Osprey/regression.ps1 -Dataset Stellar` - byte-identical to the committed
  golden at 1e-9; Phase 1 is pure code motion, so any diff is a defect.
- `pwsh -File ./ai/scripts/CarafeSharp/Build-CarafeSharp.ps1 -RunTests -RunInspection`
- `pwsh -File ./pwiz_tools/CarafeSharp/regression.ps1 -Leg Chained` (about two minutes, no data)
- Before merge of every PR (all four touch Osprey's output or task paths): the TeamCity
  Perf/Regression config on `pull/<N>` (ask first) and `regression-parallel.ps1 -Dataset All` locally.
  Run them once per merge candidate, not per commit; the local Stellar gate covers the commits.
- PR 1 additionally: SkylineBatch tests and the AutoQC build. PR 2 additionally: Skyline's
  command-line tests. CarafeSharp's golden regression (`regression.ps1`, CPU, 12-38 min) for PRs 1,
  3 and 4 (the writers and the stamp in 1; records, contracts and the library writer in 3; the
  in-process stages in 4).

## Open questions

- Mike's position on the CommonUtil dependency (decision 1 assumes yes).
- Default `--training-input` (design 4), with Mike.
- Whether the shared pipeline base is a namespace in CommonUtil or its own `Shared/` project
  (PR 1 decides; a separate project only if Skyline must not see it).
- ~~Where the Phase 2 contracts assembly lives~~ Decided in PR 3 (2026-10-15):
  `pwiz_tools/CarafeSharp/CarafeSharp.Contracts`, see the PR 3 section.
- The `MultiProgressReporter` scoped-output seam depends on `AsyncLocal` flow into `Parallel.For`;
  confirm CarafeSharp's writer thread (`LibraryChunkWriter`) attributes its lines correctly after PR 1.
