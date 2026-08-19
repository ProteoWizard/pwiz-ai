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

## Session end 2026-08-18 - branch complete, PR deliberately not opened

`C:\proj\pwiz` is on `Skyline/work/20260817_osprey_net8_pwiz_sharp` @ `3a18479f8e`, clean,
pushed, nothing unpushed. Every gate is green: 576/576 unit tests, ReSharper 0/0,
`regression.ps1 -Dataset All` passed twice (before and after the `/code-review max` fixes),
byte comparisons on SEA-AD and TDP-43, and byte-identical output between Windows and
Linux/WSL2.

**The PR is NOT opened on purpose.** If the CommonUtil WinForms split
(`TODO-20260818_commonutil_winforms_split.md`) lands in Matt's branch first,
`ProteowizardWrapper` becomes plain `net8.0`, Osprey can go back through it, and the six
`MsDataFileImpl` semantics this branch reproduces BY HAND get inherited from one place again.
Decide that sequencing before opening. Draft PR body: `ai/.tmp/pr-4497-body.md`.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260818_commonutil_winforms.md` before starting work.

## Session 2026-08-18 (evening) - rebased onto the CommonUtil split; design decision REOPENED

`C:\proj\pwiz` is now on `Skyline/work/20260817_osprey_net8_pwiz_sharp` @ `1ed9ed74c3`,
clean, force-pushed. It no longer sits on `chambem2/pwiz-sharp` directly - it sits on
**`Skyline/work/20260818_commonutil_winforms_split`** (PR #4587), so development can
continue before Matt merges. Rebase back onto `chambem2/pwiz-sharp` once he does; the
shared commits will drop out as duplicates.

Stack, bottom to top:

    9f6fa31949  Fixed two build breaks on the pwiz-sharp branch
    f5d452fd36  Split the WinForms half of CommonUtil into CommonBaseUI
    4f3b2c9150  Made CommonUtil and ProteowizardWrapper plain net8.0, retired PortableUtil
    99e5ef965c  Added a build-only mode to build.bat, dropped Osprey's net472 target
    3b6755c392  Fixed installer manifests and two weakened verifiers
    69b331e7f0  osprey: Made ProteoWizard the only spectrum reader on net8.0   <- was 3a18479f8e
    1ed9ed74c3  osprey: Forwarded the vendor licence flag instead of warning it was inert

Pre-rebase state is tagged `pre-rebase-20260818` locally in `C:\proj\pwiz`.

### THE decision to make first

**`ProteowizardWrapper` is now plain `net8.0`.** The "Design decision" section above chose
to read pwiz-sharp DIRECTLY, and said so explicitly: *"The wrapper route is closed by a TFM,
not by taste."* That TFM is gone. So the choice is live again:

* **Through the wrapper** - delete the six hand-reproduced `MsDataFileImpl` semantics (RT in
  minutes, isolation offsets, vendor centroiding, `CombineIonMobilitySpectra=false`,
  `AllowMsMsWithoutPrecursor=false`, `IgnoreCalibrationScans=true`) and inherit them from one
  place. Also makes the `CreateReaderConfig` question below mostly moot.
* **Stay direct** - smaller surface, no dependency on a Skyline-facing wrapper, but the six
  semantics stay duplicated and can drift.

Nothing is blocked on this - the branch is green either way. It is a design call, and it is
the first thing the next session should settle with Brendan.

### Verified after the rebase

* Osprey build + **576/576 tests** green on the new base (`Build-Osprey.ps1 -RunTests`)
* `BrukerFormat.cs` collapsed automatically - git saw identical content, so the branch now
  carries that fix once instead of twice. The "drop it on the next rebase" item is DONE.
* Two rebase conflicts, both resolved deliberately rather than mechanically:
  * `Directory.Build.props` - kept this branch's fuller net472 rationale, but replaced its
    now-false closing clause (that the wrapper is `net8.0-windows`) with a note that the
    constraint is gone and the decision is open.
  * `build.ps1` - took this branch's full removal of `$Framework` over the other branch's
    narrowed `ValidateSet`.

### Finding #6 partially addressed

`build.ps1` gained a real `-IAgreeToVendorLicenses` switch that reaches MSBuild, and
`build.bat` now translates `--i-agree-to-the-vendor-licenses` into it. Verified: builds
succeed with the flag. **Still unwired: `package.ps1`, `tcbuild.bat`, `regression.ps1`** -
CI artifacts and the shipped zips still contain readers that throw on vendor files.

### Correction to "Next session picks up here" above

That list is stale. Item 1 (WSL) is DONE and ticked in Tasks - Linux/WSL2 output was verified
byte-identical to Windows. Only item 3 (open the PR) survives, and it now depends on the
design decision above.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260817_osprey_net8_pwiz_sharp.md` before starting work.

## Session 2026-08-18 (evening, part 2) - decision made: THROUGH the wrapper

Brendan settled the reopened design decision in favour of `ProteowizardWrapper`, on DRY
grounds: having to reason about how the shared code behaves for Skyline as well as Osprey
is the point, not a tax. He also read `IgnoreCalibrationScans = true` as right for Osprey
on its merits - inappropriate for reading raw data or writing verbatim mzML, but correct
for a search, which should not be hunting peptides in calibration scans.

### What the wrapper route exposed before a line of Osprey changed

Writing the wrapper version surfaced three defects in shared code, all pre-existing, none
of them Osprey's. They are fixed in `pwiz-work1` on PR #4587's branch, not here, because
they are Skyline-shared code:

1. **Vendor centroiding was a no-op through the wrapper** - the same bug `/code-review max`
   caught in Osprey's direct reader, still live in `MsDataFileImpl`. It passes `"1-"` to
   `SpectrumList_PeakPicker`'s STRING overload, whose private `ParseIntegerSet` splits on
   `,`/space and `int.TryParse`s each token - no range syntax at all - so the level set was
   EMPTY and `GetSpectrum` returned every spectrum unpicked. `IntegerSet.Parse` in the same
   assembly handles `"1-"` correctly (regex group `b3`, `e = int.MaxValue`); the picker just
   never called it. Fixed by delegating.
   * **net472 is unaffected** - C++ `IntegerSet.cpp:96` handles the trailing dash, which is
     why `msconvert --filter "peakPicking vendor msLevel=1-"` has always worked. A port
     defect in the managed re-implementation, not a long-standing Skyline bug.
   * `SpectrumListFactory` is unaffected too - it builds a real `IntegerSet` via `.Parse()`.
     The blast radius was the string overload's callers: the wrapper and `ReaderTestConfig`.
   * Thermo/Waters/Sciex still got vendor centroids anyway, because `_vendorCentroidPath` is
     assigned from `inner is IVendorCentroidingSpectrumList` alone. **Agilent** does not
     implement it, so it silently returned PROFILE peaks and the `VendorOnlyPeakDetector`
     fail-fast never fired.
   * Regression test added at the untested seam: `PeakPickingTests.cs` now asserts the ctor
     overload agrees with `IntegerSet.Parse` for `1-`, `2-`, `1`, `1,2`, `2-3`.
