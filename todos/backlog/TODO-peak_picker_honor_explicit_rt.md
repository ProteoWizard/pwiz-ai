# Peak picker should honor ExplicitRetentionTime over peak intensity

## Branch Information
- **Branch**: TBD
- **Base**: `master`
- **Status**: Backlog
- **GitHub Issue**: (pending)
- **Support thread**: https://skyline.ms/home/support/announcements-thread.view?rowId=66356 (Wesley)
- **Related (merged)**: Skyline/work/20260511_shared_q1_compound_collapse —
  fixes the binding side so same-Q1 compounds each get a chromatogram. This
  TODO covers the *downstream* picker behavior surfaced by that work.

## Problem

When a small-molecule target has an `ExplicitRetentionTime` set, Skyline's
peak picker still prefers the highest-intensity peak in the chromatogram
even when smaller peaks sit closer to the explicit RT. Visible in
Wesley's `Labsolutions_PackA_MA_alt` dataset: Cortexolone_MO has
explicit RT 7.0; the dominant peak is at ~6.7 (which belongs to the
co-eluting Corticosterone_MO at explicit RT 6.8). The picker chooses
the 6.7 peak for both compounds. Reproduces on master in a stripped-
down `tiny.sky` with no Q1 collision at all — confirming this is a
pre-existing picker issue, not a side-effect of the binding fix.

## Why it matters

In SRM methods where two compounds share Q1 (or Q1+Q3) and rely on
distinct retention times to be told apart, the binding fix delivers
data to both compounds but the picker collapses them onto a single
peak. From the user's perspective the "missing compound" reappears but
its peak integration is wrong.

## Reproducer

- `Labsolutions_PackA_MA_alt.mzML` + Wesley's full document. Cortexolone_MO
  picks the wrong peak.
- Minimal reproducer (verified by Brian on 2026-05-11): a single-
  compound `.sky` with Cortexolone_MO at Q1=376.248, explicit RT=7.0;
  importing the alt file picks the 6.7 peak even though the explicit
  RT is not inside the displayed peak boundary.

## Out of scope

- Same-Q1 chromatogram binding — handled by the related branch above.

## Tasks

- [ ] Locate the small-molecule SRM peak-picking entry point and confirm
      whether `ExplicitRetentionTime` is consulted at all.
- [ ] Decide on a policy: prefer the peak whose apex/boundary is closest
      to the explicit RT (subject to a sanity minimum-area floor), or
      fall back to dominant peak only if no peak exists in the window.
- [ ] Re-enable the boundary assertion in `ShimadzuSrmDuplicateQ1Test`
      (currently commented as a known-issue reference to this TODO).
- [ ] Sweep TestPerf SRM tests for area/RT regressions from the new
      policy.
