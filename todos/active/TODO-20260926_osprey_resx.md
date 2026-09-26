# TODO-20260926_osprey_resx.md - move Osprey's user-facing text to RESX and make it locale-correct

## Branch Information
- **Branch**: `Skyline/work/20260926_osprey_resx` (checkout `C:\proj\pwiz-work2`; created at
  `8422c59eca`, the #4718 tip, and pushed 2026-09-26)
- **Base**: `Skyline/work/20260924_osprey_log_readability` - STACKED on PR #4718. When #4718
  squash-merges into `Skyline/work/20260612_net8_port`, merge `origin/Skyline/work/20260612_net8_port`
  into this branch (never rebase once a PR exists) and retarget the PR base to the port branch.
- **Created**: 2026-09-26
- **Status**: Not started - branch created, plan only. Next: Step 1 (infrastructure) on
  `Osprey.Core`. Note: the port branch has moved since #4718 branched (`bba770990a` ->
  `5246fa6b2f` on 2026-09-26); #4718 will pick that up when it merges or updates.
- **GitHub Issue**: (none)
- **Module**: `osprey`
- **PR**: (pending) - `gh pr create --base Skyline/work/20260924_osprey_log_readability --label osprey`
  while #4718 is open; base becomes the port branch after it merges.

**Origin**: the second half of `TODO-20260924_osprey_log_readability.md` (PR #4718 did steps 1-3:
machine channel, gates, `Error:`/`Warning:`, rewording). Brendan, 2026-09-11: C# .NET has won;
Osprey will be integrated into Skyline within the year, and the time when our command-line tools
could stay English-only is over. Osprey's text must translate to Japanese and Chinese through
Skyline's existing pipeline, and it must be correct in any locale.

**Read first**: `TODO-20260924_osprey_log_readability.md` - "Two kinds of line", "Decided
vocabulary", "Rules that fell out of the review", and its companion spec
`TODO-20260924_osprey_log_readability-spec.html` / `-lines.csv` (583 emitting call sites, the
worklist; line numbers are for master `794cb6a5d8` - locate each site by its text).
`pwiz_tools/Osprey/docs/20-command-line.md` ("Log format") and `docs/21-user-facing-text.md` are
the rules as they now stand in the code.

## Scope

**Goes to RESX (user-facing):**
- Every default-tier log line: `LogInfo`, `LogWarning`, `LogError`, `ProgressReporter` headings,
  and the `Warning:` / `Error:` prefixes themselves (Skyline's translated prefixes; the ja / zh-CHS
  forms are already in `CommandStatusWriter.ERROR_PREFIXES`).
- The `--verbose` tier (a documented CLI flag; its calibration statistics are for a careful user).
- The `--model-diagnostics` CONSOLE lines (`[MODEL-DIAGNOSTICS]` prose after the tag).
- `--help` text: argument and group DESCRIPTIONS (already `Func<string>`, so a resource drops in).
  The generated `Documentation/Help/en/CommandLine.html` already has `en` in its path.
- Exception messages that reach the user through `Fatal error: {0}` / `Pipeline failed: {0}` and
  describe a user-correctable condition: file not found, unreadable or empty library, missing
  column at row N, unsupported format version, incompatible daily build, damaged intermediate
  file. Roughly 65 such throws in `Osprey.IO` and `Osprey/`.
- Enum display text: the `GetLocalizedString(this Enum)` extensions added in PR 1 use literal
  `LOCALIZED_VALUES` arrays (`FdrMethod`, `FdrLevel`, resolution, ...) - swap in resources, as
  Skyline's `Model/Export.cs` does. Add `Helpers.EnumFromLocalizedString` only where a value is
  user-typed; CLI values stay English tokens (`--resolution unit|hram|auto`).
- Every `CountText.Format` call is TWO resources (singular sentence, plural sentence).

**Stays verbatim English, `@"..."` (NOT resourced) - Brendan, 2026-09-26:**
- Developer-only diagnostics: anything reached only through `-d`, an `OSPREY_*` variable
  (`OspreyFileDiagnostics`, `PercolatorDiagnosticsDump`, `[BISECT]`, `[DIAG]`, `[MEM ...]`,
  `OSPREY_PASS2_VERIFY_WORKER`, `OSPREY_DUMP_*`, the co-assignment allocation tally ...).
- The machine channel: every tagged line (`[TASK]`, `[PATH]`, `[COUNT]`, `[TIMING]`, `[BENCH]`,
  `[STAGE-WALL]`, `[TRAIN]`) and every `LogKey` key.
- Text written into files for programs: column headings (TSV, parquet, blib, FDRBench input),
  JSON keys, `.osprey.task` validity keys, format-version tokens.
- Command-line argument NAMES and values, environment variable NAMES, file names and extensions
  inside otherwise-resourced strings (passed as `{0}` arguments).
