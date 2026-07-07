# TODO-osprey_assumption_failure_detection.md -- Osprey FDR assumption diagnostics (equal-chance, stability, entrapment)

## Status
Backlog (brendanx67). Not started. **Consolidates the former
`TODO-osprey_model_diagnostics_null_alignment_decoy_qc` (now a stub) into one design** —
they were two facets (report-visualization vs automated-detector) of the same thing:
auditing whether Osprey's target-decoy FDR assumptions actually hold. Motivated by the
2026-07-03/04 FDR-calibration sprint and the 2026-07-06/07 decoy-m/z research night, and
now framed against the published **diagFDR** framework (Chion et al., bioRxiv 2026).

Osprey's target-decoy FDR rests on assumptions that, when violated, fail SILENTLY and
produce confidently-wrong q-values. We now understand the failure signatures — and have
a formal vocabulary for them — well enough to detect several automatically and warn.

## The one assumption underneath (equal-chance) + its two support conditions
The classical target-decoy null (Elias & Gygi; Käll et al.; Gupta & Pevzner) rests on the
**"equal-chance" assumption**: an incorrect match is equally likely to land on a decoy or
on a false target. diagFDR (Chion et al. 2026) formalizes this and gives pipeline-agnostic
diagnostics; the **TargetDecoy** R package (Debrie et al., JPR 2023) provides score-level
equal-chance checks; **Chan, Madej, Chung & Lam (JPR 2025)** showed template decoys in
*predicted* spectral libraries (our Carafe setting) systematically violate it.

The assumptions that fail silently in Osprey:
1. **Decoys represent the target null (equal-chance on marginals).** When decoys are
   systematically weaker than real false targets, the decoy count undercounts and q is
   anti-conservative. Sprint example: **Osprey-generated reverse decoys** whose
   distribution does not match the null (left) half of the target bimodal — gendecoy
   entrapment coin ~22% vs the fair ~50% of library decoys, ~10x miscalibration
   ([[project_osprey_libdecoy_vs_gendecoy_calibration]]). Research-night example: any
   **m/z-manipulated decoy** (shift / permute) is separable from real false targets on
   MS1 → equal-chance violation → anti-conservative (see the night report; Bernhardt 2016
   showed the identical effect for a fragment-m/z-shift decoy on HRAM).
2. **The competition coin is fair (equal-chance on pairs).** Even with matched marginals,
   a consistent within-pair target advantage collapses decoy competition (the boost
   experiment: real coin 47%->27% while entrapment held 50%). Marginals cannot see this;
   the paired win fraction can.
3. **The decoy null is populated where FDR is read (stability / granularity).** diagFDR's
   **"granularity paradox"** (Couté, Bruley & Burger, Anal Chem 2020): as scoring sharpens
   target-decoy separation, so few decoys remain near stringent cutoffs that the FDR
   estimate becomes numerically fragile — worsened by high-resolution instruments. Osprey
   also depletes the decoy null structurally: pass-2 compaction shrinks it to a
   target-selected set ([[TODO-osprey_pass2_recalibration_fix.md]],
   [[project_osprey_pass2_recalibration_inflates_fdr]]).

## Detection ideas (start simple, escalate)

### A. Shared decoy-independent null reference (build once, used by B/C and the pass-2 fix)
Fit the TARGET composite-score distribution as a 2-component mixture
`f_target = pi_true*f_true + (1-pi_true)*f_false` (EM; Gaussian or skew-normal), take the
lower-mean component as **f_false** — a decoy-INDEPENDENT estimate of the null. **Must be
non-circular**: do NOT define f_false as the decoys, or the check is vacuous. Guard against
ill-conditioning when separation is poor (min component weight, identifiability check,
fallback "insufficient separation to assess"). This is the pi_0/mixture reference the
sprint kept converging on; the plots, the alarm, and the pass-2 fix all want it.

### B. Equal-chance null alignment (marginals) — report overlay + metric + alarm
- **Overlay the (up to) three nulls** — decoys, fitted f_false, entrapment (if present) —
  area-normalized on the composite (and optionally per-feature) chart in
  `--model-diagnostics`, generalizing the existing "decoy normal" overlay so misalignment
  is obvious at a glance.
- **Divergence metric**: decoy-vs-f_false (headline), plus decoy-vs-entrapment and
  f_false-vs-entrapment when available. KS / Wasserstein / symmetric-KL on binned
  densities, or a cheaper interpretable location+scale mismatch (delta-mean/delta-std in
  composite sigma). Also port diagFDR's **q-band decoy-fraction** check (decoy fraction
  within low-confidence q bands should be ~0.5 under equal-chance; `|delta_balance|>0.15`
  flags imbalance) and stratify by charge / precursor length / intensity to localize where
  equal-chance fails (our mass-defect finding: charge-dependent decoy anomalies are real).
- **Alarm**: past a calibrated threshold, KPI badge + console warning on the FDR path:
  "decoys poorly match the false-target population; FDR likely anti-conservative." Fires on
  ordinary runs with no entrapment library.

