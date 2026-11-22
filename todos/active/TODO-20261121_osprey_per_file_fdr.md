# TODO: Feasibility of a per-file first-pass FDR model (DIA-NN style), to drop the feature parquet

## Branch Information
- **Branch**: `nightlywork/20261121_osprey_per_file_fdr` (local only, C:\proj\pwiz)
- **Base**: `master` (b3dcb52e07)
- **Created**: 2026-11-21
- **Status**: In progress - measurement study (A0 control launched)
- **Module**: `osprey`
- **PR**: (none - developer-only experiment switch, not for merge as is)

## Goal

Osprey finds 97,120 precursors at true FDP 1% (pass 1) on SEA-AD 82 files, within 4% of
DIA-NN's 101,269, but writes ~183 GB, ~165 GB of it `.scores.parquet`, where DIA-NN writes
7.5 GB. The parquet exists to feed FirstPassFDR's experiment-wide feature join; after
FirstPassFDR the later stages read only its scalar stub columns. A model trained PER FILE
inside PerFileScoring (as DIA-NN trains one per run) would emit only per-run scores/q/PEP,
shrink FirstPassFDR to calibration + planning, and remove the feature parquet.

Question: does a per-file model keep the detections? Measured on real data before any redesign.

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

Measured at FirstPassFDR only: the persisted model stays global, so pass 2 under transfer is not
valid for these arms.

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

## Decisions
