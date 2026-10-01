# TODO: SEA-AD 82-file end-to-end on the .NET 10 port branch at --parallel-files 3

## Branch Information
- **Branch**: `Skyline/work/20260612_net8_port` (PR [#4619](https://github.com/ProteoWizard/pwiz/pull/4619), "Port ProteoWizard core to .NET 10")
- **Pinned commit for this measurement**: `5bd83dae8b7b2347c8b9f60bac020c46199699b7` (2026-09-25, "pwiz: Reverted the Spectronaut parquet support pushed by mistake")
- **Base**: `master` (branch was 1 commit behind master at pin time)
- **Created**: 2026-09-25
- **Status**: COMPLETE - ran 2026-09-25 21:58:04 -> 2026-09-26 02:57:27 PDT (4h59m23s); both correctness anchors exact
- **Module**: `osprey`
- **PR**: none of our own; we are MEASURING #4619, not modifying it
- **Worktree**: `D:\Users\brendanx\proj\pwiz-net10`, local branch `net10port-par3`, reset to the pinned SHA and clean

## Goal

End-to-end 82-file SEA-AD numbers from the **.NET 10 port branch** on MACS2 at
`--parallel-files 3`, as a starting point for further analysis. Brendan is running
**the same analysis on two other machines** and wants to compare all three in the
morning, so the configuration must be recorded exactly and reproduced exactly.

This is a measurement of the port branch, NOT a concurrency A/B. Do not present it
as comparable to the 4h29m `--parallel-files 4` figure from 2026-09-10: that ran on
master-lineage code, at a different concurrency, before eight Osprey commits landed.

## The configuration being measured (record this with any result)

| | |
|---|---|
| host | MACS2 |
| cpu | 2 x Intel Xeon Gold 6354 @ 3.00GHz - 36 cores / 72 threads |
| RAM | 511.5 GB |
| OS | Windows Server 2022 Standard 10.0.20348 |
| branch / commit | `Skyline/work/20260612_net8_port` @ `5bd83dae8b` |
| target framework | **net10.0** (the branch name says net8; the target moved to .NET 10) |
| dataset | SEA-AD, 82 files, from `.spectra.bin` caches on D: |
| library | `lib/astral/target+decoy+entrapment-20260817` |
| arm | `-DecoyMode libdecoy -Ratio 1.0` |
| concurrency | `--parallel-files 3`, `--threads 72` (threads are DIVIDED across files, so ~24/file) |

## Reference numbers from this machine (different code, different concurrency)

From 2026-09-10 on master-lineage code, for orientation only:

| stage | sequential | par4 |
|---|---|---|
| PerFileScoring | 15,340.1 s | 7,223.1 s |
| FirstPassFDR | 4,173.7 s | 4,086.3 s |
| PerFileRescoring | 7,905.4 s | 4,163.3 s |
| SecondPassFDR | 689.7 s | 662.5 s |
| **total** | **28,109 s (7h48m)** | **16,135 s (4h29m)** |

Correctness anchors that a good run should reproduce: **353,085,961 scored entries**,
and `pass1_fdp.py` pass-1 experiment-scope `q=0.0100 n=45943 combinedFDP=0.7460%`.
A different scored-entry count is a red flag worth stopping for.

## Progress Log

### 2026-09-25 - Set up, not yet run

Established the branch state and prepared the worktree. Nothing built or run yet.

**A serious false start worth recording.** The remote-tracking ref for this branch
was corrupted locally - the same ref stored twice with different values (loose
`5d27353235`, packed-refs `5c046bdb7a`), so every `git fetch` failed its
compare-and-swap and silently left a **two-week-old** view of the branch. On that
stale data I reported that #4619 lacked #4652 and #4680, was 23 commits behind, and
carried a different `ParquetNet.dll`, and I began merging master into it. All of
that was wrong; Brendan stopped it. The real tip has both parquet fixes and the
same DLL as master, and was 1 commit behind. The merge was aborted, nothing pushed.

Lesson: **read fetch output.** The first fetch printed
`error: cannot lock ref ... is at X but expected Y` and I proceeded anyway. When a
branch's history looks implausibly stale, verify against `git ls-remote origin
<ref>` or `gh api repos/ProteoWizard/pwiz/pulls/<N> --jq .head.sha` before drawing
any conclusion.

The ref broke again on a later plain `git fetch origin` in the worktree, so it is
not a one-off. **Pin the SHA rather than trusting the ref.**

### 2026-09-26 (night session) - Built, launched at 21:58:04 PDT

**Build.** `pwiz_tools/Osprey/build.ps1 -Configuration Release` (with tests) in the
`pwiz-net10` worktree at the pinned SHA. **598/598 tests passed**, exit 0.
Worktree SHA verified against ground truth before building:
`git ls-remote origin refs/heads/Skyline/work/20260612_net8_port` ->
`5bd83dae8b7b2347c8b9f60bac020c46199699b7`, an exact match for the pin. No `git fetch`
was run in the worktree, so the corrupted-ref trap was not re-entered.

**Exe snapshot.** `D:\Users\brendanx\test\osprey-runs\_bin\26.1.1.268-net10port-par3-5bd83dae8b`
- `Osprey.exe --version` -> `Osprey v26.1.1.268 (5bd83dae8b)`.

**Pre-flight.**
* `Test-SpectraCache.ps1`: 82/82 v4, 0 REJECT / 0 INCOMPLETE. All report PENDING because
  the mzML are not local - the directory is **cache-only**, 348 GB of `.spectra.bin` and
  nothing else. The runner handles this and the banner says so.
* `-WhatIf` confirmed exe, 82 inputs, the `target+decoy+entrapment-20260817` library with
  its pairing manifest, `--output-dir` (not `--work-dir`), and the learned pick model.
* `Clear-StandbyCache.ps1`: 459.9 -> 417.9 GB available.
* Harvest toolchain verified up front: Python 3.12.10, pyarrow 25.0.1, all five readers load.

**Launch.** 2026-09-25 **21:58:04 PDT**, via `Run-SeaAd.ps1` (the sanctioned runner),
backgrounded through the harness so completion notifies.

Osprey's own log confirms the configuration:
* `82 of 82 input(s) are absent but have a spectra cache; reading those from the cache.`
* `Osprey v26.1.1.268 (5bd83dae8b)`
* banner `files at once: 3   threads 72 -> ~24 per file`
* `--parallel-files 3 --threads 72 --model-diagnostics --fdrbench-pass both --decoys-in-library`

Run directory:
`D:\Users\brendanx\test\osprey-runs\sea-ad\runs\seaad-82files-libdecoy-r1.0-protein-compactnet10port-par3\`

**Status**: PerFileScoring in flight.

### 2026-09-26 - RESULT: run completed in 4h59m23s, both correctness anchors EXACT

Completed 2026-09-26 **02:57:27 PDT**, exit 0, `Analysis complete in 4 hours 59 minutes`.
Run dir (184 GB):
`D:\Users\brendanx\test\osprey-runs\sea-ad\runs\seaad-82files-libdecoy-r1.0-protein-compactnet10port-par3\`

#### The configuration, for the three-machine comparison

| field | value |
|---|---|
| host | MACS2 (Dell PowerEdge R650) |
| cpu | 2 x Intel Xeon Gold 6354 @ 3.00 GHz |
| cores / threads | 36 / 72 |
| RAM | 511.5 GB |
| OS | Windows Server 2022 Standard 10.0.20348 |
| branch | `Skyline/work/20260612_net8_port` (PR #4619) |
| commit | `5bd83dae8b7b2347c8b9f60bac020c46199699b7` |
| Osprey version | `26.1.1.268 (5bd83dae8b)` |
| TFM | **net10.0** |
| dataset | SEA-AD 82 files, **cache-only** `.spectra.bin` on local D: (no mzML on disk) |
| library | `lib/astral/target+decoy+entrapment-20260817` (measured r = 0.9998) |
| arm | libdecoy, r=1.0, pass2 `protein-compact`, pick = learned LDA (Osprey default) |
| other levers | expagg `max`, qualify `run`, SVM C-sel default, model-diagnostics ON, fdrbench `both` |
| concurrency | `--parallel-files 3`, `--threads 72` (~24 per file) |
| exe snapshot | `_bin\26.1.1.268-net10port-par3-5bd83dae8b` |

#### Stage times

| stage | this run (par3, port) | seq ref | par4 ref |
|---|---|---|---|
| PerFileScoring | **8,153.5 s** (2:15:54) | 15,340.1 s | 7,223.1 s |
| FirstPassFDR | **4,015.7 s** (1:06:56) | 4,173.7 s | 4,086.3 s |
| PerFileRescoring | **4,127.9 s** (1:08:48) | 7,905.4 s | 4,163.3 s |
| SecondPassFDR | **1,663.0 s** (0:27:43) | 689.7 s | 662.5 s |
| **total** | **17,960.1 s / wall 4:59:23** | 28,109 s (7:48) | 16,135 s (4:29) |

The references are 2026-09-10, master-lineage code, different concurrency. They orient;
they are not an A/B. **Cross-machine comparison at this exact configuration is the point.**

#### Correctness - both anchors reproduced EXACTLY

* scored entries: **353,085,961** - `Coelution analysis complete. 353085961 total scored
  entries across 82 files`. Anchor is 353,085,961. **Exact.**
* `pass1_fdp.py` pass-1 experiment scope: **`q=0.0100 n=45943 combinedFDP=0.7460%`**
  (pairedFDP 0.7221%). Anchor is `q=0.0100 n=45943 combinedFDP=0.7460%`. **Exact.**

So the .NET 10 port reproduces the reference discovery set on this cohort. That is the
headline correctness result and it is not a near-match.

Full pass1_fdp (quote pass 1, not pass 2 - pass-2 inflation is a known open issue):

| view | q | n | combinedFDP | pairedFDP |
|---|---|---|---|---|
| pass 1, experiment | 0.0100 | 45,943 | 0.7460% | 0.7221% |
| pass 1, run | 0.0100 | 70,355 | 8.5377% | 8.1301% |
| pass 2, experiment | 0.0098 | 54,218 | 1.0495% | 1.0219% |
| pass 2, run | 0.0100 | 92,321 | 8.1150% | 7.8057% |

Matched-true-FDP counts, pass-1 experiment: n=44,609 at FDP<=0.650%; **n=45,943 at
FDP<=0.750%**; n=48,166 at FDP<=1.000%.

Reproducibility (`runcount_fdp.py`): at >= half the runs (>=41), experiment scope
nPept=23,399 at **FDP 0.11%**; perRun 23,477 at 0.11%. High-run-count peptides stay clean.

`compute_pass2_fdp.py` at reported q: q<=0.010 -> N_T 54,367, N_E 293, combinedFDP 1.072%.

#### Memory / observability (`perfviz.py --files 82`)

```
duration      : 4:59:23  (21:58:04 -> 02:57:27)
reporting gap : max 30s   median 5s   p95 11s
gaps >= 30s   : 1   <-- OVER THRESHOLD
      30s at 01:22:58 after: [1] 66%  [28] 65%  [55] 64%
managed MB    : peak 34.8 GB   floor  6.5 ->  4.0 GB   drift  -2.57 GB   -32 MB/file  FALLING
total MB      : peak 46.8 GB   floor 21.8 ->  9.2 GB   drift -12.66 GB  -158 MB/file  FALLING
per phase       managed p10 / p50 / peak      private peak
  PerFileScoring      8.1 / 18.9 / 34.8 GB     46.8 GB   135:54
  FirstPassFDR        9.0 / 11.3 / 15.3 GB     25.2 GB    66:55
  PerFileRescoring    9.9 / 12.6 / 22.3 GB     35.4 GB    68:48
  SecondPassFDR       4.2 /  5.0 / 11.7 GB     21.8 GB    27:43
```

Reading these against the recorded goals:

* **Peak private 46.8 GB - INSIDE the "82 files inside 52.1 GB on a 64 GB box" goal.**
  par4 at 82 files needed 66.1 GB, well over it. At par3 on this branch the run would fit
  a 64 GB box. The peak is in PerFileScoring; no later stage approaches it.
* **`gaps >= 30s` = 1, and it is exactly 30 s.** The gate fails, but the sequential
  baseline on this machine was already failing with 3 gaps, so this is an improvement, not
  a new regression. The single gap is at 01:22:58, ~2 min into PerFileRescoring.
* **Both floors FALL across the run** (-32 MB/file managed, -158 MB/file total). That is
  the bounded-sawtooth shape, not O(files) accumulation - the scaling question is clean.

#### The one thing that stands out: SecondPassFDR is 2.4x the reference

**1,663.0 s here vs 689.7 s sequential and 662.5 s par4.** Every other stage lands at or
better than its par4 reference; this one is 2.4x worse. It is the only stage that moved in
the wrong direction, and concurrency is an unlikely explanation because SecondPassFDR
barely responds to `--parallel-files` in the references (689.7 -> 662.5 from seq to par4).

That leaves the port itself or one of the eight Osprey commits between the references and
this SHA. It is NOT explained by memory pressure: SecondPassFDR ran at the lowest
footprint of any stage (11.7 GB managed peak, 21.8 GB private).

This does not touch correctness - both anchors are exact - and at 27 min it is 9% of the
run. Flagging it as the one measured regression worth attributing before it grows.

### 2026-09-26 - Investigation: where the SecondPassFDR 1,663 s actually goes

> **SUPERSEDED IN PART** - see "Comparability control" below. The FileSaver hypothesis
> is WITHDRAWN, and the "2.4x regression" framing overstated the evidence: the reference
> ran on a different .NET runtime. The sub-step decomposition below is still valid.

Decomposed the stage from `run.log` timestamps rather than leaving "2.4x slower" as the
finding. **No single sub-step dominates** - the stage is ~18 steps and the largest is 13%:

| sub-step | dur |
|---|---|
| compute 2nd-pass FDR scores from reconciled features (0/82 precomputed) | 158 s |
| `protein-compact`: streaming the competition over 82 files | 179 s |
| `protein-compact`: writing experiment q to 82 files | 46 s |
| protein FDR: collecting best scores over 82 runs | 130 s |
| protein parsimony (6,349 groups) + 1% protein FDR | ~1 s |
| patching pass-2 protein q into 82 sidecars | 22 s |
| writing experiment-scope FDR sidecar | 8 s |
| **per-replicate protein FDR over 82 runs** | **213 s** |
| selecting peptides passing experiment FDR over 82 files | 123 s |
| selecting charge states passing precursor FDR over 82 files | 128 s |
| collecting passing entries over 82 files | 130 s |
| resolving shared peak boundaries (4,480,674 entries) | 4 s |
| blib writes (54,660 spectra; 4,480,674 RT rows) | 19 s |
| writing FDRBench pass-2 input over 82 runs | 136 s |
| classifying 6,175,389 library entries for model diagnostics | 19 s |
| **folding pass-2 diagnostics over 82 runs** | **178 s** |
| **building pass-2 co-assignment over 82 runs** | **130 s** |
| total | **1,663 s** |

**The shape matters more than any one number.** To get from 1,663 s to the reference
662.5 s, essentially *every* step has to be ~2.5x faster. A broad, across-the-board tax
fits that; one slow algorithm does not. That reframes the candidate list.

#### What is ruled OUT

* **Configuration.** The reference run dir was `seaad-82files-libdecoy-r1.0-protein-compactpar4`
  - same dataset, same arm, same `protein-compact` pass-2 mode. And the reference TODO
  reports `pass1_fdp.py` numbers for both 09-10 runs, which can only come from a
  `--model-diagnostics` report, so mdiag was ON there too. Not a diagnostics-newly-enabled
  artifact.
* **Concurrency.** SecondPassFDR is nearly concurrency-insensitive in the references
  (689.7 s sequential -> 662.5 s at par4, 1.04x). par3 vs par4 cannot produce 2.5x.
* **Memory pressure.** This stage had the *lowest* footprint of the run - 11.7 GB managed
  peak, 21.8 GB private, on a 511 GB box. Nothing was paging.
* **The pass-1 FDRBench emitter (#4661).** It is new since the reference (pre-#4507 runs
  wrote no `fdrbench.pass1.tsv`), but the log shows only the *pass-2* emitter inside
  SecondPassFDR; pass-1 emission lands in an earlier stage.
* **#4642 / #4646** (SecondPassFDR fold-over-runs, Stage-7 join run-by-run) - both landed
  2026-09-08/09, so they are already IN the reference.

#### Candidates, in order

1. **#4694 `17e5945523` (09-23) "Made artifact file writes go through FileSaver."**
   Best fit for a *broad* tax: SecondPassFDR is by far the most write-heavy stage (82
   sidecar patches, the blib, the FDRBench TSV, protein groups, stats, the mdiag report),
   and FileSaver turns each artifact write into write-temp-then-move. It also touched
   `FdrDiagnostics.cs` (+110) and `PercolatorDiagnosticsDump.cs` (+160). No env-var kill
   switch exists - the only new variable is `OSPREY_KEEP_FAILED_WRITES`.
2. **#4662 `06ae566254` (09-15) "Stopped the diagnostics fold and the pass-2 q floor
   re-deriving per file."** The only post-reference commit that rewrites
   `ModelDiagnosticsData.CoAssignment.cs` (363 lines) and adds `ExperimentQFloors.cs`
   (205) and `FdrExperimentAccumulator.cs`. Those files emit, by name, the
   `experiment-q floors: folded ...`, `Folding pass-2 diagnostics` (178 s) and
   `Building pass-2 co-assignment` (130 s) lines - **308 s, 19% of the stage.** Worth
   noting it was *intended* as a de-duplication speedup. Ships `OSPREY_MDIAG_COASSIGN_ONLY`
   and `OSPREY_LOG_COASSIGN_ALLOC` as diagnostics.
3. **net10.0 itself.** The TFM moved. A uniform ~2.5x on a write- and fold-heavy stage,
   with every other stage at or better than its reference, would be odd for a runtime
   change - but it is the one variable that applies to every sub-step at once, so it
   cannot be dismissed without an experiment.
4. Lesser: **#4656** (`7af9eb0ea5`) and **#4679** (`e904ed8e95`) both touch Stage 7
   adjacent code, but their diffs land mostly in PerFileScoring / FirstPassFDR /
   PerFileRescore, and those three stages all came in at or better than reference.

#### The decisive experiment (NOT run tonight - see why)

Cheapest first, all Stage-7-only so each is ~25-45 min, not a re-run:

1. `-Task SecondPassFDR -LinkFrom <this run> -NoModelDiagnostics` on this same SHA.
   If the stage drops by roughly the 308 s the mdiag path costs and no more, #4662 is
   bounded out as the main cause and #4694 / net10.0 move up.
2. Same harness, but build the 09-10 reference tip and run Stage 7 against the *same*
   linked inputs. That is a true single-stage A/B and settles code-vs-runtime.
3. If still open, bisect #4694 -> #4662 with the same harness.

**Why I did not run these tonight.** `-LinkFrom` hard-links the Stage 1-5 caches, so the
new run's directory shares inodes with this completed run. By design only Stage 7 is
regenerated and the linked inputs are read-only, but a mistake there damages the night's
only deliverable - the 184 GB harvested run these numbers come from. That is the
developer's call to make, not a 3 AM unsupervised one. Also note the SEA-AD README's
warning that a *full* resume (every `.1st-pass` sidecar on disk) under `--model-diagnostics`
forces the resident pool; run both arms identically so that cost cancels.

### 2026-09-26 - PASTE-READY: one row per machine

This is the single table the three-machine comparison goes in. Fill the two empty columns
from the other boxes; every field is recorded so nothing has to be reconstructed.

| field | MACS2 (this run) | machine 2 | machine 3 |
|---|---|---|---|
| host | MACS2 (Dell PowerEdge R650) | | |
| cpu | 2 x Intel Xeon Gold 6354 @ 3.00 GHz | | |
| cores / threads | 36 / 72 | | |
| RAM | 511.5 GB | | |
| OS | Windows Server 2022 Standard 10.0.20348 | | |
| branch | `Skyline/work/20260612_net8_port` (PR #4619) | | |
| commit | `5bd83dae8b` | | |
| Osprey version | `26.1.1.268 (5bd83dae8b)` | | |
| TFM | net10.0 | | |
| dataset | SEA-AD 82 files, cache-only `.spectra.bin`, local D: | | |
| library | `target+decoy+entrapment-20260817` (r measured 0.9998) | | |
| arm | libdecoy r=1.0, pass2 protein-compact, pick learned LDA | | |
| `--parallel-files` | 3 | | |
| `--threads` | 72 (~24/file) | | |
| PerFileScoring | 8,153.5 s | | |
| FirstPassFDR | 4,015.7 s | | |
| PerFileRescoring | 4,127.9 s | | |
| SecondPassFDR | 1,663.0 s | | |
| **total (sum of stages)** | **17,960.1 s** | | |
| **wall clock** | **4:59:23** (21:58:04 -> 02:57:27) | | |
| scored entries | **353,085,961** (anchor: exact) | | |
| pass-1 FDP (experiment) | **q=0.0100 n=45,943 combinedFDP=0.7460%** (anchor: exact) | | |
| pass-1 pairedFDP | 0.7221% | | |
| perfviz peak private | **46.8 GB** | | |
| perfviz peak managed | 34.8 GB | | |
| perfviz `gaps >= 30s` | **1** (exactly 30 s, at 01:22:58) | | |
| output size | 184 GB | | |

Two notes so the comparison is not misread:

* **Wall clock 4:59:23 is 3 s longer than the stage sum** (17,963 s vs 17,960.1 s). Startup
  and teardown, not a missing stage.
* **Compare like for like.** Every column above must match across machines before the
  totals mean anything - especially TFM, `--parallel-files`, `--threads`, pass-2 mode and
  the pick model, since `pick` and `qualify` MOVE the discovery set. If another machine
  ran the legacy product-form pick, its ID counts are not comparable at all.

### 2026-09-26 - Filed: the single `gaps >= 30s` violation, characterized

The README says a long run's findings get filed while the log is still on disk, so this
is the one gate violation, run down rather than just counted.

**Where.** Exactly one gap, exactly 30 s, `01:22:58 -> 01:23:28` - about 2 minutes into
PerFileRescoring, while all three lanes sat at ~65%.

**What happens across it.** Memory roughly doubles during the silence:

```
[01:22:58]   7801 MB managed   15517 MB total    [1] 66%  [28] 65%  [55] 64%
        <-- 30 s, no output -->
[01:23:28]  15770 MB managed   32728 MB total    [1] 66%  [28] 68%  [55] 66%
[01:23:52]  13228 MB managed   34369 MB total    [1] 100% [28] 100% [55] 100%
```

Managed 7.8 -> 15.8 GB and total 15.5 -> 32.7 GB in one step, then all three lanes run
65% -> 100% in the next 24 s and the stage moves on to files 2/29/56.

**Reading.** This is not a stall in per-file work - it is **one-time shared hydration at
the start of PerFileRescoring**, done once for the stage, not per file. It allocates
~17 GB, emits no progress line while it runs, and once it is resident the first file in
every lane finishes almost immediately. It also sets PerFileRescoring's private peak
(35.4 GB); the stage's p10 floor is only 9.9 GB.

**Why it is worth filing even though the run passed.** Per the memory-band guide a gap is
an observability failure, not a throughput one: 30 s of 17,963 s is 0.17% of the run, but
no watchdog can be tuned below the largest gap, and during this one a reader cannot
distinguish "hydrating" from "hung" - while memory doubles, which is exactly when someone
watching would worry.

**It is not the par4 gap.** The 2026-09-10 par4 run recorded "one new marginal 30 s gap at
the very end of SecondPassFDR". This one is at the *start of PerFileRescoring*. Different
place, so it is a distinct observation, not the same known gap re-surfacing.

**Net vs the recorded baseline: better.** The sequential baseline on this machine was
already failing this gate with 3 gaps. This run has 1, and it is exactly at the 30 s
threshold rather than over it. Suggested fix is a progress line (or a memstamp tick)
around the hydration step so the stage is never silent for 30 s.

### 2026-09-26 - Comparability control: the reference was a DIFFERENT RUNTIME

Brendan pushed back on the FileSaver hypothesis and asked for a real side-by-side before
trusting a comparison of "prior numbers vs the latest run". Both points were right.

#### 1. FileSaver hypothesis: WITHDRAWN

`FileSaver` allocates a **sibling temp in the same directory** and commits with
`File.Delete` + `File.Move` - a rename, not a copy. The bytes are written exactly once;
the added cost is two metadata ops per artifact. There is no I/O tax to find. And #4694's
diff does not touch the Stage-7 path at all: it is `PercolatorDiagnosticsDump`,
`PickCandidateDump`, `OspreyFileDiagnostics`, `PeakDataExtractor`, `FdrDiagnostics` and
`PerFileScoringTask`, plus the one-shot `-d` dumps this run never enabled. Its own commit
message says it converted the *remaining* raw writes - most artifacts already went through
FileSaver before it.

#### 2. The reference numbers are from net8.0, this run is net10.0

`<TargetFrameworks>net472;net8.0</TargetFrameworks>` at `56bae86901` (2026-09-10, the
reference date) vs net10.0 at the pin. The Osprey tree moved to net10.0 on **2026-09-12**
(`3114ac1049`, #4588) - AFTER the reference run.

**So every stage comparison in this TODO against the 2026-09-10 numbers conflates the
.NET runtime with 30 Osprey commits.** That is a real limitation of the whole reference
table, not just of the SecondPassFDR row. I found it only because the arm-B build emitted
`Release\net472` and `Release\net8.0` instead of `net10.0`.

I had earlier written "same TFM at both points, so this A/B isolates code" - that was
wrong. I grepped `TargetFramework` in `Osprey.csproj`, got no hit at either commit, and
read "both empty" as "both the same". The property lives in `Directory.Build.props`.

#### 3. Harness control: LinkFrom-isolated stage time carries a ~+10% bias

`--task FirstPassFDR -LinkFrom <the par3 run>`, same exe, same inputs, same machine:

| measurement | FirstPassFDR |
|---|---|
| inside the full par3 run | 4,015.7 s |
| LinkFrom-isolated re-run | **4,422.2 s** |
| difference | **+406.5 s, +10.1%** |

The isolated re-run is ~10% SLOWER, plausibly because a resume must hydrate the library
and caches the full run already had warm. Two consequences:

* **Stage-time comparisons carry ~10% uncertainty**, so small deltas (FirstPassFDR 4,015.7
  vs 4,086.3; PerFileRescoring 4,127.9 vs 4,163.3) are **noise, not signal**. Do not read
  them as "slightly faster than par4".
* **10% does not explain 2.4x.** The SecondPassFDR gap survives this control.

It also re-confirmed the anchor off the linked Stage 1-4 caches: `353085961 total scored
entries`.

#### 4. Disk: D: sustained write is ~342 MB/s, and small probes lie

Measured on an idle box, incompressible data, `buffering=0` + `fsync`:

| size | throughput |
|---|---|
| 512 MiB | 1,618 MB/s |
| 2 GiB | 1,276 MB/s |
| **8 GiB** | **342 MB/s** |

A textbook SLC-cache exhaustion curve. 342 MB/s sustained matches the ~280-500 MB/s
already recorded for D:. **Anything under ~2 GiB measures the cache, not the disk** - which
is exactly the trap the MACS2 storage memory warns about. Brendan reports this machine has
unresolved disk issues, so this is a live confound for the most write-heavy stage.

#### Where SecondPassFDR stands now

Still 1,663.0 s against a last-recorded 662.5 s, and the +10% harness bias does not close
that. But the cause is **unattributed**, and there are now three live candidates, none
eliminated:

1. **The net10.0 runtime** - newly the leading candidate, since the TFM provably changed
   after the reference.
2. **Disk** - sustained D: is 342 MB/s and the machine has known unresolved issues;
   SecondPassFDR is the most write-heavy stage.
3. **The 30 Osprey commits**, of which #4662 remains the only one rewriting the
   co-assignment fold (308 s of the stage by name).

Next, in order: the par4 run now in flight gives a **free replicate of SecondPassFDR on
identical code** - if it lands near 1,663 s the stage time is reproducible and not disk
noise; if near 660 s, last night's was an outlier. Then `--task SecondPassFDR` repeated on
the new exe for a variance estimate, and the old net8.0 exe
(`_bin\old-net8-56bae86901`, already built) for the runtime-vs-code split.

### 2026-09-26 - par4 A/B (in progress): PerFileScoring is 1.33x faster than par3

Same exe snapshot, same library, same arm, same machine - the ONLY variable is
`--parallel-files`. Run dir: `...-protein-compactnet10port-par4`, started 09:22:46.

| stage | par3 | par4 | ratio |
|---|---|---|---|
| PerFileScoring | 8,153.5 s | **6,124.6 s** | **1.33x** |

Anchor matched a third time: `353085961 total scored entries across 82 files`.

**This is real signal, not noise** - 33% is far outside the +10.1% floor the FirstPassFDR
control measured.

**It also contradicts the extrapolation from the 8-file sweep.** That sweep
(`TODO-20260909_osprey_parallel_parquet_write.md`) measured N=1/2/4/8 and never N=3;
interpolating its par2->par4 (1.12x) suggested par3->par4 would be single-digit percent.
At 82 files it is 33%. **The small-cohort sweep understates par4's benefit at production
scale** - which is precisely why this finer-grained 82-file test was worth running.

Secondary: today's par4 PerFileScoring (6,124.6 s) is **1.18x faster than the 2026-09-10
par4 reference** (7,223.1 s) at the same concurrency, cohort and machine. Different code
AND runtime (net8.0 -> net10.0), so unattributed - but it means the new stack is *faster*
for scoring, which makes SecondPassFDR's 2.4x more anomalous, not less.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260925_seaad_par3_net10port.md` before starting work.

### 2026-09-30 - Re-run on the current tip, and a MEASUREMENT PROTOCOL failure

Re-ran the 82-file cohort on the port-branch tip to get valid pass-2 numbers after the
`FrozenModelScorer` race fix. Build `Osprey v26.1.1.273 (ed25627d81)`, 628/628 tests
(including the new `SubsetPipelineTest` suite). Worktree `pwiz-net10b`, snapshot
`_bin\26.1.1.273-net10tip-ed25627d81`.
Run dir: `...runs\seaad-82files-libdecoy-r1.0-protein-compactnet10tip-par4`.

#### The one solid result: the anchor is UNCHANGED

```
First-pass scoring complete: 353,085,961 precursor candidate peaks across 82 files.
```

Bit-identical to the 2026-09-25 and 2026-09-26 runs, despite #4720 (library-decoy pairing),
#4746 (decoy modifications) and #4703 (SVM C selection) all landing since. The first-pass
candidate set is stable across all eleven commits. **Contention does not affect output**,
so this result is trustworthy even though the timings below are not.

Note the log wording changed with #4718/#4721: the anchor line was
`Coelution analysis complete. N total scored entries across M files`; it is now the above,
"scored entries" is "precursor candidate peaks" throughout, and counts carry thousands
separators (`{0:N0}`). Every pre-2026-09-30 harvest grep silently matches NOTHING. A
corrected harvest script is at
`ai/.tmp/sessions/20260926-e07c35eb/harvest-tip.sh` (temporary; fold into the SEA-AD tools
if it is wanted durably).

#### WITHDRAWN: the "2.1x PerFileScoring regression" was CONTENTION, not code

`PerFileScoring:done (13198.4s)` against the 2026-09-26 par4's 6,124.6 s. I reported this
as a ~2.1x regression on the current tip, with a bisect plan. **That conclusion is not
supported and is withdrawn.**

MACS2 is a SHARED machine. `quser` shows **seven sessions, two active** (`brendanx` and
`nicksh`). During the run:

* Total system CPU measured **70-92% of 72 cores**, while **Osprey itself held only
  4.9-6.9 cores**.
* `Get-Counter '\Process(*)\% Processor Time'` showed **`diann.exe` ~4.5 cores** and
  **`python.exe` ~3.0 cores** that are not mine - `Win32_Process.GetOwner` returns BLANK
  for them, which is what "owned by another user" looks like from an unprivileged query.
* Load is bursty: 70-92% one minute, 14-34% the next.

**How I got it wrong, so it is not repeated**: I measured CPU with
`Get-Process | ... $_.CPU`, which returns null for other users' processes. My filter
skipped them silently, so "Osprey has 16.5 of 72 cores" read as "Osprey is
under-parallelised" when the truth was "Osprey is being starved by someone else's job".
A single-process view cannot distinguish those. Brendan prompted the check.

#### MANDATORY protocol for any future timing measurement on MACS2

Before trusting ANY wall-clock number from this machine:

1. `quser` - who else is logged on.
2. `(Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 2 -MaxSamples 5)` -
   total load, sampled repeatedly because other users' work is bursty.
3. `Get-Counter '\Process(*)\% Processor Time'` - per-process cores INCLUDING other users.
   **Do not use `Get-Process | $_.CPU` for this** - it silently omits other users.
4. Record the measured system load alongside the stage times, so a later reader can tell a
   clean measurement from a contended one.

A stage time taken while another user's DIA-NN is running is not comparable to one taken on
an idle box, and nothing in the run log records the difference.

#### What is still open

* Whether there IS any real throughput regression on the tip is now **unknown**. It must be
  re-measured on a quiet box. The 4-file harness at
  `ai/.tmp/sessions/20260926-e07c35eb/bisect-scoring.ps1` reproduces a PerFileScoring
  number in ~15 min and is the cheap way to check, but only when the machine is quiet.
* The cross-arm determinism check of the race fix (par3 vs par4 producing identical
  per-file output) was never run. `-NumFiles 8` on both arms is the cheap substitute, and
  it is NOT sensitive to contention because it compares outputs, not times.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260930_osprey_perf_night.md` before starting work. It leads with the
shared-machine contention trap that invalidated tonight's timings.
