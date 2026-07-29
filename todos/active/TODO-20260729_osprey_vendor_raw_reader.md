# Osprey: read vendor raw directly via pwiz_data_cli in the net472 configuration - drop the msconvert step

## Branch Information
- **Branch**: `Skyline/work/20260729_osprey_vendor_raw_reader` (pwiz-work1, off clean master)
- **Base**: `master` (520d559fd6)
- **Module**: `osprey`
- **Created**: 2026-07-29
- **Status**: In Progress
- **GitHub Issue**: [#4496](https://github.com/ProteoWizard/pwiz/issues/4496)
- **PR**: (pending)
- **Requester**: Brendan (issue author, Osprey developer) — NO credit line.

## Objective

Read vendor raw files directly in Osprey's **net472** configuration by integrating
`pwiz_data_cli.dll` — the same build Skyline uses on master — so the test and development workflow
drops its msconvert step entirely.

**Near-term goal**: run `--task PerFileScoring` with `.raw` files as input, producing the
`.spectra.bin` caches and the Pass-1 `.scores.parquet` directly. Nothing downstream changes.

**Why now**: every large dataset currently costs download → msconvert (hours, +0.73x raw size on
disk) → Osprey. Measured on the 82-file SEA-AD Astral set: 484 GB raw → 324.5 GB mzML → 345.9 GB
caches; the 164-file TDP-43 set staged locally is 784 GB of raw awaiting the same treatment. We are
iterating heavily on the FDR tasks, so time-to-first-parquet on a new dataset is what gates cyclic
development on the later stages.

## Design (from the issue — the surface is small)

Osprey's whole requirement is what `SpectraCache` (v4 format, `Osprey.IO/SpectraCache.cs`)
serializes: **~7 scalars and 2 arrays**. Per MS2 record — scan number, retention time, precursor
m/z, isolation centre + lower/upper offsets, m/z (f64[]) + intensity (f32[]). Per MS1 record — scan
number, retention time, and the same two arrays.

`pwiz_tools/Shared/ProteowizardWrapper` (itself `v4.7.2`, references `pwiz_data_cli` at
`ProteowizardWrapper.csproj:91`) already exposes every one of them, so **no direct `pwiz_data_cli`
binding is needed** — wrap `MsDataFileImpl` instead:

| Osprey needs | ProteowizardWrapper |
|---|---|
| scan number | `MsDataSpectrum.Index` / `.Id` |
| retention time | `MsDataSpectrum.RetentionTime` |
| MS level | `MsDataSpectrum.Level`, `MsDataFileImpl.GetMsLevel(scanIndex)` |
| precursor m/z | `MsPrecursor.IsolationWindowTargetMz` (`MsDataFileImpl.GetPrecursors`) |
| isolation lower / upper OFFSET | `MsPrecursor.IsolationWindowLower` / `.IsolationWindowUpper` |
| m/z + intensity arrays | `MsDataSpectrum.SetArrays(mzs, intensities)` |

**Isolation window semantics match exactly** — `MsDataFileImpl:2187` reads
`MS_isolation_window_lower_offset` / `upper_offset`, the same OFFSET semantics as Osprey's
`IsolationWindow(center, lowerOffset, upperOffset)`; not a width, not an absolute bound. That is the
detail most likely to be silently wrong in a hand-rolled binding, and it is the reason to go through
the wrapper.

Osprey touches none of the rest of Skyline's surface — no ion mobility, chromatograms, SONAR, lock
mass, DIA-Umpire, or `SpectrumMetadata`. **This is an adapter, not an integration.**

Build wiring is a copy, not a design problem — `Skyline/Jamfile.jam:442/452/476/483` already solve
vendor API deployment (Thermo, Agilent, Bruker, Waters, Sciex), and `pwiz_tools/Osprey/Jamfile.jam`
(115 lines) already mirrors Skyline rules by copy and says so at `:39`/`:43`.

## Explicitly NOT in scope

**The hand-coded `MzmlReader` stays.** Osprey targets `net472;net8.0`
(`Directory.Build.props:4`) and `pwiz_data_cli` is net472-only, so the net8.0 configuration on
master must keep reading mzML. Removing the reader belongs to the .NET 8 port (companion #4497).

Lifting the duplicated Jamfile rules into a shared Jamfile is optional cleanup and must NOT gate
this.

## Tasks

- [ ] Add a vendor-raw reader to `Osprey.IO` behind the same contract `MzmlReader` provides —
      `LoadAllSpectra(path) -> MzmlResult { Ms2Spectra, Ms1Spectra, UnsortedSpectrumCount }`
- [ ] Select the reader by file extension in `PerFileScoringTask` (call site is the current
      `MzmlReader` invocation) so nothing downstream is aware of the source format
- [ ] Wire `pwiz_data_cli.dll` into the **net472** configuration only, via
      `pwiz_tools/Shared/ProteowizardWrapper` (already `v4.7.2`), not a direct CLI assembly binding
- [ ] Add the assembly reference + vendor-dependency conditional to `pwiz_tools/Osprey/Jamfile.jam`,
      following the `Skyline/Jamfile.jam` precedent
- [ ] Keep `MzmlReader` and the net8.0 target-framework path intact

## Acceptance (from the issue)

- [ ] `--task PerFileScoring -i <file>.raw` produces `.spectra.bin` + `.scores.parquet` equivalent
      to the same file converted to mzML first
- [ ] Byte-parity: a raw-sourced run and an mzML-sourced run of the same file agree at the Stage-4
      parquet, or the differences are characterized and understood (vendor centroiding vs the
      msconvert `peakPicking vendor msLevel=1-` filter is the obvious candidate — see
      `ai/scripts/Osprey/SEA-AD/convert-one.cmd` for the settings in use)
- [ ] `regression.ps1 -Dataset All` unaffected (it is mzML-driven and must stay green)
- [ ] net8.0 configuration still builds and runs on master via `MzmlReader`

**A divergence here is an Osprey bug, not a tolerance question.** ProteoWizard reliably produces the
same results from raw as from the mzML it writes — Skyline depends on this directly. So if a
raw-sourced run disagrees with an mzML-sourced one, the fault is almost certainly in Osprey's own
hand-coded `MzmlReader`, the only parser in this picture that is not pwiz. Any difference is a
concrete defect to fix in our reader, not a judgement call about which side to trust.
**Do NOT reach for `-CreateGolden`** — a rebaseline is how a real regression gets blessed into the
baseline.

## Regression Test

Two tiers, both required. Brendan set the primary one (2026-07-29): prove parity on a **real file
from the actual target dataset**, at the `.spectra.bin` level, end to end.

### Tier 1 (primary) — end-to-end `.spectra.bin` parity on real TDP-43 data

Target: `D:\test\osprey-runs\tdp43-plasma-ev\raw\2025-0724-TDP43-PlasmaEV-PLT1-A01-365-001.raw`
(3.07 GB; one of the 164 files / 784.2 GB staged locally). The end goal is running Osprey on that
whole directory with no mzML conversion, so the test data is the goal's data.

1. **Stage-1-only path** — run just the input -> `.spectra.bin` conversion. **This does not exist
   yet**: the CLI has exactly four tasks (`PerFileScoring`, `FirstPassFDR`, `PerFileRescoring`,
   `SecondPassFDR`, `Program.cs:293-315`), and the smallest, `PerFileScoring`, also runs
   calibration + scoring + parquet and *requires* `--library` (`Program.cs:365`). Proposed:
   **`--task SpectraCache`**, which calls the existing `EnsureSpectraCache`
   (`PerFileScoringTask.cs:2413`) and exits — no `--library` needed, since cache building does not
   use one. Worth doing as a real task rather than test scaffolding: it is precisely the staging
   primitive that replaces the msconvert step (point it at 164 raws, get 164 caches), and it makes
   the parity check a pure CLI exercise — one binary, two inputs, two outputs.
2. **Convert to mzML** with the standard proven command line: `convert-one.cmd <raw> <outdir>
   <msconvert.exe>` (`ai/scripts/Osprey/SEA-AD/convert-one.cmd`). Invoke it directly rather than
   `Convert-SeaAdRaw.ps1`, which is hard-wired to the SEA-AD `Astral-DIA\` layout.
3. Run the Stage-1-only path on the **mzML** -> `.spectra.bin`.
4. Run the Stage-1-only path on the **`.raw`** -> `.spectra.bin`.
5. **Compare** with `ai/scripts/Osprey/Compare/Compare-SpectraCache.ps1` (written and validated
   2026-07-29, see below).

**GOTCHA — the two caches collide by default.** `SpectraCache.GetCachePath` is
`Path.GetFileNameWithoutExtension(inputFile) + ".spectra.bin"` (`SpectraCache.cs:261`), so
`FOO.raw` and `FOO.mzML` both resolve to `FOO.spectra.bin`. Runs 3 and 4 MUST write to different
directories (separate mzML/raw dirs, or the `ArtifactPaths` cache-dir redirect). Worse than
overwriting: whichever runs second would find the first's cache, reject it on the fingerprint, and
silently re-parse — looking like success while proving nothing.

#### Comparison method: masked byte compare — no Osprey change, no semantic comparator

The concern about needing "consistent identifying cache information" resolves better than expected.
The v4 header (`SpectraCache.cs:153-158`) is:

| offset | size | field |
|---|---|---|
| 0 | 8 | magic `OSPRSPC\0` |
| 8 | 4 | version (u32) |
| 12 | 8 | **source_size (u64)** |
| 20 | 8 | **source_mtime_ms (i64)** |
| 28 | 4 | n_ms2 (u32) |
| 32 | 4 | n_ms1 (u32) |

`ComputeSourceFingerprint` (`SpectraCache.cs:440-441`) is just `fi.Length` +
`LastWriteTimeUtc`, so **bytes 12..27 are the only bytes derived from the source file's identity
rather than its contents.** Mask those 16 bytes and byte-compare the rest. That needs no production
change and is *stronger* than a field-by-field comparator: it covers every byte the cache stores,
including the MS2 record body, the MS1 section, the 40-byte-per-record index block and the footer.

`n_ms2` / `n_ms1` are deliberately **not** masked — a spectrum-count difference is the most likely
real defect (any converter filter that drops or reorders spectra shifts every later record), and it
should fail loudly and early.

`Compare-SpectraCache.ps1` does exactly this. Validated against real v4 caches on 2026-07-29:
- negative case (two different SEA-AD caches) -> `DIFFERENT SPECTRUM COUNTS`, n_ms2 162,620 vs
  165,699, exit 1, before touching the body
- positive case (3.8 GB cache vs itself) -> `PARITY: 3,834,851,952 bytes identical`, **15.9 s**,
  exit 0

15.9 s for ~4 GB makes this cheap enough to run per file, not just once.

### Tier 2 (permanent guard) — committed unit test, net472 leg of Osprey.Test

Tier 1 needs 3 GB of off-repo data and an msconvert run, so it cannot gate CI. A small committed
test keeps the field mapping honest afterwards:
`pwiz/data/vendor_readers/Thermo/Reader_Thermo_Test.data/source_cid_test_3scans.raw` with its
tracked `source_cid_test_3scans-centroid.mzML` (already in the repo, nothing new to commit; all 3
spectra carry `MS:1000827/828/829`). Caveat: that fixture's arrays are 32-bit for **both** m/z and
intensity, so it pins the mapping and the isolation-window semantics but cannot catch an f64 m/z
precision defect — which is exactly what Tier 1 covers.

- **Test name**: (filled in once written)
- **Test project**: Osprey.Test, net472 leg only
- **Fails on master**: (pending)
- **Passes on fix**: (pending)

## Companion work: msconvert round-trip cvParam values (separate PR, module `pwiz`)

The raw-vs-mzML parity census came out clean on every field except retention time:

| field | differing records (of 161,099) |
|---|---|
| scanNumber, precursorMz, isoCenter, isoLower, isoUpper, peakCount, m/z, intensity | **0** |
| **retentionTime** | **9,269** (5.8%), worst \|dRT\| 3.55e-15 min (1 ULP) |

**CORRECTION (later the same day).** The first diagnosis below - that msconvert's 12-digit
truncation caused the RT gap, and that the raw path was therefore the more accurate one - was
**wrong**, and the opposite of the truth. Both paths read the SAME truncated text, so the
truncation cancelled out. The actual cause is in the wrapper:

`MsDataFileImpl.GetStartTime` (`pwiz_tools/Shared/ProteowizardWrapper/MsDataFileImpl.cs:2097`) did
`return param.timeInSeconds() / 60;` on a value the Thermo reader had already recorded in
**minutes** - converting minutes -> seconds -> minutes. That is not an identity in floating point:

    0.5903117      * 60 / 60 = 0.5903116999999999   (differs)
    1.811994433333 * 60 / 60 = 1.8119944333330003   (differs)

`0.5903116999999999` is **exactly** the raw-path value the census reported against a reference of
`0.5903117`. So the raw path was the LESS accurate one, and it affected every vendor reader that
records scan start time in `UO_minute`. Fixed by returning the recorded value directly when the
unit is already minutes.

This became visible only after fixing `toString`: with the mzML text made exact, the wrapper's
round-trip no longer cancelled, and the first differing record moved from #23 to #0.

**Both defects are real and independent:**

1. `MsDataFileImpl.GetStartTime` unit round-trip (the cause of the observed 9,269 differences).
2. `toString` 12-digit truncation (a genuine precision loss in what pwiz stores, inherited by both
   paths; it was masked because both paths read the same truncated text).

**Second defect, still worth fixing on its own merits.** `pwiz::util::toString(double)`
(`pwiz/utility/misc/String.cpp`) uses a boost::spirit::karma `double12_policy` with
`precision(T) { return 12; }` - **12 fractional digits**. `ParamContainer::set(CVID, double, CVID)`
(`pwiz/data/common/ParamTypes.cpp:279`) routes every double cvParam through it, so
`SpectrumList_Thermo.cpp:260`'s `scan.set(MS_scan_start_time, raw->rt(ie.scan), UO_minute)` stores
an already-truncated string. Confirmed directly in the mzML text: `value="0.001232516667"`,
`value="0.5903117"`.

So the mzML cannot reproduce the RT of the raw file it was converted from, and the raw-sourced
value is the *more* accurate one. The 12-digit policy exists to avoid `lexical_cast` noise like
`123.00000000007` - an aim that shortest-round-trip formatting satisfies while also being exact.

**Fix (branch `Skyline/work/20260729_pwiz_roundtrip_cvparam`, off master):** in the `AutoNotation`
path, keep the karma 12-digit text whenever it already reloads bit-exact, and fall back to the
shortest round-tripping form (`%.15g` -> `%.16g` -> `%.17g`, first that reloads equal) only when it
does not. Existing output and file sizes are therefore unchanged except where today's output is
silently lossy.

Deliberately **not** `std::to_chars`: floating-point `to_chars` is C++17 but library support is not
universal across the toolsets pwiz builds with (`Jamroot.jam:393-396` sets `-std=c++17` for msvc,
gcc, darwin and clang; libstdc++ needs GCC 11, libc++ a recent LLVM). `snprintf`/`strtod` are
available everywhere and the slow path is rare.

New `pwiz/utility/misc/StringTest.cpp` (registered in that Jamfile) asserts the property directly:
every value `toString` writes must `strtod` back equal, over the motivating Thermo RTs, range
extremes, and 20,000 generated values across 40 decades - plus a test that ordinary values keep
their exact existing text.

**Open questions for Matt Chambers' review** (both are his call, not ours):

1. **Scope** - whether the round-trip guarantee should apply to all double cvParams (as
   implemented) or only to selected CVIDs such as scan start time. All-cvParams is the principled
   answer; per-CVID is arbitrary but churn-free.
2. **Baseline regeneration.** The committed vendor-reader baselines contain values sitting exactly
   at the truncation boundary - e.g. `scan start time" value="0.259556549483"` in
   `Reader_Thermo_Test.data/source_cid_test_3scans.mzML` - and **1,097 values with exactly 12
   fractional digits** across the Thermo baselines alone. Wherever those were truncated, the fixed
   msconvert emits more digits, so those baselines need regenerating. That is a deliberate
   consequence (the old baselines encode the lossy values), but it is real work across every vendor
   reader and should be agreed before the PR, not discovered in CI.

Note the fix is intentionally conservative on formatting: output is byte-identical to today
wherever today's output already round-trips, so only genuinely-truncated values move.

## Result: raw vs mzML parity after both precision fixes

Verified end to end on `2025-0724-TDP43-PlasmaEV-PLT1-A01-365-001.raw` (3.07 GB), comparing a
raw-sourced `.spectra.bin` against one built from the mzML msconvert produced from that same raw
file, both with the fixed pwiz:

| MS2 field (of 161,099 records) | before fixes | after fixes |
|---|---|---|
| retentionTime | 9,269 | **2** |
| scanNumber, precursorMz, isoCenter, isoLower, isoUpper, peakCount, m/z, intensity | 0 | **0** |
| MS1 count | 965 = 965 | 965 = 965 |

Worst residual `|dRT|` = **1.11e-16 minutes** (relative 1.28e-16, a half ULP), down from 3.55e-15.

**Two records remain unexplained** (0.001%): record 129320 / spectrum index 5679 and record 155352
/ index 6378. For both, the RAW value is the clean one (`0.86653405`) and the mzML-sourced value is
perturbed (`0.8665340500000001`), which is the opposite direction from the original defect. The
mzML text for index 5679 is `value="0.86653405"` with `unitName="minute"`, which should parse
exactly, and `0.86653405 * 60 / 60` round-trips cleanly, so neither the truncation nor the unit
round-trip explains it. Left open rather than guessed at; it does not affect the conclusion, but it
is a loose end for whoever picks this up.

**Cost of the msconvert fix**: 2,593,206,083 vs 2,590,796,882 bytes on this file - **+2.4 MB on
2.41 GB (+0.09%)**. The two candidate implementations (snprintf and the shipped locale-safe
ostringstream) produced byte-identical output sizes, confirming the rewrite did not change the
digits.

Verification was done on a throwaway `tmp-verify-combined` branch (osprey branch + cherry-picked
pwiz commit), because the demonstration needs both changes at once while the two PR branches stay
independent.

## Reader-vs-reader isolation: OSPREY_MZML_VIA_PWIZ

`OSPREY_MZML_VIA_PWIZ=1` (commit `7aad6bba1c`) routes mzML through ProteoWizard instead of
`MzmlReader`, so the two readers can be compared against ONE fixed input file. Raw-vs-mzML varies
reader and file together; this varies only the reader, so any difference is unambiguously a
`MzmlReader` defect.

Vendor centroiding is NOT requested on the mzML path: `MsDataFileImpl` centroids through a
`VendorOnlyPeakDetector` that **throws when no vendor API is behind the data**
(`MsDataFileImpl.cs:783-786`), and the mzML is already centroided by the conversion. That also makes
it a pure reader comparison rather than a centroiding comparison.

**Result on the same 2.41 GB mzML, both readers, all precision fixes applied:**

| MS2 field (of 161,099) | differing records |
|---|---|
| retentionTime | **2** |
| scanNumber, precursorMz, isoCenter, isoLower, isoUpper, peakCount, m/z, intensity | **0** |

Identical file lengths (2,260,174,556). MS1 counts equal. So **161,097 of 161,099 records are
byte-identical between the hand-written reader and ProteoWizard**, and the residual is entirely
`MzmlReader`'s - the same 2 records, same values, as the raw-vs-mzML comparison, which confirms the
raw path was never implicated in them.

### The 2 records: what is known, and what is NOT

Records 129320 (spectrum index 5679) and 155352 (index 6378). `MzmlReader` yields
`0.8665340500000001` / `0.9726369500000001`; ProteoWizard yields `0.86653405` / `0.97263695`.

Established facts:

* The arithmetic matches a seconds->minutes division **exactly**:
  `51.992043 / 60 == 0.8665340500000001` and `58.358217 / 60 == 0.9726369500000001`. Both hit their
  observed value bit-for-bit, which is not coincidence.
* BUT neither `51.992043` nor `58.358217` appears anywhere in the mzML.
* Spectrum 5679's `<scanList>` contains exactly ONE retention time:
  `MS:1000016 value="0.86653405" unitName="minute"`. No `MS:1000894`, no seconds-valued param.
* `XmlConvert.ToDouble("0.86653405") == 0.86653405` exactly, so the documented parse of the actual
  text cannot produce the observed value.

`MzmlReader` has two RT branches - `MS:1000016` (divided by 60 when `unitName` contains "second")
and `MS:1000894` (always divided by 60) - and a seconds division is clearly implicated by the
arithmetic. Worth noting `MS:1000927 ion injection time` carries `unitName="millisecond"`, which
**contains the substring "second"**; whether that can reach the scan-start-time branch was not
established.

**Not diagnosed. Do not treat the seconds-division story as confirmed** - the two facts above
(no seconds text in the file, clean parse of the real text) contradict the simple version of it. The
next step is a single-spectrum reproduction to distinguish a parse bug from state leaking across
spectra in the producer/consumer decode, not more hypothesising.

## SOLVED: the 2 records are a .NET Framework double-parsing defect

`MzmlReader` on **net472** parses `value="0.86653405"` to a double 1 ULP away from the correctly
rounded value. Confirmed by bit pattern, which is the only representation that does not lie here:

| decimal text | .NET Framework 4.8 | .NET 10 (and C++ `strtod`) |
|---|---|---|
| `0.86653405` | `0x3FEBBAA59DB3DA8E` | `0x3FEBBAA59DB3DA8D` |
| `0.97263695` | `0x3FEF1FD7866432B0` | `0x3FEF1FD7866432AF` |
| `0.5903117`  | `0x3FE2E3D55CBE46F8` | `0x3FE2E3D55CBE46F8` (same) |

.NET Framework's string->double conversion is **not correctly rounded** for certain decimals;
`XmlConvert.ToDouble` inherits it. .NET Core 3.0 fixed both parsing and `"R"` formatting. Only some
values are affected, which is why 2 of 161,099 diverged rather than thousands.

**The `TryParseXmlDouble` doc comment is wrong**: it says "XmlConvert.ToDouble is required by XML
schema spec to be IEEE-correct". That holds on .NET Core, not on .NET Framework. The comment is the
reason this looked impossible for so long.

Consequences beyond this issue:

* **The net472 and net8.0 Osprey builds produce DIFFERENT `.spectra.bin` from the same mzML.** Any
  golden-file baseline is implicitly TFM-specific, which matters for the .NET 8 port.
* An mzML-vs-raw or mzML-vs-pwiz divergence is not necessarily a reader-logic bug; on net472 it can
  be the runtime's parser. The issue's "a divergence is an Osprey bug" doctrine needs this caveat.
* Bit-exact parity between net472 Osprey and pwiz is **unreachable** for such values without a
  correctly-rounded parse.

### Two diagnostic traps that cost real time here (worth remembering)

1. **`double.ToString("R")` is also inexact on .NET Framework.** A probe printing `"R"` showed the
   parsed value and the literal as identical text when they were different doubles. Compare bit
   patterns (`BitConverter.DoubleToInt64Bits`), not formatted strings.
2. **A self-referential assertion passes for the wrong reason.** The first version of
   `TestMzmlReaderRetentionTimePrecision` compared the reader's value against
   `XmlConvert.ToDouble(text)` - the same buggy conversion - so it passed while the defect was live.
   Assert against a compiled literal or a known-good reference, never against the code under test.

**Fix options (Brendan's call, none applied yet):**

* **P/Invoke `strtod`** on net472 - literally the function pwiz uses, so cross-impl parity by
  construction. Adds native interop (CRITICAL-RULES wants PInvoke isolated in one place).
* **Correctly-rounded managed parse** for net472 (BigInteger/decimal based). No interop, more code.
* **Accept and document** - net472 stays 1 ULP off on rare values; requires the parity tests below
  to tolerate it, which weakens them.

## TeamCity: the Osprey PR will break the build as written

Checked build 4084490 (`ProteoWizard_OspreyWindowsNetPerfRegressionTests`, SUCCESS):

* **net472 IS built.** The step is *labelled* `Building Osprey (Release, net8.0)`, but it builds
  `Osprey.sln`, and the projects are multi-targeted, so both TFMs compile - including
  `Osprey\bin\x64\Release\net472\Osprey.exe`. The `-TargetFramework` parameter only selects which
  test assembly runs, not what compiles.
* **No bjam, no Skyline build.** Steps go from "Set PYTHON_HOME" straight to `Build-Osprey.ps1`.
  So `pwiz_tools/Shared/ProteowizardWrapper/obj/x64` is **never staged** in that workspace, and the
  net472 leg of `Osprey.IO` cannot resolve `pwiz_data_cli`. **The PR fails there as written.**
* Regression data is already on the agent at
  `c:\skyline-downloads\Perftests\osprey-testfiles-mzML`, with a 3-file Stellar mzML dataset.

### Decided (Brendan): split the two CI configs

* **Unit config** builds with the vendor reader OFF, so it needs no ProteoWizard at all. This is the
  default, verified: a clean tree with no `ProteowizardWrapper/bin` builds and passes 554/554, and
  the wrapper is not built.
* **Perf/Regression** builds the full net472 vendor configuration and runs the mzML round-trip test.

Implemented as `/p:OspreyVendorReader=true` (opt-in property, off by default) plus
`Build-Osprey.ps1 -VendorReader`. Opting in by property rather than probing for the DLL keeps a
missing staged assembly a hard error in the config that asked for the capability, instead of
silently producing an Osprey that cannot read raw files.

### The staging step must use TRACKED entry points

`b.bat` / `bs.bat` are **gitignored personal shortcuts** (`.gitignore:442-449`) and do not exist on
a fresh clone or on TeamCity. Decomposed by reading how Skyline actually builds there
(build 4111964, `bt209`):

    C:\pwiz\scripts\misc\tcbuild.bat pwiz_tools\Skyline//Test ... ^
        --i-agree-to-the-vendor-licenses -j8 toolset=msvc-14.5 address-model=64 release ^
        --without-compassxtract --teamcity-test-decoration --automated --official

run from `C:\pwiz\build-nt-x86`. `tcbuild.bat` cleans, builds bjam, then calls `quickbuild.bat`;
later steps call `quickbuild.bat` directly with `--incremental`. Both `scripts/misc/tcbuild.bat` and
`quickbuild.bat` are tracked; `pwiz_tools/build-apps.bat` is too (it is what `b.bat` wraps).

So the Osprey Perf/Regression staging step is a `quickbuild.bat` invocation, NOT a personal batch
file:

    quickbuild.bat pwiz\utility\bindings\CLI//pwiz_data_cli ^
        --i-agree-to-the-vendor-licenses -j%NUMBER_OF_PROCESSORS% ^
        toolset=msvc-14.5 address-model=64 release --without-compassxtract

plus whatever target installs the vendor runtime DLLs next to `Osprey.exe` (the 78 files listed
above). `Build-Osprey.ps1 -VendorReader` prints exactly this command when staging is absent.

Earlier options considered, for the record:

1. **Switch the config's build step to bjam** (`bo.bat`'s target), so the Jamfile stages the wrapper
   deps as Skyline's does. Cleanest and matches the intended `bo.bat` end state, but the first build
   on each agent becomes a full native pwiz compile.
2. **Add a staging step** before `Build-Osprey.ps1` that builds only what is needed
   (`pwiz/utility/bindings/CLI//pwiz_data_cli` plus the vendor-dependency install). Much cheaper
   than a full Skyline build; still a config change.
3. **Make the ProjectReference conditional on the staged DLL existing.** No CI change, but Osprey
   silently loses vendor-raw support wherever staging is absent - including the very parity test
   below - which is the per-machine capability drift rejected earlier.

Recommendation: **2** for the immediate PR (smallest CI change that keeps one capability), with 1 as
the follow-up once `bo.bat` exists.

## Proposed TeamCity test: mzML through both readers, one Stellar file

Cheapest possible form of what was verified by hand today:

* One Stellar mzML from `osprey-testfiles-mzML` (the smallest of the three).
* `--task SpectraCache` twice: once default, once with `OSPREY_MZML_VIA_PWIZ=1`, into two cache dirs.
* Assert byte equality with `ai/scripts/Osprey/Compare/Compare-SpectraCache.ps1` (masks only the
  16-byte source fingerprint; the two runs share a source file so even that could be compared).
* Runtime is dominated by two parses of one file - seconds, not the hour the full Perf/Regression
  leg takes.

**This test cannot pass on net472 until the parse defect is addressed**, because the two readers
disagree on exactly the values .NET Framework misparses. It WOULD pass on net8.0 today. So the test
and the parse fix have to land together, or the test starts life red.

## Progress Log

### 2026-07-29 - Reader implemented; vendor runtime deployment identified

**`--task SpectraCache`** (commit `691f0c3aea`): Stage 1 alone, no `--library`. `EnsureSpectraCache`
moved from `PerFileScoringTask` to `ScoringTaskShared` so the staging and scoring paths write caches
through the identical method.

**`ProteowizardWrapper` reference** (commit `82bdc03302`): net472 only. The x64 mapping had to go in
**Osprey.sln**, not the csproj: an SDK-style project does not pass `Platform` across a
ProjectReference to an old-style one, and neither `AdditionalProperties` nor `SetPlatform` metadata
had any effect. The wrapper resolves `pwiz_data_cli` from `obj\$(Platform)\` and only `obj\x64\` is
staged, so an AnyCPU build fails on every `pwiz.CLI` type. Skyline.sln does exactly this mapping.
Consequence: **Osprey must be built through the solution**; a bare csproj build would fail.

**`SpectrumBuilder`** (new): the single definition of what a spectrum IS - peak sort order, the
isolation-window fail-fast, the precursor-m/z fallback - extracted from `MzmlReader` and shared with
the vendor reader. Without it, a raw-vs-mzML difference could come from two code paths assembling
equivalent data differently, which would make the whole comparison meaningless.

**Refactor verified byte-identical on real data**: rebuilt the TDP-43 mzML cache after the
extraction and compared to the pre-refactor copy - `PARITY: 2,260,174,556 bytes identical`,
n_ms2=161,099, n_ms1=965. The extraction changed nothing.

**`VendorRawReader`** (new, net472 only) + **`SpectrumFileReader`** (both TFMs, dispatches by
extension; net8.0 raises a clear error for a vendor path rather than silently producing nothing).

#### Vendor runtime deployment - the real remaining build work

`pwiz_data_cli.dll` being present next to `Osprey.exe` is NOT sufficient. It is a mixed-mode
assembly and the first raw run failed with:

> Could not load file or assembly 'pwiz_data_cli.dll' or one of its dependencies.

The MSBuild copy brings 101 files to the Osprey output; `ProteowizardWrapper/obj/x64` holds 135.
**78 are missing**, and they are exactly what a vendor-enabled deployment needs:

* **Vendor native**: `MassLynxRaw.dll` (Waters), `timsdata.dll` + `baf2sql_c.dll` (Bruker),
  `Clearcore2.*.dll` + `Sciex.Data.SimpleTypes.dll` (Sciex), `MassSpecDataReader`/`cdt.dll`/
  `MSMSDBCntl.dll`/`IOModuleQTFL.dll`/`PeakItgLSS.dll` (Agilent), `MBI_SDK.dll`, `msparser[D].dll`
* **C/C++ runtime**: `msvcp110/120/140`, `msvcr110/120`, `vcruntime140[_1]`, `vcomp110/140`,
  `ucrtbase.dll`, and ~40 `api-ms-win-*` apiset shims
* **Other**: `SQLite.Interop.dll`, `CABINET.dll`, `msconvert.exe`, `PrmPasefScheduler.dll`

This is the set `install-vendor-api-dependencies` must install into Osprey's output, and it is why
the Jamfile work is a real task rather than a formality. Discovered empirically (copy from
`obj\x64` and re-run) rather than inferred from Skyline's Jamfile, which is what having a Skyline
build in place first bought.

### 2026-07-29 - Session Start

Starting work on this issue.

- Created `pwiz-work1` as a fresh clone of `ProteoWizard/pwiz` for this sprint (origin points at
  GitHub; master fast-forwarded to `520d559fd6`).
- Branched `Skyline/work/20260729_osprey_vendor_raw_reader` off clean master there. `pwiz` is still
  occupied by `Skyline/work/20260727_osprey_stage6_rescore_streaming`.
- Issue #4496 had no module label; inferred `osprey` from the paths the work touches
  (`pwiz_tools/Osprey`) and applied the label to the issue.
- Verified the issue's file references against the new checkout: `Osprey.IO/MzmlReader.cs` (799
  lines here, issue said 874 — master has moved), `Osprey.Tasks/PerFileScoringTask.cs`,
  `Osprey/Directory.Build.props`, `Osprey/Jamfile.jam`, `Osprey.IO/SpectraCache.cs`,
  `Shared/ProteowizardWrapper/ProteowizardWrapper.csproj`, `Osprey/regression.ps1` — all present.

#### Verification of the issue's technical claims (all hold)

- **One call site, one seam.** `MzmlReader.LoadAllSpectra` is called from exactly one place in
  production code: `PerFileScoringTask.cs:2455`, inside `EnsureSpectraCache` (cache-miss path,
  behind `s_mzmlReadGate`). `Osprey.Test/IOTest.cs` has three more. So format selection has a
  single natural home.
- **Isolation-window semantics match exactly** — confirmed at `MsDataFileImpl.cs:2187-2188`:
  `IsolationWindowLower/Upper = GetIsolationWindowValue(p, CVID.MS_isolation_window_lower_offset /
  _upper_offset)`. OFFSETs, same as Osprey's `IsolationWindow(center, lowerOffset, upperOffset)`.
  The single detail most likely to be silently wrong is correct through the wrapper.
- **`ScanNumber` is the mzML `index` attribute, not a vendor scan number** — `MzmlReader` sets
  `ScanNumber = Index` (the 0-based position in the file) for both MS1 and MS2. The wrapper's
  `MsDataSpectrum.Index` is the same 0-based file index, so they line up **only if the raw file
  yields the same spectrum set in the same order as the mzML**. Any msconvert filter that drops or
  reorders spectra shifts every index. See the centroiding/`--simAsSpectra` note below — this is
  the top parity risk, ahead of the numerics.
- **Intensity narrowing is f64 -> f32.** `MsDataSpectrum.Intensities` is `double[]`
  (`MsDataFileImpl.cs:2414-2418`), Osprey's `Spectrum.Intensities` is `float[]`. Vendor intensities
  originate as float32, so widen-then-narrow should be exact; worth asserting rather than assuming.
- **The msconvert settings we must reproduce are known exactly.**
  `ai/scripts/Osprey/SEA-AD/convert-one.cmd:11` is
  `--zlib --simAsSpectra --filter "peakPicking vendor msLevel=1-"` (+ a `titleMaker` filter that
  affects only spectrum titles). Mapping onto the `MsDataFileImpl` constructor
  (`MsDataFileImpl.cs:167-175`):
  | msconvert | MsDataFileImpl |
  |---|---|
  | `--filter "peakPicking vendor msLevel=1-"` | `requireVendorCentroidedMS1: true, requireVendorCentroidedMS2: true` |
  | `--simAsSpectra` | `simAsSpectra: true` |
  | `--zlib` | n/a (mzML encoding only) |
  Getting these wrong yields profile data or a different spectrum set — i.e. the index shift above,
  not a subtle numeric drift.

#### The real cost is the build seam, not the adapter

The C# is genuinely an adapter (~7 scalars + 2 arrays, all present on the wrapper). The
integration cost is elsewhere, and the issue does not call it out:

`ProteowizardWrapper.csproj` is an **old-style, non-SDK, v4.7.2** project that references
`pwiz_data_cli` from `obj\$(Platform)\pwiz_data_cli.dll` (`:91-94`), plus `MassSpecDataReader`,
`SCIEX.Apis.Data.v1` and Thermo assemblies from the same staged directory, and it
ProjectReferences `CommonUtil`. **Those DLLs are bjam build products, not checked in** — verified:
`pwiz-work1` (fresh clone) has no `ProteowizardWrapper/obj/x64/pwiz_data_cli.dll`; the built
`C:\proj\pwiz` checkout does. Skyline stages them via
`Skyline/Jamfile.jam:449-463` (`install install-native-dependencies` ->
`<location>$(PWIZ_WRAPPER_PATH)/obj/$(PLATFORM)`).

Every existing consumer of the wrapper (Skyline, MSConvertGUI, BullseyeSharp, the Test projects)
lives inside a solution that bjam builds *after* that staging. **Osprey does not** — its Jamfile
(`:71`) just shells `msbuild Osprey.sln`, and the everyday gate
(`ai/scripts/Osprey/Build-Osprey.ps1`, default `-TargetFramework net472`) builds the solution
standalone with no bjam prerequisite. Taking a ProjectReference on the wrapper therefore makes a
prior full pwiz build a hard prerequisite of the ~30s Osprey pre-commit gate, on every machine and
every fresh clone.

**Resolved by Brendan (2026-07-29): follow Skyline's example — take the ProjectReference.** The
bjam staging step is not a new burden, it is the established way a checkout is set up for iterative
development:

1. **full build once** — `bs.bat` at the repo root (`b.bat pwiz_tools\Skyline//Skyline.exe` ->
   `pwiz_tools/build-apps.bat 64 --i-agree-to-the-vendor-licenses toolset=msvc-14.5`). Brendan
   normally runs this himself to prepare a checkout.
2. **iterate from there** in the solution (`Skyline.sln` for Skyline; `Osprey.sln` for Osprey).

Skyline.exe depends on `install-native-dependencies`, so `bs.bat` is exactly what stages
`ProteowizardWrapper/obj/x64`. Osprey adopts the same shape. **No conditional compilation, no
per-machine capability drift.**

### Build plan (Skyline's pattern, copied)

* `Osprey.IO.csproj`: `ProjectReference` on `ProteowizardWrapper.csproj` under
  `Condition="'$(TargetFramework)' == 'net472'"`; add ProteowizardWrapper + CommonUtil to
  `Osprey.sln`.
* `Osprey/Jamfile.jam`: add `<assembly>../../pwiz/utility/bindings/CLI//pwiz_data_cli`, a
  `<dependency>` that stages the wrapper's `obj/$(PLATFORM)` (Skyline declares this as
  `install install-native-dependencies` at `Jamfile.jam:449-463`), and an Osprey variant of
  `<conditional>@install-vendor-api-dependencies-to-debug-and-release`.
