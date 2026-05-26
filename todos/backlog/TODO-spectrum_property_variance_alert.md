# Alert on chromatograms whose contributing scans have varying filterable properties

## Branch Information
- **Branch**: TBD
- **Base**: `master`
- **Status**: Backlog
- **GitHub Issue**: (pending)
- **Support thread**: https://skyline.ms/home/support/announcements-thread.view?rowId=74731 (Eva Pferschy, Sciex ZenoTOF MRM HR — serrated peaks from CE-cycling acquisition)
- **Depends on (merge)**: PR #4115 (Nick — spectrum filter parser, transition list column, editable grid column) — alert refers users to that feature as the remedy
- **Related**: [TODO-empty_chromatogram_filter_diagnostic.md](TODO-empty_chromatogram_filter_diagnostic.md) — inverse failure mode (filter set, excludes all)

## Problem

When a user imports data, Skyline extracts chromatograms from whatever
spectra match the precursor target — without flagging when those spectra
differ in properties the user could have filtered on (CE, polarity, CV,
dissociation method, isolation window, etc.). The result is a serrated/
spiky chromatogram that looks like a quality problem rather than a
mis-configured acquisition that needed a spectrum filter.

Eva's ZenoTOF MRM HR case is the canonical example: she set CE = -30 V
in her method but the data file has scans cycling through CE 20, 23, 25,
27, 30. Skyline silently extracted across all of them and gave her a
spiky chromatogram. The support thread took five round-trips to get to
"add a spectrum filter."

## Sketch

At the end of chromatogram extraction (import or re-import), if any
extracted chromatogram's contributing spectra varied in one or more
`SpectrumClassColumn` properties, show a single dismissable message box:

> "5 chromatograms were extracted from spectra with varying filterable
> properties. Use **Spectrum Filter** (right-click a precursor) to limit
> extraction to the intended values."

Optionally expandable to list the affected precursors and the property
values seen, so the user can confirm it's the case they expect.

Single message at end of extraction, not per-chromatogram. Dismissable
with "Don't show again for this document" (or stronger — per-session /
per-user, see open question).

## Why message-box rather than richer UX

Per developer decision (Brian, 2026-05-19): start with the simplest
surface that solves the discovery problem. A document grid column,
chromatogram graph badge, or one-click "apply this filter" action could
land as follow-up work if the message-box version proves insufficient.
Smaller scope, lower regression risk, lands sooner.

## Open questions

- **CES handling.** Sciex Collision Energy Spread varies CE intentionally
  per scan. With a naive heuristic this alert fires on every CES run,
  which would train users to dismiss it reflexively. Either (a) detect
  CES from the file metadata and suppress CE-only variance there, or
  (b) accept the false positive and rely on "Don't show again" — to be
  decided when implementing.
- **DIA / PASEF false positives.** Similar concern for isolation window
  (DIA) and IM range (PASEF). For typical schemes a single precursor's
  chromatogram extracts from one window / one IM band, so variance
  should be low — verify on representative data before deciding whether
  per-acquisition-mode suppression is needed.
- **Dismissability scope.** Per-document, per-session, or persistent
  user preference? Per-document is the safest default — a new document
  with a new acquisition deserves a fresh look.
- **Detection timing.** Cheapest place is during the extraction loop
  itself (each spectrum metadata already in hand). Confirm and tally
  per-precursor distinct-value sets as a side effect of extraction
  rather than re-walking metadata after.

## Tasks

- [ ] Identify extraction completion hook where end-of-import UI runs.
- [ ] Decide watched property set (start: all `SpectrumClassColumn`
      properties; trim if any prove noisy).
- [ ] Wire per-chromatogram distinct-value tally into the extraction
      loop (or a follow-up pass over cached metadata, whichever is
      cheaper).
- [ ] Implement message box at end of extraction with dismiss + (stretch)
      expandable details listing affected precursors and their distinct
      values.
- [ ] Resolve CES / DIA / PASEF false-positive question on representative
      data before shipping.
- [ ] Tests: a small document with CE-cycling scans must trigger the
      message; a clean fixed-CE document must not.

## Out of scope

- The spectrum filter editing UX itself (PR #4115).
- Document grid "variance" column.
- Chromatogram graph badge.
- One-click "apply this filter" action.
- Auto-populating filters from Explicit CE / IM / isolation values.
- The inverse failure mode (filter set, excludes all spectra) —
  separate TODO.
