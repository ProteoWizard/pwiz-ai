# TODO-20260801_decoy_similarity_gate.md

## Branch Information
- **Branch**: `Skyline/work/20260801_decoy_similarity_gate` (not yet created)
- **Base**: `master`
- **Created**: 2026-08-01
- **Status**: In Progress
- **GitHub Issue**: [#4515](https://github.com/ProteoWizard/pwiz/issues/4515)
- **Module**: `skyline`
- **PR**: (pending)

Most of the work lands in **maccoss/Carafe** (Java), which is where the affected libraries are
built. The Skyline half is a separate, smaller change to `Model/DecoyGenerator.cs`. Osprey C# and
Rust need **no change** - they are already correct and already agree.

## Problem

Entrapment and decoy sequences in the `target+decoy+entrapment` carafe libraries are generated
with **no similarity gate**. A shuffled entrapment peptide can land close enough to its own
target that it is detected wherever the target is - which makes it not a false peptide at all,
while the FDP estimator counts it as one.

Measured on the **pass-1 accepted sets** (experiment q <= 1%) of both datasets. The paired count
reproduces each run's own mdiag `crossRun` accepted-entrapment count exactly (174 == 174,
130 == 130), so this is the official accepted set:

| | SEA-AD 82f | TDP-43 163f |
|---|---|---|
| filter-rejectable near-copies | **28.7%** | **26.9%** |
| near-copy: source target ALSO accepted | **54.0%** | 42.9% |
| dissimilar: source target also accepted | 1.6% | 2.1% |
| Fisher two-sided p | **9.2e-16** | 1.8e-08 |
| near-copy **same-peak** rate (apex within 0.05 min) | 33.2% | **41.1%** |
| dissimilar same-peak rate | 14.4% | 2.3% |

The rates match between datasets because both search the **same library** - this is a library
property, not a dataset property. Near-copies **co-elute with their source target**, which is the
mechanism proven physically rather than inferred: `SMCMDNK`/`MSCMDNK` share an apex in 100% of
shared files, `HILQIYEIQNR`/`HLQIIYEINQR` in 98%.

Severity is bounded: peak assignment is **non-exclusive**, so both the entrapment and its target
hold a peak at that apex and both are accepted. The contamination **inflates the measured false
count but does not suppress real identifications**.

