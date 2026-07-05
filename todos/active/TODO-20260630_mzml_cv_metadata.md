# TODO-20260630_mzml_cv_metadata.md

## Branch Information
- **Branch**: `Skyline/work/20260630_mzml_cv_metadata`
- **Base**: `master` (checkout `C:\Dev\SmartCV`)
- **Created**: 2026-06-30
- **Status**: Phase 1 PR open; self-review + Copilot addressed (commit 9e3f912), threads resolved; awaiting TeamCity + human review. Phase 2 planned.
- **GitHub Issue**: (none)
- **PR**: https://github.com/ProteoWizard/pwiz/pull/4349 (Brian adds the screenshot to the description manually)

## Objective

Surface the mzML controlled-vocabulary (CV) and user parameters that Skyline reads
through the ProteoWizard API but does not interpret into its own typed fields, so users
can (1) see them in the FullScan graph's properties sidebar and (2) eventually set
Spectrum Filters on them.

## Context

`MsDataFileImpl.GetSpectrumMetadata` hand-maps ~20 known CVIDs into typed fields; every
other cvParam/userParam was dropped. Examples lost: base-peak m/z (MS:1000504), base-peak
intensity (MS:1000505), lowest/highest observed m/z, Thermo filter string (MS:1000512),
vendor userParams. Full design and decisions in the plan file
`~/.claude/plans/when-skyline-reads-mass-validated-milner.md`.

Key decisions (made with the user): per-(term, unit) "split by unit" properties; runtime
numeric-vs-string type inference (throw on numeric mismatch); friendly names from the CV
ontology, keyed internally by accession.

## Phase 1 - Capture + FullScan sidebar display (COMPLETE, local)

- `CommonUtil/Spectra/SpectrumMetadataTerm.cs` (new) - immutable {Accession, Name, Value, Unit}.
- `CommonUtil/Spectra/SpectrumMetadata.cs` - `OtherParams` ImmutableList, excluded from
  Equals/GetHashCode (spectrum identity stays the interpreted fields).
- `ProteowizardWrapper/MsDataFileImpl.cs` - captures uninterpreted spectrum/scan/scan-window
  cvParams + userParams, skip-set of interpreted CVIDs; gated on new `CaptureOtherParams`
  flag so only the viewer pays for it.
- `Skyline/Model/Results/ScanProvider.cs` - sets `CaptureOtherParams` on the display reader.
- `Skyline/Model/RawMetadataProperties.cs` (new) - ICustomTypeDescriptor; expandable
  "Raw metadata" node in the FullScan sidebar.
- `Skyline/Model/FullScanProperties.cs` + `FullScanPropertiesRes` - new RawMetadata category.
- Display refinements (commits 2-4): terms shown as a single expandable **"Raw Metadata"** node
  (children = terms) in the **Acquisition** category. Each term carries its CV definition
  (`CVTermInfo.def`, captured in the wrapper) as PropertyGrid help text; the node itself has help
  text (`Description_RawMetadata`); value-less flag terms show a blank value. Expandable nodes stay
  expanded when stepping between scans (`MsGraphExtension.SetSelectedObjectPreservingExpansion`,
  called from `GraphFullScan`).
  - **Why a nested node, not bare rows under a top-level "Raw Metadata" category:** WinForms
    `PropertyGrid` throws an NRE in `RestoreHierarchyState`/`GridEntry.NonParentEquals` when custom
    `PropertyDescriptor`s form a *dynamic top-level category*. The nested-expandable-object pattern
    (same as the existing Instrument node) is robust. `RawMetadataInfo` is that node. User chose the
    node-under-Acquisition layout over a top-level category with a redundant intermediate node.
- Test: `FullScanPropertiesTest` asserts MS:1000505/MS:1000512 surface, interpreted terms
  (TIC/ms-level) are not duplicated, the CV definition is captured and wired as the grid row's
  help text, and the Parameters node stays expanded across `ChangeScan(1)`.

Verified: Build Debug|x64 clean; TestFullScanProperties passes; CodeInspection passes;
ReSharper full inspection clean for changed files (notes only, all pre-existing).

Commits (local, branch `Skyline/work/20260630_mzml_cv_metadata`, not pushed):
`cd868e7` (capture + display), `b8d2d82` (display refinements).

## Phase 2 - Filtering (PLANNED)

