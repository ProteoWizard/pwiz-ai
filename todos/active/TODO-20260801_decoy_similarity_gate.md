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
built. The Skyline half has moved out to
[pwiz #4516](https://github.com/ProteoWizard/pwiz/issues/4516).

> **CORRECTION 2026-08-02.** This file previously said Osprey C# and Rust need **no change** -
> "they are already correct and already agree". That was true of the *fragment-overlap gate* and is
> now **stale**: it predates the I/L finding, which is an independent defect neither implementation
> has. Both still use an EXACT-string collision check
> (`DecoyGenerator.cs:264,280`; `osprey-scoring/src/lib.rs:3440,3463`) and neither normalises I to L
> anywhere. Simulating Osprey's own gendecoy path (reverse -> cycle, **overlap gate ON**) over the
> 1,390,979-target Astral set gives **0 exact** collisions and **742 I/L-isobaric** ones (0.0534%) -
> e.g. `AAEESLR -> LSEEAAR`, `ADILLLR -> LLLIDAR`. That rate matches the 792 measured in Carafe's
> library decoys, and it is empirical proof the overlap gate does NOT catch this, since the gate
> compares a candidate to its OWN source while a collision is a match to a DIFFERENT target.
>
> This matters more for decoys than for entrapment: decoys drive the FDR *estimate* through
> target-decoy competition, so a decoy indistinguishable from a real target wins on that target's
> own signal. See "Osprey I/L gap" in the task list.

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

## UI spec

`TODO-20260801_decoy_similarity_gate-carafe-spec.html`, beside this file - open it in a browser.
Traced from the running Carafe 2.2.0 Osprey tab, so the mockups match real row heights and label
column rather than approximating them. Covers the three progressive-disclosure states, a
control reference with settings keys and CLI mapping, validation, and what is deliberately NOT
exposed on the panel.

The part worth reading even if you do not care about UI: hiding rows means a hidden field keeps
its value, so the command must be built from the LOGICAL state (checkbox on AND source is FASTA)
rather than from field contents. Otherwise switching the source back to Shuffle silently builds a
foreign-entrapment library. Same class of bug as any stale-state-leaks-into-output defect.

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
- [x] **DONE 2026-08-02 - Carafe I/L-normalised collision rejection.** Commit `fe25b55`.
      Reject any entrapment candidate whose **I->L normalised** sequence appears in the I->L
      normalised TARGET set. One hash set at generation time.
      **Implementation notes.** The normalised comparison SUBSUMES the exact one (a sequence with
      no isoleucine normalises to itself), so it replaces the existing collision check rather than
      adding a second lookup. Applied to **decoys as well as entrapment** - the same argument
      holds, a decoy indistinguishable from a real target is not a valid null either, it just
      inflates the decoy count instead of the entrapment count.
      **`-no_similarity_gate` had to mean "reproduce the pre-FIX generator"**, skipping I/L
      rejection too and not merely the overlap gate. Making I/L unconditional would have broken the
      byte-reproduction oracle; verified still intact, an audit build reproduces the delivered
      `osprey_library_db_peptides.fasta` at identical SHA-256 over 349 MB.
      **Measured on Astral, against the night session's independent counts:**
      gated shuffle **663** entrapment sequences changed + **10** more dropped for having no
      acceptable alternative = 673, vs **678** colliders measured in that library. Arabidopsis
      **1,116** candidates dropped from the pool vs **1,043** measured in the built library - the
      pool is only ~95.7% consumed and 1,043/1,116 = 93.5% matches the assignment rate. Also
      **1,562** decoys changed. And the reason an exact-string audit read clean: **2,608** exact
      matches were ALREADY being filtered, so only the isobaric ones survived to be counted.
      **Independent of the fragment-overlap gate, which cannot catch this**: the gate compares each
      entrapment to its OWN paired target, while a collision is an exact isobaric match to a
      DIFFERENT one. An exact-string audit reports 0 for every library and misses it entirely.
      Measured (night session 2026-08-02): 735 / 678 / 1,043 colliders per library, enriched
      **41.7x / 58.9x / 110.3x** among ACCEPTED entrapment - the signature of a peptide that is
      genuinely present. Removes a **4-5%** FDP over-estimate on shuffle libraries and **~20.7%**
      on foreign-species ones.
      Shipped WITH the FASTA source flag, as required: foreign proteomes are hit hardest, because
      plant and human share conserved proteins whose tryptic peptides differ by conservative
      I<->L substitutions. A regression test asserts the overlap gate PASSES a candidate the
      collision index rejects, which is the property proving the two checks are independent rather
      than redundant.
- [x] **DONE 2026-08-02 - Carafe GUI for the entrapment options.** Commit `9fc114c`. Source combo,
      FASTA path with Browse/Download, and ratio spinner under the existing checkbox, hidden rather
      than disabled so the panel is unchanged when entrapment is off. Spec:
      `TODO-20260801_decoy_similarity_gate-carafe-spec.html`.
- [ ] **NEXT STEP on this PR - converge Carafe and Osprey on ONE decoy sequence set, then gate on
      it.** Goal: given the same input sequences, Carafe and Osprey emit the **identical** decoy
      set. That is the strongest available gate, and it buys something specific - it reduces
      "Carafe decoys vs Osprey decoys" to a single variable, namely **predicted spectra + predicted
      RT (Carafe) versus spectra + RT inherited from the target (Osprey)**. Today that comparison
      silently mixes in a second variable, because the two can generate different sequences.

      **Feasible, and closer than it looks - the permutation algorithms are ALREADY identical.**
      Verified line by line 2026-08-02; Carafe's were written from Osprey's and never diverged:

      | | Osprey C# | Carafe |
      |---|---|---|
      | reverse | reverse 0..len-2, keep len-1 | same |
      | cycle | `mid[(i+c) % (len-1)]`, C-term appended | identical formula |
      | retry ladder | cycle 1..min(len,10) | identical |
      | edge cases | len<=2 or c==0 -> unchanged | identical |
      | overlap gate | 0.40 over b/y within 0.02 Da | identical |

      **Four deltas remain, and only the first is a real defect:**
      1. **I/L normalisation** - Carafe has it, Osprey does not (see the task below). Must land
         first; without it the two cannot agree by construction.
      2. **Residue mass tables differ in the 6th decimal** (Osprey `71.037114` vs Carafe
         `71.03711`). As a FILTER this cannot matter - 4e-6 Da per residue against a 0.02 Da
         window. For a BIT-IDENTICAL gate it is not provably harmless across 1.4M sequences: a
         decoy whose overlap ratio sits exactly on the 0.40 boundary could flip if one rung sits
         within ~1e-4 Da of the tolerance edge. Unify the table before claiming parity. **My
         earlier note that this "cannot change a verdict" was right for a filter and too loose for
         a gate.**
      3. **Enzyme handling** - Osprey conditions C-term preservation on
         `_enzyme.PreservesCTerminus()`; Carafe always preserves. Agree for trypsin, may not for
         other enzymes. Either match the condition or scope the gate to tryptic.
      4. **Collision universe** - Carafe checks against targets + entrapment, Osprey against the
         library's target sequences, and Osprey additionally skips entries with no fragments. These
         are INPUT differences, not algorithmic ones; the gate should feed both the same sequence
         list so they fall away.

      **The gate**: a committed list of input sequences (include the nasty ones - poly-A, poly-G,
      collagen repeats, I/L palindromes, len 7 and len 35) plus the expected decoy for each, checked
      by a unit test in Carafe, Osprey C# and Osprey Rust. Cheap, no spectra, no GPU, and it fails
      the moment any implementation drifts. It also subsumes the existing ad-hoc claim that the
      three "agree" - which turned out to be false for I/L precisely because nothing tested it.

      **Then the real experiment becomes clean**: same sequences, same decoys, and the only
      difference between the two libraries is where each decoy's spectrum and RT came from.
- [ ] **NEW 2026-08-02 - Osprey I/L gap (C# AND Rust), needs a decision before implementing.**
      Neither has I/L-normalised collision rejection; both check exact strings only. Measured 742
      colliding decoys (0.0534%) in a simulation of Osprey's own gendecoy path over the Astral
      target set, with the overlap gate on.
      **Why this is not a quick fix.** It changes generated decoy sequences, so it changes output:
      it needs a deliberate golden re-baseline via `regression.ps1`, and it must land in C# and
      Rust **together** to keep the cross-impl parity gate meaningful. That is a different class of
      change from the Carafe work, which had no golden to break.
      **Scope question to settle first**: production searches use `--decoys-in-library` with
      Carafe-supplied decoys, which are now gated at the source, so this only bites runs that let
      Osprey generate its own decoys. Worth confirming how much that path is still used before
      spending a re-baseline on it.
- [ ] ~~**Skyline**~~ - MOVED to [pwiz #4516](https://github.com/ProteoWizard/pwiz/issues/4516),
      which also covers making the shuffle Fisher-Yates (consistent with Carafe) and removing
      `ADD_RANDOM` entirely. Original note kept below for context.
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

### 2026-08-02 - Carafe half implemented end to end; five Astral libraries delivered

**Carafe branch `feature/decoy-similarity-gate`, 8 commits, LOCAL AND UNPUSHED, 121 tests green.**
Cannot push: `maccoss/Carafe` reports `push: false` for brendanx67 and no fork exists. Either
request collaborator access (recommended - matches the `maccoss/osprey` arrangement, and this will
not be the last Carafe change) or fork. **Not done unilaterally; it is a decision about a repo we
do not own.**

Commits: overlap gate + bounded retry; co-location assignment for foreign entrapment; two seed
reviewer-notes; ratio floor; I/L collision rejection; GUI; GUI layout fix.

**Five Astral libraries built, audited and delivered** to
`D:\test\AstralTest-TargetDecoyLibraries\` and copied to
`M:\home\brendanx\data\MacCoss\Osprey\AstralLib` (6 zips, each byte-count verified):

| library | quartets | near-copies | I/L colliders (ent / dec) |
|---|---|---|---|
| `-ungated` (baseline) | 1,390,979 | 4.22% | 742 / 792 |
| `-gated` | 1,391,732 | 0% | 678 ent |
| `-gated-no-il` | 1,391,588 | **0%** | **0 / 0** |
| `-arabidopsis` | 1,391,734 | 0% | 1,043 ent |
| `-arabidopsis-no-il` | 1,391,655 | **0%** | **0 / 0** |

All five share ONE prediction basis - fine-tuned `ms2_model.pt`/`rt_model.pt` byte-identical by
SHA-256 across five separate Carafe invocations - so `ungated -> gated -> gated-no-il` and
`-> arabidopsis -> arabidopsis-no-il` are each single-variable chains.

**Findings worth keeping:**

1. **Fine-tuning is deterministic given the same blib and seed.** Three separate invocations
   produced byte-identical models and 100.0% identical target predictions (3,126/3,126 fragment
   m/z lists, RT identical). So a controlled comparison needs a shared prediction BASIS, not
   literally one invocation - which is worth knowing because "must share one run" would force
   rebuilds that are not necessary. Across peptdeep model VERSIONS it collapses to 56.3%.
2. **The foreign-entrapment assignment optimises a threshold, not an average, and the two want
   different algorithms.** Nearest-available in mass order 81% co-location; quantile map (optimal
   transport) 49%; nearest-available in sequence order 95%; bin-based 99.86%. Optimising mean
   displacement was the wrong instinct and cost two rebuilds.
3. **The audit tooling gained I/L detection and a p_decoy relationship**, and both confirmed draft
   claims that were previously uncheckable: p_decoy 1.8889% -> 0% (draft said 1.86%), and a
   colliding DECOY population nobody had measured (792, alongside 742 entrapment, both 0 exact).
4. **Every rate in the PR draft is sample-based and runs slightly under the full-manifest value**
   (4.05/4.22, 1.70/1.74, 1.86/1.89). Both are now given in the draft.
5. **`-no_similarity_gate` had to mean "reproduce the pre-FIX generator"**, skipping I/L as well as
   the overlap gate, or the byte-reproduction oracle would have been spent. Verified still intact.

**Skyline half moved out** to [pwiz #4516](https://github.com/ProteoWizard/pwiz/issues/4516), which
also covers Fisher-Yates (consistent with Carafe) and removing `ADD_RANDOM` entirely.

**Osprey is NOT as rigorous as Carafe** - see the correction at the top of this file and the two
new tasks. 742 I/L-colliding decoys measured by simulating its own gendecoy path.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260802_decoy_similarity_gate.md` before starting work.

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

**IMPLEMENTED on the Carafe machine same day**, with two new libraries delivered:
`-gated-no-il` (1,391,588 quartets) and `-arabidopsis-no-il` (1,391,655). Independently
verified here from the manifests: **0 entrapment collisions, 0 decoy collisions, 0 exact** in
both. All five arms share one prediction basis (fine-tuned `ms2_model.pt` / `rt_model.pt`
byte-identical by SHA256 across all five Carafe invocations), so
`ungated -> gated -> gated-no-il` and `ungated -> arabidopsis -> arabidopsis-no-il` are both
single-variable chains.

**COLLIDING DECOYS - a second population, not previously measured.** The Carafe machine's
extended audit surfaced **792** I/L-colliding DECOYS in the ungated baseline (789 distinct).
Same mechanism, different consequence: a decoy that is isobaric with a real target is really a
target, so it scores well and is counted as a decoy win - **inflating the decoy count at good
scores and making reported q too CONSERVATIVE**. That is the opposite direction from colliding
entrapment (which inflates measured FDP), so the two contaminations distort the reported-q axis
and the true-FDP axis independently. `-gated-no-il` and `-arabidopsis-no-il` clear **both**, so
they test the combined effect rather than the entrapment half alone.

**Counting convention, agreed across machines.** The Carafe audit reports **742** entrapment
colliders where this machine measured **735**. Both are correct: 742 is ROWS, 735 is DISTINCT
sequences, and the 7-count gap is exactly the duplicate-entrapment population measured earlier
(324 sequences appearing more than once in the ungated shuffle pool). Decoys likewise 792 rows /
789 distinct. **Prefer DISTINCT sequences as the contamination denominator** - a sequence
duplicated across charge states is one contaminated peptide, not two.

**The gate conclusion is robust to this correction** - on I/L-corrected numbers the gate still
moves 0.835% -> 0.718% (**-14.0%** in reimplementation terms, vs -12.7% uncorrected), so
correcting the oracle slightly INCREASES the measured benefit of the gate.

**Nothing in this experiment separates the two readings for the REMAINING +17.7%.** See "Open
questions" below.

#### 7. THE I/L FIX MEASURED DIRECTLY - and it REVERSES the Arabidopsis surprise

The Carafe machine shipped the I/L gate same-day; `-arabidopsis-no-il` was searched on the same
40 files (3 h 11 m, v26.1.1.213).

| variant | disc@1%q | trueFDP% | matched@1% | eff% | matched-disc FDP vs ungated |
|---|---|---|---|---|---|
| ungated | 24,413 | 0.837 | 25,193 | 78.78 | - |
| gated | 25,064 | 0.743 | 26,379 | 80.18 | **-28.7%** |
| arabidopsis | 23,385 | 1.183 | 22,550 | 69.24 | **+60.9%** |
| **arabidopsis-no-il** | **26,085** | **0.992** | **26,085** | **78.71** | **-17.3%** |

**Removing I/L collisions takes the Arabidopsis arm from +60.9% WORSE than the shuffle baseline
to 17.3% BETTER**, while gaining **+11.5% discoveries** and **+9.5 points** of union efficiency.
**Finding 5's surprise was an artifact of I/L contamination, not a property of foreign-species
entrapment.** With the contamination removed, foreign entrapment behaves as the guide and the
Stellar result predicted - which substantially defuses open question 1.

Fix verified end to end: `il_collision_correction.py` finds **0** colliders in the library and
**0** among 459 accepted entrapment, and is a no-op on this arm (identical numbers before and
after) - the behaviour a clean library must show.

**Decomposition: most of the gain is the DECOY half, not the entrapment half.** Entrapment
removal cannot change the discovery set - it only relabels which accepted precursors count as
false - so any discovery gain is attributable to the decoys:

| | predicted, entrapment only | measured, both | attributable to decoys |
|---|---|---|---|
| matched@1% | 22,273 -> 23,505 (**+5.5%**) | 22,550 -> 26,085 (**+15.7%**) | **~+10 pts** |
| disc@1%q | unchanged by construction | 23,385 -> 26,085 (**+11.5%**) | **all of it** |

The magnitude is arithmetically consistent: at 1% FDR with ~26,000 targets there are ~260
decoys at threshold; if colliding decoys are accepted at the rate colliding entrapment were
(3.7% of 792 ~ 30), removing ~30 of ~260 threshold decoys relaxes the cutoff by ~11.5%, matching
the observed gain. **This is a consistency argument, not a measurement** - confirming it needs
the decoy-side accepted counts, which the pass-1 harvest does not currently retain.

**If it holds, colliding decoys were costing ~11.5% of all discoveries at 1% q** - a larger
practical win than the entrapment fix, and one nobody was looking for.

**The pre-registered caveat is what made this readable.** Before the arm ran, it was recorded
that "if the result overshoots the -20.7% prediction, the decoy half is the first thing to
suspect rather than the competition effect". It overshot to **-48.6%** at matched discoveries -
more than double - and the decoy attribution follows from the structural fact that oracle
surgery cannot move discoveries.

**CORRECTION to the power analysis that ordered these arms.** `gated-no-il` was scheduled second
on the grounds that its predicted entrapment-only effect (-5.3%) sits under Poisson noise and so
"cannot resolve its own prediction". That reasoning covered only the entrapment half and
**understated the arm's value**: the decoy correction is the larger effect, is not subject to
that noise floor, and `gated-no-il` vs `arabidopsis-no-il` is now the ONLY clean comparison of
anagram vs foreign entrapment, since `gated` still carries 678 colliders. The ordering happened
to be right for the wrong reason.

#### 8. THE COLLIDING-DECOY EFFECT, MEASURED - and it is a UNIVERSAL win, not an Arabidopsis rescue

Finding 7 attributed the discovery gain to colliding decoys by a consistency argument, and
recorded as open work that `pass1_entrap.py` would need to retain decoy-side counts. **That was
wrong - it already does**, and the correction script was simply skipping them. No re-harvest, no
new run:

| arm | decoys at q<=0.01 | I/L-colliding | fraction |
|---|---|---|---|
| ungated | 258 | 21 | **8.1%** |
| gated | 262 | 15 | **5.7%** |
| arabidopsis | 251 | 19 | **7.6%** |
| **arabidopsis-no-il** | 278 | **1** | **0.4%** |

Predicted ~30 of ~260 from the consistency argument; **measured 19 of 251**. Mechanism confirmed,
magnitude the right order: a **7.6%** cut in effective threshold decoys against an observed
**+11.5%** discovery gain, the remainder plausibly from cleaner SVM negatives sharpening the
ranking.

**The decoy contamination is ROUGHLY EQUAL ACROSS ALL LIBRARIES** (8.1% / 5.7% / 7.6%), unlike
the entrapment contamination which hit Arabidopsis ~4x harder (8.26% vs 2.20% of accepted
entrapment). **So the decoy half of the I/L fix is a universal win that applies to the shuffle
libraries too** - it is not an Arabidopsis-specific rescue, and it is the part with direct
practical value for every user.

Internal consistency check passes: decoys/targets at q<=0.01 is **1.07%** for both `arabidopsis`
(251/23,385) and `arabidopsis-no-il` (278/26,085) - the identical ratio a 1% FDR threshold must
produce. The FDR machinery was behaving correctly; it was being fed 19 fake decoys.

**PRE-REGISTERED PREDICTION for `gated-no-il`** (recorded before it landed). If the decoy
mechanism is right and universal, `gated-no-il` should gain discoveries over `gated` at roughly
the colliding-decoy fraction, scaled as Arabidopsis did (7.6% colliders -> +11.5% discoveries,
~1.5x):

* `gated` removes **5.7%** of threshold decoys -> predicted **+7 to +9%** discoveries,
  i.e. disc@1%q **25,064 -> ~26,800-27,300**;
* entrapment-side effect should be small (only 11/383 accepted entrapment were colliders), so
  the FDP drop at matched discoveries should be modest, **-5 to -10%**.

**A large FDP drop with a small discovery gain would falsify the decoy attribution** and send
the explanation back to the entrapment side.

#### 9. THE EARLY FDP SPIKE: conserved orthologs, and the gate's THIRD blind spot

Brendan spotted an early jump to ~1% FDP at q~0 in the `arabidopsis-no-il` calibration plot -
otherwise very well calibrated, resolving to 0.99% at 1% q. That shape means one or two
entrapment peptides scoring near the very top. It does.

**The top three accepted precursors in the entire run are entrapment** (ranks 1, 2, 3 of 31,320,
tied at q = 1.6e-04), and the identities are diagnostic:

| entrapment | max overlap | matching HUMAN target | protein |
|---|---|---|---|
| `GILAADESTGTIGKR` | **0.857** | `GILAADESTGSIAKR` | **ALDOA_HUMAN** (aldolase A) |
| `GILAADESTGTIGK` | **0.846** | `GILAADESTGSIAK` | **ALDOA_HUMAN** |
| `EILHIQGGQCGNQIGAK` | **0.750** | `EIVHIQAGQCGNQIGAK` | **TBB5_HUMAN** (beta-tubulin) |
| `AAGWGVMVSHR` | **0.650** | `AAQDSFAAGWGVMVSHR` | **ENO1_YEAST** (the spiked RT standard) |
| `GHYTEGAELIDSVLDVVRK` | 0.500 | `GHYTEGAELVDSVLDVVRK` | **TBB5_HUMAN** |
| `IVLIGDSGVGK` | 0.500 | `DDEYDYLFKVVLIGDSGVGK` | RB11A_HUMAN (Rab11) |
| `GQETSTNSIASIFAWTR` | 0.500 | `GQETSTNPIASIFAWTR` | IDHC_HUMAN |

Every one is **above the 0.40 gate threshold**, and every one is a near-copy of an **abundant,
reliably present** protein - tubulin, aldolase, enolase, Rab GTPase. `AAGWGVMVSHR` is a
C-terminal sub-peptide of the yeast enolase RT standard, so its entire y-ion series is shared.

**Note the `_p_target` protein names are the arbitrary human PAIRING partners** (PATZ1, MOCS1,
ZN721), not the Arabidopsis source, so they actively mislead when reading this table.

**Root cause - the gate is PAIRWISE but the contamination is SET-WISE.**
`EILHIQGGQCGNQIGAK` was paired with a PATZ1 peptide, so the gate compared it to PATZ1, found low
overlap, and passed it. It never compared it to beta-tubulin, a different target entirely.
**This is the same structural blind spot as the I/L bug** (finding 6), which was also an exact
isobaric match to a DIFFERENT target. Three manifestations of one root cause:

| # | contamination | caught by current gate? |
|---|---|---|
| 1 | near-copy of its OWN paired target | **yes** |
| 2 | I/L-isobaric with ANY target | no - fixed by the no-il libraries |
| 3 | high fragment overlap with ANY OTHER target | **no - still open** |

**Why foreign-species entrapment is hit hardest**: shuffled human peptides are anagrams, which
essentially never resemble a DIFFERENT human peptide; real Arabidopsis peptides from conserved
proteins are near-identical to their human orthologs **by evolution**.

| arm | accepted entrapment | overlap>0.40 with SOME OTHER target | |
|---|---|---|---|
| ungated (shuffle) | 826 | **1** | 0.1% |
| gated (shuffle) | 913 | **1** | 0.1% |
| arabidopsis | 879 | **33** | 3.8% |
| arabidopsis-no-il | 917 | **25** | **2.7%** |

**~30x worse for foreign entrapment**, and this is a LOWER BOUND - the index only catches
peptides sharing an 8-mer prefix or suffix, so internal similarity is missed.

**Impact is far larger than the 2.7% share implies, because these sit at the TOP of the score
distribution**: removing the 22 identified cross-target near-copies moves FDP
**1.037% -> 0.883% (-14.9%)** and matched discoveries **25,955 -> 26,732 (+3.0%)**.

**This is what produces the spike Brendan saw.** At q~0 only a few hundred precursors are
accepted, so two or three entrapment hits at ranks 1-3 drive the ratio to ~1% before the target
count grows enough to wash it out. The headline 1%-q number barely moves; the low-q calibration
shape is dominated by it.

**THE SPIKE, MEASURED AT THE SIDECAR'S OWN FIRST GRID POINT.** The plot's visible 2.6% / 1.0%
is where the curve returns ON SCALE; the true first point is far above the axis cap:

| arm | entrapment present at the top q | first-point FDP |
|---|---|---|
| ungated (shuffle) | **0** | **0.00%** |
| gated (shuffle) | **0** | **0.00%** |
| arabidopsis | **7** | **177.8%** |
| arabidopsis-no-il | **3** | **152.4%** |

**The shuffle libraries have literally zero entrapment among their top-scoring precursors**;
Arabidopsis had seven and the I/L fix removed four. Independently confirmed: solving the
combined-FDP formula at 1 accepted target gives n_ent = 7.03 and 3.00, matching the per-entry
harvest exactly. On the shuffle side the first entrapment does not appear until **11,216
(ungated) / 10,606 (gated)** targets have been accepted.

**All three survivors exceed 0.40 against SOME human target** - so an all-targets gate at the
EXISTING threshold removes the entire residual spike:

| entrapment | 8-mer index | **true max overlap** | matching human target |
|---|---|---|---|
| `EILHIQGGQCGNQIGAK` | 0.750 | **0.750** | `EIVHIQAGQCGNQIGAK` TBB5 (beta-tubulin) |
| `IVLIGDSGVGK` | 0.500 | **0.900** | `VIILGDSGVGK` **RAB7A** |
| `WVILGHSER` | *no match* | **0.438** | `ADVLEGTAER` MYLK3 |

`IVLIGDSGVGK` vs `VIILGDSGVGK` differ only in the ORDER of the first three residues; everything
from position 4 is identical, so almost the whole y-series is shared with an abundant ubiquitous
GTPase.

**The 2.7% figure above is a FLOOR, not an estimate.** The prefix/suffix index both understates
overlap (0.500 vs a true 0.900 for `IVLIGDSGVGK`) and misses cases outright (`WVILGHSER` scored
0.0 by index, 0.438 in truth). An exhaustive all-targets scan will find more.

**THE THREE CALIBRATION PLOTS, AND WHAT THEY SAY TOGETHER.** Brendan compared all three
experiment-wide FDR tabs directly:

| arm | entrapment at top q | spike | curve vs y=x | FDP @1% q |
|---|---|---|---|---|
| **gated** (shuffle) | **0** | **none** | **below throughout - conservative** | **0.74%** |
| arabidopsis-no-il | 3 | 152% (clipped) | approximately ON the line | 0.99% |
| arabidopsis | 7 | 178% (clipped) | **above throughout - anti-conservative** | 1.18% |

The shuffle arm is spike-free AND conservative across the whole range **even with its 678 I/L
colliders still present** - the contamination that wrecks the foreign-species arm barely
perturbs it, because anagram entrapment almost never resembles a DIFFERENT human peptide.

**THIS LARGELY SETTLES THE "TWO READINGS" QUESTION FROM FINDING 5.** The two nulls disagreed
badly (0.74% vs 1.18%, ~60%) and it was unclear whether shuffle under-reports or foreign
over-reports. With BOTH contamination classes accounted for they nearly converge:

| null | FDP @1% q | state |
|---|---|---|
| shuffle (`gated`) | **0.74%** | measured; its own I/L contamination is small here |
| foreign, I/L removed | **0.99%** | measured (`arabidopsis-no-il`) |
| foreign, I/L **and** cross-target removed | **~0.88%** | ESTIMATED (finding 9's -14.9%) |

**Both nulls then say the same thing: Osprey's reported q is MILDLY CONSERVATIVE at the 1%
operating point, with true FDP somewhere around 0.75-0.90%.** The apparent contradiction was
contamination in the foreign null, not a disagreement about FDR. Reading 2 ("Arabidopsis is a
biased null that over-reports") is essentially confirmed - but the bias is a specific,
fixable library-generation defect rather than an intrinsic property of foreign-species
entrapment.

**The ~0.88% is an ESTIMATE from post-hoc correction, not a measurement.** Confirming it needs
the all-targets gate implemented and a fresh run. That is the one remaining experiment in this
line.

**PROPOSED FIX, AND WHY IT IS NOT YET A SPEC.** The obvious move is to gate entrapment
candidates against **all** targets rather than the paired one. Do NOT hand that over as written -
the 0.40 threshold was calibrated for a PAIRWISE test and is meaningless applied set-wise
against 1.39M targets:

| criterion | gated | arabidopsis-no-il |
|---|---|---|
| overlap > 0.40, any mass | **305 (33.4%)** | **253 (27.6%)** |
| overlap > 0.40, dm <= 5 Da | 50 (5.5%) | 39 (4.3%) |
| overlap > 0.70, dm <= 5 Da | **34 (3.7%)** | **15 (1.6%)** |
| overlap > 0.70, dm <= 1 Da | 34 (3.7%) | 15 (1.6%) |

**A precursor-mass constraint is essential and was missing from the first formulation.** All
three confirmed offenders are mass-matched by construction - `EILHIQGGQCGNQIGAK` vs
`EIVHIQAGQCGNQIGAK` is V->L (+14) with A->G (-14), net **zero**; `GILAADESTGTIGK` vs
`GILAADESTGSIAK` is S->T with A->G, net **zero**; `IVLIGDSGVGK` vs `VIILGDSGVGK` is an anagram,
**identical**. Mass matching is WHY they co-isolate and get detected; a chance 40% fragment
overlap at an unrelated mass is harmless. Adding it collapses the flag rate ~6x, and counts are
stable from 0.60 to 0.70, so there is clean separation rather than a threshold cliff.

**The blocking problem: the criterion does not yet predict the harm.** It flags MORE in `gated`
(3.7%) than in `arabidopsis-no-il` (1.6%), while the observed pathology is the reverse - `gated`
has zero entrapment at the top q and is conservative throughout, `arabidopsis-no-il` spikes. The
missing factor is that the Arabidopsis offenders match **tubulin, aldolase, enolase and RAB7A**,
the most abundant proteins present, while the shuffle offenders match whatever target sits
nearby in mass. **Abundance/detectability is sample-dependent and not a library property**, so a
purely library-level filter cannot currently be threshold-tuned from this evidence.

**ALSO CORRECTED: the earlier "shuffle is clean at 0.1%" figure was an indexing artifact.** It
used raw 8-mer prefix/suffix keys; with a **k=6 I/L-NORMALISED** index the same measure gives
33.4%. The index must be built on I/L-normalised sequences or it misses exactly the class it
hunts - `IVLIGDSGVGK`'s C-terminal 8-mer is `IGDSGVGK` against the target's `LGDSGVGK`, so the
raw index scored it 0.500 when the truth is **0.900**.

**What IS ready to hand over**: the I/L rule (implemented, validated, 0 residual in both new
libraries), the problem statement with named examples, and the structural insight that the gate
is pairwise while contamination is set-wise. **What is NOT ready**: a numeric threshold for the
all-targets gate. Settling it needs the abundance question resolved - e.g. gate against a
curated high-abundance subset, or accept a mass-matched-high-overlap rule and measure the
resulting library empirically rather than tuning on this cohort.

#### 10. WHAT THE FDP:q PLOT ACTUALLY MEASURES - and why that matters for every conclusion above

**Brendan's framing, recorded because it governs how all of finding 9 should be read.** Three
distributions are in play:

| | |
|---|---|
| **D** | decoys - what Osprey's reported q is derived from |
| **E** | entrapment - what the measured "true FDP" is derived from |
| **F** | target-false - the real false positives among targets. **Unobservable.** |

**FDR validity is a claim about D ~ F. The FDP:q plot measures D vs E.** It is evidence about
FDR only to the extent that **E ~ F**.

So a curve deviating from y=x says *the decoys do not model the entrapment*. Whether that is
also a statement about the decoys failing to model target-false depends entirely on whether the
entrapment is a faithful proxy - and **here it demonstrably was not**: E was polluted with
sequences behaving like target-TRUE (I/L isobars, conserved orthologs of abundant proteins).

**Therefore the anti-conservative Arabidopsis curve diagnosed a broken INSTRUMENT, not
necessarily broken FDR.** Findings 5-9 should be read as "the entrapment null was contaminated
and has been repaired", NOT as "Osprey's FDR was wrong and has been fixed". Nothing in this
series demonstrated an FDR failure.

**Corroborating evidence that the two diagnostics probe different regions.** The null-band
D-vs-E checks PASSED for every arm including the badly polluted one (`plateauRatio` 0.9564,
entrapment decoy-win **0.4981**, real-target **0.4974** - fair coin flips), while the FDP:q curve
failed badly. Both are D-vs-E comparisons; the null-band ones sample the LOW-scoring region and
the pollution lives at the CONFIDENT end. **The two disagreeing is itself the localizing
signal**, and is the reason both diagnostics are worth keeping.

**A run-count sanity check for E-pollution: proposed, ATTEMPTED, and NOT YET VALID.** The idea
is sound - a genuine false positive is detected sporadically, while a conserved ortholog of an
abundant protein is detected reproducibly like a real peptide - so the polluted subset should
sit at high k. The attempt made here used the `peaks` map in the pass-1 harvest and is
**INVALID**: `peaks` is the EXTRACTED peak set, not independent detections. Stage 6 fills a peak
for nearly every run, so everything reads 26-36 of 40 and even targets reach only 36.5. This is
precisely the trap the Entrapment README documents about `NRunsDetected` being
post-reconciliation, and it was walked into anyway. The numbers it produced show no separation
and must not be quoted.

The aggregate mdiag `crossRun` histogram IS in the correct domain and confirms entrapment
behaves like false positives overall (**30-33% at k=1 versus 8-11% for all accepted**), but it
is far too diluted to isolate a 2.7% polluted subset - I/L removal moved the k>=6 share only
47% -> 40%, and `ungated` (45%) sits above `gated` (37%), so the ordering is not even monotone
in contamination.

**To do it properly**: retain per-file `run_prec_q` in `pass1_entrap.py` so each accepted entry
carries a true independent-detection count, then compare the run-count distribution of the
identified polluted subset against clean entrapment. That is a harvest change, not a
re-analysis.

#### 11. FINAL MATRIX - and the decoy attribution in finding 7/8 is WITHDRAWN

`gated-no-il` completed (3 h 01 m). Full series, all six arms:

| variant | disc@1%q | trueFDP% | matched@1% | eff% | matched-disc FDP vs ungated |
|---|---|---|---|---|---|
| delivered | 24,153 | 0.837 | 25,173 | 76.36 | -4.2% |
| **ungated** (baseline) | 24,413 | 0.837 | 25,193 | 78.78 | - |
| gated | 25,064 | 0.743 | 26,379 | 80.18 | -28.7% |
| **gated-no-il** | 25,454 | **0.739** | 26,348 | 78.27 | **-51.5%** |
| arabidopsis | 23,385 | 1.183 | 22,550 | 69.24 | +60.9% |
| arabidopsis-no-il | 26,085 | 0.992 | 26,085 | 78.71 | -17.3% |

**`gated-no-il` is the best-calibrated arm in the series** - 0.356% true FDP at a matched 23,385
discoveries, less than half the shuffle baseline's 0.736%.

**THE PRE-REGISTERED PREDICTION FAILED, ON ITS OWN STATED FALSIFICATION CONDITION.**

| | predicted | measured |
|---|---|---|
| disc@1%q | 25,064 -> **~26,800-27,300 (+7 to +9%)** | 25,454 (**+1.6%**) |
| FDP at matched discoveries | -5 to -10% | **-32%** |

Finding 8 registered: *"a large FDP drop with a small discovery gain would falsify the decoy
attribution and send the explanation back to the entrapment side."* That is exactly what
happened. **The claim in findings 7 and 8 that colliding decoys cost ~11.5% of discoveries is
WITHDRAWN.**

The disproof is direct - both arms cleared their colliders, but nearly equal decoy removal gave
7x different discovery gains:

| arm | decoys q<=.01 | colliding | entrapment q<=.01 | colliding | disc gain |
|---|---|---|---|---|---|
| gated -> gated-no-il | 262 -> 268 | 15 -> **0** | 94 -> 95 | 5 -> **0** | **+1.6%** |
| arabidopsis -> arabidopsis-no-il | 251 -> 278 | 19 -> **1** | 144 -> 134 | 30 -> **0** | **+11.5%** |

**What survives**: the discovery gain tracks ACCEPTED ENTRAPMENT colliders (5 vs 30, ~6x) far
better than decoy colliders (15 vs 19, ~1.3x), so the entrapment side is the better candidate.
**What does not survive**: any quantitative mechanism. 30 accepted colliders cannot mechanically
free 2,700 discoveries, so this is not simple one-for-one competition either. **The mechanism
behind the Arabidopsis discovery gain is UNRESOLVED.**

**What is solid across both arms regardless of mechanism**: the I/L fix cleans the TOP of the
entrapment score distribution, which is why the matched-discovery FDP improves sharply
(gated -28.7% -> gated-no-il **-51.5%**) while FDP at matched q barely moves (0.743% ->
0.739%). The confident end is where the colliders lived, and it is where the fix acts.

Note also `gated-no-il` union efficiency FELL (80.18 -> 78.27) with matched flat (26,379 ->
26,348), so on the shuffle side the fix is close to a pure oracle correction - the opposite of
the Arabidopsis arm. That asymmetry is the unexplained part.

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

#### 7. mean(best-N) beats a POST-HOC REPRODUCIBILITY CUTOFF at every threshold (2026-08-02, Brendan)

Added after the series. The "N* = 1" conclusion was drawn from **total experiment-wide
detections**, a metric that counts a precursor found in 1 of 163 runs equally with one found in
163. For a quantitative experiment that is the wrong weighting - quantifying a 1-of-163 detection
means gap-filling 162 runs.

**The comparison that matters is against the lever this actually competes with.** Running plain
`max` and then keeping only precursors seen in >= N runs IS the standard post-hoc reproducibility
cutoff. So the `max` column below is not a neutral baseline - it is the competing method.

Accepted precursors at or above a run-count threshold, TDP-43 163 files, each arm at its own
1% experiment-wide q:

| bar | post-hoc cutoff (`max`) | best mean-best-N | gain over the cutoff |
|---|---|---|---|
| k>=1 (total) | **30,070** | 29,501 (mb2) | **-1.89%** (the headline decline) |
| k>=2 | 28,663 | **29,161** (mb2) | **+498 (+1.74%)** |
| k>=3 | 27,224 | **28,080** (mb3) | **+856 (+3.14%)** |
| k>=5 | 25,033 | **25,836** (mb4) | **+803 (+3.21%)** |
| k>=9 | 21,928 | **22,400** (mb6) | **+472 (+2.15%)** |
| k>=17 | 18,194 | **18,354** (mb6) | +160 (+0.88%) |
| k>=41 | 13,079 | 13,094 | +0.11% |

**The optimal N tracks the reproducibility bar**: mb2 at k>=2, mb3 at k>=3, mb4 at k>=5, mb6 at
k>=9 and above. Monotone. A single N* is the wrong summary; N should be chosen for the
reproducibility requirement.

**Mechanism - the two levers have different powers.** A post-hoc cutoff can only REMOVE: a
precursor rejected at the q stage never reaches the filter, however reproducible it was.
mean(best-N) lets reproducibility contribute to the q itself, so it can also PROMOTE - a
precursor marginal on best-single-run score but consistent across runs clears the line. Filtering
after the fact discards that information; scoring with it does not. That is why it wins at every
bar even on the dataset where it loses on total count.

**Caveat, and it limits how strongly this can be stated.** This is matched on the *q cut*, not on
FDP. At k>=2 the cutoff measures 0.360% and mb2 0.421%, so the +498 is partly bought with FDR
budget; the marginal precursors are ~3.9% false (+19 entrapment for +498 targets). Both figures
sit far under the 1% the user asked for, so the cutoff is leaving budget unspent - but a
matched-FDP comparison is the rigorous form and this is not it.

**Blocked on a diagnostics gap, not on a search.** The matched-FDP version needs run-count
histograms across the q sweep; `crossRun` currently emits them only at the 1% cut. That is a
small `--model-diagnostics` addition and would make this comparison rigorous without new runs.

**Not yet checked on SEA-AD**, where mean(best-N) wins on total count outright (+14.6% at N=2,
+16.4% at N=6) - so the threshold analysis there should be strictly more favourable, but the arms
live on the other machine.

#### Open questions

0. **SHIP THE I/L GATE** (finding 6). Reject any entrapment candidate whose I->L normalised
   sequence is in the target set. One hash set at generation time; removes a **4-5%** FDP
   over-estimate on shuffle libraries and **~21%** on foreign-species ones. Independent of, and
   complementary to, the fragment-overlap gate - which does not catch it. This is the most
   actionable result of the series.

1. ~~**Astral vs Stellar disagree on Arabidopsis entrapment.**~~ **LARGELY RESOLVED by finding
   7**: with I/L collisions removed, Arabidopsis goes from +60.9% worse than shuffle to 17.3%
   BETTER, i.e. back to the direction Stellar reported. The Astral +125% was contamination, not
   a contradiction. Residual work is only to confirm the Stellar library's collider count for
   completeness.

1b. ~~**Measure the colliding-DECOY effect directly.**~~ **RESOLVED - see finding 8. No new run
   was needed; `pass1_entrap.py` already retains decoys and the claim that it did not was
   wrong.**
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
