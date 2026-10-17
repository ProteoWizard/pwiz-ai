# TODO: Derive molecular formulas from richer nomenclature (small molecules)

**Branch:** `Skyline/work/20260701_nomenclature_derive_formula` (in checkout `C:\Dev\OtherFormulaSources`)
**Started:** 2026-07-01 (autonomous session)
**Design study:** `ai/.tmp/nomenclature-modes-design.md` (full analysis; gitignored working doc)

## Objective
Let users enter a small molecule by something OTHER than a chemical formula and have Skyline
derive the formula automatically (replacing the spreadsheet/calculator workflow). Modes span
lipid/glycan/oligo shorthand, peptide sequence, and identifier translation (InChI, InChIKey, name).

## Architecture (the reframe)
Four derivation mechanisms, each a thin front-end over a shared engine:
- M1 residue-sum (peptide/oligo/glycan/lipid-composition), M2 structure-notation (InChI/SMILES/name),
  M3 identifier resolver (InChIKey/CAS/DB IDs, online), M4 formula-syntax enrichment.
Single fallback hook `NomenclatureRegistry.TryDeriveFormula(text, mode, ...)` invoked when a normal
formula parse fails, at two verified choke points:
- Paste import: `SmallMoleculeTransitionListReader.cs` formula branch (~:1779).
- Interactive: `FormulaBox.UpdateAverageAndMonoTextsForFormula` (~:648) / `EditCustomMoleculeDlg.OkDialog`.

## Roadmap (see design doc Section 6)
- Wave 1 (zero new deps): InChI formula-layer parse + glycan composition + M4 niceties + the skeleton.
- Wave 2 (one MIT lib): lipids via csgoslin (offline, ~31 files, no ANTLR dep) + oligonucleotides
  (residue tables validated) + bridge the existing peptide engine to the small-molecule path.
- Wave 3 (legal-gated): SMILES/MOL/IUPAC-name via NCDK (LGPL review) or RDKit.NET (BSD, native).
- Wave 4 (enhancement): online resolvers (PubChem PUG-REST) for InChIKey/CAS/name/accession.
- Also: M5 mass->formula enumeration (SIRIUS/MS-FINDER inverse problem) as its own later track.

## Progress
- [x] Wave-1 CORE (this commit): `INomenclatureInterpreter`, `NomenclatureRegistry`,
      `InChiFormulaInterpreter` under `Util/Nomenclature/`; unit test `NomenclatureTest`
      (`TestInChiFormulaDerivation`) covering glucose, multi-component multiplier, `/p` proton
      removal (sulfate), explicit mode, auto-miss, malformed-error, CanHandle. Build green;
      test passes; ReSharper QuickInspection clean (0/0).
- [ ] Wire `TryDeriveFormula` into the paste-import choke point (+ optional "Formula Source" column).
- [ ] Wire into `FormulaBox`/`EditCustomMoleculeDlg` with the "Interpret as" selector + localized
      `DisplayName` (adds resx/Designer) and derived-formula read-back.
- [x] Glycan composition interpreter (commit b873d0ce5): `GlycanCompositionInterpreter` +
      `HexNAc2Hex3` / `Hex(3)HexNAc(2)` grammars; validated residue tables + H2O. Extracted
      `ElementCounts` (Hill-order accumulator) and refactored InChI onto it. Build/test/inspect green.
- [ ] Functional test (PasteMoleculesTest extension; EditCustomMoleculeDlg toggle).

## Notes / decisions
- Interpreter throws a value-only parser exception (no English) on failure; the UI layer composes
  the localized message. `DisplayName` deferred to the UI increment to keep the core resx-free.
- InChI parse handles multi-component (dot + integer multiplier) and the `/p` proton layer; `/q`
  net charge is retained in the InChI but not folded into the neutral formula (adduct handles charge).
