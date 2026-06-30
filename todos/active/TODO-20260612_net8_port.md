# TODO: Skyline → .NET 8 port + pwiz-sharp swap + Jamfile retirement

Branch: `Skyline/work/20260612_net8_port` (off `master`)
Worktree: `C:\dev\pwiz-net8\`

## The multi-target conversion pattern (proven on PortableUtil + CommonUtil)

The Skyline tree is large but the conversion of each csproj follows a repeatable
template. **Multi-target `net472;net8.0-windows`** — net472 keeps the legacy
Skyline build path working unchanged; net8.0-windows is the new path.

Template csproj (drop the legacy 600-line XML, replace with ~40 lines):

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <ProjectGuid>{...}</ProjectGuid>                 <!-- preserve from legacy -->
    <TargetFrameworks>net472;net8.0-windows</TargetFrameworks>
    <Platforms>AnyCPU;x64</Platforms>
    <LangVersion>latest</LangVersion>
    <Nullable>disable</Nullable>
    <ImplicitUsings>disable</ImplicitUsings>
    <RootNamespace>pwiz.X</RootNamespace>
    <AssemblyName>pwiz.X</AssemblyName>
    <UseWindowsForms>true</UseWindowsForms>           <!-- if WinForms used -->
    <Company>University of Washington</Company>
    <Copyright>Copyright (c) University of Washington 2026</Copyright>
    <GenerateAssemblyInfo>false</GenerateAssemblyInfo>  <!-- AssemblyInfo.cs already exists -->
    <GenerateResourceUsePreserializedResources>true</GenerateResourceUsePreserializedResources>
  </PropertyGroup>

  <ItemGroup>
    <!-- both targets -->
    <PackageReference Include="System.Resources.Extensions" Version="8.0.0" />
  </ItemGroup>

  <ItemGroup>
    <!-- net472-only assemblies the SDK doesn't add by default -->
    <Reference Include="System.Net.Http" Condition="'$(TargetFramework)' == 'net472'" />
    <Reference Include="System.Web" Condition="'$(TargetFramework)' == 'net472'" />
    <Reference Include="System.Security" Condition="'$(TargetFramework)' == 'net472'" />
    <!-- HintPath legacy DLLs, kept net472-only so the existing path uses
         exactly the binaries it always has -->
    <Reference Include="JetBrains.Annotations" Condition="'$(TargetFramework)' == 'net472'">
      <HintPath>..\Lib\JetBrains.Annotations.dll</HintPath>
      <Private>True</Private>
    </Reference>
  </ItemGroup>

  <ItemGroup Condition="'$(TargetFramework)' == 'net8.0-windows'">
    <!-- net8 equivalents via NuGet -->
    <PackageReference Include="JetBrains.Annotations" Version="2024.3.0" />
  </ItemGroup>

  <ItemGroup>
    <ProjectReference Include="..\Dep\Dep.csproj" />
  </ItemGroup>
</Project>
```

**Source-code adjustments commonly needed:**

1. **`.Reverse()` on arrays** — net8 prefers `Span<T>.Reverse()` (void, in-place)
   over LINQ `Enumerable.Reverse()`. Use explicit `Enumerable.Reverse(arr)` so
   the same source picks the right overload on both targets.
2. **VS-tooling assemblies** (`Microsoft.ConcurrencyVisualizer.Markers`) — wrap
   in `#if NET472` blocks; net8 path becomes a no-op.
3. **Native deps with `$(PLATFORM)` substitution** (System.Data.SQLite) — switch
   to `Microsoft.Data.Sqlite` or `System.Data.SQLite.Core` NuGet package on net8.
4. **NHibernate** — versions ≥5.5 support net6+. Multi-target by package version
   if legacy needed.

## Status (2026-06-30)

### Cumulative progress (2026-06-30, end of working session — substantial)

