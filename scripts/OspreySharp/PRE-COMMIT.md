# OspreySharp Pre-Commit Validation

Required validation before committing OspreySharp changes.  The project
holds zero ReSharper warnings; the OspreySharp test suite is small
enough that the inspection completes in ~20 seconds.  Catching issues
here takes a few seconds; catching them after commit requires a
cleanup commit later.

## Required Pre-Commit Command

```powershell
pwsh -File ./ai/scripts/OspreySharp/Build-OspreySharp.ps1 -Configuration Debug -RunTests -RunInspection
```

This single command:

1. Builds `OspreySharp.sln` in Debug|x64
2. Runs the unit-test suite via `vstest.console.exe`
3. Runs `jb inspectcode` against `OspreySharp.sln.DotSettings`

Exit code 0 = safe to commit.  Non-zero = fix issues before committing.
Typical wall under 30 seconds from a warm incremental build.

Common LLM-introduced inspection findings (caught here, not after):

- `RedundantUsingDirective` (unused `using` left behind after edits)
- `RedundantExplicitArrayCreation` (`new double[] { ... }` -> `new[] { ... }`)
- `InvalidXmlDocComment` (`<see cref="..."/>` references that do not resolve)
- `NotAccessedField.Local` / `CollectionNeverQueried.Local` (dead code
  from incomplete refactors)

## Individual Validation Steps

```powershell
# Build only (fastest feedback)
pwsh -File ./ai/scripts/OspreySharp/Build-OspreySharp.ps1

# Build + unit tests
pwsh -File ./ai/scripts/OspreySharp/Build-OspreySharp.ps1 -RunTests

# Build + inspection only
pwsh -File ./ai/scripts/OspreySharp/Build-OspreySharp.ps1 -RunInspection
```

## C#-side Refactor / Algorithm Regression

Changes that touch scoring, calibration, LOESS, KDE, the SVM kernel,
FDR thresholds, decoy generation, or the blib write path must also
pass a regression gate.

### Preferred routine gate (C#-side changes, Rust unchanged)

The multi-file straight-through run that REUSES a cached Rust reference
(Rust is not re-run), comparing Stage 7 + blib at 1e-9.  Build the Rust
reference once per dataset, then reuse it with `-SkipRust` on every
iteration:

```powershell
# Stellar all-files, C#-only (cached Rust reused; ~minutes)
pwsh -File ./ai/scripts/OspreySharp/Compare/Compare-EndToEnd-Crossimpl.ps1 -Dataset Stellar -Files All -SkipRust

# Astral all-files, C#-only (~17 min)
pwsh -File ./ai/scripts/OspreySharp/Compare/Compare-EndToEnd-Crossimpl.ps1 -Dataset Astral -Files All -SkipRust
```

This is faster than the stage-isolated snapshot below AND exercises the
multi-file reconciliation / consensus-RT / multi-charge / gap-fill
machinery that single-file runs never touch.  Caveats: do NOT pass
`-Force` with `-SkipRust` (it wipes the cached `rust/`), and the cached
reference must match the `-Files` set or you get a false, gross-looking
FAIL that mimics a regression.  Re-run Rust (drop `-SkipRust`) only when
Rust itself changes.

### Alternative gate (no Rust checkout available)

The OspreySharp-alone snapshot gate compares the current build against a
frozen baseline -- no Rust required.  Slower (per-stage process restarts
+ dump overhead), so prefer the `-SkipRust` gate above for routine
checks.

```powershell
# Smoke (~3 min): Stellar single
pwsh -File ./ai/scripts/OspreySharp/Test-Full-Regression.ps1 -Smoke

# Quick (~10 min): Stellar + Astral single
pwsh -File ./ai/scripts/OspreySharp/Test-Full-Regression.ps1 -Quick

# Full (~70 min): Stellar + Astral all
pwsh -File ./ai/scripts/OspreySharp/Test-Full-Regression.ps1
```

If your change is intentional, refresh the baseline AFTER PR
approval:

```powershell
pwsh -File ./ai/scripts/OspreySharp/Test-Full-Regression.ps1 -CreateSnapshot
```

See [Test-Snapshot.ps1](Test-Snapshot.ps1) for the per-stage
comparator details, and [Test-Full-Regression.ps1](Test-Full-Regression.ps1)
for the wrapper.

## Cross-impl Regression (rare; for ports of Rust algorithm changes)

Only relevant when you also need to confirm OspreySharp hasn't
drifted from Rust osprey at the 1e-9 gate.  Requires a Rust checkout
(`<project root>/osprey` by default, override via `$env:OSPREY_ROOT`).

```powershell
# Stellar single (~5 min) -- quickest cross-impl sanity
pwsh -File ./ai/scripts/OspreySharp/Compare/Compare-EndToEnd-Crossimpl.ps1 -Dataset Stellar -Files Single

# Astral all (~45 min) -- stress test
pwsh -File ./ai/scripts/OspreySharp/Compare/Compare-EndToEnd-Crossimpl.ps1 -Dataset Astral -Files All -Force
```

See [Compare/README.md](Compare/README.md) for cross-impl usage.

## Setup Requirements

### ReSharper Command-Line Tools

Required for `-RunInspection`.  One-time install:

```powershell
dotnet tool install -g JetBrains.ReSharper.GlobalTools
where.exe jb   # expect: C:\Users\<you>\.dotnet\tools\jb.exe
```

The script errors with the install hint if `jb` isn't on PATH.

### Project Root

Helper functions in `Dataset-Config.ps1` resolve sibling repos
(`pwiz`, `osprey`) via:

1. `$env:OSPREY_PROJECT_ROOT` if set
2. Walking up from Dataset-Config's own location
3. `C:\proj` as a final fallback

Override per-repo paths via `$env:PWIZ_ROOT`, `$env:OSPREY_ROOT`,
`$env:OSPREY_MM_ROOT` if your checkouts don't share a single parent.

## Common Pitfalls

### Type-inference regression from auto-fixes

ReSharper's "remove redundant explicit array type" quick-fix can
break tests that depend on the explicit type.  See
`ai/STYLEGUIDE.md` "Array Literal Type Inference" for the rule on
when to keep the explicit type.

### Release-only warnings

Almost all warnings surface identically in Debug and Release.  A few
(unused parameters in release-specific branches) can differ.  If
you're about to ship a release, run once with `-Configuration Release`:

```powershell
pwsh -File ./ai/scripts/OspreySharp/Build-OspreySharp.ps1 -Configuration Release -RunInspection
```

## Exit Codes

- `0` -- all checks passed, safe to commit
- non-zero -- failures detected, fix before committing

## See Also

- [Build-OspreySharp.ps1](Build-OspreySharp.ps1) -- the validation script
- [Test-Snapshot.ps1](Test-Snapshot.ps1) -- same-impl regression engine
- [Test-Full-Regression.ps1](Test-Full-Regression.ps1) -- dual-dataset wrapper
- [Compare/README.md](Compare/README.md) -- cross-impl bridge
- [ai/STYLEGUIDE.md](../../STYLEGUIDE.md) -- coding conventions
- [ai/CRITICAL-RULES.md](../../CRITICAL-RULES.md) -- absolute constraints
- [ai/scripts/Skyline/PRE-COMMIT.md](../Skyline/PRE-COMMIT.md) -- Skyline counterpart
