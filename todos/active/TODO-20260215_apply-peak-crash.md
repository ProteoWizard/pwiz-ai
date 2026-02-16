# "Apply Peak to All" crashes when some replicates lack chromatogram data

## Branch Information
- **Branch**: `Skyline/work/20260215_apply-peak-crash`
- **Base**: `master`
- **Created**: 2026-02-15
- **Status**: In Progress
- **GitHub Issue**: [#3983](https://github.com/ProteoWizard/pwiz/issues/3983)
- **PR**: (pending)
- **Exception Fingerprint**: (from exception report #73976)
- **Exception ID**: 73976

## Objective

Fix crash in "Apply Peak to All" when some replicates don't have chromatogram data at the target retention time. 30 reports from 21 users since June 2025.

## Tasks

- [ ] Wrap `doc.ChangePeak()` in `PeakMatch.ChangePeak` with try-catch for `ArgumentOutOfRangeException`
- [ ] On catch, return `doc` unchanged (skip replicates without matching data)
- [ ] Leave throws in `TransitionGroupDocNode.ChangePeak` and `SrmDocument.ChangePeak` as-is

## Progress Log

### 2026-02-15 - Session Start

Starting work on this issue...