* The underlying rule **`install-vendor-api-dependencies-to-locations` is in `Jamroot.jam:801`**
  and takes arbitrary locations, so Osprey's variant is a ~4-line rule pointing at Osprey's own
  output dirs (note the TFM subdir: `bin/x64/{Debug,Release}/net472`). `PWIZ_WRAPPER_PATH` is
  Skyline-local (`Skyline/Jamfile.jam:26`), so Osprey declares its own path-constant. This is the
  same copy-from-Skyline precedent the Osprey Jamfile already documents at `:39`/`:43`.

**Prerequisite not yet met in this checkout**: `pwiz-work1` has never had a full build, so
`ProteowizardWrapper/obj/x64/` is empty and nothing net472-against-the-wrapper can compile here
yet. `bs.bat` must run before the first build of the new reference.

### Parity test fixture — already in the repo, nothing to commit

The survey question is closed: `pwiz/data/vendor_readers/Thermo/Reader_Thermo_Test.data/` ships
small tracked Thermo `.raw` files (76 KB `FT-HCD-MSX.raw` up to 343 KB `BSA-FT-HCD.raw`), and
`source_cid_test_3scans.raw` (290 KB) comes with **both** `source_cid_test_3scans.mzML` and
`source_cid_test_3scans-centroid.mzML` — the `-centroid` pair being the vendor-centroided form that
matches `requireVendorCentroidedMS1/MS2: true`.

Verified in `source_cid_test_3scans-centroid.mzML`: 3 spectra, and all 3 carry
`MS:1000827/828/829` (isolation window target + lower + upper offset), so `MzmlReader` can read it
without tripping its fail-fast on missing offsets, and the isolation-window comparison is
exercisable.

**Caveat to record**: this fixture's binary arrays are **32-bit** for BOTH m/z and intensity (8
`MS:1000521`, 0 `MS:1000523`). Production data has f64 m/z, so this test pins the field mapping and
the isolation-window semantics but will NOT catch an f64 m/z precision defect. The full-file
Stage-4 parquet parity check remains the acceptance criterion for that; the unit test is the
permanent guard for the mapping.
