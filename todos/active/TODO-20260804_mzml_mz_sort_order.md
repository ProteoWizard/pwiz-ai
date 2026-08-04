# TODO-20260804_mzml_mz_sort_order.md

## Branch Information
- **Branch**: `Skyline/work/20260804_mzml_mz_sort_order`
- **Module**: `pwiz` - the point of the branch is now the pwiz-core read-seam correction; the
  Skyline and BiblioSpec pieces came along from #4498 and are secondary
- **Base**: `origin/master` @ `e7b5a917b` (branched from the tip on 2026-08-04)
- **Created**: 2026-08-04, split out of `Skyline/work/20260727_Waters_dataconvert_mzml_import`
- **Status**: Green and pushed, **PR not yet opened**. `/code-review max` is the gate before
  `gh pr create` (run it on the branch - it diffs master...HEAD and needs no PR), so that
  Copilot's automatic pass lands on already-hardened code.
- **GitHub Issue**: (none)
- **PR**: (not yet opened - title `pwiz: Corrected disordered m/z arrays on read`, label `pwiz`)
- **Cherry-pick to release**: undecided
- **Split from**: #4498, which keeps the Waters calibration/waters_connect story. Brian's call
  2026-08-04: the m/z sort issue is separate from the calibration scans issue.

## Objective

Peaks that are not in ascending m/z order must not silently produce empty chromatograms, for
**any** consumer of pwiz - not just Skyline.

## Context

Waters DATA Convert 5.0.0.2900 writes each spectrum's peak arrays sorted by ascending
**intensity**. Skyline's extraction binary searches the m/z axis, so on such a file the search
lands at an arbitrary index and nothing accumulates: `TotalArea=0` at all 5998 points, no error.
In metabolomics that reads as "compound not detected". 4.0.0.2619 is correct, so it is a
regression in the converter. Ascending m/z is nowhere in the mzML spec - it is a de facto
standard everything assumes.

Full evidence, four independent methods, and the acceptance measurement are in
`TODO-20260727_Waters_dataconvert_mzml_import.md` Phase 9. Not repeated here.

## What changed on 2026-08-04, and why

