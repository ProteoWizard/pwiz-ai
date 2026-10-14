# TODO-20260804_mzml_mz_sort_order.md

## Branch Information
- **Branch**: `Skyline/work/20260804_mzml_mz_sort_order`
- **Module**: `pwiz` - the point of the branch is now the pwiz-core read-seam correction; the
  Skyline and BiblioSpec pieces came along from #4498 and are secondary
- **Base**: `origin/master` @ `e7b5a917b` (branched from the tip on 2026-08-04)
- **Created**: 2026-08-04, split out of `Skyline/work/20260727_Waters_dataconvert_mzml_import`
- **Status**: **Completed.** Merged 2026-08-21.
- **GitHub Issue**: (none)
- **PR**: [#4552](https://github.com/ProteoWizard/pwiz/pull/4552) (merged 2026-08-21 as `641602c20`,
  `pwiz: handle disordered m/z arrays on read (#4552)`), label `pwiz`, opened 2026-08-08 from commit
  `bed52f708`. Approved by Matt Chambers
- **Copilot review**: one comment, on 2026-08-08, and it was right. The verdict comment claimed an
  out-of-order spectrum "always wins", but the function returns at the top once the verdict is
  `writerSortsByMz`, so a later out-of-order spectrum is never examined - the asymmetry only holds
  against a later *ascending* spectrum. Reworded in `53a134f8b` to state both halves and name the
  mixed-writer limitation, which `/code-review max` round 3 had also raised. Replied and pushed;
  no code behaviour changed
- **Reported by**: Hans
- **Cherry-pick to release**: **no** (Brian, 2026-08-09). No `Cherry pick to release` label.
- **Split from**: #4498, which keeps the Waters calibration/waters_connect story. Brian's call
  2026-08-04: the m/z sort issue is separate from the calibration scans issue.

## Working rule for this task (Brian, 2026-08-09)

**Do not commit or push without explicit clearance.** Overrides the standing commit authorization
for the remainder of this task. Stage and describe, then wait.

## TeamCity on #4552: 19 vendor test failures, and they are this branch's fault

Build `4127061` (Core Windows x86_64, commit `bed52f708`). The Wine/Docker build `4127072` that
the URL pointed at only inherited it - "Tests passed: 44, muted: 2; snapshot dependency failed".
Its own two red tests are muted known-failures and unrelated.

- **18 of 19**: every Waters (8), Agilent (8) and Mobilion (2) failure is a `config-combineIMS`
  variant failing `!diff_mz5` at `VendorReaderTestHarness.cpp:469`, with the warning firing on
  `merged=1 frame=1`. Combined ion mobility is being **globally sorted and its bin structure
  destroyed**. Cause: the mz5 writer keeps only two per-peak datasets and drops the mobility array,
  so on an mz5 round trip there is no CV term left for `hasNonMzOrderingAxis` to find. This is
  exactly `/code-review max` round 3 finding #7, which the TODO had waved off as "practical harm is
  limited". It is not limited.
- **1 of 19**: ABI `config-srmSpectra` fails the plain mzML diff (`!diff` at `:384`). SRM-as-spectra
  peaks are ordered by transition, not m/z - a legitimate order with no CV term marking it.

Root cause common to both: **the guard can only recognise an ordering axis when the format
preserved one.** Where it did not, legitimately-ordered data is indistinguishable from a broken
writer and gets silently rewritten - the very failure this branch exists to prevent. Compounding
it, vendor reads are not corrected while their mzML/mz5 representations are, so vendor data that is
not m/z-ascending no longer round-trips to itself.

Correction to something Claude said while triaging: narrowing to mzML does **not** fix all 19. The
ABI failure is on the mzML diff, so it survives any narrowing that keeps mzML. The two decisions are
independent.

**mz5 (18 failures)**: drop the call site. The reason is not provenance - Brian pointed out mz5 can
come from external sources - but that mz5 *discards* the arrays that would tell us an ordering axis
exists. `Configuration_mz5` has only `SpectrumMZ`/`SpectrumIntensity`, and
`VendorReaderTestHarness.cpp:465` sets `ignoreExtraBinaryDataArrays = true` for the mz5 diff alone,
which is the existing acknowledgement of that loss. Correcting m/z order there is necessarily blind.
**The underlying mz5 defect was looked at and consciously left alone (Brian, 2026-08-09): a
longstanding situation nobody cares about.** So this skip is permanent, not provisional. Detail, so
this decision does not depend on the abandoned TODO (`todos/completed/`):

