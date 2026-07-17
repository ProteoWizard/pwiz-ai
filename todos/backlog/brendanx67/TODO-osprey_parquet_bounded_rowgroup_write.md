# TODO: Osprey bounded row-group Parquet write (cap the end-of-file write tail)

**Status**: Backlog (start immediately after the Stage-6 spectra-streaming PR
`Skyline/work/20260716_osprey_stage6_rescore_spectra_streaming` squash-merges).
**Priority**: Medium-High -- once the resident MS2 is streamed (Stage-6 PR), the
Parquet write is the tallest remaining per-file peak in BOTH PerFileScoring and
PerFileRescoring.
**Complexity**: Medium (the writer chunking is mechanical; the reconciled
streaming round-trip is moderate; the real gate is the Parquet byte-parity
contract, shared with the scored-entry-streaming TODO).
**Created**: 2026-07-16
**Scope**: `pwiz_tools/Osprey/Osprey.IO/ParquetScoreCache.cs`
(`WriteScoresParquet` x2, `BuildRowGroupColumns`, `WriteRowGroupColumns`,
`LoadFullFdrEntries`), `pwiz_tools/Osprey/Osprey.Tasks/ReconciledParquetWriter.cs`
(`Write`), `pwiz_tools/Osprey/Osprey.Tasks/PerFileScoringTask.cs` (the write path).

## Motivation (measured, 2026-07-16)

The Stage-6 spectra-streaming PR removed the ~6 GB resident MS2 from the rescore
peak (working-set peak 29.8 -> 14.1 GB on Astral file 49). Reading the AFTER
dotMemory timeline (`D:\test\osprey-runs\_stage6mem\stage6-rescore-after-20260716-191611.dmw`,
the new `perfile-rescore-apex` snapshot), the **tallest remaining peak is a
staircase ramp at the very end during the Parquet write-back**:

- The scoring itself (subset re-score + gap-fill) is the blue gen-0 sawtooth,
  ~7-8 GB.
- The END ramp climbs to **~14 GB total but only ~3.5 GB .NET managed** -- so
  **~10 GB is UNMANAGED** (Apache.Arrow + IronCompress native buffers), plus
  growing gen-2 + LOH. It ramps up over the last ~25 s and is retained, not churn.

**Brendan observed the SAME clear tail in the PerFileScoring profile** during its
`WriteScoresParquet`. So this is one shared write-path characteristic, not a
rescore-only quirk.

## Root cause (verified against the code)

Parquet is **columnar**, organized into **row groups**; a single logical row's
fields are physically scattered across separately-compressed column chunks. So the
streaming unit is the **row group**, NOT the row -- the writer must buffer a whole
group's columns, compress each, and flush the group. Osprey writes the **entire
file as ONE giant row group**, so there is nothing to stream today:

- `ParquetScoreCache.WriteScoresParquet` (both overloads: `CoelutionScoredEntry`
  at `:182`, `FdrEntry` at `:299`) opens a SINGLE `writer.CreateRowGroup()`
  (`:466`, no loop) for all `n` rows. `BuildRowGroupColumns` (`:491`) first
  materializes every column array for ALL n rows -- including the heavy blob
  columns `fragment_mzs` / `fragment_intensities` / `reference_xic_*` /
  `cwt_candidates` as `byte[][]` -- then `WriteRowGroupColumns` (`:534`) Zstd-
  compresses + writes them (IronCompress -> native buffers). So the whole dataset
  is resident (managed column arrays) AND driven through native compression
  buffers at once.
- `LoadFullFdrEntries` (`:944`) already loops `reader.RowGroupCount` and
  accumulates into one `List<FdrEntry>` -- fine structurally, but the file is a
  single group, so it reads everything.
- `ReconciledParquetWriter.Write` (`:54`) is the rescore write-back: it
  `LoadFullFdrEntries(original)` (full reload of every row + blob column),
  `ApplyRescoredRows` overlays the SMALL re-scored + gap-fill subset by
  `ParquetIndex`, then `WriteScoresParquet(all)` writes the whole set back. A
  read-all -> overlay-a-subset -> write-all round-trip that materializes
  everything twice (read buffers + write buffers overlap -> the ~10 GB unmanaged).

## The fix

**(a) Bounded row groups in `WriteScoresParquet` (both overloads).** Loop over the
entries in chunks (e.g. 50-100K rows/group), and per chunk: build only that
chunk's column arrays, `CreateRowGroup()`, write, dispose, release. This caps BOTH
the managed column-array build AND the native compression buffers to one chunk
instead of the whole file. This is the piece the scored-entry-streaming TODO's
step 3 also needs ("WriteScoresParquet from one-shot to row-group append"), done
standalone here so the write tail is capped without the dedup-manifest
rearchitecture.

