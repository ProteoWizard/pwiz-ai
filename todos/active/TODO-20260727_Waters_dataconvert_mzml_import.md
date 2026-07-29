# TODO-20260727_Waters_dataconvert_mzml_import.md

## Branch Information
- **Branch**: `Skyline/work/20260727_Waters_dataconvert_mzml_import`
- **Base**: `master` @ `55cedad25`
- **Created**: 2026-07-27
- **Status**: In Progress - both halves done and green, two AI review rounds addressed, not pushed
- **GitHub Issue**: (none)
- **PR**: https://github.com/ProteoWizard/pwiz/pull/4498

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
- Seven other `cvParamChild(MS_spectrum_type)` sites remain first-child-wins. Only the msLevel
  predicate dropped data; the rest fail permissive or are cosmetic.
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
  `MS:1000928`; answer pending.
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
