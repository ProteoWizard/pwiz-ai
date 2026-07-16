# TODO: Osprey spectra.bin v4 — end-of-file index for cheap streaming build

**Status**: Backlog (follow-up to the Stages 1–4 streaming PR).
**Priority**: Medium — makes the per-window streaming *I/O*-efficient (the streaming PR
already made it *memory*-efficient).
**Created**: 2026-07-16
**Scope**: `pwiz_tools/Osprey/Osprey.IO/SpectraCache.cs` (writer + version),
`Osprey.IO/SpectraWindowIndex.cs` (`BuildFromCache`), `Osprey.Test/IOTest.cs`.

## Motivation
The Stages 1–4 streaming PR builds the per-window streaming index
(`SpectraWindowIndex.BuildFromCache`) by **walking every MS2 record's 48-byte prefix
front-to-back**, seeking past each peak blob — because the current **V3** format has no
offset index, just front counts (`nMs2`, `nMs1`) followed by sequential variable-length
records. That walk saves **memory** and **peak-decode CPU**, but the prefixes are scattered
across the whole ~6.3 GB file, so on a **cold HDD** the disk still scans the entire file to
locate windows (and OS read-ahead pulls much of it in) — it does *not* save build-time disk
I/O. So streaming currently reads the file roughly twice on a cold HDD: the header-walk to
build the index, then per-window peak loads during scoring.

Skyline's standard cache pattern — **an index at the end of the file** — fixes this: seek to
EOF, read one compact contiguous index, build the map from it alone, then touch only the
peaks of the windows actually scored. That turns "scan 6.3 GB of scattered prefixes +
re-read scored windows" into "read ~8 MB index + read scored windows."

## What to do
- **Bump `SpectraCache.VERSION` 3 → 4.** Writer (`SaveSpectraCache`) appends an index block
  after the MS1 section holding, per MS2 record, everything `BuildFromCache` derives:
  `{ fileOffset, isoCenter, isoLower, isoUpper, rt }` (≈ 40 B × nMs2 ≈ 8 MB on Astral), plus
  the MS1 section's offset + count. Record the index's start offset in the header (or a
  trailing 8-byte pointer at EOF, the classic "index at end" locator).
- **`BuildFromCache` (v4):** seek to the index, read it, build `windowKey→offsets` +
  `AllMs2Rts` + first-cycle `IsolationWindows` + load MS1 (from the recorded MS1 offset) —
  **no record walk**. Must produce a **byte-identical** index/map to the v3 walk
  (same `windowKeysInFileOrder`, same per-key first `IsolationWindow`, same `AllMs2Rts`,
  same first-cycle windows), so streaming output stays byte-identical.
- **V3 migration decision (pick one):**
  - *Dual-read* — `BuildFromCache` branches on version (v3 → walk, v4 → end-index); no forced
    re-parse; keeps two read paths for a while. (Recommended initially — zero migration cost.)
  - *Invalidate* — `TryReadHeader` rejects < 4 → one-time re-parse + re-cache per file on
    first use (a one-time HDD cost for a large corpus; single read path afterwards).
- **`LoadSpectraCache` (full loader, Stage 6):** confirm unaffected — it reads exactly
  `nMs2 + nMs1` records and ignores the trailing index bytes.
- **Co-design with the streaming-parse lever:** a v4 writer that tracks offsets as it writes
  is a step toward *never materializing on a cache miss* either (stream mzML → write records
  → append index), so keep the writer streaming-friendly. That parser rewrite is its own
  separate lever/TODO.

## Gates
- `regression.ps1 -Dataset All` (streaming output byte-identical to golden — the map must be
  identical whether built by walk or end-index).
- A v4 round-trip unit test (write v4, `BuildFromCache`, assert the map == the v3-walk map on
  the same spectra; extend `TestSpectraWindowIndex`).
- **Cold-HDD I/O measurement** (`BuildFromCache` wall-time + bytes read, v3-walk vs
  v4-index) on a large Astral file — this is the whole justification; prove it.

## Not in scope
- Stage-6 rescore streaming (separate TODO
  `TODO-osprey_stage6_rescore_spectra_streaming.md`).
