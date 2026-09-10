# TODO-osprey_oop_review_round.md

## Summary
Run a fresh **blind `/pw-oop-review` round over the Osprey codebase** and work the slate it
returns. The last review was **2026-06-18**; **83 Osprey PRs have merged since**, all of them
feature-cycle work, none structural. The cadence this codebase is supposed to run at is a
review every ~3-4 PRs. We are roughly 20 rounds overdue - and the last arc's own closeout
step was never taken (below).

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

## The last review period, and what has happened since

**The arc (2026-05-29 -> 2026-06-20).** Seeded by the 2026-05-29 OOP review, worked as the
OspreySharp debt-paydown arc: PR 1 (#4302, merged 06-15) through PR 9 (#4319, merged 06-20),
with blind re-reviews interleaved on 06-16, 06-17 and 06-18. The two later reports are still
on disk: `ai/.tmp/20260617-oop-review-report.txt`, `ai/.tmp/20260618-oop-review-report.txt`.
Their headline: *"well-architected code... the debt is not in the bones, it's in the flesh of
the Tasks layer. Four task files exceed 1,000 LOC, and inside them sit orchestration methods
of 250-350 lines."*

**The arc was never formally closed.** `TODO-20260619_ospreysharp_debt_paydown_pr9.md` ends
with an explicit outstanding item - *"run the FINAL confirmatory blind `/pw-oop-review`; if
clean, declare the OOP debt-paydown arc complete."* No review report exists after 2026-06-18
and no TODO since mentions one, so that confirmation never happened. This round subsumes it:
the first thing the review answers is whether the 06-18 findings stayed fixed.

**Growth since (measured 2026-09-10).** Same metric both sides - raw lines of non-test `.cs`
under the Osprey tree, at the arc-close commit `a0065b3efa` vs today:

| | 2026-06-20 (arc close) | 2026-09-10 | change |
|---|---:|---:|---:|
| non-test `.cs` files | 131 | 196 | 1.50x |
| non-test lines | 42,562 | 85,203 | **2.00x** |

**The production tree has doubled in twelve weeks**, with no structural pass in that window.

The four largest files then and now - the same metric that defined the last review's dominant
finding:

```
2026-06-20                                    2026-09-10
2,401  PercolatorFdr.cs                       3,941  Osprey.Tasks/FirstPassFdrTask.cs
2,126  OspreyFileDiagnostics.cs               3,607  Osprey.Tasks/PerFileRescoreTask.cs
1,630  Tasks/PerFileScoringTask.cs            3,599  Osprey.Tasks/Pass2FdrSidecar.cs
1,504  Tasks/PerFileRescoreTask.cs            3,237  Osprey.Tasks/PerFileScoringTask.cs
1,311  Tasks/Calibrator.cs                    2,346  Osprey.Tasks/Calibrator.cs
1,211  IO/ParquetScoreCache.cs                2,139  Osprey.IO/ParquetScoreCache.cs
```

"Four task files exceed 1,000 LOC" was the dominant issue in June. Those same files are now
3,237-3,941, and thirteen files exceed 1,000. `PerFileScoringTask` and `PerFileRescoreTask`
have each roughly doubled since being decomposed.

**`Audit-Loc.ps1`, run 2026-09-10** (`ai/.tmp/osprey-loc-audit-20260910-1648.md`) - cloc
executable lines, so smaller than the raw counts above and directly comparable to Rust:

```
Measure                      C#         Rust    C#/Rust
Production code          44,766       29,221      1.53x
Test code                18,203       13,435      1.35x
Comment lines            41,549       12,463      3.33x
Files                       245           60      4.08x

Per-module (C# code):
  Osprey.Tasks     13,901   (no Rust counterpart - the pipeline layer is ours)
  Osprey.FDR        9,992   vs osprey-fdr 5,169     1.93x
  Osprey.IO         6,695   vs osprey-io  5,368     1.25x
  Osprey.Scoring    5,234   vs osprey-scoring 7,944 0.66x
  Osprey.Core       2,895   vs osprey-core 2,539    1.14x
```

`Osprey.Tasks` is the largest project, has no reference implementation to be measured
against, and is where all four of the big files live. `Osprey.FDR` at 1.93x its Rust
counterpart is the next thing worth a look - some of that is the diagnostics report, which
Rust does not have, but not all of it.

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
* **The four pipeline tasks are where every feature lands.** 14,400 lines across four files
  that every PR touches is the classic monolith-by-accretion signature, and it is what the
  review's file-size heuristic will flag first. Note the June review explicitly cleared the
  big ALGORITHM files (`PercolatorFdr`, `CoelutionScorer`) as "large cohesive algorithm" and
  faulted only the orchestration bodies - the same distinction should be drawn again rather
  than assumed.

## Definition of done

1. Blind `/pw-oop-review` over `pwiz_tools/Osprey`, report banked in `ai/.tmp/`. It also
   discharges PR 9's unfinished closeout: say whether the 2026-06-18 findings stayed fixed.
2. Slate triaged with Brendan into a prioritized order - dominant issue first.
3. The dominant issue fixed in its own PR, gated the usual way
   (`regression-parallel.ps1 -Dataset All`, output byte-identical).
4. A second blind review after that PR to confirm the issue no longer flags and to surface
   what is underneath it. Expect several iterations; one pass does not reach "exemplary".

Related: `ai/docs/code-review-guide.md` (the five lenses and the review posture),
`TODO-20260910_osprey_mdiag_resident_removal.md` (the finding's origin and the fix that
closed the instance).
