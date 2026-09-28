# TODO-20260927_osprey_pwizsharp_one_config.md

## Branch Information
- **Branch**: `Skyline/work/20260927_osprey_pwizsharp_one_config`
- **Base**: `Skyline/work/20260612_net8_port` (45a7f00a03)
- **Created**: 2026-09-27
- **Status**: In Progress
- **Module**: `osprey`
- **PR**: [#4725](https://github.com/ProteoWizard/pwiz/pull/4725) (base: the port branch)
- **Worktree**: `D:\Dev\pwiz-osprey-oneconfig`
- **Related**: [#4724](https://github.com/ProteoWizard/pwiz/pull/4724) (VendorPinsGenerator race), whose review found this.
  Both edit the same comment block in `pwiz_tools/Directory.Build.targets`, so the second to merge resolves a
  small conflict.

## Objective

Make an Osprey build compile pwiz-sharp in one configuration instead of three.

Baseline, Release|x64 Osprey.sln (`ai/.tmp/sessions/20260927-vendorpins/build3-detailed.txt`): 27 projects, 49
compiles. Util, Common, MsData, IdentData, Analysis and Vendor.Common were compiled into bin\x64\Release, bin\Debug
and bin\Release; the vendor projects and CommonUtil into two of those.
- **x64|Release** came from the Osprey projects. `ShouldUnsetParentConfigurationAndPlatform=false` is a plain
  property in Osprey's Directory.Build.props, so it covers the first hop only.
- **Debug** came from the second hop. The x64|Release pwiz-sharp projects are in a solution build and not in
  the solution, so they strip Configuration and Platform from their own references.
- **Release|AnyCPU** came from ProteowizardWrapper, which imports `pwiz_tools/Directory.Build.targets`.

## Decision: keep x64 (option a)

- Every scripted Osprey build is x64: build.ps1 and the Jamfile build Osprey.sln as x64, and package.ps1
  publishes Osprey.csproj with `-p:Platform=x64` (unchanged since #4336), so shipped pwiz-sharp has always been
  x64. Forwarding the build's own platform makes the solution build compile those same binaries; an Any CPU
  solution configuration forwards AnyCPU (the build kept for Arm64 hosts).
- The deployed Osprey output keeps its DLL set, and ReSharper's out-of-solution resolution is unchanged.
- Neither pwiz-sharp nor the CommonUtil Osprey builds (`pwiz_tools/Shared/CommonUtil`) has Platform-dependent
  build logic; both only declare `<Platforms>`. So x64 vs AnyCPU changes the PE header and output folder, nothing
  else. (An earlier note here attributed PlatformTarget logic to CommonUtil; that was the unused legacy
  `pwiz_tools/Shared/Common/CommonUtil.csproj`.) Option (b), AnyCPU like Skyline.sln, would have changed every
  deployed DLL and split what CI tests from what package.ps1 ships.

## Change

- `pwiz_tools/Osprey/Directory.Build.targets`: new `CarryConfigurationToOutOfSolutionReferences`, after
  AssignProjectConfiguration in solution builds. It gives out-of-solution references
  `Configuration=$(Configuration)` and
  `Platform=$(Platform);ShouldUnsetParentConfigurationAndPlatform=false;PwizOutOfSolutionConfigurationCarried=true`
  as global properties, which flow down the whole subtree. Its comment is the one full explanation, including the
  constraints: subtree projects stay out of Osprey.sln, all Osprey projects map to one platform per solution
  configuration, and alternating Skyline.sln and Osprey.sln recompiles ProteowizardWrapper.
- `pwiz_tools/Directory.Build.targets`: AssignOutOfSolutionProjectReferenceConfiguration skips only a project
  marked `PwizOutOfSolutionConfigurationCarried=true`. The first version keyed on
  `ShouldUnsetParentConfigurationAndPlatform=false`, which review showed can also come from a local setting, a
  `/p:` override or MSBuild's default; with the marker, Skyline builds exactly as before.
- `pwiz_tools/Osprey/Directory.Build.props`: removed the now-redundant plain
  `ShouldUnsetParentConfigurationAndPlatform=false` (a pointer to the target remains).
- `Osprey.IO.csproj`: its history paragraph replaced by a pointer; "eight vendor projects" corrected to nine.

## Progress

- [x] Release|x64 detailed build: 27 projects, 27 compiles; no bin\Debug or bin\Release pwiz-sharp folders (the
      only AnyCPU output is VendorPinsGenerator's own `dotnet run -c Release`); one RegenerateVendorSdkPins
- [x] Deployed Osprey output: the same 53 files as the baseline, all 51 in-tree assemblies byte-identical to their
      x64\Release build outputs
- [x] Debug|x64 gate with detailed log: 27 compiles, no duplicate; inspection 0/0 on a fresh tree; 604/604 tests
- [x] `-VendorReader` Release build: 28 projects, 28 compiles (the extra is MobilionShim.vcxproj, once); every
      Extract*Assemblies and BuildMobilionShim ran exactly once on a tree with no vendor-assemblies
- [x] `regression.ps1 -Dataset Stellar` PASSED (first version of the change)
- [x] `/code-review max`: 15 findings (report in the session); applied the marker, removed the props property,
      consolidated and corrected the comments
- [ ] Re-run the gates on the reviewed version (waiting for memory: the demux session's DIA-NN holds ~30 GB):
      Release and Debug compile counts, deploy hash check, vendor build, Stellar regression
- [ ] PR (authorized tonight once the gates pass)

## Noted, not pursued

- Found in review, outside this change: `ai/scripts/Skyline/Build-Skyline.ps1` builds Skyline's csproj list as x64,
  so BlibBuild, BlibFilter, MsConvert and BullseyeSharp land in `bind\<cfg>`, while `Skyline.csproj` deploys them
  only from `bin\$(Configuration)
et10.0` (Exists()-guarded). The developer chose not to pursue it here (2026-09-27).