Discovered per-(term, unit) dynamic `SpectrumClassColumn`s; evaluate CV-term FilterSpecs
directly against `SpectrumMetadata` via `FilterPredicate.MakePredicate(type)` (bypassing the
`SpectrumClass` POCO projection); discovery feeds the Spectrum Grid + EditSpectrumFilterDlg +
autocomplete; persist the term bag in the per-file metadata cache (proto + CacheFormatVersion
bump) for grid/autocomplete over already-imported files. See plan file for detail.

## Phase 2 - Filtering (IN PROGRESS, branch `Skyline/work/20260701_mzml_cv_filtering` off Phase 1)

### Phase 2a - predicate core + round-trip (DONE, committed `7c5810e08`, tested)
- `SpectrumClassColumn.cs`: new dynamic `CvParamColumn` keyed by (accession, unit), read from
  `SpectrumMetadata.OtherParams`; NOT bound to a SpectrumClass property (its SpectrumClass accessors
  throw). Encoded path-safe **alphanumeric** column name `"cvparam"+hex(accessionunit)` (PropertyPath
  only leaves letters/digits unquoted, so base64 would double-quote and risk double-escaping through the
  two filter-string serializer layers). `FindColumn` reconstructs a CV column from the path alone (so saved
  filters validate/reload before import). `GetLocalizedColumnName` made virtual; CV override shows
  "name (unit)".
- `SpectrumClassFilter.MakePredicate`: splits each clause into CV vs non-CV specs. Non-CV keep projecting
  through the SpectrumClass POCO; CV specs evaluate directly against SpectrumMetadata. Type inferred from
  operator/operand (ordered->numeric, contains/startswith->string, equals->numeric iff operand parses as
  number). Numeric comparison meeting a present non-numeric value THROWS InvalidDataException with filter
  context (reuses the existing "Error evaluating the spectrum filter: {0}" wrap + new resource).
- Unit tests in `Test/SpectrumClassFilterTest.cs` (TestCvParamColumnRoundTrip, TestCvParamFilterPredicate)
  all green. TestSpectrumClassFilter passes.

### Phase 2b - persist term bag in cache (DONE, committed `c025989ab`, tested)
- proto OtherParam pool (field 6) + SpectrumMetadata.otherParamIndex (field 17); SpectrumMetadatas
  (de)serialize mirroring the precursor pool/index pattern; null value/unit/definition round-trip as null.
- Generated proto C# is git-ignored and regenerated on every build (Skyline.csproj PreBuildEvent ->
  generatecode.bat, bundled protoc); committing the .proto is sufficient.
- Round-trip test `TestResultFileMetaDataOtherParams` in TestData/Results/ResultFileMetaDataTest.cs (green).
- **NO cache-format version bump**: ResultFileMetaData is a self-describing protobuf blob (written for
  caches >= Eighteen; CURRENT=Nineteen), so a new `repeated` field is forward/backward compatible without
  a bump. The bump is optional/advisory -> CHECKPOINT below.

### Phase 2 capture-during-extraction (DONE, committed `58d74249c`, tested)
- Load-bearing gap: Phase 1 captured OtherParams only for the full-scan VIEWER, so extraction saw
  empty bags and a CV filter would match nothing. Added SpectrumClassFilter.ReferencesCvColumns();
  SpectraChromDataProvider sets MsDataFileImpl.CaptureOtherParams when the document's full-scan filter
  or any transition group filter references a CV column (perf: pay only when filtering on CV). Capture
  is in the shared GetSpectrum(Spectrum,int), so terms flow into both the extraction predicate and the
  persisted cache. Regression (Ms1SpectrumFilterTest etc.) still green.

### Phase 2 end-to-end functional test (DONE, committed `4dc139237`)
- TestCvSpectrumFilter (TestFunctional): reuses Ms1SpectrumFilterTest data (MS:1000505 base peak
  intensity in sci-notation, MS:1000512 filter string with cv=-50/-70). Two "contains" filters on the
  filter string partition the MS1 spectra (unfiltered == cv50 + cv70); a numeric base-peak-intensity
  filter admitting all matches everything. Applies filters via EditMenu.ChangeSpectrumFilter (no dialog,
  since Phase 2c UI is not built). PASSES - proves the feature in the real extraction pipeline.

### CHECKPOINT RESOLVED (2026-07-02): no cache-format version bump.
Brian decided NOT to bump CacheFormatVersion. Persistence rides in the self-describing ResultFileMetaData
protobuf blob (forward/backward compatible), so no bump is needed. CacheFormat.cs / SkylineVersion.cs
left untouched.

