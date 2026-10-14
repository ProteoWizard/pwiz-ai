# TODO-20260930_net10_waters_calibration_port.md - Port #4498 (waters_connect lockmass / calibration scans) to the .NET 10 branch

## Branch Information
- **Branch**: `Skyline/work/20260930_net10_waters_calibration_port` (checkout `C:\Dev\DotNetPort`;
  created at `ea1d1dc2df`, the port-branch tip, 2026-09-30; not yet pushed)
- **Base**: `Skyline/work/20260612_net8_port` (PR #4619 -> master)
- **Module**: `skyline`
- **Created**: 2026-09-30
- **Status**: Completed
- **Source PR**: #4498 (`Skyline/work/20260727_Waters_dataconvert_mzml_import`, checkout `C:\Dev\lockmass`);
  see TODO-20260727_Waters_dataconvert_mzml_import.md
- **PR**: [#4782](https://github.com/ProteoWizard/pwiz/pull/4782) (merged 2026-10-14 as `e7b02632bb`;
  opened 2026-10-06 against `Skyline/work/20260612_net8_port`, retargeted to master 2026-10-12) on branch
  `Skyline/work/20261006_net10_waters_calibration_port`. Replaces #4753 (closed): the base branch
  was rewritten after 2026-09-24, so #4753's history (which carried Matt's merge of the old base)
  could no longer merge cleanly. The three commits were rebased onto the new base (`490a4d3825`).

## Why port first
Decided 2026-09-30: port to .NET 10 BEFORE merging #4498 to master, so anything the port
exposes can be fixed on #4498 instead of needing a follow-up master PR - the pattern from
2026-09-29, where porting #4669 (#4742) exposed the `--culture zh-CHS` problem and needed #4743.
#4498 is green on CI but still carries chambm's CHANGES_REQUESTED review (all threads resolved;
awaiting his re-review), so the port runs while that is pending.

## This is a hand port, not a merge
On the .NET 10 branch Skyline reads data ONLY through pwiz-sharp:
- `ProteowizardWrapper.csproj` targets `net10.0` only, references pwiz-sharp MsData/Analysis/vendor
  projects, no pwiz.CLI.
- It `Compile Remove`s `ProteowizardWrapper/MsDataFileImpl.cs` and compiles
  `ProteowizardWrapper.PwizSharp/MsDataFileImpl.cs` instead. A master merge would land #4498's
  wrapper edits in the file .NET 10 does not build, leaving the live one untouched.
- The C++ changes in `pwiz/` do not reach .NET 10 Skyline at all; each needs a pwiz-sharp equivalent.

## Port plan

### 1. Skyline side - the reported bug (still live on .NET 10)
`ProteowizardWrapper.PwizSharp/MsDataFileImpl.cs` still uses positional
`MsDataSpectrum.WatersFunctionNumberFromId(id, isCombinedIonMobility)`, so waters_connect
`channel=2 process=0 spectrum=1 scan=1` reads as function 2 and is taken for lockspray.
- [x] Port `WatersFunctionNumberFromNativeId` (layout-based parse; waters_connect forms deliberately
      return null) and the `MsDataSpectrum.WatersFunctionNumber` property from #4498's
      `ProteowizardWrapper/MsDataFileImpl.cs` (~line 2539-2600 there). pwiz-sharp's Waters reader
      emits the same three id layouts (`SpectrumList_Waters.cs:151/172/223`).
- [x] Callers: `IsWatersLockmassSpectrum`, lockmass-function detection, `SpectraChromDataProvider.cs`,
      `SpectrumFilter.cs` - byte-identical to #4498's versions so the later master merge is clean.
- [x] `IsCalibrationSpectrum` from MS:1000928, `IsWatersFile` cache, `CalibrationSpectraAreOmitted`
      passthrough in `ProteowizardWrapper.PwizSharp/MsDataFileImpl.cs`.
- [x] Port `PwizFileInfoTest` additions + `WatersLockmassMzml.zip` (applied from #4498 as a binary
      patch). No `TestData.csproj` entry needed: the SDK-style project globs `**\*.zip`.
- [x] Skyline: `TestWatersCalibrationSpectrum` and `TestTicChromatogram` pass (Release, vendor
      readers on, run by the developer in SkylineTester 2026-09-30 11:44).

