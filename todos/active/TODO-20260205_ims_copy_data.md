# "Copy Data" for IMS heatmap display in Full Scan view outputs poorly formatted data

## Branch Information
- **Branch**: `Skyline/work/20260205_ims_copy_data`
- **Base**: `master`
- **Created**: 2026-02-05
- **Status**: In Progress
- **GitHub Issue**: [#3953](https://github.com/ProteoWizard/pwiz/issues/3953)
- **PR**: [#3954](https://github.com/ProteoWizard/pwiz/pull/3954)

## Objective

Fix the "Copy Data" feature in Full Scan viewer for IMS data to output properly formatted data that is usable in R or Python.

## Problem

The current output formatting has multiple issues:
- Columns for m/z and 1/K0 (Vs/cm²) are repeated excessively
- Intensity value assignments are unclear
- Not user-friendly for analysis in R or Python

## Requested Improvement

Simplified output format:
- For IMS data: three columns - m/z, 1/K0 (Vs/cm²), and intensity
- For 2D scans: m/z, intensity, and annotation

## Tasks

- [ ] Investigate current Copy Data implementation for Full Scan IMS heatmap
- [ ] Identify why columns are repeated excessively
- [ ] Implement cleaner output format for IMS data
- [ ] Test with IMS data files
- [ ] Verify output is usable in R/Python

## Progress Log

### 2026-02-05 - Session Start

Starting work on this issue. Need to locate the Copy Data implementation for the Full Scan viewer.
