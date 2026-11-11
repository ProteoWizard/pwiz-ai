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
- **UW8 reply (2026-11-09 00:30): agreed.** Branch `Skyline/work/20261109_osprey_scoring_uw8` created from 1cbe1463bd
  in `C:\proj\pwiz-pb` with the four changes (7 files, CRLF clean, gate 684/684, 0 inspection); Stellar regression
  running; commit and push wait on Brendan. One correction: **DIA-NN is now installed on UW8** (2.7.0 and 2.6.1 in
  `C:\DIA-NN\<version>`, Brendan's go-ahead), so the same-machine Osprey vs DIA-NN wall-time comparison is UW8's
  too. DIA-NN 2.7.0 library predicted from the split's own peptides (targets + entrapment, no decoys, each under the
  protein Osprey files it under, entrapment via `assign.tsv`, so `split_calibration.py` reads both tools on one split):
  `D:\test\osprey-runs\sea-ad\lib\diann-split-sized` (builder `ai/.tmp/sessions/20261108-uw8perf/diann_split_fasta.py`,
  `diann-predict.ps1`, `diann-search.ps1`). MACS2 keeps the 82-file runs.
- **UW8 branch pushed (2026-11-09 01:00): `Skyline/work/20261109_osprey_scoring_uw8` at 4ecdc54fee** (one commit on
  1cbe1463bd). Stellar regression PASS (golden, 1c, 4, 6); gate 684/684, 0 inspection. MACS2: ready to merge into
  share and pipeline. DIA-NN 2.7.0 library: 3,081,739 precursors, 40,892 proteins, predicted in 6.6 min at 32 threads.
- **Same-machine Osprey vs DIA-NN, 3 files (A01_005, A06_010, A10_014), 32 threads, UW8 idle (2026-11-09 01:30).**

  | run | wall | q 1% kept (FDP) | at FDP 1% |
  |---|---|---|---|
  | DIA-NN 2.7.0, NN, MBR (`runs-uw8\diann270-3files`) | 20.15 min | 75,028 (0.59%) | 78,667 |
  | Osprey tip 1cbe1463bd (`...pb-gbdt-tip-warm`) | 18.6 min (1,116.9 s) | 73,978 (0.91%) | 74,643 |
  | Osprey 4ecdc54fee (`...pb-gbdt-4ecdc54fee`) | 15.2 min (910.3 s) | 73,978 (0.91%) | 74,643 |

  Osprey stages tip -> 4ecdc54fee: PerFileScoring 709.2 -> 508.9 s (coelution ~176 -> ~122 s/file), FirstPassFDR
  249.8 -> 247.7, PerFileRescoring 137.4 -> 132.2, SecondPassFDR 18.8 -> 20.3. All three `.scores.parquet` identical,
  both passes' split numbers identical. Both Osprey arms pinned `OSPREY_VERSION_OVERRIDE=26.1.1.312` so they read
  the same warm `.blib` (the derived library is stamped with the daily version; a .313 build would rebuild it,
  ~250 s). DIA-NN reproduces MACS2's row (75,125 / 0.59% / 78,668) on its own rebuild of the library. Osprey is
  1.25x faster than DIA-NN end to end (was 1.08x) at 5.1% fewer IDs at FDP 1%. Script `arm3.ps1` in the session folder.
  Not yet compared: DIA-NN with the Osprey library's own spectra, and 82-file walls (DIA-NN per-file cost scales
  linearly; Osprey's FirstPassFDR does not).
- **16 files (SEA-AD samples 0001-0016, `arm3.ps1 -NumFiles 16 -IncludePattern ''`), UW8, 32 threads (2026-11-09).**

  | run | PerFileScoring | FirstPassFDR | Rescoring | SecondPass | total | q 1% kept (FDP) | at FDP 1% |
  |---|---|---|---|---|---|---|---|
  | Osprey 1cbe1463bd | 3,838 s | 822 | 1,313 | 82 | 100.9 min | 89,453 (1.04%) | 89,244 |
  | Osprey 4ecdc54fee | 2,895 s | 817 | 1,290 | 85 | 84.8 min | 89,453 (1.04%) | 89,244 |
  | DIA-NN 2.7.0 (82.5 min pass 1, 19 min MBR) | | | | | 104.9 min | 92,794 (0.75%) | 95,115 |

  UW8 speedups: -16% end to end (59 s/file, all in PerFileScoring), 16 `.scores.parquet` identical. Osprey vs DIA-NN:
  1.04x faster before, 1.24x after (1.33x at 3 files). Gap at FDP 1% 6.2% (5.1% at 3 files); reported q 1% reads
  1.04% FDP (0.91% at 3). Per-file cost 3 -> 16 files: scoring 170 -> 181 s, Rescoring 44 -> 81 s (super-linear;
  the largest stage after scoring and untouched by any branch so far), FirstPassFDR 248 -> 817 s total.