- mz5 is *not* missing ion mobility generally. Non-combined IMS - one spectrum per drift bin,
  mobility as a scan-level cvParam - round trips fine through the generic `ParamListMZ5` on
  `ScanMZ5` (`Datastructures_mz5.hpp:678,734`). Grepping all of `pwiz/data/msdata/mz5` for
  `ion_mobility|drift` returns zero hits because none is needed.
- What is lost is the **per-peak** array of a *combined* IMS spectrum: `BinaryDataMZ5`
  (`Datastructures_mz5.hpp:795-814`) is a fixed x/y pair and an HDF5 `CompType`, and the writer
  takes only `getMZArray()`/`getIntensityArray()` (`Datastructures_mz5.cpp:3057-3061`). Signal-to-
  noise, baseline, resolution, charge and the scanning-quadrupole bounds go the same way.
- Consequence: `msconvert somePASEF.d --combineIonMobilitySpectra --mz5` is silently lossy, and has
  been for years. `VendorReaderTestHarness.cpp:465` sets `ignoreExtraBinaryDataArrays = true` for
  the mz5 diff alone - the existing acknowledgement, and why no test ever failed over it.

Which is exactly why `ensureMzAscending` must skip mz5: the per-peak mobility array is the only
marker that a combined-IMS spectrum is bin-ordered, and it is the one thing mz5 discards.

**ABI srmSpectra (1 failure)**: still undecided. MRM transitions rendered as spectra are ordered by
acquisition, not m/z, and nothing marks them - `SpectrumList_ABI.cpp` branches on
`experimentType == MRM` internally but never sets `MS_SRM_spectrum`, so no term survives into the
mzML. Options: set that term in the ABI reader and add it to the guard, or regenerate the reference
and accept that msconvert emits SRM spectra m/z-sorted. Less harmful than the mz5 case either way -
every (m/z, intensity) pair stays intact, only acquisition order is lost.

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

## Design (third and final shape - Brian, 2026-08-07)

**`SpectrumListBase::ensureMzAscending()`**, called by each open-format list on the way out of its
own `spectrum()`. No wrapper anywhere.

Brian's question - "is there no one chokepoint in the API where the m/z array is transferred to the
client?" - is what got here. There is: all seven open-format lists already derive from
`SpectrumListBase`, which its own header calls "common functionality for base SpectrumList
implementations" and which already hosts the `warn_once` this code uses. Each list has a single
internal funnel, so it is one call each in `SpectrumList_mzML/_mzXML/_MGF/_MSn/_mz5/_BTDX`.

The original note justified `ReaderList::read` by saying there was no lower chokepoint - but it was
looking for the moment the *arrays are assigned*, which really does differ per format. The moment
the *spectrum is returned* is shared, and that is the one that matters.

Cost: six explicit call sites, so an open format added later could forget - failing safe,
uncorrected, the same direction as before. Checked and not a problem: `Serializer_mzML::read`
always uses `SpectrumList_mzML::create` (`Serializer_mzML.cpp:304`), with `Index_mzML` scanning when
the file has no index, so there is no `SpectrumListSimple` on the reader path to miss.

### What this deleted rather than fixed

The two `/code-review max` rounds produced 15 findings between them; most were collateral from
interposing a universal wrapper, and are gone by construction:

- foreign index space through `findInChain` (the severe one - `SpectrumList_Filter` remaps
  index->originalIndex, so reaching past it called the vendor list with the wrong index and emitted
  entirely different scans, silently)
- `SpectrumList_3D` throwing, `SpectrumList_PrecursorRefine`'s dead Agilent branch,
  `SpectrumList_PeakFilter`'s first-filter copy guard, `calibrationSpectraAreOmitted` not forwarded
- vendor centroiding bypassing the correction; the `spectrum(seed, bool)` overload; the whole
  `benefitsFromWorkerThreads` transparency problem; invented `DataProcessing`

`SpectrumListWrapper`, `Reader.cpp`, `SpectrumList_PeakPicker`, `SpectrumList_LockmassRefiner`, the
CLI binding and msconvert are all back to master, untouched by this branch.

### Superseded designs, for the record

1. Wrap in `ReaderList::read` unconditionally - broke every bare `dynamic_cast` to a vendor list.
2. Wrap, but gate on `Reader::mayProduceUnsortedMz()` - rejected by review 1 as treating the
   symptom; it also pushed the question onto out-of-tree `Reader` implementers.
3. Wrap unconditionally + `findInChain()` at the cast sites - review 2 found the index-space
   defect. Claude recommended this one and was wrong.

