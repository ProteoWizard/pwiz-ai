# TODO-carafe_predict_blib.md

## Branch Information
- **Branch**: Skyline/work/20261029_carafe_predict_blib (checkout `C:\proj\pwiz`)
- **Created**: 2026-10-29
- **Status**: PR #4938 open, awaiting TeamCity and review
- **PR**: https://github.com/ProteoWizard/pwiz/pull/4938
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
- **The model-support limit moves into CarafeSharp** (Brendan, evening): "Don't ask a model to predict
  something it had no training data for" - David Shteynberg's validation of the default AlphaPeptDeep
  models (Carbamidomethyl, Oxidation: all; Phospho, GlyGly: MS2 only) - but Carafe holds the knowledge
  of what its default models support, not Skyline. `ModelSupport` in CarafeSharp.Models, applied by
  `LibraryGenerator` on both routes: RT withheld unless Chronologer (the default RT model, which
  encodes phosphorylation and was trained on it) predicted it itself; CCS withheld per the table; a
  saved model adds its training modifications for MS2 and RT. Withheld values are NULL in the blib
  (the old TSV path wrote 0). Consequence for AlphapeptdeepBuildLibraryTest: the phosphopeptide keeps
  Chronologer's RT, so the iRT dialog counts 7 peptides (6 before, when the RT was zeroed), and its CCS
  is withheld.

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
- [x] Build and run: Build-Osprey -RunTests -RunInspection (646 passed, inspection clean; the help
      pages regenerated); Build-CarafeSharp -RunTests (108 passed, two ion-mobility assertions updated
      for the CCS column); Build-Skyline, CarafeLibraryBuilderTest, BuildLibraryCarafeWizardTest,
      CodeInspection (all clean)
- [x] Committed as df36da2edc and pushed
- [x] `/code-review medium`: 8 findings; 6 fixed in 4447472f29 (TestPerf's `AlphapeptdeepBuildLibraryTest`
      compared the TSV and no longer compiled; the library's folder was opened as a model folder; the
      task declared no output; the digest's alphabase forms were materialized up front; the fine-tune's
      products were keyed on the library name; orphaned BlibBuild resources), 2 were the decided
      behavior changes (Carafe's defaults; RT and CCS no longer zeroed for fragmentation-only mods)
- [x] AlphapeptdeepBuildLibraryTest's answers re-recorded as blibs in its data folder in the repository
      (`TestPerf/AlphapeptdeepBuildLibraryTest.data`, not a Panorama zip): the TSVs removed, the test
      passes against the blibs; IsRecordMode copies into the test's working copy, so copy into the data
      folder right after the run, before another test run cleans the results folder
- [x] PR #4938 with label osprey (four commits: the change, the review fixes, the timing message removal,
      the pause description in the connector's form listing with the ScreenshotBorderTest one-liner)
- [ ] TeamCity Osprey Perf/Regression gate on the PR (ask Brendan first)

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

### 2026-10-29 evening - Five commits on PR #4938, handoff to a night session

Commits: df36da2edc (the change), 4447472f29 (review fixes), 436184d66b (timing message removed),
4033bbf8ed (pause description in the connector's form listing, ScreenshotBorderTest one-liner),
b487fece47 (ModelSupport in CarafeSharp, recorded perf-test answers, three redundant usings). TeamCity is
green on everything it ran; GitHub shows Update Branch (master moved). Brendan's instruction for the
night: update the branch (`git merge origin/master`, never rebase), trigger every TeamCity configuration
on `pull/4938` - the Skyline PR build, Skyline Perf tests, Tutorials, and the Osprey Windows .NET
Perf/Regression Tests (that one is normally ask-first; this instruction is the authorization, once, on
the PR branch) - with the goal of all green and ready to merge by morning. Then a stacked PR making the
Koina source's Predict For route real (the defect in TODO-20261028_osprey_integration_demo_deck.md:
`CreateKoinaBuilder` in BuildLibraryDlg.cs never reads PredictForDocument, PredictForFastaPath,
PredictDecoys or EntrapmentFastaPath; the FASTA digest, decoy and entrapment block of
`CreateCarafeBuilder` (~lines 420-450) is the code to share; verify with a document that differs from
the FASTA, since the demo's 720-precursor library equalled the document's count and proved nothing).
Open question left for Brendan: whether ModelSupport should also apply to the FASTA route, which would
break Carafe Java parity for phospho RT when the peptdeep RT model (not Chronologer) predicts.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20261029_carafe_predict_blib.md` before starting work.
