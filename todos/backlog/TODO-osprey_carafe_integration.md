# Sprint: one shared toolkit under Osprey and CarafeSharp, then one pipeline

## Branch Information
- **Branch**: not yet created. Each PR gets its own `Skyline/work/YYYYMMDD_...` branch off
  `master`, listed under its PR section as it starts. The TODO moves to `active/` with PR 1.
- **Base**: `master`
- **Created**: 2026-10-13 (as a vision note); restructured into a staged sprint 2026-10-14
- **Status**: Planning. Phase 1 agreed with Brendan 2026-10-14 (see Decisions); Mike's agreement
  to the CommonUtil dependency is assumed pending his return from vacation.
- **GitHub Issue**: (none yet; PR #4717 closed #4707)
- **Module**: `osprey`
- **PR**: (pending)
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

- [ ] Add `pwiz_tools/Shared/CommonUtil/SystemUtil/FileSaver.cs` from Osprey's (cross-platform
      temp allocation, overwrite on commit, temp cleaned on dispose). Resource strings move to
      `CommonResources`.
- [ ] `KeepFailedWrites` becomes a static property on the shared class; Osprey's `Program` sets
      it from `OspreyEnvironment.KeepFailedWrites`. CommonUtil reads no `OSPREY_*` variable.
- [ ] Carry `PartialFile.CommitAs`'s behavior as a method on the shared class: commit under a
      "name (N)" sibling when the final name cannot be replaced.
- [ ] `Osprey.Core.csproj` references `CommonUtil.csproj`; delete `Osprey.Core/FileSaver.cs`;
      25 call sites change only their `using`.
- [ ] `CarafeSharp.Core.csproj` references `CommonUtil.csproj`; add CommonUtil to
      `CarafeSharp.sln`; delete `PartialFile.cs`; `BlibLibraryWriter`, `CarafeLibraryTsvWriter`,
      `EntrapmentFastaBuilder` (FASTA + manifest), `PairingManifestReconciler` move onto it. Note
      that `PartialFile` is not `IDisposable` and its fixed `<name>.partial` temp is deleted by a
      second process writing the same output; both go away.
- [ ] `CarafeModelFile.Save`'s `.tmp` + move becomes a `FileSaver` (the "atomic model-folder
      writes" follow-up from PR #4717).
- [ ] SharedBatch: delete `SharedBatch/FileSaver.cs` and its two resource strings; SkylineBatch
      `DownloadDlg`, `SkylineBatchTest/TestUtils`, DevTools `ImageComparer`, `ResourcesOrganizer`
      (two files), `SortRESX` reference the shared one. Overwrite semantics change from refuse to
      replace for these callers: check each site wants that (a download to a fresh name does).
- [ ] `Osprey.Test/FileSaverTest.cs` moves to `Skyline/CommonTest` (translation-proof per
      `ai/TESTING.md`); add the `CommitAs` fallback and the keep-failed-writes case.
- [ ] Extra gate for PR 1: `SkylineBatchTest` and the AutoQC build, since SharedBatch changes.

### PR 1, part B - CarafeSharp output and errors through CommonUtil

- [ ] `CarafeSharp/Program.cs`: the log writer is a `CommandStatusWriter` over stderr (as Osprey's
      `Program._out`), so `--timestamp`, `--memstamp` and `--log-file` are available to CarafeSharp
      and, later, in-process stages write to Osprey's sink with its prefixes. The existing
      `TextWriter log` plumbing accepts it unchanged.
- [ ] Top-level catch follows Osprey's `DescribeFailure`: a user-actionable exception
      (`CommonExceptionUtil.IsProgrammingDefect` false) is its message; a defect is the whole
      exception with its stack. `UnwrapUserException` for the parallel-loop `AggregateException`.
- [ ] Exit codes as Osprey's: 0 success, 1 failure to start (usage, missing input), 2 ran with
      errors. `IsErrorReported` reconciles a failing exit code with an `Error:` line.
