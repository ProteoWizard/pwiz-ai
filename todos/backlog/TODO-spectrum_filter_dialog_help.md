# Per-property help in the Edit Spectrum Filter dialog

## Branch Information
- **Branch**: TBD
- **Base**: `master`
- **Status**: Backlog
- **GitHub Issue**: (pending)
- **Related**: PR #4115 (Nick — spectrum filter feature) and the grid dialog-launch / parse-error work layered on top (Skyline/work/20251225_SpectrumFilterParser)

## Problem

In `EditSpectrumFilterDlg` the user picks a Property, an Operation, and a Value,
but the dialog gives no guidance on what each spectrum-filter property means or
what kind of value it accepts. Users (e.g. Eva's ZenoTOF case) have to guess
whether CollisionEnergy wants a number, a list, what the units are, etc.

## Sketch

Show contextual help for the selected property. Two parts with very different cost:

**1. "What values it accepts" — auto-derivable, no content authoring.**
Generate from each column's type / filter handler:
- numeric (CollisionEnergy, CompensationVoltage, SourceOffsetVoltage, ...) ->
  "a number, or a comma-separated list" (separator adapts to locale: comma in
  period-decimal locales, semicolon in comma-decimal locales)
- enum-like (Analyzer, DissociationMethod) -> list the actual allowed values
- text (ScanDescription) -> "text; use Contains for partial match"
- list-valued columns -> note that multiple values match any/all per semantics

**2. "What each filter is for" — prose, needs domain input.**
A one-line purpose per `SpectrumClassColumn` (~13: Ms1Precursors, Ms2Precursors,
ScanDescription, CollisionEnergy, ScanWindowWidth, CompensationVoltage,
PresetScanConfiguration, MsLevel, Analyzer, IsolationWindowWidth,
DissociationMethod, ConstantNeutralLoss, SourceOffsetVoltage). These become
resource strings (ja/zh handled by translators); the English content needs
Brian/Nick — several are vendor-specific.

## UI mechanism (landed design)

One static tooltip on the **Property column**, not dynamic per-selection help.
Build the tooltip text once from a name -> description table over
`SpectrumClassColumn.ALL`: each line `Caption - purpose (accepts: ...)`. Attach it
to the Property column header tooltip and the Property cells (via
`CellToolTipTextNeeded`) so it shows wherever the user's mouse lands. The "accepts"
half is auto-derived from each column's value type / filter handler, so authors
write only the purpose sentence. Co-locating the table with the column definitions
keeps it in sync with what is actually filterable.

## Enforcement (the key part)

Give each `SpectrumClassColumn` a `Description` (localized resource), and add a unit
test that iterates `SpectrumClassColumn.ALL` asserting every column has a non-empty
description. A developer who adds a new spectrum-class column then cannot ship it
without a description -- the test goes red. "Trust comes from verifiers": the test,
not reviewer diligence, keeps the help complete and prevents drift.

## Suggested staging

- Phase 1: auto-derived "accepts" + the Property-column tooltip wiring + the
  enforcement test (immediately useful, zero prose burden), with stubbed purpose text.
- Phase 2: fill in the per-property purpose prose (domain input; several are
  vendor-specific). The enforcement test guarantees none are forgotten but cannot
  write the content.

## Out of scope

- The grid dialog-launch editing, parse-error UX, locale fallback, and tooltip
  formatting (already implemented on the SpectrumFilterParser branch).