2. **`ProteowizardWrapper`'s net8 target did not compile without vendor licenses.**
   `MsDataFileImpl.cs:798` used `SpectrumList_LockmassRefiner` unguarded, and pwiz-sharp
   `Compile-Remove`s it (plus defines `NO_VENDOR_SUPPORT`) when the licenses are not agreed.
   That is the configuration CI and the shipped zips build, and it is Osprey's default.
   Same family as the `BrukerFormat.cs` CS1574 break: Osprey is the first consumer to build
   these projects no-vendor. Guarded with `#if NO_VENDOR_SUPPORT`, throwing rather than
   silently dropping a lockmass correction the caller asked for.
   * The guard needed the property, and **the two ways of agreeing do not have the same
     reach**: `-p:IAgreeToVendorLicenses=true` is global and arrives everywhere, but
     `i-agree-to-the-vendor-licenses.bat` writes `pwiz-sharp/Directory.Build.user.props`,
     which only `pwiz-sharp/Directory.Build.props` imports - nothing under `pwiz_tools/`
     ever saw it. `ProteowizardWrapper.csproj` now imports the same file, so both routes
     agree. Without that, the `.bat` route would have left pwiz-sharp compiling the refiner
     while the wrapper believed it absent - lockmass silently dropped from a build that
     fully supports it.
3. **Vendor registration failures left no trace in any shipping build** - the wrapper's
   `Debug.WriteLine` is `[Conditional("DEBUG")]`, i.e. Osprey's own review finding #9, again
   in the shared copy. Now collected into `VendorReaderRegistration.Failures` and surfaced
   by the host; Osprey prints them through `OspreyOutput`.

### Also found, NOT fixed (out of scope, pre-existing)

* **Skyline net8 cannot build no-vendor at all.** With defect 2 fixed, the build gets past
  compilation and then fails copying vendor native runtime files that a no-vendor build
  never produces (`MBI_SDK.dll`, `MIDAC.dll`, `MobilionShim.dll`, `msvcp120.dll`,
  `msvcr120.dll`, `OFX.Logging.dll`, ...). `Skyline.csproj` copies them unconditionally.
  Does NOT block Osprey, which does not build `Skyline.csproj`. Matt should know.
