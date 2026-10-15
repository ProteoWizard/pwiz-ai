# TODO-20261015_skyline_single_build.md

## Branch Information
- **Branch**: `Skyline/work/20261015_skyline_single_build`
- **Base**: `master` (6496d05222)
- **Created**: 2026-10-15
- **Status**: In Progress
- **Module**: `skyline`
- **PR**: (pending)
- **Checkout**: `C:\Dev\BuildTrouble`

## Objective

Remove redundant work from the Skyline build that `build64.log` (a top-level `build.bat` followed by
`pwiz_tools\Skyline\build.bat --no-tests`) showed.

## Findings (from build64.log, 2026-10-14)

1. pwiz-sharp compiles twice: AnyCPU in the top-level build (`bin\Release`), then x64 under Skyline
   (`bin\x64\Release`). Out of scope here - see "AnyCPU vs x64" below.
2. Skyline's build.bat ran 9 separate `dotnet restore` + 9 separate `dotnet build` calls (Skyline, 7 test
   projects, TestRunner). Each was its own MSBuild session; the 8 after the first did no compiling and
   still took 11-17 s each (~105 s), and re-ran SortRESX, generatecode.bat and the native shim probes.
3. Steps with no up-to-date check (SortRESX, generatecode, cmake probe) - now run once per build, not 9x.
4. Vendor test-data extraction stamped per consuming project, so TestData and TestFunctional each
   extracted the Agilent archive - concurrently, once (2) put them in one parallel session.

## Changes

- `pwiz_tools/Skyline/SkylineBuild.proj` (new): builds the 9 projects in one session
  (`BuildInParallel`), restores them as one NuGet graph via `RestoreGraphProjectInputItems` (full paths -
  relative ones are skipped with NU1503). No `-f`: an extra TargetFramework global on CommonTest/TestUtil
  would make MSBuild build a second instance into the same obj.
- `pwiz_tools/Skyline/build.bat`: one `dotnet build SkylineBuild.proj` replaces the two loops.
- `build/ExtractTestDataArchive.proj` (new) + `build/ExtractTestData.targets`: one extraction per archive
  per build via the MSBuild task with normalized `Archive`/`Parent` globals and the caller's globals
  removed; stamp per archive in `build/obj/extracted/`.

## Verification (logs in ai/.tmp/sessions/20261015-singlebuild/)

- [x] run1: every project built exactly once, 19.2 s with real compiling
- [x] run2: restore fix proven (deleted TestRunner project.assets.json; restored); 9.3 s no-op
- [x] run3: `--no-tests` staging - all 9 staged
- [x] Developer clean `bs.bat`: Skyline section 20.6 s (was ~141 s), 48 projects once each
- [x] run4: Agilent extracted once with both consumers; run5: deleted fixture + stamp restored
- [ ] Clean `bs.bat` after the extraction change (pwiz-sharp side: UIMF, BiblioSpec archives + reader tests)
- [ ] `tc-perftests.bat` has the same per-project loop (4 projects) - fold in
- [ ] `/code-review medium`

## Related

- Developer's `c:\mystuff\b64_base.bat` hid build.bat failures behind `| tee` (and `tee.exe` there does not
  truncate) - fixed locally, not in the repo.
- Intermittent pwiz-sharp failure seen once: `Reader_Bruker_Sample_1_A_1_01_985` handle still held on
  `Analysis.yep` after Dispose. Not investigated.

## AnyCPU vs x64 (question to the team)

pwiz-sharp is AnyCPU in the top-level build, installer and Osprey.sln (forced by
`pwiz_tools/Osprey/Directory.Build.targets`), x64 under Skyline (`pwiz_tools/Directory.Build.targets` passes
`Platform=$(Platform)`) and Osprey's `package.ps1`. The two targets' comments each claim to share one build
with the other; they do not. Every vendor SDK DLL in the AnyCPU output is x64-only (PE machine 0x8664),
except Shimadzu CABINET.DLL (x86). Overlaps TODO-20260927_osprey_pwizsharp_one_config.md.
