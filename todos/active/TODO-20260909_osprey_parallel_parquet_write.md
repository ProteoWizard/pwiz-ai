# TODO: Parallel parquet column compression (and the bool-encoder bug behind it)

## Branch Information
- **Branch**: pwiz side not yet branched; fork work on
  `maccoss-developers` branch `parquet-parallel-compression`
- **Base**: `master`
- **Created**: 2026-09-09
- **Status**: Working and deterministic; measured; not yet turned into a PR
- **Module**: `osprey`
- **PR**: none yet (Brendan: hold off, still testing)

## Result

Parquet write for one SEA-AD `.scores.parquet` (4,324,599 rows, 40 columns,
44 row groups): **75.9s -> 33.2-33.4s (~2.3x)**, byte-identical output.

Three runs, one sequential and two parallel, all produced
`sha=87E505583C14`, size 1721755392. Determinism verified, not assumed.

Memory cost is small, which is the point for the 64 GB dev boxes:

| | managed peak | private peak | gaps >=30s |
|---|---|---|---|
| sequential write | 23.6 GB | 32.4 GB | 0 |
| parallel write   | 23.6 GB | 35.2 GB | 0 |

+2.8 GB private, managed peak unchanged, against 5-15 GB for one extra
concurrent FILE. So this is ~5x cheaper per unit of parallelism than
`--parallel-files`, and it needs no memory headroom - it is intra-file, so a
single-file run gets the whole gain (the measurement above IS
`--parallel-files 1`).

Scale: on the 82-file run, parquet write was 6152s of PerFileScoring's 15340s
(40%). A 2.3x cut is ~58 min off a 4h11m PerFileScoring, ~11% of an 8.5h run,
with no configuration change.

## The bug this uncovered (upstream, already fixed in 6.1.0)

`ParquetPlainEncoder.Encode(ReadOnlySpan<bool>, Stream)` in 4.25.0:

```csharp
int targetLength = (data.Length / 8) + 1;          // over-counts by a byte
byte[] buffer = ArrayPool<byte>.Shared.Rent(targetLength);   // UNCLEARED
...
if(n != 0)
    buffer[ib] = b;                                 // only on a PARTIAL byte
Write(destination, buffer.AsSpan(0, targetLength)); // but always writes it
```

When `data.Length` is a multiple of 8 - **100,000 rows per row group is exactly
12,500 bytes** - the loop ends with `n == 0`, so the last byte is never written
and whatever the shared `ArrayPool` held goes into the file. Parquet readers
ignore bits past the value count, so data round-trips correctly and this was
invisible; it is still uninitialised heap being written into every bool page.

It is deterministic single-threaded (stable pool reuse - which is why the
goldens were stable) and NON-deterministic as soon as pages encode
concurrently. `is_decoy` is the only bool column in `.scores.parquet` and was
the only column whose compressed size varied run to run - 2 chunks of 1760 -
which is what localised it.

Fix is `(data.Length + 7) / 8`. Files get ~1 byte smaller per bool page (42
bytes on the test file: 43 full row groups shed a byte, the 44th is a genuine
partial). The old golden was stable but wrong.

**Upstream 6.1.0 already has exactly `(data.Length + 7) / 8`**, so there is
nothing to upstream. Its SIMD path (`EncodeHwx`, on by default via
`ParquetOptions.UseHardwareAcceleration`) writes computed bytes straight to the
stream with no rented buffer, so it is clean too. This is a concrete measured
argument for the 6.1.0 upgrade: parallel parquet writing is safe there and
provably is not on 4.25.0.

## What was ruled out along the way

Worth recording so nobody re-treads it. The variance was NOT:

* the compressor - a standalone test compressed 40 realistic buffers
  sequentially vs under `Parallel.For`, with a shared `Iron` AND with
  per-thread instances: **0 mismatches**. zstd is deterministic under
  concurrency.
* `ThriftFooter.CreateColumnChunk` / `CreateDataPage` / `CreateDictionaryPage` -
  all pure constructors, no footer mutation.
* the shared `RecyclableMemoryStreamManager` - replacing all four
  `_rmsMgr.GetStream()` with `new MemoryStream()` did not help.
* emit ordering - the ordered-append design was right; a strictly sequential
  pass through the NEW Prepare/Emit code reproduced the old golden EXACTLY
  (`7393EAF1A79F`), proving the refactor byte-faithful.
* the string encoder's flush chunking - chunked writes concatenate identically.

Baseline control (run twice, same binary) was byte-identical, so Osprey's
parquet output was reproducible before this work and the variance was
genuinely introduced by concurrency.

## Implementation

Fork (`skylinedev/Parquet.Net`, 4.25.0):
* `DataColumnWriter` split into `PrepareAsync` (pure: encode + compress into
  its own buffer, no stream access, safe to run concurrently) and `EmitAsync`
  (ordered append, rewrites the only two position-dependent fields,
  `FileOffset` and `MetaData.DataPageOffset`).
* `ParquetRowGroupWriter.WriteColumnsAsync(columns, customMetadata, dop, ct)` -
  additive, non-breaking. `dop <= 1` and `dop > 1` call the same `PrepareOne`
  and differ only in `for` vs `Parallel.For`, so a sequential-vs-parallel A/B
  isolates concurrency and nothing else.
* `ParquetPlainEncoder` bool fix above.

pwiz:
* `ParquetScoreCache.WriteRowGroupColumns` - one batch call instead of the
  per-column loop; `BuildRowGroupColumns` already returned all 40 columns.
* `OSPREY_PARQUET_WRITE_THREADS` knob (0 = core count) - how the A/B is taken.
* **`Osprey.IO.csproj` needs `ExcludeAssets="compile"` on the Parquet.Net
  PackageReference plus a direct `<Reference>` to `Shared/Lib/Parquet/ParquetNet.dll`.**
  `Directory.Build.targets` only swaps the RUNTIME binary, which is enough
  while the fork merely FIXES upstream behaviour but not once it ADDS API - the
  compiler otherwise binds the stock reference assembly and fails CS1061. This
  gap will recur on any future fork API, including the 6.1.0 upgrade.

## Merge path (cheaper than first assumed)

* **No golden rebaseline.** `osprey-regression.data` is 59 TSVs and 1 MD, zero
  parquet - goldens capture decoded values, which never changed.
* **No byte assertions in Skyline's parquet tests** (`ParquetReportExporterTest`,
  `ExportHugeParquetReportTest`, `CommandLineReportTest`) - checked.
* **No version upgrade required** - this is all on the 4.25.0 fork.
* Still to do: `regression.ps1 -Dataset Astral` to confirm the gate passes and
  to measure the benefit there (published Astral `stage1to4` is 8:12; if the
  write share resembles SEA-AD's 40%, expect ~110s off). Then cross-impl
  Stage 1-4, which should move TOWARD Rust since parquet-rs lacks this bug.

## Interaction with --parallel-files

Scoring wall is roughly flat in N (445-463s for N>=2 on the 8-file sweep); the
write wall was the whole variable (720/368/196/177s). With the write now
~33-40s regardless of N, the write wall becomes `ceil(files/N) x ~35s`, so the
N=1 to N=8 spread should roughly halve rather than vanish - the sequential arm
still serialises one write phase per file. Closing it entirely needs file N's
write overlapped with file N+1's scoring, i.e. a pipeline, which is what
`--parallel-files` already supplies. The two stack; the residual value of
`--parallel-files` on a 64 GB box is now small.
