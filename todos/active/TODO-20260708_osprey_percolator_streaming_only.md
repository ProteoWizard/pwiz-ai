# TODO-20260708_osprey_percolator_streaming_only.md -- Remove the direct Percolator path (streaming-only)

## Branch Information

- **C#**: `Skyline/work/20260708_osprey_percolator_streaming_only` in `C:\proj\pwiz-work1`
  (stacked on #4378 `Skyline/work/20260703_osprey_memory_bounding`; needs the projection
  streaming infrastructure #4378 added). WIP commit `5384e01ffb`.
- **Rust**: `percolator-streaming-only` in `C:\proj\osprey`, branched off the parity base
  `reconciliation-v3-first-pass-base-ids` (@ `0cfe78c`, the #49 clamp). WIP commit `df6698a`.
- **Matched pair** (cross-impl parity gate): C# PR + maccoss/osprey PR, modeled on the
  pwiz#4390 <-> osprey#49 template. Neither PR opened yet.

## Objective

Make Osprey's Percolator **always stream** -- remove the direct/small-experiment path in
BOTH implementations. Mike: there is no reason to ever NOT stream (faster; drops a modest
experiment from >120 GB to ~30 GB); the direct path existed only to preserve full-CV
scoring for small libraries and to match Rust. It is a **parity-affecting** change: the
streaming path trains the SVM on the best-per-precursor subsample, not all entries, so the
Stellar training set (and every downstream q-value) shifts -- Stellar output re-baselines,
and BOTH tools must switch together or cross-impl parity breaks.

## Done this session (2026-07-08)

- **Rust** (`df6698a`): removed the `use_streaming` dispatch + `run_percolator_fdr_direct`
  in `crates/osprey/src/pipeline.rs`; always take the streaming path. `cargo fmt` /
  `clippy -D warnings` / `cargo test` all pass. Binary rebuilt.
- **C#** (`5384e01ffb`, WIP): `PercolatorEngine` -- the projection overload dispatch AND
  `DispatchSvm` now always call the streaming path; removed the dead `PopulateFeaturesFromFiles`.
  Debug build + 474 unit tests pass.
- **Cross-impl parity, Stellar: PASS at 1e-9.** `Compare-EndToEnd-Crossimpl` (with
  `PWIZ_ROOT=C:\proj\pwiz-work1`) -- precursors 57112 == 57112 (moved from the direct-path
  56534, confirming BOTH switched), Stage-7 protein FDR match, blib content match. This was
  the make-or-break: the streaming path had never been cross-checked on Stellar (Stellar
  always went direct) and it agrees bit-for-bit.

## Remaining (in order)

1. **Re-baseline the C# regression golden** `pwiz_tools/Osprey/osprey-regression.data` to the
   streaming-only output (mode1 now differs; safe to re-baseline since parity confirms the new
   output matches Rust). Then `regression.ps1 -Dataset Stellar` mode1/2/3 must PASS.
2. **Entrapment FDP re-check**: `Run-FdrBench.ps1 -Dataset StellarLibraryDecoy -ProteinFdr '' -Pass 1`
   -- confirm calibration still ~0.90% combined @ 1% q (the clamp reference).
3. **Dead-code cleanup** (dead once the direct path is gone): remove
   `PercolatorEngine.ApplyPercolatorResultsToProjection` and its test
   `FdrTest.TestApplyPercolatorResultsToProjectionMatchesFdrEntry`, and the now-unused public
   `PercolatorEntryBuilder.BuildFromProjection`. Re-run build + `-RunInspection` (zero-warning).
4. **Finalize + open the matched pair**: drop the `[WIP]` commits (amend/replace with final
   messages), push both, open the C# PR (stacked on #4378) and the maccoss/osprey PR, each
   body cross-referencing the other.
5. **Astral**: trigger `ProteoWizardOspreyWindowsNetPerfRegressionTests` on the streaming-only
   PR (its own run; the #4378 Astral does not cover it).

## Key context / gotchas

- **PWIZ_ROOT footgun**: `Compare-EndToEnd-Crossimpl.ps1` resolves the C# exe from
  `Get-PwizRoot` = `C:\proj\pwiz` (master) unless `$env:PWIZ_ROOT` is set. Validating a
  `pwiz-work1` branch REQUIRES `PWIZ_ROOT=C:\proj\pwiz-work1`, else it silently runs the
  primary checkout's exe. The first streaming-only parity run FAILED for exactly this reason
  (master-C# direct 56534 vs Rust streaming 57112); the corrected run PASSED. Worth adding to
  `ai/scripts/Osprey/Compare/README.md`.
- **Parity is a standing gate** -- every substantive change is a matched C#+Rust pair
  (see `ai/docs/osprey-development-guide.md`, "The parity gate is a STANDING requirement").
- **Parent #4378** is pushed (origin `7bcf812539`) with the #4390 experiment-q clamp integrated
  the memory-bounded way (flat `ClampExperimentQToBestRunFlat`); its Astral gate (TeamCity build
  `4083292`) was triggered this session. Streaming-only stacks on it.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260708_osprey_percolator_streaming_only.md` before starting work.
