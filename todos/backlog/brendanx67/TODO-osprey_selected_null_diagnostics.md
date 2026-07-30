# TODO-osprey_selected_null_diagnostics.md -- diagnostics for SELECTION-CONDITIONED nulls
# (decoys retained only as pairs of targets that survived a first pass)

## Status
Backlog (brendanx67). Requested by Brendan 2026-07-30, out of the protein-compact / DIA-NN
discussion. Design spec + measured evidence below; no branch yet. The measurement scripts already
exist in `ai/scripts/Osprey/CohortAnalysis/` (see "Tools that already exist").

## The crux
A second pass that **re-derives q on a pool selected by the first pass** is estimating error
against a null chosen for the STRENGTH OF THE TARGETS, not for any independent reason that applies
equally to decoys. Keeping the paired decoy does not repair this: **pairing gives matched COUNTS,
not exchangeability.** A target clears a first-pass cut partly BY BEATING ITS OWN DECOY, so
conditioning on the target's survival conditions its decoy to be the weaker draw - and the decoys
that remain no longer represent the population they are being asked to calibrate.

We have reason to think this is not just an Osprey problem. Osprey hit it first (full Percolator
retrain in pass 2 on targets q<1% plus their paired decoys, ~9% true FDP at 82 files). Wen et al.
2025 Fig 4a shows the telltale for **EncyclopeDIA** (peptide-level estimated FDP jumps and then
sits flat ~1.3% across a 0-5% FDR sweep) and **Spectronaut** (flat ~1.3% within a 0.002% sweep),
while DIA-NN's curve rises with the threshold. A flat curve means the reported q has stopped
discriminating: sweeping the nominal threshold returns nearly the same set, pinned at whatever
true error the first-pass filter admitted.

## THE ORGANISING RULE (Brendan, 2026-07-30) - what decides whether anyone can catch it

**An entrapment oracle can audit a selection rule if and only if the rule is a function of
properties the entrapment peptides POSSESS.** Both failure modes below share one estimator error -
a null conditioned on target survival - but they split on this, and the split decides the detector.

| selection criterion | do entrapment peptides have it? | consequence |
|---|---|---|
| target score / q threshold | YES - entrapment IS a false target | rides into the pool at the false-target rate; oracle SEES the inflation (shows up as the Fig-4a plateau) |
| protein co-membership (>=2 peptides) | NO - no coherent protein | cannot ride along; oracle goes BLIND, no plateau, metrics look fine |
| run count / reproducibility | YES - 48-73% of accepted entrapment has k>=2 | auditable; this is why mean(best-N) can be validated |
| reconciliation / consensus RT | PARTLY - has an RT, but consensus is gated on target q | partially auditable |

Measured on the same 82-file data:
- q-gate at 5% sweeps **1,294 entrapment peptides** into the pool (332 at 1%, 647 at 2%, 2,225 at
  10% - the count roughly doubles as the gate doubles, implied FDP 1.96 / 3.20 / 5.01 / 7.09%).
  Relabel that pool as "1%" and those 1,294 are still inside it: the oracle reports ~5%.
- the >=2-peptide protein stratum contains **37**. A **~35x difference in oracle visibility.**

So the q-gate reductio below models the **EncyclopeDIA / Spectronaut / original-Osprey-pass-2**
failure (detectable, plateaus), NOT protein-compact (undetectable by entrapment, no plateau).
Class A needs the SHAPE test; class B needs provenance + auditability. A suite with only one of
them has a hole exactly where the most elusive method sits.

## Why FDRBench alone will not catch every form

Two independent escape routes, both measured on our own data:

1. **The plateau escapes the point estimate.** A tool can sit under 2% at q=1% - looking
   acceptable - while its q is wildly overconfident and simply flat. Reading only the value AT 1%
   misses it; the SHAPE is the signal.
2. **A protein-level prior escapes the oracle entirely.** `protein-compact` expands to peptides of
   proteins detected with >=2 peptides. Entrapment sequences have no biologically coherent protein,
   so they cannot clear that gate at the rate real proteins do. Measured on the 82-file run
   (`gate_audit.py`): **73.7% of real proteins clear >=2 peptides vs 6.4% of entrapment ones**;
   inside the stratum the ratio is **~1000:1 real:entrapment against a library that is ~1:0.97**.
   The oracle barely samples the population the method expands over, so its 1.51% reading is a
   LOWER BOUND, not an estimate.

