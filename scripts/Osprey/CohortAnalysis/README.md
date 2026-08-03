# Cross-cohort analysis of Osprey `--model-diagnostics` runs

Tooling for comparing MANY Osprey runs against each other - "how does the result change when the
set of input files changes?" - as opposed to
[`../ModelDiagnostics/`](../ModelDiagnostics/README.md), which generates and validates a single
report.

Built for the mean(best-N) experiment-score investigation (2026-07-28/30) on the SEA-AD Pilot-MTG
Astral DIA dataset with the entrapment oracle. The written analysis, including the hypotheses that
were tested and rejected, is in `ai/todos/active/TODO-20260728_osprey_mean_best2.md`; the
interactive summary of the numbers is `TODO-20260728_osprey_mean_best2.html` beside it. Nothing
here is specific to mean(best-N) except the default arm-name patterns.

## Configuration

| Variable | Default | Meaning |
|---|---|---|
| `OSPREY_RUNS_DIR` | `D:/test/Pilot-MTG-Tissue-May2026/runs` | where the run directories live |
| `OSPREY_ANALYSIS_OUT` | `ai/.tmp` | where CSV / PNG / HTML products are written |

Products never land in the repo. An arm is read from its
`out.model-diagnostics.data.json` (or the JSON embedded in `out.model-diagnostics.html`), so a run
only needs to have reached its pass-1 model-diagnostics write - it can be killed after that.

## Arm naming

Arms are discovered from directory names, so new cohorts need no code change:

```
seaad-<F>files-libdecoy-r1.0-<pass2mode>-f<F>n<N>[s<SKIP>]   contiguous, or a disjoint slice
seaad-<F>files-libdecoy-r1.0-<pass2mode>-<word><F>n<N>       content-defined (spread17, nopool75)
```

`n0` is the max / best-of-runs baseline and is treated as `N=1` (mean of the best 1 per-run score
IS max). Every arm sharing a cohort label differs only in `N`, so each comparison is a
within-cohort A/B.

`<pass2mode>` is `percolator` for every arm on disk today, and the harvest patterns still read
those. It is a variable rather than a literal because Osprey REMOVED that mode - a new arm runs
`protein-compact` (or whatever `Run-CohortArms.ps1 -Pass2Mode` selects) and is named for it. The
two are not comparable: build a surface from one mode.

## Scripts

Harvest and reporting:

- **`mbn_surface.py`** - the library the rest import (`load`, `metrics`, `classify`, `RUNS`,
  `OUT`) and the main harvest: writes `mbn_surface.csv` plus a four-panel figure.
  `--no-plot` skips matplotlib.
- **`brief.py [filter ...]`** - one line per cohort; the cheap check during a long run.
- **`make_report.py`** - builds the self-contained interactive HTML summary (no CDN; data
  embedded). This is what produced the report committed beside the TODO.

Two-arm A/B (any pair of runs, not just cohort arms):

- **`mdiag_ab.py <baseline_run_dir> <variant_run_dir>`** - A/Bs two runs on the pass-1
  model-diagnostics at BOTH scopes, calibration before sensitivity, plus `modelComposite`,
  per-file targets and per-file entrapment. **Report both scopes**: a change that acts at
  PerFileScoring (peak picking) shows up at RUN scope, while one that acts after aggregation
  (mean-best-N) leaves run scope untouched - quoting only the experiment number confuses "the
  scoring got better" with "aggregation liked the result". Matched-true-FDP uses the same
  convention as `Run-FdrBench.ps1`'s `Get-FdrBenchCalibration` (:217) - MAX qualifying grid point,
  because the curve is noise at tiny counts - so numbers splice into the existing cohort series.
  **It adds one thing the references do not have**: it returns `n/a` instead of a number when the
  only qualifying points are low-count noise, so a weak arm shows a blank where the committed
  cohort series would show a value. **The mdiag curves are also THINNED** (470 points; ~130-200
  discoveries per point at these cohort sizes), so a delta of a few hundred is inside the
  quantization - the tool prints that warning on every run. Its
  "experiment-accepted / run-accepted" ratio is NOT the union-efficiency statistic in
  TODO-20260728 - do not mix them.
