# mean(best-N) programme: recommendations by priority

Status 2026-08-01. Evidence base: SEA-AD Pilot-MTG (82 files, dataset 1) and TDP-43 Plasma
EV-Quant (163 files, dataset 2), plus a pass-1 audit of the shared entrapment library.
Detail: `ai/todos/completed/TODO-20260728_osprey_mean_best2_{seaad,tdp43,summary}.html`.

---

## P1 - Fix entrapment / decoy generation similarity ([#4515](https://github.com/ProteoWizard/pwiz/issues/4515))

**First because it corrupts the oracle every other decision is measured against.** Every FDP
number in this programme - both datasets, every pass-2 mode comparison, the frontier gate in P3 -
is calibrated against an entrapment population that is contaminated by an unquantified amount.

**Measured on BOTH datasets** (pass-1 accepted set, experiment q <= 1%). The paired entrapment
count reproduces the mdiag's own `crossRun` accepted-entrapment count exactly on both
(174 == 174, 130 == 130), so this is the official accepted set, not a differently-scoped one:

| | SEA-AD 82f | TDP-43 163f |
|---|---|---|
| filter-rejectable (near-copy) | **28.7%** | **26.9%** |
| near-copy: source target also accepted | **54.0%** | 42.9% |
| dissimilar: source target also accepted | 1.6% | 2.1% |
| Fisher two-sided p | **9.2e-16** | 1.8e-08 |
| near-copy same-peak rate | 33.2% | 41.1% |

The rate is essentially identical because both search the SAME library - confirming this is a
library property, not a dataset property. **So SEA-AD's +16.4% rests on an oracle contaminated
at the same rate as the dataset where the lever failed.** Fixing P1 moves dataset 1's headline
number too, which is why "re-run dataset 1's arms after the fix" sits in P6.

Detail (TDP-43):

* **22.5-27% of accepted entrapment** would be rejected by a published similarity filter at its
  own threshold (OpenSWATH identity > 0.50: 13.4%; EncyclopeDIA fragment overlap > 0.40: 20.6%).
* Near-copies **co-elute with their source target**: same apex RT (within 0.05 min) in **41.1%**
  of shared files, vs **2.3%** for dissimilar entrapment - an 18x difference. Some are absolute:
  `SMCMDNK`/`MSCMDNK` co-elute in 100% of shared files.
* Near-copies are **34.9x more likely** to have their source target also accepted (42.9% vs
  2.1%, Fisher p = 1.8e-08).
* At pass 1 the shadow scores only **3.9x worse** than the real peptide (the blib's 16x was
  pass-2 rescoring sharpening it after the fact).

**Fix: gate at GENERATION time with retry, for entrapment AND decoys.** A shuffle that lands too
close to its target is a failed draw, not a valid entrapment peptide - reject and re-shuffle, as
gendecoy's cycling fallback already does. Keeps entrapment 1:1 with targets, leaves `r`
unchanged, restores exchangeability rather than patching it.

* Do **not** filter entrapment at load time and recompute `r`: the surviving entrapment then
  models only *dissimilar* false peptides while real false targets still include the analogous
  class, swinging the estimator ANTI-conservative. Trading a safe bias for an unsafe one.
* Do **not** also drop the matched targets: preserves `r` but does not restore exchangeability,
  and removes real IDs in a structured way (the affected sequences are low-complexity -
  poly-G, poly-E, collagen-like).
* **Fragment overlap alone is insufficient.** `LMDLIGDR`/`IMDLLGDR` differ only by isobaric L/I
  swaps, so overlap is 1.000 - yet they land on the same peak only 31% of the time, because the
  peak picker also uses predicted RT, which differs. Gate on identity AND overlap.

