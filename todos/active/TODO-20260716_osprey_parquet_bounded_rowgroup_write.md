# TODO: Osprey bounded row-group Parquet write (cap the end-of-file write tail)

## Branch Information
- **Branch**: `Skyline/work/20260716_osprey_parquet_bounded_rowgroup_write`
- **Base**: `master` (post-#4429 Stage-6 merge `d4b7ad54b`)
- **Created**: 2026-07-16
- **Status**: In Progress
- **PR**: [#4430](https://github.com/ProteoWizard/pwiz/pull/4430)

**Status**: Active (started 2026-07-16; predecessor Stage-6 PR
[#4429](https://github.com/ProteoWizard/pwiz/pull/4429) merged as `d4b7ad54b`).
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

## Progress Log

### 2026-07-16 (session start: branch cut, load-bearing parity question RESOLVED)
Branch `Skyline/work/20260716_osprey_parquet_bounded_rowgroup_write` off master
`d4b7ad54b` (#4429 Stage-6 merge). TODO backlog -> active.

**THE LOAD-BEARING QUESTION (Parquet byte-parity contract) -- RESOLVED read-only,
BEFORE any code.** Verdict: **NO gate byte-compares `.scores.parquet`.** Row-group
chunking changes physical parquet bytes but preserves logical rows, their global
sort order, and `ParquetIndex` -> every gate stays green with NO golden refresh and
NO Rust row-group-size matching. Evidence (airtight, four independent angles):

1. **regression.ps1 (mode1/2/3)** compares the **blib SQL content + Stage-7 protein
   FDR dump at 1e-9**, never parquet bytes (SYNOPSIS lines 16-36 authoritative;
   mode1 = text golden `osprey-regression.data`, mode2/3 = blib-vs-blib at 1e-9).
   Per-stage parquet compare exists ONLY as a red-gate bisection tool
   (`Compare-Stage7-Rehydration-Strict-CSharp.ps1`), not a first-line gate.
2. **Committed golden `osprey-regression.data/`** contains ONLY `.tsv` table dumps
   (blib SQL tables + `protein_fdr.tsv` + `blib_summary.tsv`) -- **zero `.parquet`**.
3. **Cross-impl Rust gate** (`Compare-EndToEnd-Crossimpl.ps1` + `Compare/README.md`)
   compares **Stage-7 protein FDR + blib SQL at per-column 1e-9**; grep shows zero
   parquet `Get-FileHash`/byte hashing. `Regression/` helpers: zero
   `Get-FileHash`/`SequenceEqual`/`.parquet` references at all.
4. **Unit tests**: every `byte-for-byte`/`ReadAllBytes`/`CollectionAssert.AreEqual`
   assertion in `IOTest.cs` targets `FdrScoresSidecar` (`.fdr_scores.bin`),
   `.spectra.bin`, or `.libcache` -- NOT parquet. The parquet tests
   (`ReconciledParquetWriterTest`, `Pass2FdrSidecarTest`) assert LOGICAL content
   (EntryId/ParquetIndex/counts/metadata), not bytes -- e.g.
   `ReconciledParquetWriterTest:82 Assert.AreEqual(3u, gapFill.ParquetIndex)` pins
   the exact invariant chunking preserves.

**Corrects the sibling `[[TODO-osprey_perfile_scored_entry_streaming]]`**, whose
"Open decision" section claims `.scores.parquet` "is compared **byte-for-byte** vs
the C# golden (regression.ps1) and cross-impl vs Rust." That is factually wrong:
the gate is already a LOGICAL compare (blib + protein-FDR at 1e-9). So that TODO's
options (a)/(b)/(c) collapse -- "(a) logical compare" is ALREADY the reality; no
manifest-parity contract change or golden refresh is needed for either TODO's
physical parquet-layout change. (The `ScoringPipeline`/`ParquetScoreCache` code
comments still assert cross-impl "identical physical row layout" intent -- historical
aspiration, NOT enforced by any live gate. Flagged for Brendan.)

**Not a gate loosening** (`[[feedback_bit_parity_tolerance]]`): I am not widening a
comparator or adding a skip-list -- I am confirming the existing gates never
constrained parquet physical bytes. Surfaced to Brendan for explicit go/no-go before
writing the chunking code, given the sibling-TODO contradiction + the code-comment
intent.

**Write-path facts (for the chunking design):** both `WriteScoresParquet` overloads
(`:182` CoelutionScoredEntry, `:299` FdrEntry) materialize ALL n column arrays then
write ONE `CreateRowGroup()` (`:276`/analogous). Rows are emitted in a **global
canonical sort** (`entry_id, charge, scan_number`, `:226`/`:351`); `ParquetIndex` =
post-sort global row position. Chunking = slice that SAME sorted index array into
50-100K-row groups, build+write+dispose per chunk -> identical row sequence and
ParquetIndex, bounded managed + native (IronCompress) buffers. Metadata footer
written once, unchanged. Implementation must audit every parquet reader
(`LoadFullFdrEntries` already loops `RowGroupCount`; verify `LoadPinFeatures*`,
`LoadCwtCandidates*`, and ParquetIndex-based random access in the rescore overlay
all handle multi-row-group + preserve ParquetIndex).

### 2026-07-16 (night session: fix (a) IMPLEMENTED + PR #4430 opened)
**Scope decision:** ship fix (a) bounded 100K-row row groups + an empty-blob->null
robustness fix as this PR; **DEFER fix (b)** (streaming reconciled round-trip) to a
follow-up. Fix (a) already bounds the dominant UNMANAGED tail on BOTH the reconciled
write AND read (`LoadFullFdrEntries` already reads group-by-group, so once the file is
multi-row-group its native Arrow/IronCompress buffers are per-group too). Fix (b) only
targets the residual managed `fullEntries` reload; keep it out of this PR to stay
low-risk for TeamCity. Memory measurement (in flight) quantifies the residual.

**Implemented (commit `5b7199fdb`, pushed):**
- `ParquetScoreCache.WriteChunkedParquet` helper: both `WriteScoresParquet` overloads
  build+compress+flush+release one 100K-row group at a time (`MAX_ROWS_PER_ROW_GROUP`,
  test seam `RowGroupRowCapForTest`). Same global `(entry_id,charge,scan)` sort ->
  identical row order + `ParquetIndex`. `WriteRowGroupColumns` simplified (file-level
  progress in the helper).
- `EncodeF64Blob`/`EncodeF32Blob` write empty blobs as **null** (columns already
  `isNullable:true`) not a 0-length blob. Root cause found via the unit test: an
  all-0-length blob COLUMN in a row group can't be decoded by Parquet.Net, and chunking
  makes it reachable (decoys are a contiguous block at the end of the entry_id sort ->
  a 100K group can fall entirely in a region with no reference XIC). Null decodes back
  to empty (`DecodeF64Blob(null)==empty`) -> blib-neutral, no gate compares parquet bytes.
- `TestParquetBoundedRowGroupRoundTrip`: forced multi-group == single-group (rows/order/
  ParquetIndex/features/blobs) + an all-empty blob column across 3 groups reads back empty.

**Gates so far (all green):** Build-Osprey -RunTests -RunInspection = 512 tests, 0 fail,
inspection 0/0. `/pw-self-review` (fresh-context subagent) = CLEAN, no Critical/High/Med
(2 informational LOW: test-only static seam reset in finally; fix (b) deferral is a
memory opt not a correctness dep). Stellar regression mode1 (vs golden) PASS byte-identical
(straight blib 45,064,192); mode2/mode3 in flight.

**PR #4430** opened. **TeamCity Osprey Perf/Regression** triggered on `pull/4430`
(build 4096475, Brendan-authorized overnight) = the authoritative Stellar+Astral
mode1/2/3 + perf gate; Astral legs exercise the real multi-row-group write.

**In flight:** single-file memory+perf A/B on PerFileScoring + PerFileRescoring with
dotMemory AFTER dumps (subagent); /pw-respond to the auto Copilot review.

### 2026-07-16 (night: measurement DONE + Copilot fix)
**Memory+perf (single-file Astral file 49, --threads 8, AFTER = 5b7199fdb), posted to
PR #4430 as a comment; dotMemory AFTER dumps captured for BOTH tasks:**
- **PerFileRescoring** (reconciled write-back, tallest peak after #4429): pre-GC managed
  at write apex **8.63 -> 5.46 GB (-3.2 GB, -37%)**; WS peak ~14.1 -> 13.18 GB; warm wall
  57.5 -> 54.1 s (-6%, faster). Dump: `D:\test\osprey-runs\_memperf_night\rescore-base-20260716-231617\rescore-after-20260716-232226.dmw`.
- **PerFileScoring**: WS peak 15.0 GB, managed-at-peak 9.47 GB, write phase 17.1 s, warm
  147.4 s. Dump: `D:\test\osprey-runs\_memperf_night\score-after-20260716-230253.dmw`.
- The bounded 100K-row write caps the end-of-file managed column arrays + native
  Zstd/IronCompress buffers to one chunk (was all 1.68M rows). Residual at the apex is now
  the managed `fullEntries` reload -> motivates deferred fix (b). Full write-up +
  before/after tables: `ai/.tmp/agent-memperf-results.md`. BONUS same-session before-binary
  A/B was left incomplete (before-binary built at worktree `C:\proj\pwiz-membase-night`;
  before-runs not captured) -- optional, not needed for Brendan's ask.

**Copilot review (PR #4430):** ONE finding -- the test seam `RowGroupRowCapForTest`, if set
to 0/negative, could spin the write loop forever. Accepted: guarded
`rowsPerGroup = Math.Max(1, RowGroupRowCapForTest ?? MAX_ROWS_PER_ROW_GROUP)` (production
unchanged: null -> 100000). New commit (gated) + thread reply/resolve.

**TeamCity** Perf/Regression 4096475 on pull/4430: queued (agent not yet free); runs overnight.
