# Quasar scripts

Scripts for Quasar (`pwiz_tools/Quasar`), the spectrum-centric companion to Osprey. The spec is
`pwiz_tools/Quasar/docs/00-spec.md` in the checkout; progress is in
`ai/todos/active/TODO-20261126_quasar.md`.

| Script | What it does |
|---|---|
| `Build-Quasar.ps1` | Builds `Quasar.sln` through the in-repo `build.ps1`; `-RunTests` runs `Quasar.Test`, `-RunInspection` runs the ReSharper zero-warning gate on Quasar's own files. |
| `DatumGolden/` | Prints datum's EMG outputs on the fixed inputs `EmgTest.TestEmgMatchesDatum` uses, so its expected values can be regenerated. Needs a `maccoss/datum` clone beside `ai/` (or `-p:DatumRoot=<path>`). |

Regenerating the datum values:

```powershell
dotnet run -c Release --project ./ai/scripts/Quasar/DatumGolden/DatumGolden.csproj
```

## Pre-commit gate

```powershell
pwsh -File ./ai/scripts/Quasar/Build-Quasar.ps1 -SourceRoot C:/Dev/pwiz-quasar -RunTests -RunInspection
```

Always pass `-SourceRoot`: Quasar is developed in its own worktree (`C:\Dev\pwiz-quasar` on the
machine where it started), and without it the script builds the default `pwiz` checkout.

Notes:
- Quasar's projects build with `TreatWarningsAsErrors`, so a compiler warning fails the build itself.
- `Quasar.sln` includes the Osprey projects Quasar references. The inspection reports on them
  too, but only issues in Quasar's files fail this gate; Osprey has its own (`Build-Osprey.ps1`).
- The build uses `dotnet msbuild` / `dotnet test` on every platform; the projects are plain `net10.0`.
