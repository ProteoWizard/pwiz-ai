# Inform the user when a spectrum filter excludes all candidate spectra

## Branch Information
- **Branch**: TBD
- **Base**: `master`
- **Status**: Backlog
- **GitHub Issue**: (pending)
- **Support thread**: https://skyline.ms/home/support/announcements-thread.view?rowId=74731 (Eva Pferschy, Sciex ZenoTOF MRM HR)
- **Depends on (merge)**: PR #4115 (Nick — spectrum filter parser, transition list column, editable grid column)

## Problem

When a `SpectrumClassFilter` is configured such that no candidate spectrum
matches (wrong sign on CE for negative-mode data, wrong unit, value not
present in this run, typo), the resulting chromatogram is empty. Today
this looks indistinguishable from corrupted data or a method/document
mismatch — the user gets a blank graph with no hint that a filter they
set is the cause.

This is the worst-case failure mode of the filter feature: silent, hard
to attribute, surfaces only after re-import (slow iteration loop).

## Why it matters

Spectrum Filter usability hinges on this. Bulk-editing CE filters via
the transition list column or the document grid (both delivered by PR
#4115) is only safe if users can trust that a typo gives an obvious
error rather than silently empty output. Without this diagnostic, every
support thread about "my chromatograms are blank" requires Brian/Nick
to ask the user to inspect spectrum properties and reason about whether
a filter applies.

## Sketch

Per-precursor, at extraction time (or at the chromatogram graph display
layer): when a precursor has a non-empty `SpectrumClassFilter` and its
extracted chromatogram contains zero points (or all-zero intensity),
surface an explanatory note on the chromatogram graph instead of a
blank pane. Ideal note:

- "Spectrum filter excluded all N candidate spectra in this run."
- Optionally: "Candidate values were: CE = 20, 23, 25, 27, 30"
  (i.e. distinct values for the properties referenced in the filter).

Coupling the "what's in the run" hint with the "your filter matched
nothing" message would have short-circuited the Eva thread.

## Tasks

- [ ] Identify the chromatogram-graph entry point that draws "no data"
      and confirm whether it can distinguish "filter excluded all" from
      "no candidate spectra existed at all".
- [ ] Decide where the candidate-value enumeration is cheapest: during
      extraction (free, but only when re-importing) vs. on-demand from
      the cached metadata file (works without re-import).
- [ ] Wire the message into the empty-chromatogram graph state.
- [ ] Tests: build a small document where a filter excludes all spectra
      and verify the message appears with the expected candidate values.

## Out of scope

- The filter editing UX itself (PR #4115).
- Auto-populating filters from Explicit CE / IM / isolation values.
- Vendor-specific defaults (Sciex ZenoTOF MRM-HR, etc.).
- Detection of "the chromatogram extracts from spectra with varying CE"
  *before* the user has set a filter (a separate, more ambitious
  discoverability heuristic — different surface).
