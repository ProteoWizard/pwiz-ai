# TODO-20260423_deduce_im_units.md

## Branch Information
- **Branch**: `Skyline/work/20260423_deduce_im_units`
- **Base**: `master`
- **Created**: 2026-04-23
- **Status**: Awaiting merge (all tasks complete, PR #4162 green)
- **GitHub Issue**: (none - reported via email from Nick Shulman)
- **PR**: [#4162](https://github.com/ProteoWizard/pwiz/pull/4162)
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

**Grid setter** at `Precursor.ExplicitIonMobility` silently applies a
deduced unit along with the value when the document unambiguously implies
a single one. When deduction is empty or ambiguous, accepts the value with
units=none rather than blocking the edit - the user may be setting the
Units column next, or may not have it visible in their current grid view
at all (it is configurable separately from the IM value column). Transient
invalid state is allowed; the safety net at consumption time catches any
unresolved state with a clear error.

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
- [x] Wire deducer into `Precursor.ExplicitIonMobility` setter (silent deduce when unambiguous; accept value-before-units entry otherwise)
- [x] Add safety net in `SrmSettings.GetIonMobilityFilter` with deduction + export-target fallback + friendly error
- [x] Wire Bruker timsTOF exporter to pass `inverse_K0_Vsec_per_cm2` as export target fallback
- [x] Unit test `TestIonMobilityUnitsDeduction` covering empty/single/conflict/none-filtered scenarios
- [x] Resource strings localized in DocSettingsResources and EntitiesResources
- [x] Decide whether to wire other exporters (Waters, Agilent, FAIMS) with their native units — N/A: `BrukerTimsTofIsolationListExporter` is the only exporter that calls `GetIonMobilityFilter`. Waters writes hardcoded DT placeholders, Agilent emits no IM column, Thermo FAIMS uses the separate `GetCompensationVoltage` pipeline.
- [x] Decide whether to add legacy-doc auto-repair on load (`DocumentReader`) or leave safety net as sufficient — Leave safety net as sufficient. Repair would need a post-construction pass (deducer needs full settings + sibling groups), would silently mutate documents on open, and can't resolve ambiguous-units cases anyway. Going forward the grid setter prevents the bad state; legacy docs hit the safety net only at consumption time, where a peptide-named localized error is most actionable.
- [x] Create PR
- [x] Regression test reproducing exception 74341 (verified: fails on pre-fix code with the same InvalidOperationException, passes on post-fix)

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

### 2026-05-05 - Manual test surfaced dialog auto-populate bug

Brian's manual test: empty doc in small molecule mode, add three molecules with
explicit IM. The third molecule's IM units silently auto-populated to the
*first-seen* unit even when the document already contained two molecules with
*different* IM units (ambiguous state). Same class of bug the deducer was built
to prevent - the grid setter was already correct (`Precursor.cs:355`) but
`EditCustomMoleculeDlg.PopulateIonMobilityUnits()` predated the deducer and
still used a `FirstOrDefault` walk + `GetFirstSeenIonMobilityUnits()` fallback.

Replaced both lookups with `TransitionIonMobilityFiltering.GetDocumentIonMobilityUnits(doc)`
+ count==1 check. Behavior:

- Empty document → units stay none, OK click flags it (existing safety net).
- One existing unit → auto-populate (unchanged UX).
- Two or more conflicting units → units stay none, user must pick.

Added `TestDocumentIonMobilityUnitsDeduction` covering empty/single/conflict/
none-filtered cases for the document-level deducer. All IM tests green
(including 29s functional `TestIonMobility`).

### 2026-05-05 - Open decisions resolved

Reviewed the two remaining scope decisions:

- **Other exporters**: Surveyed `Export.cs`. `BrukerTimsTofIsolationListExporter`
  is the only exporter that calls `GetIonMobilityFilter`. Waters writes
  hardcoded DT placeholders, Agilent emits no IM column, Thermo FAIMS uses
  the separate `GetCompensationVoltage` pipeline. No work needed.
- **Legacy-doc auto-repair on load**: Declined. Repair needs full settings
  scope (post-construction pass), silently mutates documents on open, and
  can't resolve ambiguity. Safety net at consumption time produces a
  peptide-named localized error precisely when it's most actionable.

All TODO tasks are now complete. Branch awaits merge.

### 2026-04-23 - Initial implementation

Worked through the email thread with Brian. Key design decisions:

- **Root cause is at the grid setter**, not just a downstream crash. The
  setter helps invisibly when it can (unambiguous deduction) but does not
  block the user when it can't - downstream guard is the enforcement point.
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
- **Grid setter initially rejected the edit on ambiguity**, but Brian pointed
  out this was hostile UX: users naturally enter value-then-units, and the
  Document Grid can be configured to show the IM value column without the
  Units column. Relaxed to silent deduce + accept - safety net handles the
  unresolved case at consumption time.

Build green, regression test verified to fail on pre-fix code (same
`InvalidOperationException` as exception 74341) and pass on post-fix.
