# TODO-20260513_maxquant_blank_invk0.md

## Branch Information
- **Branch**: `Skyline/work/20260513_maxquant_blank_invk0`
- **Base**: `master`
- **Created**: 2026-05-13
- **Completed**: 2026-05-14
- **Status**: Merged
- **Source Thread**: [skyline.ms support #74557](https://skyline.ms/home/support/announcements-thread.view?rowId=74557)
- **PR**: [#4207](https://github.com/ProteoWizard/pwiz/pull/4207) (merged 2026-05-14)

## Objective

Stop BiblioSpec from throwing on blank `1/K0` cells in MaxQuant `evidence.txt` when
importing TIMS-DDA search results. Per Nick's response in the support thread: "safely
ignore blank values in that column."

## Reporter

Ani — 2026-05-12 (MaxQuant 2.7 TIMS-DDA SILAC import into Skyline Daily).
Workaround offered in thread was deleting evidence.txt; this fix removes the need for that.

## Fix

`pwiz_tools/BiblioSpec/src/MaxQuantReader.cpp` `initEvidence()`:

* Treat blank (or whitespace-only) `1/K0` cells as `0.0` instead of letting
  `boost::lexical_cast<double>` throw.
* Bounds-check `columns[colInvK0]` for malformed (short) rows.
* Row alignment preserved — `inverseK0_` is indexed by `evidenceID`; the downstream
  consumer at line 760 already treats `ionMobility == 0` as "no IM" (no
  `ionMobilityType` set), so blank rows correctly produce a PSM with no IM annotation.

## Cherry-pick

Bug exists verbatim on `Skyline/skyline_26_1`. PR #4207 was initially labeled
`Cherry pick to release`, but the team decided **not** to cherry-pick (2026-05-14).
Label removed; fix ships in master only.

## Test plan

- [x] Manual verification with the reporter's evidence.txt — bspratt 2026-05-13.
- [ ] Possible follow-up: minimal regression fixture under `pwiz_tools/BiblioSpec/tests/`
      (deferred — not part of this PR).
