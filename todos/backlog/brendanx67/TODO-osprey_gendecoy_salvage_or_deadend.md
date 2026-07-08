# TODO: Osprey generated-decoys — salvage or declare a deadend

## Owner / status
Brendan. Deferred to a concerted sprint (raised 2026-07-08). Do NOT turn the option
off before this decision.

## The question
Osprey can build its own decoys ("gendecoy", reverse) when the library has none, OR use
library-supplied decoys from a predictive model ("libdecoy": Carafe / Prosit /
AlphaPeptDeep). The FDRBench entrapment oracle shows gendecoy is **badly miscalibrated**
(~12–16% true FDP at a claimed 1% q on Stellar/Astral), while libdecoy is near-calibrated
(~0.8–1.3%). See [[project_osprey_libdecoy_vs_gendecoy_calibration]].

Decide: **can the generated decoys be fixed** to match the target false distribution
(so gendecoy is honest), or is in-tool decoy generation a **deadend** — in which case
Osprey should always require decoys from a predictive model and the gendecoy option is
removed / hard-gated.

## Why it matters / what to weigh
- The q-value clamp work exposed how gendecoy's miscalibration inflates the apparent
  impact of FDR changes: the clamp drops ~5.4% on the gendecoy `stellar` regression vs
  ~0.9% (--protein-fdr) / ~0 (no --protein-fdr) on libdecoy — the recommended path.
- Candidate salvage angles (from prior notes): honest MS1 power for foreign/predicted
  decoys ([[TODO-osprey_foreign_decoys_honest_ms1_power]]); decoy-quality alarms /
  null-alignment diagnostics ([[TODO-osprey_assumption_failure_detection]]); re-predicting
  decoy spectra+RT from the same model instead of mechanical reversal.

## Related change (separate, do when convenient)
Move the **Osprey regression test off the gendecoy `stellar` dataset onto the libdecoy
path** (the recommended one). The regression's purpose is parity/determinism so gendecoy
is still valid today, but it should exercise the path we actually recommend. Not part of
any q-value PR.
