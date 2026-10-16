# TODO-20261015_skyline_single_build.md

## Branch Information
- **Branch**: `Skyline/work/20261015_skyline_single_build`
- **Base**: `master` (6496d05222)
- **Created**: 2026-10-15
- **Status**: In Progress
- **Module**: `skyline`
- **PR**: [#4850](https://github.com/ProteoWizard/pwiz/pull/4850) (draft)
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
- [x] `tc-perftests.bat` folded in via `-p:SkylineBuildProjects` (%3B-separated, Unescape'd in the proj);
      run6: 43 projects once each, all four staged (`SKYLINE_TEST_ARGS=test=NoSuchTest`, so TestRunner's
      "No tests found" exit 1 is expected). Note tc-perftests builds AnyCPU (no Platform=x64), unlike build.bat
- [x] run7 (`build.bat --no-tests` after review fixes): each archive once, 48 projects once, 21.1 s
- [x] `/code-review medium` - 9 findings. Fixed: stamp keyed on archive+destination; Parent defaults to the
      archive's folder (was MSB4184 on empty); tc-perftests; Clean/Rebuild targets on SkylineBuild.proj; stale
      BUILD_TARGET comment in SkylineTester.csproj. Dropped: RemoveProperties denylist could miss a property
      (no real caller differs); shared stamp survives deleting a project's obj (clean.bat clears build\obj,
      old stamp also survived Clean); path-casing mismatch (both spellings derive from project-file paths);
      no Inputs/Outputs on the calling target (a few tiny evaluations per no-op build)

## Matt's review + AnyCPU answer (2026-10-16)

- Matt (review on tc-perftests.bat) found the %3B list awkward; replaced with named sets
  (`-p:SkylineBuildSet=All|Perf`, unknown name is an error). Replied on the thread.
- Matt (email) on AnyCPU vs x64: "Everything to x64 I think. Like I already did with Skyline so it
  reused code inspection's build." tc-perftests.bat now passes Platform=x64 (run16: all four staged from
  bin\x64). Remaining for a follow-up PR: top-level build.bat pwiz-sharp, installer, Osprey.sln override,
  Osprey package.ps1.
- Perf set re-restored Skyline.csproj on every run - ROOT CAUSE (found by a Fable 5.1 subagent):
  tc-perftests.bat itself ran `rmdir /s /q pwiz_tools\Skyline\obj` before the build (since the .NET 10 port,
  254112b277), deleting Skyline's NuGet cache and compile intermediates. NuGet 7.9 logs "restore inputs have
  changed" for ANY non-no-op, including "no cache file" - the hash never differed. Evidence:
  ai/.tmp/sessions/20261016-restore-rca/ (watch-perf1.log, perf1.log vs perf-normdir.log, notes.md). My two
  "ruled out" experiments were confounded by the same rmdir. Removed the rmdir (its CS0579 Net8Version.g.cs
  hazard is gone: one g.cs per IntermediateOutputPath behind an inputs cache, cafeb7048c); run17/run18: no
  restore, ~9 s each, no CS0579. Lesson: check the wrapper script for obj/ deletion before suspecting NuGet.

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
except Shimadzu CABINET.DLL (x86). (TODO-20260927_osprey_pwizsharp_one_config.md is completed - #4725.)
