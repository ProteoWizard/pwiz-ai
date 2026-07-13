# TODO-model_diagnostics_memory_streaming -- Stream --model-diagnostics so it doesn't scale memory with run count

- **Status**: Backlog
- **Created**: 2026-07-13
- **Raised by**: Brendan (2026-07-13, after the 82-file run OOMed on a 64 GB box)

## Problem
`--model-diagnostics` (and `--fdrbench-pass 1`) force the RESIDENT first-pass pool at the FirstJoin
(`FirstJoinTask.cs:274` `needsResidentFirstPassPool`) -- exactly the pool the projection streaming
path (#4400, default) was built to DROP so large file counts fit a modest machine. Consequence:
memory scales with run count DIFFERENTLY with the flag than without it.
- 20 files WITH --model-diagnostics peaks ~60 GB (measured, --memstamp).
- 82 files WITH --model-diagnostics is expected to OOM at the FirstJoin resident pool on 64 GB.

Two independent memory ceilings hit the 82-run set, so BOTH must be addressed to make 82-file
diagnostics feasible on 64 GB:
1. **--model-diagnostics forced resident first-pass pool** (this flag's own cost).
2. **Stage-6 reconciliation persistent reload** -- a SEPARATE ceiling (see below), also un-streamed.

## Goal
Make `--model-diagnostics` feasible on the full 82-run SEA-AD set on a 64 GB machine, and make its
memory NOT scale with run count differently than a normal (no-flag) run. (Yes -- streaming.)

## Approach (streaming)
1. **Diagnostics data is aggregate-shaped, not per-entry-resident.** The report needs per-file
   summaries + binned histograms + FDP/yield curves + feature contributions -- NOT every
   pre-compaction entry held resident. Stream the diagnostics accumulation per file (fold each
   file's contribution into the histograms/curves as it is scored, on the projection path) instead
   of forcing the whole resident pool at FirstJoin. Keep byte-identity of the default (no-flag) path.
2. **Stage-6 reconciliation** (independent, also OOMs at 82 files even WITHOUT --model-diagnostics):
   #4394 (`9353ed4c31`, Fixes #4376) bounded the per-file rescore TRANSIENTS (per-file drop + forced
   GC) and validated on 8-file NON-entrapment Astral Carafe, but explicitly DEFERRED the persistent
   reload lever: "stream/project `LoadFullFdrEntries` so the per-file reload is small in the first
   place" (still `Stage6Planner.cs:267` perFileCwtCandidates all-files load + `PerFileRescoreTask.cs
   :589` all-files rescored FdrEntry buffer). At 82 files x the ~2x entrapment library this exceeds
   64 GB. Build the deferred streaming lever.

## Validation
- `--memstamp` (managed + private MB per line, now in the run scripts) to profile each phase; confirm
  no phase's private MB scales with run count once streamed.
- 82-file `--model-diagnostics` run completing on the 64 GB box, byte-identical default path
  (`regression.ps1 -Dataset Stellar` mode1/2/3), perf-neutral (`Test-PerfGate.ps1`).

## References
- `FirstJoinTask.cs:274` (needsResidentFirstPassPool), #4400 (projection streaming), #4405.
- #4394 / #4376 / `ai/todos/completed/TODO-20260707_osprey_reconciliation_memory.md` (deferred lever).
- This session's 82-file OOM diagnosis: budget log + `ai/.tmp/pass2ab-20file-results.md`.
