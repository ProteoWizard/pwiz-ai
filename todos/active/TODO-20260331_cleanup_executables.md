# Clean up Executables folder: remove obsolete projects, move dev tools to DevTools

## Branch Information
- **Branch**: `Skyline/work/20260331_cleanup_executables`
- **Base**: `master`
- **Created**: 2026-03-31
- **Status**: In Progress
- **GitHub Issue**: [#4124](https://github.com/ProteoWizard/pwiz/issues/4124)
- **PR**: (pending)

## Objective

Clean up `pwiz_tools/Skyline/Executables` by removing obsolete projects, moving developer tools to the `DevTools` subfolder, and adding README.md files to document each remaining project.

## Tasks

### Remove (7 projects)
- [ ] KeepResx — superseded by DevTools/ResourcesOrganizer
- [ ] KeepResxW — superseded by DevTools/ResourcesOrganizer
- [ ] PwizConvert — created 2009 for a long-resolved problem; no references in Skyline code
- [ ] LocalizationHelper — old ReSharper inspectcode helper, no longer needed
- [ ] MultiLoad — superseded by ImportPerf
- [ ] SkylinePeptideColorGenerator — POC that became Model/ColorGenerator.cs
- [ ] JavaSkylineAlgorithms — empty stub project

### Move to DevTools (7 projects)
- [ ] AssortResources — **high risk**: deep integration with CodeInspectionTest, Jamfile, DotSettings
- [ ] SortRESX
- [ ] UniModCompiler
- [ ] ParseIsotopeAbundancesFromNIST
- [ ] IPItoUniprotMapCompiler
- [ ] ImportPerf
- [ ] PeakComparison

### Add README.md files
- [ ] All projects moved to DevTools
- [ ] Existing DevTools projects lacking READMEs
- [ ] Remaining Executables projects lacking READMEs

## Progress Log

### 2026-03-31 - Session Start

Starting work on this issue. Branch created, TODO created.
