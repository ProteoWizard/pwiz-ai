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
- [x] Find the 48.8 min case: John's email "The Summum Bonum on Drift Time / CCS Annotation"
      (2018-09-29). K.IMFVGGPNTR.K 2+ (546.2870; M, M+1, y6 601.3052+) in
      5ug_MouseLiverDigest_AltFrame_IM-MS.d, after CCS Predictor on M/M+1 then adding one
      fragment. Skyline picked ~50.1 min; M+1 has a large interference apex at 50.7, M peaks at
      52.0; John expected the small co-eluting 48.8 min peak. His drift spectrum at 48.8 showed no
      IM ambiguity. Peptide is in the full MouseLiverDigest_by_AutoMSMS*.sky docs, not the
      3-precursor subset. He asked to search for a common drift apex over the RT window with the
      high-energy offset off or small - i.e. bands must carry the fragment offset or tolerate it.
- [x] Second fixture: trim IMFVGGPNTR (546.287 / 547.2884 / 601.3052) from the AltFrame .d -
      one mzWindow must span 545.5-602, so even at 47.5-53 min it is 176 MB
      (D:\bench\im-peak-picking\trim\IMFVGGPNTR_trim2.mzML); perf-test data, not repo.
      Doc: D:\bench\im-peak-picking\trim\IMFVGGPNTR_only.sky (no IM, no library, RT filter none).

## Prototype status (2026-11-27, uncommitted in C:\Dev\PeakPickWithIM)

* Setting: TransitionIonMobilityFiltering.SearchIonMobilityWhenUnknown (XML
  search_ion_mobility_when_unknown, both 26.11/Current xsd, audit-log name); CanSearchIonMobility
  requires a window width mode other than none.
* Bands: SpectrumFilter.GetIonMobilitySearchBands - 10%..100% of the file's max IM, WidthAt()
  wide, half overlap (117 bands at RP50 on John's 59.5 ms range); not FAIMS/SONAR. Needed
  SpectraChromDataProvider.NeedMaxIonMobilityValue to fetch the max when searching.
* Competition: ChromCacheBuilder.GetChromDataSets splits a precursor's chromatograms by band IM;
  PeptideChromDataSets keeps extra bands aside (_ionMobilityBandSets), scores each band by
  picking peaks on clones, keeps the winner before the normal pick. Ranking = best legacy
  CombinedScore (placeholder). TEMPORARY Console.WriteLine diagnostics still in.
* Test TestIonMobilitySearch (TestData, IonMobilitySearchTest.zip 2.9 MB): summed picks 17.53;
  searched picks 19.30 (band 23.33 ms) - red.
* FINDING: in MS1-only M/M+1 data with no RT constraint, the 22.4-23.8 ms bands hold three clean
  features: 17.53/17.67 (idotp 0.98-0.99), 19.30 @ ~23.5 ms (idotp 0.97, shape 0.97) and
  20.52 @ ~22.6 ms (idotp 0.97-0.997, shape 0.93-0.99). The 19.5 interferer drops to idotp
  0.61 in the 22.4 band, so bands do remove the summed-IM interference, but nothing in M/M+1
  alone says which clean feature is VLSSIEQK. The test doc stripped John's library (ID RT
  20.1 from the AutoMSMS run) and ms2_ids +/-5 min filter; even with them, 19.30 is in range.
  Fragments (AltFrame run) or an ID/predicted RT are what can decide. Needs Brian's call on
  the test's premise and on band ranking.

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

### Test data trimming (2026-11-27)

* CCS conversion exists only in vendor readers (pwiz/data/msdata/IIonMobilityCcsConversion.cs:
  Agilent, Bruker, Waters, Mobilion), never mzML. So band range = CCS trendline when the file
  converts, else the file's observed IM range (fallback makes mzML test data possible).
* msconvert --combineIonMobilitySpectra + scanTime [1020,1440] + mzWindow [450,455] gives a
  15.9 MB mzML (D:\bench\im-peak-picking\trim\VLSSIEQK_trim.mzML) - BUT it is corrupt:
  m/z and intensity arrays 13,618 long, raw ion mobility array 2,031,351 long.
* Root cause: pwiz C# port regression. pwiz/analysis/SpectrumListMzWindow.cs trims only m/z and
  intensity. The retired C++ SpectrumList_MZWindow (git show 6dd40d8c93^:pwiz/analysis/
  spectrum_processing/SpectrumList_MZWindow.cpp) sort_together'ed and trimmed every array of
  m/z length. Needs a pwiz-module fix (separate PR) before the trimmed test data is usable.
* Unverified side note: every combined spectrum also carries a scan-level "ion mobility drift
  time" (29.9298, constant). Stripping it did not change the result (array mismatch dominates);
  check whether C++ msconvert wrote it too.
* With the corrupt file: no-IM import picks 17.53 min (isotope dotp 0.99) because RT filter and
  library were removed for the test doc; with IM 22.598 no peak at all.

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