- **MACS2 branches timed on UW8 (2026-11-09 06:40-06:55; A10_014, `--task PerFileScoring`, full settings, 32
  threads, warm cache, `OSPREY_VERSION_OVERRIDE=26.1.1.312`):**

  | build | coelution | dedup after coelution | PerFileScoring wall |
  |---|---|---|---|
  | UW8 4ecdc54fee (`t2-uw8`) | 124.0 s | 8 s | 193.3 s |
  | share fb73f1ba11 (`t-share`) | 124.6 s | 7 s | 198.7 s |
  | pipeline c70b7af35e (`t-pipeline`) | 125.8 s | 0 s | 192.4 s |
  | share + pipeline, local merge 89557f2093 (`t-combo`) | 126.9 s | 0 s | 192.8 s |

  All `.scores.parquet` identical to UW8's. share: no measurable gain on UW8 (its chosen-peak correlation sharing
  does not move coelution). pipeline: the per-window dedup removes ~8 s of serial work per file for ~2 s more
  coelution, ~6 s/file net (~3%); the CWT `Convolve` hoist is not visible. The first `t-uw8` run (277.7 s) had a
  cold OS cache after the 16-file runs (library load 97 s vs 33 s) and is not comparable. The remaining wall at 16
  files is Rescoring (~1,300 s, super-linear) and FirstPassFDR (~820 s), which no branch touches yet.
- **Why PerFileRescoring scales super-linearly (UW8, 2026-11-09 07:30; `recon_counts.py` in the session folder).**
  A01_005 per file, 3 -> 16 files: re-scored 62,542 -> 113,073 peaks, of which paired DECOYS 44,087 (70%) ->
  80,364 (71%) (forced integration 34,232 / 62,454 decoy; CWT re-pick 9,855 / 17,910 decoy; gap fill targets only).
  The planner admits a (base id, charge) when any of run/experiment x precursor/peptide q passes 1% in ANY run,
  and pairs its decoy by base id; a decoy's apex is almost never at the consensus RT, so nearly every decoy is
  moved. The union of run-level passers grows with run count (reconciled targets per file 101k -> 138k vs 74k ->
  89k experiment q 1%), and per-peak rescore cost rose 0.10 -> 0.18 ms. Stage 6 per file at 16 files: rescore +
  gap fill ~25 s, planning ~11 s, reconciled-parquet write ~24 s (248k rows; reads the 3.9 GB first-pass parquet),
  model-diagnostics mass-error pass ~11 s.
- **Brendan (2026-11-09): carrying decoys into PerFileRescoring is a protein-compact artifact; under transfer there
  is no re-competition and decoys need not change past the first pass.** UW8 is implementing: `FilePlanner` takes
  whether to reconcile decoys, and `RunReconciliationPlanner` passes false under transfer (protein-compact
  unchanged). Stage 6 planner only - not the coelution code, not on either MACS2 branch. Verify: 3-file arm, target
  pass-2 q and FDRBench pass 2 unchanged, then time 16 files.
- **The transfer reconciliation set is the blib set (Brendan, 2026-11-09).** The planner and gap fill admitted any
  precursor passing at any of run/experiment x precursor/peptide in any run - run-level q inflates with run count,
  protein-compact's need. Measured: 101,394 reconciled target precursors vs 74,210 in the blib at 3 files (1.37x),
  139,039 vs 89,771 at 16 (1.55x) (`recon_set_size.py`). Brendan: under transfer keep every experiment-wide value from
  pass 1 and let reconciliation improve only per-run peak picking (as Skyline does); mean-best-N has shown little
  value after protein-best and climbers are unlikely. Code: new `ExperimentOutputSet` (Osprey.FDR.Reconciliation)
  applies the blib writer's two experiment-level gates (peptide at FdrLevel, then charge states, best-charge
  fallback) to first-pass q in `Stage6Planner.ScanFiles` under transfer; validity token `;reconset=output;
  recondecoys=0` on FirstPassFDR (writes the Stage 6 consensus), PerFileRescoring and SecondPassFDR under transfer.
  The transfer fold already carries pass-1 experiment q unchanged (`CarryPass1Experiment`), so blib membership
  cannot change; only per-run peaks and run q do.
