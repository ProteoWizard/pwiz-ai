# TODO-osprey_oop_review_round.md

## Summary
Run a fresh **blind `/pw-oop-review` round over the Osprey codebase** and work the slate it
returns. The last round was 2026-06-18/19 (the debt-paydown arc, PRs 3-9); **83 Osprey PRs
have merged since**, all of them feature-cycle work, and none of them structural. The
cadence this codebase is supposed to run at is a review every ~3-4 PRs. We are roughly 20
rounds overdue.

**Status**: Backlog (not started). **Type**: Architecture / structural debt (Osprey).
**Origin**: Brendan, 2026-09-10, prompted by a `/code-review max` finding on
`Skyline/work/20260910_osprey_mdiag_resident_removal` (see "The case that prompted this").

## Why now

Osprey grows by organic feature-cycle pairing rather than up-front design. That mode
reliably accretes structure debt, and the deliberate mechanism for managing it is a periodic
OOP/architecture review applied in **iterations** - each round fixes the dominant issue,
which exposes the next one underneath. Skipping ~20 rounds' worth of cadence does not mean
the debt did not accrue; it means nobody has looked.

What has changed since the last round is not small. The whole memory-scaling arc landed in
it: the Stage 5 -> 6 -> 7 boundary sidecars, the HPC `--task` split, per-run survivor
loaders, streamed joins, the model-diagnostics report and its accumulator, pass-2
per-file competition, and the resident-path ratchet. Those are exactly the kind of changes
that add cross-cutting predicates and quiet coupling.

Current inventory, as a starting point for the review's own survey (excludes `Osprey.Test`):

```
196 files, 85,203 LOC
  3,941  Osprey.Tasks/FirstPassFdrTask.cs
  3,607  Osprey.Tasks/PerFileRescoreTask.cs
  3,599  Osprey.Tasks/Pass2FdrSidecar.cs
  3,237  Osprey.Tasks/PerFileScoringTask.cs
  2,346  Osprey.Tasks/Calibrator.cs
  2,139  Osprey.IO/ParquetScoreCache.cs
  2,126  Osprey/OspreyFileDiagnostics.cs
  2,102  Osprey.FDR/ModelDiagnostics/ModelDiagnosticsData.cs
  1,781  Osprey.FDR/ModelDiagnostics/ModelDiagnosticsData.CoAssignment.cs
  1,515  Osprey.Tasks/SecondPassFdrTask.cs
  1,461  Osprey.FDR/StreamingFdr.cs
  1,378  Osprey.FDR/PercolatorTrainer.cs
  1,367  Osprey.FDR/PercolatorScorer.cs
```

Nine files over 1,000 LOC, four of them over 3,000 - and the four largest are the four
pipeline tasks, i.e. the code every one of those 83 PRs touched.

**Run it BLIND.** The value of the last round came from an independent review re-finding the
dominant issue without being told where to look, and then converging with a second blind
pass. Seeding the review with the candidates below would defeat that. Read this section
AFTER the review returns its slate, and use it to check the slate rather than to write it.

## The case that prompted this

`/code-review max` on the mdiag branch raised, as one of 15 findings, that **`HpcTask`
routing is a hand-maintained enum list spread across four predicates in three different
styles.** Nothing forces the four to agree, and nothing forces a newly added task to be
considered by all of them.

Both known Osprey OOMs trace to that shape. `--task ModelDiagnostics` was the second task
added by hand; one predicate (`ScoringTaskShared.CanHydratePerRun`) was not updated for it,
so it took the all-runs reconciliation bundle, grew 0.10 GB/file and died past a 63.7 GB box
at file ~310 of 446. The branch above fixes that instance. It does not fix the shape, and
the review's point is that the seventh task will do it again.

Proposed direction (for the review to accept, reshape or reject): an `HpcTaskProfile` table
with one entry per task, stating its properties, read by an exhaustive `switch` so the
compiler refuses to build when a task is added without answering every question.

**This is a candidate for the round, not a decision.** It is recorded here so it is
considered and prioritized against whatever the blind review finds dominant - it may well
not be the top item, and the discipline of the iteration is to fix the dominant issue first.

## Other candidates observed in passing

Same rule: these are checks on the review's slate, not a substitute for it. Each was noticed
while doing unrelated work, which is precisely why none of them has been addressed.

* **Predicates that conflate unrelated questions.** `CanHydratePerRun` answered "is this
  route admitted?" and "does the artifact exist on disk?" in one boolean, so its false
  branch had two meanings and a guard built on it refused runs it had no remedy for. It was
  split on 2026-09-10 (`PerRunSurvivorLoaderAvailable`). Worth asking how many siblings have
  the same shape - `CanStreamStage7Join`, `Stage7StreamAdmittedBeforeRescore`,
  `NeedsResidentPool`, `ShouldStreamCompaction` are the neighbours.
* **The guard/warn family has no common shape.** `PerFileScoringTask.ResidentPoolGuardError`,
  `Stage6ResidentHandoffGuardError`, `ScoringTaskShared.AllRunsBundleGuardError`,
  `WarnPreCompactionPool` and `SecondPassFdrTask.WarnResidentStage7Join` are five members of
  one concept living in three classes with three signatures and two dispositions (refuse vs
  disclose). Which one applies where is carried in prose.
* **Task-membership flags derived in one place, interpreted in four.** `Program.cs` derives
  `NoJoin` / `StopAfterStage5` / `ExpectReconciledInput` from `--task`; each task's
  `IsIncluded` re-derives what that means for it. Same hand-maintenance hazard as the
  finding above, one level down.
* **Diagnostics bleed.** Extracting a shared scoring core is already blocked by exe-only
  `OspreyDiagnostics` statics reaching into task code - a known boundary violation with a
  standing consequence, not a hypothetical one.
* **The four pipeline tasks are where every feature lands.** 12,400 LOC across four files
  that every PR touches is the classic monolith-by-accretion signature, and it is what the
  review's file-size heuristic will flag first.

## Definition of done

1. Blind `/pw-oop-review` over `pwiz_tools/Osprey`, report banked in `ai/.tmp/`.
2. Slate triaged with Brendan into a prioritized order - dominant issue first.
3. The dominant issue fixed in its own PR, gated the usual way
   (`regression-parallel.ps1 -Dataset All`, output byte-identical).
4. A second blind review after that PR to confirm the issue no longer flags and to surface
   what is underneath it. Expect several iterations; one pass does not reach "exemplary".

Related: `ai/docs/code-review-guide.md` (the five lenses and the review posture),
`TODO-20260910_osprey_mdiag_resident_removal.md` (the finding's origin and the fix that
closed the instance).
