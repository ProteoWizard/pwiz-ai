# TODO-20260802_osprey_cache_write_progress.md

## Branch Information
- **Branch**: `Skyline/work/20260802_osprey_cache_write_progress` (pwiz-work1)
- **Base**: `master` (at `0245ad7a21`, i.e. after #4513)
- **Created**: 2026-08-02
- **Status**: In Progress
- **Module**: `osprey`
- **PR**: (pending)
- **Requester/Reporter**: Brendan (Osprey developer) - NO credit line

## Problem

`SpectraCache.SaveSpectraCache` writes 3-5 GB with no console output at all. On the
AHA Plasma Stroke EV staging run (197 Astral `.raw`, `--task SpectraCache`) that is a
**21-27 second silence per file**, and it lands immediately after the read has already
printed its own `100%` - so the last thing a watching user sees is a completed
progress bar, followed by half a minute of nothing.

Measured on the first 8 files of that run:

| file | read (to 100%) | write (100% -> WARN) | cache |
|---|---|---|---|
| 001-B_A5_005 | 118 s | **26 s** | 4.44 GB |
| 001-C_E10_058 | 111 s | **24 s** | 4.20 GB |
| 001-D_H3_087 | 132 s | **25 s** | 4.44 GB |
| 001-E_F8_068 | 155 s | **27 s** | 4.53 GB |
| 001-F_D2_038 | 131 s | **22 s** | 3.67 GB |
| 002-A_G10_082 | 132 s | **21 s** | 3.39 GB |
| 002-B_D8_044 | 130 s | **21 s** | 3.79 GB |

The gap tracks cache SIZE, not unsorted-spectrum count - it is the serialization, at
roughly 180 MB/s. Confirmed directly: the `FileSaver` temp (`~OSwiypkbiu.wem`) appeared
2 s after the read's `100%` and was still growing at 4.80 GB the second the completion
line printed.

This was missed by #4513 ("Reported progress through the silent multi-minute phases"),
which covered the compute phases but not the cache write.

## Fix

Wrap the write in the existing `ProgressReporter` on `IO_INTERVAL_SECONDS` (5 s), the
same cadence and seam the read uses (`VendorRawReader.LoadAllSpectra`), so the phase
announces itself and shows motion:

```
Reading 2025-Ast-Levitt-AHA_001-F_D2_038.raw...
  ...
  100%
Writing 2025-Ast-Levitt-AHA_001-F_D2_038.spectra.bin...
  38%
  74%
  100%
  2025-...-038.spectra.bin: ms2=136,945 ms1=1,096 3.67 GB in 159.8s
```

Progress is reported per RECORD, not per byte: the total byte length is not known until
the records are written, and `VendorRawReader` already sets the per-spectrum precedent for
the same reason. Total is `nMs2 + nMs1`; the index block and footer are ~40 bytes per MS2
against the body's ~31 KB, so they ride under the final 100% that `Dispose` forces.

**Logging only - not one byte of the cache changes.** Caches written before and after this
commit are interchangeable, so it is safe to swap the binary mid-dataset.

## Explicitly NOT in scope

**Streaming the write to overlap it with the read.** That is the real fix for the 25 s
(and for the 10-12 GB peak working set, since the whole file is materialized in RAM before
`SaveSpectraCache` is called), but the cache body is grouped by isolation window
(`SpectraCache.cs:136-159`) and the grouping is what makes `SpectraWindowIndex.LoadWindow`
a single sequential run - the cold-HDD fix. Streaming it means one temp file per isolation
window, streamed back in sequence, the way Skyline builds the SKYD chromatogram cache.

Brendan's call (2026-08-02): **not now.** It is a lot of work, and the design it would copy
dates from when the machines had 16 GB. Revisit if the write cost grows or the peak becomes
the binding constraint.

## Observed, and NOT a defect: the vendor file-open pause

With the write instrumented, the longest silence in the run moved to the gap between
`Caching spectra N/197` and `Reading X.raw...` - 121 s and 38 s on two files, against
~7-9 s typical:

```
23:47:33  Caching spectra 29/197: ...AHA_008-F_A1_001.raw
23:49:34  Reading AHA_008-F_A1_001.raw...          <- 121 s, no output
```

That is `new MsDataFileImpl(...)` - ProteoWizard opening the file and building its scan
index before it can serve spectrum 0. Brendan (2026-08-02): **expected, and not fixable
from here.** Thermo `.raw` has a much larger open cost than mzML, and the same pause is
visible in Skyline's own progress UI. Do not spend time bisecting it.

Osprey cannot report a percent through it (the work is inside the vendor call, which
exposes no position), so the only available improvement is an indeterminate
`Opening X.raw...` line before the open, so the console at least names what it is doing.
Not implemented - raise it only if the pause starts drawing questions.

## Checklist

- [x] `ProgressReporter` around the MS2 body + MS1 section in `SaveSpectraCache`
- [x] Unit coverage: `TestSpectraCacheRoundTrip` captures `OspreyOutput` across the save and
      asserts the file name and `100%` appear (assertion avoids the English heading word so
      it survives translation of the surrounding output)
- [x] Pre-commit gate: `Build-Osprey.ps1 -Configuration Debug -RunTests -RunInspection`
      -> 563/563 tests, 0 inspection warnings
- [ ] Observe the real 5 s cadence on an Astral file (unit test data is too small to emit
      intermediate percents - it shows only heading + 100%)
- [ ] `regression.ps1 -Dataset Stellar` (logging-only change, but it touches the cache path)
- [ ] PR

## Related

- `ai/docs/osprey-large-datasets.md` - the AHA dataset this surfaced on
- `ai/.tmp/run-spectracache-aha.ps1` - the staging run driver
- `D:\test\osprey-runs\aha-plasma-ev\spectracache-197.log` - the log the timings came from
