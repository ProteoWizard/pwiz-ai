# TODO-20260629_thermo_rawfilereader_cv_update.md

## Branch Information
- **Branch**: `Skyline/work/20260629_thermo_rawfilereader_cv_update`
- **Base**: `Skyline/work/20260612_net8_port` (the .NET 10 port, PR #4619) — retargeted 2026-09-21;
  was `master`
- **Checkout**: `C:\dev\pwiz-msconvert-pr` (git worktree)
- **Module**: `pwiz` (CV data + pwiz-sharp readers; nothing under `pwiz_tools/Skyline`)
- **Created**: 2026-06-29 (as a master PR); retarget started 2026-09-21
- **Status**: retargeted and pushed 2026-09-21 (`bcab0f28d0`, one commit, force-push over `8981502bc1`); PR base/title/label/description updated; CI running
- **PR**: [#4339](https://github.com/ProteoWizard/pwiz/pull/4339)

## Objective

Land the PSI-MS / UNIMOD CV refresh and the two new Thermo instruments (Orbitrap Tribrid Apex,
Orbitrap Excedion) on the .NET 10 port instead of master.

## Why the master PR stalled

The master version carried Thermo RawFileReader 5.1.0.27 (the Net48 line) for the C++ msconvert,
which dragged in System.Memory 4.0.5.0 + a .NET Framework 4.8 bump + binding redirects for
~100 csproj/app.config files. That combination broke Thermo under the Wine container
(`System.Memory` could not bind through the redirects), and the PR was never merged.

None of that applies on the .NET port:

- pwiz-sharp's Thermo reader uses the **.NET 8 line** of RawFileReader (8.0.6.0 in
  `pwiz-sharp/vendor-archives/vendor_api_Thermo.7z`), a newer build than the PR's 5.1.0.27.
  **Decision (Matt, 2026-09-21): do not touch the archive.** (Thermo's GitHub now ships 8.0.42
  for .NET 8, with an OpenMcdf 3.1.4 dependency; a bump is a separate change if ever wanted.)
- .NET Core binds by simple name; there are no binding redirects to get wrong.
- Everything managed runs on Linux natively, so the Wine container is a regression check
  rather than the deployment target.

## What the retargeted branch carries

Rebuilt on top of `origin/Skyline/work/20260612_net8_port` (`d18cc24983`); the master-era tip
`8981502bc1` is tagged locally as `pr4339-master-era`.

Kept from the master PR (C++ tree — still present on the port branch until #4658 retires it,
and `psi-ms.obo` / `cv.hpp` are live inputs to pwiz-sharp: the OBOs are embedded resources parsed
at run time, `CVID.generated.cs` is generated from `cv.hpp`):
- `pwiz/data/common/{psi-ms.obo 4.1.232→4.1.257, unimod.obo, cv.hpp, cv.cpp, cvgen.cpp, cvtest.cpp}`
- `pwiz/utility/bindings/CLI/common/{cv.hpp, cvgen_cli.cpp}` (same MS_TOF_TOF dedup fix)
- `pwiz/data/identdata/{IdentData.cpp, Serializer_pepXML.cpp}`, `pwiz/data/msdata/LegacyAdapter.cpp`,
  `pwiz/data/vendor_readers/Thermo/Reader_Thermo_Detail.cpp`,
  `pwiz_aux/msrc/utility/vendor_api/thermo/RawFileTypes.h` — reference implementation for the
  C# ports below; C++ CI does not run on the port branch (validated on master CI in June)
- `.gitattributes`: `*.7z binary`

Dropped: `pwiz_aux/msrc/utility/vendor_api_Thermo.7z` (5.1.0.27), the thermo `Jamfile.jam`
System.Memory assemblies, `pwiz_tools/Shared/Lib/System.*.dll`, every csproj/app.config
net472→net48 + binding-redirect edit.

C# side (pwiz-sharp):
- `pwiz/src/Common/generate_cvid.py`: fixed the stale output path (still wrote to the
  pre-relayout `pwiz-sharp/src/Pwiz.Data.Common/Cv/`), regenerated `CVID.generated.cs`
  (+173 enum names, 14 removed — the `MS:10037xx` instrument-class terms gained an
  `_instrument` suffix, three GC-MS system-model terms were dropped upstream)
- `pwiz/src/Vendor/Agilent/Reader_Agilent.cs` + `Agilent.Tests`: the three instrument-class
  CVIDs renamed
- `pwiz/src/Common/OboParser.cs`: unescape `\!` `\:` `\,` `\(` `\)` `\[` `\]` `\{` `\}` in
  names and synonyms, as cpp `obo.cpp` does — the refreshed OBO escapes the `!` in the
  cleavage-regex term names (`(?<=[ALIV])(?\!P)`), which the verbatim parser would have kept.
  Test in `OboParserTests`
- `pwiz/src/Vendor/Thermo/{ThermoInstrumentModel.cs, Reader_Thermo.cs}`: `ORBITRAP EXCEDION`
  → `MS_Orbitrap_Excedion` (was mapped to Excedion Pro), new `TRIBRID APEX` →
  `MS_Orbitrap_Tribrid_Apex`; IC recipes (Excedion = quad+orbitrap, Tribrid Apex = Fusion-style
  two ICs). `ThermoInstrumentModelTests` rows + `ThermoModelReference.tsv` rows for both
  (the TSV is a static fixture now — its cpp generator was removed in `39e15e29af`; rows were
  derived by hand from the same `RawFileTypes.h` / `Reader_Thermo_Detail.cpp` cases)

No C# counterpart exists for the pepXML cleavage-agent / `snapModificationsToUnimod` /
`LegacyAdapter::manufacturer` fixes: pwiz-sharp's identdata port has no enzyme-specificity
table or Unimod snapping, and `MzxmlWriter.ResolveManufacturer` already walks `is_a`
transitively (so the new multi-parent instrument terms resolve to the brand without a fix).

Not done: bumping to the current upstream psi-ms.obo (4.2.2, 2026-09-18, 6061 terms vs 4113)
— needs the C++ `cvgen` re-run and is a separate, larger change.

## Verification

- [x] `pwiz-sharp` `dotnet build Pwiz.sln` Release + vendor: clean
- [x] pwiz-sharp tests: Common 58, Thermo 15, Agilent 17, and the other 18 suites via
      `Run-Tests-Parallel.ps1` all green (Installer.Tests not run — builds an installer)
- [x] Skyline net10 `build.bat Release --i-agree` with `SKYLINE_TEST_ARGS=test=TestData.dll,TestInstrumentInfo`:
      179 tests, 0 failures (ThermoFormatsTest, AgilentFormatsTest, TestInstrumentInfo among them)
- [x] Thermo on Linux natively: `dotnet publish -r linux-x64 --self-contained -p:PwizTargetIsWindows=false`
      of MsConvert + MsDiff (Windows host; vendor DLLs left app-local), copied onto the container fs,
      `scripts/container/tctest.sh --vendor Thermo` in `ubuntu:24.04` (+libicu74): **7/7 match**.
      Full msdiff on BSA-FT-HCD: only sourceFile locations / SHA-1 / command line / softwareRef differ
- [x] Thermo under Wine: this branch's win-x64 msconvert+msdiff bin (robocopy of the MsConvert
      output + msdiff into `installer/build/wine-stage`) run via `wine` inside `pwiz-net10:twopayload`
      (its installed 10.0.11 runtime, `DOTNET_ROOT` preset): **7/7 match**, output stamped
      psi-ms 4.1.257. Scripts: `pwiz-sharp/installer/build/{wine,linux}-thermo-sweep.sh` (gitignored)
- [x] Pushed (force, lease on the old tip), `gh pr edit --base Skyline/work/20260612_net8_port --add-label pwiz`, title prefixed `pwiz:`, description rewritten
- [ ] CI: Core Windows .NET #4182205, Skyline Windows .NET #4182208 (VCS-triggered), CodeQL

Docker gotchas hit: mounting the session scratchpad (`%LOCALAPPDATA%\Temp\claude\...`) makes
`docker run` fail with `error during connect ... EOF` (not a shared path) — put scripts under
`C:\dev\pwiz*`; and Git Bash rewrites `/scratch` in `-v` to `C:/Program Files/Git/scratch`
(`MSYS_NO_PATHCONV=1`). The linux-x64 publish with `PwizTargetIsWindows=false` rebuilds every
referenced pwiz-sharp project Linux-flavored in place; rebuild `Pwiz.sln` afterwards.

## Progress

- 2026-09-21: parked `C:\dev\pwiz-msconvert-pr`'s unrelated uncommitted `.editorconfig`
  change as WIP `afdd899bb5` on `Skyline/work/20260917_resharper_inspection_noise`, then
  rebuilt the branch as above. Verified (see above), committed as `bcab0f28d0`, force-pushed,
  PR retargeted. Waiting on CI.
