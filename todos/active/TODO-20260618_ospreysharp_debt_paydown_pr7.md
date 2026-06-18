# TODO-20260618_ospreysharp_debt_paydown_pr7.md -- OspreySharp debt-paydown PR 7 (decompose CoelutionScorer.ScoreCandidate)

## Branch Information
- **Branch**: `Skyline/work/20260618_ospreysharp_debt_paydown_pr7` (to be created; REBASE onto master after PR 6 lands -- see status)
- **Base**: `master` (after PR 6 merges)
- **Created**: 2026-06-18
- **Status**: Queued (start after PR 6 #pending merges; rebase onto merged master)
- **PR**: (pending)

> PR 7 of the OspreySharp OOP debt-paydown arc. The blind review's Rec 1 headline:
> `CoelutionScorer.ScoreCandidate` (~827 LOC) is the single largest remaining giant.
> Seeded by the 2026-06-17 blind `/pw-oop-review` (`ai/.tmp/20260617-oop-review-report.txt`,
> Rec 1 + the AbstractScoringTask open question).

## Framing -- output-invariance, and this one is parity-SENSITIVE
Pure CODE MOTION, output-locked by the golden. `ScoreCandidate` is the coelution
scoring core -- keep the COMPUTATION whole (do not reorder/restructure math); extract
named collaborators around it by pure motion only. See
`feedback_refactor_gate_output_not_structure` and `feedback_no_unverified_ports`.

## Primary work -- decompose CoelutionScorer.ScoreCandidate
- `CoelutionScorer.ScoreCandidate` lives at `OspreySharp.Scoring/CoelutionScorer.cs`
  (~157; the file is ~1068 lines). The review identified separable phases to extract
  (names indicative, verify in-session): RT-window math, the 3-tier CWT fallback,
  peak ranking (`PeakRanker`), boundary recomputation, stage-6 candidate capture, and
  the `FdrEntry` serialization (`FdrEntryBuilder`). Reduce `ScoreCandidate` to a
  sequencer over those collaborators.
- Each extraction is pure motion: same computation, same output. Decompose for
  readability/maintainability, NOT by restructuring the algorithm.

## Coupled decision -- the AbstractScoringTask fork (review open question)
Before relocating the dedup/scoring helpers, decide the architectural fork:
`AbstractScoringTask` (~629 LOC) shares `RunCoelutionScoring`, `DeduplicateDoubleCounting`,
`DeduplicatePairs` via INHERITANCE. `DeduplicateDoubleCounting` is feature-envy (an
algorithm over library fragments parked on a task base). Decide: move these into a
COMPOSED Scoring-project collaborator (testable in isolation) vs keep inherited.
- If "compose" and the move is large, it can be its own follow-up PR -- record the
  decision here and scope accordingly.

## Why this is now LOW-RISK (use the safety net)
Decomposing the scorer used to feel like touching the parity core. It is now
well-protected:
- `regression.ps1` (committed C# golden + resume @1e-9) -- proves C# output is
  byte-identical after each commit.
- **`Compare/Compare-CrossImpl-Reference.ps1`** (the cross-impl reference gate built
  2026-06-17, all-green) -- proves no drift from Rust at every stage boundary.
Run BOTH; the combination makes pure-motion extraction of the scorer giant safe.

## Out of scope
- ProteinFdrEngine / RunPercolator -> PR 6.
- Any algorithm change to the scorer (this is decomposition only).

## Gates (standing cadence + emphasis on the cross-impl gate)
- Per commit: `Build-OspreySharp.ps1 -Configuration Debug -RunTests -RunInspection`
  (0 warnings) + `regression.ps1 -Dataset Stellar` (modes 1 & 2 byte-identical).
- Pre-merge: `regression.ps1 -Dataset All` + `Test-PerfGate.ps1 -Dataset Stellar`
  + **`Compare/Compare-CrossImpl-Reference.ps1 -Dataset Stellar`** (all boundaries
  green) + `/pw-self-review`, then PR, Copilot, `/pw-respond`.

## Notes
- Reference set local at `D:\test\osprey-runs\stellar\_crossimpl_reference\`
  (Rust 696c938 / v26.6.1; README inside); regenerate with `Build-CrossImplReference.ps1
  -Force` (needs a built Rust osprey) if missing.
- After PR 7 lands, run the next blind `/pw-oop-review` to re-survey the decomposed
  tree and seed the next batch (this PR + PR 5/6 are the post-06-17 batch).