Root cause, located in source (see [#4515](https://github.com/ProteoWizard/pwiz/issues/4515)):
`EntrapmentFastaGear.shufflePreservingCterm` is called **once**, with no retry, and the only
rejection is an **exact string collision** with a real target. With 17 alanines in
`AAAAAAAAAAAAAAAAGATCLER` there is nothing to permute into, and nothing was checking.

## The current landscape (surveyed 2026-08-01)

| implementation | algorithm | fragment-overlap gate | seq-identity gate |
|---|---|---|---|
| Osprey C# `Osprey.Scoring/DecoyGenerator.cs` | reverse -> cycle | **live, always on** (0.4) | absent |
| Osprey Rust `crates/osprey-scoring/src/lib.rs` | reverse -> cycle | **live, always on** (0.4) + 2 unit tests | absent |
| Carafe `EntrapmentFastaGear` entrapment | one-shot shuffle | **none** | none |
| Carafe `EntrapmentFastaGear.generateReverseDecoy` | reverse -> cycle 1..min(len,10) | **none** (exact uniqueness only) | none |
| Skyline `Model/DecoyGenerator.cs` shuffle | n random transpositions | **none** (exact equality only) | none |

C# and Rust landed together (#4480 / maccoss/osprey #58, both 2026-07-27) and are in parity:
same 0.4 threshold, same fixed 0.02 Da window, same stripped-sequence rule. **Nothing is
commented out in either**, contrary to an earlier report. What genuinely does not exist anywhere
is the *sequence-identity* gate - it was built and measured in the 2026-07-25 gendecoy session,
found to barely bind on reversed decoys, and only the overlap half shipped.

**So Osprey's own gendecoy path is protected and the libraries we actually search are not**,
because they are built by Carafe. That is why this never surfaced in gendecoy testing.

## DECISION: implement the fragment-overlap gate ONLY, not sequence identity

Measured the marginal value of adding OpenSWATH's identity gate on top of EncyclopeDIA's overlap
gate, over the pass-1 accepted entrapment of both datasets:

| | both gates | overlap ONLY | **identity ONLY** | neither |
|---|---|---|---|---|
| SEA-AD n | 24 | 20 | **6** | 124 |
| target also accepted | 17/24 | 10/20 | **0/6** | 2/124 |
| TDP-43 n | 19 | 13 | **3** | 95 |
| target also accepted | 11/19 | 4/13 | **0/3** | 2/95 |

**All 9 identity-only cases across both datasets have a source target that was NOT accepted** -
zero demonstrated shadowing. The overlap gate alone rejects ~25% of accepted entrapment on both,
and its catches are the harmful ones (10-17 shadowing an accepted target, co-eluting 28-42%).

Mechanistic reason, and the part worth remembering: **detection is driven by fragment evidence,
not positional string similarity.** Fragment overlap is the causal quantity; identity is a weakly
correlated proxy. `EIVELEK`/`EEVEILK` has identity 0.571 but overlap 0.333 - positionally similar,
ladders diverge, shadows nothing. `LMDLIGDR`/`IMDLLGDR` has identity 0.750 but overlap **1.000**
(isobaric L/I) - the overlap gate catches it, identity nearly misses it. Identity both misses real
harm and flags harmless cases.

Parity argument points the same way: the overlap gate already exists in C# and Rust, so porting it
to Carafe brings all implementations into agreement with **zero new gates anywhere**. Adding
identity would mean changing four implementations across three languages, each needing parity
verification, for no measured benefit.

**Not "never"** - the identity-only groups are n=6 and n=3, and "target not accepted" is not proof
of harmlessness (the target could be present but sub-threshold). Compute and REPORT identity in
the audit tooling; revisit if a dataset ever shows an identity-only case that shadows an accepted
target and co-elutes.

## PR description draft

`TODO-20260801_decoy_similarity_gate-pr-description.md`, beside this file. Written for **Carafe
maintainers** rather than Osprey developers - it presents this as a library-generation defect
affecting any consumer, and leads on the fact that EncyclopeDIA / OpenSWATH / SpectraST already
apply these filters and Carafe is the outlier.

It carries the full evidence chain (defect -> in-data demonstration on both datasets -> the fix
-> what was deliberately not done), the measured caveats, and the reasoning for gating both
populations. **A draft to adapt, not final text** - the session implementing the Carafe change
owns the PR. Kept current with this TODO; re-read it after any finding that changes a number.

## Tasks

- [x] **Carafe entrapment gate** (`EntrapmentFastaGear.shufflePreservingCterm` + caller). Bounded
      retry, 20 attempts, seed `SHA-1(masterSeed:seq:attempt)`. **Deviation, deliberate**: attempt 0
      keeps the original two-part `SHA-1(masterSeed:seq)` derivation, so only peptides the gate
      actually rejects get a new entrapment and a rebuilt library stays a clean differential against
      the old one. Poly-alanine drops as intended.
- [x] **Carafe decoy gate** (`generateReverseDecoy`), on both accept conditions.
- [x] **Port `IsCandidateAcceptable` to Java** - `DecoySimilarityGate`, constants verbatim. Uses
      Carafe's existing residue-mass table rather than duplicating Osprey's: they agree to 5 dp,
      which is 1e-5 Da against a 0.02 Da window, so no verdict can differ and there is one table
      instead of two that can drift.
- [ ] **NEW 2026-08-02, HIGHEST VALUE REMAINING - Carafe I/L-normalised collision rejection.**
      Reject any entrapment candidate whose **I->L normalised** sequence appears in the I->L
      normalised TARGET set. One hash set at generation time.
      **Independent of the fragment-overlap gate, which cannot catch this**: the gate compares each
      entrapment to its OWN paired target, while a collision is an exact isobaric match to a
      DIFFERENT one. An exact-string audit reports 0 for every library and misses it entirely.
      Measured (night session 2026-08-02): 735 / 678 / 1,043 colliders per library, enriched
      **41.7x / 58.9x / 110.3x** among ACCEPTED entrapment - the signature of a peptide that is
      genuinely present. Removes a **4-5%** FDP over-estimate on shuffle libraries and **~20.7%**
      on foreign-species ones.
      **Ship it WITH `--entrapment-fasta`, not after**: foreign proteomes are hit hardest, because
      plant and human share conserved proteins whose tryptic peptides differ by conservative
      I<->L substitutions. Offering the source flag without this check hands users the failure
      mode that flag is most exposed to.
- [ ] **Skyline: add the gate** to `SequenceMods.Shuffle`'s `while` condition, which currently
      tests only `newSequence.Equals(Sequence)`. Also applies to `Reverser`. Consider the I/L
      check here too - same reasoning, though Skyline decoys are not compared against an
      entrapment set.
- [ ] **Skyline: replace the shuffle with Fisher-Yates** (see below).
- [x] **Measure the cost**: done on Astral before building - 4.19% of entrapment changed, 0.043% of
      quartets dropped, loss confirmed structured (60% of dropped are >=50% one residue vs 0.7% of
      kept). Net target count actually RISES by 753 because the retry rescues old collision drops.
- [ ] **Rebuild both libraries and re-audit** with `ai/scripts/Osprey/Entrapment/` to verify the
      contamination actually cleared before spending a search on them.
- [ ] **Re-run both datasets' mean(best-N) arms** against a clean library. The +16.4% on SEA-AD
      was measured against the same contaminated oracle as the -0.20% on TDP-43.
- [ ] Osprey C# / Rust: **no change**.

## Skyline: replace n-random-transpositions with Fisher-Yates

Current implementation:

```csharp
for (int i = 0; i < lenPrefix; i++)
    newIndices[i] = i;
for (int i = 0; i < lenPrefix; i++)
    Helpers.Swap(ref newIndices[random.Next(newIndices.Length)], ref newIndices[random.Next(newIndices.Length)]);
```

This performs `n` transpositions of two uniformly-chosen positions - a random-transposition walk
on the symmetric group. **It does not produce a uniform permutation.** The random-transposition
shuffle has a mixing time of about `(1/2) n log n`; at only `n` transpositions the distribution is
still far from uniform and is **biased toward permutations close to the identity**.

That bias is not academic here: permutations close to the identity are precisely the near-copies
this TODO exists to eliminate. So the shuffle algorithm is a *second, independent* contributor to
the same problem, on top of the missing gate.

Fisher-Yates gives an exactly uniform permutation in `n-1` swaps:

```csharp
for (int i = lenPrefix - 1; i > 0; i--)
{
    int j = random.Next(i + 1);
    Helpers.Swap(ref newIndices[i], ref newIndices[j]);
}
```

Note **Carafe already uses correct Fisher-Yates** in `shufflePreservingCterm` - it is Skyline that
is the outlier. Osprey's gendecoy does not shuffle at all (reverse + cycle), so it is unaffected.

### Blast radius to check before committing

- Skyline decoys are **generated into the document and persisted**, so changing the algorithm
  changes decoy sequences for any document regenerated afterwards. Existing documents are not
  rewritten, but a regenerate produces different decoys than before.
- `Test/DecoysTest.cs` exercises `DecoyGeneration.SHUFFLE_SEQUENCE` via `ValidateDecoys`; confirm
  it asserts properties rather than pinned sequences. Also check `TestFunctional/DecoyTargetMatchTest.cs`,
  `AutoTrainModelTest.cs`, `ImportPeptideSearchTest.cs`, and `TestPerf/AcquisitionComparisonTutorialTest.cs`.
- `RANDOM_SEED = 7^5` is fixed, so output stays deterministic - just different from today's.

## Regression Test

Osprey side: `regression.ps1` is unaffected (no Osprey code changes). Carafe and Skyline each need
their own coverage:

- **Java**: port the two Rust unit tests -
  `test_overlap_gate_rejects_an_isobaric_near_duplicate` (a rejected near-duplicate AND an
  accepted ordinary reversal - without the second half the test would pass equally well with a
  gate that rejected everything) and `test_generation_never_emits_a_rejected_candidate`.
- **Skyline**: a shuffle test asserting the gate rejects a near-copy, plus a uniformity sanity
  check on Fisher-Yates.
- **Library-level**: `ai/scripts/Osprey/Entrapment/` on a rebuilt library - the accepted-entrapment
  rejectable fraction should fall from ~27% to ~0.

## How much does the contamination actually move the science?

Answered without a library rebuild: every arm kept its 163 pass-1 sidecars, so each arm's FDP
curve was rebuilt twice - once with the full entrapment set, once with overlap-gated near-copies
removed and `r` recomputed (0.9699 -> 0.9296, from a library-wide gate rate of 4.15%).

| arm | gain as reported | gain, near-copies removed | shift |
|---|---|---|---|
| mean-best-2 | -0.52% | **-0.16%** | +0.36 |
| mean-best-3 | -3.23% | -2.67% | +0.56 |
| mean-best-4 | -6.47% | -5.26% | +1.21 |
| mean-best-6 | -9.33% | -8.94% | +0.40 |

**The contamination biases AGAINST mean(best-N), as predicted, but only by 0.4-1.2 points and no
conclusion changes**: N* = 1 still, mean-best-2 still negative, curve shape unchanged. Crucially a
~1 pt correction against SEA-AD's **+16.4%** is noise, so **dataset 1's positive result is not an
artifact of entrapment contamination** - re-running it after the fix is about precision, not
validity.

Measured FDP falls 0.894% -> 0.695% (-22% relative). The other machine, substituting Arabidopsis
entrapment on Stellar, measured 1.62% -> 1.15% (-29% relative). **Two methods, two datasets, two
instruments, same ~25% over-estimate by shuffle entrapment.**

The gate rejects **4.15%** of library entrapment and **7.7%** of the ACCEPTED set - a **1.9x**
enrichment of near-copies among hits, the shadowing effect as a single ratio.

> **Corrected 2026-08-01 (night session).** This line previously read "~27% of the ACCEPTED
> set - a 6.5x enrichment". That is not reproducible: `contamination_corrected.py` itself
> prints `accepted entrapment sequences across all arms: 1,638   gated as near-copy: 126
> (7.7%)`, and `posthoc_gate_prediction.py` independently measures 90/1,103 = 8.2% on the max
> arm alone. Every other number this tool emits still reproduces exactly (the full
> mean-best-N gain table above, and 0.894% -> 0.695%), so the enrichment figure was an
> isolated error and no conclusion depends on it. The shadowing effect is real but ~2x, not
> ~6.5x.
>
> **The enrichment figure is strongly sensitive to which accepted population is measured**,
> which is probably how a much larger number arose. Near-copies are concentrated among
> high-confidence hits, so a narrower q cut inflates the ratio. On the delivered library,
> 40-file cohort: **2.7x** at a q<=0.01 harvest but **1.5x** at q<=0.03; on the 163-file
> arms at q<=0.03 it is **2.0x**. None of these approaches 6.5x. Any future quote of this
> number must state the accepted population and the q cut it was measured at.

Caveats: this reimplements the estimator (rebuilt max arm 30,584 matched vs Osprey's 30,616), so
the DIFFERENTIAL is reliable and the absolutes drift; and removing near-copies is a NON-random
subsample, so it is the lower bound on the correction - the Arabidopsis result implies true FDP is
below 0.695%.

Tool: `ai/scripts/Osprey/Entrapment/contamination_corrected.py`.

## Progress Log

### 2026-08-02 (night session) - FDP series measured on Astral, 40 files, three libraries

Same 40-file TDP-43 cohort searched against three libraries differing in one variable at a time,
Stage 1-5 only (`--task FirstPassFDR`, which preserves the pass-1 mdiag sidecar). Osprey
**v26.1.1.213** (pwiz master `0245ad7a21`); `delivered` reused existing parquets at
**26.1.1.211**. Each arm ~2 h 48 m.

#### Predictions vs outcomes

| step | predicted | measured | verdict |
|---|---|---|---|
| ungated -> gated | FDP falls **20-25%** | **-24.6%** | **CONFIRMED**, top of band |
| gated -> arabidopsis | falls a further **5-10%** | **+125%** | **FALSIFIED, opposite direction** |
| arabidopsis absolute | ~**0.65-0.70%** | **1.183%** | **FALSIFIED** |
| delivered vs ungated | isolates peptdeep model version | **0.837% vs 0.837%** | **no effect** |

#### The series

| variant | disc@1%q | trueFDP% | nEnt | matched@1% | eff% |
|---|---|---|---|---|---|
| delivered *(confounded ref)* | 24,153 | 0.837 | 196 | 25,173 | 76.36 |
| **ungated** *(baseline)* | 24,413 | 0.837 | 198 | 25,193 | 78.78 |
| **gated** | 25,064 | 0.743 | 180 | **26,379** | **80.18** |
| **arabidopsis** | 23,385 | **1.183** | 268 | 22,550 | 69.24 |

**Matched-discovery control** (all arms at 23,385 accepted targets) - this is the comparison
that isolates the entrapment change, because the arms do not accept the same number of targets
at matched q:

| | FDP | vs ungated |
|---|---|---|
| ungated | 0.736% | - |
| **gated** | **0.525%** | **-28.7%** |
| arabidopsis | 1.183% | **+60.9%** |
| delivered | 0.705% | -4.2% |

#### 1. The gate works, and both axes improve at once

At matched discoveries the gate cuts measured FDP **24.6%** (at the 24,413 common point) to
**28.7%** (at 23,385) - squarely in the pre-registered band and consistent with the post-hoc
estimate. **At matched reported q the drop reads only -11.2%**, because gated also accepts
+2.67% more targets and therefore sits further along its own curve. Both are true; only the
matched-discovery figure isolates the entrapment change. Report both, lead with the control.

Gated simultaneously finds MORE: disc@1%q **+2.67%**, matched@1% **+4.71%**, union efficiency
78.78 -> **80.18**. Not a sensitivity/accuracy trade.

Gate confirmed in the ACCEPTED set, not just library-wide: **0 near-copies among 913 accepted
entrapment** vs ungated's 59/826 (7.1%, **1.8x** enriched).

#### 2. The +4.7% gain is ORACLE CORRECTION, not extra detection

Post-hoc near-copy removal on the ungated run predicted matched **+4.6%**; the gated arm
measured **+4.71%**. Post-hoc surgery never touches the search - it only cleans the oracle of an
unchanged run - so reproducing the whole gain without changing the search shows these are not
newly detected peptides. They are peptides the contaminated oracle was falsely flagging,
recovered once the 1%-true-FDP frontier stops being dragged in by near-copy hits.

#### 3. The competition effect is bounded SMALL

Post-hoc predicted **-19.2%**, measured **-24.6%**: directionally larger, as genuine competition
would produce. Sized honestly, that is **11 more entrapment removed than predicted against a
Poisson sigma of ~13-14 - under 1 sigma**. Bounded small, not shown absent. Settling it needs a
larger cohort.

#### 4. The peptdeep model version is worth ~nothing in measured FDP

`delivered` and `ungated` share only **15.9%** of target fragment lists, **0%** at identical
intensities, differ by 2.8M fragment rows and up to 0.33 min in RT - and report **the same FDP
to three decimals (0.837%)**, with matched discoveries **+0.08%**. Verified across the sweep,
where intermediate cuts differ in both directions (+19% at q<=0.005, -6% at q<=0.015, ~1.2
sigma). **Measured FDP is robust to the prediction basis**, so past cross-model comparisons are
less compromised than feared. Only efficiency moved (76.36 -> 78.78).

#### 5. THE SURPRISE: real Arabidopsis entrapment measures MUCH HIGHER FDP, not lower

**This contradicts both the prior expectation and the other machine's Stellar result**, which
measured 1.62% -> 1.15% (**-29%**) substituting Arabidopsis entrapment. Here the same
substitution goes the other way: `gated -> arabidopsis` is **0.525% -> 1.183% at matched
discoveries (+125%)**.

It is not noise and not an arithmetic artifact:

* arabidopsis is higher at **every** cut of the sweep (0.508/0.631/0.955/1.183/1.798/2.357 vs
  ungated 0.220/0.466/0.636/0.837/1.209/1.606) - consistent separation, nEnt 268 at 1% (+-6.1%);
* **`r` is identical to three decimals** across arms (0.96993 / 0.96969 / 0.96903), and targets
  match to 0.04%;
* arabidopsis carries only **+1.6%** more entrapment in the library but gets **+35%** more of it
  ACCEPTED - a per-entry acceptance-rate effect;
* **0 near-copies** among its accepted entrapment, so contamination cannot explain it;
* **0 sequence collisions** with the human target set (checked over all three libraries), so
  these are not genuinely-present peptides.

Arabidopsis is also WORSE on sensitivity: matched **25,193 -> 22,550 (-10.5%)**, efficiency
**78.78 -> 69.24 (-9.5 pts)**.

**What is ruled out so far.** Peptide LENGTH is matched (entrapment mean 15.691 vs target
15.726; len<=8 16.49% vs 16.41%). What is NOT matched is amino-acid composition:
**P -1.392, Q -1.383, S +1.012, I +0.887, N +0.777, D +0.738** percentage points. The shuffle
libraries score **exactly 0.000 on every residue** - the anagram design is composition-matched
BY CONSTRUCTION, and foreign-species entrapment is not. Proline especially drives fragmentation
behaviour. Modest, and probably not sufficient alone for +60%, but it is a real measured
asymmetry in the null model.

**What gets ACCEPTED differs sharply, from identical pools.** Both entrapment pools have the
same length distribution (shuffle is target-matched by construction, 15.73; Arabidopsis 15.69),
so any difference in the accepted set is a property of matching, not of the pool:

| arm | accepted entrapment mean len | len<=8 | accepted targets mean len | len<=8 |
|---|---|---|---|---|
| ungated (shuffle) | **9.98** | **48.5%** | 12.47 | 15.5% |
| gated (shuffle) | 10.69 | 41.0% | 12.58 | 14.6% |
| **arabidopsis (real)** | **11.53** | **27.8%** | 12.55 | 14.9% |

All entrapment is short-skewed relative to its pool - short peptides carry fewer fragments and
are matched spuriously more often, as expected. But **shuffle entrapment's acceptances are
concentrated in trivially short peptides (48.5% at <=8 residues) while Arabidopsis's sit much
closer to the real target profile (27.8%)**. Arabidopsis does not merely produce MORE false
positives; it produces more TARGET-LIKE ones. That is what a null modelling genuine false
discovery should look like, and it is a point in favour of reading 1 - though it does not settle
it, because a composition-driven matching advantage would also raise acceptance at longer
lengths.

**The two readings, both consequential, not yet separated:**

1. **Arabidopsis is the more honest null and shuffle UNDER-estimates FDP.** Shuffled sequences
   are unnatural and out-of-distribution for peptdeep, so their predicted spectra may be poor
   and they may be under-identified. If so true FDP at 1% reported q is ~1.18%, not 0.84%, and
   Osprey is mildly anti-conservative rather than conservative.
2. **Arabidopsis is a biased null that over-reports.** The composition skew and whatever else
   distinguishes a foreign proteome makes its peptides easier to match spuriously than the
   absent human peptides they are meant to model.

These have opposite implications for how FDR should be validated.

**Reading 1's proposed MECHANISM was tested directly and is too weak to carry the effect.**
`predicted_spectrum_quality.py` compares the predicted spectra in the libraries themselves, no
search needed (sampled by sequence hash, ~800 precursors per class):

| library / class | nfrag | entropy | top ion % |
|---|---|---|---|
| ungated / target | 14.82 | 2.1658 | 28.34 |
| ungated / **entrapment (shuffle)** | **14.57** | **2.1445** | **29.02** |
| arabidopsis / target | 14.81 | 2.1663 | 28.31 |
| arabidopsis / **entrapment (real)** | **15.11** | **2.1968** | **27.77** |

Targets agree across libraries to 4 significant figures, re-confirming the shared prediction
basis. And the direction is exactly what reading 1 predicts: shuffled entrapment gets slightly
POORER predicted spectra than real peptides (fewer fragments, lower entropy, more dominated by
a single ion) while real Arabidopsis entrapment gets slightly RICHER ones. **But the magnitudes
are 1-3%**, which cannot plausibly produce a 35% difference in acceptance rate or 125% in FDP.

**Important limit of this test**: fragment count and entropy measure spectrum RICHNESS, not
ACCURACY. A shuffled peptide could receive a perfectly rich prediction that is simply WRONG,
and this test would not see it. So it rules out "shuffles get obviously degenerate predictions"
but not "shuffles get confidently wrong ones" - which remains reading 1's live mechanism and
needs ground-truth spectra to test.

#### 6. ROOT CAUSE, PARTIAL: I/L-isobaric entrapment is genuinely PRESENT, and no gate catches it

**Leucine and isoleucine have identical residue masses (113.08406).** An entrapment peptide
differing from a human target only by I<->L is mass-identical AND produces an identical fragment
ladder - **indistinguishable by mass spectrometry**. It is not a model of a false discovery; it
will be detected wherever its human twin is, and every such detection is counted as false when
it is not.

The exact-string collision audit run earlier reported **0** for all three libraries and missed
this completely. Under I->L normalisation:

| arm | library colliding | **accepted** colliding | enrichment vs library | FDP corrected |
|---|---|---|---|---|
| ungated | 735 (0.0529%) | 8/363 (2.20%) | **41.7x** | 0.868% -> 0.835% (**-3.8%**) |
| gated | 678 (0.0487%) | 11/383 (2.87%) | **58.9x** | 0.758% -> 0.718% (**-5.3%**) |
| **arabidopsis** | 1,043 (0.0749%) | **39/472 (8.26%)** | **110.3x** | 1.240% -> **0.983%** (**-20.7%**) |

**The 40-110x enrichment among ACCEPTED entrapment is the proof.** If these were ordinary
entrapment they would be accepted at roughly the library base rate. Being accepted 40-110x more
often is what "genuinely present in the sample" looks like.

**This explains roughly HALF the Arabidopsis excess.** After correction the gap against ungated
narrows from **+42.9% to +17.7%**. And the reason foreign-species entrapment is hit hardest is
the conserved-protein route flagged before the arms ran: plant and human share conserved
proteins whose tryptic peptides differ by conservative I<->L substitutions. **That concern was
correct; it was tested with too strict a comparison** (exact string equality) and so read as
clean.

**The similarity gate does not catch this** - `gated` still carries 678 colliders, because the
fragment-overlap gate compares each entrapment to its OWN paired target while a collision is an
exact isobaric match to a DIFFERENT one.

**Actionable**: the entrapment generator should reject any candidate whose I->L normalised
sequence appears in the target set. Cheap (one hash set), and it removes a 4-5% FDP
over-estimate on shuffle libraries and ~21% on foreign-species ones.

**The gate conclusion is robust to this correction** - on I/L-corrected numbers the gate still
moves 0.835% -> 0.718% (**-14.0%** in reimplementation terms, vs -12.7% uncorrected), so
correcting the oracle slightly INCREASES the measured benefit of the gate.

**Nothing in this experiment separates the two readings for the REMAINING +17.7%.** See "Open
questions" below.

#### Confounds closed by measurement before the arms ran

* **Shared prediction basis, verified for BOTH controlled steps.** `ungated` vs `gated`:
  **3,126/3,126 (100.0%)** identical target fragment m/z lists, RT identical to 4 decimals.
  `ungated` vs **`arabidopsis`**: **3,126/3,126 (100.0%)** likewise. So all three controlled
  arms carry byte-identical target predictions, and **the +125% arabidopsis result cannot be
  attributed to a different prediction basis.** (For contrast, `delivered` vs `ungated` is only
  **15.9%** identical - which is why delivered is a reference and not a baseline.)
* **Ratio**: all three manifests are perfect quartets, **r = 1.000000**, arms differing by only
  753-755 quartets (0.054%).
* **Arabidopsis/human sequence collisions**: **0 (0.0000%)** on EXACT sequence in all three
  libraries - a failure mode the fragment-overlap gate cannot catch, since it compares each
  entrapment only to its own paired target. **But see finding 6: this test was too strict.**
  Under I->L normalisation (the two residues are isobaric, so such peptides are
  indistinguishable by MS) the counts are **735 / 678 / 1,043**, and they are enriched
  **40-110x** among accepted entrapment. The exact-match result above is correct but
  insufficient, and should never be quoted on its own.
* **Cohort identity**: all arms use the same 40 files, verified file-by-file.

#### Tooling added (pwiz-ai)

`entrapment_target_collision.py`, `posthoc_gate_prediction.py` (cohort-matched post-hoc,
validated against the 163-file -22.3%), `entrapment_composition.py`, `libseries.ps1` (serial
idempotent driver), and `pass1_entrap.py` gained `OSPREY_PASS1_QCUT`.

**Trap fixed**: `pass1_entrap.py` hardcoded `QCUT = 0.01`, but the matched-true-FDP frontier
sits ABOVE q=0.01, so a 0.01 harvest truncates the search and the frontier saturates at the
q<=0.01 count **by construction** - reading as a result rather than a truncation. The 163-file
`arm_*.json` were harvested to 0.03; use 0.03 for anything compared against them.

#### Open questions

0. **SHIP THE I/L GATE** (finding 6). Reject any entrapment candidate whose I->L normalised
   sequence is in the target set. One hash set at generation time; removes a **4-5%** FDP
   over-estimate on shuffle libraries and **~21%** on foreign-species ones. Independent of, and
   complementary to, the fragment-overlap gate - which does not catch it. This is the most
   actionable result of the series.

1. **Astral vs Stellar disagree on Arabidopsis entrapment, in opposite directions.** Same
   substitution, -29% there and +125% here. **Re-check the Stellar result for I/L collisions
   first** - if its Arabidopsis library had few, that alone could reverse the sign, and it is a
   cheap check on an existing library. Reconciling these remains the most important open item;
   one of the two results is measuring something other than FDP.
2. **Test whether shuffled sequences are under-identified because peptdeep predicts them
   poorly.** Compare predicted-spectrum properties (fragment counts, intensity distribution)
   between shuffled and real-peptide entrapment in the same library build. This is the
   discriminating experiment for reading 1 vs reading 2, and it needs no new search.
3. **The gate's discovery gain is not attributable to entrapment alone** - the gate was applied
   to DECOYS as well (rejectable decoys 1.5840% -> 0%), and reported q comes from the
   decoy-trained model. The matched-discovery FDP result is unaffected; the +2.67% disc@1%q
   should be described as "gate applied to both populations".
4. Competition effect needs a larger cohort to move from bounded-small to measured.

Raw diagnostics preserved: `ai/.tmp/mdiag-archive/<variant>.model-diagnostics.{html,data.json}`
for all four arms, plus 40/40 `.1st-pass.fdr_scores.bin` and `.scores.parquet` per arm on D:.

### 2026-08-01 (later) - Carafe half implemented and validated; libraries building

Branch `feature/decoy-similarity-gate` on `maccoss/Carafe` (commits `037980b`, `c3f8fc2`).
Full suite green: 116 tests, 0 failures, including 11 new ones.

**Implemented**: `DecoySimilarityGate` (transcription of the C#/Rust rule, same 0.4 / 0.02 Da
constants, sharing Carafe's existing residue-mass table because a 1e-5 Da difference cannot move a
0.02 Da window); bounded retry (20 attempts) on the entrapment shuffle; the gate on both
`generateReverseDecoy` accept conditions; and `-entrapment_db` / `-entrapment_ratio` for
foreign-species entrapment.

**The validation that matters**: `-no_similarity_gate` reproduces the pre-gate behaviour, and an
ungated Astral rebuild reproduces Mike's delivered library **exactly** - `osprey_library_db_peptides.fasta`
byte-identical by SHA256 over 349 MB, and all **1,390,979** manifest quartets identical in target,
p_target, decoy and p_decoy. So the digest parameters are confirmed and the gated library differs
from the delivered one **only** by the gate. That converts every number below from an inference
into a measurement.

**Cost of the gate on Astral** (1,392,350 digested targets):

| | count | of targets |
|---|---|---|
| entrapment changed | 58,319 | **4.19%** |
| decoy changed | 24,257 | 1.74% |
| dropped, no acceptable entrapment | 155 | 0.011% |
| dropped, no acceptable decoy | 449 | 0.032% |

The 4.19% independently reproduces the 4.15% library-wide rate measured by the Python audit
tooling - two implementations, same answer.

**The loss is structured and benign**, as predicted: 60% of dropped peptides are >=50% a single
residue against 0.7% of kept ones (median single-residue fraction 0.571 vs 0.200) - poly-A/G/E/Q
and collagen-like repeats (`GGGGGGGGDGGGR`, `QQQRQQQQQQQQK`, `PGSPGPPGSPGPR`, `RPPPPPPPPPPR`).

**The retry more than pays for the gate.** It also rescues peptides the old one-shot shuffle
dropped on an exact collision, so the gated build keeps **1,391,732** targets vs the delivered
**1,390,979** - a net GAIN of 753. Cost/benefit on this task is better than the TODO assumed.

**A finding worth keeping, on the foreign-entrapment assignment.** The objective is to maximize the
NUMBER of target/entrapment pairs sharing an isolation window - a threshold - not to minimize total
mass displacement, and the two want different algorithms. Nearest-available in mass order
accumulates a deficit and reaches 81%; the quantile map is the optimal monotone transport and has
the best worst case but spreads error evenly across every pair, reaching only 49%; nearest-available
in sequence order gets 95% with a bad tail. Binning at 0.25 Da and serving from the nearest
non-empty bin gets **99.86%** (median |dm| 0.043 Da, 99th 1.16 Da). Optimizing the average when the
criterion is a threshold was the wrong instinct and cost two rebuilds to see.

**Arabidopsis at r=1.0 on Astral is feasible**, which was not obvious: the pool is 1,454,810
candidates against 1,392,350 targets, only 4.3% headroom, and all targets matched. Zero entrapment
gate failures on the foreign path against 155 on the shuffle path - direct evidence that foreign
peptides do not shadow their targets the way anagrams do.

**Both Astral libraries are BUILT and audited clean.** Under an hour total on an RTX 4070
(stage 2 6.0 min, stage 3 7.7 min, stage 4-5 15.1 min per variant) because stages 1a/2/3 are
entrapment-free and shared.

| | delivered | library 1 (gated shuffle) | library 2 (Arabidopsis r=1.0) |
|---|---|---|---|
| quartets | 1,390,979 | 1,391,732 | 1,391,734 |
| library size | 13.09 GB | 11.84 GB | 11.97 GB |
| rejectable entrapment | 4.05% | **0%** | **0%** |
| rejectable decoys | 1.70% | **0%** | **0%** |
| median entrapment overlap | 0.100 | 0.100 | **0.024** |

Audited in FULL (all 1.39M quartets), not sampled, with the new
`ai/scripts/Osprey/Entrapment/library_overlap_audit.py`. Packaged as drop-in replacements at
`D:\test\AstralTest-TargetDecoyLibraries\target+decoy+entrapment-{gated,arabidopsis}\`, each with
a PROVENANCE.txt and a transport zip.

The fine-tune metrics are **identical between the two variants** (RT R² 0.9971, MS2 COS 0.9778)
because both use the same training blib and seed - so the RT/MS2 model is held constant and the
only difference between the libraries is which peptides were predicted. That is what makes them a
controlled A/B rather than two separate builds.

**Two effects to keep separate.** The gate removes the *tail* - by construction nothing survives
above 0.4. Foreign entrapment shifts the *whole distribution*: median overlap 0.024 vs 0.100 and
median positional identity 3.2x lower, before any gating. A shuffle is an anagram of its target
and shares its fragment masses however it is permuted; a real foreign peptide does not.

**Transient GPU fault worth knowing about**: variant 2's prediction died with a native
`0xC0000409` (no Python traceback) while several workers loaded models onto the GPU seconds after
variant 1 released it. Data was ruled out first (identical alphabet, identical 7-35 length range,
entry counts within 8); a clean retry succeeded in the same 15.1 min.

**Still to do**: a validation search of the new libraries (the accepted-set audit, ~27% -> ~0, needs
a real run - the library-level audit above cannot measure enrichment among hits); re-running both
datasets' mean(best-N) arms; and the Skyline half (Fisher-Yates + gate), which is untouched.

### 2026-08-01 - Problem isolated, landscape surveyed, decision taken

Root cause traced from measured output back to source across four implementations. Decision to
gate on fragment overlap only is backed by the marginal-value measurement above rather than by
the "checkbox coverage" reasoning that produced the original C#/Rust gates - which turned out to
have picked the right one of the two.
