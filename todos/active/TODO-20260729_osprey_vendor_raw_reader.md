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

- **Test name**: (filled in once written)
- **Test project**: Osprey.Test, net472 leg only
- **Fixture**: `pwiz/data/vendor_readers/Thermo/Reader_Thermo_Test.data/source_cid_test_3scans.raw`
  paired with the committed `source_cid_test_3scans-centroid.mzML` — **already tracked, nothing new
  to commit** (see the fixture survey above)
- **Fails on master**: (pending)
- **Passes on fix**: (pending)

Shape: read the `.raw` through the new reader (`requireVendorCentroidedMS1/MS2: true`,
`simAsSpectra: true` — the `convert-one.cmd` mapping) and the `-centroid.mzML` through
`MzmlReader`, then assert the `SpectraCache` v4 fields agree per spectrum: scan number, RT,
precursor m/z, isolation centre/lower/upper offsets, m/z + intensity arrays. That is the parity
acceptance criterion made permanent, and it is the **first** deliverable on the branch: write it,
watch it fail with no raw reader, then make it pass.

## Progress Log

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
