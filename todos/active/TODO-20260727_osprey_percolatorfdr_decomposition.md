# Osprey: decompose PercolatorFdr.cs into training / scoring / TDC-FDR / diagnostics collaborators

## Branch Information
- **Branch**: `Skyline/work/20260727_osprey_percolatorfdr_decomposition`
- **Base**: `master` (1c1ae8532)
- **Created**: 2026-07-27
- **Status**: In Progress
- **Worktree**: `C:\proj\pwiz`
- **GitHub Issue**: [#4468](https://github.com/ProteoWizard/pwiz/issues/4468)
- **PR**: (pending)
- **Requester/Reporter**: none - filed by Brendan, an Osprey developer, so no credit line

## Objective

`pwiz_tools/Osprey/Osprey.FDR/PercolatorFdr.cs` is a god class mixing SVM training
orchestration, model application / population scoring, target-decoy FDR math, and
Stage-5 diagnostic dumps. Break it into collaborators. Structural only - the output
must stay byte-identical.

Re-measured on this branch against master 1c1ae8532 (matches the issue):

| | lines |
|---|---|
| `PercolatorFdr.cs` | **4,778** |
| `Osprey.FDR` assembly, all `.cs` | 13,260 |
| share of assembly | **36%** |

## Constraint

The only real constraint is **byte-identical output** against the committed golden.
The giant Rust-shaped methods are porting residue and can be decomposed freely
(see [[feedback_refactor_gate_output_not_structure]] - Rust retirement unlocks
nothing here, the gate was always output).

## Gates (both required before PR)

- **Correctness**: `pwsh -File ./pwiz_tools/Osprey/regression.ps1 -Dataset Stellar`
  (`-Dataset All` before merge). NOTE: regression.ps1 cannot run concurrently -
  shared Release dir + SQLite.Interop.dll lock.
- **Perf**: `pwsh -File ./ai/scripts/Osprey/Test-PerfGate.ps1 -Dataset Stellar`
- **Pre-commit**: `Build-Osprey.ps1 -Configuration Debug -RunTests -RunInspection`

## Survey of the current file (line numbers on master 1c1ae8532)

Public types that are already separable data holders (lines 49-343):
`PercolatorConfig`, `PercolatorEntry`, `PercolatorResult`, `PercolatorResults`.

Responsibility clusters inside the static `PercolatorFdr` class:

| Cluster | Representative members | Rough span |
|---|---|---|
| Training orchestration | `RunPercolator`, `TrainFold`, `TrainFoldGbt`, `GridSearchC`, `SelectPositiveTrainingSet`, `FindBestInitialFeature`, `CalibrateScoresBetweenFolds`, `TrainProgressReporter` | 344-902, 2106-2650 |
| Model application / scoring | `ScorePopulationAndComputeFdr`, `ScoreProjectionAndComputeFdrInPlace`, `RunStreamingFirstPass`, `ScoreWithFoldModel`, `ScoreStandardizedRow`, `AverageGbtScore`, `ScoreProjectionRowsGbt` | 903-2105, 2546-2650 |
| TDC / FDR math | `CompeteAll`, `CompeteFromIndices`, `CompeteFromDicts`, `ComputeConservativeQvalues`, `ComputeQvalues*`, `CountPassing*`, per-run and experiment q-value families, `StreamingFirstPassQ` | 2684-3350, 3653-4202 |
| Sampling / fold selection | `BestPrecursorPerPeptide`, `CreateStratifiedFoldsByPeptide`, `BuildTrainingSubset`, `SelectBestPerPrecursor`, `SubsampleByPeptideGroup` | 4216-4490 |
| **Stage-5 diagnostic dumps** | `WriteStage5SubsampleDump`, `WriteStage5SvmWeightsDump`, `WriteStage5StandardizerDump`, `WriteStage5PercInputDump`, `EmitFeatureContributions`, `FormatC`, `FormatCGrid` | **4491-4728** |

## Plan - revised 2026-07-27 on MEASURED cluster sizes

Every member's span was measured (`ai/.tmp/bucket-clusters.sh`) rather than
estimated, because the original 5-file plan would have traded one god class for
two smaller ones: a single `TargetDecoyFdr` would have been ~1,450 lines and
training ~1,285. Measured against the post-step-1 file (4,555 lines):

| Cluster | lines | % |
|---|---:|---:|
| Training orchestration | 1,285 | 28% |
| Scoring / model application | 1,069 | 23% |
| FDR q-values | 778 | 17% |
| FDR streaming | 388 | 9% |
| FDR competition (TDC) | 286 | 6% |
| Data types (Config/Entry/Result/Results) | 279 | 6% |
| Sampling / fold selection | 262 | 6% |
| Matrix utilities | 80 | 2% |
| *(step 1, done)* | *223* | *4.7%* |

Revised to **8 collaborators** so nothing lands above ~1,285:

1. ~~Stage-5 diagnostic dumps~~ **DONE**
2. ~~**Sampling / fold selection**~~ (270) **DONE**
3. ~~**Data types**~~ (286) **DONE** - plain holders, zero call-site churn.
4. ~~**Matrix utilities**~~ (~65) **DONE** - shared by training AND scoring, so they
   had to become a common helper rather than travel with either.
5. **Scoring -> `PercolatorScorer`** (1,069).
6. **Training -> `PercolatorTrainer`** (1,285).
7. **FDR competition -> `TargetDecoyCompetition`** (286).
8. **FDR q-values -> `QValueCalculator`** (778).
9. **FDR streaming -> `StreamingFdr`** (388).

**Ordering corrected 2026-07-27**: an earlier revision of this list put the three
FDR extractions at 5-7, ahead of scoring and training. That contradicted the issue,
which says the parity-critical FDR math goes **last**. Restored to the issue's
order. (Mechanically either works - the per-step parity gate attributes a break
to whichever step is in flight - but the FDR math is the hardest place to diagnose
a subtle break, so it goes last with every simpler move already banked.)

**`RunPercolator` is 558 lines by itself** - 43% of the training cluster. Training
is not really "a big class", it is one giant Rust-shaped method plus helpers.
Decomposing it into named phases is its own step, kept separate because it changes
code *shape* rather than just relocating code. Permitted: the gate is output-only
(see Constraint above).

**Decided 2026-07-27 (Brendan): the `RunPercolator` decomposition stays in THIS PR**,
not a follow-up. Leaving training at ~1,340 lines with a 558-line method inside is
the shape the size concern was about, and splitting would cost a second review cycle
without changing the risk.

**Verification note for that step**: every step so far has had TWO independent
checks - a verbatim body-for-body diff proving the move changed nothing, plus
byte-identical parity. An internal decomposition forfeits the verbatim diff, since
the text legitimately changes. Parity becomes the sole verifier, on the most
intricate method in the file. Mitigation: decompose in SMALL increments with a
parity run each, rather than one reshape, so a break stays attributable. Run
`-Dataset All` before the PR, not just Stellar.

**End state**: `PercolatorFdr.cs` becomes a facade well under 200 lines, or goes
away entirely if the public entry points read better on the collaborators.

Each step: extract, build, pre-commit gate, then the Stellar regression to confirm
byte-identical output before starting the next. Do not batch several extractions
before a parity run - that destroys the ability to attribute a break.

Steps 8-9 move the hot paths, so run `Test-PerfGate.ps1` when scoring lands rather
than only at the end - a perf regression found at the end is not attributable.

## Step 1 result (2026-07-27)

New `Osprey.FDR/PercolatorDiagnosticsDump.cs` holding the five write-only members,
renamed to drop the now-redundant `Stage5` prefix (the class name carries it):

| was | now |
|---|---|
| `WriteStage5StandardizerDump` | `PercolatorDiagnosticsDump.WriteStandardizerDump` |
| `WriteStage5PercInputDump` | `PercolatorDiagnosticsDump.WritePercInputDump` |
| `WriteStage5SubsampleDump` | `PercolatorDiagnosticsDump.WriteSubsampleDump` |
| `WriteStage5SvmWeightsDump` | `PercolatorDiagnosticsDump.WriteSvmWeightsDump` |
| `EmitFeatureContributions` | `PercolatorDiagnosticsDump.EmitFeatureContributions` |

`PercolatorFdr.cs`: **4,778 -> 4,555 lines** (-223). 8 call sites redirected.
`BASE_ID_MASK` widened from `private` to `internal` (commented) so the dump can
mask base IDs the same way; `using System.IO` dropped, now unused.

**Deliberately NOT moved**: `FormatC` / `FormatCGrid`. They read like dump helpers
but are used by the *training* console output (`RunPercolator`, lines 631/635), so
they belong with training in step 3.

### Verification gap worth recording

`regression.ps1` does **not** cover these methods - every one of them is gated
behind a `PercolatorDiagnosticsConfig` flag that the regression does not set. So a
green parity run says nothing about whether the move was faithful. The actual
verifier used was a textual body-for-body comparison against the pre-edit file
(`ai/.tmp/verify-extraction.sh`), normalizing only the intended deltas (rename,
access modifier, `BASE_ID_MASK` qualification):

```
IDENTICAL  WriteSubsampleDump (57 lines)
IDENTICAL  WriteSvmWeightsDump (37 lines)
IDENTICAL  WriteStandardizerDump (26 lines)
IDENTICAL  WritePercInputDump (45 lines)
IDENTICAL  EmitFeatureContributions (7 lines)
RESULT: all method bodies moved verbatim
```

Later steps move code the regression DOES cover, so the parity gate regains its
force there. This gap is specific to the diagnostics step.

### Gates

- Build (net472 + net8.0): PASS
- Unit tests: 543/543 PASS
- Inspection: 0 warnings both frameworks - after fixing one real finding it caught,
  a `using System.IO` left redundant by the extraction
- Stellar `regression.ps1`: **PASS** - mode1 (vs golden), mode2 (resume), mode3
  (HPC chain), blib byte-identical to the baseline at 30,597,120 bytes
- Committed as `045fe23c9`
- Baseline anchor first: unmodified branch was mode1/2/3 PASS, so a later red is
  attributable to the refactor rather than to a pre-existing break

## Step 2 result - sampling / fold selection (2026-07-27)

New `PercolatorSampling` (public static, 311-line file) holding the five
training-set selection primitives, moved verbatim (264 lines, diff-verified):
`BestPrecursorPerPeptide`, `CreateStratifiedFoldsByPeptide`, `BuildTrainingSubset`,
`SelectBestPerPrecursor`, `SubsampleByPeptideGroup`.

`PercolatorFdr.cs`: 4,555 -> **4,285**. Unlike step 1 these had callers outside the
file: 8 inside `PercolatorFdr`, 2 in `PercolatorEngine`, 3 in `FdrTest`, plus
doc-comment crefs. Accessibility preserved (`InternalsVisibleTo Osprey.Test` already
lets the tests reach the `internal` ones).

Two things the gates caught that review would not have:

- **The compiler**: the block referenced `BASE_ID_MASK` in 5 places (now qualified
  as `PercolatorFdr.BASE_ID_MASK`).
- **The inspection**: 7 `InvalidXmlDocComment` findings - crefs broken in *both*
  directions by the move. Those compile fine and would have rotted silently.

Gates: build PASS, 543/543 tests, 0 inspection warnings, Stellar mode1/2/3 PASS,
blib byte-identical. Committed `58bb8247b`.

## Step 3 result - data types (2026-07-27)

Split the four public holders into their own files, moved verbatim (diff-verified):
`PercolatorConfig.cs` (146), `PercolatorEntry.cs` (45), `PercolatorResults.cs` (95,
holding `PercolatorResult` + `PercolatorResults` - separating a per-entry result
from its aggregate would be noise).

`PercolatorFdr.cs`: 4,285 -> **3,999**. Zero call-site changes: same namespace, so
nothing referencing these types had to move. Only fix needed was a `using System;`
for `Environment.ProcessorCount`, caught by the compiler.

Gates: build PASS, 543/543 tests, 0 inspection warnings, Stellar parity (running).

## Step 4 result - shared matrix row helpers (2026-07-27)

New `MatrixRows` (internal static) holding `ExtractRows`, `ExtractRowsInto`,
`ExtractRow`, `CopyRow`. `PercolatorFdr.cs`: 3,999 -> **3,933**.

These were `private` and lived in two separate regions of the file. Checking their
call sites is what determined the destination: they are used by **both** training
(lines 174, 424-463, 2198-2273) and scoring (1969-2011), so they belong to neither
and had to become a shared helper - otherwise steps 5 and 6 would have had to
duplicate them or reach across into each other.

This is also the hottest code in Percolator (`ExtractRows` runs ~540x per file on
200K x 21 matrices), so it was moved with no edits at all beyond `private` ->
`internal`.

**Process note**: the sed line ranges were off by one, leaving `ExtractRowsInto`'s
closing brace behind in `PercolatorFdr.cs` as an orphan and missing from the new
file. Caught by reading the seam immediately after the cut, before building. Worth
keeping the habit of printing both seams after every extraction rather than
trusting the range arithmetic.

Gates: build PASS, 543/543 tests, 0 inspection warnings, bodies diff-verified
verbatim, Stellar parity (running).

## Step 5 result - scoring / model application (2026-07-27)

New `PercolatorScorer` (public static, 1,136-line file). `PercolatorFdr.cs`:
3,933 -> **2,845** (-1,088). 1,087 moved lines diff-verified verbatim under only
the intended transforms.

The members were in three contiguous runs, not truly scattered: 603-795
(`ScorePopulationAndComputeFdr`), 1016-1799 (the projection-native path,
`RunStreamingFirstPass`, `FirstPassDedupRow`, `RowBuffer`, `ComputeStreamedScore`,
`GroupIndicesByFileName`, `ResolveFeatureRow`) and 2256-2363 (the per-row model
application primitives).

### Two seams that are NOT clean, stated rather than hidden

1. **`ScoreWithFoldModel` straddles.** It is called from `RunPercolator` (training,
   which stays) at three sites, so it moved to the scorer as `internal` rather than
   `private`. That is the right direction - applying a fold model to rows IS
   scoring, and training legitimately asks for it to evaluate held-out folds - but
   it is a real dependency from training onto scoring, not an accident.
2. **Four `private` q-value helpers had to widen to `internal`**:
   `ComputeStreamingCompetitionQvalues`, `UpdateExperimentQClampFloor`,
   `ComputePerFileRunQvalues`, `QProgress`. The scorer's entry points compute
   q-values as well as scores - their names say so - so this is pre-existing
   scoring/FDR conflation surfacing, not new coupling. All four are destined for
   the FDR collaborators in steps 7-9, at which point they are cross-class calls
   anyway and the widening stops being a compromise.

### Method

Rather than pre-enumerating cross-class references by hand, the cut was made and
the **compiler asked**: one build produced the complete list of CS0103 / CS0117 /
CS0246 in both directions, which drove the qualification pass. Then the inspection
caught 7 more broken doc-comment crefs and 2 usings the move made redundant - none
of which the compiler cares about.

A `grep -rl` sweep for the moved names caught four more callers outside the files
I had thought to check (`FrozenModelScorer`, `FdrProjectionOutput`,
`PercolatorEntryBuilder`, `PercolatorConfig`). Enumerating caller files by hand
would have missed them; the build then confirmed.

Gates: build PASS, 543/543 tests, 0 inspection warnings, Stellar mode1/2/3 PASS
(blib byte-identical at 30,597,120). Committed `e78da071c`.

Perf gate attempted now rather than at the end: this step moves the hot path, and a
perf regression discovered after several more extractions would not be attributable
to any one of them. Baseline is the pinned `pwiz-perfbase` worktree at `f4de68645`.

### PERF GATE RESULT - stage 5 neutral (+0.6%)

Measured against a baseline pinned to **this branch's exact merge-base**
(`1c1ae8532`, verified with `git merge-base`), so the only delta is the five
refactor commits:

| Stage | Median delta | per-rep | Read |
|---|---:|---|---|
| **stage5 (Percolator)** | **+0.6%** | +0.6, -0.4, +0.9 | neutral - the stage that holds the extracted code |
| stage6 | 0.0% | -7.6, 0.0, +2.2 | neutral |
| stage7 | +1.2% | -0.6, +1.2, +3.1 | neutral |
| stage1to4 | -9.6% | +14.1, -9.6, -19.8 | noise; I/O bound, untouched by this work |
| total | -5.3% | +7.1, -5.3, -9.1 | dominated by the stage1to4 noise |

No JIT-inlining penalty from the new class boundary, which was the one real risk in
moving hot-path code (`ScoreWithFoldModel`, `MatrixRows`) across classes.

**The default invocation of this gate was misleading and should not have been
trusted.** `Test-PerfGate.ps1` defaults to `C:\proj\pwiz-perfbase`, pinned at
`f4de68645` - **19 days and 58 commits behind this branch point, 33 of them
touching Osprey**. Against that baseline the same branch reported stage5 **-17.7%**
and stage7 **-46%**, which is master's own work since 2026-07-08, not this refactor.
A structural, byte-identical move cannot make stage7 46% faster. The risk is not the
flattering number, it is that a real regression from these commits could hide inside
a comparison dominated by 33 unrelated Osprey commits.

Re-run with `-BaselineRoot` pointed at a worktree checked out to the merge-base.
The shared `pwiz-perfbase` was deliberately **not** re-pointed: refreshing it changes
the meaning of every other developer's perf comparison and is not a side decision to
make mid-task. Worth raising separately - a baseline this stale makes the routine
per-PR gate close to non-attributing.

### Earlier attempt: blocked, not failed

The run exited 1 with `MSB3027` / `MSB3021`: it could not relink `C:\proj\pwiz`
because a **different session's** Osprey process (PID 25468) held the Release DLLs.
Identified before touching anything - it was launched by
`ai/scripts/Osprey/SEA-AD/Run-SeaAd.ps1 -DecoyMode libdecoy -Ratio 1.0 -NumFiles 2
-Tag -smoke`, an Astral SEA-AD entrapment smoke run at 30 threads / 23 GB, ~9
minutes in and actively burning ~9.5 cores. Killing it to unblock the gate would
have destroyed real work. **No perf number exists for step 5 yet.**

**Cross-session hazard worth fixing separately**: `Run-SeaAd.ps1` runs
`C:\proj\pwiz\...\Release\net8.0\Osprey.exe`, i.e. whatever is currently built in
the shared default worktree. That session is therefore smoke-testing SEA-AD against
this branch's mid-refactor binaries rather than master. Byte-parity means the
numbers should be unaffected, but the coupling is real in both directions: their run
blocks my builds, and my rebuilds swap binaries under theirs. The pinned
`pwiz-perfbase` pattern exists precisely to avoid this; SEA-AD runs should probably
take a `-SourceRoot` too.

Re-run the perf gate when that worktree is free, before step 6 stacks another hot
path change on top.

## Step 6 result - training orchestration (2026-07-27)

New `PercolatorTrainer` (public static, 1,343-line file) holding `RunPercolator`,
`TrainFold`, `TrainFoldGbt`, `TrainProgressReporter`, `SelectPositiveTrainingSet`,
`FindBestInitialFeature`, `GridSearchC`, `CalibrateScoresBetweenFolds`,
`FindScoreAtFdr`, the C-grid console formatters, and `MIN_POSITIVE`.

`PercolatorFdr.cs`: 2,845 -> **1,561**, and what remains is purely FDR math.
1,291 moved lines diff-verified verbatim.

### The seam is the messiest yet, and that is informative

Training needed **6 more private FDR members widened to `internal`** - `CompeteAll`,
`ComputeQvalues`, and the four per-run / experiment q-value functions - on top of the
4 the scorer already needed. Ten widenings total.

That is not accidental coupling: `RunPercolator` **is** the train -> score -> FDR
monolith, so extracting it exposes how far it reaches into q-value math. It is the
measurable argument for decomposing the method rather than just relocating it, and
steps 7-9 should convert most of those widenings back into ordinary cross-class
calls.

### Tooling: a brace-aware extractor replaced hand-computed line ranges

Manual `sed` ranges had already caused two errors (an orphaned closing brace in step
4; a cut that took the NEXT member's doc comment in step 5). For a four-run,
~1,290-line cut that was no longer acceptable, so the members were located by brace
matching instead (`ai/.tmp/extract_members.py`, reporting each member's extent and
asserting no overlaps).

It immediately earned itself: **`TrainFoldGbt` has a `///` doc block followed by a
plain `//` note before its declaration**, so a walk-back that only accepted `///`
stopped early and would have silently orphaned 19 lines of documentation into the
FDR file. Fixed the walk-back to accept plain `//` too.

Gates: build PASS, 543/543 tests, 0 inspection warnings (after removing two usings
the move made redundant), Stellar mode1/2/3 PASS with the blib byte-identical at
30,597,120. Committed `8a55e0e1b`.

## Endgame: PercolatorFdr does not survive

Bucketing the 1,561 lines left after step 6 gives **competition 286 / streaming 388
/ q-values 782, and zero unclassified**. So once steps 7-9 land, `PercolatorFdr` has
no members at all - it does not become a thin facade, it goes away.

That settles the `BASE_ID_MASK` question below: the constant has to be rehomed as
part of step 9 rather than left where it is, because its current home ceases to
exist. Candidates: alongside the entry-id concept it masks, or as a shared constant
the four consumers and `ModelDiagnosticsData` can both reference.

## RunPercolator decomposition (2026-07-27)

**Increment A - DONE** (`9f427d3c3`): `TrainFoldModels` takes the fold-index
precompute, scratch pool, parallel fold training and per-fold reporting.
`RunPercolator` 546 -> **440** lines. `foldElapsed` / `foldBestC` moved with it -
declared above the phase but used only inside it, so block state not caller state,
which only the compiler caught. Stellar mode1/2/3 PASS.

**Increment B - ATTEMPTED AND REVERTED.** Extracting `ScoreEntriesWithFoldModels`
(64 lines, held-out-fold scoring) built and tested clean but turned the inspection
red with 6 findings: `ConditionIsAlwaysTrueOrFalse` plus `HeuristicUnreachableCode`
at two `if (trainSubset != null)` sites in `RunPercolator`.

They are correct. `PercolatorSampling.BuildTrainingSubset` returns `.ToArray()` on
both of its return paths and can never be null, so **both `else` branches are dead
code** - the "no subsampling" clone path and the un-remapped calibration call. This
is **pre-existing**, not introduced: shrinking `RunPercolator` far enough let
ReSharper's data-flow analysis complete where it previously gave up. A real side
benefit of the decomposition, and an argument for it beyond readability.

**Why it was reverted rather than fixed**: removing those branches is not something
this PR's verifier can check. If `trainSubset` is never null then both versions
behave identically on Stellar, so a green parity run is evidence of *nothing*. The
deletion would rest entirely on the null-impossibility argument with no gate behind
it - which is the standard every other step here was held to. Suppressing a true
finding to keep the gate green would be worse.

**DECIDED 2026-07-27 (Brendan): cleared to remove the unreachable branches.**

Removed in `419a72c03`. There were **three** sites, not two - the scoring block had
its own `if (trainSubset != null) ... else { // No subsampling }`. Net -58 / +36
lines, no live-path logic touched (`git diff -w` shows only the declaration collapse
to `var`, the branch removals and comments). Stellar mode1/2/3 PASS.

On Brendan's question about a ReSharper guard: `[NotNull]` (JetBrains.Annotations)
does exist and pwiz already references it from `Shared/CommonUtil` via a HintPath,
but it was **not** used here for two reasons:

1. `Osprey.FDR` does not reference it, and Osprey ships as a standalone
   redistributable - adding a third-party assembly to the shipped dependency set to
   annotate one return is a poor trade.
2. It would not avoid a warning, it would *cause* one: annotating `[NotNull]` makes
   `if (x != null)` provably redundant, which is the same warning class being
   resolved. The annotation documents deadness rather than making it acceptable.

So the guarantee is documented in prose instead - a `<returns>` block on
`BuildTrainingSubset` stating it is never null, why (both paths return materialized
arrays), and that callers must not test for null because that reads as a real
alternative path and hides dead code.

The code comment also carries the caveat that outlives this conversation: an
unreachable branch is invisible to the golden, so the removal rests on
`BuildTrainingSubset`'s return paths, **not** on a green gate.

**Increment B re-applied** after the cleanup and now passes (the dead code was the
blocker): `ScoreEntriesWithFoldModels`, 46 lines moved verbatim.
**`RunPercolator` 546 -> 368 lines** over the phase.

## /code-review max triage (2026-07-28)

15 findings. The review verified the decomposition itself as faithful (72 old method
bodies diffed against the 11 new files; only `RunPercolator` differs substantively).

**Fixed in `96135dd6e`** - all were introduced by this branch:

| Finding | Why it mattered |
|---|---|
| `QValueCalculator` name collision | `pwiz.Osprey.ML.QValueCalculator` already exists; the FDR namespace shadowed it, and the two entry points differ only by one letter's case (`ComputeQValues` vs `ComputeQvalues`) while computing different FDR formulas. Renamed `PercolatorQValues`. |
| Six mangled class summaries | An earlier bulk `sed` ate "extracted from", so `MatrixRows` read as though `Matrix` were the god class. Restored + trailing whitespace. |
| Two mis-pointed comments | `FrozenModelScorer`'s averaged-model warning and `FdrTest`'s index-alignment contract pointed at the wrong class after the rename. The earlier "corrected two doc pointers" commit caught two and missed these. |
| `CompeteFromIndices` public-in-internal | Effective visibility silently narrowed cross-assembly with nothing in the diff to show it. |
| Uncommitted extraction + vestigial `{ }` | `ScoreEntriesWithFoldModels` had never been committed; its leftover brace pair from the removed `if` left the body over-indented, and its "see above" comment referenced a proof that had moved methods away. |

**NOT fixed - pre-existing, and out of scope for a byte-identical PR:**

- **`--fdr-method gbdt` config drop** (`PercolatorScorer.RunStreamingFirstPass`): hand-builds
  its train config and never copies `UseGradientBoostedTrees` / `GbtParams` / `NThreads`, so a
  gbdt run silently trains a linear SVM. **Verified pre-existing** - it sits at old-file line
  1799 and moved verbatim. Real bug, needs its own issue; the one-line fix
  (`percConfig.CloneForTrainOnly()`) changes behavior and would need a golden rebaseline.
- **`captureModel` invoked before the `DiagnosticAbort` check** (`PercolatorEngine`): hands the
  pass-2 transfer hook an all-default `PercolatorResults` on a diagnostic-only run. The sibling
  path in `PercolatorScorer` checks first, so the two disagree. Provenance not yet verified.

**Logged, not done** (context-limited, all real):

- **Dependency cycle** `PercolatorScorer` <-> `PercolatorTrainer` - the only cycle among the 11
  classes, because `RunStreamingFirstPass` (a train-then-score driver) sits on the scorer while
  its two siblings live in `PercolatorEngine`. Moving it breaks the cycle and would let the two
  largest files separate, which is the stated goal of the extraction.
- ~50 stale `PercolatorFdr.cs:NNN` citations across `pwiz_tools/Osprey/docs/`, `DIVERGENCES.md`,
  `ai/docs/osprey-development-guide.md` (auto-loaded by the osprey skill) and an active TODO.
- `ai/scripts/Osprey/Combine-Stage5-Profile.ps1` symbol map keys on `PercolatorFdr.*`; two rows
  silently stop matching. A live tooling break, not a doc rot - and it is in the shared `ai/`
  checkout, so it needs committing promptly once fixed.
- `TrainFoldModels` takes 14 positional parameters with adjacent same-typed ints, two derivable
  from arguments already passed.

**Process note**: while fixing the vestigial block, a brace-matching bug in my own fix script
dedented 867 lines instead of 43. Caught by checking indentation before building, restored from
git, redone with real brace counting plus a size assertion. Worth recording because a scripted
"cleanup" corrupted more than the thing it was cleaning.

## Follow-up noticed (not fixed here)

`BASE_ID_MASK` is defined twice - `PercolatorFdr` (`static readonly`) and
`ModelDiagnosticsData` (`const`) - and is now referenced from four classes. Step 9
forces the issue since `PercolatorFdr` disappears; `Osprey.FDR` does not reference
`Osprey.Scoring`, so unifying with the `CalibrationScorer` side would need a shared
home in Core/ML and is a separate change.

`CalibrationScorer` also has its own private `CreateStratifiedFoldsByPeptide`, a
second implementation of the fold split extracted in step 2. Whether the two are
actually identical is worth answering, but merging them moves behavior across an
assembly boundary and does not belong in a structural-only PR.

## Tasks

- [x] Step 1: extract Stage-5 diagnostic dumps (223)
- [x] Step 2: extract sampling / fold selection (270)
- [x] Step 3: extract the data types (286)
- [x] Step 4: extract the shared matrix row helpers (~65)
- [x] Step 5: extract scoring / model application (1,088)
- [x] Step 6: extract training orchestration (1,284)
- [ ] Step 2: extract sampling / fold selection
- [ ] Step 3: extract training orchestration
- [ ] Step 4: extract scoring / model application
- [ ] Step 5: extract TDC / FDR math
- [ ] Full `-Dataset All` regression + perf gate before PR
- [ ] `/code-review max` before `gh pr create`

Steps 3-5 are large; if the session ends before they are done, the branch should be
left at a green, byte-identical intermediate state rather than mid-extraction.

## Regression Test

- **Test name**: `regression.ps1` (committed C# golden + resume leg, 1e-9) plus the
  Osprey unit suite via `Build-Osprey.ps1 -RunTests`
- **Test project**: Osprey.Test + the standing regression harness
- **Fails on master**: n/a - this is a structural refactor, not a bug fix. There is
  no red-to-green test; the verifier is the inverse, an output-unchanged gate.
- **Passes on fix**: (to verify per step)

No new regression test is added, and that is the correct answer here: the change is
required to alter nothing observable, so the existing byte-identical golden is
exactly the right verifier. A new test asserting new structure would only pin the
refactor's own shape.

## Progress Log

### 2026-07-27 - Session Start

Branch created in `C:\proj\pwiz` (freed by PR #4480 merging). Confirmed the issue's
line counts against master and surveyed the file into the responsibility clusters
above. Starting with the Stage-5 diagnostic dumps.
