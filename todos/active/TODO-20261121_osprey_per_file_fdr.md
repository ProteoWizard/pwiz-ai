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
| A2 two-level | | | | | | |

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

## Decisions