- **`pick_disagreement.py <file.pick_candidates.tsv> [astral|stellar]`** - how often the learned
  pick model actually chooses a different candidate than the default product form, split
  target vs decoy. Needs ONE run with `OSPREY_PICK_DUMP_CANDIDATES=1`: both argmaxes are
  recomputed offline from the same candidate set, so there is no confound from two arms having
  scored different populations. Streams the (large) dump group by group, uses the extractor's
  IEEE-754 total-order tie-break (Python's `max` treats -0.0 == +0.0, which is exactly what
  `PeakDataExtractor.cs:361-370` fixes, and 24% of rows have a zero intensity term), and validates
  its own replication against the dump's `is_picked` column - refusing to print a rate on any
  mismatch. Measured 2026-07-31 on one Astral file: the two picks differ on **~44% of contested
  precursors** (target 43.2%, decoy 45.5%) while discoveries move only about **1-3%** across the
  seven arms in TODO-20260727 (-0.3% to -3.5%, one +1.8%) - a ceiling on what pick-model tuning
  can buy. **Do not quote "under 1%"**: that is true only of the single Astral 3-file arm this
  dump came from.

Mechanism:

- **`mechanism.py [--plot]`** - the core one. Union-FDP growth as files accumulate, the marginal
  purity of the last files added, the accepted set resolved by run count `k`, and where
  mean(best-N) moves acceptances. Writes `mechanism.txt`.
- **`kcompare.py [cohort ...]`** - k-structure of named cohorts side by side.
- **`entrap_k.py`** - how selectively false hits sit in the singleton bin.
- **`perfile_audit.py`** - per-file outliers, and how one file's run-level passing changes as the
  cohort around it grows (a clean control: run-level q is computed within a file, so the only
  cross-file channel is the shared trained model).
- **`cohort_split.py`** - pooled QC vs donor files, and acquisition-order halves.

Predictors (all of these ended up NEGATIVE results - see the TODO):

- **`predictor_check.py`** - correlation helpers (`pearson`, `rank`) plus the leakage-vs-gain check.
- **`reservoir.py`**, **`stability.py`**, **`model_health.py`**, **`model_vs_gain.py`** - reservoir
  size, union-normalised scatter, trained-model separation, and their (non-)relationships to the gain.
- **`twofactor.py`** / **`predict.py`** - the two-factor screen
  (`gain% ~= 82.8 * A * B - 1.24`, A = share of accepted false hits resting on one run,
  B = reservoir / union). Both factors come from the MAX arm, so `predict.py` states a prediction
  BEFORE that cohort's mean(best-N) arm exists. Final record: 9 out-of-sample tests, mean error
  2.6 points, systematic ~1.4-point over-prediction. **Use as a large-recovery screen, not as an
  effect-size estimate.**

Running the arms:

- **`Run-CohortArms.ps1`** - serial queue driver. One arm at a time, resumable (an arm whose
  mdiag exists is skipped), kills scoped to the arm's own output directory, and an anchored wait
  sentinel when chaining behind another queue.

Pass the jobs as ONE comma-separated string. `pwsh -File` does not hand a PowerShell array to a
script cleanly, and a bare `-Jobs a b` is rejected outright (deliberately - it used to bind the
second value to the next parameter and run a silently wrong arm).

```powershell
# contiguous cohorts and disjoint slices: jobs are "<files>:<N>[:<skip>]", N=0 is max
pwsh -File ./ai/scripts/Osprey/CohortAnalysis/Run-CohortArms.ps1 -Jobs '40:0,40:2,40:0:30,40:2:30'

# content-defined cohorts: the sampling flags apply to every job, and -TagPrefix names the cohort
pwsh -File ./ai/scripts/Osprey/CohortAnalysis/Run-CohortArms.ps1 -Jobs '17:0,17:2' -EveryNthFile 5 -TagPrefix spread
pwsh -File ./ai/scripts/Osprey/CohortAnalysis/Run-CohortArms.ps1 -Jobs '75:0,75:2' -ExcludePattern pool -TagPrefix nopool
```

Two failure modes cost real machine time when this was built, both now designed out and worth
keeping in mind if you write another driver: an UNANCHORED wait sentinel matches the waiting
script's own log line (so the wait falls straight through and two Osprey runs contend), and a
blanket `Get-Process Osprey | Stop-Process` kills an unrelated queue's in-flight arm.

## Cohort recipes

Arms are produced by `../SEA-AD/Run-SeaAd.ps1` with `-LinkFrom <a completed 82-file run>`, which
adopts the Stage 1-4 caches so only the FDR stage re-runs (~0.38 min/file + ~2.5 min). Cohort
shape comes from `-NumFiles`, `-SkipFirstFiles`, `-EveryNthFile` and `-ExcludePattern`.

**Beware on this dataset**: file name order tracks acquisition order and instrument response drifts
badly across the series (the 7 QC pool injections, which are the same sample, fall from 23,472 to
10,882 passing targets). So a "first N files" cohort is also the earliest and best N files - cohort
size is confounded with cohort quality unless you use the sampling flags. See
`project_sead_pilot_mtg_dataset` in memory.