- Internal-invariant exceptions (`InvalidOperationException` in `Osprey.ML`, `Matrix`, the
  reconciliation planner, etc.) and `ToString()` overrides, per STYLEGUIDE "Non-Localizable Text".

**Out of scope here:** the model-diagnostics HTML REPORT. Brendan: it will most likely get
per-language HTML template files (not RESX), one per language - separate work.

## Locale split (Brendan, 2026-09-26)

Text written for a PERSON uses the CURRENT culture: the log, `--help`, errors. In fr-FR the
thousands separator is a (narrow) space and the decimal separator a comma. Text written for a
PROGRAM uses the INVARIANT culture: every output file, every tagged machine-channel line.

- Osprey has never been run under anything but en-US. fr-FR is the culture that exposes the split
  (ja-JP and zh-CHS format numbers like en-US), so test under fr-FR as well as ja-JP.
- Known break (PR 1 code review): machine-channel lines format numbers with the current culture -
  `[STAGE-WALL] stage5: 12,3s` on de-DE / fr-FR, `{0:P0}` gives `1 %` / `%1`. About 80 call sites
  (`[TIMING]`, `[STAGE-WALL]`, `[TASK] :done ({1:F1}s)`, `[COUNT]` with `P0`). Only
  `LogKey.Format` is invariant today. Fix: an invariant-formatting overload for tagged lines
  (`log.LogInfo(tag, format, args)` formatting with `CultureInfo.InvariantCulture`), and move
  every tagged call site onto it.
- Audit every writer to a file for culture-sensitive formatting (TSV writers, `OspreyReportWriter`,
  FDRBench input, JSON sidecars, blib metadata strings, `ToString()` of doubles in keys).

## Mechanics

- One `Resources.resx` per assembly that emits user text: `Osprey.Core`, `Osprey.IO`,
  `Osprey.Scoring`, `Osprey.FDR`, `Osprey.Tasks`, `Osprey` (exe), named after the assembly so the
  generated classes are distinct (`OspreyCoreResources`, `OspreyTasksResources`, ...), as Skyline
  does with `ModelResources`, `MenusResources`. `Chromatography`, `ML`, `Diagnostics` emit no user
  prose and get none.
- Osprey is **net10.0 only** (the old TODO said multi-TFM; that is obsolete). Check in the
  `.Designer.cs` (`PublicResXFileCodeGenerator`; SDK projects need the `<EmbeddedResource
  Update=...><Generator>` / `<Compile Update=...><DependentUpon>` items so VS regenerates on save).
  `.ja.resx` / `.zh-CHS.resx` build satellite assemblies; the installer and standalone ZIP must
  ship the satellite folders.
- Keys follow Skyline's `Class_Method_Message_text_with_underscores` (what ReSharper's "Move to
  resource" produces). Designer properties in alphabetical order.
- `string.Format` stays; the resource holds the format string. Counts `{0:N0}` inside the resource.
- **Never capture a resource string in a static field** (CRITICAL-RULES) - tests switch culture
  in process.
- Runtime culture: mirror Skyline's internal `--culture <name>` (`CommandArgs.ARG_INTERNAL_CULTURE`,
  sets `CurrentCulture` and `CurrentUICulture`) so a run can be forced to `ja` / `fr-FR`. Default
  is the OS UI culture, as in Skyline.
- The `@` prefix carries meaning after this PR: verbatim = machine channel / developer, plain =
  resourced. PR 1's review found `@` used on some user-facing default lines (e.g.
  `@"Loading cross-run reconciliation files"`, `@"  {0}: {1:N0} precursors at {2:P1} run-level FDR"`);
  fix as each string is resourced.

## Enforcement (Skyline's own)

- `Osprey.sln.DotSettings` inherits `LocalizableElement = WARNING`, but no Osprey project opts in.
  Add a `<Project>.csproj.DotSettings` beside each of the six projects with Skyline's two lines
  (`Localization/Localizable = Yes`, `Localization/LocalizableInspector = Pessimistic`) IN THE
  SAME COMMIT that resources the last string in that project, so `Build-Osprey.ps1 -RunInspection`
  never has a red interval. From then on any plain `"..."` literal fails the gate.
- Translation-proof tests (`ai/TESTING.md`): every `Osprey.Test` assertion on prose moves to the
  resource constant, a tagged line, or a flag/file name. Tighten `CommandLineErrorTest` to exact
  messages: `string.Format(OspreyResources.X, arg)` against the same resource the code uses, as
  Skyline's `CommandLineTest` does (Brendan, 2026-09-25).
