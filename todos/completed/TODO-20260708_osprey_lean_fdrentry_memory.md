# TODO: Osprey memory — lean the Stage-5 FDR stub buffer and the dense XCorr spectrum cache

**Created:** 2026-07-08  **Requested by:** Mike
**Issues:** #4397 (Lever 1, Stage-5 fat stubs) · #4398 (Lever 2, dense XCorr spectrum cache)
**Goal:** 100s of files in 64 GB (Rust parity) minimum; stretch under 32 GB.
**Follows:** #4378 (scoring/join bounding + default-on FDR streaming), #4381 (library),
#4376/PR #4394 (reconciliation drop). **Byte-parity is the hard gate on every phase.**

**Status:** COMPLETED 2026-07-10 — both levers shipped. Lever 1 (#4397) MERGED as PR #4400
(`c9526f0e6`, 2026-07-09); Lever 2 (#4398, dense XCorr spectrum cache) MERGED as PR #4409
(`0a8a7676a`, 2026-07-10). Issues #4397 and #4398 both closed-completed. See Resolution at end.

## Where the memory actually goes (measured, 82-file Astral, 2026-07-08)

Run completed in 8 h 28 m on a 64 GB box, peak WS **55.61 GB** (`peak_paged` 77.47 GB), blib
385,818,624 B. 191,227,519 scored entries, 2,322,560 distinct peptides.

| Stage | Anchor | Measured |
|---|---|---|
| Library resident (#4381) | `[MEM library-resident]` | 3.20 GB |
| **Per-file scoring** | `[MEM scored file N/82]` | **47.83 GB WS peak / ~26 GB managed, FLAT** (already ~26.33 GB at file 1) |
| **Stage 5 stub load** | `[MEM Stage 5 start]` | **53.13 GB managed** (191.2 M fat `FdrEntry`) |
| Stage 5 projection build | `[MEM projection built]` | 59.06 GB managed — see correction below |
| After 1st-pass Percolator | — | 26.57 GB |
| Reconciliation floor / resident (#4376) | `[MEM reconciliation-*]` | 8.40 GB / **11.78 GB**, flat |

### Correction: the 59.06 GB is NOT live coexistence

`FdrProjectionSet.BuildFromEntries(..., releaseStubs: true)` already releases each file's stubs
as its projection rows are built (`FirstJoinTask.cs:1355`, `FdrProjection.cs:220`). The probe
reads total managed heap (`GC.GetTotalMemory(false)`), so 59.06 GB = live projection (~6 GB) +
**not-yet-collected stub garbage**. The real live peak is the **53.13 GB fat stub buffer**.

---

## Lever 1 — Stage-5: stop rematerializing 191 M fat `FdrEntry` stubs

**Root cause:** `PerFileScoringTask.cs:334-346`. After scoring releases its transients, it loops
every file and calls `ParquetScoreCache.LoadFdrStubsFromParquet` to **rematerialize all 191 M
`FdrEntry` objects** (~280 B each: 16 B header + 15 doubles + 7 heap pointers, arrays null),
publishing them as `ScoredEntries`. `FirstJoinTask.cs:1361` then immediately converts them into
32 B `FdrProjection` rows and drops them. **We allocate 53 GB of objects to produce ~6 GB of structs.**

**Consumers (checked):** on the straight-through path `ScoredEntries` has exactly **one**
consumer — `FirstJoinTask`. `PerFileRescoreTask.cs:411` reads it only on the HPC **merge** path
(after an early return; its own comment: *"the merge path must NOT materialize FirstJoin"*).
`needsResidentFirstPassPool` (`FirstJoinTask.cs:258`) still wants fat stubs for
`--model-diagnostics` / FDRBench-pass-1.

**Fix:** load the lean projection **directly from parquet**; never allocate `FdrEntry`.
Byte-parity crux: `BuildFromEntries` assigns `PeptideId` as the **global Ordinal rank** of the
modified sequence across ALL files, so a streaming loader must assign insertion-order ids and
**remap** them to the ordinal rank at the end (remap table ≈ 9 MB at 2.3 M peptides).

**Expected: 53.13 GB → ~6 GB** (191 M × 32 B), and the garbage spike goes with it.

**Status: MERGED 2026-07-09 as PR #4400** (`c9526f0e`, squash; Fixes #4397). Branch was
`Skyline/work/20260708_osprey_lean_fdr_stub` (rebased off #4378 onto master before merge):
- `FdrProjectionSet.Builder` (`Osprey.FDR/FdrProjection.cs`) — streaming rows + insertion-order
  ids + ordinal remap in `Build()`.
- `ParquetScoreCache.ReadFdrStubScalars` (`Osprey.IO`) — reads the 5 needed columns
  (entry_id, charge, is_decoy, coelution_sum, modified_sequence), allocates no `FdrEntry`.
  Callback-based because **Osprey.IO must not depend on Osprey.FDR** (IO → Core only).
- `TestFdrProjectionBuilderMatchesBuildFromEntries` — pins element-for-element parity.
- Build + 474 tests green.

**Shipped in #4400:** wired `PerFileScoringTask` (publishes the lean `FdrProjections` byproduct)
+ `FirstJoinTask` (consumes it, skips `BuildFromEntries`); fat-stub loads stay on
model-diagnostics / FDRBench pass 1 / SecondPassFDR + the merge/rehydrate path. Gates green:
build + 473 tests, `regression.ps1 -Dataset Stellar` mode1/2/3 byte-identical, `Test-PerfGate`
PASS (+0.1% total), and the TeamCity Perf/Regression (Stellar+Astral) on `pull/4400`. Copilot
review added a defensive `ExpectReconciledInput` term to the lean gate (byte-neutral; that mode
is Rehydrate-routed). **Deferred: the at-scale 82-file Astral `OSPREY_LOG_MEMORY` measurement to
confirm 53 → ~6 GB** (correctness is proven; this is the memory-payoff number).

### Wiring design (the structural fact that makes this safe)

`ctx.Publish(new ScoredEntries(_perFileEntries))` (`PerFileScoringTask.cs:559`) sits in a **shared
Run/Rehydrate tail**, but the fat-stub loop (`:334-346`) is in **`Run`** (fresh scoring) only; the
merge/resume path fills `_perFileEntries` via a **separate `Rehydrate`** method (`:446+`,
`TryLoadStubsAndCalibration`). So:

1. **`Run` path**: replace the fat-stub loop with `FdrProjectionSet.Builder` +
   `ParquetScoreCache.ReadFdrStubScalars` per file; publish a new lean `FdrProjections` byproduct.
   Leave `_perFileEntries` empty (`ScoredEntries` still publishes, just empty). `totalScored` must
   come from `FdrProjectionSet.TotalRows` instead of summing `perFileEntries`.
2. **`Rehydrate` path**: unchanged — merge/resume keeps its fat stubs, so
   `PerFileRescoreTask.cs:411` is unaffected.
3. **`FirstJoinTask`**: consume `FdrProjections` directly (skip `BuildFromEntries`). When
   `needsResidentFirstPassPool` (`:258`, `--model-diagnostics` / FDRBench-pass-1), lazily load fat
   stubs from `PerFileParquetPaths` via the existing `LoadFdrStubsFromParquet`.

This keeps the fat buffer alive exactly where it is genuinely required and nowhere else.

---

## Lever 2 — Scoring: the dense preprocessed XCorr **observed-spectrum** cache (~18-37 GB)

**Root cause:** `HramStrategy.PreprocessWindowSpectra` (`Osprey.Scoring/ResolutionStrategy.cs:165-183`)
rents one **`float[NBins]`** per spectrum per window — `NBins = 2000/0.02 = 100,001` →
**391 KB each, on the LOH** — held for the whole window's candidate loop, from an
`XcorrScratchPool` `ConcurrentBag` that **never shrinks** (`XcorrScratchPool.cs:63-64,128-135`).
Astral: ~163 k MS2 / ~80 windows ≈ **2,000 spectra/window** → ~780 MB per active window;
`Parallel.For` runs `NThreads` windows concurrently (`ScoringPipeline.cs:269-271`) → **~18-37 GB**.
Present from file 1, flat across files (per-file transient, but the LOH high-water stays committed).

### What Brendan's sparse XCorr did — and did NOT do

`SpectralScorer.XcorrFromPreprocessed(float[] preprocessed, LibraryEntry, bool[] visitedBins)`
already iterates the ~10-30 **library fragments** and indexes into the preprocessed spectrum,
instead of materializing an `NBins` **theoretical** vector for a dense dot product. Brendan wrote
this in C# and ported it to Rust as `SpectralScorer::xcorr_sparse` (`osprey-scoring/src/lib.rs:2442`,
gated by `OSPREY_XCORR_SPARSE=1`); the Rust doc states it matches the C# sum order bit-for-bit.

**That sparsity is on the theoretical side.** Both implementations still hold the **observed**
spectrum as a dense `float[NBins]` (`xcorr_sparse(&self, spectrum_preprocessed: &[f32], ...)`).
The ~18-37 GB is untouched by it.

### The observed spectrum cannot be stored sparsely — but it need not be materialized

`ApplySlidingWindowD` (`SpectralScorer.cs:477-495`), Comet fast-XCorr, offset 75:

```
prefix[i+1] = prefix[i] + spectrum[i];
result[i]   = spectrum[i] - (prefix[right] - prefix[left] - spectrum[i]) / 150;
```

The **input** `spectrum[]` (binned + windowed peaks) is sparse (~1-3 k nonzero bins). The
**output** `result[]` is effectively dense: every bin within ±75 of any peak becomes nonzero, and
with ~1.5 k peaks over 100 k bins those windows overlap almost everywhere. So caching `result`
sparsely is not possible.

**But `XcorrFromPreprocessed` only ever probes `result[bin]` at ~10-30 fragment bins per
candidate.** Each probe is computable on demand from the sparse input:
- `spectrum[bin]` — sparse lookup (0 when no peak)
- `prefix[right] - prefix[left]` — binary-search the sorted peak bins, read a running prefix sum

**Bit-exact:** the dense prefix adds `0.0` at every empty bin and `x + 0.0 == x` exactly in
IEEE-754 (intensities are >= 0, so no -0.0 case). A prefix sum over only the peaks therefore equals
the dense prefix at every index, bit for bit — same `result[bin]`, same XCorr, same golden.

**Expected: ~391 KB → ~40 KB per spectrum.** Three arrays are needed per peak, not two: the bin
(`int`), the windowed **value** (`double`, needed for the `- spectrum[i]` centre term), and the
running prefix (`double`) = **20 B/peak**. At ~2 k peaks that is **~10x**, not the ~20x first
estimated here, taking the scoring cache from ~18-37 GB to ~2-4 GB.

**Caveats:**
- **Perf**: each fragment probe becomes **three** binary searches (centre value + prefix at `left`
  and `right`), ~11 compares each, rather than one array index; ~180 probes/candidate. Must pass
  `Test-PerfGate.ps1 -Dataset Astral` — **not Stellar**: Stellar is `Resolution = "unit"` and never
  enters `HramStrategy`, so a Stellar-only gate exercises none of this code.
- `XcorrFromPreprocessed(float[], LibraryEntry)` (the 2-arg overload, `SpectralScorer.cs:223`)
  allocates `new bool[preprocessed.Length]` — a **100 KB allocation per call**. Rust's
  `xcorr_sparse` deliberately avoids this with a linear-scan dedup. Confirm the pooled 3-arg
  overload is the only hot-path caller.
- Secondary scoring cuts found: `calibratedSpectra` clones every MS2 `Mzs` array
  (`ScoringPipeline.cs:104-124`, ~1-2 GB); the parquet write builds a **full second columnar copy**
  of all ~3 M rows in one row group (`ParquetScoreCache.cs:299-479`, ~4-6 GB transient) → batch
  row groups. Raw spectra (~4-8 GB) are the true floor.

### Lever 2 — implemented (2026-07-09, commit `ed9d97fef`)

Branch `Skyline/work/20260709_osprey_sparse_xcorr_cache`, stacked on the Lever-1 branch.

- New `Osprey.Scoring/SparseXcorrSpectrum.cs`: `int[] bins` + `double[] values` + `double[] prefix`,
  `CenteredAt(bin)` does the three binary searches and **narrows to `float`**. The narrowing is
  load-bearing: the dense path computed in f64, stored `float[]`, and widened back on read, so
  returning raw f64 would drift every XCorr off the golden.
- `SpectralScorer.PreprocessSpectrumForXcorrSparse` / `XcorrFromSparse` (mirrors the dense
  `XcorrFromPreprocessed` exactly: same bin dedup via `visitedBins`, same touched-bin-only clear,
  same `XCORR_SCALING`).
- `HramStrategy` builds/scores/releases the sparse cache. `UnitStrategy` untouched.
- **Deleted** `XcorrScratchPool.RentBins/ReturnBins/ReturnBinsArray` + its `ConcurrentBag<float[]>`.
  Nothing rents from it now, and that never-shrinking bag *was* the resident memory.

**Verified:**
- `TestSparseXcorrCacheMatchesDenseCache` compares all 100,001 bins against the dense `float[]` cache
  by **raw IEEE-754 bits** (not a delta) — zero difference. Plus empty-spectrum/out-of-range and
  dedup/`visitedBins`-reset tests. 477 pass, 3 skipped.
- `regression.ps1 -Dataset All`: **all six legs PASS**, including Astral mode1 vs golden. Astral blib
  131,174,400 B — identical to the pre-change baseline.
- Perf gate: **not yet measured.** This trades memory for CPU and it is the one open risk.

**Still projections, not measurements:** scoring 18-37 → ~2-4 GB, Stage-5 stub load 53.13 → ~6 GB.
Only the 82-file rerun with `OSPREY_LOG_MEMORY=1` settles them.

---

## Lever 3 (secondary) — `LoadFullFdrEntries` reload (~22 GB)

`ParquetScoreCache.cs:845` reinflates ~940 B entries (21 features + CWT + 4 blob arrays) for the
reconciled-parquet rewrite + blib, when the blib path reads only `ApexRt/StartRt/EndRt/BoundsArea`
(`BlibOutputWriter.cs:209-250`). Rust uses a 5-col `BlibPlanEntry` (~72-96 B, `pipeline.rs:6814`)
plus in-memory library lookup. Add `LoadBlibPlanEntries`; stream untouched rows column-wise in
`ReconciledParquetWriter.Write:64`.

---

## Gates (per phase, each its own branch/PR)

- `regression.ps1 -Dataset Stellar` (mode1/2/3, 1e-9) → `-Dataset All` before merge; cross-impl
  `Compare-EndToEnd-Crossimpl` on Stellar + Astral.
- `Test-PerfGate.ps1 -Dataset Astral` (mandatory for Lever 2 — Stellar runs `UnitStrategy` and would
  pass without executing a single changed line).
- **Machine setup:** `Test-PerfGate.ps1` defaults to `-BaselineRoot C:\proj\pwiz-perfbase`; on this
  box the pinned worktree is `C:\Dev\pwiz-perfbase` (at `245a69d3a`). `-TestBaseDir` is the *dataset
  root* (`C:\Users\macco\Downloads\Perftests\osprey-testfiles-mzML`, holding `stellar/` + `astral/`),
  not a scratch dir. Invoke `ai/` scripts by absolute path — the checkout cwd is `C:\Dev\pwiz`.
- 82-file Astral fit test with `OSPREY_LOG_MEMORY=1`: confirm `[MEM Stage 5 start]` 53 → ~6 GB and
  `[MEM scored file N]` ~26 → ~6-8 GB managed; then push file count to 150-300.

## Note for #4378

Its inspection reports **9 pre-existing warnings in `Osprey.Core/SystemMemory.cs`**
(8x `UnassignedField.Compiler`, 1x `NotAccessedField.Local`) — not introduced by this work, but
they fail `Build-Osprey.ps1 -RunInspection` on that branch.

## Resolution

**Completed 2026-07-10** — both levers shipped and both issues closed-completed.

### 2026-07-10 - Merged

- **Lever 1 (#4397, Stage-5 fat stubs):** PR #4400 (`c9526f0e6`, 2026-07-09) — load the lean
  `FdrProjectionSet` straight from parquet instead of rematerializing 191 M `FdrEntry` stubs
  (~53 GB → ~6 GB), byte-identical.
- **Lever 2 (#4398, dense XCorr spectrum cache):** PR #4409 (`0a8a7676a`, 2026-07-10) — replaced
  the dense `float[NBins]` per-spectrum HRAM cache with the sparse on-demand form
  (`SparseXcorrSpectrum`), removing the ~15 GB pool; bit-identical and ~9% faster scoring. Its
  perf gate settled the "perf not yet measured" risk noted above.

Related retention fix from the same campaign: PR #4406 (`3a4e49e37`, 2026-07-10) released the
first-pass `FdrProjections` after Stage 5. The 64 GB minimum goal is met; the sub-32 GB stretch
remains aspirational, not a blocker for this TODO.
