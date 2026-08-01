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

## Tasks

- [ ] **Carafe entrapment gate** (`EntrapmentFastaGear.shufflePreservingCterm` + caller). Add the
      bounded retry the path entirely lacks: derive the seed as `SHA-1(masterSeed:seq:attempt)` so
      it stays deterministic, re-shuffle, accept when overlap is under threshold, drop the quartet
      after N attempts using the collision-drop policy already present. Dropping is correct for
      `AAAAAAAAAAAAAAAAGATCLER` - no permutation of 17 alanines is a valid entrapment peptide.
- [ ] **Carafe decoy gate** (`generateReverseDecoy`). The cycling retry already exists; add the
      gate to both accept conditions, mirroring C#'s two call sites exactly.
- [ ] **Port `IsCandidateAcceptable` to Java** - transcription, not design. Keep the C#/Rust
      constants and rationale verbatim: `MAX_FRAGMENT_OVERLAP = 0.4`, `LADDER_MATCH_TOLERANCE =
      0.02` Da (deliberately NOT the search tolerance, so the decoy set stays a pure function of
      the library), stripped sequences only, full ladder.
- [ ] **Skyline: add the gate** to `SequenceMods.Shuffle`'s `while` condition, which currently
      tests only `newSequence.Equals(Sequence)`. Also applies to `Reverser`.
- [ ] **Skyline: replace the shuffle with Fisher-Yates** (see below).
- [ ] **Measure the cost**: how many peptides get dropped from the entrapment set at 0.4, and
      whether the loss is structured (low-complexity sequences - poly-G, poly-E, collagen-like -
      are exactly the ones that fail). Acceptable for entrapment since it only shrinks `r`, which
      is recomputed, but quantify before building.
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

The gate rejects **4.15%** of library entrapment but ~**27%** of the ACCEPTED set - a 6.5x
enrichment of near-copies among hits, the shadowing effect as a single ratio.

Caveats: this reimplements the estimator (rebuilt max arm 30,584 matched vs Osprey's 30,616), so
the DIFFERENTIAL is reliable and the absolutes drift; and removing near-copies is a NON-random
subsample, so it is the lower bound on the correction - the Arabidopsis result implies true FDP is
below 0.695%.

Tool: `ai/scripts/Osprey/Entrapment/contamination_corrected.py`.

## Progress Log

### 2026-08-01 - Problem isolated, landscape surveyed, decision taken

Root cause traced from measured output back to source across four implementations. Decision to
gate on fragment overlap only is backed by the marginal-value measurement above rather than by
the "checkbox coverage" reasoning that produced the original C#/Rust gates - which turned out to
have picked the right one of the two.
