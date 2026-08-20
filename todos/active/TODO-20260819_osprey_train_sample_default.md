# TODO-20260819_osprey_train_sample_default.md

## Branch Information
- **Branch**: `Skyline/work/20260819_osprey_train_sample_default`
- **Base**: `master`
- **Created**: 2026-08-19
- **Status**: In Progress
- **Module**: `osprey`
- **PR**: (pending)

Spun out of the investigation in `TODO-20260801_decoy_similarity_gate.md`, which carries all the
measurement history. This file is the SHIPPING half: the training-selection change, the separately
published Stellar library, and the golden re-baseline they force.

## Problem

Osprey's first-pass Percolator trains one global model on the **best observation of each precursor
across all files** (`PercolatorSampling.SelectBestPerPrecursor`). Every training row is therefore a
maximum over however many runs were batched together, while the model it produces scores ordinary
per-run rows. The mismatch grows with the batch: mean `coelution_sum` is 1.19 at one file and 5.75
at 82, against 1.18 in the population actually being scored.

The visible symptom was read for two weeks as a property of a spectral library. It was not.

## The change

Represent each precursor by ONE uniformly sampled run's observation, at the same row count and the
same memory. Size-1 reservoir: the k-th run a precursor appears in takes the slot with probability
1/k, decided by a SplitMix64 mix of (base_id, k, training seed) rather than a shared RNG, so
thread scheduling cannot move it and a re-run trains on the same rows.

**Measured, 82 SEA-AD files, pass-1, experiment scope, protein-compact + max, at MATCHED true FDP:**

| arm | @0.650% | @0.750% | @1.000% |
|---|---|---|---|
| ours baseline | 33,789 | 34,552 | 35,533 |
| ours + reservoir | 42,131 | 42,982 | 45,252 |
| mike baseline | 34,708 | 36,143 | 39,144 |
| mike + reservoir | 41,204 | 42,989 | 47,154 |

+24.7% for our library, +18.7% for Mike's; with it the two libraries are at parity
(+2.25 / -0.02 / -4.03%). Pass-2, ours: **48,353 @ 0.750%** against 38,776 historical.

`OSPREY_MAX_TRAIN_SIZE` deliberately does NOT change: at matched FDP 300K and 1M are
indistinguishable, 2M and 3M buy ~1.8% for 7-10x the training rows and ~45% more first-pass wall
time. The sampling gets ~+25% for free.

## DECISION (Brendan, 2026-08-19): this ships as a FIX, not an env var

> "The sampling has earned its place as a fix and not an env var."

* Uniform reservoir is the DEFAULT in every selection path.
* Escape hatch INVERTED: `OSPREY_TRAIN_PICK_RUN=0` restores the cross-run maximum. Read with
  `IsNotZero`, so every script written while this was an experiment (which sets it to 1) selects
  the shipped behaviour instead of silently reverting.

## What the flip actually cost - it was not a one-line inversion

The opt-in design threaded per-file offsets (`fileStart`) into `SelectBestPerPrecursor` and made
any path WITHOUT them **throw**:

```
OSPREY_TRAIN_PICK_RUN reached a multi-run selection with no per-file offsets ...
```

Two of the three call sites pass no offsets - `PercolatorTrainer` (the direct path) and
`PercolatorEngine.RunPercolatorStreaming` - and the direct path is what a 3-file Stellar run takes.
Flipping the default alone would have hard-failed the regression suite.

**Root cause of the over-constraint**: the reservoir never read the run index the offsets existed
to supply. `ReservoirTakesSlot(baseId, seen, seed)` needs only the arrival COUNT. The cursor that
walked `fileStart` advanced a `file` local that nothing consumed - dead code. So:

* `fileStart` removed from `SelectBestPerPrecursor` and `BuildTrainingSubset`;
* the abort removed with it;
* every path now honors the reservoir identically, which is a requirement of a shipped behaviour
  and not merely a tidy-up - a path-dependent default is the same defect class as the one this
  investigation started from.

Uniform over OBSERVATIONS is uniform over RUNS exactly when there is one observation per precursor
per run, which is what first-pass per-file rows are. Stated in the doc comment rather than assumed.

## Validity keying - deliberately NOT what the handoff proposed

