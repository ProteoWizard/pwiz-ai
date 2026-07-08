# TODO: Osprey --fdrbench-pass both — emit pass-1 and pass-2 FDRBench pools in one run

## Branch Information
- **Branch**: `Skyline/work/20260707_osprey_fdrbench_pass_both`
- **Base**: `master` (`31168db37b`, the #4380 partial-entrapment merge)
- **Created**: 2026-07-07
- **Status**: PR open, awaiting self-review + CI
- **PR**: [#4386](https://github.com/ProteoWizard/pwiz/pull/4386)
- **Worktree**: `C:\proj\pwiz-libdecoy`

**Priority**: Small enabler — salvaged from the decommissioned
  `20260630_osprey_libdecoy_reconciliation_baseid` branch (its other content is already
  upstream). This is the one genuinely-new, un-upstreamed piece.
**Requested by**: Brendan

## Why this exists
The pass-2 FDR-recalibration assessment ([[project_osprey_pass2_recalibration_inflates_fdr]],
[[project_osprey_pass2_gate_divergence]]) needs the pre-compaction first-pass pool (pass 1)
and the reported post-compaction pool (pass 2) on the **same axes** from a **single run**, so
the entrapment oracle can plot both FDP curves without two separate invocations. Before this,
`--fdrbench-pass` accepted only `1` or `2` (mutually exclusive per run).

## Scope
- `Osprey.Core/OspreyConfig.cs` — `FdrBenchPass` becomes a bitmask; `FDRBENCH_PASS_1` /
  `FDRBENCH_PASS_2` constants; default stays `FDRBENCH_PASS_2`.
- `Osprey/OspreyCommandArgs.cs` — accept `both` / `1,2`; `ParseFdrBenchPass` returns the mask;
  help text.
- `Osprey.Tasks/FdrBenchInputWriter.cs` — new `PathForPass(config, pass)`: returns the output
  path for a requested pass (or null), suffixing `.pass1` / `.pass2` when both are requested so
  they do not overwrite.
- `Osprey.Tasks/FirstJoinTask.cs` — pass-1 writer gated via `PathForPass(FDRBENCH_PASS_1)`.
- `Osprey.Tasks/MergeNodeTask.cs` — pass-2 writer gated via `PathForPass(FDRBENCH_PASS_2)`;
  the pairing-manifest path also threads `benchPath` so `both` mode suffixes both files.
- `Osprey.Test/OspreyCommandArgsTests.cs` — parse tests for `1`, `2`, `both`, `1,2`.
- `Documentation/Help/en/CommandLine.html` — regenerated help row.

## Test plan
- [x] `OspreyCommandArgsTests` — `--fdrbench-pass` parses `1` / `2` / `both` / `1,2`; invalid throws.
- [x] Osprey.sln builds clean (net472 + net8.0, 0 warnings).
- [ ] Manual: one run with `--fdrbench <p> --fdrbench-pass both` writes `<p>.pass1(.pairing).tsv`
  and `<p>.pass2(.pairing).tsv`.

## Notes
- The sibling instrument `OSPREY_BOOST_TARGET_DISCRIMINANT` (target-distribution-drift what-if)
  was **deliberately excluded** from this PR and stashed for later under
  [[TODO-osprey_model_diagnostics_null_alignment_decoy_qc]] (it is a null-alignment QC test
  mechanism, not FDRBench plumbing).
