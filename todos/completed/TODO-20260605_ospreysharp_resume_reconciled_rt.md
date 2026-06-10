# TODO-20260605_ospreysharp_resume_reconciled_rt.md — Straight-through resume writes 1st-pass RTs

## Branch Information
- **Branch**: `Skyline/work/20260605_ospreysharp_resume_reconciled_rt`
- **Base**: `master`
- **Created**: 2026-06-05 (bug originally reported 2026-06-03; fixed under this branch as PR-E)
- **Status**: Completed
- **GitHub Issue**: (none — tracked via this TODO)
- **PR**: [#4270](https://github.com/ProteoWizard/pwiz/pull/4270) (merged 2026-06-05 as `6d6db7dd`)

**Status**: **Completed — FIXED + merged 2026-06-05 as PR [#4270](https://github.com/ProteoWizard/pwiz/pull/4270) (`6d6db7dd`).**

### 2026-06-05 — Merged
PR #4270 (PR-E) merged as `6d6db7dd`. PerFileRescore's resume paths (the Rehydrate no-op and the
ExecuteRescore per-file skip) now load each file's own `.scores-reconciled.parquet` and overlay the
reconciled boundary/area/feature columns onto the post-compaction buffer (by EntryId, preserving
ParquetIndex + 1st-pass scores), append gap-fill rows, and apply the canonical
(EntryId,Charge,ScanNumber,ParquetIndex) sort to EVERY file — so MergeNode writes Stage-6 reconciled
RTs to the blib, not 1st-pass. A reconciled-parquet load failure now throws (fail-loud) rather than
producing a wrong blib. Gated by resume-smoke byte-parity + worker-strict bit-parity on Stellar AND
Astral; the resume parity gate (added with PR-D #4269) is now green. Copilot + fresh-context
self-review both addressed.

---
*Original (pre-fix) bug report below.*

**Status (original)**: Backlog — pre-existing bug (predates the PR-B declarative-dataflow work;
PR-B's mode-routing NPE was masking it). Straight-through resume IS a supported workflow
(confirmed 2026-06-03), so this is a real correctness issue.

**2026-06-05 update (PR-D night session)**: The gate now exists.
`ai/scripts/OspreySharp/Compare/Compare-StraightThroughResume-CSharp.ps1` reproduces this bug
byte-exact (Stellar 3-file: warm/resume blib 52,486,144 vs cold 52,514,816; ~11K/59768 RTs off by
~1.3 min) and FAILS on it today. PR-D (rehydrate purity) is behavior-preserving and deliberately does
NOT fix it. **The fix is now PR-E**: make PerFileRescore's straight-through resume Rehydrate
(PerFileRescoreTask.cs, the `!ExpectReconciledInput` branch — currently reads CompactedEntries) load
its own `.scores-reconciled.parquet` and overlay reconciled RT/area/Features/ParquetIndex onto the
CompactedEntries rows + append gap-fill rows, reaching the same buffer a fresh `ExecuteRescore` leaves.
Full recipe + parity traps in `ai/.tmp/prd-implementation-map.md` and the Site-3 sub-agent map (esp.:
fresh OverlayRescoredEntries PRESERVES the original ParquetIndex, PerFileRescoreTask.cs:1013, and
gap-fill rows carry ParquetIndex=uint.MaxValue — the load must reproduce that, NOT the reconciled-row
index; and gap-fill vs compacted-out rows must be disambiguated via PerFileGapFillForRescore). Gate
the fix with the resume smoke (Stellar + Astral) until cold==warm.
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
