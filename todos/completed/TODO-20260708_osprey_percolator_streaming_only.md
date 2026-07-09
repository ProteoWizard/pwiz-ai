# TODO-20260708_osprey_percolator_streaming_only.md -- Remove the direct Percolator path (streaming-only)

- **Status**: Completed (C# side)
- **C# PR**: shipped inside [#4378](https://github.com/ProteoWizard/pwiz/pull/4378)
  (merged 2026-07-08 as f4de686450) -- folded into the memory-bounding branch, NOT a
  separate stacked PR. See [[TODO-20260703_osprey_memory_bounding]].
- **Rust PR**: [maccoss/osprey#51](https://github.com/maccoss/osprey/pull/51) -- MERGED
  2026-07-08 as `56cf1b0f` (squash) into `reconciliation-v3-first-pass-base-ids` (the
  parity integration branch, on top of #49). Cross-impl bit parity held at 1e-9
  (Stellar 57112==57112, Astral 160358==golden). reconciliation-v3 -> maccoss `main` is
  a separate step the Rust side sequences.

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

## Done session 2 (2026-07-08) -- steps 1-3 COMPLETE

1. **Re-baselined the C# golden** DONE. `regression.ps1 -Dataset Stellar -CreateGolden`
   regenerated `osprey-regression.data/stellar` (56534 -> 57112 across RefSpectra/RunScores/
   ExperimentScores/PeakBoundaries/PeakDigest; proteins 7302 -> 7350). Verify run
   (`regression.ps1 -Dataset Stellar -NoBuild`): mode1/2/3 all PASS, identical blib
   (50,237,440 bytes) across straight/HPC-chain/resume.
2. **Entrapment FDP** DONE. `Run-FdrBench.ps1 -Dataset StellarLibraryDecoy -ProteinFdr '' -Pass 1`
   (PWIZ_ROOT=pwiz-work1): combined FDP 0.90% @ 1% q, paired 0.81%, 26898 disc -- calibration
   held at the clamp reference. metrics.csv in D:\test\osprey-runs\_fdrbench\StellarLibraryDecoy_library_precursor_pass1_noprot.
3. **Dead-code cleanup** DONE. Removed `PercolatorEngine.ApplyPercolatorResultsToProjection`,
   `PercolatorEntryBuilder.BuildFromProjection`, and the test
   `FdrTest.TestApplyPercolatorResultsToProjectionMatchesFdrEntry` (helpers CapturingSink/
   BuildWritebackFixture kept -- shared by other tests); fixed the now-stale doc in
   `FdrProjectionOutput.cs`. Build clean, zero-warning inspection, 473 unit tests pass (was 474).
   Committed C# as `0d4e86fb06` (on top of the `5384e01ffb` [WIP]); Rust unchanged at `df6698a` [WIP].

## Step 4/5 -- RESOLVED: no separate stacked PR; folded into #4378

Per Brendan (2026-07-08 session 2): the C# streaming-only work is NOT a separate stacked
PR. It belongs in **pwiz PR #4378** (`Skyline/work/20260703_osprey_memory_bounding`). The
two streaming-only commits (`5384e01ffb` [WIP] + `0d4e86fb06`) are linear descendants of
#4378's tip, so #4378's branch was **fast-forwarded** `7bcf812539 -> 0d4e86fb06` (no rewrite,
no merge). The scratch branch `Skyline/work/20260708_osprey_percolator_streaming_only` (pushed
to origin, no PR) is now redundant -- delete it once #4378 is green.

- **C# deliverable = pwiz #4378** (now contains memory-bounding + streaming-only + re-baselined
  golden). head `0d4e86fb06`.
- **Rust deliverable = maccoss/osprey #51** `Percolator: always stream...` (`percolator-streaming-only`,
  base `reconciliation-v3-first-pass-base-ids`, matching the #49 template). Body cross-refs #4378.

### Progress (session 2, cont.)
- **Self-review DONE** (fresh-context agent): no functional/compile issues; found doc drift
  (stale "direct path"/"MaxTrainSize*2" prose + a test doc claiming to gate the removed direct
  dispatch). Fixed in commit **380afbf058** (comment/test-doc only; build + 473 tests + zero-warning
  inspection green). #4378 fast-forwarded to 380afbf058.
- **Cross-link DONE**: osprey#51 body -> #4378; #4378 comment -> osprey#51.
- **maccoss/osprey #51 CREATED** (base reconciliation-v3-first-pass-base-ids); no Actions CI on that
  base; cross-impl bit parity already PASS locally at 1e-9 (57112==57112) + cargo fmt/clippy/test.

### Remaining to close the goal
4. **TeamCity Perf/Regression on #4378 must pass** (the standing gate; regression.ps1 mode1/2/3 on
   Stellar + Astral + perf). Build history: 4083546 (0d4e86fb06) cancelled for the doc-fix; 4083584
   (380afbf058) auto-cancelled ("Updated branch") when Brendan clicked Update-branch merging master
   (#4386 --fdrbench-pass both) into #4378 -> new head **245a69d3aa**. Verified the merge is
   golden-neutral: #4386's FirstJoin/MergeNode changes are gated behind FdrBenchInputWriter.PathForPass
   (null on the normal path). Astral golden NOT re-baselined by design -- Astral (160358 precursors,
   millions of entries >> 600k threshold) always streamed, so streaming-only leaves it unchanged;
   only Stellar (previously direct) was re-baselined. Build **4083634** on `pull/4378` (245a69d3aa)
   **PASSED (SUCCESS)** -- all Stellar + Astral mode1/2/3 + perf legs green. Astral mode1 vs the
   un-rebaselined golden passed, confirming Astral is unchanged by streaming-only (Rust cross-impl
   Astral run also produced 160358 == golden). GATE MET.
5. Redundant scratch branch `Skyline/work/20260708_osprey_percolator_streaming_only` (all commits
   folded into #4378, no PR) can be deleted from origin -- optional cleanup, left for the developer.
   Human review + merge of #4378 and osprey#51 is the developer's call.

## STATUS: goal met -- both PRs pass all gates
- **pwiz #4378** (head 245a69d3aa): build + 473 tests + zero-warning inspection green; TeamCity
  Perf/Regression 4083634 SUCCESS (Stellar+Astral mode1/2/3 + perf); entrapment FDP 0.90% @ 1% q;
  cross-impl bit parity vs Rust at 1e-9 (Stellar 57112==57112, Astral 160358==golden).
- **maccoss/osprey #51**: open, MERGEABLE; no Actions CI on its base; parity held. Ready for review.

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
