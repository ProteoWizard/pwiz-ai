# Declared small-molecule adduct silently replaced when precursor m/z doesn't match it

## Branch Information
- **Branch**: `Skyline/work/20261005_declared_adduct_mz_mismatch`
- **Base**: `Skyline/work/20260612_net8_port` (.NET 10 port branch; PR targets it, not master)
- **Created**: 2026-10-05
- **Status**: In Progress
- **GitHub Issue**: [#4776](https://github.com/ProteoWizard/pwiz/issues/4776)
- **Module**: `skyline`
- **PR**: (pending)
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
- [ ] Build and run the test on the port branch
- [ ] Small-molecule regression sweep on the port branch
- [ ] CodeInspection + full ReSharper inspection
- [ ] `/code-review max`
- [ ] PR to `Skyline/work/20260612_net8_port`
- [ ] Draft a reply to Haley (workaround: `C27H46O` with `[M(-4.0313)+H]` or `[M(-2.01565)+H]`)

## Regression Test

- **Test name**: `TestDeclaredMassOffsetAdductMzMismatch` (in `TestPasteMolecules`)
- **Test project**: TestFunctional
- **Fails without fix**: yes, on master 2026-09-29 ("No errors" instead of the mismatch error)
- **Passes on fix**: yes on master 2026-09-29; not yet verified on the port branch

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
