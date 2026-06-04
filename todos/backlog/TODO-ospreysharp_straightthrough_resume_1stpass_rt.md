# TODO: Straight-through resume writes 1st-pass RTs (ExecuteRescore per-file skip)

**Status**: Backlog — pre-existing bug (predates the PR-B declarative-dataflow work;
PR-B's mode-routing NPE was masking it). Straight-through resume IS a supported workflow
(confirmed 2026-06-03), so this is a real correctness issue.
**Priority**: Medium — correctness bug, but only on the resume path (rare); no fresh-run impact.
**Found by**: PR-B fresh-context self-review follow-up (2026-06-03).

## Symptom

Resume an interrupted **straight-through** run (`-i mzML ... -l lib -o out.blib`, no
`--input-scores`) where PerFileRescore's per-file `.scores-reconciled.parquet` outputs are
already valid on disk. The run completes, but `output.blib` carries **1st-pass retention
times** instead of the reconciled RTs — `RefSpectra`/`RetentionTimes` diverge by ~1.3 min on
~11K/59768 entries (Stellar 3-file), plus `copies`/`bestSpectrum`/`NRunsDetected` deltas.

## Repro (Stellar 3-file)

1. Full run: `OspreySharp -i f20.mzML -i f21.mzML -i f22.mzML -l lib -o output.blib --resolution unit --protein-fdr 0.01` → blib 52514816.
2. Invalidate FirstJoin so it re-runs: `rm *.1st-pass.fdr_scores.bin.FirstJoin.osprey.task *.reconciliation.json.FirstJoin.osprey.task output.blib`.
3. Resume the same command → completes, blib **52486144** with 1st-pass RTs.
4. `Compare-Blib-Crossimpl.ps1 -RustBlib <reconciled-canonical> -CsBlib <resume>` → OVERALL FAIL on RefSpectra/RetentionTimes.

## Root cause

`PerFileRescoreTask.ExecuteRescore`'s per-file resume skip (the
`File.Exists(reconciledPath) && TaskValiditySidecar.IsValid(...)` → `continue` near
`PerFileRescoreTask.cs:~567`) leaves that file's entries in the shared `_perFileEntries`
buffer at their **pre-rescore (1st-pass) state** — it never reloads the reconciled scores.
Its own comment says *"the skipped file's in-memory entries remain at the pre-rescore state
... because the worker's StopAfter terminates the pipeline here -- no downstream consumer
reads them."* That holds in the **stage-6 worker** mode it was written for, but is FALSE on a
**straight-through resume**, where MergeNode is downstream and reads `_perFileEntries` for the
2nd-pass FDR + blib write → it gets 1st-pass RTs.

This logic is unchanged from master, so master has the same bug; PR-B's mode-routing NPE
(now fixed) was crashing before reaching it. The PR-B fix (`Rehydrate` defers to `Run` on the
non-worker path) restores master's exact behavior here, so PR-B neither caused nor cures it.

## Fix direction (to design)

When `ExecuteRescore` per-file-skips an already-reconciled file, **reload that file's
reconciled entries from `.scores-reconciled.parquet` into `_perFileEntries`** (so a downstream
MergeNode sees reconciled RTs), instead of `continue`-ing with the 1st-pass entries. Mirror
the load shape `PerFileScoring`/`LoadFullFdrEntries` already use. Gate with a NEW
**straight-through resume** parity check (the existing strict-rehydration gate validates the
multi-process HPC chain, never single-process resume — that is the coverage gap that let this
hide). Add that resume smoke to the gate at the same time.

## Related
- `ai/todos/active/TODO-20260601_ospreysharp_declarative_pipeline_dataflow.md` (PR-B; where
  this was surfaced and the NPE that masked it was fixed).
