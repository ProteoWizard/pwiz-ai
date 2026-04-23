# TODO-20260423_deduce_im_units.md

## Branch Information
- **Branch**: `Skyline/work/20260423_deduce_im_units`
- **Base**: `master`
- **Created**: 2026-04-23
- **Status**: In Progress
- **GitHub Issue**: (none - reported via email from Nick Shulman)
- **PR**: (pending)
- **Exception ID**: 74341 (skyline.ms/home/issues/exceptions, reported by Todd M. Greco 2026-04-20)

## Objective

Fix `InvalidOperationException: Nullable object must have a value` in
`SrmSettings.GetIonMobilityFilter` when a peptide has an `ExplicitIonMobility`
value set but `ExplicitIonMobilityUnits` is still `none`. The crash is reached
through `BrukerTimsTofIsolationListExporter` during method export, but the
invalid state originates at the Document Grid `Precursor.ExplicitIonMobility`
setter, which writes the new value through with whatever units happen to be
set - including `none`. Rather than only guarding the downstream crash,
prevent the invalid state at the source and auto-repair it where possible
from existing document information.

## Approach

**Deducer** at `TransitionIonMobilityFiltering.GetSettingsIonMobilityUnits`
(settings-only: results, IM library, spectral libraries keyed on a given
LibKey set) and `GetDocumentIonMobilityUnits` (adds sibling transition
groups). Returns the set of distinct non-none units implied by the document.
Zero = unknown, one = deduced, more than one = ambiguous (do not silently
pick - FAIMS and TIMS must never be confused).

**Grid setter** at `Precursor.ExplicitIonMobility` now deduces units at set
time when the current units are `none`, applies value and units atomically,
and rejects the cell edit with a friendly `InvalidDataException` when
deduction yields zero or multiple candidates.

**Safety net** at `SrmSettings.GetIonMobilityFilter` attempts the same
deduction for legacy documents already in the bad state. A new optional
`exportTargetUnits` parameter lets the exporter supply its instrument-native
unit as a last-resort fallback when document evidence is empty; Bruker
timsTOF passes `inverse_K0_Vsec_per_cm2`. Deduction evidence takes precedence
over the export target - substituting would silently convert stored values
to the wrong semantics.

## Tasks

- [x] Build deducer helper (`GetSettingsIonMobilityUnits`, `GetDocumentIonMobilityUnits`)
- [x] Add `PeptideLibraries.GetDistinctIonMobilityUnits(LibKey[])` helper
- [x] Wire deducer into `Precursor.ExplicitIonMobility` setter (deduce + atomic set; reject on ambiguity)
- [x] Add safety net in `SrmSettings.GetIonMobilityFilter` with deduction + export-target fallback + friendly error
- [x] Wire Bruker timsTOF exporter to pass `inverse_K0_Vsec_per_cm2` as export target fallback
- [x] Unit test `TestIonMobilityUnitsDeduction` covering empty/single/conflict/none-filtered scenarios
- [x] Resource strings localized in DocSettingsResources and EntitiesResources
- [ ] Decide whether to wire other exporters (Waters, Agilent, FAIMS) with their native units
- [ ] Decide whether to add legacy-doc auto-repair on load (`DocumentReader`) or leave safety net as sufficient
- [ ] Create PR

## Files Modified

- `pwiz_tools/Skyline/Model/DocSettings/TransitionIonMobilityFiltering.cs` - deducer methods
- `pwiz_tools/Skyline/Model/DocSettings/PeptideSettings.cs` - `GetDistinctIonMobilityUnits`
- `pwiz_tools/Skyline/Model/DocSettings/SrmSettings.cs` - safety net + export-target fallback
- `pwiz_tools/Skyline/Model/Databinding/Entities/Precursor.cs` - grid setter deduction
- `pwiz_tools/Skyline/Model/Export.cs` - Bruker exporter passes native unit
- `pwiz_tools/Skyline/Test/IonMobilityUnitTest.cs` - `TestIonMobilityUnitsDeduction`
- `pwiz_tools/Skyline/Model/DocSettings/DocSettingsResources.resx`/`.designer.cs` - strings
- `pwiz_tools/Skyline/Model/Databinding/Entities/EntitiesResources.resx`/`.designer.cs` - strings

## Progress Log

### 2026-04-23 - Initial implementation

Worked through the email thread with Brian. Key design decisions:

- **Root cause is at the grid setter**, not just a downstream crash. The
  proper fix is to prevent the invalid state from being written. Downstream
  guard remains as a safety net for legacy documents.
- **Ambiguity must never silently resolve** - FAIMS (compensation_V) vs TIMS
  (inverse_K0) vs drift_time_msec are semantically incompatible. Mixed-unit
  documents are legitimate; guessing would silently mis-export.
- **Export target is a valuable last-resort signal** but does not override
  document evidence. Using the target when document sources agree on a
  different unit would convert stored values to wrong semantics without the
  user noticing.
- **Spectral library support** added (`GetDistinctIonMobilityUnits` on
  `PeptideLibraries`) so pre-import users with library-based targets get
  deduction coverage too.

Build green, unit test passes, all existing IM tests still pass.
