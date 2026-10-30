# TODO-koina_predict_for_fasta.md

## Branch Information
- **Branch**: Skyline/work/20261030_koina_predict_for_fasta (checkout `C:\proj\pwiz`, from `origin/master`)
- **Created**: 2026-10-30 (night session following PR #4938's handoff)
- **Status**: PR #4941 open, awaiting TeamCity and review
- **PR**: https://github.com/ProteoWizard/pwiz/pull/4941
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

## Finding: the Predict For digest honored the document's auto-select setting
The first recording run never reached Koina: `ImportFastaToPredict` reported "The FASTA file ... gave
no peptides with the document settings" for a FASTA whose tryptic peptides pass the document's filter.
Reproduced with SkylineCmd (`--in=Rat_plasma.sky --import-fasta=... --keep-empty-proteins`: the
proteins arrive, with no peptides; a default document gives 40 for rat_mini.fasta), then bisected by
transplanting the document's settings blocks into the default document
(`ai/.tmp/sessions/20261029-night-blib/fasta-import-bisect.py`): only `<peptide_filter>` drops them,
and the attribute that differs is `auto_select` (absent, so false, in `Rat_plasma.sky`).
`PeptideGroupDocNode.ChangeSettings` creates a FASTA protein's peptides only when
`PeptideSettings.Filter.AutoSelect` is on (line ~182), and `PeptideDocNode.ChangeSettings` creates
precursors only when `TransitionSettings.Filter.AutoSelect` is on (line ~969). So for any document with
"Auto-select all matching peptides" or "Auto-select all matching transitions" unchecked, the Predict For
route - Koina and Carafe alike, the block is shared - digested the FASTA into empty proteins, or
peptides without precursors, and blamed the FASTA. Fix: `GetDocumentToPredict`'s `settingsDigest` turns
both auto-select flags on beside the existing pick=filter override; the digest is a document of its own,
so the open document is untouched. The new test covers it as written, because the rat plasma document is
exactly such a document.

## Tasks
- [x] Fix: auto-select forced on in `BuildLibraryDlg.GetDocumentToPredict`'s digest settings
- [x] Branch from origin/master; FASTA copied into the test's data folder
- [x] Test and builder property written (patch script: `ai/.tmp/sessions/20261029-night-blib/patch-koina-test.py`)
- [x] Recorded against live Koina (33 KB, `koinaFastaQueries.json`); `koinaQueries.json` restored; RecordData false
- [x] Offline pass of KoinaSkylineIntegrationTest (15 s), CodeInspection, BuildLibraryCarafeWizardTest
- [x] Committed eeb5fa84d0, pushed, PR #4941 (label `skyline`)
- [x] `/code-review medium 4941`: 7 findings, 5 fixed in the second commit, 2 dropped (below)
- [ ] TeamCity green on #4941

## Progress Log
### 2026-10-30 night - Written, fixed, tested, PR opened
Session logs: `ai/.tmp/sessions/20261029-night-blib/koina-*.log`, `rr-*.log`. What the test measured on the way
to passing, all by design and left alone (rising triage bar near merge):
- Of 18 target peptides (3 from the FASTA, 15 entrapment from Carafe's own digest of it, which allows
  missed cleavages), 15 got a reverse-sequence decoy: `DecoyGenerator` drops a decoy that duplicates
  another's key or gets no precursor. The test asserts 0 < decoys <= targets and that every decoy's
  source is a target.
- 33 peptides gave 30 precursors, all Koina-supported; the 31-residue entrapment peptides have no
  precursor at charge 2 within the document's 50-1500 m/z instrument range. The test derives the expected
  library from `KoinaHelpers.EncodeSequence` rather than a hardcoded unsupported count.
- `LibraryDecoyPairs.Write` keys on unmodified sequence and charge and skips a key the library holds
  twice, so every methionine peptide (unmodified and oxidized forms, the document's variable Oxidation)
  goes unpaired: 14 rows for 30 spectra. Documented behavior of the writer; the test computes the expected
  rows the same way. Worth a look if Osprey needs pairs for modified forms.
- Running `BuildLibraryCarafeWizardTest` on this branch after building Osprey from the #4938 branch fails
  with `predict.predicted.speclib.tsv` not found: master's Skyline expects the TSV, the other branch's
  Osprey writes the blib. Rebuild Osprey from whichever branch is checked out before running Carafe tests.

### 2026-10-30 night - /code-review medium 4941 triage
Seven findings. Fixed: (1) `ChangePick(PeptidePick.filter)` with a library rank set throws in
`PeptideLibraries.DoValidate` ("does not support peptide ranking") through `ChangeProp`'s validation, so a
document ranking its library peptides failed Build Library on both sources, the document route included,
since `settingsDigest` is built before the route check (pre-existing from #4925; now
`.ChangeRankId(null).ChangePick(filter)`, the idiom at `Library.cs:259`, and the test ranks its document);
(2) the test now asserts the auto-select flags it depends on; (3) `EntrapmentTargets` null-guarded before
the HashSet; (4) the expected DecoyPairs rows dedupe by library key before the sequence-and-charge
grouping, as the writer's `ReadSpectrumIds` sees one spectrum per key; (7) `GetDocumentToPredict`'s
summary names the overrides. Dropped: (5) the digest settings are built on the document route too - three
clones, and with (1) fixed no longer a failure; (6) `WaitForCondition(Builder != null)` after a synchronous
`OkWizardPage` - a refused page already fails the test on its dialog's text (seen twice tonight).
