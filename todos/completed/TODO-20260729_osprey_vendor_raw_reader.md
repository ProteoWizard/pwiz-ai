# Osprey: read vendor raw directly via pwiz_data_cli in the net472 configuration - drop the msconvert step

## Branch Information
- **Branch**: `Skyline/work/20260729_osprey_vendor_raw_reader` (pwiz-work1, off clean master)
- **Base**: `master` (520d559fd6)
- **Module**: `osprey`
- **Created**: 2026-07-29
- **Status**: Completed
- **GitHub Issue**: [#4496](https://github.com/ProteoWizard/pwiz/issues/4496)
- **PR**: [#4502](https://github.com/ProteoWizard/pwiz/pull/4502) (merged 2026-07-30 as
  `c4670c1e3d`), with companions [#4501](https://github.com/ProteoWizard/pwiz/pull/4501)
  (`skyline`, green, separate) and [#4500](https://github.com/ProteoWizard/pwiz/pull/4500)
  (`pwiz`, PARKED - see the merge entry)
- **Requester**: Brendan (issue author, Osprey developer) — NO credit line.

## HANDOFF - state as of 2026-07-29 end of session

**Three draft PRs are open, all marked experimental / not ready for review:**

| PR | module | branch | state |
|---|---|---|---|
| [#4500](https://github.com/ProteoWizard/pwiz/pull/4500) | `pwiz` | `Skyline/work/20260729_pwiz_tostring_roundtrip` | complete; `DBL_MAX` round-trip defect found by CI on Linux and fixed (`27e91d2bc9`), awaiting re-run; informational for Matt, may be mooted by #4178 |
| [#4501](https://github.com/ProteoWizard/pwiz/pull/4501) | `skyline` | `Skyline/work/20260729_wrapper_rt_precision` | complete; 9 lines; needs Skyline suite on CI |
| [#4502](https://github.com/ProteoWizard/pwiz/pull/4502) | `osprey` | `Skyline/work/20260729_osprey_vendor_raw_reader` | **incomplete** - build integration unfinished |

### What to do next, in order

1. ~~**Watch TeamCity on all three.**~~ **DONE 2026-07-29 (see progress log).** #4502 came back
   green, which is the *expected* result and confirms the config split worked: the Osprey **unit**
   config was deliberately built so it needs no `ProteowizardWrapper` at all. The predicted net472
   failure belongs to the **Perf/Regression** config, which is manual and has NOT run — Brendan is
   holding that trigger until the Jamfile + staging work below is in place, so the vendor-enabled
   net472 build is still untested on CI. #4500 was red on Linux only; fixed and pushed.
2. **Wire the Perf/Regression config** - see "How the Osprey and Skyline CI configs actually invoke
   the build" below, which corrects the earlier reading of this config and settles where the
   vendor-license flag may live. Two parts: a NEW config step calling `quickbuild.bat` with the
   flags in the step's Command parameters, and a small tracked change so `tctest.bat` can be told
   `-NoBuild`. **Blocked on a real problem**: `regression.ps1` runs the **net8.0** exe, and the
   vendor reader is net472-only.
3. ~~**Jamfile work**~~ **DONE** - commit `de922c9d60`, see progress log. The "78 native runtime
   files" framing was wrong; the necessary set is much smaller and `dumpbin /dependents` names it.
4. **`-ReaderParity` mode in `regression.ps1`** (design in this file). ~34 s on one Stellar file.
5. **Bruker/ReaderTest failures**: 4 of 52 Bruker cases and `ReaderTest` fail LOCALLY with
   `--without-compassxtract` (`Bruker API was built with only BAF and TDF support`). `ReaderTest` was
   confirmed to fail identically on master; the Bruker four were NOT yet controlled against master,
   though the error names the build configuration and cannot be caused by number formatting. Let
   TeamCity settle it.

### Loose ends not owned by any PR

* `C:\proj\pwiz` has two modified submodule pointers (`BullseyeSharp`, `Hardklor`) that may be from
  an accidental build there early in the session. Not investigated; nothing lost.
* ~22 GB of test artifacts under `D:\test\osprey-runs\tdp43-plasma-ev\` (`mzml`, `mzml-roundtrip`,
  `mzml-final`, `cache-*`) and `sea-ad\readercheck\`, plus `C:\proj\ai\.tmp\stellar-readercheck\`.
  Safe to delete.
* `.claude/hooks/Deny-DirectBuildTest.ps1` is registered on the **Bash** tool only, so build commands
  issued through the PowerShell tool bypass it. It also matches on command TEXT, so it blocks commit
  messages that merely mention `MSBuild` or `b.bat`.

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

- [x] Add a vendor-raw reader to `Osprey.IO` behind the same contract `MzmlReader` provides —
      `LoadAllSpectra(path) -> MzmlResult { Ms2Spectra, Ms1Spectra, UnsortedSpectrumCount }`
      (`VendorRawReader`, net472 only)
- [x] Select the reader by file extension in `PerFileScoringTask` (call site is the current
      `MzmlReader` invocation) so nothing downstream is aware of the source format
      (`SpectrumFileReader`, both TFMs)
- [x] Wire `pwiz_data_cli.dll` into the **net472** configuration only, via
      `pwiz_tools/Shared/ProteowizardWrapper` (already `v4.7.2`), not a direct CLI assembly binding
- [x] Add the assembly reference + vendor-dependency conditional to `pwiz_tools/Osprey/Jamfile.jam`,
      following the `Skyline/Jamfile.jam` precedent — commit `de922c9d60`, proven by a raw read from
      a pure bjam build
- [x] Keep `MzmlReader` and the net8.0 target-framework path intact (both TFMs compile in every
      build; `MzmlReader` is still the only net8.0 path)

## Acceptance (from the issue)

- [~] `--task PerFileScoring -i <file>.raw` produces `.spectra.bin` + `.scores.parquet` equivalent
      to the same file converted to mzML first — **`.spectra.bin` half verified** (`--task
      SpectraCache`, byte-identical); the `.scores.parquet` half has NOT been run from a `.raw`
- [x] Byte-parity: a raw-sourced run and an mzML-sourced run of the same file agree at the Stage-4
      parquet, or the differences are characterized and understood — met in the **strong** form, no
      tolerance: `PARITY 2,260,174,556 bytes` on the 3.07 GB TDP-43 file, and `PARITY 12,784 bytes`
      on the committed Thermo fixture from a pure bjam build
- [ ] `regression.ps1 -Dataset All` unaffected (it is mzML-driven and must stay green) — NOT run
      since the Jamfile change
- [~] net8.0 configuration still builds and runs on master via `MzmlReader` — **builds** in every
      configuration exercised; a net8.0 RUN has not been re-verified since the strtod commit

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
2. ~~**Baseline regeneration.**~~ **WRONG - measured, and no regeneration is needed.** The concern
   was that the committed baselines hold values at the truncation boundary (1,097 with exactly 12
   fractional digits across the Thermo `.mzML` baselines), so more digits would break them. It does
   not, because `VendorReaderTestHarness.cpp:382` compares with
   `Diff<MSData, DiffConfig>` - a **semantic diff of parsed MSData with a configurable precision**
   (`diffConfig.precision`), not a byte comparison of mzML text. Extra digits parse to the same
   value. `Reader_Thermo_Test` **passes** with the change. Counting text patterns was a bad proxy
   for "will the tests fail"; running them was the answer.

Note the fix is intentionally conservative on formatting: output is byte-identical to today
wherever today's output already round-trips, so only genuinely-truncated values move.

## FINAL RESULT: exact byte parity, both comparisons

With all three precision fixes in place, on
`2025-0724-TDP43-PlasmaEV-PLT1-A01-365-001.raw` (3.07 GB, 161,099 MS2 + 965 MS1):

| comparison | result |
|---|---|
| **raw-sourced vs mzML-sourced** `.spectra.bin` | `PARITY: 2,260,174,556 bytes identical` |
| **same mzML through MzmlReader vs ProteoWizard** | `PARITY: 2,260,174,556 bytes identical` |

Acceptance criterion 2 of the issue ("byte-parity ... OR the differences are characterized and
understood") is met in its **strong** form. No tolerance, no characterization needed.

The three defects, all in our own code, all now fixed:

| defect | records affected | fix |
|---|---|---|
| `MsDataFileImpl.GetStartTime` did `timeInSeconds()/60` on a value already in minutes | 9,269 RTs | return the recorded value when the unit is `UO_minute` |
| .NET Framework misparses some decimals; `XmlConvert.ToDouble` inherits it | 2 RTs | net472 parses via the CRT's `strtod` (`NativeStrtod`) |
| `pwiz::util::toString` truncated double cvParams to 12 fractional digits | lossy storage; masked the other two | shortest round-tripping form when 12 digits would lose information |

The `strtod` fix also removes a cross-target-framework divergence: net472 and net8.0 Osprey now
produce identical `.spectra.bin` from one mzML, so golden baselines stop being TFM-specific - which
matters for the .NET 8 port independently of vendor raw reading.

## Branch split (2026-07-29) and pwiz test results

Three branches, each verified standing alone off master. All use `Skyline/work/YYYYMMDD_*`, which is
the convention for **every** module here - `Skyline/` is a repo namespace TeamCity keys off, not a
module marker (166 of ~180 remote branches use it; the exceptions are Matt's own `chambem2/*`, a few
`feature/*` and `misc/*`, and generated copilot/backport/revert branches). The module is carried by
the PR title prefix and label instead.

| branch | module | scope | verification |
|---|---|---|---|
| `Skyline/work/20260729_pwiz_tostring_roundtrip` | `pwiz` | 3 files, +197 | `StringTest.passed`; msdata suite clean |
| `Skyline/work/20260729_wrapper_rt_precision` | `skyline` | 1 file, +9 | compiles clean |
| `Skyline/work/20260729_osprey_vendor_raw_reader` | `osprey` | 15 files, +1130 | 554/554, zero inspection warnings |

### pwiz test results for the toString change

Ran `pwiz\data\msdata` + `pwiz\utility\misc` (103-505 targets depending on incrementality):

* **One failure, pre-existing and unrelated**: `ReaderTest.cpp:270` asserts the reader-type set
  contains `Bruker FID`, `Bruker U2`, `Bruker YEP`, and `--without-compassxtract` (which
  `build-apps.bat` passes by default) removes exactly those three readers. **Fails identically on
  master**, verified as a control.
* **No new failures from the change.** `Serializer_mzML_Test`, `IOTest`, `DiffTest`, `MSDataTest`,
  `SpectrumList_mzML_Test`, `ChromatogramList_mzML_Test`, `Serializer_mzXML_Test` all pass - i.e.
  the mzML round-trip and diff tests are unaffected, which is expected since round-tripping a value
  that now keeps more digits still compares equal.

Process note: the first of these runs was accidentally executed on the WRAPPER branch (which touches
no C++), so it tested nothing about `toString` - but it doubled as the master-equivalent control that
established the `ReaderTest` failure as pre-existing.

## PR sequencing: we are NOT gated on Matt's review

The pwiz branch carries two INDEPENDENT fixes, and only one is Matt's:

* **A** - `pwiz/utility/misc/String.cpp` `toString` round-trip. C++, ProteoWizard core, Matt's review.
* **B** - `pwiz_tools/Shared/ProteowizardWrapper/MsDataFileImpl.cs` `GetStartTime`. **C#, Skyline-side,
  ours to review.**

**The proposed CI test needs B and C (the net472 `strtod` parse) only, NOT A.** Verified in the source:
reading an mzML does `getAttribute(attributes, "value", cvParam->value)` (`pwiz/data/msdata/IO.cpp:208`)
- the value attribute is copied **verbatim as a string**. `toString` is only reached when
CONSTRUCTING a CVParam from a number, i.e. writing an mzML or building params from a vendor API. It is
never on the mzML read path.

**Verified empirically too**, which matters more than the reasoning given how often the reasoning was
wrong today. The SEA-AD mzML files were converted 2026-07-09 by **pre-A msconvert** (max 12
fractional digits in their `scan start time` text, confirmed). Reader-vs-reader on one of them:

    PARITY: 4,368,477,008 bytes identical    n_ms2=162,620  n_ms1=974  compared in 2.0s

So the CI test passes against an mzML written WITHOUT Matt's fix, on a second dataset. No stacking,
no gate.

### Raw-vs-mzML without A: depends on CONSISTENCY, not on A itself

| msconvert that wrote the mzML | pwiz reading the raw | result |
|---|---|---|
| no A | no A | **parity** (both at 12-digit precision) |
| A | A | **parity** (both at full precision) |
| no A | A | **mismatch** |

Without A anywhere, the raw path's in-memory CVParam is truncated by the same `toString`, so both
sides land on the identical decimal - which is why the original 9,269 differences were `GetStartTime`
and not truncation. The mixed row is the case actually observed: after fixing `toString`, the old
12-digit mzML vs the full-precision raw diverged from record 0.

**Consequence to tell Matt:** every mzML already archived was written by pre-A msconvert, so once A
lands, reading those raws directly will no longer byte-match those stored mzML files. That is a
one-time discontinuity for archived data - an argument for landing A deliberately, not against it.

**Recommended sequencing:** (1) Osprey PR + B, self-contained and green; (2) A to Matt separately on
its own merits (precision preservation + the 1,097 baseline values).

### Verified on Stellar too

(I first reported Stellar as absent from this machine - wrong. `regression.ps1` acquires it to
`<Downloads>\Perftests\osprey-testfiles-mzML-v2\stellar\`, i.e.
`D:\Users\brendanx\Downloads\Perftests\...` here. My search was capped at depth 5 and that path is
depth 6.)

| dataset | mode | mzML written by | reader-vs-reader result |
|---|---|---|---|
| TDP-43 PlasmaEV | Astral | post-fix msconvert | `PARITY` 2,260,174,556 bytes |
| SEA-AD | Astral | **pre-fix** msconvert | `PARITY` 4,368,477,008 bytes |
| **Stellar** file 22 | **unit** | **pre-fix** msconvert | `PARITY` 1,122,449,320 bytes |

Stellar: ms2=97,500, ms1=780. Its RTs are 11-12 fractional digits (`0.001708192067`), so it is
pre-A output and passes anyway - consistent with the read path never touching `toString`.

**Cost on the Stellar file: ~34 s total** - 11.7 s hand-rolled parse, 20.4 s via ProteoWizard,
1.3 s to compare 1.12 GB.

### Wiring it into regression.ps1

`regression.ps1` already owns everything the test needs:

* `-Dataset {Stellar, StellarLibDecoy, StellarGenDecoyEntrap, Astral, All}`, `-DownloadsPath`,
  `-TeamCity`, `-NoBuild`, `-Threads`.
* Data acquisition via `Get-RegressionData` (`Osprey/Regression/RegressionData.ps1`) from the
  Panorama zip `osprey-testfiles-mzML-v2.zip`, skip-if-present on the extracted root, with the URL's
  `perftests` segment mapping to `<Downloads>\Perftests`. So the Stellar mzML path comes for free and
  works identically on TeamCity (which logged "data present, skipping download").

Proposed: a `-ReaderParity` mode that takes ONE file from the selected dataset's mzML folder, runs
`--task SpectraCache` twice into two temp cache dirs (default, then `OSPREY_MZML_VIA_PWIZ=1`), and
byte-compares.

Two design notes:

1. **No fingerprint masking is needed here.** Both runs read the SAME source file, so
   `source_size`/`source_mtime` match too - a plain full-file byte comparison is valid and strictly
   stronger than `Compare-SpectraCache.ps1`'s masked compare. Keep the masked comparator for the
   raw-vs-mzML case, where the fingerprints must differ.
2. **It requires the vendor-enabled build.** On a build without it, `OSPREY_MZML_VIA_PWIZ=1` raises a
   clear `NotSupportedException` naming `/p:OspreyVendorReader=true`, so the mode can detect that and
   fail loudly in the config that is supposed to have the capability rather than silently pass.

## Earlier result (before the strtod fix), kept for the record

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

## How the Osprey and Skyline CI configs actually invoke the build (2026-07-29, from screenshots)

### CORRECTION: the Osprey Perf/Regression config does NOT call Build-Osprey.ps1

Its build steps are just two:

1. `Set PYTHON_HOME if unset by agent` (custom script)
2. Command executable `pwiz_tools/Osprey/tctest.bat`, **Command parameters: not specified**

`tctest.bat` is TRACKED and runs `pwsh -NoProfile -File regression.ps1 -TeamCity -Dataset All`.
`regression.ps1:308-310` then calls the tracked `pwiz_tools/Osprey/build.ps1
-Configuration Release -Framework net8.0 -NoTests`.

The earlier claim that the steps went "from Set PYTHON_HOME straight to `Build-Osprey.ps1`" was a
misreading: `Building Osprey (Release, net8.0)` is a `Write-Progress-Tc` message emitted by
`regression.ps1` INSIDE the `tctest.bat` step, not a TeamCity step name, and the script it runs is
`pwiz_tools/Osprey/build.ps1` (in-repo), not `ai/scripts/Osprey/Build-Osprey.ps1`.

### The vendor-license flag must NEVER be committed (Brendan, 2026-07-29)

`--i-agree-to-the-vendor-licenses` belongs in the **TeamCity config's Command parameters**, never in a
tracked script. Agreeing to the vendor licenses has to be an explicit act by whoever runs the build;
a committed flag would accept the licenses on behalf of everyone who builds the project. **This is
why `b.bat` / `bs.bat` are small private gitignored files - creating one IS the act of agreeing.**

Skyline's config is the model. Its steps put every such argument in the config:

    Step 2  exe: %teamcity.build.checkoutDir%/scripts/misc/tcbuild.bat   workdir: build-nt-x86
            params: pwiz_tools\Skyline//Test pwiz_tools\Skyline//TestData
                    pwiz_tools\Skyline//Skyline.passed ... --i-agree-to-the-vendor-licenses
                    -j%env.NUMBER_OF_CORES% %env.toolset_property% %env.address_model_property%
                    %env.architecture_property% %env.variant_property% %env.link_property%
                    --without-compassxtract --teamcity-test-decoration --automated --official

    Step 3  exe: %teamcity.build.checkoutDir%/quickbuild.bat             workdir: build-nt-x86
            params: pwiz_tools\Skyline//TestFunctional --abbreviate-paths --verbose-test
                    --incremental --i-agree-to-the-vendor-licenses -j... (same env properties)
                    --without-compassxtract --teamcity-test-decoration --automated

Note step 3 passes `--incremental` AFTER the non-incremental step 2 - which is exactly the ordering
the `Version.cpp` generation gotcha requires, and confirms the agent-provided
`%env.*_property%` values are how toolset/variant/address-model reach bjam.

**The Jamfile change is consistent with this**: it READS ARGV to see whether the flag was supplied
and never supplies it, so the vendor capability turns on only for someone who agreed.

### Revised plan for the Osprey config - TWO steps, not one

* **New step** before the `tctest.bat` step: exe `%teamcity.build.checkoutDir%/quickbuild.bat`,
  working directory `build-nt-x86`, params
  `pwiz_tools\Osprey//Osprey --i-agree-to-the-vendor-licenses -j%env.NUMBER_OF_CORES%
  %env.toolset_property% %env.address_model_property% %env.variant_property%
  --without-compassxtract`. Non-incremental, so `Version.cpp` is generated.
* **`tctest.bat` forwards `%*`** to `regression.ps1` (a tracked change carrying NO flag), so the
  config can append `-NoBuild` - and later `-ReaderParity` - without another repo change.

### BLOCKER for -ReaderParity: the regression gate runs net8.0, the reader is net472

`regression.ps1:137-138` hardcodes

    $ospreyBinDir = Osprey\bin\x64\Release\net8.0
    $ospreyExe    = $ospreyBinDir\Osprey.exe

and `build.ps1` is invoked with `-Framework net8.0`. Verified: there is no `pwiz_data_cli.dll` in the
net8.0 output, correctly - it is a net472-only mixed-mode assembly. So **`-ReaderParity` cannot use
`$ospreyExe`**; it needs the net472 exe, and `build.ps1` has no vendor switch (its params are
`Configuration`, `Framework {net8.0|net472|both}`, `NoTests`, `Coverage`, `TeamCity`, `Verbosity`).

Design that follows: `-ReaderParity` resolves its own net472 exe path rather than reusing
`$ospreyExe`, and fails loudly if the vendor runtime is absent (the `NotSupportedException` naming
`/p:OspreyVendorReader=true` already gives it a clean signal). Do NOT switch the whole regression to
net472 to make this convenient - the mzML-driven gate is net8.0 for good reasons and the strtod fix
made the two TFMs produce identical caches anyway.

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

**UPDATE - it passes now.** With the CRT `strtod` parse in place, the reader-vs-reader comparison on
the full 2.41 GB TDP-43 mzML is **`PARITY: 2,260,174,556 bytes identical`** (n_ms2=161,099,
n_ms1=965, compared in 1.8 s). Both readers on net472 produce a byte-identical `.spectra.bin` from
the same file, so the test can land green rather than red-until-fixed as feared. The comparison
itself took under two seconds on 2.26 GB, so the CI cost is dominated by the two parses.

## Progress Log

### 2026-07-30 - Merged

PR #4502 merged as `c4670c1e3d`. Osprey reads vendor instrument files directly in the net472
configuration through `ProteowizardWrapper`, opt-in at build time
(`/p:OspreyVendorReader=true`) and **off by default**, so nothing that does not opt in
changes. `--task SpectraCache` ships as the staging pass that replaces msconvert, and in a
build that HAS ProteoWizard it is now the reader for every format including mzML - the
direction toward deleting `MzmlReader` once #4178 gives ProteoWizard a .NET 8 build.

Gates at merge: `regression.ps1 -Dataset All` 18/18 locally, TeamCity Perf/Regression SUCCESS
on the exact merged commit (build 4114985, full four-dataset run verified in the log rather
than inferred from a green light), 556/556 unit tests, zero inspection warnings, 18/18
automatic PR checks. Byte parity proven three ways: raw vs mzML on a 3.07 GB TDP-43 file
(2,260,174,556 bytes identical), reader vs reader on the same mzML, and raw vs mzML on the
committed Thermo fixture from a pure bjam build.

**Deferred deliberately, not shipped**: the `run.raw` / `run.mzML` cache-stem collision
(Brendan: `run.raw.spectra.bin` is awkward when the 98% case is one data file per directory);
`precursors[0]` vs `MzmlReader`'s effective LAST precursor, which needs a decision about which
side is correct before either is called a bug; and the `SpectraCache.VERSION` bump, whose
narrow exposure is documented above.

**`Test-PerfGate.ps1` was never run** - no `pwiz-perfbase` worktree on the machine. Brendan
merged with that known, reasoning that the gate is dominated by everything AFTER
`.spectra.bin` is built, and that raw -> `.spectra.bin` cannot plausibly be slower than
raw -> mzML -> `.spectra.bin`, which also carries a large disk cost unless the mzML is
discarded.

**Follow-ups worth filing** (none are this PR's to fix): the rescore payload
decode-then-discard and the warn-only mode 3 with nothing in CI scanning warnings (both
#4488, which arrived via the merge), and the pre-existing `ParseSpectrumRaw` hang where an
escaping exception bypasses `queue.CompleteAdding()` and blocks the consumer forever.

**Also delivered**: 163 `.spectra.bin` caches for the 164-file TDP-43 raw set (10 h, ~22 MB/s
end to end), staged with no mzML anywhere; the 164th is an aborted acquisition the depositor marked -bad.

### 2026-07-30 (morning) - /code-review findings addressed (commit `68cd2fe703`)

15 findings; 11 fixed, 2 deferred by Brendan, 2 out of scope. 556/556, inspection clean.

**The one that mattered: a silently GREEN broken build.** `IF ERRORLEVEL 1 exit %ERRORLEVEL%`
inside a parenthesized cmd `IF` block returns **0** on a command that exits 7 - cmd parses the
whole block first, so `%ERRORLEVEL%` is substituted at PARSE time - and `exit` without `/b`
kills the action, so `msbuild Osprey.sln` never ran while bjam recorded success. Reproduced
independently before fixing. Now a `GOTO` with the check at top level, exactly as
`Skyline/Jamfile.jam:185` does it, verified to return 7.

**Two corrections to the review itself:**

1. Of the four `ReaderConfig` values it flagged, only `combineIonMobilitySpectra` is settable.
   `acceptZeroLengthSpectra` already defaults to true (matching pwiz), and
   `ignoreCalibrationScans` / `allowMsMsWithoutPrecursor` are **hardcoded in the wrapper's
   ReaderConfig initializer**, not constructor parameters - changing them would change shared
   Skyline behavior. Set the one that is settable; documented the two that are not as bounding
   the parity claim to Thermo, where it was actually measured.
2. The first fix for the fingerprint hole **broke `TestSpectraCacheFingerprint`**, which
   deliberately asserts that a cache written with NO fingerprint is accepted even when a
   source is supplied. That is a contract, not an oversight. Final design distinguishes "no
   source given" (0, still trusted) from "source exists but unmeasurable"
   (`FINGERPRINT_UNMEASURABLE = ulong.MaxValue`, always rejected) - closing the hole on both
   read and write sides with no version bump, since an older reader just mismatches the
   sentinel and re-parses.

**Deferred by Brendan**: the `run.raw` / `run.mzML` stem collision (#6) - his reasoning:
`run.raw.spectra.bin` is awkward when the 98% case is one data file per directory, or the same
data matching by base name; and `precursors[0]` vs `MzmlReader`'s effective LAST precursor
(#10), which needs a decision about which side is correct before either is called a bug.

**NOT bumping `SpectraCache.VERSION`** (Brendan's call - it would invalidate every existing
cache including the 163-file set). Exposure is narrow: a cache is only at risk if written by a
**net472** build from an **mzML** source **before** `eb727aedeb` with the source unchanged.
net8.0 never had the defect and raw-sourced caches get values from pwiz, so the 163 are
unaffected. The one real bite: a raw-vs-mzML parity check run against such a warm cache
reports a SPURIOUS difference. Remedy is deleting those specific caches, not a global bump.

**Out of scope** (they arrived with the #4488 merge, not this PR's diff): the rescore payload
decode-then-discard, and mode 3 being warn-only with nothing in CI scanning warnings. Both
look real; worth follow-up issues.

**Pre-existing hazard noted in passing, worth an issue**: an exception escaping
`ParseSpectrumRaw` (`MzmlReader.cs:127`) bypasses `queue.CompleteAdding()`, leaving the
consumer `Parallel.ForEach` blocked forever on an undisposed `BlockingCollection`. This diff
adds new throw sites on that path.

### 2026-07-30 (morning) - ProteoWizard is now the reader for EVERY format in the opt-in build

Commit `f37a6a4b1c`. Brendan's call, and the direction it sets: in a build that has
ProteoWizard, all mass spec data flows through it, mzML included. `MzmlReader` survives only
because `pwiz_data_cli` has no .NET 8 build; when **#4178** lands it should be deleted
outright and `SpectrumFileReader` stops having a decision to make.

**The switch inverted rather than disappeared.** `OSPREY_MZML_VIA_PWIZ` (opt IN to
ProteoWizard) is now `OSPREY_MZML_VIA_MZMLREADER` (opt OUT of it). It has to survive in some
form: it is the only thing that makes the reader-vs-reader parity check expressible - the
same mzML read both ways, byte-compared - which is the check that justified this change in
the first place. In a build WITHOUT ProteoWizard it is a no-op rather than an error, since
it asks for what already happens.

**Verified the new default empirically, not from the `#if`.** Both readers log the identical
"Reading X.mzML..." line, so the log cannot tell them apart, and a byte comparison alone
would pass vacuously if the switch did nothing. The discriminator: **remove
`pwiz_data_cli.dll` from the output directory.**

| run | pwiz_data_cli present? | result |
|---|---|---|
| default | removed | **FAILS** - `Could not load file or assembly 'pwiz_data_cli...'` |
| `OSPREY_MZML_VIA_MZMLREADER=1` | removed | **SUCCEEDS** - ms2=3 cached |

So the default path genuinely is ProteoWizard and the switch genuinely selects `MzmlReader`.
With that established, the two readers' caches byte-compare:
`PARITY: 12,784 bytes identical`.

**One inspection consequence**: the `#else` branch no longer touches `OspreyEnvironment`, so
`using pwiz.Osprey.Core;` became a redundant-using warning in the default build. It is now
wrapped in `#if OSPREY_VENDOR_READER`.

Gates: 556/556 and inspection clean in the default build; vendor build compiles and runs.

### 2026-07-30 (night session) - Merged master, PR READY FOR REVIEW, TeamCity fired

Night session goal: get #4502 as close to merge-ready as possible against the bar
**"safe to merge with opt-in OFF by default"**, plus stage `.spectra.bin` for the whole
TDP-43 raw set. Brendan runs `/code-review` himself in the morning.

**Where #4502 stands:**

| item | state |
|---|---|
| `regression.ps1 -Dataset All` | **18/18 PASS** in one clean run over `8b59effee3` |
| master merged in (`0672018888`) | clean, no conflicts |
| post-merge unit gate | **556/556**, zero inspection warnings, both TFMs |
| PR body | rewritten; no longer says "experimental" |
| PR state | **READY FOR REVIEW** (Copilot will auto-review) |
| TeamCity Perf/Regression | triggered on `pull/4502`, **build 4114865** |
| `Test-PerfGate.ps1` | still NOT run - no `pwiz-perfbase` worktree on this machine |

**The merge mattered more than it looked.** master gained #4488 (Stage-6 memory bounding),
which rewrote `PerFileScoringTask.cs` (+473) and `RescoreHydration.cs` (+625) - and this
branch MOVED `EnsureSpectraCache` out of `PerFileScoringTask`. `git merge-tree` predicted a
clean merge and the merge was clean, but textual cleanliness does not rule out a semantic
conflict, so it was verified explicitly afterwards: the atomic-write change, the new test,
and `EnsureSpectraCache` living only in `ScoringTaskShared` (count 1 there, 0 in
`PerFileScoringTask`). No goldens changed in #4488, as expected for behavior-preserving
memory work.

**Deliberately did NOT re-run the local regression after the merge.** TeamCity
Perf/Regression on `pull/4502` builds GitHub's MERGE ref, so it runs
`regression.ps1 -Dataset All` against exactly the merged state, in the cloud, with no
contention against the 164-file caching run using this machine's disks. That is the
stronger artifact and it is already in flight.

#### Provenance trap caught before the caching run

The staged `obj/x64/pwiz_data_cli.dll` was the **fix-A** build left over from the Agilent
investigation on the `pwiz` branch. Since #4500 is parked, master will NOT have fix A, so
caches built with that binding would embed full-precision RTs that **no post-merge build
could reproduce**. Rebuilt the binding from this branch first (`String.obj` recompiled,
14,582,784 bytes vs 14,585,344 with fix A) and moved the one pre-existing cache aside to
`tdp43-plasma-ev/cache-preA-reference/`, so all 164 caches come from one stock binary.

#### TeamCity Perf/Regression GREEN on the merged state

Build **4114865** on `pull/4502` (commit `0672018888`, i.e. GitHub's merge ref):
**SUCCESS**, and verified it actually ran rather than skipping - the log shows all four
datasets from 22:27 to 23:51 and `Osprey regression PASSED`. A ~23-minute apparent runtime
was my own clock error; the real run was 84 minutes.

The only commit after it is `2b55d0963b`, which is **comments and two log strings only**
(the Copilot doc fixes). Deliberately did NOT re-fire the config for a doc-only delta - a
re-trigger is a fresh ask under the ask-first rule, and the regression compares blib and
parquet output, not log text.

#### Copilot review addressed (commit `2b55d0963b`)

Two inline comments, both legitimate and both documentation accuracy:

* `ScoringTaskShared.EnsureSpectraCache` doc said a cache miss "re-parses mzML", and two
  runtime log messages said the same, when the input can now be a vendor raw. Also fixed
  the adjacent comment on `s_mzmlReadGate`, which serializes vendor-raw parses too; the
  FIELD NAME was left alone deliberately to keep the diff doc-only.
* `Program.cs` said per-file parquet lands "next to each input mzML".

Both threads replied to with the SHA and resolved. 556/556 and inspection clean afterwards.

#### The 164-file SpectraCache run

* 164 `.raw` files, 787 GB (Brendan said 162; the set is 164).
* Runs from a SNAPSHOT at `D:\test\osprey-runs\_bin\vendor-pr4502\` (178 files), so
  rebuilding the working tree cannot disturb it.
* Caches land BESIDE each `.raw` - Osprey's default cache dir - so a morning run pointed
  at the same inputs finds them with no extra flags.
* Launcher `ai/.tmp/run-spectracache-164.ps1`; log
  `D:\test\osprey-runs\tdp43-plasma-ev\spectracache-164.log`.
* `--timestamp --memstamp` are on, so `ai/scripts/perfviz.py` can read the log: this
  doubles as a **scaling measurement** over 164 files. A per-file memory floor that RISES
  across the set would be an O(files) regression worth knowing about.
* `SpectraCacheTask` iterates `foreach` (sequential), so memory stays bounded to one file -
  checked before launching 164 of them unattended.
* Pre-flight: the snapshot read a committed Thermo `.raw` and wrote a cache before the big
  run started.

**FINAL: `Cached 163 of 164 file(s) in 36,024.4s`** - 10h 00m, finished 08:26:59, exit 1.

The exit code is CORRECT, not a failure: `SpectraCacheTask` logs an unreadable input,
continues the sweep, and still fails the run at the end, which is what the one corrupt file
produced. 163 caches now sit beside their `.raw` files, so a run pointed at those inputs
finds them with no extra flags and no mzML anywhere.

Throughput for planning: 787 GB in 10 h is **~22 MB/s end to end**, well under the ~55 MB/s
projected from the Stellar mzML timing - raw parsing plus a ~3 GB cache write per file is
heavier than reading mzML. Budget ~3.7 min/file on this hardware.

**The one failure is a aborted acquisition marked bad by the depositor, not a defect.**
`2025-0724-TDP43-PlasmaEV-PLT2-C03-5112-027-bad.raw` - note the `-bad` suffix - fails with
`[RawFileImpl::ctor()] Corrupt RAW file`. Osprey logged it and **continued to the next
file** rather than aborting the staging pass, which is the behavior a 164-file run needs.
So 163 usable caches are the expected final count, not 164.

**`--task SpectraCache` is memory-BOUNDED over the set** (`perfviz --files 164 --force`;
`--force` needed because the corrupt-file `[ERROR]` makes perfviz refuse by default):

| | peak | floor | drift | verdict |
|---|---|---|---|---|
| managed | 11.9 GB | 0.8 -> 1.2 GB | +0.43 GB (+3 MB/file) | RISING but trivial |
| total (private) | 14.8 GB | 5.1 -> 3.6 GB | -1.49 GB (-9 MB/file) | **FALLING** |

**Correction worth recording**: two raw `--memstamp` samples (151 MB at file 1 vs 8.9 GB at
file 113) looked like severe O(files) accumulation, and the computed FLOOR refutes it. That
is exactly the trap `ai/docs/memory-band-guide.md` names - point samples catch the per-file
transient at different phases. Trust the floor, never two stamps.

10 reporting gaps >= 30 s (max 81 s), every one immediately after a file reaches 100%, so
they are the multi-GB cache write plus index pass, not stalls.

### 2026-07-29 (evening) - Full regression gate GREEN; non-opt-in cache consumption

**Standing gate result on this branch: 18 checks, 0 failures**, across all four datasets. This was
the gap for a checkpoint merge, since the branch refactors the SHARED mzML read path
(`SpectrumBuilder` extraction, `EnsureSpectraCache` moved to `ScoringTaskShared`).

| dataset | modes |
|---|---|
| Stellar | mode1 vs golden, mode3 HPC chain, mode2 resume - PASS |
| StellarLibDecoy | mode1, mode1b diagnostics, mode1b FDR bounds, mode3, mode2 - PASS |
| StellarGenDecoyEntrap | mode1, mode1b diagnostics, mode1b FDR bounds, mode3, mode2 - PASS |
| Astral | mode1, mode1b diagnostics, mode1b FDR bounds, mode3, mode2 - PASS |

**`Test-PerfGate.ps1` still NOT run**: it needs the pinned `C:\proj\pwiz-perfbase` worktree, which
does not exist on this machine. Either create it (the documented setup, and what makes perf numbers
comparable across sessions) or pass `-BaselineRoot C:\proj\pwiz` (on master, but a baseline that
moves whenever that checkout does). The perf gate matters here specifically because
`SpectrumBuilder` was extracted into the hot per-spectrum assembly loop.

#### A false alarm that was MY fault, and the real bug it exposed

The first `-Dataset All` run aborted on StellarGenDecoyEntrap with
`Missing PrecursorCharge at row 249759`. Cause: **I killed an earlier invocation with `TaskStop`**
(to move it off a `tail` pipe) while it was deriving
`TestResults/_derived/carafe_spectral_library.nodecoy.tsv`. That left the file truncated mid-field
(249,758 complete lines, last line ending `...^IEAVLHACR^I47`), and because the derived library is
reused skip-if-present, every later run consumed the corrupt copy. Deleting it made the dataset pass
all five checks. **Not a branch regression.**

The underlying defect is real and independent of my mishap: the derivation wrote **directly to the
final path**, so any interruption - Ctrl-C, a cancelled TeamCity build (we watched one get
`Canceled (Retry attempt 1/3)` today), an agent reboot - leaves a truncated file whose mtime is
NEWER than the source, so the staleness check accepts it forever. Fixed by writing to
`$stripped.tmp` and `Move-Item`-ing into place only after the `$dropped -eq 0` sanity check passes.

Second tooling gap noted: a LOCAL failure loses its own evidence. The run dir is pruned
(`-KeepRunDirs 0`) and the design assumes the diagnosis lives in the TeamCity build log, so the
console pointed at a `straight.log` that no longer existed. Re-running with `-KeepOutput` was the
only way to read it.

#### Non-opt-in builds can consume raw-derived caches (Brendan's requirement)

Goal: stage `.spectra.bin` once on a vendor-capable machine, then run any build - net8.0, or net472
without the flag - against the SAME `.raw` inputs with no mzML conversion.

**It already worked, for file-based formats.** `EnsureSpectraCache` checks the cache and returns
(`ScoringTaskShared.cs:150`) before `SpectrumFileReader.LoadAllSpectra` (line 176), and nothing
upstream filters by extension - `-i` appends tokens verbatim (`OspreyCommandArgs.cs:79`). The
fingerprint still protects a Thermo `.raw`, so a STALE cache is still caught and then fails with the
clear vendor-reader error instead of using stale data.

Three changes (commit `8b59effee3`):

1. **Directory inputs accepted.** `Program.cs` validated with `File.Exists` alone, and Agilent `.d`,
   Bruker `.d` and Waters `.raw` are DIRECTORIES - so they were rejected with "Input file not found"
   on EVERY build, opt-in or not. Only file-based formats (Thermo `.raw`, Sciex `.wiff`) could reach
   the reader at all. That is a real limitation of the feature as first written, not just a
   non-opt-in issue.
2. **Directory fingerprint.** `FileInfo.Exists` is false for a directory, so
   `ComputeSourceFingerprint` returned 0/0 - and the read side SKIPS the staleness comparison when
   the stored size is 0 (`SpectraCache.cs:308`), meaning a directory-sourced cache was accepted no
   matter how the source changed. Now sums content sizes and takes the newest write time. The file
   branch is byte-for-byte unchanged, so existing caches stay valid.
   Trade-off recorded in the code: a vendor SDK that writes a sidecar into the bundle on read would
   move the fingerprint and cost a re-parse - a performance cost that announces itself in the log,
   versus silently trusting a stale cache. **Verified Agilent does not mutate on read**: msconvert
   read a tracked `.d` and `git status` showed nothing modified inside it. Bruker TDF/sqlite is
   untested (no local data) and stays a known residual.
3. **`TestVendorCacheUsableWithoutVendorReader`** pins the ordering, which nothing else did - an
   up-front extension check added for a friendlier error message would have broken the workflow with
   every other test green. **Proved it can fail**: temporarily inserting exactly that check made it
   fail at `ScoringTaskShared.cs:142`, then reverted. The test is also sound in both build
   configurations - a cache MISS throws either way, so it cannot pass for the wrong reason.

**Gate**: 555/555 (the +1 is the new test), inspection clean, both target frameworks.

### 2026-07-29 (later still) - Jamfile vendor deployment DONE and proven end to end

Commit `de922c9d60`. **`--task SpectraCache` on a vendor `.raw` now works from a pure bjam build**,
and the `.spectra.bin` is byte-identical to the one built from the tracked centroided mzML:

    PARITY: 12,784 bytes identical (source fingerprint masked)   n_ms2=3  n_ms1=0

on `pwiz/data/vendor_readers/Thermo/Reader_Thermo_Test.data/source_cid_test_3scans.raw` vs its
committed `-centroid.mzML`. **That is raw-vs-mzML parity on data already in the repo**, which is the
Tier-2 fixture - so the permanent unit test has a proven assertion to make, not a hoped-for one.

**Three pieces in `pwiz_tools/Osprey/Jamfile.jam`:**

1. **Capability gate** - `OSPREY_VENDOR_READER` is true only with
   `--i-agree-to-the-vendor-licenses`, the flag every other vendor-API consumer keys off
   (`Skyline/Jamfile.jam:22`). Verified for real, not just `-n`: a no-flag
   `bjam pwiz_tools/Osprey//Osprey` updated 1 target and pulled in no native pwiz build at all, so
   the everyday Osprey build stays ProteoWizard-free.
2. **`do_osprey`** builds `ProteowizardWrapper.csproj` for x64 first when the capability is on (it is
   not in `Osprey.sln`, and `Osprey.IO` references its built output by HintPath), then passes
   `OspreyVendorReader=` to the solution build.
3. **`install-vendor-api-dependencies-to-osprey-net472`** + two `install-osprey-native-runtime-*`
   targets, into `Osprey/bin/x64/{Debug,Release}/net472`.

**Staging is REUSED from Skyline's `install-native-dependencies`, not redeclared.** Two installs
writing the same files to the same location would collide as duplicate targets in any build
requesting both, and Skyline's is the exact staging every parity result here was produced against.
Cost: an Osprey vendor build also builds `msconvert` and `TestDiagnostics`. Lifting the shared rules
to a common Jamfile stays the follow-up cleanup.

#### The 78-file list was necessary-vs-sufficient, and the real answer is much smaller

The earlier list came from copying all of `obj/x64` and re-running, which proves sufficiency, not
necessity. `dumpbin /dependents` on `pwiz_data_cli.dll` gives the actual imports: `timsdata.dll`,
`MSVCP140`, `VCRUNTIME140[_1]`, `MassLynxRaw.dll`, `msparser.dll`, `baf2sql_c.dll`, `MBI_SDK.dll`,
the `api-ms-win-crt-*` shims, plus system DLLs. **`msconvert.exe`, `PrmPasefScheduler.dll`,
`TestDiagnostics.dll`, `msparserD.dll` and the `H5*.exe` are NOT needed** - they were only in
`obj/x64` because Skyline puts them there.

Two rounds of "still could not load" were needed, each diagnosed rather than guessed:

* **C/C++ runtimes.** `install-vendor-api-dependencies-to-locations` installs the vendor APIs but not
  the runtimes they link against (VC110/VC120 for Sciex/Agilent/Waters, the VC140 UCRT apisets).
  Jamroot's `install-msvc-runtime-dlls` (`Jamroot.jam:1585`) has the file list but **cannot be
  retargeted** with a location-qualified `<dependency>` the way the vendor installs can
  (`Skyline/Jamfile.jam:526`): its requirements include `<conditional>@install-location`, which
  returns `<location>` unconditionally, so an override hands `stage.jam` two locations and bjam dies
  inside `path.relative`. Hence Osprey-local installs that share only the source list.
* **`msparser.dll`.** `pwiz_data_cli` imports it directly, and the Mascot parser is not a `pwiz_aux`
  vendor API, so no vendor rule carries it. Skyline gets it from the `msparser` searched-lib's
  `<assembly-dependency>` (`Jamroot.jam:1391`) via `install-dependencies`; Osprey's output is
  populated by the solution build instead, so it is installed explicitly (the real 11.8 MB one -
  note `msparserD.dll` in `obj/x64` is the 116-byte FAKE Skyline makes at `Jamfile.jam:395`).

**The failure mode gives you nothing to go on.** `pwiz_data_cli` is mixed-mode, so a missing native
import surfaces only as `Could not load file or assembly 'pwiz_data_cli.dll' or one of its
dependencies`, naming none of them. `dumpbin /dependents` against the deployed directory is the tool;
do not iterate by copying files.

#### bjam invocation gotcha: --incremental disables Version.cpp generation

`generate-version.jam:33` skips generation unless the build is non-incremental or passes
`--force-generate-version`, and regeneration DELETES the file first. A `--incremental` build in a
checkout without generated `Version.cpp` files fails with `Unable to find file or target named
'Version.cpp'` from `pwiz/analysis` - nothing to do with the Osprey change. TeamCity gets this right
by making the first step non-incremental. Locally, `--incremental --force-generate-version` is the
combination that both generates versions and skips the `git submodule update --init --recursive` that
merely LOADING Skyline's Jamfile triggers (`Skyline/Jamfile.jam:45-49`) - which is the likely origin
of the modified `BullseyeSharp`/`Hardklor` submodule pointers noted as a loose end in `C:\proj\pwiz`.

#### Build-Osprey.ps1 guidance was wrong, now corrected

When `obj/x64/pwiz_data_cli.dll` was missing the script told you to run
`quickbuild.bat pwiz\utility\bindings\CLI//pwiz_data_cli`. **Nothing under `pwiz/` references
`ProteowizardWrapper`** - that target builds the DLL into `build-nt-x86` and never copies it to the
path the script then tests for, so following its own instructions left the check still failing. Now
points at `pwiz_tools\Osprey//Osprey`, and documents that `-VendorReader` COMPILES the reader but
never deploys the vendor runtime, so an Osprey built that way cannot read a raw file until the bjam
target has run once in the checkout.

#### Two inspection warnings fixed (were NOT clean before this session)

The TODO's "zero inspection warnings" predates commit `eb727aedeb`, which landed with two:

* `MzmlReader.cs:698` - `<see cref="NativeStrtod"/>` cannot resolve in the net8.0 pass, because
  `NativeStrtod.cs` is entirely `#if NET472`. Now `<c>NativeStrtod</c>`.
* `IOTest.cs:31` - `using System.Xml;` left over from switching that test off `XmlConvert` as its
  oracle; referenced only in comments now.

**Gate after the fixes**: 554/554, inspection clean, both target frameworks.

### 2026-07-29 (later) - CI results on all three PRs; StringTest DBL_MAX defect fixed

**TeamCity / GitHub checks read on all three PRs:**

| PR | module | verdict |
|---|---|---|
| #4502 | osprey | **15 SUCCESS, 0 failing.** Expected. The unit config builds with the vendor reader off (`/p:OspreyVendorReader=true` not passed), so it never needs staged `pwiz_data_cli`. **This does NOT exercise the net472 vendor build** - that is the manual Perf/Regression config, deliberately not triggered yet. |
| #4501 | skyline | 12 SUCCESS, 3 Windows legs still running, none failing. |
| #4500 | pwiz | **2 red, one cause** - the new `StringTest`, on Linux only. |

#### Root cause of the #4500 Linux failure: the round-trip check accepted overflowing text

    [pwiz/utility/misc/StringTest.cpp:69] Assertion failed:
        expected "1.7976931348623157e+308" but got "inf" (reloaded)

Both red legs (GitHub `Build with latest g++ on ubuntu-latest`, and `teamcity - Core Linux x86_64`
at 271 passed / 1 new failure) are this same assertion; Bumbershoot Linux was only cancelled
downstream. **No compile errors** - gcc 13 built `StringTest.o` fine.

`toRoundTripString` validated each candidate with `parseClassic`, i.e. `istringstream >> double`.
**C++11 requires an out-of-range extraction to set `failbit` AND store the largest representable
value**, so `"1.79769313486232e+308"` - the 15-significant-digit form of `DBL_MAX`, about 21 ULP
*above* it - reads back as exactly `DBL_MAX` and compares equal. The loop returned at 15 digits and
never tried 17. A consumer reading that text with `strtod`, as the test does, gets `inf`.

The chain is forced by the failure message alone, no platform guessing: the karma 12-digit output
(`1.797693134862e+308`) reloads finite-but-unequal, so the fallback ran; of its three candidates
only the 15- and 16-digit forms `strtod` to `inf`; therefore `parseClassic` returned exactly
`DBL_MAX` for a decimal that exceeds it, which is only possible by clamping.

**Why it passed on Windows**: MSVC's `num_get` does not store the clamped value, so the loop there
correctly advanced to 17 digits. Windows was never wrong, which is why local `StringTest.passed`
and the Linux red are both true.

**This was a production defect, not just a test bug**: on glibc, `toString(DBL_MAX)` wrote text that
reloads as `inf` - the exact property the change exists to guarantee.

**Fix** (commit `27e91d2bc9`): `parseClassic` -> `reloadsExactly(text, value)`, returning
`!iss.fail() && reloaded == value`. The `failbit` test is not redundant with the equality test, and
the comment says so. Correct under both implementations: MSVC stores `inf` (unequal), libstdc++
clamps but sets `failbit`. **The behavior that caused the bug is what guarantees the fix detects
it** - the standard sets `failbit` in the same clause that mandates the clamping.

**Verified without a Linux box** (no WSL on this machine) by emulating libstdc++'s clamping
semantics in a probe (`ai/.tmp/dblmax-probe/`), running both predicates against it:

| value | old predicate | new predicate |
|---|---|---|
| `DBL_MAX` | `1.79769313486232e+308` -> **inf** | `1.7976931348623157e+308` -> exact |
| `-DBL_MAX` | `-1.79769313486232e+308` -> **inf** | `-1.7976931348623157e+308` -> exact |
| `DBL_MIN`, the Thermo RTs, `0.10000000000000002`, `1e9` | exact | **identical text** |

The new text is character-for-character what the CI assertion said it expected, and no in-range
value's text moves - so the "byte-identical output wherever today's output round-trips" promise
survives the fix.

**Gate**: `quickbuild.bat pwiz/utility/misc pwiz/data/msdata` -> 1303 targets, `StringTest` passes,
one failure: `ReaderTest.cpp:270` (Bruker FID/U2/YEP under `--without-compassxtract`), the
documented pre-existing failure already controlled against master. Windows `toString(DBL_MAX)` text
is unchanged by the fix, and `testFastPathTextUnchanged` still pins the 12-digit fast path.

**Lesson worth keeping**: the test caught this only because its oracle is `strtod` - a reader
*independent* of the one production validates with. An `istringstream`-based oracle would have
agreed with the defect and gone green. Same trap as `TestMzmlReaderRetentionTimePrecision` earlier
in this sprint, one layer down.

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
