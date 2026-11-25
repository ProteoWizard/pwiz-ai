# TODO: Per-file first-pass FDR model (DIA-NN style) - moves FirstPassFDR's work into the fan-out

## Branch Information
- **Branch**: `Skyline/work/20261122_osprey_per_file_fdr` (pushed to origin; was `nightlywork/20261121_osprey_per_file_fdr`)
- **Base**: `master` (b3dcb52e07)
- **Created**: 2026-11-21
- **Status**: Completed
- **Module**: `osprey`
- **PR**: [#5070](https://github.com/ProteoWizard/pwiz/pull/5070) (merged 2026-11-24)

## Goal

**The key benefit is HPC** (Brendan, 2026-11-22). FirstPassFDR is the single-node join. Today it
accumulates per-file work - the training-feature loads, the two-round training, scoring all
~359 M rows - and must be shipped every run's ~2 GB `.scores.parquet` (~165 GB at 82 files).
Training the first-pass model per file moves that work into the fan-out stage, where it scales
with nodes, and shrinks the join to a competition over ~0.2 GB/file stubs (~15 GB shipped).

Storage (the ~165 GB of feature parquet a cohort writes, against DIA-NN's 7.5 GB total) and
MACS2's file parallelism are secondary benefits. Single-box wall time may be roughly a wash -
first guess PerFileScoring +40-80 min, FirstPassFDR down to ~15-30 min, total ~5.5-6 h against
5 h 11 m with `--parallel-files` on UW8. That is a guess to be measured; interpret performance
with caution until it is.

The question this study answered first: does a per-file model keep the detections? Osprey finds
97,120 precursors at true FDP 1% (pass 1) on SEA-AD 82 files, within 4% of DIA-NN's 101,269.
Measured on real data before any redesign.

## Design (study hook)

`OSPREY_PER_FILE_FDR` (developer switch, keyed into the gbdt validity key):

- unset: master behavior (A0).
- `model` (A1): the global two-round training still runs (round 1 provides PROTEIN_BEST); in
  pass 1 each file then trains its own gbdt on its own rows (best peak per precursor in the
  run, subsample to MaxTrainSize, 3 folds by peptide group), scores ALL its rows out of fold
  (each row by the fold model that held its peptide group out), and calibrates per file
  (Granholm affine map: run-q 1% threshold -> 0, median best-per-entry decoy -> -1) so the
  max-over-runs experiment competition compares like with like.
- `stacked` (A2): a per-file pre-pass trains each file's model WITHOUT PROTEIN_BEST, the same
  way, and the existing global two-round trainer then trains on one feature, the per-file
  calibrated score (+ PROTEIN_BEST computed from round 1 on that single feature). This is the
  shape that could ship: after PerFileScoring nothing would need the feature parquet.
- `OSPREY_PER_FILE_FDR_ROUNDS=2` (A1b, A2b, A3): each per-file model trains in two rounds, as the
  global model does (`PercolatorTrainer.TrainWithScorePrefilter`).
- `file` (A4): `model`, two rounds, with each file computing PROTEIN_BEST from its OWN round-1
  model - no input to the file's model crosses files. The design that would ship.

Measured at FirstPassFDR only: the persisted model stays global, so pass 2 under transfer is not
valid for these arms.

## How to run the A4 arm (any machine)

Branch `Skyline/work/20261122_osprey_per_file_fdr` (pwiz). Build Release, snapshot the
output dir (`D:\test\osprey-runs\_bin\<tag>` or the machine's equivalent), then with a
completed 82-file SEA-AD run of the same build line as the input (its `.scores.parquet` are
what FirstPassFDR reads; the runner pins `OSPREY_VERSION_OVERRIDE` from it):

```powershell
$env:OSPREY_PER_FILE_FDR = 'file'      # per-file two-round model with its own protein-best column
# optional cost levers (unset = A4 as measured):
#   $env:OSPREY_PER_FILE_FDR_TRAIN_SIZE = '100000'   # round-1 rows per file (round 2 = 2/3)
#   $env:OSPREY_GBT_N_TREES = '100'; $env:OSPREY_GBT_MAX_ITERATIONS = '10'
pwsh -File ai/scripts/Osprey/SEA-AD/Run-SeaAd.ps1 -Exe <snapshot>\Osprey.exe `
    -LibraryDir '<lib root>\target+decoy+entrapment-20260817-split-sized' `
    -Task FirstPassFDR -LinkFrom '<completed 82-file run dir>' -Tag '-pfA4'
python -I ai/scripts/Osprey/SEA-AD/tools/split_calibration.py `
    --lib-dir '<lib root>\target+decoy+entrapment-20260817-split-sized' --osprey '<new run dir>'
```

The runner does not strip `OSPREY_PER_FILE_FDR*` or `OSPREY_GBT_*`, so they pass through from
the launching shell; the run.log "Environment switches:" line records them. Leave
`-FdrFileLanes` to the resolver unless measuring per-file cost at full threads (`-FdrFileLanes 1`).
A0 reference on BRENDANX-UW25: 97,120 at true FDP 1%, A4 98,280.

## Arms

Input: `D:\test\osprey-runs\sea-ad\runs\seaad-82files-libdecoy-r1.0-default-pr5043` (not
modified). Each arm: `Run-SeaAd.ps1 -Task FirstPassFDR -LinkFrom <pr5043> -Tag -pf<arm>`.
Scored with `split_calibration.py` (pass-1 row `p1`).

| arm | p1 at true FDP 1% | delta vs A0 | q-1% kept (FDP) | FirstPassFDR wall | per-file training | peak private |
|---|---|---|---|---|---|---|
| pr5043 source | 97,120 | | 96,870 (0.97%) | 4061 s | - | |
| A0 control | 97,120 | 0 | 96,870 (0.97%) | 4015 s | - | 45.7 GB |
| A1 per-file (one round) | 90,202 | -6,918 (-7.1%) | 89,615 (0.97%) | 5212 s | 10,602 s lane (~25 min wall of 7 lanes) | 48.9 GB |
| A1b per-file, two rounds | 97,233 | +113 (+0.1%) | 96,394 (0.90%) | 7004 s | 22,751 s lane (~54 min wall) | 74.6 GB |
| A2b two-level, two-round level 1 | 96,151 | -969 (-1.0%) | 95,705 (0.95%) | 4805 s | 21,385 s lane; pre-pass 3834 s wall | 72.2 GB |
| A3 per-file, two rounds, no PROTEIN_BEST | 90,349 | -6,771 (-7.0%) | 86,276 (0.60%) | 5852 s | 22,067 s lane | 75.1 GB |
| A2 two-level (one-round level 1) | 89,796 | -7,324 (-7.5%) | 89,088 (0.95%) | 2985 s | 9,140 s lane; pre-pass 2003 s wall | 45.4 GB |
| **A4 fully per-file, own PROTEIN_BEST** | **98,280** | **+1,160 (+1.2%)** | 97,433 (0.93%) | 7509 s | 25,490 s lane | 98.0 GB |
| A5 = A4 with `OSPREY_GBT_MAX_ITERATIONS=5` | 97,266 | +146 (+0.15%) | 96,486 (0.93%) | 6075 s | 15,423 s lane (-39%) | 93.4 GB |

Wall and memory of A1-A4 are study numbers, not production ones: the per-file models train on
FirstPassFDR's 7 file lanes at 4 threads each, every lane holds its file's ~4.5 M candidate
feature vectors for the two-round training, and the global training still runs beside them.

## Progress

- 2026-11-21: master Release snapshot `D:\test\osprey-runs\_bin\perfile-a0-master-b3dcb52e07`;
  A0 launched 13:24.
- A0 (master, hook absent) reproduced the pr5043 pass 1 exactly: 97,120 at true FDP 1%,
  97,191 at experiment q 1%, every per-file count identical. 4015 s, peak private 45.7 GB,
  no reporting gap >= 30 s. Log: `ai/.tmp/sessions/20261117-5ada8293/perfile/run-A0.log`
  (run dir deleted). The harness is valid.
- pwiz 0b7e8bde1c: the switch (`PerFileFirstPassModel.cs`, hooks in
  `PercolatorEngine.RunStreamingFirstPass`). Build + 671 tests + inspection green. Release
  snapshot `D:\test\osprey-runs\_bin\perfile-0b7e8bde1c`.
- 3-file smokes (FirstPassFDR, linked, `-NumFiles 3`): stacked completed (254 s; pre-pass
  103 s wall), 74,125 at experiment q 1%; model completed (279 s), 75,127.
- A1 (`model`, 82 files, 14:41-16:08): 90,202 at true FDP 1%, -7.1% vs A0; calibration held
  (q 1% kept 89,615 at FDP 0.97%). Experiment q 1%: 89,909. FirstPassFDR 5212 s (+1197 s);
  per-file training 10,602 s summed lane time at 4 threads/file, scoring 1,920 s, calibrate
  510 s; pass-1 wall 2646 s vs 1299 s. Peak private 48.9 GB, no gap >= 30 s.
  Per-file run-level passing targets fell in EVERY file: median -6.7% (files 1-40 -6.6%,
  41-75 -7.0%, pools -7.8%), range -4.0% to -18.1% (file 55). The late weak files were not
  helped: positions 69-82 -4.3% to -12.9%. Total run-level passes 4,523,486 -> 4,192,000.
  Logs: `perfile/run-A1.log`, `perfile/split-A1.txt`, `perfile/perfile-A1.txt` (run dir deleted).
  Confound: the per-file model trained ONE round from the best single feature (~1,000-1,700
  targets at 1% to start), while the global model trains two rounds, round 2 seeded by round 1's
  scores on the 200k groups round 1 scores best. Added `model2` / `stacked2` (per-file two-round)
  to remove it.
- A2 (`stacked`, 16:09-16:58): 89,796 at true FDP 1%, -7.5%; q 1% kept 89,088 at FDP 0.95%.
  FirstPassFDR 2985 s, 1030 s FASTER than A0: the feature parquet is read once (161 GB of
  parquet reads vs 443 GB), the pre-pass is 2003 s wall (train 9,140 s summed), and the global
  training and pass 1 then run on one cached feature (pass-1 wall 327 s vs 1299 s; the
  protein-best column for round 2 took 48 s vs 1031 s). Peak private 45.4 GB (the resident
  per-file scores, 2.9 GB, are inside A0's peak). One reporting gap of 69 s (the pre-pass
  reports per finished file).
  Per-file run-level passing fell more than in A1: median -11.7% (1-40 -11.1%, 41-75 -12.2%,
  pools -11.7%), range -6.7% to -27.2%; total 3,994,208. The run-level q in A2 comes from the
  level-2 model's score, which sees only the per-file score and PROTEIN_BEST.
  PROTEIN_BEST at level 2: round 1 on the single per-file score, round 2 with the column
  reached 46.9-48.8% of training targets at 1% (A0's round 2: 49.9-53.5%). Experiment-level
  A2 lands within 406 of A1, whose per-file models had the column as a raw feature, so the
  stacked column recovers about what the per-file column gave; it does not recover the global
  model's 7%.
  Logs: `perfile/run-A2.log`, `split-A2.txt`, `perfile-A2.txt`, `perfviz-A2.txt`.
- pwiz 32d8922bba: `OSPREY_PER_FILE_FDR_ROUNDS=2` trains each per-file model the way the
  global one is (`PercolatorTrainer.TrainWithScorePrefilter`: every best-per-precursor row of
  the file is a candidate, ~4-5 M; round 2 on the 200k best groups, seeded by round 1). 3-file
  smoke: per-file run-level passes 61,466 / 70,448 / 69,309 vs one round 55,145 / 66,049 /
  64,835. The one-round training, not the per-file split, was the 7% loss.
- A1b (`model`, rounds 2, 17:19-19:16): **97,233 at true FDP 1%, +113 (+0.1%) vs A0** - parity.
  q 1% kept 96,394 at FDP 0.90% (slightly conservative); experiment q 1% 96,692.
  Per-file run-level passing: median +0.7% (files 1-40 +0.4%, 41-75 +1.1%, pools +1.9%),
  range -1.9% to +4.5%; the weakest late files and pools gain most (pool-07 +4.5%, pool-05
  +3.1%). Total run-level 4,523,486 -> 4,556,711.
  Cost: FirstPassFDR 7004 s (+2989 s vs A0); per-file training 22,751 s summed lane time at
  4 threads/file (~54 min of wall across 7 lanes), pass-1 wall 4450 s. Peak private 74.6 GB
  (A0 45.7): each lane holds its file's ~4.5 M candidate feature vectors (~2.5 GB) through
  round 1's scoring. No gap >= 30 s. Logs: `perfile/run-A1b.log`, `split-A1b.txt`,
  `perfile-A1b.txt`, `perfviz-A1b.txt`.
- A2b (`stacked`, rounds 2, 19:16-20:36) - the shape that could ship: **96,151 at true FDP 1%,
  -969 (-1.0%) vs A0**; q 1% kept 95,705 at FDP 0.95%; experiment q 1% 96,038.
  FirstPassFDR 4805 s (+790 s vs A0): pre-pass 3834 s wall (train 21,385 s summed), then the
  global two-round training on [per-file score, PROTEIN_BEST] and pass 1 take minutes (pass-1
  wall 297 s; the round-2 protein-best column 36 s vs 1031 s). Peak private 72.2 GB (the
  per-file two-round candidates again). One 68 s reporting gap at the start of the pre-pass.
  Level-1 strength: each file's round 2 started at 24k-66k targets at 1% (of 200k).
  Level 2: round 2 with PROTEIN_BEST reached 49.4-50.7% of training targets at 1% (A0 49.9-53.5%).
  Per-file run-level passing: median -4.8% (1-40 -4.6%, 41-75 -5.2%, pools -4.2%), range -3.3%
  to -7.6%; total 4,309,160. Run level loses more than experiment level: the level-2 model's
  score (per-file score + PROTEIN_BEST) separates within a run less well than A1b's per-file
  model, which took PROTEIN_BEST as one of its 71 raw features.
  Logs: `perfile/run-A2b.log`, `split-A2b.txt`, `perfile-A2b.txt`, `perfviz-A2b.txt`.
- A3 (`model`, rounds 2, `--protein-boost off`, 20:38-22:15): per-file two-round models with no
  PROTEIN_BEST anywhere: **90,349 at true FDP 1%, -7.0% vs A0**; q 1% kept 86,276 at FDP 0.60%
  (conservative). Per-file run-level -11.4% median vs A0, -12.0% vs A1b. FirstPassFDR 5852 s,
  peak 75.1 GB. So PROTEIN_BEST is worth +6,884 (+7.6%) as a per-file raw feature (A3 -> A1b)
  and +5,802 (+6.4%) when added only at level 2 (A3 -> A2b): the stacked design keeps 84% of the
  column's value. Logs: `perfile/run-A3.log`, `split-A3.txt`, `perfile-A3.txt`.
- The protein-best column is per RUN already (`ProteinBestFeature.ComputeColumn`: each row's best
  sibling-peptide score on its proteins within the same run); only the round-1 model that scores
  the run is global. So a fully per-file design can compute it from the FILE's own round-1
  model. Added `OSPREY_PER_FILE_FDR=file` (always two rounds) to measure that (A4).
- A4 (`file`, 22:35-00:40): **98,280 at true FDP 1%, +1,160 (+1.2%) vs A0**, +1,047 vs A1b;
  q 1% kept 97,433 at FDP 0.93%; experiment q 1% 97,748. Per-file run-level passing: median
  0.0% vs A0 (files 1-40 -0.6%, 41-75 +0.4%, pools +1.4%, pool-07 +4.1%), range -1.3% to
  +4.1%; -0.8% vs A1b at run level but +1.1% at experiment level. FirstPassFDR 7509 s; per-file
  training 25,490 s summed lane time (~311 s a file at 4 threads); peak private 98.0 GB (7 lanes
  x the two-round candidate features plus the file's own column; the global training also ran).
  No gap >= 30 s. Logs: `perfile/run-A4.log`, `split-A4.txt`, `perfile-A4.txt`, `perfviz-A4.txt`.
  Every arm's run dir is deleted; logs under `ai/.tmp/sessions/20261117-5ada8293/perfile/`.

## Decisions

- A0 reproduced 97,120 exactly, so the harness is valid.
- The 7% loss of the first arms was the ONE-round per-file training, not the per-file split:
  with two rounds the per-file model matches (A1b) or beats (A4) the global one.
- PROTEIN_BEST is worth ~7% and does not need an experiment-wide model: computed per run from
  the file's own round-1 model (A4) it does better than from the global round 1 (A1b). Stacking
  it at a global level 2 (A2b) keeps only 84% of its value and costs 1% of detections, so the
  stacked design is not needed.
- Per-file models gain most on the weak late files and pools (+1.4% median pools, +4.1% on the
  last pool), as expected of a model fitted to each run's own quality.
- Calibration stayed honest in every arm (q 1% kept at FDP 0.90-0.97%; A3 without the column
  is conservative at 0.60%).

## Cost sweep (2026-11-22)

pwiz c04008a63c adds a [TIMING] line per file (wall, threads, rows, final training rows,
train / protein-best column / out-of-fold scoring seconds) and a round-1 vs round-1-scoring line
from the two-round trainer; 27264fea33 adds `OSPREY_PER_FILE_FDR_ROUND2_SIZE` and
`OSPREY_GBT_PATIENCE` (c991a2bd9a fixed the `/code-review medium` findings on them). Smokes: `ai/.tmp/sessions/20261117-5ada8293/perfile/sweep.ps1` and
`chain-smokes.ps1`: 3 files, FirstPassFDR only, `-FdrFileLanes 1` so each file trains ALONE at
30 threads - the PerFileScoring layout. The per-file model sees only its own file, so the 3
files' run-level passing targets are exactly what an 82-file run gives those files (A4's files
1-3 match the smoke to the target). Metric: the sum of the 3 files' run-level passes.

Where the time goes (A4 default, 30 threads, ~80 s a file): round 1 (300k rows) ~25-40 s, round 2
(200k rows) ~40 s, the file's protein-best column 3.3 s, round-1 scoring of ~4.4 M candidates
~3 s, out-of-fold scoring of every row ~4 s. Inside a round, each of 3 folds (10 threads each)
costs ~13 s per semi-supervised iteration (one 200-tree GBDT on the selected targets plus all
decoys), and a fold runs a mean 5.9 iterations, the last two of them only to confirm the early
stop (patience 2). At 4 threads (A4's 7 lanes) a file took 311 s = 1,244 thread-s; at 30 threads
83 s = 2,490 thread-s, so the training is ~50% efficient at 30 threads.

| point | 3-file run-level sum | vs A4 | per-file training wall @30 thr |
|---|---|---|---|
| A4 default (300k / 200k rows, 200 trees, max 30 iter, patience 2) | 200,832 | 0 | 82.9 s |
| iterations <= 6 | 200,343 | -0.24% | 61.1 s |
| patience 1 | 200,076 | -0.38% | 64.2 s |
| **iterations <= 5** | 199,776 | -0.53% | **53.9 s** |
| iterations <= 5, patience 1 | 199,009 | -0.91% | 52.4 s |
| round 1 100k, round 2 200k | 198,562 | -1.1% | 58.2 s |
| 100 trees, learning rate 0.2 | 198,335 | -1.2% | 48.4 s |
| round 1 100k / round 2 200k, patience 1 | 198,070 | -1.4% | 49.0 s |
| iterations <= 4 | 197,866 | -1.5% | 46.0 s |
| iterations <= 5, 150 trees | 197,318 | -1.7% | 43.6 s |
| iterations <= 3 | 196,086 | -2.4% | 39.0 s |
| 100 trees | 192,943 | -3.9% | 43.7 s |
| 50 trees | 181,008 | -9.9% | 29.6 s |
| 100k rows (round 2 67k) | 165,582 | -17.6% | 36.3 s |
| 50k rows (round 2 33k) | 155,387 | -22.6% | 24.6 s |

Shrinking the training rows is the worst lever - round 2's size is what matters (round 1 at 100k
with round 2 kept at 200k costs only 1.1%). Fewer trees costs more than it saves. Capping the
semi-supervised iterations is the cheapest: `OSPREY_GBT_MAX_ITERATIONS=5` (an existing switch)
cuts 35% for 0.5%.

**A5 (82 files, `file` + `OSPREY_GBT_MAX_ITERATIONS=5`, 06:48-08:29)**: 97,266 at true FDP 1%,
+146 (+0.15%) vs A0 but -1,014 (-1.0%) vs A4 - twice the 3-file estimate, so the cap costs
more on the later files. q 1% kept 96,486 at FDP 0.93%. Per-file run-level vs A0: median -0.7%
(files 1-40 -1.0%, 41-75 -0.3%, pools +0.6%, pool-07 +3.5%). Training 15,423 s summed lane time,
-39% vs A4 (223 s a file at 4 threads); FirstPassFDR 6075 s; peak private 93.4 GB; no gap
>= 30 s. Logs `perfile/run-A5.log`, `split-A5.txt`, `perfile-A5.txt`, `perfviz-A5.txt`.

**Projected PerFileScoring cost if training moved there** (files sequential, 30 threads; today
~160 s a file, Stage 1-4 13,119 s at 82 files): A4 +83 s a file (+52%, +113 min at 82 files);
A5 +54 s (+34%, +74 min). Against that, FirstPassFDR (67 min today) would become a reduce over
stubs - a guess of 15-30 min, from A2's ~5-min pass 1 on cached scores plus protein FDR and
planning. Single box, files sequential: roughly +30 min (A5) to +70 min (A4) on a ~6.3 h run.
With file parallelism the training is ~2x more thread-efficient (1,244 thread-s a file at 4
threads vs 2,490 at 30 in A4; 892 at 4 threads in A5): ~41 min of a 30-thread box at A5 for 82
files, ~17 min on MACS2's 72 threads, if it overlaps perfectly. Unmeasured; caution until it is.

**Decision (Brendan, 2026-11-22)**: roughly a wash on single-machine wall time is acceptable - the
design is justified by HPC (the map-reduce join), disk, a modest detection gain, and following the
per-run model DIA-NN and others use. Training cost is NOT optimized further now.

`/code-review medium` on the branch (8 findings): fixed in c991a2bd9a - patience passed into the
explicit validity-key overload, the round-2 size keyed only when a round 2 runs and never enabling
one, a named patience default, corrected docs. Dropped: patience carried on PercolatorConfig
(the switch is deliberately process-wide, shared by the global and per-file models) and new
validity-key unit tests (experiment switches; the terms are append-only and read in review).

### Future performance area: per-file training cost

What the sweep found: each fold costs ~50 s fixed + ~13 s per semi-supervised iteration
single-threaded (from A4's 7-lane log, 1 thread a fold), and a fold runs ~6 iterations, the last
two only confirming the early stop. Iterations and trees are the levers that beat training-set
size (round 2's size is what the model needs). Obvious headroom: intra-fold parallelism (at 30
threads the training is ~50% efficient), and overlapping a file's training with the next file's
scoring in PerFileScoring.

## Developer design direction (Brendan, 2026-11-22)

**Target principle (Brendan, 2026-11-22): PER-FILE TASKS WRITE ALL PER-FILE SIDECARS; FDR JOIN
TASKS (FirstPassFDR, SecondPassFDR) WRITE ONLY EXPERIMENT-WIDE FILES.** To propose, with B's
map-reduce rule, as new principles in `pwiz_tools/Osprey/docs/00-pipeline-architecture.md`.

Audit of what the two join tasks write today (source: each task's `Outputs()`, master b3dcb52e07,
plus the writes `Outputs()` does not declare):

| task | artifact | scope | declared | where it should live |
|---|---|---|---|---|
| FirstPassFDR | `<run>.1st-pass.fdr_scores.bin` (run-scope score, run q x2, apex RT, FeatureSums; written per file from its lane by `flushFileRunScope`) | per-file | yes | **PerFileScoring** - it becomes the per-file stub (E) |
| FirstPassFDR | `<run>.1st-pass.protein_best.bin` (`--protein-boost best`: the column each run was scored with, read by pass 2) | per-file | yes | **PerFileScoring** - with per-file models each file computes its own column (A4) |
| FirstPassFDR | `<blib>.1st-pass.fdr_experiment.bin` | experiment | yes | stays |
| FirstPassFDR | `<blib>.1st-pass.consensus.json` (cross-run consensus RT) | experiment | yes (with reconciliation) | stays |
| FirstPassFDR | `<blib>.1st-pass.retained_base_ids.bin` | experiment | yes | stays |
| FirstPassFDR | `<blib>.1st-pass.model-diagnostics.json` | experiment | yes (with `--model-diagnostics`) | stays |
| FirstPassFDR | `<blib>.1st-pass.model.json` (global model, `FirstPassModelIO.WriteText`) | experiment | no | becomes per-file models written by PerFileScoring; a global one only if a stacked level 2 is kept |
| FirstPassFDR | `<blib>.1st-pass.stratum.json` (protein-compact stratum) | experiment | no | stays |
| FirstPassFDR | `fdrbench.pass1.tsv` + `.pairing.tsv` | experiment | no (best-effort) | stays |
| SecondPassFDR | the output `.blib` | experiment | yes | stays |
| SecondPassFDR | `<blib>.model-diagnostics.html`, `<blib>.2nd-pass.model-diagnostics.json` | experiment | yes (with `--model-diagnostics`) | stays |
| SecondPassFDR | `<blib>.2nd-pass.fdr_experiment.bin` | experiment | yes | stays |
| SecondPassFDR | `fdrbench.pass2.tsv` + `.pairing.tsv`, `<blib>.2nd-pass.protein-entrapment.json` | experiment | no (best-effort) | stays |

SecondPassFDR already conforms: since #4816 every per-file pass-2 artifact
(`.2nd-pass.fdr_scores.bin`, `.reconciliation.json`, `.scores-reconciled.parquet`, the
protein-compact competition decoys) is PerFileRescoring's output and only an INPUT here.
FirstPassFDR violates the principle in exactly two places, the two per-file sidecars at the top,
and both move to PerFileScoring under the per-file model. Its per-file INPUT, the
`.scores.parquet`, is the other half: under the principle it reads the per-file stubs instead.

### A. The primary risk: single-machine throughput

Today FirstPassFDR trains ONE model from a cross-file summary; per-file training multiplies
model building by the run count, serialized on a workstation. Osprey's throughput lead over
DIA-NN on UW8 (SEA-AD 82: 5 h 11 m with `--parallel-files`, DIA-NN 9 h 49 m) could be a mirage
if detection parity and the disk saving cost it. So the sweep's headline number is per-file
training wall seconds at 30 threads with files sequential, against the ~160 s/file
PerFileScoring costs now (pr5043: Stage 1-4 13,119 s / 82 files), and what that does to total
wall time. Measured and projected in the cost sweep above; the developer accepted roughly a wash
(no stop threshold): HPC, disk and detections justify the design.

### B. Architecture goal: map-reduce, nothing across runs grows with run count

Target 5,000 runs. Each run contributes a fixed-size, mergeable summary, merged associatively
(tree-reducible): the best target/decoy score per precursor (max), score histograms for PEP and
q, per-protein max/counts for PROTEIN_BEST and protein FDR, and a fixed RT summary per precursor
for reconciliation (an exact median is not mergeable - it needs an approximation tested for
equivalence). The join holds O(library), not O(runs x rows); pass 2 gets the library-sized
result broadcast back. Still O(runs) and needing separate design: the blib's per-run RT rows
(~21 M at CHS 446, ~240 M at 5,000 - per-run outputs plus an index), the spectra caches (direct
raw reading removes them), and the total training compute (which fans out). To propose as a new
principle in `pwiz_tools/Osprey/docs/00-pipeline-architecture.md`.

### C. The iteration workflow must survive - the sprint's FIRST milestone

"We do need to do the coding work to preserve our iterative testing model and keep exporting
feature Parquet an option." Tasks communicate only through files, never in-memory structures,
so PerFileScoring is NOT split into two tasks:

1. **The HPC pipeline stays four file-to-file tasks**: PerFileScoring (reads spectra + library,
   plus its OWN valid `.scores.parquet` when present; writes the per-file stub + per-file model,
   and the `.scores.parquet` only with `--keep-scores-parquet`) -> FirstPassFDR (map-reduce over
   stubs) -> PerFileRescoring -> SecondPassFDR. Per-file modeling lives inside PerFileScoring;
   the parquet is an optional input/output of that one task, not a link between tasks.
2. **Two validity keys inside PerFileScoring**: the parquet's stamp covers feature settings only;
   the stub/model stamp adds the model settings. Feature stamp matches -> skip extraction and
   re-model from the parquet; a model change reuses the features, a feature change re-extracts.
3. **Composite `--task FirstPass`** (PerFileScoring + FirstPassFDR) and **`--task SecondPass`**
   (PerFileRescoring + SecondPassFDR), for local iteration only, like the ModelDiagnostics
   composite; HPC designers never need them. The loop becomes
   `--task FirstPass -LinkFrom <run with parquet>` WITH an explicit `--parallel-files` (the
   dataset runners should pass it by default for the FirstPass composite). Re-modeling 82 files
   is ~54 s/file (~74 min sequential at the A5 setting), a bit slower than today's ~65-min
   FirstPassFDR loop; file parallelism and 3-file loops cover quick checks.
4. **Only after that lands**: default the parquet off.

On the current experimental branch the training still runs in FirstPassFDR from the parquet, so
the existing `--task FirstPassFDR -LinkFrom` loop is unaffected.

### D. FirstPassFDR becomes a true reduce

Its internal file lanes exist because per-file work was hiding in the join. With per-file
modeling in PerFileScoring, FirstPassFDR needs no file lanes, and file parallelism lives only in
the fan-out stages, under `--parallel-files`.

### E. Can the existing run-scope sidecar BE the per-file stub? Mostly yes.

FirstPassFDR already writes each file's run-scope `.1st-pass.fdr_scores.bin` (format v9,
`Osprey.IO/FdrScoresSidecar.cs`) from that file's lane before any cross-file step
(`flushFileRunScope`), and the experiment scope goes to the separate `.1st-pass.fdr_experiment.bin`.
A record is entry_id, score, run precursor q, run peptide q, apex RT (36 bytes; 158.6 MB for
SEA-AD file 1 against its 2,026 MB `.scores.parquet`), plus the run's FeatureSums. Written by
PerFileScoring instead, it carries what the reduce's competition needs:

- the experiment competition and PEP: entry_id (the decoy flag is its high bit) and the
  calibrated score;
- the best-of-runs clamp floors: the two run q-values;
- consensus RT for planning: apex RT.

What the reduce needs beyond it, and where it comes from:
- **peptide (modseq) and charge** per entry, for the peptide-level competition and protein FDR:
  O(library), from the library by entry_id (or the stub parquet below) - not a per-row column.
- **protein membership** for protein FDR: the library, as today.
- **coelution_sum**: needed only by the global training's best-per-precursor dedup, which goes
  away; nothing in the reduce reads it.
- **PEP fit inputs**: the competition winners' scores, which the reduce derives from the stubs.
  At 5,000 runs this should become a mergeable score histogram (B).

What it does NOT cover: PerFileRescoring and planning read scalar stub columns of the
`.scores.parquet` (`ParquetScoreCache.LoadFdrStubsFromParquet`: entry_id, is_decoy, charge,
modified_sequence, coelution_sum, apex_rt, start_rt, end_rt, bounds_area, scan_number,
score_index). Without `--keep-scores-parquet`, PerFileScoring should still write those scalars - a
feature-free "stub parquet" of the same name and schema minus the feature columns, so every
existing reader works unchanged - or extend the sidecar by them. Prefer the feature-free parquet:
no new format, and the feature columns are almost all of the bytes. The per-file model itself
(trees + standardizer + calibration) is a new per-file artifact (FirstPassModelIO per file).

## Production design (what a sprint would build)

Milestone 1 is the iteration workflow (C above), ahead of any default change. Then:

- PerFileScoring trains the file's two-round model with its own protein-best column after
  extraction, scores every row out of fold, calibrates (run q 1% -> 0, median best decoy -> -1),
  and writes the run-scope sidecar (E) plus the feature-free stub parquet; the feature parquet
  only with `--keep-scores-parquet`. Memory: one file's ~4.5 M candidate vectors (~2.5 GB) plus
  the column, once per concurrent file.
- FirstPassFDR becomes a reduce (D): the experiment competition on calibrated scores (max over
  runs), experiment q/PEP, protein FDR, planning; no feature loads, no file lanes; heading to
  fixed-size mergeable per-run summaries (B).
- Pass 2: PerFileRescoring re-scores reconciled peaks with the FILE's frozen first-pass model, so
  each file's model and calibration are persisted (FirstPassModelIO per file, read by
  Pass2PerFileWorker), with the transfer score->q table built on calibrated scores.
- Validity keys: the two PerFileScoring stamps (C.2); FirstPassFDR's key covers only the
  competition settings. The `.scores.parquet` contract in `docs/00-pipeline-architecture.md`
  changes, with the two new principles (the per-file/join split, and B's map-reduce rule).
- Unmeasured: pass 2 under per-file models, single-box and HPC throughput, unit resolution
  (SVM), and small cohorts where a file has few precursors to train on.

## Session 2026-11-22 (afternoon): milestone 1, first working version (uncommitted)

- Step 1 done: `docs/00-pipeline-architecture.md` - two corollaries under P3 (per-file tasks
  write every per-run artifact, joins only experiment-wide; joins read fixed-size mergeable
  per-run summaries) and In flight item 5 (per-run first-pass models, the target contract).
- Step 2, first version, under `OSPREY_PER_FILE_FDR=file` only (other arms unchanged):
  - `PerFileScoringTask.WithOwnFirstPassScores`: after a run's parquet is written or kept, reads
    it back (same rows and features FirstPassFDR would load), trains the run's own model
    (`PercolatorEngine.ScoreRunWithOwnModel`, a public wrapper on `PerFileFirstPassModel`), and
    writes `<stem>.1st-pass.fdr_scores.bin` stamped by PerFileScoring under the MODEL key
    (task key + `GbdtValidityKeySuffix`). Declared as a PerFileScoring output with that key
    through `OutputValidityKey`; a current sidecar is kept, so a model change re-models from a
    current parquet without re-extracting (the two keys, step 3, mostly come free).
  - FirstPassFDR: adopts only PerFileScoring-stamped sidecars, refuses the run when any file
    lacks one, and calls the engine with `scoresPrecomputed` (no training-subset load, no
    training, no per-file lanes training). Its Outputs no longer list the per-run sidecars; its
    Inputs do. No protein-best sidecar is written in this arm.
  - `[PATH] not current: <file> (<first differing key term>)` when a PerFileScoring output exists
    but is refused.
- Verified: 3-file smoke (`-NumFiles 3`, A4 settings) - PerFileScoring re-modeled the linked
  parquets at 78-90 s/file (30 threads), FirstPassFDR 102.6 s total (pass 1 13.0 s wall, no
  feature load). Run-level sum 62,251 + 69,469 + 69,112 = **200,832, exactly A4's 3-file
  reference**. 80,026 at experiment q 1%. Run dir
  `D:\test\osprey-runs\sea-ad\runs\seaad-3files-libdecoy-r1.0-default-m1smoke`, snapshot
  `D:\test\osprey-runs\_bin\perfile-m1-wip3`.
- GOTCHA: pr5043 searched the SPLIT library. A PerFileScoring run linked from it needs
  `-LibraryDir D:\test\osprey-runs\sea-ad\lib\target+decoy+entrapment-20260817-split-sized`;
  the runner's default library has another pairing manifest, so the search hash differs and every
  file re-extracts (FirstPassFDR-only reruns never check PerFileScoring's stamp, so A0-A5 did not see it).
- Not yet: pass 2 under this arm (no global model, no protein-best sidecar - step 4);
  `--keep-scores-parquet` and the composites (step 3); no SubsetPipelineTest coverage, since the
  arm is a static environment switch.

## Session 2026-11-22 (evening): the stub parquet, and the 82-file performance run

- Committed 926b3140d8 (milestone 1 checkpoint) and 71f668b219: under `OSPREY_PER_FILE_FDR=file`
  each run's model trains from the features IN MEMORY right after the parquet write (rows in
  parquet order via the ParquetIndex the write assigns; values `Finite()` as the parquet stores
  them), and the parquet is a STUB: scalar columns + `fragment_coelution_sum` (the stub readers'
  coelution sum), footer `osprey.feature_columns=stub`, key term `;parquet=stub`.
  `OSPREY_PER_FILE_FDR_KEEP_PARQUET=1` writes the full parquet (becomes `--keep-scores-parquet`
  at step 5). A stub-writing run accepts a stub or a full parquet (`OutputValidityKey` reads the
  footer); a run that needs features refuses a stub (verified: "key term 12: stored
  'parquet=stub', this run '(none)'"), and a stub whose own scores are stale re-extracts.
- Verified: 3-file run from spectra, run-level sum 200,832 and 80,026 at experiment q 1% -
  identical to the parquet-read route. Stub parquet 309 MB vs 2,026 MB full (file 1), written in
  5.7 s vs 9.4 s. A stub-mode rerun skips PerFileScoring ("outputs valid").
- Bug caught at launch, fixed, NOT yet committed: the in-memory route passed ProcessFile's config
  copy, whose threads are already divided by the file lanes, and `PerFileFirstPassModel` divided
  again (3 threads/model at 3 lanes). `WriteOwnModelScores` now takes `ctx.Config`. Gate green.
- 82-file performance run, launched 15:15: `D:\test\osprey-runs\sea-ad\runs\seaad-82files-libdecoy-r1.0-default-m1perf`,
  exe `D:\test\osprey-runs\_bin\perfile-m1-stub3` (71f668b219 + the thread fix), bare
  `--parallel-files` -> 3 files, 10 threads each (148 s/model). PerFileScoring then FirstPassFDR
  `-Resume`, `--diskstamp`. Baseline on this box (TODO-20261114_osprey_hram_defaults, master
  pfauto, run dir deleted): PerFileScoring 10,655 s, FirstPassFDR 4,337 s, 97,120 at true FDP 1%,
  disk 183 GB, peak private 51.5 GB. Read with `perfviz.py <run>/run.log` and `split_calibration.py`.
- **82-file result (first pass only):** 98,280 at true FDP 1% and q 1% kept 97,433 (0.93%) -
  exactly A4. PerFileScoring 14,561 s (vs 10,655, +3,906 s: ~82 x 148 s / 3 lanes of training;
  extraction itself about unchanged, the stub write saves only ~3 s/file). FirstPassFDR 894 s
  (vs 4,337, -79%; pass 1 186 s wall, no feature load). First pass total 15,455 s vs 14,992 s
  (+3%). Disk 35.5 GB for 82 runs (stub 308 MB + own scores 158 MB per run) vs ~179 GB for the
  baseline's first pass (full parquet 2,026 MB + scores 158 MB). Peak private 66.3 GB in
  PerFileScoring (floor level, +38 MB/file), 37.8 GB in the reduce. Log gaps: 9 >= 30 s in
  PerFileScoring (max 156 s) - the per-file training reports nothing until done; none in the
  reduce. Logs: `<run>\run-20261122_191853.log` (PerFileScoring), `<run>\run.log` (FirstPassFDR);
  plots `ai/.tmp/sessions/20261122-perfile/perfviz/`.
- 2aa1af98a0: the thread fix. b8044e78a1: the stub drops sequence, modified_sequence,
  precursor_mz, protein_ids and file_name (the developer's call: the self-standing argument now
  belongs to `OSPREY_PER_FILE_FDR_KEEP_PARQUET`, the diagnostic/dev parquet). Stub readers take
  the peptide from the library (OSPREY_STUB_IDENTITY=1, the default; every FirstPassFDR reader
  passes it); a stub read without the library throws. 3-file check identical (200,832; 80,026),
  stub 201 MB vs 309 MB: per run 359 MB vs 2,184 MB = 6.1x.
- KEPT for now: apex_rt and coelution_sum. `ConsensusRts` (FirstPassFDR's planning) reads both
  (it skips `CoelutionSum <= 0`), so a missing column would silently empty the consensus.
- Path to the design's ~10x (~218 MB/run): (A) drop the two run q-values from the score sidecar,
  the reduce recomputes them anyway (~70 MB, 7.5x); (B) put the score in the stub parquet as a
  compressed column and stop writing the binary per-run sidecar (~110 MB, ~8.9x; also removes the
  duplicate apex_rt; changes the `.1st-pass.fdr_scores.bin` contract pass 2 and the relay lists
  name, so it goes with step 4); (C) float32 for start/end/apex RT, area, snr (~70 MB more, ~12x
  with B; changes values slightly - separate experiment). apex_rt and coelution_sum go once
  planning reads them from the score data (fits B).
- Follow-ups: training progress reporting (the gaps); stub columns the library or the score file
  already hold (sequence, modified_sequence, precursor_mz, protein_ids, apex_rt; coelution_sum
  once nothing dedups on it) - ~150 MB/run more; then step 4 (pass 2 on per-run models).

## Night session 2026-11-22/23 (log: `ai/.tmp/night-session-budget-20261122.md`)

- d01e193962: the stub carries each run's score and both run q-values (one scores file per run,
  264 MB vs 2,184 MB baseline); score-file readers fall back to the stub.
- 45620313a9: keep mode writes `<stem>.features.parquet` (full layout, feature key) beside the same
  stub; PerFileScoring re-trains from a current checkpoint when only model settings change; no
  `.bin` in the mode; `--task FirstPass` selector (PerFileScoring + FirstPassFDR). pwiz-ai 52e116a6:
  `Run-SeaAd/Tdp43/Chs -Task FirstPass -LinkFrom` links only calibration + features.
- Verified: 3-file keep run identical (200,832 / 80,026); `-Task FirstPass -LinkFrom` with
  OSPREY_GBT_MAX_ITERATIONS=5 re-trained all 3 runs from checkpoints, run-level sum 199,776 = the
  sweep's iterations<=5 point exactly, 318 s total.
- cfae6ffb76: docs (00 In flight 5 + contract rows, 14, 20, Osprey-workflow.html 2.1) via sub-agent.
- 93c9423e9e: /code-review medium (10 findings): fixed 7 - model key gains TrainSample + FDR
  feature-mask terms; a run under the mode that goes past the first pass is refused at
  PerFileScoring start (verified); stub fallback gated on the mode and fault-tolerant; uncalibrated
  run logged; doc comment. Dropped 3: stacked-arm protein-best, file arm without protein boost
  (study arms, HRAM default has it), duplicate run-q sort (~3 s/run).
- TeamCity Perf/Regression on pull/5070: build 4277220.
- 82-file perf run (`-Task FirstPass`, default stub mode, auto 3 files): `runs\seaad-82files-libdecoy-r1.0-default-m1final`.

- 22:27: the first 82-file `--task FirstPass` run was INVALID - FirstPass sets StopAfterStage5, which
  made PerFileScoring load the library without fragment peaks (meant for FirstPassFDR-only workers):
  0 calibration matches everywhere. Fixed 0eb27de6ea (omit only when PerFileScoring is not selected).
- TeamCity Perf/Regression build 4277220 on 93c9423e9e: PASSED (default mode unchanged).
- **82-file result** (`runs\seaad-82files-libdecoy-r1.0-default-m1final`, exe `_bin\perfile-m1-final2`
  = 0eb27de6ea, one `--task FirstPass` process, auto 3 files): 98,280 at true FDP 1% (A4 exactly),
  q 1% kept 97,433 (0.93%). PerFileScoring 14,541 s, FirstPassFDR 871 s, total 15,412 s vs master's
  first pass 14,992 s (+2.8%). Disk 20.8 GB vs ~179 GB (8.6x). Peak private 66.3 GB, floor falling
  (-347 MB/file). 9 log gaps >= 30 s (max 144 s), all training stalls early in PerFileScoring, plus
  one ~110 s at FirstPassFDR start. Plot `ai/.tmp/sessions/20261122-perfile/perfviz/m1final-firstpass.png`.
- PR #5070 title/body updated with these numbers; still draft (the developer marks it ready).

- Extra credit, direct mzML read under per-run models (stub parquet), 12 SEA-AD runs, auto 3 files, exe
  `_bin
awread-perfile` = local merge of #5067 + #5070 (`nightlywork/20261122_rawread_perfile` in pwiz-work1,
  not pushed): PerFileScoring cache hit 2,253 s; `--spectra-cache on` with no cache (write then read back)
  2,486 s (+10%); `--spectra-cache off` (read-ahead, no cache) 2,259 s (+0.3%). Results identical (85,620;
  run-level sum 743,831). Peak private ~86 GB for `off` vs ~65 GB for the cache hit (read-ahead holds
  spectra). Launcher `ai/.tmp/sessions/20261122-perfile/rawread/`, runs `runs\seaad-12files-*-rr-*`.
- Morning decisions (developer): pass 2 is solved in this PR (stacked branch merged into #5070), and the PR
  changes the default. Design agreed: per-run `<stem>.1st-pass.model.json` from PerFileScoring (model +
  standardizer + calibration map + protein-best floor, model key); the protein-best column as a stub column;
  the analysis-wide `<blib-stem>.1st-pass.model.json` goes away under the mode (pass 2 frozen scoring, the
  FirstPassFDR fast-resume gate and the model-diagnostics Model tab move to per-run models).

- **Developer decisions, 2026-11-23 morning:** per-run first-pass models become THE pipeline - the default,
  for HRAM and unit resolution alike, and the old mode (FirstPassFDR trains one global model from every
  run's full feature parquet) is RETIRED entirely: two workflows are too confusing for users and make the
  code harder to read and test. Stellar is tested through the regression data only. The regression results
  (goldens) are re-recorded. This is where C# Osprey leaves Rust osprey (maccoss/osprey) behind: the
  rearchitecture is not worth porting, so cross-impl parity ends here for the first pass. Why: ~85-90% less
  disk, the HPC map-reduce shape (training in the fan-out, a reduce join), more detections (98,280 vs
  97,120 at true FDP 1%), and DIA-NN's field-accepted per-run model. Pass 2 on per-run models is solved in
  this PR (a stacked branch merged into #5070 before master). `Osprey-workflow.html` is being redrawn as the
  design-review document for the new file contract.

- 2026-11-23: milestone A (pass 2 on per-run models) done on stacked local branch
  `Skyline/work/20261123_osprey_per_file_pass2` (30107eec3a code, 9c0908537e docs; NOT pushed): per-run
  `<stem>.1st-pass.model.json` (model + calibration map + protein-best floor), `protein_best` stub column,
  moved rows rescored with the run's frozen model, reconciled stub ~12 MB/run. SEA-AD 3-file through pass 2:
  first pass unchanged (200,832 / 80,026), pass 2 80,293 at true FDP 1% (p1 80,364), q 1% at FDP 0.92%.
  Developer decisions: unit resolution defaults to pass-2 `transfer`; protein-compact likely RETIRED entirely
  before #5070 merges (first merge without a Rust parity gate); DIA-NN TSVs stay undeclared derived reports
  (talk to Mike - originally for the old Carafe contract); rename `first_pass_score` -> `score`; pass-2 run q
  into the reconciled stub and retire `.2nd-pass.fdr_scores.bin`. Then milestone B (default + retire old mode +
  goldens). Developer's 5th reason (expected): PerFileRescoring faster from less parquet I/O.

- 2026-11-23 afternoon: milestones A2, B and the regression are done on the LOCAL branch
  `Skyline/work/20261123_osprey_per_file_pass2` (on top of #5070's d589a6b422; not pushed): da29b82f0d (transfer
  default everywhere, `score` column, pass-2 records in the reconciled stub, no `.2nd-pass.fdr_scores.bin`),
  9a03ee4995 (per-run models are THE pipeline; old mode, model/stacked arms and OSPREY_PER_FILE_FDR retired;
  `--keep-scores-parquet`; calibration fallback anchoring 0 at the best decoy when no target passes q 1% - the
  subset runs failed on the run-q floor 1/(targets above the first decoy), not on weak models;
  OSPREY_FIRST_PASS_TRAIN_SIZE/_ROUND2_SIZE), 8df306114a (FirstPassFDR declares each run's model as an input -
  HPC staging bug only regression mode 3 caught), e401430a7a docs, 911a12aa4e regression harness (reads stubs via
  FdrScoresSidecar.ReadRecords), d9e80fde4f re-recorded goldens. Gate 672/672, 0 warnings; regression-parallel
  -Dataset All 47 PASS / 0 FAIL / 2 SKIP. Goldens: Astral up both passes; Stellar pass 1 up, pass 2 down 7-12% with
  entrapment FDP 0.09/0.26% -> 0.76/1.34% (losing protein-compact, the old unit default). Developer wants Stellar on
  the HRAM recipe (gbdt + protein-best), maybe a DIA-NN side-by-side on the regression Stellar data; a measurement
  is running (`ai/.tmp/agent-stellar-recipe-status.md`).

**Next session handoff**: For detailed startup protocol, read `ai/.tmp/handoff-20261123b_osprey_per_file_fdr.md` before starting work.

## Session 2026-11-23 (afternoon/evening): verifier, Stellar defaults, DIA-NN, #4997

- **Transfer verifier** (8c0c60a115, cfa4055b78): OSPREY_PASS2_VERIFY_WORKER now works under the q-value transfer.
  SecondPassFDR re-scores each run's rescored rows from `<stem>.features-reconciled.parquet` with the run model,
  checks unmoved rows against the first-pass stub, re-runs the transfer and asserts score + run q bit-equal to the
  reconciled stub. Needs `--keep-scores-parquet` (refused without). regression.ps1 straight legs add the flag;
  the verifier-split SKIP is now PASS on Astral and StellarLibDecoy: regression 49 PASS / 0 FAIL / 0 SKIP.
  Known gap: a row re-scored at exactly its first-pass peak is indistinguishable from an unmoved row in the files,
  so either score is accepted for it (5 of ~5,000 re-scored rows on StellarLibDecoy).
- **Stellar recipe** (`ai/.tmp/agent-stellar-recipe-status.md`, runs `D:\test\osprey-runs\stellar-recipe`):
  arms A current / B gbdt / C +protein-best / D +HRAM scoring settings / E D+default features / F C+default
  features / G gbdt+default features. Pass 2 LibDecoy / GenDecoyEntrap: A 27,171 (0.76%) / 28,782 (1.34%);
  G 36,654 (0.76%) / 38,327 (1.41%); F 40,340 (0.15%) / 41,441 (0.36%); D and E lose (HRAM scoring settings
  hurt Stellar). Standard entrapment understates FDP under protein boosting (developer), so compare A/B/G and
  C/D/E/F within groups. Developer chose F: **3bbdeba334** unit resolution = gbdt + protein-best + `default`
  feature set, legacy scoring settings.
- **DIA-NN 2.7.0 on the regression Stellar library** (`D:\test\osprey-runs\diann-regression-stellar\analysis\summary.md`):
  GenDecoyEntrap pass 1 at combined FDP 1%: DIA-NN 37,246 (accessions without `_pep` suffix), Osprey A 27,916,
  G 36,991, F 45,533. G (no boost) closes the gap; DIA-NN also responds to protein grouping (+2,137 from
  stripping the per-peptide suffix). 14.6 min at 16 threads.
- **Tests off compact** (4b3eadc0a8): tests needing "not best" use `off`; LEGACY boost is `off`.
  `--protein-boost compact` already behaves exactly as `off`. Inventory below.
- **#4997** (Mike, MS2 m/z calibration): master merged in `C:\proj\pwiz-4997` (396df37223), gate 675/675. Two
  judgment calls to review: TestProteinBestPipeline's pre-column digest and TestSubsetLibraryDecoysAndReports
  run under OSPREY_MS2_CAL_MEAN=1 (curve changes them). Merge order agreed: #4997 first, then #5070 merges master.
- Open product question: with zero decoy protein winners (tiny Stellar subset under the new defaults)
  PepEstimator.Fit falls back to PEP 1.0 for every group alongside q = 0.
- Night session log: `ai/.tmp/night-session-budget-20261123.md`.

## Night session 2026-11-23/24 (log: `ai/.tmp/night-session-budget-20261123.md`)

- **#5070 pushed** at 802261ce91 (d589a6b422.. : pass 2 on per-run models, transfer verifier, unit defaults
  gbdt + protein-best + default features, tests off compact, Stellar goldens, out-of-process stub reader).
  Title/body updated (draft from `ai/.tmp/sessions/20261123-night/pr5070-body.md`). Still a draft PR.
- **TeamCity Perf/Regression pull/5070 build 4278781: SUCCESS.** The first attempt (4278646) failed before any
  Osprey leg: `Regression/FdrSidecars.ps1` Add-Typed against net10 Osprey.IO and the agent's pwsh runs .NET 9
  (CS1705); local pwsh 7.6/.NET 10 hid it. Fixed by 802261ce91 (`Regression/OspreyStubReader`, a net10 console
  tool in Osprey.sln; byte-identical to the old reader on 48 stubs / 96 sidecars / 7 comparer pairs).
- Local regression-parallel on the Stellar-defaults goldens: 49 PASS / 0 FAIL / 0 SKIP.
- **SEA-AD 82 full pipeline** (`D:\test\osprey-runs\sea-ad\runs\seaad-82files-libdecoy-r1.0-defaultfullperrun`,
  snapshot `_bin\pr5070-a44bb448df`), vs master 4cc5a55baf pfauto (`ai/.tmp/sessions/20261117-5ada8293/pfauto-console.log`):
  total 5:02:57 vs 5:11:52 (-2.9%); PerFileScoring 14,774 vs 10,656 s; FirstPassFDR 878 vs 4,337 s;
  PerFileRescoring 2,141 vs 3,482 s; SecondPassFDR 383 vs 237 s; disk 24.9 vs 183 GB (-86%); peak private
  66.4 vs 51.5 GB; true FDP 1% pass 2 98,244 vs 97,120 (pass 1 98,280, identical to m1final). Plots and text:
  `ai/.tmp/sessions/20261123-night/seaad/` (pr5070.png, master.png, perfviz*.txt, split_calibration.txt).
  Observation: PerFileScoring's first hour shows 5 log gaps of 121-178 s - each wave of 3 runs trains silently;
  a training progress line would remove them (not changed: rising triage bar).
- **#4997** (Mike): master merged + Stellar goldens re-recorded, pushed (19520569b7..55860fd6b6). Local
  regression 48 PASS / 0 FAIL / 1 SKIP (Astral verifier split, master's own; #5070 fixes it). TeamCity 4278657:
  regression 48/0/1, build FAILED only on "Number of tests 0 is 118 less than 118 in build #374" - a per-branch
  test-count anchor from #4997's only earlier build on that config; #5070 passes the same condition. Needs a
  TeamCity config look or a reason to dismiss. Real-data check (`D:\test\osprey-runs\pr4997-2th\analysis\summary.md`,
  Panorama 2Th TR01-03, regression LibDecoy entrapment library, master+#4997 at old unit defaults): profile pass-1
  @FDP 1% curve 30,745 vs mean 12,262 (2.5x); centroid curve 33,174 vs mean 33,768 (-1.8%). PR description is
  stale (still says small offsets keep the mean; 19520569b7 applies the curve at any offset): proposed
  corrections in `ai/.tmp/sessions/20261123-night/pr4997-description-corrections.md`.
- **Prepared #5070 + #4997** on local branch `nightlywork/5070-with-4997` (beefe59b24 merge, 654c177acd goldens;
  not pushed): conflicts only in SubsetPipelineTest(.ProteinBest).cs; #4997's TestProteinBestPipeline pin dropped
  with #5070's deletion of that check; TestSubsetLibraryDecoysAndReports keeps only #5070's core-set pin (passes
  under the curve). Gate 675/675; regression-parallel 49 PASS / 0 FAIL / 0 SKIP. Stellar goldens 43,302 -> 43,596,
  40,491 -> 40,951, 41,612 -> 41,471. Arms with #4997: F LibDecoy 40,823/40,846 (0.17%), GenDecoyEntrap
  41,363/41,303 (0.29%); A 27,222/27,259 (0.83%), 28,666/28,744 (1.32%). After #4997 squash-merges: merge master
  into #5070 the same way (the squash has the same content as 55860fd6b6), re-record goldens, TeamCity.

## Session 2026-11-24 (day): stacked on #4997, Linux tests, per-run safeguard

- **#5070 stacked on #4997**: PR base is now `Skyline/work/20261104_osprey_ms2_mz_calibration`; GitHub retargets to master
  when #4997 merges. #5070 head 01ca9eb887 (merge 74cbb39c56 of #4997 c3f08653fb + 28cb46209f safeguard + 01ca9eb887
  tests). TeamCity Perf/Regression pull/5070 build 4279506 queued.
- **#4997 Linux failures** (TestSubsetLibraryBuildTuned x4 on TeamCity Linux, Windows passed): not a Linux bug. Test
  fine-tune at LR 1e-3/no warmup amplified CPU-dispatch noise in Torch (iRT 7.253730122 TeamCity vs 7.253730010 WSL)
  onto the run-q 1% cliff. Fixed on #4997: a1a8f15e7d (production LR), c3f08653fb (Osprey.Test TorchTestSettings: 1
  thread, ATen/MKL_CBWR/oneDNN pinned to AVX2 via libc/CRT env before libtorch loads; bit-identical per OS across
  CPUs and hostile envs; Windows vs Linux still differ - separate libtorch builds). Evidence
  `ai/.tmp/sessions/20261124-pr4997linux/`, `ai/.tmp/sessions/20261124-pr4997det/`.
- **Per-run models on tiny runs are worse** (`D:\test\ms2range-scratch\summary-pooled.txt`, summary-fallback.txt):
  shifted 3-run Stellar subset (~110-150 detectable precursors/run), runs zeroed at run q 1% ((D+1)/T floor needs ~100
  targets above the first decoy): pooled SVM/core 2/120; per-run SVM/core 19/120; per-run gbdt/best/default 20/120;
  pooled gbdt/best/default 13/120 plus 8/45 whole experiments with no blib. Unshifted never zeroes under per-run.
  MS2 calibration always recovers the shift (max error 0.077 Th).
- **Safeguard 28cb46209f** (Percolator-style): per run, keep the out-of-fold model unless its best single FDR feature
  passes strictly more targets at run q 1%; the choice is saved in `<stem>.1st-pass.model.json` (FallbackFeature) and
  used by RunModelScorer in pass 2; key term `;runsafeguard=1`. Result: 20 -> 14/120 (default), 19 -> 8/120 (svm/core);
  StellarLibDecoy regression unchanged, no regression run falls back (model ~35k vs best feature ~12k).
- **Tests 01ca9eb887**: shifted-subset MS2 tests assert calibration first; count check is a 0.5x sanity floor
  (subset tests are for coverage; modeling quality is regression.ps1's job, per the developer).
- **Follow-up (open): the tiny-run floor.** Remaining zeroes are runs where the model AND every single feature pass 0;
  pooled SVM passes ~130 there. Needs strength from other runs: e.g. a pooled model trained in FirstPassFDR used only
  for runs whose own model and features all fail, or a prior/reference model. Measure on the same grid and on real
  small runs (QC, blanks, short gradients) against DIA-NN.
- **Follow-up (open): `.spectra.bin` cost.** Experiments: (1) assemble the scan set PerFileRescoring needs
  (moved + gap-fill rows: SEA-AD 2.01M of 24.7M survivors, ~24.5k/run) and read only those, sequentially as Skyline
  does - for HPC (raw on the rescoring node, no cache shipping) and local runs; (2) make the cache write cheaper
  (async/compressed) so writing it is closer to free than the measured +10%.
- Open on #4997: TeamCity Perf/Regression build 4278657 failed only the per-branch test-count anchor (#374 had 118
  tests); PR description corrections in `ai/.tmp/sessions/20261123-night/pr4997-description-corrections.md`.

## 2026-11-24 (afternoon): #4997 merged, sequential 64 GB run

- #4997 merged as 62b9748240; #5070 retargeted to master and merged origin/master (4f0f54acbc; Osprey tree
  unchanged by the merge, verified). Gate 681/681; GitHub checks 16/16 incl. Linux.
- **SEA-AD 82 sequential on BRENDANX-UW25 (i9-14900, 32 threads, 64 GB), developer-run:** 7:38, 4% longer than master; peak memory
  36.7 GB vs master 33.1 GB. PerFileScoring's level does not grow with file count: expected to scale to the
  446-run CHS cohort. Recorded in the PR description. Full report (UW25 session, 2026-11-24):
  - Setup: #5070 at 654c177acd (before the master merge) vs master c6f235a7c5, same day/box/settings: 82 mzML +
    `.spectra.bin` caches on D: (HDD), `target+decoy+entrapment-20260817` (shuffle entrapment), libdecoy r1.0,
    `--threads 30`, NO `--parallel-files`, `--model-diagnostics --fdrbench-pass both --perf-stats`, OS file cache
    cleared before each. `Run-SeaAd.ps1` (`-Tag -pr5070` for the PR arm).
  - Runs: `D:\test\osprey-runs\sea-ad\runs\seaad-82files-libdecoy-r1.0-default{,-pr5070}` on UW25 (`run.log`,
    `perfviz.png`, `out.model-diagnostics.html`).

    | phase | master | #5070 | change |
    |---|---|---|---|
    | PerFileScoring | 16,817 s (4:40:17) | 22,982 s (6:23:02) | +36.7% |
    | FirstPassFDR | 4,549 s (2 lanes) | 861 s (3 lanes) | -81% |
    | PerFileRescoring | 4,679 s | 3,022 s | -35% |
    | SecondPassFDR | 373 s | 643 s | +72% (blib 206 s) |
    | total | 7:20:18 | 7:38 | +4% |
    | private peak (phase) | 33.1 GB (FirstPassFDR) | 36.7 GB (PerFileScoring) | +3.6 GB |
    | disk written | +184.6 GB | +25.0 GB | -86% |
    | precursors / peptides / protein groups | 101,418 / 90,123 / 6,739 | 102,676 / 91,338 / 6,753 | +1.2 / +1.3 / +0.2% |

  - Per file: scoring +65-70 s, almost all the run's own model (`First-pass per-file model ... 80.9s wall at 30
    thread(s); 4,403,242 rows`, 89.5 s with the stub). Sequentially the training is not overlapped, so the
    scoring cost (+1:43) is only ~85% won back by FirstPassFDR and rescoring (-1:30); UW8's -2.9% total came
    from 3 lanes overlapping it.
  - Memory per phase (private peak): scoring 36.7, FirstPassFDR 27.4, rescoring 18.6, SecondPassFDR 13.3 GB.
    PerFileScoring floor LEVEL (18.4 -> 18.0 GB over files 1-47, -5 MB/file); master's floor falls too. So
    PerFileScoring is now the memory-critical section, with ~27 GB headroom on 64 GB sequential. FirstPassFDR
    dropped to a reduce (6.0 GB managed p10). Disk climbs linearly ~0.25 GB/file in scoring (21.7 GB at its end).
  - Log: 5 gaps >= 30 s over the whole run (max 36 s, library load) vs master's 55 (per-file
    "Scoring isolation windows").
  - FDP (`tools/pass1_fdp.py`, both runs' model-diagnostics):

    | view | master | #5070 |
    |---|---|---|
    | experiment pass 1 at 1% q: n / true FDP | 101,220 / 0.063% | 102,494 / 0.080% |
    | experiment pass 1, count at true FDP 1% | 120,689 | 121,378 (+0.6%) |
    | experiment pass 2, count at true FDP 1% | 121,820 | 123,596 (+1.5%) |
    | run pass 1 / pass 2 true FDP at 1% q | 3.93% / 3.44% | 3.46% / 3.02% |

    The gain holds at matched true FDP; experiment-level q stays very conservative in both; run-level q is
    better calibrated but still over-reports (partly the shuffle entrapment, known ~1.6x FDP over-estimate).
  - Confounds: FirstPassFDR lane count differed (2 vs 3, more free RAM on the PR run) - small against -81%.
    SecondPassFDR's +4:30 was not investigated.
- Ready for /pw-complete once TeamCity Perf/Regression 4279506 (01ca9eb887, same Osprey tree) passes.

## Progress Log

### 2026-11-24 - Merged

PR #5070 merged as commit aa864c3d2e. Shipped: per-run first-pass models trained in PerFileScoring
(two-round gbdt with protein-best, out of fold, calibrated per run, Percolator-style best-feature
safeguard), FirstPassFDR as a reduce, the q-value transfer as the only pass-2 path with the transfer
verifier, stub scores parquets in place of the full parquets and .fdr_scores.bin sidecars
(`--keep-scores-parquet` for the features checkpoint, `--task FirstPass` for iteration), unit-resolution
defaults gbdt + protein-best + default feature set, the out-of-process regression stub reader, and
re-recorded goldens (merged on top of #4997's MS2 offset curve). SEA-AD 82 files (3 at a time):
98,244 vs 97,120 at true FDP 1%, 5:02:57 vs 5:11:52, 24.9 vs 183 GB; sequential on a 64 GB i9 (UW25):
7:38 (+4%), 36.7 vs 33.1 GB peak. TeamCity Perf/Regression 4279506 and all 16 GitHub checks passed.
Deferred to follow-ups (sections above): retiring protein-compact (inventory below), the tiny-run floor
of per-run models (pooled/prior model for runs whose model and every feature fail), the PerFileRescoring
scan-set read and cheaper .spectra.bin writes, a training progress line in PerFileScoring, the per-run
Model tab drop-down in model diagnostics (Mike), and PepEstimator's PEP 1.0 fallback with zero decoy
protein winners.

### 2026-11-24 (night) - MACS2 A/B after merge: 14.9% slower, scoring +42%

Master aa864c3d2e (`_bin\master-aa864c3d2e`) on MACS2 with the 11/20 cache arm's recipe (72 threads, scoring 4 /
rescoring 8 files at once, split-sized library, no model diagnostics, OS file cache cleared first). One deviation:
the caches were read from a D: copy (`D:\...\sea-ad\raw`), while the 11/20 arm read them in place from E:. The
10/06 sweep had D: no slower than E: (318 vs 343 s on 8 files), so this favours the new run if anything. Box quiet
(other users under 1 core; `ai/.tmp/sessions/20261121-tdp43/seaad-master-aa864c3d2e-load.log`). Run dir
`D:\Users\brendanx\test\osprey-runs\sea-ad\runs\seaad-82files-libdecoy-r1.0-defaultmaster-aa864c3d2e` (`run.log`).

| Stage | 11/20 cache arm | aa864c3d2e | Change |
|---|---|---|---|
| PerFileScoring | 7,735 s / 66.4 GB | 10,983 s / 116.7 GB | +3,248 s (+42%) |
| FirstPassFDR | 1,574 s | 435 s / 51.5 GB | -1,139 s |
| PerFileRescoring | 1,373 s / 24.7 GB | 777 s / 23.8 GB | -596 s |
| SecondPassFDR | 128 s | 228 s / 21.3 GB | +100 s |
| Total | 10,811 s (3:00:11) | 12,423 s (3:27:03) | +1,612 s (+14.9%) |

- Results match the PR's A4 exactly: 97,748 at experiment q 1% (was 97,191), 97,691 library spectra, 6,774 protein
  groups. `split_calibration.py`: pass 1 98,280 at true FDP 1% (A0 97,120, +1.2%), q 1% kept 97,433 at FDP 0.93%.
- Disk 24.9 GB written (about 183 GB before). Peak private memory 116.7 GB in PerFileScoring, up from 66.4 GB.
- Moving training into PerFileScoring cost 3,248 s there and saved 1,139 s in FirstPassFDR; rescoring from the
  stubs saved 596 s. On MACS2 the net is +27 min, against the PR's -9 min (5:02:57 vs 5:11:52) at 3 lanes / 30
  threads on the 128 GB i9 (UW8). Not yet explained: why per-run training costs 4 lanes x 72 threads this much more.

### 2026-11-25 (night) - Same-setup A/B on MACS2: +24.5% total, all of it per-run training

The table above compares a D:-cache run against an E:-cache baseline. Re-run with both arms identical: caches read
in place from E:, outputs on D:, 72 threads, scoring 4 / rescoring 8, split-sized library, no model diagnostics,
standby cache cleared first, other users under 0.5 core (`seaad-*-E-load.log`). Pre = c21d734ce7 (#5070's parent,
`_bin\pre5070-c21d734ce7`), head = aa864c3d2e. Run dirs `D:\Users\brendanx\test\osprey-runs\sea-ad\runs\
seaad-82files-libdecoy-r1.0-default{pre5070-c21d734ce7-E,head-aa864c3d2e-E}`; chain
`ai/.tmp/sessions/20261121-tdp43/Start-SeaAdAB-E.ps1`; timeline `ai/.tmp/night-session-budget-20261124.md`.

| Stage | pre (c21d734ce7) | head (aa864c3d2e) | Change |
|---|---|---|---|
| PerFileScoring | 7,679 s / 65.7 GB | 11,621 s | +3,942 s (+51%) |
| FirstPassFDR | 1,558 s / 66.2 GB | 444 s | -1,114 s |
| PerFileRescoring | 1,327 s / 28.2 GB | 1,018 s | -309 s |
| SecondPassFDR | 132 s | 235 s | +103 s |
| Total | 10,695 s (2:58:16) | 13,318 s (3:42) | +2,623 s (+24.5%) |

- Pre reproduces 11/20 (7,735 s scoring, 10,811 s total, 97,122 library spectra - identical count). Head reproduces
  the D: run's results (97,691 library spectra, 6,774 protein groups).
- Per file (`scoring_breakdown.py`): coelution 279.4 vs 278.9 s, RT calibration 50.3 vs 51.4 s - unchanged. The
  per-run model + stub is 192.3 s/file (train 143.5, out-of-fold scoring 27.9); 192.3 x 82 / 4 lanes = 3,942 s,
  the whole scoring delta. Fold utilisation 82%, 1-15 Percolator iterations per fold (mean 5.9), each a fresh
  200-tree GBDT, over two rounds (300k then 200k rows): roughly 7,000 trees per file.
- E: vs D: is a separate ~640 s of scoring wall, in both builds: head on D: had RT calibration 32.9 s/file and
  coelution 269.1 s/file. So the earlier +3,248 s understated the training cost and the 14.9% understated the total.
- Why the 30-thread run trained only 1.19x slower per file at 1.8x fewer threads: MACS2 is 2 x Xeon Gold 6354,
  **36 physical cores**, 72 logical. 30 -> 72 threads is 30 -> 36 cores plus hyperthreads, about 1.2x of compute.
  It is not a GBDT scaling defect. A synthetic benchmark (200k x 70, 100 trees, idle box; temporary
  `Osprey.Test/GbtScalingBench.cs`, output `ai/.tmp/sessions/20261121-tdp43/gbt-bench.txt`) shows:
  - one model: 16.0 s at 1 thread, 4.37 s at 6, 2.91 s at 18 (5.5x; ~13% serial fraction, Amdahl ceiling ~7.5x);
  - 12 models concurrently (4 lanes x 3 folds): 8.30 s at 3 threads per fold (36 threads) and 8.31 s at 6 (72);
    8 lanes x 3 folds x 3 = 2.03 s per lane, 9 x 3 x 2 = 2.26 s. Throughput saturates at the 36 cores whatever
    the lane/thread split, so more lanes cannot hide the training: it is ~1,700 core-s of added work per file.
- Levers are therefore the amount of work, not threading: fewer Percolator iterations (early stop), fewer trees or
  rows per model, or one round instead of two. Each moves results and needs an 82-file run with FDP checks.
- **Correction to the E: vs D: bullet above:** probably warm vs cold cache, not the drives. The D: run started with
  a partial standby clear (72.9 GB left cached vs ~0 in the E: arms), its library parse took 27 s against 121-124 s
  cold, and its per-file RT calibration was bimodal (first 4 files 87-103 s, then 20-30 s). Calibration pass 1 is
  the first serial read of each 4.5 GB cache. Unconfirmed; a cold single-file run from each drive would settle it.
- **Auto lanes beat the hand-tuned 4 x 18.** Head, bare `--parallel-files`, 72 threads, same E: setup
  (`D:\Users\brendanx\test\osprey-runs\sea-ad\runs\seaad-82files-libdecoy-r1.0-defaulthead-aa864c3d2e-auto-E`):
  auto chose 9 lanes x 8 threads (RAM allowed 20, capped by the 8-threads-per-file minimum) and 8 FDR lanes.

  | stage | pre 4 x 18 | head 4 x 18 | head auto 9 x 8 |
  |---|---|---|---|
  | PerFileScoring | 7,679 | 11,621 | 10,341 |
  | FirstPassFDR | 1,558 | 444 | 483 |
  | PerFileRescoring | 1,327 | 1,018 | 804 |
  | SecondPassFDR | 132 | 235 | 219 |
  | total | 2:58 | 3:42 | **3:17** (+10.8% over pre) |

  Scoring wall per file (per-file seconds / lanes), 4 x 18 vs 9 x 8: coelution 69.8 vs 67.7 s (a wash), model +
  stub 48.1 vs 40.5 s, RT calibration 12.6 vs 6.5 s. So the synthetic benchmark's "lanes cannot hide training" holds
  only for pure GBDT: in the pipeline 9 lanes train 16% better and overlap the serial cache reads of calibration.
  97,691 library spectra, 6,774 protein groups (pre: 97,122 / 6,727). Other users' load < 0.5 core.
  The `MIN_THREADS_PER_FILE` = 8 rule (tuned before #5070) still picks the better configuration on MACS2.

## protein-compact retirement inventory

Prepared 2026-11-23 on `Skyline/work/20261123_osprey_per_file_pass2` after 3bbdeba334 plus the
"off where only not-best is needed" commit 4b3eadc0a8. Line numbers are at that commit. Scope:
`--protein-boost compact` AND `OSPREY_PASS2_QVALUE=protein-compact`, and everything that exists
only to serve them.

**Two facts that make this PR mostly deletion:**

1. **`--protein-boost compact` is already the same as `off`.** `OspreyConfig.Pass2QValue` is
   `Pass2QValueOverride ?? TRANSFER` (OspreyConfig.cs:260) - no boost selects protein-compact any
   more - and every key/behavior reads only `ProteinBest` (`== best`). The one place the enum
   NAME shows is the `Search settings:` log line (OspreyEnvironment.DescribeSearchSettings:801).
   The `_protein_boost` help text ("{1} competes the precursors ... in the second pass") is
   therefore stale today, not just retiring. The prep commit moved `ResolutionDefaults.LEGACY`
   and the `OspreyConfig.ProteinBoost` initializer to `off`, and the three refusal messages that
   advised `compact` to `off`, so after it nothing but the enum member, its help text and its
   parse test name `compact`.
2. **`OSPREY_PASS2_QVALUE=protein-compact` cannot complete a run.** Per-run first-pass models
   refuse it: `PerFileScoringTask.Run` (336-344) before any scoring whenever PerFileRescoring is in
   the pipeline, and `PerFileRescoreTask.CreatePass2Worker` (1282-1285). The only live code it
   still reaches is FirstPassFDR's stratum build/write/compaction-gate clause under a
   `--task FirstPassFDR` run, and SecondPassFDR's join is unreachable (`HasWorkerStamp` needs a
   current-version `.2nd-pass.fdr_decoys.bin` nothing can write). So the stratified competition,
   the competition decoys file and the stratum are dead in production; removing them cannot move
   a transfer run's output EXCEPT through validity-key strings (below).

**Validity-key traps (the critical ones - get these wrong and every cached cohort recomputes):**

- `OspreyEnvironment.Pass2QValueValidityKeySuffix` (1716-1728) emits `;pass2=transfer` into
  FirstPassFDR (FirstPassFdrTask.cs:539), PerFileRescoring (PerFileRescoreTask.cs:345) and
  SecondPassFDR (SecondPassFdrTask.cs:312). KEEP the literal `;pass2=transfer` in all three (a
  constant), even if `OSPREY_PASS2_QVALUE` and `Pass2QValue` are deleted. TaskValidityKeyTest
  719 and 1072-1101 pin it.
- `TransferReconciliationValidityKeySuffix` (1741-1748) is empty unless `Pass2TransferQ`. After
  retirement `Pass2TransferQ` is always true: make it unconditional, same string
  (`;reconset=output@{FdrLevel},{ExperimentFdr:R};recondecoys=0;pepfloor=reported`).
- `Pass2StrataValidityKeySuffix` / `PASS2_STRATA_TERM` (1525-1526, 1793-1805; used at
  PerFileRescoreTask.cs:348, SecondPassFdrTask.cs:315): empty under transfer, so DELETE with no
  key change. TaskValidityKeyTest 1134-1180 (strata assertions) go with it.
- `ProteinBestValidityKeySuffix` / `GbdtValidityKeySuffix` read only `ProteinBest`; removing the
  enum member moves nothing. Do NOT change enum member ORDER for any other reason (nothing
  serializes the int today, but `Enum.GetNames` order is the help text order).
- `Stage6Planner` (160,182), `RunReconciliationPlanner` (89), `PerFileRescoreTask` (1984),
  `Pass2FdrSidecar` (101) branch on `Pass2TransferQ`: keep the transfer arm, delete the else.
  None of these keys.

| Where | What | Action | Trap / dependency |
|---|---|---|---|
| Osprey.Core/OspreyConfig.cs 800-808 | `ProteinBoost.compact` member | delete | `--protein-boost compact` then fails `Enum.Parse`. Check what `OspreyArgument` does with a value outside `Values`: if it WARNS and keeps the default (other args do - OspreyCommandArgsTests ~208 "warn -> default unchanged"), a saved `--protein-boost compact` silently becomes `best` (the resolution default) where it meant `off`. Prefer a startup refusal naming `off`. |
| Osprey.Core/OspreyConfig.cs 254-268 | `Pass2QValue`, `Pass2TransferQ`, `Pass2ProteinCompact` | delete `Pass2ProteinCompact`; `Pass2TransferQ` -> remove (always true) or keep as `true` for one PR | 20+ call sites; see key traps |
| Osprey.Core/ResolutionDefaults.cs 37-39 | LEGACY boost | already `off` (prep commit) | none |
| Osprey.Core/OspreyEnvironment.cs 1356-1372 | `ValidatePass2WithProteinBest` (best + protein-compact refusal) | delete; and its caller (grep) | SubsetPipelineTest.ProteinBest.cs 169-177 leg goes |
| Osprey.Core/OspreyEnvironment.cs 1506-1600 | `PASS2_QVALUE_TRANSFER/PROTEIN_COMPACT`, `ENV_PASS2_QVALUE`, `Pass2QValueOverride/Setting/Unrecognized`, `NormalizePass2QValue`, `IsUnrecognizedPass2QValue` (1855-1876) | decide: (a) delete the variable entirely, or (b) keep it accepting only `transfer`. (a) is cleaner, and an old script's `OSPREY_PASS2_QVALUE=...` should then be REFUSED as an unknown OSPREY_* variable, as the retired `OSPREY_PROTEIN_BEST` is (SubsetPipelineTest.ProteinBest.cs ~315 `RETIRED_PROTEIN_BEST` leg) - verify with the same kind of leg | doc comment 1545-1546 is already stale ("follows --protein-boost: protein-compact under compact"). `DescribeSearchSettings` lists `ENV_PASS2_QVALUE` (787). Program.cs 648-657 unrecognized-value refusal names protein-compact. `[PATH] pass2-qvalue transfer` (Pass2FdrSidecar.cs:110, LogTag.ROUTE_PASS2_QVALUE) is asserted by SubsetPipelineTest.cs:1539 - keep the line or change the test |
| Osprey.Core/OspreyEnvironment.cs 1601-1644 | `OSPREY_PASS2_VERIFY_WORKER` | keep (transfer uses it: `VerifyTransferFile`); delete the protein-compact paragraphs ("What it is and is not" describes `CompeteOneFile`) | Program.cs 1480 `VerifyWorkerError`: drop the `config.Pass2ProteinCompact ||` clause |
| Osprey/OspreyCommandArgs.cs 455-476; OspreyCommandArgUsage.resx 196-198 `_protein_boost` | arg, DescriptionArgs {best, compact, off, hram, unit} | drop `compact`; RENUMBER the resx placeholders ({0} best, {1} off, {2} hram, {3} unit) and `DescriptionArgs` together | ja/zh-Hans resx have no `_protein_boost` (en fallback), so only en changes. `OspreyCommandArgsTests` help test is self-updating: it REWRITES Documentation/Help/{en,ja,zh-Hans}/CommandLine.html (line 148) on first run - commit the three regenerated files |
| Osprey.Tasks/PerFileScoringTask.cs 336-344; PerFileRescoreTask.cs 1280-1304 `OwnModelsProteinCompactMessage` + resx `PerFileRescoreTask_OwnModelsProteinCompactMessage_...` (resx 1355; ja/zh) | per-run-model refusals | delete | SubsetPipelineTest.cs 1237-1247 leg (now boost-independent; delete whole). `ProteinBestMismatchMessage` (1306-1320) already names `off` only |
| Osprey.Tasks/FirstPassFdrTask.cs 151, 164-168, 263-270, 1446-1530, 1771-1783, 1985-1993, 2023, 2057-2063, 2145, 2473+2550-2555 | `ProteinCompactStratum` publish, `_proteinCompactStratum`, stratum Output, `BuildProteinCompactStratum`/`BuildAndPublishProteinCompactStratum`, resume reload, gate clause `stratum.Contains` | delete; `ComputeFirstPassBaseIds` loses its `stratum` param | FirstPassFDR key comment 519-523 (stratum reason for `;pass2=`) - rewrite, KEEP the term. Gate clause is `stratum != null && ...` so transfer survivors are unchanged. 3 resx strings `FirstPassFdrTask_Build*ProteinCompactStratum_*` + Designer + ja/zh |
| Osprey.Tasks/FirstPassModelIO.cs 42, 60-80 (`EXT_STRATUM`), 151-176 (`StratumDto`, `Sidecar.StratumBaseIds`), 194-200 (`StratumPathFor`), 251-275 (`LoadForAnalysis` pairing), 362-400 (`SaveStratum`), 420, 484-505 (`LoadStratum`) | `.1st-pass.stratum.json` | delete | FirstPassModelIoTest 164-200, 471-620 (`CompactionGateRefusals` stratum legs ~591-623), 752-800, `AssertLoadsWithoutStratum` 893 - trim, not delete (model I/O stays). Leftover `.1st-pass.stratum.json` files in old output dirs become inert junk (not a declared Output any more) - fine |
| Osprey.Tasks/PipelineByproducts.cs 230-243 | `ProteinCompactStratum` byproduct | delete | FirstPassFdrTask.Publishes list (151); ByproductContextTest unaffected |
| Osprey.Tasks/Pass2FdrSidecar.cs 127-132 (mode switch), 150-195 (`RequireWorkerAnswers` decoys clause), 212-219 (stratum reload in `EnsureFrozenFirstPassPublished`), 484-499 (`HasWorkerStamp` decoys clause), 600-650 `ReadWorkerContribution`, 728-~800 `Pass1ScalarSeeder` and 2176-2290 `ReadOneFilePass2Inputs` (only caller outside the competition is Pass2PerFileWorker.CompeteAndStamp 231 - compact-only; `LogSeedSummary` at worker 606 goes too), 1109-1140 `ComputePass2FrozenCompetition`, 1173-~1570 `ComputePass2TransferCompeteFull`, 2292-2320 `FileCompetitionFromRecords` | the frozen stratified competition | delete the competition; KEEP `ComputePass2TransferFold`, `WalkSurvivors`, `FoldAndPublishExperimentScope` and `Pass2ExperimentScope` (1084; transfer publishes it too, SecondPassFDR declares the experiment sidecar unconditionally, SecondPassFdrTask.cs 255-265) | RESOURCE NAMES LIE: `Pass2FdrSidecar_ComputePass2TransferCompeteFull_Collecting_...`, `..._Writing_experiment_level_q_values_...`, `..._Raised__0__of__1__...`, `..._Second_pass_experiment_level_q_values_could_not_be_written_...` are used by the TRANSFER path (`WalkSurvivors` 1907-1908, `FoldAndPublishExperimentScope` 1961-1962/2000/2015). Deleting "everything named TransferCompeteFull" breaks the build or, worse, translations. Keep them (renaming = resx x3 + Designer churn; optional) |
| Osprey.Tasks/Pass2PerFileWorker.cs 60-66 doc, 73 `_stratumBaseIds`, 154-196 ctor (`scorer`, `transfer`, `stratumBaseIds` params), 198-218 `ComputeStampAndWrite` competition branch, 220-~300 `CompeteAndStamp` | per-file competition half | collapse to transfer only: ctor loses `transfer`/`stratumBaseIds` (and `scorer` if transfer never scores - PerFileRescoreTask.cs:1290 passes `null`), `writeAnswer`'s bestDecoy arg goes | `Pass2FileResult.Competition` |
| Osprey.IO/Pass2CompetitionDecoys.cs (whole), ArtifactValidity.cs 63-64 | `.2nd-pass.fdr_decoys.bin` | delete | IOTest.TestPass2CompetitionDecoysArtifact (4032) delete; IOTest.TestArtifactStampEmbedding ~5026 trim; SecondPassFdrTask.Inputs 152-153 |
| Osprey.FDR/StreamingFdr.cs 156-435 `ComputeFullPopulationPrecursorFdrStreaming`, 437-~500 `ComputeComplementExperimentQ`, ~600-660 `FileCompetition`, 663-~850 `CompeteOneFile`, 853-~930 `StreamedCompetitionState` | streaming stratified competition | delete | Only callers are Pass2FdrSidecar 1258/1517 and Pass2PerFileWorker 242. `ComputeStreamingCompetitionQvalues` (68) has NO caller at all already - verify and delete or leave; not compact's |
| Osprey.FDR/PercolatorQValues.cs 676-~760 `ComputeStratifiedCompetitionQvalues` | resident reference implementation | delete (test-only) | FdrTest 4123/4211 use it as the oracle |
| Osprey.FDR/ModelDiagnostics/ModelDiagnosticsData.CoAssignment.cs 110-123 (4 `*Stratum` props), 755-785 ctor param, 788-805 fields, 1153-1175 `SealCutoffs` split, 1357-1382 `ClearsExperimentBoundary`, 1492-1495; ModelDiagnosticsData.cs 928/989-992 `BuildPass2(stratumBaseIds)`; SecondPassFdrTask.cs 638-651, 827-836, 895-958 (`stratumBaseIds` params) | two-boundary co-assignment (#4573) | delete; `ClearsExperimentBoundary` -> `_experimentCutoff` | REPORT JSON loses `experimentCutoffInStratum/OffStratum/acceptedInStratum/OffStratum`. Regression/DiagnosticsGolden.ps1 191-197 adds 4 metrics x 2 passes; goldens `osprey-regression.data/{astral,stellar-libdecoy,stellar-gendecoy-entrap}/diagnostics.tsv` rows 30-33 and 52-55 (all NaN/0). Delete the Add-Metric lines AND the 8 rows per golden in the same commit, or the compare fails "metric missing from run" (DiagnosticsGolden.ps1:271). No re-record needed. The HTML template reads none of them. ModelDiagnosticsDataTest 560-660, 727, 1081-1112 (stratum split + streamed-vs-batch under a stratum) trim |
| Osprey.FDR/FdrDiagnostics.cs 214-235 `WriteCutoffs` | `experimentInStratum`/`OffStratum`/`accepted*` rows in the cutoffs dump | delete the four rows + params | a cs_ cross-impl dump: check `ai/scripts/Osprey/Compare/*` and Regression/FdrSidecars.ps1 (1203) for readers of those keys first |
| Osprey.IO/CarafeProteinIdNormalizer.cs 39-41, 179; Osprey.Scoring/PeakDataExtractor.cs 439; Osprey.IO/FdrScoresSidecar.cs 356; LibraryFragmentRelease.cs 44, 169-170; TrainingExportWriter.cs 53, 426-427; PercolatorEngine.cs 721; Calibrator.cs 230 | comments citing the stratum as motivation | reword (code stays: the normalizer also fixes picked-protein FDR) | IOTest 64-86 comment only |
| Tests that exist only for protein-compact ("delete with the option") | FdrTest: TestStratifiedCompetitionQvalues 4123, TestStreamingStratifiedMatchesResident 4211, TestStreamedCompetitionStateMultiFile 4299, TestTwoStageCompetitionMatchesGlobalPass 4653, TestEqualMaximaKeepTheEarlierFile 4706, TestFirstObservationAtTheMaximumWinsWithinAFile 4731, TestStratifiedCompetitionCompetesComplementSeparately 4757, TestFileCompetitionRoundTripsThroughSidecarRecords 4920, TestPoolDecoyRecordDoesNotOverrideCompetitionDecoyBest 5051, TestStratifiedCompetitionGivesUnchangedOffStratumPeaksComplementQ 5082; TestSecondPassPeptideCompetition 3394 (uses `ComputeFullPopulationPrecursorFdrStreaming` at 3421 - check what else it covers); TestReservoirKeepsTheBestPeakWithinTheDrawnRun 4576 (one stratum ref at 4632 - trim); IOTest.TestPass2CompetitionDecoysArtifact; SubsetPipelineTest.cs 1237-1247; SubsetPipelineTest.ProteinBest.cs 169-177; TaskValidityKeyTest 1100-1180 strata block + 326 region; OspreyCommandArgsTests 223 (`compact` parses) -> becomes "compact is refused/unknown" | delete / trim | FdrTest 5011 `TestSidecarRecordSequenceMustMatchPoolOrder` uses `Pass2FdrSidecar.AssertRecordsMatchPoolSequence` - keep if that helper survives (pool-order check is always on, per OspreyEnvironment 1630) |
| Tests already switched to `off` by the prep commit (keep) | SubsetPipelineTest.ProteinBest.cs 258, 286; TaskValidityKeyTest 98, 534-541; ProteinBestFeatureTest 259; Pass2FdrSidecarTest ~450-458; OspreyCommandArgsTests 216 | none | - |
| docs/12-second-pass-fdr.md (41 hits) | protein-compact design + history | rewrite to transfer-only; move the "why a second-pass null is a problem" history to a short "removed" note | OspreyEnvironment/Program comments cite "docs/12-second-pass-fdr.md" sections - keep the anchors they cite or update them |
| docs/00-pipeline-architecture.md 410-413, 900-902, 959-972, 1031, 1059-1060, 1428, 1564, 1573 ("Still to do: retiring protein-compact") | artifact table rows for stratum.json / fdr_decoys.bin, P12 note | delete rows; close the to-do | - |
| docs/14-intermediate-files.md 44, 88, 739, 814; docs/07-fdr-control.md 528-533 (history - keep), 647 (`--protein-boost {best\|compact\|off}`); docs/20-command-line.md 533 (`OSPREY_PASS2_QVALUE` row, already stale: "overriding the one --protein-boost implies"); docs/21-user-facing-text.md 21 (glossary "stratum" term); docs/22-training-export.md 114-115; docs/DIVERGENCES.md 49-51; docs/README.md 47 (index line names transfer-compete + protein-compact); docs/protein-shuffled-entrapment.md (18 hits - research record, keep, add a "retired" line) | doc references | update | docs/25-diann-gap-settings.md 9-11 STALE NOW: says unit resolution keeps `--protein-boost compact` + svm; 3bbdeba334 made it gbdt + best - fix regardless |
| Osprey-workflow.html 1350-1354 (FirstPassFDR out `.1st-pass.stratum.json`), 1414, 1892, 1913, 1946-1947, 2047-2057 (decision 6) | pipeline page | drop stratum output; mark decision 6 done | - |
| regression.ps1 / regression.html / Regression/*.ps1 | no leg sets protein-compact or `--protein-boost compact` (grep clean); only DiagnosticsGolden.ps1 191-197 (above) and a FdrSidecars.ps1:1203 comment | as above | the "compaction"/"pre-compaction" hits everywhere are the first-pass compaction gate, NOT protein-compact - leave them (CodeInspectionTest 334 bans `\bcompaction\b` in user text only) |
| ai/scripts (pwiz-ai, separate commit) | `Common/OspreyDatasetRun.psm1` 216-243 (`-Pass2Mode` ValidateSet incl. `protein-compact`, `transfer-compete`), 332-345 (`-ProteinBoost` ValidateSet incl. `compact`), 795 (`OSPREY_PROTEIN_COMPACT_QUALIFY`, no longer in C#), 936; Run-SeaAd/Run-Chs/Run-Tdp43/AstralEntrap/CohortAnalysis/Compare/Run-FdrBench/Benchmark/attach_entrapment.py | runners and analyses | drop the values from ValidateSets; analyses are history - leave | runner `-WhatIf` after the change |

**Known edge, a product issue to decide (not a retirement task):** on the tiny Stellar subset,
gbdt + protein-best leaves ZERO decoy protein-group winners, so `PepEstimator.Fit`
(Osprey.ML/PepEstimator.cs 87-97, "Can't estimate PEP without both classes") returns PEP 1.0 for
every protein group alongside q = 0. Under the old compact default exactly one decoy won, which
is why `TestSubsetStraightThroughAndReruns` could assert a protein PEP < 1; 3bbdeba334 moved that
assertion to `TestSubsetLibraryDecoysAndReports`. A real cohort is unlikely to hit it, but PEP 1.0
with q 0 is self-contradictory output; decide whether the fallback should be PEP 0 (or q-derived)
when there are targets and no decoys, or whether to log it.
