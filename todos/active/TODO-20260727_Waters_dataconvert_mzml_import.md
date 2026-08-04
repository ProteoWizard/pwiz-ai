# TODO-20260727_Waters_dataconvert_mzml_import.md

## Branch Information
- **Branch**: `Skyline/work/20260727_Waters_dataconvert_mzml_import`
- **Module**: `skyline` - the reported defect is a Skyline import failure and the fix lives in
  `ProteowizardWrapper`; the pwiz-side changes (TIC, wrapper forwarding) are in support of it
- **Base**: `master` @ `55cedad25`
- **Created**: 2026-07-27
- **Status**: Awaiting re-review. Phases 1-10 committed and pushed, all gates green. Matt's
  CHANGES_REQUESTED (2026-08-03) answered in 5f88ea972 plus replies on all four threads; his
  re-review is the only thing outstanding. **Start at Phase 11.**
- **GitHub Issue**: (none)
- **PR**: https://github.com/ProteoWizard/pwiz/pull/4498
- **Cherry-pick to release**: no - Brian decided 2026-07-29, do not add the label
- **Copilot review**: 2 comments, both refuted and resolved. Both claimed `int? > int`
  yields `bool?` and would not compile; lifted relational operators return `bool`, false
  when either operand is null, and the solution builds clean. That behavior is the
  mechanism the fix relies on - see the replies on the PR.

## Objective

Waters mzML files fail to import into Skyline - every spectrum is silently discarded.
Fix that, and remove the guesswork that causes it.

## Context

Reported by Hans Vissers (Waters) on the "Importing Xevo MRT P10 data into Skyline from
mzML" thread. Five failing cases were supplied, in `D:\data\lockmass\`.

Root cause: `MsDataFileImpl.SpectrumList` (~line 804) infers which Waters *function* is
the lockspray by assuming the first MS1 spectrum belongs to it if its function number is
> 1, then skips that function and all higher ones. The function number is parsed
positionally from the dotted abbreviation of the nativeID.

Waters' DATA Convert (waters_connect) writes `channel=2 process=0 spectrum=1 scan=1`
rather than the PSI Waters format `function=N process=M scan=K` (MS:1000769). Skyline
reads the *channel* number as a function number, so the first MS1 at `channel=2` sets the
lockmass function to 2 and every spectrum at channel >= 2 is discarded - in the DDA file
that is all 57,164 spectra.

The heuristic exists only because mzML had no way to say "this scan is a calibration
scan". `MS:1000928 calibration spectrum` is exactly that term, and pwiz already uses it in
the UIMF reader - but never for Waters.

Key facts established with Waters (Ian Morns, 2026-07-27):
- waters_connect calls them "channels" where MassLynx says "functions"; the id may also
  carry `spectra=19,21` (a merged list, already merged in the output), and `scan=` is just
  index+1 and carries no meaning.
- "DataConvert doesn't usually include the lockmass spectra in the mzML output, instead it
  lockmass corrects the spectra before exporting." So for these files there is no lockmass
  function to find.
- "SONAR pulse" is not regular SONAR - it is 1 wide-open MS1 plus adjoining quadrupole
  windows tiling the range, i.e. ordinary DIA. Regular SONAR is not supported by DATA
  Convert yet.

## Implementation Plan

### Phase 1: msconvert tags lockmass scans (DONE - commit 599327b29)

- [x] `SpectrumList_Waters::lockMassFunction()` extracted so the lookup is forced rather
      than depending on `createIndex()` having primed the cache
- [x] `calibrationSpectraAreOmitted()` fixed to use it (previously returned a wrong
      `false` in DDA mode, where `createDDAIndex()` never primes the cache)
- [x] `hasCalibrationSpectra()` added - asks the index, so it stays correct whether the
      lockmass function was dropped by `ignoreCalibrationScans` or by the DDA processor
- [x] Per-spectrum `MS:1000928` set additively alongside the existing spectrum type
- [x] `Reader_Waters` sets `MS:1000928` in `fileContent`, and skips the lockmass
      function's contribution entirely when its spectra are not present

Additive, not a replacement, because `MS_calibration_spectrum`'s CV parent is
`MS_spectrum_type`, not `MS_mass_spectrum`. `SpectrumList_Waters.cpp:163` gates m/z units,
collision energy, ms level, polarity, scan windows and the precursor block on
`cvIsA(spectrumType, MS_mass_spectrum)`, so replacing the type would strip all of it.

Verified:
- msconvert on `SONAR_Short.raw`: 600 spectra, `MS:1000928` on exactly the 200
  `function=3` spectra plus one in `fileContent`; those spectra keep `MS1 spectrum`,
  `ms level 1`, polarity, profile, TIC.
- `--ignoreCalibrationScans`: 400 spectra, **zero** `MS:1000928` anywhere including
  `fileContent` - absence is truthful.
- `HDDDA_Short_noLM.raw` control: zero tags.
- No Skyline-visible change: Skyline never sets `ddaProcessing`, so the one behavioural
  delta from the `calibrationSpectraAreOmitted()` fix is unreachable from Skyline. Also
  note Skyline currently runs against a `pwiz_data_cli.dll` built 2026-07-25; picking up
  this change at all would need the CLI bindings rebuilt and restaged into
  `pwiz_tools/Shared/ProteowizardWrapper/obj/x64/`.

### Phase 2: Reference mzMLs (DONE - commit 249389cb7)

Regenerated the 10 references whose raw has a lockspray function; reverted the other 21,
which regeneration had churned with path/version noise only. `Reader_Waters_Test` is green
at 62 of 62.

Verified the baseline first: on unmodified source with the original references the test
passes completely, so every difference is attributable to this change. One wrinkle worth
knowing - `ATEHLSTLSEK_profile-centroid` also picks up longer m/z decimals
(`51.80574` -> `51.805736541748`). Same values, more digits; well inside the harness
`diffPrecision` of 1e-5, which is why the baseline passed on the shorter form.

### Phase 2 (historical) - the decision that was taken

`Reader_Waters_Test` fails 20 of 62. Every failure is one of 10 reference mzMLs whose raw
has a lockspray function, each counted twice because of the automatic `threshold-top3`
pass: `MSe_Short` (+`-globalChromatogramsAreMs1Only`), `ATEHLSTLSEK_profile`
(+`-centroid`), `ATEHLSTLSEK_LM_684.3469`, `ATEHLSTLSEK_LM_785.8426`, `SONAR_Short`
(+`-combineIMS`, +`-combineIMS-mzMobilityFilter`), `091204_NFDM_008`.

