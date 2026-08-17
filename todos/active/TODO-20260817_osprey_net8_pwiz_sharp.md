# Osprey: net8.0-only on Matt's pwiz-sharp port (stacked PR) - remove net472 and the hand-coded mzML reader

## Branch Information
- **Branch**: `Skyline/work/20260817_osprey_net8_pwiz_sharp`
- **Base**: `chambem2/pwiz-sharp` (STACKED PR - not master; pattern per #4311)
- **Created**: 2026-08-17
- **Status**: In Progress
- **GitHub Issue**: [#4497](https://github.com/ProteoWizard/pwiz/issues/4497)
- **Module**: `osprey`
- **Other labels**: `enhancement`
- **PR**: (pending, base `chambem2/pwiz-sharp`)
- **Depends on**: [#4178](https://github.com/ProteoWizard/pwiz/pull/4178) (draft, `chambem2/pwiz-sharp`)
- **Builds on**: [#4502](https://github.com/ProteoWizard/pwiz/pull/4502) (merged; issue #4496 - net472 vendor raw reading, already present in this base)

## Objective

Integrate Osprey's net8.0 configuration with the ProteoWizard-wide C# .NET 8 port so that
pwiz-sharp becomes Osprey's only spectrum reader. In that world net472 does not exist, so
this branch deletes what the master-targeting work (#4496/#4502) had to keep:

* the entire `net472` target (`Directory.Build.props:4`), its conditional package
  references (e.g. `System.Memory` in `Osprey.IO.csproj`), and the dual-framework test matrix
* `Osprey.IO/MzmlReader.cs` (874 lines) and its net472-specific scaffolding

Removing `MzmlReader` is a correctness win, not just maintenance: it is the only parser in
the pipeline that is not pwiz, so it is the one component whose agreement with everything
else is unverified. If goldens shift when the reader changes, that is a defect in the code
being removed - pwiz is the reference. Do NOT rebaseline with `-CreateGolden`.

## Base state findings (2026-08-17, before any edits)

Established by reading the branch, so the plan below is grounded rather than assumed:

* `chambem2/pwiz-sharp` merge-base with master is `df3e43364c` (osprey #4531) - only 23
  commits behind master, so it is kept current. **#4502's vendor reader is already here**
  (`Osprey.IO/VendorRawReader.cs`, `SpectrumFileReader.cs`).
* `pwiz-sharp/` is a real port, not a skeleton (the README's "Phase 1 / skeleton" text is
  stale): `pwiz-sharp/pwiz/src/` has `MsData` (mzML/mzXML/MGF/MSn/mz5/mzMLb readers +
  writers), `Analysis`, `Common`, `Util`, and `Vendor/` for Thermo, Waters, Sciex, Agilent,
  Bruker, Shimadzu, Mobilion, UIMF, UNIFI.
* pwiz-sharp projects target **plain `net8.0`** (`pwiz-sharp/Directory.Build.props`) - i.e.
  cross-platform, which is what makes the Linux/WSL acceptance criterion reachable.
* `ProteowizardWrapper` on this base multi-targets `net472;net8.0-windows`; its
  net8.0-windows target is backed by pwiz-sharp via
  `pwiz_tools/Shared/ProteowizardWrapper.PwizSharp/MsDataFileImpl.cs`, keeping the same
  public `MsDataFileImpl` surface Osprey's `VendorRawReader` already calls.
* **Key constraint identified**: that wrapper target is `net8.0-windows`
  (`UseWindowsForms=true`), and a `net8.0` project cannot reference a `net8.0-windows` one.
  So Osprey cannot simply follow #4502's wrapper reference on net8 without giving up
  Linux. Resolution is the first design decision below.

## Design decision: Osprey talks to pwiz-sharp DIRECTLY, not through ProteowizardWrapper

Decided 2026-08-17 after reading the base. Option (a) of the three considered.

The wrapper route is closed by a TFM, not by taste. `ProteowizardWrapper`'s net8 target is
`net8.0-windows` because it references `pwiz.CommonUtil`, which is `net8.0-windows` with
`UseWindowsForms=true`; the net8 implementation file
(`ProteowizardWrapper.PwizSharp/MsDataFileImpl.cs`) uses `pwiz.Common.*` types (`SignedMz`,
`ImmutableList`) from it. A plain `net8.0` project cannot reference a `net8.0-windows` one,
and Osprey must stay plain `net8.0` to satisfy "runs on Linux/WSL without the Wine
container". Making `CommonUtil` cross-platform is a Skyline-wide change and is not this
issue's business.

Referencing pwiz-sharp directly is also the smaller claim on Matt's in-flight branch: zero
edits to it. And Osprey's requirement is genuinely tiny - seven scalars and two arrays per
spectrum - against the ~80 public members `MsDataFileImpl` carries for Skyline
(chromatograms, SONAR, ion mobility, CCS conversion, lockmass), none of which Osprey reads.

**What this costs, and how it is paid.** `MsDataFileImpl` encodes semantics that #4502
validated byte-for-byte, and a direct reader has to reproduce them deliberately rather than
inherit them:

| Semantic | Where it lives in MsDataFileImpl | Must be reproduced |
|---|---|---|
| RT in minutes without an ULP shift | `GetStartTime` returns `UO_minute` values as recorded rather than `TimeInSeconds()/60` (that round trip is what PR #4501 fixed) | yes - exactly |
| Isolation window as OFFSETS | `MS_isolation_window_lower_offset` / `_upper_offset`, not a width or absolute bounds | yes |
| Vendor centroiding = msconvert `peakPicking vendor msLevel=1-` | `SpectrumList_PeakPicker(list, new VendorOnlyPeakDetector(), true, "1-")` | yes |
| `CombineIonMobilitySpectra = false` | Osprey passes it explicitly today; the wrapper defaults it TRUE for Skyline | yes |
| `AllowMsMsWithoutPrecursor = false`, `IgnoreCalibrationScans = true` | hardcoded Skyline choices #4502 could not override | yes - keep the same values so the parity claim carries over |
| Vendor reader registration | `MsDataFileImpl.Vendors.cs` `[ModuleInitializer]` appends to `ReaderList.AdditionalReaders`; `ReaderList.Default` alone has only mzML/mzMLb/mzXML/MGF/MSn/BTDX | yes - Osprey needs its own registration |

Each of these is a one-line decision in the new reader, and each gets a comment saying which
`MsDataFileImpl` behaviour it mirrors, so a future divergence is visible rather than silent.

Note the vendor SDKs need no opt-in property on the Osprey side: pwiz-sharp already gates
them itself (`IAgreeToVendorLicenses`, and `NativeVendorsAvailable` = that AND Windows), and
a vendor project without the licenses compiles in `NO_VENDOR_SUPPORT` mode where `Identify()`
still works and `Read()` throws. So `Osprey.IO`'s `OspreyVendorReader` opt-in - which existed
only because #4502 needed a staged bjam x64 build - goes away entirely.

## Tasks

- [x] **Decide the net8 reader seam** - direct pwiz-sharp reference (above)
- [x] Drop `net472` from `pwiz_tools/Osprey/Directory.Build.props`; remove the
      net472-conditional package references and the `OspreyVendorReaderEnabled` net472 gate
      in `Osprey.IO.csproj`
- [x] Collapse `SpectrumFileReader` to a single pwiz-backed path (no `OSPREY_VENDOR_READER`
      conditional, no `OSPREY_MZML_VIA_MZMLREADER` escape hatch once there is no second
      reader to compare against)
- [x] Delete `Osprey.IO/MzmlReader.cs` and the plumbing built around it. **Correction to the
      issue text**: `Osprey.Core/ProgressStream.cs` must STAY - `DiannTsvLoader.cs:79` uses it
      independently of any mzML read. Only the `MzmlReader` references in its comments go.
      `ScoringTaskShared.cs`'s notes on the sequential `XmlReader` producer do go.
- [x] Retarget the tests that pinned `MzmlReader` behaviour - they are the regression test
      for this change, see below
- [x] Update `pwiz_tools/Osprey/Jamfile.jam` / build scripts for a single TFM
- [ ] Build + unit tests green (BLOCKED on the .NET 8 SDK, see Progress Log)
- [ ] `--task PerFileScoring` takes vendor raw AND mzML on net8.0
- [ ] `regression.ps1 -Dataset All` green; characterize any divergence, do not rebaseline
- [ ] Verify a run on Linux/WSL with no Wine container

### Deliberately NOT done (noted, out of scope)

* `Jamfile.jam`'s `OspreyTest` target points at
  `Osprey.Test/bin/x64/$(CONFIGURATION)/Osprey.Test.dll` with **no TFM subdirectory**, so it
  cannot have been finding the assembly even before this change (the SDK has always written
  it under a TFM folder). Pre-existing, unrelated to the reader swap; left alone rather than
  folded into this diff.
* The long tail of `// ... on net472` comments explaining code shape (`SystemMemory.cs`,
  `StreamingFdr.cs`, `ScoringTest.cs`, ...). Each marks a compatibility choice that could now
  be simplified, but simplifying them is a separate change and "do not reformat unrelated
  code" applies.

## Regression Test

- **Test names**: `TestSpectrumFileReaderRetentionTimePrecision`,
  `TestSpectrumFileReaderIsolationWindowParsing`,
  `TestSpectrumFileReaderMs1Ms2Separation`,
  `TestSpectrumFileReaderRetentionTimeSeconds`,
  `TestSpectrumFileReaderFormatRouting`, `TestVendorCacheUsableWithoutVendorSdk`
- **Test project**: Osprey.Test (+ `regression.ps1` / the Perf-Regression config for the
  dataset run)
- **Fails on master**: n/a in the usual sense - see below
- **Passes on fix**: (pending - blocked on the .NET 8 SDK)

The usual red-then-green shape does not apply to a deletion, but this change turned out to
have a better verifier than a new test: **the four mzML tests that pinned the deleted reader
were kept and pointed at the new one.** They build a minimal mzML from test helpers and
assert on the parsed Osprey spectra, so with the assertions untouched they now say "pwiz-sharp
produces the same Osprey spectra from the same bytes that the hand-written reader did".

That makes them the direct check on the semantics this change had to reproduce by hand
(see the decision table above): the RT-precision case fails if `GetStartTime` routes a
minute-valued scan time through `TimeInSeconds()/60`; the seconds case fails if the unit
conversion is wrong in the other direction; the isolation-window case fails if the
lower/upper CVs are read as widths or absolute bounds instead of offsets; the MS1/MS2 case
fails if level dispatch or precursor selection moved.

Beyond the unit suite, `regression.ps1 -Dataset All` is what proves the reader swap against
real acquisitions. Any divergence there is characterized as a defect, never rebaselined with
`-CreateGolden`: the goldens were captured through Osprey's own parser, and pwiz is the
reference.

## Progress Log

### 2026-08-17 - Session Start

Starting work on this issue.

* Branched `Skyline/work/20260817_osprey_net8_pwiz_sharp` off `origin/chambem2/pwiz-sharp`
  (`5ef89bd228`) rather than master - stacked PR per #4311.
* Surveyed the base and recorded the findings above. The `net8.0` vs `net8.0-windows` TFM
  mismatch between Osprey and `ProteowizardWrapper` is the first thing to resolve; it
  decides whether Osprey talks to pwiz-sharp through the wrapper or directly.
* Resolved it in favour of a direct pwiz-sharp reference (see the design section) and
  implemented the whole change:
  * `Directory.Build.props` is `net8.0` only; the net472-conditional `System.Memory`
    references and the `OspreyVendorReader` opt-in machinery are gone, as is
    `Osprey/app.config` (net472 server-GC settings only).
  * `Osprey.IO` now project-references pwiz-sharp's `MsData` / `Analysis` / `Common` /
    `Util` plus the eight vendor readers `ProteowizardWrapper` registers for Skyline.
  * `SpectrumFileReader.cs` rewritten as the single reader, against pwiz-sharp directly;
    `SpectrumFileReader.Vendors.cs` added for `ReaderList.AdditionalReaders` registration.
  * `MzmlReader.cs` (742 lines), `VendorRawReader.cs` (182), `NativeStrtod.cs` and
    `OspreyEnvironment.MzmlViaMzmlReader` deleted. `NativeStrtod` was the .NET-Framework
    correctly-rounded `strtod` interop that existed only for the deleted parser, and its own
    doc said it retires with it - it had no other caller.
  * `MzmlResult` renamed to `SpectrumFileResult`; it lived in the deleted `MzmlReader.cs` and
    the old name was the last mzML misnomer on the type the pipeline consumes.
  * `Jamfile.jam` lost ~110 lines: the `pwiz_data_cli` assembly reference, the wrapper
    pre-build, the vendor-API install to `bin/x64/*/net472`, the msparser requirement and the
    two native-runtime installs. `--i-agree-to-the-vendor-licenses` now simply forwards to
    pwiz-sharp's own `IAgreeToVendorLicenses` gate.
  * `build.ps1` / `build.bat` / `tcbuild.bat` / `package.ps1` / `regression.ps1` /
    `Directory.Build.targets` and the Osprey docs updated for one TFM.
  * `ai/scripts/Osprey/Build-Osprey.ps1` made branch-agnostic rather than re-defaulted: the
    requested test framework falls back to whichever assembly the build produced, and the
    ReSharper inspection discovers its framework passes from the build output. That keeps the
    shared script correct on master (still `net472;net8.0`) and here at the same time.

**Blocked verifying it: this machine has no .NET 8 SDK** (only 9.0.316 and 10.0.302).
`pwiz-sharp/global.json` pins `8.0.100` with `rollForward: latestFeature`, which 9/10 do not
satisfy, and `pwiz/src/Vendor/Common/Vendor.Common.csproj` shells out to `dotnet run` for its
`VendorSdkPins` generator with an explicit comment that the child must resolve its SDK from
that `global.json` rather than inherit the outer build. Everything else compiled: all of
pwiz-sharp's `MsData`, `Analysis`, `Common`, `Util` and every vendor project built, and the
only source change the integration forced was bumping `System.Data.SQLite.Core` from 1.0.118
to 1.0.119 to match what pwiz-sharp's Bruker and UIMF readers require (NU1605 otherwise).

This is a prerequisite of the base branch, not of this change. `winget install
Microsoft.DotNet.SDK.8` needs UAC, which this session cannot answer (exit 1602).
