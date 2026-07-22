# Add the M-1 precursor isotope to MS1 filtering

## Branch Information
- **Branch**: `Skyline/work/20260707_refine_add_m1_precursor`
- **Base**: `master`
- **Status**: Active (started 2026-07-07)
- **Checkout**: `C:\git\sky_mminusone`
- **PR**: [#4385](https://github.com/ProteoWizard/pwiz/pull/4385)
- **Origin**: Requested by Richard, who wants the M-1 precursor transition present on
  every precursor in the document so the peak below the monoisotopic peak can be
  inspected.

## Problem

MS1 full-scan filtering extracts the monoisotopic peak and N-1 peaks above it
(`Peaks:` on Settings > Transition Settings > Full-Scan). There is no way to also
extract the M-1 peak, even though `IsotopeDistInfo` already computes and retains it
(the constructor deliberately inserts an M-1 peak "even if it is not expected in the
isotope mass distribution").

## Scope

A document setting, not a one-shot refinement. The M-1 peak is part of what MS1
filtering extracts, so it belongs next to the isotope peak count on the Full-Scan tab
and must round-trip in the document.

## Design decisions
- **Setting, not refinement**: the first attempt added an "Add M-1 precursor transition"
  checkbox to the Refine dialog, which mutated the document once and turned off
  auto-manage on every precursor it touched. Replaced with a `TransitionFullScan`
  property so the choice persists, participates in auto-manage, and is undone by
  unchecking the box. That first approach was reverted in full.
- **Implemented in `SelectMassIndices`**: `TransitionGroup.GetPrecursorTransitions`
  needed no change - the `Count` branch yields mass index -1 first and the `Percent`
  branch lets -1 through regardless of abundance (the M-1 peak is normally below the
  minimum abundance, so a percentage filter would otherwise never include it).
- **High resolution only**: a QIT precursor mass analyzer supports a single isotope
  peak, so the setting is rejected by `DoValidate` and the checkbox is disabled and
  cleared for QIT, for EI (MS2-only), and when MS1 filtering is off.
- **No form resizing**: the checkbox fits in the existing gap between the Peaks textbox
  and the "Isotope labeling enrichment" label, so no containing form had to grow. The
  Import Peptide Search wizard's `groupBoxMS1` shrink was re-anchored to the checkbox.
- **New document format**: `VERSION_26_11` / `MINUS_ONE_PRECURSOR`, with a
  `RemoveUnsupportedFeatures` clause that clears the flag when saving to an older format.

## Completed
- Reverted the Refine dialog approach (RefineDlg, RefinementSettings, RefineMenu,
  EditUIResources, PropertyNames, RefineTest, RefineAddMinusOnePrecursorTest).
- `TransitionFullScan.IncludeMinusOnePrecursor`: property, constructor parameter,
  `ChangeIncludeMinusOnePrecursor`, `include_minus_one_precursor` XML attribute,
  Equals/GetHashCode, validation, audit log property name, `Skyline_Current.xsd`.
- `SelectMassIndices` yields mass index -1 when the setting is on and the isotope
  distribution has a peak below the monoisotopic peak.
- `SrmSettings.ComputeDiff` treats a change to the flag as `DiffTransitions` so the
  transitions appear and disappear immediately.
- `DocumentFormat.VERSION_26_11` plus the `RemoveUnsupportedFeatures` downgrade clause.
- "and M-1" checkbox on `FullScanSettingsControl`, with `IncludeMinusOnePrecursor` and
  `IsIncludeMinusOnePrecursorEnabled` exposed through `TransitionSettingsUI`.
- Tests: extended `FullScanPrecursorTest` and `SerializeTransitionFullScanTest`, added
  `MinusOnePrecursorTest` (TestFunctional).

## Remaining
- Tune the MS1 group box spacing (more room above "Peaks" / "Resolving power", more
  room below "and M-1").
- Consider a CLI argument for the setting (`CommandArgs` full-scan group) - not
  requested, deliberately out of scope so far.
- Update the PR description, which still describes the Refine dialog approach.

## Verification
Build clean. Passing: `FullScanPrecursorTransitionsTest`, `SerializeTransitionFullScanTest`,
`TestMinusOnePrecursor`, `CodeInspection`, `TestAuditLog`, `TestAuditLogLocalization`,
the settings/document serialization batch (25 tests), `TestImportPeptideSearch`,
`TestDdaSearch`, `TestFullScanFilterInteraction`.
