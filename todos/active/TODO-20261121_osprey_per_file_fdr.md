# TODO: Per-file first-pass FDR model (DIA-NN style) - moves FirstPassFDR's work into the fan-out

## Branch Information
- **Branch**: `Skyline/work/20261122_osprey_per_file_fdr` (pushed to origin; was `nightlywork/20261121_osprey_per_file_fdr`)
- **Base**: `master` (b3dcb52e07)
- **Created**: 2026-11-21
- **Status**: Experimental switch complete (A4 +1.2%, A5 +0.15% at 35% less training); draft PR text ready; next: milestone 1 (iteration workflow)
- **Module**: `osprey`
- **PR**: (pending - draft, experimental)

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

**Next session handoff**: For detailed startup protocol, read `ai/.tmp/handoff-20261122_osprey_per_file_fdr.md` before starting work. Draft PR #5070; sprint order and agreed design (four file-to-file tasks, per-file vs join rule, two validity keys, FirstPass/SecondPass composites, map-reduce summaries) are in this TODO's design section.
