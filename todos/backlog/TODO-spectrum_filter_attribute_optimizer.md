# Scan loaded data to find the spectrum-filter attribute value that yields the best chromatogram

## Branch Information
- **Branch**: TBD
- **Base**: `master`
- **Status**: Backlog
- **GitHub Issue**: (pending)
- **Support thread**: https://skyline.ms/home/support/announcements-thread.view?rowId=74731 (Eva Pferschy, Sciex ZenoTOF MRM HR)
- **Precedent**: the existing ion-mobility "measure from results" feature (EditIonMobilityLibraryDlg / measured drift times), which scans loaded data to find the IM value that gives the best chromatogram
- **Related**: [[spectrum_property_variance_alert]] (detecting which attributes vary), [[spectrum_filter_dialog_help]], PR #4115 (spectrum filter feature)

## Idea

For ion mobility, Skyline can already search through loaded data and determine
which observed IM value yields the best chromatogram, then use it. Generalize
that to the other attributes available to Spectrum Filters (CollisionEnergy,
DissociationMethod, CompensationVoltage, isolation window, ScanDescription, ...):
scan the observed values of a chosen attribute, extract a chromatogram for each,
and report/apply the value that gives the best chromatogram.

This is the auto-optimize complement to the discoverability alert: instead of
just telling the user "this chromatogram mixes CE 20/23/25/27/30," it would find
that CE=25 gives the cleanest peak and offer to apply it as a spectrum filter --
directly solving Eva's "which CE do I want?" problem.

## UX sketch

- The user picks the attribute they're interested in. A quick scan of the loaded
  data can offer a short list of the attributes that actually vary (reuse the
  variance scan from [[spectrum_property_variance_alert]]), so the user chooses
  from "CollisionEnergy, DissociationMethod" rather than the full column list.
- For the chosen attribute, enumerate its distinct observed values, extract a
  chromatogram per value, score them, and present the ranked results.
- Offer to apply the winning value as a Spectrum Filter on the precursor(s)
  (reusing the dialog / SetSpectrumClassFilter path from the grid work).

## Open questions

- **"Best chromatogram" metric**: peak area, signal-to-noise, coelution with the
  other transitions of the precursor, mass/IM error, peak shape? IM optimization
  already has a notion of this -- see what it uses and whether it transfers.
- **Scope**: per-precursor vs document-wide; one attribute at a time vs combinations.
- **Cost**: extracting a chromatogram per distinct value per precursor could be
  expensive; reuse cached spectrum metadata where possible, and bound the value
  count (the variance scan already yields a short list).
- **Discrete vs continuous**: CE/CV are discrete sets in the data (good); isolation
  window / IM are more continuous (the IM feature already handles that case).

## Out of scope

- The spectrum filter editing UX and parser (PR #4115).
- The passive variance alert ([[spectrum_property_variance_alert]]) -- this TODO
  is the active "find the best value" follow-on that builds on it.