### 2. pwiz-sharp - missing
- [x] `pwiz-sharp/pwiz/src/MsData/SpectrumList_IgnoreCalibrationScans.cs` - lives in MsData (not
      Analysis) because the readers install it and cannot reference Pwiz.Analysis, so it derives from
      `SpectrumListBase` and owns its inner list. `Create` (fileContent gate + return-inner-if-nothing-
      removed) and `Apply` (installs it, drops the fileContent term). No `min_level_accepted` in
      pwiz-sharp and none needed: mzML/mzMLb/mz5 serve every level below FullData as the same
      metadata-only read, so the scan asks FullMetadata.
      Wired into `MzmlReaderAdapter` (lazy + eager paths), `MzMlbReaderAdapter` (both), and
      `Mz5ReaderAdapter` - **pwiz-sharp DOES have an mz5 reader**, contrary to the note above.
      Tests: `MsData.Tests/SpectrumListIgnoreCalibrationScansTests.cs` (4 cpp cases, the
      detail-level one recast as "never asks FullData", plus an mzML reader round trip that also
      checks the written output no longer carries MS:1000928). MsData suite 90/90.
- [x] UIMF: `SpectrumList_UIMF` skips calibration frames at index time and overrides
      `CalibrationSpectraAreOmitted`; `ChromatogramList_UIMF` + `UimfData.GetTic(bool)` drop them from
      the TIC (both arrays and metadata-only length); `Reader_UIMF` stops declaring MS:1000928 when
      ignoring. No raw-index split needed (pwiz-sharp entries carry frame/scan/type directly) and no
      scan-time->frame map exists in pwiz-sharp (nothing calls `GetDriftScansForFrame`).
      **Closed the fixture gap cpp has**: `UIMF.Tests/UimfCalibrationFrameTests.cs` copies the BSA
      fixture and relabels frame 8 as calibration (`UPDATE Frame_Parameters` - legacy schema, the
      single source for both the index query and `GetFrameTypeForFrame`). UIMF suite 3/3.

### 3. pwiz-sharp - verify, port if absent
- [x] Writers drop the fileContent declaration: `SpectrumList_IgnoreCalibrationScans.Apply` removes
      it (asserted through MzmlWriter output); UIMF never declares it when ignoring.
- [x] Waters global TIC: was NOT excluding the lockmass function. `ChromatogramList_Waters` now
      takes `ignoreCalibrationScans` from `Reader_Waters` and skips it. Ported cpp's new
      `MSe_Short-ignoreCalibrationScans.mzML` reference and added the variant to
      `Reader_Waters_MSe_Short`; red-checked (fails with the exclusion disconnected). Waters 21/21.
- [x] msconvert help: pwiz-sharp's "Vendor toggles" block lists option names without descriptions,
      so there is no wording to match. Updated the stale "honored for Waters" comment in
      `MsConvert/src/Converter.cs` and the `ReaderConfig.IgnoreCalibrationScans` doc instead.
- [x] Worker-thread inference: N/A - msconvert-sharp is single-threaded; no
      `benefitsFromWorkerThreads` equivalent exists.

### 4. Already present in pwiz-sharp
- `SpectrumListWrapper.CalibrationSpectraAreOmitted` forwards (`Analysis/SpectrumListWrapper.cs:60`).
- Waters `IgnoreCalibrationScans` + `CalibrationSpectraAreOmitted`. **Correction**: the lockmass
  function was NOT computed per call - `WatersRawFile.GetLockMassFunction` cached it lazily with the
  checked flag set before the value was stored and no lock, the same shape cpp fixed. Now locked
  (`WatersRawFile.cs`).
- msLevel predicate reads declared level first (`Analysis/Predicates.cs:119`, per chambm).

### 5. Findings to feed back to #4498
Anything the port shows is wrong in the design goes here AND onto #4498 as a commit before it merges.
- `PwizFileInfoTest.cs`: the blank line after `VerifyWatersConnectSpectra` holds three spaces
  (`git apply` flagged it). Fixed in the port; needs the same one-line fix on #4498 so the eventual
  master merge does not reintroduce it.
