# TODO: Osprey --model-diagnostics — null-distribution alignment + a decoy-quality alarm

**Status**: Backlog (feature idea — design captured, NOT a coding task yet)
**Priority**: High-value (turns the decoy-quality insight into an automatic alarm; could fire on
  ordinary runs with no entrapment library)
**Created**: 2026-07-06
**Requested by**: Brendan
**Scope**: `pwiz_tools\Osprey\Osprey.FDR\ModelDiagnostics\ModelDiagnosticsData.cs`
  (score histogram + a new mixture fit + a divergence metric),
  `Osprey.Tasks\ModelDiagnostics\model-diagnostics-template.html` (composite/density charts),
  possibly a console warning in `ModelDiagnosticsReport` / the FDR path.
**Related**: extends the composite/per-feature distributions in PR #4377; sibling to
  [[TODO-osprey_model_diagnostics_training_pool_distributions]]. Calibration data already exists
  (the libdecoy vs gendecoy runs; see [[project_osprey_libdecoy_vs_gendecoy_calibration]]).

## Why this exists — three nulls that must agree

The target composite-score distribution is, by construction, a two-component mixture:

    f_target(s) = pi_true * f_true(s)  +  (1 - pi_true) * f_false(s)

- **f_true** — true targets (correct IDs; the high-scoring population we keep).
- **f_false** — false targets: random matches to an absent or undetectable peptide.

The load-bearing observation: **f_false, the decoy distribution, and (when present) the
entrapment distribution are three independent estimates of the SAME thing** — the score
distribution of random searching. A faithful FDR requires them to coincide. When they don't,
the null used for FDR (the decoys) is not modeling the real false-target population, and the
reported q-values are wrong — exactly the **gendecoy** case (Osprey-generated decoys →
combined FDP ~11.8% at a reported 1% q, vs ~0.9% for library decoys). The current report makes
that *visible* if you know to look; this TODO makes it *measured and alarmed*.

**The prize:** estimating f_false from the target mixture directly gives a **decoy-quality
check that needs no entrapment library** — it can fire on any normal run. When entrapment IS
present, it becomes a stronger three-way consistency test (and entrapment is the ground-truth
null to calibrate against).

## The idea

1. **Fit the target mixture** to recover f_false (and f_true) from the target scores.
2. **Overlay the (up to) three nulls** — decoys, fitted target-false, entrapment (if present) —
   area-normalized on the composite (and optionally per-feature) chart, so misalignment is
   obvious at a glance. (The chart already draws a "decoy normal" overlay; this generalizes it.)
3. **Emit a null-alignment metric** — a divergence between the estimated nulls (esp.
   decoy vs target-false) — shown as a KPI and, past a calibrated threshold, raised as an
   **alarm**: "decoys poorly match the false-target population; FDR is likely anti-conservative
   (degenerate)." A console warning on the FDR path would let it catch degenerate runs even for
   users who never open the HTML.

## Statistical approach (candidates — pick during design)

- **Recovering f_false (must be non-circular — don't define f_false AS the decoys, or the
  check is vacuous):**
  - 2-component fit on the TARGET scores alone (EM; two Gaussians, or skew-normals to allow
    asymmetry) → take the lower-mean component as f_false. Independent of the decoys, so
    decoy-vs-f_false is a real test.
  - Or a semi-parametric decomposition (e.g. fit pi_true and a parametric f_true, treat the
    residual as f_false), à la PeptideProphet / mixture-model FDR.
  - Caveat: the composite is trained to separate, so the two target components can overlap
    heavily and EM may be ill-conditioned when separation is poor — needs guards (min
    component weight, identifiability checks, fallback to "insufficient separation to fit").
- **Divergence metric (decoy vs f_false; also decoy vs entrapment, f_false vs entrapment):**
  - Distribution distance: KS statistic, Wasserstein/earth-mover, or symmetric KL on the
    binned densities.
  - Or a cheaper, interpretable location+scale mismatch (delta-mean / delta-std in composite
    units) — often enough to separate gendecoy from libdecoy and easy to explain.
  - Report the pairwise matrix; the headline alarm keys on decoy-vs-f_false (and decoy-vs-
    entrapment when available).

## Feasibility

Much of the raw material is already in the report:
- `ScoreHistogram` already carries per-class composite histograms (target / decoy / p_target /
  p_decoy) plus a decoy Gaussian fit (`DecoyMean` / `DecoyStd`). So the null overlays are mostly
  a rendering + one mixture-fit away.
- The fit + metric are pure functions over the best-per-precursor composite scores already
  reduced in `ModelDiagnosticsData` — no new pipeline data required.
- Runs for calibration exist: **gendecoy** (should trip the alarm) and **libdecoy** (should
  not), on both Stellar and Astral; use them to set the threshold and prove the metric
  discriminates before wiring any hard warning.

## Metric + threshold
Calibrate on the existing runs so the alarm fires on gendecoy (~11.8% FDP) and stays quiet on
library decoys (~0.9%). Prefer a threshold with a clear interpretation (e.g. "decoy mean is
> N composite-sigma below the estimated false-target mean" or "KS p < x"), and start as a
*warning* KPI (visible, non-fatal) before considering anything stronger.

## Open questions / design decisions
- **f_false estimation:** independent 2-component EM on targets (proposed, non-circular) vs a
  simpler decoy-anchored decomposition (circular — avoid for the core check, maybe fine for
  display). Which, and what parametric family (Gaussian vs skew-normal)?
- **Where FDR "lives":** do the alignment check on the composite score (where q is computed) —
  primary. Per-feature null alignment is a possible bonus view but not the alarm signal.
- **Entrapment's role:** when present, is it the ground-truth null to calibrate the metric
  against (decoy-vs-entrapment), or just a third overlay? (Both are cheap; likely both.)
- **Alarm surface + severity:** report KPI + colored badge always; console warning on the FDR
  path when degenerate; never hard-fail (diagnostics must not abort a run) — consistent with the
  existing feedback that diagnostics stay non-fatal.
- **Poor-separation guard:** what to show when the target mixture can't be identified (low
  separation / tiny true fraction) — "cannot assess" rather than a spurious alarm.

## Why worth doing
It converts the qualitative "the decoys don't look like the false targets" into a quantitative,
always-on decoy-quality gauge — the kind of guardrail that would have flagged the gendecoy
degeneracy automatically, and would warn future users when their decoy model silently makes the
reported FDR meaningless. Squarely the transparency mission of --model-diagnostics.