### C. Paired-coin fairness (pairs)
When a pairing manifest with entrapment is present, compute the entrapment-pair
decoy-win fraction; flag deviation from ~50% (gendecoy trips at 22%). Without entrapment
the check is weaker (real pairs confounded by true positives) — note the limitation.

### D. Stability / granularity + decoy-null size
- **Decoy-tail support / cutoff fragility** (diagFDR D_alpha and the sensitivity curve):
  count decoys in a neighborhood of the operating cutoff; report whether small
  perturbations (tie-breaks, score jitter, alternative decoy realizations) move the cutoff
  and change the accepted list. Small support → "granular regime; threshold fragile"
  warning. Especially relevant on Astral/HRAM.
- **Decoy-null size floor**: at any FDR stage that recomputes q, assert the feeding decoy
  population is above a usable-size floor; if compaction depleted it, warn or hard-fail
  (ties to the pass-2 fix).

### E. External entrapment (the oracle) — comparative, and representative
When entrapment is present, report `FDP_entrap(alpha)=E_alpha/T_alpha` read
**comparatively** (Wen [22]; diagFDR): **`FDP_entrap >> alpha` = strong anti-conservative
evidence** (alarm); `FDP_entrap ≈ alpha` is consistent-but-not-proof (optimistic decoy +
pessimistic entrapment can cancel). CRITICAL (research-night finding): the entrapment must
be **representative and independent of the decoy construction** — isobaric / mass-matched,
at real occupied precursor m/z — or it colludes with a manipulated decoy and hides the
anti-conservatism (the shift-both trap). Do not let the entrapment share the decoy's m/z
manipulation.

## Policy
- Prefer a prominent WARNING with the diagnostic number over silent proceed. Where output
  would be silently INVALID that a user might trust (e.g. decoy null depleted to an
  unusable size), escalate to a hard fail ([[feedback_hard_fail_over_warn_proceed]]).
- Diagnostics must not abort a run for the *soft* checks (B/C/E display); keep them cheap
  enough to run on every search, or gate the expensive mixture-fit tier behind `-d`.
- Localize user-facing text ([[no_localizable_string_in_static]]).

## Gates
- No false alarms on calibrated cases: Stellar/Astral **libdecoy must NOT trip**;
  **gendecoy SHOULD** (~11.8% FDP / 22% coin). Calibrate thresholds on these existing runs
  before wiring any warning.
- `Build-Osprey.ps1 -Configuration Debug -RunTests -RunInspection` clean.

## Feasibility
Much of the raw material already exists: `ScoreHistogram` carries per-class composite
histograms (target/decoy/p_target/p_decoy) + a decoy Gaussian fit (`DecoyMean`/`DecoyStd`);
the fit + metrics are pure functions over the best-per-precursor composite scores already
reduced in `ModelDiagnosticsData.cs`. Scope: `ModelDiagnosticsData.cs` (mixture fit +
divergence + stability metrics), `model-diagnostics-template.html` (null overlays, KPIs,
stability view), a console warning in `ModelDiagnosticsReport` / the FDR path.

## Open questions / design decisions
- f_false estimation: independent 2-component EM on targets (non-circular, proposed) vs a
  decoy-anchored decomposition (circular — display only). Parametric family (Gaussian vs
  skew-normal)? Poor-separation guard = "cannot assess", not a spurious alarm.
- Alarm surface + severity: KPI badge always; console warning when degenerate; hard-fail
  only on genuinely-invalid (null depletion).
- How much of diagFDR to port directly (its concepts are pipeline-agnostic; the R package
  is a reference implementation to mirror, not to depend on).

## References
- Sprint/night data: [[project_osprey_libdecoy_vs_gendecoy_calibration]] (gendecoy 22% coin
  / ~10x miscalibration), [[project_osprey_pass2_recalibration_inflates_fdr]] (null
  depletion), [[project_osprey_natural_entrapment]] + `ai/.tmp/night-report-decoy-mz-collision.md`
  (equal-chance violation by m/z-manipulated decoys; MS1 mechanism; the anagram reframe).
- Related Osprey TODOs: [[TODO-osprey_diagnostics_fdr_plots.md]] (human-eye version of B/C),
  [[TODO-osprey_pass2_recalibration_fix.md]] (the pass-2 depletion in D), the partial-
  entrapment PR #4380 + `pwiz_tools/Osprey/docs/fractional-entrapment.md` (the E oracle).
- Literature (the formal basis): diagFDR — Chion, Godmer, Douché, Matondo, Giai Gianetto,
  bioRxiv 2026 (doi:10.64898/2026.04.16.718468); TargetDecoy — Debrie et al., JPR 2023;
  template-decoy equal-chance violation — Chan, Madej, Chung, Lam, JPR 2025; granularity —
  Couté, Bruley, Burger, Anal Chem 2020; decoy-FDR correctness — Freestone, Noble, Keich,
  JPR 2024; entrapment — Wen et al., Nat Methods 2025; Bernhardt et al. (Biognosys) 2016
  decoy-validation poster (E. coli negative control; m/z-shift decoy underestimates FDR).