* **CORRECTED - pwiz-sharp DOES have a sanctioned runner, and I missed it.** I first
  concluded there was no way to run its tests (`Build-Osprey.ps1` runs only `Osprey.Test`,
  `Build-Skyline.ps1`'s targets are all Skyline projects, and the `Deny-DirectBuildTest`
  hook blocks the direct SDK test command). Wrong: **`pwiz-sharp/build.bat` is exactly that
  runner** - TeamCity's `tcbuild.bat` calls it - and it DISCOVERS test projects by globbing
  `*.Tests.csproj` under `pwiz\test\` and `Tools\` rather than keeping a list.
  `pwiz-sharp/scripts/Run-Tests-Parallel.ps1 -TestProjects <paths>` is the targeted form,
  but it passes `--no-build`, so the assemblies must exist first. The test is RUN and green.
* What IS missing is discoverability from our side: nothing under `ai/` mentions pwiz-sharp,
  and the `Deny-DirectBuildTest` hook names only the Skyline and Osprey wrappers, which is
  what made "no way to run these" look like the right conclusion. Brendan is asking Matt for
  a `/pwiz-development` skill backed by `ai/docs/pwiz-development-guide.md`; draft email
  written 2026-08-18 (Gmail draft to matt.chambers42@gmail.com, Brendan CC'd).
* Also found: **`build.bat`'s own no-vendor path cannot run its tests** - without
  `--i-agree`, `BUILD_TARGET` is just `MsConvert.csproj`, so the test projects are never
  built and `Run-Tests-Parallel.ps1` runs `--no-build` against nothing. TeamCity always
  passes `--i-agree`, so CI never walks it. A third under-exercised no-vendor path.
* Hook false positive worth knowing: `Deny-DirectBuildTest` matched the blocked command
  name appearing INSIDE a grep pattern, blocking a read-only search.

### The Osprey change

`Osprey.IO.csproj`: twelve pwiz-sharp `ProjectReference`s collapse to one on
`ProteowizardWrapper`, which pulls the same eight vendor projects transitively.
`SpectrumFileReader.Vendors.cs` (79 lines) deleted outright - the wrapper registers the
readers from a `[ModuleInitializer]`. `SpectrumFileReader.cs` drops `CreateReaderConfig`,
`CreateSpectrumList` and seven private helpers (`GetStartTime`, `GetPrecursor`,
`GetPrecursorMsLevel`, `GetPrecursorMz`, `GetIsolationWindowValue`, `GetMsLevel`,
`ToArray`) - 489 lines of reader down to about 250, and the six semantics are now
inherited rather than reproduced.

**The `ReaderConfig` is equivalent, argument for argument.** Checked rather than assumed:
`simAsSpectra: true`, `requireVendorCentroidedMS1/MS2` on a vendor path, and
`combineIonMobilitySpectra: false` are the three that differ from the wrapper's defaults;
everything else the old `CreateReaderConfig` set explicitly (`SrmAsSpectra`,
`AcceptZeroLengthSpectra`, `IgnoreZeroIntensityPoints`, `PreferOnlyMsLevel`,
`ReportSonarBins`, `IncludeIsolationArrays`, `GlobalChromatogramsAreMs1Only`,
`AllowMsMsWithoutPrecursor`, `IgnoreCalibrationScans`) the wrapper sets to the same value.
Note `PreferOnlyMsLevel` is computed as `combineIonMobilitySpectra ? 0 : preferOnlyMsLevel`,
which with combining off is 0 either way.

**One deliberate behaviour change.** Osprey passed `algorithm: null` to the peak picker and
guarded the LIST (`is IVendorCentroidingSpectrumList`), which let a spectrum the vendor
declined to centroid pass through as PROFILE. The wrapper passes `VendorOnlyPeakDetector`,
which throws per SPECTRUM with the message Skyline converts to `NoCentroidedDataException`.
Stricter and better - Osprey scores centroids - but it is a real difference on data with
non-vendor-centroidable scans, and it only becomes reachable now that defect 1 is fixed.

Two traps handled in the mapping: `MsPrecursor` is a STRUCT, so an empty precursor list has
to be tested by `Count` (`FirstOrDefault()` yields a default with null m/z, scoring an MS2
with precursor 0); and the scan number still comes from the read loop, not
`MsDataSpectrum.Index`, which the wrapper assigns from pwiz-sharp's `-1`-when-unassigned
`Spectrum.Index` (review finding #12 does not go away by moving).

### Gates

* Osprey Debug build through the wrapper, **no-vendor** - succeeds. That is the direct
  verification of defect 2's fix in the configuration that matters.
* **576/576 unit tests**, unchanged count. Includes the four mzML tests that pinned the
  deleted `MzmlReader` and now pin the wrapper path, i.e. the direct check on the six
  inherited semantics, plus `TestRawVsMzmlSpectraParity`.
* ReSharper inspection **0 warnings / 0 errors**. (The handoff's note that `-RunInspection`
  refuses on net8 is stale - it ran.)
* `regression.ps1 -Dataset Stellar` **PASSED** - all five modes, including
  `mode1 (vs golden)`. Real mzML read through the wrapper reproduces every committed
  golden; nothing rebaselined.
* `regression.ps1 -Dataset All` **PASSED** - all four datasets (Stellar, StellarLibDecoy,
  StellarGenDecoyEntrap, Astral), every mode: mode1 vs golden on all four, mode1b
  diagnostics + FDR sanity on the three that carry them, mode3 HPC-chain, mode4 warm
  re-run, mode2 resume. Real mzML read through ProteowizardWrapper reproduces every
  committed golden. Nothing rebaselined.
* pwiz-sharp's own suite via Matt's `build.bat Debug --i-agree-to-the-vendor-licenses`:
  **657 tests across 21 suites, zero failures**, including the new
  `SpectrumList_PeakPicker_StringOverloadParsesPwizIntervalSyntax`. The "committed unrun"
  caveat below is resolved - see the corrected tooling note.

### Byte verification, re-run against the wrapper path (2026-08-18)

Brendan accepted redoing this rather than carrying the direct-reader results over. Both runs
used the vendor-enabled Release snapshot at `D:\test\osprey-runs\_bin\wrapper-4497-vendor`
and wrote to a fresh `--cache-dir` under `D:\test\osprey-runs\_verify`, so no reference
cache was touched.

**A. SEA-AD mzML - PARITY, 4,368,477,008 bytes identical.** `Compare-SpectraCache.ps1`
against the 2026-07-18 reference (written by the deleted `MzmlReader`), n_ms2=162,620,
n_ms1=974, compared in 28.5s. That makes a FOUR-way identity on one 4 GB acquisition:

| Producer | Reader | Result |
|---|---|---|
| Windows, 2026-07-18 | Osprey's hand-written `MzmlReader` | reference |
| Windows, 2026-08-17 | pwiz-sharp, direct | identical |
| Linux/WSL2, 2026-08-17 | pwiz-sharp, direct | identical |
| **Windows, 2026-08-18** | **via `ProteowizardWrapper`** | **identical** |

**B. TDP-43 raw - identical to what the DIRECT reader produced, to the byte.** The
comparison target here is not "no differences": the 2026-07-29 reference carries the
pre-#4501 `TimeInSeconds()/60` error, so the direct reader already differed from it by
18,339 bytes. The question was whether the wrapper reproduces that exact difference.

* file length identical (2,260,174,556), n_ms2=161,099, n_ms1=965 - all matching
* the run logged the same `156 spectra had unsorted centroids` warning as the reference run
* byte census: **18,339 differing bytes**, the same number the direct reader produced.
  Every one an isolated single byte, **0 runs straddling an 8-byte boundary**, 18,339
  distinct 8-byte slots. Reconciles exactly: 9,145 MS2 retention times x 2 (record AND
  trailing index) + 49 MS1 = 18,339.
* first differing double decoded at offset 86,872: reference `0.5903116999999999`,
  wrapper `0.5903117` - the exact value PR #4501 names. The reference is the wrong one.

**The `VendorOnlyPeakDetector` refusal never fired** across 161,099 real Thermo MS2 spectra,
so the one deliberate behaviour change (per-spectrum rather than per-list centroiding
refusal) is inert on this data - stricter without being disruptive. It would fire on a
vendor whose reader declines to centroid, which is what it is there for.

Census tool: `ai/.tmp` scratch script, not committed - `Compare-SpectraCache.ps1` stops at
the FIRST mismatch by design, so it answers "identical?" but not "how many, and where?",
which is the question when a known-wrong reference is the only baseline available.

**C. Linux/WSL2 - PARITY, 4,368,477,008 bytes identical to the Windows wrapper cache.**
`package.ps1 -Rid linux-x64 -Configuration Release -NoZip` produced a self-contained
publish; under WSL2 it is a real ELF (`ELF 64-bit LSB pie executable, x86-64 ... dynamically
linked`) reporting `Osprey v26.1.1.230`. No Wine, no container. The same SEA-AD Astral mzML
cached on Linux compares byte-identical to the Windows run of the same code, n_ms2=162,620,
n_ms1=974.

So the acceptance criterion "runs on Linux/WSL without the Wine container" still holds in its
strongest form after the wrapper swap: not merely runs, but produces the same bytes.

### Committed

`7827f53004` **osprey: Made ProteoWizard reading go through ProteowizardWrapper** - 3 files,
+135 / -368. Stack in `C:\proj\pwiz`:

    3b6755c392  Fixed installer manifests and two verifiers weakened by the CommonBaseUI move
    ba16d3c884  Fixed vendor centroiding and the no-vendor build of the net8 wrapper   <- #4587
    b3a3072491  Recorded vendor reader registration failures instead of dropping them  <- #4587
    a89c957e4d  osprey: Made ProteoWizard the only spectrum reader on net8.0
    ffce6d97b9  osprey: Forwarded the vendor licence flag instead of warning it was inert
    7827f53004  osprey: Made ProteoWizard reading go through ProteowizardWrapper

NOTE the two #4587 commits reached this checkout by `git fetch` from the LOCAL
`C:\proj\pwiz-work1` path, not from origin. This branch is therefore NOT pushable until
those two are pushed to origin and this branch is rebased onto them from there.

### Still to do

1. `/code-review max` on the branch (before the PR exists - see the version-control skill).
2. Push #4587's two commits (needs Brendan's okay - they update an open PR Matt reviews),
   rebase this branch onto origin, then open the PR with `ai/.tmp/pr-4497-body.md`.
4. Push #4587's two new commits and rebase this branch back onto them from origin (the
   rebase so far was from the local `pwiz-work1` path, so this branch is NOT pushable yet
   without that).
5. `/code-review max`, then the PR, which still stacks on #4587.

## Night session 2026-08-18 - PR opened, gate triggered, raw dataset support

**PR [#4588](https://github.com/ProteoWizard/pwiz/pull/4588)** - base
`Skyline/work/20260818_commonutil_winforms_split` (#4587), label `osprey`. Copilot may not
review it, since the base is not master.

**TeamCity**: Osprey Windows .NET Perf/Regression, build
[4140348](https://teamcity.labkey.org/build/4140348) on `pull/4588`. Brendan cleared both the
trigger and a later re-trigger once the raw-dataset work lands on the same branch.

### `f583ba9fab` - the `/code-review max` fixes

The review was NOT flawed and did not need re-running against a PR number; it targeted this
branch's changes accurately. Every finding verified before acting:

* **Real, mine**: `Path.GetExtension` returns EMPTY for a path ending in a separator
  (verified), so a tab-completed vendor DIRECTORY (`sample.d\`) read with centroiding OFF and
  scored profile peaks as centroids. Now trims separators first.
* **Real, newly reachable**: `SpectrumList_Agilent` implements `IIonMobilitySpectrumList,
  IIonMobilityCcsConversion` but NOT `IVendorCentroidingSpectrumList` (verified), so an
  Agilent .d reaches `VendorOnlyPeakDetector` and threw past the
  `VendorSupportNotEnabledException` catch. Now translated the way Skyline translates it in
  three places. This **corrects my own earlier claim** that the stricter per-spectrum refusal
  was "inert" - that was true of Thermo and over-generalized from one vendor.
  `MsDataFileImpl.SupportsVendorPeakPicking` cannot pre-empt it: it answers "is this a vendor
  reader" (true for Agilent), not "does it centroid".
* **Real, mine**: the vendor-registration latch was a non-atomic check-then-set; now
  `Interlocked.Exchange`.
* **Real**: the parity test's `catch (Exception)` overlapped its own success path, since
  Osprey's message interpolates the path; narrowed to `NotSupportedException`.
* **REFUTED**: "TestRawVsMzmlSpectraParity cannot pass with the Thermo SDK." Ran it against a
  vendor build - passes in 159 ms, and the .raw genuinely reads (confirmed separately by
  caching the fixture: ms2=3), so the try branch runs and its eight assertions hold.
* **Known and already dispositioned, not acted on**: SpectraCache VERSION (Brendan decided
  NO), package.ps1 licence (finding #6), Debug-config-in-Release (documented in the csproj).
* **Shared code, deferred to #4587**: mzML with no `unitAccession` yields RT 0 silently;
  `SpectrumList_PeakPicker`'s ParamGroup promotion copies nothing and then deletes the group
  (and mutates the shared group in place); `scans[0]` unguarded on the `simAsSpectra` path
  this change now takes for every file.

Gates after those fixes: 576/576 no-vendor, 576/576 vendor, inspection 0/0,
`regression.ps1 -Dataset Stellar` PASSED.

### `regression.ps1 -Source mzML|raw`

Brendan: the two panorama zips exist to PROVE raw and mzML agree, and `-v2` specifically
means the mzML carries post-#4501 retention times - without that the two acquisitions could
not agree (#4496 recorded exactly that mismatch; PR #4500 was closed rather than merged).
Same goldens for both; a divergence is to be characterized, never rebaselined.

* URL table keyed by `-Source`; the two zips extract to separate roots, so one machine holds
  both and neither invalidates the other.
* File discovery, the phase-1 cleanup and the three HPC 0-byte stubs now key off
  `$sourceExt` instead of a literal `.mzML`.
* Layout verified identical - `stellar` / `stellar-libdecoy` / `astral`, and the input STEMS
  match exactly, which is what lets both acquisitions share one set of goldens.
* **`-IAgreeToVendorLicenses` added, and REQUIRED for `-Source raw`** unless `-NoBuild`.
  regression.ps1 built through `build.ps1 -Configuration Release -NoTests` with no licence,
  so a raw run would otherwise link NO_VENDOR_SUPPORT readers and throw on every file -
  finding #6 turning from theoretical into a real blocker. Deliberately a switch the INVOKER
  passes: the script does NOT set it merely because `-Source raw` was requested, because
  agreeing has to be the builder's act (Brendan's decision 3 - a repo file that asserts the
  agreement would invalidate it).

### Result: .raw reproduces .mzML exactly, on all four datasets

`regression.ps1 -Dataset All -Source raw` **PASSED** - every dataset, every mode, against
the goldens captured from the mzML acquisition. Nothing rebaselined, nothing tolerated.

| Dataset | vs golden | diagnostics | FDR sanity | HPC chain | warm | resume |
|---|---|---|---|---|---|---|
| Stellar | PASS | - | - | PASS | PASS | PASS |
| StellarLibDecoy | PASS | PASS | PASS | PASS | PASS | PASS |
| StellarGenDecoyEntrap | PASS | PASS | PASS | PASS | PASS | PASS |
| Astral | PASS | PASS | PASS | PASS | PASS | PASS |

The run's own no-copy assertion confirms which acquisition it read:
`data dir unchanged across run: ...\osprey-testfiles-v2\{stellar,stellar-libdecoy,astral}` -
the RAW roots, not the mzML ones.

**What this proves, beyond "the switch works".** The goldens were captured from msconvert
mzML. A raw-sourced search reproducing them means Osprey's ProteoWizard read of a Thermo
.raw agrees with msconvert's conversion of that same .raw through the entire pipeline -
spectra, scoring, calibration, FDR, protein rollup and blib. `StellarGenDecoyEntrap` carries
it furthest: it is the leg with a true-FDP entrapment oracle, so the agreement holds through
decoy generation and measured false-discovery proportion, not merely through peak lists.

It also confirms Brendan's reason for publishing both zips. The comparison is only fair
because `-v2`'s mzML was converted by an msconvert carrying PR #4501; against a pre-#4501
conversion the direct raw read differs by an ULP on most retention times (#4496 recorded it;
PR #4500 was closed). The two acquisitions agreeing to the last bit IS the evidence that
#4501 closed that gap.

**Cost of the raw leg**: the mzML default was re-verified unchanged in the same session
(`-Dataset Stellar` PASS with the refactor in place, including mode 3, which is the leg that
exercises the extension-driven 0-byte stubs).

### Review finding F1 investigated - mechanism real, framing wrong

The claim: an mzML scan start time with no unitAccession yields RT 0 silently, and this PR
changed its own fixtures to hide it. Verified both halves rather than accepting or
dismissing it.

* **The mechanism is real.** pwiz-sharp TimeConversion.ToSeconds ends in a 0.0 default
  (Common/CVParam.cs), so unknown units give RT 0, which is indistinguishable from a
  measured 0.
* **But it is FAITHFUL pwiz behaviour, not a port defect.** The C++
  timeInSecondsHelper (pwiz/data/common/ParamTypes.cpp:53-74) ends in the same
  bare return 0. So Skyline net472, msconvert and pwiz-sharp all behave identically, and
  nothing about this was introduced by the port, by #4497, or by the wrapper swap.
* **The fixture was wrong in a SECOND way the finding did not mention.** It used
  MS:1000894 (retention time), not MS:1000016 (scan start time) - a term ProteoWizard
  does not read as a scan start time at all. So the old fixture was not
  msconvert-shaped mzML, and correcting it was not concealment.

What survives, and is worth carrying upstream rather than patching here: anywhere in pwiz,
an mzML whose scan start time carries no recognizable unit scores at RT 0 with no
diagnostic. Not this PR to fix; the reader here would be the wrong layer.

### Review finding F4 verified - real bug, but low practical reachability

`SpectrumList_PeakPicker`'s ParamGroup promotion:

```
foreach (var p in pg.CVParams)
    if (!spec.Params.HasCVParam(p.Cvid)) spec.Params.CVParams.Add(p);