**Direction of the bias, as a hypothesis rather than a claim.** Near-copies shadow their
targets, so a reproducibly-detected target has a reproducibly-detected shadow. mean(best-N)
rewards reproducibility, so it should promote near-copy entrapment MORE than the max arm does -
inflating the mean(best-N) arm's measured FDP and therefore **understating its gain**. If that
holds, the contamination biases AGAINST the lever on both datasets, and the fix would move
TDP-43's -0.20% toward zero and SEA-AD's +16.4% higher. Testable only by re-running both arms
after the fix; not established here.

**Severity is bounded, which is why this is P1 and not P0.** Peak assignment is **non-exclusive** -
in 41.1% of shared files both the entrapment and its target hold a peak at the same apex and both
are accepted. So the contamination **inflates the measured false count but does not suppress real
identifications**.

**Interim, non-invasive:** a load-time diagnostic for externally-built libdecoy libraries
reporting the identity / overlap distribution against the pairing manifest, plus FDP computed
both ways (all entrapment, and gated with `r` recomputed) to bracket the contamination. Costs
seconds. Turns a silent bias into a visible one without changing anyone's numbers.

---

## P2 - mean(best-N) is the better REPRODUCIBILITY LEVER; defaulting it is a product question

**REVISED 2026-08-02.** The earlier version of this recommendation said "the sign flips between
datasets, so no default is supportable". That rested on **total experiment-wide detections** - a
metric that counts a precursor found in 1 of 163 runs equally with one found in 163. For
quantitative work that is the wrong weighting: quantifying a 1-of-163 detection means gap-filling
162 runs.

**Against the lever it actually competes with, the sign does not flip.** Running plain `max` and
keeping only precursors seen in >= N runs IS the standard post-hoc reproducibility cutoff. At
every reproducibility bar on TDP-43 - the dataset where mean(best-N) "lost" - it beats that
cutoff:

| bar | post-hoc cutoff | best mean-best-N | gain |
|---|---|---|---|
| k>=1 (total) | **30,070** | 29,501 | **-1.89%** |
| k>=2 | 28,663 | **29,161** (mb2) | **+1.74%** |
| k>=3 | 27,224 | **28,080** (mb3) | **+3.14%** |
| k>=5 | 25,033 | **25,836** (mb4) | **+3.21%** |
| k>=9 | 21,928 | **22,400** (mb6) | **+2.15%** |

And the optimal N tracks the bar (mb2 at k>=2, mb3 at k>=3, mb4 at k>=5, mb6 at k>=9+), so a
single N* was the wrong summary. On SEA-AD it wins on total count outright as well.

**Why**: a post-hoc cutoff can only REMOVE - a precursor rejected at the q stage never reaches
the filter. mean(best-N) lets reproducibility contribute to the q, so it can also PROMOTE.

**So the honest statement is narrower and more useful than the old one:** mean(best-N) is a
better way to select for reproducibility than post-hoc filtering. **Whether to default it is a
product question - do you want reproducibility selection on by default? - not a measurement
question.** For a quantitative workflow the answer is plausibly yes; for a discovery workflow
maximising raw identifications, plausibly no.

Caveat: matched on the q cut, not on FDP (k>=2: 0.360% cutoff vs 0.421% mb2, marginal population
~3.9% false, both far under the 1% requested). The matched-FDP comparison needs run-count
histograms across the q sweep, which `crossRun` emits only at the 1% cut - a small mdiag addition,
no new searches. See TODO-20260801 finding 7.

**A file-count rule is specifically ruled out.** TDP-43 has twice the files and a max-arm union
efficiency of 67.2%, already as high as SEA-AD's *best-2* efficiency at 82 files. The
scale-driven efficiency loss the lever repairs is not a function of N.

What the lever's value actually tracks is the **size of the post-gate single-run leak** - a
property of matrix, library match and instrument series. On TDP-43 that leak is ~60 recoverable
false IDs; the transform fires correctly (demotes 76% of singletons, pulls their slice FDP to
nominal) and simply has nothing to collect.