The original fix was Skyline + BiblioSpec only, a deliberate scope call ("fix only in code we
control"). Matt questioned the pwiz-core seam in review and the answer was the scope note. Then
measuring for a review reply produced a fact that undercut it:

**msconvert passes the bad order straight through, byte for byte, with no filters.** Measured on
the fixture, mzML to mzML: 3 and 2 m/z descents in, 3 and 2 out. So converting one of these files
produces another broken file, and the tool users are told to run is a propagator rather than a
remedy. The blast radius is not Skyline-shaped, it is "anything that ever touches one of these
files".

Filters repair it only incidentally, and only when they actually do work:

| filter | order after |
|---|---|
| none | broken |
| `msLevel 1-` | broken |
| `threshold count 100 most-intense` | **broken** |
| `threshold count 3 most-intense` | fixed |
| `mzWindow [100,800]` | fixed |

The threshold pair corrects a claim recorded as settled in the Waters TODO.
`ThresholdFilter::operator()` returns early at line 264 - *"if count threshold is greater than
number of data points, return as is"* - before reaching the m/z re-sort at line 423. So
"threshold re-sorts by m/z" holds only when it cuts something. `sortByScanTime` reorders spectra,
not peaks; nothing in pwiz reordered peaks within a spectrum before this branch.

**Decision (Brian, 2026-08-04): correct on read in pwiz, and warn when it fires.**

## Design

`SpectrumList_MzOrder` (`pwiz/data/msdata/`), inserted in `ReaderList::read` - both overloads -
immediately after the matching reader returns.

Why that seam: there is no lower choke point. mzML decodes straight into `BinaryDataArray`, mzXML
goes through `setMZIntensityPairs`, MGF/MSn/BTDX/mz5 through `setMZIntensityArrays`. There is no
shared "the arrays are now assigned" moment like Skyline's `SetArrays`. Correcting per reader
would mean six sites and a seventh format that forgets. `ReaderList::read` covers `MSDataFile`,
msconvert, BiblioSpec's `FullReaderList`, Skyline and any third party using
`DefaultReaderList`/`FullReaderList` - everyone who opens a file the normal way.

Same verdict rule as the downstream guards: settled per file, asymmetric. Out of order condemns
at any peak count and always wins; in order is only believed from a spectrum with more than 10
peaks. Held in a `std::atomic` because `spectrum()` is const and runs on worker threads, and
condemnation is an unconditional store while the good verdict is a compare-exchange from
unsettled, so no late-arriving good spectrum can un-condemn a file.

Spectra with anything other than exactly two binary data arrays are left alone: a third per-peak
array means combined ion mobility or a scanning quadrupole position, where m/z ascends only
within each block and a global sort would destroy the structure rather than repair it. Those
spectra are not treated as evidence about the writer either.

## Four hazards found in review of the design, all mitigated

1. **msconvert threading.** `msconvert.cpp:1086` does `dynamic_pointer_cast<SpectrumListWrapper>`
   and, when it succeeds, takes `benefitsFromWorkerThreads()` as authoritative. A universal
   wrapper always succeeds that cast, while the inherited `innerBenefitsFromWorkerThreads()`
   returns **false** when the inner list is not itself a wrapper - so every unfiltered conversion
   would have gone single-threaded. Overridden to defer to a real inner wrapper and otherwise
   report the pre-wrapper answer. Pinned by `testWorkerThreadAnswerIsUnchanged`.
2. **Invented DataProcessing.** `SpectrumListWrapper`'s constructor creates
   `DataProcessing("pwiz_Spectrum_Processing")` when the inner list has none, and `IO.cpp:2977`
   writes that id as `spectrumList/@defaultDataProcessingRef`. Applied universally that would have
   moved every reference mzML in the repository. Cleared in the constructor when the inner had
   none. Pinned by `testNoDataProcessingIsInvented`, and confirmed by `Reader_Waters_Test` staying
   green with no baseline churn.
3. **Vendor `dynamic_cast`s stay safe only because the wrap is last.** Every vendor reader casts
   `run.spectrumListPtr` back to its own concrete list inside `read()`, and
   `References::resolve()` casts it to `SpectrumListSimple`. Both run before the wrap. There is a
   comment in `Reader.cpp` saying so - do not move the call earlier.
4. **Pre-existing msconvert slip, not fixed here.** Line 998 computes into
   `configCopy.singleThreaded` and then reads `config.singleThreaded` on the next line, so on the
   merge path the threading query is dead. Line 1088 uses `configCopy` and is live. Worth
   mentioning to Matt; out of scope for this branch.

## Verification

- [x] `SpectrumList_MzOrderTest` - 7 cases: reordering with intensities still paired, sorted input
      untouched, the short-ordered-leader case a first-spectrum probe gets wrong, a condemned file
      staying condemned, combined IMS left alone, no invented DataProcessing, worker thread answer
      unchanged. `SpectrumList_MzOrderTest.passed`
- [x] End to end: the fixture through the rebuilt msconvert goes from 3 and 2 m/z descents to
      **0**, and prints the warning naming the first offending spectrum
- [x] `Reader_Waters_Test` green - no reference churn, including the combined-IMS configs
- [x] Whole `pwiz/data/msdata` unit suite green (MSDataTest, IOTest, ReferencesTest,
      SpectrumList_mzML_Test, Serializer_mzML_Test, ...)
- [x] `TestUnsortedMzArrays` green; mutation-verified on the Waters branch before the split
- [x] CodeInspection green; ReSharper whole-solution 0 errors 0 warnings, verified in
      `bin/x64/Release/InspectCodeOutput.xml` directly (336 bytes, zero `Issue` elements)
- [ ] `/code-review max` - **the gate before opening the PR**
- [ ] BiblioSpec `SpectrumTest` re-run after the comment change (comment-only, but unbuilt since)

## Why the downstream guards were kept rather than deleted

Both are now redundant for the common path, and both were kept deliberately - say so in the PR so
a reviewer does not read it as duplication that was missed.

- **Skyline** (`MsDataSpectrum.SetArrays`): Skyline runs against a `pwiz_data_cli.dll` that lags
  the pwiz tree, so the customer fix would otherwise wait on a CLI rebuild. Five other places
  build an `MsDataSpectrum` from arrays that never passed a reader.
- **BiblioSpec** (`PwizReader::ensureMzAscending`): still earns its keep for a different reason.
  `openFile` reads with `combineIonMobilitySpectra` on, and pwiz deliberately leaves those spectra
  alone - but BiblioSpec wants them flattened, because `SpectrumInfo::data` has no mobility axis to
  lose and `binPeaks()` merges only *adjacent* equal bins, so bin-concatenated input leaves
  same-bin peaks unmerged. `Spectrum::setRawPeaks` also stays, for `.blib` re-reads and copies,
  which never pass a reader at all.

## Open Questions / Unresolved

- **No opt-out knob.** The correction is unconditional. A `Reader::Config` flag would let someone
  see a file exactly as written; nothing needs it today, and our own diagnostics read the bytes
  directly rather than through pwiz.
- `std::sort` is UB on NaN m/z and `is_sorted` cannot screen it. Carried over from the earlier
  work unchanged; a NaN m/z means a corrupt file, but this is now on every read path rather than
  Skyline's alone, which is a stronger reason to decide.
- The wrapper allocates a `vector<pair<double,double>>` per reordered spectrum. Only on the
  already-broken path, so it has never been on a hot path in practice.
- **Tell Hans about the DATA Convert 5.0.0.2900 regression.** Still not done. Peaks ordered by
  ascending intensity instead of ascending m/z; 4.0.0.2619 is correct. Silent - every extraction
  reads as zero. Users can re-run their raw data once Waters ships a fix, which is the real remedy.
- Only `Reader_Waters_Test` was run for reference churn. The other vendor suites are expected to be
  unaffected (already-sorted data settles the verdict and nothing is reordered) but were not run.

## Data

`D:\data\lockmass\` - the customer files. `ai/.tmp/unsorted-fixture/` holds the synthesized
fixture, `ai/.tmp/check-mz-order.ps1` reports per-spectrum m/z descents straight from the mzML
bytes without going through pwiz, and `ai/.tmp/repack-unsorted-fixture.ps1` rebuilds the zip.