- [ ] Usage errors keep their one-line form (the parser's `ArgumentException`, as today).
- [ ] `CommandLineErrorTest` asserts the exit codes and that a synthetic defect prints its type.

### PR 1, part C - one progress reporter in CommonUtil

- [ ] Move `ProgressReporter`, `MultiProgressReporter` (with `IProgressSink`, `FileScope`),
      Osprey's `ProgressStream` and the `OspreyOutput` seam to `CommonUtil/SystemUtil` under
      neutral names (the seam becomes the process output writer with the per-flow scoped
      redirect; `PerfStats` / `Verbose` stay on it or move to `LogTag`, whichever keeps
      `OspreyLog.Write` unchanged). Behavior, constants and line formats unchanged: the
      regression gate and `perfviz.py` read them.
- [ ] CommonUtil's existing `ProgressStream` (Nick's, `IProgressMonitor`-driven) and Osprey's
      (reporter-driven) differ in sink only; keep one class with two constructors, or two
      clearly named classes. Decide in the PR, document on the class.
- [ ] `ProgressReporterTest` moves to `CommonTest`.
- [ ] CarafeSharp reports its determinate loops through it: `LibraryGenerator`'s batches and
      chunks, `FineTuneRun`'s epochs, `Digester` / `LibraryDatabase.DigestPeptides` over proteins,
      `BlibLibraryWriter` over spectra. The `TextWriter log` parameters stay for prose; the
      reporter carries the percent lines. The `Action<string> log` variants (`ModelFineTuner`,
      `FastaReader`, `FineTuneRun`) collapse onto the same writer.
- [ ] `Osprey.Core` keeps `OspreyOutput` only as a thin alias if the rename would touch too many
      files in one PR; otherwise delete it.

### PR 2, part D - one command-line grammar in CommonUtil, CarafeSharp declared on Argument

- [ ] Generalize Osprey's `TokenizeAndDispatch` / `MatchToken` into CommonUtil as the one
      tokenizer, configured by the host: long prefix(es) (`--` for Skyline and Osprey, `-` for
      Carafe), short aliases, whether a value may follow as the next token, `=value` acceptance,
      variadic arguments, optional-count arguments, positional fallback, duplicate policy (last
      wins vs first wins), unknown-token policy (error vs warning vs ignore). Skyline's strict
      grammar is the default configuration, so `CommandArgs` and its tests are unchanged.
- [ ] `OspreyCommandArgs` declares its grammar and drops the private tokenizer; `ArgTokens`,
      `CommandLineErrorTest` and `OspreyConfig` round-trips lock the parsed config byte for byte.
- [ ] `CarafeCommandLine` becomes a set of `Argument<CarafeCommandLine>` declarations with the
      Carafe configuration (single dash, first value wins, unknown is an error, stray tokens
      ignored, every Carafe 2.2.0 option declared, the unused ones marked as accepted-and-ignored).
      Its `Settings` building (`LibrarySettings`, `TrainingSettings`, `EntrapmentFastaSettings`)
      is untouched. `CarafeSharp.Test/CommandLineErrorTest` and `LibraryCommandLineTest` lock
      every parse result and error message, and the parity tests keep feeding Carafe's own
      command lines (`CarafeReferenceRun`), which is the reason the grammar is kept at all.
- [ ] Standard first, compatibility second: one declaration can be reachable under more than one
      grammar, so CarafeSharp can accept the standard `--name value` form alongside Carafe's
      `-name value` without a second declaration, and a grammar is a configuration object the
      host picks, never a subclass per tool. Decide in the PR whether CarafeSharp's generated
      help shows the standard form, the Carafe form, or both; the Carafe form is what the
      maccoss/Carafe users and the workflow scripts type today.
- [ ] `--help` and `--help html` for CarafeSharp are generated from the declarations (the
      `ArgUsage.Provider` descriptions come from a resx of argument text only, as
      `OspreyCommandArgUsage.resx` does; this is not the deferred general resx extraction).
      The hand-written `Usage` block is deleted. Osprey's `docs/20-command-line.md` gets a sibling
      in `CarafeSharp/docs`.
