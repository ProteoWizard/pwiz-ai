# TODO: Read raw data directly by default, so a single analysis writes no .spectra.bin

## Branch Information
- **Branch**: (not started) - measurement first, branch when the prototype begins
- **Base**: `master`, after #4950 merges
- **Created**: 2026-11-19
- **Status**: Measured A-C, E, F on MACS2; next is a metadata-only read in pwiz-sharp
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

### 2026-11-19 - First measurements (MACS2, SEA-AD Astral)

Harness `ai/.tmp/sessions/20261119-rawread/harness` (one mode per process), vendor build of #4950 at 0970eb0431
(`D:\Users\brendanx\test\osprey-runs\_bin\vendor-0970eb0431`); logs and per-window TSVs in
`D:\Users\brendanx\test\osprey-runs\rawread` (`run1.log`, `run2.log`, `par9\`). One file: 6.1 GB `.raw`,
4.3 GB `.spectra.bin`, 163,594 spectra, 167 windows. Raw files on D:, caches on E:.

- Exactness: reading each window's spectra from the raw file gives the same spectrum and peak counts as the
  cache for all 167 windows of both files tested.
- Raw, window by window, warm: 19 s for all windows (117 ms median, 158 ms max), single thread.
- Cache, warm: 3.5 s for all windows (20 ms median). Cold from E: 34 and 104 min for the two files - E: was
  badly contended again, cause not found (no recent writes under E:\Users\chrhsu).
- Today's cache-miss read (`LoadAllSpectra`, acquisition order): 39 s warm, 58 s cold, 12.7 GB peak.
- The "metadata" pass is not cheap: 22 s warm, because pwiz-sharp's Thermo reader decodes every spectrum's
  peaks even without binary data (`SpectrumList_Thermo.cs:722`, "Always retrieve the mass list"); C++ pwiz skips
  this below `DetailLevel_FullData`. It is a second full read. A metadata-only path is the first fix.
- Memory: the reader's 6 GB working set is memory-mapped file pages; private memory 0.15 GB.
- CPU: Osprey's server GC (72 heaps) put ~10x CPU on the harness's allocations (300 vs 32 core-s for the
  metadata pass with workstation GC). Inside Osprey that cost is shared with scoring; worth a check there.
- 9 files at once, cold (F): the metadata pass took 430-520 s per file, D: delivering ~112 MB/s in total against
  218 MB/s for one sequential stream - D: is spinning disk and 9 interleaved readers thrash it.

Budget (SEA-AD `runs-validate\final-82files\run.log`, 18 threads per file): coelution scores a window in 28 s
median per thread against 0.12 s to load it, so loading disappears behind coelution. Calibration pass 1 scores
all windows in 37 s, so a single producer's 19 s overlaps only if it runs ahead.

Reading so far: a single analysis needs no `.spectra.bin` - reading the raw file directly costs less than
building the cache does today (a full read plus a 4.3 GB write). The open question is cohort scale on spinning
disk: raw is 1.4x the cache's bytes, read up to three times per file, and parallel files' readers compete for
one disk. The 9-file case is 9 files' producers, one per file as designed, sharing one disk - not
parallel readers within a file. Next: (1) metadata-only reads in pwiz-sharp (issue #5059, assigned to Matt,
with an audit of every reader), then re-measure A; (2) measure whether 9 producers on one spinning disk need
to take turns across files, as `serialBlockReads` does for cache blocks; (3) the same single-file and
9-file measurements on UW8's SSD.

### 2026-11-19 - Thermo metadata fix, and why window-by-window fails cold

Thermo fix (pwiz worktree `D:\Users\brendanx\proj\pwiz-thermo`, branch
`Skyline/work/20261119_thermo_detail_level`, local commit 16b43b04eb, not pushed): `SpectrumList_Thermo` now
honours DetailLevel the way the C++ reader does (instant: index only; fast: no zoom-scan search; precursor
intensity and mass list only at full metadata). Metadata pass 22 s -> 2.1 s warm, 33-50 s -> 2.9 s cold,
working set 0.6 GB. Window checksums, intensity sums included, unchanged. Thermo.Tests 15/15.

9 files at once, cold, window-by-window with the fix (`D:\Users\brendanx\test\osprey-runs\rawread\par9t\`):
4,300-5,800 s per file (median window 25-34 s), against 445-540 s before the fix (`par9\`). The fix did not
slow reading. It removed the full sequential pass that, before the fix, warmed the OS page cache: before, the
metadata pass took ~510 s and the 167 windows then took 19-23 s from memory; now the metadata pass takes
~20 s and every window gathers ~1,000 spectra scattered across the 6 GB file from a cold spinning disk.
(File 9 was a second copy of a file `par9` had just read and finished in 27 s from cache.)

So the window-major access pattern, not the number of producers, is what a cold spinning disk cannot serve.
This matches Skyline's experience: it reads forward in RT order. A direct-read producer has to read the file
sequentially, once, and route each spectrum to its window. Holding every window costs about LoadAllSpectra's
12.7 GB per file, so the open design question is how few windows can be in flight at once: a single
sequential pass that keeps all windows, or bounded passes over RT. `.spectra.bin` stays for now: its layout is
window-major, which is exactly what this access pattern needs. The single-file cold case was not measured
because all 21 raw files on D: are now in the page cache.

### 2026-11-19 - Direct read built and timed

`OSPREY_DIRECT_READ=1` (pwiz worktree `D:\Users\brendanx\proj\pwiz-directread`, branch
`Skyline/work/20261119_osprey_direct_raw_read` from #4950 0970eb0431, local commit 5909cf752f, not pushed):
per-file scoring reads the input in full, forward (the same LoadAllSpectra the cache build uses), and a
resident `SpectraWindowIndex.FromSpectra` hands out copies of each window (callers calibrate m/z in place); no
`.spectra.bin` is written or read, and the re-score reads the source again. Unit tests 671/671, inspection
clean; Stellar regression passes unchanged from mzML. From raw, mode 1 reports 4 issues, all `.raw` vs `.mzML`
file-name keys, and the default build reports the same 4, so `-Source raw` is already broken on #4950.

SEA-AD, 3 raw files on D: (0001, 0005, 0009; already in the OS file cache), 82-file settings, 72 threads,
one file at a time (`D:\Users\brendanx\test\osprey-runs\sea-ad\runs-directread\<arm>\run.log`). All three
arms report the same counts at every stage (75,214 precursors at 1% experiment FDR, 74,566 blib spectra).

| Arm | Total | Library load | PerFileScoring | PerFileRescoring | Peak private, scoring |
|---|---|---|---|---|---|
| direct | 1,040 s | 139 s (first run, cold) | 612 s | 186 s | 38.0 GB |
| cachebuild | 860 s | 50 s | 506 s | 113 s | 30.4 GB |
| cachehit | 770 s | 45 s | 409 s | 115 s | 31.2 GB |

Net of the library load, direct scoring is 473 s against 456 s for building the cache and 364 s for a hit: the
read is ~35-40 s per file either way, and the cache write it skips is cheap here. The re-score's second full
read adds ~73 s over 3 files. So for one file direct read costs about what building the cache costs, and each
later run of the same file costs about 30 s per read more than a cache hit. Peak memory is ~7 GB higher.

### 2026-11-19 - Direction: direct read as the default, cache as the iterative option

Agreed with Brendan: direct reading is worth continued effort, because the prize is not writing a
`.spectra.bin` (71% of the raw's size) for most runs. `--task SpectraCache` stays for iterative work, where a
user may choose to pay the disk to go faster, and may even delete the raw files.

Constraint on overlap: a forward read completes no isolation window until it reaches the end of the file
(every window spans the whole gradient), and calibration samples every window. So reading cannot hide behind
scoring of the SAME file; it can hide behind scoring of the PREVIOUS file. Design, in order of measurement:

1. Free each window's spectra after its last use in the file (main scoring, after both calibration passes),
   so a file's resident peaks fall as scoring proceeds instead of holding until the file ends.
2. Read file N+1 while file N scores, in a `ProducerConsumerWorker` (pwiz_tools/Shared/CommonUtil, already
   referenced by Osprey) gated on memory: the producer waits until file N releases enough windows, so the
   high-water mark stays under two files' spectra. Same for the rescore's second read.
3. Decode in parallel behind the one forward read (the Thermo decode is single-threaded; ~32 s per 6 GB
   file at 180 MB/s), keeping the read itself sequential for spinning disks.

Measure each step on SEA-AD at 3 and 20 files against the cache-hit arm: wall time, peak private memory, and
identical counts. The O(files) memory rule rules out keeping more than the in-flight files resident.

### 2026-11-19 night - Read-ahead reader built; 82-file assessment running

Night log: `ai/.tmp/night-session-budget-20261119.md`.

Local commit a3bd386a46 on `Skyline/work/20261119_osprey_direct_raw_read` (worktree
`D:\Users\brendanx\proj\pwiz-directread`, not pushed). Under `OSPREY_DIRECT_READ=1`:
- `SpectraPrefetcher` (Osprey.Tasks): a `QueueWorker` from CommonUtil whose producer thread reads the stage's
  inputs in input order (the order `OrderedFileLanes` hands them out) and whose consumer thread hands each
  finished file to the lane waiting on it. Started by the first lane's request, so a stage that reads nothing
  reads no file; reads with the stage's own demux settings and falls back to the normal path for a multiplexed run.
- Memory: a byte budget over every file's resident peaks, (lanes + `OSPREY_DIRECT_READ_AHEAD`, default 1) x the
  first file's bytes. The reader holds back spectrum by spectrum (a hook added to `LoadAllSpectra`) while the
  next would exceed the budget and another file holds memory, so it can never wait on itself.
- Per-file scoring calls `SpectraWindowIndex.ReleaseWindowsAsLoaded()` before the main search: each window's
  spectra are handed over without a copy and dropped as it is scored (a second load throws). Calibration still
  gets copies. Each lane releases what remains of its file when it finishes (try/finally), and the rescore uses
  the same reader with whole-file release.
- Tests: 671/671; `TestSubsetOptionVariants` now runs direct read on one lane, a lane per file, and one lane at a
  1.5-file budget (the reader must wait mid-file), each blib equal to the cached run's. Inspection clean.

3 SEA-AD files, one lane (`D:\Users\brendanx\test\osprey-runs\sea-ad\runs-directread2\direct\run.log`; the
download was writing to D: at the time): identical counts (75,214 / 74,566), 858 s against 770 s for a cache hit
and ~951 s for direct read without the reader. Files 2 and 3 waited 0.0 s for their spectra in both scoring and
rescoring; peak resident spectra 8.13 GB, the two-file budget. What remains is the first file's read in each
stage (37 s and 30 s), which nothing precedes to hide behind.

82-file assessment: downloaded the 61 missing SEA-AD raw files from Panorama (82/82 on D:, sizes verified,
`D:\Users\brendanx\test\osprey-runs\sea-ad\raw`). Two arms with the 2026-11-16 final-82 arguments (split-sized
library, 72 threads, 4 scoring / 8 rescoring lanes, FDRBench both passes), same binary, OS file cache cleared
before each: DIRECT from D: raw (started 22:38), then CACHE from the E: `.spectra.bin` set. Outputs under
`D:\Users\brendanx\test\osprey-runs\sea-ad\runs-directread82\`.

**23:05 - one reader cannot keep four lanes fed; fixed with two above-normal-priority readers.** The first
82-file direct arm (stopped after 12 files; logs kept in `runs-directread82\v1-onereader-defaultdirect`) read file 1
in 40.7 s while the library loaded, then took 77-120 s per file once four lanes (72 threads) were scoring, and
every lane waited 100-140 s for each file. Resident spectra stayed at 5.5-8.6 GB of the 20.3 GB budget, so
the budget was not the limit: one decode thread competing with every scoring thread was. Four lanes finish a
file about every 97 s (the final-82 run's 7,980 s over 82 files), so the reader needs to do better than that
per file with room to spare. Local commit 6b1c6d9304: `OSPREY_DIRECT_READ_THREADS` (default 2) readers at
`ThreadPriority.AboveNormal`; with more than one read in flight, the oldest read waits only on memory held by
files lanes have taken (which scoring frees), and later reads also wait on other reads, so reads never wait on
each other. Each reader publishes its own file, because `ProducerConsumerWorker` stops its consumer as soon as
the first producer runs out of work and would strand a file another producer is still reading. Tests 671/671
(the 1.5-file-budget leg now runs two readers), inspection clean.

Order changed: the CACHE arm started at 23:09 (`runs-directread82\seaad-82files-libdecoy-r1.0-defaultcache`);
the fixed DIRECT arm is chained after it (`Chain-Direct82.ps1`), with the file cache cleared before each.
