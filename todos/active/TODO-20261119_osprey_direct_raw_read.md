# TODO: Read raw data directly by default, so a single analysis writes no .spectra.bin

## Branch Information
- **Branch**: (not started) - measurement first, branch when the prototype begins
- **Base**: `master`, after #4950 merges
- **Created**: 2026-11-19
- **Status**: Planning; raw-read harness to run on MACS2 once the CHS 446 re-run stops
- **Module**: `osprey`
- **PR**: (none yet)

## Goal

Match DIA-NN in what a user perceives Osprey to need on disk. A naive user running one analysis
should see only their data files and Osprey's outputs: no `.spectra.bin`. Keep the cache as an
option for the cases where it pays (Brendan, 2026-11-19):

- `--task SpectraCache` then deleting the sources stays the staging recipe for cohorts and HPC:
  the caches are smaller than the raw files (CHS: 1,168 GB of caches vs 1,774 GB of raw, 0.66x),
  faster to read, and usable without the sources.
- Demultiplexing (`.demux.spectra.bin`) keeps its cache: there it saves real processing.
- mzML input probably keeps it too (56-212 s to parse an Astral mzML, and mzML is larger than the cache).

`.spectra.bin` began as an optimization for parsing mzML (text, needing decoding), first written in
acquisition order like the raw files. Skyline's XIC extraction reads vendor files directly and fast,
folding I/O behind processing, which is the model to follow.

## Today

- Cache miss: `ScoringTaskShared.EnsureSpectraCache` reads the whole file in acquisition order
  (`SpectrumFileReader.cs:161`, `msData.GetSpectrum(i)`), holds it resident (~6 GB MS2 for an Astral
  file), writes the cache, then streams from it.
- Cache hit: `StreamingWindowSpectraProvider` reads one isolation window block at a time from the
  window-grouped `.spectra.bin` (`serialBlockReads` serializes block loads), so only the windows
  being scored are resident. This is what bounds memory at 9 files x 8 threads.
- Readers: PerFileScoring (calibration, then coelution) and PerFileRescoring (rescore + CWT re-pick).
  Without a cache a file is read up to three times: calibration, coelution, rescoring.

## Design direction

Window-at-a-time reads from the raw file, folded behind scoring with a `ProducerConsumerWorker`
(`pwiz_tools/Shared/CommonUtil/SystemUtil/ProducerConsumerWorker.cs`):

- A metadata pass builds each window's spectrum indices without decoding peaks - Skyline's
  `LookaheadContext` (`SpectraChromDataProvider.cs:1479`), which uses `MsDataFileImpl`'s
  escalating detail levels (`GetMsLevel`, `GetPrecursors`, `GetWindowGroup`; `MsDataFileImpl.cs:105-115`).
- One producer thread per file decodes a whole window (scoring order, largest first) into a bounded
  queue - Skyline's "Spectrum reader" (`SpectraChromDataProvider.RunAsync`, `:956`) and
  `ChromCacheBuilder`'s `MAX_CHROM_READ_AHEAD` bound (`:261`, `:1293`). It is the only thread touching
  the reader, so no lock.
- The file's scoring threads consume windows. Results are stored by window index, so output stays
  byte-identical.

If scoring a window takes longer than loading one, the load disappears. Budget (CHS, 8 threads per
file): a window is needed about every 4.7 s (38 s median per window / 8); a raw window load at the
full-read rate is ~0.7 s (135 s / 200 windows). The risks are calibration, whose work per window is
smaller and may be read-bound, and the decode CPU competing with saturated scoring (~33 of ~870
core-hours on CHS, ~4%).

## Measurements

1. [ ] Harness on the vendor build against SEA-AD `.raw` + `.spectra.bin` on D: (21 + 4 raw files):
   - A: metadata pass time, and the detail level that yields the isolation window
   - B: full acquisition-order read (today's cache-miss path): wall, core-s, peak memory
   - C: window-by-window reads from A's index, one producer
   - D: producer read time per window vs consumer score time per window, calibration and coelution
   - E: `.spectra.bin` window block loads for comparison
   - F: A-E with 9 files at once (disk and CPU contention)
   Run on MACS2 after the CHS re-run stops; single-file case on UW8 too.
2. [ ] Prototype a no-cache default; regression tests should pass without change. SEA-AD 82 at 9 x 8
   on MACS2 and sequential on UW8: wall, memory, disk vs cache-backed runs. Needs 39 more SEA-AD raw
   files on MACS2 (~230 GB download).
3. [ ] After the cache: the scores parquets are the larger disk target (CHS ~510 GB per search).

## Progress Log

### 2026-11-19 - Planned

Discussion with Brendan after the CHS 446 runs on MACS2 (benchmark TODO
`TODO-20261006_osprey_seaad_benchmark_port.md`).
