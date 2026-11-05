# TODO-20261105_ilcompiler_nu1903.md

## Branch Information
- **Branch**: `Skyline/work/20261105_ilcompiler_nu1903`
- **Base**: `master`
- **Created**: 2026-11-05
- **Status**: Completed
- **GitHub Issue**: (none)
- **Module**: `pwiz`
- **PR**: [#4999](https://github.com/ProteoWizard/pwiz/pull/4999) (merged 2026-11-05)

## Objective

Since 2026-11-03 every restore of `pwiz/utility/bindings/NativeAot/MsData.NativeAot.csproj`
warns NU1903 on `Microsoft.DotNet.ILCompiler` (GHSA-p3jp-9v83-76w9, CVE-2026-111497, .NET
Brotli decoder out-of-bounds write; affects >= 10.0.0 < 10.0.14, fixed in 10.0.14). The project
sets `PublishAot`, so the SDK adds an implicit ILCompiler reference at the version it bundles
(10.0.3 on TeamCity's SDK, 10.0.12 on SDK 10.0.401 locally). Since #4995 made build warnings
fatal for the "Core code inspection" status (bt83, `tcinspect.ps1` pre-build of Pwiz.sln), that
check fails on every PR, e.g. https://teamcity.labkey.org/buildConfiguration/bt83/4250532.

## Tasks

- [x] Check nothing else pins ILCompiler or a NativeAOT runtime pack (`git grep` of csproj/props/targets/global.json: none)
- [x] Confirm 10.0.14 on nuget.org for `Microsoft.DotNet.ILCompiler`, `runtime.win-x64.Microsoft.DotNet.ILCompiler`, `Microsoft.NETCore.App.Runtime.NativeAOT.win-x64`
- [x] Pin to 10.0.14 in `MsData.NativeAot.csproj`
- [x] Restore/build of the project: zero warnings
- [x] win-x64 Native AOT publish succeeds with all three packs at 10.0.14
- [x] Full Pwiz.sln rebuild (vendor licenses) shows zero warnings
- [x] MsData.NativeAot.Tests 10/10
- [x] PR opened, reviewers chambm and bspratt

## Decisions

- **`KnownILCompilerPack Update`, not an explicit `PackageReference`.** The documented explicit
  `<PackageReference Include="Microsoft.DotNet.ILCompiler" Version="10.0.14" />` removes NU1903,
  but restore still computes the `PackageDownload`s (ILCompiler host pack and
  `Microsoft.NETCore.App.Runtime.NativeAOT.win-x64`) from the SDK's bundled version, because
  restore evaluation does not import package props. The win-x64 publish (what tcbuild.bat runs)
  then failed: `Microsoft.NETCore.Native.Publish.targets(70,5): error : The PrivateSdkAssemblies
  ItemGroup is required for _ComputeAssembliesToCompileToNative`. Overriding
  `ILCompilerPackVersion` on the `KnownILCompilerPack` item moves the implicit reference, the
  host pack and the runtime pack together; the ILC and link response files reference only 10.0.14.
  The runtime pack matters beyond the audit: it supplies the native Brotli code linked into
  `pwiz_msdata.dll`.
- The override is a floor, not a pin: it applies only to the net10.0 item and only when the
  bundled version is below 10.0.14, so a machine on a later SDK keeps its own compiler.
- Remove the override once `global.json` moves to an SDK that bundles ILCompiler >= 10.0.14.

## Code review (/code-review medium, 6 findings)

- Fixed: unconditional Update would downgrade a newer bundled ILCompiler -> made it a floor (`VersionLessThan`).
- Fixed: Update touched every TFM's `KnownILCompilerPack` (net7/8/9) -> conditioned on `TargetFramework == net10.0`.
- Fixed: comment said "10.0.1xx SDKs"; the SDK in use is 10.0.401 via rollForward -> reworded.
- Dropped: `KnownRuntimePack` NativeAOT at 10.0.12 might pair with ILCompiler 10.0.14 - the actual win-x64 publish's ILC and link response files reference only 10.0.14 packs. linux-x64 not exercised (no Linux box here); TeamCity's Linux leg covers it.
- Dropped: move the override to a shared Directory.Build.targets - this is the only `PublishAot` project; a second one can lift it.
- Dropped: offline agents lose the bundled packs - CI restores from nuget.org, where 10.0.14 is published.

## Progress Log

### 2026-11-05
- Baseline: `before.log` shows NU1903 on ILCompiler 10.0.12 (local SDK 10.0.401 via `rollForward: latestFeature`).
- Explicit PackageReference: build clean, publish failed (above). Switched to the item override: build 0 warnings, publish succeeded.
- Added `-Publish` / `-RuntimeIdentifier` to `ai/scripts/PwizSharp/Build-PwizSharp.ps1` so the Native AOT publish can be exercised through the script (the linker step needs `vswhere.exe` on PATH outside a VS developer prompt).
- Logs: `C:\proj\ai\.tmp\sessions\20261105-n1\` (`before.log`, `after-project.log`, `publish-pinned.log` = failed explicit-reference publish, `publish-known.log`, `after-sln.log`).

### 2026-11-05 - Merged

PR #4999 merged as commit dd1ea43e89. Shipped: a KnownILCompilerPack override to 10.0.14 for net10.0 on MsData.NativeAot.csproj, clearing NU1903 (GHSA-p3jp-9v83-76w9) so the Core code inspection check is green again; verified by a full Pwiz.sln rebuild, a win-x64 publish and the shim's tests. Also added -Publish / -RuntimeIdentifier to Build-PwizSharp.ps1. Remove the override once global.json moves to an SDK bundling 10.0.14 or later. Merged on Brendan's approval before either reviewer responded.
