# Quasar scripts

Scripts for Quasar (`pwiz_tools/Quasar`), the spectrum-centric companion to Osprey. The spec is
`pwiz_tools/Quasar/docs/00-spec.md` in the checkout; progress is in
`ai/todos/active/TODO-20261126_quasar.md`.

| Script | What it does |
|---|---|
| `Build-Quasar.ps1` | Builds `Quasar.sln` through the in-repo `build.ps1`; `-RunTests` runs `Quasar.Test`, `-RunInspection` runs the ReSharper zero-warning gate on Quasar's own files. |
| `Benchmark-Clusters.py` | The cluster benchmark (spec, Validation): for each Osprey precursor at q <= 0.01 in one isolation window, the Quasar cluster holding most of its library fragments; completeness, purity, member composition. `--traces` adds the fragments seen in any trace as the denominator. Reads a clusters TSV from the bench harness. |
| `Compare-SageToOsprey.py` | The Phase 1 positive control: a Rust Sage search of Quasar's pseudo-spectrum mzML against Osprey's blib for the same run; peptides found by both, Sage-only, apex time differences. `--q-levels spectrum_q` for one window (peptide q has a floor at a few hundred PSMs). |
| `DatumGolden/` | Prints datum's EMG outputs on the fixed inputs `EmgTest.TestEmgMatchesDatum` uses, so its expected values can be regenerated. Needs a `maccoss/datum` clone beside `ai/` (or `-p:DatumRoot=<path>`). |

Regenerating the datum values:

```powershell
dotnet run -c Release --project ./ai/scripts/Quasar/DatumGolden/DatumGolden.csproj
```

## Pre-commit gate

```powershell
pwsh -File ./ai/scripts/Quasar/Build-Quasar.ps1 -SourceRoot C:/Dev/pwiz-quasar -IAgreeToVendorLicenses -RunTests -RunInspection
```

Always pass `-SourceRoot`: Quasar is developed in its own worktree (`C:\Dev\pwiz-quasar` on the
machine where it started), and without it the script builds the default `pwiz` checkout.

Notes:
- Quasar's projects build with `TreatWarningsAsErrors`, so a compiler warning fails the build itself.
- `Quasar.sln` includes the Osprey projects Quasar references. The inspection reports on them
  too, but only issues in Quasar's files fail this gate; Osprey has its own (`Build-Osprey.ps1`).
- The build uses `dotnet msbuild` / `dotnet test` on every platform; the projects are plain `net10.0`.