...
spec.Params.ParamGroups.Remove(pg);
```

**Confirmed**: `ParamContainer.HasCVParam` (line 91) delegates to `CvParam`, which recurses
into `ParamGroups` (lines 38-43). While `pg` is still attached, the guard is TRUE for every
`p`, so nothing is copied - and the group is then removed, discarding those terms. The
`UserParams` on the following line ARE copied, which is what makes the omission look
deliberate rather than accidental. The preceding `RemoveCv(pg, MS_profile_spectrum)` also
mutates the document-level group in place, so every other spectrum referencing it loses that
term too.

**Reachability, which is why it is NOT being patched tonight**: the branch only executes when
peak picking is REQUESTED for a source whose spectra carry `referenceableParamGroup`
references. Osprey requests vendor centroiding for vendor formats ONLY (see
`IsVendorFormat`), and vendor readers synthesize spectra rather than parsing mzML param
groups - so Osprey cannot reach it today. It is reachable for a caller that requests
centroiding on an mzML that uses param groups, which is a Skyline-shaped scenario, not an
Osprey one.

It was entirely dead before this branch: `ParseIntegerSet` yielded an EMPTY level set, so
`GetSpectrum` returned at the level check before ever reaching the relabeling code. Fixing
the parser is what made this code run at all.

**Recommendation**: report to Matt rather than patch here. It is his code, the fix needs a
test with a param-group mzML fixture, and getting the copy-then-detach order wrong would be
a worse regression than the latent bug. Not a blocker for #4588.

### Review finding F9 - same disposition

`MsDataFileImpl.GetSpectrum` indexes `scans[0]` unguarded on the `simAsSpectra` path, six
lines above a `Count > 0` guard on the same list, and #4497 passes `simAsSpectra: true` for
every file. An MS1 spectrum with an empty scanList would throw `ArgumentOutOfRangeException`,
which the enclosing `catch (NullReferenceException)` does not catch. Real, one-line fix, but
it is in the shared wrapper and belongs to #4587 with a fixture that exercises it - none of
the four regression datasets produce an empty scanList, so a fix tonight would be untested.

### Measured: the Debug-linkage defect costs 30% of vendor read throughput

Review finding F14 argued the new reader is a throughput regression, without a number.
Measured it on TDP-43 A01 (2.10 GB cache, 161,099 MS2 / 965 MS1), single file, idle machine:

| Reader | Time | vs the old path |
|---|---|---|
| net472 `pwiz_data_cli` (native C++/CLI), 2026-07-29 | 59.7s | - |
| pwiz-sharp **Debug** - what this branch ships today | 78.1s | **+31%** |
| pwiz-sharp **Release** | **54.8s** | **-8%** |

Release output verified byte-identical to the Debug output
(`PARITY: 2,260,174,556 bytes identical`), so this is pure code-generation, not a
behavioural difference.

**Conclusion: the managed reader is FASTER than the native one, and the apparent regression
is entirely the Debug-linkage defect.** `Osprey.IO.csproj` already documents it - building a
.sln unsets Configuration across a `ProjectReference` to a project outside that .sln, so
ProteowizardWrapper and all of pwiz-sharp compile Debug even in a Release Osprey - and
defers the fix on the grounds that "the code is correct either way ... the cost is an
unoptimized ProteoWizard doing the spectrum reading, not a wrong answer". That reasoning
stands, but the cost now has a number: **30% of read time**, on the path that is now 100% of
how Osprey reads spectra.

That moves "put these projects in Osprey.sln" from housekeeping to a scheduled throughput
item. It does NOT block #4588: the results are identical either way, and the branch is
faster than master's native path the moment the linkage is fixed.

**Scope of this measurement**: Thermo .raw, i.e. managed pwiz-sharp reader vs native
pwiz_data_cli. It does NOT measure F14's other half - the deleted `MzmlReader` overlapped a
sequential XML parse with a `Parallel.ForEach` base64/zlib decode, and the mzML path is now
a single-threaded loop. That comparison needs a master build to baseline against.

**Caveat on the 59.7s figure**: taken from the first file of a 164-file sequential run on
2026-07-29 (`spectracache-164.log`), not a dedicated benchmark. Tonight's numbers are
single-file runs on an idle machine. An earlier tonight measurement of 146.5s was discarded
as contended - it ran concurrently with the SEA-AD cache.

### TeamCity gate GREEN

Build [4140348](https://teamcity.labkey.org/build/4140348), config Osprey Windows .NET
Perf/Regression Tests, branch pull/4588, commit d6fef70e60: **SUCCESS**. That is
tctest.bat, i.e. regression.ps1 -TeamCity -Dataset All plus the perf leg - every mode on all
four datasets, on the commit carrying BOTH the wrapper swap and the raw-source support.

Note it resolved the revision at build START, not at queue time: triggered while the branch
was at f583ba9fab, it checked out d6fef70e60 after the raw work was pushed. So the
re-trigger Brendan authorised was not needed, and the shared agent was spared a second hour.

### CORRECTION to the perf note above - single-run numbers did not survive repeats

The section above was written from ONE run per configuration and drew a conclusion the data
did not support ("the managed reader is faster than native; the apparent regression is
entirely the Debug linkage"). Re-measured with 3 interleaved repeats per configuration,
same file, idle machine. Medians, with observed ranges:

**mzML (SEA-AD Astral, 4.07 GB cache, 162,620 MS2 / 974 MS1)**

| Build | Median | Range |
|---|---|---|
| master `MzmlReader` (parallel decode) | **32.9s** | 28.1 - 33.2 |
| this branch, Debug pwiz-sharp (ships today) | 38.0s | 37.6 - 54.4 |
| this branch, Release pwiz-sharp | 43.9s | 42.3 - 44.7 |

**Thermo .raw (TDP-43 A01, 2.10 GB cache, 161,099 MS2 / 965 MS1)**

| Build | Median | Range |
|---|---|---|
| this branch, Debug pwiz-sharp (ships today) | 72.4s | 68.8 - 80.1 |
| this branch, Release pwiz-sharp | **55.0s** | 54.5 - 58.2 |
| net472 `pwiz_data_cli` (native), 2026-07-29 | 59.7s | single sample, from a 164-file run |

**What actually holds:**

1. **Review finding F14 is REAL but modest.** Replacing `MzmlReader`'s parallel base64/zlib
   decode with a single-threaded loop costs roughly **15-33%** on mzML (32.9s -> 38.0-43.9s),
   NOT the "40 seconds versus multi-minute" the finding predicted. Output is byte-identical:
   master's cache and this branch's compare `PARITY: 4,368,477,008 bytes identical`.
2. **The Debug-linkage defect is real on the VENDOR path** - 72.4s -> 55.0s, non-overlapping
   ranges, ~24%. Worth scheduling the "put these projects in Osprey.sln" fix on that basis.
3. **But it does NOT explain the mzML gap**, where Release measured consistently SLOWER than
   Debug. That is unexplained and I am not going to invent a reason for it; it is the open
   question if anyone wants to push further. Candidates worth checking: whether the Release
   pwiz-sharp assemblies I hand-copied over the snapshot differ in more than optimization
   (they were produced by `pwiz-sharp/build.bat Release`, a different build entry point than
   the one Osprey's ProjectReference drives), and tiered-JIT warmup on a ~40s process.
4. **The earlier claim that the managed reader beats the native one is NOT supported.**
   55.0s vs a single 59.7s sample taken from the first file of a 164-file sequential run is
   not a like-for-like benchmark, and one sample cannot carry that conclusion.

**Bearing on #4588**: none of this blocks it. Results are byte-identical on both paths, and
the regression gate is green including its perf leg. This is a known, now-quantified cost of
deleting a hand-written parallel reader in favour of the shared one, plus a separate
build-configuration defect that was already documented and is now measured.

### Perf, settled at n=6 (supersedes both notes above)

Six interleaved repeats per configuration, one file each, idle machine. The two earlier
sections in this TODO were written at n=1 and n=3 and both got the magnitude wrong; this is
the number to use.

**mzML - SEA-AD Astral, 4.07 GB cache, 162,620 MS2 / 974 MS1**

| Build | Median | Range | vs master |
|---|---|---|---|
| master `MzmlReader` (parallel decode) | 27.0s | 23.9 - 33.2 | - |
| branch, Debug pwiz-sharp (SHIPS TODAY) | 38.2s | 37.4 - 54.4 | **+41%** |
| branch, Release pwiz-sharp | 45.4s | 42.3 - 46.8 | +68% |

On the last three repeats alone (fully warmed OS cache, the most comparable set) it is
master 24.8s vs branch 38.3s, i.e. **+54%**. So the honest range is 40-55% slower on mzML.

**Thermo .raw - TDP-43 A01, 2.10 GB cache, 161,099 MS2 / 965 MS1** (3 repeats)

| Build | Median | Range |
|---|---|---|
| branch, Debug pwiz-sharp (SHIPS TODAY) | 72.4s | 68.8 - 80.1 |
| branch, Release pwiz-sharp | 55.0s | 54.5 - 58.2 |

**Findings that survive repetition:**

1. **mzML is 40-55% slower than master**, output byte-identical
   (`PARITY: 4,368,477,008 bytes identical` between master's cache and this branch's). This
   is review finding F14, confirmed and quantified - though far short of the "40 seconds
   versus multi-minute" the finding predicted.
2. **The Debug-linkage defect costs ~24% on the VENDOR path** (72.4s -> 55.0s, non-overlapping
   ranges). Real, and an argument for scheduling the Osprey.sln fix.
3. **Release pwiz-sharp is reproducibly SLOWER on mzML** (45.4s vs 38.2s, six repeats, tight
   ranges) - the opposite of the vendor path, and unexplained. The assemblies were verified
   genuinely different (241,152 vs 259,584 bytes for Pwiz.Data.MsData.dll), so it is not a
   failed copy. Worth someone's attention before the Osprey.sln fix is done, because that fix
   would move the mzML path onto the SLOWER configuration measured here.
4. The recovery path, if throughput matters later, is to reintroduce parallel decode against
   the shared reader rather than to bring back a second parser - the per-spectrum decode is
   independent. Blocker: `MsDataFileImpl` holds per-instance spectrum caching
   (`_lastSpectrum` / `_lastSpectrumInfo`) and is not thread-safe as used, so it would need
   one instance per worker or a different seam.

**Corrections to my own earlier claims in this TODO**: the n=1 note claimed the managed
reader beat the native one and that the whole regression was the Debug linkage. Neither
survived repetition. The n=3 note put the mzML regression at 15-33%; it is 40-55%.

### Isolation: the WRAPPER is not the cost. pwiz-sharp's mzML read is.

Brendan asked to separate two suspects - the extra per-spectrum work `MsDataFileImpl` does
that Osprey discards, versus the loss of `MzmlReader`'s parallel decode. Built a worktree at
`ffce6d97b9` (this branch's last commit BEFORE the wrapper swap, i.e. the minimal direct
pwiz-sharp reader) and timed all three readers on one file. 3 repeats; `r1` for master was a
cold-cache artifact (73.6s vs 42.4 / 42.7) and is excluded.

**mzML - Astral regression file, 5.99 GB, 204,149 MS2 + 1,223 MS1**

| Reader | Median | vs master |
|---|---|---|
| master `MzmlReader` (parallel decode) | **42.5s** | - |
| direct pwiz-sharp, minimal reader (`ffce6d97b9`) | **80.4s** | +89% |
| through `ProteowizardWrapper` (ships today) | **82.4s** | +94% |

**The wrapper costs 2.0s of 82.4s - about 2.5%.** All of `SpectrumMetadata`, the scan
description, instrument-config lookup and the `ImmutableList` precursor grouping together
amount to that. Reverting to the direct reader would recover ~2.5%, not the regression. The
regression is pwiz-sharp's mzML read itself against a purpose-built parallel decoder.

That kills the "go back to reading pwiz-sharp directly" option as a performance argument -
which matters, because that was the design this branch deliberately moved AWAY from, and it
would be the obvious thing to propose on seeing the regression.

### Raw vs mzML on the SAME acquisition

| Source | Size | Median | Per GB |
|---|---|---|---|
| mzML | 5.99 GB | 82.4s | 13.7 s/GB |
| .raw | 8.19 GB | 165.3s | 20.2 s/GB |

**Reading the .raw is ~2.0x slower end to end, ~1.5x per byte.** Converting to mzML first
still buys real throughput, which is worth stating plainly now that reading .raw directly is
possible - "it works" is not "it is the fast path". (Both produce identical search results;
that is the `-Source raw` regression result recorded above.)

Direct vs wrapper on the .raw path: 165.3s vs 169.5s medians, ranges 164.9-192.3 and
163.8-170.7 - overlapping, so no measurable wrapper cost there either.

### The magnitude is file-dependent, and NOT explained yet

| File | master | wrapper | regression | per-spectrum delta | per-GB delta |
|---|---|---|---|---|---|
| SEA-AD Astral, 4.13 GB, 163,594 spectra | 27.0s | 38.2s | +41% | 69 us | 2.7 s/GB |
| Regression Astral, 5.99 GB, 205,372 spectra | 42.5s | 82.4s | +94% | 194 us | 6.7 s/GB |

The added cost differs ~3x between the two files under BOTH normalizations, so it is neither
per-spectrum nor per-byte. A per-spectrum-overhead theory was tested and does not hold. The
untested candidate is binary-array encoding - 32- vs 64-bit arrays, zlib vs none - which
changes decode work independently of spectrum count and file size; the SEA-AD conversion and
the regression conversion were produced by different msconvert invocations. Checking the
`cvParam` encoding terms in the two mzML headers would settle it in minutes and is the
obvious next step.

**Honest summary for the PR**: 40-95% slower on mzML depending on the file, byte-identical
output, wrapper overhead ~2.5% of that.

### Mechanism RESOLVED: the cost tracks DECODE VOLUME

The magnitude difference between the two files above is explained. Read the encoding
cvParams straight out of both mzML headers:

| File | m/z array | intensity array | regression |
|---|---|---|---|
| SEA-AD Astral | 64-bit float, zlib | **32-bit float**, zlib | +41% |
| Regression Astral | 64-bit float, zlib | **64-bit float**, zlib | +94% |

(SEA-AD: 68 x 32-bit + 68 x 64-bit across 136 zlib arrays = 68 spectra carrying one array of
each. The regression file is 64-bit throughout - 114 x 64-bit, 113 zlib, no 32-bit at all.)

So the regression scales with the volume of binary data DECODED per spectrum - zlib inflate
plus the float conversion - which is exactly the work the deleted MzmlReader handed to
Parallel.ForEach and which pwiz-sharp performs on the read thread. That is why neither
per-spectrum nor per-byte normalization fit: the right unit is decoded bytes, and these two
files differ in intensity-array width by 2x.

Predictions this makes, stated so they can be falsified:

* Ordinary msconvert output (64-bit m/z, 32-bit intensity) pays around 40%.
* An all-64-bit conversion pays around 90%.
* An UNCOMPRESSED mzML should narrow the gap further, since inflate leaves the serial path.
* A vendor .raw sits at ~2x the mzML cost regardless, because the vendor SDK does its own
  decoding and none of that was ever parallel in Osprey.

It also sharpens the recovery option. The expensive work is per-spectrum, independent and
CPU-bound - the ideal shape for parallelism - so reintroducing it against the SHARED reader
would recover most of the gap without resurrecting a second parser. The blocker remains that
MsDataFileImpl keeps per-instance spectrum caching (_lastSpectrum / _lastSpectrumInfo) and is
not thread-safe as used, so it needs one instance per worker or a different seam.

### Parallel decode inside pwiz-sharp: PROTOTYPED, WORKS, byte-identical

Implemented in `C:\proj\pwiz` (NOT committed - feasibility prototype on Matt's code):

* `MzmlReader` gains an optional `PendingDecodes` collector. When active,
  `ReadBinaryDataArray` records (array, base64, encoderConfig) instead of decoding inline.
  Sound because decode was ALREADY separable and pure: `BinaryDataEncoder` holds only a
  readonly config, its decode helpers are `static`, and a fresh encoder is built per array.
  Nothing in the decode path touches the reader's reference maps or `_skipBinaryData`.
* `SpectrumList_Mzml` parses a batch of 64 spectra with decoding deferred, runs those decodes
  through `Parallel.ForEach`, and serves the batch from a small index-keyed cache. Falls back
  to the original single-spectrum path for non-sequential access or metadata-only reads.
* Opt-in: `PWIZ_SHARP_MZML_DECODE_THREADS=<n>`, default off (1).

**XML parsing stays single-threaded on the existing stream.** That is the key design choice:
it means no reentrancy work on `MzmlReader` (the non-reentrant `_skipBinaryData` field is
untouched), no second file handle, and it works for mzMLb as well, whose `_openStream` cannot
be called twice. Only the pure decode goes wide.

| mzML read, Astral 5.99 GB, 205,372 spectra | Time |
|---|---|
| serial (today) | 82.6s |
| parallel decode, 8 threads | **53.8s** |
| parallel decode, 16 threads | 52.4s |
| master's deleted `MzmlReader` (target) | 42.5s |

Output **byte-identical**: `PARITY: 6,333,591,188 bytes identical` between the serial and
8-thread caches.

Recovers ~35% and closes about three-quarters of the gap to master. It plateaus at ~52s
because master OVERLAPPED parse with decode (producer/consumer), while this batches
parse-then-decode - so the serial XML parse is now the floor. Closing the rest means a true
pipeline with a bounded queue, which is the shape the old Osprey reader had. Worth doing only
if someone wants the last ~10s.

Note for Osprey specifically: it already parallelises across FILES, so turning intra-file
decode threads on by default would oversubscribe. Leaving the choice to the host is
deliberate, not laziness.

### Pipeline reality check: converting to mzML first is NOT the fast path

Brendan pushed back on the claim that reading .raw being 2x slower argues for converting
first, pointing out that `.spectra.bin` is already a duplicate of the spectra, so
raw -> mzML -> spectra.bin buys a second copy to produce one cache. Measured it:

msconvert on the 8.19 GB Astral .raw (`--mzML --zlib --filter "peakPicking vendor
msLevel=1-"`) took **341s** and wrote 5.46 GB.