## Design (superseded - kept for the reasoning about seams)

`SpectrumList_MzOrder` (`pwiz/data/msdata/`), inserted in `ReaderList::read` - both overloads -
immediately after the matching reader returns, for **every** reader. The multi-run overload wraps
only the runs that read appended, not the whole vector, because `msconvert --merge` accumulates
every input file into one vector and revisiting earlier runs would stack a second wrapper on each.

Consumers that reach for a concrete list after the read use `msdata::findInChain<T>()` - see "How
the vendor consumers survive the wrapper" below.

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

**Rewritten 2026-08-07 (Brian objected to the array-count test).** The guard used to be
`binaryDataArrayPtrs.size() != 2`, which did not implement what its own comment claimed: the comment
justifies the skip by naming *ordering axes*, the code counted arrays. It was wrong both ways.

- **Too permissive.** mzML per-peak *integer* arrays parse into `integerDataArrayPtrs`, a separate
  member of `Spectrum`. A `{m/z, intensity, charge}` spectrum counts 2, passed the guard, got
  permuted, and the charge array was written back unpermuted - the exact mispairing this class
  exists to prevent. Found by `/code-review max`.
- **Too restrictive.** A spectrum carrying any ordinary per-peak extra - signal-to-noise, baseline,
  resolution - was refused, so a genuinely intensity-ordered file went unrepaired and contributed
  no evidence either way. Also `/code-review max`.

Now: `hasNonMzOrderingAxis` asks the arrays by name - `cvIsA(..., MS_ion_mobility_array)` plus the
two scanning-quadrupole bound terms - and everything holding one value per peak is carried through
the same permutation, identified by length the way `ThresholdFilter::getExtraArrays` does it,
integer arrays included. The sort is now `stable_sort` over an index permutation, so peaks sharing
an m/z keep the order the writer gave them.

The residual is unchanged and still accepted: a combined-IMS file that genuinely *is* disordered
gets no repair, silently. And data concatenated by bin that carries **no** mobility array is
indistinguishable from a plain disordered spectrum and would be sorted.

**Correction (review 3):** the earlier note said that last case "needs a third-party file that
dropped the axis". Wrong - pwiz is that tool. `Configuration_mz5.hpp` defines exactly two per-peak
datasets, and `Datastructures_mz5.cpp` writes only the m/z and intensity arrays, so
`msconvert PASEF.d --combineIonMobilitySpectra --mz5` produces bin-concatenated peaks with no
mobility axis, and reading that back re-sorts them globally. The practical harm is limited - the
mobility information was already lost at write time, and nothing downstream can interpret the bins
without it - but the justification as written was false. The mz5 writer dropping per-peak arrays is
its own issue, not this branch's.

## The wrapper must not reach vendor readers (found 2026-08-07, Brian)

Brian asked whether wrapper order was safe for vendor peak picking. It was not. Hazard 3 below
covers the vendor `dynamic_cast`s *inside* `Reader::read()`, which do run before the wrap. But two
more sets of casts run **after** `ReaderList::read` returns, on the very pointer the wrap replaces:

- `SpectrumList_PeakPicker.cpp:71-123` casts the outermost list to each of nine vendor list types
  to select `mode_`. With a wrapper interposed all nine fail, `mode_` stays 0, and every
  `--filter "peakPicking vendor"` silently drops to `LocalMaximumPeakDetector(3)` or CWT.
- `SpectrumList_LockmassRefiner.cpp:45, 87, 112` casts to `SpectrumList_Waters`; on failure it
  falls to `inner_->spectrum(index, true)`, so Waters lockmass correction becomes a passthrough.
  Note line 44's comment "If there's a peak picker, it will be outermost" - that code hand-unwraps
  exactly one known wrapper type, so a universal wrapper defeats it by construction.
- Skyline inherits both: `MsDataFileImpl.cs:784, 793` builds them over the `MSDataFile` list.

Nothing warned. `msd.countFiltersApplied()` counts only factory-applied filters, so the existing
"peakPicking is not the first filter" warning at `SpectrumListFactory.cpp:376` stayed silent, and
`supportsVendorPeakPicking()` keys off the file path rather than the list.

**Why no test caught it**: `Reader_Waters_Test.cpp:73` constructs a bare `Reader_Waters` and the
harness calls `reader.read(...)` directly (`VendorReaderTestHarness.cpp:357, 625, 776`) - that is
`Reader_Waters::read`, never `ReaderList::read`. `ensureMzOrder` never fired anywhere in any vendor
suite, including the vendor-centroiding config at line 96. So the "Reader_Waters_Test green, no
reference churn" evidence said nothing about the wrapped path.

