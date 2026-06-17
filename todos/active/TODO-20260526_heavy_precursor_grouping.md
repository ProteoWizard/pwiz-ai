# Duplicate heavy precursor when importing mz-only transition list with multiple transitions

## Branch Information
- **Branch**: `Skyline/work/20260526_heavy_precursor_grouping`
- **Base**: `master`
- **Created**: 2026-05-26
- **Status**: PR open, awaiting Copilot review
- **Support thread**: https://skyline.ms/announcements/home/support/announcements-thread.view?rowId=74741 (reporter: Amandine)
- **GitHub Issue**: (none)
- **PR**: [#4242](https://github.com/ProteoWizard/pwiz/pull/4242) (commit 43ea0c240)
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
- [ ] Address Copilot review (`/pw-respond 4242`) and run `/pw-self-review 4242`.
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
