# Osprey: stream `--model-diagnostics` (Deliverable B)

**Date:** 2026-07-14
**Branch:** `Skyline/work/20260714_osprey_mdiag_streaming` (pwiz), stacked on PR #4419's
branch `Skyline/work/20260713_osprey_diagnostics_memory`.
**Parent:** the explicitly-deferred "Deliverable B" follow-up of
`TODO-20260713_osprey_model_diagnostics_memory.md` ("stream `--model-diagnostics`").

## Problem
`--model-diagnostics` forced the resident pre-compaction first-pass pool at FirstJoin
(`FirstJoinTask.cs` `needsResidentFirstPassPool = config.ModelDiagnostics || ...`) because
`ModelDiagnosticsData.Build` walks every per-file `FdrEntry`. At 82 SEA-AD Astral files that
pool is ~340M entries and OOMs a 64 GB box at the join — so the 82-file mdiag comparison could
never be produced. #4400/#4355 already stream the default path via a thin `FdrProjection`; mdiag
opted out.

## Approach (byte-identical streaming)
Every report card is derived from the REDUCED best-per-precursor set (bounded by unique
precursors / base-ids, not the 340M raw entries). The reductions (max score, min q, per-file
passing tallies, cross-run key-sets, per-base_id max) are all ORDER-INDEPENDENT (within a
`modseq|charge` key the class / is_decoy / pair are invariant), so folding each row as it streams
reproduces the batch reduction exactly. New `ModelDiagnosticsData.Accumulator` (nested, mirrors
`FeatureContributions.Accumulator`) is fed per-row by the projection score-pass sink
(`FdrProjectionSinkBase.Accept`) and its `Build` runs the identical downstream builders. The
projection SVM now also collects the per-feature histograms (Model tab) and surfaces
`FeatureContributions` via a capture callback. `--model-diagnostics` dropped from the
resident-pool gate → mdiag takes the projection path; the resident path keeps the old batch
`Write` as the byte-identity oracle. Pass-2 report (MergeNode, small reported pool) unchanged.

Transfer arm (`OSPREY_PASS2_QVALUE=transfer`) still forces the resident pool via its own
`Pass2TransferQ` term (builds the full score→q table) — separate, smaller follow-up (stream the
`(score,label)` table). Arm A (percolator) is unblocked by B alone.

## Status
- Implemented across 6 product files + 2 test files (see budget log / commit).
- Osprey pre-commit GREEN (build net472+net8.0, inspection 0 warnings, 506/509 tests, 3 skipped).
- **Byte-identity unit test GREEN** (`TestStreamingAccumulatorMatchesBatch`): streaming
  Accumulator == batch Build (serialized JSON) on a 3-file entrapment fixture, all cards populated.

## Remaining / gates
- `regression.ps1 -Dataset Stellar` — blib byte-identical (B must not touch the mainline blib).
- End-to-end report byte-identity: same input, resident (`OSPREY_USE_FDR_PROJECTION=0`) vs
  projection mdiag HTML must match (validates projection-vs-resident SVM + histograms end to end).
- Produce the 82-file arm A (percolator) mdiag HTML with the B build (the science deliverable).
- Open the stacked PR (base = the #4419 branch). Run `/pw-self-review`. Do NOT trigger TeamCity.

## References
- Design: `ai/.tmp/deliverable-B-design.md`; night log: `ai/.tmp/night-session-budget.md`.
- Handoff: `ai/.tmp/handoff-20260714_osprey_mdiag_82file_pass2ab.md`.
