# Remove --write-pin and its .cs_features.tsv dump

## Branch Information
- **Branch**: `Skyline/work/20261017_osprey_remove_write_pin` (rebased onto master `e89d533739`, pushed)
- **Base**: `master`
- **Created**: 2026-10-17
- **Status**: Completed
- **GitHub Issue**: (none)
- **Module**: `osprey`
- **PR**: [#4864](https://github.com/ProteoWizard/pwiz/pull/4864) (merged 2026-10-18 as `aef1494771`)
- **Checkout**: `C:\proj\pwiz-writepin` (worktree of `C:\proj\pwiz`)

## Objective

Split out of TODO-20261015_osprey_firstpassfdr_slimming (decided with Brendan 2026-10-17). `--write-pin`
wrote `<stem>.cs_features.tsv` beside the INPUT mzML (the shared data folder): one row per scored
candidate with SpecId, label, scan, charge, the 21 PIN features and the peptide - every column already
in `.scores.parquet` - sorted and LF-formatted for diffing against Rust's PIN output. Not a valid
Percolator PIN (no Proteins column), not a declared output, in the "Decoys" argument group. Rust is a
reference only; C# does not carry output whose purpose is Rust integration.

## Done
- [x] Removed the argument, `OspreyConfig.WritePin`, `_write_pin` usage resource (en/ja/zh-Hans +
      Designer), `PerFileScoringTask.WriteFeatureDump`, the `WritePin ||` term on the cal-sample dump
      (still reachable via `OSPREY_DUMP_CAL_SAMPLE`), doc rows in 00/01/04/07/14/20, test uses;
      CommandLine.html regenerated (en/ja/zh-Hans) by its self-updating test.

## Remaining
- [x] `regression.ps1 -Dataset Stellar` in the worktree: PASS, data dir unchanged
      (`sessions/20261016-b2pr/writepin-regression-stellar.log`)
- [x] At merge, the ai/ follow-through (applied by hand 2026-10-18; the patch script had been
      cleaned out of `ai/.tmp`): `Run-Osprey.ps1 -WritePin` dropped; the DIAGNOSTICS.md
      feature-parity recipe rewritten onto `Compare/parquet_diff.py` over the Stage 4
      `.scores.parquet` from two `-ExitAfterScoring` runs.
- [ ] Optional: add a Stage 4 `.scores.parquet` boundary to `Compare-EndToEnd-Bisect-Crossimpl.ps1`
      (its "rewritten in place at Stage 6" note is stale for C#, which writes `.scores-reconciled.parquet`;
      check whether Rust still rewrites in place).
- [x] Push / PR / TeamCity (Brendan approved 2026-10-17).

## Progress Log

### 2026-10-17 - Implemented
- Gates: `sessions/20261016-b2pr/writepin-run1.log` (inspection 0; only the self-updating help test red),
  `writepin-run2.log` (637/637).

### 2026-10-18 - Merged

PR #4864 merged as commit aef1494771 (squash; every check green, Copilot refused on quota, no review
threads). Shipped: `--write-pin` and the `.cs_features.tsv` dump removed, the usage resource and doc
rows gone, CommandLine.html regenerated. The ai/ follow-through landed in the same pwiz-ai commit as
this entry (`Run-Osprey.ps1 -WritePin` dropped, DIAGNOSTICS.md recipe on `parquet_diff.py`).
Deferred: the optional Stage 4 `.scores.parquet` boundary in `Compare-EndToEnd-Bisect-Crossimpl.ps1`
(and the check whether Rust still rewrites its parquet in place at Stage 6) was not done; it belongs
with the next cross-impl bisect that needs it. The `C:\proj\pwiz-writepin` worktree was already gone.