Controls all pass: no `HD*_noLM`, no `Minimal_DDA`, no `DDA_IsolationWindow`, no
`ddaProcessing`, no `ignoreCalibrationScans` failures.

Per instruction the checked-in references were **not** regenerated. Proposed replacements
were generated into `C:\Dev\ai\.tmp\waters-calspectra\` instead and diffed. The only
substantive change is added `MS:1000928` lines - 2 for `MSe_Short` (1 spectrum + 1
fileContent), 201 for `SONAR_Short` (200 + 1). Everything else in the diff is the
scratch-dir `sourceFile location` and stale cvList/pwiz version strings, all of which the
harness neutralizes at compare time (`mangleSourceFileLocations`, `manglePwizSoftware`).

**Decision needed:** these are expected-output fixtures, so a given config has exactly one
reference and adding files alongside does not help - nothing would read them. Either
regenerate those 10, or add new `.raw` test data that has a lockspray function so the new
behaviour gets fresh references without touching the old.

To regenerate:
```
quickbuild.bat -q toolset=msvc address-model=64 --i-agree-to-the-vendor-licenses ^
  --abbreviate-paths --incremental --generate-mzML -j4 pwiz/data/vendor_readers/Waters
```

### Phase 3: Skyline stops guessing (DONE - commit 5753f6b63)

- [x] `MS:1000928` honored wherever it appears (`MsDataSpectrum.IsCalibrationSpectrum`)
- [x] waters_connect ids recognized (`IsWatersConnectNativeId`); no lockmass inferred from them
- [x] Function number parsed by nativeID layout, null when the layout carries none
- [x] MSe level falls back to the declared MS level when there is no function number
- [x] `TestWatersCalibrationSpectrum` in `PwizFileInfoTest`, over an untagged/tagged mzML
      pair built from `MSe_Short.raw` (`TestData\WatersLockmassMzml.zip`), plus a
      table over all five real nativeID shapes

Verified against the real customer files:
- 06_DDA: 0 -> 30 non-zero peaks, 245 KB skyd
- 05_MSE: 4 -> 5 peaks, matching the raw import exactly; area 1,697,928 vs raw
  1,755,175 at the same RT
- Waters regression suite green (`WatersImsMse*`, `TestTicChromatogram`,
  `TestInstrumentInfo`, `WatersFileTypeTest`, `WatersCacheTest`), CodeInspection green

**The version gate (old case 3) turned out to be unnecessary and was dropped.** For
msconvert output the heuristic already lands correctly in every case: with lockspray
present it sorts first so the guess is right, and with `--ignoreCalibrationScans` the
first MS1 is function 1 so nothing is inferred. The only place the guess was ever wrong
is the waters_connect dialect, which is now handled directly. No need to parse
date-encoded pwiz revisions.

### Phase 3 (original plan, for reference)

**Requirement: Skyline must be shown to handle both kinds of mzML** - older files where
the lockmass function has to be guessed, and newer files where it is labelled. A proven
fixture pair exists, both converted from `MSe_Short.raw` (3 spectra, lockspray is
function 3, which msconvert puts at index 0 so the heuristic genuinely fires):

| | old style | new style |
|---|---|---|
| built by | pwiz 3.0.26200 (pre-change) | pwiz 3.0.26208 (this branch) |
| `function=3` lockspray spectra | 1 | 1 |
| `MS:1000928` | 0 | 2 (spectrum + fileContent) |

Currently staged in `C:\Dev\ai\.tmp\waters-calspectra\MSe_Short_{old,new}style.mzML`; they
need a permanent home in Skyline test data. The assertion is that importing both yields
identical chromatograms - old via the heuristic, new via the tag.


Four-way logic, replacing the current two-way:

1. `MS:1000928` present - skip exactly those spectra.
2. nativeIDs are the waters_connect dialect (`channel=`/`spectrum=`/`spectra=`) - assume
   no lockmass function, skip only what is explicitly tagged.
3. Tag absent and the file identifies as a pwiz Waters reader at or after the revision
   Phase 1 lands - authoritative "none".
4. Otherwise - the existing heuristic, unchanged. **It is not going away**: every existing
   mzML, and anything from a writer that is not a new-enough msconvert, carries no tag and
   no way to distinguish "none" from "never says".

**Case 2 is the actual customer fix and is independent of Phase 1** - no tagging, no
version gate, no cooperation from Waters. It alone would fix every file in the thread.
Consider shipping it first.

Discriminate case 2 on the **nativeID dialect, not the software terms**. The terms are not
stable across DATA Convert versions - the working Aug-2025 K562 file has plain
`MS:1000694` and no DATA Convert software entry, while the failing Jul-2026 file has
`MS:1003382 waters_connect` and `data_convert_4.0.0.2619`. `channel=` is on all five
sample files across both vintages, and appears nowhere in the pwiz source.

Better still for case 1: have pwiz honour `ignoreCalibrationScans` generically for any
input that declares calibration spectra, not just the Waters raw reader. Skyline already
sets the flag unconditionally, so it would get correct behaviour on tagged mzML with no
Skyline change at all.

### Phase 4: Review response (DONE - 17 commits total, tree clean)

Two `/code-review max` rounds. Round 1: 15 findings, acted on 9, pushed back on 2. Round 2 (on the
enlarged diff): 15 findings, acted on 6, refuted 1. Both rounds also ran `inspect` - CodeInspection
green, ReSharper solution-wide clean with **zero findings on any changed line** (checked by
intersecting `git diff -U0 55cedad25...HEAD` line ranges against the SARIF, not by eye).

Substantive things the reviews caught that testing did not:

- `SpectrumList_LockmassRefinerTest` was broken and unnoticed - a second reference suite built from
  the same raw. See [[reference_vendor_reference_mzml_regeneration]].
- `_mseLevel` could latch to 0 and silently disable all-ions handling for the rest of a file.
- `SpectrumListWrapper` did not forward `calibrationSpectraAreOmitted`, so the pwiz-side fix was
  invisible to Skyline whenever the list was wrapped.
- `cvParamChildren` is the only member of that family without the null-`paramGroupPtr` guard; the
  first attempt at the order-independence fix could have dereferenced null. `hasCVParamChild` is
  guarded, allocation-free, and was already used in the same file.
- The lockmass test could not detect deletion of the branch it existed to cover, and
  `ignoreCalibrationScans` had no C++ coverage at all (its only config used a file with no lockspray).
  Both now mutation-verified.

Refuted with evidence: the reviewer's claim that regenerated m/z values indicated drift or a dirty
tree. All 16 values are exactly the 5-decimal rounding of the new 12-decimal ones - identical
computation, different serialization precision.

**Still open from the reviews, deliberately.** None affect the customer cases:

- `_mseLevel` aliases function numbers with MS levels, losing the ">2 means ignore" state. Design
  question. Mitigated: DataConvert removes lockspray and survivors are tagged.
- All eight `cvParamChild(MS_spectrum_type)` sites are first-child-wins again after Phase 6 - the
  msLevel predicate fix went back with the rest. Safe inside pwiz, because no pwiz writer emits
  two children of `spectrum type`: the Waters writer is gone, and UIMF sets
  `MS_calibration_spectrum` *as* the type rather than additively
  (`SpectrumList_UIMF.cpp:106`). A third-party mzML carrying both terms could still be
  misread by the msLevel predicate, but that was equally true before this branch - pre-existing,
  and not this PR's to own.
- `IsCalibrationSpectrum` is still computed for every vendor. Gating it on `IsWatersFile` would make
  the property lie for UIMF, which legitimately uses MS:1000928.
- `WatersFunctionNumber` re-derives what `MS_preset_scan_configuration` already carries - two
  sources of the same fact that could disagree.
- `int.TryParse` on the function value is culture-sensitive; this file parses machine-generated
  numbers correctly elsewhere with `NumberStyles.Any, CultureInfo.InvariantCulture`.
- `fileContent` consistency - filed as https://github.com/ProteoWizard/pwiz/issues/4499. Three related faults,
  one cause: `fillInMetadata` derives fileContent from a parallel walk over function types rather
  than from what is actually indexed or emitted.
  - Over-declares: createIndex drops SIM, CNL, CNG and (without srmAsSpectra) SRM functions while
    fileContent still advertises them. `160109_Mix1_calcurve_070.mzML` announces "SRM spectrum"
    while holding none.
  - Under-declares: the MSe high-energy reclassification happens per-spectrum in
    `SpectrumList_Waters::spectrum()`, so `MSe_Short.mzML` carries a spectrum with
    `MS:1000580 MSn spectrum` and ms level 2 while fileContent lists only MS1. Note this is an
    internal contradiction in the file, not a claim that MSE is really MS2 - it is all-MS1
    acquisition with alternating CE, and pwiz *chooses* to present the high-energy function as MSn.
    A review round claimed this makes Skyline "alternate 1/2 instead of trusting the declared ms
    level" via `SpectrumFilter.cs:893` - **that consequence is wrong**: line 893 is inside
    `else if (!_isWatersMse)`, unreachable for Waters all-ions, and `_sourceHasDeclaredMSnSpectra`
    self-heals at line 846 from the first ms-level-2 spectrum anyway. No demonstrated misbehavior.
  - Committed pre-filter: `fillInMetadata` runs before any wrapping or filtering, so msconvert with
    a spectrum-dropping filter yields an mzML whose fileContent claims MS:1000928 while no surviving
    spectrum carries it. This is the one that undercuts the contract PR #4498 relies on.

### Phase 5: Third review round + the TIC fix (DONE - 20 commits, tree clean)

A third `/code-review max` returned 5 findings, down from 15 in each earlier round. It also verified
several things clean: all 32 baselines present and correctly tagged, the five `-ddaProcessing` ones
correctly untagged, no dangling sentinel, no test registration needed beyond the csproj entry.

**Fixed: the global TIC summed the lockmass function even when its scans were excluded.**
`ignoreCalibrationScans` kept lockspray out of the spectrum list, but `ChromatogramList_Waters` never
honored the flag, so the TIC carried points no spectrum accounted for. The new baseline made it
visible - `spectrumList count="2"` beside `defaultArrayLength="3"`. Skyline sets that flag on every
open, so its reported TIC maximum for `MSe_Short` was the lockspray scan's own signal (3,286,253)
rather than the sample's (2,912,084). Pre-existing and user-visible; `TestTicChromatogram` updated
from `(2, 3286253)` to `(1, 2912084)`.

Verifying that needed a from-source build - Skyline had been running against a `pwiz_data_cli.dll`
predating the branch. A manual attempt to restage it broke Skyline entirely ("side-by-side
configuration is incorrect"): the pipeline uses a **`without-cxt`** binding variant, built without
the embedded MSVC runtime assembly, and a default-variant build is not a drop-in. Backed out; Brian
did a clean build, after which the derived value passed.

**Fixed: the test fixtures embedded absolute machine paths.** Scrubbed to bare filenames as pwiz does
via `mangleSourceFileLocations`. Note the fixtures must be generated with `--noindex` first - an
indexed mzML stores byte offsets, and shortening earlier content invalidates every one of them
("Bad istream"). The scrub script now refuses an indexed file rather than corrupting it.

**REFUTED - do not act on these two.**

1. *"The reference m/z values drifted, possibly from a dirty tree."* All 16 values are exactly the
   5-decimal rounding of the new 12-decimal ones. Identical computation, different serialization.
2. *"The pre-existing `HDDDA` ignoreCalibrationScans config is vacuous and superseded."* **It is not -
   leave it alone.** `git log -S` traces it to 27f6f8dbf (Matt Chambers, June 2023), *"fixed errors
   caused by assuming lockmass function is not IMS: Invalid Scan Number exceptions (reported by
   Pierre)"*, which removed exactly that assumption from `SpectrumList_Waters.cpp`. It is a **crash
   regression test** for `ignoreCalibrationScans` + `combineIonMobilitySpectra` + `peakPickingCWT`,
   as its own comment says ("CWT should work with ion mobility"). The byte-identical baseline is the
   assertion, not evidence of waste: the raw has no lockspray, so enabling the flag *should* change
   nothing, and the property pinned is "identical output, no exception". The new `MSe_Short` config
   does not supersede it - that one has no ion mobility and no CWT, so it could never catch Pierre's
   crash, while `HDDDA` has no lockspray so it cannot assert suppression. They are complementary.

Calibration note: two of round 3's five findings were overstated, versus one refutation in round 2.
Verify before acting, especially where a finding recommends deleting existing coverage.

### Phase 6: Withdrew the writing half - honor MS:1000928, never emit it (IN PROGRESS)

**Decision (Brian, 2026-07-29): do not write "calibration spectrum"; honor it if encountered.**
Phases 1 and 2 - msconvert tagging lockspray scans and the 13 regenerated reference mzMLs -
are reverted in the working tree. The read side (Phase 3) is untouched and is the whole
customer fix on its own.

Why the asymmetry is the right trade: honoring the term costs nothing and works for any
writer that emits it, including the UIMF reader which already does. Emitting it would have
committed pwiz to a guarantee `fillInMetadata` cannot keep - see the "committed pre-filter"
fault in https://github.com/ProteoWizard/pwiz/issues/4499, where fileContent is derived before
any wrapping or filtering, so msconvert with a spectrum-dropping filter would write an mzML
declaring MS:1000928 while no surviving spectrum carries it. That is precisely the contract a
consumer would have to trust. Withdrawing the writer leaves #4499 as the prerequisite rather
than shipping a claim we would then have to qualify.

Reverted, and now byte-identical to master (verified, not assumed):
- Per-spectrum `MS:1000928` in `SpectrumList_Waters::spectrum()`
- `hasCalibrationSpectra()` and the fileContent `MS:1000928` logic in `Reader_Waters.cpp`
- `SpectrumList_Filter.cpp`'s `hasCVParamChild` order-independence fix, and the three
  `SpectrumList_LockmassRefinerTest` baselines. The multi-spectrum-type situation was ours to
  have created; with no writer, nothing in pwiz emits two children of `spectrum type`, so
  first-child-wins is correct again.
- All 13 regenerated `Reader_Waters_Test.data` references

Deliberately kept, all independent of tagging:
- `MsDataFileImpl.cs` - waters_connect dialect, nativeID-layout function parsing, and
  `MS:1000928` honored wherever it appears
- `ChromatogramList_Waters.cpp` global TIC fix
- `SpectrumListWrapper` forwarding `calibrationSpectraAreOmitted`
- Constructor-time lockmass resolution in `SpectrumList_Waters`
- The new `MSe_Short` `ignoreCalibrationScans` config and its baseline. Checked against the
  reverted code path: its fileContent is `MS1 spectrum` only, and post-revert the lockspray
  function (MS1 type) contributes `MS1 spectrum` as well, so the baseline is still correct and
  does not need regenerating.
- `MSe_Short_tagged.mzML` in `WatersLockmassMzml.zip`. It no longer represents our own
  msconvert output - it stands in for a writer that labels, which the standard permits and
  UIMF already does. The test comment says so.

Remaining:
- [x] `Reader_Waters_Test.cpp:134` comment no longer claims the term is "withheld from
      fileContent"; it now points at the global TIC, which is what that config actually shows
- [x] Staged the comment rewrap in `SpectrumList_Waters.cpp` with the rest
- [x] Deleted stray untracked `DiannSearchControlLog.txt`
- [x] `Reader_Waters_Test` green - 64 configs, 269 targets, on the reverted baselines
- [x] `SpectrumList_LockmassRefinerTest` and `SpectrumList_FilterTest` green, along with the rest
      of `spectrum_processing`. Note bjam prints `testing.unit-test <name>.passed` for these and
      `**passed**` only for run-tests, so grepping for `**passed**` alone under-reports the suite
- [x] `TestWatersCalibrationSpectrum` and `TestTicChromatogram` green (Release; the clean build
      was Release, and `Run-Tests.ps1` defaults to Debug - it reports "TestRunner.exe not found"
      and still exits 0, so check its output rather than trusting the exit code)
- [x] `CodeInspection` green, and the full ReSharper whole-solution inspection re-run on the
      final head (2026-07-30): **0 errors, 0 warnings solution-wide**. Verified against
      `bin/x64/Release/InspectCodeOutput.xml` directly - 336 bytes, zero `Issue` elements -
      not just the script's summary line. Stronger than the earlier rounds, which only
      established zero findings on changed lines.
- [ ] Commit, push, and replace the PR #4498 body with `ai/.tmp/pr-body.md` (rewritten to match
      "Nothing here writes it", and corrected twice since: it listed `SpectrumList_FilterTest`,
      which has no test target, and described two fixtures rather than three)

### Phase 7: File-level coverage for the reported shape (IN PROGRESS)

The gap Brian caught: nothing in the repo opened a waters_connect file. Coverage of the actual
defect was unit-level (`WatersFunctionNumberFromNativeId("channel=2 ...")` returns null) plus
synthetic `MsDataSpectrum` objects. That does guard the root cause against a positional-parsing
regression, but no test read a file in the dialect and asserted its spectra survived. Checked:
`WatersLockmassMzml.zip` only ever held the two `MSe_Short` files, in both of its revisions.

**Why no small real file could close it.** Surveyed all of `D:\data\lockmass\`. The failure needs
*both* a leading MS1 at `channel >= 2` **and** further spectra at that channel or above, and only
the two largest files have that shape:

| file | size | spectra | ids | reproduces? |
|---|---|---|---|---|
| `01_ToFMRM/...TofMRMchrom.mzML` | 321 KB | 0 (46 chroms) | - | no - no `spectrumList`, and no `MS:1000526`; OpenMS `FileConverter` output |
| `01_ToFMRM/...Tof MRM.mzML` | 17 MB | 4494 | all `channel=1` | no - 1 is not `> 1`, so nothing was ever inferred |
| `03_.../250 fmol%2FuL_noMS1.mzML` | 33 MB | 2021 | `channel=3..22` | no - all ms level 2, and the heuristic keyed on the first MS1 |
| `04_SONARpulse/SONAR_Short.mzML` | 2 MB | 600 | `function=1..3` | n/a - our own msconvert output |
| `06_DDA/260701PP...mzML` | 782 MB | 57,164 | `channel=2` MS1 then `channel=3` | **yes** |
| `05_MSE/41 ng...mzML` | 1.1 GB | - | `channel=2` MS1, `channel=3` | **yes** |

So the minimum faithful reproducer is two spectra: `channel=2` at ms level 1 followed by
`channel=3` at ms level 2.

**Decision (Brian, 2026-07-29): synthesize now, add a trimmed real file later once cleared.**

- [x] `MSe_Short_watersconnect.mzML` added to `WatersLockmassMzml.zip`, built from our own
      `MSe_Short_untagged.mzML` by `ai/.tmp/make-watersconnect-fixture.ps1`. Rewrites only the
      dialect-relevant metadata - `channel=` ids, waters_connect + DATA Convert software terms,
      Xevo MRT, `MS:1000616` carrying the channel number as DATA Convert really does - and drops
      the lockspray spectrum, since DATA Convert does not export it. Peak data is inherited from
      `MSe_Short.raw` and carries no meaning. Also declares MSn in `fileContent`, which
      `MSe_Short` does not (that is #4499), so the fixture does not carry an unrelated defect.
      The two pre-existing entries are byte-identical - same lengths after repacking.
- [x] `VerifyWatersConnectSpectra` in `TestWatersCalibrationSpectrum`. Asserts `IsWatersFile`
      first, so the test cannot pass vacuously, then that both spectra survive, that no function
      number is parsed, that nothing is treated as lockspray, and that ms levels 1 and 2 come
      through - which covers the MSe-level fallback to the declared level.
- [x] Mutation-verified, which the earlier review rounds showed is the bar here. Adding
      `{ @"channel.process.spectrum.scan", 0 }` back to `WATERS_FUNCTION_ID_LAYOUTS` reinstates
      exactly the reported misreading, and the test fails at `WatersFunctionNumber`
      (`Expected:<(null)>. Actual:<2>`) naming `MSe_Short_watersconnect.mzML`. It fails there
      *before* reaching the older string-level assertions, so the file-level test stands on its
      own rather than duplicating them. Its distinct coverage beyond the string table is the
      `IsWatersFile` gate and the ms-level fallback, which no string assertion touches.
- [ ] **Follow-up: trim `06_DDA/260701PP_B1P1_QC_01 (3).mzML` to its first ~4 spectra and add it
      alongside**, once Waters confirms a slice may be redistributed in the public repo. Needs
      `--noindex` handling - the source is `indexedmzML`, so the offsets must be dropped rather
      than left stale. That fixture would additionally pin real peak data and the genuine
      `MS:1000616`/channel duplication, which the synthetic one only imitates.

### Phase 8: The msLevel predicate reads the declared level (IN PROGRESS)

Brian's observation, and he is right: if we honor "calibration spectrum" on read, the msLevel
filter has to accept a declared ms level whether or not the spectrum is a "mass spectrum".

`MS_calibration_spectrum`'s only CV parent is `MS_spectrum_type` (`cv.cpp:7055`) - it is **not**
under `MS_mass_spectrum`. `SpectrumList_UIMF.cpp:106-108` sets it as the *sole* spectrum type on a
calibration frame while still setting a real `MS_ms_level`. So master's predicate hit
`!cvIsA(param.cvid, MS_mass_spectrum)`, returned `msLevelSet_.contains(0)`, and threw the declared
level away: `msconvert --filter "msLevel 1-"` dropped UIMF calibration frames and `msLevel 0` kept
them.

**The Phase 6 revert did not cause this and restoring that hunk would not have fixed it.** The
reverted form asked `hasCVParamChild(MS_mass_spectrum)`, which for a calibration-*only* spectrum is
still false, so it still returned `contains(0)`. That hunk only ever helped when *both* terms were
present - the situation our own additive writer created. Brian's version is the correct superset: it
fixes the calibration case and gets order-independence for free, with no additive-writer premise.

Fix: ask for `MS_ms_level` first and let it decide; fall back to the spectrum type only when no
level is declared, which is what the level-0 rule is actually for.

Scope note: this is a **`pwiz`-module change inside a `skyline`-module PR**, at Brian's direction
after the mismatch was flagged. Called out in the PR body so a reviewer treats it on its own terms
rather than as Waters collateral.

- [x] `SpectrumList_FilterPredicate_MSLevelSet::accept` reordered
- [x] `testMSLevelSetCalibrationSpectrum` added, on its own 3-spectrum list (MS1 with level 1,
      calibration with level 1, emission with no level). It cannot extend the shared
      `createSpectrumList` fixture - that list is pinned by exact sizes and ids throughout the
      871-line file, so adding a spectrum would break unrelated assertions.
- [x] Mutation-verified: restoring the type-first ordering fails it at
      `SpectrumList_FilterTest.cpp:561`, `expected "2" but got "1"` - the calibration spectrum
      dropped by `msLevel 1`.
- [x] No checked-in baseline can shift: no vendor reader test uses an msLevel filter, and the UIMF
      reference `BSA_10ugml_CID.mzML` contains no calibration frames. That also means this unit
      test is the *only* thing standing behind the change, which is why it was mutation-verified.

**Tooling trap found here.** `quickbuild.bat` exited **0** on the mutated run even though the test
failed. Never read a bjam exit code as a test result - grep for `assertion failed`, `...failed`,
`**FAILED**`. Also two result formats: `unit-test-if-exists` targets print
`testing.unit-test <path>.passed`, run-tests print `**passed** <path>.test`, so grepping only for
`**passed**` under-reports the suite. Saved as
[[reference_quickbuild_exit_code_hides_test_failure]].

### Phase 9: DATA Convert 5.x writes peaks in intensity order, not m/z order (IN PROGRESS)

Brian, 2026-07-30: `D:\Data\Lockmass\09_MS\MS1xMRTmzML_BSP.sky` extracted a puzzlingly low chromatogram.
It was not low, it was **exactly zero** at all 5998 points, `TotalArea=0`.

**Root cause: Waters DATA Convert 5.0.0.2900 writes each spectrum's peak arrays sorted by ascending
INTENSITY rather than ascending m/z.** Skyline's extraction binary searches the m/z axis
(`SpectrumFilterPair.cs:373`), which is only valid on a sorted array; on this input the search lands
at an arbitrary index, the scan loop starts past the window, and nothing accumulates. No error.

Ascending m/z is nowhere in the mzML spec - it is a de facto standard everything assumes.

**Evidence, four independent methods, all agreeing:**

| method | pwiz in path? | result |
|---|---|---|
| raw base64+zlib decode of the vendor bytes, .NET only | **no** | n=598, **296** m/z descents |
| `mscat` (built from `pwiz_tools/examples`) | yes | m/z unordered, intensity ascending |
| `msaccess -x "binary index=0"` | yes | same |
| `msconvert --ms1` text writer | yes | 296 m/z descents, **0 intensity descents** |

Sharper than "unsorted": 598 peaks, **zero** intensity descents, terminating at the base peak
(441,159 at m/z 212.075). The wrong sort *key*, not corruption.

**It is a regression in 5.0.0.2900.** 06_DDA from DATA Convert 4.0.0.2619 has 0 descents in 1506
pairs; 03_MSMS and our own msconvert output are clean too.

**Why it stayed invisible:** `basePeakMZ`, `basePeakIntensity`, `mzLow`/`mzHigh` and TIC are all
computed by scanning, so they are correct regardless of order. Only consumers that binary search
the m/z axis break, and they break to zero rather than to an error. In metabolomics (this is an
itaconic acid standard on a Xevo MRT) a user reads that as "compound not detected".

**Decision (Brian, 2026-07-31): fix only in code we control.** Waters can ship a converter fix and
users re-run their raw data, which is a better remedy than anything we could offer downstream, and
pwiz fixes would not reach other packages in time to matter. So: Skyline and BiblioSpec.

- [x] **Skyline**: `MsDataSpectrum.SetArrays` calls `EnsureMzAscending` for 2-array spectra.
      Combined IMS is excluded deliberately - **it is legitimately not globally m/z sorted**.
      Measured on `HDDDA_Short_noLM-combineIMS.mzML`: 521,802 points, **180** m/z descents, every
      one a full roll-over (smallest drop 1950 Da), against **181** ion-mobility runs with 0 IM
      descents. So it is m/z ascending *within* each mobility bin, 181 bins. A global sort would
      shred it. Skyline already flat sorts those separately on dedicated threads
      (`SpectraChromDataProvider.EnsureSortedMzs`, `ScanProvider.cs:242`), which this leaves alone.
- [x] Placed in `SetArrays` rather than in `GetSpectrum` on Brian's prompting: `SetArrays` accepts
      `scanningQuadMzLows`/`scanningQuadMzHighs` and **assigns neither** (dead parameters, evidently
      meant for SONAR). If they are ever wired up they become a fourth per-peak array; putting the
      sort where the arrays are assigned means whoever adds it is looking straight at the warning.
- [x] Reused the #4157 sort (`eb1e95f50`, "Speed up IMS chromatogram extraction with custom m/z
      sort") rather than hand-rolling: moved its double-specialised core to
      `CommonUtil/Collections/ParallelDoubleSort.cs` (`pwiz.Common.Collections`), with
      `ArrayUtil.Sort`/`IsSorted` delegating. No new dependency - `ProteowizardWrapper` already
      references `CommonUtil` - `ArrayUtil`'s public surface is unchanged so none of the 51 files
      using it were touched, and `MsDataFileImpl` already had the using directive.
- [x] `TestUnsortedMzArrays` in `PwizFileInfoTest`, over a synthesized fixture (invented peaks, no
      customer data) whose peaks are deliberately intensity-ordered. Asserts the m/z **and** the
      intensity pairing, since sorting m/z alone leaves every value plausible and every pairing
      wrong. Went red (element 0: 500.5 where 200.2 expected) then green.
- [x] **Acceptance**: on the real file, extraction went from all-zero to matching an independent
      msconvert XIC with **largest per-point difference 0.0** across 400 points.
- [x] Waters suite green incl. all three combined-IMS tests; CodeInspection green.
- [x] **BiblioSpec**: sort in `Spectrum::setRawPeaks` - the one choke point every source funnels
      through, which matters because **libraries already built from 5.x data carry the bad order
      inside the .blib**; fixing only at pwiz ingestion would leave those broken. Two defects there,
      not one: `binPeaks` merges only *adjacent* equal bins, so on intensity-ordered input same-bin
      peaks never merge (corrupting intensities even when `isClearPrecursor_` is off), and
      `removePrecursorPeaks` then binary searches the unsorted result and erases the wrong range.
      New `SpectrumTest` unit test (`lib blib` links `Spectrum.cpp`, so no test-data tarball
      repacking needed - note `inputs/` is packaged as `inputs.tar.bz2`, which is why the
      end-to-end `blib-test-build-basic` route was not taken; it is the first unit test in
      BiblioSpec's `src/Jamfile.jam`, `TestWeibull.cpp` having never been wired up).
      Mutation-verified: disabling the sort fails it at `SpectrumTest.cpp:65`,
      `|200.2 - 500.5| < 1e-09`.

**Checked and found NOT at risk**, so the blast radius is smaller than first feared: `threshold`
sorts by intensity itself and re-sorts by m/z on output (`ThresholdFilter.cpp:423`); `peakPicking
cwt` sorts explicitly (`CwtPeakDetector.cpp:82`); the default `LocalMaximumPeakDetector` compares
array neighbours and *would* be vulnerable, but `SpectrumList_PeakPicker.cpp:252` returns centroided
spectra as-is and DATA Convert 5.x output is centroided, so it is unreachable. `SpectrumList_MZWindow`
already calls `sort_together`. Verified empirically - peakPicking on the real file was a no-op,
234,489 peaks in and out.

**`/code-review max` (2026-07-31) found a real hole in the BiblioSpec fix.** `setRawPeaks` is NOT on
BlibBuild's path: `BuildParser.cpp:471` declares a `SpecData`, `PwizReader::getSpectrum(int,
SpecData&)` calls `transferSpec` which copies `specInfo->data` in file order, and
`BuildParser.cpp:649` hands those arrays to `insertPeaks` - no `BiblioSpec::Spectrum` is ever built.
A library built from a 5.x file would have been stored intensity-ordered. Verified both halves
before acting. Fixed by sorting in `PwizReader::ensureMzAscending`, called after both
`SpectrumInfo::update` sites - the one point `transferSpec` and `transferSpectrum` share.
`setRawPeaks` stays for the `.blib` re-read and copy paths.

Also from that review, acted on: `unit-test` -> `unit-test-if-exists` (the BiblioSpec source tarball
ships the Jamfile but strips `*Test.?pp`); `TestFilesDir` given `suffix: "-unsorted"` because
`TestWatersCalibrationSpectrum` extracts the same zip and the ctor deletes the directory it finds;
and `TestUnsortedMzArrays` now decodes the fixture's m/z array from the mzML text and asserts it is
NOT ascending - every other assertion in it is satisfied by an already-sorted file, so without that
the fixture could be regenerated in order and the test would pass covering nothing.

**Rejected from that review: "the pwiz-core seam was available and not taken".** That is the scope
decision recorded above, not a defect - Waters ships a converter fix and users re-run their raw
data. Worth stating in the PR so it is not re-raised.

Still open from it, not yet acted on: `std::sort` is UB on NaN m/z and `is_sorted` cannot screen it
(`LibReader::getUncompressedPeaks` does no validation while `BlibFilter`'s twin explicitly rejects
NaN); the C# guarantee is advisory rather than an invariant (public setters, six construction sites
bypass `SetArrays`); `EnsureMzAscending`'s length-mismatch guard returns silently; and nothing pins
the `IonMobilities == null` carve-out.

**Two traps worth remembering.** Skyline caches chromatograms in a `.skyd` next to the *input*
document, so repeated `SkylineCmd --in=X.sky --import-file=...` runs serve stale results - several
early "still zero" variant results were cache artifacts, not real. Delete `*.skyd` between runs.
And a `sorted` check that only compares first vs last element proves nothing; it hid this for
several rounds.

### Phase 10: Review feedback on the m/z sort (DONE - commit 5f88ea972)

**The check is now settled per file instead of run per spectrum.** Design chosen by Brian
2026-08-03: Matt's first-spectrum-probe-plus-cached-flag, with Brian's >10 m/z refinement, and
one sharpening Brian added - **any out-of-order spectrum is proof regardless of size, no need to
look past it**. So the two verdicts are deliberately asymmetric:

- Out of order -> the writer does not sort, at any peak count. Two peaks in the wrong order is
  already proof. Every spectrum from then on is sorted, and no later spectrum can talk the
  verdict back round.
- In order -> the writer sorts, but only believed from a spectrum with **more than 10** m/z
  values. Three peaks ascend by chance; early scans can precede the sample. Until such a
  spectrum arrives the checking continues, so a short leading scan costs a few extra passes
  rather than the correctness of the file.

Both sides carry the same rule in a small class rather than loose flags: `MzOrderVerdict` in
`MsDataFileImpl.cs` (held per `MsDataFileImpl`, passed to `SetArrays` by named arg) and
`BiblioSpec/src/MzOrderVerdict.h` (held by `PwizReader`, `reset()` in `openFile`). Extracting the
C++ one made the state machine unit-testable without a file - `ensureMzAscending` needs one, the
rule does not.

**Combined IMS is excluded upstream of the verdict on the Skyline side** (`IonMobilities == null`
in `SetArrays`), which matters more now than before: those spectra are legitimately only m/z
ordered *within* each mobility bin, so letting them vote would condemn every IMS file on its first
spectrum and sort every 2-array spectrum in a mixed file for nothing.

**BiblioSpec is the opposite case, and correctly so.** `PwizReader::openFile` sets
`combineIonMobilitySpectra = true`, so its spectra *are* combined - but `SpectrumInfo::data` is a
flat `vector<MZIntensityPair>` (`SpectrumInfo.hpp:68`) with no per-peak mobility axis to shred. A
combined spectrum fails the check, condemns the file immediately, and every spectrum gets sorted.
That is what Phase 9 already did; the latch changes nothing there. It is right for that consumer:
`binPeaks` merges only *adjacent* equal bins, so bin-concatenated input is exactly the shape that
leaves same-bin peaks unmerged, and flattening to m/z order is what makes the binning correct. For
IMS input the sort does real work rather than looking for something that is not there.

**Not taken, and why** (both said on the PR so they are not re-raised):
- *Sample every ~1000th spectrum and restart the import if a later one needs sorting.* Only pays
  for itself on a file that changes its mind partway through. Order is a property of the writer,
  not the scan, and none of the eight Waters files we hold mixes the two. Restart plumbing for a
  case never observed.
- *Detect unsortedness during the binary search.* Free on the 99.9% path, but a binary search can
  land in a locally ordered neighbourhood and return a plausible wrong answer without ever
  stepping on the disorder. Weaker guarantee, not just a cheaper one.
- *Throw on unsorted input.* The customer files in hand extract correctly today; refusing them
  until Waters ships is a worse outcome than sorting them.

Fixture and tests:
- [x] `DataConvert5_unsorted_mz.mzML` gained a **short in-order leading spectrum** (3 peaks,
      ascending) ahead of the two unsorted 6-peak ones. That is the shape a first-spectrum-only
      probe gets wrong, and without it nothing would pin the >10 rule. Repacked by
      `ai/.tmp/repack-unsorted-fixture.ps1`; the three pre-existing entries are byte-identical.
- [x] The order pin Matt questioned is **kept and now does two jobs** - first array ascending,
      the two after it not. Defended on the thread rather than dropped: every other assertion in
      the test passes on an already-sorted file, so without it an msconvert round trip of the
      fixture would leave the test green covering nothing.
- [x] Mutation-verified: dropping the peak-count rule (settle on the first ordered spectrum
      whatever its size) fails at `CollectionAssert.AreEqual ... spectrum 1`, second spectrum
      back in writer order. Restored and re-run green - note the first re-run after restoring
      was a false red because `Run-Tests.ps1` does not rebuild.
- [x] `testMzOrderVerdict` in `SpectrumTest` pins the C++ state machine directly, including that
      a condemned file stays condemned and that `reset()` clears it. `SpectrumTest.passed`.
- [x] Gates: Waters suite green (TIC, InstrumentInfo, FileType, Cache, all five `WatersImsMse*`),
      `TestUnsortedMzArrays`, `TestWatersCalibrationSpectrum`, CodeInspection, and the full
      ReSharper solution inspection - 0 errors, 0 warnings, verified in
      `bin/x64/Release/InspectCodeOutput.xml` directly (336 bytes, zero `Issue` elements).

Replies posted on all four threads. The `SpectrumList_Filter.cpp:321` one was answered rather
than complied with - see Phase 11.

### Phase 11: NEXT SESSION STARTS HERE - awaiting Matt's re-review

All four of Matt's 2026-08-03 comments are answered - three by the Phase 10 commit, one by argument.
Nothing is outstanding on this branch except his re-review. If he comes back:

1. **`MsDataFileImpl.cs:2471`** and 2. **`PwizReader.cpp:440`** (the perf objection) - fixed in
   5f88ea972, see Phase 10. He may still want the sampling-with-restart variant; the reply says
   why it was not taken and offers it.
3. **`PwizFileInfoTest.cs:206`** - the order pin is kept and defended, and now also pins the
   in-order leading spectrum. Reply offers to drop it if he still objects; **do not drop it
   silently**, it is the only thing keeping that test from covering nothing.
4. **`SpectrumList_Filter.cpp:321`** - *"Shouldn't this be reverted since it was only needed for
   multiple spectrum types?"* **Answered, not complied with.** The multi-type change WAS reverted
   in Phase 6. What is there is the Phase 8 change: read a declared ms level before consulting the
   spectrum type, which fixes calibration-spectrum-*only* spectra - the form
   `SpectrumList_UIMF.cpp:106` writes today on master. Verified while replying: master's
   `!cvIsA(param.cvid, MS_mass_spectrum)` returns `contains(0)` and discards a good declared ms
   level, so `msconvert --filter "msLevel 1-"` drops UIMF calibration frames. **Restoring the
   reverted hunk would not have fixed it** - it asked `hasCVParamChild(MS_mass_spectrum)`, equally
   false for a calibration-only spectrum. Moot only once psi-ms #539 lands *and* UIMF is updated.
   The reply offers to split it into its own PR, which is the likeliest follow-up ask.

**The perf objection was sound and had been under-weighted.** `/code-review max` measured the check
at ~1.25 ns/element, roughly 0.2-2% of import wall time, and that was recorded in this TODO without
being acted on until Matt raised it independently. Worth remembering as a calibration point: a
measured cost noted and not acted on is a finding, not a footnote.

**psi-ms CV issue #539 - agreed, not landed, nothing to bundle.** Matt opened it 2026-07-30 out of
this very work; edeutsch minuted agreement on 2026-07-31 (*"Joshua will make a PR"*) to move
`MS:1000928` from `spectrum type` to `spectrum attribute`. **Same CVID, re-parented in place - no new
accession.** Verified 2026-08-03: issue still open, no PR, `psi-ms.obo` master 4.1.258 still says
`is_a: MS:1000559`, and the most recent obo commit (2026-07-31, #536) does not touch it. OLS agrees.
Matt is fine not bundling it.

When it does land, two things here need revisiting: `MSe_Short_tagged.mzML` currently declares
`calibration spectrum` as the lockspray scan's **sole** type (correct today, wrong once it is an
attribute - it would then need `MS1 spectrum` plus the attribute), and `SpectrumList_UIMF.cpp:106`
has the same problem in the writer.

## Open Questions / Unresolved

- **Tell Hans about the DATA Convert 5.0.0.2900 sort-order regression.** Peaks ordered by ascending
  intensity instead of ascending m/z; 4.0.0.2619 is correct. Silent - every extraction reads as zero,
  and in metabolomics that looks like "compound not detected". Users can re-run their raw data once
  Waters ships a fix, which is the real remedy.
- `MsDataSpectrum.SetArrays` accepts `scanningQuadMzLows`/`scanningQuadMzHighs` and assigns neither.
  **Investigated 2026-07-31: vestigial, not a defect** - an earlier session note called this "SONAR
  quad ranges silently discarded", which is wrong. pwiz writes both bound arrays
  (`SpectrumList_Waters.cpp:361,363`) and Skyline reads only the lower one (`MsDataFileImpl.cs:1314`)
  as the per-peak position axis - with `reportSonarBins = true` (line 199) that is bin numbers. The
  m/z <-> bin mapping lives in pwiz and Skyline asks for it on demand via `SonarMzToBinRange` /
  `SonarBinToPrecursorMz`, so the per-peak upper-bound array is genuinely redundant. Worth deleting
  the two dead parameters for tidiness; nothing is lost.
  Also confirms the Phase 9 gate is right for SONAR: those spectra arrive with `IonMobilities`
  non-null (it holds the quad/bin axis), so they are excluded from `EnsureMzAscending` - correct,
  since SONAR spectra are blocked by quad bin exactly as IMS is blocked by drift bin.
- The #4157 NaN caveat came across to `ParallelDoubleSort` unchanged. `SetArrays` is a broader entry
  point than "chromatogram extraction" (it is every spectrum Skyline materialises), so the original
  "no NaN can reach here" justification is stretched, though a NaN m/z means a corrupt file. No guard
  added; decide whether one is wanted.
- `Spectrum::getSignalToNoise` sorts `rawPeaks_` by intensity in place - a mutation inside an
  accessor. Harmless today: its only caller is `compSpecPtrSignalToNoise`, which has no users.
- #4498 now spans Skyline, pwiz, BiblioSpec and Common under a `skyline` prefix. Coherent as one
  Waters story but against the one-module convention; a reviewer may want BiblioSpec split out.
- Stray untracked `Spectrum.cpp.bak` and `MsDataFileImpl.cs.bak` appeared in the tree - not created
  by the session, left alone.

- **SONAR regression, unexplained.** In an earlier experiment (offset mapping, since
  reverted) the SONAR pulse import failed with `OverflowException: Array dimensions
  exceeded supported range` at `ChromCollector.cs:679` - the chromatogram spill file
  exceeded the 2 GB `byte[]` limit - where baseline succeeded with a 270 MB `.skyd`. An
  Explore pass confirmed the code model is right, so the discrepancy is in a file premise.
  Needs instrumentation (log `_lockmassFunction`, `IsWatersFile`, `_isWatersMse`, and
  per-channel kept/skipped counts), not more reading. Note the file legitimately has 140
  DIA windows against a 12.8 MB target list, so a large volume is expected.
- `ChromatogramList_Waters.cpp:140` folds the lockmass function into the "MS1 only" global
  TIC. Arguably wrong, deliberately left alone.
- Waters asked whether their unusual "lockmass scans included" case is tagged
  `MS:1000928`. Answer after Phase 6: **no** - nothing pwiz writes emits the term, and Skyline
  cannot identify those scans in a waters_connect file. If DATA Convert ever includes lockmass
  scans, it should label them itself; Skyline will honor it. Worth telling Hans, since it turns
  a question into a request.
- ~~No unit test calls the Waters nativeID parsing directly~~ - added in
  `TestWatersCalibrationSpectrum`, covering all five real id shapes.
- **No waters_connect ion mobility data exists anywhere.** All eight files we hold are
  `binaryDataArrayList count="2"`, with no IM, drift time or scanning quadrupole terms - Hans
  confirmed regular SONAR is not supported by DATA Convert yet. So the `merged=` layouts are
  MassLynx-only in practice, and a waters_connect IM dialect cannot be designed for without
  inventing it. Brian requested data 2026-07-28; until it arrives the code declines to infer,
  which is the right default.
- The branch now touches shared pwiz analysis code (`SpectrumList_Filter`, `SpectrumListWrapper`)
  that every vendor passes through, not just Waters. Justified - the multi-spectrum-type situation
  is ours to have created - but it is the part a human reviewer should look hardest at.

## Data

`D:\data\lockmass\` - the five cases from Waters, plus `SONAR_Short.raw` and
`SONAR_Short_first200.mzML` copied in for comparison with their SONAR pulse file.
