# OspreySharp Pre-Commit Validation

**Required** validation steps before committing OspreySharp changes.
The project currently has zero ReSharper warnings and 186 passing unit
tests; these checks exist to keep it that way.

## Why This Matters

OspreySharp is small enough (~19K LOC) that the full ReSharper
inspection completes in **~20 seconds**, so there is no excuse to skip
it. LLM-assisted edits frequently introduce:

- `RedundantUsingDirective` (unused `using` left behind after edits)
- `RedundantExplicitArrayCreation` (`new double[] { ... }` -> `new[] { ... }`)
- `InvalidXmlDocComment` (`<see cref="..."/>` references that do not resolve)
- `NotAccessedField.Local` / `CollectionNeverQueried.Local` (dead code
  from incomplete refactors)

All of these have shown up in OspreySharp cleanup work. Catching them
before commit takes ~20 seconds; catching them after requires a
separate cleanup commit later.

## Required Pre-Commit Command

From anywhere in the repo, run:

```powershell
pwsh -File ./ai/scripts/OspreySharp/Build-OspreySharp.ps1 -Configuration Debug -RunTests -RunInspection
```

This single command performs all required validation:

1. Builds `OspreySharp.sln` in Debug|x64
2. Runs all 186 unit tests via `vstest.console.exe`
3. Runs `jb inspectcode` against `OspreySharp.sln.DotSettings`

**Exit code 0 = safe to commit. Non-zero = fix issues first.**

Typical wall-clock:

- Build: ~1-4 seconds
- Tests: ~1 second (186 tests, MSTest)
- Inspection: ~18-21 seconds (full solution)

Total under 30 seconds from a warm incremental build.

## Individual Validation Steps

Useful during fast iteration when you only need one check:

```powershell
# Build only (fastest feedback)
pwsh -File ./ai/scripts/OspreySharp/Build-OspreySharp.ps1

# Build + unit tests
pwsh -File ./ai/scripts/OspreySharp/Build-OspreySharp.ps1 -RunTests

# Build + inspection only
pwsh -File ./ai/scripts/OspreySharp/Build-OspreySharp.ps1 -RunInspection
```

## Parity Regression (before any algorithm-affecting change)

Changes that touch scoring, calibration, LOESS fitting, or feature
extraction must also pass the cross-implementation parity gate. This
is NOT part of the pre-commit command because it requires ~2 minutes
for Stellar and ~18 minutes for Astral, and requires large external
test datasets that live on the developer workstation.

```powershell
# Stellar (small, fast, ~2 min including Rust baseline)
pwsh -File ./ai/scripts/OspreySharp/Test-Features.ps1 -Dataset Stellar

# Astral (big, slow, ~18 min including Rust baseline)
pwsh -File ./ai/scripts/OspreySharp/Test-Features.ps1 -Dataset Astral

# Skip the Rust run if a previous run's output is still on disk
pwsh -File ./ai/scripts/OspreySharp/Test-Features.ps1 -Dataset Astral -SkipRust
```

All 21 PIN features must remain bit-identical at the 1E-06 threshold.

## Setup Requirements

### ReSharper Command-Line Tools

Required for `-RunInspection`. One-time install:

```powershell
dotnet tool install -g JetBrains.ReSharper.GlobalTools
```

Verify:

```powershell
where.exe jb
# Should print a path like C:\Users\<you>\.dotnet\tools\jb.exe
```

The script gracefully errors with the install hint if `jb` is not on
PATH.

## Common Pitfalls

### Type-inference regression from auto-fixes

ReSharper's "remove redundant explicit array type" quick-fix can break
tests that depend on the explicit type. Session 18 caught this in
`MLTest.TestMatrixSlice` where `CollectionAssert.AreEqual(new[] { 1, 2, 1 },
row0)` compared `int[]` against `double[]` after the fix stripped
`new double[]`. See `ai/STYLEGUIDE.md` "Array Literal Type Inference"
for the rule on when to keep the explicit type.

### Release-only warnings

Almost all warnings surface identically in Debug and Release. A few
(unused parameters in release-specific branches) can differ. If you're
about to ship a release, run once with `-Configuration Release` too:

```powershell
pwsh -File ./ai/scripts/OspreySharp/Build-OspreySharp.ps1 -Configuration Release -RunInspection
```

## Exit Codes

- **0** -- all checks passed, safe to commit
- **non-zero** -- failures detected, fix before committing

## See Also

- [Build-OspreySharp.ps1](Build-OspreySharp.ps1) -- the validation script
- [Test-Features.ps1](Test-Features.ps1) -- cross-impl parity gate
- [Bench-Scoring.ps1](Bench-Scoring.ps1) -- performance benchmark
- [ai/STYLEGUIDE.md](../../STYLEGUIDE.md) -- coding conventions
- [ai/CRITICAL-RULES.md](../../CRITICAL-RULES.md) -- absolute constraints
- [ai/scripts/Skyline/PRE-COMMIT.md](../Skyline/PRE-COMMIT.md) -- Skyline counterpart (slower, different suite)
