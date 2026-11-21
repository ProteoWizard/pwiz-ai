# TODO: Read raw data directly by default, so a single analysis writes no .spectra.bin

## Branch Information
- **Branch**: `Skyline/work/20261119_osprey_direct_raw_read` (worktree `D:\Users\brendanx\proj\pwiz-directread`)
- **Base**: `master` (#4950 merged 2026-11-20; merged in as 2881dd85b5)
- **Created**: 2026-11-19
- **Status**: PR in preparation: the read-ahead cache write becomes the default cache-miss path, plus `--spectra-cache off`
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

**2026-11-20 06:53 - 82-file assessment: direct read gives identical results; scoring +5.7%, rescoring 4.9x (disk-bound).**
Same binary family, file cache cleared before each arm, final-82 arguments. CACHE = existing E: `.spectra.bin` (a cache
hit, the fastest case; builds nothing). DIRECT = local commit 6b1c6d9304 reading the D: `.raw` files.
Logs: `D:\Users\brendanx\test\osprey-runs\sea-ad\runs-directread82\seaad-82files-libdecoy-r1.0-default{cache,direct}\run.log`.

| Stage | Direct read | Cache hit | final-82 (2026-11-16) |
|---|---|---|---|
| PerFileScoring | 8,175 s / 75.8 GB | 7,735 s / 66.4 GB | 7,980 s / 67.7 GB |
| FirstPassFDR | 1,588 s | 1,574 s | 1,602 s |
| PerFileRescoring | 6,695 s / 30.5 GB | 1,373 s / 24.7 GB | 1,345 s / 23.8 GB |
| SecondPassFDR | 140 s | 128 s | 140 s |
| Total | 16,598 s | 10,811 s | 11,067 s |

- Results: 97,191 precursors and 97,122 library spectra in all three; FDRBench pass1/pass2 TSVs byte-identical
  (sha256 431e7bc0.../5811d02b...).
- Scoring: reads averaged 185 s per file beside four lanes; lanes waited 5,435 s summed, mostly overlapped (wall
  +440 s). Peak resident spectra 14.2 GB of a 20.3 GB budget, so memory was not the limit.
- Rescoring: disk-bound. D: 98% busy at ~90 MB/s, CPU 3.5%; 160 s per file read, eight lanes waited 34,783 s summed.
  The cache arm re-reads a window-grouped `.spectra.bin`; direct read decodes every `.raw` a second time.
- Cause of the slow reads: the vendor reader maps the file and faults it in ~264 KB pieces (330 reads/s, 9.6 ms each;
  the process's own IO counters read 0). Two such readers interleave on the RAID-5 spindles.
- Not measured: a cold start from `.raw` that BUILDS the caches (the guide's ~70 min / ~340 GB at 82 files). That is
  the like-for-like comparison for a first run; the cache hit above is the comparison for iterative runs.
- Next (running): `OSPREY_DIRECT_READ_WARM_MB=16` (uncommitted; snapshot `_bin\directread-warm`) reads each file
  start to end in 16 MB blocks, one file at a time, before the decode, so the decoder works from the OS file cache.
  82-file arm `...-defaultdirectwarm` started after the direct arm.

**2026-11-20 - Thermo metadata fix opened as #5062 for Matt (part 1 of #5059).** `/code-review medium` raised one real
issue: fast metadata skipped the zoom-scan search (as cpp does), but `MsDataFileImpl.GetPrecursors` settles on the first
level that returns precursors, so Skyline would have taken triple-play precursors without the zoom correction. Commit
1079d177d1 keeps the search at fast metadata (no measurable cost: 2.6-3.6 s metadata pass either way) and adds
`SpectrumListThermoDetailLevelTests` (7 fixtures, every spectrum). Thermo.Tests 16/16 (needs
`-p:IAgreeToVendorLicenses=true`). Dropped: the shared `ToDetailLevel` helper, the instant-path scan duplication, and
the `SpectrumListWrapper` bool collapse (#5059 part 2).

**2026-11-20 - Cold start measured: `.raw` in, `.spectra.bin` written during scoring** (arm
`runs-directread82\seaad-82files-libdecoy-r1.0-defaultrawcache`, 72 threads, 4 scoring / 8 rescoring lanes):

| Stage | Direct read | Cold start (writes cache) | Cache hit |
|---|---|---|---|
| PerFileScoring | 8,175 s / 75.8 GB | 9,739 s / 53.9 GB | 7,735 s / 66.4 GB |
| FirstPassFDR | 1,588 s | 1,782 s | 1,574 s |
| PerFileRescoring | 6,695 s / 30.5 GB | 1,565 s / 25.1 GB | 1,373 s / 24.7 GB |
| SecondPassFDR | 140 s | 130 s | 128 s |
| Total vs cache hit | 16,598 s (+53.5%) | 13,217 s (+22.3%) | 10,811 s |

- Results identical in all three (97,191 precursors, 97,122 library spectra, same FDRBench sha256).
- Cold start is 20.4% faster than direct read: writing the cache costs scoring +1,564 s, rescoring from it saves 5,130 s.
- The cache it writes: 82 files, 371.4 GB (345.9 GiB) in `sea-ad\raw`, 71.5% of the 483.6 GB of `.raw`.
- So with today's reader, a `.raw` run should keep writing `.spectra.bin` by default; a no-cache flag is a disk-for-time
  option (+25.6% wall vs cold start). The warm-pass arm (`...-defaultdirectwarm`, now running) tests whether a sequential
  pre-read closes the rescoring gap; that decides whether direct read can become the default.
- Brendan's framing: a lab reanalyzing later either keeps 72% extra storage or pays the cold start again, and no
  lossless `.raw` alternative feeds Skyline yet.
- Thermo PR #5062: Matt asked to stack it on #5057 (its harness adds a detail-level agreement check). Merged #5057 in
  (5dd68b0015), retargeted, Thermo.Tests 16/16; listed what the Thermo test still covers beyond the harness.

**2026-11-20 - Warm pass (`OSPREY_DIRECT_READ_WARM_MB=16`) measured at 82 files: slower** (arm `...-defaultdirectwarm`,
third attempt after two snapshots without working vendor DLLs). Scoring 10,263 s / 97.6 GB, FirstPassFDR 2,237 s,
rescoring 8,842 s, SecondPassFDR 212 s, total 21,554 s (direct 16,598 s); results identical. The pre-read averaged 45 s
per file (~130 MB/s) and the decode after it stayed slow. Caveat: the two FDR stages, which read no `.raw`, ran 41% and
51% slower too, so the machine was busier during this arm and the comparison is confounded; still no sign of a gain.
Not carried into a PR.

**2026-11-20 - Direct read that writes the cache (no read-back), committed locally as 3dc7d70e4b** (`pwiz-directread`,
not pushed). `OSPREY_DIRECT_READ_WRITE_CACHE=1`: the scoring reader writes each `.spectra.bin` from the read-ahead
spectra before handing them over, scoring uses memory, the re-score reads the cache. The old cache path did
read `.raw` -> write -> read `.spectra.bin` back for scoring, with no read-ahead (`ScoringTaskShared.cs` EnsureSpectraCache).
Osprey tests 671/671 with a new SubsetPipelineTest leg (same blib; caches byte-identical to the cached run's). 82-file
arm `...-defaultdirectwritecache` queued behind the warm arm (Chain-WriteCache82.ps1), no warm pass; three caches
hashed before/after to confirm identical output.

**2026-11-20 night - Write-cache arm measured: no faster than the old cold start** (arm
`runs-directread82\seaad-82files-libdecoy-r1.0-defaultdirectwritecache`, 18:54-22:33, exit 0; table from
`ai/.tmp/sessions/20261119-rawread/compare-arms82.py`):

| Stage | Direct read | Old cold start | Write cache, no read-back | Cache hit |
|---|---|---|---|---|
| PerFileScoring | 8,175 s | 9,739 s | 9,526 s / 71.5 GB | 7,735 s |
| FirstPassFDR | 1,588 s | 1,782 s | 1,780 s | 1,574 s |
| PerFileRescoring | 6,695 s | 1,565 s | 1,722 s | 1,373 s |
| SecondPassFDR | 140 s | 130 s | 136 s | 128 s |
| Total vs cache hit | 16,598 s (+53.5%) | 13,217 s (+22.3%) | 13,165 s (+21.8%) | 10,811 s |

- Results identical (97,191 precursors, 97,122 library spectra, same FDRBench sha256), and the sampled caches hash the
  same before and after (`cache-hash-before.txt` / `-after.txt`, 8 lines each, no diff).
- Skipping the read-back saved 52 s (0.4%), because scoring is reader-bound on this disk. The cache writes took only
  1,207 s in total (14.7 s per file), but they share the RAID-5 HDD with the `.raw` reads: read-ahead took 18,156 s
  summed against direct read's 15,196 s, and scoring lanes waited 12,209 s against 5,435 s.
- So from `.raw`, writing the cache costs ~22% over a cache hit by either route, and the extra switch buys nothing
  here. It might help where the cache goes to a different device than the `.raw`; not measured. Not carried forward.
- Load: other users peaked at 0.2 logical processors (`load-writecache82.log`, 43 samples). Overlaps of my own: ~5 min
  of builds and tests during scoring (noted earlier), and a `du` walk of `D:\Users\brendanx\test` plus a trim of
  ~520 GB of old run outputs from 21:30 to 22:15, i.e. during FirstPassFDR and rescoring. FirstPassFDR is +13% over
  the cache hit here, and equally in the old cold-start arm, which had neither, so the +13% more likely comes from
  ~350 GB of cache writes evicting the score parquets from the file cache than from my overlap.

### 2026-11-21 - Direction changed: keep the cache by default, ship direct read as an option

Brendan, after the 82-file arms: the cache keeps enough benefit, especially written from the
read-ahead spectra with no read-back, that it stays the default; users willing to trade speed for disk
get an option to run without it. Local commit 3d7a9eaae8 on the branch (not pushed):

- Default: per-file scoring starts the read-ahead reader (`SpectraPrefetcher`) for the inputs that have
  no `.spectra.bin` (nor `.demux.spectra.bin`) when the stage begins; it writes each cache from the
  spectra it read and scoring uses them from memory. Inputs with a cache stream from it as before; a
  cache found stale still goes through the old read, write, read-back path, as does `--task SpectraCache`.
- `--spectra-cache on|off` (`OspreyConfig.SpectraCache`, not in the search hash): off writes no cache,
  and the re-score starts the reader again for inputs with no cache. An existing cache is read either way.
- Removed `OSPREY_DIRECT_READ`, `_WRITE_CACHE` and `_WARM_MB`; `_AHEAD` and `_THREADS` renamed
  `OSPREY_READ_AHEAD` / `OSPREY_READ_THREADS`. Docs: 14-intermediate-files, 15-hpc-scoring-split,
  20-command-line; help pages regenerated.
- Tests 671/671, inspection clean (`ai/.tmp/sessions/20261119-rawread/tests-spectracache2.log`).
  `TestSubsetOptionVariants` now asserts that the default run reads ahead, that the caches it writes are
  byte-identical to `--task SpectraCache`'s, and that the three `--spectra-cache off` legs write no cache.
  An earlier run reported a second failure that did not recur; its truncated log lost the name.
- Measured basis (82 SEA-AD files, sections above): default path 13,165 s vs 13,217 s for the old cold
  start (-0.4%), scoring peak 71.5 vs 53.9 GB; off is +26% wall over the default path.
- Next: `regression-parallel.ps1 -Dataset All` (regression tests should pass without change) after the
  109-feature SVM arm on MACS2 finishes, `/code-review medium` (running), then the PR.
