# PR description material: similarity gating + configurable entrapment in Carafe

Draft for the maccoss/Carafe PR. Written for **Carafe maintainers**, not Osprey developers -
this is a library-generation defect that affects any tool consuming these libraries, and the
filters proposed are already standard practice elsewhere in the field.

---

## Title

`Gate generated entrapment and decoy sequences on similarity; add configurable entrapment source and ratio`

---

## Summary

Decoy and entrapment peptides exist to model matches arising **by chance**. Both are generated
here by permuting a target sequence, and a permutation is rejected only when it collides
**exactly** with a real target - nothing checks whether it is merely *similar*. For low-complexity
sequences a permutation is close to a no-op, so the generated peptide keeps most of its source's
fragment ladder and is detected wherever the source is detected.

**Such a peptide is not a valid null.** Its detection is a deterministic consequence of the source
being present, not a chance event, and a null population is only valid if its members' detection
is independent of whether the corresponding target is present. Measured on real data below, these
peptides are **34.9x more likely** to be accepted when their source target is - matched to the
**same chromatographic peak**, at a **consistently lower score**.

**Both generated populations are affected, and both over-count in the same direction:**

* **Decoys** inflate the FDR *estimate* they drive through target-decoy competition. A decoy that
  matches on its target's own fragments is not competing fairly.
* **Entrapment** over-reports the FDP *validation*: a measurable fraction of entrapment "hits" are
  not false discoveries at all, but the target's own signal matched by a near-copy of the target's
  own sequence.

They are the same defect in two populations, differing only in rate (4.05% entrapment vs 1.70%
decoys - see below, the rate tracks the generation method). Fixing one and not the other would
replace a symmetric bias with an asymmetric one, so this PR gates **both**.

This PR adds an EncyclopeDIA-style fragment-overlap gate with retry to both generated populations,
plus two flags that make the entrapment design configurable rather than hard-coded.

## The defect

`EntrapmentFastaGear` generates entrapment with a single, unretried shuffle:

```java
q.pTarget = shufflePreservingCterm(q.target, cfg.entrapmentSeed);   // called ONCE, no loop
...
boolean drop = (q.pTarget != null && targetSet.contains(q.pTarget))  // EXACT collision only
        || (cfg.addDecoys && q.decoy == null)
        || (cfg.addDecoys && cfg.addEntrapment && q.pTarget != null && q.pDecoy == null);
```

`generateReverseDecoy` has a cycling retry, but its acceptance test is also exact:
`!cyc.equals(seq) && !targetSet.contains(cyc)` - unique, not dissimilar.

Worked example from the shipped library. A 17-alanine target has nothing to permute into, and no
retry to escape with:

```
target      AAAAAAAAAAAAAAAAGATCLER
entrapment  AEAAAAAAGAATAAAALAAAACR      positional identity 0.78
```

The extreme cases are worse. `GGWGGGGGGWGGGGGGGGGWGGGGGGGR` -> `GGWGGGGGGWGWGGGGGGGGGGGGGGGR`
(0.93). And `LMDLIGDR` -> `IMDLLGDR` differs only by L/I swaps, which are **isobaric** - the two
peptides have identical b and y ions at every position, so they are indistinguishable by mass
spectrometry.

## Evidence that it matters

Measured over all 1,391,000 quartets of the shipped `target+decoy+entrapment` library:

| | rejectable at EncyclopeDIA's 0.40 threshold |
|---|---|
| entrapment | **4.05%** |
| decoys | **1.70%** |

Three independent implementations agree on that rate (Java over all quartets; two separate Python
audits over 200-250k samples, 4.04% and 4.15%).

### The near-copies are not hypothetical - they were found in real data, on the same peaks

Two independent Astral DIA datasets, searched against this library. Measurements are on the
**pass-1 accepted set** (experiment-wide q <= 1%); the paired entrapment count reproduces each
run's own reported accepted-entrapment count exactly, so this is the shipped accepted set and not
a differently-scoped one.

