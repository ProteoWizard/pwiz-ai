# TODO-osprey_reduced_pool_fdr_calibration.md -- low-noise FDR: calibrating and assessing q with reduced decoy / entrapment / false-target pools

## Status
Backlog (brendanx67). **Reach goal** -- a line to investigate further "as other things
settle into place." Created 2026-07-09, requested by Brendan, out of the PR #4399
decoy-modeling-diagnostics discussion (density-ratio + paired-coin-collapse). The hard
part is not the math (largely published) but **getting the field to accept it**, so this
is a long horizon, not a next sprint.

**Deliberately kept OUT of `pwiz_tools/Osprey/docs/fractional-entrapment.md`.** That doc
stays focused on the single, easier-to-sell idea: a **10% foreign-species entrapment
overlay** gives valid FDR visibility at ~10% cost, when the field has already accepted the
~2x cost of decoys. That one idea has an immediate, concrete payoff (routine entrapment in
all runs for FDR accuracy visibility) and should not be diluted by the broader program
below. This TODO is where the broader program lives.

## The big idea: assess true signal while introducing less noise
Target-decoy FDR, as practiced, buys statistical confidence with **noise**: an exhaustive
FASTA search deliberately admits a large false-target population so the null is well
populated, and pairs it 1:1 with decoys (2x library) -- and entrapment, when used at all,
adds another 1:1 (Wen et al. 2025's 2-fold-2-fold => ~4x). The reach goal is to **shrink
every null pool** -- fewer decoys, a small entrapment overlay, and (the aggressive step) a
culled/targeted false-target population -- while keeping the FDR estimate **valid**, by
combining (a) ratio-corrected estimators for the shrunken pools with (b) the equal-chance
diagnostics shipped in PR #4399 as the tripwire for when a pool has been shrunk too far.

Two questions frame it.

## Q1 -- accurately calibrated q with target:decoy ratio != 1:1
The ratio correction that makes a fractional **entrapment** overlay valid is the *same*
law for **decoys** (Fitzgibbon, Li & McIntosh 2008; `k = |target|/|decoy|`,
`FIR = (k+1)*(decoys>x)/(total>x)`). Fitzgibbon's Fig 1D shows decoy DBs at 1/2, 1/4, 1/10
of target size are "not highly distinguishable" -- **unbiased at any decoy ratio <= 1**;
only decoy >> target collapses yield. Brendan's own experience (1:4 down to 4:1 holding
up) is exactly this plateau.

- **Feasibility (implementation, not theory).** Osprey's *decoy* q is target-decoy
  **competition** (winner-take-all per pair, Kall/Storey/MacCoss/Noble 2008 lineage),
  which structurally assumes 1:1 (every target needs a decoy competitor). Calibrating at
  r != 1 means a **ratio-corrected counting q** -- literally the `(1 + 1/r)` combined
  estimator already implemented in Osprey's entrapment path. So it is a **port of existing
  code onto the decoy-q path**, not new math.
- **Cost = precision, not bias -- the granularity paradox.** ~10x fewer decoys near the 1%
  cutoff => noisier tail q; worst on Astral/HRAM (sharp separation, sparse null at
  stringent cutoffs, Coute/Bruley/Burger 2020). Read q as an interval; the report should
  flag thin decoy-tail support near the cutoff (diagFDR `D_alpha`).
- **The economics are the whole point.** 10% decoy (calibrate) + 10% entrapment (assess)
  = **+20% library**, vs Wen's 1:1 entrapment (2x) *and* 1:1 decoy (2x) = **4x**. The 4x --
  piling up 4-fold outputs in time and disk -- is why people skip entrapment and eat the
  2x for decoys. +20% could make routine entrapment affordable, which is the thing that
  would actually change practice.

