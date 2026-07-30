# TODO-20260727_Waters_dataconvert_mzml_import.md

## Branch Information
- **Branch**: `Skyline/work/20260727_Waters_dataconvert_mzml_import`
- **Module**: `skyline` - the reported defect is a Skyline import failure and the fix lives in
  `ProteowizardWrapper`; the pwiz-side changes (TIC, wrapper forwarding) are in support of it
- **Base**: `master` @ `55cedad25`
- **Created**: 2026-07-27
- **Status**: In Progress - read side only; the writing half was withdrawn (Phase 6), revert
  staged and uncommitted, awaiting a clean build to re-verify
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

## Open Questions / Unresolved

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