**First fix, since replaced**: a `Reader::mayProduceUnsortedMz()` flag, default false, overridden
true by the seven `DefaultReaderList` readers, so vendor lists were never wrapped. `/code-review max`
rejected it and was right - see below.

## How the vendor consumers survive the wrapper (final design, 2026-08-07)

The flag treated the symptom. The actual defect is that `SpectrumList_PeakPicker` casts `&*inner`
bare, nine times, and `SpectrumList_LockmassRefiner` hand-rolls a one-level peel through the peak
picker - while `SpectrumListWrapper::innermost()` has existed all along and
`SpectrumList_IonMobility.cpp:52-59` already uses it for exactly this. The flag made those casts
work again only by guaranteeing nothing was ever interposed, which means the next transparent
wrapper anyone adds breaks them again, silently. It also pushed the problem onto every `Reader`
implementer including out-of-tree ones, who inherit the wrong answer by default - and `Reader_UIMF`
and `Reader_ABI_T2D` sit under `vendor_readers/` but read files written by third-party desktop
software, so "peaks come from the instrument API already ascending" was never true for them.

**Final**: `msdata::findInChain<T>(SpectrumListPtr)` in `SpectrumListWrapper.hpp` - walks the chain
from the given list inward. Plain `innermost()` is not enough because `SpectrumList_PeakPicker`
looks for the *intermediate* `SpectrumList_LockmassRefiner`. Both consumers now use it; the peak
picker resolves once in its constructor into `vendorList_` rather than searching per spectrum.
`mayProduceUnsortedMz` and all its overrides are gone, and the wrap is unconditional again.

One behaviour note: the peak picker's nine casts were previously order-independent, because a bare
cast on one pointer can match at most one type. Searching a chain can match more than one, so the
lockmass refiner is now tested **first** - when one is present it is the thing to call, and it
reaches the Waters list itself.

This is also the shape Brian asked for: a completely pwiz-side fix, with clients unchanged.

## Four hazards found in review of the design, all mitigated

