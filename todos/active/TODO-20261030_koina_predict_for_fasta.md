# TODO-koina_predict_for_fasta.md

## Branch Information
- **Branch**: Skyline/work/20261030_koina_predict_for_fasta (checkout `C:\proj\pwiz`, from `origin/master`)
- **Created**: 2026-10-30 (night session following PR #4938's handoff)
- **Status**: In progress - test written, Koina queries being recorded
- **PR**: (none yet)
- **Module**: `skyline`
- **Objective**: Prove, with a functional test that runs offline, that the Koina source's Predict For
  route in Build Library predicts the chosen protein FASTA's digest with its decoys and entrapment
  peptides, for a document that differs from the FASTA, and pairs them in the library's DecoyPairs
  table.
- **Requested by**: Brendan, 2026-10-29, as the follow-up to PR #4938 ("a stacked PR that makes the
  Koina source's Predict For actually work").

## Why
The demo-deck session (TODO-20261028_osprey_integration_demo_deck.md) ran a Koina build for a FASTA and
got a 720-precursor library - the open document's own count, because the test document was that FASTA
digested with the same settings - and concluded from reading `CreateKoinaBuilder` that the Koina route
ignored `PredictForDocument`, `PredictForFastaPath`, the decoy and the entrapment choices. That reading
was of code older than master: PR #4925 (b68aa96d5f, merged 2026-10-27) already sends the Koina builder
through `GetDocumentToPredict` (the FASTA digest, `ImportEntrapmentPeptides`, reverse-sequence decoys)
and gave `KoinaLibraryBuilder` the `DecoyMethod` and `EntrapmentTargets` it writes with
`LibraryDecoyPairs.Write` after the build. What #4925 did not add is a Koina test of that route; the
only Koina library-build test (`KoinaSkylineIntegrationTest.TestKoinaLibraryBuild`) predicts the open
document. So the production path is on master and the deliverable here is the proof and the regression
guard, with whatever that test exposes.

## Design
- `KoinaSkylineIntegrationTest.TestKoinaLibraryBuildForFasta`, a sub-test of the one `[TestMethod]`,
  inside its own `FakeKoina` scope with its own recorded queries
  (`KoinaSkylineIntegrationTest2.data/koinaFastaQueries.json`), so re-recording it leaves the rat plasma
  document's `koinaQueries.json` as it was.
- The FASTA is `ThreeProteins.fasta` (copied from `Test/CmdLineAssociateProteinsTest.data`): three
  single-peptide proteins whose tryptic peptides are absent from `Rat_plasma.sky` (checked by grep of the
  .sky), so the library proves the route by holding the FASTA's peptides and none of the document's.
- Asserts: the builder's document is not the open one; every target has a decoy; no target is in the
  open document; the library's spectrum count equals the predicted precursor count and holds every
  predicted LibKey and not the open document's first; the DecoyPairs table has a row per decoy precursor
  and per entrapment precursor.
- `KoinaLibraryBuilder.Document` added (the predicted document, as `AbstractDeepLibraryBuilder.Document`
  exposes it for the Carafe test).
- Recording: `RecordData => true`, `Run-Tests.ps1 -TestName KoinaSkylineIntegrationTest -EnableInternet`
  (both JSONs are rewritten; restore `koinaQueries.json` from git), then `RecordData => false` and the
  test must pass offline.

## Tasks
- [x] Branch from origin/master; FASTA copied into the test's data folder
- [x] Test and builder property written (patch script: `ai/.tmp/sessions/20261029-night-blib/patch-koina-test.py`)
- [ ] Recorded against live Koina; `koinaQueries.json` restored; RecordData false
- [ ] Offline pass of KoinaSkylineIntegrationTest; CodeInspection
- [ ] Commit, push, PR (label `skyline`)

## Progress Log
### 2026-10-30 night - Written
Session logs: `ai/.tmp/sessions/20261029-night-blib/koina-*.log`.