- **Committed f90d19aaa6 on `Skyline/work/20261109_osprey_scoring_uw8` (2026-11-09, pushed):** under transfer, (1) paired
  decoys keep first-pass peaks, (2) reconciliation + gap fill take the blib set (`ExperimentOutputSet`), (3)
  multi-charge consensus re-scores only reported charge states (`MultiChargeConsensus.ReportedOnly`; leader still by
  run FDR), (4) the pass-2 peptide q floor derives from reported charge states only
  (`ExperimentQFloors.DerivePeptideFloors(reportedTarget)`). Gate 688/688, 0 inspection. 3 files: re-scored peaks
  203,856 -> 18,482, multi-charge targets 32,084 -> 1,013.
  - **Floor bug found on the way:** the best-of-runs peptide floor read every charge state, so an unreported charge
    state re-scored in pass 2 at a sibling's or consensus boundaries could lower OR raise a reported peptide's q. 3 of
    74,210 at 3 files (GVDAQGTLSKIFK, SFLPSYDAVAASQGAVK, SKFADLSEAANR); in pass 1 the unreported states never passed
    run FDR in any run (`peptide_runq.py`). The floor's invariant is "reported => a run has an ID line"; only reported
    precursors have ID lines.
  - **Verification:** with the floor fix, the old any-level rule (decoys and every charge reconciled; temporary
    build via `old_rule_variant.py`) and the new rule give IDENTICAL blibs (74,210 RefSpectra, 222,532 RetentionTimes,
    every column; `compare_blib.py`). vs the pre-fix baseline only those 3 PeptideQValue rows differ. Pass 2 at q 1%
    unchanged (73,978, 0.91%); FDRBench beyond 1% moves slightly (unreported precursors keep first-pass peaks).
  - Stage 6 per file at 3 files is now mostly fixed cost: reconciled-parquet write ~20 s (decodes all 4.4M
    first-pass rows, every column, to keep ~180k Stage 5 survivors) and the model-diagnostics mass-error pass ~10 s.
- **16 files on UW8, f90d19aaa6 vs master 813bf69cee vs DIA-NN (2026-11-09; night log
  `ai/.tmp/night-session-budget-20261109.md`).** f90d19aaa6 (PerFileScoring linked from 4ecdc54fee, same code):
  FirstPassFDR 817-889 s, PerFileRescoring 1,250 s (re-scored 2,004,773 -> 220,309), SecondPassFDR 85 s, ~84 min;
  blib = 4ecdc54fee's except 1 PeptideQValue row (the floor fix); Stellar regression PASS. Stage 6 barely moved because
  it is I/O-bound on UW8's SATA HDD (D:): re-scoring 8k peaks took 21 s like 113k did, the per-window cost being the
  cold read of the 4.1 GB `.spectra.bin` (profile `runs-uw8\profile-stage6-16f.dtp`: GetCalibratedWindow 11,412 s
  total vs ScoreWindow 709 s). The earlier "super-linear" Stage 6 was the OS cache (warm at 3 files, cold at 16), not
  workload - the decoys and run-level-only precursors were real but small CPU.
  Master at its defaults (protein-compact, none of the SEA-AD settings), same 16 files: 55.5 min (~50 warm; 369 s
  one-time blib build); PerFileScoring 1,799 s (coelution 38.8 s/file vs ~122 branch), FirstPassFDR 303 s,
  PerFileRescoring 976 s (905,753 re-scored), SecondPassFDR 253 s; 54,504 found at FDP 1% (branch 89,244, +64%;
  DIA-NN 95,115); reported q 1% reads 1.17% FDP (branch 1.04%, DIA-NN 0.75%). Branch Stage 7 is 3x faster (no
  re-competition); branch Stage 6 is slower (78 vs 61 s/file) because its first-pass `.scores.parquet` is 3.62 GB vs
  1.75 GB per run (12 fragments, more features) and Stage 6 reads it twice (planning, writer). Writer (sub-agent,
  read-only): survivors are 11-column stubs, so writing from memory changes bytes; key-first decode saves CPU not disk;
  the HDD wins are write-behind overlap or reading fewer columns.