| | SEA-AD Pilot-MTG, **82 files** | TDP-43 Plasma EV, **163 files** |
|---|---|---|
| accepted entrapment (paired to a source target) | 174 | 130 |
| of which **near-copies** | **50 (28.7%)** | **35 (26.9%)** |
| near-copies whose **source target is ALSO accepted** | **27 (54.0%)** | **15 (42.9%)** |
| dissimilar entrapment, same measure | 2 (1.6%) | 2 (2.1%) |
| odds ratio / Fisher exact p | **9.2e-16** | **34.9x**, p = **1.8e-08** |
| near-copies on the **SAME PEAK** as their target | **33.2%** | **41.1%** |
| dissimilar entrapment on the same peak | 14.4% | 2.3% |
| median apex-RT difference, near-copies | 0.249 min | **0.074 min** |

Three things follow, and they are measurements rather than inferences:

1. **Near-copies are preferentially detected.** They are ~27-29% of *accepted* entrapment against
   4.05% of the library - a 6-7x enrichment. In the gated rebuild they are **0 of 913 accepted**,
   against 59 of 826 (7.1%) ungated.
2. **They are matched to the same chromatographic peak as their source target**, in 33-41% of the
   files where both were scored, against 2.3-14.4% for dissimilar entrapment. Individual cases are
   unambiguous: `SMCMDNK`/`MSCMDNK` share an apex in **100%** of shared files,
   `HILQIYEIQNR`/`HLQIIYEINQR` in **98%** (median apex difference 0.006 min).
3. **They score consistently WORSE than the target sharing that peak** - median experiment q
   **4.20e-03 vs 1.74e-03 (2.4x worse)** on SEA-AD and **5.12e-03 vs 1.32e-03 (3.9x worse)** on
   TDP-43, and worse in **85%** and **100%** of cases where both were accepted.

Point 3 is what identifies the mechanism. A weaker score on the *same peak* is the signature of
**partial fragment sharing**: the near-copy matches enough of the target's fragment ladder to
clear the 1% threshold, but not all of it, so it lands below the real peptide. That is not two
coincidentally-similar peptides being detected independently - it is one peptide's signal being
counted twice, once as a target and once as a "false discovery".

Because these hits are counted in the entrapment numerator, they inflate the measured FDP without
corresponding to any real false identification.

### The same is true of decoys, which matters more

Decoys drive the FDR *estimate* rather than validating it, so the same analysis was run pairing
each accepted decoy to the target it was reversed from:

| | TDP-43, 163 files | SEA-AD, 82 files |
|---|---|---|
| accepted decoys paired to a source target | 192 | 241 |
| of which **near-copies** | 19 (9.9%) | 25 (10.4%) |
| near-copies **on the same peak** as their source | **63.2%** | **42.6%** |
| dissimilar decoys, same measure | 8.3% | 4.0% |
| median apex-RT difference, near-copies | **0.0000 min** | 0.345 min |
| median q, near-copy decoy vs its source target | 2.0x worse | 1.3x worse |

**Near-copy decoys shadow their source target as entrapment does, and score closer to it** - 1.3-2.0x
against entrapment's 2.4-3.9x. Some pairs reach identical q:

```
overlap  same peak   decoy q     target q    decoy / target
1.000       97%      5.37e-03    5.37e-03    ALEIEIAK    / AIEIELAK
1.000      100%      1.66e-03    1.66e-03    SIDLDLSK    / SLDLDISK
0.900      100%      3.65e-03    1.44e-04    EAQELKEQAEK / EAQEKLEQAEK
0.833       65%      8.65e-03    8.65e-03    EPNSPER     / EPSNPER
```

The first two normalise to the same sequence under I->L. Since isoleucine and leucine are
**isobaric**, those decoys are mass-spectrometrically indistinguishable from their targets -
identical fragment ladders, same peak, identical q. That is target-decoy competition run against
a copy of the target.