**(b) Stream the reconciled round-trip in `ReconciledParquetWriter.Write`.** With
the original now multi-row-group, loop over its row groups; per group, apply the
resident (small) `ParquetIndex -> rescored values` overlay for rows in that group,
write the group, release. Append the gap-fill rows as final group(s). Read side
bounded to one group -> drops the full `LoadFullFdrEntries` reload. Residency goes
from O(all rows) to O(one row group) + the tiny overlay map + gap-fill rows --
exactly the "read buffer + write buffer" bound.

Target: the ~14 GB write tail drops toward one row group's worth of buffers.

## THE LOAD-BEARING QUESTION: Parquet byte-parity contract

Row-group chunking changes the **physical** parquet bytes (different chunk
boundaries + independent per-chunk compression) while preserving the **logical**
rows, their order, and `ParquetIndex` positions. Two things must be settled BEFORE
shipping (do NOT loosen a bit-parity gate unilaterally -- `[[feedback_bit_parity_tolerance]]`):

1. **Does the regression golden compare parquet BYTES or just the final blib?**
   The `[[TODO-osprey_perfile_scored_entry_streaming]]` states `{stem}.scores.parquet`
   is compared byte-for-byte vs the C# golden. If so, chunking breaks that golden
   -> needs a deliberate, versioned golden refresh, OR the parity moved to a
   logical (row-set) compare. If regression.ps1 only byte-compares the **blib**
   (the Stage-6 PR run reported only `blib 45,064,192 bytes`), the logical rows are
   unchanged so the blib should stay byte-identical -- confirm which by inspecting
   regression.ps1's compare + running `-Dataset Stellar` mode1/2/3.
2. **Cross-impl vs Rust.** If the C# == Rust parquet-byte gate is still live, Rust's
   row-group sizing would have to match. Parity is slated to break C#-only
   (`[[project_osprey_parity_removal_sprint]]`); sequencing this after the parity
   break removes the constraint entirely. Coordinate with that timeline.

This is the SAME "Parquet byte-parity contract" decision the scored-entry TODO
raises (its options a/b/c) -- resolve it once, for both.

## Gates

- `regression.ps1 -Dataset All` (mode1 golden + mode2 resume + mode3 HPC chain) --
  the byte-parity question above; Astral is the load-bearing leg.
- Memory before/after: `ai/.tmp/stage6-mem.ps1` (rescore write-back tail) and
  `Profile-Osprey.ps1 -MemoryProfile` (PerFileScoring tail) -- quantify the tail
  drop at the `perfile-rescore-apex` / `perfile-scoring` write boundary.
- `Test-PerfGate.ps1` -- chunked writes + streamed reconciled round-trip should be
  perf-neutral-to-faster (less GC pressure, smaller buffers); confirm no regression.

## Relationship to the scored-entry-streaming TODO

`[[TODO-osprey_perfile_scored_entry_streaming]]` is the larger refactor: stream
each isolation window's scored entries out per-window (never accumulate all 1.7M),
with a dedup keep-manifest. This TODO is the **row-group write building block** it
depends on, delivered standalone: it caps the WRITE tail (and the reconciled
round-trip) without the per-window yield / manifest rearchitecture. Sequence this
first; the scored-entry streaming then builds on the incremental writer. Both hinge
on the same Parquet byte-parity decision, so settle that once.

## Explicitly NOT in scope

- The per-window scored-entry streaming + dedup manifest (that is the sibling TODO).
- Structure-of-Arrays for the per-entry payload (a separate, larger refactor noted
  in the sibling TODO).
- GC-config tuning (interim ~10% lever, tracked separately).

## References

- Measurement: `D:\test\osprey-runs\_stage6mem\stage6-rescore-after-20260716-191611.dmw`
  (`perfile-rescore-apex` snapshot: ~14 GB total / ~3.5 GB .NET -> ~10 GB
  unmanaged); harness `ai/.tmp/stage6-mem.ps1`.
- Code: `ParquetScoreCache.cs:182`/`:299` (WriteScoresParquet), `:466`
  (single CreateRowGroup), `:491` (BuildRowGroupColumns), `:534`
  (WriteRowGroupColumns), `:944` (LoadFullFdrEntries);
  `ReconciledParquetWriter.cs:54` (Write) `:64` (LoadFullFdrEntries reload) `:90`
  (WriteScoresParquet rewrite). Parquet stack: Parquet.Net + Apache.Arrow +
  IronCompress (`build.ps1:241`).
- Sibling lever: `[[TODO-osprey_perfile_scored_entry_streaming]]`.
- Predecessor: the Stage-6 spectra-streaming PR
  (`ai/todos/active/TODO-20260716_osprey_stage6_rescore_spectra_streaming.md`).
- Memory: `[[feedback_bit_parity_tolerance]]`,
  `[[project_osprey_parity_removal_sprint]]`,
  `[[reference_osprey_resident_firstpass_streams_features]]`.
