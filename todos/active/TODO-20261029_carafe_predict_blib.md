# TODO-carafe_predict_blib.md

## Branch Information
- **Branch**: Skyline/work/20261029_carafe_predict_blib (checkout `C:\proj\pwiz`)
- **Created**: 2026-10-29
- **Status**: In progress - code written, building and testing
- **Module**: `osprey`
- **Objective**: Osprey's `--precursors` route (Skyline's Build Library with the Carafe source) writes
  the `.blib` the command line asks for, through the same CarafeSharp writer the FASTA route uses,
  instead of the peptdeep-format TSV that Skyline then transformed and imported with BlibBuild and
  BlibFilter.
- **Requested by**: Brendan, 2026-10-29, on seeing "BlibBuild completed successfully" in the Immediate
  Window during a Build Library demo capture: "That's just silly."

## Why
`CarafeLibraryBuilder` sent the document's precursors to Osprey as a table and got back
`<out>.predicted.speclib.tsv`, the file Python peptdeep used to write, then renamed its columns,
rebuilt the modified sequences, ran BlibBuild into a redundant library and BlibFilter into the final
one, and added the DecoyPairs table. Osprey's own FASTA route already writes a `.blib` directly
(`LibraryGenerator` through `BlibLibraryWriter`). The TSV detour was a hold-over of the Python
integration that nobody meant to keep; Brendan missed it in review of the integration (PR #4927).

## Decisions (Brendan, 2026-10-29)
- **Carafe's library conventions for Build Library too**: `CarafeFragmentSelector` (top 20
  fragments, m/z 200-1800, a precursor with fewer than 2 fragments dropped), NCE 27 on an Eclipse
  unless `--nce`/`--instrument` say otherwise. The peptdeep rules (top 12, 200-2000, NCE 30 Lumos)
  and `PrecursorTablePredictor` are gone.
- **The blib carries the CCS and the 1/K0**: `BlibLibraryWriter` now writes
  `collisionalCrossSectionSqA` beside `ionMobility` for every spectrum with a CCS, on both routes.
  Skyline uses the CCS with each data file's calibration (and converts it to drift time or
  traveling-wave mobility); Osprey keeps reading the 1/K0. "I don't think we want the Carafe no CCS
  route at all."
- A precursor table's library always predicts the CCS (Skyline reads it back); it is a `.blib`
  alone whatever `-lf_type` says, and the output is the `-o` path itself.

## Tasks
- [x] CarafeSharp: `LibraryGenerator.PrecursorTablePath` (table precursors in place of a digest,
      grouped by peptide form), `LibrarySpectrumBuilder.Build(PrecursorForm, ...)` for a precursor
      with no peptidoform, `ModifiedPeptideNotation.FormatSkyline(PeptideForm, ...)` from alphabase's
      masses, `BlibLibraryWriter` CCS column, `PredictPrecursorTableTask` through the generator
- [x] Osprey: `LibraryBuildWorkflow.TableLibraryPath` (the `-o` path), `PREDICTED_TABLE_SUFFIX` and
      `PredictedTablePath` removed, usage text, docs (`20-command-line.md`, `Osprey-workflow.html`,
      `Help/en/CommandLine.html`)
- [x] Skyline: `CarafeLibraryBuilder` predicts straight to the library path (a fine-tune into
      Osprey's working folder, copied over), transform/BlibBuild/BlibFilter steps and
      `OspreyHelpers.GetPredictedTablePath` removed, the two unit tests of those steps and their
      embedded TSV/blib resources removed
- [x] Tests: `PrecursorTableLibraryTest` (CarafeSharp, replaces `PrecursorTablePredictorTest`),
      `SubsetPipelineTest.TestSubsetPrecursorTable` asserts the blib
- [ ] Build and run: Build-Osprey -RunTests -RunInspection; Build-CarafeSharp -RunTests
      -TestName PrecursorTableLibraryTest; Build-Skyline, CarafeLibraryBuilderTest,
      BuildLibraryCarafeWizardTest, CodeInspection
- [ ] `/code-review medium`, PR with label osprey

## Open points
- The translated usage resx files have no `_precursors` entry (they fall back to English);
  `TestCommandLineHelpDocumentation` regenerated all three `CommandLine.html` pages from the resx,
  so the ja and zh-Hans pages carry the English text for this option until a translation pass.
- The old transform zeroed RT and CCS for peptides whose modifications the peptdeep-era support
  table did not cover (Phospho, GlyGly: fragmentation only); the blib now carries the models'
  predictions for them. `AbstractDeepLibraryBuilder` still leaves peptides with unsupported
  modifications out of the table.
- The library's "File" is now the library's own name (Osprey's source-file convention), not
  `predict_sky.speclib.tsv`.

## Progress Log
### 2026-10-29 - Written
See the Tasks list; the design and the two decisions above were settled with Brendan before any
code. Related: the Koina Predict-for defect and the wiki drafts in
`TODO-20261028_osprey_integration_demo_deck.md`.
