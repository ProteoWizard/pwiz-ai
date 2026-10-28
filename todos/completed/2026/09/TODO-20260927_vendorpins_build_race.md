# TODO-20260927_vendorpins_build_race.md

## Branch Information
- **Branch**: `Skyline/work/20260927_vendorpins_build_race`
- **Base**: `master` (the port branch merged into master; master merged in 2026-10-26)
- **Created**: 2026-09-27
- **Status**: Completed
- **Module**: `pwiz`
- **PR**: [#4724](https://github.com/ProteoWizard/pwiz/pull/4724) (merged 2026-10-27)
- **Worktree**: `D:\Dev\pwiz-vendorpins` (Mike); adopted 2026-10-26 by Matt in `C:\dev\pwiz-smallmol`

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

## Scope expansion (2026-10-26): no-change builds skip the vendor steps

Brendan and Brian timed no-change bs.bat/bo.bat after #4850 and found two per-build costs in the
vendor projects; the scope of this PR now covers both.

- **Extract*Assemblies never skipped.** 7-Zip gives extracted files the dates stored in the archive,
  which predate a fresh checkout of the archive, so Inputs=archive / Outputs=extracted files was always
  out of date. Their proposal touched the extracted DLLs; instead each of the 9 targets (Agilent,
  Bruker x2, Mobilion, Sciex, Shimadzu, Thermo, Waters, Mascot in BiblioSpec) now has a stamp file in its
  extraction folder as Outputs, touched at the end. Vendor files keep their real dates, and no
  referenced DLL gets newer, which would re-run CoreCompile downstream.
- **RunVendorPinsGenerator ran `dotnet run` every build (~2.6 s).** Now Inputs = vendor-archives
  vendor_api_*.7z, vendor-sdk-pins.json, the generator's sources and csproj, the generated .cs (so
  deleting it forces a run) and obj/VendorPins.head; Outputs = obj/VendorPins.stamp. VendorPins.head
  holds `git rev-parse HEAD`, written only when it differs (RecordVendorPinsHead, ~60 ms), because the
  pins' commit can change without any file changing. The generated .cs cannot be the Outputs: the
  generator rewrites it only on a content change, so it would stay older than a new HEAD forever.
  Chose rev-parse over the suggested .git/logs/HEAD: works in worktrees and without a reflog.

### Verified

- [x] No-change msconvert-sharp build (`dotnet build MsConvert.csproj -c Release
      -p:IAgreeToVendorLicenses=true`): master 6.8 s (extract targets 0.1-0.9 s each, generator 2.67 s)
      -> 3.2 s, all 8 extract targets + RunVendorPinsGenerator skipped
- [x] Re-runs when needed: touched archive re-extracts (DLL keeps its archive date); generator re-runs
      after deleting the .cs (file restored), a new commit, a reset back, and a touched archive, and
      skips on the next build each time
- [x] Fresh-generator (obj/bin deleted) `Build-Osprey.ps1 -Configuration Release -VendorReader`:
      succeeded, generator run once; no-change rerun 14.0 s with all 9 skips
- [x] Mascot (`dotnet build BiblioSpec.csproj -c Release -p:IAgreeToVendorLicenses=true`): first build
      extracted (0.94 s) and wrote the stamp, no-change build skipped it (3.4 s total), touched
      msparser archive re-extracted (headers keep 2021/2022 dates), next build skipped again

### /code-review high (2026-10-26), 9 findings

Fixed:
- Bruker/Waters stamp shared across target OS (a Linux-target build after a Windows one skipped
  extraction): stamp names now carry $(BrukerArchiveDir) / $(WatersNativeLibArchiveDir).
- Stamp lost the old Outputs' self-healing (deleted/never-extracted DLL): the key extracted files are
  back in Inputs; a missing input makes MSBuild run the target. Verified by deleting the Thermo
  RawFileReader DLL.
- Mascot stamp sat in the user-overridable $(MascotParserPath) (Touch fails if it does not exist):
  moved to BiblioSpec obj/, header added to Inputs.
- The repeated 3-line comment now lives once beside $(SevenZaExe) in Directory.Build.props.

Dropped:
- Archive replaced by an mtime-preserving copy: the archives come from make_*_7z.bat (fresh mtime)
  and git checkout always writes a fresh mtime.
- BuildMobilionShim ignores an SDK whose MBI_SDK.lib predates the built shim: pre-existing, and
  adding the extraction stamp to its Inputs made it run every build (the inner vcxproj build
  doesn't rewrite an up-to-date DLL) while the C++ link check would still skip the relink.
  Needs a forced rebuild on SDK change if ever wanted.
- Deleted pinned archive / deepened shallow clone leave stale pins: dev builds only; the installer
  runs the generator directly, unconditionally, with --require-all-pins.
- Concurrent extraction from multiple configurations: pre-existing; the stamp narrows it, and the
  one-configuration Osprey follow-up removes it.

After fixes: no-change msconvert-sharp build 3.2 s with all 8 extract targets, the generator and
BuildMobilionShim skipped; BiblioSpec no-change skips Mascot.

### 2026-10-27 - Merged

PR #4724 merged as commit f4efbd4f21, all checks green (Core Windows/Linux, no-vendor, Osprey
Windows .NET, Skyline, Perf/Tutorial, Wine container). Shipped: one VendorPinsGenerator run per build
(MSBuild-task call with fixed global properties, skipped in design-time builds); the 9
Extract*Assemblies targets skip via per-target stamps, with the key extracted files kept in Inputs
and per-OS stamps for Bruker and Waters; RunVendorPinsGenerator skips unless the archives, pins JSON,
generator, generated file or HEAD commit changed. No-change msconvert-sharp build 6.8 s -> 3.2 s.
The Osprey one-configuration follow-up already shipped separately (#4725). Not done: relinking
MobilionShim when a new SDK's MBI_SDK.lib predates the built shim (dropped review finding). No
issues filed.