**What DOES replicate across both datasets:** the calibration improvement. True FDP falls
monotonically with N on both. mean(best-N) is a universal calibration gain and a
matrix-dependent sensitivity gain.

---

## P3 - Adopt the reproducibility-frontier panel as the pre-flight gate

Already rendered in every `--model-diagnostics` report. Read the **experiment-wide** route (not
the per-run route - the selector decides the answer):

| | experiment-route peak | k=1 -> k=2 step | mean(best-N) actual |
|---|---|---|---|
| SEA-AD 82f | **k = 4** | **+16.16%** | **+16.4%** |
| TDP-43 163f | **k = 1** | **-3.75%** | -0.20% / -9.36% |

**2 for 2 on the two datasets with opposite outcomes**, and the step size is a reasonable
first-order estimate of the realised gain, not merely a sign test. Costs one ordinary run - no
A/B, no code change.

Caveats: two datasets; and it is entrapment-calibrated, so it inherits P1's contamination.
Re-validate after the generation fix lands.

**Superseded:** the A x B screen from dataset 1. On verified indexing it ranks correctly
(SEA-AD 0.380/0.413, TDP-43 0.227/0.328) but overpredicts TDP-43 by 5.1 points (+4.92% predicted
vs -0.20% actual). It is a screen for extremes, as its authors said - not an effect-size
estimator, and strictly worse than the frontier panel.

---

## P4 - Entrapment design research

* **Arabidopsis entrapment library** (Brendan retrieving). Tests the mass-twin co-isolation route
  directly: an Arabidopsis peptide has no mass-matched human twin, so it cannot shadow one. The
  earlier finding that it behaved indistinguishably from shuffled entrapment is evidence the
  estimator is robust along that axis - worth re-checking now that the contamination is
  quantified.
* **Draw decoys from another species too.** Removes the co-isolation route entirely and gives
  decoys realistic fragment behaviour rather than reversed ladders.
* **Entrapment attributed to PRESENT proteins.** The gap neither shuffled nor foreign-species
  entrapment closes: a real absent human peptide whose isoforms and modified forms ARE present
  has no analogue in either design. Required to audit any protein-level or reproducibility prior
  (already recorded in the completed mean_best2 TODO for `mean-2-prot`).

---

## P5 - Tooling

* **Other machine to write up its Carafe + FDRBench configuration** for this work.
* **Possible FDRBench PR** contributing diagnostics `--model-diagnostics` has accumulated that
  FDRBench lacks. Strongest candidates, in the order they proved useful here:
  1. the **reproducibility frontier** panel (per-run and experiment-wide routes) - P3's gate
  2. **k-resolved entrapment FDP** (`entrapmentFdpByRunCount`) - the mechanism panel
  3. an **entrapment similarity audit** against the pairing manifest - P1's diagnostic
* **Indexing note for anyone reading `crossRun`:** those arrays have length n and are indexed by
  **k-1**. Reading them as if indexed by k reports every k=2 quantity under the k=1 label.

---

## P6 - Deferred / open

* **Third dataset: AHA Plasma Stroke EV** (downloading, 200 files). The only catalog dataset
  shipping a **ChromLib** (GPF runs), so a sample-matched plasma EV library is buildable - which
  separates "plasma EV matrix" from "library built for the wrong tissue", the confound dataset 2
  cannot resolve.
* **154-file EV-only cohort** on TDP-43, excluding the nine `Total-*` samples (positions
  152-160, 4,371 targets vs a 10,095 median - a different preparation, not instrument decay).
  Tests whether sample-type heterogeneity suppresses the gain. One Stage-5-only pair, ~3 h.
* **The 28 of 47 near-copies whose source target was NOT accepted** - shadowing a sub-threshold
  target, shadowing another present species, or genuine false discoveries. Not separable from the
  accepted set alone.
* **Re-run the dataset-1 arms after the P1 fix** to see how much of +16.4% survives a clean
  oracle.
