# PR description material: similarity gating + configurable entrapment in Carafe

Draft for the maccoss/Carafe PR. Written for **Carafe maintainers**, not Osprey developers -
this is a library-generation defect that affects any tool consuming these libraries, and the
filters proposed are already standard practice elsewhere in the field.

> **Implementation status, 2026-08-03.** All six changes are implemented on
> `feature/decoy-similarity-gate` in `maccoss/Carafe` (10 commits, not yet pushed). Change 4, the
> set-wise isobaric shadow gate, landed last and is the one whose measured cost most exceeded its
> scoping estimate - read its section before quoting a number from an earlier revision. Where the code
> diverged from this draft, the draft has been corrected to match the code, EXCEPT the items
> listed here which are code decisions a reviewer may want to revisit:
>
> * **Flag names follow Carafe's convention, not this draft's original.** Carafe uses single-dash
>   with underscores throughout (`db`, `itol`, `min_pep_charge`, `build_entrapment_fasta`) and has
>   no `--double-dash` or hyphenated option anywhere, so the draft's `--entrapment-fasta` /
>   `--entrapment-ratio` would have been the only ones. Shipped as **`-entrapment_db`** (parallel
>   to the existing `-db`) and **`-entrapment_ratio`**.
> * **A third flag exists that this draft does not mention: `-no_similarity_gate`.** An AUDIT
>   switch that reproduces the pre-fix generator so a rebuild can be proved to differ from a
>   delivered library only by this change. It is what verified the digest parameters here - an
>   ungated rebuild reproduces the delivered `osprey_library_db_peptides.fasta` byte for byte
>   (SHA-256 over 349 MB, all 1,390,979 quartets). It necessarily skips the I/L check too, since
>   its whole purpose is byte-reproduction of a historical library. A library built with it carries
>   the contamination and should not be searched.
> * **The retry seed keeps its original derivation on attempt 0.** The draft says the seed is
>   re-derived per attempt; attempt 0 deliberately keeps the original two-part
>   `SHA-1(masterSeed:seq)` form, with `:attempt` appended only for retries. This is what lets
>   `-no_similarity_gate` reproduce a pre-fix library exactly, and it keeps a before/after FDP
>   comparison nearly paired, since only the ~4% of entrapment the gate rejects changes rather than
>   all of it.
> * **`-entrapment_ratio` is bounded to [0.10, 1.00]** and errors below 0.10 explaining that the
>   region is untested rather than silently accepting it - the sweep covers r = 1, 0.5, 0.25, 0.1
>   and at 0.1 only ~32 entrapment peptides were accepted at 1% q.
>
> Rates in this draft are from 200-250k samples. Full-manifest audits over all ~1.39M quartets read
> slightly higher and are given alongside them below.

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

**2. `-entrapment_db` - entrapment from a foreign proteome.**
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
`-entrapment_db` rather than after it** - offering a foreign-proteome source without it would
introduce the failure mode it is most exposed to.

**Decoys collide too, and at a similar rate** - a population not previously measured. Full audit of
the ungated library, checking every generated sequence against the whole target set rather than
only its own pair:

| population | exact collisions | I/L-isobaric collisions |
|---|---|---|
| entrapment | **0** | **742** |
| decoy | **0** | **792** |

The zeros are the point: an exact-string audit reports this library clean, and it is not. A decoy
that is I/L-identical to a real target is not a valid null either - it wins target-decoy
competition on the target's own signal, inflating the decoy count rather than the entrapment
count, which is why the check is applied to both populations for the same reason the overlap gate
is. Both read **0 / 0** after the fix.

Implementation is one hash set at generation time: reject any candidate whose I->L normalised
sequence appears in the I->L normalised target set. The normalised comparison **subsumes** the
exact one, since a sequence containing no isoleucine normalises to itself, so it replaces the
existing collision check rather than adding a second lookup.

Verified against the independently derived counts: on the gated shuffle library 663 entrapment
sequences changed and 10 more were dropped for having no acceptable alternative (673 against 678
colliders measured from search output), and on Arabidopsis 1,116 candidates were excluded from the
pool against 1,043 measured in the built library - the pool is only ~95.7% consumed, and
1,043/1,116 = 93.5% matches that assignment rate. **2,608 EXACT matches were already being
filtered**, which is precisely why an exact-string audit read clean while the isobaric ones went
through.

