# Running the protein-best / SEA-AD tests on another machine

Companion to TODO-20261030_osprey_scoring_library.md (written 2026-11-08 on MACS2). For a session on an i9 (or any
second machine) picking up the `--protein-best` branch and the per-file scoring performance work.

## Code

- pwiz branch `Skyline/work/20261108_osprey_protein_best` (pushed, no PR yet), on top of #4950
  (`Skyline/work/20261028_osprey_diann_fdr_gap`, c0c2bcd43c). Tip 1cbe1463bd.
- Build: `pwsh -File ./ai/scripts/Osprey/Build-Osprey.ps1 -SourceRoot <checkout>` (Release, net10.0). Gate:
  `-Configuration Debug -RunTests -RunInspection` (683/683, 0 inspection at the tip).
- Copy the Release output folder to a snapshot dir and run from there (MACS2 used `_bin\n1108-pbfix`), so a rebuild
  cannot change a run in flight. The version string must be clean (built after the commit).

## Data

- **mzML** (82 SEA-AD Astral files) and their `.spectra.bin`: see `ai/scripts/Osprey/SEA-AD/README.md` (lab share
  `\\gs-ddn2\maccoss-vol1\...\SEA-AD\Astral-DIA\mzml`, or re-convert the .raw from Panorama). Copy to a local SSD.
