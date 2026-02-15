# TODO-20251224_SkylineParquetSupport.md

## Branch Information
- **Branch**: `Skyline/work/20251224_SkylineParquetSupport`
- **Base**: `master`
- **Created**: 2024-12-24
- **Status**: In Progress
- **GitHub Issue**: (none)
- **PR**: [#3968](https://github.com/ProteoWizard/pwiz/pull/3968)
- **Objective**: Add Parquet export support for Skyline reports

## Background

Skyline currently exports reports in CSV, TSV, and other text-based formats. For very large reports (millions of rows), these formats are inefficient both in file size and read/write performance. Parquet is a columnar storage format designed for efficient data storage and retrieval, widely used in data science and analytics workflows.

This feature adds the ability to export Skyline reports directly to Parquet format, with optimizations for handling extremely large datasets.

## Goals

1. **Parquet Export**: Export reports to `.parquet` format from both UI and command-line
2. **Performance**: Efficient handling of very large reports (millions of rows)
3. **Data Fidelity**: Preserve data types (numbers, dates, lists) rather than converting everything to strings
4. **Integration**: Seamless integration with existing report export workflows

## Implementation

### Phase 1: Core Parquet Export (Completed)

- [x] Add Parquet.Net library dependency
- [x] Rename Parquet.dll to ParquetNet.dll (avoid conflict with existing Parquet.dll)
- [x] Add assembly binding redirect in config
- [x] Create `ParquetRowItemExporter` class for writing Parquet files
- [x] Add "Parquet" as export format option in `ExportLiveReportDlg`
- [x] Support command-line export when filename ends in `.parquet`

### Phase 2: Performance Optimizations (Completed)

- [x] Implement chunked output (10,000 row batches) to manage memory
- [x] Create `BigList<T>` class for lists exceeding ImmutableList capacity
- [x] Implement `RowItemEnumerator` for efficient iteration over big lists
- [x] Parallelize `Pivoter` for faster report generation
- [x] Parallelize Parquet file writing

### Phase 3: Data Type Handling (Completed)

- [x] Implement proper DateTime handling in Parquet export
- [x] Fix column formats when exporting reports
- [x] Support array/repeated fields in Parquet schema
- [x] Handle nullable elements in repeated fields
- [x] Fix type conversion issues

### Phase 4: Entity Optimizations (Completed)

- [x] Remove `Lazy<T>` from Transition, Precursor, and Peptide entities
- [x] Make Protein, Peptide, etc. collections read-only for thread safety
- [x] Create `ResultMap` class for efficient result lookups
- [x] Add `RowItemEnumerator.Take()` method

### Phase 5: Testing (In Progress)

- [x] Create `ParquetRowItemExporterTest` for unit testing
- [x] Create `ExportHugeParquetReportTest` for large-scale testing
- [x] Fix `ConsoleReportExportTest` and `AuditLogTest`
- [ ] Run full test suite
- [ ] Performance benchmarking with large documents

## Key Files Modified

### New Files
- `pwiz_tools/Skyline/Model/Databinding/ParquetRowItemExporter.cs` - Core Parquet export logic
- `pwiz_tools/Shared/CommonUtil/Collections/BigList.cs` - Large list support
- `pwiz_tools/Skyline/Model/Databinding/Collections/ResultMap.cs` - Result lookup optimization
- `pwiz_tools/Skyline/Model/Results/ReplicatePositions.cs` - Replicate position tracking
- `pwiz_tools/Skyline/TestFunctional/ExportHugeParquetReportTest.cs` - Large export test
- `pwiz_tools/Skyline/TestFunctional/ParquetRowItemExporterTest.cs` - Unit tests

### Modified Files
- `pwiz_tools/Skyline/CommandArgs.cs` - Command-line parquet support
- `pwiz_tools/Skyline/CommandLine.cs` - Export logic for parquet
- `pwiz_tools/Skyline/Controls/Databinding/ExportLiveReportDlg.cs` - UI parquet option
- `pwiz_tools/Skyline/Model/Databinding/IRowItemExporter.cs` - Export interface
- `pwiz_tools/Skyline/Model/Databinding/RowItemExporter.cs` - Base exporter
- `pwiz_tools/Skyline/Model/Databinding/RowFactories.cs` - Row creation
- `pwiz_tools/Shared/Common/DataBinding/Internal/Pivoter.cs` - Parallelization
- `pwiz_tools/Shared/Common/DataBinding/RowItemEnumerator.cs` - Iterator support
- `pwiz_tools/Skyline/Model/Databinding/Entities/Peptide.cs` - Remove Lazy
- `pwiz_tools/Skyline/Model/Databinding/Entities/Precursor.cs` - Remove Lazy
- `pwiz_tools/Skyline/Model/Databinding/Entities/Transition.cs` - Remove Lazy
- `pwiz_tools/Skyline/Util/FormattableList.cs` - List formatting

## Technical Details

### Parquet Library
Using `Parquet.Net` (renamed from `Parquet.dll` to `ParquetNet.dll` to avoid naming conflicts).
Upgraded through versions 4.0 and 5.0 during development.

### BigList Implementation
The `BigList<T>` class handles lists larger than the 2^30 element limit of `ImmutableList<T>` by internally using multiple smaller lists. This is necessary for reports with millions of rows.

### Parallelization
- `Pivoter` now processes rows in parallel for pivot operations
- Parquet writing uses parallel compression and encoding
- Thread-safe entity collections enable concurrent access

### Command-Line Usage
```bash
SkylineCmd --in=document.sky --report-name="Transition Results" --report-file=output.parquet
```
The `.parquet` extension automatically selects Parquet format.

## Progress Log

### 2024-12-24 (Initial)
- Started branch from Skyline/work/20251017_ExportOtherReports
- Merged initial parquet export support

### Late December 2024 - Early January 2025
- Added BigList class for handling huge datasets
- Implemented parallel Pivoter
- Parallelized Parquet writing
- Fixed various type conversion and format issues
- Upgraded Parquet library through multiple versions
- Added array/repeated field support

### January 2026
- Created ExportHugeParquetReportTest
- Merged multiple master updates
- Removed ai folder from branch (submodule conversion)

## Remaining Tasks

- [ ] Run full test suite to verify all tests pass
- [ ] Performance benchmarking with large documents
- [ ] Update documentation if needed
- [ ] Create PR for review
- [ ] Address review feedback

## Usage Examples

### Export from UI
1. Open Document Grid (View > Document Grid)
2. Select desired report view
3. File > Export Report
4. Choose "Parquet" format
5. Save as .parquet file

### Export from Command Line
```bash
SkylineCmd --in=document.sky --report-name="Transition Results" --report-file=results.parquet
```

## Related

- `pwiz_tools/Skyline/Model/Databinding/` - Databinding infrastructure
- `pwiz_tools/Shared/Common/DataBinding/` - Shared databinding components
- Original export feature branch: `Skyline/work/20251017_ExportOtherReports`
