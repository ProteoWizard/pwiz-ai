# Remove --write-pin and its .cs_features.tsv dump

## Branch Information
- **Branch**: `Skyline/work/20261017_osprey_remove_write_pin` (local, from origin/master `23e870a9b7`, not pushed)
- **Base**: `master`
- **Created**: 2026-10-17
- **Status**: Implemented and committed locally; unit 637/637 + inspection 0. Not pushed, no PR.
- **GitHub Issue**: (none)
- **Module**: `osprey`
- **PR**: (none yet)
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
- [ ] `regression.ps1 -Dataset Stellar` in the worktree (outputs unchanged by construction - non-default flag)
- [ ] At merge, apply `ai/.tmp/sessions/20261016-b2pr/patch_ai_write_pin.py C:/proj/ai`: drops
      `Run-Osprey.ps1 -WritePin`; rewrites the DIAGNOSTICS.md feature-parity recipe onto
      `Compare/parquet_diff.py` over the Stage 4 `.scores.parquet` (Rust `-ExitAfterScoring`).
      Not before: current master still accepts the flag.
- [ ] Optional: add a Stage 4 `.scores.parquet` boundary to `Compare-EndToEnd-Bisect-Crossimpl.ps1`
      (its "rewritten in place at Stage 6" note is stale for C#, which writes `.scores-reconciled.parquet`;
      check whether Rust still rewrites in place).
- [ ] Ask Brendan before push / PR.

## Progress Log

### 2026-10-17 - Implemented
- Gates: `sessions/20261016-b2pr/writepin-run1.log` (inspection 0; only the self-updating help test red),
  `writepin-run2.log` (637/637).
