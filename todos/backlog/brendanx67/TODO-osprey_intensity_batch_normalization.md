# TODO-osprey_intensity_batch_normalization.md -- Per-run intensity normalization (median-of-medians in log space) before the Percolator standardizer

## Status
**Backlog (created 2026-07-11).** Deferred follow-up to the shipped intensity log-conditioning fix
([[TODO-20260711_osprey_fdr_entrapment_collapse_investigation]] / pwiz `Skyline/work/20260711_osprey_intensity_log_conditioning`,
maccoss/osprey PR #53). The `log10(x+1)` conditioning that shipped removes the heavy-tail hijack and
is the validated core. This TODO captures the SECOND, deferred lever Brendan specified: normalize each
intensity feature by a per-run scale before the log, so the experiment-wide Percolator model compares
runs on a common intensity scale.

## Why (the recalibration principle)
RT, mass, and intensity are all per-run-variable MEASUREMENTS that become better FEATURES once made
consistent across runs. Osprey per-run-calibrates RT and mass but currently feeds intensity to the
EXPERIMENT-WIDE Percolator model un-normalized, so the single global standardizer sees intensity
variance = between-run (batch confound) + within-run (where the weak true/false signal lives).
Un-normalized, the between-run component swamps the within-run signal, so a peak's standardized
intensity largely encodes "which run" rather than "is it real". Quantification already normalizes
(median / TIC) post-scoring; scoring should too, for the same reason.

log10(x+1) alone (shipped) collapses the per-run intensity STD/tail spread from ~47% (raw) to ~4%
(log) -- the decisive fix that recovered file 006. It does NOT remove the per-run OFFSET: residual
cross-run log-median spread on the single-batch SEA-AD set is only 0.139 log units = 0.17 pooled-SD
(small -> why log alone sufficed there). But the offset is SYSTEMATIC per run and scales with drift:
a 10x cross-run intensity drift (routine across batches / months) = 1.0 log unit = ~1.22 pooled-SD of
systematic bias on the affected runs. That is the regime this normalization is for.

## Proposed change (Option B -- Stage-5 conditioning, driven by a calculator flag)
Locked decisions (Brendan, 2026-07-11):
- **Option (B): ALL intensity conditioning at Stage-5 feature-prep.** The parquet keeps RAW features,
  so changing the conditioning needs NO re-score (existing parquets are reusable). One conditioning
  site, upstream of the generic (feature-agnostic) `FeatureStandardizer`.
  (NOTE: the shipped log-only fix does the opposite -- it conditions in the calculator, so the parquet
  now stores the logged value. Moving to median-of-medians means shifting the conditioning OUT of the
  calculator to Stage-5 feature-prep and reverting the parquet columns to raw, since the per-run
  median needs every run's raw distribution. Plan the migration explicitly.)
- **Calculator declares a flag** (e.g. `IsIntensityScaleFeature` / `NormalizeToMedianTic`) on
  `PeakApexCalc` / `PeakAreaCalc` / `PeakSharpnessCalc`. The calculator returns the raw physical
  value; it only advertises the feature's NATURE. Stage-5 feature preparation reads the flag and
  conditions the flagged features using cross-run statistics (the one place that has both the raw
  features and every run's scale).
- **Median-of-medians normalization, in LOG space.** Per flagged feature: `L = log10(x+1)`; per-run
  median `m_run = median(L over that run)`; reference `M = median over runs of m_run`; conditioned
  `L' = L - m_run + M`; then standardize. This is TRUE median normalization -- recenter every run's
  median onto the experiment median-of-medians. It keeps values in the NATIVE log-intensity scale
  (just shifted), which Brendan prefers over a TIC ratio (fraction-of-TIC produces unintelligible
  magnitudes with no intrinsic meaning). Median-of-medians is computable at Stage-5 straight from the
  existing parquet column -> zero plumbing, no re-score.
- **No command flag yet.** Hardcode median-of-medians for now. Revisit later: (i) a
  `--intensity-norm {median|tic}` flag; (ii) whether median-of-medians can introduce bias (runs with
  very different true-ID depth have different median-log-intensity for legitimate reasons, so
  recentering could over/under-correct). Open sub-question: TIC vs median-apex vs
  median-of-confident-IDs as the per-run scale.

Note vs Skyline: Skyline's `MQuestIntensityCalc` puts log10 in the calculator, but mProphet is
per-document, so it has no cross-run-scale problem to solve. Osprey's experiment-wide Stage-5 model
does -- which is what pushes the conditioning (and the flag) out to Stage 5.

## Validation -- this single-batch set will NOT show it
`L' = L - m_run + M` is a UNIFORM per-run additive shift in log space = a uniform per-run score
offset, so run-level q (per-file IDs) is INVARIANT to first order -- 006's 34,165 and the other
per-file counts will NOT move from adding median-norm on the SEA-AD set. Its effect flows only through
(a) the experiment-wide ranking and (b) model TRAINING (stripping per-run offset variance so
intensity's learned weight reflects true-vs-false, not run identity). On this single-batch set the
offset is only ~0.17 SD, so even those are small.

**Must be validated on CROSS-BATCH / instrument-drift data** (offset large -> visible), NOT on this
single-batch set. Correct targets: experiment-wide FDR calibration + the trained intensity feature
weight/stability, not run-level IDs. On the single-batch set the only expected result is "no
regression + a small cleanup of the intensity weight."

## Harness note (important)
The median-norm test must be done IN-CODE (the Stage-5 conditioning: per-file median pre-pass + apply
at the direct/streaming train+score points), NOT by baking pre-conditioned values into copies of the
scores parquets. Osprey's Parquet.Net reader CANNOT read pyarrow-rewritten parquets -- it fails to
parse the `entry_id`/`is_decoy` columns and skips every row group (-> "0 total scored entries"),
regardless of row-group count / compression / dictionary-encoding / format-version settings. So the
parquet-baking shortcut is a dead end; implement the in-code Stage-5 pre-pass.

## Related
- [[TODO-20260711_osprey_fdr_entrapment_collapse_investigation]] -- the root cause + the shipped log-conditioning core (this is its deferred robustness follow-up)
- [[TODO-osprey_scale_free_sharpness_feature]] -- redesign peak_sharpness as a scale-free (slope/apex) shape descriptor that stays linear, complementary to conditioning the current magnitude feature
- [[TODO-osprey_calibrator_selection_review]] -- the Pass-1 seed / calibrator-selection lever (intensity pinned low, looser first cutoff), complementary to feature conditioning
