# OspreySharp Scripts

Build, test, profile, and (occasionally) cross-impl-compare OspreySharp.
All scripts default to `-Dataset Stellar` with `-Dataset Astral` and
`-Dataset AstralLibraryDecoy` as alternatives.  Dataset-specific paths
and resolution flags live in [`Dataset-Config.ps1`](Dataset-Config.ps1),
which also exposes project-root helpers (`Get-PwizRoot`,
`Get-OspreySharpExe`, etc.) so nothing here hard-codes `C:\proj`.

## Layout

```
ai/scripts/OspreySharp/
  README.md                     (this file)
  DIAGNOSTICS.md                env-var reference for OSPREY_DUMP_*
  PRE-COMMIT.md                 pre-commit + pre-PR validation gates

  Build-OspreySharp.ps1         build the .sln (+ optional tests/inspection/coverage)
  Summarize-Coverage.ps1        summarize a dotCover JSON report (whole-project)
  Run-Osprey.ps1                run OspreySharp or Rust osprey on a dataset
  Dataset-Config.ps1            dataset definitions + path helpers
  Clean-TestData.ps1            wipe caches / diagnostic dumps

  Test-Snapshot.ps1             OspreySharp same-impl regression gate
                                (frozen-baseline byte-equality per stage)
  Test-Full-Regression.ps1      wrapper: Stellar + Astral, smoke/quick/full

  Measure-Pipeline.ps1          perf table generator (Osprey-workflow.html)
  Profile-OspreySharp.ps1       dotTrace wrapper for OspreySharp
  Profile-Stage5.sh             isolated Stage 5 profile (WSL)
  Combine-Stage5-Profile.ps1    merge dotTrace + samply outputs into a table
  samply-to-csv.py              samply JSON -> flat per-function CSV

  Compare/                      cross-impl bridge (used rarely now)
    README.md                   when/how to use the cross-impl gate
    Build-OspreyRust.ps1
    Compare-EndToEnd-Crossimpl.ps1
    Compare-Stage7-Crossimpl.ps1
    Compare-Blib-Crossimpl.ps1
    archive/                    historical sprint-specific tools (26 scripts)
```

OspreySharp is the primary implementation; the Compare/ folder is the
bridge for the rare "did this change drift us from Rust?" question.
The rest of this README focuses on the OspreySharp-primary workflow.

## Build

```powershell
# Build (Release, all projects)
pwsh -File ./ai/scripts/OspreySharp/Build-OspreySharp.ps1

# Build + run all unit tests
pwsh -File ./ai/scripts/OspreySharp/Build-OspreySharp.ps1 -RunTests

# Build + ReSharper inspection (zero-warning gate)
pwsh -File ./ai/scripts/OspreySharp/Build-OspreySharp.ps1 -RunInspection
```

See [PRE-COMMIT.md](PRE-COMMIT.md) for the full pre-commit gate.

## Coverage

`-Coverage` runs the unit tests under JetBrains dotCover and exports a
JSON report; `Summarize-Coverage.ps1` turns that JSON into a
whole-project picture (overall %, per-assembly table, most-uncovered
types, zero-coverage types). This is the measured complement to the
by-eye `/pw-test-review` — run it first to ground the review in actual
numbers.

```powershell
# Build + run all unit tests under dotCover, export coverage JSON
pwsh -File ./ai/scripts/OspreySharp/Build-OspreySharp.ps1 -Coverage

# Summarize the exported JSON (path is printed at the end of the run)
pwsh -File ./ai/scripts/OspreySharp/Summarize-Coverage.ps1 `
  -CoverageJsonPath ai/.tmp/osprey-coverage-<timestamp>.json
```

Coverage spans the `OspreySharp.*` production assemblies; the
`OspreySharp.Test` assembly is excluded. The `.json` and `.dcvr`
snapshot land in `ai/.tmp/`; import the `.dcvr` in Visual Studio
(ReSharper > Unit Tests > Coverage > Import from Snapshot) for
line-by-line detail. Requires the dotCover command-line tool
(`dotnet tool install -g JetBrains.dotCover.CommandLineTools`).

## Run

```powershell
# Run OspreySharp on Stellar single file (default)
pwsh -File ./ai/scripts/OspreySharp/Run-Osprey.ps1

