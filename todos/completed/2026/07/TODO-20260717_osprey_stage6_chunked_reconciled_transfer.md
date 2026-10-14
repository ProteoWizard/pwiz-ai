# TODO: Osprey Stage-6 chunked reconciled transfer (stream the reconciled round-trip)

**Status**: Completed.
**PR**: [#4433](https://github.com/ProteoWizard/pwiz/pull/4433) (merged 2026-07-17 as 3086197)
**Branch**: `Skyline/work/20260717_osprey_stage6_chunked_reconciled_transfer`
**Base**: `master`
**Priority**: High -- this is the HALF THAT ACTUALLY BOUNDS STAGE 6. #4430 chunked the
Parquet *write* (so the original is multi-row-group); this chunks the Stage-6 *transfer*
that reloads it. The original night session was meant to deliver BOTH; #4430 is only part 1.
**Complexity**: Medium-High (the streaming read->overlay->write is mechanical; the real
gate is the reconciled byte-parity contract, decided empirically by regression mode3).
**Created**: 2026-07-17
**Scope**: `pwiz_tools/Osprey/Osprey.Tasks/ReconciledParquetWriter.cs` (`Write`),
`pwiz_tools/Osprey/Osprey.IO/ParquetScoreCache.cs` (a new streaming writer + a per-row-group
reader; reuse `WriteChunkedParquet`/`BuildRowGroupColumns` column-build + `LoadFullFdrEntries`
per-group read).

## Why (measured 2026-07-16/17, PR #4430 diagnostics)

The conversation that started this: could Parquet imitate CSV row-by-row streaming (read one
row, modify, write, release)? **Answer: no row-by-row, but yes CHUNK-by-chunk.** And the only
way Stage 6 improves is if BOTH halves are chunked: (1) the Stages-1-4 WRITE so the original
`.scores.parquet` is multi-row-group (**#4430, done**), and (2) the Stage-6 reconciled
TRANSFER that reloads+rewrites it (**this TODO**).

Chunking the Stages-1-4 write was NOT meant to lower Stage 1-4's own peak (it didn't:
WS 15.64 -> 15.0). Its target was **Stage 6**: a multi-group original lets Stage 6 read it back
in chunks. Diagnostic A/B (single-file Astral 49, `--task PerFileRescoring`, only variable =
original's row-group count):

| Stage-6 metric | 1-group original (pre-#4430) | 17-group original (#4430 shape) |
|---|---|---|
| working-set peak | 13.09 GB | **11.12 GB (-2.0 GB)** |
| last-GC heap | 7.28 GB | **6.07 GB (-1.2 GB)** |

That -2 GB is only the read **transient**. A reload/write-boundary [MEM] probe showed the
reload is a discrete **+3.6 GB WS / +4.4 GB managed step** (`LoadFullFdrEntries` materializing
the whole 1.68M-entry `List<FdrEntry>` + its per-entry blob arrays), the overlay adds **0**
(in-place), and the write adds only **~2 GB**. So the Stage-6 peak is driven by the RELOAD,
and the **~4.4 GB resident `fullEntries` list is the prize this TODO removes** by never
materializing the whole file.

## Current code (the thing to replace) -- `ReconciledParquetWriter.Write`

1. `fullEntries = LoadFullFdrEntries(original)` -- loads ALL rows (the +4.4 GB step).
2. `ApplyRescoredRows(fullEntries, fdrEntries)` -- overlays the rescored subset in place by
   `ParquetIndex`, APPENDS gap-fill rows (ParquetIndex == uint.MaxValue) at the end.
3. `WriteScoresParquet(reconciledPath, fullEntries, ...)` -- RE-SORTS by
   `(entry_id, charge, scan_number)` and writes (now chunked by #4430, but fed the whole list).

## The fix -- stream the transfer group-by-group

- Build the small resident maps ONCE from `fdrEntries`: `overlayByIndex` = { origParquetIndex ->
  rescored FdrEntry } (entries with `Features != null` && `ParquetIndex != MaxValue`, ~65K for
  file 49); `gapFill` = entries with `ParquetIndex == MaxValue` (small).
- Open the original reader + the output writer. Track a running global row index.
- For each ORIGINAL row group g (in order): read that group's `FdrEntry` rows (per-group body
  of `LoadFullFdrEntries`); for each row whose running index is in `overlayByIndex`, swap in the
  rescored entry; write the group to the output as a row group; RELEASE it.
- Append `gapFill` as final row group(s) (chunk at `MAX_ROWS_PER_ROW_GROUP` if large).
- Residency: O(one original row group) + overlayByIndex (~65K) + gapFill -- NOT O(all rows).

Reuse: extract a `BuildFdrEntryColumns(IReadOnlyList<FdrEntry>, libraryById, fileName,
featureFields)` from the `WriteScoresParquet(FdrEntry)` chunk callback, and a
`ReadFdrEntryGroup(reader, g, ...)` from `LoadFullFdrEntries`. A streaming
`ScoresParquetWriter` (open/WriteGroup/Commit) wraps `FileSaver + ParquetWriter`. Note:
`ParquetIndex` is NOT a stored column -- it is re-derived on read as a running count -- so the
reconciled write need not preserve any specific ParquetIndex.

## THE KEY DECISION: gap-fill ordering (decide empirically)

Current output is fully sorted `(entry_id, charge, scan)` with gap-fill INTERLEAVED (the
re-sort in step 3). Streaming original-groups-then-appended-gap-fill puts gap-fill AT THE END.
Since the original rows are already sorted and overlay preserves the sort key, the ONLY
difference is gap-fill position.

- **Byte-parity contract is already settled (from #4430): NO gate compares `.scores.parquet`
  bytes** (regression + cross-impl compare the blib + Stage-7 protein-FDR at 1e-9), and
  ParquetIndex is re-derived on read. So the reconciled physical order matters only if a
  downstream consumer (SecondPassFDR / MergeNodeTask) relies on it.
- **Plan:** implement the SIMPLE append-first version, then run `regression.ps1 -Dataset All`
  **mode3** (HPC 4-task chain = Stage-6 rescore -> SecondPassFDR -> blib), the byte-identity
  oracle. If the blib stays byte-identical, append is correct + simplest. If NOT, add a
  streaming k-way merge: [original groups streamed in sorted order] merge-with [resident
  `gapFill` sorted by (entry_id,charge,scan)] -> reproduces the exact interleaved order.
  (`[[feedback_bit_parity_tolerance]]`: don't loosen the gate; make the output match.)

## Gates
- `regression.ps1 -Dataset Stellar` (fast) then `-Dataset All` -- mode3 is critical.
- `Build-Osprey.ps1 -RunTests -RunInspection`. Add a unit test: streaming reconciled transfer
  of a multi-group original == the old load-all+overlay+write output (logical rows), incl.
  gap-fill.
- Memory A/B (single-file `--task PerFileRescoring`, Astral 49, multi-group original): the
  **+4.4 GB reload step should vanish** (residency ~one group). Re-add the reload/write-boundary
  [MEM] probes to confirm.

## Reuse / references
- **PR #4430** (bounded row-group WRITE): `[[TODO-20260716_osprey_parquet_bounded_rowgroup_write]]`
  -- fix (a). This TODO is fix (b), broken off per Brendan (2026-07-17) to keep #4430 mergeable.
- Diagnostic data + harness: `ai/.tmp/agent-loh-results.md`, `ai/.tmp/agent-memperf-results.md`,
  `ai/.tmp/loh-diag.ps1`; the reload/write-boundary [MEM] probe diff is in `agent-loh-results.md`
  (reverted from #4430's branch; re-add on implementation).
- dotMemory dumps (Astral 49): AFTER (single-group reload) `_memperf_night\rescore-base-20260716-231617\rescore-after-*.dmw`;
  multi-group reload `_lohdiag_night\loh-rescore-caseB-20260717-063527.dmw`. Diff apex dominators
  to see the reloaded `fullEntries` set this TODO removes.
- Sibling (larger, per-window scored-entry streaming for PerFileScoring):
  `[[TODO-osprey_perfile_scored_entry_streaming]]`.
- Memory: `[[feedback_bit_parity_tolerance]]`, `[[project_osprey_parity_removal_sprint]]`.

## Progress (2026-07-17)

**Implemented -- streaming k-way merge (NOT append-first).** The KEY DECISION above
was resolved without needing the full `-Dataset All` mode3 run: the existing unit test
`Pass2FdrSidecarTest.TestScanOmittedProjectionSortMatchesLegacyOrder` hard-asserts that
gap-fill *interleaves by scan* in the reconciled parquet, because Pass 2's projection
sort recovers scan order from the reconciled row index. So append-at-end is observably
wrong; the streaming 2-way merge (original groups streamed in sorted order, merged with
the resident `gapFill` sorted by (entry_id,charge,scan), ties keep the original first to
match the stable `WriteScoresParquet` re-sort) was required. The merge reproduces the
former load-all + re-sort physical order byte-for-byte.

Changes:
- `Osprey.IO/ParquetScoreCache.cs`: extracted `BuildFdrEntryColumns` (from the
  `WriteScoresParquet(FdrEntry)` chunk callback) and `ReadFdrEntryGroup` (per-group body
  of `LoadFullFdrEntries`, which now loops it); added public
  `StreamReconciledScoresParquet` (streaming read -> overlay -> merge -> bounded-group
  write) + `KeyLess`. Residency is one original row group + the overlay map + gap-fill,
  never the whole `List<FdrEntry>`.
- `Osprey.Tasks/ReconciledParquetWriter.cs`: `Write` now builds the overlay map + gap-fill
  list via the new pure `BuildOverlay` (replaces `ApplyRescoredRows`) and calls the
  streaming transfer; out-of-range warning moved into the IO method. `FirstJoinTask.cs`
  comment updated (`ApplyRescoredRows` -> `BuildOverlay`).
- Tests: `ReconciledParquetWriterTest` now tests `BuildOverlay`; `IOTest` adds
  `TestStreamReconciledTransferMatchesLoadAllOverlay` (multi-group round-trip ==
  load-all+overlay, canonical physical order, out-of-range warning, overlay effect);
  `Pass2FdrSidecarTest` harness rebuilt on the streaming path.

Gates passed: `Build-Osprey.ps1 -RunTests -RunInspection` green (513 tests, zero-warning
inspection); `regression.ps1 -Dataset Stellar` mode1 (vs golden) / mode3 (HPC chain) /
mode2 (resume) all PASS -- blib byte-identical (45,064,192 bytes) across all three.

Remaining: `Test-PerfGate.ps1 -Dataset Stellar` (speed A/B); `-Dataset All` Astral legs via
the TeamCity Perf/Regression config (Brendan-gated); `/pw-self-review` + PR. The `.gitignore`
nested-nuget fix (`**/.nuget/.nuget/`) is folded into this branch/PR per Brendan.

## Memory investigation conclusion (2026-07-17) -- MOTIVATION REFRAMED

The max-RSS motivation in "Why" above is **largely invalidated by measurement.** Memory
A/B (single-file Astral case B) + dotMemory showed the reconciled-write peak is NOT the
managed reload -- it is **Server-GC committed-but-free managed heap** left after the
scoring Gen-0 burst (dotMemory paints it "unmanaged" gray; native is ~0.8 GB). See
`[[project_osprey_pipeline_peak_is_servergc_retained_committed]]` for the proof
(`gc_committed 9.80` vs `gc_heap 3.55`; compacting GC collects but does not decommit;
`DOTNET_GCConserveMemory=9` decommits at 3x GC cost). The streaming transfer moved the
dotMemory peak only 11.34 -> 10.43 GB and #4430 only shaved the read transient -- neither
touched the ~9 GB retained floor.

**Decision (Brendan, 2026-07-17): KEEP + finish the PR on its real merits** -- byte-identical
output (regression mode1/2/3 green), ~1.5 GB less managed churn per file (helps the
`--threads` commit scaling, the one place memory is a real wall), and simpler code (no
whole-file `List<FdrEntry>` materialization). It is NOT a max-RSS fix; do not claim one in
the PR. The real per-worker peaks are separate backlog items:
`[[TODO-osprey_perfilescoring_calibration_memory_peak]]` (15.5 GB) and
`[[TODO-osprey_firstpassfdr_memory_peak]]`.

### 2026-07-17 - Merged

PR #4433 merged (squash) as commit 3086197. Shipped the streaming k-way-merge Stage-6
reconciled transfer (byte-identical, regression mode1/2/3 green), plus a monotonic-key
hard-fail guard against non-canonical output (self-review Findings 1+2) and the nested
`**/.nuget/.nuget/` gitignore. Self-review + both Copilot doc threads resolved; Stellar
perf gate green (exit 0). DEFERRED (small, noted on the PR): self-review Finding 3
(single-group residency docstring caveat) and Finding 4 (a unit test that the guard
FIRES on a scan-moving overlay crossing a same-(entry_id,charge) sibling). The max-RSS
motivation was reframed to byte-identity + managed-churn (see the section above); the
real per-worker peaks moved to the two backlog TODOs. `pwiz-perfbase`/TeamCity Astral
were green at merge.
