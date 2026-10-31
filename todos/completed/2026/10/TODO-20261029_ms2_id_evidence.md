# Show all MS/MS ID evidence a precursor uses, and drop outlier IDs when setting the extraction window

## Branch Information
- **Branch**: `Skyline/work/20261029_ms2_id_evidence`
- **Base**: `master`
- **Created**: 2026-10-29
- **Status**: Completed
- **GitHub Issue**: [#4935](https://github.com/ProteoWizard/pwiz/issues/4935)
- **Module**: `skyline`
- **PR**: [#4947](https://github.com/ProteoWizard/pwiz/pull/4947) (merged 2026-10-31)

## Objective

Retention time evidence for chromatogram extraction is pooled across all library precursors of a
peptide, but the document shows only the IDs of the precursor displayed. In the DDASearch tutorial
(TestDdaTutorial, MS Amanda 3.0), R.TGEGFLCVFAINNTK.S is held as charge 2 light/heavy, while the
library also holds charge 3 spectra including a false ID at 20.79 min. That single ID:

* Extends extraction in 2_UPS1_300fmol to nearly the whole run, with no ID drawn to explain it
* Is aligned into 1_UPS1_100fmol at 21.3 min, where a one-point M+1 noise spike is integrated

The heavy precursor shows "ID" annotations although only light was identified, has no Library Match
combo, and the Library Match title says "(heavy)" over the light spectrum.

Not known to be a .NET 10 regression: MS Amanda 2.0 -> 3.0 produced the false charge 3 ID.

## Tasks

- [x] Chromatograms: draw ID and aligned ID lines for every library precursor used as evidence,
      labeled with charge and label type (e.g. "ID 3+"); mark IDs from another form as such
      (e.g. heavy matched to light IDs) rather than as the precursor's own IDs
- [x] Extraction window (`RetentionTimeFilterType.ms2_ids`): center on the median of ID times and
      drop outliers before extending the range (like RCalcIrt / IrtPeptidePicker); apply the same
      rejection to aligned times
- [x] Library Match combo: list all spectra of the peptide (all charges and label types), exact
      precursor matches first, for both light and heavy precursors
- [x] Library Match title: name the label type of the spectrum shown, not the selected precursor
- [x] Spectral Library Explorer: keep consistent with the Library Match combo change (no change
      needed - ViewLibraryDlg already lists each LibKey as its own row)
- [ ] Check behavior on 26.1.1 with this data

## Regression Test

- **Test name**: TestRemoveOutlierIdTimes (unit) + TestDdaTutorial `VerifyOutlierIdIgnored` (end to end)
- **Test project**: Test + TestPerf
- **Fails on master**: yes - with the filter bypassed, TestDdaTutorial screenshot mode (`Run-Tests.ps1
  -TakeScreenshots -EnableInternet`) fails "1_UPS1_100fmol extraction starts at 16.32". The unit test
  fails by construction (API absent on master).
- **Passes on fix**: yes - both, 2026-10-29 (screenshot run 499 s, MS Amanda path confirmed by s-12).
- **Limitation (Brendan accepted)**: `VerifyOutlierIdIgnored` runs only in MS Amanda / full-data
  (screenshot) mode; the normal run searches one file with MSFragger. A smaller functional test would
  need too much data and test time for this one case.

## Progress Log

### 2026-10-29 - Session Start

Starting work on this issue. Branch created from master at 4f92fe97ba (#4915) in `C:\proj\pwiz`.

Decisions (Brendan):
* Outlier rule: keep IDs within RetentionTimeFilterLength of the median of the pooled ID times -
  that setting is how close the user expects peaks to be. If nothing survives (e.g. 2 IDs that
  disagree), keep all.
* 2026-10-30 refinement (Brendan approved): keep the IDs CONNECTED to the median by gaps no wider
  than RetentionTimeFilterLength (still "keep all" when no ID is within the tolerance of the median).
  The plain median distance dropped ~136 of ~170 contiguous IDs of a broadly eluting BSA peptide in
  TestTargetedMSMSTutorial (low-res DDA, tolerance 2 min) and lost a peak (88 -> 87 transitions).
* 2026-10-30 overnight run (English, SkylineTester, log at D:\test\skyline-runs\20261030_4935_overnight_en):
  11 failures. Fixed so far: TestFullScanId (Library Match now lists the other charge - asserts order),
  TestTargetedMSMSTutorial(+AsSmallMolecules): 80fmol 87 -> 86 accepted by Brendan after reviewing
  DRVYIHPF over the MCP - stray IDs at 28.9-62.6 had widened extraction to 26.9-64.6; now 42.1-46.7,
  same peak, precursor ion no longer coelutes. Not ours: TestDiannSearchTutorialDraft (no audit log),
  Waters lockmass x3 (import timeouts), TestLabelLayoutDeterminism (ignore for now).
  Remaining: DecoysMatchTest, TestDiaQe/TtofDiaUmpireTutorialFullFileset.
* Charge text in ID labels and Library Match entries now uses `Transition.GetChargeIndicator`
  (Brendan: the display normalizer; handles charge 5+ and small-molecule adducts), e.g. "ID +++".
* Screenshot runs needed (Brendan): TestDdaTutorial and TestTargetedMSMSTutorial (proteomic version,
  which drives the PRM tutorial screenshots) with `Run-Tests.ps1 -TakeScreenshots`; review the changed
  PNGs with Brendan before committing them (DDASearch s-15 labels/Library Match; PRM extraction ranges).
* Item 5: ViewLibraryDlg lists each LibKey (charge) as its own row via its own lookup - no change.
* Gotcha: the Debug Solution build skips TestTutorial and TestPerf (`-Target TestTutorial`/`TestPerf`);
  without them TestRunner says "No tests found" and the run reports no failures.
* Verification: a Test.csproj unit test of the filtering helper first, then assertions in
  TestDdaTutorial (2_UPS1_300fmol window, 1_UPS1_100fmol peak).

Code map:
* Pooling: `SrmSettings.GetBestRetentionTimes` (SrmSettings.cs:1212), all labels and charges via
  `GetTargets`; own file -> aligned -> unaligned, no filtering.
* Window: SpectrumFilter.cs:284-292 (min - length, max + length).
* Same pooled times also used by ChromCacheBuilder.cs:699-731 (median center, Range() width) and
  MQuestFeatureCalc.cs:111-123.
* ID lines: GraphChromatogram.SetRetentionTimeIdIndicators (GraphChromatogram.cs:2440) uses
  `TryGetRetentionTimes` - one charge, first label type - not the pooled set.
* Done (uncommitted): `TransitionFullScan.RemoveOutlierIdTimes` (TransitionSettings.cs), applied in
  `SrmSettings.GetBestRetentionTimes` (SpectrumFilter window, mQuest) and ChromCacheBuilder (peak
  picker times and the unaligned fallback). Unit test `TestRemoveOutlierIdTimes` (Test/Ms2IdTimesTest.cs)
  passes. TestRetentionTimeAlignment, TestAlignedIdTimes, TestMs1Tutorial, TestTargetedMSMSTutorial,
  TestMixedSrmPrm, TestMidas all pass.
* Environment: C:\proj\pwiz needed `Build-Skyline.ps1 -VendorLicenses` (Brendan approved); without it
  TestMixedSrmPrm fails at line 61 (.raw not imported) and TestMidas passes with every .wiff import failing.
* 2026-10-29 evening - items 1, 3, 4 done and reviewed with Brendan in TestDdaTutorial at a temporary
  s-15 PauseTest (Run-Tests -TakeScreenshots -AiConnector): ID lines labeled "ID 3+" / "(light)";
  Library Match lists all 9 spectra of TGEGFLCVFAINNTK for the light 2+ precursor (best 2+, best 3+,
  3 x 2+ IDs, 4 x 3+ IDs incl. the false 20.79) and gives the heavy precursor a dropdown; title
  "(light spectrum for heavy)". Title cause: SpectrumRanker.cs:394 gives the ranked spectrum
  PredictLabelType (precursor's) - by design, cross-label prediction is intended - so the title now
  uses `SpectrumGraphItem.SpectrumLabelType` / `SpectrumAdduct` from the displayed spectrum.
* Shared model: `SrmSettings.GetLibraryPrecursors` + `LibraryPrecursor` feed both the ID lines and
  the Library Match list; small molecules keep the old exact-precursor list (`GetExactPrecursorSpectra`).
* Next: full test run overnight (Brendan expects breakage from the list/title changes), then
  CodeInspection, `/code-review`, item 5 (ViewLibraryDlg consistency), commit, PR.
* ID lines (item 1) - first implementation notes: `Library.GetKeysWithSequence`,
  `SrmSettings.GetPrecursorIdTimes` + `PrecursorIdTimes`, GraphChromatogram `GetIdLabel` ("ID",
  "ID 3+", "ID 2+ (light)"), ChromGraphItem `RetentionMsMsLabels`.
* Title "(heavy)" (item 4): the tutorial blib holds only light TGEGFLC[+57]VFAINNTK at 2+ and 3+, so
  no heavy entry exists - cause not yet found by reading; needs a live look at the heavy precursor.
* Library Match: GraphSpectrum.cs:787-859 (`GetBestSpectra` own charge only, `GetRedundantSpectra`
  own label type only); title in SpectrumGraphItem.GetTitle (SpectrumGraphItem.cs:360).

### 2026-10-30 - Review, commit, PR

* `/code-review medium`: 10 findings, 7 fixed - majority guard (connected run must hold > half the IDs;
  `{20, 60, 100}` keeps all), unaligned IDs from other runs not filtered (no shared time scale), SRM files
  in mixed documents not filtered, small molecules keep per-precursor ID lines (adducts can share a
  charge), ID labels compared within the same peptide, a joined line, AssertEx. Dropped 3: non-cached
  libraries supply no per-file ID times; per-replicate list order is the reviewed layout; pre-existing
  RT cascade duplication in ChromCacheBuilder.
* 12-test batch passes after the fixes (unit, FullScanId, TargetedMSMS x3, Ms1Tutorial, AlignedIdTimes,
  RetentionTimeAlignment, MixedSrmPrm, Midas, DecoysMatchTest, CodeInspection); log checked per test.
* DIA-Umpire FullFileset JSON re-recorded (mass error stats, mProphet coefficients only) BEFORE the
  review fixes - confirm in Brendan's next overnight run.
* Brendan re-recorded and staged DDASearch s-14..17 and PRM s-16/21/22/24 (en, ja, zh-CHS), also
  before the review fixes; TestDdaTutorial `VerifyOutlierIdIgnored` needs a screenshot-mode rerun.
* Committed 88d8ccb6ea, pushed; PR opened for TeamCity.

### 2026-10-31 - Merged

PR #4947 merged as commit 8944f3f2a4. Shipped: outlier MS/MS ID rejection before `ms2_ids`
extraction (full-scan files, IDs from or aligned to the file), chromatogram ID lines for every pooled
library precursor labeled by charge and label type, all of the peptide's spectra in the Library Match
list, and a Library Match title naming the spectrum shown. The Spectral Library Explorer needed no
change (it already lists each charge as its own row). Deferred: the 26.1.1 behavior check. Brendan ran and verified
all screenshots with the final rule before the merge, and the overnight TeamCity Skyline Perf and
Tutorial runs passed (all 19 checks green), so the DIA-Umpire FullFileset values and TestDdaTutorial
`VerifyOutlierIdIgnored` noted as pending on 2026-10-30 are confirmed.