# Astral all-files
pwsh -File ./ai/scripts/OspreySharp/Run-Osprey.ps1 -Dataset Astral -Files All

# Clean caches first
pwsh -File ./ai/scripts/OspreySharp/Run-Osprey.ps1 -Clean

# Run Rust osprey for ad-hoc comparison (optional sibling checkout)
pwsh -File ./ai/scripts/OspreySharp/Run-Osprey.ps1 -Tool Rust
```

## Regression

For routine C#-side refactors (Rust unchanged), the preferred gate is
the multi-file straight-through cross-impl run that reuses a cached Rust
reference -- faster than the snapshot below, and it exercises the
multi-file reconciliation / consensus-RT / gap-fill machinery that
single-file runs never touch:
`Compare/Compare-EndToEnd-Crossimpl.ps1 -Files All -SkipRust`.  See
[PRE-COMMIT.md](PRE-COMMIT.md) and [Compare/README.md](Compare/README.md).

When no Rust reference is available, use the OspreySharp-alone snapshot
gate instead.  `Test-Snapshot.ps1` compares the current OspreySharp
build against a frozen snapshot captured from an earlier known-good
build; no Rust checkout required.  Stage-by-stage isolation:
byte-equality SHA-256 checks on stages 1-6, structured comparators on
stage 7 (protein FDR) and blib.

`Test-Full-Regression.ps1` is the one-command wrapper that drives
Test-Snapshot across both datasets at the chosen scale.

```powershell
# Smoke (~3 min): Stellar single
pwsh -File ./ai/scripts/OspreySharp/Test-Full-Regression.ps1 -Smoke

# Quick (~10 min): Stellar single + Astral single
pwsh -File ./ai/scripts/OspreySharp/Test-Full-Regression.ps1 -Quick

# Full (~70 min): Stellar all + Astral all
pwsh -File ./ai/scripts/OspreySharp/Test-Full-Regression.ps1

# Refresh the frozen baseline after an approved behavior change
pwsh -File ./ai/scripts/OspreySharp/Test-Full-Regression.ps1 -CreateSnapshot
```

When to refresh the baseline: only after the PR carrying the
intentional behavior change has been reviewed and approved.  Run
`-CreateSnapshot` on master HEAD; the manifest records the source
commit and the OspreySharp binary SHA-256 so a future bisection
can identify the boundary.

## Performance

```powershell
# Refresh the Osprey-workflow.html perf table (3 reps median, both impls)
pwsh -File ./ai/scripts/OspreySharp/Measure-Pipeline.ps1 -Dataset Both -Tool Both -Repeats 3

# OspreySharp-only Stage 5 profile (dotTrace sampling)
pwsh -File ./ai/scripts/OspreySharp/Profile-OspreySharp.ps1 -Dataset Astral -Stage Scoring

# Full Stage 5 cross-impl profile (WSL dotTrace + samply)
wsl bash ./ai/scripts/OspreySharp/Profile-Stage5.sh
pwsh -File ./ai/scripts/OspreySharp/Combine-Stage5-Profile.ps1 -CsharpDtp ... -RustJson ...
```

## Test Data

| Dataset | Default Directory | Library | Resolution | Files |
|---|---|---|---|---|
| Stellar | `D:\test\osprey-runs\stellar\` | `hela-filtered-SkylineAI_spectral_library.tsv` | `unit` | 20, 21, 22 |
| Astral  | `D:\test\osprey-runs\astral\`  | `SkylineAI_spectral_library.tsv` | `hram` | 49, 55, 60 |
| AstralLibraryDecoy | `D:\test\osprey-runs\astral-libdecoy\` | `SkylineAI_entrapment_carafe_spectral_library.tsv` | `hram` | 49, 55, 60 |

Override the base via `-TestBaseDir`, `$env:OSPREY_TEST_BASE_DIR`,
or rely on the default.  Stellar requires `--resolution unit`;
Astral requires `--resolution hram` --- all scripts forward this
automatically via Dataset-Config.

## Cross-impl Bridge

Rarely needed now that OspreySharp is the primary implementation.
See [Compare/README.md](Compare/README.md) for when to invoke the
1e-9 parity gate, and how to opt in to the historical bisection
tools archived under `Compare/archive/`.
