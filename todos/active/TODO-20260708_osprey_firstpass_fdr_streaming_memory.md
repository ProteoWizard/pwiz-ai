# TODO: Stream first-pass FDR memory in the Osprey C# port (mirror Rust)

**Created:** 2026-07-08  **Requested by:** Mike  **Issue:** ProteoWizard/pwiz#4393
**Goal:** Make the C# first-pass Percolator FDR stream the read the way Rust does, so
the 82-file SEA-AD Carafe set (and 100s of Astral files) fits a 32–64 GB machine
byte-identically. This is the memory blocker that survived #4378 + #4381 + #4376.

## Evidence (overnight 82-file fit test, combined 3-lever build, 64 GB box)

- Scoring (Stage 1–4) plateaued flat at **WS peak ~48 GB** across all 82 files — the
  #4378 bounding holds. Scoring is NOT the problem.
- **Stage 5 first-pass FDR is the blocker.** Committed memory climbed to **120 GB**
  (pagefile auto-grew to 49.5 GB → no clean OOM, just multi-hour thrash at ~0.5 cores).
  `[MEM Stage 5 start: 82 files loaded (stubs)] working_set=53.4 GB, managed_heap=54.4 GB`.
- Log evidence: `First-pass Percolator input: 191,227,519 entries (21 features)` →
  `features computed: 191,227,519 entries with PIN features, 0 fallback` → the SVM then
  trains on the correct `streaming subsample: 300,000 entries`.

The SVM/300k is fine and always was. The blowup is holding all 191M observations'
features resident to *feed* the FDR — exactly the read-path memory the streaming design
was built to avoid.

## Root cause: the C# port materializes what Rust streams

Rust `crates/osprey/src/pipeline.rs::run_percolator_fdr` (streaming path, ~line 5766):
```
// === Streaming path for large experiments ===
// Memory-efficient: no flat metadata arrays for all entries.
// Subsamples directly from per_file_entries (~16 MB HashMaps),
// scores directly to entry.score, computes q-values per-file.
```
Rust design (see `osprey/CLAUDE.md` "Memory Architecture"):
- `per_file_entries` holds only **~128-byte `FdrEntry` stubs**; PIN features live on disk
  in `.scores.parquet`.
- Best-per-precursor selection uses tiny `HashMap<base_id,(file_idx,local_idx,score)>` +
  a `Vec<(usize,usize)>` of index pairs — **no flat arrays over all N**.
- PIN features are loaded on demand from Parquet for **only the training subset**;
  scoring **streams per-file** through the Parquet caches, writing `entry.score` and
  releasing each file. Never materializes all N feature vectors.

C# divergence (`Osprey.FDR/PercolatorEngine.cs::RunPercolatorFdr`, `PercolatorEntryBuilder`):
1. **`FdrEntry` (Osprey.Core/FdrEntry.cs:59+) carries heavy arrays inline** — `Features`
   (21 doubles), `FragmentMzs`, `FragmentIntensities`, `ReferenceXicRts/Intensities`.
   First-pass FDR holds all 191M resident (`ScoredEntries` context via `FirstJoinTask`),
   ~54 GB. (Rust FdrEntry is a lean stub, features on disk.)
2. **`PercolatorEntryBuilder.Build` makes a second full copy** — 191M `PercolatorEntry`
   each with a 21-double feature vector (`PercolatorEngine.cs:100`).
3. **`RunPercolatorStreaming` builds flat `labels[]`/`entryIds[]`/`peptides[]` arrays over
   all 191M** (`PercolatorEngine.cs:322-330`) — the exact "flat metadata arrays for all
   entries" Rust's comment says it avoids — then "applies the averaged model to ALL
   entries" from the resident list (`PercolatorEngine.cs:302`).

Net: ~54 GB (inline features) + ~30–40 GB (second copy) + ~10 GB (flat arrays) → ~120 GB.

## The fix already has infrastructure in C#

`Osprey.IO/ParquetScoreCache.cs` already provides the selective loaders Rust uses:
- `LoadFdrStubsFromParquet(path)` (line 723) — lean stubs, no features.
- `LoadPinFeaturesFromParquet(...)` (line 834 region) — mirror of Rust
  `load_pin_features_from_parquet`.
The first-pass FDR path simply doesn't use them for streaming.

## Plan for the C# port (mirror Rust `run_percolator_fdr` streaming path)

