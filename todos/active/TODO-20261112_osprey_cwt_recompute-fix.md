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

## Decision (developer, 2026-11-14): match PerFileScoring for multi-window precursors

A precursor in two windows arises from isolation margins (Gillet-style SWATH), which Osprey does not
exclude yet: #5034. For this fix, handle it the way Stage 4 does rather than reproduce Stage 4's
choice across windows: each window computes the moved row's candidates from its own spectra, picks
its boundaries and scores it, and the rescore keeps the best row by `CoelutionSum` (Stage 4's
`DeduplicatePairs` rule) instead of the last window's. No cross-window reads, no slice reader. The
reproduction check applies in the window holding Stage 4's apex scan. Goldens may move only for
multi-window rows; log how many there are.

## UW8's "computation, not I/O" reading (2026-11-14)

UW8 measured #5030 at +42% PerFileRescoring (5,678 -> 8,062 s) and attributed it to compute because
the `[PATH]` block-read totals were flat ("other" 26.1 vs 26.0 GB). Those counters do not see
`.spectra.bin` MS2 reads at all: 26 GB / 82 = 0.32 GB per file, against 4.2 GB of MS2 cache per file
that both builds read in the rescore. +2,384 s / 82 = 29 s per file, about one 4.2 GB cache at a SATA
HDD's ~145 MB/s (or a cold parallel sweep at the ~85 MB/s the serial-read comment measured). The
recompute's compute is ~50-75 thread-s per file (MACS2 rd2post, file 4/82: rescoring 15,854 peaks
and detecting 11,038 missing peaks each took 52 thread-s), i.e. ~2-3 s/file on 32 threads. The fixed
build's A/B on an UW8-like layout decides it: parity with pre-#5030 = I/O; a residual ~29 s/file =
compute.

## Progress Log

### 2026-11-14 - Session Start

Branch created in `D:\Users\brendanx\proj\pwiz` from #4950 head 849586af76. Code map above read
from that tree.

### 2026-11-14 - Implementation (uncommitted), gate green

- `ReconciliationPlanner.FilePlanner.SelectMoves` chooses the moved entries (no candidates) as
  `ReconcileMove` (expected RT, half-width, RT tolerance; `Resolve` = `DetermineAction`); `PlanFile`
  = SelectMoves + candidate source + Resolve (the test-only whole-experiment path).
- `RunReconciliationPlanner.PlanRun` returns a `RescorePlan` (refit, gap fill, moves);
  `CompleteRun` builds the `.reconciliation.json` from entry_id-keyed actions; `PartialRun` (no
  actions) is what `ApplyPlan` applies before the rescore. A run with no moves is saved at once.
- `IWindowBoundaryResolver` + `ScoringContext.BoundaryResolver`; `CoelutionScorer.ScoreWindow`
  resolves the window's moved candidates right after sorting its spectra and scores with a
  window-local override map (`ScoringContext.WithBoundaryOverrides`).
- `CwtCandidateRecompute` is now that resolver: per window, `RecomputeCwtCandidates` (first-pass
  settings) + `ReconcileMove.Resolve`; the window holding the Stage 4 apex scan sets the plan's action
  and the reproduction check; `Verify` throws `NotReproduced` per run. The planning sweep is gone.
- `RescoreOneFile` builds the resolver, verifies after the rescore, logs
  `[COUNT] Moved peaks resolved in more than one isolation window`, saves the plan before the
  reconciled parquet. `RescoreOneFileStreamed` reports a resolver failure per run.
- Gate: `Build-Osprey.ps1 -Debug -RunTests -RunInspection` 684/684, inspection 0
  (`ai/.tmp/sessions/20261112-5023/fix-gate2.log`). Snapshots: `_bin\cwtfix-base-849586af76`,
  `_bin\cwtfix-wip1`.
- Running: `regression-parallel.ps1 -Dataset All` (`fix-regression-all.log`); 20-file A/B chain
  `ai/.tmp/sessions/20261112-5023/cwtfix-ab.ps1` -> `D:\...\sea-ad\runs-cwtfix\cwtfix-ab.log`
  (full runs base20/pre20, then PerFileRescoring arms base/fix/pre x2 after a ~500 GB cache flush,
  spectra on E: then copied to D:; drive I/O in `runs-cwtfix\disk-io.tsv`).

**Overlapping windows (the open design question), traced:**
- Every MS2 scan belongs to one isolation window, so exactly one window holds a row's Stage 4 apex
  scan: the window its candidates must come from (the "apex window").
- The rescore scores a target in EVERY window holding its precursor m/z
  (`ScoringPipeline.RunCoelutionScoring`, parallel, largest window first, results flattened in
  window-index order), and `OverlayRescoredEntries` keeps the LAST row per entry_id
  (`rescoredByEntryId[entry.EntryId] = entry`) - the highest-index window that found a peak.
- So a moved row in two windows whose apex window is not the one being scored needs the apex
  window's candidates in the other window's job. Windows depend on each other in both directions
  (adjacent overlaps), so no processing order resolves it, and holding windows in memory until a
  neighbour finishes is unbounded under largest-first scheduling.
- `SpectraWindowIndex` keeps per-record offsets and the records are in RT order, so a window's
  RT slice can be read alone. Candidate detection should read only the first-pass search range
  (to verify in `PeakDataExtractor.TryExtract`: any margin beyond it sets the slice bounds).

Proposed: in each window's job, resolve the moved rows whose apex is in that window from the
loaded spectra; for an overlap row whose apex window is elsewhere, read that window's RT slice
(search range only, through the gated reader) and resolve from it. Bulk rows: no extra read; overlap
rows: a slice of a few scans. Every window computes identical boundaries for a row, so the result is
independent of which window's row wins. The reproduction check (apex at Stage 4's scan) still
guards bit-identity, including that the slice covers what detection reads.

### 2026-11-14 - Regression and 20-file A/B (MACS2)

- `regression-parallel.ps1 -Dataset All`: 49 PASS / 0 FAIL in 1:00:50, unchanged output; multi-window
  resolutions 0 in every leg (`ai/.tmp/sessions/20261112-5023/fix-regression-all.log`).
- Commit a43f875c51 (local, not pushed).
- 20-file PerFileRescoring A/B, #4950 head (849586af76) vs the fix, chain `cwtfix-ab.ps1`, results under
  `D:\Users\brendanx\test\osprey-runs\sea-ad\runs-cwtfix\` (`cwtfix-ab.log`, `disk-io.tsv`):

  | Spectra on | #4950 head | Fix |
  |---|---|---|
  | E: | 397, 375 s | 450, 436 s |
  | D: (copied beside parquets) | 450, 307 s | 294, 298 s |

  - Output: `.reconciliation.json` and `.scores-reconciled.parquet` byte-identical across all arms
    (40 files per comparison).
  - The runs were NOT cold. MACS2 has 511 GB RAM; the 263 GB "flush" left ~450 GB standby, and
    `disk-io.tsv` shows ~0 GB of disk reads in 7 of 8 arms. Only d1base read from disk (21 GB, D: queue 12),
    so its 450 s is the one cold-ish number. The A/B therefore measures compute, not I/O.
  - Warm, the same fix binary took 443 s (E: arms) and 296 s (D: arms), so run-to-run noise on the shared
    machine is as large as the effect. Window-thread busy time: base ~2,550-3,700 thread-s, fix
    ~2,550-4,920 thread-s.
  - Not yet a demonstrated gain. The I/O benefit needs a machine whose RAM cannot hold the working set
    (the 64 GB i9, or UW8).
