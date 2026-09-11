# TODO-osprey_log_readability.md - make Osprey's user-facing text read for a mass spectrometrist, and move it to RESX

## Branch Information
- **Branch**: (pending; suggest `Skyline/work/YYYYMMDD_osprey_log_readability`)
- **Base**: `master`
- **Created**: 2026-09-11
- **Status**: Backlog (spec complete, not started; Brendan plans to start after PR #4656 merges)
- **GitHub Issue**: (pending)
- **Module**: `osprey`
- **PR**: (pending)

**Origin**: Brendan, 2026-09-09, after noticing that log terms such as "projection" come from
class names Claude assigned during development and mean nothing to a user. Reviewed line by
line on 2026-09-09..11 against master `794cb6a5d8` (#4646). On 2026-09-11 Brendan widened the
scope: do the whole thing in one sprint, **including moving Osprey's user-facing text to RESX
files**. Rationale, in his words: C# .NET has won; Osprey is to be a solid companion to Skyline
and will be fully integrated into it within the year; BiblioSpec will follow (converted to C#
.NET with its user-facing text in RESX); the time when our command-line tools were allowed to
stay all English is over.

Supersedes `ai/todos/backlog/TODO-osprey_log_lines_are_user_facing_prose.md` (now a stub
pointing here). Related: `ai/todos/backlog/TODO-osprey_env_var_cataloging.md` (env vars named
in log lines).

**Companion files beside this TODO** (the spec is the four of them together):

| File | What it is |
|---|---|
| `TODO-osprey_log_readability-spec.html` | The review page: glossary with decisions, Table A (user-facing lines by confusion, with rewrites), B1 (developer lines leaking into the default log), B2 (gated diagnostics inventory), C (warnings written for a developer). Open in a browser. Same content as the published artifact `https://claude.ai/code/artifact/c51944d7-39b3-4208-9432-92160c6a2fca`. |
| `TODO-osprey_log_readability-lines.csv` | One row per emitting call site (583), with priority, the flag that exposes it, current text, flagged terms, why, suggested text and action. Line numbers are for master `794cb6a5d8`. This is also the worklist for the RESX move: every default-tier row becomes a resource. |
| `TODO-osprey_log_readability-terms.csv` | The term sheet with Brendan's decisions in the "Brendan decision so far" column. |

The HTML is the readable form; the CSV is the checklist to work down. Where they disagree,
the HTML is newer.

## Summary

Osprey's console log is its only user interface, and roughly a third of the lines a user sees
in an ordinary run use vocabulary that exists only inside the codebase: sidecar, compaction,
survivors, hydrate, stratum, base_id, fold, bundle, stubs, projection. Some lines print C#
method names (`[PATH] First-pass streaming ingest (RunStreamingFirstPass)`), some announce the
default behaviour by an environment-variable assignment the user never made
(`OSPREY_PASS2_QVALUE=protein-compact: ...`), and the second-pass progress headings narrate the
code structure (seed, collect, stream, patch, reload) rather than what the user is waiting for.

The gating of developer output is in good shape: `[COUNT]`/`[TIMING]`/`[BENCH]`/`[STAGE-WALL]`
are behind `--perf-stats`, `[MEM ...]` behind `OSPREY_LOG_MEMORY`, bisection dumps behind
`-d`/`OSPREY_DUMP_*`, implementer detail behind `--verbose`. The problem is inside the default
tier.

The work has four parts, in this order: **gate** the developer lines that leak (no wording
decisions needed); **move every script and test that keys off prose onto tagged machine
lines**, so prose can change and be translated without breaking a gate; **rewrite** the
user-facing lines with the decided vocabulary; and **move the user-facing text to RESX** with
the same enforcement Skyline uses, so it can be translated to Japanese and Chinese with
Skyline's existing pipeline. The first two parts are what make the last two safe.

## Evidence (master `794cb6a5d8`, tests excluded)

| Tier | Call sites | Exposed by |
|---|---:|---|
| default log | 399 | every run |
| perf stats | 83 | `--perf-stats` (`[COUNT]` `[TIMING]` `[BENCH]` `[STAGE-WALL]`) |
| model diagnostics | 35 | `--model-diagnostics` |
| bisection dumps | 31 | `-d`, `OSPREY_DUMP_*`, `OSPREY_DIAG_*` |
| verbose | 20 | `--verbose` |
| FDRBench / entrapment | 12 | `--fdrbench` |
| memory probes | 3 | `OSPREY_LOG_MEMORY` |

Inside the 399 default lines: 47 contain a C# method, class, task or variable name; 53 say
"sidecar"; 15 name an `OSPREY_*` variable; about 120 use at least one codebase-only term.
Only 3 of 583 sites format a count with a thousands separator.

Two real logs were read end to end: the 3-file Stellar run
`D:\test\osprey-runs\defectb2-stellar.log` and the 82-file Astral run
`D:\test\osprey-runs\sea-ad\runs\seaad-82files-libdecoy-r1.0-protein-compact-s7offB-20260831_115149\run.log`.
In the 82-file log, 82 of 369 lines are the same developer note repeated once per file
("Loaded N FDR stubs (features not loaded - not read on this path)").

## Decided vocabulary (Brendan, 2026-09-09..11)

Use this as the rename map. The full table with meanings is the glossary on the spec page.

| Never in user text | Say instead |
|---|---|
| sidecar | **intermediate file** ("intermediate" is the key word: not the end result). Name the file where it helps. |
| entry / entries, base_id(s) | **precursor candidates** (targets + decoys); "candidates" replaces "entries" and "library entries" everywhere |
| compaction / compact | say what was kept: "kept N of M precursor candidates for cross-run reconciliation" |
| survivors / survivor pool / retained set | precursor candidates carried forward (no objection recorded; open) |
| stratum, protein-compact stratum | **precursor candidates from proteins with 2 or more detections**; "protein-compact subset" only where the flag itself is named. "Detections" = passed the current cutoff, without saying which. |
| hydrate / rehydrate | load / reload from intermediate files (open) |
| fold (verb) | one run at a time. Not liked even as a developer term. |
| projection | (the last progress heading using it was removed by #4646; the `[PATH]` line moves to perf-stats) |
| bundle / envelope | **cross-run reconciliation files**. "Reconciliation plan" was opaque; "results" is reserved for end results a user looks at. |
| stubs | "Loading FDR values from intermediate files" (one heading, not one line per file) |
| scalars | first-pass scores (open) |
| frozen model / no retrain | **drop**. Records what the code no longer does; diagnostic channel only if a test needs it. |
| use_cwt / forced / gap-fill / action(s) | **peaks re-picked / peak boundaries imputed / missing peaks** (Skyline's peak-boundary-imputation vocabulary; in a count, just "missing peaks") |
| Stage 1-4 / 5 / 6 / 7 | never a stage number. The `--task` names are fine: the CLI help documents them. |
| resident, byproduct, interned, parquet index | diagnostic output if a test needs it, else drop |
| worker / fan-out / join | per-file run / merge (open) |
| boundary file pair | intermediate files (do not add "that the next task needs") |
| `OSPREY_*` on a default path | never. Name a variable only when the user set it; env vars are developer-facing. |
| enum `ToString()` (UnitResolution, DiannTsv, Reverse, percolator) | Skyline's `GetLocalizedString(this Enum)` extension over a `LOCALIZED_VALUES` array of resource strings (`Skyline/Model/Export.cs`) |

Kept as they are: **coelution** (known DIA term; Skyline has a "coelution score"),
**reconciliation / cross-run reconciliation** ("cross-run" carries the meaning; TRIC is the
nearest published concept), **Percolator**, **`[TASK] Name:starting` markers** (Brendan likes
them; the names are the `--task` values).

Rules that fell out of the review:

1. A noun swap is not a fix for a data-structure word ("stratum" -> "set" is equally opaque).
   The line must state the effect on the results, in one clause: which candidates get new
   q-values, what was kept, what will be imputed.
2. "results" means end results the user looks at. Anything written beside an input for a
   later step is an "intermediate file"; do not stack the two words.
3. Every count carries a thousands separator (`{0:N0}`). Global, not per line.
4. A line whose only purpose is to record which code path ran, or how memory is managed, is
   diagnostic output behind `--verbose`, `--perf-stats` or `OSPREY_LOG_MEMORY`, never user text.
5. No C# identifier, no task name outside the `[TASK]` marker, no environment variable and no
   stage number in a default-tier line.

## Two kinds of line

This is the design decision that makes the rewrite safe now and the translation possible.

**Prose** is for the person watching the run. It lives in RESX, may change in any PR, and is
translated. **Tagged lines** (`[TASK]`, `[COUNT]`, `[TIMING]`, `[BENCH]`, `[STAGE-WALL]`,
`[PATH]`, `[MEM ...]`) are the machine channel: ASCII, verbatim `@"..."` literals, never
resourced, never translated, and the only thing a script or test may key off. Write this into
`pwiz_tools/Osprey/docs/20-command-line.md` as a "Log format" section:

- **A script or test that reads the log keys off tagged lines only.** A prose probe is a
  defect to fix in the consumer, not a reason to freeze the prose.
- **Tag format is `[TAG] key: value` or `[TAG] key=value`.** Adding a tag or key is fine;
  renaming one means updating the consumers in the same PR.
- **The tags are gated** (`--perf-stats` for the stat tags, `OSPREY_LOG_MEMORY` for `[MEM]`),
  except `[TASK]`, which is a section header and stays in the default log. `[PATH]` and
  `[TRAIN]` are not in `OspreyOutput.IsStatLine` today and so leak into the default log; add
  them, and have every gate that needs them pass `--perf-stats`.
- **Route assertions get a `[PATH]` line each.** `regression.ps1` asserts which route a run
  took by grepping prose ("Second-pass join: folding over N run(s)", "worker's written answer
  for all N file(s)", "folding the report from the completed first pass", "ALL-RUNS
  reconciliation bundle", "a consumer asked for the whole-run survivor pool"). Each becomes a
  `[PATH] <route-key>` line emitted where the prose is today, e.g.
  `[PATH] stage7-join: fold-per-run`, `[PATH] pass2-per-file: worker-answers 82/82`,
  `[PATH] mdiag: fold-pass1`, `[PATH] all-runs-bundle: refused`.
- **Counts a gate asserts get a `[COUNT]` line**, e.g.
  `[COUNT] library-fragments-released: N of M (K retained for rescore+gap-fill)`.
- **In code, the marker is the string prefix.** Verbatim `@"..."` on a `LogInfo` call means
  "machine channel or developer-only, not for translation"; a plain `"..."` literal is a
  localization warning (see enforcement below). Today the `@` prefix is used on both kinds
  of line at random; after this work it carries meaning.

## RESX: scope, mechanics, enforcement

**What is user-facing (goes to RESX).** Every string a user can see without setting an
environment variable or passing `-d`: the default tier (`LogInfo`, `LogWarning`, `LogError`,
`ProgressReporter` headings, the `[WARN]`/`[ERROR]` prefixes themselves), the `--verbose`
tier (it is a documented CLI flag and its calibration statistics are for a careful user),
the `--model-diagnostics` console lines, `--help` text (argument and group descriptions,
already `Func<string>` so a resource drops straight in; the generated
`Documentation/Help/en/CommandLine.html` already carries an `en` in its path), and the
exception messages that reach the user through `Fatal error: {0}` / `Pipeline failed: {0}`
when they describe a user-correctable condition: file not found, unreadable or empty library,
missing column at row N, unsupported format version, incompatible daily build. Roughly 65
such throws sit in `Osprey.IO` and `Osprey/` today.

**What stays verbatim English.** Tagged machine lines; `OSPREY_*`-gated and `-d` diagnostics
(`OspreyFileDiagnostics`, `PercolatorDiagnosticsDump`, `[BISECT]`, `[MEM]`); internal-invariant
exceptions (`InvalidOperationException` in `Osprey.ML`, `Matrix`, the reconciliation planner)
per STYLEGUIDE "Non-Localizable Text"; `ToString()` overrides; file names, flag names, env-var
names and format-version tokens inside otherwise-resourced strings stay as `{0}` arguments.

**Mechanics (SDK-style, multi-TFM `net472;net8.0`).**
- One `Resources.resx` per assembly that emits user text: `Osprey.Core`, `Osprey.IO`,
  `Osprey.Scoring`, `Osprey.FDR`, `Osprey.Tasks`, `Osprey` (exe). Name them after the
  assembly to keep the generated classes distinct (`OspreyTasksResources`, ...), as Skyline
  does with `ModelResources`, `MenusResources`, `CommonMsDataResources`. The `Chromatography`,
  `ML` and `Diagnostics` assemblies emit no user prose and get none.
- Check in the `.Designer.cs` (generated by VS's `PublicResXFileCodeGenerator`; SDK projects
  need the `<EmbeddedResource Update=...><Generator>` / `<Compile Update=...><DependentUpon>`
  items so VS regenerates on save). `dotnet build` on Linux compiles the checked-in Designer
  and builds the `ja` / `zh-CHS` satellite assemblies from `.ja.resx` / `.zh-CHS.resx`
  automatically; the installer and the standalone ZIP must ship the satellite folders.
- Resource keys follow Skyline's convention `Class_Method_Message_text_with_underscores`
  so ReSharper's "Move to resource" produces them and the translators' CSV reads well.
- `string.Format` stays; the resource holds the format string with `{0}` placeholders.
  Counts use `{0:N0}` (rule 3) inside the resource string.
- Enums: `GetLocalizedString(this Resolution)` etc. over `LOCALIZED_VALUES`, plus
  `Helpers.EnumFromLocalizedString` for the CLI parse direction where the value is user-typed
  (CLI values themselves stay English: `--resolution unit|hram|auto` is a token, not prose).
- Culture at runtime: mirror Skyline's internal `--culture <name>` argument
  (`CommandArgs.ARG_INTERNAL_CULTURE`, sets `CurrentCulture` and `CurrentUICulture`) so a run
  can be forced to `ja` for testing and screenshots. Default is the OS UI culture, as in
  Skyline.

**Enforcement, using what Skyline already has.**
- `Osprey.sln.DotSettings` already inherits `LocalizableElement = WARNING` from Skyline, but
  no Osprey project opts in, which is why the zero-warning inspection gate passes today with
  plain literals everywhere. Add a `<Project>.csproj.DotSettings` beside each of the six
  projects above with the two lines `Skyline.csproj.DotSettings` carries:
  `Localization/Localizable = Yes` and `Localization/LocalizableInspector = Pessimistic`.
  From then on `Build-Osprey.ps1 -RunInspection` (the existing pre-commit gate) fails on any
  plain `"..."` literal that is not resourced, and `@"..."` is the deliberate exemption for
  the machine channel and diagnostics. Do this on a branch where the 583 call sites have
  been walked, or the gate goes red on every one of them at once.
- Add the per-project DotSettings in the same commit that resources the last string in that
  project, so the gate never has a red interval.
- Translation-proof tests (TESTING.md): every `Osprey.Test` assertion on prose moves to the
  resource constant, or to a tagged line, or to a flag/file name. Add a locale switch to the
  Osprey test project (an `AssemblyInitialize` that reads `OSPREY_TEST_CULTURE`, since Osprey
  runs under `vstest.console` rather than Skyline's `TestRunner /locale`) and have
  `Build-Osprey.ps1 -RunTests` run the suite once more under `ja-JP` before a commit that
  touches resources. A `ja.resx` with a handful of machine-translated strings is enough to
  make an English-literal assertion fail; the real translations come through the pipeline.

**Translation pipeline.** No tooling change: `MakeResourcesDb.bat` already adds every
`.resx` under `pwiz_tools` with an exclusion list, so `pwiz_tools/Osprey/**/*.resx` joins
`IncrementalUpdateResxFiles` / `FinalizeResxFiles` and `LastReleaseResources.db` as soon as
the files exist (`ai/docs/translation-guide.md`). Osprey's first translations will arrive with
the next Skyline translation round; until then the `ja`/`zh-CHS` files fall back to English.

**BiblioSpec.** Out of scope here, but the same two-kinds-of-line rule and the same
DotSettings enforcement apply when it is converted; this TODO is the template.

## Coupling inventory: everything that reads log text today

Found by grepping `Osprey.Test`, `pwiz_tools/Osprey/*.ps1`, `ai/scripts`. Every row either
moves to the machine channel or is confirmed format-only. With RESX in scope this table is not
optional: a prose probe that survives will break the first time a run is launched under `ja`.

### `pwiz_tools/Osprey/regression.ps1` (the correctness gate; runs with `--timestamp --memstamp`, NOT `--perf-stats`)

| Probe (line) | Text it matches | Disposition |
|---|---|---|
| task cache map (1044-1069) | `[TASK] <Name>:starting`, `[TASK] <Name>:skipping (outputs valid)` | keep; `[TASK]` is machine channel and stays as is |
| cold-work probes (1044-1045) | `Scoring file ` / `Re-scoring file ` (case-sensitive prefix of the per-file lines) | prose a user reads, and it will be translated. Add `[PATH] score-file N/M` / `[PATH] rescore-file N/M` and move the probe |
| library-fragment release (1051-1054, 1290s) | regex over `Released library fragments for N of M entries (K base_ids retained for <scope>)` | B1 demotion target. Emit `[COUNT] library-fragments-released: ...` under `--perf-stats`; regression passes `--perf-stats`; prose goes behind `OSPREY_LOG_MEMORY` |
| no-all-runs-bundle (1197, 1227-1290) | `ALL-RUNS reconciliation bundle` in the guard's error text; anchor `Threads:` from the banner | `[PATH] all-runs-bundle: refused` / `: built`; the banner anchor becomes a `[TASK]`-style start marker (`Threads:` will be translated) |
| mode 3 fold split (2132-2205) | `Second-pass worker verification ACTIVE`, `worker's written answer for all \d+ file\(s\)`, `Second-pass join: folding over \d+ run\(s\)`, `Second-pass (worker verification ACTIVE\|fold )` | A20/A22 targets. Replace with `[PATH]` lines |
| mode 10 alt arms (2333) | `OSPREY_PASS2_QVALUE=transfer:`, `Experiment aggregation: mean-best-2 ACTIVE` | assert `[PATH] pass2-qvalue: transfer` and `[PATH] experiment-agg: mean-best-2` |
| mode 11 pay-later report (3134-3152) | `folding the report from the completed first pass`, `folding the pass-2 report from the completed second pass`, `[STAGE-WALL] second-pass-fdr`, `Running protein-level FDR`, `Re-scoring file ` | A28 targets. `[PATH] mdiag: fold-pass1` / `fold-pass2`; the forbidden-work probes move to `[STAGE-WALL]`/`[PATH]` |
| pooled-survivor check (2815) | `a consumer asked for the whole-run survivor pool` | C2. `[PATH] survivor-pool: materialized` |

### `ai/scripts`

| Script | Text it matches | Disposition |
|---|---|---|
| `perfviz.py` | `LINE_RE` (timestamp + memstamp columns), `TASK_RE` `\[TASK\] (\w+):(starting\|done\|skipping)`, `FAIL_RE` `\[ERROR\]\|Unhandled exception\|Pipeline failed` | `[TASK]`/`[ERROR]` stay ASCII. "Pipeline failed" and "Unhandled exception" are prose: emit `[ERROR] pipeline-failed:` as the machine prefix and keep the human sentence after it |
| `Osprey/Test-PerfGate.ps1`, `Osprey/Measure-Pipeline.ps1` | `[STAGE-WALL]` names `stage1to4 stage5 stage6 stage7 second-pass-fdr blib`; `[TIMING] Percolator/Simple FDR`, `[TIMING] First-pass protein FDR` | unaffected (perf-stats channel; stage numbers in machine keys are fine) |
| `Osprey/Get-MemoryReport.ps1` | `[MEM <label>]`; `[STAGE-WALL]`; prose `Coelution analysis complete. N total scored entries across N files`; `Total pipeline: Ns` | the coelution line is A23. Add `[COUNT] scored-candidates: N across M files` and move the probe; `Total pipeline` is already `[TIMING]` |
| `Osprey/SEA-AD/Measure-Stage6Rescore.ps1` | `[MEM reconciliation-resident]`, `[MEM stage7-inherited]` etc. | unaffected |
| `Osprey/Run-Osprey.ps1 -Summary` | a prose pattern list (`calibrated frag`, `Coelution search RT`, `Applying MS2`, `First-pass RT tolerance`, `Refined RT tolerance`, `Wrote feature`, `precursors at`, `Coelution analysis complete`, `MS2 calibration (pass`, `Confident peptides`, `Coelution scored`, `Analysis complete`) | a convenience filter, not a gate. Rebase it on `[TASK]`/`[COUNT]` lines or drop it |
| `Osprey/Common/OspreyDatasetRun.psm1`, dataset runners | no log-text parsing | unaffected |

### `Osprey.Test`

| Test | What it asserts | Disposition |
|---|---|---|
| `ProgramTests.cs` (~40 asserts) | CLI validation errors: flag names (`--task PerFileScoring`, `--library and --output`, `2+ files`, `No input files`, `unknown task`), version-guard text (`different daily build`, `incompatible release identity`, `search_hash mismatch`) | flag names are tokens and stay. Everything else asserts the resource constant (`AssertEx.Contains(err, OspreyResources.X)`) |
| `ResidentPoolGuardTest.cs:342-344` | `O(files x entries)`, `per-run survivor loader`, `cannot admit this path` from `ScoringTaskShared.AllRunsBundleGuardError` (`ScoringTaskShared.cs:805-811`) and `PerFileScoringTask.cs:2257-2260` | developer prose not on the spec's Table C; add as C13 and rewrite. Assert the guard fired via `[PATH] all-runs-bundle: refused` or a return value, not the wording |
| `MultiProgressReporterTest.cs`, `ProgressReporterTest.cs` | progress *format*: `<activity>...`, `  N%`, `[1] 10%  [2] 20%`, `[TIMING]` filtered | format-only; the `...` suffix and percent layout are not resourced |
| `FdrTest.cs:1520-1590`, `ModelDiagnosticsDataTest.cs` | model-diagnostics *report* text (`Model sanity check`, `(unexpected direction)`, `Reason` strings) | report content, not the log. In scope for RESX only if the report is user-facing (it is: `--model-diagnostics` is a CLI option). Same translation-proof rule |
| `CodeInspectionTest.cs` | no rule about strings today | the DotSettings opt-in above is the enforcement; a banned-word rule is still worth adding for vocabulary (below) |

## Implementation plan

Work from the CSV, `Priority` column, in this order. Each step is independently green.

**Step 1: machine channel and gates (no wording decisions).**
- Add `[PATH]` and `[TRAIN]` to `OspreyOutput.IsStatLine`.
- Add the `[PATH]` route lines and `[COUNT]` lines from the coupling inventory, next to the
  prose they replace.
- `regression.ps1`: pass `--perf-stats` (add to `$memStampArgs`), move every probe in the
  table to the tagged line, keep the `[TASK]` probes. `Get-MemoryReport.ps1`: same for the
  coelution count. `perfviz.py`: `[ERROR] pipeline-failed:`. `Run-Osprey.ps1 -Summary`: rebase
  or drop.
- Demote the B1 lines (spec page, Table B1) to `--verbose` or `OSPREY_LOG_MEMORY`. This alone
  removes about a third of the default-tier jargon and a quarter of the 82-file log.
- `ProgressReporter`: no change; the heading/percent format is what the tests pin.

**Step 2: the High rows (A1-A13).** Thirteen rows, all in every default run. A1, A2 and A11 are
what a new user hits in the first run that reaches the second pass. Use the decided wording in
the CSV verbatim. A4 is resolved on master by #4646 and is listed only to keep "projection"
banned.

**Step 3: Medium and Low rows (A14-A31) and Table C.** A14 (`[TASK]`) is decided "keep".
Table C is the warnings written for a developer: keep the one user sentence each already
contains, move mechanism, issue numbers and method names into a code comment beside the call.
Add C13 (`AllRunsBundleGuardError`, `PerFileScoringTask.cs:2257`).

**Step 4: RESX.** Per project, in dependency order `Core`, `IO`, `Scoring`, `FDR`, `Tasks`,
exe: create the resx, move every default-tier and `--verbose` string (the CSV rows with
`Visible when` = default or `--verbose`, plus `--help` text and the user-correctable exception
messages), mark the machine-channel and diagnostic strings `@"..."`, add the enum
`GetLocalizedString` extensions, add the project's `.csproj.DotSettings`, and run
`Build-Osprey.ps1 -RunTests -RunInspection` before moving to the next project. Steps 2-3 can
be done as the strings are moved rather than before: rewriting a string and resourcing it is
one edit.

**Step 5: tests under a second culture.** The `OSPREY_TEST_CULTURE` switch, a seed `ja.resx`
per project, `Build-Osprey.ps1 -RunTests` running twice, and every English-literal assertion
in the coupling table converted.

**Step 6: guard against vocabulary regrowth.** A `CodeInspectionTest` rule that scans the
English `.resx` values (not code, now that the strings live there) for the banned tokens:
`sidecar`, `stratum`, `base_id`, `hydrat`, `compaction`, `survivor`, `stubs`, `scalars`,
`frozen`, `projection`, `byproduct`, `interned`, `resident`, `Stage [1-7]`, `OSPREY_[A-Z_]+`
and any `\w+\.cs` / `\w+Task\b` / `Run\w+\(` identifier. The review found ~120 such lines;
without a guard they return one feature at a time, because the class name is the nearest word
to hand for whoever is inside the class.

**Docs.** The "Log format" section in `pwiz_tools/Osprey/docs/20-command-line.md` (two kinds
of line, tag list, gating, consumer rule, the `@` convention, the vocabulary table), and a
short "Localization" section pointing at `ai/docs/translation-guide.md`. These are "what the
code does", so they live in pwiz, not `ai/`.

## Acceptance

- `Build-Osprey.ps1 -RunTests -RunInspection` green with the six `.csproj.DotSettings` in
  place, i.e. zero `LocalizableElement` warnings and no un-resourced plain literal left in
  those projects.
- `Build-Osprey.ps1 -RunTests` green under `OSPREY_TEST_CULTURE=ja-JP` as well as `en-US`.
- `regression-parallel.ps1 -Dataset All` green with `--perf-stats` in the harness args and no
  prose probes left in `regression.ps1`; then green again with the harness launching Osprey
  under `--culture ja` (proves the gate reads only the machine channel).
- `Test-PerfGate.ps1 -Dataset Stellar` runs (it only reads `[STAGE-WALL]`).
- Re-read the 3-file Stellar default log and an 82-file second-pass log against the banned
  list: zero hits in the default tier. The 82-file log shrinks by the 82 per-file stub lines.
- `MakeResourcesDb.bat` picks up the Osprey resx files (run it once and check the database).
- The standalone ZIP and the MSI include the `ja` and `zh-CHS` satellite folders.

## Shape of the PR

One PR (memory: lean bigger on PRs; the small-PR instinct is not free), reviewed in two
passes: steps 1 and 6 first (mechanical, no wording), then steps 2-5. If it must split, split
after step 1, because step 1 is what makes everything after it safe against the gates. Run
`/code-review max` before opening, and ask before triggering the TeamCity Perf/Regression
config (memory).
