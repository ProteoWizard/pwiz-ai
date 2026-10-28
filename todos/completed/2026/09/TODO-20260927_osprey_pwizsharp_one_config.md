# TODO-20260927_osprey_pwizsharp_one_config.md

## Branch Information
- **Branch**: `Skyline/work/20260927_osprey_pwizsharp_one_config`
- **Base**: `Skyline/work/20260612_net8_port` (45a7f00a03)
- **Created**: 2026-09-27
- **Status**: Completed
- **Module**: `osprey`
- **PR**: [#4725](https://github.com/ProteoWizard/pwiz/pull/4725) (merged 2026-09-30 into the port branch as ed25627d81)
- **Worktree**: `D:\Dev\pwiz-osprey-oneconfig` (reviewed and finished in `C:\proj\pwiz`)
- **Related**: [#4724](https://github.com/ProteoWizard/pwiz/pull/4724) (VendorPinsGenerator race), whose review found this.
  The final version no longer touches `pwiz_tools/Directory.Build.targets`, so the two PRs no longer conflict.

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

## Decision: AnyCPU, like Skyline.sln (option b)

The PR as opened chose option (a): pass Osprey's own platform (x64) down, matching `package.ps1`, which publishes
`-p:Platform=x64`. Review on 2026-09-30 reversed it to option (b):
- The goal is that Skyline and Osprey share one pwiz-sharp build during iterative development, working with both
  solutions open in Visual Studio in one checkout, as the two head toward a single Skyline release. Matt asked the
  same on the PR.
- x64 left two pwiz-sharp trees (`bin\x64\<cfg>` from bo.bat, `bin\<cfg>` from bs.bat), needed a marker property
  in the shared `pwiz_tools/Directory.Build.targets`, and made each solution recompile ProteowizardWrapper after
  the other.
- Skyline cannot move to x64: `Skyline.csproj` deploys BlibBuild/BlibFilter, MascotShim/msparser, MsConvert and
  BullseyeSharp only from `pwiz-sharp\...\bin\$(Configuration)\net10.0`, which only an AnyCPU build writes.
- Nothing in pwiz-sharp, ProteowizardWrapper or CommonUtil depends on `$(Platform)`, and native staging follows the
  target platform (b56df0f18e), so AnyCPU vs x64 changes only the PE header and output folder. The accepted cost is
  that a solution-built Osprey deploys AnyCPU pwiz-sharp while `package.ps1` ships x64.

## Change (as merged)

- `pwiz_tools/Osprey/Directory.Build.targets`: new `CarryConfigurationToOutOfSolutionReferences`, after
  AssignProjectConfiguration in solution builds. It gives out-of-solution references `Configuration=$(Configuration)`
  and `Platform=AnyCPU;ShouldUnsetParentConfigurationAndPlatform=false` as global properties, which flow down the
  whole subtree. It is a target because the SDK flattens transitive references into every Osprey project and each
  must pass identical global properties. Comment cut to 7 lines.
- `pwiz_tools/Directory.Build.targets`: unchanged. The marker the first version added is not needed, because
  ProteowizardWrapper's own AnyCPU assignment now produces the same global properties as Osprey's.
- `pwiz_tools/Osprey/Directory.Build.props`: removed the plain `ShouldUnsetParentConfigurationAndPlatform=false`.
- `Osprey.IO.csproj`: removed the outdated FIXED history paragraph; "eight vendor projects" corrected to nine.
- Root `clean.bat` now also calls `pwiz-sharp\clean.bat` (`-all` passes `--all`, wiping pwiz-sharp's caches), and
  `pwiz_tools/clean-apps.bat` now cleans Osprey. Before, a root clean left pwiz-sharp and Osprey output behind.

## Progress

- [x] First version (x64): Release|x64 27 compiles; deploy hash check; Debug gate 604/604 and inspection 0/0;
      `-VendorReader` build; `regression.ps1 -Dataset Stellar` PASSED; `/code-review max` findings applied
- [x] Final version (AnyCPU), after `clean.bat`: bo.bat compiled 18 AnyCPU Release projects (pwiz-sharp,
      CommonUtil, ProteowizardWrapper) and 10 Osprey x64\Release projects, each once; no `bin\x64` or `bin\Debug`
      under pwiz-sharp; bs.bat reused the same `bin\Release` tree
- [x] `Build-Osprey.ps1 -Configuration Release -VendorReader -RunTests`: 604/604
- [x] Skyline.sln and Osprey.sln Release|x64 builds in Visual Studio after the bootstrap .bat
- [x] `clean.bat` removed every bin/obj under pwiz-sharp, Osprey, Skyline and Shared, and kept vendor-assemblies
- [x] TeamCity: 7/7 checks green
- [x] PR merged

## Deferred

- **bo.bat/bs.bat still recompile 8 vendor projects and ProteowizardWrapper when alternated** (~10 s). The
  restore entered through `TestFunctional.csproj` records Analysis without its IAgreeToVendorLicenses-gated Waters
  `ProjectReference`, and Agilent and Sciex without their NativeVendorsAvailable-gated `PackageReference`s. The other
  Skyline entry points and Osprey record them correctly, and whichever restore last touches the vendor projects
  decides their reference lists. A diagnostic TestFunctional restore showed the property true in every evaluation and
  NuGet collecting Analysis -> Waters, yet the dgspec it wrote lacked it. Ruled out: VS background restore, the NuGet
  version (VS 7.10 vs SDK 7.9), solution vs project restore, reference metadata, package pruning. Not reproducible
  after 12:52 on 2026-09-30, though TestFunctional still re-restores ~22 projects every run. Suggested fix: make those
  restore-affecting items unconditional and leave the Compile Remove / NO_VENDOR_SUPPORT gating alone. Handed to
  Matt on the PR (pwiz-sharp owner).
- Found in review, outside this change: `ai/scripts/Skyline/Build-Skyline.ps1` passes `/p:Platform=x64`, so
  BlibBuild, BlibFilter, MsConvert and BullseyeSharp land in `bin\x64\<cfg>`, while `Skyline.csproj` deploys them
  only from `bin\$(Configuration)\net10.0` (Exists()-guarded). The developer chose not to pursue it here (2026-09-27).
- The Build-Osprey.ps1 default (no `-VendorReader`) builds pwiz-sharp in NO_VENDOR_SUPPORT mode into the same
  `obj\Release`/`bin\Release` as bo.bat and bs.bat, so alternating it with them recompiles Analysis and every vendor
  project.

## Progress Log

### 2026-09-30 - Merged

PR #4725 merged into `Skyline/work/20260612_net8_port` as ed25627d81. After review the design moved from x64 to
AnyCPU so that Osprey and Skyline share one pwiz-sharp build, which also dropped the change to the shared
`pwiz_tools/Directory.Build.targets` and the conflict with #4724. The added comments were cut from about 50 lines to
7, and root `clean.bat` now cleans pwiz-sharp and Osprey. Deferred: the restore-driven vendor recompile when
alternating bo.bat and bs.bat (above), handed to Matt on the PR.
