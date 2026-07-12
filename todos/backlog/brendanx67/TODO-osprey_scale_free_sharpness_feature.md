# TODO-osprey_scale_free_sharpness_feature.md -- Evaluate a scale-free (shape-only) peak_sharpness feature

## Status
**Backlog (created 2026-07-11).** Spun off from the intensity log-conditioning fix
([[TODO-osprey_fdr_entrapment_collapse_investigation]] / the pwiz PR that log-conditions
peak_apex/peak_area/peak_sharpness). Brendan flagged that `peak_sharpness` is conceptually a
peak-SHAPE descriptor, which we normally assess at linear scale -- so logging it needs more
justification than apex/area. This TODO is to evaluate a cleaner design that makes sharpness a
true scale-free shape feature.

## The issue
`peak_sharpness` as currently defined (Osprey.Scoring/PeakShapeCalculators.cs `PeakSharpnessCalc`,
Rust pipeline.rs:5212-5234) is the mean of the left/right slopes on the reference XIC:
`(apexIntensity - edgeIntensity) / dt`. That is an ABSOLUTE slope (intensity per minute), so it
scales ~linearly with peak intensity -- a 2x more intense peak of identical shape has ~2x steeper
slopes. So it is really an intensity-MAGNITUDE feature, not a shape descriptor. This is why it
participated in the intensity hijack (standardized z ~= 190 on a lone high-intensity DIA
interference) and why the log fix conditions it along with apex/area. The log is correct for the
feature AS DEFINED, but it treats a "shape" feature as a magnitude feature.

## The idea
Define a **scale-free** sharpness that isolates shape from intensity, e.g. normalize the slope by
the apex: `sharpness_rel = mean_slope / apex` (equivalently the fractional intensity drop per
minute). This is intensity-independent (a sharp peak has the same value at any intensity), stays
at LINEAR scale (no log needed -- it is already bounded/well-scaled), and gives the SVM a genuine
shape signal rather than a second copy of intensity.

## Tasks
- [ ] Define the scale-free form (slope/apex, or an alternative like FWHM-based sharpness) and its
  edge/zero-apex guards. Keep it cross-impl parity-safe (C# + Rust identical).
- [ ] A/B it against the log-conditioned absolute-slope sharpness on the SEA-AD entrapment sets:
  does the scale-free feature separate target/decoy better (feature contribution in the model
  diagnostics) and hold or improve the entrapment-oracle FDP? Does it change the +IDs the log fix
  recovered?
- [ ] If it wins, replace `peak_sharpness` (calculator + parquet feature + Rust) and re-bless the
  regression golden; if neutral, keep the logged absolute-slope form and close this out.
- [ ] Coordinate with the intensity-normalization work ([[TODO-osprey_intensity_batch_normalization]])
  -- both are "condition the intensity-scale PIN features so the linear SVM sees the right signal."

## References
- Log-conditioning fix: pwiz PR (Skyline/work/20260711_osprey_intensity_log_conditioning) +
  [[TODO-osprey_fdr_entrapment_collapse_investigation]] (root cause + validation).
- Skyline analog: `MQuestShapeCalc` / shape features assessed at linear scale.
