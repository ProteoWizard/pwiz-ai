# Use the ion mobility dimension in peak picking when no IM filter value is set

## Branch Information
- **Branch**: `Skyline/work/20261127_im_peak_picking`
- **Base**: `master`
- **Created**: 2026-11-27
- **Status**: In Progress
- **GitHub Issue**: [#5083](https://github.com/ProteoWizard/pwiz/issues/5083)
- **Module**: `skyline`
- **PR**: (pending)
- **Requester/Reporter**: John (Agilent, 2018 report with mouse liver digest data) - `Requested by John.`

## Objective

When IM data is present and a precursor has no IM filter value, chromatograms are
extracted by summing across the whole IM dimension, peak picking runs on those summed
traces, and the IM library editor's *Use Results* takes the IM value from whichever RT
peak was picked. Interference can pick the wrong peak, and re-importing with the learned
IM value then locks the error in. Treat IM as a search dimension during peak picking
instead of collapsing it.

## Tasks

- [ ] Map the current path: summed-IM extraction, peak picking, IM library *Use Results*
      (including the 24.1 isotope-distribution matching)
- [ ] Find IM candidates per RT peak (cheapest first: IM profile at candidate RT apex from
      raw spectra; then IM-band extraction; then 2D RT x IM apex detection)
- [ ] Add peak scoring features for IM agreement (isotope IM apex consistency; fragment IM
      offset from precursor IM) usable by default and mProphet models
- [ ] Record the IM value that goes with the chosen peak so *Use Results* can store it directly
- [ ] Support MS1-only IM data (isotope agreement only) as well as fragmentation data
- [ ] Measure import time and memory against summed-IM extraction; opt-in setting acceptable at first
- [x] Locate John's 2018 data - \\BSPRATT-UW3\data\JohnF (84 GB), copied to D:\data\JohnF
- [x] Extract 5ug_MouseLiverDigest_IM-MS.d (MS1-only run, 9.8 GB) from IM\Protein Digest Data.zip
      into D:\data\JohnF\IM\ (where the 2018 .sky files expect it)
- [ ] Find the 48.8 min case (not in the pptx; maybe in another JohnF doc or email)

## Test Data (John, Agilent DTIMS, 2018)

* Case 1 (IM\Occasional Miss-Annotation of Drift Time (2).pptx, slides 1-3):
  R.VLSSIEQK.S 2+ (452.2609), 1433S_MOUSE, doc MouseLiverDigest_by_AutoMSMS-IM-Only.sky on
  5ug_MouseLiverDigest_IM-MS.d. Interferer at 19.5 min dominates M+1 (452.76) at a different
  drift time; correct peak 20.5 min with M and M+1 co-aligned near 23 ms. Doc's 3 targets:
  AVTEQGHELSNEER 3+, NVTELNEPLSNEER 2+, VLSSIEQK 2+.
* AltFrame All-Ions run: IM\5ug_MouseLiverDigest_AltFrame_IM-MS.d (23 GB),
  doc IM\MouseLiverDigest_by_AutoMSMS\MouseLiverDigest_by_AutoMSMS.sky.
* Slide images extracted to ai/.tmp/sessions/20261127-impeak/johnf_pptx/.
* 3-precursor doc: IM\MouseLiverDigest_by_AutoMSMS-IM-Only-SubsetBSP.sky (+ .blib/.slc document
  library). ai/.tmp/sessions/20261127-impeak/Make-NoImDoc.ps1 strips results (and IM unless
  -KeepIonMobility). Runs live in D:\bench\im-peak-picking (doc library copied beside each doc).

### Baseline on master (2026-11-27, Debug build, ~30 s import)

* No IM (JohnF_Subset_NoIM_master.sky): VLSSIEQK 2+ picks 19.502 min, isotope_dotp 0.810,
  original_score 14.12 - WRONG, reproduces John's report.
* With 2018-learned IM 22.598 ms, RP 50, window 0.904 ms (JohnF_Subset_WithIM_master.sky):
  VLSSIEQK picks 20.521 min, isotope_dotp 0.992, original_score 14.82 - RIGHT. So a single
  RP50-wide band at the right drift time is enough for the existing picker to separate the
  interferer. AVTEQGHELSNEER (18.42) and NVTELNEPLSNEER (44.97) pick the same peak either way.

## Acceptance

- John's 2018 cases pick the right peak with the right IM value (20.5 min rather than
  19.5 min; the 48.8 min peak where M, M+1 and top fragment align in RT and IM)
