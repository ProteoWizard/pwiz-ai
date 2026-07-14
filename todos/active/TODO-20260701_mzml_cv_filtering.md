# TODO-20260701_mzml_cv_filtering.md

## Branch Information
- **Branch**: `Skyline/work/20260701_mzml_cv_filtering` (checkout `C:\Dev\SmartCV`)
- **Base**: `master` (was branched off the Phase 1 branch, now merged as `cdea33f0b`)
- **Created**: 2026-07-01
- **Status**: In progress, unpushed. Phase 2a/2b/2c + Declared operator + filter-string
  authoring all done and green locally. Gates not re-run since the Declared increment.
- **GitHub Issue**: (none)
- **PR**: (none yet)

Phase 1 (capture + full-scan display) shipped in
[#4349](https://github.com/ProteoWizard/pwiz/pull/4349), merged 2026-07-14 as `cdea33f0b`.
Record: `ai/todos/completed/TODO-20260630_mzml_cv_metadata.md`. Note that Phase 1 renamed the
display node to **"Other Metadata"** (`OtherMetadataInfo`) and added per-unit value formatting;
rebase this branch onto the merged master before doing more work.

## Objective

Let users set Spectrum Filters on the mzML CV/user parameters that Phase 1 surfaced: discover
them, filter on them during extraction, persist them in the cache, and offer them in the filter
editor and Spectrum Grid.

## Context

Discovered per-(term, unit) dynamic `SpectrumClassColumn`s; evaluate CV-term FilterSpecs
directly against `SpectrumMetadata` via `FilterPredicate.MakePredicate(type)` (bypassing the
`SpectrumClass` POCO projection); discovery feeds the Spectrum Grid + EditSpectrumFilterDlg +
autocomplete; persist the term bag in the per-file metadata cache. See the plan file
`~/.claude/plans/when-skyline-reads-mass-validated-milner.md` for detail.

### Phase 2a - predicate core + round-trip (DONE, committed `7c5810e08`, tested)
- `SpectrumClassColumn.cs`: new dynamic `CvParamColumn` keyed by (accession, unit), read from
  `SpectrumMetadata.OtherParams`; NOT bound to a SpectrumClass property (its SpectrumClass accessors
  throw). Encoded path-safe **alphanumeric** column name `"cvparam"+hex(accessionunit)` (PropertyPath
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
- **NO cache-format version bump** (CHECKPOINT RESOLVED 2026-07-02, Brian): ResultFileMetaData is a
  self-describing protobuf blob (written for caches >= Eighteen; CURRENT=Nineteen), so a new `repeated`
  field is forward/backward compatible without a bump. CacheFormat.cs / SkylineVersion.cs untouched.

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

### Phase 2c - filter editor + catalog (DONE for the editor path; grid display below)

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

### Declared operator (DONE 2026-07-05, unpushed, all green)
Built as a **unary pair** "Is Declared"/"Is Not Declared" (NOT the originally-sketched bool-operand
`Declared True/False` - the unary shape mirrors `OpIsBlank`, needs no operand cell, and the spectrum
editor lists all ops ungated so it appears automatically for CV columns). Presence = `GetValue(metadata)
!= null` (a present bare flag captures as empty string -> non-null -> Declared; absent -> null); this is
exactly the distinction `Is Not Blank` cannot make, since an empty value reads as blank.
- `FilterOperation.cs`: `OP_IS_DECLARED`/`OP_IS_NOT_DECLARED` as `UnaryFilterOperation`s. `IsValidFor`
  returns **false** everywhere -> report/quick filters (which honor IsValidFor) hide them; only the
  spectrum-filter editor (ungated list) offers them. No gating-machinery changes, no blast radius.
- `SpectrumClassFilter.CompileCvSpec`: explicit presence special-case (bypasses value coercion).
- New master resources `FilterOperations_Is_Declared` / `_Is_Not_Declared`.
- **Cache-persistence bug found+fixed via the functional test**: the `.skyd` cache serializes filters
  through a SEPARATE proto enum map (`ChromatogramGroupId._filterOperationMap` + `ChromatogramGroupData.proto`
  `FilterOperation` enum), independent of the registry. Added `FILTER_OP_IS_DECLARED`/`_IS_NOT_DECLARED`
  (append-only enum, no cache-format bump) + map entries. See memory `reference_filter_operator_registration_points`.
- Tests: unit `TestCvParamDeclaredFilter` (present flag / valued / absent + the Is-Not-Blank contrast +
  round-trip) and `TestDeclaredOperatorScoping` (IsValidFor false, registered by symbol) in
  `SpectrumClassFilterTest`; functional Declared assertions folded into `TestCvSpectrumFilter` (Is Declared
  on always-present filter-string term and Is Not Declared on never-present zoom-scan term both reproduce
  the unfiltered chromatogram, exercising capture+predicate+cache round-trip); new guard
  `TestFilterOperationProtoRoundTrip` in `ChromatogramGroupIdsTest` (every ListOperations() op round-trips
  through the cache proto). All green + regression batch green. **Gates (CodeInspection + ReSharper) not
  yet re-run for this increment; not committed.**

### CV accession references in filter strings (DONE 2026-07-05, commit 288c7c5ad, all green)
Command-line/transition-list authoring: a filter string can now name a CV term by accession instead of
the opaque `cvidMS1000505` token. `SpectrumClassFilter.ParseFilterString` -> `CanonicalizeCvColumnReferences`
rewrites a bare `MS:1000505` or a double-quoted caption containing one (e.g. `"base peak intensity
(MS:1000505)"`) to the canonical token BEFORE the generic grammar (needed because `PropertyPath.Parse`
rejects the colon and a quoted caption's spaces/parens). Single-quoted operands untouched; reference
normalizes to canonical so it's identical to a UI-authored filter. Reachable via `--import-transition-list`
(shared parse path the MCP RunCommand also uses). Test: `TestCvColumnFriendlyReference` in
`SpectrumClassFilterParserTest`. Gates green (CodeInspection + ReSharper clean on changed code).

### userParam references + nonsense-input tests (DONE 2026-07-05, commit d3bf96065, all green)
- userParam authorability: a userParam (no accession) is named with the explicit `userParam:` marker
  (bare, case-insensitive, or inside a double-quoted caption for names with spaces) -> canonical `cvup...`
  token. Marker checked BEFORE the accession rule (so `userParam:123` is a userParam, not a CV term) and
  is REQUIRED - a bare unknown token stays an "unknown property" error, so a typo of an interpreted column
  doesn't silently become a no-match userParam. All in `CanonicalizeCvColumnReferences`.
- Edge/nonsense tests (`TestNonsenseColumnReferences`): well-formed-but-fake accession `MS:9999999`
  accepted (lenient, matches nothing - Brian chose to keep leniency, NOT add typo-catching validation);
  malformed accession (`MS:`, `MS:abc`) and undecodable encoded tokens (`cvidMSabc`, `cvupZZ`) -> errors;
  bare userParam name without marker -> unknown-property error.
- Known edge (not special-cased): `userParam:MS:1000505` (userParam named like an accession) encodes as
  the CV term, because the shared encoder auto-detects accessions. Pathological; document if grammar docs
  are written.

### Operator-token discoverability - A+C (DONE 2026-07-07, commit 235909c2b, all green)
Filter strings previously required the raw op symbols (`=`, `isnullorblank`, `isdeclared`), which don't
match the UI names and aren't discoverable. Fixed, SCOPED TO SPECTRUM FILTERS only (SpectrumClassFilter
parse layer; shared FilterClauseSerializer and other filter UIs untouched - confirmed Is(Not)Declared has
no use outside spectrum filters):
- **A**: friendly case-insensitive operator aliases rewritten to canonical symbols in
  `NormalizeAuthoredFilterString` (renamed from CanonicalizeCvColumnReferences; the colon fast-path was
  removed since aliases have no colon). `equals`->`=`, `greaterthan`->`>`, `isblank`->`isnullorblank`,
  etc.; already-word symbols case-normalized. English-only (like `and`/`or`). Operand-safe (single-quoted
  text untouched); only recognized alias words rewritten (column names never collide).
- **C**: the invalid-filter error now appends `Available operators: = <> > >= < <= contains ... isdeclared`
  (new resource `SpectrumClassFilter_ParseFilterString_Available_operators__0_`).
- Tests: `TestOperatorAliases`, `TestInvalidFilterListsOperators`. Updated two existing tests that used
  "Equals" as a *bad* operator example (now a valid alias): `TestValidateSpectrumClassFilter` and
  functional `TestSpectrumFilterImportError` -> use "foobar".

## Remaining

- **Rebase onto merged master** (`cdea33f0b`). Phase 1 renamed `RawMetadataInfo` -> `OtherMetadataInfo`,
  the property `RawMetadata` -> `OtherMetadata`, and the resx keys; `SpectrumMetadataTerm` gained
  `UnitAccession`. Expect conflicts in MsDataFileImpl / SpectrumMetadataTerm / ScanProvider.
- **Re-run gates** (CodeInspection + full-solution ReSharper) - not run since the Declared increment.
- **Discoverability #1 (chosen with Brian 2026-07-05; DESIGN PAUSED - capture strategy undecided).**
  Annotate the filter editor's CV column picker: distinguish terms actually **present in the loaded
  file(s)** vs the ontology **catalog** (possible-but-unseen), and surface each term's CV definition as
  tooltip/help.
  - Definition tooltip works with no capture change (catalog carries `def`; but `GetCvColumnCatalog`
    currently DROPS it building `CvParamColumn(accession, name, false)` - thread the def onto the column).
  - Picker plumbing: `EditSpectrumFilterDlg.DisplayCurrentPage` -> `AddFilterColumn`, `_extraColumns` =
    `GetEditorCvColumns(document)` (flat catalog UNION discovered, no present/catalog distinction today).
  - **Blocker (prerequisite): "present in file" is empty in the normal case.** `SpectraChromDataProvider`
    gates `CaptureOtherParams` on `DocumentReferencesCvSpectrumFilter` (a CV filter must already
    exist), so `DiscoverCvColumns(document)` (reads the cache) returns nothing pre-filter. Three options
    surfaced, decision pending with Brian (he wants to clarify tradeoffs first):
    (A) always-on capture at import - reuses cache plumbing, smallest editor change, but taxes every
    import + grows caches + risks perf/stream-audit/leak tests;
    (B) scan first N spectra of the raw files when the editor opens - isolated from import/cache path,
    reflects the actual file, but needs files accessible (fallback to catalog-only when missing);
    (C) defer capture; ship definitions + catalog/present split now, present-set lights up only after a
    filter exists.
  - (SeeMS enhancement is a secondary power-user option.)
- **Autocomplete** of CV filter values (SpectrumFilterAutoComplete): include CV columns. Deferred (nicety).
- **Grid direct file-read path** (SpectrumReader.ReadSpectraFromFile uses GetSpectrumMetadata, which does
  not capture OtherParams) shows no CV values for not-yet-imported files; the imported-cache path works.
- Editing an existing CV filter whose accession isn't in the catalog nor discovered still drops the row
  in the editor (pre-existing unknown-column behavior) - minor.

## Progress Log

### 2026-07-14 - Split from the Phase 1 TODO

Phase 1 merged as #4349 (`cdea33f0b`); this file carries the Phase 2 filtering work, which was
previously tracked in TODO-20260630_mzml_cv_metadata.md. All Phase 2 content above is unchanged
from that file. Next step is a rebase onto the merged master, since Phase 1 renamed the display
type and added `SpectrumMetadataTerm.UnitAccession`.
