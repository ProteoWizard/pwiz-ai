# Osprey: stream `--model-diagnostics` (Deliverable B) + kill its 82-file memory/logging anomalies

**Date:** 2026-07-14
**Branch:** `Skyline/work/20260714_osprey_mdiag_streaming` (pwiz). **PR #4420**, now based on
**master** (retargeted + rebased after #4419 merged 2026-07-14).
**Parent:** the explicitly-deferred "Deliverable B" of `TODO-20260713_osprey_model_diagnostics_memory.md`.

## Problem
`--model-diagnostics` OOM'd / mis-behaved on the full 82-file SEA-AD Astral run in two ways:
1. **Report build** walked every per-file `FdrEntry` (340M entries), forcing the resident pool at
   FirstJoin. (Deliverable B, below, streamed this.)
2. **Upstream per-file pool** stayed resident because `PerFileScoringTask.NeedsResidentPool`
   still included `ModelDiagnostics` -> the scoring->FirstJoin boundary spiked to **~100 GB** on a
   64 GB box (perfviz on the 82-file arm-A log). Plus a cluster of **silent logging gaps** (5-15 min
   with no output) in FirstPassFDR / SecondPassFDR that made the run look hung.

## Deliverable B (committed: 9259c059cf, dccced9b1b)
Every report card derives from the REDUCED best-per-precursor set. New nested
`ModelDiagnosticsData.Accumulator` is fed per-row by the projection score-pass sink and its `Build`
runs the identical downstream builders -> byte-identical to the resident batch `Write`. `--model-diagnostics`
dropped from the FirstJoin resident gate. Gated: unit byte-identity test + Stellar blib + 3-file
resident-vs-projection HTML identity (all green pre-session).

## This session (2026-07-14, autonomous) -- memory + logging anomalies (Brendan-requested)
- **L1 (100 GB spike):** dropped `config.ModelDiagnostics` from `PerFileScoringTask.NeedsResidentPool`
  so the COMPUTE path streams the lean projection per file (no fat FdrEntry pool). The scoring->FirstJoin
  fat-pool assembly (the perfviz spike, ~41->102 GB over a 15-min silent gap) is gone.
  - **Resume-path fix (self-review HIGH):** a resume SKIPS the first-pass score pass that feeds the
    streaming accumulator, so `FirstJoinTask.RehydrateFromOwnOutputs` emits mdiag via the BATCH
    `ModelDiagnosticsReport.Write(perFileEntries,...)`. With L1 that got empty entries -> empty report.
    Fix: `NeedsResidentPool(config) || config.ModelDiagnostics` on the resume path only (pre-L1-identical;
    compute path stays lean). PerFileScoringTask.cs:602.
- **Logging heartbeats** (output-safe; blib/HTML/JSON gates don't read the log) for the silent phases:
  pool load (fat+lean, PerFileScoringTask), library classification (ModelDiagnosticsReport heading),
  training-vector load (PercolatorEngine), competition q-values (PercolatorFdr, phase markers gated on
  n>2M), reconciliation planning (ReconciliationPlanner), 2nd-pass PIN reload (Pass2FdrSidecar).
- **M2 (memory step-up PerFileScoring ~50 GB -> PerFileRescoring 60-75 GB):** INVESTIGATED, deferred to
  a **profiled follow-up** (NOT this byte-identity PR). Root: `PerFileRescoreTask.Run:200` holds the whole
  `CompactedEntries` pool resident FirstJoin->MergeNode (the #4394 lever). Candidate win: the 2nd pass
  RELOADS PIN features from the reconciled parquet (`Pass2FdrSidecar:504`), so features held resident
  meanwhile may be droppable -- but needs a dotMemory profile at 82-file scale + byte-identity proof first.
  L1 already removes the dominant 100 GB spike; the 60-75 GB band is pre-existing on ALL 82-file runs.

## Gates (this session)
- Osprey pre-commit GREEN (build net472+net8.0, 506/509 tests, inspection clean modulo the known
  SystemMemory.cs #4379 local flake).
- `regression.ps1 -Dataset Stellar` PASS: mode1/2/3 blib byte-identical (45,064,192 bytes) -> default path
  byte-neutral.
- Self-review clean after fixes (1 HIGH resume regression + 2 LOW nits, all addressed).
- **3-file resident-vs-projection(lean) mdiag HTML byte-identity** PASS (355,767 bytes; validates L1's
  lean-path accumulator == batch oracle on the NEW lean path).
- **20-file perfviz** CONFIRMED L1 + the pool-load heartbeat removed the ~100 GB PerFileScoring spike + its
  15-min gap. Surfaced 3 residual first-pass-FDR gaps that scale with file/entry count (~5x at 82 files):
  per-run q-values (~83 s), experiment q-values (~97 s), survivor reload / "First-pass compaction" (~73 s).
  FIXED (commit 39a7fc0037): a throttled ProgressReporter threaded through the shared CompeteFromIndices/
  CompeteAll (experiment + PEP ~344M-row walks) + per-file per-run q-value + survivor-reload reporters,
  gated on a large population. Re-gated: pre-commit + regression Stellar blib-identical + 3-file projection
  mdiag byte-identical with all six new reporters firing. Console-only, byte-neutral.
- The definitive 82-file perfviz (spike + all gaps gone at scale) comes from tonight's overnight re-run.

## Remaining / overnight
- **Tonight (overnight):** re-run BOTH Arm A (percolator) and Arm B (transfer) 82-file `--model-diagnostics`
  on this fixed build; validate at scale (perfviz: no 100 GB spike, no FirstPassFDR/SecondPassFDR gaps) and
  produce the Pass-2 A/B comparison (`Compare-Pass2AB.py`). Arm B may still OOM via the `Pass2TransferQ`
  resident term -> stream the (score,label) score->q table if so (separate lever).
- **Open follow-up (profiled):** M2 Stage-6 resident-pool profiling + streaming lever, AND Copilot's
  accumulator key-allocation note (#4420 threads deferred, left unresolved): `Add` builds a `modseq|charge`
  key string per projection row (340M on 82 files). A `(modseq,charge)->string` cache is byte-safe but adds
  ~100-300 MB resident; a value-tuple key is allocation-free but reorders `_best.Values` and breaks the
  BuildScoreHistogram byte-identity invariant. Measure allocation-churn vs peak-resident with dotMemory at
  82-file scale before choosing -- do not guess.

## References
- Design: `ai/.tmp/deliverable-B-design.md`; night log: `ai/.tmp/night-session-budget.md`.
- perfviz: `ai/scripts/perfviz.html`; gap/mem analyzers: `ai/.tmp/find-log-gaps.py`, `find-mem-spikes.py`,
  `make-perfviz.py`. 3-file A/B: `ai/.tmp/run-mdiag-ab3.ps1` + `Compare-MdiagData.py`.