- **82 files on UW8, f90d19aaa6, full pipeline, `--model-diagnostics` off (2026-11-09 13:52-21:20;
  `runs-uw8\seaad-82files-libdecoy-r1.0-transferpb-gbdt-f90d19aaa6-nodiag`):** 7 h 27 min (26,835 s, 5.45 min/file).
  PerFileScoring 15,092 s (184 s/file), FirstPassFDR 4,442 s (54 s/file), PerFileRescoring 6,953 s (85 s/file; re-scored
  1,996,700 = 24.4k/file vs 13.8k at 16), SecondPassFDR 348 s; blib 96,973 precursors. Per-file costs ~linear from 16
  to 82 files.
- **82 files: Osprey vs DIA-NN 2.7.0 on UW8 (same files, split-sized library, 32 threads, SATA HDD; split audit
  `ai/.tmp/sessions/20261108-uw8perf/split-82files.txt`):**

  | run | wall | per file | q 1% kept (FDP) | at FDP 1% |
  |---|---|---|---|---|
  | Osprey f90d19aaa6, pass 2, diagnostics off | 7 h 27 min | 5.45 min | 96,641 (0.99%) | 96,654 |
  | DIA-NN 2.7.0 NN + MBR (`runs-uw8\diann270-82files`) | 9 h 49 min | 7.18 min | 99,575 (0.78%) | 101,269 |

  Osprey 1.32x faster, 4.6% behind at FDP 1% (5.1% at 3 files, 6.2% at 16), reported q 1% honest (0.99%) where DIA-NN
  is conservative (0.78%). DIA-NN: first pass 425 min, MBR ~146 min.
- **Decision (Brendan, 2026-11-09): the MACS2 share and pipeline branches are not merged.** On UW8 share gave no
  measurable gain and pipeline ~6 s/file (~3%, the per-window dedup); not worth the added complexity. The UW8 branch
  (f90d19aaa6) carries neither. Keep for the follow-up issue only: the whole-file dedup shares `removed[]` across
  windows, so an entry in two windows can make output timing-dependent (no such entries in SEA-AD or Stellar).
