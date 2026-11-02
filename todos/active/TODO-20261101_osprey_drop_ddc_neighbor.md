# TODO-20261101_osprey_drop_ddc_neighbor.md

## Branch Information
- **Branch**: `Skyline/work/20261101_osprey_drop_ddc_neighbor`
- **Base**: `master`
- **Created**: 2026-11-01
- **Status**: In Progress
- **GitHub Issue**: [#4709](https://github.com/ProteoWizard/pwiz/issues/4709)
- **Module**: `osprey`
- **PR**: (pending)

## Objective

Remove the training export's `ddc_neighbor_n` column (~0 by construction, nothing reads it), its
three `osprey.ddc.*` footer keys, the per-run MS2 RT sort that fed it, and the plumbing that made
Stage 4 dedup internals public.

## Change

- TrainingExportWriter: no dedup tolerance, no RT neighborhood (the per-run sort of every MS2 RT),
  no per-window neighbor list, no `DdcNeighborCount`, no `osprey.ddc.*` keys.
- `TrainingEvidence.CountDoubleCountingNeighbors` removed.
- `ScoringPipeline.DoubleCountingRtNeighborhood`, `CompareDoubleCountingOrder` and
  `SharesDoubleCountingFragments` back to private. `DoubleCountingTolerance` stays public:
  `ScoringTest.AssertDoubleCountingToleranceIsTheSearchTolerance` pins it.
- CarafeSharp.Contracts (the shared export schema): the column, `TrainingRecord.DdcNeighborCount`
  and the three key constants removed. CarafeSharp itself never read any of them (grep:
  only the contract's own definitions).
- Format version 2 -> 3, following the precedent of the v1 -> v2 column drop; formats 1, 2 and 3
  all read (a column the schema no longer names is skipped). CarafeSharp's "refuses an unknown
  version" test now uses FORMAT_VERSION + 1 instead of a literal 3, and a format-2 file with
  the old column is shown to read.
- Docs: 22-training-export.md (column row, footer row, explanatory paragraph, version note),
  14-intermediate-files.md (format version).

## Decision Brendan might revisit

- The version bump. Without it an older build's reader would refuse a new file for the missing
  column with a "has no ddc_neighbor_n column" message; with it, with a clear version message.
  It also changes the training export's validity input (PerFileRescoreTask keys on
  FORMAT_VERSION), so existing exports are rewritten on the next run that asks for them.

## Tasks

- [x] Code, contract, tests, docs
- [x] Build-Osprey -RunTests -RunInspection: 646/646, inspection 0 warnings
- [x] Build-CarafeSharp -RunTests: 108 passed, 8 skipped for absent Carafe test data (none
      failed). Its inspection reports one PRE-EXISTING warning in an untouched file
      (`CarafeSharp.Models\PeptdeepConstants.cs:25` RedundantUsingDirective), also on master
- [x] regression.ps1 -Dataset Stellar: PASSED (no leg runs --training-export; the subset tests
      SubsetPipelineTest.TrainingExport and TrainingExportWriterTest cover it)
- [x] Review (independent agent; `/code-review` is blocked from this agent's pinned cwd): no
      defects; no remaining reader of the column, keys or property under pwiz_tools; the bump is
      read in one place; Stage 4 dedup unchanged (visibility only). The int[] column in the new
      CarafeSharp case was the one open question - the test passed, so Rewrite writes it
- [ ] PR

## Progress Log

### 2026-11-01
- Implemented. Commit 36be271fe1.
