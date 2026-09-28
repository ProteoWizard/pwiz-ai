# TODO-20260927_vendorpins_build_race.md

## Branch Information
- **Branch**: `Skyline/work/20260927_vendorpins_build_race`
- **Base**: `Skyline/work/20260612_net8_port` (45a7f00a03)
- **Created**: 2026-09-27
- **Status**: In Progress
- **Module**: `pwiz`
- **PR**: [#4724](https://github.com/ProteoWizard/pwiz/pull/4724) (base: the port branch)
- **Worktree**: `D:\Dev\pwiz-vendorpins`

## Objective

Fix an intermittent parallel-build race in pwiz-sharp's VendorPinsGenerator.

Symptoms on 2026-09-27:
- TeamCity "Osprey Linux .NET" build 4190698 (pull/4708) failed after 25 s with
  `MSB3030: Could not copy the file ".../VendorPinsGenerator/obj/Release/net10.0/apphost"`, then
  `Vendor.Common.csproj(55,5): error MSB3073` for its `dotnet run --project VendorPinsGenerator`.
- A local `Build-Osprey.ps1` failed with `CS2012: Cannot open '...\VendorPinsGenerator\obj\Release\
  net10.0\VendorPinsGenerator.dll' for writing -- ... being used by another process`.

## Root cause (confirmed from a detailed build log)

Vendor.Common ran `dotnet run --project VendorPinsGenerator -c Release` in a `BeforeTargets="CoreCompile"`
Exec, once per configuration of Vendor.Common. One Osprey build compiles Vendor.Common three times:

| Instance | Requested by | Configuration |
|---|---|---|
| 24:12 | Osprey.IO (in the solution) | x64\|Release |
| 24:15 | Mobilion (not in the solution: Configuration/Platform stripped) | Debug\|AnyCPU |
| 24:27 | Bruker via ProteowizardWrapper (`pwiz_tools\Directory.Build.targets`) | Release\|AnyCPU |

All three compiled the generator into the same `obj\Release\net10.0`, and 24:12 and 24:15 overlapped (both
targets started before either Exec finished). Log:
`ai/.tmp/sessions/20260927-vendorpins/build1-detailed.txt`.

## Fix

- Vendor.Common's `RegenerateVendorSdkPins` calls the MSBuild task on the generator project's new
  `RunVendorPinsGenerator` target with fixed global properties (`Configuration=Release;Platform=AnyCPU`,
  and removes `TargetFramework;RuntimeIdentifier;SelfContained;ShouldUnsetParentConfigurationAndPlatform`).
- MSBuild shares a target result between requests with identical global properties, so the generator runs
  once per build and the other configurations wait for it or reuse it.
- The first attempt removed only the ProjectReference trio. The ProteowizardWrapper configuration still
  ran it a second time, because `pwiz_tools\Directory.Build.targets` passes
  `ShouldUnsetParentConfigurationAndPlatform=false` down as a global property.
- Verified: `build3-detailed.txt` shows one `RunVendorPinsGenerator` run and two
  "skipped. Previously built successfully".

## Other callers checked

- `pwiz-sharp/installer/build.ps1` runs `dotnet run --project VendorPinsGenerator ... --require-all-pins` once,
  before its build: sequential and unchanged.
- Skyline (through ProteowizardWrapper), Pwiz.sln, and the MsConvert, SeeMS and MsDiff tools reach the
  generator only through Vendor.Common.
- No build in the repo uses `-graph`/`-isolate`, which would reject an MSBuild task call to an undeclared
  project.

## Progress

- [x] Hypothesis confirmed (three configurations, two overlapping generator runs)
- [x] Fix: one generator run per build
- [x] Old vs new, generator obj/bin deleted before each build: old 3/5 failed (2x CS2012 on
      VendorPinsGenerator.dll, 1x SourceLink lock on VendorPinsGenerator.sourcelink.json); new 5/5 passed, one run each
- [x] `/code-review max`: 13 findings (ai/.tmp/sessions/20260927-vendorpins/). Applied in this PR: design-time
      builds skip the step (they run in their own sessions and raced a command-line build), accurate comments, a
      back-reference in pwiz_tools/Directory.Build.targets, installer wording, dropped the unexplained
      WorkingDirectory, and "$(PwizSharpRoot).." for the root argument (a drive-root checkout's trailing backslash
      escaped the quote)
- [x] Final head: race loop 3/3 (one run each); `Build-Osprey.ps1 -Configuration Debug -RunTests -RunInspection`
      604/604, 0 inspection warnings
- [x] PR #4724 opened 2026-09-27
- Follow-ups (own PRs): Osprey compiling pwiz-sharp in three configurations
  (`TODO-20260927_osprey_pwizsharp_one_config.md`; it also removes the Debug same-folder double compile and the
  vendor-extraction race); a HEAD-keyed up-to-date skip for the generator (every build still pays one child
  `dotnet run`)