**4. Set-wise isobaric shadow rejection - the same defect as change 3, one substitution wider.**

> **VALIDATED END TO END: two independently-built nulls CONVERGE once this gate is applied.**
> Two Astral libraries were rebuilt with it and searched over a 40-file cohort sharing one
> prediction basis. Shuffle entrapment and *Arabidopsis* entrapment - an anagram of the human
> proteome and a foreign plant proteome, built by different mechanisms with no reason to share a
> bias - disagreed by **3.5 sigma** before the gate and by **0.0** after:
>
> | | shuffle | foreign | disagreement |
> |---|---|---|---|
> | before | 0.739% | 0.992% | **+34.2% +- 9.7% (3.5 sigma)** |
> | **after** | **0.895%** | **0.895%** | **0.0** |
>
> The matched-discovery control collapses the same way, 71% apart to 4% apart. **The gate moved
> the two designs in OPPOSITE directions and they met**: shuffle up 21.0%, foreign down 9.8%.
>
> That also refutes the strongest objection raised against this change - that it removes valid
> false-discovery models and silently biases FDP downward. **A correction that flattered the
> estimator could not raise the shuffle arm.** It additionally identifies which design was wrong
> in which direction: anagram entrapment reads LOW, conserved orthologs read HIGH, and the gate is
> what makes the two commensurable.

Change 3 catches a generated sequence that is I/L-identical to a real target. The general form is a
COMPENSATING substitution: `Q = G+A` exactly (128.05858), `N = G+G` exactly (114.04293), `V+A` and
`L+G` both 170.10552. A candidate related to a real target that way is precursor-isobaric with it,
shares most of its ladder, and is invisible to every check that existed - an exact-string audit,
an I/L-normalised audit, and a pairwise overlap gate that only ever looks at the candidate's own
source.

Measured on a real library: `EAQALAR`, generated as entrapment for `AAAEQLR`, shadows the
unrelated real target `EAGAAALR` at fragment overlap **0.833**, dMass **1e-5 Da**. That is the
Q -> G+A substitution.

Rejects where the candidate is **isobaric within 0.01 Da AND fragment overlap > 0.70** against
**any** real target. Both halves are needed and the mass half is what makes it affordable: a
mass-sorted index means each candidate is compared against ~15 targets rather than 1.4M, and the
whole 1.39M-peptide digest costs **2 minutes**. Isobaric is not a convenience tolerance - it is
where MS1 discrimination fails, since a non-isobaric near-copy still differs in precursor m/z and
MS1 chromatogram. Sweeping the window from +-0.5 Da to +-40 Da changes the rejected population not
at all; only tightening to isobaric does.

The threshold is **0.70** rather than the pairwise gate's 0.40 because the SCOPE changed. 0.40 is
EncyclopeDIA's number for one pre-selected pair; applied against every target in a library it
flags a third of all entrapment, because chance matches dominate.

**What it is for, stated precisely, because two different things get called "shadowing".**
*Within-group* similarity (targets resembling other targets, entrapment resembling other
entrapment) is a real phenomenon that a null population must REPRODUCE to model the target
population faithfully - it is deliberately untouched. *Cross-group* similarity, where a generated
sequence sits on a real and highly detectable peptide, is contamination: the null is detected on
the real peptide's signal and counted as a false positive it never earned. Only the second is
rejected. Measured on the human Astral library, 1-in-60 sample:

| | before | after |
|---|---|---|
| entrapment -> **target** (cross) | 0.875% | **0.000%** |
| decoy -> **target** (cross) | ~0.9% | **0.000%** |
| entrapment -> entrapment (within) | 0.880% | 1.036% |
| decoy -> decoy (within) | 1.561% | 1.467% |
| target -> target (within) | 1.496% | unchanged |

**This matters far more for foreign-proteome entrapment, and the reason is evolutionary.** What
harms an estimate is the cross-group rate weighted by how likely the shadowed target is to be
detected. A shuffle lands on whatever target happens to be isobaric and ladder-similar, detected
at the base rate. A conserved ortholog matches a human peptide BECAUSE it is conserved, and
conservation tracks functional importance, which tracks expression, which tracks detectability -
so the mechanism that creates the match is the one that makes the shadowed protein abundant. The
library rates are nearly identical and the detection rates are not:

| arm | flagged in library | flagged among ACCEPTED entrapment | enrichment |
|---|---|---|---|
| shuffle | 0.875% | 1 of 95 (1.05%) | ~1.2x |
| **Arabidopsis** | 0.874% | **8 of 134 (5.97%)** | **~6.8x** |