**And protein-compact passes the plateau test** (`plateau_check.py`): segment slopes 1.85 / 1.48 /
1.37 / 1.03 / 0.63 - its q still discriminates, it is just inflated ~1.5x. So the two escape routes
are complementary and a suite must cover both. This is the "almost designed to elude the original
FDRBench metrics" property: mild enough to keep a rising curve, structured so the entrapment set
cannot audit it.

## THE ISOLATION EXPERIMENT (Brendan, 2026-07-30) - what exactly is fatal

Three arms at the SAME truncation depth, same scores, same counting estimator, no retraining
(`paired_recal_demo.py`; the pool is simulated from this dataset's measured score histograms with
equal chance holding by construction):

| arm | targets | decoys | accepted @1% | true FDP |
|---|---|---|---|---|
| baseline, no truncation | 400,000 | 400,000 | 9,519 | 0.96% |
| symmetric, kept on own merit | 13,385 | 669 | **9,519** | **0.96%** |
| symmetric + pair completion | 14,028 | 14,028 | **9,519** | **0.96%** |
| **paired to selected targets** | 13,385 | 13,385 | **13,385** | **5.05%** |

**Truncation is harmless. Pair completion is harmless. One-sided SELECTION is fatal.** The third
arm carries essentially the same decoy count as the fourth (14,028 vs 13,385), so it is not how
many decoys you keep - it is WHY each one is there.

Why the harmless arms are harmless: TDC counts right-to-left, so discarding anything below a score
changes no count above it, and T(s)/D(s) are identical for every s >= cut. Pair completion adds
partners BELOW the cut, which cannot change counts above it; those additions skew decoy-heavy down
there, but q is a MINIMUM over lower thresholds, so a worse region below can never pull a q down.

**DESIGN RULE (checkable, unlike "is the null still exchangeable"): an entry may be retained
because of its own score, or because its partner was retained - but NEVER because of whether the
other side of its pair passed a threshold the entry itself was not held to.** Compaction that obeys
this is safe to recompute on, which is the practical payoff: memory savings without calibration
loss. `transfer` satisfies it trivially by never recomputing.

