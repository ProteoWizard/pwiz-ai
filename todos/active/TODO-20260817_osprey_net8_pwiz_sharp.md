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
- [x] Build + unit tests green (576/576) and ReSharper inspection clean (0/0)
- [x] Vendor raw AND mzML both read on net8.0 - verified via `--task SpectraCache` on both
      (TDP-43 `.raw` and SEA-AD/Stellar `.mzML`). NOTE: `--task PerFileScoring` itself was
      exercised on mzML only, by `regression.ps1`; scoring straight from a `.raw` end to end
      is not covered here.
- [x] `regression.ps1 -Dataset All` green (twice: before and after the review fixes); the
      one divergence found was characterized, not rebaselined
- [x] Verified on Linux/WSL with no Wine container - byte-identical to Windows

### 2026-08-17 - Real-data verification on SEA-AD and TDP-43

Two independent A/Bs on staged acquisitions, both writing to `--cache-dir` scratch so the
reference caches were never touched.

**A. mzML: the deleted parser vs pwiz-sharp. BYTE-IDENTICAL.**

Reference caches in `D:\test\osprey-runs\sea-ad\mzml\` were written 2026-07-18, i.e. by
Osprey's hand-written `MzmlReader`, from msconvert mzML. Re-cached the same two Astral files
through the new reader:

| File | Size | SHA-256 |
|---|---|---|
| SEA-AD-0001_7124_A01_005 | 4,368,477,008 bytes | identical |
| SEA-AD-0002_7297_A02_006 | 4,815,176,236 bytes | identical |

9.18 GB, 328,319 MS2 + 1,967 MS1 spectra, zero differing bytes. **This is the direct answer
to the issue's central question: deleting `MzmlReader` changes nothing.** It also
retroactively validates the unit-test fixture change - real msconvert mzML round-trips
perfectly through the new `GetStartTime`, so the fixture was the only thing that was wrong.

**B. Vendor raw: pwiz C++ (`pwiz_data_cli`) vs pwiz-sharp. RETENTION TIMES ONLY, +-1 ULP,
and the NEW values are the correct ones.**

References in `D:\test\osprey-runs\tdp43-plasma-ev\raw\` were written 2026-07-29 22:26 by
`_bin\vendor-pr4502\Osprey.exe` (the #4502 net472 path).

| | A01-365-001 | A02-11035-002 |
|---|---|---|
| MS2 / MS1 records | 161,099 / 965 identical | 168,944 / 1,012 identical |
| Record offsets differing | 0 | 0 |
| Isolation windows differing | 0 | 0 |
| Retention times differing | 9,145 (5.7%) | 9,502 (5.6%) |
| Magnitude | all +-1 ULP, max 3.6e-15 min | same |

A byte census on A01 supports the strong claim: **18,339 differing bytes, every one an
isolated single byte, none straddling an 8-byte boundary.** That reconciles exactly - 9,145
MS2 retention times x 2 (each appears in its record AND in the trailing index) = 18,290,
plus 49 differing MS1 retention times = 18,339. Peak arrays, m/z, intensities and isolation
windows are bit-identical.

**Characterized, not rebaselined.** The first differing value is `0.5903116999999999`
(reference) -> `0.5903117` (new) - the exact value named in PR #4501, "Preserved retention
time precision when reading vendor files", whose defect was `TimeInSeconds()/60` multiplying
by 60 and dividing again. Dates settle it: the reference caches were built 2026-07-29 22:26,
and #4501 (`72e0401`) merged 2026-07-30 16:37, eighteen hours later. **The reference carries
the pre-#4501 error; the new values are correct.** The near-symmetric ULP split (4,580 down
/ 4,565 up on A01) is rounding noise, not a systematic shift.

This is the post-#4501 `GetStartTime` - one of the six semantics the direct reader had to
mirror by hand - demonstrated correct on ~330,000 real Thermo spectra.

Note what B compares: pwiz C++ against Matt's managed port, with identical Osprey code
downstream. A divergence there could have been a pwiz-sharp defect rather than an Osprey
one. It was neither.

### 2026-08-17 - /code-review max, and the bug it caught

Ran before opening the PR, per the version-control skill. 15 findings; the ones acted on:

**#1 - REAL BUG I INTRODUCED. Vendor centroiding was partly a no-op.** I passed msconvert's
`"1-"` spelling to `SpectrumList_PeakPicker`'s STRING overload, whose `ParseIntegerSet`
splits on `,`/space and `int.TryParse`s each token - `int.TryParse("1-")` is false, so the
MS-level set was EMPTY and `!_msLevels.Contains(msLevel)` returned early for every spectrum.

Verified in the source rather than taken on faith, and one nuance matters:
`SpectrumList_PeakPicker.cs:114` assigns `_vendorCentroidPath` from
`preferVendor && inner is IVendorCentroidingSpectrumList` ALONE, independent of `_msLevels`,
and `GetSpectrum` calls it BEFORE the level check. Thermo implements that interface, so
vendor-centroided peaks were still delivered - which is exactly why the TDP-43 peak arrays
came back bit-identical to the `pwiz_data_cli` reference. That result stands and is now
explained rather than lucky. What was dead: the profile->centroid CV relabeling (metadata
Osprey never persists) and the `VendorOnlyPeakDetector` fail-fast.

The real exposure is **Agilent**, which does NOT implement the interface: it was silently
reading PROFILE peaks and scoring them as centroids. Fixed with the in-tree template
(`pwiz-sharp/Tools/BiblioSpec/.../PwizSharpSpecFileReader.cs:111-118`) -
`IntegerSet(1, int.MaxValue)`, `algorithm: null` - plus an explicit guard that REFUSES a
vendor file with no centroiding rather than reading profile data.

**#5 - a regression I introduced.** `Jamfile.jam` passed
`IAgreeToVendorLicenses=$(OSPREY_VENDOR_LICENSES)` unconditionally, and `/p:` sets a GLOBAL
MSBuild property that outranks the `Directory.Build.user.props` written by
`i-agree-to-the-vendor-licenses.bat`. A developer with a standing opt-in running plain
`bjam Osprey` would silently get a NO_VENDOR_SUPPORT build. Now only the `true` form is
emitted, matching pwiz-sharp's own `build.bat`.

**#12** `(uint) spectrum.Index` was an unchecked cast of a property pwiz-sharp documents as
`-1` when unassigned - 4294967295 into every cache and `.blib`. Now uses the read loop's
index. **#9** `Debug.WriteLine` is `[Conditional("DEBUG")]`, so a failed vendor registration
left no trace in any shipping build; now goes through `OspreyOutput`.

**Re-verified after the fixes** (the read path AND the index source both changed, so this
was checked, not assumed): the TDP-43 raw cache is byte-identical to the pre-fix output, and
the SEA-AD mzML cache is still byte-identical to the Jul-18 reference. 575/575 tests,
inspection 0/0.

### 2026-08-17 - Committed: 3a18479f8e (pushed, PR not yet opened)

Prompted by Brendan: **read `ai/todos/completed/TODO-20260729_osprey_vendor_raw_reader.md`
before claiming thoroughness.** Two corrections came out of it.

1. **`ai/scripts/Osprey/Compare/Compare-SpectraCache.ps1` already existed** and implements
   exactly the right method (mask bytes 12..27 - source size + mtime, the only bytes derived
   from file identity rather than content - and byte-compare the rest, deliberately NOT
   masking n_ms2/n_ms1 so a count difference fails first). I hand-rolled comparators instead,
   against my own standing note to check `ai/scripts` first. Re-ran sea-ad through the
   sanctioned tool: `PARITY: 4,368,477,008 bytes identical`, matching both my result and the
   figure recorded in the #4496 TODO.
2. **The retention-time ULP finding was NOT new.** #4496 already recorded "the original 9,269
   differences were `GetStartTime`". My 9,145 on a different file is the same mechanism,
   already characterized and fixed by #4501. The conclusion stands; the discovery framing did
   not.

**Validation axes, compared against what #4496 did:**

| Axis | #4496 | Here |
|---|---|---|
| Same mzML, old reader vs new | PARITY | **done** - 9.18 GB byte-identical, 2 SEA-AD files |
| raw-sourced vs mzML-sourced, same file | PARITY 2,260,174,556 | **done small** (committed test); full-scale pending |
| raw via `pwiz_data_cli` vs via pwiz-sharp | n/a | done - RT-only +-1 ULP, explained by #4501 |

**Landed #4496's Tier 2, which it designed and never shipped**: `TestRawVsMzmlSpectraParity`
reads the tracked `source_cid_test_3scans.raw` and its `-centroid.mzML` and compares scan
number, RT, precursor m/z, isolation window and every peak, exactly. No off-repo data, no
msconvert run, so it can gate CI. Both branches assert: with the vendor SDK it checks parity,
without it checks the error NAMES the file - it never silently passes.

That test earned its place on its first run: it failed, because pwiz-sharp's
`VendorSupportNotEnabledException` message names no file and tells the user to rebuild
*pwiz-sharp* with `--i-agree-to-the-vendor-licenses`, which is not how Osprey is built (review
finding #11). Fixed by restating it in Osprey's terms with the original as InnerException,
rather than by weakening the assertion.

Gates at commit: 576/576 tests, inspection 0/0, `regression.ps1 -Dataset All` PASSED
(all four datasets, all goldens) AFTER the review fixes.

### Next session picks up here

1. **WSL** - Brendan installed it 2026-08-17 and a reboot was pending. After reboot:
   `dotnet publish -r linux-x64` and run the suite plus `--task SpectraCache` on an mzML
   under WSL. This is the issue's "runs on Linux/WSL without the Wine container" criterion
   and the last unmet acceptance item.
2. **Full-scale raw-vs-mzML** - msconvert is at
   `pwiz/build-nt-x86/msvc-release-x86_64/msconvert.exe`; settings in
   `ai/scripts/Osprey/SEA-AD/convert-one.cmd`. Convert one TDP-43 raw, cache both ways,
   compare with `Compare-SpectraCache.ps1`. CAVEAT from the #4496 TODO: a pre-precision-fix
   msconvert against a full-precision raw read is a KNOWN mismatch (its table, "no A / A"),
   and PR #4500 was closed - so interpret, do not just report a verdict.
3. Open the stacked PR against `chambem2/pwiz-sharp` (base is NOT master).

### Decisions from Brendan, 2026-08-17

1. **`SpectraCache.VERSION` bump - NO.** Few `.spectra.bin` caches exist and they are all
   our own test data, so a global version bump to protect a scenario only we hit is a poor
   trade. Residual risk accepted and mitigated by hand: **when running an A/B that must not
   reuse old-reader output, write to a fresh `--cache-dir`** (which is what every comparison
   in this TODO did) or delete the cache first. Noting the reading in case it was the
   opposite - reversing it is a one-line change to `SpectraCache.cs:87`.
2. **`CreateReaderConfig` flags - ASK MATT CHAMBERS.** Left exactly as-is pending his answer.
   The question, stated for handing over:
   > Osprey reads vendor files through pwiz-sharp and pins three `ReaderConfig` flags
   > OPPOSITE to pwiz cpp's defaults, inherited from Skyline's `MsDataFileImpl`:
   > `AcceptZeroLengthSpectra=true` (cpp false), `IgnoreCalibrationScans=true` (cpp false),
   > `AllowMsMsWithoutPrecursor=false` (cpp true). Consumers are Sciex + Agilent
   > (zero-length), Waters only (calibration scans). Thermo consumes none, which is why the
   > #4502 parity measurement could not have caught a difference. Should Osprey follow
   > Skyline's choices or msconvert's defaults? A mismatch changes WHICH spectra exist, and
   > Osprey writes the spectrum index as its scan number, so every record after the first
   > difference shifts.
   > (Also: pwiz-sharp's `AllowMsMsWithoutPrecursor` appears inert - no reader consumes it,
   > and `IReader.cs:168` calls it "Advisory". Worth confirming.)
3. **Vendor license in CI / packaging - NOT THIS PR, and NOT via a committed file.**
   Committing the agreement would invalidate the license. The route is TeamCity with a
   secret plus code signing, as its own piece of work. **Verified this branch complies**:
   the only committed line that SETS the property is `Jamfile.jam:96`, gated on
   `--i-agree-to-the-vendor-licenses` appearing on the command line, so the agreement is
   the builder's act rather than something the repo asserts - the same pattern
   `Skyline/Jamfile.jam:22` uses. `Directory.Build.user.props` is gitignored and untracked.
4. **linux-x64 RID gating - NOT NOW.** Pairs with 3; both belong to the packaging work.

### Open findings NOT yet dispositioned

* **#3 - bump `SpectraCache.VERSION`.** The file's own history sets the precedent (VERSION 2
  was bumped for a reader behaviour change). Correct in principle: caches written by the old
  reader are silently reused, which can turn an A/B meant to validate this change into a
  false green. Cost: invalidates every existing cache, including the 484 GB SEA-AD set and
  the 163 TDP-43 caches. Not done unilaterally.
* **#7 - `CreateReaderConfig` vs msconvert defaults.** `AcceptZeroLengthSpectra`,
  `IgnoreCalibrationScans` and `AllowMsMsWithoutPrecursor` are pinned OPPOSITE to pwiz cpp's
  defaults, inherited from `MsDataFileImpl`. Consumers are Sciex/Agilent/Waters - never
  Thermo - which is why #4502's parity measurement could not have caught it. Deciding
  whether Osprey wants Skyline's choices or msconvert's is a data question, not a code one.
* **#6 - no build entry point sets the vendor license.** `build.ps1`, `package.ps1`,
  `tcbuild.bat` and `regression.ps1` never pass it, so CI artifacts and the shipped
  win-x64/linux-x64 zips contain readers that throw on every vendor file. Pre-existing in
  shape (the net472 world had the same opt-in), but #4497 is what makes it user-visible.
* **#8 - linux-x64 packaging.** pwiz-sharp gates native vendor SDKs on the BUILD HOST OS,
  not the target RID, so once #6 is wired up a cross-published linux zip would carry Windows
  PEs. Belongs with #6.

### Follow-up when this merges

`ai/` is one shared master serving every branch, and on master `OspreyVendorReader`,
`MzmlReader` and `pwiz_data_cli` all still exist - so these describe the world correctly
today and must NOT be edited until this lands:

* `ai/docs/new-machine-setup.md`
* `ai/scripts/Osprey/SEA-AD/README.md`, `ai/scripts/Osprey/TDP43/README.md`

`ai/scripts/Osprey/Build-Osprey.ps1` is the exception and was changed now, because it was
made branch-AGNOSTIC rather than switched over: it reads the declared frameworks from
`Directory.Build.props` and picks the vendor-enable mechanism from them, so it is correct on
master and here simultaneously.

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

### 2026-08-17 - Verification, and two defects it exposed

.NET 8 SDK installed (8.0.424), which unblocked everything below.

**Gates passed**: Debug build; **575/575 unit tests**; ReSharper inspection **0 warnings /
0 errors**; `regression.ps1 -Dataset All` **PASSED - all four datasets, every mode**
(Stellar, StellarLibDecoy, StellarGenDecoyEntrap, Astral; modes 1, 1b, 2, 3, 4 as each
carries them), including all four `mode1 (vs golden)` and both `mode1b (diagnostics vs
golden)`. That is the result that matters: real mzML read through pwiz-sharp instead of the
deleted hand-written parser reproduces every committed golden. No divergence to
characterize, nothing rebaselined.

**Defect 1 (in the BASE branch, fixed here): Bruker does not compile without vendor
licenses.** `pwiz-sharp/pwiz/src/Vendor/Bruker/BrukerFormat.cs` had
`<see cref="CompassXtractData"/>` in two doc comments, but `CompassXtractData.cs` is
`Compile Remove`d when `$(NativeVendorsAvailable)` is not true. With pwiz-sharp's
`GenerateDocumentationFile` + `TreatWarningsAsErrors`, the unresolvable cref is CS1574 -
a build ERROR in exactly the no-licenses configuration. Osprey is the first consumer to
build the vendor projects that way, which is why it had not surfaced. Fixed by making the
two references `<c>` instead of `<see cref>` (a doc comment cannot be conditionally
compiled). Two lines in Matt's branch, forced by a real break rather than preference - the
"zero edits to it" claim above is now "two doc-comment lines".

**Defect 2 (mine): a Release Osprey was linking the DEBUG pwiz-sharp assemblies.** Building
a `.sln` unsets Configuration and Platform across a `ProjectReference` to a project that is
not in that solution (`ShouldUnsetParentConfigurationAndPlatform`, on by default), and none
of the pwiz-sharp projects are in `Osprey.sln`. So they built Debug regardless, and
`pwiz-sharp/.../bin/` contained only a `Debug` folder after a Release Osprey build. The only
visible symptom was the copy source path in the build log - the code is correct either way,
so no test could have caught it. Fixed with `SetConfiguration` / `SetPlatform` metadata on
the references.

Found while rebuilding for the raw-file check, not by a gate. Worth remembering: a
cross-solution `ProjectReference` needs those two metadata items or it silently builds the
wrong configuration.

**(Resolved 2026-08-17 - kept for the record.) Blocked verifying it: this machine had no
.NET 8 SDK** (only 9.0.316 and 10.0.302).
`pwiz-sharp/global.json` pins `8.0.100` with `rollForward: latestFeature`, which 9/10 do not
satisfy, and `pwiz/src/Vendor/Common/Vendor.Common.csproj` shells out to `dotnet run` for its
`VendorSdkPins` generator with an explicit comment that the child must resolve its SDK from
that `global.json` rather than inherit the outer build. Everything else compiled: all of
pwiz-sharp's `MsData`, `Analysis`, `Common`, `Util` and every vendor project built, and the
only source change the integration forced was bumping `System.Data.SQLite.Core` from 1.0.118
to 1.0.119 to match what pwiz-sharp's Bruker and UIMF readers require (NU1605 otherwise).

This is a prerequisite of the base branch, not of this change. `winget install
Microsoft.DotNet.SDK.8` needs UAC, which this session cannot answer (exit 1602).

### 2026-08-17 - Linux/WSL verification (the last acceptance criterion)

WSL2 + Ubuntu installed after Brendan's reboot. `package.ps1 -Rid linux-x64 -Configuration
Release -NoZip` produced a self-contained publish; under WSL it is a real ELF
(`ELF 64-bit LSB pie executable, x86-64 ... dynamically linked`) and reports
`Osprey v26.1.1.229 (3a18479f8e)` - the commit on this branch. **No Wine, no container.**

**Finding worth carrying into the PR**: the "self-contained" publish is not free of system
dependencies. On a bare Ubuntu image it fails at startup with

    Couldn't find a valid ICU package installed on the system.

`package.ps1`'s doc claims "Self-contained means ZERO system-.NET dependency: copy the folder
to an HPC node and run it." That is true of .NET itself but not of **libicu**, which the
runtime needs for globalization. Installing `libicu-dev` fixed it immediately. A real HPC
node almost certainly has it, so this is a documentation gap rather than a defect - but a
node that does not have it fails with a message about ICU, not about Osprey. Worth either
amending the claim or setting `InvariantGlobalization` deliberately (note pwiz-sharp sets it
true for its own libraries and Thermo explicitly opts OUT, because the Thermo SDK constructs
CultureInfo("en-US") - so that switch is not free and needs care).

**Cross-platform byte parity - the strongest result of the whole change.** The same SEA-AD
Astral mzML cached on Linux under WSL2 and compared with `Compare-SpectraCache.ps1` against
the Windows cache:

    PARITY: 4,368,477,008 bytes identical (source fingerprint masked)
        n_ms2=162,620  n_ms1=974  compared in 24.2s

That makes a three-way identity on one 4 GB acquisition:

| Producer | Reader | Result |
|---|---|---|
| Windows, 2026-07-18 | Osprey's hand-written `MzmlReader` | reference |
| Windows, 2026-08-17 | pwiz-sharp | identical |
| **Linux/WSL2, 2026-08-17** | pwiz-sharp | **identical** |

So deleting the hand-written reader changed nothing, and the replacement is deterministic
across operating systems - 162,620 MS2 and 974 MS1 spectra, every peak, every retention time,
every isolation window. The acceptance criterion "Runs on Linux/WSL without the Wine
container" is met in the strongest available form: not merely runs, but produces the same
bytes.