This is a failure mode specific to **reversal**: a sequence that is palindromic under I/L
equivalence reverses to itself. It is **rare** - 5 in 200,000 quartets (0.0025%), so roughly 35
library-wide, and 0 after gating - so it is an illustration of the mechanism rather than a driver
of the measured effect. The bulk of the effect is the broader near-copy population (1.70% of
decoys, 4.05% of entrapment).

**What this does not establish.** `p_decoy` (the entrapment population's own decoy) shows little
shadowing - 0/19 and 2/21 near-copies had their source accepted - which is expected, since
entrapment is itself rarely accepted so there is little signal to shadow. Its 1.86% library-level
rate is still gated, on the same symmetry argument rather than on separate in-data evidence.

**Effect on the FDR estimate.** Rebuilding the same library with the gate applied and re-searching
the same cohort, compared at **matched discovery count** (see Caveats for why that control
matters):

| | |
|---|---|
| measured FDP | **-24.6%** |
| discoveries at 1% reported q | **+2.67%** |
| discoveries at matched 1% true FDP | **+4.71%** |
| near-copies among accepted entrapment | 59/826 (7.1%) -> **0/913** |

**Both axes improve at once** - the gated library finds more while measuring less false discovery,
so this is not a sensitivity/accuracy trade.

The +4.71% is **oracle correction, not extra detection**, and that is established rather than
assumed: removing near-copies post-hoc from the *unchanged* run's oracle predicted +4.6%, and the
rebuilt library measured +4.71%. Post-hoc surgery never touches the search, so reproducing the
whole gain without changing the search shows these are peptides the contaminated oracle was
falsely flagging - not newly detected ones.

## What this PR changes

**1. Fragment-overlap gate with retry, on both generated populations.**
Rejects a candidate whose theoretical singly-charged b/y ladder overlaps its target's by more than
**0.40** within a fixed **0.02 Da** window - EncyclopeDIA's `PeptideUtils.getSmartDecoy` rule and
threshold. Entrapment gains the bounded retry it never had (seed re-derived per attempt so output
stays deterministic); decoys reuse the existing cycling fallback as the retry path. A quartet is
dropped only after all attempts fail, using the collision-drop policy already present.

The fixed tolerance is deliberate: keying it to a search tolerance would make the same library
produce different sequences for different downstream settings.

**2. `--entrapment-fasta` - entrapment from a foreign proteome.**
A gated shuffle still shares the target's exact amino-acid composition and precursor mass, so it
co-isolates with the target in every DIA window. The gate removes the tail of that distribution
but not the relationship: median target/entrapment fragment overlap is **0.100 ungated, 0.100
gated, 0.024** with real *Arabidopsis* peptides mass-matched to targets. Foreign-species
entrapment is standard practice (Biognosys, Bernhardt).

**This flag makes entrapment design configurable; it is NOT presented as a proven improvement,
and the one controlled measurement of it went the other way.** Substituting mass-matched
*Arabidopsis* peptides for the gated shuffle, same 40-file Astral cohort, same prediction basis,
same `r`:

| | measured FDP at matched discovery |
|---|---|
| gated shuffle | 0.525% |
| **Arabidopsis** | **1.183%** (**+125%**) |

About half of that excess is I/L collisions (see change 3, which is why the two ship together);
a **+17.7%** gap remains after correcting for them. Arabidopsis was also worse on sensitivity -
matched discoveries **-10.5%**, union efficiency **-9.5 points**.

Two readings remain open and this experiment does not separate them: either real peptides are the
more honest null and shuffles are under-identified (their predicted spectra are 1-3% poorer by
fragment count and entropy - the right direction, too small to carry the effect), or a foreign
proteome is a biased null that over-reports. The composition asymmetry is real and measured -
Arabidopsis entrapment differs from the target population by **P -1.39, Q -1.38, S +1.01
percentage points**, where an anagram shuffle is composition-matched by construction at exactly
0.000 on every residue.

**The flag exists so this can be studied, not because the answer is known.** The default is
unchanged.

**3. I/L-normalised collision rejection (independent of the overlap gate, and the overlap gate
does NOT catch it).**
Leucine and isoleucine are **isobaric** (113.08406). An entrapment peptide differing from a human
target only by I<->L is mass-identical to it and produces an identical fragment ladder, so it is
indistinguishable by mass spectrometry - it will be detected wherever its twin is, and every such
detection is counted as a false discovery when it is not one.

The fragment-overlap gate cannot catch this, because it compares each entrapment to **its own
paired target** while a collision is an exact isobaric match to a **different** one. An
exact-string collision audit reports 0 for every library and misses it entirely.

Under I->L normalisation, and note the enrichment among *accepted* entrapment - the signature of
a peptide that is genuinely present:

| library | colliding in library | colliding among ACCEPTED entrapment | enrichment | FDP if corrected |
|---|---|---|---|---|
| ungated shuffle | 735 (0.053%) | 8/363 (2.20%) | **41.7x** | -3.8% |
| gated shuffle | 678 (0.049%) | 11/383 (2.87%) | **58.9x** | -5.3% |
| **Arabidopsis** | 1,043 (0.075%) | **39/472 (8.26%)** | **110.3x** | **-20.7%** |

Foreign proteomes are hit hardest because plant and human share conserved proteins whose tryptic
peptides differ by conservative I<->L substitutions. **This is why the I/L check ships alongside
`--entrapment-fasta` rather than after it** - offering a foreign-proteome source without it would
introduce the failure mode it is most exposed to.

Implementation is one hash set at generation time: reject any candidate whose I->L normalised
sequence appears in the I->L normalised target set.

**4. `--entrapment-ratio` - entrapment:target ratio.**
At r=1 the entrapment pool is half the searched library and demonstrably perturbs the target
search (targets recovered 27,931 at r=1.0 vs 30,654 at r=0.1). Combined FDP is ratio-invariant at
~1.1% across a 10x pool-size change once `r` is factored into the estimate, so a small-r overlay
measures without distorting. r <= 0.25 is preferable when the goal is measurement rather than a
1:1 library.

**5. UI support** for the flags.

## Why the gate must apply to BOTH generated populations

This is a design requirement, not a convenience. Decoys and entrapment model the same thing - a
peptide that is not in the sample - and differ only in role: **decoys drive the FDR estimate**
through target-decoy competition, **entrapment validates it**. A near-copy in either population
wins on its source's signal, so it is over-counted, and in both cases the over-count pushes the
resulting estimate *conservative*.

Fixing only one side therefore replaces a symmetric bias with an asymmetric one:

* **Gate entrapment only** -> an honest FDP numerator measured against a threshold still inflated
  by over-counted decoys. Calibration would appear **better** than it is.
* **Gate decoys only** -> the q threshold loosens while entrapment stays inflated. Calibration
  would appear **worse** than it is.

Both populations are gated here, so the comparison stays symmetric.

**All four generated relationships are gated, including the entrapment population's own decoy.**
Entrapment competes against `p_decoy` exactly as targets compete against `decoy`, so leaving that
pair ungated would put the entrapment competition on a different footing from the target
competition - the same asymmetry one level down. Measured against the source each is derived from:

| relationship | generation method | ungated | gated |
|---|---|---|---|
| target -> entrapment (`p_target`) | C-term-preserving **shuffle** | **4.05%** | **0%** |
| target -> decoy | **reverse** + cycle | **1.70%** | **0%** |
| entrapment -> its decoy (`p_decoy`) | **reverse** + cycle | **1.86%** | **0%** |

**The magnitude tracks the generation method, not the population.** The two reverse-derived
relationships sit at 1.70% and 1.86%; the shuffle-derived one is more than double at 4.05%
(median positional identity 0.194 vs 0.143). A shuffle of a low-complexity sequence is close to a
no-op, whereas reversal reorders by construction.

That also explains a piece of history worth flagging for anyone re-assessing these filters: an
earlier evaluation measured them against **reversed decoys only**, found they barely bound
(52-522 exclusions in 494,495), and nearly dropped them on that basis. They were being tested on
the population where reversal has already destroyed the similarity they look for.

## Cost

Small, and it is the predicted low-complexity tail: **0.043%** of quartets dropped. Both rebuilt
libraries in fact retain **more** targets than the original, because the retry also rescues
peptides the old one-shot shuffle lost to exact collisions.

## Prior art

The gate is not novel here - it is what other implementations already do, and Carafe is the
outlier:

* **EncyclopeDIA** `PeptideUtils.getSmartDecoy` - rejects above 0.4 fragment overlap and reshuffles
* **OpenSWATH** `shuffle_sequence_identity_threshold` - rejects above 0.5 positional identity
* **SpectraST** - regenerates on excessive similarity

## Deliberately NOT included: a sequence-identity gate

OpenSWATH's identity threshold was implemented and measured alongside the overlap gate, and
**rejected on evidence**. Marginal value of adding it on top of the overlap gate, over the
accepted entrapment of two datasets:

| | both gates | overlap only | **identity only** |
|---|---|---|---|
| dataset 1, n | 24 | 20 | **6** |
| source target also accepted | 17/24 | 10/20 | **0/6** |
| dataset 2, n | 19 | 13 | **3** |
| source target also accepted | 11/19 | 4/13 | **0/3** |

**All nine identity-only cases have a source target that was never accepted** - no demonstrated
shadowing. The overlap gate catches the harmful population; identity adds cases with no measured
harm.

The mechanistic reason is worth stating because it generalises: **detection is driven by fragment
evidence, not by positional string similarity.** Fragment overlap is the causal quantity; identity
is a weakly correlated proxy. `EIVELEK`/`EEVEILK` has identity 0.571 but overlap 0.333 -
positionally similar, ladders diverge, shadows nothing. `LMDLIGDR`/`IMDLLGDR` has identity 0.750
but overlap **1.000** - caught by overlap, nearly missed by identity.

Identity is still *computed and reported* by the audit tooling, so this can be revisited if a
dataset ever shows an identity-only case that shadows an accepted target.

## Caveats

**Applying the gate to both populations is required (see above), but it does mean the measurement
is one intervention over two populations.** The FDP result is unaffected - decoys never enter the
entrapment FDP numerator - but the **+2.67% discovery gain should be attributed to "the gate
applied to both populations," not to entrapment alone**, since reported q is computed from a
decoy-trained model and the decoy population also changed (1.70% -> 0% rejectable). This is an
attribution limit on one secondary number, not a reason to gate only one side - doing that would
bias the whole comparison.

**Comparing at matched reported q understates the effect.** The same experiment reads **-11.2%**
at matched q and **-24.6%** at matched discovery count, because the gated library also accepts
2.67% more targets and therefore sits further along its own FDP curve. The matched-discovery
comparison is the correct control; without it this measurement would have looked like a miss.

**A competition effect is bounded, not excluded.** Predicting the FDP drop purely from removing
near-copies gives -19.2%; the rebuilt library measured -24.6%. The difference is ~11 entrapment
peptides against a Poisson sigma of 13-14 - under 1 sigma. Real competition (a gated entrapment
peptide winning where a near-copy previously did) would push in exactly that direction, so the
effect is plausibly real but not demonstrated at this cohort size.

**Libraries built in different runs are not comparable.** Between two runs with different peptdeep
model versions, **44%** of target precursors receive a different reported fragment set (median
relative intensity difference 2.3%, p90 8.4%). Fine-tuning *is* deterministic given the same
training blib and seed - two separate invocations produced byte-identical models and 100%
identical target predictions. Any A/B intended to isolate a library variable must therefore share
a prediction basis; the measurements above do.
