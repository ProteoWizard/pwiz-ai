# TODO-20261008_zero_warnings.md

## Branch Information
- **Branch**: `Skyline/work/20261008_zero_warnings` (created 2026-10-08)
- **Checkout**: `C:\Dev\NoWarn` (exact case - see below)
- **Module**: `pwiz`
- **Base**: `origin/master` @ `93c1b9a5b8`
- **Status**: PR open; awaiting TeamCity and review.
- **GitHub Issue**: (none)
- **PR**: (none)

## Objective

We aim for a warning-free build but did not have one. The local `build.bat` log
(`C:\Dev\master_clean\build64.log`) had 50 warnings; TeamCity build 22139 (Skyline master and
PRs, x86_64) had 42 in its pre-build step. Fix every warning, then make the build fail on a new one.

## Why warnings survived `TreatWarningsAsErrors=true`

1. Root `Directory.Build.props` exempted `CS1591;CA1859` via `WarningsNotAsErrors` (38 of 42 on TC).
2. All three MSConvertGUI projects set `TreatWarningsAsErrors=false` (TestConnected had 5 warnings).
3. `TreatWarningsAsErrors` does not cover MSBuild task warnings: MSB3568 (duplicate resx names in
   `pwiz_tools/Shared/Common/DataBinding/Controls/Editor/ViewEditor.resx`) passed through.
4. Skyline-side projects (`pwiz_tools/Directory.Build.props`) do not set TreatWarningsAsErrors at all.

## Done (uncommitted on the branch)

- [x] Removed `WarningsNotAsErrors`; added `MSBuildTreatWarningsAsErrors` to root props
- [x] Removed the three MSConvertGUI `TreatWarningsAsErrors=false` opt-outs
- [x] ViewEditor.resx: deleted the duplicated `>>tabPageSource.*` block (identical values)
- [x] CS1591 x12: 4 were doc comments stranded on the wrong member by later insertions
  (DefaultReaderList `Default`, Spectrum.cs `Chromatogram`, Reportfile `WriteMatches`); the rest
  given `<inheritdoc/>` or a summary matching sibling conventions
- [x] CA1859 x37 (33 + 4 cascaded): non-public parameter/return types narrowed to the concrete type.
  One analyzer false positive: SpectrumListWrapperTests sort keys feed a `Func<..., IComparable>`,
  so they became delegate-typed fields rather than `int`-returning methods (CS0407 otherwise)
- [x] RemoteAccountTest.cs: `StringComparison.Ordinal`, List instead of constant array,
  `AssertFailedException` instead of `Exception`; IDE0161 suppressed with a `#pragma` (see Decisions)
- [x] Verified: `Build-PwizSharp.ps1 -VendorLicenses -Rebuild` -> 0 warnings, 0 errors (281
  CoreCompile); no-vendor MsConvert.csproj rebuild clean; tests pass: Analysis 179, BiblioSpec 143,
  MsData 86, Common 58, Bruker 15, IdentData 7, TraData 6

- [x] Skyline measured: no-vendor Release build of the solution, 0 warnings (282 outputs)
- [x] Locked the Skyline side too (developer's decision 2026-10-08): `TreatWarningsAsErrors` +
  `MSBuildTreatWarningsAsErrors` in `pwiz_tools/Directory.Build.props` and
  `pwiz_tools/Shared/Common/Directory.Build.props` (which does not import the former); removed the
  `TreatWarningsAsErrors=false` opt-outs from `StlContainers.csproj` and `SeeMS.csproj`

- [x] 2026-10-09: fast-forwarded to master `8321319734`. Developer's x64 Release Skyline build
  (`C:\Dev\NoWarn\build64.log`) and clean pwiz-sharp build + tests (`build64a.log`): 0 warnings,
  0 errors, 22 test suites pass (Installer.Tests' 2 tests skip)
- [x] Committed `85a448e9dc`
- [x] CodeInspection passed (Release). `/code-review medium`: 9 findings, 2 acted on (blanket
  MSBuild promotion, see Decisions), 7 dropped with reasons
- [x] Committed `bbe7819d8f` (MSBuild code list); `bs.bat` rerun 15:36: 0 warnings, 0 errors,
  22 suites pass. An earlier `build64.log` had an Analysis.Tests failure from two overlapping
  builds writing the same log; the single-run rerun is clean

## Remaining

- [ ] TeamCity: Debug configuration, and AutoQC/SkylineBatch (now inherit `TreatWarningsAsErrors`)

## Decisions

- No `NoWarn` for WFO1000 (developer, 2026-10-08). The mis-cased-path failure is fixed at its
  source instead: skyclaude and Build-PwizSharp.ps1 now resolve the on-disk casing (pwiz-ai
  `b3cc49e1`, `ef7b07c3`). Prefer fixing a warning, or its cause, over suppressing it.
- `MSBuildWarningsAsErrors=MSB3568;MSB3277;MSB3245`, not blanket `MSBuildTreatWarningsAsErrors` (developer,
  2026-10-09, from `/code-review medium`). The blanket form promotes the warning that
  `ContinueOnError="true"` logs when git fails (PwizVersion.targets, SkylineVersion.targets -
  nightly "dubious ownership") and SkylineTester.csproj's deliberate `<Warning>`, failing the build
  in exactly the no-git case those fallbacks exist for. MSB3277/MSB3245 added with no current
  instances (none in this branch's or master_clean's logs). Add further MSB codes as needed.
- IDE0161 in RemoteAccountTest.cs suppressed with a `#pragma`, not converted (developer,
  2026-10-09). Conversion re-indents the whole file (304+/305-) for no behavior change. The
  MSConvertGUI sources it tests stay block-scoped (exempt via `AnalysisLevel=none`).
- [ ] TeamCity run to catch MSB warnings in steps not reproduced locally (restore, packaging)
- [ ] Out of scope, noted: CodeInspectionTest tolerates `new WebClient()` in
  `pwiz_tools/Skyline/Executables/Installer/SetupDeployProject.cs:109`

## Gotchas hit

- Build from `C:\Dev\NoWarn` exactly. The session hook's lowercase `nowarn` turned WFO1000 into
  errors (case-sensitive .editorconfig matching); `MSBUILDDISABLENODEREUSE=1` plus the exact-case
  path fixed it. Build-PwizSharp.ps1 now canonicalizes `-SourceRoot` casing.
- A no-vendor build overwrites shared Release outputs and a later vendor-on incremental build does
  not recompile them: BiblioSpec `*_Prg2012_Wiff` tests then fail with "Sciex WIFF reading requires
  the vendor SDK". A vendor-on `-Rebuild` restores them.
- Incremental builds do not re-report warnings of up-to-date projects; verify with `-Rebuild`.
