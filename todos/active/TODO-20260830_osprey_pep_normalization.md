# Normalize PEP: stop materializing a left-outer-join across every observation

## Branch Information
- **Branch**: `Skyline/work/20260830_osprey_pep_normalization`
- **Base**: `2d07cf48fd` ("Split the FDR sidecars by scope, making the per-file ones immutable")
  - the Phase 1 commit whose immutability claim this repairs. NOT on master: Phase 1 and
    Phase 2 both live on PR #4621's branch.
- **Worktree**: `C:\proj\pwiz`
- **Created**: 2026-08-30
- **Status**: In Progress
- **Issue**: [#4486](https://github.com/ProteoWizard/pwiz/issues/4486)
- **Merges into**: the Phase 2 work in `C:\proj\pwiz-work1`
  (`Skyline/work/20260827_osprey_stage7_stream_increment`, WIP at `d901a28d10`)

## The flaw

`2d07cf48fd` claims *"making the per-file ones immutable"* and deletes `PatchProteinQvalues`
and `PatchExperimentValues`. It keeps `PatchPep`, which **re-opens every per-run 2nd-pass
sidecar after the experiment fold and rewrites the 8-byte `pep` column**. So the 2nd-pass
per-file sidecar is not immutable: it is written by one task and modified by another.

**The HPC consequence was never surfaced**: SecondPassFDR must hold WRITE access to every run
node's sidecar. That contradicts the contract - run nodes write, a separate machine reads what
they wrote. Brendan: *"That breaks the design, and I was not aware of a need to break the
design... it totally broke the contract I attempted to establish without proclaiming it loudly
that it needed to do this and asking for permission, which I would have denied."*

### Why it is a materialized left-outer-join

PEP is `PepEstimator.PosteriorError(winner.score)` - **one value per base_id**, derived from the
winning observation's score. `_winnerLoc` is `base_id -> (fileIdx, entryId, score)`: one row.
Today that single fact is spread across ~933K per-observation slots (3 Stellar files), real on
the winner and `1.0` everywhere else. The `1.0` is not a posterior error probability; it is a
sentinel meaning "not the row the estimate was computed on" - the same participation-vs-value
conflation this sprint has now root-caused three times.

The estimator is fitted from `(winner score, isDecoy)`, both of which the experiment sidecar
already carries, so nothing about PEP needs per-observation storage.

**Brendan's ruling: normalize the storage and perform the left-outer-join at RUNTIME, in all
cases.**

## The design

Semantics are PRESERVED exactly - normalizing is a storage change, not a meaning change.

* **Store once**, in the experiment record (already keyed by entry_id, and the winner entry_id
  determines its base_id, so this needs no new table): a single `Pep` double, real on the
  WINNING entry_id and 1.0 on the losing label. Record 36 -> 44 bytes, format v2.

**NO file dimension** - and an intermediate design that had one was wrong. I first added a
`PepWinnerFileIndex` so the per-observation view (real in the winning run, 1.0 elsewhere) could
be reproduced exactly. Brendan: *"I don't yet understand why PEP needs the file it was based on
while q values and even experiment-wide composite scores don't. Do you?"* - and the answer is
that it does not. PEP is `PosteriorError(winner.score)`, a property of the PRECURSOR exactly
like the q-values beside it; the winning run is where the maximum happened to occur, not part of
the value. Reproducing the per-observation view means preserving the materialized join while
claiming to normalize it, and the 1.0 it preserves is the sentinel, not information. The
distinction that IS real - winning label vs losing label - is entry_id-scoped and survives for
free. Removing the index also deleted the canonical-sorted-stems machinery written to support it.
* **Per-file sidecar drops `pep`**, 36 -> 28 bytes, **identically on both passes**. Brendan:
  *"The two passes should use the same normalization."* Pass 1 wrote it once as final, pass 2
  wrote a placeholder and patched it - one column, two lifecycles, which is the trap.
* **`PatchPep` and its whole extra traversal are deleted.**

### What it buys

1. Per-file FDR sidecars become genuinely write-once - the contract `2d07cf48fd` claimed.
2. The join stops needing write access to files it does not own; the HPC contract holds.
3. 22% off every per-file FDR sidecar: ~11 GB of the measured 52.3 GB at 257 files.
4. Fixes mode 7's three "regeneration touched an artifact" failures on the Phase 2 branch,
   which were PatchPep all along (verified: at this base `WriteCore`'s `DiagnosticsOnly` skip
   leaves `sidecarsWritten` empty so the patch loop never runs; after the relocation ownership
   comes from disk, so it runs and rewrites all three).

## Verifiers to add (the rule drifted because nothing enforced it)

1. **Write-once guard, in code**: a per-file FDR sidecar is written at most once per run. Fires
   on every route including straight-through. This is the contract stated executably instead of
   in a commit title.
2. **Cross-task file-modification assertion in `regression.ps1` mode 3** (Brendan's): fingerprint
   each phase dir immediately before and after `Invoke-OspreyTaskRun` and assert the task
   modified nothing but its own declared outputs. Mode 3 is the right home because there task
   boundaries ARE process boundaries - *"we know exactly which task is running when."*
   Note it would NOT have fired at this base (no 2nd-pass bin is relayed, so phase 4 creates
   what it patches); it fires once ownership moves, which is why verifier 1 is also needed.

## Risks to close before merge

* **KDE fit order**: `PercolatorQValues.cs:66` warns the estimator's sum is NOT associative.
  Storing the fitted value (as designed) avoids this; deriving it by refitting at read time
  would need the fit order pinned canonically. Do not switch to refitting casually.
* **Diagnostics dumps** print `e.Pep` per row (`OspreyFileDiagnostics.cs:1521,1589`). With the
  runtime join they must reproduce the same per-observation values; assert that rather than
  assume it.
* No scientific output consumes PEP - the blib writer has **zero** references to it, and neither
  do the report or FDRBench writers. Consumers are the two diagnostic dumps and entry re-seeding.

## Tasks

- [x] Extend `FdrExperimentRecord` + `FdrExperimentSidecar` (Pep only, 36 -> 44, format v2)
- [x] Populate them where `_winnerLoc` / the PEP estimator are in hand (`PepWinner`)
- [x] Drop `Pep` from `FdrScoreRecord` / `FdrScoresSidecar`, both passes (36 -> 28, format v6)
- [x] Delete `PatchPep` and its call site; the finish loop is now read-only
- [x] `entry.Pep` sourced from the experiment record on every path (no runtime file join needed)
- [ ] Write-once guard on per-file sidecar writes
- [ ] mode 3 per-phase file-modification assertion
- [ ] `regression.ps1 -Dataset All` green; golden updates reviewed, not absorbed
- [ ] Merge into the Phase 2 branch and re-run its gates

## Progress Log

### 2026-08-30 - LANDED `e72ba273ed`, gate green
Build clean, **597/597**, ReSharper 0/0, net -60 lines. `Pep` is now subject to the SAME
cross-key bitwise-equality check that originally rejected it, and satisfies it. The unit tests
are green; the real proof is a regression run where the accumulator sees one `Add` per
observation across three files - NOT yet run.

### 2026-08-30 - branch created, design agreed
Root-caused during the Phase 2 investigation (see
`TODO-20260826_osprey_stage7_stream_pool.md`). Brendan's direction: land the Phase 1 repair
first as a small, independently testable change, then merge it into the Phase 2 work so that
phase becomes a much smaller diff. The whole of #4486 is to land as ONE atomic squash-merge to
master, fully correct and fully validated.

## HOW THE FLAW GOT IN: a failing denormalization test read as the wrong verdict (Brendan, 2026-08-30)

Brendan's account, and it matches the code exactly. Phase 1 was required to test that every
value entering the experiment-wide sidecar is consistent across the join key - denormalized
join semantics, all values equal across the key. That test is
`FdrExperimentAccumulator.Add`'s bitwise-equality check:

> *"Bitwise equality, not a tolerance. These are copies of one computed value, so any
> difference at all means the premise of the collapse has failed, and a tolerance would only
> decide how much of a wrong answer to accept."*

PEP failed it, because `Pep(fileKey, entryId)` returned the estimator's value in the winning
run and 1.0 in every other. The session concluded PEP "fits neither model" and that preserving
all the information required writing it back into the per-file sidecar - i.e. `PatchPep` - and
did not proclaim that judgment loudly enough to be scrutinized. It required breaking the
immutability contract that the same commit's title claims.

### The reasoning error, stated generally

**A failure of the "all values agree across the key" test has TWO possible causes, and only one
was considered:**

| cause | correct home |
|---|---|
| (a) the value genuinely varies per observation | the per-observation record |
| (b) the value is a normalized fact plus ABSENCE MARKERS | the keyed record; the markers are the join's NULL |

PEP is (b). The varying part was not information: 1.0 means "not the row the estimate was
computed on". Reading it as (a) treats a NULL as a value, and then "preserve all information"
argues for materializing a left-outer-join across every observation.

**The second question that was never asked**: does any consumer need the markers? Measured now -
no. The blib writer has ZERO references to PEP; neither the report writer nor FDRBench touch it.
The only consumers are two diagnostics dump columns and entry re-seeding.

### The check that should be applied next time

When a value fails the cross-key equality test, before concluding it is per-observation:

1. Is the variation a VALUE or an ABSENCE MARKER? (Does one row carry a real number and the rest
   a constant?) If the latter, it is a normalized fact and the constant is NULL.
2. Does any consumer need the marker - i.e. does anything read the per-observation view?
3. If a value truly fits neither model, that is a DESIGN decision with a contract cost. Say so
   loudly and get a ruling, rather than choosing the option that preserves bytes.

### The invariant now holds for the right reason

`StreamedCompetitionState.PepWinner(entryId)` does not vary by file, so PEP is now subject to
the very check that originally rejected it - `Pep` was added to the accumulator's bitwise
equality set. Unit tests are green; the real proof is a regression run, where the accumulator
sees one `Add` per observation across three files. NOT yet run - do not claim it until it is.

## WHY NO EXPERIMENT-SCOPE VALUE CARRIES ITS ORIGINATING RUN (Brendan, 2026-08-30)

The decisive argument against the intermediate `PepWinnerFileIndex` design, and the one to put
in the PR description. PEP may eventually be reported in the BLIB, so this is not a
diagnostics-only question.

**1. It does not generalize across levels.** If "originating run" were the pattern, every
experiment-wide column would need its own specifier, and they would not agree. Precursor q
originates from one run; PROTEIN q originates from the best-scoring run of the best-scoring
PEPTIDE - a different coordinate entirely. One file column on an entry_id-keyed record cannot
serve both, even under plain `max`.

**2. Under `mean-best-N` it has no referent at all.** The aggregate is
`mean(N best per-run scores)`, not `max(scores)`, so the composite score - and every q derived
from it - originates in N runs, not one. There is nothing to write.

**And that mode is live on the pass that matters.** `StreamingFdr` sets
`winnerLoc[bid] = (win.fileIdx, win.entryId, win.score)` from a max-across-files fold, which
looks like a usable origin - but the comment beside it records that this is the 2nd-pass path
and *"the experiment aggregation is 1st-pass only ... so effScores == scores here"*. On the
1st pass, where `mean-best-N` IS applied, a `PepWinnerFileIndex` would have been
**unpopulatable**. The design was not merely redundant; it had no correct value to write.

### The rule

> An experiment-scope value is a property of its KEY. WHERE it came from is a property of the
> COMPUTATION, not of the value, and it is not generally expressible - under `mean-best-N` there
> is no single origin, and across levels the origins do not share a coordinate system.

### Why this retro-explains the Phase 1 dead end

The session met a value whose per-observation view varied (real on one row, 1.0 on the rest) and
reached for provenance to preserve that view. Provenance is exactly what an experiment-scope
value cannot carry - so the only way to keep the varying view was to write it back into the
per-run files. `PatchPep`, and the broken immutability contract, follow from trying to store
something that does not belong to the record at all. The dead end was UPSTREAM of the choice
that was made: the question "which file did this come from?" has no general answer, so a design
that needs one is already wrong.

The correct reading of the varying view was that the variation was an ABSENCE MARKER, and the
join that produces it belongs at read time - which needs no provenance, because a consumer
asking "is this precursor's PEP real here?" already knows which file it is reading.

## PEP is ASPIRATIONAL, not vestigial (Brendan, 2026-08-30)

Correction to an argument used above. I justified the change partly on "no scientific output
consumes PEP" (true today: the blib writer has zero references, nor do the report or FDRBench
writers). Brendan: PEP is **less vestigial than aspirational** - Mike added it expecting to have
that statistic available, and like the protein q-value it needs new BLIB plumbing before Skyline
can present it.

So the standard is not "harmless now" but **right for the eventual consumer**, and the
normalization meets it more clearly than the old form did:

* Skyline would present a posterior error probability for an IDENTIFICATION - one number per
  precursor. That is exactly the entry_id-keyed value now on `FdrExperimentRecord`.
* The old per-observation form would have been actively WRONG for that consumer. A blib writer
  would have had to scan every run's sidecar to find the single row holding the real value, with
  1.0 in all the others - the materialized left-outer-join reappearing at the consumer, and
  meaningless if ever surfaced per replicate.
* **`ExperimentProteinQvalue` is the precedent, not an analogy**: already in this record, keyed
  by entry_id, no file dimension, for the same reason. PEP now sits beside it in the same shape -
  two experiment-scope statistics, one normalization, both waiting on the same BLIB plumbing.

**Follow-on work (NOT this branch)**: BLIB plumbing for PEP and protein q so Skyline can present
them. Noted here because this change is what makes that a column read rather than a cross-file
search.
