# TODO-20261015_skyline_single_build.md

## Branch Information
- **Branch**: `Skyline/work/20261015_skyline_single_build`
- **Base**: `master` (6496d05222)
- **Created**: 2026-10-15
- **Status**: In Progress
- **Module**: `pwiz` (was `skyline`; retitled 2026-10-16 when x64-everywhere was folded in)
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
  bin\x64).
- 2026-10-16: folded "everything x64" into this PR (developer's call) - a7f0812b6f:
  Pwiz.sln x64 configs remap the 57 Any CPU projects to x64 (BOM/CRLF preserved - sed stripped the BOM, restored);
  root Directory.Build.props declares Platforms AnyCPU;x64 (StlContainers in its csproj); build.bat and
  Run-Tests-Parallel.ps1 pass x64; installer builds x64 and stages from bin/x64/Release (build.bat runs it with
  -SkipBuild, so both had to move together); Osprey's out-of-solution target passes $(Platform) instead of AnyCPU
  (reverses #4725's AnyCPU choice - its premise "Skyline can't be x64" ended with cafeb7048c on 10-02; Mike was
  its author); Bench-*.ps1 paths. Linux build.sh left AnyCPU (no sharing to gain; keeps non-x64 hosts working).
  Found by test-first: MSConvertGUI IsDevBuildDirectory rejected bin\x64\<Config>\<TFM> (dev defaults silently
  lost) - extended IsDevBuildDirectory_OnlyBuildOutput (red in run19), fixed (run20 green, 736 passed).
  Verified: Osprey 637/637 on the shared x64 tree; pwiz<->Skyline alternation no-op both ways (run23 8.6 s,
  run24 12.4 s). Installer not run locally (no ISCC) - checked its x64 input files exist.
- Merged master (developer's GitHub "Update branch", aa29c9cd1c): #4852 added Shared\BiblioSpec\BiblioSpec.IO,
  referenced by BiblioSpec.Tests (in Pwiz.sln) but not added to Pwiz.sln, so Release solution builds built it
  twice as Debug|AnyCPU into bin\Debug (run25) - a master defect, not from this PR. Added it to Pwiz.sln
  (482b23a8c6); run28: once, x64 Release, 737 passed.
- 2026-10-19: #4855 (Brendan, 10-16) added BiblioSpec.IO to Pwiz.sln on master too; the developer's master merge
  (340a941e78) kept both entries (no textual conflict). Removed ours, kept master's (already x64->x64): 10699696a1.
  Pwiz.sln now differs from master only by the 228 x64 remap lines. Clean bs.bat on 0608dac15e + fix: 757 passed,
  BiblioSpec.IO once per section. PR body bullet about adding BiblioSpec.IO removed.
- Superseded: my earlier claim that Osprey still builds pwiz-sharp three ways was stale - #4725 fixed that 09-30.
- Copilot (high): BiblioSpec.Tests ExecuteBlib.TryResolveToolPath looked only in bin\<Config>\net10.0. My grep for
  literal bin\Release missed it (Path.Combine("bin", config, ...)). Earlier "737 passed" runs used STALE AnyCPU tools
  (BlibBuild.exe 08:54 vs x64 09:44). Deleted stale AnyCPU bin\Release under pwiz-sharp + BiblioSpec tools' bin\Debug:
  run29 red = 125/144 BiblioSpec skipped, "Test Run Successful" (silent on clean CI); all other suites passed (no
  other hidden path dependency). Fixed to match the test assembly's layout, never crossing platforms (634b5d8e9d);
  run30: 737 passed, 0 failed. Replied + resolved the thread. Lesson: after a platform/path move, delete the old
  output tree before trusting a green run.
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
