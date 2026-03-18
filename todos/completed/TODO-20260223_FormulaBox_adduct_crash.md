# FormulaBox crashes with InvalidChemicalModificationException during adduct typing

## Branch Information
- **Branch**: `Skyline/work/20260223_FormulaBox_adduct_crash`
- **Base**: `master`
- **Created**: 2026-02-23
- **Status**: Completed
- **GitHub Issue**: [#4009](https://github.com/ProteoWizard/pwiz/issues/4009)
- **PR**: (pending)
- **Exception Fingerprint**: `0e95385b5da1fab2`
- **Exception ID**: 73990
- **Repo**: AdductStuff (C:\Dev\AdductStuff)

## Objective

Fix unhandled `InvalidChemicalModificationException` in FormulaBox when typing an adduct that references more isotope-labeled atoms than exist in the molecule formula. The `textFormula_TextChanged` handler fires on every keystroke with partial input.

## Tasks

- [x] Add catch for `InvalidChemicalModificationException` in `UpdateAverageAndMonoTextsForFormula()`
- [x] Show exception message as tooltip on formula textbox (all 4 exception types)
- [x] Consolidate 4 catch blocks into one using exception filter
- [x] Detect negative atom counts in formulas (e.g. "U-H2O") — skyline.ms issue #1053
- [x] Block OK button when FormulaError is set (via FormulaError property)
- [x] Add automated test (TestFormulaErrorTooltip)
- [x] Verify build succeeds
- [x] Run relevant tests (AdductTest, EditCustomMoleculeDlgTest)
- [x] Manual test - tooltip shows on hover over invalid formula
- [x] Manual test - OK blocked for negative atom count formulas
- [x] Create PR

## Progress Log

### 2026-02-23 - Session Start

Starting work. Fix already applied in FormulaBox.cs — catch `InvalidChemicalModificationException` and set `valid = false`, same as existing handling for other parse exceptions.

Build succeeded (17s). Tests passed:
- AdductTest (2 tests, 0.3s) — AdductParserTest, ChargeStateTextTest
- EditCustomMoleculeDlgTest (1 test, 12s) — TestEditCustomMoleculeDlg

Ready for PR when requested.

Enhanced: all 4 catch blocks (InvalidOperationException, InvalidDataException, ArgumentException,
InvalidChemicalModificationException) now capture ex.Message into tooltip. When formula is valid,
tooltip reverts to normal help text. Manual testing confirmed tooltip appears on hover over red
formula text (e.g., "Adduct [M-O+H] calls for removing more O atoms than are found in the molecule C12H").

Consolidated 4 catch blocks into one using `catch (Exception ex) when (...)`.

Added negative atom count detection for formulas like "U-H2O" (skyline.ms issue #1053). Parses
neutralFormula via Molecule.Parse() and checks for negative Values before mass calculation. Shows
error tooltip and blocks OK button via new FormulaError property on FormulaBox.

Added TestFormulaErrorTooltip test covering: adduct removing atoms not present (C12H[M-O+H]),
adduct labeling too many atoms (H[M7H2+NH4] — original #4009 crash), negative atom counts (U-H2O —
#1053), and tooltip revert on valid formula. All tests pass.