- From `/code-review max` on the port (2026-09-30), issues that live in #4498 itself:
  - `PwizFileInfoTest` waters_connect case asserts `MsDataSpectrum.Level` but never calls
    `SpectrumFilter.UpdateMseLevel`, so the `WatersFunctionNumber ?? Level` fallback (the actual
    waters_connect MSe fix, SpectrumFilter.cs ~903) is untested. Its comment claims otherwise.
  - Replacing `WatersFunctionNumberFromId(..., HasCombinedIonMobility)` left
    `SpectrumFilter.HasCombinedIonMobility`, `IIonMobilityFunctionsProvider.HasCombinedIonMobility`
    and `DataFileInstrumentInfo`'s implementation dead (plus the already-dead
    `SpectrumFilterPair.HasCombinedIonMobility`); comments still say it "affects spectrum ID format".
  - `applyIgnoreCalibrationScans`: in the declared-but-untagged (#4499) case it returns before
    dropping the fileContent term, and its comment ("either absent or still true") is wrong -
    the declaration is false there, and keeping it makes every later read rescan. Decide on
    #4498; pwiz-sharp keeps cpp parity (comment corrected only).
  - `PwizFileInfoTest.cs` (+148 lines) has no `AI assistance:` header line.
- No other design problems found.

### 5b. `/code-review max` triage (2026-09-30, 15 findings)
Fixed:
- `SpectrumList_LockmassRefiner` now derives from `SpectrumListWrapper` (as in cpp): forwards
  `CalibrationSpectraAreOmitted` and lets `Innermost` reach the Waters list, so Skyline's lockmass
  path keeps SONAR/combined-IMS/CCS support. Red-checked in `SonarAndFlagsTests` (both new
  assertions fail against the old refiner). Pre-existing, but it defeated #4498's handshake.
- `SpectrumList_Waters` resolves the lockmass function in its constructor (cpp parity); the
  `WatersRawFile` remark no longer claims SDK serialization that pwiz-sharp does not have.
- UIMF metadata TIC length now `FrameCount - CalibrationFrameCount` from the open-time index,
  not a whole-file SDK aggregate; `GetTic` uses the same frame set.
- mzML reader test disposes its MSData on every path; UIMF test uses `PwizSharpPaths`;
  `AI assistance:` header on the pwiz-sharp wrapper; `Apply` comment corrected.
Dropped:
- Declaration kept via ParamGroup ref (mz5 only, no known writer; cpp same).
- FullMetadata scan parses whole spectra (cpp same cost; needs SpectrumList_Mzml level support).
- Five ApplyIgnoreCalibrationScans call sites (per-reader placement mirrors cpp; adapters are
  called directly, so ReaderList is not a single choke point).
- Duplicated wrapper/filter logic (moving SpectrumListWrapper into MsData is a pwiz-sharp
  restructuring beyond a port).
- UIMF `UimfData` never disposed (pre-existing ownership gap; see section 6).

### 6. Noted, out of scope
- pwiz-sharp `Reader_UIMF` hands its `UimfData` to lists that never dispose it, so an opened UIMF
  file's SQLite/DataReader handles live until finalization. Pre-existing; not a #4498 issue.

### Build trouble on this machine (environment, not the branch)
WFO1000 errors that moved between projects run to run (ZedGraph, CommonBaseUI, PanoramaClient,
TestUtil, Skyline-as-reference). NOT the SDK (an earlier guess, wrong: this checkout built on 9/29
under 10.0.401). The build log shows a random subset of projects under `C:\Dev\dotnetport` instead of
`C:\Dev\DotNetPort`; Roslyn matches .editorconfig paths case-sensitively, so the WFO1000 demotion
silently drops for those. The same restore with `-nodeReuse:false` shows no lowercase at all, so the
casing arrives through reusable MSBuild worker nodes. The lowercase originates in this session's
`PWIZ_LSP_DIR` (`C:\Dev\dotnetport\pwiz_tools`), which the start hook `cd`s to and the C# LSP loads.
Killing stale nodes alone did NOT fix it - fresh nodes created during the next build picked the
casing up again, which points at the LSP sharing reusable nodes (unconfirmed). Proposed test:
`set MSBUILDDISABLENODEREUSE=1` before `bs.bat`. The two tests were then run via SkylineTester
from a separate build. Root fix belongs wherever `PWIZ_LSP_DIR` gets its casing.

## Progress Log
### 2026-09-30
- Mapped #4498 onto the .NET 10 branch from the lockmass session; created branch in DotNetPort.
- Sections 1-3 implemented (uncommitted). pwiz-sharp MsData 90/90, Waters 21/21, UIMF 3/3.
  Skyline side verified in SkylineTester (both tests pass). Committed `ce4cc1805a` (not pushed).
- CodeInspectionTest passes. Full ReSharper: 2738 branch-wide issues (unresolved-symbol noise on
  this branch); in touched files only "Cannot resolve symbol" for the new MsDataSpectrum members,
  resolved against the legacy net472 wrapper. Left as is.
- `/code-review max`: triaged (section 5b), fixes committed `308e589d5e`. Waters 21/21,
  Analysis lockmass 9/9, MsData calibration 5/5, UIMF 3/3, and the Skyline
  `TestWatersCalibrationSpectrum`, `TestTicChromatogram`, `WatersLockmassCmdlinePerfTest` pass.
- Gotcha: `Build-Skyline.ps1 -RunTests` does not enable perf tests (ran 2 of 3, silently);
  use `Run-Tests.ps1` for TestPerf.
- 2026-10-01: pushed, opened #4753. Fed section 5 back to #4498 as `c7a6dc27e8` (SpectrumFilter
  fallback test, red-checked with `?? 0`; dead HasCombinedIonMobility members removed; AI headers;
  whitespace). Mirrored the four shared Skyline files onto #4753 as `d90c8d14f1`, byte-identical
  to #4498 in every #4498-touched region. Port: TestWatersCalibrationSpectrum, TestTicChromatogram,
  CodeInspectionTest pass.
