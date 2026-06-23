# TODO: OspreySharp — adopt the PortableUtil declarative CLI-arg framework (declarative args + generated help)

## Branch Information
- **Branch**: `Skyline/work/20260622_ospreysharp_cli_args_adoption`
- **Base**: `master`
- **Created**: 2026-06-22
- **Status**: In Progress
- **PR**: (pending)
- **Depends on**: Phase A PR [#4322](https://github.com/ProteoWizard/pwiz/pull/4322) (merged) — PortableUtil now on master

**Status**: In Progress (Phase B of two-phase sprint)
**Priority**: Medium — removes the hand-rolled `switch` parser + the separately hand-maintained
`PrintUsage` (which drifts from the parser), giving a single source of truth and drift-proof
generated help (ascii / unicode / HTML).
**Type**: OspreySharp refactor (behavior-preserving; gate on the Stellar regression)
**Source**: 2026-06-22 planning session with Brendan on unifying OspreySharp's CLI with Skyline's
declarative `CommandArgs` model.
**Sequencing**: This is **Phase B**. It **DEPENDS ON Phase A**
(`TODO-portableutil_cli_args_framework.md`) being merged first — the `PortableUtil` DLL and the
generic `Argument<TContext>` / `NameValuePair` / `ArgumentGroup<TContext>` / `IUsageBlock` /
`ConsoleTable` it provides must exist. Do not start until Phase A is on master.

## Context / why

OspreySharp's CLI is a hand-rolled `while`/`switch` over `argv` in `Program.cs` (~lines 214-580),
with a separate hand-written `PrintUsage` (~796-865) of literal `Console.Error.WriteLine` lines that
can drift from the parser, ~25 flags, and no generated/multi-format help. Phase A extracts Skyline's
declarative framework into `PortableUtil`; this phase adopts it in OspreySharp so the args are
declared once and the help is generated (can't drift), with ascii/unicode/HTML output like Skyline.
**CLI args only** — the ~90 `OSPREY_*` environment variables are explicitly out of scope.

This is a refactor: keep the exact current CLI behavior (same flags, same `OspreyConfig` population,
same task-aware validation, same exit codes). The win is structure + generated help, gated by the
Stellar regression behaving byte-identically.

## What to build

### 1. New `OspreySharp/OspreyCommandArgs.cs` (namespace `pwiz.OspreySharp`, exe project)
- `OspreyCommandArgs` **is the `TContext`** for `Argument<OspreyCommandArgs>` — mirrors Skyline's
  controller pattern. Holds the static arg declarations, the `ArgumentGroup` list, raw parse-sink
  fields, and `ToConfig()` which runs today's `ParseArgs` epilogue (resolution / work-dir /
  fragment-unit defaults) so `OspreyConfig` population stays **byte-identical**.
- Expose `internal static OspreyConfig ParseArgs(string[] args)` with the **same signature** the
  existing `ProgramTests` already call, so those tests keep compiling.

### 2. Keep OspreySharp's own tokenizer (do NOT adopt Skyline's `=`-only grammar)
The framework's `Argument.Parse` only understands `--name` / `--name=value`. OspreySharp needs short
aliases (`-i`), space-separated values (`--name value`), variadic consumption (`-i a b c`,
`--input-scores …`), and positional-file fallback — forcing those onto `--name=value` would change
the CLI surface and break the Stellar gate. So OspreySharp keeps a small `TokenizeAndDispatch(args)`
that resolves each token to a declared `Argument` and calls its
`ProcessValue(this, new NameValuePair(name, value))`. Reuse the framework for **declaration,
`NameValuePair` coercion, grouping, and help rendering only**.
- Two small descriptor extensions: add **`ShortName`** to `Argument<T>` in PortableUtil (broadly
  useful; Skyline could use it too — coordinate with whoever picks this up if Phase A didn't add it).
  Keep **`Variadic`** as an OspreySharp-local `OspreyArgument : Argument<OspreyCommandArgs>` property
  (greedy multi-token consumption is a quirk the shared grammar shouldn't carry).
- Enum aliases (`th`/`da`→`mz`) and warn-and-default enums (`--fdr-method`, `--fdr-level`,
  `--shared-peptides`) stay in the `ProcessValue`/epilogue with `HasValueChecking=true` so the
  framework doesn't reject them (preserving the exact warning strings).

### 3. Argument groups + `--help` UX
Six `ArgumentGroup`s: **General I/O** (`-i/--input`, `-l/--library`, `-o/--output`, `--work-dir`,
`--output-dir`, `--cache-dir`, `--report`) · **Scoring & Tolerance** (`--resolution`,
`--fragment-tolerance`, `--fragment-unit`, `--no-prefilter`) · **FDR & Protein Inference** (`--run-fdr`,
`--experiment-fdr`, `--protein-fdr`, `--fdr-method`, `--fdr-level`, `--shared-peptides`) · **Decoys**
(`--decoys-in-library`, `--decoy-pairing-manifest`, `--write-pin`) · **Distributed / HPC** (`--task`,
`--input-scores`, `--threads`) · **Diagnostics & Info** (`-d/--diagnostics`, `-h/--help`,
`-v/--version`). Plus leading/trailing `ParaUsageBlock`s (tagline + synopsis, and the EXAMPLES / HPC
prose from today's `PrintUsage`).
`--help` (or no args) → ascii tables; `--help unicode` → unicode (the framework's no-borders renderer
under the friendlier name); `--help sections`; `--help html` → `GenerateUsageHtml()`;
`--help <Section>` → section filter.

### 4. Program.cs surgery
- **Replace:** the `ParseArgs` switch body (→ thin `OspreyCommandArgs.ParseArgs` facade + tokenizer),
  `RequireValue`/`ParseDouble` (fold into the tokenizer + `NameValuePair` coercion), and `PrintUsage`
  (entirely → generated help). This is the drift-elimination win.
- **Keep unchanged:** `Main`'s `--task` pre-scan + membership flags; `ValidateArgs` (stays the
  post-parse, task-aware validator — do NOT force it into `ArgumentGroup.Validate`); `ResolveTask`;
  `ResolveInputScores` (still invoked from the `--input-scores` lambda during parse); logging; the
  top-level `catch`; `-h`/`-v` exit-0 behavior.

### 5. Descriptions: inline strings through the seam (no resx yet)
Construct `OspreyCommandArgs` with an `IArgDescriptionProvider` defaulting to an inline-literal
provider (a `static Dictionary<string,string>` keyed by arg name). OspreySharp text isn't localized
yet; routing through the seam means swapping in a resx later is a one-line change with no edits to the
declarations or the drift test.

### 6. sln + csproj plumbing
- `OspreySharp/OspreySharp.csproj`: add
  `<ProjectReference Include="..\..\Shared\PortableUtil\PortableUtil.csproj" />` (exe project only).
- Add PortableUtil to `OspreySharp.sln` with Debug/Release × AnyCPU/x64/x86 rows (x86→AnyCPU),
  `Platforms=AnyCPU;x64`. `OspreySharp.Test` already has `InternalsVisibleTo`, so `OspreyCommandArgs`
  is testable.

## Tests (`OspreySharp.Test`)
- Keep existing `ProgramTests.cs` (ValidateArgs / ResolveTask / ResolveInputScores / retired-flag
  rejection all survive). Add `OspreyCommandArgsTests.cs`:
  - (a) **Table-driven arg→config mapping** — one row per flag asserting the parsed `OspreyConfig`
    field (incl. variadic `-i a b c`, `--work-dir` fan-out + override, `--resolution unit` injected
    defaults, `--fragment-unit th/da/mz/ppm`, warn-and-default enums, `--task=MergeNode`). The
    regression net proving the rewrite reproduces the old switch exactly.
  - (b) **Drift killer** — every non-internal `Argument` is in exactly one group AND resolves a
    non-empty description; fails the build if an arg is added without grouping/documenting it.
  - (c) **ascii help golden** snapshot + cheap smoke for `--help sections/unicode/html`.
  - (d) short-alias equivalence (`-i`==`--input`, etc.) + the existing missing-value-throws cases.

## Verification
- `ai/scripts/OspreySharp/Build-OspreySharp.ps1 -RunTests -RunInspection` (builds net472 + net8.0,
  runs the new arg tests, zero inspection warnings).
- `pwiz_tools/OspreySharp/regression.ps1 -Dataset Stellar` — **byte-identical output gate**: the
  committed golden blib must be unchanged (proves the CLI behaves identically after the rewrite).
- Manual spot-checks on the built exe: `osprey --help [ascii|unicode|sections|html]`, `osprey`
  (no args → usage + exit 1), `osprey -v`.
- One pwiz PR through the standard review chain (`/pw-self-review` → PR → Copilot → optional ultrareview).

## Acceptance criteria
- OspreySharp parses its ~25 args declaratively via the PortableUtil framework; `Program.cs`'s switch
  and `PrintUsage` are gone; help is generated (ascii/unicode/sections/html) and cannot drift.
- `OspreyConfig` population, task-aware validation, and exit codes are unchanged; Stellar regression
  golden unchanged.
- Build green (net472 + net8.0), inspection clean, new arg tests pass.

## Critical files
- New: `pwiz_tools/OspreySharp/OspreySharp/OspreyCommandArgs.cs`,
  `pwiz_tools/OspreySharp/OspreySharp.Test/OspreyCommandArgsTests.cs`.
- Modify: `pwiz_tools/OspreySharp/OspreySharp/Program.cs` (remove ParseArgs internals + PrintUsage),
  `OspreySharp.sln`, `OspreySharp/OspreySharp.csproj`.
- Reference (unchanged target of the mapping): `pwiz_tools/OspreySharp/OspreySharp.Core/OspreyConfig.cs`.

## Full plan reference
The combined two-phase plan (Phase A + this) was authored at
`~/.claude/plans/okay-now-i-would-melodic-fog.md` (2026-06-22 planning session).
