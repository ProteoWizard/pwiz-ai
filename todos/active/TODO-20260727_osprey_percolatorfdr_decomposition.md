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
2. **Sampling / fold selection** (262) - pure, deterministic, `internal` surface.
3. **Data types** (279) - `PercolatorConfig` / `Entry` / `Result` / `Results` are
   plain holders; zero-risk relocation.
4. **Matrix utilities** (80) - `ExtractRows` / `ExtractRowsInto` / `ExtractRow` /
   `CopyRow`. Hot path, so move only, no edits.
5. **FDR competition -> `TargetDecoyCompetition`** (286).
6. **FDR q-values -> `QValueCalculator`** (778).
7. **FDR streaming -> `StreamingFdr`** (388).
8. **Scoring -> `PercolatorScorer`** (1,069).
9. **Training -> `PercolatorTrainer`** (1,285).

**`RunPercolator` is 558 lines by itself** - 43% of the training cluster. Training
is not really "a big class", it is one giant Rust-shaped method plus helpers.
Decomposing it into named phases is its own step, kept separate because it changes
code *shape* rather than just relocating code. Permitted: the gate is output-only
(see Constraint above).

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

## Follow-up noticed (not fixed here)

`BASE_ID_MASK` is defined twice - `PercolatorFdr` (`static readonly`) and
`ModelDiagnosticsData` (`const`). Left alone to keep this step's parity surface
minimal; fold into a later step.

## Tasks

- [x] Step 1: extract Stage-5 diagnostic dumps
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