| Project | csproj converted | net8 builds | Notes |
|---|---|---|---|
| PortableUtil | yes (predates branch) | ✅ | template |
| CommonUtil | yes | ✅ | ConcurrencyVisualizer net472-only, Reverse() shadow fix |
| ZedGraph (fork) | yes | ✅ | Deterministic=false for AssemblyVersion("5.1.*") |
| MSGraph | yes | ✅ | trivial — only refs ZedGraph |
| Common | yes | ✅ | NHibernate via NoWarn NU1605; MathNet downgraded to 4.15 (5.0 dropped API); Control.LinearAlgebraProvider→Providers.LinearAlgebra.LinearAlgebraControl.Provider per-target; alglib_info/AssemblyInfo attribute dedup; SQLite NuGet swap |
| ProteomeDb | yes | ✅ | DotNetZip HintPath fix + Ionic.Zip→System.IO.Compression on net8; dev-only Forms/ excluded |
| PanoramaClient | yes | ✅ | trivial |
| **ProteowizardWrapper** | yes | ✅ **with pwiz-sharp** | the chokepoint — Compile Remove legacy MsDataFileImpl + 3 siblings on net8, Compile Include from ProteowizardWrapper.PwizSharp sandbox |
| CommonMsData (wrapper) | yes | ✅ | Unifi/WatersConnect remote API excluded on net8 (IdentityModel 7 rewrite deferred); 219 Skyline files import this namespace |
| CommonFileDialogs | yes | ✅ | one source fix for WatersConnect auth dispatch |
| BiblioSpec (wrapper) | yes | ✅ | trivial shell-out wrapper |
| TestUtil | no | n/a | next session |
| **Skyline.csproj** | no | n/a | the monolith — 1,311 Compile + 1,230 None/EmbeddedResource entries, 30+ HintPath refs. Its own multi-session conversion |
| TestData.csproj | no | n/a | goal target — depends on TestUtil + Skyline |

### Critical milestone reached: pwiz-sharp is the data layer on net8

ProteowizardWrapper.csproj's net8.0-windows path **builds against pwiz-sharp**
end-to-end. The 219 Skyline files importing `pwiz.CommonMsData` and the 74
importing `pwiz.ProteowizardWrapper` now link transitively against managed C#
data code on net8, with the legacy pwiz.CLI C++/CLI bindings preserved only
on net472. **The phase-2 data-layer swap is real, not just sandbox.** Skyline
itself isn't running yet (csproj cascade incomplete) but everything below it
is wired correctly.

### Known source-level fixes recurring across the cascade

1. **Reverse() on arrays** → `Enumerable.Reverse(arr)` explicit form.
2. **`Microsoft.ConcurrencyVisualizer.*`** → `#if NET472` wrap.
3. **AssemblyCompany/Product/Title/Copyright/Version/FileVersion duplicates** —
   wrap these in `Properties/AssemblyInfo.cs` and any vendor-shipped
   `*_info.cs` (e.g. alglib) in `#if NET472`; let the SDK generate them on net8.
4. **MathNet.Numerics 5.0 API changes** — `Properties.Resources` (substitute
   English literals), `Control.LinearAlgebraProvider` (renamed),
   plus likely more across the `DataAnalysis/` tree.
5. **NHibernate transitive NU1605** — add `<NoWarn>$(NoWarn);NU1605</NoWarn>`
   to projects that pull NHibernate.
6. **`$(PLATFORM)` SQLite HintPath** — net472 keeps the HintPath;
   net8 uses `System.Data.SQLite.Core` NuGet.
7. **net472-only BCL refs** — explicit `System.Net.Http` / `System.Web` /
   `System.Security` `<Reference Include>` with `Condition='net472'`.

### Realistic remaining work

The multi-target pattern is proven; each leaf takes ~30 min – 2 hours to convert
**plus iterative debug on per-project source-compat issues that depend on
the project's NuGet dep surface**. Skyline.csproj alone will take 2-3 full
sessions because the dep mass is large and the binding-redirect / app.config
story has to be replaced.

**Best estimate: 5-10 sessions of dedicated work to reach "TestData tests
running with pwiz-sharp".** Multi-session is explicitly supported by the user;
no shortcut available.

### Done
  pwiz-sharp. Originally 6 suspected pwiz-sharp gaps; verification dig closed 5
  — they're already present. 1 real gap (`ReaderConfig.PassEntireDiaPasefFrame`)
  added as an advisory flag; Bruker reader implementation deferred until a
  TestData fixture exercises it. See
  `pwiz_tools/Shared/ProteowizardWrapper/NET8-PORT-NOTES.md`.