1. **Hold only lean stubs in first-pass FDR.** After Stage-4 scoring writes each file's
   `.scores.parquet`, the `ScoredEntries` fed to Stage 5 should be feature-less stubs
   (drop `Features`/`Fragment*`/`ReferenceXic*` from the resident entries, or load via
   `LoadFdrStubsFromParquet`). `coelution_sum`, `entry_id`, `is_decoy`, `charge`,
   `scan_number`, `parquet_index` stay on the stub (already there) — enough for selection.
2. **Index-based best-per-precursor selection** (mirror Rust 5786-5834): build
   `Dictionary<uint,(int fileIdx,int localIdx,double score)>` for best target / best decoy
   by `base_id = entry_id & 0x7FFFFFFF`, weighted by `coelution_sum`; collect
   `List<(int,int)>` index pairs; sort for determinism. No 191M flat arrays.
3. **Load PIN features from Parquet for ONLY the subset.** After best-per-precursor +
   peptide-grouped subsample selects the ≤300k index set, call `LoadPinFeaturesFromParquet`
   for just those rows → build the 300k `PercolatorEntry` list → train (unchanged SVM).
4. **Stream scoring per-file.** For each file: `LoadPinFeaturesFromParquet`, apply the
   averaged model, write `entry.score`, release before the next file. No all-resident
   `percEntries`.
5. **Global/experiment q-values on a lean projection.** The experiment-level q-value sort
   genuinely needs all observations at once, but only `(score:double, isDecoy:bool,
   groupKey)` ≈ 24 B × 191M ≈ ~4.5 GB — not FdrEntry+features. Build that lean array, sort,
   compute q-values, stream back per file.

**Projected peak:** ~120 GB → ~6–8 GB (300k subset + ~4.5 GB lean score array + one file in
flight). Fits 64 GB comfortably; likely 32 GB (fewer threads on a smaller box lowers it
further).

## Hard constraint: byte-identical parity

- The selected 300k subset and the global q-value ranking must stay **bit-identical**
  (regression gate + cross-impl vs Rust). The current selection runs on the fully-sorted
  in-memory list; the streamed selection must reproduce the **exact same canonical sort**
  (`entry_id, charge, scan_number, parquet_index` — see Rust 5721-5728 / C#
  `PercolatorEngine.cs:85-94`) and the **same subsample RNG seed**
  (`SelectBestPerPrecursor` / `SubsampleByPeptideGroup`).
- Because Rust already streams and Osprey must match Rust byte-for-byte, mirroring Rust's
  index-based selection is the safest route to preserve parity (Rust is the oracle here).
- Cross-validation grouping invariant (Rust CLAUDE.md): target–decoy pairs and all charge
  states of a peptide share a fold; subsample by `base_id` groups, not individual entries.
  The streamed selection must preserve this.

## Validation

- `pwsh -File ./pwiz_tools/Osprey/regression.ps1 -Dataset Stellar` byte-identical
  (mode1/2/3), then `-Dataset All`.
- Cross-impl: `ai/scripts/Osprey/Compare/Compare-EndToEnd-Crossimpl.ps1` on Stellar +
  Astral (this change is squarely in the FDR path — parity check is mandatory).
- Re-run the 82-file SEA-AD Carafe set; confirm Stage-5 peak drops from ~120 GB to single
  digits and it completes without pagefile thrash. Data + run script:
  `Z:\2026-05-SEA-AD-Pilot-MTG\Carafe-Osprey\` and `ai/.tmp/run-osprey-82.ps1`.

## Notes / related

- Secondary target once first-pass streams: the same materialization likely repeats in the
  **second-pass** percolator (`Pass2FdrSidecar.cs` → `FirstJoinTask.RunPercolatorFdr`) and
  possibly protein FDR — audit `ProteinFdrEngine`/`ProteinFdr` for all-resident pools.
- Prior memory levers (context): #4378 scoring/join bounding, #4381 library resident,
  #4376 reconciliation per-file drop. This TODO is the first-pass-FDR analogue of #4376's
  streaming philosophy, applied to the FDR read path.
- Rust reference commit: `maccoss/osprey` @ fe52573, `crates/osprey/src/pipeline.rs`
  lines 5688 (`run_percolator_fdr`) / 6107 (`run_percolator_fdr_direct`).