## Q2 -- changing the true-target : false-target ratio (culling the search space)
Prior-knowledge / targeted DIA (SRM's heritage; Aebersold: "stop rediscovering our samples
on every mass spec run") culls the search to higher-confidence targets -- raising the true
fraction (pi0 drops from the exhaustive-FASTA regime toward 1:1 or 9:1). The worry: culling
for signal (less noise) corrupts the true-vs-false statistics.

- **Equal-chance is about false-targets ~ decoys, not pi0 directly** -- so a different
  true:false ratio does not, by itself, break FDR.
- **But *how* you cull can.** The remaining false targets are no longer random FASTA
  sequences; they are *curated peptides that happen to be absent from this sample*,
  selected for being good targets, so they carry better spectra/fragmentation and
  **systematically outscore their reversed decoys** => equal-chance violation =>
  anti-conservative. Structurally this is **the same failure as the target-score boost**
  ([[TODO-osprey_assumption_failure_detection]] SS F, `OSPREY_BOOST_TARGET_DISCRIMINANT`):
  the false-target distribution slides up relative to the decoy null. **Culling is a
  natural boost.**
- **The shipped tools are the tripwire.** The **paired-coin collapse** (Competition tab,
  PR #4399) catches curated-false-targets beating their decoys in the null band exactly as
  it caught the synthetic boost (Stellar libdecoy +3: real coin 47.8% -> 22.7% while
  entrapment held 50%). The **density-ratio plateau height IS the pi0 readout**
  (plateauRatio = false fraction), and its flatness says whether equal-chance still holds
  as you cull.
- **The escape from "need noise to see signal": move the noise into an independent
  entrapment overlay.** Entrapment supplies the false-signal null *without* a large native
  false-target population, so you can cull the native search (less noise, higher yield) and
  still validate FDR against the independent entrapment. Conditions: the entrapment must be
  **representative of the culled difficulty** (matched precursor-m/z distribution, real
  occupied m/z -- else "too easy" and under-reports), and lean on entrapment (independent)
  rather than the culling-depleted decoy tail (granularity).

## Synthesis
Ratio-corrected decoys (calibrate cheaply) + ratio-corrected entrapment (assess cheaply) +
equal-chance diagnostics (coin/density as the tripwire) = a framework to **reduce noise
while keeping a detector for when you have reduced it too far**. That is the concrete answer
to "assess true signal with less noise."

## Experiments (mirror the fractional-entrapment ratio table)
- **A -- decoy ratio (Fitzgibbon table for decoys).** Stellar at decoy:target =
  1:1, 1:2, 1:4, 1:10 with the ratio-corrected q; report (i) entrapment FDP stays ~1%
  (unbiased?), (ii) decoy-tail count at 1% q (granularity), (iii) yield. Direct analog of
  the entrapment-ratio table already in `fractional-entrapment.md`.
- **B -- culling / true:false (natural boost).** Curated-subset libraries at true:false ~
  exhaustive, 1:1, 9:1 (plus a known-absent fraction + 10% entrapment); measure whether the
  coin/density detectors flag the equal-chance drift and whether entrapment FDP diverges
  from decoy q. The `OSPREY_BOOST_TARGET_DISCRIMINANT` instrument is the synthetic
  positive control; culling is its natural counterpart.

## Implementation implications (if pursued)
- A **ratio-corrected counting q for decoys** (`(1 + 1/r)` / lower-bound), reusing the
  entrapment estimator math, as an alternative to target-decoy competition when decoy:target
  != 1:1. Gate behind an explicit non-1:1-decoy mode; keep competition as the 1:1 default.
- A **decoy-tail-support / granularity KPI** (diagFDR `D_alpha`) so the report warns when a
  shrunken decoy pool is too thin near the operating cutoff to trust q as more than an
  interval.
- Reuse of the shipped coin-collapse + density-ratio diagnostics as the equal-chance
  tripwire for any culled/targeted search.

## Why this is a reach, and the near-term wedge
Field acceptance is the obstacle, not the statistics: target-decoy 1:1 competition and the
2x-decoy cost are deeply entrenched, and "cull the search to see signal with less noise"
runs against the exhaustive-search orthodoxy DDA bequeathed to DIA. The **near-term wedge**
is the `fractional-entrapment.md` idea alone: get the field to include a **10% entrapment
overlay in all runs** for FDR-accuracy visibility (10% cost against an already-accepted 2x
decoy cost). Once entrapment is routine and its ratio-correction is trusted, the *decoy*
ratio reduction (Q1) is the natural next step by the identical Fitzgibbon argument, and the
culled-search question (Q2) becomes assessable with the tools already in place.

## References
- Fitzgibbon M, Li Q, McIntosh M. Modes of inference... *J. Proteome Res.* 2008; 7(1):35-39.
  (ratio-corrected FIR; decoy DBs at 1/2, 1/4, 1/10.)
- Kall L, Storey JD, MacCoss MJ, Noble WS. Assigning significance... *JPR* 2008; 7(1):29-34.
  (competition / paired lineage that assumes 1:1.)
- Wen B, Freestone J, Riffle M, MacCoss MJ, Noble WS, Keich U. Assessment of FDR control...
  using entrapment. *Nat. Methods* 2025; 22:1454-1463.
- Bernhardt et al. 2016 (foreign-organism negative control; identifications alone are not
  evidence). Chion et al. 2026 (diagFDR: equal-chance, granularity, comparative reading).
- Related: `pwiz_tools/Osprey/docs/fractional-entrapment.md` (the focused 10% idea),
  [[TODO-osprey_assumption_failure_detection]] (equal-chance diagnostics + the boost
  instrument SS F), [[project_osprey_libdecoy_vs_gendecoy_calibration]], PR #4399
  (density-ratio + paired-coin-collapse, the tripwire tools).
