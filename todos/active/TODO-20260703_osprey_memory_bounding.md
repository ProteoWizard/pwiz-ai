# TODO-20260703_osprey_memory_bounding.md -- Bound Osprey peak memory on large multi-file runs

> An ~80-sample DIA search OOMs a 96 GB box (memory 100%, SSD 100% pagefile, CPU
> ~29%). Peak memory scales O(N) with sample count because every file's heavy
> `FdrEntry` arrays -- already spilled to `scores.parquet` -- stay resident until
> Stage-5 compaction. Port the Rust "shrink-after-spill + rehydrate" so an 80-file
> Astral run fits in **64 GB** with **byte-identical** output.

## Branch Information

- **Branch**: `Skyline/work/20260703_osprey_memory_bounding`
- **Base**: `master` (`d032f5978`)
- **Created**: 2026-07-03
- **Status**: In Progress
- **GitHub Issue**: [#4355](https://github.com/ProteoWizard/pwiz/issues/4355)
- **PR**: (pending)

## Problem (evidence)

- Real run `Y:\2026-05-SEA-AD-Pilot-MTG\Carafe-Osprey\carafe_log.txt` (via Carafe): 82
  Astral files, `File parallelism: 1` (sequential), 3.2M-entry library. Stopped mid
  per-file scoring at file 55/82.
- Host: 96 GB RAM. Symptom: RAM 100% + SSD 100% + CPU ~29% == memory exhaustion ->
  Windows pagefile thrashing (threads blocked on page faults). Target: **64 GB**.
- Because parallelism == 1, only one file's spectra are resident. The blowup is NOT
  spectra; it is the accumulating results buffer.

## Root cause (from 3 code probes + Rust comparison)

- All N files' `FdrEntry` objects accumulate in one shared buffer
  (`PerFileScoringTask._perFileEntries`) held until Stage-5 compaction; peak = end of
  Stage 4 (all N resident, pre-compaction).
- **Dominant term:** each retained `FdrEntry` still carries heavy arrays already
  written to parquet and reloadable -- `Features`, `CwtCandidates`, `FragmentMzs`,
  `FragmentIntensities`, `ReferenceXicRts`, `ReferenceXicIntensities`
  (`FdrEntry.cs:59-104`). They are never nulled after `WriteScoresParquet`
  (`ProcessFile` returns them as-is). ~N x the full heavy per-entry set stays resident.
- The C# port kept the Rust per-file spill-to-parquet but NOT the Rust struct
  downsizing (`CoelutionScoredEntry` ~940 B -> `FdrEntry` stub ~128 B after spill).
- Compounding: `--parallel-files` free-RAM guard budgets only per-file *spectra* bytes,
  not the growing results buffer (`PerFileRescoreTask.cs:558-566`).
- Not a leak: no undisposed streams/SQLite, no sample-keyed static caches, spectra are
  per-file locals; the buffer is reclaimed at compaction and run end.

## Disk symptom (secondary)

- Mostly pagefile thrashing (memory). Plus an independent contributor: score parquets
  are staged in local `%TEMP%` (SSD) then cross-volume `File.Move`d to the NAS
  (`ParquetScoreCache.cs:262-290, 455-480`) -- unlike `FileSaver`, which stages a
  sibling temp in the destination dir.

## Fix plan (phased, ordered by impact/risk)

**Phase 0 -- Instrument & measure the baseline.**
- Add `ProfilerHooks.LogMemoryStats` calls in the per-file scoring loop and around
  `CompactFirstPass` / the join boundary. Run a subset that does not OOM (e.g. 15-20
  files) to get the per-file GB slope; confirm the linear climb + drop-at-compaction
  signature and quantify the dominant term. This is the yardstick for every later phase.

**Phase 1 -- Drop heavy arrays after the parquet spill (the O(N) killer).**
- Enumerate the heavy `FdrEntry` fields that are (a) already persisted to parquet and
  (b) reloadable. For each, map EVERY downstream consumer (Stage-5 compaction,
  `FirstJoinTask`/Percolator, `ConsensusRts`, `MergeNodeTask`/blib, `PerFileRescoreTask`)
  and confirm it either does not need the array or rehydrates it from parquet
  (`RescoreHydration`).
- Null those arrays on each retained stub immediately after `WriteScoresParquet`; add
  rehydration where a consumer needs them. Port of the Rust tiered downsizing.
- Delicate: a consumer that reads a nulled array = silently WRONG output, not a crash.
  The regression gate is the safety net; consider a debug guard that a nulled field is
  never read without rehydration.

**Phase 2 -- Parallelism RAM accounting.**
- Make the `--parallel-files` free-RAM guard budget the accumulating results buffer, not
  just spectra, so K reflects true peak RAM. Independent, low risk.

**Phase 3 -- DROPPED (Mike's catch, 2026-07-03).** An earlier draft proposed staging the
parquet temp beside the destination (like `FileSaver`) instead of `%TEMP%`. Withdrawn: for
a remote NAS destination the local-stage-then-move is the *better* design (fast local seeky
writes + one bulk transfer; the NAS only ever sees a complete file; `ParquetScoreCache.cs:261`
comments it "safe NAS writes"). The SSD-100% is the pagefile (memory), fixed by Phase 1.

**Separate robustness follow-up (NOT part of this memory fix).** The C# temp->final move
(`ParquetScoreCache.cs:288-290`, `File.Delete` then `File.Move`) does no post-copy integrity
check, so a truncated write on a flaky CIFS/SMB mount could land silently. Rust guards every
such move with `osprey_core::copy_and_verify` (`crates/osprey-core/src/lib.rs:26`): stat the
source, `fs::copy`, verify the copied byte count == source size, retry with a buffered
`io::copy` on mismatch ("handles CIFS/NFS where `copy_file_range` may silently truncate").
Used at 6 Rust sites (scores + reconciled parquet, calibration, libcache, `.spectra.bin`).
Port a `CopyAndVerify` helper and route the C# parquet/blib/cache moves through it. Track
separately (own issue/TODO).

**Phase 4 (only if Phase 1 falls short of 64 GB) -- Stream the join.**
- Stream Percolator scoring from per-file parquet instead of holding all entries
  (Rust #5/#3); fix the Stage-7 `O(passing x N)` pre-size (`MergeNodeTask.cs:482`).
  Larger; gate on measurement.

## Success criteria / gates

- [ ] ~80-file Astral search peaks **< 64 GB** (measured via `ProfilerHooks`).
- [ ] `Build-Osprey.ps1 -RunTests -RunInspection` green.
- [ ] `regression.ps1 -Dataset Stellar` (and `All` before merge): **byte-identical**
      output vs golden (this is a scoring-pipeline change -- mandatory).
- [ ] `Test-PerfGate.ps1`: no speed regression (rehydration adds I/O -- watch it).
- [ ] SSD no longer saturated by parquet staging.

## Risks

- **Rehydration completeness** -- the one that can bite: a missed consumer reads a nulled
  array and produces wrong FDR silently. Mitigate: explicit per-consumer audit +
  regression gate + optional debug assertion.
- **Reload cost** -- rehydrating from parquet is extra I/O; keep it only where needed;
  verify with the perf gate.
- **Library baseline** -- 3.2M-entry library is a separate fixed cost; only address if
  Phase-0 measurement shows it dominates after Phase 1.

## Cross-reference: Rust techniques (frozen oracle at `D:\GitHub-Repo\maccoss\osprey`)

The 10 techniques inventoried from the archived Rust impl; C# already has per-file
spectra freeing + spill + `XcorrScratchPool` + streaming blib. The gaps that matter
here: #1 (free results per file) and #2 (shrink struct after spill) -- Phase 1; the
parallelism/accounting -- Phase 2. Streaming Percolator (#5) -- Phase 4 if needed.

## Phase 1 design (from the rehydration audit, 2026-07-03)

Heavy `FdrEntry` fields + verdicts (all persisted by `ParquetScoreCache.WriteScoresParquet`
and reloadable by `ParquetIndex`):
- **5 blob fields** (`CwtCandidates`, `FragmentMzs`, `FragmentIntensities`,
  `ReferenceXicRts`, `ReferenceXicIntensities`) -- **no in-memory consumer** after the
  per-file write (Stage 6 CWT loads from parquet via `CwtCandidateLoader`; blib fragments
  come from the library, not these). Safe to null. The bulk of the memory.
- **`Features`** (double[21]) -- one in-memory consumer: Stage-5 first-pass Percolator
  (`FirstJoinTask.RunFdr` -> `PercolatorEntryBuilder`). Stage 7 reloads from parquet.
- **Landmine:** `ReconciledParquetWriter.ApplyRescoredRows` uses `Features == null` as the
  "not rescored, keep parquet row" sentinel -> invariant `Features-null <=> blobs-null`.
  Breaking it silently overlays empty blobs into the reconciled parquet.

3-site implementation (null all six; matches the existing warm-path contract):
1. After `WriteScoresParquet` (`PerFileScoringTask.cs:~1307`, before `return` at ~1314):
   null all six on each entry -> stub shape.
2. Before Stage-5 Percolator (`FirstJoinTask` before `RunFdr`): bulk-reload `Features` per
   file via `ParquetScoreCache.LoadPinFeaturesFromParquet` + bind by `ParquetIndex` (reuse
   `Pass2FdrSidecar.MapFeaturesByParquetIndex` / `LoadJoinOnlyScores`).
3. After first-pass + protein FDR, before Stage 6: re-null `Features` (mirror
   `FirstJoinTask.cs:431-433`) so the sentinel invariant holds.

**Percolator refinement (confirmed in code):** C# ALREADY subsamples training to 300K
(`PercolatorConfig.MaxTrainSize = 300000`, `PercolatorFdr.cs:115`; `BuildTrainingSubset`).
So training memory is bounded, same as Rust. The Stage-5 watermark is the **score** pass:
`RunFdr` holds the full `IList<PercolatorEntry>` and a dense `n x nFeatures` matrix
(`PercolatorFdr.cs:254`) over ALL entries. Rust streams the score pass from per-file
parquet and never materializes that. => **Phase 4, if needed, streams the SCORING (not the
trainer)** + drops the separate dense `stdFeatures` copy. Phase 0 measurement decides.

## Progress log

- 2026-07-03: Diagnosed via 3 code probes (C# memory, C# disk/temp, Rust techniques) +
  the live Carafe log. Filed issue #4355, created branch + this TODO. Root cause = O(N)
  heavy-array retention; not a leak.
- 2026-07-03: Rehydration audit complete (per-field verdicts + 3-site design above);
  confirmed the 300K training subsample is already ported (Stage-5 lever is streaming the
  score pass). Dataset confirmed: 82 SEA-AD Astral files at `Y:\...\project_mzML`.
  Implementing Phase 0 (ProfilerHooks) + Phase 1 next.
- 2026-07-03: Phase 0 (gated `ProfilerHooks.LogMemoryStatsIfEnabled` via `OSPREY_LOG_MEMORY`;
  per-file + Stage-5 boundary probes) committed `9dd06feb1`. Phase 1 (null the 6 heavy
  `FdrEntry` arrays after each per-file parquet write; reload PIN features by `ParquetIndex`
  before first-pass Percolator via `Pass2FdrSidecar.MapFeaturesByParquetIndex`; re-null
  before Stage 6 to keep the `ApplyRescoredRows` sentinel valid) committed `a2ce32b87`.
  Verified `ParquetScoreCache.cs:384` sets `ParquetIndex` on the passed entries; the f64
  feature roundtrip is the same one 2nd-pass FDR already uses (regression-exact). Debug +
  Osprey.Test 447 pass + 0-warning inspection.
  PENDING: (1) byte-identical `regression.ps1` (Release binary busy with the 20-file
  baseline run); (2) baseline `[MEM]` curve; (3) instrumented-Release fixed run to confirm
  the 82-file peak < 64 GB. Baseline (20 files) running in background.
- 2026-07-04: Corrected the disk-symptom analysis (issue #4355 body + comment). Phase 3
  dropped -- local-stage-then-move is the right design for a NAS destination. Confirmed Rust
  does post-copy integrity verification (`osprey_core::copy_and_verify`, byte-count +
  buffered-retry, 6 sites); C# `File.Move` lacks it -> tracked as a separate robustness
  follow-up above (filed #4356). Also filed #4357 (near-linear parsimony) + backlog TODO.
- 2026-07-04: Overnight fixed-20 measurement on the 64 GB TARGET machine. Phase 1 WORKS:
  file-13 managed 19.9 GB (vs unfixed baseline 56 GB); the unfixed baseline OOM'd at file 14,
  the fixed run scored all 20 + Stage 5 + into Stage 6 at ~46 GB working set (~2x reduction),
  producing valid output (no crash). BUT Stage 5 is the new ceiling: the Phase-1 feature-reload
  is itself O(N) -- ~27 GB managed for 20 files (library + 20x features) -> ~89 GB extrapolated
  for 82; and peak_paged already hit 65.57 GB at 20 files. => **Phase 1 necessary but NOT
  sufficient for 82 files on 64 GB; Phase 4 (streaming Percolator) confirmed required.** The
  run was killed by the machine SLEEPING at 02:08 (healthy in Stage 6, not an OOM) -> future
  unattended runs need sleep disabled. Parsimony: 8454 protein groups @ 20 files (#4357 sizing).
  Started Phase 4: two probes mapping the C# `PercolatorFdr` flow + the Rust streaming reference
  (`crates/osprey-fdr/src/percolator.rs`) before coding. Byte-identical is the gate.
- 2026-07-04: Phase 4 (streaming Percolator) implemented via a worktree agent, REVIEWED here +
  byte-identity verified (`CoelutionSum == Features[0]` so best-per-precursor unchanged; per-entry
  score math character-identical; `ResolveFeatureRow` == the old reload). Integrated + committed
  `d46708fc5` + pushed. Debug + Osprey.Test **448 pass**, 0 new inspection warnings (fixed 2
  ReSharper nits the agent missed). Phase-4 82-file run on the 64 GB machine: **working set
  BOUNDED ~35-53 GB** (was OOM @ file 14 unfixed) -- Phase 4 works -- BUT managed heap climbs
  ~0.6 GB/file (the `FdrEntry` STUB buffer O(N) + the fixed 3.17M library) and peak_paged hit
  65 GB, so 82-on-64 GB is at the EDGE (paging). Killed the 64 GB run; moved the definitive
  82-file run + peak measurement to the **96 GB machine** (handoff written at
  `\\maccoss-nas\home\2026-05-SEA-AD-Pilot-MTG\Carafe-Osprey\OSPREY-MEMORY-WORK-HANDOFF.md`).
- **NEXT LEVERS (Phase 5+, still #4355), to get 82 comfortably under 64 GB:** (1) intern
  `ModifiedSequence` (Rust #4 `Arc<str>`; likely the biggest stub win); (2) compact non-passing
  stubs after the first pass (Rust #3); (3) Phase 4b -- stream the Stage-7 2nd-pass FDR (the agent
  left it resident: gap-fill `ParquetIndex == uint.MaxValue` + `CoelutionSum` diverges after
  rescore); (4) profile the 3.17M-library fixed cost. Size these from the 96 GB peak.
- **Byte-identity gates still PENDING:** `regression.ps1`/Stellar (direct path) + a >600K
  before/after diff (streaming path -- Stellar doesn't exercise it).

- 2026-07-04 (96 GB machine): Ran the definitive peak measurement on the 96 GB box (branch
  `d46708fc5`, Release, `OSPREY_LOG_MEMORY=1`, the 82-file SEA-AD command). Stopped early at
  **file 14/82** -- the trajectory was already decisive: working_set peak **76.8 GB**,
  managed_heap peak **39.74 GB**, peak_paged **78.14 GB**, steady managed-heap slope
  **~0.69 GB/file** (files 4->12, confirms the handoff's ~0.6 GB/file). Free RAM fell
  ~0.8 GB/file (13.6 GB by file 12) -> projects to exhaust physical around file ~20 and page
  after; i.e. 82 files does NOT fit even 96 GB past-Phase-4, let alone the <64 GB target.
  Confirmed the slope's root in C# code: `FdrEntry.ModifiedSequence` is an **un-interned
  `string`** (one object/entry, duplicated across GPF replicates) AND `FdrEntry` is a **`class`**
  (16 B object header + gen2/LOH GC churn -> the 96 GB working_set ballooned to 77 GB while
  managed_heap was only 40 GB; a smaller box would GC harder and OOM sooner).
- 2026-07-04: DECISION (Mike) -- port the two Rust techniques that are already worked out +
  byte-identity-validated, **faithfully**, before any C#-specific structural change:
  - **#1 Intern `ModifiedSequence`** -- Rust `intern_seq` (`pipeline.rs:2371`, a
    `HashSet<Arc<str>>` canonicalizing pool threaded through every stub builder). C# intern
    points mapped: `CoelutionScorer.cs:448` (fresh scoring, the O(N) primary),
    `ParquetScoreCache.cs:754` (`LoadFdrStubsFromParquet`) + `:898` (join-only loader),
    `PerFileRescoreTask.cs:1349` (gap-fill). Byte-identity-trivial: only string *reference*
    identity changes, values are character-identical.
  - **#3 Compact non-passing stubs after first-pass FDR** -- Rust commit `1a93449` (drop stubs
    for precursors passing in no replicate; `ParquetIndex` -- already added in Phase 1 --
    preserves the parquet row ref; gap-fill uses `ParquetIndex = uint.MaxValue`). Slots in
    right after first-pass protein FDR (Rust `pipeline.rs` ~4580).
  - **FALLBACK only** (if faithful #1+#3 still misses <64 GB): make C# `FdrEntry` a value
    struct in a contiguous buffer (removes the per-entry header + class-instance GC pressure).
    This is a C#-idiom change NOT in the Rust algorithm -> fallback, not first resort.
  - Sequence: implement #1 -> build Debug + `Osprey.Test` -> re-measure the 20-file `[MEM]`
    slope -> decide if #3 (and/or the struct fallback) is still needed. Gate every step on
    `regression.ps1 -Dataset Stellar` (direct path) + the >600K streaming before/after diff.
- Reference: the Rust `maccoss/osprey` clone on this machine is
  `C:\Users\macco\Documents\github\maccoss\osprey` (`main` @ `696c938`), NOT the skill's
  `C:\proj\osprey` convention.

- 2026-07-04: Inventoried the FULL Rust memory-strategy set vs the C# port (verified in code,
  not just the handoff). #1 interning IMPLEMENTED (static thread-safe `SequenceInterner`, ordinal
  `ConcurrentDictionary`, `Reset()` at the single `AnalysisPipeline.Run` chokepoint; interned at
  `CoelutionScorer` fresh-scoring + both `ParquetScoreCache` loaders); Debug + Osprey.Test 448
  pass, 0 new warnings. PENDING: diff review + 20-file `[MEM]` re-measure. Additional levers to
  track beyond #1/#3, priority order:
  - **Tier 4 -- streaming blib output** (Rust `BlibPlanEntry` ~96 B: 5-col parquet projection +
    in-memory library lookup). C# instead reloads FULL ~940 B entries for blib via
    `ParquetScoreCache.LoadFullFdrEntries` (`ParquetScoreCache.cs:850`) -- the ~22 GB @24M cost
    Rust designed away. The real remaining full-reload; biggest post-first-pass lever. MISSING.
  - **Tier 3 -- `LightFdr`** (~48 B): extract a light struct before blib and DROP the FdrEntry
    stubs (Rust frees ~19 GB @240f). No `LightFdr` in C#. MISSING.
  - **Reconciliation re-scoring parallelism**: Rust forces SEQUENTIAL (`iter_mut`) to avoid
    K x ~3 GB spectra resident; C# uses `Parallel.For` (`PerFileRescoreTask.cs:563`,
    byte-identical output). On 64 GB, match Rust's sequential default or make the
    `--parallel-files` RAM guard conservative (overlaps Phase 2). WATCH.
  - **Phase 4b (stream 2nd-pass FDR) -- effectively already handled; DOWNGRADED.**
    `Pass2FdrSidecar.cs:136-190` ALREADY reads PIN features per-file
    (`LoadPinFeaturesFromParquet` in a per-file loop) -- no dense reload-all. It only attaches
    them onto the resident stubs for 2nd-pass Percolator; that residency is O(pool-at-2nd-pass) =
    O(all-N) WITHOUT compaction but O(passing) once #3 lands, so **#3 subsumes it**. Phase 4b
    (score-and-discard) is at most a minor follow-up on the compacted pool. The measured OOM is
    at Stage-4 per-file scoring (file 14), before the 2nd pass is reached.
  - Sequence: finish #1 (diff review + 20-file `[MEM]`) -> #3 compaction -> re-measure ->
    Tier 4 -> Tier 3. Byte-identity gated each step (`regression.ps1 -Dataset Stellar` + >600K
    streaming diff).

- 2026-07-04: MEASURED #1 (interning) -- clean fresh 14-file A/B (interned build fresh-scoring
  files 1-14 vs the preserved non-interned baseline `C:\temp\phase4-82.log`). **RESULT: interning
  is a NET NEGATIVE in C#.** Median delta managed_heap (files >=4) = **+0.58 GB (interned HIGHER)**;
  slope 4->14 interned **0.875** vs baseline **0.687** GB/file (baseline confirms the original
  ~0.69). The interner's `ConcurrentDictionary` (~3.17M unique strings + node overhead) is not
  repaid by string dedup. => **#1 REVERTED** (`SequenceInterner.cs` deleted, 3 edits restored;
  branch clean at d46708fc5). Root cause of the wash: in Rust `FdrEntry` is a 128 B *struct* where
  the interned `Arc<str>` is the only per-entry heap allocation (interning is a big win there); in
  C# `FdrEntry` is a ~300 B *class* (16 B header + 16 doubles + string + 6 heavy-array refs), so the
  string is a minor slice and the interner overhead exceeds the saving.
- 2026-07-04: CONFIRMED **#3 (stub compaction) is ALREADY IMPLEMENTED** in the C# straight-through
  pipeline (`FirstJoinTask.cs:307 CompactFirstPass`, drops non-passing base_ids 32.3M->2.06M). The
  handoff/TODO were wrong to list it as a lever -- REMOVED from the plan. (Phase 4b likewise
  effectively handled: 2nd pass reads PIN features per-file, residency bounded by #3.)
- 2026-07-04: **NEW PRIMARY LEVER -- make C# `FdrEntry` match Rust's Tier-2 stub (~128 B):**
  (a) value **STRUCT** in a contiguous buffer -- kills the 16 B/object header x tens of millions
      AND the gen2/LOH GC churn that ballooned the 96 GB working_set to 77 GB vs 40 GB live heap;
  (b) **split the 6 heavy array fields OUT of the stub** -- Rust's `FdrEntry` has NO array fields
      (heavy data reloaded from parquet); C# carries them as nulled refs (+48 B/stub).
  Target ~128 B/stub (vs C#'s ~300 B) = ~2.3x cut => 82 files ~25 GB stubs, fits 64 GB. Bigger,
  byte-identity-sensitive refactor (structs copy on assignment: every in-place mutation of a
  `List<FdrEntry>` element must become index-assign or array/`Span` access). SCOPE before coding;
  gate on `regression.ps1 -Dataset Stellar` + the >600K streaming diff.

- 2026-07-04: MEMORY BREAKDOWN (reconstructed from [MEM] anchors) -- three groups: **library
  ~4-6 GB** (fixed); **stub buffer ~1.0-1.2 GB/file** (ACCUMULATES across files in
  `perFileEntries`); **per-file transient ~20 GB** (spectra + full scored entries; released per
  file, does NOT accumulate). Two peaks: scoring peak = lib + accumulated stubs + current transient
  (~108 GB @ 82f); first-pass-FDR peak = lib + all stubs (no transient). The OOM is the transient
  stacking on the growing stub buffer during scoring.
- 2026-07-04: EMPIRICAL JOIN-WALL measurement (`--task FirstPassFDR` over session-scored parquets,
  OSPREY_LOG_MEMORY, no re-scoring). 14 & 20 files scale cleanly:
  - Stage-5 start (all stubs+features loaded, pre-FDR): 14f=20.84 / 20f=28.01 GB heap -> library
    ~4 GB + ~1.2 GB/file. **Extrapolate 82f: ~102 GB just to LOAD.**
  - After first-pass Percolator FDR: 20f WS 73 (peak 78), heap 37.2, peak_paged 80.6.
    **Extrapolate 82f: heap ~126 GB, peak_paged ~200 GB.**
  => the join cannot fit 82f even on 96 GB. The join loads "stubs + FEATURES" per file
  (`PerFileScoringTask.LoadJoinOnlyScores:854`, `889`/`893`) -> ~450 B stub + ~168 B features =
  ~618 B/entry resident.
- 2026-07-04: **NEW PLAN (Mike's architecture) -- decouple scoring + minimal-projection streaming
  join. Struct-ify DEMOTED off the critical path.**
  1. **Decouple scoring:** `PerFileScoringTask` spills each file's parquet and FREES it instead of
     `perFileEntries.Add()` (mirror `--task PerFileScoring`). Bounds Stage 4 to lib + one-file
     transient (~26 GB), N-flat -> 82-file scoring COMPLETES.
  2. **Minimal-projection streaming join:** replace `LoadJoinOnlyScores`' full-stub+feature load
     with a **~20 B/entry value-struct projection** [Score 8 + IsDecoy 1 + EntryId 4 + Charge 1 +
     peptide_id 4 (int index into a modseq string table) + file_idx 2] in a contiguous array
     (base_id = EntryId & 0x7FFFFFFF, derived). 82f: 189M x 20 B = ~3.8 GB + lib 4 + 300K training
     features (~50 MB) + one-file streamed features (~0.4 GB) = **~9 GB join** (vs ~100-126 GB).
     ~12-20x cut; fits 64 GB with huge headroom. The `int` peptide_id IS the correct modseq
     interning (4 B/entry) the `ConcurrentDictionary` failed to deliver.
  - Reuse EXISTING machinery: `PercolatorEngine.RunPercolatorStreaming` (streams the score pass,
    Phase 4; `PercolatorEngine.cs:139-149`), `FdrScoresSidecar` (writes per-file
    `.1st-pass.fdr_scores.bin` q-values), `LoadFdrStubsFromParquet` (per-file reload for
    reconciliation/output = the byte-parity-validated HPC-split path), the 300K `BuildTrainingSubset`.
  - Competition reads only Score/IsDecoy/EntryId/Charge/ModifiedSequence and WRITES the q-values
    (to sidecars) -> the projection is sufficient; full stubs reload later per-file.
  - Impl surface: `PerFileScoringTask.LoadJoinOnlyScores` (+ the straight-through `perFileEntries`
    build), `PercolatorEngine.RunPercolatorFdr`, `FdrScoresSidecar` 1st-pass write, reconciliation/
    output reload. Byte-identity-critical (competition + q-value math bit-exact); gate on
    `regression.ps1 Stellar` + >600K streaming diff. Large but reuses proven streaming/sidecar plumbing.

- 2026-07-04: **STEP (a) DECOUPLE SCORING -- IMPLEMENTED + COMMITTED** (pwiz branch `8920f8bda`,
  `PerFileScoringTask.cs` +40/-6). `Run` no longer retains per-file `FdrEntry` stubs during Stage 4
  (records only ordered file names); after the scoring loop it reloads scalar stubs from each
  `.scores.parquet` (`LoadFdrStubsFromParquet`) before `FinalizeAndCheck`. Calibrations stay LIVE
  (not in parquet). **Unconditional** (matches the HPC per-file spill/reload contract -> one path
  for single-system + distributed; a gate would add a divergence-risk second path for a few seconds'
  small-run gain). GATES: build + Osprey.Test **448 pass / 0 new warnings**; **byte-identical**
  (`Compare-BlibFull` 1e-9, 0 diffs vs baseline -- direct A/B, since the golden is stale, below);
  **Test-PerfGate Stellar total -1.5%** (stage5/join -3.5%), PASS. Bounds the scoring peak to
  ~lib + one-file transient; the join peak (~100 GB @ 82f) is still the wall -> step (b).
- 2026-07-04: SEPARATE ISSUE (not our change) -- the regression **GOLDEN is STALE**: `regression.ps1`
  mode1 fails on clean HEAD too (byte-identical 87 issues); golden last written `1ca152c54`
  (~13 commits back, before recon fix #4347 + Phase 1/4). mode1 is red on this branch regardless;
  needs a **golden refresh** (own task). Byte-identity proven via direct `Compare-BlibFull` A/B
  instead. Machine notes: perf dataset at `C:\Users\macco\Downloads\Perftests\osprey-testfiles-mzML`
  (`OSPREY_TEST_BASE_DIR` unset -> pass `-TestBaseDir`); `pwiz-perfbase` worktree pinned at
  `d46708fc5` for the A/B (re-pin as the branch advances).
- **NEXT: step (b) minimal-projection streaming join** (~100 GB -> ~9 GB). The big win; fresh
  focused session. Surface recorded above (`LoadJoinOnlyScores`, `PercolatorEngine`, `FdrScoresSidecar`).

- 2026-07-04: **CRITICAL REGRESSION FOUND -- Phase 1 (`a2ce32b87`) silently lost 57% of
  identifications.** Refreshing the stale golden surfaced it: Stellar straight-through yields
  **25,663** precursors (RefSpectra rows) vs the correct **59,768**. Bisected on Stellar via
  `regression.ps1 -CreateGolden` RefSpectra count: Phase 0 `9dd06feb1`=59,768 OK; **Phase 1
  `a2ce32b87`=25,663 (regression HERE)**; Phase 4 `d46708fc5` / HEAD `8920f8bda`=25,663 (carried,
  NOT fixed). #4347 `b2373f9f9`=59,768 (so #4347 is NOT the cause -- it's the memory work itself).
  - Mechanism: Phase 1 nulls the in-memory `Features` and reloads PIN features from parquet via
    `Pass2FdrSidecar.MapFeaturesByParquetIndex` (`featRows[ParquetIndex]`) before first-pass
    Percolator (`FirstJoinTask`). The reloaded vectors evidently differ from the originals ->
    corrupt first-pass discriminant -> 57% fewer pass. STRAIGHT-THROUGH only (HPC reloads via
    `LoadFdrStubsFromParquet`, ParquetIndex correct -- same shape as the prior CWT
    `ParquetIndex=0` bug documented at `ParquetScoreCache.cs:366-383`).
  - **Hidden by the stale golden** (last refreshed at #4335 `1ca152c54`, before #4347). No gate ran.
  - CONSEQUENCES: the whole branch output is WRONG. **Step (b) + golden refresh ON HOLD.** Do NOT
    refresh the golden to this broken output. Step (a)'s "byte-identity" is only vs the broken
    Phase-4 baseline (step (a) itself is a sound refactor, not the culprit). This must be fixed and
    Stellar returned to 59,768 before anything else. Debug+fix delegated (subagent, gated on
    Stellar->59,768).
  - Housekeeping this session: `OSPREY_TEST_BASE_DIR` set (User) to
    `C:\Users\macco\Downloads\Perftests\osprey-testfiles-mzML`; the tracked LSP `plugin.json` edit
    REVERTED (ai/ clean now -- LSP fix kept only in the per-machine untracked cache copy, no more
    stash-dance); `pwiz-perfbase` worktree exists (parked on a bisect commit).

- 2026-07-04: **REGRESSION FIXED** (pwiz branch `c9d47d6f1`, `Pass2FdrSidecar.cs` + test). Root
  cause was NOT the first pass (that was healthy: 66,857 passing) -- it was the **second pass
  (Stage 7)**. Stage 6 reconciliation appends ~278 interleaved gap-fill rows/file and
  `WriteScoresParquet` re-sorts + re-indexes the reconciled parquet, so the compacted stubs' stale
  Stage-4 `ParquetIndex` no longer addressed their own reconciled row -- `Pass2FdrSidecar` bound
  ~55% of entries to a NEIGHBOR's PIN features -> SVM trained on wrong features -> discovery set
  halved. Straight-through only (HPC reloads stubs from the reconciled parquet, so its ParquetIndex
  matched). Fix: map second-pass features by **stable identity (entry_id, charge, scan_number)**
  (`MapFeaturesByIdentity` + `LoadReconciledFeaturesByIdentity`), still one reconciled parquet at a
  time -> memory bound intact, Phase 1 nulling kept. GATES (verified independently): build clean,
  Osprey.Test **448 pass** (+ new `TestMapFeaturesByIdentity`), **regression Stellar mode1/2/3 PASS**
  (byte-identical golden/HPC/resume), Stellar **25,663 -> 59,768**, blib 21.9MB -> 52.5MB.
- 2026-07-04: **The golden was NOT stale after all** -- mode1 passing byte-identically means the
  committed golden (59,768, last written #4335) IS the correct current reference; it was correctly
  FAILING because the branch had regressed (the "13-commits-behind, needs refresh" read was wrong --
  #4337/#4347/Phase 4 turned out byte-neutral on Stellar). **NO golden refresh needed.** Good thing
  we discarded the `-CreateGolden` capture of the broken 25,663 output instead of committing it.
- **Step (b) UNBLOCKED** -- the branch is correct again; the minimal-projection streaming join can
  resume on a sound baseline. Re-pin `pwiz-perfbase` to `c9d47d6f1` before step (b)'s perf gate.

- 2026-07-04: **STEP (b) DESIGN complete** (`C:\Dev\ai\.tmp\step-b-design.md`). Key reframes:
  the join peak is a STACK of co-resident O(N) structures (FdrEntry buffer + full PercolatorEntry
  list w/ psm_id strings + q-value arrays + results list + resultMap), not one 520 B object -- so
  step (b) collapses the whole stack. Honest process-peak floor: ~9 GB (aggressive) to ~22 GB
  (conservative), NOT 4 GB (lib alone 4-6 GB). Corrections: projection must also carry
  `CoelutionSum` (best-per-precursor ranks on it pre-Score) -> ~28 B drive set; `peptide_id` MUST
  be assigned in `Ordinal`-sorted order (SubsampleByPeptideGroup sorts groups ordinally,
  `PercolatorFdr.cs:2384`). Reload boundary already exists (`RescoreHydration.HydrateReconciliationOverlay`)
  -> straight-through converges onto the resume/HPC path modes 2/3 validate at 1e-9, so **Stage 6/7
  untouched** (small blast radius).
- 2026-07-04: **SCALING is the real driver** (per Mike): 80 files is SMALL; 300-400 typical, 1500
  done. Projection is O(total entries) so per-entry size = the file-count ceiling. (ii)'s ~88 B fits
  82f@~22 GB but 400f -> ~85 GB; **must reach (iii) ~44 B, ideally (iv) ~28 B, to fit 300-1500 files
  on a modest machine** -- that scaling is the design's whole appeal. **SPEED is a first-class gate:
  run Test-PerfGate + track wall-time at EVERY increment** (perfbase pinned at `c9d47d6f1`), no big
  regressions. Plan: (i) peptide-table + index-zip [no struct] -> (ii) projection struct ~22 GB@82f
  -> (iii) stream 4 sidecar-only q-values ~12 GB -> (iv) peptide-summary protein-FDR + two-phase
  sidecar ~9 GB. Each gated mode1/2/3 + perf. Target: at least (iii), ideally (iv).

- 2026-07-05: **STEP (b) INCREMENT (i) COMMITTED** (pwiz branch `5dde76e66`). Replaced the
  psm_id-string + `resultMap` re-join in first-pass Percolator with a positional index-zip
  (`PercolatorEngine.ApplyPercolatorResults`, count-invariant guard), removed the per-observation
  psm_id string + dead `Id` props. Peptide table DEFERRED to (ii) (would be throwaway scaffolding in
  (i)). GATES: build + Osprey.Test **453 tests, 450 pass**; regression Stellar **mode1/2/3 PASS 1e-9**
  (2nd pass covered via mode3); +2 unit tests incl. one driving the REAL streaming assembler. Perf:
  gate PASSED but noise-dominated this run (untouched stage6 moved +14% -> machine noise floor);
  stage5 -1.8% where the change lives. Est. **-16 to -22 GB transient** at 82 files.
- 2026-07-05: **DIRECT-vs-STREAMING measured** (Mike's Q: why keep 2 Percolator paths?). Forced
  streaming on Stellar via temp `OSPREY_FORCE_STREAMING` override (reverted). Result over 3
  interleaved reps: **direct 3:54 median == streaming 3:54 median** (~2%, within noise) and
  **byte-identical** (all forced-streaming runs mode1-vs-golden PASS, blib 52,514,816 B identical).
  **CORRECTION (2026-07-05, standardizer verification):** the "byte-identical / safe to collapse"
  conclusion below was WRONG -- it was a DEGENERATE case. Stellar's 1st pass has ~one observation
  per precursor, so best-per-precursor dedup is a no-op and the streaming subset == the full set,
  making streaming coincide with direct. It does NOT generalize. Direct and streaming differ in TWO
  Rust-matched ways: (i) the feature **standardizer** is fit on ALL entries in direct
  (`PercolatorFdr.cs:284`) vs the best-per-precursor **subset** in streaming (`PercolatorEngine.cs:694`/
  `:924`); (ii) scoring is held-out CV folds + Granholm calibration (direct) vs a single averaged
  model, no calibration (streaming). Rust switches at `pipeline.rs:5748` and fits the same two ways
  (`percolator.rs:191` "global" vs `pipeline.rs:5985` subset). So for a MULTI-observation population
  (real multi-file, and the 2nd pass) subset (subset) full and every score diverges -- which is exactly
  why the always-stream attempt (increment A) broke Stellar's 2nd pass. **Keep the 600K size-dispatch
  -- it is required for Rust parity, NOT an incidental artifact.** Unifying to one path is a cross-impl
  algorithmic decision (changes the Stellar oracle + breaks Rust parity in one regime + trades
  small-data quality vs memory) -- filed as **[#4375](https://github.com/ProteoWizard/pwiz/issues/4375)**,
  not a mechanical cleanup. Legacy-streaming and projection-streaming (iii) fit the SAME subset -- iii
  is faithful, no bug. Guarded permanently by the multi-observation red-guard test
  `TestProjectionRunPercolatorFdrMatchesFdrEntry` (`FdrTest.cs:681`).

- 2026-07-05: **STEP (b) INCREMENT (ii) COMMITTED** (pwiz branch `e2fe78a32`, 9 files +1514/-134,
  new `Osprey.Core/FdrProjection.cs`). `readonly struct FdrProjection` (**80 B**: EntryId+ParquetIndex
  +PeptideId+FileIdx+Charge+IsDecoy=16, + 8 f64 incl. CoelutionSum f64 + Score + 6 q-values). Built at
  the load choke point with ordinal-sorted `peptide_id` (risk #1); routes first-pass Percolator +
  protein-FDR + sidecar + compaction; **releases FdrEntry stubs before the SVM peak**; reloads full
  survivors via existing `RescoreHydration.HydrateReconciliationOverlay` (risk #9), Stage 6/7 UNCHANGED.
  **Feature-flagged `OSPREY_FDR_PROJECTION`, OFF by default** (legacy = oracle). GATES: build +
  **457 tests/454 pass/0 warn** (+4 new incl. end-to-end SVM equivalence); **mode1/2/3 PASS 1e-9 in
  BOTH flag states** (+ I independently re-ran flag-ON mode1, PASS, blib 52,514,816 B identical);
  **Test-PerfGate -0.2% total, stage5 -1.9%** (survivor-reload I/O negligible).
  - MEMORY: 82f first-pass peak **~95 -> ~60 GB (fits 64 GB)**; 400f projection alone ~74 GB.
  - **HONEST CAVEAT / what's left:** (ii) kept the parity-locked SVM core byte-for-byte, so the
    transient stack (`PercolatorEntry` list + q-value arrays + `results`, ~230 B/entry) still
    co-exists WITH the projection DURING `RunFdr` -> ~60 GB not the idealized ~22 GB. **Reaching
    ~22 GB AND fitting 300-1500 files requires (iii)/(iv): collapse that transient stack (make
    `ScorePopulationAndComputeFdr` consume the projection in place) + shrink the struct (stream the
    4 sidecar-only q-values -> ~44 B, then peptide-summary protein-FDR + two-phase sidecar -> ~28 B).**
    (iii)/(iv) touch the byte-parity-locked SVM core -> higher risk, need fresh care + the Astral leg.

- 2026-07-05: **STEP (b) INCREMENT (iii) COMMITTED** (pwiz branch `96ac54406`, 3 files +591/-57).
  Collapsed the transient SVM stack on the projection STREAMING path: no full-population
  `PercolatorEntry` / `PercolatorResult` list -- score + competition run over the projection rows in
  place, q-values written straight back. The PEP/q-value math was extracted VERBATIM into a shared
  `PercolatorFdr.ComputeStreamingCompetitionQvalues` called by BOTH the legacy and projection scorers
  (one source of truth -> parity-locked ordering can't drift). GATES: build + **458 tests/455 pass/0
  warn** (+`TestProjectionStreamingMatchesFdrEntryStreaming`); **mode1/2/3 PASS both flag states**;
  perf **-1.9%** (faster). **I independently verified the STREAMING collapse end-to-end** by forcing
  Stellar through the streaming projection path (temp `OSPREY_FORCE_STREAMING` override, reverted) +
  `OSPREY_FDR_PROJECTION=1` -> mode1 PASS, blib 52,514,816 B identical (Stellar default is DIRECT, so
  mode1/2/3 alone don't exercise (iii)'s change -- this closes that gap).
  - MEMORY: transient ~239 -> ~95 B/entry; **82f process peak ~65 -> ~38 GB**. Residual ~95 B/entry
    flat math arrays remain (lowering needs columnar/SoA of the parity-locked signatures = higher
    risk, deferred). **400f still ~162 GB (the 80 B struct buffer dominates) -> (iv) required.**
- **NEXT (per Mike): FIRST LARGE-DATASET MEMORY VALIDATION** now that a large run is viable (~38 GB
  @ 82f). Run the 82-file Carafe set with `OSPREY_FDR_PROJECTION=1` + `OSPREY_LOG_MEMORY=1`, parse
  [MEM] for the actual first-pass peak, confirm ~38 GB (vs legacy ~65 GB) -- the empirical proof.
  Multi-hour (full scoring + join); no fast join-only path (not all 82 valid parquets on disk). THEN
  (iv): stream the 4 sidecar-only q-values (-> ~44 B) + peptide-summary protein-FDR + two-phase
  sidecar (-> ~28 B) for the 300-1500-file scale.

- 2026-07-05: **VALIDATION-RUN FINDING + SCOPE SPLIT.** First large-dataset run (40 Carafe files,
  flag ON, `OSPREY_LOG_MEMORY`) shows scoring is BOUNDED/flat (step (a) works) but the plateau is
  **~50-60 GB WS**, because the **3.17M-entry library is ~18-20 GB resident** (file-1 heap 26.5 GB is
  mostly library) -- much bigger than the design's ~5 GB assumption. So the projection correctly moved
  the JOIN below scoring (legacy ~100 GB join -> ~57 GB overall), but the **library/scoring plateau is
  now the ceiling**, which the join projection cannot touch. **Split to a SEPARATE issue+TODO:
  ProteoWizard/pwiz#4372 / `TODO-20260705_osprey_library_resident_memory.md`** (memory-map / page /
  don't-hold-full-target+decoy library). #4355 stays the JOIN lever; #4372 the library/scoring lever.
  (40-file run still in progress; join-peak extrapolation to 82/400/1500 pending via the periodic check.)

- 2026-07-05: **FIRST LARGE-DATASET VALIDATION** (40-file Carafe, `OSPREY_FDR_PROJECTION=1`,
  `OSPREY_LOG_MEMORY`, 92,850,667 entries / 2,262,311 distinct peptides). Empirical peaks:
  - **Scoring: BOUNDED/flat** (step (a) confirmed on real data) -- ~45 GB heap / **~64.8 GB WS**
    plateaued from file 11, zero creep across all 40 files.
  - **First-pass FDR join: steady ~35 GB heap, but PEAK ~43.7 GB heap / 57.6 WS** at
    `[MEM projection built ... FdrEntry stubs released]` -- the cold FdrEntry stubs + the projection
    **co-exist transiently** (~235 B/entry) before the stubs are released. After `CompactFirstPass`:
    22.5 GB heap (library + survivors).
  - **Reconciliation (Stage 6): WS ~67 GB (climbing)** -- a NEW peak ABOVE scoring. The memory
    ceiling is shifting OFF the first-pass join onto scoring/library (#4372) and reconciliation.
  - Extrapolation (join peak ~43.7, ~22 GB fixed library): 82f **~66 GB** (borderline/over 64 at the
    spike; ~half of legacy ~100 GB); 400f/1500f far over -> **(iv) + #4372 required** for real scale.
  - **OPTIMIZATION to fold into (iv) (Mike agreed):** build the projection and **release the FdrEntry
    stubs INCREMENTALLY per file** (as each file's projection rows are built) instead of all-at-once
    -> removes the ~43.7 GB stubs+projection coexistence spike, dropping the first-pass peak toward
    the steady ~35 GB (projection-only footprint). Cheap, high-value.
  - Reconciliation (Stage 6) WS ~67 GB is worth its OWN look (separate from #4355/#4372) if it proves
    the true ceiling once scoring/join are bounded.

- 2026-07-05: **40-file run COMPLETED** (blib 228.7 MB, NO OOM on 94 GB) -- but the run revealed the
  **TRUE memory ceiling is Stage 6/7 (reconciliation + 2nd-pass FDR) at ~79-80 GB WS**, ABOVE the
  scoring plateau (~64.8) and the first-pass join (~57.6) that #4355 optimized. So #4355 fixed a real
  ~100 GB stage but not the tallest pole on this dataset. Root cause (confirmed -- Mike's insight):
  the **2nd-pass Percolator holds all survivor features RESIDENT** (`Pass2FdrSidecar`:
  `LoadReconciledFeaturesByIdentity` -> `MapFeaturesByIdentity` sets `entry.Features` resident on the
  full `FdrEntry` survivor buffer; calls `FirstJoinTask.RunPercolatorFdr(..., "Second-pass")` with
  `loadFileFeatures = null`) -- NOT the 1st-pass streaming+projection (increment iii). Same Percolator
  engine, two memory strategies, not standardized. Plus reconciliation (Stage 6) heavy CWT/gap-fill;
  NO `[MEM]` anchors in Stage 6/7. **Filed ProteoWizard/pwiz#4374** (standardize 2nd pass to the
  1st-pass streaming/300K/projection method + instrument Stage 6/7).
- **MEMORY-CEILING MAP (40-file empirical):** scoring ~64.8 WS (#4372 library floor) < first-pass
  join ~57.6 WS / 43.7 heap (#4355, DONE i-iii; (iv) + incremental stub release remaining) <
  **Stage 6/7 ~79-80 WS (#4374, the current ceiling)**. Three independent levers -- #4355+(iv),
  #4372, #4374 -- all needed to fit 300-1500 files on a modest machine.

- 2026-07-05: **Increment (A) = #4374 2nd-pass streaming COMMITTED (`90b773b84`).** Routed
  `Pass2FdrSidecar` through the shared projection `RunPercolatorFdr` (streams reconciled features by an
  identity-baked `ParquetIndex` = reconciled-parquet row, via `BuildReconciledIdentityToRow`) instead
  of holding all survivor features resident. Kept the 600K direct/streaming size-dispatch on BOTH
  passes -- an attempt to always-stream (Mike's "one strategy") broke Stellar's 2nd pass and is
  genuinely impossible byte-identically: direct fits the SVM standardizer on ALL entries + CV/Granholm
  calibration, streaming on the best-per-precursor SUBSET + averaged model, and Rust switches at the
  same threshold (`pipeline.rs:5748`). Filed **[#4375](https://github.com/ProteoWizard/pwiz/issues/4375)**
  for the future one-path unification (cross-impl decision: changes the Stellar oracle + Rust parity).
- 2026-07-05: **(A) byte-identity was hard-won -- three false alarms, all cache/measurement artifacts.**
  (1) A first 8-file Carafe scale A/B (flag-ON projection vs flag-OFF legacy) showed 10 RT/peak-only
  diffs (~0.05%; FDR scores byte-identical). (2) Determinism check: two legacy runs are
  content-identical (0 issues) -- NOT non-determinism. (3) A code bisect attributed it to (A)'s
  scan-omitted 2nd-pass sort. (4) But a CLEAN re-run (clearing FDR+reconciliation intermediates before
  EACH path so neither reuses the other's reconciled parquets) gave **0 issues** -- the divergence was a
  **cache-contamination artifact** (flag-OFF reusing flag-ON's reconciliation / stale validate-40 state),
  not a real bug. Confirmed with a **second** independent clean run (0 issues, blib 69,566,464 both).
  LESSON: for any scale A/B, clear per-file FDR+reconciliation intermediates first, every time.
- 2026-07-05: **(A) gates all green:** Stellar mode1/2/3 byte-identical (flag OFF oracle + flag ON ==
  golden 52,514,816); scale byte-identical x2 (clean 8-file Carafe); build+tests 460/457 (0 warnings)
  incl. new guard `TestScanOmittedProjectionSortMatchesLegacyOrder` (`Pass2FdrSidecarTest.cs:129`,
  asserts scan-omitted projection order == legacy scan+original-index order through the real Stage-6
  chain, PASS -- and genuine scan-ties don't even arise, `DeduplicatePairs` removes them); perf
  flag-ON vs flag-OFF Stellar 3-rep median 06:00 vs 05:57 (**+0.8%, neutral**).
- **NEXT: increment (iv)** (memory shrink, NOT started): (B) incremental per-file stub release (kills
  the ~43.7 GB first-pass "projection built" spike); (C1) 2nd-pass `FdrProjection` struct 80->~28 B
  (single-phase, easy); (C2) 1st-pass struct ->~28 B (two-phase tail). Then #4372 (library floor).

## Handoff prompt

Fixing O(N) memory in Osprey multi-file runs (issue #4355). Root cause: heavy `FdrEntry`
arrays already spilled to parquet stay resident for all N files. Start at Phase 0
(instrument + measure baseline), then Phase 1 (null-after-spill + rehydrate, audit every
consumer of `Features`/`CwtCandidates`/`Fragment*`/`ReferenceXic*`). Gate on
`regression.ps1` (byte-identical) + a `ProfilerHooks` measurement showing <64 GB for ~80
files. Rust reference (frozen) at `D:\GitHub-Repo\maccoss\osprey`.
