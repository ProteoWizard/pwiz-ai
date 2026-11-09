# Update CE optimization workflow to read actual CE values for waters_connect data

## Branch Information
- **Branch**: `Skyline/work/20260910_WatersConnectActualCE`
- **Base**: `master`
- **Created**: 2026-09-10
- **Status**: In Progress
- **GitHub Issue**: [#4346](https://github.com/ProteoWizard/pwiz/issues/4346)
- **Module**: `skyline`
- **PR**: [#4683](https://github.com/ProteoWizard/pwiz/pull/4683)
- **Checkout**: `pwiz2`

## Objective

Update the collision energy (CE) optimization workflow to read actual CE values from waters_connect data,
rather than relying on CE step increments encoded as product m/z shifts in methods/data.

The issue's second request (reduce the product m/z step to 0.001 Da) is dropped by agreement with the
developer: once the exported waters_connect method carries the real product m/z, there is no mass change.

Source: waters_connect Skyline integration feedback (2026-06-17), item 6. Jira: INFMTD-306.

## Design

* **Export**: waters_connect methods get the real product m/z for every CE step (no 0.01 Da per-step
  shift); CE per step is already the actual value. Only step 0 is flagged as the quant ion.
* **Reader (C++)**: waters_connect MRM channels expose their CE as `MS_collision_energy` on the
  chromatogram precursor activation (never read before).
* **Import**: before the loader runs, waters_connect data (detected by the `MS_waters_connect` software
  CV term, so msconverted mzML behaves the same as live server data) has channels with identical
  precursor/product m/z and distinct CE sorted by CE and their product m/z shifted by
  `ChromatogramInfo.OPTIMIZE_SHIFT_SIZE` per step. The Skyline loader (`ChromDataProvider`) is unchanged.
* **Backward compatibility**: old files acquired with shifted product m/z have a unique Q3 per channel,
  so nothing is shifted and they load exactly as before.

## Tasks

- [x] C++: parse `msTechnique.fragmentationProperties.collisionEnergy` in `WatersConnectData.ipp`,
      store on `UnifiChromatogramInfo`, set `MS_collision_energy` in `ChromatogramList_UNIFI.cpp`
- [x] C#: `MsDataFileImpl.IsWatersConnectFile` + product m/z shift in `GetChromatogramMetadata`
      (math in a pure helper `WatersConnectCeSteps`)
- [x] Export: waters_connect product m/z unshifted, quant ion only on step 0
- [x] Unit test for the shift math (`WatersConnectCeStepsTest`, Test project)
- [x] Extend `WatersConnectMethodExportTest` with a CE optimization export (`TestCeOptimizationExport`)
- [x] Build (native + Skyline) and run the tests
- [x] Regression run (all pass, Release x64): TestAgilentCeOptimization, TestAgilentCEOpt, TestAsymCEOpt,
      TestMissingOptSteps, TestIsOptimizationSpacing, TestVerifyOptimizationSpacingInFile,
      TestImportOptimizationChromatograms, TestOptimization, TestPrmCeOptimization, TestLegacyOptimizationStep,
      TestChromDataSetMatching, TestExportMethodDlg, ConsoleMethodTest, TestSmallMolMethodDevCEOptTutorial,
      TestCEOptimizationTutorial
- [x] Import test with old-style and actual-CE waters_connect data (`WatersConnectCeImportTest`)
- [x] Reader reference mzML: no regeneration needed - all existing devconnect MRM data reports CE as NaN,
      so the reader adds no CE param for it

## Regression Test

- **Test name**: `TestWatersConnectCeSteps` (shift math); `TestWatersConnectExportMethodDlg` ->
  `TestCeOptimizationExport` (export); `TestWatersConnectCeImport` (import, both data styles)
- **Test project**: Test (shift math), TestFunctional (export, import)
- **Fails on master**: yes - with master's `Export.cs`, `TestCeOptimizationExport` fails at line 414
  (22 distinct product m/z vs 2 expected: the steps are shifted). `WatersConnectCeSteps` does not exist on master.
- **Passes on fix**: yes - all three tests pass (Release x64; export test looped 4x), 2026-09-10 / 2026-09-17
- **Import test red/green (2026-09-17)**: with the shift line in `MsDataFileImpl.GetChromatogramMetadata`
  commented out, `TestWatersConnectCeImport` fails with area 0 for every step of the actual-CE file; with it
  restored the two files agree step for step.

## Import test data

Stephen (Waters) added a CE-step run on devconnect: sample set `2c8b56a1-81d7-41ed-9cdd-450b015c69e9`,
injection `75fb8289-e287-492a-a81a-0eca56738ff3` ("6-Mix", folder Skyline/6mix). 121 MRM channels with
**numeric CE**, 11 transitions x 11 steps (2 V apart, step count 5), product m/z still shifted per step
because the method came from the current export. Converted with the rebuilt msconvert; the mzML keeps the
`MS_waters_connect` software term, which is what switches the shift on.

`TestFunctional/WatersConnectCeImportTest.zip` holds:
* `6Mix.sky` - built from the channel list (center product m/z and center CE per transition, CE regression
  step size 2 / count 5); scripts in `ai/.tmp/sessions/20260910-4346/`
* `6Mix-CEsteps-shifted.mzML` - the converted run as acquired (old style)
* `6Mix-CEsteps-actual-ce.mzML` - the same run with each series' product m/z set to its center value, which is
  what a method exported without the shift acquires (stand-in until such a run can be acquired)

## Progress Log

### 2026-09-10 - Session Start

Explored export (`WatersMassListExporter.WriteTransition`, `Export.cs:4697` shifts product m/z per step)
and import (`ChromDataProvider.SetOptStepsFromProductMz`; waters_connect reader never reads CE).
Agreed design with the developer: shift applied before the loader, gated on the waters_connect software
CV term; test data (new-style and old-style CE optimization runs) requested from the Waters team.

Scanned devconnect (scripts in ai/.tmp/sessions/20260910-4346/): 120 MRM injections, none new-style.
`DataRoot/Company/Skyline/SmallMolOptimization` / "CE Opt" (5 injections, ID33144 EnergyMet tutorial data) is
old-style (product m/z shifted 0.01 per step). Every MRM channel reports `fragmentationProperties.collisionEnergy`
= NaN in both `/channels` and `/channels/mrm`; CE is only in the channel title ("145>100.98 1eV"). Open question
for Matt / Waters: do current acquisitions populate the numeric field, and is a title fallback needed?
Import tests ON HOLD until the developer settles how to obtain the test data.

Implemented the reader, shift, and export changes plus the unit and export tests. Build gotcha: the
Claude Code harness sets `NoDefaultCurrentDirectoryInExePath=1`, so `cmd /c build_skyline_64.bat` reports
"not recognized"; the detached launcher clears it before running the build.

### 2026-09-17 - Review and PR

Ran /code-review max: 20 items. Refuted finding 5 (reference mzML needs no regeneration - all existing
devconnect MRM data reports CE as NaN, verified by re-converting the Hazell injection). Acted on the rest in
two commits: moved the CE spacing from MsDataFileImpl into ChromatogramDataProvider (shared library keeps no
Skyline semantics, short series anchor from the highest CE, duplicated constant removed), then fixed the
cases where CE cannot identify a step (no predictor, whole-volt collisions, DP optimization), put the quant
ion on the center step without relying on ParseMethod's fallback, and accepted a quoted CE in the reader.
Finding 13 (SortByMz) left alone deliberately; finding 14 (ChromKey.FromId and a comma in the chromatogram
ID) is pre-existing and now in todos/backlog/TODO-chromkey_fromid_comma_in_chromatogram_id.md.

Uploaded a CE optimization method built by this code to devconnect (Skyline/6mix, 6Mix-ceopt-09171440) for
Waters to acquire; the server accepted steps that differ only in CE, which confirms the export premise. Note
the template must be a tandem-MS method - the Lancaster LC template was rejected with TargetsNotSupported.
PR #4683 opened.

### 2026-11-09 - Merge master after the C++ tree retirement

PR #4683 had been conflicting with master since #4658 retired the C++ tree and hoisted the C# port into
`pwiz/data/...`, #4789 normalized stored line endings to LF, and the .NET 10 port made the csproj files
SDK-style with auto-globbed Compile items. Merged `origin/master` into the branch in pwiz2 (no rebase):

* The three C++ reader files are deleted on master; ported the CE read to the C# UNIFI reader instead.
  `UnifiChromatogramInfo.CollisionEnergy` (UnifiData.cs), parsed from
  `msTechnique.fragmentationProperties.collisionEnergy` in `WatersConnectDataSource.FetchMrmChromatograms`
  (finite number or quoted number kept as a magnitude; NaN, null and missing read as 0) and set as
  `MS_collision_energy` in eV on the precursor activation in `ChromatogramList_UNIFI.FillSrmChromatogram`.
* Took master's copies of Export.cs, ChromDataProvider.cs and MsDataFileImpl.cs and re-applied the PR hunks;
  dropped the three csproj edits (globbed now); `git add --renormalize` so every PR file is stored LF.
* The .NET 10 build compiles `ProteowizardWrapper.PwizSharp/MsDataFileImpl.cs`, not the legacy wrapper file,
  so `IsWatersConnectFile` lives in both (as `IsShimadzuFile` does).
* Reader tests: `Discovery_MrmChannels_ReadCollisionEnergy` (WatersConnectDataSourceTests, six CE spellings)
  and CE assertions in `GetChromatogram_SRM_PopulatesQ1Q3AndPolarity` plus
  `GetChromatogram_SRM_WithoutCollisionEnergy_SetsNoActivation` (ChromatogramListUnifiTests). UNIFI.Tests
  46/46 pass; Skyline Debug build clean with `-VendorLicenses`; the three PR tests and all 15 regression tests
  from the PR body pass, the two CE optimization tutorials among them (TestTutorial built separately).
* Run-Tests.ps1 gotchas: a long comma list becomes the log file name and fails before any test runs, so use
  `@file`; TestTutorial is not part of the solution build, so build it with `-Target TestTutorial` first.

### 2026-11-09 - Live check of the C# reader against devconnect

* `Reader_UNIFI_HarnessAgainstReferenceUrls` with `WC_PASSWORD` set read both devconnect fixtures live and matched the
  references, the Hazell MRM injection among them, so the server does not send a bare `NaN` token for older MRM
  channels (System.Text.Json would have rejected it); `"NaN"` or null reads as 0 and no CE param is written, as before.
* Converted the 6-Mix CE-step injection (75fb8289) with the C# msconvert built from this branch: 242 SRM chromatograms,
  121 CE params in eV, per-chromatogram id/CE sequence identical to the September C++ conversion in the test zip.
  The server delivers numeric CE as JSON numbers (the first commit parsed numbers only and produced that file).
* Still unverified: a run acquired from a method exported by this code (6Mix-ceopt-09171440 was uploaded for Waters).
* Gotchas: the harness needs `-VendorLicenses` (no-vendor UNIFI makes Read throw) and the password in the PROCESS
  environment - user-level `setx` values are not inherited by shells spawned from an already running Claude Code, so
  copy them in with `$env:WC_PASSWORD = [Environment]::GetEnvironmentVariable("WC_PASSWORD","User")` first.
* Pre-push inspection on the merged tree: CodeInspection test passes; tcinspect.ps1 (CI-equivalent ReSharper run) reports
  success with no warnings. tcinspect had been failing with "inspectcode exited with code 4" on this machine because a
  gitignored Boost.Build-era `SkylineTester/Properties/AssemblyInfo.cs` duplicated the SDK-generated attributes; moving
  that leftover out of the checkout fixed it. PR description updated for the C# reader port and the live checks.