- [ ] A `CarafeArgNames` class (or shared constants) replaces the `TRAINING_EXPORT_SUFFIX`
      duplicate between `CarafeCommandLine` and `OspreyTrainingExport`.
- [ ] Extra gate for PR 2: `Skyline/Test` command-line tests (`CommandLineTest`, `CommandLineUsageTest` or
      equivalents) since the tokenizer now serves `CommandArgs`.

### PR 1, part E - the task contract in Shared, CarafeSharp's stages on it

- [ ] Extract the generic part of `OspreyTask` + `AnalysisPipeline`'s driver loop to Shared
      (namespace `pwiz.Common.Pipeline` inside CommonUtil unless it needs its own assembly; decide
      in the PR): task `Name`, declared `Inputs` / `Outputs`, a validity key, an in-file stamp
      (`ArtifactStamp` with the version supplied by the host, not read from `OspreyVersion`),
      `Run` / `Rehydrate`, the skip-when-current rule, the one-shot materialization guard, and the
      byproduct registry (`Publish` / `Get` / `Demand`). Osprey-specific facts (`OspreyConfig`,
      `SearchIdentity`, `ISelectableTask`'s HPC predicates, `LogTag` routes) stay in Osprey as a
      derived task and context.
- [ ] `OspreyTask` derives from the shared base; `TaskValidityKeyTest`, `SubsetPipelineTest`
      (resume, rehydrate, HPC chain, sidecars) lock the behavior.
- [ ] CarafeSharp's four stages become tasks on the shared base, inside CarafeSharp (no Osprey
      reference): build-entrapment-fasta, reconcile-manifest, predict-library, train. Each
      declares its inputs and outputs (FASTA, manifest, `.blib` / TSV, `.carafemodel`, the
      `.training.parquet` set) and stamps its outputs; `CarafeSharp.exe` runs the selected task
      through the shared driver, so a re-run with current outputs skips, as Osprey's does. Stage
      selection moves from `Run-CarafeSharpWorkflow.ps1 -Stages` toward the tool.
- [ ] The `.carafemodel` zip and the blib/TSV writers carry the stamp in their own slot (the model
      manifest; a blib metadata row; a TSV header comment), per `ArtifactStamp`'s "lives in the
      artifact" rule. CarafeSharp's `RegressionTest` goldens must be unaffected (the stamp is
      excluded from the compared content, as Osprey's goldens exclude it).
- [ ] `TODO-task_file_contract_from_declarations.md` item 1 (`IsPerFile` on the task) and 2
      (`--help-files` derived from the declarations) are done here for both tools, since the
      printer is generic once the declarations are shared. Item 3 (harness staging) is PR 4, part I.

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
- **Part G - contracts.** Fold the pairing manifest schema into the same assembly and land the
  library contract validator from `TODO-carafe_osprey_library_contract.md` (CarafeSharp refuses to
  write a violating library; Osprey fails at load, every violation listed by class). Also the one
  library blib writer: `CarafeSharp.IO/BlibLibraryWriter` and `Osprey.IO/LibraryBlibWriter` become
  one, in the contracts assembly or CommonUtil, with `LibrarySpectrum`/`LibraryEntry` reconciled.

### PR 4 - one command

- **Part H - one command.** Osprey runs the stages in-process with checkpoints and resume;
  `Run-CarafeSharpWorkflow.ps1` reduces to one Osprey invocation per dataset (kept as the harness
  that names the dataset presets).
- **Part I - HPC tasks** for the new stages with declared file contracts; harness staging from the
  declarations (`TODO-task_file_contract_from_declarations.md` item 3).
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
- Where the Phase 2 contracts assembly lives so CarafeSharp references it without the Osprey search
  stack (the library contract TODO's open question; PR 3 decides).
- The `MultiProgressReporter` scoped-output seam depends on `AsyncLocal` flow into `Parallel.For`;
  confirm CarafeSharp's writer thread (`LibraryChunkWriter`) attributes its lines correctly after PR 1.
