# TODO-20261029_pwiz_resharper_inspection.md

## Branch Information
- **Branch**: `Skyline/work/20261029_pwiz_resharper_inspection` (created 2026-10-29)
- **Checkout**: `C:\Dev\CodeInspection`
- **Module**: `pwiz`
- **Base**: `origin/master`
- **Status**: In progress. Step 1 (settings) committed locally, not pushed.
- **GitHub Issue**: (none)
- **PR**: (none)

## Objective

Extend the ReSharper code inspection that gates Skyline.sln to the ported C# in Pwiz.sln
(pwiz core, vendor readers, BiblioSpec, msconvert, MSConvertGUI, SeeMS, MsDiff, ...), with
the same rules except where ported code legitimately differs - first of all localization,
which SeeMS, MSConvertGUI and the command-line tools do not do.

## Findings so far (2026-10-29)

Measured with `dotnet jb inspectcode Pwiz.sln --no-swea -e=WARNING` (the tool pinned in
`pwiz_tools/Skyline/.config/dotnet-tools.json`, 2025.3.3), run from `pwiz_tools/Skyline`.
About 3-4 minutes on a built tree.

- **Baseline with Skyline's rules** (`--profile=Skyline.sln.DotSettings`): 4407 findings.
  SeeMS 2461 (1702 of them `TabsAreDisallowed`), Analysis 363, MsData 274, MsConvertGUI 184,
  everything else under 100. By type: tabs 1702, `RedundantNameQualifier` 864,
  `RedundantUsingDirective` 530, `CheckNamespace` 261, `LocalizableElement` 130, ~150
  nullable-contract warnings, 67 `EmptyGeneralCatchClause`, 5 CS0162 reported as ERROR
  (`SpectrumList_ChargeFromIsotope.cs`, `MSFReader.cs`).
- **The 7 projects shared with Skyline.sln** (ZedGraph, MSGraph, CommonUtil, CommonMsData,
  CommonBaseUI, CommonFileDialogs, ProteowizardWrapper) show 0 under Skyline's rules and 2536
  under ReSharper defaults. Pwiz.sln must keep Skyline's rules or exclude them, or the two gates
  disagree about the same code.
- **LocalizableElement fires without any opt-in**: ReSharper's default localizability treats
  WinForms forms (and some exception messages) as localizable. Fixed by `Localizable=No` at the
  solution layer; projects opt in with a `*.csproj.DotSettings` `Localizable=Yes`, as CommonUtil,
  CommonMsData and MSGraph already do. (SkylineBatch/AutoQC solve the same problem differently:
  `Sync-DotSettings.ps1` demotes `LocalizableElement` to HINT.)
- **Settings-layer injection does not work in inspectcode.** A `Pwiz.sln.DotSettings` holding
  only a `FileInjectedLayer` pointing at `Skyline.sln.DotSettings` was ignored, with
  `RelativePath` alone and with `AbsolutePath` added - the run fell back to defaults (2160
  `InconsistentNaming`, no `TabsAreDisallowed`). So the settings are a copy.
- **Roslyn CodeStyle analyzers fail to load** in inspectcode (`Microsoft.Bcl.AsyncInterfaces
  10.0.0.1` not found). Findings from those analyzers may be missing; check whether Skyline's
  CI run shows the same.

## Tasks

### Step 1 - settings (done, committed locally)
- [x] `Pwiz.sln.DotSettings` = `Skyline.sln.DotSettings` + `Localizable=No` (4407 -> 4153)
- [x] `<RootNamespace>` on 21 test projects that defaulted to their assembly name
  (`CheckNamespace` 261 -> 137)
- [ ] `CheckNamespace` off for the library projects whose files sit flat in a folder with
  sub-namespaces (MsData, Util, Common, Analysis, SeeMS, ...) - accepts the port's layout
  rather than moving files

### Step 2 - cleanup to zero
- [ ] Mechanical: tabs (SeeMS), redundant qualifiers, unused usings - `jb cleanupcode` or IDE
  bulk fix; SeeMS in its own commit since it is whitespace-heavy
- [ ] Judgment: nullable-contract findings, empty catches, CS0162, the remaining ~1300

### Step 3 - CI
- [ ] Add the ReSharper half to root `tcinspect.ps1` (status `Core code inspection`), modelled on
  `pwiz_tools/Skyline/tcinspect.ps1`
- [ ] Add `jetbrains.resharper.globaltools` 2025.3.3 to the root `.config/dotnet-tools.json`
- [ ] `--exclude` the 7 shared projects (Skyline's gate owns them)
- [ ] Decide: enable at zero, or enable now with a shrinking per-project exclude list

### Step 4 - drift and loose ends
- [ ] Keep `Pwiz.sln.DotSettings` in step with Skyline's: add it as a target of
  `ai/scripts/Skyline/scripts/Sync-DotSettings.ps1` (override: the `Localizable=No` line), or a
  test asserting it equals Skyline's plus that line. Osprey and CarafeSharp copies have already
  drifted (only Skyline has the `Boolean.ToString` SSR pattern).
- [ ] `pwiz/utility/test/CodeInspectionTests.cs` walks `pwiz/` and `Tools/`; `Tools/` was
  removed by the hoist (#4658), so its rules no longer cover the ported `pwiz_tools/` projects

## Progress Log

### 2026-10-29
- Baseline measured; step 1 committed (`Added ReSharper settings for Pwiz.sln`).
- Injection experiment failed as described above; fell back to a copy.
