# Parallel parquet write corrupts byte-typed columns (Osprey's `charge`)

## Branch Information
- **Branch**: `Skyline/work/20260917_parquet_write_race`
- **Checkout**: `C:\proj\pwiz-work2`
- **Base**: `master`
- **Created**: 2026-09-17
- **Module**: `osprey`
- **Status**: Completed
- **PR**: [#4680](https://github.com/ProteoWizard/pwiz/pull/4680) (merged 2026-09-17)
- **Fork PR**: the `maccoss-developers` `parquet-parallel-compression` PR (awaiting Nick's
  review) carries the library-side fix as commit `2ca33b1`. This pwiz PR only STAGES the
  rebuilt binary and adds the regression guard.

## Objective

Stage the rebuilt `ParquetNet.dll` that fixes a use-after-return in Parquet.Net's
narrow-integer encoders, and add the in-process stress test that catches it.

## The bug

`ParquetPlainEncoder.Encode(ReadOnlySpan<byte>, Stream, SchemaElement)` widens a `byte`
column into a rented `int[]`, **returns the buffer to the pool in a `finally`, and then reads
it**:

```csharp
int[] ints = ArrayPool<int>.Shared.Rent(data.Length);
try {
    for(int i = 0; i < data.Length; i++) ints[i] = data[i];
} finally {
    ArrayPool<int>.Shared.Return(ints);          // returned here...
}
Encode(ints.AsSpan(0, data.Length), destination); // ...then READ after return
```

Benign single-threaded - nothing rents in between, so the contents survive, which is why it
has been latent for years. A live data race once #4652's `WriteColumnsAsync` encodes columns
concurrently. `sbyte`, `short` and `ushort` carry the identical copy-paste.

## Blast radius

* **Only Osprey.** `WriteColumnsAsync` (the parallel API) has exactly ONE caller in pwiz:
  `ParquetScoreCache.cs:770`. Skyline's `ParquetReportExporter.cs:50` uses the stock singular
  `WriteColumnAsync` and is sequential, so Skyline parquet reports are unaffected.
* **Only the `charge` column.** The corruption is confined to `byte`/`sbyte`/`short`/`ushort`
  columns; Osprey's schema has exactly one (`charge`). Every other column is uint, double,
  string, bool or a `byte[]` blob - all different encoders. `is_decoy` is the `bool` whose
  sibling bug was fixed on 2026-09-09.
* **Both Osprey write paths** go through it: `WriteScoresParquet` and
  `StreamReconciledScoresParquet`.
* **Since 2026-09-10** (#4652 merged; the staged DLL is dated Sep 11).

## Measured

20,000 write/read round-trips of the same 7-row fixture per arm:

| arm | corrupted round-trips |
|---|---|
| parallel (default DOP) | **27 / 20,000** (0.135%) |
| serialized (`OSPREY_PARQUET_WRITE_THREADS=1`) | 0 / 20,000 |
| parallel, after the fix | 0 / 20,000, and **0 / 100,000** |

## Upstream

Present in upstream `master` AND `6.1.0` (`ParquetPlainEncoder.cs:580`), verified by fetching
the source. No `EncodeHwx` bypass for these types - that exists only for `bool`. So unlike the
bool-encoder byte count, this one IS worth reporting upstream, and it corrects the fork's
PATCH-NOTES claim that 6.1.0 makes parallel writing safe.

## Tasks

- [x] Fix all four overloads in the fork; rebuild; PATCH-NOTES
- [x] Stage the rebuilt `ParquetNet.dll` / `.xml` into `pwiz_tools/Shared/Lib/Parquet`
- [x] Add `TestParquetRoundTripScalarStress` as the regression guard
- [x] Pre-commit gate: 596 tests, zero inspection warnings
- [x] Decide whether artifacts written 2026-09-10..17 need invalidating - NO, see the scan below
- [x] Hard-fail a zero charge on read (RequireCharge)

## Existing artifacts: scanned, and they are CLEAN

Every Osprey parquet on this machine written since the writer landed was checked - 2,176 files
modified on or after 2026-09-10, 1,444,467,818 rows.

Two passes, because scanning for zeros alone is not sufficient: the buffer that overwrites the
charge column belongs to a dictionary encoder writing string indexes, so a stolen value can be
ANY byte. The 7-row fixture happened to always yield 0; production need not.

1. **Zero scan** - 0 rows with `charge == 0`.
2. **Data vs. statistics** - the rigorous one. Parquet statistics are computed from the
   IN-MEMORY span while the corruption happens inside the encode, so for a corrupted page the
   stats still describe the intended values and the data does not. Comparing them detects the
   defect whatever value was stolen. **15,544 row groups compared, 0 mismatches**, and every
   row group reports data min 2 / max 3.

So **no cached scoring needs invalidating**, and the new `RequireCharge` guard will not fire on
anything already on disk.

**Why production escaped while a 7-row fixture corrupted 1 write in 750** is not established.
The plausible reason is `ArrayPool` size bucketing: `Rent(7)` lands in a heavily contended
small bucket, `Rent(100000)` (the production row-group size) in a large one with few
competitors. That is a hypothesis, not a measurement - the defect is real either way and the
fix is not conditional on it.

## Still open

Whether the daily version stamp invalidates window-era files on every resume path - moot for
correctness now that the scan is clean, but still unverified.

**Silent defaults on read.** `ReadColumnByName` (`ParquetScoreCache.cs:848`) returns null for
a column it cannot read, and three sites substitute `(byte)0`. That did NOT cause this bug -
the column reads back faithfully - but a silently defaulted charge is invalid output a user
would trust, which is what the hard-fail-over-warn rule exists for.

## 2026-09-17 - Merged

PR #4680 merged as commit `f8f0a9a6f5`. Shipped the rebuilt `ParquetNet.dll`, the
`RequireCharge` guard, and `TestParquetRoundTripScalarStress`.

**Gates on the merged head `366586a855`** (which carries a merge of master, so this is the
#4679 + #4680 combination, not a stale base):

| gate | where | result |
|---|---|---|
| `regression-parallel.ps1 -Dataset All` | local | 70 PASS / 0 FAIL / 0 SKIP |
| Perf/Regression, build 4178032 | MacCoss TeamCity Agent 1 | 70 PASS / 0 FAIL / 0 SKIP (1:07:38) |
| Osprey Windows .NET, build 4177603 | MacCoss TeamCity Agent 1 | 596 tests passed |
| stress A/B, 100k iterations per arm | local | 0 corrupted, parallel and serial |

Both TeamCity builds show FAILURE for `Failed to load build settings from VCS` only - the
configs were moved into `ProteoWizard / Versioned Configs` and a master-based ref cannot carry
versioned settings. A third red, `ProteoWizard and Skyline Docker container (Wine x86_64)`, was
investigated and dismissed: it failed three `msconvert` vendor conversions, and build 4170821 on
unrelated master commit `e5afd8e6c2` failed two of the same three with the identical
Unicode-filename stderr. msconvert never touches Parquet.Net.

**An earlier build was worse than it looked and is worth remembering.** Build 4177770 landed on
an AWS agent (`pwiz-windows-i-0aac9f75d0b8ec680`) where dotCover is not installed; step 3 exited
2 and **zero tests ran** - `number of tests 0 is 595 less than 595`. Its summary line still read
as an ordinary settings failure. Pinning `agent_name='MacCoss TeamCity Agent 1'` is what turned
that into the real 596/70 PASS numbers above.

**Existing artifacts were scanned and are clean** - see the section above: 2,176 files,
1,444,467,818 rows, 15,544 row groups compared against their own statistics, zero corruption. No
cached scoring needed invalidating, and the guard fires on nothing already on disk.

**Upstream is still open.** The same use-after-return is present in upstream `master` and
`6.1.0`; the fork carries the patch and PATCH-NOTES records that a 6.1.0 upgrade would not avoid
it. The library-side fix is `2ca33b1` on the `maccoss-developers` `parquet-parallel-compression`
branch, pushed to the PR awaiting Nick's review.
