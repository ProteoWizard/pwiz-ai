# TODO: Osprey --model-diagnostics — null-distribution alignment + decoy-quality alarm

## Status
**COMPLETED — the concrete "night-ready slice" (the Storey non-parametric density-ratio plot)
shipped as #4399** (merged 2026-07-09, "Added a non-parametric null-alignment density-ratio plot
to model diagnostics"). This was already a consolidation stub (below); moved to completed under
its original slug so the inbound `[[...]]` links keep resolving. Any remaining
assumption-diagnostics scope lives in [[TODO-osprey_assumption_failure_detection]].

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

## Night-ready slice (2026-07-08, with Brendan + Mike) — Storey non-parametric ratio plot
A bounded, TeamCity-green-PR-sized carve-out of §B, teed up for a `/night-session`:
`ai/.tmp/handoff-20260708-osprey-model-diagnostics-two-prs.md` (PR 2, first priority).
- **Storey's non-parametric null check** (Mike, 2026-07-08): ratio of the points between
  targets and decoys on the left/null side is a **horizontal line** that rises at real hits;
  a non-flat left side = decoy/false-target mismatch — no parametric fit needed (the
  decoy-normal overlay misfits the skewed decoys, screenshot `...195912.png`).
- **Decided scope:** a new plot on the **Density tab under "Score density by class"** with
  exactly **two density-ratio lines — target:decoy and p_target:p_decoy** (the latter ≈1 flat,
  the matched-null reference: entrapment ≈ entrapment-decoy, screenshot `...200147.png`) +
  a **left-side flatness KPI**. NO console alarm, NO parametric f_false, keep the normal
  overlay. Validation oracle = libdecoy (flat) vs gendecoy (non-flat). Diagnostics-only
  (golden unchanged). Full design in the handoff.

**Stashed here (2026-07-07):** the `OSPREY_BOOST_TARGET_DISCRIMINANT` instrument — a synthetic
equal-chance violation that is invisible to the entrapment oracle, useful as a positive-control
test fixture for these null-alignment / decoy-QC detectors — was lifted out of the
`--fdrbench-pass both` PR and written up in **section F** of
[[TODO-osprey_assumption_failure_detection]] (with recovery pointer to git tag
`osprey-stash/boost-target-discriminant`).
