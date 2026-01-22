# TODO-20260122_SpectrumFilterMissingChromatograms.md

## Branch Information
- **Branch**: `Skyline/work/20260122_SpectrumFilterMissingChromatograms`
- **Base**: `master`
- **Created**: 2026-01-22
- **Status**: In Progress
- **GitHub Issue**: (none yet)
- **PR**: (pending)

## Objective

Investigate and fix why documents with spectrum class filters (e.g., HCD) are missing chromatograms after results import, while equivalent documents created from scratch work correctly.

## Task Checklist

### Completed
- [x] Created test `ImportSpectrumFilterTransitionListTest` to reproduce the issue
- [x] Confirmed 99 transition groups with HCD spectrum filter are missing chromatograms
- [x] Traced chromatogram extraction flow through `SpectraChromDataProvider`, `SpectrumFilter`, `ChromatogramGroupId`
- [x] Ruled out global `SpectrumClassFilter` as the cause (both documents have empty global filters)
- [x] Confirmed both documents have identical filter pairs (990 total, 495 HCD each)
- [x] Confirmed both documents have identical `ChromatogramGroupId` values
- [x] Confirmed OptStep is null for all HCD filter pairs (so CollisionEnergy check in FilterQ3SpectrumList is skipped)
- [x] Confirmed issue persists even when importing ONLY WithTransitions.sky (not related to import order)

### In Progress
- [ ] Determine exactly WHERE in the extraction pipeline HCD chromatograms are being lost

### Remaining
- [ ] Implement fix
- [ ] Verify fix passes the test
- [ ] Add any additional test coverage
- [ ] Clean up diagnostic code from test

## Key Files

- `pwiz_tools/Skyline/TestFunctional/ImportSpectrumFilterTransitionListTest.cs` - Test reproducing the issue
- `pwiz_tools/Skyline/TestFunctional/ImportSpectrumFilterTransitionListTest.data/` - Test data directory
- `pwiz_tools/Skyline/Model/Results/SpectraChromDataProvider.cs` - Main extraction driver
- `pwiz_tools/Skyline/Model/Results/SpectrumFilter.cs` - Filter pair creation and spectrum matching
- `pwiz_tools/Skyline/Model/Results/SpectrumFilterPair.cs` - Individual filter pair, `FilterQ3SpectrumList()`, `MatchesSpectrum()`
- `pwiz_tools/Skyline/Model/Results/ChromatogramGroupId.cs` - `ForPeptide()` creates ID with `SpectrumClassFilter`
- `pwiz_tools/Skyline/Model/Results/ChromatogramCache.cs` - Cache lookup requires exact `SpectrumClassFilter` match
- `pwiz_tools/Skyline/Model/Results/Spectra/SpectrumClassFilter.cs` - `MakePredicate()` for spectrum matching

## Critical Diagnostic Results

### Latest Test Output (simplified test - only imports WithTransitions.sky)
```
=== SPECTRUM FILTER PAIRS ===
Total filter pairs: 990
HCD filter pairs: 495
Empty filter pairs: 0
HCD filter pairs with OptStep: 0
HCD OptStep values: null

=== CACHE ENTRIES ===
Total cache entries: 102
HCD cache entries: 0
Empty filter cache entries: 3

=== DISTINCT SPECTRUM FILTERS IN CACHE ===
Cache distinct filters: , (null), Dissociation Method=CID AND Collision Energy=20 AND MS Level=2

=== DOCUMENT ===
Unique HCD ChromatogramGroupIds: 495
HCD transition groups BEFORE import: 495
Empty filter groups BEFORE import: 0
HCD transition groups AFTER import: 495
Empty filter groups AFTER import: 0
```

### Key Findings
1. **Filter pairs are IDENTICAL** between blank doc and WithTransitions.sky
   - Both have 990 total filter pairs
   - Both have 495 HCD filter pairs
   - 0 differences between filter pair sets

2. **Cache entries differ dramatically**
   - Blank doc: 201 entries (99 HCD, 102 non-HCD)
   - WithTransitions: 102 entries (0 HCD, 102 non-HCD)
   - The 102 = 201 - 99 pattern confirms ONLY HCD is missing

3. **CID extraction works for both documents**
   - Both extract `Dissociation Method=CID AND Collision Energy=20 AND MS Level=2`
   - Only HCD (`Dissociation Method=HCD AND Collision Energy=15 AND MS Level=2`) fails for WithTransitions

4. **OptStep is null for all filter pairs**
   - This means `CollisionEnergy` (from optimization) is also null
   - The collision energy check in `FilterQ3SpectrumList` (lines 160-177) is SKIPPED
   - So that's NOT the cause

5. **Issue persists when importing WithTransitions.sky first**
   - Not related to state from previous import
   - Problem is inherent to WithTransitions.sky document

## Document Differences

### BlankDocument.sky
- No peptides (truly blank)
- Settings identical to WithTransitions.sky
- After importing transition list: gets same transition groups as WithTransitions.sky
- Successfully extracts HCD chromatograms

### WithTransitions.sky
- Has peptide_lists organized by spectrum filter (label_name contains filter string)
- Precursors have `collision_energy="0"` attribute (calculated, not explicit)
- Has 495 HCD transition groups before import
- Fails to extract HCD chromatograms

### Settings (identical in both)
```xml
<transition_full_scan acquisition_method="PRM" product_mass_analyzer="qit" product_res="0.7" />
<transition_prediction ... optimize_by="None" />
```

## Extraction Pipeline Analysis