| Path from .raw to .spectra.bin | Total | Extra disk |
|---|---|---|
| **direct raw read** | **165.3s** | none |
| via mzML, serial decode | 423.9s | 5.46 GB |
| via mzML, parallel decode | 393.4s | 5.46 GB |

**Direct raw is ~2.4x faster end to end.** My earlier "converting first still buys
throughput" was wrong: the conversion costs roughly four times what the faster read saves.
The raw-vs-mzML READ ratio only matters to someone who already holds mzML - it is not an
argument for producing one.

### Correction: the raw-vs-mzML ratio is Astral-specific

Recorded above as "reading .raw is ~2x slower than mzML, ~1.5x per byte". That is stated too
generally. From Matt, via Brendan: **the Thermo Astral decoder is known to be slow**, and
Thermo has been asked to improve it. Matt's first question on hearing that mzML read faster
was "is this Astral data?" - it was.

So the 165.3s vs 82.4s figure describes Astral, not vendor reading in general. It matters
because Astral is a primary Osprey format for the MacCoss lab, so the slow case is also the
common case here - but a different Thermo instrument would not necessarily show that ratio,
and nothing about pwiz-sharp's vendor path is implicated.

Two consequences worth keeping straight:

* **It is still not an argument for converting first.** msconvert takes 341s on that .raw, so
  the pipeline is 165s direct against 424s via mzML, plus 5.46 GB of intermediate that
  `.spectra.bin` already duplicates. And msconvert reads the .raw through the same slow
  decoder, so a Thermo fix speeds BOTH paths and direct stays ahead.