- 2026-10-06: base branch rewritten upstream. A rebase plus a `git pull` in this checkout produced a
  155-file merge of the two base histories, and `libraries/` had been deleted from disk. Aborted the
  merge, restored `libraries/` from HEAD, branched the rebased commits as
  `Skyline/work/20261006_net10_waters_calibration_port`. On the new base: build green;
  TestWatersCalibrationSpectrum, TestTicChromatogram, CodeInspectionTest, WatersLockmassCmdlinePerfTest
  pass; pwiz-sharp MsData 90/90, Waters 21/21, UIMF 3/3, Analysis lockmass 9/9. Opened #4782,
  closed #4753. The old local branch `Skyline/work/20260930_net10_waters_calibration_port` and its
  remote are left in place (diverged); safe to delete once #4782 is settled.
- Decided 2026-10-05 (developer): from now on, develop on the .NET 10 branch and leave master
  alone - it is about to become master. The "keep shared files identical to #4498" rationale for
  `d90c8d14f1` matters only if #4498 still merges to master first.
- Decided 2026-10-05 (developer): `applyIgnoreCalibrationScans` keeps a declared-but-untagged
  (#4499) fileContent term as is, in both cpp and pwiz-sharp. No change.

### 2026-10-14 - Merged

PR #4782 merged as commit e7b02632bb. The .NET 10 port branch it was based on had itself merged
into master, so on 2026-10-12 origin/master was merged into the branch (no rebase: the PR was open)
and the PR retargeted to master; the net diff stayed the same 26 files. Copilot review: restored
the public `Inner` on `SpectrumList_LockmassRefiner` (lost in the switch to `SpectrumListWrapper`)
and expanded a one-line `if` in `UimfCalibrationFrameTests` (`60e6ae592d`); declined reconciling a
param-group-backed fileContent declaration, citing cpp parity (same call as section 5b, thread left
for a human reviewer). TeamCity code inspection then flagged a redundant `(int?)` cast in
`MsDataFileImpl.WatersFunctionNumberFromNativeId`, fixed in `7d1ade38cd`; a no-vendor Core Windows
failure was an agent submodule checkout error, not the code. Shipped: sections 1-3 and 5b.
Not done: the `UimfData` disposal gap (section 6) remains out of scope. The superseded local/remote
branch `Skyline/work/20260930_net10_waters_calibration_port` (in `C:\Dev\DotNetPort`, closed #4753)
was still in place at merge time.
