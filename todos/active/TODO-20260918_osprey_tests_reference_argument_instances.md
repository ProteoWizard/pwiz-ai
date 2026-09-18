# TODO-20260918_osprey_tests_reference_argument_instances.md

## Branch Information
- **Branch**: `Skyline/work/20260918_osprey_tests_reference_argument_instances`
- **Base**: `Skyline/work/20260612_net8_port` (all Osprey development moved there 2026-09-18)
- **Created**: 2026-09-18
- **Status**: In Progress
- **Module**: `osprey` (a few lines land in `pwiz_tools/Shared/CommonUtil`, behavior-neutral for Skyline)
- **PR**: (pending)
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