* **It narrows who benefits from the parallel-decode work (#4590).** Brendan's expectation is
  that with direct vendor reading available, fewer Osprey users will want the mzML route at
  all, since for them mzML is just an intermediate on the way to `.spectra.bin`. The
  parallel decode therefore pays off mainly for Skyline and for existing mzML workflows,
  rather than for Osprey's future. It is still worth having - it is the shared library, and we
  were the ones who wrote the parallel decompression in the first place - but it should not be
  justified by Osprey throughput going forward.

### Stellar timings - and a correction to the correction above

Same acquisition as both zips, one file, 3 repeats, identical counts every run
(97,500 MS2 + 780 MS1, 1.04 GB cache). Stellar raw is 0.80 GB against 1.38 GB of mzML - the
normal direction, unlike Astral, whose raw is UNCOMPRESSED (Thermo has been asked for zlib
and has not delivered), which is why its raw is larger than its own mzML.

| Stellar | 1 thread | 8 threads |
|---|---|---|
| mzML | 13.9s | **9.2s** (-34%) |
| raw | ~26s (cold 30.6, then 20.8) | 20.7s |

**1. Parallel decode pays at this size too** - 34%, matching Astral's 35%. Not a
large-file-only win, and Stellar is what `regression.ps1 -Dataset Stellar` runs.

**2. Decode threads do not affect the raw path**, exactly as designed - raw lands ~20s either
way. A useful check that the knob really is mzML-only rather than accidentally global.

**3. The "Astral-specific" note above was an over-correction.** Raw is slower than mzML on
Stellar too. Per SPECTRUM, which is the fair unit across formats that compress differently:

| | raw | mzML @1 thread | ratio |
|---|---|---|---|
| Astral (205,372 spectra) | 805 us | 401 us | 2.0x |
| Stellar (98,280 spectra) | 211 us | 141 us | 1.5x |

Both things are true and I had conflated them:

* Vendor raw reading costs **1.5-2x more than reading the equivalent mzML**, on both
  instruments tested. That is general, not an Astral artifact.
* **Astral's decoder is ~3.8x slower per spectrum than Stellar's** (805 us vs 211 us). That
  is the Astral-specific problem Matt raised and Thermo has not fixed.

Per-byte figures mislead here - Stellar's raw looks worse per GB (26 vs 20 s/GB) purely
because it is compressed and Astral's is not.

**None of this changes the pipeline conclusion.** Converting first still loses: msconvert
pays the same vendor read AND writes the mzML, so direct raw remains the shorter path. What
it does change is the framing - "vendor reading is slower than mzML" is a real, general
property worth knowing when choosing an input format, not something peculiar to one
instrument.
