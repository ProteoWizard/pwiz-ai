# TODO-20260907_pwiz_local_nuget.md

## Branch Information
- **Checkout**: `C:\git\sky_net10build`
- **Branch**: `Skyline/work/20260907_pwiz_local_nuget`
- **Base**: `Skyline/work/20260612_net8_port` (the .NET 10 port, PR #4619)
- **Created**: 2026-09-07
- **Status**: In Progress
- **GitHub Issue**: (none yet)
- **Module**: `skyline`
- **PR**: (pending)

## Objective

Make it simple for a project to use the ProteoWizard we build. Today a consumer
(Skyline, its test projects, and in principle MSConvertGUI and SeeMS) has to carry a
dozen-plus `ProjectReference`s into `pwiz-sharp\`, plus Content globs that scrape other
projects' bin folders, plus knowledge of how pwiz-sharp was built (vendor licenses agreed
or not). The goal is that the pwiz-sharp command-line build produces something that
looks like a NuGet package, and a consumer references that one thing.

Three hard constraints from the 2026-09-07 discussion:

1. **Never download ProteoWizard from a NuGet website.** Skyline still gets its other
   packages (WebView2 etc.) from nuget.org; `Pwiz.*` ids must be pinned to the local feed
   and nothing else.
2. **Never use a ProteoWizard package from `%USERPROFILE%\.nuget\packages`.** Developers
   keep many pwiz checkouts on one machine. The package a tree consumes must be the one
   built from that same tree, and nothing on the machine may redirect it.
3. **Building pwiz-sharp from the command line, then opening Skyline.sln in Visual
   Studio, must just work.** No out-of-solution ProjectReference gymnastics.

Secondary motivation: MSConvertGUI and SeeMS (in `pwiz-sharp\Tools\`) each reference
15+ pwiz-sharp projects to get the full reader set. Whatever "one thing to reference"
Skyline ends up with should be usable by them too.

## Scope decision (2026-09-07, Nick)

**The package is ProteoWizard proper: the libraries under `pwiz-sharp\pwiz\src`** (core
data layer, vendor readers, Bruker.PrmScheduling, and whatever else there is a consumer
for). **Everything under `pwiz-sharp\Tools\` is a consumer of that package, exactly like
Skyline is.** That includes BiblioSpec and its executables (BlibBuild, BlibFilter,
BlibSearch, BlibToMs2), msconvert, bullseye-sharp, MSConvertGUI and SeeMS.

Consequences:

- There is no `Pwiz.Tools` package. The earlier draft that packed the executables so
  Skyline could pull them from a package is withdrawn.
- How Skyline obtains BlibBuild, BlibFilter, msconvert and bullseye-sharp is a separate,
  later question ("after we do that, we'll figure out how to get Skyline to use
  BlibBuild"). Until then Skyline keeps the `PwizSharpDeployTools` block from Phase 1
  (ProjectReference + Content glob), unchanged.
- pwiz-sharp's own build becomes two stages: build + pack `pwiz\src`, then build `Tools\`
  against the packages. `Pwiz.sln` today builds both in one graph through
  ProjectReference; the Tools projects need the same PackageReference/ProjectReference
  switch Skyline gets, and `build.bat` needs to run the stages in order.
- The package's consumer surface is therefore tested three ways before Skyline touches
  it: BiblioSpec (library consumer with vendor readers), msconvert (command-line
  consumer), MSConvertGUI/SeeMS (WinForms consumers). Skyline is the last and largest.

## What exists today (surveyed 2026-09-07 on the net8_port base)

**Consumers of pwiz-sharp outside `pwiz-sharp\`:**

| Consumer | How it reaches pwiz-sharp |
|---|---|
| `pwiz_tools/Shared/ProteowizardWrapper/ProteowizardWrapper.csproj` | 13 `ProjectReference`s: MsData, Analysis, Common, Util + 9 vendor readers. Imports `pwiz-sharp\Directory.Build.user.props` to learn `IAgreeToVendorLicenses` so it can define `NO_VENDOR_SUPPORT` to match. |
| `pwiz_tools/Skyline/Skyline.csproj` | `ProjectReference` (ReferenceOutputAssembly=false) to BlibBuild, BlibFilter, MsConvert, BullseyeSharp so they build first, then `Content` globs over each project's `bin\$(Configuration)\net10.0\**` guarded by `Exists()`. Special-cased MascotShim/msparser copy because files linked under `runtimes\...` do not deploy into consuming bins. Direct `ProjectReference` to Bruker.PrmScheduling. |
| `pwiz_tools/Skyline/SkylineTester/SkylineTester.csproj` | `DistroZipPrereq` item pointing at BlibToMs2.csproj. |
| `pwiz_tools/Skyline/TestData`, `TestFunctional` | Import `pwiz-sharp\build\ExtractTestData.targets` (test fixture 7z extraction, not a binary dependency). |
| `pwiz_tools/Shared/Lib/VendorNativeCrt.targets` | Copies CRT DLLs into `runtimes\win-x64\native` because HDF.PInvoke's hdf5.dll lives there. |

**Skyline's own `build.bat` never calls `pwiz-sharp\build.bat`.** The pwiz-sharp
projects get built inline through ProjectReference. The "build ProteoWizard first"
habit is left over from the C++ days; on this branch its only real purpose is to get
Visual Studio into a working state.

**Visual Studio pain** is the driver. Skyline.sln (28 projects) does not contain the
pwiz-sharp projects. Out-of-solution references lose Configuration/Platform in VS and
resolve to `bin\Debug`. PR #4634 (branch `Skyline/work/20260902_net10_sln_pwiz_projects`,
open against net8_port) patches this with an `AssignOutOfSolutionProjectReferenceConfiguration`
target in `pwiz_tools/Directory.Build.targets`; an earlier attempt added the projects to
the .sln and was reverted. Once consumers use PackageReference, that target has no
references left to fix and can be removed.

**pwiz-sharp already has** a date-based version (`4.0.{YY}{DDD}` from
`Directory.Build.targets` / `build\PwizVersion.targets`), a `Directory.Build.user.props`
opt-in for vendor licenses, and native assets flowing as `Content` (Waters native lib,
license.key, 7za.exe, vendor SDK DLLs extracted from encrypted 7z archives). No project
sets `IsPackable`/`GeneratePackageOnBuild` except the tests (false).

**ProteowizardWrapper usage in Skyline:** 81 files `using pwiz.ProteowizardWrapper`,
57 files mention `MsDataFileImpl`. The net10 implementation lives in
`pwiz_tools/Shared/ProteowizardWrapper.PwizSharp/` (~2,700 lines, linked into the
wrapper csproj).

## Design

### Package production (pwiz-sharp side)

- `pwiz-sharp\build.bat` gains a **pack** step after the build. Output: `.nupkg` files in
  a tree-local folder, e.g. `pwiz-sharp\artifacts\packages\`. This folder is the feed.
- Pack every library under `pwiz\src` that has a consumer (see Scope decision).
  ProjectReferences become package dependencies automatically; pwiz-sharp's own
  PackageReferences (HDF.PInvoke, System.Data.SQLite.Core, MathNet, Parquet.Net, Snappier,
  ...) are recorded in the nuspec so consumers get them transitively without redeclaring
  anything.
- **One meta package** (working name `Pwiz.All`; it is no longer Skyline-specific) that
  depends on the core libraries + all vendor readers + IdentData/TraData. A consumer has
  exactly one `PackageReference`. Consumers that want less (msconvert without a GUI
  dependency, say) reference the individual packages.
- Tools are NOT packed. BlibBuild and friends consume the packages (Scope decision).
- **Vendor natives** go into the package's `runtimes\win-x64\native\` layout so the
  runtime probes them through deps.json. Must be checked against the MascotShim/msparser
  problem noted in Skyline.csproj (files linked under `runtimes\` not deploying).
- **Vendor flavor travels with the package.** A `build\*.props` in the meta package sets
  `PwizSharpVendorSupport=true|false`. The wrapper (or any consumer) derives
  `NO_VENDOR_SUPPORT` from that and drops the `Directory.Build.user.props` import.
- Include `.pdb` files in the packages so stepping into pwiz-sharp source works in VS
  (source is on the same machine at the recorded paths).
- Pack step writes the absolute path of the producing tree into the meta package's
  props (`PwizSharpSourceTree`) as a tripwire (see below).

### Package consumption (Skyline side)

- `pwiz_tools\Directory.Build.props`: set `RestorePackagesPath` to a tree-local folder
  derived from `$(MSBuildThisFileDirectory)`. The MSBuild property outranks
  `NUGET_PACKAGES` and any nuget.config `globalPackagesFolder`, so nothing on the
  machine can send restore to the user-profile cache. Every tree extracts its own
  packages (a few hundred MB per checkout).
- Tree-local `nuget.config` (under `pwiz_tools\` or repo root): adds
  `pwiz-sharp\artifacts\packages` as a source and uses **package source mapping** to
  route `Pwiz.*` there and nothing else. A tree that has not built pwiz-sharp fails
  restore with "package not found" instead of borrowing a neighbor's build.
- Pack step **deletes `pwiz.*` from the tree-local packages folder** before writing new
  packages. NuGet's no-op restore check verifies every package in the assets file exists
  on disk, so the next VS or command-line build re-extracts. This makes unique
  per-build version numbers unnecessary; the existing `4.0.{YY}{DDD}` scheme is enough.
- **Tripwire target** in a shared `pwiz_tools\Shared\PwizSharp.targets`: compare the
  package's `PwizSharpSourceTree` against the consuming tree's root; fail the build
  with a clear message if they differ.
- **Escape hatch**: the same `PwizSharp.targets` holds both a PackageReference block and
  a ProjectReference block, switched by `UsePwizSharpProjects=true`, for people editing
  pwiz-sharp and Skyline together. All pwiz-sharp references in Skyline.csproj,
  ProteowizardWrapper.csproj and SkylineTester.csproj are consolidated into this one file.

### Package consumption (pwiz-sharp Tools side)

- The same mechanism, inside pwiz-sharp: a `Tools\Directory.Build.props` (or a shared
  `build\PwizPackages.targets`) that gives every Tools project a PackageReference to the
  meta package by default and the ProjectReference graph under `UsePwizSharpProjects=true`.
- Tree-local `RestorePackagesPath` and the `Pwiz.*` source mapping apply here too; the
  feed folder is the same one Skyline reads.
- `Pwiz.sln` splits or gains solution configurations so that "build the libraries" and
  "build the tools" are separable; `build.bat` runs: restore/build `pwiz\src` -> pack ->
  restore/build `Tools\` -> tests. The Tools test projects follow their project.

### Rejected alternatives

- **Adding pwiz-sharp projects to Skyline.sln** - tried in #4634's history and reverted;
  VS then builds ~20 extra projects and the solution stops being Skyline's.
- **Loose output folder + props file** (no NuGet at all) - avoids the cache question but
  loses transitive package dependencies and native probing, so HDF.PInvoke, SQLite and
  the vendor natives would have to be redeclared by hand in every consumer.
- **Unique version per build with floating `4.0.*` references** - unnecessary once the
  packages folder is tree-local and the pack step clears it; would also grow the feed.

## Open question: do we still need ProteowizardWrapper?

Nick's note (2026-09-07): the wrapper exists only because consuming ProteoWizard needed
so many references and dependencies that it was easier to put them in one project. With
a single package to reference, and with ProteoWizard now .NET, Skyline.csproj could
reference ProteoWizard directly and work with pwiz-sharp's own types (`SpectrumList`,
`MSData`, ...) instead of `MsDataFileImpl`.

Two separable pieces:

1. **Reference simplification** - achieved by the package work above regardless.
2. **API simplification** - retiring `MsDataFileImpl` as the chokepoint means touching
   the 81 files that use the wrapper namespace and re-expressing Skyline's data access
   in pwiz-sharp terms. That is a large refactor with its own risk profile and should be
   its own TODO/PR once the package work has landed and proven itself. Some wrapper
   pieces (`Centroider`, `LockMassParameters`, `DiaUmpire` params writer,
   `IterationListenerToMonitor`) are Skyline-flavored helpers rather than adapters and
   would simply move.

Decision for this TODO: do (1) now, keep the wrapper's public surface unchanged, and
write up (2) as a follow-on with the concrete list of `MsDataFileImpl` members Skyline
actually uses.

## Tasks

### Phase 1: Survey and consolidate (no behavior change) - DONE 2026-09-07
- [x] List exactly which pwiz-sharp assemblies land in Skyline's output today
      (`bin\x64\Release\net10.0-windows`) and where each came from (ProjectReference,
      Content glob, transitive package). This is the acceptance checklist for Phase 3.
      Result: `TODO-20260907_pwiz_local_nuget-output-attribution.txt` (per-file), summary
      in "Phase 1 findings" below.
- [x] Move every pwiz-sharp reference in Skyline.csproj, ProteowizardWrapper.csproj and
      SkylineTester.csproj into `pwiz_tools\Shared\PwizSharp.targets` (ProjectReference
      form only at this point). Build + run a smoke test; output must be identical.
      Result: file list identical (624 files); no pwiz-sharp, vendor or tool file changed
      hash. `TestInstrumentInfo` (Thermo/Agilent/Bruker reads) and `LibraryBuildTest`
      (BlibBuild) pass on the Release build. SkylineTester builds.

#### Phase 1 findings

Skyline's Release output holds 624 files. Attribution by identical relative path in the
upstream output directories:

| Files | Arrive through |
|---|---|
| 159 | ProteowizardWrapper's ProjectReference graph: 13 `Pwiz.*` assemblies (+pdb/xml), vendor SDK assemblies (Thermo, Clearcore2/Sciex, Shimadzu, MIDAC, MassLynxRaw, UIMFLibrary, timsdata, baf2sql_c, MobilionShim), `license.key`, `7za.exe`, `wiff2\`, HDF5 and vendor natives under `runtimes\win-x64\native\` |
| 4 | Bruker.PrmScheduling ProjectReference |
| 246 | Tool Content globs only (BlibBuild 75, BlibFilter 6, msconvert + bullseye-sharp 165); 79 of these are under `runtimes\` |
| 4 | Mascot natives copied FLAT by the special-case items (`MascotShim.dll`, `msparser.dll`, `msparser-config\*.xsd`) |
| ~211 | Skyline's own (Skyline, Shared projects, Skyline's packages, `Method\` builders, satellite assemblies) |

Two things the survey turned up that the package work has to handle deliberately:

- **Vendor SDK helper DLLs do not always reach consumers.** Thermo.csproj references
  `ThermoFisher.CommonCore.BackgroundSubtraction` and `.MassPrecisionEstimator` with
  `Private=true`, and they sit in Thermo's own bin, but `Pwiz.Vendor.Thermo.dll` does not
  reference them, so ResolveAssemblyReferences never carries them into the wrapper or
  Skyline. A Sep 3 output from the same sources had them (built through Visual Studio
  with the pwiz-sharp projects in the .sln at the time); today's command-line build does
  not, and the incremental clean removed them. Packages fix this properly: a vendor
  package's `lib\` or `runtimes\` carries whatever the vendor project says it needs,
  independent of what the compiled assembly happens to reference. Phase 2 must decide
  per vendor which SDK files are genuinely required (Reader_Thermo loads them by name at
  runtime or not at all).
- **Package version skew between Skyline and pwiz-sharp.** Skyline pins
  `MathNet.Numerics` 4.15.0; pwiz-sharp's Util.csproj uses 5.0.0. Skyline's assets file
  resolves 4.15.0, yet the file in Skyline's output is 5.0.0.0 because the wrapper's
  copy-local output wins the copy race. With PackageReference NuGet will unify the graph
  and flag the downgrade (NU1605); the answer is to move Skyline to 5.0.0 as part of
  Phase 3. Check the other shared packages the same way (System.Data.SQLite.Core and
  Newtonsoft.Json already match).

Not touched in Phase 1, on purpose: `SkylineVersion.targets` still imports
`pwiz-sharp\build\PwizVersion.targets` by relative path (it is also consumed by
Executables\Tools\SkylineMcp projects, and version stamping may come from the package
later); `ProteowizardWrapper.PwizSharp\` (sandbox project referenced only by the Smoke
project, not built by anything); Osprey.IO's HintPath to the wrapper (hard-off).

### Phase 2: Produce packages from pwiz-sharp\pwiz\src
- [ ] Inventory what `Tools\*` and Skyline consume from `pwiz\src` (which projects, and
      which files beyond the assemblies: natives, license.key, 7za.exe, SDK helper DLLs).
      Decide package ids and which projects pack (core libs, IdentData, TraData,
      Vendor.Common + 9 vendors, Bruker.PrmScheduling, StlContainers, MSGraph/ZedGraph
      for SeeMS).
- [ ] Meta package `Pwiz.All` with `build\*.props` carrying `PwizSharpVendorSupport`
      and `PwizSharpSourceTree`.
- [ ] Vendor natives via `runtimes\win-x64\native`; verify Waters license.key, 7za.exe,
      and the CRT files from `VendorNativeCrt.targets` still arrive. Decide per vendor
      which SDK helper DLLs ship (Phase 1 finding: Thermo's BackgroundSubtraction and
      MassPrecisionEstimator currently do not reach consumers).
- [ ] Include pdbs in the packages.
- [ ] Add the pack step to `pwiz-sharp\build.bat` (both vendor and no-vendor modes),
      clearing old `pwiz.*` from the feed folder and the tree-local packages folder first.
- [ ] Decide whether `Pwiz.sln` also gets a solution-level "pack" so a developer in VS
      on the pwiz-sharp side can refresh the feed without leaving the IDE.

### Phase 2b: pwiz-sharp Tools consume the packages
- [ ] Shared props/targets under `pwiz-sharp\Tools\` with the PackageReference default and
      the `UsePwizSharpProjects` escape hatch; tree-local `RestorePackagesPath` and
      `Pwiz.*` source mapping for the pwiz-sharp tree.
- [ ] Convert BiblioSpec + BlibBuild/BlibFilter/BlibSearch/BlibToMs2 first (library
      consumer with vendor readers and the MascotShim native). BiblioSpec.Tests pass.
- [ ] Convert msconvert and bullseye-sharp. msconvert's tests and Installer.Tests pass.
- [ ] Convert MSConvertGUI and SeeMS (WinForms consumers; SeeMS also wants MSGraph/ZedGraph).
- [ ] `build.bat` runs the two stages in order; `Pwiz.sln` still opens and builds in VS
      after a command-line build of the libraries. TeamCity ProteoWizard_CoreWindowsNet
      config stays green.
- [ ] Record in the TODO what the Tools conversion taught us about the package shape
      before Skyline is converted.

### Phase 3: Consume packages from Skyline
- [ ] `pwiz_tools\Directory.Build.props`: tree-local `RestorePackagesPath`.
- [ ] Tree-local `nuget.config` with the feed source and `Pwiz.*` source mapping.
- [ ] `PwizSharp.targets`: PackageReference block (default) + ProjectReference block
      (`UsePwizSharpProjects=true`), tripwire target.
- [ ] ProteowizardWrapper: derive `NO_VENDOR_SUPPORT` from the package props; remove the
      `Directory.Build.user.props` import.
- [ ] `PwizSharp.targets`: the libraries and PrmScheduling blocks switch to
      PackageReference. The `PwizSharpDeployTools` block stays as ProjectReference +
      Content glob until the "how does Skyline get BlibBuild" question is answered
      (Scope decision). Note that this block is then the only out-of-solution
      ProjectReference left, so #4634's `AssignOutOfSolutionProjectReferenceConfiguration`
      target is still needed for it.
- [ ] Move Skyline's `MathNet.Numerics` pin to 5.0.0 (Phase 1 finding).

### Phase 3b: How Skyline obtains the tools (design TBD with Nick)
- [ ] Options to weigh once Phases 2-3 have landed: (a) keep ProjectReference + Content
      glob; (b) a pwiz-sharp "tools" publish step that drops the exes into a known folder
      Skyline's Content items read from; (c) a separate `Pwiz.Tools`-style package after
      all, now that the tools themselves are package consumers; (d) Skyline builds the
      tool projects into its own output via a shared props file. Not decided.
- [ ] Verify Phase 1's output checklist matches byte-for-byte in file list.

### Phase 4: Prove it
- [ ] Clean tree: `pwiz-sharp\build.bat` then open Skyline.sln in VS, Debug and Release,
      build, F5, import a Thermo .raw and a Waters .raw, run a BlibBuild.
- [ ] Two-checkout test: build pwiz-sharp in tree A only, open tree B's Skyline.sln,
      confirm restore fails with the "package not found" message and nothing leaks
      across trees. Then build B and confirm it works.
- [ ] Tripwire test: copy A's feed folder into B, confirm the build fails with the
      source-tree mismatch message.
- [ ] TeamCity: `pwiz_tools\Skyline\build.bat` and `tcbuild.bat` still pass; `build.bat`
      must now run the pwiz-sharp pack step (or depend on the pwiz-sharp TC config's
      artifacts) since ProjectReference no longer builds pwiz-sharp inline.
- [ ] Docker parallel test workers: confirm the staged test folder still carries every
      native and tool (`Stage-Tests.ps1` copies from Skyline's output, so this should be
      automatic, but check).
- [ ] MSConvertGUI / SeeMS / BlibBuild / msconvert: already converted in Phase 2b; confirm
      they still run from a clean two-stage `pwiz-sharp\build.bat`.

### Phase 5: Documentation and follow-ons
- [ ] Update `ai/docs/build-and-test-guide.md` (or the net10 equivalent) with the new
      two-step flow and the `UsePwizSharpProjects` escape hatch.
- [ ] Write the follow-on TODO for retiring `MsDataFileImpl` (open question above), with
      the measured list of members Skyline uses.

## Risks and things to watch

- **VS restore timing.** After a pwiz-sharp rebuild the packages folder is cleared; VS
  must notice and restore before building. Verify that a plain Build (not Rebuild)
  triggers restore when the assets file's packages are missing. If not, the pack step
  can also touch `obj\project.assets.json` inputs or we document "Restore NuGet
  Packages" as part of the flow.
- **`runtimes\` deployment into consumers.** Skyline.csproj records that Content linked
  under `runtimes\...` did not deploy to consuming bins. Package native assets use a
  different mechanism (deps.json + `ResolvePackageAssets`), so this should work, but the
  Mascot path is the test.
- **Design-time IntelliSense** across a PackageReference needs the package restored;
  a fresh checkout shows red squiggles until pwiz-sharp has been built once. Acceptable,
  but document it.
- **TeamCity Skyline builds** currently get pwiz-sharp for free via ProjectReference.
  With PackageReference the Skyline build must run the pwiz-sharp build+pack first.
  `tcbuild.bat` ordering needs a look.
- **Osprey** consumes ProteowizardWrapper on Linux (`net10.0`, PR #4588). Package source
  mapping and `RestorePackagesPath` must work identically on Linux; use forward-slash
  safe path construction.

## Files (expected)

- `pwiz-sharp/build.bat` - pack step
- `pwiz-sharp/build/Pack.targets` (new) - pack orchestration, feed cleanup
- `pwiz-sharp/pwiz/src/**/*.csproj` - `IsPackable`, package metadata, native asset packing
- `pwiz-sharp/Tools/Directory.Build.props` (new) or `pwiz-sharp/build/PwizPackages.targets` (new) - Tools consume the packages
- `pwiz-sharp/Tools/**/*.csproj` - ProjectReferences into `pwiz\src` replaced by the shared import
- `pwiz-sharp/Pwiz.sln` - library/tool stages
- `pwiz-sharp/nuget.config` (new) - feed + source mapping for the pwiz-sharp tree
- `pwiz_tools/nuget.config` (new) - feed + source mapping
- `pwiz_tools/Directory.Build.props` - `RestorePackagesPath`
- `pwiz_tools/Shared/PwizSharp.targets` (new) - single reference point, escape hatch, tripwire
- `pwiz_tools/Shared/ProteowizardWrapper/ProteowizardWrapper.csproj`
- `pwiz_tools/Skyline/Skyline.csproj`
- `pwiz_tools/Skyline/SkylineTester/SkylineTester.csproj`
- `pwiz_tools/Directory.Build.targets` - remove #4634's target once merged

## Progress

- 2026-09-07: Branch created from `origin/Skyline/work/20260612_net8_port` at
  `5c046bdb7a`. Survey of current references done (table above).
- 2026-09-07: Phase 1 complete. New `pwiz_tools\Shared\PwizSharp.targets` with three
  opt-in blocks (`PwizSharpReferenceLibraries`, `PwizSharpDeployTools`,
  `PwizSharpReferencePrmScheduling`); `$(PwizSharpRoot)` defined in
  `pwiz_tools\Directory.Build.props`. ProteowizardWrapper.csproj lost its 13
  ProjectReferences + user.props import + NO_VENDOR_SUPPORT block; Skyline.csproj lost
  its 5 tool ProjectReferences, the Content globs, the Mascot special case and the
  PrmScheduling reference; SkylineTester/TestData/TestFunctional use `$(PwizSharpRoot)`.
  Output verified identical against a same-branch baseline. Next: Phase 2.
