# TODO-20261106_remove_unimod_xml.md

## Branch Information
- **Branch**: `Skyline/work/20261106_remove_unimod_xml`
- **Base**: `master` (cut from dd1ea43e89)
- **Created**: 2026-11-06
- **Status**: In Review - gates green, PR open; TeamCity not triggered (parent session queues it). Decision
  (conservative, for Brendan to revisit): only comments that described unimod.xml in the present
  tense were rewritten; comments that already read as history were left alone.
- **GitHub Issue**: [#4980](https://github.com/ProteoWizard/pwiz/issues/4980) (step-1 leftover; Part of, not Fixes)
- **Module**: `pwiz`
- **PR**: [#5003](https://github.com/ProteoWizard/pwiz/pull/5003)
- **Worktree**: `C:\proj\wt-unimodxml` (agent U1)

## Objective

Delete `pwiz/data/common/unimod.xml` (2.45 MB). Nothing has read it since #4990 moved UniModCompiler
to `pwiz/data/common/unimod.obo` and #4991 moved BiblioSpec's MzTabReader to
`Pwiz.Data.Common.Unimod`. No behavior change.

## Tasks
- [x] `git grep -n -i "unimod\.xml"` over the whole tree: only comment hits in 6 .cs files
      (UniModOboReader.cs, UniModCompiler/Program.cs, MzTabReader.cs, MzTabReaderTests.cs,
      UniModTest.cs). No reader; no csproj/props/targets/Jamfile/.ps1/.bat/.wxs/.nsi copy step;
      no glob over `pwiz/data/common` that would pick it up (Common.csproj embeds the .obo files by name).
- [x] `git rm pwiz/data/common/unimod.xml`
- [x] Rewrote present-tense comments as history (UniModOboReader.cs x4, UniModTest.cs x1)
- [x] Build-BiblioSpec -RunTests: 143 passed, 0 warnings
- [x] Build-PwizSharp -VendorLicenses: 0 warnings, 0 errors
- [x] Build-Skyline -VendorLicenses: 0 C# warnings; Run-Tests TestUniMod, TestUniModAgreesWithObo,
      CodeInspection: all passed
- [x] Commit, push, PR (label `pwiz`)

## Progress Log

### 2026-11-06
- Grep clean (above). File removed; comment-only edits, CRLF preserved.
- Logs: `ai/.tmp/sessions/20261106-U1/` (biblio.log, pwizsharp.log, pwizsharp-vendor.log,
  skyline-build.log, skyline-tests.log).
- Note for Brendan: the brief said a `Directory.Build.user.props` was copied into the worktree; it
  was not there. Build-PwizSharp without `-VendorLicenses` then failed in untouched code
  (`ThermoModelParityTests.cs(110)`: no `Reader_Thermo.GetInstrumentConfigurationComponents`;
  `SeeMS/Processing.cs(595)`: no `SpectrumList_LockmassRefiner`), i.e. Pwiz.sln may not build in
  no-vendor mode on master. Not investigated here (out of scope); reran with `-VendorLicenses`.
- Skyline build's 43 warnings are all C4251 in Mobilion's vendor SDK headers (MobilionShim), from
  the vendor-licensed native build; none in repo C#.
- `/code-review medium`: no correctness findings. Fixed 2: the hand-copied tables in
  UniModOboReader.cs and UniModTest.cs now cite `git show dd1ea43e89:pwiz/data/common/unimod.xml`
  as their source. Dropped 1: add "the retired" to UniModCompiler/Program.cs:738 - it already reads
  as history ("listed"), and the brief says to leave those. Rebuilt and reran the 3 tests: pass,
  0 warnings (skyline-build2.log, skyline-tests2.log).
- CodeInspection's only WARNING is the pre-existing tolerated `new WebClient` in
  SetupDeployProject.cs.
