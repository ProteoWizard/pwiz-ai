# TODO: Osprey per-file scored-entry streaming to Parquet (dedup manifest)

**Status**: Backlog
**Priority**: Medium-High (the largest structural lever on the per-file memory
envelope; GC tuning caps out ~10%, this targets the genuine in-scoring live set)
**Complexity**: Large (streaming refactor of a parity-locked scoring->write path,
plus a new on-disk artifact and manifest-aware loaders; the design is clear, the
risk is byte-parity and multi-site loader changes)
**Created**: 2026-07-14
**Scope**: `pwiz_tools/Osprey/Osprey.Scoring/ScoringPipeline.cs`,
`pwiz_tools/Osprey/Osprey.Tasks/PerFileScoringTask.cs`,
`pwiz_tools/Osprey/Osprey.IO/ParquetScoreCache.cs`, and the parquet loaders in
`FirstJoinTask.cs` / `PerFileRescoreTask.cs`.

## Motivation (measured, 2026-07-14)

Follow-up to the dotMemory retention-hooks work (PR #4423,
`[[project_ospreysharp_output_architecture]]` era). That work established, with the
new `Profile-Osprey.ps1 -MemoryProfile` + `[MEM ...]` boundaries, where the
Osprey per-file memory goes on a single Astral file (file 49, Stage 1-4):

- working_set peak ~28 GB, managed crest ~15 GB, post-scoring **live floor
  4.03 GB** (of which ~3.2 GB is the spectral library).
- A GC-config A/B (`ai/.tmp/gc-cap-experiment.ps1`) showed GC tuning is a modest
  ~10% safe win (`DOTNET_GCConserveMemory=9`: WS 28.0->26.0), **negligible perf
  cost**, results identical. But a 30% heap **hard cap crashes mid-scoring** ->
  the per-file peak is NOT mostly collectable garbage; ~20 GB is **genuinely live
  during scoring**: all ~200k HRAM spectra resident + in-flight scoring + the
  accumulating ~1.7M scored `FdrEntry` objects with their heavy per-entry arrays.
- Allocation tracking confirmed the peak is a **fixed setup cost** (6 windows
  churn as much as 167), so the levers are structural, not per-window tuning.

This TODO tackles the **scored-entry** slice of that live set. (The resident
**spectra** are a parallel streaming question, not covered here; see step 1 --
the `.dmw` retention ranking tells us which of {scored entries, spectra, library}
to attack first.)