- The streaming mzML→cache writer that avoids materializing on a cache *miss* (separate lever).

## Session startup (2026-07-16) — measure PR #4427 perf FIRST
Spun into its own session/branch off **master**, orthogonal to PR #4427 (#4427 = per-file MS2
streaming; this = the cache format). They merge cleanly later, NOT stacked. Before implementing v4,
**measure PR #4427's perf impact** to understand the streaming trade-off: on a v3 cache hit #4427
now SKIPS the full `List<Spectrum>` load and streams immediately (a real win — verify + quantify),
but pays extra HDD I/O from the header-walk + per-window re-reads. The night-session 88 vs 123 s A/B
is cache-warmth-confounded and invalid; a controlled cold/warm measurement is needed. That result
motivates v4 (the end-index removes the header-walk I/O).

**Next session handoff**: For the detailed startup protocol (perf-measurement method, v4 spec,
gates, key files), read `ai/.tmp/handoff-spectra-bin-v4.md` before starting work.

## Progress Log

### 2026-07-16 (session start: branch cut, STEP 1 warm A/B setup)
**Branch**: `Skyline/work/20260716_osprey_spectra_bin_v4_end_index`, cut off master
`fc148e446` -- which is the EXACT #4427 merge-base, i.e. the clean pre-#4427 baseline.
TODO moved backlog -> active (dated). No commits on the branch yet.

**STEP 1 measurement setup (warm-only, per Brendan's call -- quick pass, cold-HDD cost
deferred):**
- Built baseline (master, this checkout) + #4427 Release net8.0. #4427 lives in a throwaway
  worktree `C:\proj\pwiz-4427` @ `88dc80f5f` (`git worktree add`).
- Driver `ai/.tmp/measure-4427-warm.ps1` + `ai/.tmp/measure-4427-both.ps1`: single Astral file
  49, `--task PerFileScoring --perf-stats`, `OSPREY_LOG_MEMORY=1`. Forces re-scoring by deleting
  `.scores.parquet` + its `.PerFileScoring.osprey.task` sidecar each rep while KEEPING the warm
  6.3 GB `.spectra.bin` (cache hit = the load path under test) and `.calibration.json`. Warm-up
  rep discarded, 3 measured reps/arm, sequential arms (no CPU contention).

**Probe finding (baseline, 1 rep = 126.8s wall / 105.5s "All files processed"):** the baseline's
`[TIMING] mzML parsing: 23.7s (258.9 MB/s)` is NOT an mzML parse -- `swParse`
(PerFileScoringTask.cs:1612) wraps `LoadSpectra`, which hit the cache via `LoadSpectraCache`; the
MB/s is just computed against the mzML byte size. So that 23.7s is the **full 6.3 GB cache
DECODE** -- exactly the load slice #4427's `BuildFromCache` header-walk replaces. Other slices:
Coelution scoring 43.9s, calibration recomputes each run (~25s). This makes the per-slice A/B
signal clean: compare `[TIMING] mzML parsing` (load) + `Coelution scoring` + `All files
processed` (total) across arms.

**BRANCH-DEPENDENCY DISCOVERY (must resolve before STEP 2):** `SpectraWindowIndex.cs` -- the file
holding `BuildFromCache`, the reader the v4 TODO says to modify -- is **#4427-ONLY**; it does not
exist on master. The handoff's "orthogonal / not stacked / no file overlap with #4427" premise is
**wrong**: v4's writer (SpectraCache format) is on master, but v4's reader change requires #4427's
`SpectraWindowIndex`. So v4 must either be **stacked on #4427** or **deferred until #4427 merges
to master**. Branch has no commits yet -> cheap to re-base.

**DECISION (Brendan, 2026-07-16): STACK v4 on #4427.** #4427 will be merged to master BEFORE this
work; stacked-PR ordering worked out later. Re-base action: `git reset --hard 88dc80f5f` on the v4
branch (no commits to preserve), done AFTER the A/B completes so the running baseline measurement
(master exe out of `C:\proj\pwiz`) is not perturbed. At #4427 merge time: retarget v4 PR to master
+ `git rebase --onto master 88dc80f5f` (see [[feedback_stacked_pr_no_delete_branch]]).