- **Library**: download the r=1.0 entrapment drop `target+decoy+entrapment-20260817` (README, "Entrapment
  libraries", Panorama), then derive the size-weighted split; only the pairing manifest and `assign.tsv` change, the
  12.4 GB TSV is hard-linked:

```
python ai/scripts/Osprey/Library/Build-ProteinShuffledEntrapment.py --library-dir <...>\target+decoy+entrapment-20260817 `
    --out-dir <...>\target+decoy+entrapment-20260817-split-sized --in-targets 0.5 --size-weighted
```

  Verified on MACS2: both files byte-identical to the library every run below used. The split is 1:1 entrapment to
  targets (r = 1.0), half on target proteins, half on their own: 6.18M precursors per file with decoys, about 1.7x
  the work of a 10% + 10% split.

## The experiment settings every SEA-AD arm used

Environment (cleared and set per arm; `Run-SeaAd.ps1` strips some levers, so set these inside the arm loop):

```
OSPREY_XIC_FRAGMENTS=12  OSPREY_LOESS_BANDWIDTH=0.10  OSPREY_MIN_RT_TOLERANCE=1.0  OSPREY_TC_HALF_WINDOW=0.40
OSPREY_CORR_FRAGMENT_TOLERANCE=7  OSPREY_REF_XIC=corr  OSPREY_LOCAL_RT_TOLERANCE=15
OSPREY_FDR_SEED=1  OSPREY_FEATURE_MASK=none  OSPREY_RECON_REFIT=off
GBDT: OSPREY_FDR_MODEL=gbdt OSPREY_GBT_OOF=1      SVM: OSPREY_FDR_MODEL=svm
```

`--protein-best` is on by default; `Run-SeaAd.ps1 -ProteinBest off` turns it off (empty passes nothing, for older
builds). With it off and GBDT, the MACS2 "off" arms also set `OSPREY_GBT_PREFILTER_SIZE=200000` (two-round, no column).

## Reproduction check (do this first)

Osprey is bit-identical across machines and thread counts, so the matched 3-file arms must reproduce MACS2's
FDRBench byte for byte:

```
pwsh -File ai/scripts/Osprey/SEA-AD/Run-SeaAd.ps1 -DecoyMode libdecoy -Ratio 1.0 -Threads <n> -NumFiles 3 `
    -IncludePattern 'A01_005|A06_010|A10_014' -Pass2Mode transfer -FdrBenchPass both -Tag pb-gbdt `
    -DataDir <mzml> -LibraryDir <split-sized> -RunsRoot <runs> -Exe <snapshot>\Osprey.exe
```

Later arms on the same files: add `-LinkFrom <first run dir>` (hard links; scoring is skipped as "outputs valid").
Read them with:

```
python ai/scripts/Osprey/SEA-AD/tools/split_calibration.py --lib-dir <split-sized> --osprey <run dir> ...
```

Expected (precursors at reported q 1% with true on-target FDP, and found at true FDP 1%):

| arm | q 1% kept (FDP) | at FDP 1% |
|---|---|---|
| GBDT, protein-best on, pass 2 | 73,978 (0.91%) | 74,643 |
| GBDT, protein-best off, pass 2 | 66,937 (0.63%) | 69,837 |
| SVM, protein-best on, pass 2 | 64,415 (0.85%) | 65,722 |
| DIA-NN 2.7.0 NN (same peptides, its own split draw) | 75,125 (0.59%) | 78,668 |
| DIA-NN --no-nn | 56,662 (0.42%) | 62,472 |

DIA-NN rows need its own library and assignment (`--diann <report.parquet> --diann-assign <A2-sized.assign.tsv>
--diann-n-target 1129657`); a Carafe TSV that still holds Osprey's decoys is searched by DIA-NN as targets.

## Performance: where to start

- One file, `--task PerFileScoring`, A10_014, 72 threads, nothing else on the machine: 456 s total; coelution
  scoring 316 s (4.40M candidates, 13,945 cand/s), library load 53 s, parquet write 57 s, RT calibration 28 s.
  Per-window 30 / 113 / 226 s (min / median / max; slowest m/z 437.9, 48,339 candidates) over 167 windows.
- The window loop (`ScoringPipeline.cs` ~277) is one `Parallel.For` over windows, nothing parallel inside a window,
  so a file cannot finish faster than its largest window, and threads idle in the tail. Spectra stream per window
  (`StreamingWindowSpectraProvider`), so memory is about `--threads` windows' spectra.
- MACS2 runs used no parallel files (`parallelfiles=0`). Do not use parallel files yet: narrow the per-file cost first.
- Profile: `ai/scripts/Osprey/Profile-Osprey.ps1 -OspreyArgs <args> -ScopeToMainSearch -Exe <snapshot exe> -TopN 60
  -OutputPath <x>.dtp` (sampling; the build carries JetBrains.Profiler.Api). On MACS2 the dotTrace CLI global tool is
  2026.2.1 but the installed Reporter.exe is 2022.1, which cannot read the snapshot ("Reporter.exe did not generate
  report"); use a Reporter from the same version (NuGet `JetBrains.dotTrace.CommandLineTools.windows-x64`) or open
  the .dtp in a current dotTrace GUI. MACS2's snapshot: `D:\Users\brendanx\test\osprey-runs\sea-ad\runs-timing\
  profile-full.dtp` (+ .0000-.0003), A10_014, full settings, 64 threads.
- Single-setting ablations not yet measured (each drops one switch from the set above, same file and task): XIC 12
  -> 6, no CORR_FRAGMENT_TOLERANCE, no REF_XIC, no LOCAL_RT_TOLERANCE, all off, and the 26.1.1.301 build, which
  separates code growth from settings growth.

## Still to run (good use of a second machine)

- Regression at the tip for StellarLibDecoy and Astral (`pwiz_tools/Osprey/regression-parallel.ps1 -Dataset
  StellarLibDecoy,Astral`); Stellar and StellarGenDecoyEntrap passed on MACS2.
- The 82-file arms on links to a scored baseline (`-Task FirstPassFDR -LinkFrom <82-file run>` for first-pass
  variants, ~30 min each; full pass-2 arms ~4-6 h): GBDT protein-best + transfer, transfer only, SVM on/off. The
  MACS2 82-file baseline (GBDT, protein-best off, protein-compact) reads q 1% -> FDP 1.29% in pass 2.
- DIA-NN 82 files on the same split peptides (MACS2 timed DIA-NN only on the unsplit library: 5.9 min/file).

## BRENDANX-UW8 results (2026-11-08, i9-14900K, 32 threads, 128 GB, machine otherwise idle)

Worktree `C:\proj\pwiz-pb` at 1cbe1463bd; snapshot `D:\test\osprey-runs\_bin\uw8-pb-1cbe1463bd`; runs under
`D:\test\osprey-runs\sea-ad\runs-uw8`; scripts in `ai/.tmp/sessions/20261108-uw8perf` (`ablate.ps1`, `compare_scores.py`).

- **Reproduction: exact.** GBDT, protein-best on, transfer pass 2, 3 files: pass 2 73,978 at q 1% (FDP 0.91%), 74,643
  at FDP 1% - MACS2's numbers. 25.5 min wall at 32 threads.
- **Single-setting ablations** (A10_014, `--task PerFileScoring`, 32 threads; coelution / task wall): full 182.8 / 257.1 s;
  XIC 6 121.4 / 194.7; no CORR_FRAGMENT_TOLERANCE 120.9 / 194.3; no REF_XIC 180.4 / 250.9; no LOCAL_RT_TOLERANCE
  175.7 / 246.1; all four off 77.5 / 152.1. XIC 12 and the 7 ppm correlation re-extraction each cost ~61 s; REF_XIC and
  LOCAL_RT are near free. (Faster per file than MACS2: 24k cand/s here vs 13.9k there.)
- **Code changes in hand, NOT committed (UW8 owns these; do not duplicate):**
  1. Largest-window-first scheduling in `ScoringPipeline.RunCoelutionScoring` (exact candidate count, `NoBuffering`
     partitioner) plus a "Window threads busy" log line: coelution 182.8 -> 169.7 s, busy 94%.
  2. The OSPREY_CORR_FRAGMENT_TOLERANCE XICs extracted in the same scan-major pass as the search XICs
     (`ExtractXicsScanMajor` gains a corr config, `TryExtract` takes them precomputed). The candidate-major re-extraction
     was 1,123 core-s of `MzBucketIndex.LowerBound` against 414 for the same lookups scan-major. Coelution
     169.7 -> 134.5 s (-26% cumulative), CPU 5,104 -> 3,995 core-s.
  Both: `.scores.parquet` identical to the baseline (4,356,316 rows x 128 columns); Debug gate 683/683, 0 inspection;
  `ScoringTest` scan-major test now also checks the corr XICs bitwise.
  3. Shared lower bound for the two windows in the scan-major pass (`TopFragmentExtractor.FindClosestPeakInWindows`:
     the wide window's bucket lookup seeds the narrow one): 134.5 -> 131.4 s, CPU 3,906.
  4. Median polish of every pick candidate (`CandidateLibCosine`) in reused per-thread buffers
     (`TukeyMedianPolish.TryLibCosineOverScans`; `Compute` now runs the same `Fit` and copies out): 131.4 -> 124.1 s,
     CPU 3,691. New `MedianPolishMetricsTest.TestLibCosineOverScansMatchesCompute` (bitwise, 2,000 random fits).
  Tried and dropped: insertion-sort medians for short rows (134.5 s, inside the ~3 s run-to-run noise).
  Cumulative: coelution 182.8 -> 124.1 s (-32%), task wall 257.1 -> 196.9 s; parquet identical at every step; gate
  684/684, 0 inspection. Per file now: library load 33 s (once per process), RT calibration 12 s, coelution 124 s,
  window dedup ~9 s, parquet write 17 s.
- **Possible work conflict (2026-11-09 00:00).** The main TODO (63152c70, MACS2, 23:17) describes a sub-agent on local
  `Skyline/work/20261108_osprey_scoring_share` doing largest-window-first scheduling, sharing the second extraction's
  m/z lookups and reusing the median-polish fit from the pick - items 1-4 above overlap it. Brendan is checking with
  the MACS2 agent; UW8 makes no further coelution code changes until he decides who keeps what. UW8's changes are
  uncommitted in `C:\proj\pwiz-pb` (snapshot of the latest: `_bin\uw8-polish`).
- Latest profile (`runs-uw8\profile-full-polish.dtp`, report `ai/.tmp/sessions/20261108-uw8perf/profile-full-polish-report.xml`):
  ScoreWindow 3,630 core-s (from 5,007). Largest left, core-s: scan-major extraction 746 (LowerBound 459 of it),
  median-polish Fit 503 (all callers), PeakDominance 269, SgWeightedSweep 241, PearsonCorrelationInRange 211, CWT
  Convolve 206, ReextractedCorrelations 207, SpectrumMatchScores 192.
- dotTrace CLI here was 2025.3.2 and hit a CLR assert (`TS_Hijacked`) under .NET 10 with no snapshot; updated to
  2026.2.4.1, which works with the installed 2026.2 Reporter. Snapshots: `runs-uw8\profile-full-lpt.dtp`,
  `profile-full-corrsm.dtp`.
- Next candidates from the profile: median polish per CWT candidate in `CandidateLibCosine` (~365 core-s) and the
  chosen peak's polish recomputed in `ScoreCandidate` (~73 core-s, same XICs and bounds as the pick).
- DIA-NN is not installed on UW8, so there is no same-machine DIA-NN timing yet.

## Division of work between UW8 and MACS2 (proposed by MACS2 2026-11-09, for Brendan to confirm)

- **UW8 keeps its four coelution changes** (largest-window-first, corr XICs in the scan-major pass, shared lower
  bound, median polish in reused buffers). MACS2 has dropped its overlapping steps: the pipeline agent's
  largest-first and the share agent's second-extraction lookup reuse. UW8: commit them on a branch from 1cbe1463bd
  (e.g. `Skyline/work/20261109_osprey_scoring_uw8`) and push it when Brendan says, so MACS2 can merge.
- **MACS2 keeps the non-overlapping code items**, each byte-identical with gate + Stellar regression, on local
  branches until pushed:
  - share (`pwiz-nightbase`, `Skyline/work/20261108_osprey_scoring_share`): the pick's fit + crop reused for the
    chosen peak (81541d6ffe; UW8 lists it as not done), a shared chosen-peak correlation matrix;
  - pipeline (`pwiz-perfbase`, `Skyline/work/20261108_osprey_scoring_pipeline`): CWT `Convolve` without the per-term
    bounds test, dedup inside each window's task, an ordered streaming parquet writer (CommonUtil `QueueWorker` +
    reorder buffer).
  - MACS2 also keeps the work only it can do: DIA-NN runs (not installed on UW8) and the 82-file runs.
- **UW8 becomes the clean-timing machine.** It is idle and its noise is ~3 s; MACS2 shares cores with another
  user's jobs and its own agents. Each MACS2 branch, once pushed and merged with UW8's, is timed and profiled on UW8
  (A10_014, `--task PerFileScoring`, full settings, 32 threads) against `uw8-pb-1cbe1463bd`. UW8 makes no further
  changes inside the coelution code without posting here first.
- **Merge order:** UW8 branch pushed -> MACS2 merges it into share and pipeline (both should merge cleanly: the
  overlap was dropped) -> pushed -> UW8 times each and the combination.

## Machine-sharing check

Before timing anything: `quser` and `tasklist /v /fi "imagename eq Osprey.exe"` (the session column names the
owner; another user's processes cannot be stopped). On MACS2 the night of 2026-11-08 another user's two Osprey jobs
used ~26 cores from 19:42, so that night's wall times are inflated.