### Data Flow
```
1. SpectrumFilter constructor creates filter pairs from document
   - dictPrecursorMzToFilter keyed by PrecursorTextId
   - _filterMzValues = dictPrecursorMzToFilter.Values.ToArray()
   - Sorted by PrecursorTextIdComparer (mz, OptStep, CE, IM, ChromatogramGroupId, Extractor)

2. For each spectrum in raw file:
   a. Extract() called with spectrum array
   b. GetIsolationWindows() returns isolation m/z
   c. FindFilterPairs() searches _filterMzValues by m/z (binary search + forward iteration)
   d. For PRM: returns filter pairs with CLOSEST m/z match

3. For each matching filter pair:
   a. Check ContainsRetentionTime()
   b. If SpectrumClassFilter is not empty:
      - Call MatchesSpectrum() which uses SpectrumClassFilter.MakePredicate()
      - If no spectra match, SKIP this filter pair
   c. Call FilterQ3SpectrumList() to extract chromatogram data
   d. Yield ExtractedSpectrum with FilterIndex = filterPair.Id

4. ProcessExtractedSpectrum() stores data in PrecursorCollectorMap[spectrum.FilterIndex]

5. AddChromatogramsForFilterPair() retrieves from PrecursorCollectorMap[filterPair.Id]

6. Cache written with ChromKey including ChromatogramGroupId
```

### Where Issue Could Be
The user observed "chromatograms were being extracted, but were somehow being lost."

Possible locations:
1. **FindFilterPairs()** - HCD filter pairs not being found for HCD spectra
   - But filter pairs are identical, so this seems unlikely

2. **MatchesSpectrum()** - HCD spectra not matching HCD filter
   - Same raw file works for blank doc, so metadata is correct

3. **FilterQ3SpectrumList()** - Returns null for some reason
   - CollisionEnergy check is skipped (OptStep is null)

4. **Storage/Retrieval mismatch** - FilterIndex doesn't match filterPair.Id
   - Would require different filter pairs during extraction vs. retrieval

5. **Something specific to how WithTransitions.sky is structured**
   - Peptide lists vs. flat list?
   - Some attribute or setting that affects extraction?

## Hypotheses to Test

### Hypothesis 1: SpectrumFilter differs between test diagnostic and actual import
The test creates `new SpectrumFilter(document)` AFTER import using the simple constructor.
The actual import uses the full constructor with additional parameters:
- `msDataFileUri`
- `instrumentInfo`
- `chromatogramSet`
- `maxObservedIonMobilityValue`
- `retentionTimePredictor`
- `firstPass`
- `gce`

**Test**: Create SpectrumFilter BEFORE import and compare to one created after.

### Hypothesis 2: Filter pair Id assignment differs
Filter pairs get `Id = dictPrecursorMzToFilter.Count` at creation time.
If documents enumerate peptides in different order, Ids could differ.

**Test**: Compare the Id values of corresponding filter pairs between documents.

### Hypothesis 3: Something in MatchesSpectrum is failing
The predicate created from SpectrumClassFilter might behave differently.

**Test**: Add logging to trace MatchesSpectrum calls for HCD filter pairs.

### Hypothesis 4: Raw file spectra metadata differs between imports
Unlikely since same raw file, but worth checking.

**Test**: Log spectrum metadata during extraction for both imports.

## Next Steps

1. **Add more targeted diagnostics** to trace the extraction process:
   - Log when HCD filter pairs are found by `FindFilterPairs`
   - Log when `MatchesSpectrum` is called and what it returns
   - Log when `FilterQ3SpectrumList` is called and if it returns data
   - Log when data is stored in `PrecursorCollectorMap`

2. **Compare SpectrumFilter state during actual import** vs. test diagnostic:
   - Access SpectrumFilter through reflection or add test hooks
   - Compare filter pair arrays

3. **Examine the document structure more closely**:
   - Check if peptide list organization affects filter pair creation
   - Check if any document properties affect SpectrumFilter behavior

## Code Locations for Debugging

### To trace FindFilterPairs results
`SpectrumFilter.cs` line 1275-1390 - `FindFilterPairs()`

### To trace MatchesSpectrum
`SpectrumFilterPair.cs` line 561-569 - `MatchesSpectrum()`
`SpectrumClassFilter.cs` line 123-145 - `MakePredicate()`

### To trace extraction
`SpectrumFilter.cs` line 973-1030 - `Extract()`
`SpectrumFilterPair.cs` line 155-388 - `FilterQ3SpectrumList()`

### To trace storage/retrieval
`SpectraChromDataProvider.cs` line 1706+ - `ProcessExtractedSpectrum()`
`SpectraChromDataProvider.cs` line 422+ - `AddChromatogramsForFilterPair()`

## Test Data

- **Raw file**: `crv_qf_hsp_ms2_opt0.raw` (in `crv_qf_hsp_ms2_opt0.zip`)
  - Contains HCD/CE=15 and CID/CE=20 spectra
  - 99 peptides with HCD data

- **BlankDocument.sky**: Empty document with settings configured

- **WithTransitions.sky**: Document with 495 peptides × 5 CE levels = 495 HCD transition groups
  - Peptides organized in peptide_lists by spectrum filter
  - Only CE=15 (HCD) is relevant for this raw file

- **TransitionList.csv**: Transition list with spectrum class filters for import into blank doc

## Progress Log

### 2026-01-22 - Session 1 (continued)
- Confirmed issue is specific to WithTransitions.sky (not import order)
- Added OptStep diagnostic - confirmed it's null for all HCD filter pairs
- This rules out the CollisionEnergy check in FilterQ3SpectrumList
- Both documents create identical filter pairs
- CID extraction works, only HCD fails
- Next: need to trace exactly where in the pipeline HCD chromatograms are lost

### 2026-01-22 - Session 1 (initial)
- Created test to reproduce the issue
- Initial hypothesis (global spectrum filter) was WRONG
- Traced through extraction pipeline
- Added extensive diagnostics
