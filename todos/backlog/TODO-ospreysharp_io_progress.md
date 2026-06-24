# TODO-ospreysharp_io_progress.md

## Status
- **Type**: OspreySharp CLI output (follow-on to PR #4326)
- **Origin**: Replaces the abandoned `TODO-ospreysharp_progressmonitor_portableutil.md`.
  PR #4326 chose the cheap OspreySharp-local `ProgressReporter` over porting Skyline's
  `ProgressStatus`/`IProgressMonitor` into PortableUtil (that port carries the heavy
  UI+CLI dual-support burden and a build-infra blast radius), so the relocation is OFF
  the table. This TODO is the narrow remaining goal that motivated it.
- **Branch**: TBD (`Skyline/work/YYYYMMDD_ospreysharp_io_progress`)

# Add %-complete progress to OspreySharp I/O so no step stalls silently

## Goal (acceptance criterion)
On the **Astral** dataset, **non-verbose**, NO single step goes more than **8 seconds**
with no console output. Measured as the max **Time Diff** in `perfviz.html` over a
straight-through run. Stellar already clears this bar; Astral is the binding case because
its files are ~15x larger (one mzML ~200k MS/MS spectra, scored parquet ~2.9M rows).

## The gaps to fill
Measured on Astral, 2026-06-24, non-verbose (`ai/.tmp/osprey-astral-default/run.log` +
its perfviz capture). The percent-counted **compute** blocks are already fine at the 2s
`ProgressReporter` timer; every remaining >8s stall is **I/O that emits nothing while it
runs**:

| Step | File / method | ~Gap | Mechanism |
|---|---|---|---|
| mzML read | `OspreySharp.IO/MzmlReader.cs` `LoadAllSpectra` | 40-44s | **byte-based** |
| Scored parquet write | `OspreySharp.IO/ParquetScoreCache.cs` | 33-41s | **count-based** (rows) |
| Reconciled parquet write | `OspreySharp.Tasks/ReconciledParquetWriter.cs` | 43-47s | **count-based** (rows) |
| Post-training Percolator apply | `OspreySharp.FDR/PercolatorEngine.cs` (apply, post-train) | ~26s | count-based (entries) |

(7-8 spikes of 40-47s are visible in the Astral perfviz Time-Diff trace; everything
between them is already <8s.)

## Approach: reuse the `ProgressReporter` from PR #4326
`OspreySharp.Core/ProgressReporter.cs` is the cheap, stopwatch-throttled (2s) percent
printer already shipped. No new infrastructure needed -- wire each I/O step to it.

**Survey the existing Skyline patterns first.** Skyline tracks I/O progress **several
ways**; `ProgressStream` (`pwiz_tools/Shared/CommonUtil/SystemUtil/ProgressStream.cs`, a
byte-counting `Stream` decorator reporting `min(99, 100*pos/len)` on each `Read`) is just
ONE. Inventory the others (row/line-count reporters on writes, IProgressMonitor loops) and
pick per call-site rather than forcing one mechanism.

- **mzML read -> byte-based.** Wrap the `FileStream` feeding `XmlReader.Create` in
  `MzmlReader.LoadAllSpectra` in a `ProgressStream`-style decorator that drives
  `ProgressReporter` (`total = stream.Length`, `Report(bytesRead)`). Byte-based is robust;
  prefer it over counting spectra via `<spectrumList count="N">` (attr not always
  present/trustworthy).
- **parquet writes -> count-based** ("output rows vs expected count"): the writers emit
  row-groups, so `ProgressReporter("Writing N entries", totalRows).Report(rowsWritten)`
  per row-group.
- **Percolator apply -> count-based** on entries if it has a clean denominator; else leave
  (smallest gap).
- Keep the disposition model: heading + final line stay in default; intermediate percents
  are 2s-throttled like the scoring loop. Per-spectrum/per-row detail (if any) -> `--verbose`.

## Prerequisite tweak
`ProgressReporter` is currently `int`-based (`total`/`current`). mzML peak data and parquet
row counts can exceed `int.MaxValue` on Astral-class data, so **widen `total`/`Report` to
`long`** (safe: `int` promotes; the percent math already uses `100L`). Update the existing
scoring/rescore call sites (they pass `int` counts -> implicit widen).

## Verification
- `pwsh -File ./ai/scripts/OspreySharp/Build-OspreySharp.ps1 -Configuration Debug -RunTests -RunInspection`
- Output behavior-neutral: `pwsh -File ./pwiz_tools/OspreySharp/regression.ps1 -Dataset Stellar`
  (progress is output-only -> expect byte-identical golden + resume + HPC modes).
- **Acceptance run**: `pwsh -File ./ai/.tmp/Run-OspreyStellar.ps1 -Dataset Astral` (non-verbose),
  load `run.log` into `ai/scripts/OspreySharp/perfviz.html`, confirm **max Time Diff <= 8s**.
  Re-run `-Verbose` to confirm detail still available.

## Risks / watch-outs
- A `ProgressStream` over the XML read must not perturb decode throughput (the read overlaps
  parallel decode); the decorator just counts bytes on `Read`, no extra copies.
- Parquet writers may buffer the whole table before flushing row-groups -- verify the write
  actually streams row-groups (otherwise the % jumps 0->100 at the end and the gap stays).
  If a writer is single-shot, a coarse "Writing N rows..." heading + final line is the
  fallback (still better than silence, but won't meet the 8s bar -- check before relying on it).
- Keep it OspreySharp-only (Core/IO/Tasks); do NOT reach back toward the PortableUtil port.
