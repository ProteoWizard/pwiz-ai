# TODO-carafe_predict_blib.md

## Branch Information
- **Branch**: Skyline/work/20261029_carafe_predict_blib (checkout `C:\proj\pwiz`)
- **Created**: 2026-10-29
- **Status**: Completed
- **PR**: [#4938](https://github.com/ProteoWizard/pwiz/pull/4938) (merged 2026-10-30)
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
- [x] TeamCity Osprey Perf/Regression gate on the PR: build 4243012 on 1f636e42e9, 117/117 (the head 11cf54f23c differs only by the audit-log rename)

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

### 2026-10-30 night session - Master merged, every gate queued
origin/master (4 commits, mostly tutorial screenshots) merged as fb97a4d2b3, no conflicts. Local gates on
the merge: Build-Osprey -RunTests -RunInspection (646 passed, inspection clean), Build-CarafeSharp
-RunTests (108 passed), Build-Skyline and -Target TestPerf, then CarafeLibraryBuilderTest,
BuildLibraryCarafeWizardTest, CodeInspection and AlphapeptdeepBuildLibraryTest in one run (0 failures,
41 s; logs in `ai/.tmp/sessions/20261029-night-blib/`). Pushed 22:03. Triggered on `pull/4938`: Osprey
Windows .NET Perf/Regression Tests (build 4242978, the authorization in the handoff) and Skyline PR Perf
and Tutorial tests (4242979); the per-push configurations re-ran on the push. The Koina follow-up found
the defect already fixed on master by #4925; see TODO-20261030_koina_predict_for_fasta.md.

### 2026-10-30 night, later - Perf test red on TeamCity: master's Osprey, not the PR's
Skyline PR Perf and Tutorial tests (build 4242979, on fb97a4d2b3) failed `TestAlphaPeptDeepBuildLibrary`
at `VerifyAddIrts`: 6 iRT peptides, not the 7 the re-recorded answers expect (the phosphopeptide's RT
withheld, the TSV-era result). Its stdout shows why: `OspreyTestUtil.EnsureOsprey` finds no Osprey build
beside the Skyline source on the perf agent and downloads `OspreyHelpers.GetLatestBuildDownloadInfo()`,
the latest successful **master** Osprey (build 4242390, 4f92fe97ba), so the PR's Skyline ran master's
Osprey and CarafeSharp. Locally the sibling build hides this. A PR that changes Osprey and Skyline
together could therefore never pass its perf run before merging.

Fix (1f636e42e9): `OspreyTestUtil.EnsureOsprey` reads `BUILD_VCS_NUMBER` (set in every TeamCity build)
and `OspreyHelpers.TryGetRevisionBuildDownloadInfo` asks the REST API for the finished successful Osprey
Windows .NET build of that revision on any branch (`revision:<sha>,branch:default:any`; PR pushes build
Osprey too), falling back to master's latest. The zip is cached as `Osprey-<version>-<sha8>-win-x64.zip`
(`FileDownloadInfo.MirrorFilename`) because every build of a day shares the version in the zip's name and
`CachedDownloadsForTests` would hand back a cached master zip. Verified by hiding the sibling build and
running the perf test with `BUILD_VCS_NUMBER=fb97a4d2b3...`: it fetched the PR's build 4242981 and passed
(`ai/.tmp/sessions/20261029-night-blib/blib-perftest-revision.log`). Caveat: the perf run must start
after the revision's Osprey build has finished, or it falls back to master's; the night session triggers
it only once that build is done. The Osprey Perf/Regression gate was re-queued on the new head as build
4243012 (4242978 on the old head never left the queue; cancelled).

### 2026-10-30 night, later still - Second perf-run red: master's DIA-NN tutorial rename
The re-run on 1f636e42e9 (build 4243013) and the old-head run (4242979) both fail
`TestDiannSearchTutorialDraft` at `EndAuditLogging`: "Log file ... TestDiannSearchTutorialDraft.log does not
exist". #4915 (4f92fe97ba, master's newest commit, in tonight's merge) renamed the method from
`TestDiannSearchTutorial` and left `TutorialAuditLogs/<lang>/TestDiannSearchTutorial.log` behind in all five
languages; the test body passed, only the audit-log comparison keyed on the method name found nothing.
Master's own perf run of 4f92fe97ba had not happened yet, so this PR's merge is where it first showed.
Fixed on this branch as 11cf54f23c: `git mv` of the five logs to the draft name (the recorded steps are the
same). Brendan may prefer that commit split into its own skyline PR; it is one rename. Local check running:
`TestDiannSearchTutorialDraft -EnableInternet` (`ai/.tmp/sessions/20261029-night-blib/blib-diann-tutorial.log`).
The perf run will be triggered a third time once the head's Osprey build finishes.
Local check done: `TestDiannSearchTutorialDraft -EnableInternet` passed with the renamed log (0 failures, 663 s).
Osprey Perf/Regression gate 4243012: SUCCESS, 117 passed of 117, the same count as build #345 (4240683) on
PR #4931, so a complete run. It ran on 1f636e42e9; the head 11cf54f23c changes only test data (the audit
logs), so it was not re-queued - Brendan can re-trigger on the head if the status must be on that commit.
Third perf run on the head: build 4243067 (started 23:56, ~3.7 h).
Transient on 1f636e42e9: bt209 #22561 (4243005) failed only `TestRInstaller` (could not reach www.r-project.org);
the Docker (Wine) container build 4243011 then failed on its snapshot dependency alone (its own 348 tests
passed; the one msconvert wiff diff it reports is also in the passing build 4242989). bt209 #22563 on the head
passed; Docker 4243187 queued for the head.

### 2026-10-30 03:48 - Session close: all green
Head 11cf54f23c: 20 of 20 GitHub checks pass. Skyline PR Perf and Tutorial tests build 4243067: 118 passed of 118
(the last master run, 4241191 on pull/4546, had 117), with the PR's own Osprey (build 4243057). Osprey Perf/Regression
gate 4243012 on 1f636e42e9: 117/117. Night session 21:33-03:48 (6 h 15 min). Three commits tonight beyond the merge:
1f636e42e9 (perf tests fetch the Osprey of their own revision), 11cf54f23c (DIA-NN tutorial audit logs renamed
after master's #4915), plus the merge fb97a4d2b3. Brendan merges.
PR #4942 (b816bdd8e6) carries the audit-log rename alone, from master, so it can merge first; this PR's 11cf54f23c then becomes a no-op rename.
PR #4942's own Perf and Tutorial run: build 4243193 (queued 2026-10-30 04:22).

PR #4942 closed 2026-10-30: Brian's #4943 (19c4e61b28) made the same five-file rename and merged first, so master has
the fix and this branch's 11cf54f23c is a no-op rename on merge. #4941 merged as 232005d401 (/pw-complete, --admin).

### 2026-10-30 - Merged

PR #4938 merged as commit c03ad0b5f7 (squash, --admin over a duplicate perf run, 4243177, whose 23 failures were all
"not enough space on the disk" on a cloud agent; the run on the same head, 4243067, passed 118/118 and the
Osprey gate 4243012 117/117). Shipped: Osprey's --precursors route writes the .blib itself through
CarafeSharp's writer, the CCS beside the 1/K0, ModelSupport in CarafeSharp withholding unvalidated RT and
CCS on the table route, Build Library following Carafe's fragment rules, the perf test's answers as blibs
in the repository, TeamCity perf tests downloading the Osprey of their own revision, and the connector's
pause description. Open points left for Brendan: ModelSupport on the FASTA route (Carafe Java parity for
phospho RT), and the translated usage resx entries for --precursors.