- **Idea for later (Brendan, 2026-11-09): shared peak boundaries for all charge states of a peptide in PASS 1**, as
  Skyline enforces (the molecule's elution sets the time; charge comes after). Pass 1 today picks each charge state
  independently (32,084 survivor charge states across 3 files sit outside half the leader's width), e.g. GVDAQGTLSKIFK
  z2 picked 12.58 min (score -11.7) but scores +9.2 at z3's 13.95 min. Doing it in pass 1 for targets and decoys
  alike keeps the null honest (no post-FDR second chance) and makes Stage 6 multi-charge consensus a no-op. Changes
  the first pass: measure on the split audit like protein-best. After the Stage 6 efficiency work.

- **MACS2 merging (2026-11-09):** both MACS2 sub-agents told to `git merge origin/Skyline/work/20261109_osprey_scoring_uw8`
  at their next clean point. share has 81541d6ffe (pick fit reused for the chosen peak) and 6c92959bd5 (shared chosen-peak
  pairwise correlations); its step 1 must be reconciled with UW8's buffered CandidateLibCosine. Merged tips are
  verified byte-identical vs `n1108-pbfix`, gated, then pushed for UW8 to time. Same-machine DIA-NN timing is UW8's.

- **MACS2 branches ready (2026-11-09 ~03:00, local, not pushed; both include the UW8 merge, byte-identical vs
  `n1108-pbfix` with full and default settings at 64 and 8 threads, gate 684/684, Stellar regression PASS):**
  - `Skyline/work/20261108_osprey_scoring_share` (pwiz-nightbase) fb73f1ba11: shared chosen-peak pairwise
    correlations (`PeakPairCorrelations`) read by the reference choice, CoelutionStats, ReferenceCorrelations and
    top-3 features; one shared peak crop (`PeakPolishFit`). The pick-to-scoring fit hand-off was dropped at the
    merge (UW8's per-thread buffers are reused by the next candidate).
  - `Skyline/work/20261108_osprey_scoring_pipeline` (pwiz-perfbase) c70b7af35e: CWT `Convolve` bounds hoist
    (29c8a80b7a) and the double-counting dedup run inside each window task when library ids are unique and no
    library entry falls in two windows (SEA-AD and Stellar both take it; whole-file pass otherwise). Indicative
    MACS2 times only (shared machine): dedup ~30 s -> 0 s; coelution 307-323 s -> 257 s at 64 threads.
  - Ordered streaming parquet writer not done: rows are sorted by entry_id over the whole file after the
    cross-window pair dedup, so window-order streaming would change the bytes.
  - Existing race confirmed by reading the code: the whole-file dedup shares `removed[]` across windows, so an entry
    in two windows can make output timing-dependent. Neither SEA-AD nor Stellar has such entries (both now take the
    per-window path); data with overlapping windows still runs the old pass. For the follow-up issue.

- **MACS2 parallel-files re-test (2026-11-09 03:23-03:51; chrhsu's one bursty Osprey still running, total CPU ~12%):**
  4 files (A01_005, A02_006, A06_010, A10_014), `--task PerFileScoring`, full settings, 72 threads, `n1108-pbfix`
  (before the UW8/share/pipeline changes): sequential 933 s vs `--parallel-files-scoring 4` 707 s = **1.32x** (was
  ~2.2x before this work), peak memory 38.7 GB -> 83.4 GB. Sequential coelution 148-167 s/file (26.6-29.6k cand/s),
  so the evening's 13.9k cand/s single-file numbers were inflated by the other user's jobs. Lanes now buy only the
  per-window tail and the serial calibration/dedup/write; the pushed branches attack the same tail. Logs
  `D:\Users\brendanx\test\osprey-runs\sea-ad\runs-pfidle\{seq4,pfs4}\run.log`.

## BRENDANX-UW25 memory scaling (2026-11-09, i9-14900 65 W, 32 threads, 64 GB)

Question: does the #4950 tip (GBDT + OOF, protein-best, transfer pass 2) stay bounded in memory, and will
500-1000 runs (CHS 446) fit in 64 GB? Local branch `Skyline/work/20261109_osprey_uw25_memscale` in
`C:\proj\pwiz-uw25` = pipeline c70b7af35e + share fb73f1ba11 merged cleanly (da4eff9f63), snapshot
`_bin\uw25-da4eff9f63`. Runs `D:\test\osprey-runs\sea-ad\runs-uw25`; ladder script + logs + perfviz PNGs in
`ai/.tmp/sessions/20261109-uw25mem`. Full settings above, `-LogMemory` (post-GC [MEM] probes), no mdiag.

- **Reproduction exact** on the merge: pass 2 73,978 at q 1% (FDP 0.91%), 74,643 at FDP 1%. Coelution ~185 s/file
  here (65 W part) vs ~122 s on UW8; scoring ~3.9 min/file.
- `-LinkFrom` refuses a source missing any declared file, so the ladder scores in legs (`-Task PerFileScoring
  -SkipFirstFiles`) and each FDR rung links all legs: score 1-20, FDR 10, FDR 20, score 21-41, FDR 41, score 42-82,
  FDR 82.
- **Live sets flat in file count** (post-GC): entering FirstPassFDR 5.21 / 4.23 / 4.23 GB at 3 / 10 / 20 files;
  after first-pass FDR 5.89 / 4.91 / 4.91 (13.0M / 42.7M / 86.5M rows streamed); rescoring ~3.65 GB per run;
  Stage 7 < 3 GB. Private peaks 31-38 GB are Server-GC headroom (managed peak ~2x live). FirstPassFDR wall linear,
  ~63 s/file (326 / 745 / 1,374 s). Only growth seen: the best-per-precursor training-feature load (5.8M x 109 at
  20 files), O(library) - plateau 12.3 -> 16.5 GB managed from 10 to 20 files, should saturate near 6.18M.
- Detections (on-target half): 10 files p2 85,389 at q 1% (FDP 1.01%); 20 files p2 90,189 (0.93%), 90,617 at FDP 1%.
- **Silent gap found and fixed:** `AppendProteinBestToRows` (round-2 protein-best column, scores every row of every
  file with the round-1 models) logged nothing for 34 / 143 / 311 s at 3 / 10 / 20 files (~20 min at 82, ~2 h at
  446). Wrapped in `ProgressReporter.Run` - 7a615c6082 on the local branch (gate 684/684, 0 inspection; not pushed).
  Belongs on the protein-best branch; Brendan to place. Run-verified in the 82-file rung (snapshot
  `_bin\uw25-7a615c6082`): the step now reports percent lines; only a 31 s heading-to-first-percent gap remains.
- **41 files:** live sets unchanged (4.23 / 4.92 / 2.91 GB); private peak 41.2 GB at the score-pass start with 3 FDR
  file lanes (2 at 10, 20 and 82; lanes come from free memory at ~7 GB each). p2 96,801 at q 1% (FDP 1.05%).
- **82 files (2026-11-09 14:53-18:12, 199 min):** entering FirstPassFDR 4.23 GB, after 4.92 GB (358.9M rows),
  reconciliation floor 2.92, rescoring 3.75 -> 4.04 GB over the first 60 runs then flat (saturating, not O(files)),
  Stage 7 3.08-3.20. Private peaks: FirstPassFDR 34.3 GB, PerFileRescoring 18.3, SecondPassFDR 11.6.
  Best-per-precursor 5,978,187 (library 6.18M). Stage walls: stage5 5,082 s (protein-best 1,349 s = 27% of it),
  stage6 6,558 s, stage7 37 s. p2 96,641 at q 1% (FDP 0.99%), 96,654 at FDP 1%.
- **Verdict:** no O(files x entries) structure on the GBDT + PB + transfer path; peak is set by FDR file lanes and
  Server-GC headroom, not cohort size. CHS 446 projected on this box: ~29 h scoring + ~7.7 h stage5 (~2 h of it
  the PB column) + ~10 h stage6 = ~47 h, within 64 GB. Remaining 30-57 s gaps are per-file-granularity reports in
  the first-pass score pass and training-feature load (heartbeat fires only on Report calls); pre-existing.
- **Protein-best cost, measured (82 files):** the training-time column step (1,349 s) writes nothing; it re-reads
  every file's features (~200 GB of parquet: block reads 4.1 -> 406.6 GB across training load + this step; the score
  pass reads 205 GB) and round-1 GBDT-scores all 359M rows to keep ~200k training values. The score pass then
  recomputes the full column (needed: the round-2 model takes it as a feature, and pass 2 reads it). All per-file
  sidecar writes in the score pass total 29.5 s, so writing is not the cost. The per-protein reduction itself is
  already cheap (best per peptide, top N+1 per protein, self excluded, memoised). Accepted as an expensive score.
- **Bug fixed, 282fe1c2e5 (local, not pushed):** protein-best grouped evidence by MODIFIED sequence, so two forms of
  one sequence counted as two peptides and a form could read its own other form (at top-1). Now keyed on the
  unmodified sequence (`ProteinBestMembership.FromLibrary`); new check in `TestProteinBestReduction`; gate 684/684,
  0 inspection; Stellar regression PASS (unchanged). SEA-AD/CHS libraries carry only fixed CAM, so unaffected.
- **Brendan's plan (2026-11-09), not yet implemented:** keep training-time compute-all-keep-training-rows; fold the
  per-run protein-best values into `.1st-pass.fdr_scores.bin` (f64 field, record 36 -> 44 B) and retire the
  separate `.1st-pass.protein_best.bin` (52.8 MB/run).
- **Note for later - shrink the FirstPassFDR -> PerFileRescoring handoff** (a scale bottleneck): readers of
  `.1st-pass.fdr_scores.bin` across tasks use only survivors (~7% of rows: the 2nd-pass file is 11.3 MB vs 158.6 MB)
  except transfer's per-run score->q tables (`Pass2FdrSidecar.TransferOneFile`) and the recompete modes. With exact
  tables written explicitly, recompete retired and the all-rows file kept only as a FirstPassFDR-private checkpoint,
  the handed-off file could be survivors-only (~71 GB -> ~5 GB at 446 runs). Also consider one file-name separator
  convention (inherited from Rust: `.1st-pass.fdr_scores.bin` vs `.scores-reconciled.parquet`).
- **PUSHED for MACS2 (2026-11-10): `Skyline/work/20261110_osprey_uw25_pb_fixes` at 1c34f9c23c**, branched from
  `Skyline/work/20261109_osprey_scoring_uw8` f90d19aaa6 (so no share/pipeline, per the decision above), carrying the
  two fixes above re-applied by cherry-pick: 49fe80fde6 (protein-best column progress, was 7a615c6082) and 1c34f9c23c
  (protein-best keyed on unmodified sequence, was 282fe1c2e5). Gate 688/688, 0 inspection; Stellar regression PASS
  (unchanged vs golden). Both touch only protein-best code (`PercolatorEngine.AppendProteinBestToRows`,
  `ProteinBestFeature`, `FirstPassFdrTask.BuildProteinBestRequest`, resources, `ProteinBestFeatureTest`).
  **MACS2: please merge it into the protein-best line.** The local memscale branch (da4eff9f63 base) is retired.
  The memory results above were measured on the share+pipeline build; those changes are inside-window coelution
  scoring only, so the scaling verdict carries over to f90d19aaa6. Next on UW25 (pending Brendan): CHS 446 on a
  snapshot of this branch.
- **PUSHED (2026-11-10): c3bdbea78d on the same branch - protein-best round 1 bounded to 10 runs.** Round 1's
  training rows come from at most `OSPREY_PROTEIN_BEST_ROUND1_RUNS` (default 10) runs drawn by the training seed, so
  its feature read is 10 files; the rest of the training-feature load is merged into the read that computes the
  protein-best column (one full read instead of two). Validity-key term `;proteinbestround1runs=10` (every
  protein-best directory re-runs FirstPassFDR). No change at or below the bound: Stellar regression PASS vs golden;
  unit test pins bound = run count identical to every run. 20 SEA-AD files (bound engaged, 10 of 20): 97.9 -> 73.9 GB
  read through training, stage 5 1,374 -> 1,282 s; pass 2 89,640 at q 1% (FDP 0.92%) and 90,376 at FDP 1%, vs
  90,189 (0.93%) / 90,617 with every run - calibration unchanged, detections -0.27% at matched FDP, seed spread not
  yet measured. Reproducible: 16 vs 32 threads gave byte-identical `.1st-pass`/`.2nd-pass` sidecars and model (61
  files). Gate 688/688, 0 inspection. Brendan: bounding is the idea to keep; 10 is not settled. 82-file effect (10 of
  82 runs) untested. **MACS2: please merge this commit too.** UW25 snapshot `_bin\uw25-c3bdbea78d`.
- **UW25 next (Brendan, 2026-11-10): the feature-set study** (`TODO-20261110_osprey_feature_set.md`), UW25 dedicated
  to it for a few days; the CHS 446 run waits.
- **MACS2 (2026-11-10): next PR into #4950 assembled on `Skyline/work/20261110_osprey_gap_pr2`** (pwiz-nightbase):
  1cbe1463bd + UW8 4ecdc54fee, f90d19aaa6 + UW25 49fe80fde6, 1c34f9c23c + 4bce784f5c. **c3bdbea78d (round-1 run
  bound) is left out** (Brendan): a review found `Round1Pool` (`PercolatorEngine.cs` ~2025) admits each dedup row by
  its own drawn run, and pass 0 draws a target and its paired decoy (and each charge) separately, so above the bound
  a pooled target keeps its decoy only ~bound/N of the time (12% at 82 runs, 2% at 446) and round 1 trains on unpaired
  competition. Brendan: an upper bound on runs is right (like the 200,000-row bound) but 10 is arbitrary; the goal
  is that the -0.27% at 20 files goes away, perhaps at 20 or 40, then re-test at 446 files (after the feature set
  shrinks). Fix to carry: a best-per-precursor map restricted to the chosen runs in pass 0, so pairs and charge
  groups are complete within them. 4bce784f5c (review finding 2, from f90d19aaa6): the transfer `reconset` token now
  names `--fdr-level` and `--experiment-fdr` (the blib gate), with a failing-first check in
  `TestFlippedDefaultsParticipateInTheValidityKey`; transfer run directories re-run FirstPassFDR once. Accepted, in
  the PR text: a charge a pass-2 floor pushes past the gate falls back to an unreconciled sibling charge. Gate
  688/688, 0 inspection; regression All PASSED on 4bce784f5c (4,599 s; `ai/.tmp/sessions/20261104-night/
  pr2-regression.log`). Opened as **#5016** (into #4950); follow-up perf and disk issue **#5018**.
- **MACS2 (2026-11-10): Osprey is not bit-identical across Windows and Linux, and has not been since before #4950.**
  #5016's Osprey Linux .NET build (TC 4258345) failed only `TestProteinBestPipeline`: the protein-best-off digest pinned
  on Windows (484FA69B...) came out 0D193CB9... on Linux. It is the first unit test that pins analysis bits across
  platforms. Bisected in a re-imported WSL distro (`OspreyLinux`, D:\WSL\OspreyLinux, Ubuntu 24.04, SDK 10.0.115; the
  tree must be a git repo for VendorPinsGenerator) on the Stellar subset, same arguments as the test
  (`ai/.tmp/sessions/20261104-night/subset-off.sh`, `cmp_platforms.py`; outputs `D:\Users\brendanx\test\linuxrepro`):
  - Windows vs Linux at the PR head: 6 of the parquet's feature columns differ by 1-4 ulp in a few rows per file -
    `peak_apex`, `peak_area`, `peak_sharpness` (`PeakShapeCalculators.cs:146`, `Math.Log10`, unchanged since the port)
    and `median_polish_cosine`, `_residual_ratio`, `_min_fragment_r2` (`TukeyMedianPolish.cs`, `Math.Exp`/`Math.Log`);
    everything downstream follows. The platform C libraries (UCRT vs glibc) differ in the last bit; ~30 raw
    `Math.Exp`/`Log`/`Log10`/`Pow` calls remain in scoring, FDR and peak detection outside `DeterministicMath`
    (which has only Exp and Log).
  - Linux, #4950 c0c2bcd43c default vs PR head `--protein-best off`, same work path: every parquet, sidecar, spectra
    cache and model byte-identical (only the calibration.json timestamp differs). The PR's "off is the pre-column
    analysis" holds on each OS. Fix in #5016 (520b383045): the pin is per OS (`PreProteinBestDigest`); gate
    688/688 + 0 inspection on Windows, and the full suite 688/688 on Linux in WSL (`linuxrepro\linux-tests.log`).
  - Two portable exp/log classes already exist, each for its own subsystem: `DeterministicMath` (Osprey.Core, fdlibm
    5.3, #4967, GBDT only, `OSPREY_DETERMINISTIC_MATH` switch, pinned-grid test) and Mike's `PortableMath`
    (Osprey.Demux, e1b2446b83 on the unmerged #4710 branch, with `TestDemuxPortableMath` and a "math library" item 5 in
    `docs/16-determinism.md` saying `regression.ps1` runs on Windows only). Neither has Log10 or Pow or reaches scoring.
    Standardize on `DeterministicMath`; Demux moves to it when the port merges. #5005 (HRAM spectrum-match and
    library-agreement families) already uses `DeterministicMath`; the raw calls left are in the older families.
- **MACS2 night 2026-11-10: defaults audit for checkpointing #4950 into master with no default change** (Brendan:
  merge #5016 into #4950, then #4950 into master with every gap setting opt-in). Log
  `ai/.tmp/night-session-budget-20261110.md`.
  - Since the master base ab7c6b21a7 the regression goldens were re-recorded once, ce85b50fd1 (--protein-best on).
    No other change on #4950 or #5016 moves a default output on the four regression datasets.
  - SEA-AD matched 3 files (A01_005, A06_010, A10_014; split-sized r1.0; `runs-audit`, driver
    `ai/.tmp/sessions/20261104-night/audit3.ps1`): master 61591d866b at defaults vs #5016 (4bce784f5c) with
    `--protein-best off`: `fdrbench.pass1/2.tsv` byte-identical, parquets equal in every column (4,325,912 rows per
    file), 7.7 GB each. Found at true FDP 1% (pass 2): 45,858.
  - The recipe reproduces on #5016: GBDT 74,646 at FDP 1% (-5.1% vs DIA-NN NN 78,668; q 1% kept 73,978 at 0.91%),
    SVM 65,728 (+5.2% vs `--no-nn` 62,472; 64,415 at 0.85%); 13 GB per 3 files without the spectra caches. Wall
    times overlapped a regression on the machine; UW8's same-machine timings remain the reference.
  - Branch `nightlywork/20261110_defaults_off` (pwiz-nightbase, local): --protein-best default off, goldens restored
    to master's; gate 688/688 + 0 inspection; regression against master's goldens running.
  - `git merge-tree origin/master` into #5016: conflicts only `SubsetPipelineTest.cs` (~375, union of asserts),
    `docs/12-second-pass-fdr.md` (pass-2 mode table) and the goldens master's #4823 changed.
  - `OSPREY_GBT_OOF` is in no task validity key (`OspreyEnvironment.cs` 756/1117): a resume can adopt FirstPassFDR
    outputs made under the other setting. Research-only today; key it before it becomes a lever.
  - Open (own PR; changes every golden): route the scoring transcendentals through `DeterministicMath` (add Log10 and
    an integer-exponent Pow), measure the cost on the median-polish hot path, recapture goldens. Also check how the
    11-03 Linux Stellar regression PASS against Windows goldens was possible with `peak_apex` already diverging (what
    the regression compares).

## Machine-sharing check

Before timing anything: `quser` and `tasklist /v /fi "imagename eq Osprey.exe"` (the session column names the
owner; another user's processes cannot be stopped). On MACS2 the night of 2026-11-08 another user's two Osprey jobs
used ~26 cores from 19:42, so that night's wall times are inflated.