- IM library filled by *Use Results* after one import matches one built from a clean,
  simple-mixture run, within tolerance
- No regressions when IM filtering is on

## Regression Test

- **Test name**: (filled in once written)
- **Test project**: TestFunctional or TestPerf (depends on data size)
- **Fails on master**: (pending)
- **Passes on fix**: (pending)

## Progress Log

### 2026-11-27 - Session Start

Starting work on this issue. Branch created in C:\Dev\PeakPickWithIM.

Design constraint from Brian: do NOT seed candidates from RT peaks found in the summed-IM
chromatogram - interference in the sum is the very problem, so the true peak may never be
a candidate. Candidates must come from IM-resolved data (sliding IM window / IM bands /
2D RT x IM), which is the expensive option; cost must be bounded and measured.

Code map (paths under pwiz_tools/Skyline):
* IM window per precursor: SpectrumFilter ctor (Model/Results/SpectrumFilter.cs:230) via
  SrmSettings.GetIonMobilityFilter (SrmSettings.cs:1037); EMPTY when nothing known, and
  SpectrumFilterPair.FilterSpectrumList then sums every IM bin (SpectrumFilterPair.cs:204-428).
* Extraction key PrecursorTextId includes the IonMobilityFilter (SpectrumFilter.cs:302), so K
  band filters per precursor are cheap to create at extraction.
* BUT downstream grouping ignores IM: ChromKey.ComparePrecursors (ChromHeaderInfo.cs:2030) and
  PeptideChromDataSets.FindAndMerge (PeptideChromData.cs:943) would fold all K bands into one
  ChromDataSet as duplicate transitions. Band competition has to happen explicitly before
  peak picking / storage.
* Scoring calculators (Scoring/IPeakScoringModel.cs:699 CALCULATORS) see no IM at all; ChromPeak
  has no IM field. Only extraction filter IM is stored (ChromTransition.IonMobilityValue ->
  TransitionChromInfo.IonMobility).
* Use Results: IonMobilityFinder (Model/Results/IonMobilityFinder.cs); GetApexRTs :392 uses ALL
  stored candidate peaks of M0, isotope iDotP matching in EvaluateBestIonMobilityValue :511.
* Must work for ALL IM flavors (Brian): DTIMS (Agilent, ms), TWIMS (Waters, ms, MSe), TIMS
  (Bruker 1/K0, PASEF/diaPASEF/All-Ions), SLIM (MOBILion), FAIMS (Thermo/SCIEX compensation_V,
  discrete CV per scan). Waters SONAR (waters_sonar units) is not IM - excluded. Keep the band
  generator per-flavor and everything downstream flavor-agnostic (bands are just IonMobilityFilters).
  Flavor differences to handle: continuous vs discrete (FAIMS: one band per observed CV, no
  sliding); combined 3-array vs per-scan IM spectra (SpectrumFilter.IsOutsideIonMobilityRange
  rejects per-scan IM outside known windows); diaPASEF MS2 already restricted to the window
  group's IM span; high-energy fragment IM offset (Waters/Agilent all-ions) vs none (TIMS);
  WidthAt() returns 0 for WindowWidthMode.none so a default band width per unit is needed;
  CCS-trendline narrowing only where CCS conversion exists (not FAIMS).
* Brian 2026-11-27: we may ASSUME CCS conversion is available, and may REQUIRE a functional
  FilterWindowWidthCalculator.WidthAt (non-none window mode) for the opt-in feature. So: band
  search range per precursor = per-charge CCS-vs-m/z trendline +/- tolerance, converted to the
  file's IM units via the file's CCS calibration; band width from WidthAt. FAIMS (no CCS) keeps
  the discrete one-band-per-CV path, which is cheap anyway.
* Candidate tests: TestPerf MeasuredDriftValuesPerfTest (PerfMeasuredDriftTimes.cs, Agilent .d,
  no IM library then Use Results), AgilentIMSImportTest; TestData WatersImsMseNoDriftTimesChromatogramTest.
