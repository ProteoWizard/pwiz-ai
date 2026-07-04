# TODO-osprey_assumption_failure_detection.md -- Detect and flag when Osprey's FDR assumptions are silently failing

## Status
Backlog (brendanx67). Not started. Motivated by the 2026-07-03/04 FDR-calibration
sprint. Osprey's target-decoy FDR rests on assumptions that, when violated, fail
SILENTLY and produce confidently-wrong q-values. We now understand the failure
signatures well enough to detect several of them automatically and warn.

## The assumptions that fail silently
1. **Decoys represent the target null.** Target-decoy FDR assumes a false target and
   its decoy are a fair coin. When decoys are systematically weaker than the false
   targets, the decoy count undercounts and q is anti-conservative. The clearest
   example this sprint: **Osprey-generated reverse decoys** whose distribution does not
   match the LEFT (null) half of the target bimodal -- gendecoy entrapment coin ~22% vs
   the fair ~50% of library decoys, driving a ~10x miscalibration. See
   [[project_osprey_libdecoy_vs_gendecoy_calibration]].
2. **The competition coin is fair.** Even with matched marginals, a consistent
   within-pair target advantage collapses the decoy competition (the boost experiment:
   real coin 47%->27% while entrapment held 50%). Marginals cannot see this; the paired
   win fraction can.
3. **The decoy null is not depleted before a later FDR stage.** The pass-2 recalibration
   fails because compaction shrinks the decoy null to an unusable, target-selected set
   (see [[TODO-osprey_pass2_recalibration_fix.md]] and
   [[project_osprey_pass2_recalibration_inflates_fdr]]).

## Detection ideas (start simple, escalate)
1. **Decoy-vs-target-null match (assumption 1).** Fit/estimate the target score
   distribution's null (left) mode -- the decoy-INDEPENDENT reference. Two tiers:
   - Cheap: quantile/KS comparison of the decoy distribution against the target scores
     below a low percentile (a proxy for the null mode). If decoys sit systematically
     lower, warn "decoy scores do not match the target null; FDR may be anti-conservative
     (generated decoys not peptide-like?)".
   - Principled: a pi_0 / mixture decomposition (PeptideProphet / Nesvizhskii style) of
     the target score distribution to isolate the null component, then compare decoys to
     it. This is the decoy-independent estimator the sprint kept converging on -- it is
     also the tie-breaker for the anti-conservatism question and is worth building once,
     here, as the reference oracle the checks compare against. See
     [[feedback_no_unverified_ports]] -- build the verification harness first.
2. **Paired-coin fairness (assumption 2).** When a pairing manifest with entrapment is
   present, compute the entrapment-pair decoy-win fraction; flag deviation from ~50%
   (gendecoy would trip at 22%). Without entrapment, the check is weaker (real pairs are
   confounded by true positives) -- note the limitation rather than over-claim.
3. **Decoy-null size (assumption 3).** At any FDR stage that recomputes q, assert the
   decoy population feeding it is above a usable-size floor; if compaction depleted it,
   warn or hard-fail. Ties directly to the pass-2 fix.

## Policy
- Prefer a prominent WARNING with the diagnostic number over silent proceed. Where the
  output would be silently INVALID that a user might trust (e.g. decoy null depleted to
  an unusable size), escalate to a hard fail per [[feedback_hard_fail_over_warn_proceed]].
- These are calibration self-checks; keep them cheap enough to run on every search, or
  gate the expensive (mixture-fit) tier behind `-d`.

## Relationship to other TODOs
- [[TODO-osprey_diagnostics_fdr_plots.md]] is the human-eye version of the same signals
  (the win-fraction and 4-class density plots); this TODO is the automated detector.
- The pi_0/mixture estimator built here is the reference the plots and the pass-2 fix both
  want. Consider building it once and sharing.

## Gates
- No false alarms on the calibrated cases (Stellar/Astral libdecoy must NOT trip the
  warnings; gendecoy SHOULD).
- `Build-Osprey.ps1 -RunTests -RunInspection` clean; localize user-facing text
  ([[no_localizable_string_in_static]]).

## References
- [[project_osprey_libdecoy_vs_gendecoy_calibration]] (the gendecoy 22% coin / ~10x miscalibration),
  [[project_osprey_pass2_recalibration_inflates_fdr]] (decoy-null depletion),
  this sprint's win-fraction / boost / entrapment-oracle analysis.