The handoff said to make the suffix EMPTY for the new default so no existing directory is
disturbed. That is wrong here, and the codebase had already settled it twice:
`PickValidityKeySuffix` and `Pass2QValueValidityKeySuffix` are both UNCONDITIONAL, each with the
reasoning written out - a flipped default whose new arm emits nothing produces a post-flip key
EQUAL to every pre-flip key, so a resume or `-LinkFrom` adopts the OLD selection's scores as though
the new one produced them. `AssertSuffixesAreUnconditional` already asserted the principle.

So `;trainpick=run|max` is emitted for BOTH arms. `;maxtrain=` stays conditional - that knob's
default never moved, so silence for it is correct. The one-time cost is that every
FirstPassFDR-and-later directory predating this is invalidated; Stages 1-5 carry no training
suffix, so `-LinkFrom` still adopts the expensive extraction artifacts.

**If Brendan prefers the empty default anyway it is a one-line change**, but it re-opens the silent
adoption path above.

## `LibraryUrl`: the Stellar library ships separately from the mzML bundle

`stellar-libdecoy-v3.zip` removes 21 entrapment peptides whose I/L-normalised sequence collides
with a real target. An exact-string audit shows 0 collisions for BOTH v2 and v3 - only the
I/L-normalised check separates them.

Bundle acquisition is UNCHANGED (skip-if-present on the extracted root; nobody re-downloads
24.6 GB). The library is a second, independent acquisition:

* new optional dataset key `LibraryUrl`, on both specs that set `LibraryFolder='stellar-libdecoy'`;
* presence check is the **downloaded zip itself**, `<libDir>/stellar-libdecoy-v3.zip`. NOT the
  extracted `carafe_spectral_library.tsv` - both versions produce that same name, so a v2 machine
  would look satisfied and stay on the old library forever;
* downloaded to `<marker>.part` and renamed in, so an interrupted download cannot leave a truncated
  file whose NAME claims v3 is present and suppress every later attempt;
* extracted with OVERWRITE (`Expand-ZipInto -Overwrite`, renamed from `Expand-ZipNoOverwrite` and
  given the switch) because both zips carry the same three entry names;
* ordered so `LibraryUrl` wins and the `NestedZip` branch is skipped outright when it fired, rather
  than relying on the no-overwrite semantics to protect it by accident.

## Tasks

- [x] Separate the work onto its own branch (it was sharing another topic's branch)
- [x] Flip the default; remove `fileStart` and the abort; honor the reservoir on every path
- [x] Invert the escape hatch to `OSPREY_TRAIN_PICK_RUN=0`
- [x] Key the selection unconditionally; keep the training cap conditional
- [x] Test that the previously-aborting path samples (`TestEveryPathSamplesARun`) - verified to
      FAIL under `OSPREY_TRAIN_PICK_RUN=0` with "every winner came from the highest-scoring run"
- [x] Wire `LibraryUrl`; point both Stellar libdecoy specs at v3
- [ ] `regression.ps1 -Dataset Stellar` - the owed gate
- [ ] `regression.ps1 -Dataset All`, re-baseline every golden
- [ ] `/code-review max`
- [ ] PR + TeamCity Perf/Regression on `pull/<N>`

## Open question the Stellar gate answers

Whether a 3-file dataset can SEE a cross-run-maximum change at all. If the goldens do not move, the
regression suite cannot protect this behaviour and the PR needs a multi-file dataset that can.

## C#/Rust parity

This is a C#-only behaviour change. The Rust equivalent is
`crates/osprey/src/pipeline.rs:6817-6900` (best-per-precursor dedup + subsample). `regression.ps1`
has no cross-impl comparison, so no gate goes red, but the "C# == Rust" signal is broken for
first-pass training until Rust takes the same change or parity is retired.

## Product defects found, worth filing separately

1. **`-Resume` past FirstPassFDR silently breaks protein-compact pass 2.** The stratum is published
   in memory only, so a resumed run has none, the stratified competition does not happen, and
   pass-2 output equals pass-1 - with no error. Fix: persist the stratum, or hard-fail without one.
2. **Batch-composition sensitivity** - a file's identifications depend on which other files were
   batched with it (~+-20% at baseline). Draft at `ai/.tmp/issue-draft-pool-sensitivity.md`.
