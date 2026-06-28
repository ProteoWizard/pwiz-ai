# Osprey Scripts

Build, test, profile, and (occasionally) cross-impl-compare Osprey.
All scripts default to `-Dataset Stellar` with `-Dataset Astral` and
`-Dataset AstralLibraryDecoy` as alternatives.  Dataset-specific paths
and resolution flags live in [`Dataset-Config.ps1`](Dataset-Config.ps1),
which also exposes project-root helpers (`Get-PwizRoot`,
`Get-OspreyExe`, etc.) so nothing here hard-codes `C:\proj`.

## Layout

```
ai/scripts/Osprey/
  README.md                     (this file)
  DIAGNOSTICS.md                env-var reference for OSPREY_DUMP_*
  PRE-COMMIT.md                 pre-commit + pre-PR validation gates

  Build-Osprey.ps1         build the .sln (+ optional tests/inspection/coverage)
  Summarize-Coverage.ps1        summarize a dotCover JSON report (whole-project)
  Run-Osprey.ps1                run Osprey or Rust osprey on a dataset
  Dataset-Config.ps1            dataset definitions + path helpers
  Clean-TestData.ps1            wipe caches / diagnostic dumps

  Test-PerfGate.ps1             perf gate: branch vs pinned pwiz-perfbase
                                (same-session A/B, 3-rep median)
  Test-Snapshot.ps1             stage-isolated bisection (per-stage byte-equality)
  Test-Full-Regression.ps1      wrapper around Test-Snapshot (smoke/quick/full)

  Measure-Pipeline.ps1          perf table generator (Osprey-workflow.html)
  Profile-Osprey.ps1       dotTrace wrapper for Osprey
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

Osprey is the primary implementation; the Compare/ folder is the
bridge for the rare "did this change drift us from Rust?" question.
The rest of this README focuses on the Osprey-primary workflow.

## Build

```powershell
# Build (Release, all projects)
pwsh -File ./ai/scripts/Osprey/Build-Osprey.ps1

# Build + run all unit tests
pwsh -File ./ai/scripts/Osprey/Build-Osprey.ps1 -RunTests

# Build + ReSharper inspection (zero-warning gate)
pwsh -File ./ai/scripts/Osprey/Build-Osprey.ps1 -RunInspection
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
pwsh -File ./ai/scripts/Osprey/Build-Osprey.ps1 -Coverage

# Summarize the exported JSON (path is printed at the end of the run)
pwsh -File ./ai/scripts/Osprey/Summarize-Coverage.ps1 `
  -CoverageJsonPath ai/.tmp/osprey-coverage-<timestamp>.json
```

Coverage spans the `Osprey.*` production assemblies; the
`Osprey.Test` assembly is excluded. The `.json` and `.dcvr`
snapshot land in `ai/.tmp/`; import the `.dcvr` in Visual Studio
(ReSharper > Unit Tests > Coverage > Import from Snapshot) for
line-by-line detail. Requires the dotCover command-line tool
(`dotnet tool install -g JetBrains.dotCover.CommandLineTools`).

## Run

```powershell
# Run Osprey on Stellar single file (default)
pwsh -File ./ai/scripts/Osprey/Run-Osprey.ps1

# Astral all-files
pwsh -File ./ai/scripts/Osprey/Run-Osprey.ps1 -Dataset Astral -Files All

# Clean caches first
pwsh -File ./ai/scripts/Osprey/Run-Osprey.ps1 -Clean

# Run Rust osprey for ad-hoc comparison (optional sibling checkout)
pwsh -File ./ai/scripts/Osprey/Run-Osprey.ps1 -Tool Rust
```

## Regression

Two standing gates guard every C#-side refactor; see
[PRE-COMMIT.md](PRE-COMMIT.md) for the full gate doc.

**Correctness** -- `pwiz_tools/Osprey/regression.ps1` (in the pwiz
tree, self-contained): a straight-through run vs a committed Osprey
golden plus a resume self-consistency leg, both at 1e-9.  No Rust
checkout.  This is also the overnight TeamCity gate for Osprey PRs.

```powershell
# Routine per-change correctness gate
pwsh -File ./pwiz_tools/Osprey/regression.ps1 -Dataset Stellar
```

**Performance** -- `Test-PerfGate.ps1` (this folder): a same-session A/B
of the branch build vs the pinned `pwiz-perfbase` baseline worktree,
3-rep median, failing only on a real regression (non-overlapping noise
bands).

```powershell
# Routine per-refactor perf gate
pwsh -File ./ai/scripts/Osprey/Test-PerfGate.ps1 -Dataset Stellar
```

`Test-Full-Regression.ps1` / `Test-Snapshot.ps1` are now the
stage-isolated BISECTION tools -- run them to localize WHERE a red
`regression.ps1` diverged (per-stage SHA-256 + structured stage7/blib
comparators), not as the first-line gate.

```powershell
# Localize a divergence (~3 min smoke): Stellar single
pwsh -File ./ai/scripts/Osprey/Test-Full-Regression.ps1 -Smoke
```

## Performance

`Test-PerfGate.ps1` (see Regression, above) is the pass/fail perf gate
for refactors.  The scripts below are for *characterizing* perf, not
gating: `Measure-Pipeline.ps1` generates the cross-impl Osprey-workflow.html
table, and the profilers attribute time within a stage.

```powershell
# Refresh the Osprey-workflow.html perf table (3 reps median, both impls)
pwsh -File ./ai/scripts/Osprey/Measure-Pipeline.ps1 -Dataset Both -Tool Both -Repeats 3

# Osprey-only Stage 5 profile (dotTrace sampling)
pwsh -File ./ai/scripts/Osprey/Profile-Osprey.ps1 -Dataset Astral -Stage Scoring

# Full Stage 5 cross-impl profile (WSL dotTrace + samply)
wsl bash ./ai/scripts/Osprey/Profile-Stage5.sh
pwsh -File ./ai/scripts/Osprey/Combine-Stage5-Profile.ps1 -CsharpDtp ... -RustJson ...
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

Rarely needed now that Osprey is the primary implementation.
See [Compare/README.md](Compare/README.md) for when to invoke the
1e-9 parity gate, and how to opt in to the historical bisection
tools archived under `Compare/archive/`.
