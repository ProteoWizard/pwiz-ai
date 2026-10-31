# TODO-20261030_import_search_blib.md

## Branch Information
- **Branch**: `Skyline/work/20261030_import_search_blib`
- **Base**: `master`
- **Created**: 2026-10-30
- **Status**: In Progress
- **Module**: `skyline`
- **Worktree**: `D:\Users\brendanx\proj\pwiz-blib`

## Objective

Found while building Skyline review documents for DIA-NN vs Osprey peaks (TODO-20261030_osprey_scoring_library).

1. `--import-search-file=<one .blib>` uses the library as is, like "Use existing" in the Import Peptide Search
   wizard, instead of rewriting it through BlibBuild/BlibFilter (which kept 56,839 of 169,612 RetentionTimes rows of an
   Osprey .blib).
2. `--import-fasta` treats a file whose first line starts with `>>` as peptide lists, like File > Import > FASTA.
   Before, each `>>` header became a custom-named protein (concatenated peptides, re-digested) saved as
   `<protein label_name=...>` without the schema-required `name`.
3. `--add-library-path` (and an existing search library) records the library in the Spectral Library list, as Edit
   Library does, so a library outside the document folder is found again when the document is reopened.
4. Fixed the out-of-date Parquet comment in BiblioSpec `DiaNNSpecLibReader.cs`.

## Done
- [x] All four above; `--import-fasta` and `--import-search-file` help text updated (English resx only)
- [x] ConsoleImportPeptideSearchTest extended; CommandLineTest + CommandLineImportTest 52/52 pass
- [x] Proved on the SEA-AD review: review4\osprey.sky validates against the schema (review3: 5 errors), 741/741
      precursor-runs match the library's per-run boundaries (was 35%), reopens with no missing-library warning

## Remaining
- [ ] BlibBuild/BlibFilter: carry a non-redundant input's RetentionTimes rows, LibMetadata and DecoyPairs through a
      build (see the agent report in ai/.tmp/agent-blibrt-status.md). Needs a decision on how a redundant library is
      recognized (`BiblioSpecLite.IsRedundantLibrary` keys on the RetentionTimes table being absent).
- [ ] A `>>` header in the middle of a FASTA still writes `<protein>` without `name` (schema says required)
- [ ] /code-review medium, then PR

## Related
- pwiz #4948 (skyline, tech-debt): linked files are not found at their saved path on open, and spectral libraries
  save no path. Item 3 above (the Spectral Library list entry) is a stopgap until that is fixed.