## Severity ladder the suite must span (all measured or published)
| form | mechanism | true FDP at nominal 1% | curve shape |
|---|---|---|---|
| q-gate + re-competition (synthetic reductio) | accept 5%, recompete on paired decoys only | 5.05% reported as 1% | total collapse (everything in the gate passes) |
| retrain on the filtered pool (Osprey's original pass 2; EncyclopeDIA-like) | full model retrain on survivors + pairs | ~9% (82f) | plateau |
| `transfer-compete` | frozen model, competition over a reconciliation-selected pool | 1.96% | tracks, inflated |
| `protein-compact` | frozen model, competition constrained to a target-selected stratum | 1.51% (lower bound) | **tracks - no plateau** |

## Proposed diagnostics (the HTML work)

**D1 - Populate the pass-2 distribution + competition panels.** Today `pass2` carries only the
q-driven half (`fdpViews`, `idYield`, `crossRun`, `perFile`, `model`); `winFraction` and
`densityRatio` exist as keys but are EMPTY, and there is no pass-2 score histogram or class count
(`ModelDiagnosticsData.cs:639` documents the split). So the plots that would show a depleted null
do not exist for the pass where the depletion happens. Build them from the pass-2 competed
population: score histogram by class, paired-coin win fraction, density-ratio plateau. Pass 1 on
the 82-file run reads coin(real) 49.1% / coin(entrap) 50.0% / plateau 0.922 / flatness -0.0065 -
that is what health looks like; we need the same four numbers for pass 2.

**D2 - Null-provenance panel (the new idea, and the one aimed at the crux).** For the population
each pass competes on, report HOW each decoy got there:
- entered independently (its own score cleared a threshold) vs **entered only as the pair of a
  retained target**;
- decoy:target ratio in the competed pool vs in the source pool (depletion factor);
- the same split for entrapment.
A pool where most decoys are passengers is the signature, visible without any oracle. This is the
one diagnostic that would have flagged Osprey's original pass-2 retrain, EncyclopeDIA's global
run, and protein-compact - because it looks at the SELECTION, not at the outcome.

**D3 - Calibration-shape panel (FDP vs threshold), done carefully.** Plot estimated FDP against the
nominal threshold with the diagonal, per-segment slopes, and the overconfidence ratio at the
operating point. **Trap, learned the hard way:** a q-filtered report goes flat when it simply runs
out of pool, and that is NOT a plateau. Osprey's own pass 1 gains 5,864 discoveries from 1%->2%
(slope 0.92, calibrated) and then exactly ONE more out to 5%. A whole-range slope reads that as a
plateau; the correct test is flat FDP **while that same segment is still gaining discoveries**.
`plateau_check.py` implements the segment version.

**D4 - Null-support / granularity KPI near the cutoff.** Report how many decoys remain above the
operating-point score. In the reductio the full competition holds **95 decoys against 9,519
targets** at the 1% cut; inside the gated subset, **1**. A q resting on single-digit decoy support
should be labelled an interval, not a number (diagFDR `D_alpha`, Chion et al. 2026).

**D5 - Oracle-auditability KPI.** For any stratum/selection rule, report the entrapment:target
ratio INSIDE the selected pool against the library ratio. When it diverges (protein stratum:
1000:1 vs 1:0.97), print an explicit warning that **the entrapment oracle cannot audit this
selection** and that the reported FDP is a lower bound. Generalizes past protein grouping to any
future prior (gene rollup, chromatographic grouping, cross-sample structure). The repair for
protein-level priors is protein-level entrapment - a foreign proteome retains real multi-peptide
proteins, with a peptide-count distribution matched to the targets; see the natural Arabidopsis
entrapment work and `fractional-entrapment.md`.

**D6 - Synthetic positive controls, so the detectors are validated not assumed.** Ship the
q-gate reductio as an env-gated diagnostic mode (accept at Q, re-compete on paired decoys only) -
the stratified-competition machinery already exists, so the stratum definition is the only new
part. It provably breaks calibration by construction, exactly as
`OSPREY_BOOST_TARGET_DISCRIMINANT` does for the target-score boost. **Acceptance criterion for the
whole suite: it must flag all four rows of the severity ladder AND leave pass 1 unflagged.**

**D7 - Contribute the harder-to-game plots to FDRBench** (already listed as pressing in
TODO-20260727): run-count histogram + per-k FDP, reproducibility frontier, per-run vs
experiment-wide calibration, plus D3's segment-slope reading. Fig 4a's x=y test is what DIA-NN was
tuned to pass; these are the ones that would separate reproducible signal from single-run
accumulation.

## Tools that already exist (ai/scripts/Osprey/CohortAnalysis/)
- `gate_audit.py` - the >=2-peptide gate rate for real vs entrapment proteins; the D5 measurement.
- `plateau_check.py` - the D3 segment-slope reading, with the frozen-pool guard.
- `null_depletion.py` - pass-1 vs pass-2 class counts + the coin/plateau tripwires; shows the D1 gap.
- `paired_recal_demo.py` - the reductio, driven by this dataset's measured score histograms:
  **+40.6% acceptances on identical evidence, reported 1% while true FDP is 5.05%.**

## Related
- `ai/todos/active/TODO-20260727_osprey_pass2_fdr_default.md` - the validity argument and the
  82-file 4-way (protein-compact 1.51%, transfer-compete 1.96%, percolator ~9%, transfer/pass-1 0.92%).
- [[TODO-osprey_reduced_pool_fdr_calibration]] - "culling is a natural boost"; the same failure
  reached from the library side, and the coin/density tripwires.
- [[TODO-osprey_assumption_failure_detection]] - equal-chance diagnostics + the boost instrument.
- Wen B, et al. Nat Methods 2025;22:1454-1463 (FDRBench; Fig 4a is the plateau evidence).
- Chion, Bruley, Burger 2026 (diagFDR: equal-chance, granularity). Fitzgibbon 2008 (ratio law).
