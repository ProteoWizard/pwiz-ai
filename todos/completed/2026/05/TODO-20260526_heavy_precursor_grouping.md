# Duplicate heavy precursor when importing mz-only transition list with multiple transitions

## Branch Information
- **Branch**: `Skyline/work/20260526_heavy_precursor_grouping`
- **Base**: `master`
- **Created**: 2026-05-26
- **Status**: Completed
- **Support thread**: https://skyline.ms/announcements/home/support/announcements-thread.view?rowId=74741 (reporter: Amandine)
- **GitHub Issue**: (none)
- **PR**: [#4242](https://github.com/ProteoWizard/pwiz/pull/4242) (merged 2026-06-24 as cb5536af)
- **Fix Type**: bug

## Objective

Importing a small-molecule transition list for a mass-only molecule (no formula)
where the same molecule + adduct appears at two precursor m/z values causes the
heavier precursor's transitions to be split across **two** precursor nodes instead
of grouping under one.

Reported via the support board: a `Pyruvate` list declared with adduct `[M-H]` at
m/z 86.8 and 87.9, no explicit label type. Skyline correctly infers the 87.9
precursor is isotope-labeled (`[M1.1-H]`, "heavy"), but its two transitions (a
fragment and a precursor-type transition) land on two duplicate heavy precursors,
one transition each — while the light 86.8 precursor groups its two transitions
correctly. Expected: two precursors, two transitions each.

## Root Cause

`SmallMoleculeTransitionListReader.ErrorFindingTransitionGroupForPrecursor`, when
matching an incoming transition to an existing precursor group, only derived the
implied isotope label (bare `[M-H]` -> `[M1.1-H]`) for **charge-only** adducts
(`adduct.IsChargeOnly`). `[M-H]` is a deprotonation adduct, not charge-only, so the
derivation was skipped, the bare `[M-H]` failed `SameEffect([M1.1-H])`, and a
duplicate heavy precursor was created. The group-*creation* path
(`GetMoleculeTransitionGroup`) already used the correct test (`!adduct.HasIsotopeLabels`),
which is why each duplicate independently ended up labeled `[M1.1-H]`.

## Tasks

- [x] Reproduce as a functional test using the reporter's exact list (red: 3 precursors, expected 2).
- [x] Root-cause confirmed from instrumented run (two identical `[M1.1-H]` groups that failed to merge).
- [x] Fix: broaden the matching gate from `adduct.IsChargeOnly` to `!adduct.HasIsotopeLabels`, mirroring the creation path.
- [x] New test `TestHeavyPrecursorMultipleTransitionsNoFormulas` green after fix.
- [x] Full `PasteMoleculesTest` green (no regressions, 67.3s).
- [x] Confirm `CodeInspection` still passes (13.0s).
- [ ] Check `Skyline/work/20260511_shared_q1_compound_collapse` (SRM_mismatch) for overlap before PR.
- [x] Commit (43ea0c240) and open PR [#4242](https://github.com/ProteoWizard/pwiz/pull/4242).
- [x] Requested Copilot review explicitly.
- [x] Copilot review: overview summary only, zero actionable inline comments — nothing to address.
- [x] `/pw-self-review 4242` run twice (2026-06-17 and post-pull 2026-06-23): clean, no HIGH/MEDIUM. Two LOW polish notes (use `pep.CustomMolecule` on both halves of the `:434` gate for readability; test is negative-mode/single-charge only) — deferred as optional. Test question (row 2 Δ0.1) resolved: grouping keys on precursor m/z, so it doesn't affect assertions.
- [x] Reply to Amandine on the support thread (handled by Brian directly).
- No cherry-pick to release (per Brian).
- SRM_mismatch `shared_q1_compound_collapse` overlap check: dropped (per Brian).

## Regression Test

- **Test name**: `TestHeavyPrecursorMultipleTransitionsNoFormulas` (new sub-test in `PasteMoleculesTest`)
- **Test project**: TestFunctional
- **Fails on master**: yes — `MoleculeTransitionGroupCount mismatch: expected 2, actual 3`.
- **Passes on fix**: yes.

## Approach

```diff
- if (adduct.IsChargeOnly && !tranGroup.CustomMolecule.HasChemicalFormula)
+ if (!adduct.HasIsotopeLabels && !tranGroup.CustomMolecule.HasChemicalFormula)
```

One condition change in the transition-group matching loop, plus an updated comment.
The derivation math (`ApplyToMass` / `MassFromMz`) already handles non-charge-only
adducts, so broadening the gate is sufficient.

## Progress Log

### 2026-05-26 - Reproduced, root-caused, fixed (Quickee checkout)

Pulled the support thread and its attachment (`Skyline_forum.xlsx`), decoded the
4-row list, and reproduced in a new `PasteMoleculesTest` sub-test. Instrumented the
import: the dump showed `86.8 [M-H] light (2 transitions)` plus **two** identical
`87.9 [M1.1-H] heavy (1 transition each)` — proving the second heavy transition
failed to merge. Fixed the matching gate; isolated test and full `PasteMoleculesTest`
both green. Changes sit on the work branch; commit pending message confirmation.

### 2026-06-23 - Re-verified after master fold-in (Quickee checkout)

`git pull` fast-forwarded the branch (latest master folded in on the remote,
incl. OspreySharp/`CommandArgs` churn). Confirmed the real delta vs current
`origin/master` is unchanged — exactly the two intended files (+38/-2), fix
hunk intact. Ran the full inspect gate (`Build-Skyline -RunInspection -RunTests
-TestName CodeInspection`): build OK, CodeInspection 0 failures, ReSharper
full-solution inspection 0 errors / 0 warnings. Re-ran `/pw-self-review`: clean,
two LOW polish notes only (see Tasks). Resolved the self-review's test question —
row 2 declares product m/z 86.9 vs precursor 86.8, but precursor grouping keys
on precursor m/z (86.8 and 87.9 are exact within-group matches, 1.1 Th apart
between groups), so the Δ does not affect the assertions; only the inline comment
("product m/z equals precursor m/z") is loosely worded for the light row. Branch
in order to re-request team review.

### 2026-06-24 - Merged

PR #4242 merged to master as commit cb5536af. Shipped: the matching-gate fix
(broadened from `adduct.IsChargeOnly` to `!adduct.HasIsotopeLabels`) so a heavier
inferred-isotope sibling groups under one precursor instead of splitting across
duplicates. Also folded in both self-review LOW polish items — the gate's formula
guard now reads `pep.CustomMolecule.HasChemicalFormula` (aligned with the mass
derivation), and `PasteMoleculesTest` gained a positive-mode [M+H] counterpart
(`TestHeavyPrecursorMultipleTransitionsNoFormulasPositive`, using
`expectAutoManage:false` since that list doesn't trip the auto-manage prompt
heuristic). Final build + CodeInspection + ReSharper full-solution all green. No
cherry-pick to release and the SRM_mismatch overlap check were both dropped per
Brian.