Today's flow holds every entry's full payload for the whole file:
`RunCoelutionScoring` returns one `List<FdrEntry>` of all ~1.7M entries, each
carrying `Features`, `CwtCandidates`, `FragmentMzs`, `FragmentIntensities`,
`ReferenceXicRts`, `ReferenceXicIntensities` (`ScoringPipeline.cs:65`). Two dedup
passes run over the full list, then the whole list is written in one shot
(`PerFileScoringTask.cs:1744`), and only THEN are the heavy arrays nulled
(`:1759-1767`, the #4355 mitigation, `[[reference_osprey_resident_firstpass_streams_features]]`).
The comment at `:1751` already says *"these arrays dominate"* -- the mitigation
just fires at end-of-file instead of per-window.

## What dedup needs to succeed (verified against the code)

Neither dedup pass touches the heavy arrays. Both need only a ~4-field scalar
stub per entry (`{EntryId, ApexRt, IsDecoy, CoelutionSum}`, ~21 bytes,
~40 MB for 1.7M) plus the already-resident library.

- **`DeduplicateDoubleCounting` -- per-window** (`ScoringPipeline.cs:336`):
  partitions entries into isolation windows by precursor m/z (`:420-443`);
  within each window (`Parallel.ForEach`, `:455`) removes the lower-`CoelutionSum`
  member of any pair with same decoy-ness (`:485`), apex RT within
  5x median spectrum spacing (`:483`), and >=50% top-6 library-fragment overlap
  (`:493-498`). Reads only `EntryId`, `ApexRt`, `IsDecoy`, `CoelutionSum`; external
  inputs are the library (precursor m/z + top-6 fragments) and the spectrum RT
  list (`rtNeighborhood`, `:368-395`) and `ms2Cal`.
- **`DeduplicatePairs` -- global** (`ScoringPipeline.cs:538`): groups by
  `base_id` (`EntryId & 0x7FFFFFFF`), keeps best target + best decoy by
  `CoelutionSum`, sorts survivors by `EntryId` (`:579`). Reads only `EntryId`,
  `IsDecoy`, `CoelutionSum`. This is the ONLY pass that needs a global view.

## Proposed design: stream payload out, ride the manifest

The two passes decompose along the streaming boundary:

- **Double-counting (per-window)** -> apply BEFORE writing each window; write only
  that window's survivors. No manifest needed.
- **Pair-dedup (global)** -> the only decision that must wait for every window.
  By then the rows are on disk, so it emits a **keep-manifest** rather than
  mutating the file.

New per-file loop:
1. Score one isolation window.
2. Double-count-dedup within that window.
3. Append the window survivors' full payload as a Parquet **row group**
   (`ParquetScoreCache` gains an incremental/append writer).
4. Drop the heavy arrays; keep only the `{EntryId, ApexRt, IsDecoy,
   CoelutionSum}` stub + the parquet row index.
5. After all windows: run `DeduplicatePairs` on the resident stubs -> write a
   `{stem}.scores.dedup` manifest beside the parquet (a keep-bitmap over parquet
   rows, or a sorted survivor-id list).
6. Every subsequent reader (`LoadFdrStubsFromParquet`,
   `LoadPinFeaturesFromParquet`, `LoadCwtCandidatesFromParquet`) applies the
   manifest while streaming; to preserve today's `EntryId`-sorted downstream
   order it masks then sorts the stubs by `EntryId` (cheap).

Peak scored-entry footprint drops from "1.7M x heavy arrays" (multi-GB) to
"1.7M scalar stubs (~40 MB) + one window's arrays".

`RunCoelutionScoring` changes from return-a-`List` to a per-window
yield/callback; `WriteScoresParquet` from one-shot to row-group append.

## Open decision: the Parquet byte-parity contract (the load-bearing question)

Today `{stem}.scores.parquet` holds the **post-dedup** rows, `EntryId`-sorted, and
is compared **byte-for-byte** vs the C# golden (`regression.ps1`) and cross-impl
vs Rust. A pre-dedup-parquet + manifest is a **different on-disk artifact**.
Three ways to reconcile, needs an explicit call (do NOT loosen a bit-parity gate
unilaterally -- `[[feedback_bit_parity_tolerance]]`):

- **(a) Logical compare**: move the parity gate to compare the manifest-applied
  set, not raw bytes. Needs sign-off + end-of-pipeline review.
- **(b) Streaming compaction**: a final bounded-memory pass rewrites survivors to
  reproduce the exact byte-identical post-dedup file. Preserves parity, but must
  re-emit in `EntryId` order, so it needs row-addressable reads of the pre-dedup
  parquet (a wrinkle, not a blocker).
- **(c) Ride the parity-removal sprint** (`[[project_osprey_parity_removal_sprint]]`):
  parity is slated to be broken C#-only soon; afterward the byte constraint
  relaxes and the manifest can simply BE the format. Timing makes this the most
  attractive -- sequence this TODO after the parity break if it lands first.

## Phased plan

1. **Confirm the target first (cheap, no code).** Open the retention `.dmw` and
   rank **Biggest Retained Types at the `perfile-scoring-peak` snapshot** -- the
   IN-SCORING peak, before the #4355 array-null, which is the only snapshot that
   shows the heavy arrays live. Use `ai/.tmp/osprey-memory-20260714-200043.dmw`
   (SNAPSHOT #1 = `perfile-scoring-peak`, 48.73M objects; SNAPSHOT #2 =
   `perfile-scored-live` floor, 34.45M) -- the ~14.3M-object delta between them is
   the streamable array payload. (Do NOT use `perfile-scored-live` alone: a
   forced-GC snapshot taken after the arrays are nulled cannot show them; that was
   the initial mistake, fixed by the `perfile-scoring-peak` boundary in PR #4423.)
   Confirm scored-entry arrays (vs resident spectra vs the 3.2 GB library)
   dominate before touching parity-locked code. If spectra dominate, pivot to
   spectra streaming first.
2. **Decide the parity contract** (a/b/c above) with Brendan.
3. `ParquetScoreCache`: incremental row-group append writer + `.scores.dedup`
   manifest read/write.
4. `ScoringPipeline.RunCoelutionScoring`: per-window yield; move double-count
   dedup to per-window; precompute `rtNeighborhood` up front.
5. `PerFileScoringTask.ProcessFile`: drive the streaming loop; global pair-dedup
   on stubs -> manifest.
6. Manifest-aware loaders in `FirstJoinTask` / `PerFileRescoreTask`.
7. Gates: `regression.ps1 -Dataset Stellar` (+ `All`), cross-impl if parity kept,
   and a `-MemoryProfile` before/after to quantify the peak reduction.

## Explicitly NOT in scope

- **Spectra streaming** (holding all ~200k HRAM spectra resident) -- a separate,
  parallel lever; only pursue if step 1 shows spectra dominate.
- **GC-config changes** -- `DOTNET_GCConserveMemory=9` is a ~10% interim win
  tracked separately; this TODO is the structural fix.

## References

- PR #4423 (dotMemory retention hooks) + its TODO
  `ai/todos/active/TODO-20260714_osprey_dotmemory_retention_hooks.md` -- the
  measurement tooling (`Profile-Osprey.ps1 -MemoryProfile [-TrackAllocations]`)
  and the GC-cap/allocation findings that motivate this.
- `ScoringPipeline.cs:65` (RunCoelutionScoring), `:336`
  (DeduplicateDoubleCounting), `:538` (DeduplicatePairs).
- `PerFileScoringTask.cs:1713` (ScoreAndDeduplicate), `:1744` (WriteScoresParquet),
  `:1759-1767` (the #4355 array-drop this generalizes).
- Memory: `[[feedback_bit_parity_tolerance]]`,
  `[[project_osprey_parity_removal_sprint]]`,
  `[[reference_osprey_resident_firstpass_streams_features]]`,
  `[[reference_osprey_astral_thread_memory_oom]]`,
  `[[feedback_report_output_file_paths]]`.
