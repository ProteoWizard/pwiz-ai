# TODO: Lean the resident FDR entry + full-entry reloads (Osprey memory, next levers)

**Created:** 2026-07-08  **Requested by:** Mike
**Goal:** 100s of files in 64 GB (Rust parity) minimum; stretch under 32 GB. OK to land
100s-in-64 GB first.
**Gated:** do NOT start until the 82-file Astral fit test + the #4387/#4388 console PR are
done. Each phase = its own `Skyline/work/...` branch/PR. **Byte-parity is the hard gate.**
**Follows:** #4378 (scoring/join + FDR streaming), #4381 (library), #4376 (reconciliation).

## Why (measured on the 82-file all-three run, 2026-07-08)

Everything else is bounded; the ceiling is now the **resident `FdrEntry` stub buffer at
first-pass FDR**: `[MEM Stage 5 start] managed_heap 53.13 GB` = 191.2M entries × ~280 B. The
`FdrEntry` class (`Osprey.Core/FdrEntry.cs:33`) carries a 16 B header + 7 heap pointers (6
nullable arrays that are **null** on stubs + a per-entry `string`) to hold ~11 scalar columns.
Rust's `FdrEntry` is a ~128 B value struct (`osprey-core/src/types.rs:1024`), heavy data
streamed from parquet. Secondary: `LoadFullFdrEntries` (`ParquetScoreCache.cs:845`) reinflates
~940 B entries (~22 GB @ 24M) for the reconciled-parquet rewrite + blib, when the blib path
only needs RT/bounds and Rust uses a 5-col `BlibPlanEntry` (`pipeline.rs:6814`).

**Leverage:** the lean `FdrProjection` 32 B struct already exists (`Osprey.Core/FdrProjection.cs:59`,
used by the default-on `RunFirstPassProjection`) — but it's built *after* the fat stubs load,
so the peak is unchanged. Move the lean representation to **load time**.

## Phase 1 — lean stub struct at load (53 → ~14 GB; the primary win)

- Extend `FdrProjection` (or sibling `FdrStub`) with `ScanNumber, ApexRt, StartRt, EndRt,
  BoundsArea` → ~72 B/row.
- `ParquetScoreCache.LoadFdrStubsFromParquet:723` populates the lean struct array directly —
  never allocate `FdrEntry` for the resident buffer (already reads only ~11 columns).
- Thread through `FirstJoinTask` (buffer, `CompactFirstPass:636`, `ReloadFirstPassSurvivors:1631`)
  and `PercolatorFdr.ScorePopulationAndComputeFdr` (features already stream by `parquet_index`;
  q-values write back to the struct array). Fat `FdrEntry` stays only for transient scoring /
  reconciliation write-back.
- → ~72 B × entries: 100s of files fit 64 GB (Rust parity).

## Phase 2 — BlibPlanEntry projection for the full-entry reloads (~22 GB)

- Add a lean `BlibPlanEntry` struct + 5-col projection loader `LoadBlibPlanEntries` (entry_id,
  RT bounds, bounds_area, run/experiment q-values, file idx, interned modseq) — mirror Rust
  `load_blib_plan_entries`.
- Repoint the blib path (`MergeNodeTask.cs:317` → `BlibOutputWriter`,
  `BlibOutputWriter.cs:209-250`) and `PerFileRescoreTask.OverlayReconciledIntoBuffer:1217` off
  `LoadFullFdrEntries`.
- `ReconciledParquetWriter.Write:64`: stream untouched parquet rows column-wise (copy-through);
  only re-scored rows (`Features != null`) need the full object.

## Phase 3 — stretch to 32 GB (scope after Phases 1-2 measure)

At ~72 B/entry the buffer still scales 1:1 with entry count. If needed: **segment** the
first-pass target-decoy competition so not all files' stubs are resident at once, or pack
q-values to f32 where parity allows. Decide with real numbers — no code until 1-2 land.

## Gates (per phase)
- `regression.ps1 -Dataset Stellar` (mode1/2/3, 1e-9) → `-Dataset All` before merge; cross-impl
  `Compare-EndToEnd-Crossimpl` on Stellar + Astral (touches the core FDR type + q-value write-back).
- 82-file Astral fit test, `OSPREY_LOG_MEMORY=1`: confirm `[MEM Stage 5 start]` 53 → ~14 GB
  (Phase 1) and the reconciliation/blib reload −~22 GB (Phase 2); then push to 150-300 files.
- `Test-PerfGate.ps1 -Dataset Stellar` (struct-array + extra projections must not regress speed).
