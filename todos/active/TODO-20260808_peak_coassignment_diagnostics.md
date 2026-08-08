# osprey: Surface single-peak multiple-ID co-assignment in --model-diagnostics

## Branch Information
- **Branch**: `Skyline/work/20260808_peak_coassignment_diagnostics`
- **Base**: `master`
- **Created**: 2026-08-08
- **Status**: In Progress
- **GitHub Issue**: [#4522](https://github.com/ProteoWizard/pwiz/issues/4522)
- **Module**: `osprey`
- **PR**: (pending)

## Objective

DIA search can assign two IDs to a single chromatographic peak without sequence-specific
differentiating evidence. Entrapment makes this measurable: an entrapment peptide sharing a peak
with a better-scoring target is a demonstrated false co-assignment.

Measured on a 40-file Astral cohort (TDP-43 plasma-EV, q <= 0.01), the target background sits at
4.3-5.1% of accepted precursors across all seven library variants -- roughly 1,200 accepted target
IDs per run on a peak a better-scoring same-mass precursor already explains. Entrapment is enriched
4.0-6.6x over that background in every arm.

This issue asks only to **surface the effect in the `--model-diagnostics` report**. What to do about
it is a separate question.

A precursor pair "shares a peak" when it is in the same run, at the same apex RT (+/- 0.05 min), and
within +/- 0.01 Da in precursor mass. No knowledge of the sequence relationship is required -- the
metric is pure geometry, which is why it finds relationships nobody thought to look for.

## Tasks

- [ ] Locate the Stage 5 `--model-diagnostics` report generation and the per-file apex RT source
- [ ] Confirm which RT source is the true per-run detection (the prototype used pass-1 harvest apex
      RT, which is post-reconciliation extraction coverage -- presence of a peak there is not
      independent detection, though the RT values themselves are real)
- [ ] Compute co-assignment: % of accepted precursors sharing a peak with a better-scoring same-mass
      precursor, reported separately for targets, entrapment, and decoys
- [ ] Report the enrichment ratio entrapment/target (the interpretable, density-controlled quantity)
- [ ] Add a dRT histogram for co-assigned pairs, separating same-feature jitter from chance
      co-elution
- [ ] Add a listing of the worst offenders (co-assigned pairs ranked by score gap) -- this is what
      makes the panel actionable rather than merely informative
- [ ] Decide and document the RT tolerance; make the choice visible in the panel rather than baked in
- [ ] Regression test (see below)

## Caveats to carry into the implementation

- **RT tolerance sensitivity.** Entrapment is enriched at every tolerance tested, but the magnitude
  depends on it: 2.3x at +/-0.01 min, 2.9x at +/-0.02, 5.7x at +/-0.05, 4.3x at +/-0.10, 3.4x at
  +/-0.25. The +/-0.05 figure is physically motivated (it matches the observed same-feature apex
  jitter of 0.046 min) but it also maximises the ratio, so the honest headline is a range. The dRT
  histogram makes the choice visible.
- **The set-wise isobaric gate reduces entrapment co-assignment but not the target background**
  (issue comment). It moved entrapment enrichment 6.6x -> 3.7x (shuffle) and 5.7x -> 4.2x (foreign),
  and moved the target background not at all. That gate has since been reverted as too broad, so
  shipping libraries sit at the `-no-il` row (I/L filter only), where entrapment enrichment is
  5.7-6.6x.

## Regression Test

- **Test name**: (filled in once written)
- **Test project**: Osprey.Test
- **Fails on master**: (pending)
- **Passes on fix**: (pending)

## References

- Prototype: `ai/scripts/Osprey/Entrapment/peak_coassignment.py` (takes a `pass1_entrap.py` arm JSON)
- Measurement series: `ai/todos/active/TODO-20260801_decoy_similarity_gate.md`

## Progress Log

### 2026-08-08 - Session Start

Starting work on this issue. Created branch and TODO; next step is locating the
`--model-diagnostics` report generation and the per-file apex RT source in Osprey.
