# TODO-osprey_model_diagnostics_run_count_fdp -- Add a "true FDP vs number-of-runs-identified" card to --model-diagnostics

- **Status**: Backlog
- **Created**: 2026-07-13
- **Raised by**: Brendan (found "very interesting" during the pass-2 q-value discussion, 2026-07-13)

## Motivation
Experiment-wide q reduces each precursor to its single best-scoring peak across runs (min-q), which
throws away the **count of runs** a peptide was identified in -- the reproducibility signal a human
reviewer trusts most. Lukas Kall has agreed the min-q experiment-wide estimate is "highly
unsatisfying" for exactly this reason, and the true FDP climbs sharply at the low-run-count tail.

Measured on the 20-file SEA-AD r~1.0 run (experiment scope, combined estimator), from the report's
OWN `crossRun` data:
| #runs identified in | true FDP (exact) | cum >= k runs FDP |
|---|---|---|
| 1  | 7.6% (perRun 16.8%) | 0.88% (all) |
| 5  | 1.2% | 0.37% |
| 10 (>= half) | 0.45% | **0.25%** (29,439 peptides) |
| 20 (all) | 0.03% | 0.03% |

The aggregate experiment-wide q (0.88%) BLENDS the clean multi-run core with the dirty single-run
tail and hides it. Brendan's "peptides identified at run-level q in >= half the runs = sufficient FDR
control for any experiment" gives 0.25% FDP -- 3.5x better than the 1% target -- keeping 29K peptides.

## The data already exists
`crossRun.{experiment,perRun}` in `ModelDiagnosticsData` already carries `runCountHistogram`,
`entrapmentRunCountHistogram`, `entrapmentFdpByRunCount`, `atLeastHalf`, `cumUnion*`, `unionFdp`.
So this is largely a **new report card over existing data**, not new computation.

## Proposed work
1. A "FDP vs #runs" card in the --model-diagnostics HTML: bar/line of true combined FDP by exact
   run count + the cumulative ">= k runs" curve, the run-count histogram, and a marker at the
   ">= half runs" operating point with its FDP + accepted count. Both experiment and per-run scopes.
2. Optionally surface a reproducibility-based cutoff ("report peptides passing run-level q in >= half
   the runs") as an alternative/complement to the experiment-wide q, since the FDP tail shows that is
   the honest confidence axis.
3. Connect to the pass-2 story: gap-fill's value is moving peptides UP the run-count axis (1-run ->
   N-run), enriching confidence without changing experiment-wide q.

## References
- `Osprey.FDR/ModelDiagnostics/ModelDiagnosticsData.cs` (crossRun assembly), the CAL/FDR template.
- Analysis + reusable extractor: `ai/.tmp/pass2ab-20file-results.md`, `ai/.tmp/runcount_fdp.py`.
- Related: the TRIC transfer experiment-q pass-through (TODO-20260710) -- same run-count reasoning.