- Locale switch for the test project: an `AssemblyInitialize` reading `OSPREY_TEST_CULTURE`
  (Osprey runs under `vstest.console`, not Skyline's `TestRunner /locale`); `Build-Osprey.ps1
  -RunTests` gains a way to run the suite under `ja-JP` and `fr-FR` too. A seed `.ja.resx` with a
  few machine-translated strings is enough to make an English-literal assertion fail.
- Step 6 guard (`CodeInspectionTest`): scan the English `.resx` VALUES for banned vocabulary:
  `sidecar`, `entry`/`entries`, `bundle`, `stratum`, `base_id`, `hydrat`, `compaction`,
  `survivor`, `stubs`, `scalars`, `frozen`, `projection`, `byproduct`, `interned`, `resident`,
  `Stage [1-7]`, `OSPREY_[A-Z_]+` (except where the message is about a variable the user set),
  `\w+\.cs`, `\w+Task\b`, `Run\w+\(`, and `(s)` plurals.
- Numeric format guard: every integer argument of a log / progress / exception format carries an
  explicit format (`N0`, `D`, ...). Start of a scanner in `ai/.tmp/sessions/20260924-01355z/fmtfix/`.

## The error-path sweep (the reason this is a string-by-string PR)

PR 1's log reviews read only lines that PRINTED, so warnings, errors and exceptions on paths no run
reached still carry developer vocabulary. PR 1 swept "sidecar" and "hydrate" (`8422c59eca`); a grep
found ~100 more literals with stubs / base_ids / compaction / survivors / Stage N / stratum /
bundle, plus entry/entries. Brendan's call (2026-09-26): review every string as it is resourced,
with the Step 6 guard as the enforcement. Also check each REMEDY a message gives: PR 1's review
found four that could not work. Known-good remedy for a stale first pass: "delete this analysis's
*.FirstPassFDR.osprey.task files and run the first pass again" (re-running `--task FirstPassFDR`
over current stamps does nothing).

**Carried over from PR 1:**
- User-correctable exceptions that still print an exception TYPE, e.g. a blib that cannot be
  opened prints `Pipeline failed: ... SQLiteException ... CantOpen`. Catch at the boundary and
  report the condition.
- Open wording question for Brendan: drop "Computing second-pass FDR scores for N files." when
  the "Second-pass FDR over N files: ..." line follows it (straight-through protein-compact).
- Open wording question for Brendan: merge "Loading spectral library from <path>..." and
  "Parsing <file>..." (now both always print).

## Plan (each step independently green)

1. **Infrastructure on `Osprey.Core`**: its `.resx` + Designer, csproj items, the `--culture`
   argument, the test-culture switch, invariant formatting for tagged lines. Move Core's strings
   (CountText callers there, `CommandStatusWriter` prefixes stay in CommonUtil). DotSettings opt-in.
2. **Per project in dependency order**: `IO`, `Scoring`, `FDR`, `Tasks`, exe. For each: resource
   every user-facing string (reviewing wording and remedy), mark the rest `@"..."`, convert test
   assertions, add the DotSettings, `Build-Osprey.ps1 -RunTests -RunInspection`.
3. **Locale split audit** of every file writer; fr-FR regression (acceptance below).
4. **Guards**: banned vocabulary over `.resx`, explicit integer formats.
5. **Pipeline**: run `MakeResourcesDb.bat` once and confirm the Osprey `.resx` files are picked
   up (`ai/docs/translation-guide.md`); satellite folders in the ZIP and MSI.
6. Docs: a "Localization" section in `pwiz_tools/Osprey/docs/20-command-line.md` pointing at the
   translation guide; update `docs/21-user-facing-text.md` for resources.
7. `/code-review` BEFORE opening the PR, by project (the whole-diff review of #4718 died on
   "Prompt is too long" at 73 files - pass a path per run), then the PR.

## Acceptance

- `Build-Osprey.ps1 -RunTests -RunInspection` green with the six `.csproj.DotSettings` in place:
  zero `LocalizableElement` warnings, no un-resourced plain literal.
- Unit tests green under `OSPREY_TEST_CULTURE=ja-JP` and `fr-FR` as well as `en-US`.
- `regression-parallel.ps1 -Dataset All` green; `regression.ps1 -Dataset Stellar` green with
  Osprey run under `--culture fr-FR`, every output file byte-identical to the en-US golden while
  the log shows fr-FR numbers.
- The Step 6 guard finds zero banned words in the English `.resx` values.
- `MakeResourcesDb.bat` picks up the Osprey resx files; ZIP and MSI include `ja` / `zh-CHS`.

## Progress

**2026-09-26**
- Plan written by the #4718 session. Branch created in `C:\proj\pwiz-work2` (Brendan approved)
  from `origin/Skyline/work/20260924_osprey_log_readability` at `8422c59eca` and pushed;
  pwiz-work1 stays on #4718.
  **Next session handoff**: For detailed startup protocol, read
  `ai/.tmp/handoff-20260926_osprey_resx.md` before starting work.
