# TODO: Read raw data directly by default, so a single analysis writes no .spectra.bin

## Branch Information
- **Branch**: `Skyline/work/20261119_osprey_direct_raw_read` (worktree `D:\Users\brendanx\proj\pwiz-directread`)
- **Base**: `master` (merged in as bc391e44eb on 2026-11-25: #4997, #5057 vendor reader speed-up, #5070 per-run models)
- **Created**: 2026-11-19
- **Status**: Completed
- **PR**: [#5067](https://github.com/ProteoWizard/pwiz/pull/5067) (merged 2026-11-26)
- **Module**: `osprey`

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

1. [x] Harness on the vendor build against SEA-AD `.raw` + `.spectra.bin` on D: (21 + 4 raw files):
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
3. [x] (delivered by #5070: scores parquets became stubs, ~25 GB per SEA-AD run) After the cache: the scores parquets are the larger disk target (CHS ~510 GB per search).

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

### 2026-11-21 - Narrowed #5067 to `--spectra-cache off`; the cache write is not cheap on a shared disk

PR [#5067](https://github.com/ProteoWizard/pwiz/pull/5067) opened, then narrowed on Brendan's review of the
numbers: the default first-run path stays the old read, write, read-back, and the read-ahead reader runs only
under `--spectra-cache off`, for both scoring and the re-score. The read-ahead cache write (3dc7d70e4b's
switch, made the default in the PR's first version) is removed: it saved 52 s of 13,217 s and raised scoring's
peak memory from 53.9 to 71.5 GB. Branch rebuilt on master as six cherry-picked commits (the original base was
#4950's tip, which master holds only as a squash), tree byte-identical, force-pushed with a lease.

Correction to the 2026-11-20 night entry: the cache writes' 1,207 s is the time of the write calls only. Their
cost to scoring is larger, because they share the RAID-5 HDD with the `.raw` reads (82 files, same disk):

| | Straight read (no cache) | Write cache from read-ahead | Difference |
|---|---|---|---|
| Read-ahead, summed over files | 15,196 s | 18,156 s | +2,960 s |
| Lanes waiting for spectra, summed | 5,435 s | 12,209 s | +6,774 s |
| PerFileScoring wall | 8,175 s | 9,526 s | +1,351 s |

So writing the cache costs scoring 1,351 s and saves the re-score ~4,970 s (6,695 -> 1,722 s) plus every later
run. Reading `.raw` itself costs scoring only +440 s (5.7%) over a cache hit. Untested ideas: a cache on a
different drive from the `.raw` (estimate ~11,300 s for a first run, within ~5% of a cache hit - an
extrapolation from these four arms, not a measurement), or writing caches after scoring's reads.

- Code review (`/code-review medium`): ten findings; fixed seven (stale cache under `off` in the re-score,
  `--task SpectraCache --spectra-cache off` writing nothing, a double demultiplexing read under `--demux`,
  a failed write failing scoring, the missing multiplexed-run warning and saved-cache line, read-ahead
  settings in the log); two dropped (mzML reads bypass the read gate; a resume can read ahead files it then
  skips); the memory cost resolved by the narrowing.
- Regression on the pre-narrowing branch: `regression-parallel.ps1 -Dataset All` 48 PASS / 0 FAIL / 1 SKIP in
  46:10 on MACS2 (`ai/.tmp/sessions/20261119-rawread/regression-5067.log`).
- Next: Brendan measures on UW25 (i9, 64 GB): `--spectra-cache off` with `OSPREY_READ_AHEAD` 1 vs 0 (and
  `OSPREY_READ_THREADS=1`). Windows are freed as the main search takes them; calibration holds the whole file.

### 2026-11-22 - UW25 (i9-14900, 32 threads, 64 GB) measurements, in progress

Timeline: `ai/.tmp/night-session-budget-20261122.md`; plan `ai/.tmp/sessions/20261122-uw25/PLAN.md`.
Runner: `Run-SeaAd.ps1 -InputFormat raw -SpectraCache off [-ReadAhead N] [-ReadThreads N]` (pwiz-ai 63a88517).
Exe: this branch with master merged LOCALLY for `--diskstamp` (#5066) and #5061 - 7a710ea537, not pushed -
snapshot `D:\test\osprey-runs\_bin\directread-7a710ea537`; 672/672 unit tests pass.

- Master baseline (c6f235a7c5), 82 mzML + caches, sequential: 7:20:18, private peak 33.1 GB, disk +184.6 GB;
  PerFileScoring 4:40 / FirstPassFDR 1:16 / PerFileRescoring 1:18 / SecondPassFDR 0:06; 101,513 precursors
  at 1% experiment FDR, 6,739 protein groups. `D:\test\osprey-runs\sea-ad\runs\seaad-82files-libdecoy-r1.0-default`
- Arm 1, 82 raw, `--spectra-cache off`, read-ahead defaults, sequential: running (started 19:05). Scoring ~4 min
  ahead of the baseline at file 36; private memory oscillates ~30-40 GB (baseline 25-33), no rising floor.
- Auto `--parallel-files` resolves to 1 file over SEA-AD `.raw` on 64 GB (FileParallelismResolver: largest
  input 8.5 GB x 3.0 = 23.8 GiB/file vs 0.8 x ~41 GB free); over the mzML it would be 2 (5.5 GB x 3.0). The
  estimate scales with the INPUT's size, and a `.raw` is 1.55x its mzML here, so cache-off runs get fewer lanes
  than a cached mzML run would. Night chain probes auto, then runs explicit 3 (fallback 2).
- Arm 1 DONE (2026-11-23 01:57): 6:51:35 vs master 7:20:18 (-6.5%). Scoring 15,582 vs 16,817 s (-7.3%);
  rescoring 4,841 vs 4,679 s (+3.5% - one reader, hidden behind ~59 s/file compute; MACS2's 4.9x came from
  8 lanes interleaving reads on RAID-5); FirstPassFDR 3,923 (3 lanes) vs 4,549 s (2 lanes, less free RAM -
  not a #5067 effect). Peak private 44.4 vs 33.1 GB. Disk +183.8 vs +184.6 GB (baseline caches pre-existed).
  OUTPUT IDENTICAL: fdrbench.pass1/pass2.tsv sha256 equal, 101,513 precursors, 90,123 peptides.
- DEFECT found and fixed (pwiz-directread 7e2234234a, local): `--spectra-cache off` ended argument parsing,
  so everything after it was ignored (arm 1 lost --perf-stats). Same bug on MASTER for `--no-prefilter`
  (`--no-prefilter --threads 7` runs 32 threads). Cause: bool-assignment expression lambdas bind to
  Func<..., bool> and return false; ParseArgs ignored Parse's false. Fix + guard + test; 656/0 tests and
  inspection passed before a low-memory reap - full test run still owed. Master needs the --no-prefilter fix
  too (separate PR or cherry-pick). Runner now passes --spectra-cache after --perf-stats.
- pf3 arm (`-ParallelFiles 3`, raw, cache off) running since 02:05; 43.5 GB private at 02:25 with 4.2 GB
  physical free - fits, barely. Results: `runs\seaad-raw-82files-libdecoy-r1.0-default-cacheoff-pf3`.
- pf3 DONE (2026-11-23 08:42; `-ParallelFiles 3`, raw, cache off, otherwise = arm 1): 6:37 vs arm 1 6:51 vs
  master 7:20. PerFileScoring 15,626 s vs 15,582 s - no gain from 3 lanes (a 15-min build overlapped it;
  D: 43% busy at only ~26 MB/s, CPU 71%: no spare capacity on a 32-thread i9). PerFileRescoring 4,112 s vs
  4,841 s (-15%, NOT the MACS2-style read contention predicted); FirstPassFDR 3,862 s; SecondPassFDR 220 s.
  Peak private 57.3 GB (scoring) vs 44.4 GB sequential - close to the 64 GB ceiling. Output identical again
  (same FDRBench sha256, 6,739 protein groups). Conclusion with Brendan: on a 64 GB i9, --parallel-files buys
  little; auto choosing 1 over .raw is right here, though it gets there via the input-size estimate.

### 2026-11-25 - updated to master, re-test started (UW25)

- Merged origin/master as bc391e44eb (brings #4997, #5057 vendor-reader speed-up, #5070 per-run first-pass
  models, #5064/#5068/#4996/#5074). Conflicts only where both sides added an argument beside each other
  (`--spectra-cache` / `--keep-scores-parquet` in OspreyCommandArgs.cs and the three CommandLine.html); kept
  both. Pushed with 7e2234234a (the parse fix). Gate: Debug build, 681/681 tests, inspection zero warnings.
- Why re-test: #5057 changes `SpectrumList_Thermo.cs` / `MsDataFileImpl.cs`, the reader direct read drives
  (its slow ~264 KB page-in pattern was MACS2's rescoring bottleneck, and pf3 showed D: 43% busy at ~26 MB/s);
  #5070 changes what PerFileRescoring reads and costs. All direct-read numbers above predate both.
- Plan: regression-parallel All (cache on by default, so goldens should hold) -> Release -VendorReader ->
  SEA-AD 82 raw `--spectra-cache off` sequential -> SEA-AD 82 master mzML+cache sequential (the 11-24 #5070
  run at 654c177acd is not current master: 28cb46209f added a best-single-feature safeguard after it).
- Re-test results (UW25, SEA-AD 82, sequential, exe bc391e44eb = #5067 + master incl. #5057, #5070). Regression-parallel
  All 49/0/0 (1:01:58). Runs `D:\test\osprey-runs\sea-ad\runs\seaad-raw-82files-libdecoy-r1.0-default-cacheoff{,-ra0}-bc391e44eb`;
  reference = #5070 run (654c177acd, mzML + caches), whose output is IDENTICAL to both (FDRBench sha256 2291af67.../046324bc...,
  102,676 precursors, 6,753 protein groups), so it stands in for master.

  | | #5070 mzML + cache | raw, cache off, read-ahead 1 | raw, cache off, read-ahead 0 |
  |---|---|---|---|
  | PerFileScoring | 22,982 s | 24,440 s (+6.3%) | 24,688 s (+7.4%) |
  | FirstPassFDR | 861 s | 882 s | 861 s |
  | PerFileRescoring | 3,022 s | 3,611 s (+19.5%) | 3,999 s (+32%) |
  | SecondPassFDR | 643 s | 647 s | 647 s |
  | total | 7:38 | 8:13 (+7.6%) | 8:23 (+9.8%) |
  | private peak (PerFileScoring) | 36.7 GB | 57.8 GB | 51.6 GB |
  | managed peak | 27.3 GB | 49.4 GB | 40.2 GB |
  | log gaps >= 30 s | 5 | 68 | 29 |
  | disk written | 25.0 GB | 25.0 GB | 25.0 GB |

  - Since #5070, the direct read costs time (+7.6%) where before it SAVED it (-6.5% vs master on 11-22). #5057's reader
    did not remove the read cost (not isolated).
  - Memory: #5070 made PerFileScoring the memory-critical phase (per-run training), and cache-off holds the whole
    file's spectra in that same phase (the cache path streams one window at a time). Whole-file residency is most of
    the +21 GB (read-ahead 0 still peaks 51.6 GB, +15 GB over the cache path); read-ahead 1 adds ~6 GB private /
    ~9 GB managed for ~10 min (and ~6.5 min of rescoring). 57.8 GB is ~6 GB short of 64 GB SEQUENTIALLY; cache off
    under --parallel-files would not fit here.
  - Disk: with #5070 a run writes ~25 GB either way; cache off now saves only the cache itself (SEA-AD ~371 GB on a
    first run from .raw, per the MACS2 cold-start arm), not per-run intermediates.
- 2026-11-26: changed `OSPREY_READ_AHEAD` default to 0 and added a memory note (no figures - Brendan: costs vary by
  machine; let people seeking disk savings measure on their own systems) to the `--spectra-cache` help
  (45878697fd); TestSubsetOptionVariants gains a read-ahead 0 leg. Merged Brendan's GitHub "Update branch"
  (eb0dddb080: #5062 vendor readers, #5080) as d1a6822195; gate 681/681, inspection clean; pushed. The UW25
  timings in the PR predate #5062.

### 2026-11-26 - Merged

PR #5067 merged as 05c33f5cfd (TeamCity Perf/Regression build #402 SUCCESS on d1a6822195; all 17 checks green).
Shipped: `--spectra-cache on|off` (default on, unchanged), the read-ahead reader for uncached inputs with
`OSPREY_READ_AHEAD` now defaulting to 0 and `OSPREY_READ_THREADS` 2, a help note that off needs more memory (no
figures, by design), and the argument-parse fix (arguments after `--spectra-cache off` or `--no-prefilter` were
ignored; `--no-prefilter` was broken on master too). Deferred: making a no-cache read the DEFAULT (plan item 2) -
after #5070 the direct read costs time and holds a whole file's spectra during per-run training, so a default
change would need window-at-a-time reads from `.raw`, the cache path's streaming model. A final SEA-AD re-run on
d1a6822195 (shipped defaults, includes #5062) was in progress at merge:
`D:\test\osprey-runs\sea-ad\runs\seaad-raw-82files-libdecoy-r1.0-default-cacheoff-d1a6822195` on UW25.
