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

## Tasks

- [ ] **Decide the net8 reader seam** (blocks everything else). Options:
      (a) `Osprey.IO` references pwiz-sharp's `MsData` + `Vendor` projects directly and
          `VendorRawReader` is rewritten against pwiz-sharp's own API;
      (b) `ProteowizardWrapper` grows a plain `net8.0` target alongside `net8.0-windows`;
      (c) a small shared non-WinForms adapter.
      Criterion: Linux/WSL must work, and the change to Matt's in-flight branch must stay
      as small as possible.
- [ ] Drop `net472` from `pwiz_tools/Osprey/Directory.Build.props`; remove the
      net472-conditional package references and the `OspreyVendorReaderEnabled` net472 gate
      in `Osprey.IO.csproj`
- [ ] Collapse `SpectrumFileReader` to a single pwiz-backed path (no `OSPREY_VENDOR_READER`
      conditional, no `OSPREY_MZML_VIA_MZMLREADER` escape hatch once there is no second
      reader to compare against)
- [ ] Delete `Osprey.IO/MzmlReader.cs` and the parallel-decode plumbing built around it
      (`Osprey.Core/ProgressStream.cs`, the sequential-`XmlReader`-producer notes in
      `ScoringTaskShared.cs`) - verify each is genuinely reader-only before removing
- [ ] Delete or retarget the tests that pin `MzmlReader` behaviour (incl. the raw-vs-mzML
      parity test added by #4502, whose second reader disappears here)
- [ ] Update `pwiz_tools/Osprey/Jamfile.jam` / build scripts for a single TFM
- [ ] `--task PerFileScoring` takes vendor raw AND mzML on net8.0
- [ ] `regression.ps1 -Dataset All` green; characterize any divergence, do not rebaseline
- [ ] Verify a run on Linux/WSL with no Wine container

## Regression Test

- **Test name**: (filled in once written)
- **Test project**: Osprey.Test (+ the Perf/Regression config for the dataset run)
- **Fails on master**: n/a - this is a removal/port, not a bug fix; the verifier is that
  the existing suite plus `regression.ps1 -Dataset All` stay green through the reader swap
- **Passes on fix**: (pending)

Note on shape: the usual red-then-green regression test does not apply to a deletion. The
protection here is the golden datasets - `regression.ps1 -Dataset All` is the test that the
removed reader and pwiz-sharp agree. Any divergence is characterized as a defect in the
deleted reader, never rebaselined. If a targeted unit test can pin the reader swap more
cheaply (e.g. spectra-cache byte parity for one small mzML read through pwiz-sharp vs a
checked-in expected cache), add it and record it here.

## Progress Log

### 2026-08-17 - Session Start

Starting work on this issue.

* Branched `Skyline/work/20260817_osprey_net8_pwiz_sharp` off `origin/chambem2/pwiz-sharp`
  (`5ef89bd228`) rather than master - stacked PR per #4311.
* Surveyed the base and recorded the findings above. The `net8.0` vs `net8.0-windows` TFM
  mismatch between Osprey and `ProteowizardWrapper` is the first thing to resolve; it
  decides whether Osprey talks to pwiz-sharp through the wrapper or directly.
