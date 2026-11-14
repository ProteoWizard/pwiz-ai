# Fix #5030: load each run's spectra once in PerFileRescoring

## Branch Information
- **Branch**: `Skyline/work/20261114_osprey_cwt_recompute-fix`
- **Base**: `Skyline/work/20261028_osprey_diann_fdr_gap` (#4950) at 849586af76 (the #5030 squash)
- **Created**: 2026-11-14
- **Status**: In Progress
- **Fixes**: [#5030](https://github.com/ProteoWizard/pwiz/pull/5030) (TODO: `ai/todos/completed/2026/11/TODO-20261112_osprey_cwt_recompute.md`)
- **Module**: `osprey`
- **PR**: (pending) - targets the #4950 branch directly; #5033 picks it up by merging from #4950

## Problem

#5030 removed `cwt_candidates` from `.scores.parquet` and recomputes them in Stage 6, but it kept
Rust's plan-then-rescore shape: planning (`CwtCandidateRecompute.ForRows`, called through
`FilePlanner.PlanFile`'s `CwtCandidateSource`) loads every isolation window holding a consulted
precursor - the full gradient, nearly every window - in a parallel, ungated FileStream sweep, and
then the rescore loads the same windows again. Each run's spectra are read twice. The #5030 TODO
noted this ("the production version should share the rescore's window loads") and the review
triage dropped it for lack of a measured gain on 3 files from the SSD.

Measured 2026-11-13 on MACS2, 82 files, all-109, #4950 recipe, PerFileRescoring alone, ABAB
(details in `TODO-20261110_osprey_feature_set.md`; logs `D:\...\sea-ad\runs-cwt\_kept\`):

| Spectra on | pre-#5030 (stored) | #5030 (recompute) | Change |
|---|---|---|---|
| E: SSD RAID, apart from the parquets | 2,074 s | 1,823 s | -12% |
| D:, beside the parquets (UW8-like) | 2,643 s | 3,568 s | +35% |

UW8 (one SATA HDD) measured +36%. On D: the physical bytes were about equal; the planning sweep
doubled the disk queue (25 vs 14) and slowed the gated parquet reads.

## Design

Nothing the planner decides depends on the candidates except the boundaries of rows it already
chose to move:
- `PlanFile` (`ReconciliationPlanner.cs:307-337`) selects the moved rows from consensus, the
  experiment-FDR pass and the apex-vs-tolerance test; candidates are asked for afterwards (:339).
- `DetermineAction` only picks `UseCwtPeak` (closest candidate apex within tolerance) vs
  `ForcedIntegration`; both are rescored.
- The refit (`CalibrationRefit.Refit`) and gap-fill identification (`IdentifyFile`) in
  `RunReconciliationPlanner.PlanRun` use no candidates.
- The only later reader of `.reconciliation.json` is `Pass2FdrSidecar.LoadGapFillEntryIds`
  (gap-fill ids only).

So: planning emits the moved rows unresolved (expected RT, tolerance, half-width, Stage 4 apex scan);
the rescore's own window load computes their candidates (`CoelutionScorer.RecomputeCwtCandidates`,
first-pass calibration and search settings), applies `DetermineAction`, and scores the chosen range
from the same spectra. The resolved plan is written after the rescore. Spectrum reads equal
pre-#5030's; the column's writes and reads stay gone; the extra cost is an in-memory recompute for
<1% of rows.

## Tasks

- [ ] Design detail: where in `RunCoelutionScoring`'s window loop a deferred override resolves.
      Bit-identity needs Stage 4's window (holds the precursor m/z and the apex scan, lowest index).
      Open: a precursor in two overlapping windows is scored in both and deduped - every window
      that scores it must use the same resolved boundaries.
- [ ] `ReconcileAction` (or the boundary-override record) gains a deferred form; `PlanFile` stops
      calling the candidate source in production (the test-only whole-experiment `Plan` may keep it)
- [ ] `PlanAndWriteRun` writes the resolved plan after the rescore; keep the stamp rule (a killed
      run is a run that is not done)
- [ ] Keep the always-on reproduction check (apex at Stage 4's `ScanNumber`, else fail the run)
- [ ] Remove the planning sweep in `CwtCandidateRecompute.ForRows`
- [ ] Gate: `Build-Osprey.ps1 -RunTests -RunInspection`; `SubsetPipelineTest`; `.reconciliation.json`,
      reconciled parquets, FDR sidecars and blib tables byte-identical to 849586af76 on the subsets
- [ ] `regression-parallel.ps1 -Dataset All` goldens unchanged
- [ ] Same-scale check #5030 used: SEA-AD 3-file ABAB vs 849586af76 (PerFileRescoring time; the
      `[PATH]` block-read lines now include all spectra reads)
- Deferred (developer, 2026-11-14): the many-hours 82-file validation, run in parallel on MACS2
  (spectra on E: and on D:) and an i9 desktop (64 GB), later.

## Progress Log

### 2026-11-14 - Session Start

Branch created in `D:\Users\brendanx\proj\pwiz` from #4950 head 849586af76. Code map above read
from that tree.