- **Phase 2 proof-of-concept landed.** Refactored MsDataFileImpl built against
  pwiz-sharp lives at `pwiz_tools/Shared/ProteowizardWrapper.PwizSharp/` (net8
  SDK-style csproj). Smoke runner at `…PwizSharp.Smoke/`. Reads a real
  Thermo-origin mzML, walks 48 spectra and 19,914-point binary arrays, extracts
  the TIC chromatogram, decodes instrument config (`LTQ FT` /
  `electrospray ionization` / `FT-ICR` / `inductive detector`), exercises QC
  trace + static helper surface. **29/29 checks PASS.**

Ported MsDataFileImpl members (running list):
- Ctor + Dispose + FilePath + SampleIndex
- RunId, IsProcessedBy
- IsThermoFile / IsAgilentFile / IsWatersFile / IsShimadzuFile / IsABFile
- SpectrumCount, GetSpectrumCount, GetSpectrumIndex, GetSpectrumId
- IsCentroided, GetMsLevel, GetStartTime, GetSpectrum (mz+intensity overload)
- GetScanTimes
- ChromatogramCount, HasChromatogramData, GetChromatogramId, GetChromatogram
- GetQcTraces + QcTrace class + QcTraceQuality + QcTraceUnits
- GetInstrumentConfigInfoList + MsInstrumentConfigInfo POCO
- Write
- IsValidFile, SupportsMultipleSamples, GetNonUnicodePath
- IsNegativeChargeIdNullable, IsSingleIonCurrentId
- PREFIX_* / TIC / BPC constants

That's ~30 of ~80 members — the TestData-most-frequent slice + supporting types.

### Blocked / Open

- **Cannot reach "all TestData tests passing" in one session.** Even with the
  refactored MsDataFileImpl working, the path to running Skyline's TestData
  suite requires SDK-style conversion of: Skyline.csproj (7,536 lines), Common
  (206 .cs files), CommonUtil (109 .cs files), CommonMsData (~250 files via
  219 pwiz.CommonMsData consumers), MSGraph, ProteomeDb, PanoramaClient,
  CommonFileDialogs, BiblioSpec wrapper, TestUtil, TestData. Each conversion
  has its own per-project issues (designer files, packages.config →
  PackageReference, custom build targets, AssemblyInfo merge). Realistic
  estimate: 1-3 weeks of focused conversion + debugging work, not hours.
- The user-chosen "refactor MsDataFileImpl in place" decision (vs. shim)
  blocks Phase 2's original "ship before converting Skyline" path —
  the refactored types need Skyline's `SignedMz` / `IonMobilityValue` /
  `SpectrumMetadata` / `ImmutableList<T>`, which live in Common /
  CommonUtil. To refactor in place AND keep Skyline buildable means either
  net48 ProteowizardWrapper multi-targets to net8 (pwiz-sharp can't downport —
  uses file-scoped namespaces, primary constructors, init-only properties) OR
  Skyline converts to net8 in lockstep. The sandbox at
  `ProteowizardWrapper.PwizSharp/` sidesteps this by reproducing only the
  pwiz-side surface and using pwiz-sharp's types verbatim.
- Remaining MsDataFileImpl members (~50): rich `GetSpectrum(int) → MsDataSpectrum`,
  `GetPrecursors`, `MsDataSpectrum` POCO, `MsPrecursor` struct, ion-mobility
  accessors, DiaPASEF config inference, lockmass refining wrapping, SONAR
  helpers. All map mechanically using the same techniques shown in the sandbox.

### Recommended next steps (multi-session friendly)

**The proven path forward is multi-targeting `net472;net8.0-windows`.** Decision
is made: legacy Skyline.sln keeps building net472 unchanged while the same
sources also build net8.0-windows. When the cascade reaches Skyline.csproj
itself, both Skyline.exe and Skyline.Net8.exe can ship in parallel until net8
is fully validated, then net472 retires.

**Conversion order (each step is one commit; ~1 hour each for leaves, scaling up):**

1. ✅ PortableUtil — already SDK-style net472;net8.0 (done before this branch)
2. ✅ CommonUtil — done in this branch
3. **Next: MSGraph** (~30 .cs files, leaf dep of Common)
4. **Then: ZedGraph fork** (`pwiz_tools/Shared/zedgraph/`) — large but
   well-isolated; ZedGraph 6+ supports net6+
5. **Then: Common** (206 .cs files, depends on CommonUtil + MSGraph + ZedGraph,
   + NHibernate which needs ≥5.5 for net6+)