**A/B result (warm, 3 reps/arm, Astral file 49, single-file `--task PerFileScoring`):**
- Total: baseline median **87.0s** wall / 79.0s all-files; #4427 **82.7s** wall / 75.4s all-files
  (#4427 ~5% faster warm).
- Load slice (`[TIMING] mzML parsing`): baseline **3.0s** warm (cold-probe was 23.7s, disk-bound
  at 258 MB/s -> warm it's memory-bound ~2 GB/s), #4427 **0.5s**. So the decode-skip is ~2.5s
  WARM -- it is really a COLD-cache win, not a warm one.
- Coelution scoring: 41.0 vs 41.9s (tied) -> the streaming per-window `LoadWindow` re-reads cost
  ~0 warm.
- Peak working set: baseline **25.9 GB** -> #4427 **18.8 GB** (~7 GB / ~28% lower); post-cal
  20.7 -> 11.3 GB. **#4427's real win is MEMORY, not warm speed.**

**STRATEGIC REFRAME (discussed w/ Brendan 2026-07-16):** all `spectra.bin` FORMAT work is a
COLD-HDD I/O optimization -- warm is already fine, and #4427 already banked the ~7 GB memory win.
Cold has TWO scattered-read costs: (A) the header-walk BUILD, (B) the per-window `LoadWindow`
re-reads during scoring (~1222 records/window strided across 6.3 GB x 167 windows). The planned
**v4 end-index removes (A) only**; **physical window-grouping** (writing each window's peaks
contiguously) removes (A) AND (B) = the HDD-optimal design, and is cheap to write since the miss
path already materializes the full list. Caveats for grouping: diverges cache bytes from Rust
(parity substrate; Rust retirement imminent so likely moot) and conflicts with the future
never-materialize streaming-writer lever.

### 2026-07-16 (COLD validation -- decisive; confirms the v4 design)
Evicted the OS standby cache with a self-contained 42 GB memory balloon
(`ai/.tmp/Clear-StandbyCache.ps1`; no external tool), then ran ONE cold rep per arm on Astral file
49. Self-validating: the cold load slice came back ~24-28s (vs 0.5-3s warm), confirming eviction
worked. Box has 63.7 GB RAM / 6.3 GB cache -> no eviction DURING a run.

| slice (all-files)  | base warm | base COLD | #4427 warm | #4427 COLD |
|--------------------|-----------|-----------|------------|------------|
| load (mzML parsing)| 3.0s      | 23.5s     | 0.5s       | 27.7s      |
| calibration pass-1 | 7.4s      | 7.4s      | 9.1s       | **206.8s** |
| coelution          | 41.0s     | 44.0s     | 41.9s      | 41.0s      |
| **total**          | 79.0s     | **103.8s**| 75.4s      | **300.3s** |

**Root cause of the cold cost (NOT the boundary walk):** #4427's boundary walk (27.7s) only warms
record *prefixes* -- `BuildFromCache` `Seek`s past every peak blob without reading it. So the FIRST
pass that actually touches peaks -- **calibration pass-1** -- pays the scattered-read cost:
~1222 records/window strided across 6.3 GB x 167 windows = **207s of cold HDD seek-thrash** (warm
9s). By coelution the file is warm (calib warmed it) -> 41s. Baseline instead reads the whole file
ONCE sequentially (23.5s) into a resident list, then computes in-RAM -> 104s cold.

**Findings:**
1. The ~20s boundary-walk estimate was right (27.7s), but the walk is NOT the dominant cold cost --
   the scattered per-window peak reads (cost B) are (207s).
2. **#4427 is a ~2.9x COLD-HDD speed regression** vs baseline (300s vs 104s) -- it traded ~7 GB
   memory for ~200s of cold I/O. Tests run on D: (HDD), so this is real. Flag for #4427.
3. **End-index alone would NOT fix it** -- removes only the 27.7s walk, leaves the 207s scattered
   reads (~272s cold, still a disaster).
4. **Physical window-grouping IS the fix** (validated): contiguous per-window peaks make calib
   pass-1's `LoadWindow` reads sequential -> the 207s collapses toward one sequential pass (~25-30s),
   recovering baseline-like cold speed WHILE keeping #4427's ~7 GB memory win.

**DESIGN CONFIRMED (Brendan): v4 = index + BLOCKED (window-grouped) spectra**, streamed through
memory by isolation window. This is STEP 2 -- NOT a bare end-index. Re-base onto #4427 next, then
design the grouped writer + grouped-read path in `BuildFromCache`/`LoadWindow`, byte-identical
output to the v3 walk.

### 2026-07-16 (STRATEGY: grouping folded INTO #4427 as a merge blocker; v4 implemented)
**Brendan's call:** the ~7 GB memory win of #4427 is NOT shippable with the ~2.9x cold regression
(cold is the default in HPC / first-pass runs). So the blocked-spectra fix becomes a **merge
blocker for #4427**, folded into that PR -- not a stacked follow-up. Retired the empty
`20260716_...v4` branch; the work now lives on the **#4427 branch**
(`Skyline/work/20260715_osprey_perfile_spectra_window_streaming`) in `C:\proj\pwiz`. The
`pwiz-4427` worktree stays pinned at `88dc80f5f` as the **pre-grouping baseline** for the cold A/B.
This TODO is the design/measurement record for that #4427 change (see also its own TODO).

**v4 format implemented** (`Osprey.IO/SpectraCache.cs`, `SpectraWindowIndex.cs`, `IOTest.cs`):
layout `[header][MS2 grouped-by-window][MS1][index: per-record {offset,iso*,rt} in ACQ order]
[footer: ms1_offset,index_offset]`. VERSION 3->4 (invalidates v3). `BuildFromCache` reads the
index (no walk); `LoadWindow` reads each window as one contiguous sequential run. `LoadSpectraCache`
(Stage-6 full loader) reads the grouped body in ascending-offset order (one forward pass) and
returns MS2 in **acquisition order** via the index -- so Stage-6 stays a resident load, NO Stage-6
streaming required to merge. Decisions locked: invalidate v3; grouped-but-acq-ordered LoadSpectraCache;
cross-impl shares no cache (output parity intact, Rust retiring).

**Gates so far:** unit tests GREEN (511 total, 508 passed, 3 cross-impl skipped, 0 failed) --
includes a new acquisition-order assertion (proves LoadSpectraCache reorders grouped->file order on
interleaved input) and a v3-rejection test. `TestNoUnstableSort` initially failed on an `Array.Sort`
in `BuildOffsetReadOrder` -> switched to stable `OrderBy` (offsets unique, no ties). Inspection: my
files clean; only `SystemMemory.cs` reddens (known local flake #4379, CI-green).

**Gates:** unit tests GREEN. **regression.ps1 -Dataset Stellar PASS all 3 modes** (mode1 vs golden,
mode3 HPC chain==straight, mode2 resume==straight) -> v4 grouped output byte-identical to golden,
incl. the cache write/re-read handoff across HPC tasks. Left a Release build in place.
**Remaining:** regression.ps1 -Dataset All (Astral) before merge; cold A/B on Astral file 49
(grouped vs `pwiz-4427` baseline 300.3s) to prove ~300s->~110s cold with memory held; Stage-6
rescore perf (offset-order full load must not regress).

**Index design note (Brendan asked):** the EOF index is PER-RECORD `{offset,iso*,rt}` (acq order),
not a per-block `{offset,size}` directory. The per-record rt/iso are needed to rebuild AllMs2Rts +
first-cycle windows without reading bodies (what the old walk read). The cold win comes from the
physical GROUPING (LoadWindow's contiguous per-window reads are sequential), independent of
per-record vs per-block indexing. A per-block directory (one ReadBytes(block) per window, leaner
~2.4 MB index) is an optional warm/overhead follow-up.
**DECIDED (Brendan): keep the per-record index + bump the read buffer** (option 1); the single
block-read isn't necessary. Applied a **1 MB explicit `FileStream` buffer** to all four cache
streams (was the 4 KB default) -- a ~31 KB peak blob << buffer, so prefix+peaks stream from one
refill and the 8 MB index reads in ~8. Skip the per-block directory.

### 2026-07-16 (COLD A/B RESULT -- fix validated, better than the original)
Grouped v4 (Release, 1 MB buffers), Astral file 49, cold (42 GB balloon evict), v4 cache hit:

| slice (all-files, COLD) | master resident | #4427 v3 streaming | grouped v4 |
|-------------------------|-----------------|--------------------|------------|
| load (mzML parsing)     | 23.5s           | 27.7s              | **0.1s**   |
| calibration pass-1      | 7.4s            | **206.8s**         | 11.6s      |
| coelution               | 44.0s           | 41.0s              | 45.7s      |
| **total all-files**     | 103.8s          | **300.3s**         | **85.4s**  |
| peak working set        | 25.9 GB         | 18.8 GB            | **17.4 GB**|

The 207s scattered-read thrash is gone (->11.6s; windows stream contiguously). Boundary build
0.1s (8 MB index, one read). Grouped v4 cold is **3.5x faster than the #4427 regression** AND
**~18% faster than master's resident load** (no 23.5s upfront full-decode stall -- the file is read
lazily during calibration/scoring), **while keeping the ~8 GB memory win** (17.4 vs 25.9 GB). So
#4427+grouping beats master on both cold speed and memory.

**Remaining:** warm grouped confirm (no warm regression vs #4427 75.4s); Stage-6 rescore perf;
regression.ps1 -Dataset All (Astral); then commit + push to #4427.

### 2026-07-16 (WARM regression found + FIXED -> buffer reverted to default; FINAL numbers)
The 1 MB buffer decision above was WRONG. Warm grouped came in ~85s vs #4427's ~76s -- a ~9s
regression, all in coelution (47.8 vs 41.9s, 35.6K vs 40.6K cand/s), reproduced same-session
(re-measured #4427 warm = 77.3s, matching its 75.4s). Ruled out machine drift (compute-only RT
calibration flat) and LOH/GC (64 KB buffer -- off-LOH -- did NOT help).

**Root cause:** a buffer LARGER than the ~31 KB peak blob is counterproductive. At the DEFAULT 4 KB,
`ReadBytes(peaks)` is >buffer so it reads DIRECT into the array (single copy). A 64 KB/1 MB buffer
pulls all ~6 GB of peaks THROUGH the buffer (double copy). Cold hid it (disk-bound), warm exposed it.
**Reverted all four FileStreams to the default buffer.** Documented in-code (SpectraCache.cs NOTE +
a pointer at LoadWindow) with the numbers so nobody re-tries a bigger buffer. The single block-read
(Brendan's "ensure sequential reads" idea) is NOT needed -- default-buffer direct reads already do a
single copy; grouping already gives sequential.

**FINAL numbers (grouped v4, DEFAULT buffer -- all one build), Astral file 49:**

| slice (all-files)   | master resident | #4427 v3 | grouped v4 COLD | grouped v4 WARM |
|---------------------|-----------------|----------|-----------------|-----------------|
| load (mzML parsing) | 23.5 / 3.0      | 27.7/0.5 | 0.2s            | 0.0s            |
| calibration pass-1  | 7.4             | 206.8    | 11.5s           | 8.9s            |
| coelution           | 44.0 / 41.0     | 41.0/41.9| 43.1s           | 42.4s           |
| **total all-files** | 103.8 / 79.0    | 300.3/75.4| **79.0s**      | **76.6s**       |
| peak working set    | 25.9 GB         | 18.8 GB  | 17.4 GB         | 17.4 GB         |

Default buffer beat the 1 MB buffer on BOTH axes (cold 85.4->79.0, warm 84.7->76.6). **Grouped v4
final: COLD 79.0s (3.8x vs #4427's 300.3s; ~24% faster than master's resident 103.8s -- cold now
≈ master's WARM), WARM 76.6s (matches #4427, no regression), peak 17.4 GB.** Wins on every axis.
Unit tests 508/508 green on the final build.

**Remaining before merge:** Stage-6 rescore perf (offset-order full load vs v3); regression.ps1
-Dataset All (Astral byte-identity); commit + push to #4427.
