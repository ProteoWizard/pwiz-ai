# TODO-shared_commandargs_declarative_dependencies.md

## Summary
Lift Skyline `CommandArgs`'s declarative argument-dependency enforcement (and the
group-level `Validate` hook) **into the shared `PortableUtil` CommandLine parser**, so
the `ArgumentGroup<TContext>.Dependencies` / `.Validate` slots that Osprey already
inherits actually fire. Today those slots exist on every `ArgumentGroup<TContext>` but
nothing reads them outside Skyline, so Osprey must hand-roll imperative cross-argument
checks that would be one declarative line in Skyline.

**Status**: Backlog (not started). **Type**: Shared CLI-infra refactor (PortableUtil).
**Origin**: `/pw-review 4337` discussion with Brendan, 2026-06-29.

## Background: the slot exists, the enforcement doesn't
The shared grammar (extracted from Skyline's `CommandArgs`) already exposes the
declarative slots on the generic group, which `ArgumentGroup<OspreyCommandArgs>` inherits:
- `pwiz_tools/Shared/PortableUtil/CommandLine/ArgumentGroup.cs:50` —
  `IDictionary<Argument<TContext>, Argument<TContext>> Dependencies`
- `:52` — `Func<TContext, bool> Validate`

But the **enforcement** never came across. It lives only in Skyline-specific code:
`CommandArgs.ValidateArgs()` (`CommandArgs.cs:2659-2685`) walks every group's
`Dependencies`, and for any seen argument whose prerequisite wasn't seen calls
`WarnArgRequirement(...)` to emit the standard "`--X` requires `--Y`" message. The shared
`PortableUtil/CommandLine` parser has **zero** references to `Dependencies`/`Validate`
beyond the property declarations, and the entire Osprey tree has zero references to either.

Net: in Osprey, `Dependencies = { { ARG_A, ARG_B } }` compiles and **silently does
nothing**. Both the dependency map and the `Validate` hook are inert.

## Motivating case
PR #4337 (Osprey `--fdrbench` / `--fdrbench-per-run`) needed "`--fdrbench-per-run`
requires `--fdrbench`". Because the declarative path is inert in Osprey, it used an
imperative check in `OspreyCommandArgs.ToConfig()`:
```
if (_config.FdrBenchPerRun && string.IsNullOrEmpty(_config.OutputFdrBench))
    Program.LogWarning("--fdrbench-per-run is set without --fdrbench; ...");
```
In Skyline this is a one-liner: `Dependencies = { { ARG_FDRBENCH_PER_RUN, ARG_FDRBENCH } }`.
The imperative form is the correct pragmatic choice *today* — this TODO is what makes the
declarative form available so future Osprey arg dependencies are free.

## Scope / design
- Move the dependency-walk and the `group.Validate` invocation out of
  `CommandArgs.ValidateArgs()` into the shared parser (the `PortableUtil` type that owns
  `UsageBlocks` / the parsed `_seenArguments` set), iterating `ArgumentGroup<TContext>`
  blocks generically.
- Port the warning text. Skyline's `WarnArgRequirement` text is `.resx`-backed; the shared
  parser must emit through a seam, not a hardcoded string. Osprey already has one:
  `OspreyArgUsageProvider : IArgUsageProvider` carries the message hooks (see the
  `Value*Message` members). Add a "requires" message to that provider interface so each
  consumer supplies its own localized/inline text. (Osprey diagnostic text is not localized
  yet — inline is fine there; Skyline routes to `.resx`.)
- Skyline's `ValidateArgs()` then delegates to the shared walk (keep its `.resx` text via
  the provider) so Skyline behavior is unchanged.
- Replace Osprey's imperative `--fdrbench-per-run` check with a `Dependencies` entry on
  `GROUP_FDR`, validating the wiring end-to-end.

## Considerations
- **Warn vs. hard-fail.** Skyline *warns* and proceeds (the dependent arg is simply
  ignored). Preserve that default; only escalate to a hard error where proceeding would
  produce silently-invalid output (cf. [[feedback_hard_fail_over_warn_proceed]]). The
  `--fdrbench-per-run`-without-`--fdrbench` case is a benign no-op, so warn is right.
- **The `Validate` hook is separately inert in Osprey too** — wire both `Dependencies` and
  `group.Validate` in the same pass so neither is a silent trap for the next author.
- **No behavior change for Skyline** is the gate: same warnings, same order. Add/keep a
  CommandArgs test asserting the dependency warning still fires.

## Gate
Skyline solution build + the `CommandArgs` dependency/validation tests (no behavior change);
Osprey pre-commit (`Build-Osprey.ps1 -Configuration Debug -RunTests -RunInspection`) with
the converted `Dependencies` entry. Shared `PortableUtil` change also rebuilds AutoQC /
SkylineBatch consumers (see [[reference_sdk_project_pinned_guid]]).
