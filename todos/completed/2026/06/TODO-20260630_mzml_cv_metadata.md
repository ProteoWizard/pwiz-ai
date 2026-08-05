# TODO-20260630_mzml_cv_metadata.md

## Branch Information
- **Branch**: `Skyline/work/20260630_mzml_cv_metadata` (deleted, local + remote)
- **Base**: `master`
- **Created**: 2026-06-30
- **Status**: Completed
- **GitHub Issue**: (none)
- **PR**: [#4349](https://github.com/ProteoWizard/pwiz/pull/4349) (merged 2026-07-14 as `cdea33f0b`)

Phase 2 (filtering on these terms) continues in
`ai/todos/active/TODO-20260701_mzml_cv_filtering.md`, branch
`Skyline/work/20260701_mzml_cv_filtering` (checkout `C:\Dev\SmartCV`).

## Objective

Surface the mzML controlled-vocabulary (CV) and user parameters that Skyline reads
through the ProteoWizard API but does not interpret into its own typed fields, so users
can see them in the full-scan viewer's Spectrum Properties pane. (Filtering on them is
Phase 2, tracked separately.)

## Context

`MsDataFileImpl.GetSpectrumMetadata` hand-maps ~20 known CVIDs into typed fields; every
other cvParam/userParam was dropped. Examples lost: base-peak m/z (MS:1000504), base-peak
intensity (MS:1000505), lowest/highest observed m/z, Thermo filter string (MS:1000512),
vendor userParams. Full design and decisions in the plan file
`~/.claude/plans/when-skyline-reads-mass-validated-milner.md`.

## What shipped

- `CommonUtil/Spectra/SpectrumMetadataTerm.cs` (new) - immutable
  {Accession, Name, Value, Unit, UnitAccession, Definition}.
- `CommonUtil/Spectra/SpectrumMetadata.cs` - `OtherParams` ImmutableList, excluded from
  Equals/GetHashCode (spectrum identity stays the interpreted fields).
- `ProteowizardWrapper/MsDataFileImpl.cs` - captures uninterpreted spectrum/scan/scan-window
  cvParams + userParams, skip-set of interpreted CVIDs; gated on the `CaptureOtherParams`
  flag so only the viewer pays for it. Native CVParam/UserParam/Scan/ScanWindow wrappers are
  disposed rather than left to the finalizer.
- `Skyline/Model/Results/ScanProvider.cs` - applies `CaptureOtherParams` to the display reader
  on **every** `GetDataFile`, not just when opening the file (a flag set after open, or an
  adopted reader, would otherwise silently collect nothing).
- `Skyline/Model/OtherMetadataInfo.cs` (new) - ICustomTypeDescriptor; the expandable
  **"Other Metadata"** node under the Acquisition category.
- `Skyline/Model/FullScanProperties.cs` + `FullScanPropertiesRes` - the OtherMetadata property.
- Each term carries its CV definition (`CVTermInfo.def`) as PropertyGrid help text; the node
  has its own help text; value-less flag terms show a blank value. Expandable nodes stay
  expanded when stepping between scans (`MsGraphExtension.SetSelectedObjectPreservingExpansion`).
- **Unit formatting**: values whose unit Skyline has a display convention for are shown in that
  convention (m/z, mass, minutes, drift time, 1/K0, CCS, intensities, ppm, voltages - 16 of the
  40 units psi-ms can attach), keyed on the unit's **CV accession**, not its English label.
  Anything else is shown exactly as the file wrote it - as is any value the convention would
  round away to zero (intensities display as whole counts, so a relative intensity of 0.4213
  would otherwise read "0"), any non-numeric value, and the percent/fraction family (
  `Formats.Percent` scales by 100) and the second (Skyline's time convention is minutes).
- Test: `FullScanPropertiesTest` - terms surface, interpreted terms are not duplicated, CV
  definitions become grid help text, the node stays expanded across `ChangeScan(1)`, and
  `VerifyUnitFormatting` covers the formatting rules with hand-built terms (the cases that
  matter cannot all be produced from the test data file). Passes en-US and fr-FR.

**Why a nested node, not bare rows under a top-level category:** WinForms `PropertyGrid` throws
an NRE in `RestoreHierarchyState`/`GridEntry.NonParentEquals` when custom `PropertyDescriptor`s
form a *dynamic top-level category*. The nested-expandable-object pattern (same as the existing
Instrument node) is robust. `OtherMetadataInfo` is that node.

## Progress Log

### 2026-07-14 - Merged

PR #4349 merged as `cdea33f0b`. Shipped the capture + display of uninterpreted mzML CV/user
parameters in the full-scan viewer. Late in review the node was renamed from "Raw Metadata" to
**"Other Metadata"** and values gained Skyline's per-unit display conventions (keyed on unit CV
accession), with a fallback to the file's own text wherever a convention would misrepresent the
value. The fresh-context self-review caught three real defects, all fixed before merge: the
round-to-zero intensity problem, `CaptureOtherParams` only being applied on the file-open path,
and undisposed native param wrappers. Copilot caught a resx pair-ordering slip and an
overstated doc comment. Phase 2 (filtering) carries on in TODO-20260701_mzml_cv_filtering.md.