1. **Worker threads. Mitigation replaced 2026-08-07 - the first one was half right.** Callers ask
   the outermost wrapper and treat "not a wrapper" as nobody having an opinion. A wrapper on every
   read breaks that twice: it answers in place of a plain list, and it hides the list an outer
   wrapper meant to ask. The original fix - return `true` for a non-wrapper inner - fixed the first
   and caused the second, so `--filter "msLevel 2"` on an open format flipped from single- to
   multi-threaded (`/code-review max` #2). No bool can fix both: the same call needs opposite
   answers depending on who asks.

   The defaults are not even the same across callers, so each has to keep its own. msconvert leaves
   its tribool indeterminate and `bool(indeterminate)` is false, so **no opinion means threads on**
   (`msconvert.cpp:996, 1086`). The CLI binding returns `false` (`CLI/msdata/MSData.cpp:745`) and
   `MSConvertGUI/MainLogic.cs:549` assigns that straight to `useWorkerThreads`, so for the GUI **no
   opinion means threads off**.

   Now: `SpectrumListWrapper::isTransparentToWorkerThreads()`, false by default, true for
   `SpectrumList_MzOrder`; `msdata::workerThreadOpinion()` returns the outermost wrapper that is not
   transparent, or null; and `innerBenefitsFromWorkerThreads()` skips transparent wrappers on its
   way inward. All three callers use it, so every case answers exactly what it did before the
   wrapper existed. Pinned by `testWrapperIsTransparentToTheWorkerThreadQuestion`.
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

- [x] Rebuilt on `SpectrumListBase` 2026-08-07. `SpectrumListBaseTest` - 9 cases, extending the
      existing test rather than adding a file: reordering with intensities still paired, sorted
      input untouched, the short-ordered-leader case, a condemned file staying condemned, combined
      IMS left alone, combined IMS not vouching for the writer, a PDA/wavelength trace neither
      sorted nor treated as evidence, extra per-peak arrays (including an integer array) travelling
      with their peaks, and a metadata-only spectrum settling nothing
- [x] Wavelength guard mutation-verified: stubbing out the `MS_wavelength_array` test fails
      `SpectrumListBaseTest.cpp:265`
- [x] `pwiz/data/msdata` and `pwiz/analysis/spectrum_processing` suites green (108 targets) with
      the analysis layer back at master - nothing in it is touched by this branch any more
- [x] No line-ending churn and no tabs in the final diff. `SpectrumList_BTDX.cpp` has **mixed**
      endings in master (CRLF for the first 22 lines, LF after), so an Edit-tool insertion
      normalized the whole file and showed 46 changed lines for a 2-line change; re-applied with a
      byte-preserving replace. `SpectrumList_MSn.cpp` needed the same care to keep a
      trailing-whitespace line it already had
- [x] `SpectrumList_MzOrderTest` - 11 cases: reordering with intensities still paired, sorted input
      untouched, the short-ordered-leader case a first-spectrum probe gets wrong, a condemned file
      staying condemned, combined IMS left alone, no invented DataProcessing, worker thread answer
      unchanged, plus the three added 2026-08-07 for the vendor gate - a file-format reader is
      corrected through `ReaderList::read`, a vendor-like reader is left reachable by
      `dynamic_cast` on both read overloads, and every `DefaultReaderList` member opts in.
      `SpectrumList_MzOrderTest.passed`
- [x] `testMetadataOnlySpectrumSettlesNothing` - guards the behaviour the metadata gate preserves.
      `ensureMzAscending` now tests for actual peak data before anything else, because a
      metadata-only read still carries the array objects with their cvParams (`IO.cpp` builds those
      and skips only the base64 decode), so every metadata pass previously paid for the cvParam
      scans and, having no data, could never settle the verdict to stop paying. Skyline walks whole
      files that way. Sizes are read off the arrays rather than from `defaultArrayLength`, which
      `MSData.hpp` only guarantees from FullMetadata up. **Optimization only - no observable
      behaviour change, so the test is green before and after; it exists to stop a future change
      settling the verdict on an empty spectrum**
- [x] `testSeedOverloadReachesTheInnerList` - `SpectrumListWrapper` does not forward
      `spectrum(const SpectrumPtr& seed, bool)`, so the base at `MSData.cpp:1194` discards the seed
      and re-reads by index. mzML/mzXML implement it to seek to the binary data and keep the parsed
      header (`SpectrumList_mzML.cpp:124`), and `RAMPAdapter.cpp:248` asks for it by name.
      Forwarded in `SpectrumList_MzOrder`, which is safe only because it leaves the spectrum set and
      its indexing alone - a general passthrough in the base would be wrong for the filters, which
      remap the index. Mutation-verified: forwarding `seed->index` instead of `seed` fails the test
      at `SpectrumList_MzOrderTest.cpp:369`
- [x] `pwiz_data_cli` rebuilt after the CLI binding's `benefitsFromWorkerThreads` shim changed
- [x] End to end re-measured after the worker-thread change, both unfiltered and `--filter` paths:
      3 and 2 m/z descents to **0** in each
- [x] `testCombinedIonMobilitySpectrumDoesNotVouchForTheWriter`, added 2026-08-07. The existing IMS
      case uses a 4-peak spectrum - below the 10-peak threshold - so it could never have settled the
      verdict, and therefore never pinned the guard as being *ahead* of the verdict rather than just
      ahead of the sort. The new case puts a 20-peak globally ascending IMS spectrum in front of a
      disordered plain one: move the guard below the verdict logic and the IMS spectrum absolves the
      writer, so the broken spectrum after it goes out untouched
- [x] `testConcreteListStaysFindableThroughTheWrapper` - pins `findInChain` through one layer, two
      layers, and when the target is already outermost, and asserts the bare `dynamic_cast` that
      every one of those call sites used to make now finds nothing
- [x] `testMergeReadLeavesEarlierRunsAlone` - pins the `msconvert --merge` bug `/code-review max`
      found: reading a second file into the same vector must leave the first run's list the same
      object, still exactly one wrapper deep
- [x] Red before green: `testVendorReaderStaysReachableByDynamicCast` failed on the unconditional
      wrap (`SpectrumList_MzOrderTest.cpp:336`, `dynamic_cast<ConcreteSpectrumList*>` null) and
      passed once `ReaderList::read` gated on `mayProduceUnsortedMz()`
- [x] End to end: the fixture through the rebuilt msconvert goes from 3 and 2 m/z descents to
      **0**, and prints the warning naming the first offending spectrum. Re-measured 2026-08-07
      after the vendor gate, unchanged. Watch out for stale binaries when re-running this - the
      build tree holds several `msconvert.exe` under differently abbreviated path segments, and
      picking the wrong one reads as "the correction stopped working"
- [x] **The Waters reader IS built and exercised on this machine (corrected 2026-08-18, Brian).**
      The 2026-08-07 note below was wrong, and Claude repeated it on 2026-08-18 without checking.
      Measured: `SpectrumList_Waters.obj.rsp` carries `-DPWIZ_READER_WATERS`, the `.raw` fixtures are
      present in `Reader_Waters_Test.data`, and a `Reader_Waters_Test` run emits 28 `peaks were not
      written in ascending m/z order` warnings naming combined-IMS spectra (`merged=1 function=3
      block=1`) - which only a real read of real data can produce. Vendor behaviour on this branch
      **is** locally verified for Waters, Agilent, ABI and Mobilion.

      *Superseded reasoning, kept so it is not re-derived:* the note inferred from
      `pwiz_aux/msrc/utility/vendor_api/Waters/vc12_x64` holding "only 3 files" that
      `PWIZ_READER_WATERS` is never defined. A bare file count was never the right test - those three
      (`MassLynxRaw.dll`, `MassLynxRaw.lib`, `cdt.dll`) are what the build actually needs. Whatever
      the msconvert "support was explicitly disabled" observation was, it does not describe this tree
      now; check the `.rsp` defines rather than counting files
- [x] Whole `pwiz/data/msdata` unit suite green (MSDataTest, IOTest, ReferencesTest,
      SpectrumList_mzML_Test, Serializer_mzML_Test, ...). Re-run 2026-08-07 after the gate
- [x] `TestUnsortedMzArrays` green; mutation-verified on the Waters branch before the split
- [x] CodeInspection green; ReSharper whole-solution 0 errors 0 warnings, verified in
      `bin/x64/Release/InspectCodeOutput.xml` directly (336 bytes, zero `Issue` elements)
- [x] Re-run 2026-08-07 after the vendor gate: CodeInspection test 0 failures (13 sec), ReSharper
      full-solution 0 errors 0 warnings (325 sec). Verified in
      `pwiz_tools/Skyline/bin/x64/Debug/InspectCodeOutput.xml` directly - 336 bytes, scope
      `<Element>Solution</Element>`, `<IssueTypes />` and `<Issues />` both empty. Note the run was
      Debug; the 2026-08-04 evidence was the Release XML, same size and shape. Today's changes are
      C++ only, so neither gate actually covers them - this validates the branch's C# surface
- [x] `/code-review max` run twice. Round 1 drove the flag -> findInChain change; round 2 found the
      index-space defect in findInChain and a dozen wrapper-collateral issues, which is what led to
      dropping the wrapper. Both rounds reviewed designs that no longer exist
- [x] `/code-review max` round 3, on the `SpectrumListBase` design. No silent-wrong-output defect in
      the design itself this time. Acted on: two comments of Claude's that asserted things this
      branch had already disproved (that Skyline does nothing about m/z order - it sorts combined
      IMS in `SpectraChromDataProvider.EnsureSortedMzs` and `ScanProvider`, which a maintainer could
      have deleted as redundant; and that vendor peaks always arrive ascending, which does not hold
      for the readers whose input is a file another desktop tool wrote); `getArrayByCVID` instead of
      a hand-rolled cvParam loop; gather-then-swap so a throw part way through cannot leave m/z
      sorted against unsorted intensities; `swap` instead of `assign`; `std::iota`; and
      `reorderedAnySpectrum()` deleted - no production caller, and it answered false through any
      wrapper because `SpectrumListWrapper` never forwarded it. Declined: NaN (Brian's call, and the
      realized behaviour is an arbitrary-but-valid permutation, not a crash) and the mixed-writer
      verdict latch (documented trade-off; their own audit found all 11,784 spectra in the reported
      file disordered)
- [x] **Handed off - Brian has a PR in for it (2026-08-08).** `SpectrumList_BTDX.cpp:289`,
      `_mzXML.cpp:624`, `_MGF.cpp:98` and `_MSn.cpp:171` guard with `if (index > index_.size())`
      instead of `>=`, so the not-found sentinel `find()` returns passes the guard and indexes one
      past the end - mzXML does an out-of-bounds **write** to `scanMsLevelCache_`.
      `SpectrumList_mzML.cpp:132` and `_mz5.cpp:252` show the intended `>=`. Found by
      `/code-review max` round 3 on this branch, fixed separately since it predates it.
      No conflict expected with this branch: the guard is at the top of each function and the
      `ensureMzAscending` call is just before the return, 20+ lines apart in all four
- [ ] `TestUnsortedMzArrays` has never actually been executed. The Skyline test list is a generated
      file (`.gitignore:439`, "Skyline generated files"), so it needs no registration - but the test
      itself still wants a run against a rebuilt `pwiz_data_cli`
- [x] BiblioSpec `blib` rebuilds clean after the 2026-08-07 revert (25 targets), and no reference to
      `MzOrderVerdict` or `ensureMzAscending` remains anywhere under `pwiz_tools/BiblioSpec`

## The BiblioSpec changes were reverted (Brian, 2026-08-07)

All of it: `PwizReader::ensureMzAscending`, `MzOrderVerdict.h`, the `Spectrum::setRawPeaks` sort,
`SpectrumTest.cpp` and its `Jamfile.jam` target. `pwiz_tools/BiblioSpec` is byte-identical to
`e7b5a917b` again.

**Brian's call**: there are no reported BiblioSpec issues, and the changes are not warranted if pwiz
can be relied on to hand it sorted m/z. Repairing hypothetically bad existing `.blib` files is out
of scope for this branch.

Why that is safe, specifically:

- The reported defect stays covered with no BiblioSpec code at all. A DATA Convert mzML is a plain
  two-array non-IMS file, `Reader_mzML::mayProduceUnsortedMz()` is true, so pwiz corrects it before
  BlibBuild ever sees a peak.
- The revert cannot regress anything, because for the two cases pwiz does not cover - combined ion
  mobility, and `.blib` re-reads that never pass a reader - the result is exactly master's
  behaviour, which is what shipped for years.
- BlibBuild has built ion mobility libraries against bin-concatenated arrays for years with no
  reports. That is positive evidence against the `binPeaks()` concern rather than merely an absence
  of evidence.

What is knowingly left unaddressed, so it is not rediscovered as a surprise: `PwizReader::openFile`
reads with `combineIonMobilitySpectra` on, and pwiz deliberately leaves three-array spectra alone,
so BlibBuild receives peaks that roll over in m/z at each mobility bin boundary. Pre-existing,
unreported, and its own bug if it ever surfaces.

## Why the Skyline guard was kept rather than deleted

Now redundant for the common path, and kept deliberately - say so in the PR so a reviewer does not
read it as duplication that was missed. The reasoning that retired the BiblioSpec guards does not
transfer: Skyline runs against a `pwiz_data_cli.dll` that lags the pwiz tree, so the customer fix
would otherwise wait on a CLI rebuild, and five other places build an `MsDataSpectrum` from arrays
that never passed a reader at all. **Not yet re-examined against Brian's 2026-08-07 scope call.**

## Open Questions / Unresolved

- **No opt-out knob.** The correction is unconditional. A `Reader::Config` flag would let someone
  see a file exactly as written; nothing needs it today, and our own diagnostics read the bytes
  directly rather than through pwiz.
- **NaN m/z: decided, no guard (Brian, 2026-08-07).** `/code-review max` wanted this handled, on the
  grounds that `is_sorted` false-positives on NaN and `std::sort` with a bare `<` is UB. Brian's
  call: pwiz has never worried about NaN in this context, and the tree agrees - there is no `isnan`
  anywhere in `pwiz/analysis/spectrum_processing`, and `pwiz::util::sort_together`, the in-tree
  helper for this exact operation, screens nothing either. m/z binary search is everywhere in pwiz,
  so a NaN m/z is already a broken file long before it reaches this class. The branch does not
  change that exposure, which is the criterion. The review's companion argument - that the C# twin
  documented the assumption while the C++ did not - died with the C# revert.
- `pwiz::util::sort_together` was considered for the permutation and does not fit: it takes a range
  of same-typed containers, and this applies one permutation across both the `BinaryData<double>`
  extras and the `BinaryData<int64_t>` integer arrays.
- The wrapper allocates a `vector<pair<double,double>>` per reordered spectrum. Only on the
  already-broken path, so it has never been on a hot path in practice.
- **Tell Hans about the DATA Convert 5.0.0.2900 regression.** Still not done. Peaks ordered by
  ascending intensity instead of ascending m/z; 4.0.0.2619 is correct. Silent - every extraction
  reads as zero. Users can re-run their raw data once Waters ships a fix, which is the real remedy.
- Only `Reader_Waters_Test` was run for reference churn. The other vendor suites are expected to be
  unaffected (already-sorted data settles the verdict and nothing is reordered) but were not run.
- **Reviewed and accepted, do not re-litigate (Brian, 2026-08-19).** `/code-review max` raised both
  again; both are deliberate, so a later review pass finding them is not a new finding.
  - The primary vendor-vs-reference `Diff` is order-asymmetric by design: vendor `SpectrumList`s are
    not given `ensureMzAscending`, while the reference `.mzML` they are compared against is corrected
    when read back through `SpectrumList_mzML`. Accepted.
  - `assertMzAscending` reads its spectra back through the same reader that just corrected them, so
    it confirms the correction fired rather than independently proving the writer preserved order.
    Accepted; it is not the writer check its comment reads like.
- **Two latent edge cases from `/code-review max`, 2026-08-18 - noted for later, not fixed (Brian:
  uncommon).** Both narrow enough that no test currently covers them.
  - `SpectrumListBase.cpp:163` gathers any `binaryDataArrayPtrs[i]` whose length merely equals the
    peak count into the m/z permutation, with no check that it is actually per-peak. mzML has a
    first-class way to declare an array's length independent of the peak count -
    `MS_external_array_length`, which pwiz's own mzML writer emits (`IO.cpp:2046`) whenever an
    array's length differs from `defaultArrayLength` - so a non-per-peak array whose length
    happens to coincide with the peak count would get silently permuted, pairing it with an
    unrelated peak. Fix would check for `MS_external_array_length` (or otherwise confirm per-peak)
    before including an array.
  - `Diff.cpp:63`, `peaksInCanonicalOrder`: ties on exact `!=`, but the value comparison that runs
    afterward (`Diff.cpp:400` and siblings) uses `config.precision + epsilon()`, a tolerance. Two
    peaks agreeing to within tolerance but not exactly can canonicalize as tied on one side of a
    lossy round trip and distinct on the other, pairing the wrong peaks. Concrete trigger: MGF
    writes m/z at `setprecision(10)` (`Serializer_MGF.cpp:77`), so two peaks agreeing to 10 digits
    but not beyond would tie pre-write and split post-round-trip. Latent only - the dominant real
    case (same calibration reused across ion-mobility bins) produces exact ties on both sides - not
    shown to currently trigger.

## Data

`D:\data\lockmass\` - the customer files. `ai/.tmp/unsorted-fixture/` holds the synthesized
fixture, `ai/.tmp/check-mz-order.ps1` reports per-spectrum m/z descents straight from the mzML
bytes without going through pwiz, and `ai/.tmp/repack-unsorted-fixture.ps1` rebuilds the zip.

## Progress Log

### 2026-08-21 - Merged

PR #4552 merged as `641602c20`. What shipped: `SpectrumListBase::ensureMzAscending()`, called on the
way out of `spectrum()` by the six open-format lists, putting peaks into ascending m/z order when the
writer did not and carrying every per-peak array along with them. `hasNonMzOrderingAxis()` exempts
the spectra whose peak order means something else - combined ion mobility, scanning quadrupole,
diode-array wavelength, and SRM/CRM transition lists. `DiffConfig::ignorePeakOrder` lets a round trip
through a format that drops the mobility array compare as a set of peaks rather than an ordered list.

Fixed along the way, all found by TeamCity rather than locally: the four original vendor failures
(Waters, Agilent, Mobilion, ABI); a Bruker regression the branch itself introduced, where MGF's ten
significant digits manufactured up to 50 exact m/z ties per centroided PASEF spectrum that the vendor
side did not have; a merge artifact that left `PwizFileInfoTest.cs` uncompilable; a `--without-mz5`
build break; an over-broad `MS_SIM_spectrum` exemption that would have disabled the repair for
ordinary Thermo and Agilent scans; and `Configuration_mz5::doTranslating_` read uninitialized on the
non-zlib path.

New permanent coverage: three `ignorePeakOrder` tests in `DiffTest` (which had none), SRM/SIM tests
in `SpectrumListBaseTest`, and two mz5 serializer tests. Per Matt's review, `sort_together` gained a
two-range-set overload so `ensureMzAscending` could use it instead of hand-rolling the permutation.

**Lesson worth keeping**: verifying only the vendor readers that were already red is what let the
Bruker regression through - `VendorReaderTestHarness.cpp` is shared by every reader, so a change
there can break a green one. All eight readers are runnable on this machine (see the corrected note
above); run all of them.

Deferred deliberately, and recorded under Open Questions above: the verdict latch's mixed-writer
limitation, NaN handling, the vendor-vs-reference diff asymmetry, `assertMzAscending` reading back
through the corrected reader, and the two latent `Diff.cpp` / `SpectrumListBase.cpp` edge cases.
Still open and unrelated to the merge: telling Hans about the DATA Convert 5.0.0.2900 regression.
