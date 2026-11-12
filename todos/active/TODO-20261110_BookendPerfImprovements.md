# TODO-20261110_BookendPerfImprovements.md

## Branch Information
- **Branch**: `Skyline/work/20261110_BookendPerfImprovements`
- **Base**: `master`
- **Created**: 2026-11-10
- **Status**: In Progress
- **Module**: `skyline`
- **PR**: [#5021](https://github.com/ProteoWizard/pwiz/pull/5021)
- **Checkout**: `E:\Users\nicksh\git_e\sky_bookend`

## Objective

Make Bookend (an external Skyline tool, `E:\Users\nicksh\bookend\bookend-dev`) faster at getting chromatograms
out of Skyline-daily, and make Skyline's report export faster wherever Bookend was waiting on it. Bookend asks
Skyline over the JSON tool server for a Parquet report with one row per transition and replicate, holding each
chromatogram's raw times and intensities as float lists.

Test document: `E:\Users\nicksh\bugs\chiyy\20261110_Bookend\hcd-mmcc-subset-diann.sky` (11,859 precursors,
9,830 peptides, 40 replicates). dotTrace snapshots are in `E:\Users\nicksh\bookend\profiles\`. Bookend writes its
log to `%LOCALAPPDATA%\Bookend\logs\last-run.log`.

Nothing is pushed in either repository. Nick pushes himself.

## Skyline commits on the branch (local)

1. `323a5d5739` Fixed ChromDataCache re-reading a precursor's chromatograms for every cell
2. `df3abc6294` Refactored ChromDataCache into one flat cache
3. `796cfd1f94` Fixed GetLocations walking every protein for each peptide (`NodeRef.ListChildrenOfParentNode`)
4. `0fb4175c09` Fixed ChromDataCache missing when report rows are calculated in parallel (keeps 2x ParallelEx
   thread count precursors, FIFO)
5. `75ae21cc02` Fixed Parquet export converting list columns one element at a time; `TimeIntensitiesGroup`
   reads its points under a per-group lock
6. `3b7d4f12c4` Added filtering to Pivoter while expanding report rows: filters are split into root,
   per-sublist-level and pivot filters; the first two are applied during Expand
7. `189c1df294` Added `ReportDefinition.ReportXml` (JSON `report_xml`): a report in .skyr XML, which overrides
   Select, Name, Filter, the pivot settings, Uimode and DataSource. `JsonToolServer.ReadReportXml` requires exactly
   one report in the new format
8. `239dbde26d` Fixed ChromDataCache loading chromatograms while holding its lock (first stored wins)
9. `13fc70cf94` Changed `UtilDB.Uncompress` to `System.IO.Compression.ZLibStream`. Compress still uses DotNetZip,
   so written files are unchanged
10. `124c918ef8` Fixed Parquet export overflowing on row groups of long chromatograms: rows per group capped
    at 50,000 (`MAX_ROWS_PER_GROUP`)
11. `3de0a71424` Added splitting of oversized Parquet chunks into several row groups: no column of a row group
    over 512 MB; one value over 1 GB throws `IOException` (new resource
    `ParquetReportExporter_A_value_in_the_column___0___is_too_large_to_export_to_Parquet_`); packing moved
    from the calculation stage to the writer; `ListColumnBuffer.Pack` counts in a `long`
12. `bb50c13e85` Fixed Parquet export boxing every list element while packing. Had no effect: the typed loop was
    for a Nullable T, but `ListColumnBuffer<T>` is `where T : struct`, so T is never Nullable
13. `f5655ec2de` Fixed Parquet list columns still boxing every element while packing: `T[]` is copied with
    `Array.Copy`, `T?[]` gets a typed loop, and `float[]` lists are no longer converted to `float?[]`
    (`ToNullableArray` removed)
14. `42fe1e229e` Changed the `ReportXml` comment (superseded by 15)
15. `56168463be` Fixed ReportXml dropping the layouts saved with the report: the default layout is used, Sort is
    ignored like every other property, and `AddReportFromDefinition` saves the layouts (`GetReportLayout`)
16. `b3b506d340` Fixed Parquet row group splitting ignoring the lengths of strings in list columns
17. `ffebf3ad69` Changed `ChromatogramGroupInfo.TimeIntensitiesGroup` to lock a private object instead of `this`

## Bookend commits (branch `20261110_PerformanceImprovements`, local)

- `c3986fb` Fixed Skyline-chromatogram input failing on a library without retentionTime
- `ba813ef` Changed selection expansion to call GetLocations once per run
- `d03b81a` Changed the Skyline-daily chromatogram export to unpivoted Parquet (`engine/skyline_rawdata.py`)
- `f89af98` Added a single unfiltered chromatogram report for large selections
- `5e06921` Changed Skyline-daily chromatogram export to always use filtered reports (for measuring)
- `36bd362` Changed the chromatogram export to a Peptide report sent as ReportXml (row source `Peptide`, sublist
  `Precursors!*.Transitions!*.Results!*`, captions kept). Vendored `external/SkylineTool/JsonToolModels.cs` got
  only the `ReportXml` property, not a full re-sync, because upstream has diverged
- `4e9453a` Removed the report planner from the Skyline-daily export: one unfiltered report when every peptide is
  selected, otherwise one report per selected peptide. The older-Skyline CSV path still uses the planner

Package: `pwsh -File build/package-tool.ps1` gives `publish\Bookend-0.8.9.zip`.

## Decisions

- **Report name is `ReportXml`, not `ViewXml`**: users see "Report", not "View".
- **Per-peptide reports for partial selections (Nick, 2026-11-11)**: a report whose rows all share one
  `RowItem.Value` is calculated on one thread, because the Parquet exporter calculates each run of rows sharing a
  Value on one thread. That is accepted: the user knows what they selected. Do not bring back peptide grouping.
- **Row groups**: 50,000 rows at most, and split further by bytes. Parquet.Net encodes each column of a row group
  in one `int`-indexed array, and Parquet page sizes are 32-bit, so a `long` alone cannot fix sizes over 2 GB.

## Measurements

| Profile (`E:\Users\nicksh\bookend\profiles\`) | Mode | Result |
|---|---|---|
| FilterDuringExpand.dtp | Tracing | Filter pushdown worked; report 1 took 514 s, threads waiting on one precursor's `TimeIntensitiesGroup` lock |
| PeptideReport.dtp | Tracing | Lock wait gone, report 1 385 s; ~200 s waiting on the ChromDataCache lock around LoadReplicate |
| NewPeptideReport.dtp | Sampling | 19 reports, 2,033 MB, 133.7 s. Uncompress 141 s of ReadTimeIntensities' 232 s (summed over threads) |
| ZLibStream.dtp | Sampling | 128.4 s. Uncompress 51 s, ReadTimeIntensities 142 s. Stages ran one after another: each report was one chunk |
| RowGroupSplit.dtp | Sampling | 1 whole-document report, 110.5 s. Calculation busy 28 s (~7.4 of 8 workers); writer's parallel loop 97 s, of which `ListColumnBuffer.Pack` 137 s summed (boxing via `Array.GetValue`), `PrepareAsync` 48 s. Writer is the bottleneck: only the two list columns have real work |
| TypedPack.dtp | Sampling | 109.1 s, unchanged: `Pack` 132 s, of which `CastHelpers.Box` 73 s (the typed path never ran). Use a pattern with `System\..*` to see such frames |
| ArrayCopyPack.dtp | Sampling | 55.5 s. `Pack` 12 s. Writer still slightly the bottleneck (calculation waits 23 s); Zstd 28 s of `PrepareAsync`'s 62 s. Nick: fast enough for now |

Use Sampling for timings; Tracing inflates code with many small calls. Reporter command:
`"%LOCALAPPDATA%/JetBrains/Installations/dotTrace263/Reporter.exe" report <dtp> --pattern=pattern.xml --save-to=<xml>`
with patterns `pwiz\..*`, `SkylineTool\..*`, `Parquet\..*`, `System\.Threading\..*`, `System\.IO\.Compression\..*`.
If dotTrace's Timeline controller window disappears, use
`ConsoleProfiler.exe start --profiling-type=Sampling --save-to=<dtp> <exe>`.

The first run of the new Bookend (whole-document report) failed with
`minimumLength ('-364640426') must be a non-negative value`: about 1 million rows per row group made a column of
about 3.9 GB. Commits 10 and 11 fix that.

## Testing

Each change was checked with the Release build and a handful of tests:
TestDocumentGridChromatogramData, TestMixedPolarityFullScan, NistLoadLibrary, TestElibQuantifiableTransitions,
TestEncyclopeDiaLibraryMatch, TestAddLibrary, TestParquetReportInvariant, TestJsonToolServer.
Row group splitting was also run once with the byte limit set to 1 KB, so every chunk was split; the three Parquet
and report tests passed. No test was added. No test is known to export a list column with splitting.

## Remaining

- [ ] Run the whole-document export with the new Bookend and the current Skyline build, and take a Sampling
      profile. Check that calculating and writing overlap, and how busy the PopulateChunk workers are.
- [ ] Pick the next lever from that profile. Last known costs (summed over threads): protobuf
      `ChromatogramGroupData.MergeFrom` 48 s, `ChromatogramCache.CallWithStream` 37 s, `ListColumnBuffer.Pack` 47 s
      own time, `ColumnData.ToNullableArray` 12 s.
- [x] `/code-review medium` (2026-11-11): 10 findings; fixed the ReportXml layouts, string-list byte count and
      `lock (this)` (commits 15-17); dropped the rest (cache size is by design, the others were false or unchanged
      from master).
- [x] Opened PR #5021 (2026-11-11)
- [ ] Push the Bookend branch (Nick's call)