Those eight are orthologs of beta-tubulin, aldolase, enolase and RAB7A - proteins abundant enough
to be present in every sample - which is why only the foreign arm produced a spike at low q, where
calibration matters most.

**The gate is NOT free, stated plainly rather than left for review to find.** Union efficiency
falls on both arms (-2.64 pts shuffle, -5.18 pts foreign); the foreign arm loses 3.0% of
discoveries while the shuffle arm gains 2.1%; ~50,000 quartets are regenerated and 1,428 (shuffle)
/ 648 (foreign) are lost outright. A post-hoc simulation over-predicted the benefit by 2.3x and
was blind to the cost entirely - oracle surgery holds the discovery set fixed by construction, so
it cannot see what a library change costs.

**Cost is ~60x the estimate this was scoped against, and the reason is peptide length**, which is
worth stating plainly rather than discovering downstream. Measured library-wide: 0.8% of
entrapment, 0.9% of decoys and 1.9% of p_decoys are re-generated, and 0.10% of quartets have no
acceptable alternative. The scoping estimate of ~0.013% was drawn from peptides of length 11-19,
where the measured rate IS 0.01-0.09%. The rule is far more active on 7- and 8-mers (23% and 18%),
where a 12-rung ladder makes 0.70 reachable by chance and short tryptic peptides have compositional
isobars everywhere. Three independent implementations agree (0.814% Java, 0.875% and 0.835%
Python), so this is the rule's behaviour and not a coding error.

**A length-aware threshold was proposed, measured, and rejected on evidence** - recorded because
it is the obvious question a reviewer will ask. Gating only at length >= 9 would cut the
regeneration ~100x, and the short shadows it would spare looked like shared background: real
targets carry isobaric high-overlap twins at 1.486% where entrapment carries them at 0.835%. The
deciding measurement is whether a short shadow's detection is actually DRIVEN by the target it
shadows. For each accepted shadow entrapment, is that target also accepted, against a mass-matched
control (same isobaric window, split by overlap, so both halves share abundance priors)?

| length | shadowed target also accepted | mass-matched control | odds |
|---|---|---|---|
| 7 | **51.4%** | 3.3% | **15.7x** |
| 8 | **61.1%** | 2.5% | **24.4x** |
| all | 58.7% | 3.0% | **19.3x** |

Short shadows are 15-24x detection-driven, not chance, so the gate applies at **all lengths**.

Rejection triggers a RETRY, never a removal - see the ratio argument in "Why the gate must apply to
both generated populations". Foreign candidates are filtered when the pool is built instead, since
a peptide that shadows a human target can serve no target at all.

**5. `-entrapment_ratio` - entrapment:target ratio.**
At r=1 the entrapment pool is half the searched library and demonstrably perturbs the target
search (targets recovered 27,931 at r=1.0 vs 30,654 at r=0.1). Combined FDP is ratio-invariant at
~1.1% across a 10x pool-size change once `r` is factored into the estimate, so a small-r overlay
measures without distorting. r <= 0.25 is preferable when the goal is measurement rather than a
1:1 library.

**6. UI support** for the flags. Three controls under the existing "Include entrapment peptides"
checkbox: source (shuffle or FASTA), the FASTA path with Browse and a Download button wired to
Carafe's existing UniProt dialog, and the ratio. They are **hidden rather than disabled** when
they do not apply, so the panel is unchanged for anyone not using entrapment, and the FASTA row
appears only once a FASTA source is chosen. The emitted command is built from that logical state
rather than from field contents, so a path left behind after switching back to Shuffle cannot
reach the command line. Spec with mockups traced from the running app:
`TODO-20260801_decoy_similarity_gate-carafe-spec.html`.

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

| relationship | generation method | ungated (sample / full) | gated |
|---|---|---|---|
| target -> entrapment (`p_target`) | C-term-preserving **shuffle** | **4.05% / 4.22%** | **0%** |
| target -> decoy | **reverse** + cycle | **1.70% / 1.74%** | **0%** |
| entrapment -> its decoy (`p_decoy`) | **reverse** + cycle | **1.86% / 1.89%** | **0%** |

The second figure in each row is a full audit over all 1,390,979 quartets rather than a sample;
all three "gated" columns are likewise full audits, not sampled.

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