6. **Then: ProteomeDb** (SQLite proteome layer, no pwiz dep)
7. **Then: CommonFileDialogs, PanoramaClient, CommonMsData** (parallel-ish)
8. **Then: ProteowizardWrapper** — convert csproj AND retarget MsDataFileImpl
   to use pwiz-sharp instead of pwiz.CLI. The
   `pwiz_tools/Shared/ProteowizardWrapper.PwizSharp/` sandbox already proves
   ~30 of ~80 methods work; merge those ports into the real
   `ProteowizardWrapper/MsDataFileImpl.cs` under `#if NET8_0_OR_GREATER` and
   port the remaining ~50 using the same techniques (`pwiz.CLI.msdata` →
   `Pwiz.Data.MsData`, `pwiz.CLI.analysis` → `Pwiz.Data.MsData.Analysis`,
   `pwiz.CLI.cv` → `Pwiz.Data.Common.Cv`).
9. **Then: BiblioSpec wrapper** — retarget to pwiz-sharp's BiblioSpec port
10. **Then: TestUtil** (test infrastructure)
11. **Then: Skyline.csproj** — the monolith (7,536 lines legacy → ~80 SDK)
12. **Then: TestData.csproj** + run TestData tests
13. Repeat for other Test* projects, SkylineCmd, SkylineTester, Executables/*

**At each step:**
- Build both `net472` and `net8.0-windows` targets, both must be green
- Run any project-local tests (if present)
- Commit before moving to the next project

**Source-code adjustments that recur across projects** (consolidated from the
CommonUtil pass):
- `.Reverse()` on arrays — use `Enumerable.Reverse()` explicit form
- `Microsoft.ConcurrencyVisualizer.*` — `#if NET472` wrapper
- `System.Net.Http` / `System.Web` / `System.Security` — net472-only assembly
  Reference; net8 picks them up via TargetFramework
- `$(PLATFORM)` SQLite — switch to NuGet on net8


## Objective

Three coupled migrations in one branch:

1. **Skyline (and its ~60 csproj satellite tree) ports from .NET Framework 4.7.2 to
   .NET 8.0 (`net8.0-windows`).** All projects convert from the legacy MSBuild
   csproj format to the SDK style at the same time.
2. **Skyline's vendor-data ingestion swaps from the native `pwiz.CLI` C++/CLI
   bindings to the managed `pwiz-sharp` C# port** sitting at `pwiz-sharp/` in
   this same repo.
3. **The Jam / `quickbuild.sh` orchestration is retired for Skyline-side builds
   in favor of plain `dotnet build` / `msbuild Skyline.sln`.** pwiz C++ retains
   Jam for `msconvert` and the vendor SDKs that Skyline no longer needs to ship.

End state: a Skyline you can clone, `dotnet restore`, `dotnet build`, and run
on a vanilla Windows 11 box with the .NET 8 desktop runtime — no Boost, no
bjam, no C++/CLI roundtrip, no native pwiz.dll deployment.

## State of the territory (survey, 2026-06-30)

### Framework

- ~78 csprojs under `pwiz_tools/Skyline/`. **48 are legacy v4.7.2** in old
  MSBuild csproj format — this is the dominant bucket and covers every "real"
  Skyline project. The handful already on `net8.0` are peripheral dev tools.
- The monolith: `Skyline.csproj` — **7,536 lines** of old-style csproj XML
  (every .cs file enumerated explicitly). Conversion to SDK-style is a delete-
  most-of-the-file operation but a big diff to review.
- Other big-ticket conversions: `TestFunctional.csproj` (802 lines),
  `Test.csproj` (473), `TestUtil.csproj` (348), `TestData.csproj` (319),
  `TestPerf.csproj` (286), `TestRunner.csproj` (161), `SkylineCmd.csproj` (140).
- Legacy v4.0 Client Profile (7 projects) for older ancillary tools: these
  may not migrate cleanly because v4.0 Client Profile types were removed.
  Decide per-project: kill, leave on .NET Framework, or rewrite.

### pwiz binding surface

Direct `pwiz.CLI.*` usage in Skyline is intentionally narrow — **only 5 .cs
files** touch it directly. The real coupling is via three managed Shared
wrappers:

| Namespace | .cs files | Role |
|---|---|---|
| `pwiz.CommonMsData` | 219 | Skyline's actual import / chromatogram surface |
| `pwiz.ProteowizardWrapper` | 74 | Thin facade over pwiz.CLI's `MSDataFile` |
| `pwiz.BiblioSpec` | 21 | Library build / DDA search results |

Critically: **`pwiz.CommonMsData` has zero direct `pwiz.CLI` references** — it's
already pure managed code sitting on top of `ProteowizardWrapper`. The actual
C++/CLI boundary lives in 4 files under `pwiz_tools/Shared/`:
`ProteowizardWrapper/MsDataFileImpl.cs`, `MsDataFileInfo.cs`,
`IterationListenerToMonitor.cs`, `DiaUmpire.cs`.

**This is the leverage point.** Re-pointing those 4 files at pwiz-sharp lets
the 219 `pwiz.CommonMsData` consumers and the 74 `pwiz.ProteowizardWrapper`
consumers in Skyline stay untouched modulo namespace renames.

Top consumer clusters: `Skyline.cs` / `SkylineFiles.cs` / `CommandLine.cs`
(top-level), `Model/Results/Chromatogram.cs` / `ChromCacheBuilder.cs` /
`SpectraChromDataProvider.cs` / `ScanProvider.cs` (chromatogram extraction +
cache), `Model/Lib/Library.cs` / `BiblioSpecLite.cs` (library), the import
dialogs (`OpenDataSourceDialog`, `ManageResultsDlg`, `FileUI/*Import*`), and
the test harness (~80 hits).

### pwiz-sharp's current surface

Verified present and net8.0-ready (already shipped):

- **MsData abstractions:** `MSData`, `MSDataFile`, `ISpectrumList`,
  `IChromatogramList`, `BinaryDataArray`, `BinaryDataEncoder`, `Spectrum`,
  `Precursor`, `Run`, `SourceFile`, `IReader`, `DefaultReaderList`,
  `IIonMobilitySpectrumList`, `IVendorCentroidingSpectrumList`,
  serializers/readers for mzML, mzXML, MGF, MSn, mz5, mzMLb, mzPeak.
- **Vendor readers (all 10):** Thermo, Agilent, Bruker (+TDF/TSF +
  PrmScheduling), Sciex (Wiff1+Wiff2), Waters, Shimadzu, UNIFI/WatersConnect,
  UIMF, Mobilion. Each as `Reader_*` + `SpectrumList_*` + `ChromatogramList_*`.
  Vendor harness round-trip green across all of them
  (`TODO-20260616_pwiz_sharp_mzpeak.md` 114/114).
- **Analysis layer (~60 files):** SpectrumListFactory / ChromatogramListFactory,
  peak picker, smoother, lockmass refiner, ion-mobility, charge-state
  calculators, MZRefiner, demultiplexer, filters, **full DiaUmpire port** (15
  files), **Msx + Overlap demultiplexers** (direct map onto Skyline's
  `MsxDemultiplexer` / `OverlapDemultiplexer`), CWT/LocalMax/Savitzky-Golay
  peak picking, Ms2Deisotoper / ETD precursor / MS2 noise filters.
- **Common:** CV table (`CVID.generated.cs`), CVParam/UserParam/ParamContainer,
  Unimod, OboParser, full `Proteome/` (Fasta, Digestion, ProteomeData,
  ProteinList).
- **BiblioSpec:** Full managed port — BlibBuild/Filter/Search/ToMs2 programs,
  ~30 file-format readers (PepXML, MzIdentML, Mascot, MaxQuant, Hardklor,
  DiaNN, MSF, OSW, Pride, Proxl, Percolator, ProteinPilot, ShimadzuMLB,
  Tandem, MzTab, TSV, SQT, SSL, WatersMse), `BlibMaker`, `BlibBuilder`,
  `BlibFilter`, `BlibSearch`, `PwizSharpSpecFileReader` (bridges BiblioSpec
  to pwiz-sharp MsData), `MascotShimInterop` (P/Invoke to Matrix Science
  msparser).

### Notable gaps

These need pinning down before mass-rewiring:

- **No drop-in `MsDataFileImpl` facade.** pwiz-sharp exposes the canonical
  `MSDataFile` shape, but `MsDataFileImpl` was hand-crafted with extra
  Skyline-shaped helpers (chromatogram pulls, scan-range queries, ion-
  mobility access, predicate caching). Either retarget consumers at
  `MSDataFile` directly or write a thin shim that preserves the public surface.
- **`ProteomeDb` / proteome SQLite layer** has no pwiz-sharp equivalent
  surfaced. Likely stays in Skyline (it's not really a pwiz concern), but
  verify before assuming.
- **`MsDataFileInfo` / `IterationListenerToMonitor`** — small surface to swap.
- **`DiaUmpire.cs` wrapper** in Shared talks to pwiz.CLI; pwiz-sharp's
  DiaUmpire port is present but the C# wrapper needs rebinding.

### Build orchestration

Jamfiles total **1,281 lines across 6 files** under `pwiz_tools/Skyline/`,
dominated by one 689-line `Jamfile.jam` at the Skyline root. SkylineTester
doesn't reference Jam directly (grep clean). CI is single-track:
`.github/workflows/build_and_test.yml` and `appveyor.yml` both call
`./quickbuild.sh ... pwiz executables` (bjam-based).

## Strategy: leverage the wrapper chokepoint

The 4-file `Shared/ProteowizardWrapper` chokepoint changes the size of this
project dramatically. Plan:

1. **Don't try to rewrite 219 + 74 + 21 callers.** Re-implement the public
   surface of `ProteowizardWrapper.MsDataFileImpl` (and its 3 siblings) as a
   shim delegating to pwiz-sharp. Same namespace and class names; same method
   signatures; new internals.
2. **Same for `BiblioSpec` wrapper.** pwiz-sharp's BiblioSpec port is already
   structured to be a drop-in.
3. **csproj modernization is independent of the binding swap** — they could be
   sequenced separately. But they overlap in the projects they touch, so
   doing them in one branch keeps the diff coherent.

## Phases

### Phase 1 — Reconnaissance and gap fill (2-3 days)

- Catalogue every public member of `ProteowizardWrapper.MsDataFileImpl` and
  its 3 siblings. Diff against `pwiz-sharp/pwiz/src/MsData` to find what's
  missing on the pwiz-sharp side.
- Add any missing helpers to pwiz-sharp (likely small — chromatogram pulls
  by id, scan-range queries, predicate caching for repeated calls).
- Decide: shim vs. wholesale retarget. Recommend shim — keeps blast radius
  contained, lets the 293 consumer files stay byte-identical apart from
  package references.
- Smoke-test the shim against a handful of representative imports
  (Thermo .raw, Agilent .d, Bruker .d, Waters .raw, mzML, mzMLb).

**Success:** `MsDataFileImpl` shim builds against pwiz-sharp; produces
identical `SpectrumList` / `ChromatogramList` contents to today's CLI binding
on 3+ vendor fixtures.

### Phase 2 — Swap the wrappers, still on .NET Framework (3-5 days)

- Re-point `pwiz_tools/Shared/ProteowizardWrapper/MsDataFileImpl.cs` and 3
  siblings at pwiz-sharp internals via the shim.
- Same for `pwiz_tools/Shared/BiblioSpec` consumers — pwiz-sharp's BiblioSpec
  port replaces the C++ BlibBuild.
- Keep Skyline on .NET Framework throughout this phase. The shim builds as
  net472 + net8.0 multi-target so both consumer worlds stay live during the
  transition.
- Run Skyline's full functional suite to catch regressions early.

**Success:** Skyline.exe still builds under MSBuild/Jam, but its only pwiz
dependency is pwiz-sharp.dll. The native `pwiz.dll` / `pwiz_data_msdata.dll`
chain leaves the Skyline runtime payload.

### Phase 3 — SDK csproj migration in dependency order (5-7 days)

Convert projects bottom-up. Each conversion swaps:
- Old `<TargetFrameworkVersion>v4.7.2</TargetFrameworkVersion>` → SDK style
  `<TargetFramework>net8.0-windows</TargetFramework>`.
- File globbing replaces the explicit file list.
- `packages.config` → `<PackageReference>` per project.
- AssemblyInfo metadata moves into csproj `<PropertyGroup>`.

Order (rough):
1. Util libraries (DotZLib, Common, MSGraph, ZedGraph fork) — leaf nodes.
2. `Shared/ProteomeDb` — leaf-ish, SQLite consumer.
3. `Shared/ProteowizardWrapper` + `Shared/CommonMsData` + `Shared/BiblioSpec`
   — the wrappers swapped in Phase 2.
4. `SkylineCmd.csproj` — smaller commandline tool, good shakedown.
5. `Skyline.csproj` — the monolith. 7.5k-line diff but largely a delete.
6. Test projects: `TestUtil`, `Test`, `TestData`, `TestFunctional`,
   `TestPerf`, `TestTutorial`, `TestConnected`, `TestRunner`, `TestRunnerLib`.
7. `SkylineTester` (`SkylineTester.csproj` + `SkylineTesterAA.csproj`).
8. Executables tree — convert what's worth converting, leave the rest on
   .NET Framework or retire.

**Success:** `dotnet build pwiz_tools/Skyline/Skyline.sln` produces a runnable
Skyline.exe targeting net8.0-windows. All tests compile (passing them is
Phase 4+ work).

### Phase 4 — Build orchestration retire (2-3 days)

- Replace the Skyline-rooted Jamfile.jam (689 lines) with a thin
  `Build-Skyline.ps1` (probably already exists in some form via the ai/scripts
  tree — there's a `Build-Skyline.ps1` referenced in MEMORY.md) that drives
  `dotnet build` + content-staging.
- Wire `pwiz_tools/Skyline/Executables/Installer` (WiX) into MSBuild as the
  installer target. WiX 4 supports net8.0.
- Carry forward the small per-tool Jamfiles only if their target hasn't been
  retired (`ResourcesOrganizer`, `Hardklor`, `TutorialLocalization`,
  `TestDiagnostics`, `Installer`). Convert the simple ones; leave Hardklor
  on Jam if it's truly C++.
- SkylineTester's runtime configuration shouldn't change — it shells to
  TestRunner.exe, not Jam.

**Success:** `dotnet build` (or `Build-Skyline.ps1`) is the only command
required for a Skyline build. No Boost, no bjam, no `quickbuild.sh` for the
Skyline-side payload.

### Phase 5 — CI swap (1-2 days)

- Add a new GitHub Actions workflow `.github/workflows/skyline_dotnet.yml`
  that runs `dotnet build` + `dotnet test` on a windows-latest runner.
- Run it alongside the existing `build_and_test.yml` (bjam) for at least one
  release cycle so regressions can be caught before retiring the old lane.
- Update Appveyor similarly or retire it.

**Success:** Green CI on the dotnet lane for ≥1 PR cycle without falling back
to the Jam lane for Skyline-side validation.

### Phase 6 — Long tail (1-2 weeks, parallelisable)

- Native interop audit: every `[DllImport]` and `LoadLibrary` in Skyline and
  Shared. Vendor SDK packaging audit — pwiz-sharp's vendor readers already
  pin SDK versions; align Skyline's installer payload with that pinning.
- ZedGraph / NHibernate / SQLite / log4net / Crystal Reports compatibility
  pass. ZedGraph is the riskiest — Skyline forks it and that fork needs
  net8 retargeting.
- WinForms-on-net8 edge cases: GDI+ printing, IME, accessibility,
  System.Drawing primitives, designer round-trip on Visual Studio.
- Test suite reds: any test that hard-codes a pwiz.CLI type name or asserts
  on a stack trace through C++/CLI will need updating.
- Performance regression sweep: import a representative .raw and compare
  pre/post import wall-clock and peak memory. Tolerance to be set after a
  baseline run, but expect parity within 10% or investigate.

## Open questions (need answers before Phase 2 begins)

1. **Drop net48 outright, or dual-target during migration?** Dual-target makes
   the wrappers backward-compatible during Phase 2 but doubles the build
   matrix and surfaces analyzer pain. Recommend net48 + net8.0 only during
   Phase 2; single-target net8.0 from Phase 3 onward.
2. **Wholesale retarget of `MsDataFileImpl` callers, or shim that preserves
   the public API?** Recommend shim (per the strategy section). The cost of
   touching 293 files with byte-identical edits is not free, even if
   mechanical.
3. **Stays in Skyline or moves to pwiz-sharp:** `ProteomeDb` (SQLite proteome
   layer); `MsDataFileInfo` (lightweight pre-open metadata probe); the
   `IterationListenerToMonitor` progress shim. Recommend leaving all three in
   Skyline — they're not pwiz concerns, they're Skyline UI concerns.
4. **ZedGraph fork:** retarget to net8 in place, or replace with a different
   charting library? Replace is out of scope here; in-place retarget then.
5. **Vendor SDK packaging:** Skyline today ships pwiz's bundled vendor DLLs
   inside `Skyline\bin\<config>\<sdk>\`. pwiz-sharp's bundling is per-project.
   Reconcile on a single layout — recommend Skyline's installer aligns with
   pwiz-sharp's runtimes/<rid>/native layout.
6. **Microsoft.Office.Interop usage:** Skyline ships Excel export via Office
   interop. Office PIAs work on net8 but require modernized references; flag
   for Phase 6.
7. **Crystal Reports:** does Skyline still need it? If yes, the SAP runtime
   has net8 support; if no, retire.

## Risks and tradeoffs

- **Performance.** Skyline's import is hot — vendor reads + chromatogram
  extraction can take many minutes per file. pwiz-sharp's vendor readers must
  match throughput. Profile early on a representative Thermo and Bruker
  fixture before committing to the swap.
- **Vendor SDK ABI drift.** pwiz native bindings call vendor SDKs through
  C++; pwiz-sharp calls through P/Invoke or interop assemblies. The
  marshalling boundaries are different — expect a long tail of
  vendor-specific issues (Thermo IRawFileThreadManager lifecycle, Bruker
  timsdata 32-bit handles, Waters MassLynx COM apartment threading).
- **Designer round-trip.** WinForms designer files in Skyline reference
  ZedGraph + custom controls; some break on the SDK-style csproj move
  because the designer expects the legacy file list. Plan for a manual fix
  pass.
- **Test runtime divergence.** TestRunner spawns Skyline.exe and SkylineTester
  shells to TestRunner. Both need to survive the framework swap; the
  spawn-and-wait helpers may need exit-code handling tweaks.
- **Diff size.** Phase 3 alone is ~7,500 lines of Skyline.csproj going away
  plus 60 other csprojs. Code review will be hard if it lands as a single
  commit. Split per-project and merge incrementally on the branch.
- **Boost / Jam still required for `msconvert`.** This plan doesn't retire
  Jam for pwiz C++ — `msconvert` and its vendor SDK orchestration stay on
  Jam. Skyline just stops needing it. State that clearly to anyone reviewing.

## Verification

```powershell
# Phase 1
dotnet build pwiz-sharp\Pwiz.sln
pwsh -File pwiz-sharp\scripts\Run-Tests.ps1 -TestName MsData

# Phase 2 (on .NET Framework still)
msbuild pwiz_tools\Skyline\Skyline.sln /p:Configuration=Debug
# expect pwiz.CLI references gone from the bin output

# Phase 3
dotnet build pwiz_tools\Skyline\Skyline.sln
.\pwiz_tools\Skyline\bin\Debug\net8.0-windows\Skyline.exe   # smoke

# Phase 4
pwsh -File ai\scripts\Skyline\Build-Skyline.ps1
pwsh -File ai\scripts\Skyline\Run-Tests.ps1 -TestName <fast subset>

# Phase 6 — perf
# Time a representative Thermo + Bruker import end-to-end and compare to
# baseline captured before Phase 2.
```

## Key files

- `pwiz_tools/Shared/ProteowizardWrapper/MsDataFileImpl.cs` — the chokepoint.
- `pwiz_tools/Shared/CommonMsData/` — already pure managed, mostly leave alone.
- `pwiz_tools/Skyline/Skyline.csproj` — the monolith.
- `pwiz_tools/Skyline/Jamfile.jam` — the orchestration to retire.
- `pwiz-sharp/pwiz/src/MsData/` — the new ingestion layer.
- `pwiz-sharp/Tools/BiblioSpec/` — the new library-build layer.
- `.github/workflows/build_and_test.yml` — the bjam CI to replace.

## Out of scope

- pwiz C++ side of the world: `msconvert`, the vendor SDK builds, `IDPicker`,
  `Bumbershoot`, anything under `pwiz/` proper. Jam stays for these.
- Skyline's web extensions / SkylineRunner / external Tools store.
- Linux/macOS support for Skyline (still Windows-only; net8.0-windows).

## References

- `ai/todos/active/TODO-20260616_pwiz_sharp_mzpeak.md` — recent pwiz-sharp
  work; vendor harness state.
- `ai/docs/version-control-guide.md` — commit/PR format.
- `ai/WORKFLOW.md` — branch lifecycle.
