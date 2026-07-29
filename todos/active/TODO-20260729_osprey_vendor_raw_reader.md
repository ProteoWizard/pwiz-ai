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
- **Test project**: Osprey.Test (net472-conditional) — TBD
- **Fails on master**: (pending)
- **Passes on fix**: (pending)

Planned shape: a net472-only test that reads a small vendor `.raw` and its msconvert-produced mzML
through both readers and asserts the `SpectraCache` v4 fields agree (scan number, RT, precursor m/z,
isolation centre/lower/upper offsets, m/z + intensity arrays). That test is the parity acceptance
criterion made permanent, and it is the natural **first** deliverable on the branch: write it, watch
it fail with no raw reader, then make it pass.

Open question to settle early: whether a small enough vendor raw file is available to the test
suite, or whether the parity check has to stay a manual/perf-tier verification. Record the answer
here either way rather than silently omitting the test.

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