### Phase 2c - filter editor + catalog (DONE for the editor path; grid display remains)

Design pivot (decided with Brian 2026-07-04): the PSI-MS vocabulary compiled into ProteoWizard does
NOT expose a term's units or value-type to managed code (verified in cv.hpp CVTermInfo). So units can't
be known without data. Decisions:
- **Identity = CVID (accession) only**; split-by-unit dropped. (commit `ce5979d0a`)
- Compact token underneath: `cvid`+accession-without-colon (CV terms), `cvup`+hex(name) (userParams).
- Display readable as **`name (CVID)`**, e.g. "base peak intensity (MS:1000505)".
- **Catalog** the spectrum/scan-level CV terms from the ontology so the editor offers them with no
  import (solves the discover-before-filter chicken-and-egg). (commit `4a54f8744`)

Committed:
- `2086ff69c` editor offers data-discovered CV columns (FilterColumn abstraction in EditSpectrumFilterDlg;
  DiscoverCvColumns; EditMenu wiring).
- `ce5979d0a` CVID-only identity (dropped unit), compact cvid/cvup token, `name (CVID)` display.
- `4a54f8744` ontology catalog (MsDataFileImpl.GetSpectrumCvTermCatalog over CV.cvids()/parentsIsA under
  spectrum property / spectrum attribute / scan attribute roots, excluding obsolete + interpreted;
  SpectrumClassColumn.GetCvColumnCatalog / GetEditorCvColumns; EditMenu uses GetEditorCvColumns).
- Tests green: TestSpectrumClassFilter (incl. discovery), TestCvSpectrumFilter (partition + editor +
  catalog assertions), EditSpectrumFilterTest regression. CodeInspection passes.

### Phase 2c grid display (DONE, committed `8b5c616a9`, tested)
- SpectrumClass carries a `CvValues` dictionary (keyed by encoded column name); CvParamColumn's
  SpectrumClass accessors read/write it instead of throwing, so CV columns take part in grid grouping
  and the grid's MakeFilter.
- SpectrumGridForm.EnsureCvColumns discovers CV columns from imported metadata, adds them to the column
  checkbox (opt-in, hidden by default, preserving check states); the default view binds a checked CV
  column as a `SpectrumClass.CvValues!<encodedName>` lookup with the friendly `name (CVID)` caption.
- Functional test asserts checking base peak intensity makes it appear in the grid; SpectrumGridTest
  regression still passes. CodeInspection green.

Remaining (follow-ups):
- **"Declared" filter operator (NEXT, designed with Brian 2026-07-04).** A general presence test for CV
  columns: "`<term> Declared True/False`" = is this CV term present in the spectrum's OtherParams,
  regardless of whether it carries a value. Applies to ANY CV column (value-bearing or bare flag), which
  is why it is needed - the existing operators can't distinguish a present flag (captured as empty value,
  reads as blank) from an absent one. Predicate: present = `CvParamColumn.GetValue(metadata) != null`,
  absent = null, compared to the True/False operand. Implementation touches shared FilterOperations (new
  op + OpName/OpSymbol/serialization/parser + gate via IsValidFor so it is offered for these columns) and
  the CV predicate in SpectrumClassFilter (handle the Declared op by presence rather than value). Name
  chosen: "Declared" (a cvParam is a declaration in mzML). Add unit + functional coverage.
- **Autocomplete** of CV filter values (SpectrumFilterAutoComplete): include CV columns. Deferred (nicety).
- **Grid direct file-read path** (SpectrumReader.ReadSpectraFromFile uses GetSpectrumMetadata, which does
  not capture OtherParams) shows no CV values for not-yet-imported files; the imported-cache path works.
- Editing an existing CV filter whose accession isn't in the catalog nor discovered still drops the row
  in the editor (pre-existing unknown-column behavior) - minor.

### Gates (2026-07-04): CodeInspection green; ReSharper full-solution inspection clean on all changed
files (one stale-doc-comment warning found and fixed in `95a7f918a`; remaining hits are pre-existing
notes). Branch is PR-ready pending the Declared-operator increment + push/PR decision.

**Next session handoff**: For detailed startup protocol (build/test/inspect commands, key design
decisions, and the fully-specified "Declared" operator next task), read
`ai/.tmp/handoff-20260704-mzml-cv-filtering.md` before starting work.
