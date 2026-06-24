# Compounds with shared Q1 are collapsed during SRM import

## Branch Information
- **Branch**: `Skyline/work/20260511_shared_q1_compound_collapse`
- **Base**: `master`
- **Created**: 2026-05-11
- **Status**: Closed — superseded by Brendan's transition-aware fix (PR #4305, merged 2026-06-23)
- **GitHub Issue**: (pending)
- **Support thread**: https://skyline.ms/home/support/announcements-thread.view?rowId=66356 (Wesley)
- **PR**: https://github.com/ProteoWizard/pwiz/pull/4200 (CLOSED, not merged — superseded by #4305)
- **Related**: Same dataset as TODO-20260429_srm_times_intensities_mismatch (now merged
  as PR #4174, commit 3315ee92b). That fix addressed the points-count crash;
  this TODO covers the *second* issue Wesley reported on the same thread.

## Objective

When a Skyline document contains two or more compounds that share the same
precursor Q1 m/z, importing SRM results causes Skyline to display only one of
the compounds — even though all transitions, adducts, CEs, and retention times
are correctly distinct in the document. Wesley reports this on Shimadzu
LabSolutions data exported in the "grouped" format
(`DHEA_MO&Test_MO 318.2 110.2`), but the root cause is suspected to be in
Skyline's chromatogram-to-target mapping rather than vendor-specific.

## Scope (both scenarios in scope)

1. **Identical (Q1, Q3) across compounds** — e.g. two molecules at Q1=318.2
   with a shared product 110.2. The grouped CSV writes a single chromatogram
   per (Q1, Q3) under a combined header (`A&B 318.2 110.2`); both compounds
   should be populated from that chromatogram.
2. **Shared Q1, partially overlapping Q3 sets** — e.g. Wesley's
   `Labsolutions_PackA_MA_alt.mzML` at Q1=331.25 (DOC and 17α-OH-P with
   overlapping but non-identical Q3 sets). After the points-count fix,
   import succeeds, but display still collapses to one compound.

## Reproducer

- Files (existing): `D:\data\Wesley\Labsolutions_PackA_MA_alt.{lcd,mzML}` plus
  `Wesley.sky` (steroid-hormone panel, Q1=331.25 collisions).
- Wesley's symptom on 2026-05-10: "Skyline is still only showing one compound,
  not two (or three or four,…) if they have the same Q1 mass."
- Workaround that he reported earlier: Copy/Paste/rename keeps both visible,
  but re-import collapses again — meaning the collapse happens at *import*
  (chromatogram-to-target binding), not at display.

## Investigation plan (before deciding fix shape)

1. Wesley says "Since recently" — treat as suspected regression. Use
   `git log -S` / `--follow` on the chromatogram-to-target mapping code paths
   (ChromCacheBuilder, ChromatogramSet, PeptideFinder, transition-group match)
   to find any recent change that could have started collapsing duplicates.
2. Confirm reproduction in current master on the existing dataset. Identify
   which specific stage discards the second compound (chromatogram cache
   build, document update after import, or display layer).
3. Decide whether to fix at the binding stage (preserve both targets) or at
   the import stage (clone chromatogram references). Defer the decision until
   investigation pins down the offending code.

## Tasks

- [x] Reproduce on `Labsolutions_PackA_MA_alt.mzML` + `Wesley.sky` against
      current master (post times/intensities fix). Confirmed via an extra
      assertion appended to `ShimadzuSrmDuplicateQ1ImportTest` that walks
      `MoleculeTransitionGroups`, groups by `PrecursorMz`, finds the
      same-Q1 pairs, and asserts both have non-empty results. Fails with:
      *"Assert.IsFalse failed. Precursor at Q1 331.22677094 has empty
      results after import"*. One of the two compounds at 331.227 gets
      `HasResults == true` but `Results[0].IsEmpty == true` — i.e. a
      placeholder TransitionGroupChromInfo entry but no ChromInfo
      attached. The other side imports normally. Confirms the collapse
      is at the binding layer, not at document construction.
- [x] Bisect / `git log -S` on suspected mapping code — no recent changes
      to `PeptideFinder.cs`, `ChromCacheBuilder.cs`, or `ChromatogramSet.cs`
      since 2025. Wesley's "since recently" likely reflects when he started
      hitting same-Q1 datasets, not a fresh regression. Bug appears
      long-standing in the single-target SRM binding path.
- [x] Pin down whether the collapse happens during import binding or document
      mutation. Confirmed: binding in
      `SpectraChromDataProvider.ExtractChromatogramsLocked` collapses same-Q1
      spectra onto one `filterIndex` → one `ChromDataCollector` →
      first-found peptide wins; losing peptide gets placeholder
      TransitionGroupChromInfo with empty ChromInfoList.
- [x] Decide fix shape. Two-part fix:
      (1) Add `PeptideFinder.FindPeptides(SignedMz)` returning all peptides
          within tolerance (deduped). Keep existing `FindPeptide` as-is.
      (2) In `SpectraChromDataProvider.ExtractChromatogramsLocked`, fan each
          SRM spectrum out to every matched peptide, keying `dictKeyToIndex`
          by `Tuple<SignedMz, PeptideDocNode>` so each peptide gets its own
          `ChromDataCollector` and `ChromatogramGroupId`.
- [x] Add regression test. Extended `ShimadzuSrmDuplicateQ1Test` to:
      - Use `ExtensionTestContext.ExtShimadzuRaw` — `.lcd` (real Shimadzu
        vendor reader) on dev/UI runs, `.mzML` fallback on offscreen
        nightlies. Verified passing on both paths.
      - Group-level: every same-Q1 peptide must have a non-empty
        `Results[0]` for the imported replicate (covers Wesley's user-
        visible "compound missing" symptom; exercised by the 4 colliding
        pairs in `Wesley.sky`).
      - Transition-level: for any Q3 m/z shared across colliding peptides
        (e.g. Q3=343.2 between Cortexolone_diMO and Corticosterone_diMO at
        Q1=405.275), each peptide's transition at that Q3 must have a
        non-empty `Results[0]` — explicit "same Q1, same Q3" coverage.
      - Skips groups where no member has any data (the "alt" file lacks
        events at Q1=389.280 / Q1=…). Fails on master, passes with the fix.
      - Peak-boundary RT check (explicit RT must lie inside picked peak)
        is documented in the test but commented out, pending the picker
        TODO at `ai/todos/backlog/TODO-peak_picker_honor_explicit_rt.md`.
- [x] Run broader SRM-touching test sweep. ShimadzuSrmTest, AgilentCEOptTest,
      AgilentMixTest, AgilentMseTest, ImportSimTest (non-SRM sanity check),
      and ShimadzuSrmDuplicateQ1ImportTest all pass. The SRM-only branch in
      `ExtractChromatogramsLocked` is the only changed path; non-SRM
      extraction is untouched.
- [x] Open PR; reference support thread 66356. → PR #4200.

## Notes

- Same support thread as the (now-merged) points-count fix; do not re-quote
  thread context in the PR — just link.
- "Reported by Wesley." trailer goes above the Co-Authored-By in the eventual
  commit message.

## Closeout

### 2026-06-24 - Superseded

Brendan landed an alternative fix for the same support issue —
[PR #4305](https://github.com/ProteoWizard/pwiz/pull/4305) "Fix SRM shared-precursor
compound collapse via transition-aware matching (alternative to #4200)", merged
2026-06-23 as commit 41d3be94f. Our PR #4200 was closed (not merged) in favor of
the transition-aware approach. No further action here; this TODO is closed as
superseded.
