# TODO: Osprey --model-diagnostics — null-distribution alignment + decoy-quality alarm

## Status
**MERGED (2026-07-07) into [[TODO-osprey_assumption_failure_detection]]** — retitled
"Osprey FDR assumption diagnostics (equal-chance, stability, entrapment)". This idea (fit
the target mixture to recover the decoy-independent false-target null `f_false`, overlay
the three nulls — decoy / fitted-false / entrapment — in the report, emit a null-alignment
divergence metric, and raise a decoy-quality alarm) is section **A + B** of the
consolidated TODO. It was folded together with the automated assumption-failure detector
because both rest on the *same* non-circular null reference and audit the *same* published
**equal-chance** assumption (diagFDR, Chion et al. 2026; TargetDecoy, Debrie et al. 2023).

This stub is retained only to keep the `[[TODO-osprey_model_diagnostics_null_alignment_decoy_qc]]`
link (from the partial-entrapment active TODO) resolving. See the consolidated TODO for the
full design, gates, and references. Safe to delete once the inbound link is repointed.
