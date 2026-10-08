# Declared small-molecule adduct silently replaced when precursor m/z doesn't match it

## Branch Information
- **Branch**: `Skyline/work/20261005_declared_adduct_mz_mismatch`
- **Base**: `master` (the .NET 10 port branch was promoted to master 2026-10-08; PR targets master)
- **Checkout**: `C:\Dev\DeclaredAdduct` (created and removed 2026-10-08)
- **Created**: 2026-10-05
- **Status**: Abandoned (2026-10-08) - no PR
- **GitHub Issue**: [#4776](https://github.com/ProteoWizard/pwiz/issues/4776)
- **Module**: `skyline`
- **PR**: none (abandoned before PR)
- **Requester/Reporter**: Haley (from support thread rowId 75665)

## Objective

When a small-molecule transition list gives a formula, an explicitly declared adduct, and a
precursor m/z that doesn't agree with that adduct, `ValidateFormulaWithMzAndAdduct`
(`SmallMoleculeTransitionListReader.cs`) searches for some other adduct that explains the m/z and
silently substitutes it, reporting "No errors". Make a declared (non-charge-only) adduct with a
mismatched m/z an error instead.

## Tasks

- [x] Regression test `PasteMoleculesTest.TestDeclaredMassOffsetAdductMzMismatch` (red before fix)
- [x] Fix: return no match when a real adduct was declared and its m/z disagrees
- [x] Build and run the test on the port branch (red without fix, green with it)
- [x] Small-molecule regression sweep on the port branch (25/26; see log)
- [x] CodeInspection test (passed); full ReSharper inspection (no issues in changed files; run broken, see log)
- [ ] `/code-review max`
- [ ] PR to `Skyline/work/20260612_net8_port`
- [ ] Draft a reply to Haley (workaround: `C27H46O` with `[M(-4.0313)+H]` or `[M(-2.01565)+H]`)

## Regression Test

- **Test name**: `TestDeclaredMassOffsetAdductMzMismatch` (in `TestPasteMolecules`)
- **Test project**: TestFunctional
- **Fails without fix**: yes, on master 2026-09-29 and on the port branch 2026-10-05 ("No errors" instead of the mismatch error)
- **Passes on fix**: yes, on master 2026-09-29 and on the port branch 2026-10-05 (net10.0-windows, vendor readers on)

## Related

- #4741: adduct forms missing from documentation (same support thread)

## Progress Log

### 2026-09-29 - Initial fix (on master, before the process was followed)

Debugged Haley's list (second row double-applies the 4 H loss: `C27H42O` + `[M(-4.0313)+H]` at
383.3309, which is exactly `C27H42O[M+H]`). Wrote the test (red), added the fix (green). 25 of 26
small-molecule/tutorial tests passed; `TestMixedPolarityFullScan` failed its GC-leak check and
passed alone (known intermittent). Work was left uncommitted on a master-based branch
`Skyline/work/20260929_declared_adduct_mz_mismatch` with no issue or TODO.

### 2026-10-05 - Moved to the port branch

Filed #4776. Created this branch from `origin/Skyline/work/20260612_net8_port` in `master_clean`
and applied the two-file change cleanly. Original changes kept in a stash on the old branch.

Built net10.0-windows. The test's expected message used `(float)` casts, which format with
shortest round-trip digits on .NET Core (`379.29953`) while the product uses `G7` (`379.2995`);
switched to the file's existing `Mz7()` helper. `TestProperData` initially got 0 results because
this checkout's pwiz-sharp had been built without vendor readers; rebuilding with
`Build-Skyline.ps1 -VendorLicenses` fixed that. With the fix stashed the test fails with
"No errors"; with it restored `TestPasteMolecules` passes (59s).

Sweep (same 26-test list as 2026-09-29): 18/19 non-tutorial tests and 7/7 small-molecule
tutorials passed. `TestTutorial` is not built by the default `Build-Skyline.ps1` target;
needed `-Target TestTutorial`. `TestMixedPolarityFullScan` fails its GC-leak check ("SkylineWindow,
SrmDocument not garbage collected") with the fix, and also WITHOUT it on the port branch (1 pass,
3 fails in 4 solo runs), so it is pre-existing on the port branch, not caused by this change. See
TODO-20260710_mixedpolarity_fullscan_teardown_hang.

Inspection: CodeInspection test passed. Full ReSharper inspection reported 393 issues, none in
the two changed files; almost all are "cannot resolve symbol" errors in shared projects
(318 in `MsDataFileImpl.cs`; JetBrains.Annotations, Newtonsoft in CommonUtil), i.e. the local
net10 inspection can't resolve package references. Rely on TeamCity's inspection for the PR.

### 2026-10-08 - Moved to its own checkout on master

The port branch was promoted to master (#4619) after the LF normalization (#4789). Moved the
still-uncommitted two-file change out of `master_clean` (now reset to `master`) into a new
checkout `C:\Dev\DeclaredAdduct`, recreating the branch from `origin/master`; the moved diff is
byte-identical to the original. Built with `-VendorLicenses`; `TestPasteMolecules` passed (61s).

### 2026-10-08 - Abandoned

On review of the support thread, the reported behavior came from user error (the second row
double-applies the 4 H loss), and changing how a declared adduct is matched against m/z risks
destabilizing small-molecule import for lists that rely on the current fallback. Dropped the
change: deleted `C:\Dev\DeclaredAdduct`, the 9/29 stash and branch in `master_clean`. Nothing
was committed or pushed. The fix was the 6-line early `return null` in
`ValidateFormulaWithMzAndAdduct` when `mzCalc.HasValue && !adduct.IsEmpty && !adduct.IsChargeOnly`,
plus `PasteMoleculesTest.TestDeclaredMassOffsetAdductMzMismatch`, if it is ever revisited.
