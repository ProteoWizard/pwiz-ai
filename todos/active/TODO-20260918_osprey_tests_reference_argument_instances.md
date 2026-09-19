# TODO-20260918_osprey_tests_reference_argument_instances.md

## Branch Information
- **Branch**: `Skyline/work/20260918_osprey_tests_reference_argument_instances`
- **Base**: `Skyline/work/20260612_net8_port` (all Osprey development moved there 2026-09-18)
- **Created**: 2026-09-18
- **Status**: PR #4686 green on all TeamCity configs at `c8b5c0783a` (Osprey Win 592, Core Win 644, Skyline Win 1,799); waiting on review
- **Module**: `osprey` (a few lines land in `pwiz_tools/Shared/CommonUtil`, behavior-neutral for Skyline)
- **PR**: [#4686](https://github.com/ProteoWizard/pwiz/pull/4686) (opened 2026-09-18)
- **Worktree**: `C:\proj\pwiz-work2`
- **Requester/Reporter**: none - raised by Brendan 2026-09-18 while reviewing [#4660](https://github.com/ProteoWizard/pwiz/pull/4660)

# Osprey tests reference the Argument instances, and `ARG + value` works for a space-separated CLI

## The idea

Osprey uses `CommonUtil`'s `Argument` / `ArgumentBase` classes, the same ones Skyline uses, and
Skyline settled the test idiom long before Osprey was written: tests name the argument INSTANCE
(`CommandArgs.ARG_IN`) and build the token with the `+` operator (`CommandArgs.ARG_IN + docPath`),
see `pwiz_tools/Skyline/TestData/CommandLineImportTest.cs`. Osprey's tests do neither.

Measured 2026-09-18 on the port branch, `pwiz_tools/Osprey/Osprey.Test`:

| File | bare `@"--..."` | bare `-i` / `-l` / `-o` | `ARG_*` references |
|---|---:|---:|---:|
| `OspreyCommandArgsTests.cs` | 76 | 16 | 0 (1 test converted in #4660) |
| `ProgramTests.cs` | 19 | 15 | 0 |
| `LibraryFragmentReleaseTest.cs` | 7 | 0 | 0 |
| `PipelineMembershipTest.cs` | 2 | 0 | 0 |

135 literals, 0 references. The product side has the same habit: all 7 `ParseDouble` /
`ParseInt` sites in `OspreyCommandArgs.cs` pass `@"--threads"`-style literals for their error
messages, although the lambda already holds the matched instance's name in `p.Name`.

#4660 converted only its own new test (`TestBadOptionValuesAreUsageErrors`) to the instances,
through `ArgumentBase`'s implicit `string` conversion, because the `+` operator cannot be used
in Osprey today - see the consistency bug below. The rest is this TODO.

## Why `ARG + value` does not work in Osprey today - a consistency bug in the shared class

`ArgumentBase.GetArgumentTextWithValue` (what `operator +` calls) hard-codes
`ArgumentText + '=' + value`, so `ARG_THREADS + "8"` renders `--threads=8`. Osprey's
`OspreyCommandArgs.ParseArgs` is space-separated: `FindByToken` matches a whole token against
`--name` / `-x`, and the only `=` form it accepts is the `--task=Name` pre-scan in `Program.Main`.

The shared class ALREADY has the process-wide switch for this: `ArgUsage.ArgumentValueSeparator`
(static, default `"="`), which `ArgumentDescription` uses to render usage text, and which Osprey's
static constructor sets to `" "` so `--help` prints `--threads <count>`. Only
`GetArgumentTextWithValue` ignores it. Brendan, 2026-09-18: the global property is the right
shape because the separator is a process-wide decision, and `Argument` must already know it to
generate correct documentation - the operator not honoring it "is just a consistency bug".

## Agreed design (2026-09-18)

1. **`GetArgumentTextWithValue` honors `ArgUsage.ArgumentValueSeparator`** instead of `'='`.
   One line in `pwiz_tools/Shared/CommonUtil/CommandLine/ArgumentBase.cs`; Skyline keeps `=`.
   Do NOT add a second, per-instance property - a host has one convention.

2. **`operator +` takes `object`, not `string`**, and formats it with `ToString()`:
   `ARG_THREADS + 8` reads better than `ARG_THREADS + "8"`, and a double renders in the CURRENT
   culture the way a user would type it, so tests automatically follow a decimal-separator
   change. Two facts make this more than readability:
   - `ARG_THREADS + 8` already COMPILES today: the user-defined `+(ArgumentBase, string)` is not
     applicable to an `int`, so C# falls back to the predefined `string + object` through the
     implicit string conversion and silently yields `"--threads8"`. The `object` overload routes
     it through `GetArgumentTextWithValue` instead.
   - Skyline's own tests already work around it: `ARG_PEPTIDE_ADD_MOD + phosMod.UnimodId.ToString()`,
     `ARG_PEPTIDE_ADD_MOD_VARIABLE + false.ToString()` (4 + 3 sites). Every other `ARG + x` in the
     tree (grepped 2026-09-18) has a string right-hand side, so nothing depends on the fallback.
   - Trap to keep out: an `ArgumentBase` right-hand side `ToString()`s to `ArgumentDescription`
     (`--threads <count>`), and `null` must not NRE. `ARG_A + ARG_B` was already garbage with the
     string overload (`--a=--b`), so this is not a regression, but worth an assertion.

3. **`ParseArgs` splits a `--name value` single token** at the FIRST space when the prefix is a
   known option, before the existing loop, so the rest (variadic, optional value, `RequireValue`)
   is unchanged. Unambiguous - option names cannot contain spaces, so `--library C:\My Lib\x.blib`
   splits correctly - and harmless from a real shell, where a quoted `"--threads 8"` is one token
   that today fails as "Unknown argument". Decide whether to ALSO accept `--name=value` for users;
   that is a CLI feature, not part of this consistency fix, and untested capability is a liability.

4. **Convert the 135 test literals** to `OspreyCommandArgs.ARG_*`, using `+` wherever the value
   is fixed and valid. Same constraint Skyline lives with: `GetArgumentTextWithValue` throws
   `ValueUnexpectedException` for a pure flag and `ValueInvalidException` when a fixed `Values`
   list does not contain the value, so the invalid-value negative tests (`--fdr-method bogus`)
   keep `ARG.ArgumentText, @"bogus"` as two tokens. Short forms: `ARG_INPUT` renders `--input`,
   not `-i`; keep a couple of explicit `-i` / `-l` / `-o` literals where the SHORT form is the
   thing under test, and say so in the test.

5. **`ParseInt` / `ParseDouble` take the `NameValuePair`** (or the argument) and build the flag
   name from `ArgumentBase.ARG_PREFIX + p.Name`, dropping the 7 product-side literals.

## Localization caveat, deliberately out of scope

`ParseDouble` / `ParseInt` parse with `CultureInfo.InvariantCulture`. The day a test writes
`ARG_RUN_FDR + 0.01` under de-DE it will render `0,01` and fail - correctly exposing that the
parser must move to the current culture with it. That is part of the larger "make Osprey as well
behaved as Skyline in the face of non-US-English text" effort (Brendan: "a pretty large amount of
work ahead of us"), not this TODO. Until then, no Osprey test should pass a double through `+`.

## Verification

- `Build-Osprey.ps1 -SourceRoot <checkout> -Configuration Debug -RunTests -RunInspection`
  (pass `-SourceRoot`; the script defaults to `C:\proj\pwiz`).
- Skyline: `TestData\CommandLineImportTest.cs` and the other `RunCommand(... ARG_X + ...)` tests
  must be unchanged in behavior - `ArgUsage.ArgumentValueSeparator` is still `=` there.
- Osprey `--help` output unchanged (the separator was already honored there).
- Not output-affecting for Osprey runs; the regression gate is not engaged unless step 3 grows
  into accepting `=` for users.

## Progress Log

### 2026-09-18 - Implemented on the branch (`661761084f`, local)

Branch from the port tip `7bac992ee6` in `C:\proj\pwiz-work2`. Four files, +241/-131:

- `ArgumentBase.GetArgumentTextWithValue` joins with `ArgUsage.ArgumentValueSeparator`;
  `operator +(ArgumentBase, object)` formats with `Convert.ToString(value,
  CultureInfo.CurrentCulture)` and refuses an `ArgumentBase` right-hand side.
- `OspreyCommandArgs.SplitJoinedValues` runs before `TokenizeAndDispatch`: a token whose
  head is a declared option (long or short) and that contains the separator is split at
  the FIRST separator. `ParseInt` / `ParseDouble` take the `NameValuePair` and name the flag
  from `ArgumentBase.ARG_PREFIX + p.Name` (`InvalidValueMessage`); the 7 literals are gone.
- Tests: every parser token in `OspreyCommandArgsTests.cs` and `ProgramTests.cs` is an
  `ARG_*` instance (63 replacements in the first, a `RequiredIoThen` helper in the second).
  `+` wherever the value is fixed and listed; two tokens (`Parse(ARG_X, @"bogus")`) for the
  accepted-but-unlisted aliases `th`, `da`, `bogus`, `3`; the short-alias test derives `-i`
  from `ARG_INPUT.ShortName` via a `Short()` helper. The nine remaining `@"--task ..."`
  strings in `LibraryFragmentReleaseTest.cs` / `PipelineMembershipTest.cs` are assertion
  prose, not parser tokens, and were left.
- New `TestArgumentTokensFromInstances` pins the contract: separator rendering, first-space
  split with `C:\my dir\run.log`, Skyline's `=` under the same operator (set/restore),
  current-culture number rendering under a cloned invariant culture with `,` as decimal
  separator (no ICU dependency), and the three refusals.
- Gate: build, 599/599, inspection 0.

**Decisions made while implementing**

- FDR thresholds in tests stay strings (`ARG_RUN_FDR + @"0.05"`), ints go through `+` as
  numbers (`ARG_THREADS + 8`). Osprey's `ParseDouble` is invariant-only and stays so.
- Adopting `NameValuePair.ValueInt` / `ValueDouble` (the shared accessors, which already
  throw `UsageException : ArgumentException` with `ArgumentText`-carrying messages) was
  considered and deferred. Two behavior changes hide in it: `ValueDouble` parses
  local-first, and under a locale whose group separator is '.' `double.TryParse("0.01")`
  accepts the '.' as a thousands separator and returns **1** - an FDR threshold cannot
  afford that, and Skyline's own CLI carries the hazard today. And `IsMatch` enforces
  `Values`, where Osprey warns-and-defaults (`--fdr-method bogus`) and honors the
  `fasttree` alias. Also `ValueInt` catches `FormatException` only, so an overflow
  (`--threads 99999999999999999999`) would escape as a non-usage error. Worth its own PR
  as part of the locale work.
- `--name=value` for USERS is not added; the `=` pre-scan for `--task` is unchanged.

### 2026-09-18 - /code-review max, rework, PR #4686 opened (`b678c1a37b`)

The review returned 14 findings; the two it verified with the built exe changed the design.
The first cut split `"--name value"` tokens INSIDE `ParseArgs` on the premise that a quoted
single token "was Unknown argument before, so splitting is harmless". False on two counts:
`Program.Main` pre-scans the RAW argv for `--task`, so a quoted `"--task PerFileScoring"`
slipped past it, was consumed by the ARG_TASK branch, and the node ran the FULL pipeline
instead of the one HPC task (exit 1 on the base branch); and `"--no-prefilter false"` went
from a hard error to flag-plus-LogWarning. The only consumer of the split was the tests, so
it moved to a test-side `ArgTokens.Split` and the production tokenizer is byte-identical to
the base again (re-probed with the Debug exe: all three quoted tokens are `Unknown argument`).
The TODO's own "untested capability is a liability" standard applied to my own addition.

Accepted and applied from the rest: `ArgUsage.ValueFormatProvider` (Osprey sets invariant, so
`ARG_RUN_FDR + 0.05` renders `0.05` under any thread culture and the FDR tests use numbers);
null value refused; `HasValueChecking` honored by the builder and declared on
`fragment-unit`, `fdr-method`, `fdr-level`, `shared-peptides`, `fdrbench-pass` (aliases /
warn-and-default / own check) so ONE idiom covers every test; `[DoNotParallelize]` on the
static-mutating contract test and its comment corrected (CurrentCulture is per-thread);
`ArgumentBase.Parse` splits on the separator too; three stale "never reached" comments;
`ParseFdrBenchPass` and the `--task requires a value` message built from the declarations;
`ShortArgumentText` on `ArgumentBase` used by `ArgumentDescription`, `FindByToken` and the
alias test; and the literals the first `@"` sweep missed - plain `"-i"`/`"--task"` strings
in `ProgramTests.cs` 540-614 and `ArtifactPathsTest.cs`, plus the `ValidateArgs` message
assertions. The earlier "every parser token ... is an ARG_* instance" claim above was
premature; it is true as of `b678c1a37b`, with the retired `--no-join` / `--join-only` /
`--join-at-pass`, `--bogus-flag`, the deliberate `--task=` spelling and two assertion labels
left literal on purpose.

Dropped: the "memoize AllArguments" suggestion (moot once the split left production).

Gate on `b678c1a37b`: net10.0 build, 599/599, inspection 0. PR #4686 opened against the port
branch; `pwiz_tools/Shared` changed, so TeamCity runs the Skyline configs as well as Osprey's.

### 2026-09-18 - Brendan: task names are constants too (`df6c6169dd`)

Brendan, reviewing the PR: the repeated `"FirstPassFDR"` / `"PerFileRescoring"` strings in
`ProgramTests.cs` should be constants in the code, not literals. The product spelled them in
five places itself - `ARG_TASK`'s value list, `Program.ResolveTask` (six `string.Equals`), the
`HpcTask`-to-name switch, `AnalysisPipeline`'s name-to-stage map, each task's `Name`
(`PerFileRescoreTask` alone had a `TASK_NAME` const) plus two private consts in
`ModelDiagnosticsReport` - and the names are also the key `TaskValiditySidecar` stamps into
`.osprey.task`, so they are a contract with four readers.

Added `Osprey.Core/HpcTaskName.cs`: the six constants, `ALL` in `--help` order, `Of(HpcTask)`
(not `ToString()`: `FirstPassFdr` vs `FirstPassFDR`, `PerFileRescore` vs `PerFileRescoring`),
and a case-insensitive `TryParse`. Every product site reads it; `ResolveTask` collapsed to
`TryParse` with the valid-task list joined from `ALL`. Tests: `ProgramTests` (ValidateArgs
assertions and the `--task` tokens), `PipelineMembershipTest`, `LibraryFragmentReleaseTest`,
`TaskValidityKeyTest`, `IOTest`'s sidecar tests and the one `--task=` spelling all use the
constants; the six per-task `ResolveTask` tests, which pinned spellings that now live in one
constant, became one `TestResolveTask` round-trip over every `HpcTask` that also asserts
`ALL` covers the enum once and equals `ARG_TASK.Values`. No task-name literal remains in
product or test code (two doc-comment mentions aside; `OspreyTask.Name`'s now points at
`HpcTaskName`).

Gate on `df6c6169dd`: build, 592/592 (599 - 8 + 1), inspection 0.

### 2026-09-18 - Registry replaced by per-class TASK_NAME (`146faff9db`)

Brendan on `df6c6169dd`: not his favorite - `PerFileRescoreTask` had the right idea with
`public const string TASK_NAME` returned from `Name`, so a test writes
`PerFileRescoreTask.TASK_NAME` and there is no extra class to keep in step with the task
classes. Reworked: every `OspreyTask` declares its `TASK_NAME` and returns it from `Name`;
`--task ModelDiagnostics` has no task class (it re-runs the canonical pipeline with artifact
writes suppressed), so `ModelDiagnosticsReport.TASK_NAME` owns that one. `HpcTaskName.cs`
deleted. `ARG_TASK`'s value list is the six constants in `--help` order;
`Program.TaskCliName` (now internal, for the round-trip test) is the `HpcTask`-to-constant
switch; `ResolveTask` loops the enum through it case-insensitively and lists
`ARG_TASK.Values` in its error. Tests reference the class constants (36 sites).
Gate on `146faff9db`: build, 592/592, inspection 0. On `df6c6169dd` before the rework,
TeamCity Osprey Windows #689 (ID 4179214) and Osprey Linux both passed 592.

### 2026-09-18 - TeamCity Skyline caught the HasValueChecking bypass (`c8b5c0783a`)

`Skyline Windows .NET` build #288 (ID 4179223) on `146faff9db` failed ONE test:
`CommandLineRefineTest.ConsoleArgumentInvalidValuesTest` -> `ValidateInvalidValue`, "Exception
expected". That test iterates every Skyline argument with a `Values` list and asserts
`GetArgumentTextWithValue("NO VALUE")` throws `ValueInvalidException` - HasValueChecking or
not. So review finding 6 (honor HasValueChecking in the builder) contradicted a contract
Skyline's tests pin, and the "byte-identical for Skyline" claim was false for exactly those
arguments. Reverted the bypass; the builder is strict for every listed argument again, the
five `HasValueChecking = true` declarations are gone from Osprey's arguments, and the four
accepted-but-unlisted values (`th`, `da`, `bogus`, `3`) go back to two tokens in the tests
with the reason in a comment. Osprey gate: 592/592, inspection 0. Skyline verification is
the TeamCity run on `c8b5c0783a` - not run locally (a Skyline.sln build on this box is the
wrong trade for a one-line revert to base behavior; CI is ~70 min).

TeamCity on `c8b5c0783a`: Osprey Windows .NET 592, Core Windows .NET 644, Skyline Windows .NET
1,799 (`ConsoleArgumentInvalidValuesTest` included) - `ready_to_merge: true`. Osprey Linux
.NET passed 592 on the two previous heads and did not re-queue for the test-only Osprey delta.
